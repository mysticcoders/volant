import Foundation
import VolantCore

/// A fixed Apple executable and typed UUIDs; no shell, input files, or output capture for runs.
final class AppleShortcutsHost {
    private let lock = NSLock()
    private var runningProcess: Process?
    private static let environment = ChildProcessEnvironment.appleTool(home: FileManager.default.homeDirectoryForCurrentUser.path, user: NSUserName())
    static func list() throws -> Data {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["list", "--show-identifiers"]
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: timeout)
        defer { timeout.cancel() }
        var data = Data()
        while true {
            let chunk = pipe.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            guard data.count + chunk.count <= 2_000_000 else { process.terminate(); throw CocoaError(.fileReadTooLarge) }
            data.append(chunk)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.executableRuntimeMismatch) }
        return try JSONEncoder().encode(AppleShortcut.decodeListing(data))
    }

    func run(id: String, reply: @escaping (String?) -> Void) {
        guard let uuid = UUID(uuidString: id) else { reply(HostMessage(.shortcutInvalid).wire); return }
        lock.lock()
        guard runningProcess == nil else { lock.unlock(); reply(HostMessage(.shortcutRunning).wire); return }
        let process = Process()
        runningProcess = process
        lock.unlock()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", uuid.uuidString]
        process.environment = Self.environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [self] task in
            lock.lock(); runningProcess = nil; lock.unlock()
            reply(task.terminationStatus == 0 ? nil : HostMessage(.shortcutFailed).wire)
        }
        do { try process.run() }
        catch { process.terminationHandler = nil; lock.lock(); runningProcess = nil; lock.unlock(); reply(HostMessage(.shortcutsUnavailable).wire) }
        // Retain the process and host until completion; interactive shortcuts may wait for input.
    }
}
