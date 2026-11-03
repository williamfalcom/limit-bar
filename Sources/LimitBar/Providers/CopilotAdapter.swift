import Foundation

struct CopilotAdapter: ProviderAdapter, Sendable {
    private let appServerStdout: @Sendable () async throws -> String

    init(
        appServerStdout: @escaping @Sendable () async throws -> String = {
            try await CopilotAppServerClient().fetchQuotaResponse()
        }
    ) {
        self.appServerStdout = appServerStdout
    }

    func fetchUsage(for _: Account) async throws -> [LimitWindow] {
        do {
            return try Self.parse(try await appServerStdout())
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.network(error as? URLError ?? URLError(.cannotConnectToHost))
        }
    }

    static func parse(_ response: String) throws -> [LimitWindow] {
        guard let data = response.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.parseFailed
        }
        if payload["error"] != nil {
            throw ProviderError.unauthorized
        }
        guard let result = payload["result"] as? [String: Any],
              let snapshots = result["quotaSnapshots"] as? [String: Any],
              let premium = snapshots["premium_interactions"] as? [String: Any],
              let remaining = number(from: premium["remainingPercentage"]) else {
            throw ProviderError.parseFailed
        }
        let usedPercent = min(max(100 - remaining, 0), 100)
        return [LimitWindow(
            kind: .monthly,
            usedPercent: usedPercent,
            usedAbsolute: nil,
            resetsAt: resetDate(from: premium["resetDate"])
        )]
    }

    private static func number(from value: Any?) -> Double? {
        (value as? Double) ?? (value as? Int).map(Double.init)
    }

    private static func resetDate(from value: Any?) -> Date? {
        guard let raw = value as? String else { return nil }
        let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        if let date = try? Date(raw, strategy: fractional) {
            return date
        }
        return try? Date(raw, strategy: Date.ISO8601FormatStyle())
    }
}

struct CopilotAppServerClient: Sendable {
    static let commandArguments = ["--headless", "--no-auto-update", "--stdio"]
    static let responseTimeout: TimeInterval = 15

    /// Fixed executable and arguments; `nil` resolves the installed `copilot` CLI.
    private let launch: (executable: URL, arguments: [String])?
    private let timeout: TimeInterval

    init(launch: (executable: URL, arguments: [String])? = nil, timeout: TimeInterval = Self.responseTimeout) {
        self.launch = launch
        self.timeout = timeout
    }

    func fetchQuotaResponse() async throws -> String {
        let executable: URL
        let arguments: [String]
        if let launch {
            (executable, arguments) = launch
        } else {
            guard let located = Self.locateExecutable("copilot") else {
                throw ProviderError.network(URLError(.cannotFindHost))
            }
            (executable, arguments) = (located, Self.commandArguments)
        }

        let result: CLIProcessRunner.Result
        do {
            result = try await CLIProcessRunner.run(
                executableURL: executable,
                arguments: arguments,
                input: Self.requestFrame(method: "connect", id: 1) + Self.requestFrame(method: "account.getQuota", id: 2),
                timeout: timeout,
                isComplete: { ((try? Self.frames(in: $0))?.count ?? 0) >= 2 }
            )
        } catch {
            throw ProviderError.network(error as? URLError ?? URLError(.cannotConnectToHost))
        }

        let frames = try Self.frames(in: result.output)
        guard frames.count >= 2 else {
            throw ProviderError.network(URLError(result.outcome == .timedOut ? .timedOut : .networkConnectionLost))
        }
        return String(decoding: frames[1], as: UTF8.self)
    }

    static func requestFrame(method: String, id: Int) -> Data {
        let payload = Data("{\"jsonrpc\":\"2.0\",\"id\":\(id),\"method\":\"\(method)\",\"params\":{}}".utf8)
        return Data("Content-Length: \(payload.count)\r\n\r\n".utf8) + payload
    }

    /// Bodies of the complete `Content-Length` frames in `buffer`, in order.
    /// A trailing incomplete frame is left out.
    static func frames(in buffer: Data) throws -> [Data] {
        let bytes = Data(buffer)
        let separator = Data("\r\n\r\n".utf8)
        var bodies: [Data] = []
        var offset = bytes.startIndex
        while let headerEnd = bytes.range(of: separator, in: offset..<bytes.endIndex) {
            let header = String(decoding: bytes[offset..<headerEnd.lowerBound], as: UTF8.self)
            guard let lengthLine = header.split(separator: "\r\n").first(where: {
                $0.lowercased().hasPrefix("content-length:")
            }),
            let length = Int(lengthLine.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? "") else {
                throw ProviderError.parseFailed
            }
            let bodyEnd = headerEnd.upperBound + length
            guard bodyEnd <= bytes.endIndex else { break }
            bodies.append(Data(bytes[headerEnd.upperBound..<bodyEnd]))
            offset = bodyEnd
        }
        return bodies
    }

    private static func locateExecutable(_ name: String) -> URL? {
        var directories = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        directories.append(contentsOf: [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            NSString(string: "~/.local/bin").expandingTildeInPath,
            NSString(string: "~/bin").expandingTildeInPath,
            NSString(string: "~/.npm-global/bin").expandingTildeInPath,
            NSString(string: "~/.volta/bin").expandingTildeInPath,
        ])
        for directory in directories {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}
