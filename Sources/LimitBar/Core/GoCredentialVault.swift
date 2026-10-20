import Foundation

struct GoOAuthCredential: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var workspaceID: String?
}

enum GoCredentialVaultError: Error, Equatable {
    case unsupportedOAuthVersion(Int)
    case deletionFailed([String])
}

struct GoCredentialVault: Sendable {
    private struct OAuthEnvelope: Codable {
        var version: Int
        var credential: GoOAuthCredential
    }

    private static let currentOAuthVersion = 1
    private let credentials: any CredentialStore

    init(credentials: any CredentialStore) {
        self.credentials = credentials
    }

    static func apiKeyKey(for accountID: UUID) -> String {
        "go.api-key.\(accountID.uuidString)"
    }

    static func legacyAPIKeyKey(for accountID: UUID) -> String {
        accountID.uuidString
    }

    static func oauthKey(for accountID: UUID) -> String {
        "go.oauth.\(accountID.uuidString)"
    }

    func storeAPIKey(_ apiKey: String, for accountID: UUID) throws {
        try credentials.set(apiKey, forKey: Self.apiKeyKey(for: accountID))
    }

    func apiKey(for accountID: UUID) throws -> String {
        let canonicalKey = Self.apiKeyKey(for: accountID)
        if let apiKey = try? credentials.secret(forKey: canonicalKey), apiKey.isEmpty == false {
            return apiKey
        }
        return try credentials.secret(forKey: Self.legacyAPIKeyKey(for: accountID))
    }

    func storeOAuthCredential(_ credential: GoOAuthCredential, for accountID: UUID) throws {
        let envelope = OAuthEnvelope(version: Self.currentOAuthVersion, credential: credential)
        let data = try JSONEncoder().encode(envelope)
        try credentials.set(String(decoding: data, as: UTF8.self), forKey: Self.oauthKey(for: accountID))
    }

    func oauthCredential(for accountID: UUID) throws -> GoOAuthCredential {
        let key = Self.oauthKey(for: accountID)
        let encoded = try credentials.secret(forKey: key)
        let envelope = try JSONDecoder().decode(OAuthEnvelope.self, from: Data(encoded.utf8))
        guard envelope.version == Self.currentOAuthVersion else {
            throw GoCredentialVaultError.unsupportedOAuthVersion(envelope.version)
        }
        return envelope.credential
    }

    func deleteCredentials(for accountID: UUID) throws {
        let keys = [
            Self.apiKeyKey(for: accountID),
            Self.legacyAPIKeyKey(for: accountID),
            Self.oauthKey(for: accountID),
        ]
        var failedKeys: [String] = []

        for key in keys {
            do {
                try credentials.deleteSecret(forKey: key)
            } catch KeychainStore.KeychainError.itemNotFound {
                continue
            } catch {
                failedKeys.append(key)
            }
        }

        guard failedKeys.isEmpty else {
            throw GoCredentialVaultError.deletionFailed(failedKeys)
        }
    }
}
