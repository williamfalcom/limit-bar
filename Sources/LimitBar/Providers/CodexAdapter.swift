import Foundation

struct CodexAdapter: ProviderAdapter, Sendable {
    static let usageURL = URL(string: "https://chatgpt.com/backend-api/codex/usage")!
    static let weeklyThresholdSeconds: TimeInterval = 6 * 86_400

    private let appServerStdout: @Sendable () async throws -> String
    private let environmentHome: @Sendable () -> String?
    private let readFile: @Sendable (URL) throws -> Data
    private let now: @Sendable () -> Date
    private let session: URLSession

    init(
        appServerStdout: @escaping @Sendable () async throws -> String = { try await CodexAppServerClient().fetchRateLimitsStdout() },
        environmentHome: @escaping @Sendable () -> String? = { ProcessInfo.processInfo.environment["CODEX_HOME"] },
        readFile: @escaping @Sendable (URL) throws -> Data = { try Data(contentsOf: $0) },
        now: @escaping @Sendable () -> Date = { Date() },
        session: URLSession = .shared
    ) {
        self.appServerStdout = appServerStdout
        self.environmentHome = environmentHome
        self.readFile = readFile
        self.now = now
        self.session = session
    }

    func fetchUsage(for account: Account) async throws -> [LimitWindow] {
        do {
            let stdout = try await appServerStdout()
            return try Self.parseAppServerOutput(stdout, now: now())
        } catch {
            if case ProviderError.parseFailed = error { throw error }
            return try await fetchViaAuthJSON(account)
        }
    }

    private func fetchViaAuthJSON(_ account: Account) async throws -> [LimitWindow] {
        let token = try authToken(for: account)
        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw ProviderError.network(error)
        }
        guard let http = response as? HTTPURLResponse else { throw ProviderError.parseFailed }
        switch http.statusCode {
        case 200:
            return try Self.parseWindows(from: data, now: now())
        case 401, 403:
            throw ProviderError.unauthorized
        case 429:
            throw ProviderError.rateLimited(retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init))
        default:
            throw ProviderError.network(URLError(.badServerResponse))
        }
    }

    func authFileURL(for account: Account) -> URL {
        let home = account.codexHomeOverride
            ?? environmentHome()
            ?? "~/.codex"
        return URL(fileURLWithPath: Self.expandingTilde(home)).appendingPathComponent("auth.json")
    }

    private func authToken(for account: Account) throws -> String {
        let url = authFileURL(for: account)
        let data: Data
        do {
            data = try readFile(url)
        } catch {
            throw ProviderError.missingCredentials
        }
        guard let token = Self.token(from: data) else { throw ProviderError.missingCredentials }
        return token
    }

    static func expandingTilde(_ path: String) -> String {
        guard path.hasPrefix("~") else { return path }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix("~/") ? home + path.dropFirst() : home
    }

    static func token(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let apiKey = obj["OPENAI_API_KEY"] as? String, !apiKey.isEmpty { return apiKey }
        if let tokens = obj["tokens"] as? [String: Any],
           let accessToken = tokens["access_token"] as? String, !accessToken.isEmpty {
            return accessToken
        }
        return nil
    }

    static func parseAppServerOutput(_ stdout: String, now: Date) throws -> [LimitWindow] {
        for line in stdout.split(separator: "\n") {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let result = obj["result"],
                  let windows = windows(from: result, now: now) else { continue }
            return windows
        }
        throw ProviderError.parseFailed
    }

    static func parseWindows(from data: Data, now: Date) throws -> [LimitWindow] {
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let windows = windows(from: obj, now: now) else {
            throw ProviderError.parseFailed
        }
        return windows
    }

    private static func windows(from payload: Any, now: Date) -> [LimitWindow]? {
        guard let entries = rateLimitEntries(in: payload) else { return nil }
        return entries.compactMap { window(from: $0, now: now) }
    }

    private static func rateLimitEntries(in payload: Any) -> [[String: Any]]? {
        if let direct = payload as? [String: Any], let entries = direct["rate_limits"] as? [[String: Any]] {
            return entries
        }
        if let nested = payload as? [String: Any] {
            for value in nested.values {
                if let found = rateLimitEntries(in: value) { return found }
            }
        }
        return nil
    }

    private static func window(from entry: [String: Any], now: Date) -> LimitWindow? {
        let percent = (entry["used_percent"] as? Double) ?? ((entry["used_percent"] as? Int).map(Double.init))
        guard let percent else { return nil }
        let seconds = (entry["limit_window_seconds"] as? Double)
            ?? ((entry["limit_window_seconds"] as? Int).map(Double.init))
        guard let seconds else { return nil }
        let resetsIn = (entry["resets_in_seconds"] as? Double)
            ?? ((entry["resets_in_seconds"] as? Int).map(Double.init))
        let resetsAt = resetsIn.map { now.addingTimeInterval($0) }
        return LimitWindow(kind: classify(seconds: seconds), usedPercent: percent, usedAbsolute: nil, resetsAt: resetsAt)
    }

    static func classify(seconds: TimeInterval) -> WindowKind {
        seconds >= weeklyThresholdSeconds ? .weekly : .fiveHour
    }
}

struct CodexAppServerClient: Sendable {
    func fetchRateLimitsStdout() async throws -> String {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["codex", "app-server", "--stdio"]
            let stdin = Pipe()
            let stdout = Pipe()
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = Pipe()
            try process.run()
            let request = #"{"jsonrpc":"2.0","id":1,"method":"account/rateLimits/read","params":{}}"# + "\n"
            stdin.fileHandleForWriting.write(Data(request.utf8))
            try stdin.fileHandleForWriting.close()

            var collected = Data()
            while true {
                let chunk = stdout.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                collected.append(chunk)
                if collected.count > 4 * 1_024 * 1_024 { break }
            }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw CocoaError(.fileNoSuchFile)
            }
            return String(decoding: collected, as: UTF8.self)
        }.value
    }
}
