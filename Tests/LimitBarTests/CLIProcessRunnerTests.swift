import Foundation
import Testing
@testable import limit_bar

@Suite("CLIProcessRunner")
struct CLIProcessRunnerTests {

    private let shell = URL(fileURLWithPath: "/bin/sh")

    private func pid(in output: Data) -> pid_t? {
        String(decoding: output, as: UTF8.self)
            .split(separator: "\n")
            .first
            .flatMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// Foundation reaps the child asynchronously, so poll briefly before concluding.
    private func isTerminated(_ pid: pid_t) async -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if kill(pid, 0) != 0 { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    @Test("A silent process times out within the bound and is terminated")
    func silentProcessTimesOut() async throws {
        let started = Date()
        let result = try await CLIProcessRunner.run(
            executableURL: shell,
            arguments: ["-c", "echo $$; exec sleep 30"],
            input: Data(),
            timeout: 0.5,
            isComplete: { _ in false }
        )
        let elapsed = Date().timeIntervalSince(started)

        #expect(result.outcome == .timedOut)
        #expect(elapsed < 0.5 + 2)
        let childPID = try #require(pid(in: result.output))
        #expect(await isTerminated(childPID))
    }

    @Test("A child holding stdout open cannot extend the wait past the timeout")
    func heldOpenStdoutStillTimesOut() async throws {
        let started = Date()
        let result = try await CLIProcessRunner.run(
            executableURL: shell,
            arguments: ["-c", "sleep 8 & echo started"],
            input: Data(),
            timeout: 0.5,
            isComplete: { _ in false }
        )
        let elapsed = Date().timeIntervalSince(started)

        #expect(result.outcome == .timedOut)
        #expect(elapsed < 0.5 + 2)
        #expect(String(decoding: result.output, as: UTF8.self) == "started\n")
    }

    @Test("Meeting the completion condition returns early with the collected output and terminates the process")
    func completionReturnsEarly() async throws {
        let started = Date()
        let result = try await CLIProcessRunner.run(
            executableURL: shell,
            arguments: ["-c", "echo $$; exec cat"],
            input: Data("ping\n".utf8),
            timeout: 10,
            isComplete: { String(decoding: $0, as: UTF8.self).contains("ping\n") }
        )
        let elapsed = Date().timeIntervalSince(started)

        #expect(result.outcome == .completed)
        #expect(elapsed < 2)
        let lines = String(decoding: result.output, as: UTF8.self).split(separator: "\n")
        #expect(lines.last == "ping")
        let childPID = try #require(pid(in: result.output))
        #expect(await isTerminated(childPID))
    }

    @Test("Writing to a process that already exited throws instead of raising SIGPIPE")
    func writingToExitedProcessThrows() async {
        // More input than a pipe buffers, so the write must reach the closed read end.
        let input = Data(repeating: 0x41, count: 1_000_000)
        await #expect(throws: (any Error).self) {
            _ = try await CLIProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/true"),
                arguments: [],
                input: input,
                timeout: 5,
                isComplete: { _ in false }
            )
        }
    }
}
