import Foundation

/// Runs a short-lived CLI exchange with a hard deadline.
///
/// stdout is read through a readability handler, so a process that never writes,
/// or a child that keeps the pipe open, cannot block the caller past `timeout`.
/// The process is terminated when the exchange ends.
enum CLIProcessRunner {
    enum Outcome: Sendable, Equatable {
        /// `isComplete` returned true for the collected output.
        case completed
        /// stdout reached end of file before completion.
        case endOfOutput
        /// The deadline passed before completion or end of file.
        case timedOut
    }

    struct Result: Sendable {
        var output: Data
        var outcome: Outcome
    }

    /// `input` is written before reading starts, so it must stay small (well under the
    /// 64 KiB pipe buffer) to avoid stalling against a child that writes before reading.
    static func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        input: Data,
        timeout: TimeInterval,
        isComplete: @escaping @Sendable (Data) -> Bool
    ) async throws -> Result {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        // An unread stderr pipe can fill up and stall the child.
        process.standardError = FileHandle.nullDevice
        // A write to an exited child must fail with EPIPE, not kill limit-bar with SIGPIPE.
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)

        try process.run()
        let exchange = Exchange(process: process, reader: stdout.fileHandleForReading, isComplete: isComplete)

        do {
            if !input.isEmpty {
                try stdin.fileHandleForWriting.write(contentsOf: input)
            }
        } catch {
            exchange.terminate()
            throw error
        }

        return await withCheckedContinuation { continuation in
            exchange.start(continuation: continuation, timeout: timeout)
        }
    }

    private final class Exchange: @unchecked Sendable {
        private let lock = NSLock()
        private let process: Process
        private let reader: FileHandle
        private let isComplete: @Sendable (Data) -> Bool
        private var collected = Data()
        private var continuation: CheckedContinuation<Result, Never>?
        private var finished = false

        init(process: Process, reader: FileHandle, isComplete: @escaping @Sendable (Data) -> Bool) {
            self.process = process
            self.reader = reader
            self.isComplete = isComplete
        }

        func start(continuation: CheckedContinuation<Result, Never>, timeout: TimeInterval) {
            lock.lock()
            self.continuation = continuation
            lock.unlock()

            reader.readabilityHandler = { [weak self] handle in
                self?.receive(handle.availableData)
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.finish(.timedOut)
            }
        }

        private func receive(_ chunk: Data) {
            lock.lock()
            guard !finished else {
                lock.unlock()
                return
            }
            let outcome: Outcome?
            if chunk.isEmpty {
                outcome = .endOfOutput
            } else {
                collected.append(chunk)
                outcome = isComplete(collected) ? .completed : nil
            }
            lock.unlock()
            if let outcome { finish(outcome) }
        }

        private func finish(_ outcome: Outcome) {
            lock.lock()
            guard !finished else {
                lock.unlock()
                return
            }
            finished = true
            let result = Result(output: collected, outcome: outcome)
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()

            terminate()
            continuation?.resume(returning: result)
        }

        func terminate() {
            reader.readabilityHandler = nil
            if process.isRunning {
                process.terminate()
            }
        }
    }
}
