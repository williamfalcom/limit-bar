import Testing
import Foundation
@testable import limit_bar

private final class PersistingSpy: StatePersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: AppState?

    init(initial: AppState? = nil) {
        stored = initial
    }

    func load() -> AppState? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func save(_ state: AppState) {
        lock.lock()
        defer { lock.unlock() }
        stored = state
    }
}

@Suite("AccountStore")
struct AccountStoreTests {

    private let fixedNow = Date(timeIntervalSince1970: 1_770_000_000)

    @MainActor
    private func makeStore(
        initial: AppState? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> (AccountStore, PersistingSpy) {
        let spy = PersistingSpy(initial: initial)
        return (AccountStore(persistence: spy, now: now), spy)
    }

    private func account(_ provider: ProviderKind, _ label: String) -> Account {
        Account(id: UUID(), provider: provider, label: label, displayedWindow: .fiveHour, codexHomeOverride: nil)
    }

    @Test("Adding an account appends and persists through the seam")
    @MainActor
    func addPersistsAccount() {
        let (store, spy) = makeStore()
        let claude = account(.claudeCode, "Main")

        store.add(account: claude)

        #expect(store.accounts == [claude])
        #expect(spy.load()?.accounts == [claude])
    }

    @Test("Removing an account drops its snapshot")
    @MainActor
    func removeDropsSnapshot() {
        let (store, _) = makeStore()
        let claude = account(.claudeCode, "Main")
        store.add(account: claude)
        store.apply(.success([LimitWindow(kind: .fiveHour, usedPercent: 10, usedAbsolute: nil, resetsAt: nil)]), for: claude.id)
        #expect(store.snapshot(for: claude.id) != nil)

        store.remove(account: claude)

        #expect(store.snapshot(for: claude.id) == nil)
        #expect(store.snapshots[claude.id] == nil)
    }

    @Test("Removing the active account clears the persisted active selection")
    @MainActor
    func removingActiveClearsSelection() {
        let (store, spy) = makeStore()
        let claude = account(.claudeCode, "Main")
        store.add(account: claude)
        store.selectActive(claude.id)
        #expect(store.activeAccountID == claude.id)

        store.remove(account: claude)

        #expect(store.activeAccountID == nil)
        #expect(spy.load()?.activeAccountID == nil)
    }

    @Test("Removing a non-active account keeps the current selection")
    @MainActor
    func removingOtherKeepsSelection() {
        let (store, _) = makeStore()
        let a = account(.codex, "Codex A")
        let b = account(.codex, "Codex B")
        store.add(account: a)
        store.add(account: b)
        store.selectActive(b.id)

        store.remove(account: a)

        #expect(store.activeAccountID == b.id)
    }

    @Test("Multiple accounts per provider coexist distinguished by label")
    @MainActor
    func multipleAccountsPerProviderCoexist() {
        let (store, spy) = makeStore()
        let work = Account(id: UUID(), provider: .codex, label: "Work", displayedWindow: .fiveHour, codexHomeOverride: "~/codex-work")
        let personal = Account(id: UUID(), provider: .codex, label: "Personal", displayedWindow: .fiveHour, codexHomeOverride: nil)

        store.add(account: work)
        store.add(account: personal)

        #expect(store.accounts.map(\.label) == ["Work", "Personal"])
        #expect(store.accounts.filter { $0.provider == .codex }.count == 2)
        #expect(Set(store.accounts.map(\.id)).count == 2)
        #expect(spy.load()?.accounts.count == 2)
    }

    @Test("Updating an account replaces its fields in place and persists")
    @MainActor
    func updateReplacesFields() {
        let (store, spy) = makeStore()
        let original = account(.openCodeGo, "Go")
        store.add(account: original)
        var renamed = original
        renamed.label = "Go Pro"
        renamed.displayedWindow = .monthly

        store.update(account: renamed)

        #expect(store.accounts == [renamed])
        #expect(spy.load()?.accounts == [renamed])
    }

    @Test("Successful fetch stores a fresh snapshot with windows and injected fetch time")
    @MainActor
    func applySuccessStoresFreshSnapshot() {
        let (store, spy) = makeStore(now: { self.fixedNow })
        let codex = account(.codex, "Codex")
        store.add(account: codex)
        let windows = [
            LimitWindow(kind: .fiveHour, usedPercent: 42.5, usedAbsolute: nil, resetsAt: fixedNow),
            LimitWindow(kind: .weekly, usedPercent: 8.0, usedAbsolute: nil, resetsAt: nil),
        ]

        store.apply(.success(windows), for: codex.id)

        let snapshot = store.snapshot(for: codex.id)
        #expect(snapshot?.state == .fresh)
        #expect(snapshot?.windows == windows)
        #expect(snapshot?.fetchedAt == fixedNow)
        #expect(spy.load()?.snapshots[codex.id]?.state == .fresh)
    }

    @Test("Rate-limited fetch marks the snapshot stale while keeping last good data")
    @MainActor
    func applyRateLimitedKeepsLastGoodData() {
        let (store, _) = makeStore(now: { self.fixedNow })
        let claude = account(.claudeCode, "Claude")
        store.add(account: claude)
        let goodWindows = [LimitWindow(kind: .fiveHour, usedPercent: 65, usedAbsolute: nil, resetsAt: fixedNow)]
        store.apply(.success(goodWindows), for: claude.id)

        store.apply(.rateLimited(retryAfter: 120), for: claude.id)

        let snapshot = store.snapshot(for: claude.id)
        #expect(snapshot?.state == .stale)
        #expect(snapshot?.windows == goodWindows)
        #expect(snapshot?.fetchedAt == fixedNow)
    }

    @Test("Unauthorized and missing credentials map to the unauthorized state keeping the cache")
    @MainActor
    func applyUnauthorizedKeepsCache() {
        let (store, _) = makeStore(now: { self.fixedNow })
        let claude = account(.claudeCode, "Claude")
        store.add(account: claude)
        let cached = [LimitWindow(kind: .weekly, usedPercent: 30, usedAbsolute: nil, resetsAt: nil)]
        store.apply(.success(cached), for: claude.id)

        store.apply(.failure(.unauthorized), for: claude.id)
        #expect(store.snapshot(for: claude.id)?.state == .unauthorized)
        #expect(store.snapshot(for: claude.id)?.windows == cached)

        store.apply(.failure(.missingCredentials), for: claude.id)
        #expect(store.snapshot(for: claude.id)?.state == .unauthorized)
        #expect(store.snapshot(for: claude.id)?.windows == cached)
    }

    @Test("Unsupported clears bars; network and parse failures record error messages over cache")
    @MainActor
    func applyUnsupportedAndErrorTransitions() {
        let (store, _) = makeStore(now: { self.fixedNow })
        let go = account(.openCodeGo, "Go")
        let claude = account(.claudeCode, "Claude")
        store.add(account: go)
        store.add(account: claude)
        let cached = [LimitWindow(kind: .fiveHour, usedPercent: 50, usedAbsolute: nil, resetsAt: nil)]
        store.apply(.success(cached), for: go.id)
        store.apply(.success(cached), for: claude.id)

        store.apply(.failure(.unsupported), for: go.id)
        #expect(store.snapshot(for: go.id)?.state == .unsupported)
        #expect(store.snapshot(for: go.id)?.windows.isEmpty == true)

        store.apply(.failure(.parseFailed), for: claude.id)
        #expect(store.snapshot(for: claude.id)?.state == .error(AccountStore.parseFailureMessage))
        #expect(store.snapshot(for: claude.id)?.windows == cached)

        let offline = URLError(.notConnectedToInternet)
        store.apply(.failure(.network(offline)), for: claude.id)
        #expect(store.snapshot(for: claude.id)?.state == .error("Network error: \(URLError.notConnectedToInternet.rawValue)"))
        #expect(store.snapshot(for: claude.id)?.windows == cached)
    }
}
