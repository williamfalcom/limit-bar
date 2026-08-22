import Testing
import Foundation
@testable import limit_bar

@Suite("ClaudeAdapter", .serialized)
struct ClaudeAdapterTests {

    private let testID = UUID().uuidString

    private func makeAdapter(
        readCredential: (@Sendable () async throws -> String)? = nil
    ) -> ClaudeAdapter {
        let credentialImpl: @Sendable () async throws -> String
        if let readCredential {
            credentialImpl = readCredential
        } else {
            let stubToken = "stub-\(testID)"
            credentialImpl = {
                #"{"claudeAiOauth":{"accessToken":"\#(stubToken)","refreshToken":"stub-refresh","expiresAt":9999999999,"scopes":["user:inference"]}}"#
            }
        }
        return ClaudeAdapter(readCredential: credentialImpl, session: stubbedSession())
    }

    private func installDefaultHandler() {
        StubURLProtocol.router.install(id: testID) { _ in
            StubURLProtocol.Response(status: 200, json: Self.usageFixture)
        }
    }

    private func install(_ handler: @escaping @Sendable (URLRequest) -> StubURLProtocol.Response) {
        StubURLProtocol.router.install(id: testID, handler: handler)
    }

    private static let usageFixture = """
    {
      "five_hour": {"utilization": 42.5, "resets_at": "2026-08-21T18:00:00Z"},
      "seven_day": {"utilization": 12.25, "resets_at": "2026-08-27T00:00:00Z"},
      "seven_day_opus": null,
      "seven_day_fable": {"utilization": 16.0, "resets_at": "2026-08-27T07:59:00Z"},
      "iguana_necktie": null,
      "extra_usage": {"is_enabled": false, "monthly_limit": null}
    }
    """

    private var account: Account {
        Account(id: UUID(), provider: .claudeCode, label: "Claude", displayedWindow: .fiveHour, codexHomeOverride: nil)
    }

    /// Captured verbatim from the live endpoint (2026-08-21), trimmed of spend/extra_usage noise.
    private static let normalizedLimitsFixture = """
    {
      "five_hour": {"utilization": 0.0, "resets_at": "2026-08-22T04:19:59.565296+00:00"},
      "seven_day": {"utilization": 8.0, "resets_at": "2026-08-28T10:59:59.565321+00:00"},
      "seven_day_oauth_apps": null,
      "seven_day_opus": null,
      "limits": [
        {"kind": "session", "group": "session", "percent": 0, "severity": "normal", "resets_at": "2026-08-22T04:19:59.565296+00:00", "scope": null, "is_active": false},
        {"kind": "weekly_all", "group": "weekly", "percent": 8, "severity": "normal", "resets_at": "2026-08-28T10:59:59.565321+00:00", "scope": null, "is_active": false},
        {"kind": "weekly_scoped", "group": "weekly", "percent": 16, "severity": "normal", "resets_at": "2026-08-28T10:59:59.565537+00:00", "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null}, "is_active": true}
      ]
    }
    """

    @Test("Normalized limits array maps session, weekly_all, and scoped model windows")
    func parsesNormalizedLimitsArray() throws {
        let windows = try ClaudeAdapter.parse(Data(Self.normalizedLimitsFixture.utf8))

        let expectedScopedReset = ISO8601DateFormatter().date(from: "2026-08-28T10:59:59+00:00")
        #expect(windows.map(\.kind) == [.fiveHour, .weekly, .weeklyModel("Fable")])
        #expect(windows.map(\.usedPercent) == [0, 8, 16])
        #expect(windows[2].resetsAt == expectedScopedReset)
    }

