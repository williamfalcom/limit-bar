import AppKit
import Foundation

struct BackoffPolicy: Sendable, Equatable {
    static let maxDelay: TimeInterval = 1800

    private(set) var baseInterval: TimeInterval
    private(set) var doublings = 0

    init(baseInterval: TimeInterval) {
        self.baseInterval = baseInterval
    }

    var nextDelay: TimeInterval {
        guard doublings > 0 else { return baseInterval }
        let ceiling = max(Self.maxDelay, baseInterval)
        return min(baseInterval * pow(2, Double(doublings)), ceiling)
    }

    mutating func recordRateLimited() {
        doublings += 1
    }

    mutating func recordSuccess() {
        doublings = 0
    }

    mutating func reset() {
        doublings = 0
    }

    mutating func changeBase(to interval: TimeInterval) {
        baseInterval = interval
    }
}

actor PollingEngine {
    static func needsWakeRefresh(fetchedAt: Date?, interval: TimeInterval, now: Date) -> Bool {
        guard let fetchedAt else { return true }
        return now.timeIntervalSince(fetchedAt) > interval
    }

    private struct Schedule {
        var policy: BackoffPolicy
        var lastAttemptAt: Date?
    }

    private let store: AccountStore
    private let adapters: [ProviderKind: any ProviderAdapter]
    private let notifications: NotificationService?
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    private var schedules: [UUID: Schedule] = [:]
    private var loopTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    init(
        store: AccountStore,
        adapters: [ProviderKind: any ProviderAdapter],
        notifications: NotificationService? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.store = store
        self.adapters = adapters
        self.notifications = notifications
        self.now = now
        self.sleep = sleep
    }

    func start() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.runCycle()
            }
        }
        wakeObserver = NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.handleWake() }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        if let wakeObserver {
            NotificationCenter.default.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    func runCycle() async {
        await syncSchedules()
        let currentNow = now()
        for account in await store.accounts {
            guard let schedule = schedules[account.id] else { continue }
            let due: Bool
            if let last = schedule.lastAttemptAt {
                due = currentNow.timeIntervalSince(last) >= schedule.policy.nextDelay
            } else {
                due = true
            }
            if due {
                await refresh(account)
            }
        }
        let fallback = await store.pollInterval
        let delay = nextWakeDelay(after: now()) ?? fallback
        guard delay > 0 else { return }
        try? await sleep(delay)
    }

    func refreshAllNow() async {
        await syncSchedules()
        for id in schedules.keys {
            schedules[id]?.policy.reset()
        }
        for account in await store.accounts {
            await refresh(account)
        }
    }

    func intervalChanged() async {
        let interval = await store.pollInterval
        for id in schedules.keys {
            schedules[id]?.policy.changeBase(to: interval)
        }
    }

    func handleWake() async {
        await syncSchedules()
        let currentNow = now()
        for account in await store.accounts {
            guard let schedule = schedules[account.id] else { continue }
            let fetchedAt = await store.snapshot(for: account.id)?.fetchedAt
            if Self.needsWakeRefresh(fetchedAt: fetchedAt, interval: schedule.policy.baseInterval, now: currentNow) {
                await refresh(account)
            }
        }
    }

    private func refresh(_ account: Account) async {
        schedules[account.id]?.lastAttemptAt = now()
        guard let adapter = adapters[account.provider] else {
            await store.apply(.failure(.unsupported), for: account.id)
            return
        }
        let result: FetchResult
        do {
            result = .success(try await adapter.fetchUsage(for: account))
        } catch let error as ProviderError {
            if case .rateLimited(let retryAfter) = error {
                result = .rateLimited(retryAfter: retryAfter)
            } else {
                result = .failure(error)
            }
        } catch {
            result = .failure(.parseFailed)
        }
        switch result {
        case .success:
            schedules[account.id]?.policy.recordSuccess()
        case .rateLimited:
            schedules[account.id]?.policy.recordRateLimited()
        case .failure:
            break
        }
        await store.apply(result, for: account.id)
        if case .success(let windows) = result, let notifications {
            await notifications.process(success: windows, accountID: account.id)
        }
    }

    private func nextWakeDelay(after date: Date) -> TimeInterval? {
        guard !schedules.isEmpty else { return nil }
        let delays = schedules.values.compactMap { schedule -> TimeInterval? in
            guard let last = schedule.lastAttemptAt else { return nil }
            return max(0, last.addingTimeInterval(schedule.policy.nextDelay).timeIntervalSince(date))
        }
        return delays.min()
    }

    private func syncSchedules() async {
        let interval = await store.pollInterval
        let ids = Set(await store.accounts.map(\.id))
        for id in ids where schedules[id] == nil {
            schedules[id] = Schedule(policy: BackoffPolicy(baseInterval: interval), lastAttemptAt: nil)
        }
        for id in schedules.keys where !ids.contains(id) {
            schedules.removeValue(forKey: id)
        }
        for id in ids {
            if var schedule = schedules[id], schedule.policy.baseInterval != interval {
                schedule.policy.changeBase(to: interval)
                schedules[id] = schedule
            }
        }
    }
}
