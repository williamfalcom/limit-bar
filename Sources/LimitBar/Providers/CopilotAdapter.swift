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

    func fetchQuotaResponse() async throws -> String {
        try await Task.detached(priority: .utility) {
            let process = Process()
            guard let executable = Self.locateExecutable("copilot") else {
                throw ProviderError.network(URLError(.cannotFindHost))
            }
            process.executableURL = executable
            process.arguments = Self.commandArguments
            let stdin = Pipe()
            let stdout = Pipe()
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = Pipe()

            do {
                try process.run()
            } catch {
                throw ProviderError.network(error as? URLError ?? URLError(.cannotConnectToHost))
            }
            defer {
                if process.isRunning {
                    process.terminate()
                }
            }

            stdin.fileHandleForWriting.write(Self.requestFrame(method: "connect", id: 1))
            stdin.fileHandleForWriting.write(Self.requestFrame(method: "account.getQuota", id: 2))
            _ = try Self.readMessage(from: stdout.fileHandleForReading)
            let quotaResponse = try Self.readMessage(from: stdout.fileHandleForReading)
            return String(decoding: quotaResponse, as: UTF8.self)
        }.value
    }

    static func requestFrame(method: String, id: Int) -> Data {
        let payload = Data("{\"jsonrpc\":\"2.0\",\"id\":\(id),\"method\":\"\(method)\",\"params\":{}}".utf8)
        return Data("Content-Length: \(payload.count)\r\n\r\n".utf8) + payload
    }

    private static func readMessage(from handle: FileHandle) throws -> Data {
        var buffer = Data()
        let separator = Data("\r\n\r\n".utf8)
        while true {
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                throw ProviderError.network(URLError(.networkConnectionLost))
            }
            buffer.append(chunk)
            guard let headerEnd = buffer.range(of: separator) else { continue }
            let header = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self)
            guard let lengthLine = header.split(separator: "\r\n").first(where: {
                $0.lowercased().hasPrefix("content-length:")
            }),
            let length = Int(lengthLine.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? "") else {
                throw ProviderError.parseFailed
            }
            let bodyStart = headerEnd.upperBound
            guard buffer.count >= bodyStart + length else { continue }
            return Data(buffer[bodyStart..<(bodyStart + length)])
        }
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
