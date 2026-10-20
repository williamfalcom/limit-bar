import Foundation
import Testing
@testable import limit_bar

private struct OAuthStubResponse: Sendable {
    var status: Int
    var body: Data
    var headers: [String: String] = [:]

    init(status: Int, json: String, headers: [String: String] = [:]) {
        self.status = status
        self.body = Data(json.utf8)
        self.headers = headers
    }
}

private final class OAuthStubRouter: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [OAuthStubResponse] = []
    private var recordedRequests: [URLRequest] = []

    func install(_ responses: [OAuthStubResponse]) {
        lock.lock()
        defer { lock.unlock() }
        self.responses = responses
        recordedRequests = []
    }

    func nextResponse(for request: URLRequest) -> OAuthStubResponse? {
        lock.lock()
        defer { lock.unlock() }
        recordedRequests.append(request)
        guard responses.isEmpty == false else { return nil }
        return responses.removeFirst()
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }
}

private final class OAuthStubURLProtocol: URLProtocol, @unchecked Sendable {
    static let router = OAuthStubRouter()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let response = Self.router.nextResponse(for: request), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        guard let http = HTTPURLResponse(
            url: url,
            statusCode: response.status,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class OAuthTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) {
        self.date = date
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }

    func advance(_ interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        date.addTimeInterval(interval)
    }
}

private final class OAuthSleepLog: @unchecked Sendable {
    private let lock = NSLock()
    private var intervals: [TimeInterval] = []

    func append(_ interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        intervals.append(interval)
    }

    var recordedIntervals: [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return intervals
    }
}

