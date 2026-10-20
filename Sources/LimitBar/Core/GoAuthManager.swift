import Foundation

protocol GoOAuthClientProtocol: Sendable {
    func requestDeviceAuthorization() async throws -> GoDeviceAuthorization
    func pollForAuthorization(_ authorization: GoDeviceAuthorization) async throws -> GoOAuthCredential
    func refresh(_ credential: GoOAuthCredential) async throws -> GoOAuthCredential
}

extension GoOAuthClient: GoOAuthClientProtocol {}

enum GoAuthManagerError: Error, Equatable {
    case missingCredentials
}

actor GoAuthManager {
    private struct RefreshWork {
        var id: UUID
        var baseCredential: GoOAuthCredential
        var task: Task<GoOAuthCredential, Error>
    }

    private let vault: GoCredentialVault
    private let oauthClient: any GoOAuthClientProtocol
    private let now: @Sendable () -> Date
    private var refreshWorkByAccount: [UUID: RefreshWork] = [:]

    init(
        vault: GoCredentialVault,
        oauthClient: any GoOAuthClientProtocol,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.vault = vault
        self.oauthClient = oauthClient
        self.now = now
    }

    func requestDeviceAuthorization() async throws -> GoDeviceAuthorization {
        try await oauthClient.requestDeviceAuthorization()
    }

    func authorize(_ authorization: GoDeviceAuthorization, for accountID: UUID) async throws {
        let credential = try await oauthClient.pollForAuthorization(authorization)
        try Task.checkCancellation()
        try vault.storeOAuthCredential(credential, for: accountID)
        refreshWorkByAccount[accountID] = nil
    }

    func storeAPIKey(_ apiKey: String, for accountID: UUID) throws {
        try vault.storeAPIKey(apiKey, for: accountID)
        refreshWorkByAccount[accountID] = nil
    }

    func deleteCredentials(for accountID: UUID) throws {
        try vault.deleteCredentials(for: accountID)
        refreshWorkByAccount[accountID] = nil
    }

    func bearerToken(for account: Account) async throws -> String {
        switch account.effectiveGoAuthMethod {
        case .apiKey:
            do {
                return try vault.apiKey(for: account.id)
            } catch KeychainStore.KeychainError.itemNotFound {
                throw GoAuthManagerError.missingCredentials
            }
        case .consoleOAuth:
            let credential = try loadOAuthCredential(for: account.id)
            guard credential.expiresAt.timeIntervalSince(now()) <= 60 else {
                return credential.accessToken
            }
            return try await refreshedCredential(credential, for: account.id).accessToken
        }
    }

    private func loadOAuthCredential(for accountID: UUID) throws -> GoOAuthCredential {
        do {
            return try vault.oauthCredential(for: accountID)
        } catch KeychainStore.KeychainError.itemNotFound {
            throw GoAuthManagerError.missingCredentials
        }
    }

    private func refreshedCredential(
        _ credential: GoOAuthCredential,
        for accountID: UUID
    ) async throws -> GoOAuthCredential {
        let work: RefreshWork
        if let existing = refreshWorkByAccount[accountID], existing.baseCredential == credential {
            work = existing
        } else {
            let client = oauthClient
            work = RefreshWork(
                id: UUID(),
                baseCredential: credential,
                task: Task.detached {
                    try await client.refresh(credential)
                }
            )
            refreshWorkByAccount[accountID] = work
        }

        do {
            let refreshed = try await work.task.value
            let current = try loadOAuthCredential(for: accountID)
            let result: GoOAuthCredential
            if current == work.baseCredential {
                try vault.storeOAuthCredential(refreshed, for: accountID)
                result = refreshed
            } else {
                result = current
            }
            if refreshWorkByAccount[accountID]?.id == work.id {
                refreshWorkByAccount[accountID] = nil
            }
            return result
        } catch {
            // Keep the result so a consumed refresh token is never submitted again.
            // If persistence failed, the same rotated pair can be written on a later call.
            throw error
        }
    }
}
