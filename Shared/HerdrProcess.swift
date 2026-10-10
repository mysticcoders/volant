import Foundation
import Darwin
import VolantCore

/// Bounded in-memory output. A stalled SSH child cannot hold the helper's pipe read open forever.
enum HerdrProcess {
    static func run(executable: URL, arguments: [String], home: String, timeout: TimeInterval = 8,
                    directory: String? = nil, environment: [String: String]? = nil) throws -> Data {
        let result = try runStatus(executable: executable, arguments: arguments, home: home, timeout: timeout,
                                   directory: directory, environment: environment)
        guard result.status == 0 else { throw unavailable }
        return result.output
    }

    /// The same bounded run, returning a non-zero exit status instead of throwing, for commands such
    /// as `git config --get-regexp` that exit 1 to mean "nothing matched". Throws on a timeout or
    /// on output past the limit.
    static func runStatus(executable: URL, arguments: [String], home: String, timeout: TimeInterval = 8,
                          directory: String? = nil, environment: [String: String]? = nil) throws -> (status: Int32, output: Data) {
        let task = Process(), output = Pipe(), capture = HerdrOutput()
        task.executableURL = executable
        task.arguments = arguments
        task.currentDirectoryURL = URL(fileURLWithPath: directory ?? home)
        task.environment = environment ?? ChildProcessEnvironment.herdr(home: home, user: NSUserName(),
                                                                         sshAuthSocket: ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"])
        task.standardInput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.standardOutput = output
        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil; capture.finished.signal() }
            else if !capture.append(chunk), task.isRunning { task.terminate() }
        }
        defer {
            output.fileHandleForReading.readabilityHandler = nil
            try? output.fileHandleForReading.close()
        }
        try task.run()
        // The child's process group is signaled too, so what the child started, such as the checkout
        // that `git worktree add` runs, stops with it. Process makes the child a group leader on Linux;
        // where it does not, no group has that ID and the call does nothing.
        let deadline = DispatchWorkItem {
            if task.isRunning { capture.fail(); kill(-task.processIdentifier, SIGTERM); task.terminate() }
        }
        let killDeadline = DispatchWorkItem {
            if task.isRunning { capture.fail(); kill(-task.processIdentifier, SIGKILL); kill(task.processIdentifier, SIGKILL) }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout + 1, execute: killDeadline)
        defer { deadline.cancel(); killDeadline.cancel() }
        task.waitUntilExit()
        guard capture.finished.wait(timeout: .now() + 1) == .success, let data = capture.result() else { throw unavailable }
        return (task.terminationStatus, data)
    }

    private static var unavailable: NSError {
        NSError(domain: "VolantHerdrProcess", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Herdr is unavailable or the connection timed out."])
    }
}

private final class HerdrOutput: @unchecked Sendable {
    let finished = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var data = Data()
    private var failed = false
    func append(_ chunk: Data) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !failed, data.count + chunk.count <= 2_000_000 else { failed = true; return false }
        data.append(chunk); return true
    }
    func fail() { lock.lock(); failed = true; lock.unlock() }
    func result() -> Data? { lock.lock(); defer { lock.unlock() }; return failed ? nil : data }
}
