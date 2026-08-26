import Testing
import Foundation
@testable import limit_bar

@Suite("GoAdapter", .serialized)
struct GoAdapterTests {

    private let testID = UUID().uuidString

    /// Live payload captured from `GET https://opencode.ai/zen/go/v1/usage` on 2026-08-25.
    static let liveUsageFixture = """
    {
      "usage": {
        "rolling": {"status": "ok", "percent": 0, "resetsAt": "2026-08-26T01:59:47.398Z"},
        "weekly": {"status": "ok", "percent": 0, "resetsAt": "2026-08-31T00:00:00.398Z"},
        "monthly": {"status": "ok", "percent": 0, "resetsAt": "2026-08-26T00:51:18.398Z"}
      }
    }
    """

    private func makeGoAccount() -> Account {
        Account(id: UUID(), provider: .openCodeGo, label: "Go", displayedWindow: .monthly, codexHomeOverride: nil)
    }

    private func makeAdapter(mode: CredentialFake.Mode? = nil) -> GoAdapter {
        GoAdapter(credentials: CredentialFake(mode ?? .token("stub-\(testID)")), session: stubbedSession())
    }

    private func installRouter(_ handler: @escaping StubURLProtocol.Router.Handler, id: String? = nil) -> String {
        let id = id ?? testID
        StubURLProtocol.router.install(id: id) { request in
            try handler(request)
        }
        return id
    }

    private func dropRouter(id: String) {
        StubURLProtocol.router.drop(id: id)
    }

    @Test("Single GET to the official endpoint carrying the stored key as Bearer")
    func requestsOfficialEndpointWithBearerKey() async throws {
        let id = installRouter { _ in .init(status: 200, json: Self.liveUsageFixture) }
        defer { dropRouter(id: id) }
        let adapter = makeAdapter()

        _ = try await adapter.fetchUsage(for: makeGoAccount())

        let requests = StubURLProtocol.router.requests(id: id)
        #expect(requests.count == 1)
        #expect(requests[0].url?.absoluteString == "https://opencode.ai/zen/go/v1/usage")
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer stub-\(testID)")
    }

    @Test("Captured live payload maps rolling/weekly/monthly with reset dates and no dollar value")
    func livePayloadMapsAllWindows() throws {
        let windows = try GoAdapter.parse(Data(Self.liveUsageFixture.utf8))

        #expect(windows.map(\.kind) == [.fiveHour, .weekly, .monthly])
        for window in windows {
            #expect(window.usedPercent == 0)
            #expect(window.usedAbsolute == nil)
        }
        let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let expectedRolling = try? fractional.parse("2026-08-26T01:59:47.398Z")
        let expectedWeekly = try? Date("2026-08-31T00:00:00.398Z", strategy: fractional)
        let expectedMonthly = try? Date("2026-08-26T00:51:18.398Z", strategy: fractional)
        #expect(windows[0].resetsAt == expectedRolling)
        #expect(windows[1].resetsAt == expectedWeekly)
        #expect(windows[2].resetsAt == expectedMonthly)    }

    @Test("Percent accepts Int or Double values and clamps into 0...100")
    func percentIsClamped() throws {
        let payload = """
        {"usage": {
            "rolling": {"percent": -5},
            "weekly": {"percent": 42.5},
            "monthly": {"percent": 150}
        }}
        """
        let windows = try GoAdapter.parse(Data(payload.utf8))

        #expect(windows.map(\.kind) == [.fiveHour, .weekly, .monthly])
        #expect(windows[0].usedPercent == 0)
        #expect(windows[1].usedPercent == 42.5)
        #expect(windows[2].usedPercent == 100)
        for window in windows {
            #expect(window.resetsAt == nil)
        }
    }

    @Test("Unparsable reset field yields nil resetsAt without failing the window")
    func unparsableResetYieldsNil() throws {
        let payload = """
        {"usage": {"rolling": {"percent": 10, "resetsAt": "not-a-date"}}}
        """
        let windows = try GoAdapter.parse(Data(payload.utf8))

        #expect(windows.count == 1)
        #expect(windows[0].resetsAt == nil)
    }

    @Test("401 and 403 map to unauthorized")
    func authFailuresMapToUnauthorized() async {
        for status in [401, 403] {
            let id = installRouter { _ in .init(status: status, body: Data()) }
            defer { dropRouter(id: id) }
            let adapter = makeAdapter()

            await #expect(throws: ProviderError.unauthorized) {
                try await adapter.fetchUsage(for: self.makeGoAccount())
            }
            dropRouter(id: id)
        }
    }

