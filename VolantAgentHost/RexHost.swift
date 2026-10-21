import Foundation
import Security
import VolantCore

/// Runs Rex's two fixed scripts (`RexScript`) against this Mac's Rex server: the long-lived watcher
/// through `RexWatch`, and a one-shot focus. Only a `rex` signed by Superlogical's team runs, so an
/// unrelated tool that happens to be called `rex` is never handed a script. Volant never starts Rex:
/// with no server running, the reply says so.
final class RexHost {
    static let teamIdentifier = "AG92C3PT77"
    let queue = DispatchQueue(label: "com.mysticcoders.volant.rex")
    private let home = FileManager.default.homeDirectoryForCurrentUser.path
    /// Signature checks by resolved path, valid while the file's modification date is unchanged.
    private var verified: [String: Date] = [:]
    private lazy var watcher = RexWatch(queue: queue, home: home, executable: { [unowned self] in try self.executable() })

    enum Failure: LocalizedError {
        case notFound, notRunning, unreadable, changed
        var errorDescription: String? {
            switch self {
            case .notFound: return "Rex was not found. Install Rex, then try again."
            case .notRunning: return "Rex isn’t running. Open Rex, then try again."
            case .unreadable: return "Couldn’t read Rex panes."
            case .changed: return "This pane changed or closed. Refresh before continuing."
            }
        }
    }

    /// Where Rex installs its CLI: inside its server bundle, inside the app, then owner tool folders.
    static func candidates(home: String) -> [String] {
        [home + "/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex",
         "/Applications/Rex Beta.app/Contents/Helpers/Rex Server.rex/Contents/MacOS/rex",
         "/Applications/Rex.app/Contents/Helpers/Rex Server.rex/Contents/MacOS/rex",
         home + "/.local/bin/rex", "/opt/homebrew/bin/rex", "/usr/local/bin/rex"]
    }

    /// The watcher's latest panes, starting it if needed; waits for a change when there is none yet.
    /// Call on `queue`.
    func read(after revision: Int, reply: @escaping (Data?, Int, String?) -> Void) { watcher.read(after: revision, reply: reply) }

    /// Stops the watcher. Call on `queue`.
    func stop() { watcher.stop() }

    /// Focuses the pane if the script still finds it as a terminal in that session, and reports
    /// whether the Rex app switched to it. Call on `queue`.
    func focus(session: String, block: String) throws -> RexScript.FocusOutcome {
        guard let arguments = RexScript.focusArguments(home: home, session: session, block: block) else { throw Failure.changed }
        let executable = try self.executable()
        do {
            return RexScript.FocusOutcome(output: try HerdrProcess.run(executable: executable, arguments: arguments, home: home, timeout: 8,
                                                                        environment: ChildProcessEnvironment.rex(home: home, user: NSUserName())))
        } catch {
            let status = (error as NSError).userInfo[HerdrProcess.terminationStatusKey] as? Int32
            throw status == RexScript.notRunningStatus ? Failure.notRunning : Failure.changed
        }
    }

    /// The first signed `rex`, with symlinks resolved so the checked file is the one that runs.
    private func executable() throws -> URL {
        guard let url = Self.candidates(home: home).lazy
            .map({ URL(fileURLWithPath: $0).resolvingSymlinksInPath() })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) && self.isSignedByRex($0) }) else { throw Failure.notFound }
        return url
    }

    /// Checks the executable's signature against Superlogical's team, once per version of the file.
    private func isSignedByRex(_ url: URL) -> Bool {
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        if let modified, verified[url.path] == modified { return true }
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let text = "anchor apple generic and certificate leaf[subject.OU] = \"\(Self.teamIdentifier)\""
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess else { return false }
        verified[url.path] = modified
        return true
    }
}

/// One long-lived `rex do --all` watcher and the latest panes it printed. Every method and callback
/// runs on `queue`. The watcher starts on the first read, restarts with backoff while reads
/// continue, and stops when told to, when reads stop arriving, or when the helper's connection ends.
/// Each change to the panes or the message advances `revision`. A read at the current revision is
/// held until the next change or `holdLimit`, so a change reaches the app as soon as it is printed
/// and an idle read costs nothing.
final class RexWatch {
    /// The longest line the watcher may print before it is stopped as misbehaving.
    static let maximumLine = 4_000_000
    /// A watcher with no read for this long is stopped rather than restarted.
    static let idleLimit: TimeInterval = 20
    static let maximumBackoff: TimeInterval = 10
    /// How long a read at the current revision waits for a change before answering "unchanged".
    static let holdLimit: TimeInterval = 2
    /// Reads held at once; the app keeps one outstanding, so more means a misbehaving caller.
    static let maximumHeld = 4

