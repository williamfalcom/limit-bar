import Foundation

protocol StatePersisting: Sendable {
    func load() -> AppState?
    func save(_ state: AppState)
}

struct PersistenceController: StatePersisting, Sendable {
    let stateFileURL: URL

    init(directory: URL? = nil) {
        let base = directory ?? Self.defaultDirectory()
        self.stateFileURL = base.appendingPathComponent("state.json", isDirectory: false)
    }

    static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("limit-bar", isDirectory: true)
    }

    static func stateFileURL(inApplicationSupport base: URL) -> URL {
        base.appendingPathComponent("limit-bar", isDirectory: true)
            .appendingPathComponent("state.json", isDirectory: false)
    }

    func load() -> AppState? {
        guard let data = try? Data(contentsOf: stateFileURL) else { return nil }
        return try? JSONDecoder().decode(AppState.self, from: data)
    }

    func save(_ state: AppState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        let directory = stateFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: stateFileURL, options: .atomic)
    }
}
