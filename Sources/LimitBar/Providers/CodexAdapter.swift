import Foundation

struct CodexAdapter: ProviderAdapter, Sendable {
    static let usageURL = URL(string: "https://chatgpt.com/backend-api/codex/usage")!
    static let weeklyThresholdSeconds: TimeInterval = 6 * 86_400

    /// Receives the account's tilde-expanded `CODEX_HOME` override, or `nil` to inherit.
    private let appServerStdout: @Sendable (String?) async throws -> String
    private let environmentHome: @Sendable () -> String?
    private let readFile: @Sendable (URL) throws -> Data
    private let now: @Sendable () -> Date
    private let session: URLSession

    init(
        appServerStdout: @escaping @Sendable (String?) async throws -> String = {
            try await CodexAppServerClient().fetchRateLimitsStdout(codexHome: $0)
        },
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
            let stdout = try await appServerStdout(account.codexHomeOverride.map(Self.expandingTilde))
            return try Self.parseAppServerOutput(stdout, now: now())
        } catch {
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
        if let windows = try? parseAppServerEnvelope(stdout) { return windows }
        for line in stdout.split(separator: "\n") {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let result = obj["result"],
                  let windows = windows(from: result, now: now) else { continue }
            return windows
        }
        throw ProviderError.parseFailed
    }

    private static func window(fromEntry entry: [String: Any]) -> LimitWindow? {
        let percent = (entry["usedPercent"] as? Double) ?? ((entry["usedPercent"] as? Int).map(Double.init))
        guard let percent else { return nil }
        let minutes = (entry["windowDurationMins"] as? Double) ?? ((entry["windowDurationMins"] as? Int).map(Double.init))
        let epoch = (entry["resetsAt"] as? Double) ?? ((entry["resetsAt"] as? Int).map(Double.init))
        let kind = minutes.map { classify(seconds: $0 * 60) } ?? .fiveHour
        let resetsAt = epoch.map { Date(timeIntervalSince1970: $0) }
        return LimitWindow(kind: kind, usedPercent: percent, usedAbsolute: nil, resetsAt: resetsAt)
    }

    private static func windowsFromRateLimits(_ rateLimits: [String: Any]) -> [LimitWindow] {
        ["primary", "secondary"].compactMap { key in
            (rateLimits[key] as? [String: Any]).flatMap(window(fromEntry:))
        }
    }

    static func parseAppServerEnvelope(_ stdout: String) throws -> [LimitWindow] {
        for line in stdout.split(separator: "\n") {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  obj["id"] != nil,
                  obj["error"] == nil,
                  let result = obj["result"] as? [String: Any],
                  let rateLimits = result["rateLimits"] as? [String: Any] else { continue }
            let windows = windowsFromRateLimits(rateLimits)
            if !windows.isEmpty { return windows }
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
    static let responseTimeout: TimeInterval = 6
    static let maxOutputBytes = 4 * 1_024 * 1_024
    private static let readResponseMarker = Data(#""id":2"#.utf8)

    /// Fixed executable and arguments; `nil` resolves the installed `codex` CLI.
    private let launch: (executable: URL, arguments: [String])?
    let timeout: TimeInterval

    init(launch: (executable: URL, arguments: [String])? = nil, timeout: TimeInterval = Self.responseTimeout) {
        self.launch = launch
        self.timeout = timeout
    }

    func fetchRateLimitsStdout(codexHome: String?) async throws -> String {
        let (executable, arguments) = launch ?? Self.resolveLaunch()
        let initialize = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"limit-bar","title":"limit-bar","version":"1.0.0"}}}"# + "\n"
        let read = #"{"jsonrpc":"2.0","id":2,"method":"account/rateLimits/read","params":{}}"# + "\n"

        let result = try await CLIProcessRunner.run(
            executableURL: executable,
            arguments: arguments,
            environment: Self.environment(codexHome: codexHome, base: ProcessInfo.processInfo.environment),
            input: Data((initialize + read).utf8),
            timeout: timeout,
            isComplete: { collected in
                collected.count > Self.maxOutputBytes || collected.range(of: Self.readResponseMarker) != nil
            }
        )
        guard !result.output.isEmpty else {
            throw CocoaError(.fileNoSuchFile)
        }
        return String(decoding: result.output, as: UTF8.self)
    }

    /// Child environment for one account: `nil` inherits limit-bar's environment unchanged.
    static func environment(codexHome: String?, base: [String: String]) -> [String: String]? {
        guard let codexHome else { return nil }
        var environment = base
        environment["CODEX_HOME"] = codexHome
        return environment
    }

    private static func resolveLaunch() -> (URL, [String]) {
        // GUI apps launched from Finder/Dock get a minimal PATH
        // (/usr/bin:/bin:/usr/sbin:/sbin), so "/usr/bin/env codex" fails when
        // the CLI is installed via Homebrew/npm. Resolve the absolute path,
        // falling back to a login shell that sources the user's profile.
        if let codex = locateExecutable("codex") {
            return (codex, ["app-server", "--stdio"])
        }
        return (URL(fileURLWithPath: "/bin/zsh"), ["-l", "-c", "exec codex app-server --stdio"])
    }

    /// Directories that are searched in addition to `$PATH`. GUI processes do not
    /// inherit the shell profile, so Homebrew (Apple Silicon/Intel) and common
    /// user-local install prefixes must be probed explicitly.
    static let extraSearchDirectories: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "~/.local/bin",
        "~/bin",
        "~/.npm-global/bin",
        "~/.volta/bin",
        "~/node_modules/.bin",
    ]

    /// Returns the absolute URL of an executable on `$PATH` plus the known
    /// install prefixes, or `nil` when it cannot be found deterministically.
    static func locateExecutable(_ name: String) -> URL? {
        var directories = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        for extra in extraSearchDirectories {
            let expanded = NSString(string: extra).expandingTildeInPath
            if !directories.contains(expanded) { directories.append(expanded) }
        }
        for directory in directories {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}