    private let queue: DispatchQueue
    private let home: String
    private let executable: () throws -> URL
    private var process: Process?
    private var output: Pipe?
    private var buffer = Data()
    private var generation = 0
    private var restart: DispatchWorkItem?
    private var backoff: TimeInterval = 1
    private var lastRead = Date.distantPast
    private(set) var revision = 0
    private var latest: Data?
    private var problem: String?
    private var held: [(id: UUID, reply: (Data?, Int, String?) -> Void)] = []

    init(queue: DispatchQueue, home: String, executable: @escaping () throws -> URL) {
        self.queue = queue; self.home = home; self.executable = executable
    }

    func read(after known: Int, reply: @escaping (Data?, Int, String?) -> Void) {
        lastRead = Date()
        if process == nil && restart == nil { launch() }
        guard known == revision else { reply(latest, revision, problem); return }
        if held.count >= Self.maximumHeld { let oldest = held.removeFirst(); oldest.reply(nil, revision, nil) }
        let id = UUID()
        held.append((id, reply))
        queue.asyncAfter(deadline: .now() + Self.holdLimit) { [weak self] in
            guard let self, let index = self.held.firstIndex(where: { $0.id == id }) else { return }
            let expired = self.held.remove(at: index)
            self.lastRead = Date()
            expired.reply(nil, self.revision, nil)
        }
    }

    func stop() {
        generation += 1
        restart?.cancel(); restart = nil
        terminate()
        backoff = 1
        publish(nil, problem: nil)
        let waiting = held
        held = []
        for entry in waiting { entry.reply(nil, revision, nil) }
    }

    private func launch() {
        generation += 1
        let current = generation
        let task = Process(), pipe = Pipe()
        do { task.executableURL = try executable() }
        catch {
            publish(nil, problem: (error as? LocalizedError)?.errorDescription ?? RexHost.Failure.notFound.errorDescription)
            scheduleRestart()
            return
        }
        task.arguments = RexScript.watchArguments(home: home)
        task.environment = ChildProcessEnvironment.rex(home: home, user: NSUserName())
        task.currentDirectoryURL = URL(fileURLWithPath: home)
        task.standardInput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.standardOutput = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil; return }
            self?.queue.async { self?.consume(chunk, generation: current) }
        }
        task.terminationHandler = { [weak self] ended in
            let status = ended.terminationStatus
            self?.queue.async { self?.ended(status: status, generation: current) }
        }
        do { try task.run() }
        catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            publish(nil, problem: RexHost.Failure.unreadable.errorDescription)
            scheduleRestart()
            return
        }
        process = task; output = pipe; buffer = Data()
    }

    /// Splits output into lines and keeps the last valid inventory. Lines that are not inventories,
    /// such as a handler's printed error, are skipped.
    private func consume(_ chunk: Data, generation current: Int) {
        guard current == generation else { return }
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard line.first == UInt8(ascii: "{"), let inventory = try? RexInventory.parse(Data(line)),
                  let encoded = try? JSONEncoder().encode(inventory) else { continue }
            backoff = 1
            publish(encoded, problem: nil)
        }
        if buffer.count > Self.maximumLine {
            buffer = Data()
            terminate()
            publish(nil, problem: RexHost.Failure.unreadable.errorDescription)
        }
    }

    /// A watcher that reached its lifetime restarts at once; one that failed restarts with backoff,
    /// and Rex not running is reported as such. Nothing restarts once reads have stopped.
    private func ended(status: Int32, generation current: Int) {
        guard current == generation else { return }
        process = nil
        output?.fileHandleForReading.readabilityHandler = nil
        output = nil
        if status == 0 {
            backoff = 1
        } else {
            publish(nil, problem: (status == RexScript.notRunningStatus ? RexHost.Failure.notRunning : .unreadable).errorDescription)
        }
        scheduleRestart(immediately: status == 0)
    }

    private func scheduleRestart(immediately: Bool = false) {
        guard Date().timeIntervalSince(lastRead) < Self.idleLimit else { stop(); return }
        let delay = immediately ? 0 : backoff
        if !immediately { backoff = min(backoff * 2, Self.maximumBackoff) }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.restart = nil
            if Date().timeIntervalSince(self.lastRead) < Self.idleLimit { self.launch() } else { self.stop() }
        }
        restart = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Ends the process, forcefully if it ignores the polite request.
    private func terminate() {
        output?.fileHandleForReading.readabilityHandler = nil
        output = nil
        guard let task = process else { return }
        process = nil
        if task.isRunning { task.terminate() }
        let pid = task.processIdentifier
        queue.asyncAfter(deadline: .now() + 1) { if task.isRunning { kill(pid, SIGKILL) } }
    }

    /// Records a change and answers every held read with it.
    private func publish(_ data: Data?, problem message: String?) {
        guard data != latest || message != problem else { return }
        latest = data; problem = message
        revision += 1
        let waiting = held
        held = []
        for entry in waiting { entry.reply(latest, revision, problem) }
    }
}
