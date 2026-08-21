import Testing
import Foundation
@testable import limit_bar

@Suite("ClaudeAdapter", .serialized)
struct ClaudeAdapterTests {

    private let testID = UUID().uuidString

    private func makeAdapter() -> ClaudeAdapter {
        ClaudeAdapter(
            credentials: CredentialFake(.token("stub-\(testID)")),
            session: stubbedSession()
        )
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
      "seven_day": {"utilization": 12.25, "resets_at": "2026-08-27T00:00:00Z"}
    }
    """

    private var account: Account {
        Account(id: UUID(), provider: .claudeCode, label: "Claude", displayedWindow: .fiveHour, codexHomeOverride: nil)
    }

    @Test("Fixture maps to two windows with utilization and reset dates")
    func parsesTwoWindows() async throws {
        let adapter = makeAdapter()
        installDefaultHandler()

        let windows = try await adapter.fetchUsage(for: account)

        let expectedFiveHourReset = ISO8601DateFormatter().date(from: "2026-08-21T18:00:00Z")
        let expectedWeeklyReset = ISO8601DateFormatter().date(from: "2026-08-27T00:00:00Z")
        #expect(windows.map(\.kind) == [.fiveHour, .weekly])
        #expect(windows.map(\.usedPercent) == [42.5, 12.25])
        #expect(windows[0].resetsAt == expectedFiveHourReset)
        #expect(windows[1].resetsAt == expectedWeeklyReset)
    }

    @Test("Request carries GET to the usage endpoint with Bearer token and beta header")
    func requestHeadersAndEndpoint() async throws {
        let adapter = makeAdapter()
        installDefaultHandler()

        _ = try await adapter.fetchUsage(for: account)

        let requests = StubURLProtocol.router.requests(id: testID)
        #expect(requests.count == 1)
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

    @Test("Missing keychain item maps to missingCredentials")
    func missingCredentialsMapping() async {
        let adapter = ClaudeAdapter(credentials: CredentialFake(.notFound), session: stubbedSession())

        await #expect(throws: ProviderError.missingCredentials) {
            try await adapter.fetchUsage(for: self.account)
        }
    }

    @Test("Denied keychain access also maps to missingCredentials")
    func deniedCredentialsMapping() async {
        let adapter = ClaudeAdapter(credentials: CredentialFake(.denied), session: stubbedSession())

        await #expect(throws: ProviderError.missingCredentials) {
            try await adapter.fetchUsage(for: self.account)
        }
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
