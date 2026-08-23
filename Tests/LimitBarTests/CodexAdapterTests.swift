import Testing
import Foundation
@testable import limit_bar

@Suite("CodexAdapter", .serialized)
struct CodexAdapterTests {

    private let testID = UUID().uuidString
    private let fixedNow = Date(timeIntervalSince1970: 1_770_000_000)

    private var account: Account {
        Account(id: UUID(), provider: .codex, label: "Codex", displayedWindow: .fiveHour, codexHomeOverride: nil)
    }

    private func rateLimitsFixture(_ entries: [(percent: Double, seconds: Int, resetsIn: Int)]) -> String {
        let items = entries
            .map { #"{"used_percent": \#($0.percent), "limit_window_seconds": \#($0.seconds), "resets_in_seconds": \#($0.resetsIn)}"# }
            .joined(separator: ",")
        return items
    }

    private func appServerEnvelope(primary: (percent: Double, minutes: Int, resetsAtEpoch: Int)?, secondary: (percent: Double, minutes: Int, resetsAtEpoch: Int)?) -> String {
        func entry(_ e: (percent: Double, minutes: Int, resetsAtEpoch: Int)) -> String {
            #"{"usedPercent": \#(e.percent), "windowDurationMins": \#(e.minutes), "resetsAt": \#(e.resetsAtEpoch)}"#
        }
        let secondaryJSON = secondary.map { #", "secondary": \#(entry($0))"# } ?? ", \"secondary\": null"
        let primaryJSON = primary.map { entry($0) } ?? "null"
        return #"{"jsonrpc":"2.0","id":2,"result":{"rateLimits":{"limitId":"codex","primary":\#(primaryJSON)\#(secondaryJSON)}}}"#
    }

    private func appServerLine(percent: Double, minutes: Int, resetsAtEpoch: Int) -> String {
        appServerEnvelope(
            primary: (percent, minutes, resetsAtEpoch),
            secondary: nil
        )
    }

    /// Captured verbatim from `codex app-server --stdio` 0.149.0 after a correct initialize handshake.
    private let realAppServerStdout = """
    {"error":{"code":-32600,"message":"Invalid request: missing field `clientInfo`"},"id":1}
    {"id":1,"result":{"userAgent":"limit-bar/0.149.0"}}
    {"id":2,"result":{"rateLimits":{"limitId":"codex","limitName":null,"primary":{"usedPercent":0,"windowDurationMins":10080,"resetsAt":1787865353},"secondary":null,"credits":{"hasCredits":false,"unlimited":false,"balance":"0"},"individualLimit":null,"spendControlReached":false,"planType":"plus","rateLimitReachedType":null},"rateLimitsByLimitId":{"codex":{"limitId":"codex","limitName":null,"primary":{"usedPercent":0,"windowDurationMins":10080,"resetsAt":1787865353},"secondary":null}}}}
    """

    private struct TransportBoom: Error {}

    private func makeAdapter(
        appServer overrideAppServer: (@Sendable () async throws -> String)? = nil,
        home: String = "/nonexistent-codex-home",
        readFile overrideReadFile: (@Sendable (URL) throws -> Data)? = nil
    ) -> (CodexAdapter, @Sendable () -> [URL]) {
        final class Box: @unchecked Sendable {
            let lock = NSLock()
            var urls: [URL] = []
        }
        let box = Box()
        let appServerImpl: @Sendable () async throws -> String
        if let overrideAppServer {
            appServerImpl = overrideAppServer
        } else {
            appServerImpl = { throw TransportBoom() }
        }
        let adapter = CodexAdapter(
            appServerStdout: appServerImpl,
            environmentHome: { home },
            readFile: { url in
                box.lock.lock()
                box.urls.append(url)
                box.lock.unlock()
                if let overrideReadFile {
                    return try overrideReadFile(url)
                }
                return try Data(contentsOf: url)
            },
            now: { self.fixedNow },
            session: stubbedSession()
        )
        return (adapter, { box.lock.lock(); defer { box.lock.unlock() }; return box.urls })
    }

    private func installHandler(_ handler: @escaping @Sendable (URLRequest) throws -> StubURLProtocol.Response) {
        StubURLProtocol.router.install(id: testID, handler: handler)
    }

    private func authJSON(token: String) -> String {
        #"{"OPENAI_API_KEY": "\#(token)"}"#
    }

    private func makeAuthFile(home: String) throws {
        let url = URL(fileURLWithPath: home).appendingPathComponent("auth.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(authJSON(token: "stub-\(testID)").utf8).write(to: url)
    }

    private func installChatGPTSuccess() {
        installHandler { _ in
            StubURLProtocol.Response(
                status: 200,
                json: #"{"rate_limits":[\#(self.rateLimitsFixture([(33.5, 18_000, 3_600)]))]}"#
            )
        }
    }

    @Test("App-server envelope classifies ~5h as fiveHour and ≥6-day as weekly with epoch resets")
    func appServerClassification() async throws {
        let baseEpoch = Int(fixedNow.timeIntervalSince1970)
        let adapter = makeAdapter(appServer: {
            self.appServerEnvelope(
                primary: (41.5, 300, baseEpoch + 3_600),
                secondary: (8.25, 10_080, baseEpoch + 86_400)
            )
        }).0

        let windows = try await adapter.fetchUsage(for: account)

        #expect(windows.map(\.kind) == [.fiveHour, .weekly])
        #expect(windows.map(\.usedPercent) == [41.5, 8.25])
        #expect(windows[0].resetsAt == fixedNow.addingTimeInterval(3_600))
        #expect(windows[1].resetsAt == fixedNow.addingTimeInterval(86_400))
    }

    @Test("Exactly 6 days of window minutes classifies weekly")
    func sixDayBoundaryClassifiesWeekly() async throws {
        let adapter = makeAdapter(appServer: { self.appServerLine(percent: 50.0, minutes: 8_640, resetsAtEpoch: 1) }).0

        let windows = try await adapter.fetchUsage(for: account)

        #expect(windows.count == 1)
        #expect(windows[0].kind == .weekly)
    }

    @Test("Real captured app-server stdout (init error interleaved) parses the primary window")
    func realCapturedStdoutParses() throws {
        let now = Date(timeIntervalSince1970: 1_787_000_000)

        let windows = try CodexAdapter.parseAppServerOutput(realAppServerStdout, now: now)

        #expect(windows.count == 1)
        #expect(windows[0].kind == .weekly)
        #expect(windows[0].usedPercent == 0)
        #expect(windows[0].resetsAt == Date(timeIntervalSince1970: 1_787_865_353))
    }

    @Test("Error response for the read request falls back to auth.json instead of surfacing parse failure")
    func errorResponseFallsBackToAuthJSON() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-err-\(UUID().uuidString)", isDirectory: true).path
        defer { try? FileManager.default.removeItem(atPath: home) }
        try makeAuthFile(home: home)
        installChatGPTSuccess()
        let (adapter, _) = makeAdapter(
            appServer: { #"{"jsonrpc":"2.0","id":2,"error":{"code":-32601,"message":"Not initialized"}}"# },
            home: home
        )

        let windows = try await adapter.fetchUsage(for: account)

        #expect(windows.map(\.usedPercent) == [33.5])
    }

    @Test("App-server transport failure falls back to the auth.json path")
    func transportFailureFallsBack() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-home-\(UUID().uuidString)", isDirectory: true).path
        defer { try? FileManager.default.removeItem(atPath: home) }
        try makeAuthFile(home: home)
        installChatGPTSuccess()
        let (adapter, recorded) = makeAdapter(home: home)

        let windows = try await adapter.fetchUsage(for: account)

        #expect(recorded().count == 1)
        #expect(recorded()[0].path.hasSuffix("/auth.json"))
        #expect(StubURLProtocol.router.requests(id: testID)[0].url?.absoluteString == "https://chatgpt.com/backend-api/codex/usage")
        #expect(windows.map(\.kind) == [.fiveHour])
        #expect(windows[0].usedPercent == 33.5)
    }

    @Test("codexHomeOverride takes precedence over the default home when reading auth.json")
    func codexHomeOverrideHonored() async throws {
        let overrideHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-override-\(UUID().uuidString)", isDirectory: true).path
        let ignoredHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-ignored-\(UUID().uuidString)", isDirectory: true).path
        defer {
            try? FileManager.default.removeItem(atPath: overrideHome)
            try? FileManager.default.removeItem(atPath: ignoredHome)
        }
        try makeAuthFile(home: overrideHome)
        try makeAuthFile(home: ignoredHome)
        installChatGPTSuccess()
        let overriddenAccount = Account(
            id: UUID(),
            provider: .codex,
            label: "Codex",
            displayedWindow: .fiveHour,
            codexHomeOverride: overrideHome
        )
        let (adapter, recorded) = makeAdapter(home: ignoredHome)

        _ = try await adapter.fetchUsage(for: overriddenAccount)

        let readPaths = recorded().map(\.path)
        #expect(readPaths.count == 1)
        #expect(readPaths[0].hasSuffix("/auth.json"))
        #expect(readPaths[0].contains("codex-override-"))
        #expect(!readPaths[0].contains("codex-ignored-"))
    }

    @Test("Fallback request carries Bearer token from auth.json")
    func fallbackCarriesBearerToken() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-home-\(UUID().uuidString)", isDirectory: true).path
        defer { try? FileManager.default.removeItem(atPath: home) }
        try makeAuthFile(home: home)
        installChatGPTSuccess()
        let (adapter, _) = makeAdapter(home: home)

        _ = try await adapter.fetchUsage(for: account)

        let request = StubURLProtocol.router.requests(id: testID)[0]
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer stub-\(testID)")
        #expect(request.httpMethod == "GET")
    }

    @Test("HTTP 401 on the fallback path maps to unauthorized")
    func fallbackUnauthorized() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-home-\(UUID().uuidString)", isDirectory: true).path
        defer { try? FileManager.default.removeItem(atPath: home) }
        try makeAuthFile(home: home)
        installHandler { _ in .init(status: 401, json: "{}") }
        let (adapter, _) = makeAdapter(home: home)

        await #expect(throws: ProviderError.unauthorized) {
            try await adapter.fetchUsage(for: self.account)
        }
    }

    @Test("Network failure on the fallback path maps to a network error")
    func fallbackNetworkError() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-home-\(UUID().uuidString)", isDirectory: true).path
        defer { try? FileManager.default.removeItem(atPath: home) }
        try makeAuthFile(home: home)
        installHandler { _ in throw URLError(.timedOut) }
        let (adapter, _) = makeAdapter(home: home)

        do {
            _ = try await adapter.fetchUsage(for: account)
            Issue.record("Expected a network error but none was thrown")
        } catch {
            guard case ProviderError.network = error else {
                Issue.record("Expected .network, got \(error)")
                return
            }
        }
    }

    @Test("Bad payload on the fallback path maps to parseFailed")
    func fallbackBadPayload() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-home-\(UUID().uuidString)", isDirectory: true).path
        defer { try? FileManager.default.removeItem(atPath: home) }
        try makeAuthFile(home: home)
        installHandler { _ in .init(status: 200, body: Data("<html>nope</html>".utf8)) }
        let (adapter, _) = makeAdapter(home: home)

        await #expect(throws: ProviderError.parseFailed) {
            try await adapter.fetchUsage(for: self.account)
        }
    }

    @Test("Missing auth.json after transport failure maps to missingCredentials")
    func missingAuthFileAfterTransportFailure() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-missing-\(UUID().uuidString)", isDirectory: true).path
        let (adapter, recorded) = makeAdapter(home: home)

        do {
            _ = try await adapter.fetchUsage(for: account)
            Issue.record("Expected missingCredentials")
        } catch let providerError as ProviderError {
            #expect(providerError == .missingCredentials)
        }
        #expect(recorded().count == 1)
        #expect(recorded()[0].lastPathComponent == "auth.json")
    }

    @Test("Garbage stdout from a live app-server falls back to auth.json")
    func garbageAppServerOutputFallsBack() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-garbage-\(UUID().uuidString)", isDirectory: true).path
        defer { try? FileManager.default.removeItem(atPath: home) }
        try makeAuthFile(home: home)
        installChatGPTSuccess()
        let (adapter, recorded) = makeAdapter(appServer: { "hello from an old cli" }, home: home)

        let windows = try await adapter.fetchUsage(for: account)

        #expect(windows.map(\.usedPercent) == [33.5])
        #expect(recorded().count == 1)
        #expect(recorded()[0].lastPathComponent == "auth.json")
    }

    @Test("locateExecutable resolves a binary that lives only in extra search directories")
    func locateExecutableSearchesKnownPrefixes() throws {
        // Simulate the minimal PATH of a GUI process (no Homebrew directories).
        let originalPATH = ProcessInfo.processInfo.environment["PATH"]
        setenv("PATH", "/usr/bin:/bin:/usr/sbin:/sbin", 1)
        defer { if let originalPATH { setenv("PATH", originalPATH, 1) } }

        let resolved = CodexAppServerClient.locateExecutable("whoami")
        #expect(resolved?.path == "/usr/bin/whoami")
    }

    @Test("locateExecutable returns nil for an unknown binary")
    func locateExecutableReturnsNilWhenMissing() {
        let resolved = CodexAppServerClient.locateExecutable("definitely-not-a-real-cli-\(UUID().uuidString)")
        #expect(resolved == nil)
    }
}
