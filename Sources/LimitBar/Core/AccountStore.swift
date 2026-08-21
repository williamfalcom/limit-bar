import Foundation
import Observation

enum FetchResult: Sendable, Equatable {
    case success([LimitWindow])
    case rateLimited(retryAfter: TimeInterval?)
    case failure(ProviderError)
}

@Observable
@MainActor
final class AccountStore {
    static let defaultPollInterval: TimeInterval = 300
    static let parseFailureMessage = "Response could not be parsed"
    static let minPollInterval: TimeInterval = 60
    static let maxPollInterval: TimeInterval = 3600

    private(set) var accounts: [Account]
    private(set) var snapshots: [UUID: AccountSnapshot]
    private(set) var activeAccountID: UUID?
    private(set) var pollInterval: TimeInterval

    private let persistence: StatePersisting
    private let now: @Sendable () -> Date

    init(persistence: StatePersisting, now: @escaping @Sendable () -> Date = { Date() }) {
        self.persistence = persistence
        self.now = now
        if let saved = persistence.load() {
            accounts = saved.accounts
            snapshots = saved.snapshots
            activeAccountID = saved.activeAccountID
            pollInterval = saved.pollInterval
        } else {
            accounts = []
            snapshots = [:]
            activeAccountID = nil
            pollInterval = Self.defaultPollInterval
        }
    }

    func snapshot(for id: UUID) -> AccountSnapshot? {
        snapshots[id]
    }

    func add(account: Account) {
        accounts.append(account)
        persist()
    }

    func update(account: Account) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index] = account
        persist()
    }

    func remove(account: Account) {
        accounts.removeAll { $0.id == account.id }
        snapshots[account.id] = nil
        if activeAccountID == account.id {
            activeAccountID = nil
        }
        persist()
    }

    func selectActive(_ id: UUID?) {
        guard id == nil || accounts.contains(where: { $0.id == id }) else { return }
        activeAccountID = id
        persist()
    }

    func setPollInterval(_ interval: TimeInterval) {
        pollInterval = min(max(interval, Self.minPollInterval), Self.maxPollInterval)
        persist()
    }

    func apply(_ result: FetchResult, for accountID: UUID) {
        let previous = snapshots[accountID]
        let next: AccountSnapshot
        switch result {
        case .success(let windows):
            next = AccountSnapshot(windows: windows, fetchedAt: now(), state: .fresh)
        case .rateLimited:
            next = AccountSnapshot(windows: previous?.windows ?? [], fetchedAt: previous?.fetchedAt, state: .stale)
        case .failure(let error):
            switch error {
            case .unauthorized, .missingCredentials:
                next = AccountSnapshot(windows: previous?.windows ?? [], fetchedAt: previous?.fetchedAt, state: .unauthorized)
            case .unsupported:
                next = AccountSnapshot(windows: [], fetchedAt: previous?.fetchedAt, state: .unsupported)
            case .parseFailed:
                next = AccountSnapshot(windows: previous?.windows ?? [], fetchedAt: previous?.fetchedAt, state: .error(Self.parseFailureMessage))
            case .network(let urlError):
                next = AccountSnapshot(windows: previous?.windows ?? [], fetchedAt: previous?.fetchedAt, state: .error("Network error: \(urlError.code.rawValue)"))
            case .rateLimited:
                next = AccountSnapshot(windows: previous?.windows ?? [], fetchedAt: previous?.fetchedAt, state: .stale)
            }
        }
        snapshots[accountID] = next
        persist()
    }

    func markStale(accountID: UUID) {
        guard var snapshot = snapshots[accountID], snapshot.state == .fresh else { return }
        snapshot.state = .stale
        snapshots[accountID] = snapshot
        persist()
    }

    private func persist() {
        persistence.save(AppState(
            accounts: accounts,
            snapshots: snapshots,
            activeAccountID: activeAccountID,
            pollInterval: pollInterval
        ))
    }
}
