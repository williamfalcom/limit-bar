import Foundation
import Security

protocol SecItemClient: Sendable {
    func add(_ attributes: CFDictionary) -> OSStatus
    func copyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    func update(_ query: CFDictionary, _ attributesToUpdate: CFDictionary) -> OSStatus
    func delete(_ query: CFDictionary) -> OSStatus
}

struct SystemSecItemClient: SecItemClient {
    func add(_ attributes: CFDictionary) -> OSStatus {
        SecItemAdd(attributes, nil)
    }

    func copyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        SecItemCopyMatching(query, result)
    }

    func update(_ query: CFDictionary, _ attributesToUpdate: CFDictionary) -> OSStatus {
        SecItemUpdate(query, attributesToUpdate)
    }

    func delete(_ query: CFDictionary) -> OSStatus {
        SecItemDelete(query)
    }
}

struct KeychainStore: Sendable {
    enum KeychainError: Error, Equatable {
        case itemNotFound
        case accessDenied
    }

    private let service: String
    private let secItem: any SecItemClient

    init(service: String = "limit-bar", secItem: any SecItemClient = SystemSecItemClient()) {
        self.service = service
        self.secItem = secItem
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func set(_ secret: String, for account: String) throws {
        let data = Data(secret.utf8)
        let query = baseQuery(account: account)
        switch secItem.copyMatching(query as CFDictionary, nil) {
        case errSecSuccess:
            let attributes = [kSecValueData as String: data]
            let status = secItem.update(query as CFDictionary, attributes as CFDictionary)
            guard status == errSecSuccess else { throw Self.error(for: status) }
        case errSecItemNotFound:
            var addAttributes = query
            addAttributes[kSecValueData as String] = data
            let status = secItem.add(addAttributes as CFDictionary)
            guard status == errSecSuccess else { throw Self.error(for: status) }
        case let status:
            throw Self.error(for: status)
        }
    }

    func get(for account: String) throws -> String {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = secItem.copyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { throw Self.error(for: status) }
        guard let data = item as? Data else { throw KeychainError.itemNotFound }
        return String(decoding: data, as: UTF8.self)
    }

    func delete(for account: String) throws {
        let status = secItem.delete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Self.error(for: status) }
    }

    private static func error(for status: OSStatus) -> KeychainError {
        status == errSecItemNotFound ? .itemNotFound : .accessDenied
    }
}
