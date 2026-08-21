import Testing
import Foundation
@testable import limit_bar

@Suite("PersistenceController")
struct PersistenceTests {

    private let fileManager = FileManager.default

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("limit-bar-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func sampleState(label: String) -> AppState {
        let id = UUID()
        return AppState(
            accounts: [Account(id: id, provider: .claudeCode, label: label, displayedWindow: .fiveHour, codexHomeOverride: nil)],
            snapshots: [
                id: AccountSnapshot(
                    windows: [LimitWindow(kind: .weekly, usedPercent: 55.5, usedAbsolute: nil, resetsAt: Date(timeIntervalSince1970: 1_770_000_000))],
                    fetchedAt: Date(timeIntervalSince1970: 1_769_999_000),
                    state: .fresh
                )
            ],
            activeAccountID: id,
            pollInterval: 300
        )
    }

    @Test("Save then load round-trips identical state")
    func roundTrip() throws {
        let dir = try makeTempDirectory()
        defer { try? fileManager.removeItem(at: dir) }
        let controller = PersistenceController(directory: dir)
        let state = sampleState(label: "Main")

        controller.save(state)

        #expect(controller.load() == state)
    }

    @Test("Load returns nil when no state file exists")
    func loadMissingFileReturnsNil() throws {
        let dir = try makeTempDirectory()
        defer { try? fileManager.removeItem(at: dir) }
        let controller = PersistenceController(directory: dir)

        #expect(controller.load() == nil)
    }

    @Test("Load returns nil for corrupt JSON or wrong-shaped JSON without throwing")
    func loadCorruptJSONReturnsNil() throws {
        let dir = try makeTempDirectory()
        defer { try? fileManager.removeItem(at: dir) }
        let url = dir.appendingPathComponent("state.json")

        try Data("not json at all {{{".utf8).write(to: url)
        #expect(PersistenceController(directory: dir).load() == nil)

        try Data("[1, 2, 3]".utf8).write(to: url)
        #expect(PersistenceController(directory: dir).load() == nil)
    }

    @Test("Failed write leaves the previous state intact (no partial file)")
    func failedWriteKeepsPreviousState() throws {
        let dir = try makeTempDirectory()
        defer { try? fileManager.removeItem(at: dir) }
        let controller = PersistenceController(directory: dir)
        let original = sampleState(label: "Original")
        controller.save(original)

        try fileManager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        defer { try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }

        controller.save(sampleState(label: "Replacement"))

        #expect(controller.load() == original)
    }

    @Test("Successful save leaves no temporary files behind")
    func successfulSaveLeavesNoTemporaryFiles() throws {
        let dir = try makeTempDirectory()
        defer { try? fileManager.removeItem(at: dir) }
        let controller = PersistenceController(directory: dir)

        controller.save(sampleState(label: "Clean"))

        let contents = try fileManager.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(contents == ["state.json"])
    }

    @Test("Default location is Application Support/limit-bar/state.json")
    func defaultLocationPointsToApplicationSupport() {
        let base = URL(fileURLWithPath: "/Users/dev/Library/Application Support")
        let url = PersistenceController.stateFileURL(inApplicationSupport: base)

        #expect(url.path == "/Users/dev/Library/Application Support/limit-bar/state.json")
        #expect(PersistenceController(directory: nil).stateFileURL.path.hasSuffix("/Application Support/limit-bar/state.json"))
    }
}
