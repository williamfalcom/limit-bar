import Foundation

protocol CredentialStore: Sendable {
    func set(_ secret: String, forKey key: String) throws
    func secret(forKey key: String) throws -> String
    func deleteSecret(forKey key: String) throws
}

extension KeychainStore: CredentialStore {
    func set(_ secret: String, forKey key: String) throws {
        try set(secret, for: key)
    }

    func secret(forKey key: String) throws -> String {
        try get(for: key)
    }

    func deleteSecret(forKey key: String) throws {
        try delete(for: key)
    }
}
