import Foundation

struct GoAdapter: ProviderAdapter, Sendable {
    // Spike candidate list (design: "OpenCode Go | spike probes candidate endpoints"; upstream issues #10448/#18648).
    // Probed in order; first 200-with-parseable-payload wins; exhaustion degrades to .unsupported.
    static let candidateURLs: [URL] = [
        URL(string: "https://opencode.ai/api/usage")!,
        URL(string: "https://api.opencode.ai/v1/usage")!,
    ]
    static let dollarCaps: [WindowKind: Double] = [.fiveHour: 12, .weekly: 30, .monthly: 60]
    static let periodKeys: [(key: String, kind: WindowKind)] = [
        ("five_hour", .fiveHour),
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
            apiKey = try credentials.secret(forKey: Self.apiKey(for: account))
        } catch {
            throw ProviderError.missingCredentials
        }

        for url in Self.candidateURLs {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            if let windows = try? await probe(request) {
                return windows
            }
        }
        throw ProviderError.unsupported
    }

    private func probe(_ request: URLRequest) async throws -> [LimitWindow]? {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return try Self.parse(data)
    }

    static func parse(_ data: Data) throws -> [LimitWindow] {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.parseFailed
        }
        var windows: [LimitWindow] = []
        for (key, kind) in periodKeys {
            guard let entry = payload[key] as? [String: Any],
                  let used = (entry["used_usd"] as? Double) ?? ((entry["used_usd"] as? Int).map(Double.init)),
                  let cap = dollarCaps[kind], cap > 0 else { continue }
            windows.append(LimitWindow(
                kind: kind,
                usedPercent: used / cap * 100,
                usedAbsolute: String(format: "$%.2f", used),
                resetsAt: nil
            ))
        }
        guard !windows.isEmpty else { throw ProviderError.parseFailed }
        return windows
    }

    static func apiKey(for account: Account) -> String {
        "go.api-key.\(account.id.uuidString)"
    }
}
