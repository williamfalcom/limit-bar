import Foundation

struct GoDeviceAuthorization: Equatable, Sendable {
    var deviceCode: String
    var userCode: String
    var verificationURL: URL
    var expiresAt: Date
    var interval: TimeInterval
}

enum GoOAuthClientError: Error, Equatable, Sendable {
    case invalidResponse
    case untrustedVerificationURL
    case httpStatus(Int)
    case network(URLError)
    case authorizationExpired
    case authorizationDenied
    case invalidGrant
}

struct GoOAuthClient: Sendable {
    typealias Sleeper = @Sendable (TimeInterval) async throws -> Void
    typealias Clock = @Sendable () -> Date

    private struct DeviceCodePayload: Decodable {
        var deviceCode: String
        var userCode: String
        var verificationURIComplete: String
        var expiresIn: TimeInterval
        var interval: TimeInterval

        enum CodingKeys: String, CodingKey {
            case deviceCode = "device_code"
            case userCode = "user_code"
            case verificationURIComplete = "verification_uri_complete"
            case expiresIn = "expires_in"
            case interval
        }
    }

    private struct TokenPayload: Decodable {
        var error: String?
        var accessToken: String?
        var refreshToken: String?
        var expiresIn: TimeInterval?
        var workspaceID: String?

        enum CodingKeys: String, CodingKey {
            case error
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case workspaceID = "org_id"
        }
    }

    private enum PollResult {
        case pending
        case slowDown
        case authorized(GoOAuthCredential)
    }

    static let deviceCodeURL = URL(string: "https://opencode.ai/console/auth/device/code")!
    static let tokenURL = URL(string: "https://opencode.ai/console/auth/device/token")!
    private static let verificationBaseURL = URL(string: "https://opencode.ai/")!

    private let session: URLSession
    private let now: Clock
    private let sleep: Sleeper

    init(
        session: URLSession = .shared,
        now: @escaping Clock = { Date() },
        sleep: @escaping Sleeper = { interval in
            try await Task.sleep(for: .seconds(interval))
        }
    ) {
        self.session = session
        self.now = now
        self.sleep = sleep
    }

    func requestDeviceAuthorization() async throws -> GoDeviceAuthorization {
        var request = URLRequest(url: Self.deviceCodeURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": "limit-bar",
            "supports_org_scope": true,
        ])

        let (data, response) = try await send(request)
        guard response.statusCode == 200,
              let payload = try? JSONDecoder().decode(DeviceCodePayload.self, from: data),
              payload.deviceCode.isEmpty == false,
              payload.userCode.isEmpty == false,
              payload.expiresIn.isFinite,
              payload.expiresIn > 0,
              payload.interval.isFinite,
              payload.interval > 0 else {
            if response.statusCode != 200 {
                throw GoOAuthClientError.httpStatus(response.statusCode)
            }
            throw GoOAuthClientError.invalidResponse
        }
        guard let verificationURL = Self.trustedVerificationURL(payload.verificationURIComplete) else {
            throw GoOAuthClientError.untrustedVerificationURL
        }

        let start = now()
        let expiresAt = start.addingTimeInterval(payload.expiresIn)
        guard expiresAt.timeIntervalSince(start).isFinite else {
            throw GoOAuthClientError.invalidResponse
        }
        return GoDeviceAuthorization(
            deviceCode: payload.deviceCode,
            userCode: payload.userCode,
            verificationURL: verificationURL,
            expiresAt: expiresAt,
            interval: payload.interval
        )
    }

    func pollForAuthorization(_ authorization: GoDeviceAuthorization) async throws -> GoOAuthCredential {
        var interval = authorization.interval

        while true {
            try Task.checkCancellation()
            let remaining = authorization.expiresAt.timeIntervalSince(now())
            guard remaining > 0 else { throw GoOAuthClientError.authorizationExpired }

            try await sleep(min(interval, remaining))
            try Task.checkCancellation()
            guard now() < authorization.expiresAt else {
                throw GoOAuthClientError.authorizationExpired
            }

            var request = URLRequest(url: Self.tokenURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "client_id": "limit-bar",
                "device_code": authorization.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])

            let (data, response) = try await send(request)
            switch try pollResult(data: data, response: response) {
            case .pending:
                continue
            case .slowDown:
                interval += 5
            case .authorized(let credential):
                return credential
            }
        }
    }

    func refresh(_ credential: GoOAuthCredential) async throws -> GoOAuthCredential {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": "limit-bar",
            "grant_type": "refresh_token",
            "refresh_token": credential.refreshToken,
        ])

        let (data, response) = try await send(request)
        if response.statusCode == 401 || response.statusCode == 403 {
            throw GoOAuthClientError.invalidGrant
        }
        let payload = try tokenPayload(data: data, response: response)
        if payload.error == "invalid_grant" {
            throw GoOAuthClientError.invalidGrant
        }
        guard response.statusCode == 200, payload.error == nil else {
            throw GoOAuthClientError.httpStatus(response.statusCode)
        }
        return try makeCredential(from: payload)
    }

    private func pollResult(data: Data, response: HTTPURLResponse) throws -> PollResult {
        let payload = try tokenPayload(data: data, response: response)
        switch payload.error {
        case "authorization_pending":
            return .pending
        case "slow_down":
            return .slowDown
        case "expired_token", "expired_device_code":
            throw GoOAuthClientError.authorizationExpired
        case "access_denied":
            throw GoOAuthClientError.authorizationDenied
        case "invalid_grant":
            throw GoOAuthClientError.invalidGrant
        case .some:
            throw GoOAuthClientError.httpStatus(response.statusCode)
        case nil:
            guard response.statusCode == 200 else {
                throw GoOAuthClientError.httpStatus(response.statusCode)
            }
            return .authorized(try makeCredential(from: payload))
        }
    }

    private func tokenPayload(data: Data, response: HTTPURLResponse) throws -> TokenPayload {
        guard let payload = try? JSONDecoder().decode(TokenPayload.self, from: data) else {
            if response.statusCode != 200 {
                throw GoOAuthClientError.httpStatus(response.statusCode)
            }
            throw GoOAuthClientError.invalidResponse
        }
        return payload
    }

    private func makeCredential(from payload: TokenPayload) throws -> GoOAuthCredential {
        guard let accessToken = payload.accessToken, accessToken.isEmpty == false,
              let refreshToken = payload.refreshToken, refreshToken.isEmpty == false,
              let expiresIn = payload.expiresIn, expiresIn.isFinite, expiresIn > 0 else {
            throw GoOAuthClientError.invalidResponse
        }
        let start = now()
        let expiresAt = start.addingTimeInterval(expiresIn)
        guard expiresAt.timeIntervalSince(start).isFinite else {
            throw GoOAuthClientError.invalidResponse
        }
        return GoOAuthCredential(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            workspaceID: payload.workspaceID
        )
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw GoOAuthClientError.network(error)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw GoOAuthClientError.network(URLError(.badServerResponse))
        }
        guard let http = response as? HTTPURLResponse else {
            throw GoOAuthClientError.invalidResponse
        }
        return (data, http)
    }

    private static func trustedVerificationURL(_ rawValue: String) -> URL? {
        guard let url = URL(string: rawValue, relativeTo: verificationBaseURL)?.absoluteURL,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == "opencode.ai",
              components.user == nil,
              components.password == nil,
              components.port == nil || components.port == 443 else {
            return nil
        }
        return url
    }
}