    @Test("Fixture maps to 5h, weekly, and per-model windows in stable order")
    func parsesWindows() async throws {
        let adapter = makeAdapter()
        installDefaultHandler()

        let windows = try await adapter.fetchUsage(for: account)

        let expectedFiveHourReset = ISO8601DateFormatter().date(from: "2026-08-21T18:00:00Z")
        let expectedWeeklyReset = ISO8601DateFormatter().date(from: "2026-08-27T00:00:00Z")
        let expectedFableReset = ISO8601DateFormatter().date(from: "2026-08-27T07:59:00Z")
        #expect(windows.map(\.kind) == [.fiveHour, .weekly, .weeklyModel("Fable")])
        #expect(windows.map(\.usedPercent) == [42.5, 12.25, 16.0])
        #expect(windows[0].resetsAt == expectedFiveHourReset)
        #expect(windows[1].resetsAt == expectedWeeklyReset)
        #expect(windows[2].resetsAt == expectedFableReset)
    }

    @Test("Request carries GET to the usage endpoint with Bearer token, beta header, and claude-code user agent")
    func requestHeadersAndEndpoint() async throws {
        let adapter = makeAdapter()
        installDefaultHandler()

        _ = try await adapter.fetchUsage(for: account)

        let requests = StubURLProtocol.router.requests(id: testID)
        #expect(requests.count == 1)
        #expect(requests[0].value(forHTTPHeaderField: "User-Agent") == ClaudeAdapter.userAgentHeaderValue)
        let request = requests[0]
        #expect(request.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer stub-\(testID)")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
    }

    @Test("HTTP 401 maps to unauthorized")
    func unauthorizedMapping() async throws {
        let adapter = makeAdapter()
        install { _ in .init(status: 401, json: "{}") }

        await #expect(throws: ProviderError.unauthorized) {
            try await adapter.fetchUsage(for: self.account)
        }
    }

    @Test("HTTP 429 with Retry-After maps to rateLimited carrying the interval")
    func rateLimitedWithRetryAfter() async throws {
        let adapter = makeAdapter()
        install { _ in .init(status: 429, json: "{}", headers: ["Retry-After": "120"]) }

        await #expect(throws: ProviderError.rateLimited(retryAfter: 120)) {
            try await adapter.fetchUsage(for: self.account)
        }
    }

    @Test("HTTP 429 without Retry-After yields nil retry interval")
    func rateLimitedWithoutRetryAfter() async throws {
        let adapter = makeAdapter()
        install { _ in .init(status: 429, json: "{}") }

        await #expect(throws: ProviderError.rateLimited(retryAfter: nil)) {
            try await adapter.fetchUsage(for: self.account)
        }
    }

    @Test("Malformed success body maps to parseFailed")
    func malformedBodyThrowsParseFailed() async throws {
        let adapter = makeAdapter()
        install { _ in .init(status: 200, body: Data("not-json{{".utf8)) }

        await #expect(throws: ProviderError.parseFailed) {
            try await adapter.fetchUsage(for: self.account)
        }
    }

    @Test("Security CLI failure (missing item or denied access) maps to missingCredentials")
    func securityCLIFailureMapsToMissingCredentials() async {
        let adapter = makeAdapter(readCredential: { throw CocoaError(.fileNoSuchFile) })

        await #expect(throws: ProviderError.missingCredentials) {
            try await adapter.fetchUsage(for: self.account)
        }
    }

    @Test("Non-JSON CLI output falls through verbatim to the bearer")
    func bareTokenPassthrough() async throws {
        let routeID = "notjson-\(testID)"
        let adapter = makeAdapter(readCredential: { "stub-\(routeID)" })
        StubURLProtocol.router.install(id: routeID) { _ in
            .init(status: 200, json: Self.usageFixture)
        }

        let windows = try await adapter.fetchUsage(for: account)

        #expect(StubURLProtocol.router.requests(id: routeID).count == 1)
        #expect(windows.count == 3)
    }

    @Test("Null or unknown payload entries are tolerated; present window still parses")
    func nullAndUnknownEntriesTolerated() async throws {
        install { _ in
            .init(status: 200, json: #"{"five_hour": null, "seven_day": {"utilization": 99.5, "extra_field": true}}"#)
        }
        let adapter = makeAdapter()

        let windows = try await adapter.fetchUsage(for: account)

        #expect(windows.count == 1)
        #expect(windows[0].kind == .weekly)
        #expect(windows[0].usedPercent == 99.5)
    }
}
