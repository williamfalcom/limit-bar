import Foundation

struct ClaudeAdapter: ProviderAdapter, Sendable {
    static let credentialService = "Claude Code-credentials"
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let betaHeaderValue = "oauth-2025-04-20"
    static let userAgentHeaderValue = "claude-code/2.1.170"
    static let securityBinary = "/usr/bin/security"

    private let readCredential: @Sendable () async throws -> String
    private let session: URLSession

    init(
        readCredential: @escaping @Sendable () async throws -> String = {
            try await SecurityCLICredentialReader().read(service: Self.credentialService)
        },
        session: URLSession = .shared
    ) {
        self.readCredential = readCredential
        self.session = session
    }

    func fetchUsage(for account: Account) async throws -> [LimitWindow] {
        let token = try await accessToken()
        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.betaHeaderValue, forHTTPHeaderField: "anthropic-beta")
        request.setValue(Self.userAgentHeaderValue, forHTTPHeaderField: "User-Agent")

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
        let modelKeys = payload.keys.filter { $0.hasPrefix("seven_day_") }.sorted()
        for key in modelKeys {
            let model = Self.modelDisplayName(fromKey: key)
            if let modelWindow = window(from: payload[key], kind: .weeklyModel(model)) {
                windows.append(modelWindow)
            }
        }
        return windows
    }

    static func modelDisplayName(fromKey key: String) -> String {
        let suffix = String(key.dropFirst("seven_day_".count))
        guard suffix != "oauth_apps" else { return "OAuth Apps" }
        return suffix
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
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

    private func accessToken() async throws -> String {
        do {
            let raw = try await readCredential()
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

struct SecurityCLICredentialReader: Sendable {
    func read(service: String) async throws -> String {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ClaudeAdapter.securityBinary)
            process.arguments = ["find-generic-password", "-s", service, "-w"]
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardInput = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw CocoaError(.fileNoSuchFile)
            }
            return String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    }
}
