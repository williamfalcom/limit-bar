import Testing
import Foundation
@testable import limit_bar

@Suite("GoAdapter", .serialized)
struct GoAdapterTests {

    private let testID = UUID().uuidString
    static let usageFixture = """
    {
      "five_hour": {"used_usd": 5.0},
      "weekly": {"used_usd": 20.0},
      "monthly": {"used_usd": 30.0}
    }
    """

    private func makeGoAccount() -> Account {
        Account(id: UUID(), provider: .openCodeGo, label: "Go", displayedWindow: .monthly, codexHomeOverride: nil)
    }

    private func makeAdapter() -> GoAdapter {
        GoAdapter(credentials: CredentialFake(.token("stub-\(testID)")), session: stubbedSession())
    }

    @Test("Probe sequence tries documented candidates in order until one succeeds")
    func probeSequenceInOrder() async throws {
        StubURLProtocol.router.install(id: testID) { request in
            if request.url?.host == "opencode.ai" {
                return .init(status: 404, body: Data())
            }
            return .init(status: 200, json: Self.usageFixture)
        }
        defer { StubURLProtocol.router.drop(id: testID) }
        let adapter = makeAdapter()

        _ = try await adapter.fetchUsage(for: makeGoAccount())

        let requestedHosts = StubURLProtocol.router.requests(id: testID).compactMap { $0.url?.host }
        #expect(requestedHosts == ["opencode.ai", "api.opencode.ai"])
        #expect(requestedHosts.count == 2)
    }

    @Test("Successful fixture yields 5h/weekly/monthly windows at cap-relative percentages")
    func fixtureYieldsThreeWindowsAgainstCaps() async throws {
        StubURLProtocol.router.install(id: testID) { _ in
            .init(status: 200, json: Self.usageFixture)
        }
        defer { StubURLProtocol.router.drop(id: testID) }
        let adapter = makeAdapter()

        let windows = try await adapter.fetchUsage(for: makeGoAccount())

        #expect(windows.map(\.kind) == [.fiveHour, .weekly, .monthly])
        #expect(abs(windows[0].usedPercent - 41.666_7) < 0.001)
        #expect(abs(windows[1].usedPercent - 66.666_7) < 0.001)
        #expect(windows[2].usedPercent == 50.0)
        #expect(windows[0].usedAbsolute == "$5.00")
    }

    @Test("Requests carry the stored API key as a Bearer header")
    func carriesBearerKey() async throws {
        StubURLProtocol.router.install(id: testID) { _ in
            .init(status: 200, json: Self.usageFixture)
        }
        defer { StubURLProtocol.router.drop(id: testID) }
        let adapter = makeAdapter()
        let goAccount = makeGoAccount()

        _ = try await adapter.fetchUsage(for: goAccount)

        let requests = StubURLProtocol.router.requests(id: testID)
        #expect(requests.count == 1)
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer stub-\(testID)")
    }

    @Test("All candidates failing produces unsupported, not an error state")
    func allCandidatesFailProducesUnsupported() async {
        StubURLProtocol.router.install(id: testID) { _ in
            .init(status: 404, body: Data())
        }
        defer { StubURLProtocol.router.drop(id: testID) }
        let adapter = makeAdapter()

        await #expect(throws: ProviderError.unsupported) {
            try await adapter.fetchUsage(for: self.makeGoAccount())
        }
    }

    @Test("Missing stored API key maps to missingCredentials before any network call")
    func missingAPIKeyThrowsMissingCredentials() async {
        let adapter = GoAdapter(credentials: CredentialFake(.notFound), session: stubbedSession())

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
        StubURLProtocol.router.install(id: "legacy") { _ in
            .init(status: 200, json: #"{"five_hour": {"used_usd": 6}, "weekly": {"used_usd": 15}, "monthly": {"used_usd": 30}}"#)
        }
        defer { StubURLProtocol.router.drop(id: "legacy") }

        let windows = try await adapter.fetchUsage(for: goAccount)

        #expect(windows.count == 3)
        let requests = StubURLProtocol.router.requests(id: "legacy")
        #expect(requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer stub-legacy")
    }

    @Test("Reachable-but-unparseable responses across every candidate also degrade to unsupported")
    func unparseableEverywhereProducesUnsupported() async {
        StubURLProtocol.router.install(id: testID) { _ in
            .init(status: 200, body: Data("<html>under construction</html>".utf8))
        }
        defer { StubURLProtocol.router.drop(id: testID) }
        let adapter = makeAdapter()

        await #expect(throws: ProviderError.unsupported) {
            try await adapter.fetchUsage(for: self.makeGoAccount())
        }
        #expect(StubURLProtocol.router.requests(id: testID).count == 2)
    }
}
