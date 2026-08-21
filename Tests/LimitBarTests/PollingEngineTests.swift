import Foundation
import Testing
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

private final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) {
        self.date = date
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }

    func advance(_ interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        date.addTimeInterval(interval)
    }
}

private final class SleepLog: @unchecked Sendable {
    private let lock = NSLock()
    private var delays: [TimeInterval] = []

    func append(_ delay: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        delays.append(delay)
    }

    var recorded: [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return delays
    }
}

private final class FetchLog: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [UUID: Int] = [:]

    func record(_ id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        counts[id, default: 0] += 1
    }

    func count(_ id: UUID) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[id] ?? 0
    }

    var total: Int {
        lock.lock()
        defer { lock.unlock() }
        return counts.values.reduce(0, +)
    }
}

private final class ScriptedProvider: ProviderAdapter, @unchecked Sendable {
    enum Outcome {
        case success([LimitWindow])
        case rateLimited(retryAfter: TimeInterval?)
        case failure(ProviderError)
    }

    private let lock = NSLock()
    private var outcomes: [Outcome]
    private let log: FetchLog?

    init(_ outcomes: [Outcome], loggingTo log: FetchLog? = nil) {
        self.outcomes = outcomes
        self.log = log
    }

    func fetchUsage(for account: Account) async throws -> [LimitWindow] {
        let outcome = dequeue(account.id)
        switch outcome {
        case .success(let windows):
            return windows
        case .rateLimited(let retryAfter):
            throw ProviderError.rateLimited(retryAfter: retryAfter)
        case .failure(let error):
            throw error
        }
    }

    private func dequeue(_ id: UUID) -> Outcome {
        lock.lock()
        defer { lock.unlock() }
        log?.record(id)
        return outcomes.isEmpty ? .success([]) : outcomes.removeFirst()
    }
}

@Suite("PollingEngine")
struct PollingEngineTests {

    private let fixedNow = Date(timeIntervalSince1970: 1_770_000_000)

    private func account(_ provider: ProviderKind, _ label: String) -> Account {
        Account(id: UUID(), provider: provider, label: label, displayedWindow: .fiveHour, codexHomeOverride: nil)
    }

    private let sampleWindows = [LimitWindow(kind: .fiveHour, usedPercent: 42, usedAbsolute: nil, resetsAt: nil)]

    @MainActor
    private func makeEngine(
        accounts: [Account],
        outcomes: [ProviderKind: [ScriptedProvider.Outcome]]
    ) -> (PollingEngine, AccountStore, FetchLog, SleepLog, MutableClock) {
        let clock = MutableClock(fixedNow)
        let store = AccountStore(persistence: PersistingSpy(), now: { clock.now })
        let log = FetchLog()
        let sleeps = SleepLog()
        for account in accounts {
            store.add(account: account)
        }
        let adapters: [ProviderKind: any ProviderAdapter] = outcomes.mapValues {
            ScriptedProvider($0, loggingTo: log)
        }
        let engine = PollingEngine(
            store: store,
            adapters: adapters,
            now: { clock.now },
            sleep: { sleeps.append($0) }
        )
        return (engine, store, log, sleeps, clock)
    }

    @Test("BackoffPolicy doubles the delay on each rate limit")
    func doublingSequence() {
        var policy = BackoffPolicy(baseInterval: 300)
        var delays: [TimeInterval] = []
        for _ in 0..<4 {
            policy.recordRateLimited()
            delays.append(policy.nextDelay)
        }
        #expect(delays == [600, 1200, 1800, 1800])
    }

    @Test("BackoffPolicy caps the delay at 30 minutes")
    func capAtThirtyMinutes() {
        #expect(BackoffPolicy.maxDelay == 1800)
        var policy = BackoffPolicy(baseInterval: 60)
        var delays: [TimeInterval] = []
        for _ in 0..<6 {
            policy.recordRateLimited()
            delays.append(policy.nextDelay)
        }
        #expect(delays == [120, 240, 480, 960, 1800, 1800])
    }

    @Test("BackoffPolicy resets to the base interval on success")
    func resetOnSuccess() {
        var policy = BackoffPolicy(baseInterval: 300)
        policy.recordRateLimited()
        policy.recordRateLimited()
        #expect(policy.nextDelay == 1200)

        policy.recordSuccess()

        #expect(policy.nextDelay == 300)
    }

    @Test("BackoffPolicy manual reset restores the base interval")
    func resetManually() {
        var policy = BackoffPolicy(baseInterval: 300)
        policy.recordRateLimited()
        policy.recordRateLimited()
        policy.recordRateLimited()

        policy.reset()

        #expect(policy.nextDelay == 300)
    }

    @MainActor
    @Test("Loop fires at the base interval then at doubled backed-off intervals")
    func loopFiresAtBaseThenBackedOffIntervals() async {
        let claude = account(.claudeCode, "Claude")
        let (engine, store, log, sleeps, clock) = makeEngine(
            accounts: [claude],
            outcomes: [.claudeCode: [
                .success(sampleWindows),
                .rateLimited(retryAfter: nil),
                .rateLimited(retryAfter: nil),
            ]]
        )

        await engine.runCycle()
        clock.advance(300)
        await engine.runCycle()
        clock.advance(600)
        await engine.runCycle()

        #expect(log.total == 3)
        #expect(sleeps.recorded == [300, 600, 1200])
        #expect(store.snapshot(for: claude.id)?.state == .stale)
        #expect(store.snapshot(for: claude.id)?.windows == sampleWindows)
    }