    @Test("429 maps to rateLimited honoring Retry-After when present")
    func rateLimitHonorsRetryAfter() async throws {
        let id = installRouter { _ in
            .init(status: 429, body: Data(), headers: ["Retry-After": "120"])
        }
        defer { dropRouter(id: id) }
        let adapter = makeAdapter()

        do {
            _ = try await adapter.fetchUsage(for: makeGoAccount())
            Issue.record("expected rateLimited")
        } catch let error as ProviderError {
            #expect(error == ProviderError.rateLimited(retryAfter: 120))
        }
    }

    @Test("429 without Retry-After maps to rateLimited(nil)")
    func rateLimitWithoutHeaderHasNilRetry() async throws {
        let id = installRouter { _ in .init(status: 429, body: Data()) }
        defer { dropRouter(id: id) }
        let adapter = makeAdapter()

        do {
            _ = try await adapter.fetchUsage(for: makeGoAccount())
            Issue.record("expected rateLimited")
        } catch let error as ProviderError {
            #expect(error == ProviderError.rateLimited(retryAfter: nil))
        }
    }

    @Test("Other non-200 statuses map to network")
    func serverErrorsMapToNetwork() async {
        for status in [404, 500, 503] {
            let id = installRouter { _ in .init(status: status, body: Data()) }
            defer { dropRouter(id: id) }
            let adapter = makeAdapter()

            do {
                _ = try await adapter.fetchUsage(for: self.makeGoAccount())
                Issue.record("expected network error")
            } catch ProviderError.network(let urlError) {
                #expect(urlError.code == .badServerResponse, "status \(status)")
            } catch {
                Issue.record("unexpected \(error)")
            }
            dropRouter(id: id)
        }
    }

    @Test("Transport failure maps to network preserving the underlying URLError")
    func transportErrorMapsToNetwork() async {
        let adapter = makeAdapter()

        do {
            _ = try await adapter.fetchUsage(for: makeGoAccount())
            Issue.record("expected network error")
        } catch ProviderError.network(let urlError) {
            #expect(urlError.code == .unsupportedURL)
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test("Malformed 200 payload maps to parseFailed")
    func malformedPayloadThrowsParseFailed() async {
        let id = installRouter { _ in .init(status: 200, body: Data("<html>under construction</html>".utf8)) }
        defer { dropRouter(id: id) }
        let adapter = makeAdapter()

        await #expect(throws: ProviderError.parseFailed) {
            try await adapter.fetchUsage(for: self.makeGoAccount())
        }
    }

    @Test("200 without any parseable quota window maps to parseFailed")
    func emptyUsageObjectThrowsParseFailed() async {
        let id = installRouter { _ in .init(status: 200, json: #"{"usage": {}}"#) }
        defer { dropRouter(id: id) }
        let adapter = makeAdapter()

        await #expect(throws: ProviderError.parseFailed) {
            try await adapter.fetchUsage(for: self.makeGoAccount())
        }
    }

    @Test("Missing stored API key maps to missingCredentials before any network call")
    func missingAPIKeyThrowsMissingCredentials() async {
        let adapter = makeAdapter(mode: .notFound)

        await #expect(throws: ProviderError.missingCredentials) {
            try await adapter.fetchUsage(for: self.makeGoAccount())
        }
    }

    @Test("Legacy bare-UUID key location is honored as fallback")
    func legacyKeyLocationFallback() async throws {
        let goAccount = makeGoAccount()
        let adapter = GoAdapter(
            credentials: CredentialFake(.keys([goAccount.id.uuidString: "stub-legacy"])),
            session: stubbedSession()
        )
        let id = installRouter({ _ in .init(status: 200, json: Self.liveUsageFixture) }, id: "legacy")
        defer { dropRouter(id: id) }

        let windows = try await adapter.fetchUsage(for: goAccount)

        #expect(windows.count == 3)
        let requests = StubURLProtocol.router.requests(id: id)
        #expect(requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer stub-legacy")
    }
}
