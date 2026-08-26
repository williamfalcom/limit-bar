import Foundation

struct GoAdapter: ProviderAdapter, Sendable {
    // Official OpenCode Go quota endpoint (anomalyco/opencode#43983; envelope per cc-switch#6433).
    static let usageURL = URL(string: "https://opencode.ai/zen/go/v1/usage")!
    static let periodKeys: [(key: String, kind: WindowKind)] = [
        ("rolling", .fiveHour),
        ("weekly", .weekly),
        ("monthly", .monthly),
    ]

    private let credentials: any CredentialStore
    private let session: URLSession

    init(credentials: any CredentialStore, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    func fetchUsage(for account: Account) async throws -> [LimitWindow] {
        let apiKey: String
        do {
            apiKey = try Self.readKey(credentials: credentials, account: account)
        } catch {
            throw ProviderError.missingCredentials
        }

        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ProviderError.network(error as? URLError ?? URLError(.badServerResponse))
        }
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.network(URLError(.badServerResponse))
        }
        switch http.statusCode {
        case 200:
            return try Self.parse(data)
        case 401, 403:
            throw ProviderError.unauthorized
        case 429:
            throw ProviderError.rateLimited(
                retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            )
        default:
            throw ProviderError.network(URLError(.badServerResponse))
        }
    }

    static func parse(_ data: Data) throws -> [LimitWindow] {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = payload["usage"] as? [String: Any] else {
            throw ProviderError.parseFailed
        }
        var windows: [LimitWindow] = []
        for (key, kind) in periodKeys {
            guard let entry = usage[key] as? [String: Any],
                  let rawPercent = (entry["percent"] as? Double) ?? ((entry["percent"] as? Int).map(Double.init)) else { continue }
            windows.append(LimitWindow(
                kind: kind,
                usedPercent: min(max(rawPercent, 0), 100),
                usedAbsolute: nil,
                resetsAt: resetDate(in: entry)
            ))
        }
        guard !windows.isEmpty else { throw ProviderError.parseFailed }
        return windows
    }

    private static func resetDate(in entry: [String: Any]) -> Date? {
        guard let raw = entry["resetsAt"] as? String else { return nil }
        let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        if let date = try? Date(raw, strategy: fractional) {
            return date
        }
        return try? Date(raw, strategy: Date.ISO8601FormatStyle())
    }

    static func apiKey(for account: Account) -> String {
        "go.api-key.\(account.id.uuidString)"
    }

    /// Canonical key first; falls back to the pre-fix bare-UUID key written by early Settings builds.
    static func readKey(credentials: any CredentialStore, account: Account) throws -> String {
        if let key = try? credentials.secret(forKey: apiKey(for: account)), !key.isEmpty {
            return key
        }
        return try credentials.secret(forKey: account.id.uuidString)
    }
}
