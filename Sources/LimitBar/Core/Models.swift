import Foundation

enum ProviderKind: String, Codable, Sendable, Equatable { case claudeCode, codex, openCodeGo }
enum WindowKind: String, Codable, Sendable, Equatable { case fiveHour, weekly, monthly }

struct Account: Identifiable, Codable, Sendable, Equatable {
    var id: UUID
    var provider: ProviderKind
    var label: String                  // tab title; unique per user editing
    var displayedWindow: WindowKind    // drives menu bar icon (default .fiveHour)
    var codexHomeOverride: String?     // multi-account Codex via separate CODEX_HOME
}

struct LimitWindow: Codable, Equatable, Sendable {
    let kind: WindowKind
    var usedPercent: Double            // 0...100
    var usedAbsolute: String?          // "$8.40" when provider reports it
    var resetsAt: Date?
}

enum SnapshotState: Codable, Sendable, Equatable {
    case fresh, stale
    case error(String)                 // network/parse message
    case unauthorized                  // 401/403 → show CLI re-login instructions
    case unsupported                   // OpenCode Go until endpoint exists
}

struct AccountSnapshot: Codable, Sendable, Equatable {
    var windows: [LimitWindow]
    var fetchedAt: Date?
    var state: SnapshotState
}

struct AppState: Codable, Sendable, Equatable {
    var accounts: [Account]
    var snapshots: [UUID: AccountSnapshot]   // last-good cache across launches
    var activeAccountID: UUID?
    var pollInterval: TimeInterval           // default 300, clamp 60...3600
}

enum ProviderError: Error, Sendable, Equatable {
    case missingCredentials
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case network(URLError)
    case parseFailed
    case unsupported
}

protocol ProviderAdapter: Sendable {
    func fetchUsage(for account: Account) async throws -> [LimitWindow]
}
