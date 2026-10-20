import Foundation
import Testing
@testable import limit_bar

private final class CredentialVaultSpy: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String]
    private var reads: [String] = []
    private var deletes: [String] = []
    private let failedWrites: Set<String>
    private let failedDeletes: Set<String>

    init(
        values: [String: String] = [:],
        failedWrites: Set<String> = [],
        failedDeletes: Set<String> = []
    ) {
        self.values = values
        self.failedWrites = failedWrites
        self.failedDeletes = failedDeletes
    }

    var valuesSnapshot: [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    var readKeys: [String] {
        lock.lock()
        defer { lock.unlock() }
        return reads
    }

    var deletedKeys: [String] {
        lock.lock()
        defer { lock.unlock() }
        return deletes
    }

    func set(_ secret: String, forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard failedWrites.contains(key) == false else {
            throw KeychainStore.KeychainError.accessDenied
        }
        values[key] = secret
    }

    func secret(forKey key: String) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        reads.append(key)
        guard let value = values[key] else {
            throw KeychainStore.KeychainError.itemNotFound
        }
        return value
    }

    func deleteSecret(forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        deletes.append(key)
        guard failedDeletes.contains(key) == false else {
            throw KeychainStore.KeychainError.accessDenied
        }
        guard values.removeValue(forKey: key) != nil else {
            throw KeychainStore.KeychainError.itemNotFound
        }
    }
}

@Suite("GoCredentialVault")
struct GoCredentialVaultTests {
    private let accountID = UUID()

    @Test("API key storage uses the canonical account-scoped Keychain name")
    func storesAndReadsCanonicalAPIKey() throws {
        let credentials = CredentialVaultSpy()
        let vault = GoCredentialVault(credentials: credentials)
        let key = GoCredentialVault.apiKeyKey(for: accountID)

        try vault.storeAPIKey("go-api-key", for: accountID)
        let loaded = try vault.apiKey(for: accountID)

        #expect(credentials.valuesSnapshot[key] == "go-api-key")
        #expect(loaded == "go-api-key")
        #expect(credentials.readKeys == [key])
    }

    @Test("API key lookup falls back to the legacy bare UUID key")
    func readsLegacyAPIKeyFallback() throws {
        let legacyKey = accountID.uuidString
        let credentials = CredentialVaultSpy(values: [legacyKey: "legacy-api-key"])
        let vault = GoCredentialVault(credentials: credentials)

        let loaded = try vault.apiKey(for: accountID)

        #expect(loaded == "legacy-api-key")
        #expect(credentials.readKeys == [GoCredentialVault.apiKeyKey(for: accountID), legacyKey])
    }

    @Test("OAuth credential round-trip is stored in a versioned envelope")
    func storesVersionedOAuthEnvelope() throws {
        let credentials = CredentialVaultSpy()
        let vault = GoCredentialVault(credentials: credentials)
        let oauth = GoOAuthCredential(
            accessToken: "access-secret",
            refreshToken: "refresh-secret",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
            workspaceID: "workspace-123"
        )

        try vault.storeOAuthCredential(oauth, for: accountID)
        let loaded = try vault.oauthCredential(for: accountID)
        let storedJSON = try #require(credentials.valuesSnapshot[GoCredentialVault.oauthKey(for: accountID)])
        let envelope = try #require(
            JSONSerialization.jsonObject(with: Data(storedJSON.utf8)) as? [String: Any]
        )

        #expect(loaded == oauth)
        #expect(envelope["version"] as? Int == 1)
    }

    @Test("OAuth secrets are absent from serialized AppState")
    func appStateDoesNotContainOAuthSecrets() throws {
        let credentials = CredentialVaultSpy()
        let vault = GoCredentialVault(credentials: credentials)
        let oauth = GoOAuthCredential(
            accessToken: "access-secret-not-in-state",
            refreshToken: "refresh-secret-not-in-state",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
            workspaceID: "workspace-123"
        )
        try vault.storeOAuthCredential(oauth, for: accountID)
        let account = Account(
            id: accountID,
            provider: .openCodeGo,
            label: "Go",
            displayedWindow: .weekly,
            codexHomeOverride: nil,
            goAuthMethod: .consoleOAuth
        )
        let state = AppState(
            accounts: [account],
            snapshots: [:],
            activeAccountID: accountID,
            pollInterval: 300
        )
        let serializedState = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)

        #expect(serializedState.contains("consoleOAuth"))
        #expect(serializedState.contains(oauth.accessToken) == false)
        #expect(serializedState.contains(oauth.refreshToken) == false)
    }

    @Test("Credential removal attempts and deletes all API and OAuth Keychain names")
    func deletesCanonicalLegacyAndOAuthCredentials() throws {
        let apiKey = GoCredentialVault.apiKeyKey(for: accountID)
        let legacyKey = accountID.uuidString
        let oauthKey = GoCredentialVault.oauthKey(for: accountID)
        let credentials = CredentialVaultSpy(values: [apiKey: "key", legacyKey: "legacy", oauthKey: "oauth"])
        let vault = GoCredentialVault(credentials: credentials)

        try vault.deleteCredentials(for: accountID)

        #expect(credentials.deletedKeys == [apiKey, legacyKey, oauthKey])
        #expect(credentials.valuesSnapshot.isEmpty)
    }

    @Test("Credential removal is idempotent when all Keychain items are absent")
    func deletingMissingCredentialsIsIdempotent() throws {
        let credentials = CredentialVaultSpy()
        let vault = GoCredentialVault(credentials: credentials)

        try vault.deleteCredentials(for: accountID)

        #expect(credentials.deletedKeys == [
            GoCredentialVault.apiKeyKey(for: accountID),
            accountID.uuidString,
            GoCredentialVault.oauthKey(for: accountID),
        ])
    }

    @Test("Credential removal attempts every name and reports failed local cleanup")
    func deletionFailureDoesNotSkipRemainingNames() {
        let apiKey = GoCredentialVault.apiKeyKey(for: accountID)
        let legacyKey = accountID.uuidString
        let oauthKey = GoCredentialVault.oauthKey(for: accountID)
        let credentials = CredentialVaultSpy(
            values: [apiKey: "key", legacyKey: "legacy", oauthKey: "oauth"],
            failedDeletes: [apiKey]
        )
        let vault = GoCredentialVault(credentials: credentials)

        #expect(throws: GoCredentialVaultError.deletionFailed([apiKey])) {
            try vault.deleteCredentials(for: accountID)
        }
        #expect(credentials.deletedKeys == [apiKey, legacyKey, oauthKey])
        #expect(credentials.valuesSnapshot == [apiKey: "key"])
    }

    @Test("Credential storage surfaces a Keychain write failure without replacing data")
    func failedWritePreservesExistingOAuthEnvelope() throws {
        let oauthKey = GoCredentialVault.oauthKey(for: accountID)
        let prior = "prior-versioned-envelope"
        let credentials = CredentialVaultSpy(values: [oauthKey: prior], failedWrites: [oauthKey])
        let vault = GoCredentialVault(credentials: credentials)
        let replacement = GoOAuthCredential(
            accessToken: "new-access",
            refreshToken: "new-refresh",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
            workspaceID: nil
        )

        #expect(throws: KeychainStore.KeychainError.accessDenied) {
            try vault.storeOAuthCredential(replacement, for: accountID)
        }
        #expect(credentials.valuesSnapshot[oauthKey] == prior)
    }
}
