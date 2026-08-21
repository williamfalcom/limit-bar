import Testing
import Foundation
@testable import limit_bar

private let fixtureDate = Date(timeIntervalSince1970: 1_770_000_000)

private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
    let data = try JSONEncoder().encode(value)
    return try JSONDecoder().decode(T.self, from: data)
}

@Suite("Domain models")
struct ModelsTests {

    @Test("ProviderKind/WindowKind raw values match design contract")
    func rawValuesMatchDesign() {
        #expect(ProviderKind.claudeCode.rawValue == "claudeCode")
        #expect(ProviderKind.codex.rawValue == "codex")
        #expect(ProviderKind.openCodeGo.rawValue == "openCodeGo")
        #expect(WindowKind.fiveHour.rawValue == "fiveHour")
        #expect(WindowKind.weekly.rawValue == "weekly")
        #expect(WindowKind.monthly.rawValue == "monthly")
    }

    @Test("WindowKind weeklyModel survives JSON round-trip and unknown raws throw")
    func weeklyModelCodableRoundTrip() throws {
        let encoded = try JSONEncoder().encode(WindowKind.weeklyModel("Fable"))
        #expect(String(decoding: encoded, as: UTF8.self) == "\"weeklyModel:Fable\"")
        let decoded = try JSONDecoder().decode(WindowKind.self, from: encoded)
        #expect(decoded == .weeklyModel("Fable"))
        #expect(decoded.hashValue == WindowKind.weeklyModel("Fable").hashValue)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(WindowKind.self, from: Data("\"bogus\"".utf8))
        }
    }

    @Test("Account round-trip preserves every field including set codexHomeOverride")
    func accountRoundTripWithCodexHomeOverride() throws {
        let account = Account(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            provider: .codex,
            label: "Work Codex",
            displayedWindow: .weekly,
            codexHomeOverride: "~/codex-work"
        )
        #expect(try roundTrip(account) == account)
    }

    @Test("Account nil codexHomeOverride survives round-trip as nil")
    func accountRoundTripNilOverride() throws {
        let account = Account(
            id: UUID(),
            provider: .claudeCode,
            label: "Personal",
            displayedWindow: .fiveHour,
            codexHomeOverride: nil
        )
        let decoded = try roundTrip(account)
        #expect(decoded == account)
        #expect(decoded.codexHomeOverride == nil)
    }

    @Test("LimitWindow round-trip preserves percent, absolute value, reset date, kind")
    func limitWindowRoundTripPreservesAllFields() throws {
        let full = LimitWindow(kind: .fiveHour, usedPercent: 42.5, usedAbsolute: "$8.40", resetsAt: fixtureDate)
        #expect(try roundTrip(full) == full)

        let bare = LimitWindow(kind: .monthly, usedPercent: 0, usedAbsolute: nil, resetsAt: nil)
        let decodedBare = try roundTrip(bare)
        #expect(decodedBare == bare)
        #expect(decodedBare.usedAbsolute == nil)
        #expect(decodedBare.resetsAt == nil)
    }

    @Test("SnapshotState .error preserves its message through JSON")
    func snapshotStateErrorPreservesMessage() throws {
        let decoded = try roundTrip(SnapshotState.error("HTTP 500"))
        #expect(decoded == .error("HTTP 500"))
    }

    @Test("SnapshotState plain cases survive JSON round-trip")
    func snapshotStatePlainCasesSurvive() throws {
        #expect(try roundTrip(SnapshotState.fresh) == .fresh)
        #expect(try roundTrip(SnapshotState.stale) == .stale)
        #expect(try roundTrip(SnapshotState.unauthorized) == .unauthorized)
        #expect(try roundTrip(SnapshotState.unsupported) == .unsupported)
    }

    @Test("AccountSnapshot round-trip preserves windows, fetchedAt, state")
    func accountSnapshotRoundTrip() throws {
        let snapshot = AccountSnapshot(
            windows: [
                LimitWindow(kind: .fiveHour, usedPercent: 71.0, usedAbsolute: nil, resetsAt: fixtureDate),
                LimitWindow(kind: .weekly, usedPercent: 12.25, usedAbsolute: "$3.10", resetsAt: nil),
            ],
            fetchedAt: fixtureDate,
            state: .fresh
        )
        #expect(try roundTrip(snapshot) == snapshot)
    }

    @Test("AppState round-trip preserves accounts, snapshot dictionary, active ID, interval")
    func appStateRoundTrip() throws {
        let claudeID = UUID()
        let goID = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        let state = AppState(
            accounts: [
                Account(id: claudeID, provider: .claudeCode, label: "Main", displayedWindow: .fiveHour, codexHomeOverride: nil),
                Account(id: goID, provider: .openCodeGo, label: "Go plan", displayedWindow: .monthly, codexHomeOverride: nil),
            ],
            snapshots: [
                claudeID: AccountSnapshot(
                    windows: [LimitWindow(kind: .fiveHour, usedPercent: 90.0, usedAbsolute: nil, resetsAt: fixtureDate)],
                    fetchedAt: fixtureDate,
                    state: .stale
                ),
                goID: AccountSnapshot(windows: [], fetchedAt: nil, state: .unsupported),
            ],
            activeAccountID: goID,
            pollInterval: 120
        )
        let decoded = try roundTrip(state)
        #expect(decoded.accounts == state.accounts)
        #expect(decoded.snapshots == state.snapshots)
        #expect(decoded.activeAccountID == goID)
        #expect(decoded.pollInterval == 120)
    }
}