    @MainActor
    @Test("A successful fetch after backoff restores the base cadence")
    func successRestoresCadence() async {
        let claude = account(.claudeCode, "Claude")
        let (engine, _, log, sleeps, clock) = makeEngine(
            accounts: [claude],
            outcomes: [.claudeCode: [
                .rateLimited(retryAfter: nil),
                .success(sampleWindows),
            ]]
        )

        await engine.runCycle()
        clock.advance(600)
        await engine.runCycle()

        #expect(log.total == 2)
        #expect(sleeps.recorded == [600, 300])
    }

    @MainActor
    @Test("Manual refresh fetches all accounts immediately and resets backoff to base")
    func manualRefreshResetsBackoff() async {
        let claude = account(.claudeCode, "Claude")
        let (engine, _, log, sleeps, clock) = makeEngine(
            accounts: [claude],
            outcomes: [.claudeCode: [
                .rateLimited(retryAfter: nil),
                .rateLimited(retryAfter: nil),
                .rateLimited(retryAfter: nil),
                .rateLimited(retryAfter: nil),
            ]]
        )

        await engine.runCycle()
        clock.advance(600)
        await engine.runCycle()

        await engine.refreshAllNow()
        clock.advance(600)
        await engine.runCycle()

        #expect(log.total == 4)
        #expect(sleeps.recorded == [600, 1200, 1200])
    }

    @MainActor
    @Test("Network failure keeps the previous snapshot data visible untouched")
    func networkFailureKeepsPreviousSnapshot() async {
        let claude = account(.claudeCode, "Claude")
        let (engine, store, _, _, clock) = makeEngine(
            accounts: [claude],
            outcomes: [.claudeCode: [
                .success(sampleWindows),
                .failure(.network(URLError(.notConnectedToInternet))),
            ]]
        )

        await engine.runCycle()
        clock.advance(300)
        await engine.runCycle()

        let snapshot = store.snapshot(for: claude.id)
        #expect(snapshot?.state == .error("Network error: \(URLError.notConnectedToInternet.rawValue)"))
        #expect(snapshot?.windows == sampleWindows)
        #expect(snapshot?.fetchedAt == fixedNow)
    }

    @MainActor
    @Test("Rate-limited fetch keeps the last good data marked stale")
    func rateLimitedKeepsLastGoodData() async {
        let claude = account(.claudeCode, "Claude")
        let (engine, store, _, _, clock) = makeEngine(
            accounts: [claude],
            outcomes: [.claudeCode: [
                .success(sampleWindows),
                .rateLimited(retryAfter: 120),
            ]]
        )

        await engine.runCycle()
        clock.advance(300)
        await engine.runCycle()

        let snapshot = store.snapshot(for: claude.id)
        #expect(snapshot?.state == .stale)
        #expect(snapshot?.windows == sampleWindows)
        #expect(snapshot?.fetchedAt == fixedNow)
    }

    @Test("Wake predicate refreshes only data older than its interval")
    func wakePredicateBoundaries() {
        #expect(PollingEngine.needsWakeRefresh(fetchedAt: nil, interval: 300, now: fixedNow) == true)
        #expect(PollingEngine.needsWakeRefresh(fetchedAt: fixedNow.addingTimeInterval(-299), interval: 300, now: fixedNow) == false)
        #expect(PollingEngine.needsWakeRefresh(fetchedAt: fixedNow.addingTimeInterval(-300), interval: 300, now: fixedNow) == false)
        #expect(PollingEngine.needsWakeRefresh(fetchedAt: fixedNow.addingTimeInterval(-301), interval: 300, now: fixedNow) == true)
    }

    @MainActor
    @Test("Wake catch-up refreshes exactly the stale accounts")
    func wakeRefreshesExactlyStaleAccounts() async {
        let stale = account(.claudeCode, "Old")
        let fresh = account(.codex, "Recent")
        let (engine, store, log, _, clock) = makeEngine(
            accounts: [stale, fresh],
            outcomes: [
                .claudeCode: [.success(sampleWindows)],
                .codex: [.success(sampleWindows)],
            ]
        )

        store.apply(.success(sampleWindows), for: stale.id)
        clock.advance(990)
        store.apply(.success(sampleWindows), for: fresh.id)
        clock.advance(10)

        await engine.handleWake()

        #expect(log.count(stale.id) == 1)
        #expect(log.count(fresh.id) == 0)
    }

    @MainActor
    @Test("Interval changes adopt the new clamped base interval")
    func intervalChangedAdoptsNewBase() async {
        let claude = account(.claudeCode, "Claude")
        let (engine, store, log, sleeps, clock) = makeEngine(
            accounts: [claude],
            outcomes: [.claudeCode: [
                .success(sampleWindows),
                .success(sampleWindows),
                .success(sampleWindows),
            ]]
        )

        await engine.runCycle()

        store.setPollInterval(120)
        await engine.intervalChanged()
        clock.advance(120)
        await engine.runCycle()

        store.setPollInterval(10)
        await engine.intervalChanged()
        clock.advance(60)
        await engine.runCycle()

        #expect(log.total == 3)
        #expect(sleeps.recorded == [300, 120, 60])
    }
}
