import Foundation
import Testing
@testable import limit_bar

@Suite("CopilotAdapter")
struct CopilotAdapterTests {

    private let liveStyleResponse = """
    {
      "jsonrpc": "2.0",
      "id": 2,
      "result": {
        "quotaSnapshots": {
          "chat": {"isUnlimitedEntitlement": true, "remainingPercentage": 100},
          "completions": {"isUnlimitedEntitlement": true, "remainingPercentage": 100},
          "premium_interactions": {
            "isUnlimitedEntitlement": false,
            "entitlementRequests": 1500,
            "usedRequests": 263,
            "remainingPercentage": 82.5,
            "resetDate": "2026-08-26T01:38:43.579Z"
          }
        }
      }
    }
    """

    private func makeAdapter(response: String) -> CopilotAdapter {
        CopilotAdapter(appServerStdout: { response })
    }

    @Test("Premium requests maps remaining percentage to consumed monthly usage")
    func premiumRequestsMapsToMonthlyUsage() async throws {
        let windows = try await makeAdapter(response: liveStyleResponse).fetchUsage(for: makeAccount())

        #expect(windows.count == 1)
        #expect(windows[0].kind == .monthly)
        #expect(windows[0].usedPercent == 17.5)
        #expect(windows[0].usedAbsolute == nil)
        let strategy = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let expectedReset = try Date("2026-08-26T01:38:43.579Z", strategy: strategy)
        #expect(windows[0].resetsAt == expectedReset)
    }

    @Test("Unlimited chat and completions are ignored")
    func unlimitedQuotasAreIgnored() throws {
        let response = """
        {"result":{"quotaSnapshots":{
            "chat":{"remainingPercentage":50},
            "completions":{"remainingPercentage":25},
            "premium_interactions":{"remainingPercentage":90}
        }}}
        """

        let windows = try CopilotAdapter.parse(response)

        #expect(windows.map(\.kind) == [.monthly])
        #expect(windows[0].usedPercent == 10)
    }

    @Test("Remaining percentage boundaries clamp consumed usage")
    func remainingPercentageIsClamped() throws {
        let response = """
        {"result":{"quotaSnapshots":{"premium_interactions":{"remainingPercentage":-25}}}}
        """
        let overused = try CopilotAdapter.parse(response)

        let responseAtMost = """
        {"result":{"quotaSnapshots":{"premium_interactions":{"remainingPercentage":125}}}}
        """
        let unused = try CopilotAdapter.parse(responseAtMost)

        #expect(overused[0].usedPercent == 100)
        #expect(unused[0].usedPercent == 0)
    }

    @Test("Missing reset date leaves resetsAt nil")
    func missingResetDateIsNil() throws {
        let response = """
        {"result":{"quotaSnapshots":{"premium_interactions":{"remainingPercentage":60}}}}
        """

        let windows = try CopilotAdapter.parse(response)

        #expect(windows.count == 1)
        #expect(windows[0].resetsAt == nil)
    }