@Suite("GoOAuthClient", .serialized)
struct GoOAuthClientTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeClient(
        clock: OAuthTestClock? = nil,
        sleep: (@Sendable (TimeInterval) async throws -> Void)? = nil
    ) -> GoOAuthClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OAuthStubURLProtocol.self]
        let testClock = clock ?? OAuthTestClock(now)
        return GoOAuthClient(
            session: URLSession(configuration: configuration),
            now: { testClock.now },
            sleep: sleep ?? { interval in
                try await Task.sleep(for: .seconds(interval))
            }
        )
    }

    private func deviceResponse(
        verificationURI: String = "https://opencode.ai/console/device?user_code=ABCD-EFGH",
        expiresIn: Int = 600,
        interval: Int = 5
    ) -> String {
        """
        {"device_code":"device-secret","user_code":"ABCD-EFGH","verification_uri":"\(verificationURI)","expires_in":\(expiresIn),"interval":\(interval)}
        """
    }

    private func makeChallenge(
        expiresAt: Date? = nil,
        interval: TimeInterval = 1
    ) -> GoDeviceAuthorization {
        GoDeviceAuthorization(
            deviceCode: "device-secret",
            userCode: "ABCD-EFGH",
            verificationURL: URL(string: "https://opencode.ai/console/device")!,
            expiresAt: expiresAt ?? now.addingTimeInterval(60),
            interval: interval
        )
    }

    private func requestBody(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else {
            throw GoOAuthClientError.invalidResponse
        }
        stream.open()
        defer { stream.close() }

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4_096)
        defer { buffer.deallocate() }
        var data = Data()
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 4_096)
            if count < 0 { throw stream.streamError ?? GoOAuthClientError.invalidResponse }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    @Test("Device-code request posts required fields and returns a trusted challenge")
    func requestsDeviceCodeAndMapsChallenge() async throws {
        OAuthStubURLProtocol.router.install([
            .init(status: 200, json: deviceResponse()),
        ])
        defer { OAuthStubURLProtocol.router.install([]) }
        let client = makeClient()

        let challenge = try await client.requestDeviceAuthorization()

        #expect(challenge.deviceCode == "device-secret")
        #expect(challenge.userCode == "ABCD-EFGH")
        #expect(challenge.verificationURL.absoluteString == "https://opencode.ai/console/device?user_code=ABCD-EFGH")
        #expect(challenge.expiresAt == now.addingTimeInterval(600))
        #expect(challenge.interval == 5)
        let request = try #require(OAuthStubURLProtocol.router.requests.first)
        #expect(request.url?.absoluteString == "https://opencode.ai/console/auth/device/code")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try requestBody(request)
        let fields = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(fields["client_id"] as? String == "limit-bar")
        #expect(fields["supports_org_scope"] as? Bool == true)
    }

    @Test("Device-code response rejects a verification URI outside the exact HTTPS host")
    func rejectsUntrustedVerificationURI() async {
        defer { OAuthStubURLProtocol.router.install([]) }
        let client = makeClient()

        for uri in [
            "http://opencode.ai/console/device",
            "https://opencode.ai.attacker.invalid/device",
            "https://opencode.ai:444/console/device",
            "https://user@opencode.ai/console/device",
        ] {
            OAuthStubURLProtocol.router.install([
                .init(status: 200, json: deviceResponse(verificationURI: uri)),
            ])
            await #expect(throws: GoOAuthClientError.untrustedVerificationURL) {
                try await client.requestDeviceAuthorization()
            }
        }
    }

    @Test("Pending polls continue and slow_down adds five seconds before approval")
    func handlesPendingSlowDownAndApproval() async throws {
        let clock = OAuthTestClock(now)
        let sleepLog = OAuthSleepLog()
        OAuthStubURLProtocol.router.install([
            .init(status: 400, json: #"{"error":"authorization_pending"}"#),
            .init(status: 400, json: #"{"error":"slow_down"}"#),
            .init(status: 200, json: #"{"access_token":"access-new","refresh_token":"refresh-new","expires_in":3600,"org_id":"workspace-1"}"#),
        ])
        defer { OAuthStubURLProtocol.router.install([]) }
        let client = makeClient(clock: clock) { interval in
            sleepLog.append(interval)
            clock.advance(interval)
        }

        let result = try await client.pollForAuthorization(makeChallenge())

        #expect(result.accessToken == "access-new")
        #expect(result.refreshToken == "refresh-new")
        #expect(result.workspaceID == "workspace-1")
        #expect(result.expiresAt == now.addingTimeInterval(3_608))
        #expect(sleepLog.recordedIntervals == [1, 1, 6])
        let requests = OAuthStubURLProtocol.router.requests
        #expect(requests.count == 3)
        for request in requests {
            #expect(request.url?.absoluteString == "https://opencode.ai/console/auth/device/token")
            #expect(request.httpMethod == "POST")
            let body = try requestBody(request)
            let fields = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(fields["client_id"] as? String == "limit-bar")
            #expect(fields["grant_type"] as? String == "urn:ietf:params:oauth:grant-type:device_code")
            #expect(fields["device_code"] as? String == "device-secret")
        }
    }

    @Test("Polling expires before making a request when less than one interval remains")
    func expiresBeforeNextPoll() async {
        let clock = OAuthTestClock(now)
        let sleepLog = OAuthSleepLog()
        OAuthStubURLProtocol.router.install([])
        defer { OAuthStubURLProtocol.router.install([]) }
        let client = makeClient(clock: clock) { interval in
            sleepLog.append(interval)
            clock.advance(interval)
        }

        await #expect(throws: GoOAuthClientError.authorizationExpired) {
            try await client.pollForAuthorization(
                makeChallenge(expiresAt: now.addingTimeInterval(2), interval: 5)
            )
        }

        #expect(sleepLog.recordedIntervals == [2])
        #expect(OAuthStubURLProtocol.router.requests.isEmpty)
    }

    @Test("Cancelling the polling sleep stops before any token request")
    func cancellationStopsPolling() async {
        OAuthStubURLProtocol.router.install([])
        defer { OAuthStubURLProtocol.router.install([]) }
        let client = makeClient { _ in throw CancellationError() }

        await #expect(throws: CancellationError.self) {
            try await client.pollForAuthorization(makeChallenge())
        }

        #expect(OAuthStubURLProtocol.router.requests.isEmpty)
    }

    @Test("Malformed device-code payload is rejected")
    func rejectsMalformedDeviceCodeResponse() async {
        OAuthStubURLProtocol.router.install([
            .init(status: 200, json: #"{"device_code":"device-only"}"#),
        ])
        defer { OAuthStubURLProtocol.router.install([]) }
        let client = makeClient()

        await #expect(throws: GoOAuthClientError.invalidResponse) {
            try await client.requestDeviceAuthorization()
        }
    }

    @Test("Non-success device-code status is surfaced")
    func rejectsDeviceCodeHTTPFailure() async {
        OAuthStubURLProtocol.router.install([
            .init(status: 503, json: #"{"error":"unavailable"}"#),
        ])
        defer { OAuthStubURLProtocol.router.install([]) }
        let client = makeClient()

        await #expect(throws: GoOAuthClientError.httpStatus(503)) {
            try await client.requestDeviceAuthorization()
        }
    }

    @Test("Refresh exchanges the old token and returns the rotated token pair")
    func refreshesTokenPair() async throws {
        OAuthStubURLProtocol.router.install([
            .init(status: 200, json: #"{"access_token":"access-rotated","refresh_token":"refresh-rotated","expires_in":7200,"org_id":"workspace-2"}"#),
        ])
        defer { OAuthStubURLProtocol.router.install([]) }
        let client = makeClient()
        let prior = GoOAuthCredential(
            accessToken: "old-access",
            refreshToken: "old-refresh",
            expiresAt: now,
            workspaceID: "workspace-1"
        )

        let refreshed = try await client.refresh(prior)

        #expect(refreshed.accessToken == "access-rotated")
        #expect(refreshed.refreshToken == "refresh-rotated")
        #expect(refreshed.expiresAt == now.addingTimeInterval(7200))
        #expect(refreshed.workspaceID == "workspace-2")
        let request = try #require(OAuthStubURLProtocol.router.requests.first)
        #expect(request.url?.absoluteString == "https://opencode.ai/console/auth/device/token")
        #expect(request.httpMethod == "POST")
        let body = try requestBody(request)
        let fields = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(fields["client_id"] as? String == "limit-bar")
        #expect(fields["grant_type"] as? String == "refresh_token")
        #expect(fields["refresh_token"] as? String == "old-refresh")
    }

    @Test("Refresh maps unauthorized responses to invalid grant")
    func refreshUnauthorizedRequiresReauthorization() async {
        defer { OAuthStubURLProtocol.router.install([]) }
        let client = makeClient()
        let prior = GoOAuthCredential(
            accessToken: "old-access",
            refreshToken: "old-refresh",
            expiresAt: now,
            workspaceID: nil
        )

        for status in [401, 403] {
            OAuthStubURLProtocol.router.install([
                .init(status: status, json: #"{"error":"unauthorized"}"#),
            ])
            await #expect(throws: GoOAuthClientError.invalidGrant) {
                try await client.refresh(prior)
            }
        }
    }
}
