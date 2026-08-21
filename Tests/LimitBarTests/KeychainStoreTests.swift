import Testing
import Foundation
import Security
@testable import limit_bar

private final class SecItemSpy: SecItemClient, @unchecked Sendable {
    struct UpdateCall {
        var query: [CFHashable: Any]
        var attributes: [CFHashable: Any]
    }

    let lock = NSLock()
    private(set) var adds: [[CFHashable: Any]] = []
    private(set) var copies: [[CFHashable: Any]] = []
    private(set) var updates: [UpdateCall] = []
    private(set) var deletes: [[CFHashable: Any]] = []

    enum CopyOutcome {
        case value(CFTypeRef)
        case status(OSStatus)
    }

    var copyOutcome: CopyOutcome?
    var deleteOutcome: OSStatus = errSecSuccess

    func add(_ attributes: CFDictionary) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        adds.append(CFHashable.dictionary(attributes))
        return errSecSuccess
    }

    func copyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        copies.append(CFHashable.dictionary(query))
        switch copyOutcome {
        case .value(let value):
            result?.pointee = value
            return errSecSuccess
        case .status(let status):
            return status
        case nil:
            return errSecItemNotFound
        }
    }

    func update(_ query: CFDictionary, _ attributesToUpdate: CFDictionary) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        updates.append(UpdateCall(
            query: CFHashable.dictionary(query),
            attributes: CFHashable.dictionary(attributesToUpdate)
        ))
        return errSecSuccess
    }

    func delete(_ query: CFDictionary) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        deletes.append(CFHashable.dictionary(query))
        return deleteOutcome
    }

    func resetDeletes(deleteOutcome newOutcome: OSStatus) {
        lock.lock()
        defer { lock.unlock() }
        deletes.removeAll()
        deleteOutcome = newOutcome
    }
}

/// Hashable wrapper around CFString key constants so recorded queries can use the real
/// Security-framework constants (kSecClass, kSecAttrService, ...) in assertions.
struct CFHashable: Hashable {
    let raw: CFString
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.raw == rhs.raw }
    func hash(into hasher: inout Hasher) { hasher.combine(raw as String) }

    static func dictionary(_ cf: CFDictionary) -> [CFHashable: Any] {
        let ns = cf as NSDictionary
        var out: [CFHashable: Any] = [:]
        for key in ns.allKeys {
            let cfKey = key as! CFString
            out[CFHashable(raw: cfKey)] = ns[key]
        }
        return out
    }
}

@Suite("KeychainStore")
struct KeychainStoreTests {

    private let service = "limit-bar"
    private let key = "go-api-key"

    private var baseQuery: [CFHashable: Any] {
        [
            CFHashable(raw: kSecClass): kSecClassGenericPassword,
            CFHashable(raw: kSecAttrService): service,
            CFHashable(raw: kSecAttrAccount): key,
        ]
    }

    @Test("Set on missing item adds a generic-password entry with service, account, and data")
    func setAddsNewItem() throws {
        let spy = SecItemSpy()
        spy.copyOutcome = .status(errSecItemNotFound)
        let store = KeychainStore(service: service, secItem: spy)

        try store.set("s3cret-value", for: key)

        #expect(spy.updates.isEmpty)
        #expect(spy.adds.count == 1)
        let attrs = spy.adds[0]
        #expect(attrs[CFHashable(raw: kSecClass)] as? String == kSecClassGenericPassword as String)
        #expect(attrs[CFHashable(raw: kSecAttrService)] as? String == "limit-bar")
        #expect(attrs[CFHashable(raw: kSecAttrAccount)] as? String == key)
        #expect(attrs[CFHashable(raw: kSecValueData)] as? Data == Data("s3cret-value".utf8))
    }

    @Test("Set over existing item updates data without adding a duplicate")
    func setReplacesExisting() throws {
        let spy = SecItemSpy()
        spy.copyOutcome = .value(Data("old".utf8) as CFTypeRef)
        let store = KeychainStore(service: service, secItem: spy)

        try store.set("new-value", for: key)

        #expect(spy.adds.isEmpty)
        #expect(spy.updates.count == 1)
        #expect(spy.updates[0].query[CFHashable(raw: kSecAttrAccount)] as? String == key)
        #expect(spy.updates[0].attributes[CFHashable(raw: kSecValueData)] as? Data == Data("new-value".utf8))
    }

    @Test("Get returns the stored UTF-8 secret")
    func getReturnsSecret() throws {
        let spy = SecItemSpy()
        spy.copyOutcome = .value(Data("tok-123".utf8) as CFTypeRef)
        let store = KeychainStore(service: service, secItem: spy)

        let secret = try store.get(for: key)

        #expect(secret == "tok-123")
        let query = spy.copies[0]
        #expect(query[CFHashable(raw: kSecAttrService)] as? String == "limit-bar")
        #expect(query[CFHashable(raw: kSecAttrAccount)] as? String == key)
        #expect(query[CFHashable(raw: kSecMatchLimit)] as? String == kSecMatchLimitOne as String)
        #expect((query[CFHashable(raw: kSecReturnData)] as? Bool) == true || (query[CFHashable(raw: kSecReturnData)] as? NSNumber)?.boolValue == true)
    }

    @Test("Not-found status maps to the distinct itemNotFound error")
    func notFoundMapsToTypedError() {
        let spy = SecItemSpy()
        spy.copyOutcome = .status(errSecItemNotFound)
        let store = KeychainStore(service: service, secItem: spy)

        #expect(throws: KeychainStore.KeychainError.itemNotFound) { try store.get(for: self.key) }
    }

    @Test("User denial maps to the distinct accessDenied error")
    func denialMapsToAccessDenied() {
        let spy = SecItemSpy()
        spy.copyOutcome = .status(errSecAuthFailed)
        let store = KeychainStore(service: service, secItem: spy)

        #expect(throws: KeychainStore.KeychainError.accessDenied) { try store.get(for: self.key) }
        #expect(KeychainStore.KeychainError.accessDenied != KeychainStore.KeychainError.itemNotFound)
    }

    @Test("Delete issues a scoped remove and treats missing items as success")
    func deleteIsScopedAndIdempotent() throws {
        let spy = SecItemSpy()
        let store = KeychainStore(service: service, secItem: spy)

        try store.delete(for: key)
        #expect(spy.deletes.count == 1)
        let query = spy.deletes[0]
        #expect(query[CFHashable(raw: kSecClass)] as? String == kSecClassGenericPassword as String)
        #expect(query[CFHashable(raw: kSecAttrService)] as? String == "limit-bar")
        #expect(query[CFHashable(raw: kSecAttrAccount)] as? String == key)

        spy.resetDeletes(deleteOutcome: errSecItemNotFound)
        try store.delete(for: key)
        #expect(spy.deletes.count == 1)
    }
}