    @Test("Missing premium quota throws parseFailed even when unlimited quotas exist")
    func missingPremiumQuotaThrowsParseFailed() {
        let response = """
        {"result":{"quotaSnapshots":{
            "chat":{"remainingPercentage":100},
            "completions":{"remainingPercentage":100}
        }}}
        """

        #expect(throws: ProviderError.parseFailed) {
            try CopilotAdapter.parse(response)
        }
    }

    @Test("RPC error maps to unauthorized")
    func rpcErrorMapsToUnauthorized() {
        let response = #"{"jsonrpc":"2.0","id":2,"error":{"code":-32000,"message":"Not authenticated"}}"#

        #expect(throws: ProviderError.unauthorized) {
            try CopilotAdapter.parse(response)
        }
    }

    @Test("Malformed RPC response throws parseFailed")
    func malformedResponseThrowsParseFailed() {
        #expect(throws: ProviderError.parseFailed) {
            try CopilotAdapter.parse("not JSON")
        }
    }

    @Test("Transport failure maps to network")
    func transportFailureMapsToNetwork() async {
        struct ProcessFailure: Error {}
        let adapter = CopilotAdapter(appServerStdout: { throw ProcessFailure() })

        do {
            _ = try await adapter.fetchUsage(for: makeAccount())
            Issue.record("expected network error")
        } catch ProviderError.network(let error) {
            #expect(error.code == .cannotConnectToHost)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("CLI command uses headless stdio mode")
    func commandUsesHeadlessStdioMode() {
        #expect(CopilotAppServerClient.commandArguments == ["--headless", "--no-auto-update", "--stdio"])
    }

    @Test("JSON-RPC request frames declare the exact UTF-8 payload length")
    func requestFrameHasExactContentLength() {
        let frame = CopilotAppServerClient.requestFrame(method: "account.getQuota", id: 2)
        let text = String(decoding: frame, as: UTF8.self)
        let parts = text.components(separatedBy: "\r\n\r\n")
        let declaredLength = Int(parts[0].split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "")

        #expect(parts.count == 2)
        #expect(declaredLength == parts[1].utf8.count)
        #expect(parts[1] == "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"account.getQuota\",\"params\":{}}")
    }

    private func frame(_ body: String) -> Data {
        Data("Content-Length: \(body.utf8.count)\r\n\r\n\(body)".utf8)
    }

    @Test("Two complete frames in one buffer yield both bodies in order")
    func framesParsesTwoFramesFromOneBuffer() throws {
        let buffer = frame(#"{"id":1,"result":{}}"#) + frame(#"{"id":2,"result":{"quota":1}}"#)

        let frames = try CopilotAppServerClient.frames(in: buffer)

        #expect(frames.map { String(decoding: $0, as: UTF8.self) } == [
            #"{"id":1,"result":{}}"#,
            #"{"id":2,"result":{"quota":1}}"#,
        ])
    }

    @Test("A trailing partial frame is not returned")
    func framesIgnoresPartialTrailingFrame() throws {
        let second = frame(#"{"id":2,"result":{"quota":1}}"#)
        let buffer = frame(#"{"id":1,"result":{}}"#) + second.prefix(second.count - 3)

        let frames = try CopilotAppServerClient.frames(in: buffer)

        #expect(frames.map { String(decoding: $0, as: UTF8.self) } == [#"{"id":1,"result":{}}"#])
    }

    @Test("Frames split across writes return the second frame body")
    func clientReturnsSecondFrameAcrossSplitWrites() async throws {
        let script = #"printf 'Content-Length: 2\r\n\r\n{}'; sleep 0.2; printf 'Content-Length: 12\r\n'; sleep 0.2; printf '\r\n{"result":1}'; exec sleep 30"#
        let client = CopilotAppServerClient(launch: (URL(fileURLWithPath: "/bin/sh"), ["-c", script]), timeout: 5)

        let response = try await client.fetchQuotaResponse()

        #expect(response == #"{"result":1}"#)
    }

    @Test("A Copilot CLI that sends only one frame times out as a network error")
    func clientTimesOutWithoutSecondFrame() async {
        let script = #"printf 'Content-Length: 2\r\n\r\n{}'; exec sleep 30"#
        let client = CopilotAppServerClient(launch: (URL(fileURLWithPath: "/bin/sh"), ["-c", script]), timeout: 0.3)
        let started = Date()

        await #expect(throws: ProviderError.network(URLError(.timedOut))) {
            _ = try await client.fetchQuotaResponse()
        }
        #expect(Date().timeIntervalSince(started) < 0.3 + 2)
    }

    @Test("The Copilot client waits at most 15 seconds by default")
    func defaultTimeoutIsFifteenSeconds() {
        #expect(CopilotAppServerClient.responseTimeout == 15)
    }

    private func makeAccount() -> Account {
        Account(id: UUID(), provider: .githubCopilot, label: "GitHub Copilot", displayedWindow: .monthly, codexHomeOverride: nil)
    }
}
