import Foundation

struct ClaudeAdapter: ProviderAdapter, Sendable {
    static let credentialService = "Claude Code-credentials"
    static let credentialKey = "Claude Code-credentials"
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let betaHeaderValue = "oauth-2025-04-20"

    private let credentials: any CredentialStore
    private let session: URLSession

    init(credentials: any CredentialStore, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    func fetchUsage(for account: Account) async throws -> [LimitWindow] {
        let token = try accessToken()
        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.betaHeaderValue, forHTTPHeaderField: "anthropic-beta")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProviderError.parseFailed }
        switch http.statusCode {
        case 200:
            return try Self.parse(data)
        case 401, 403:
            throw ProviderError.unauthorized
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw ProviderError.rateLimited(retryAfter: retryAfter)
        default:
            throw ProviderError.network(URLError(.badServerResponse))
        }
    }

    static func parse(_ data: Data) throws -> [LimitWindow] {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.parseFailed
        }
        var windows: [LimitWindow] = []
        if let fiveHour = window(from: payload["five_hour"], kind: .fiveHour) { windows.append(fiveHour) }
        if let sevenDay = window(from: payload["seven_day"], kind: .weekly) { windows.append(sevenDay) }
        return windows
    }

    private static func window(from payload: Any?, kind: WindowKind) -> LimitWindow? {
        guard let entry = payload as? [String: Any] else { return nil }
        let utilization = (entry["utilization"] as? Double) ?? ((entry["utilization"] as? Int).map(Double.init))
        guard let utilization else { return nil }
        let resetsAt = (entry["resets_at"] as? String).flatMap { Self.parseUTCDate($0) }
        return LimitWindow(kind: kind, usedPercent: utilization, usedAbsolute: nil, resetsAt: resetsAt)
    }

    static func parseUTCDate(_ value: String) -> Date? {
        var fractionLess = value
        if let range = fractionLess.range(of: #"\.\d+"#, options: .regularExpression) {
            fractionLess = fractionLess.replacingCharacters(in: range, with: "")
        }
        return ISO8601DateFormatter().date(from: fractionLess)
    }

    private func accessToken() throws -> String {
        do {
            let raw = try credentials.secret(forKey: Self.credentialKey)
            guard let data = raw.data(using: .utf8),
                  let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let oauth = envelope["claudeAiOauth"] as? [String: Any],
                  let token = oauth["accessToken"] as? String else {
                return raw
            }
            return token
        } catch {
            throw ProviderError.missingCredentials
        }
    }
}
