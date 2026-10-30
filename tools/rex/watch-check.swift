import Foundation
import VolantCore

/// Drives the agent helper's `RexWatch` with fake `rex` shell scripts in a temporary folder: never a
/// real Rex server. Each scenario checks one supervision rule: inventory lines advance the revision,
/// an unchanged read costs nothing, Rex not running is reported, an oversized line stops the
/// watcher, a watcher that reaches its lifetime restarts, and stop ends the process.
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
let queue = DispatchQueue(label: "rex-watch-check")
var failures = 0

func check(_ condition: Bool, _ message: String) {
    if condition { print("ok: " + message) } else { failures += 1; print("FAIL: " + message) }
}

func inventory(_ state: String) -> String {
    #"{"sessions":[{"session_id":"session:fixture","label":"orbit","panes":[{"block_id":"block:one","label":"shell","records":[{"state":"\#(state)","app":"cargo"}]}]}]}"#
}

/// Writes an executable fake `rex` that ignores its arguments and runs `body`.
func fake(_ name: String, _ body: String) throws -> URL {
    let url = folder.appendingPathComponent(name)
    try ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}

/// One read, waiting for its reply, which the watcher may hold until a change.
func read(_ watch: RexWatch, after known: Int) -> (reply: (Data?, Int, String?), seconds: TimeInterval) {
    let started = Date(), done = DispatchSemaphore(value: 0)
    var reply: (Data?, Int, String?) = (nil, known, nil)
    queue.async { watch.read(after: known) { reply = ($0, $1, $2); done.signal() } }
    done.wait()
    return (reply, Date().timeIntervalSince(started))
}

/// Reads until `condition` holds for the latest reply or the deadline passes.
func poll(_ watch: RexWatch, after known: Int, seconds: TimeInterval = 5,
          until condition: (Data?, Int, String?) -> Bool) -> (Data?, Int, String?) {
    let deadline = Date().addingTimeInterval(seconds)
    var reply: (Data?, Int, String?) = (nil, known, nil)
    var current = known
    while Date() < deadline {
        reply = read(watch, after: current).reply
        if condition(reply.0, reply.1, reply.2) { return reply }
        current = reply.1
    }
    return reply
}

func states(_ data: Data?) -> [String] {
    (data.flatMap { try? JSONDecoder().decode(RexInventory.self, from: $0) }?.panes ?? []).map(\.state.rawValue)
}

func running(_ marker: String) -> Bool {
    let task = Process(), pipe = Pipe()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    task.arguments = ["-f", marker]
    task.standardOutput = pipe
    try? task.run(); task.waitUntilExit()
    return task.terminationStatus == 0
}

let lines = try fake("rex-lines", "echo 'listening: not an inventory'\necho '\(inventory("working"))'\nsleep 0.3\necho '\(inventory("blocked"))'\nexec sleep 30 # rex-lines-marker")
let watch = RexWatch(queue: queue, home: folder.path, executable: { lines })
var reply = poll(watch, after: -1) { data, _, _ in states(data) == ["working"] }
let working = reply.1
let change = read(watch, after: working)
check(states(change.reply.0) == ["blocked"] && change.seconds < 1, "a read at the current revision is answered by the next line, without waiting out the hold")
reply = poll(watch, after: -1) { data, _, _ in states(data) == ["blocked"] }
check(states(reply.0) == ["blocked"], "inventory lines replace each other and a non-inventory line is skipped")
let held = reply.1
let idle = read(watch, after: held)
check(idle.reply.0 == nil && idle.reply.1 == held && idle.reply.2 == nil && idle.seconds >= RexWatch.holdLimit - 0.1,
      "a read at the current revision with no change waits out the hold and carries nothing")
queue.sync { watch.stop() }
Thread.sleep(forTimeInterval: 1.5)
check(!running("rex-lines-marker"), "stop ends the watcher process")

let stopped = try fake("rex-stopped", "exit 4")
let notRunning = RexWatch(queue: queue, home: folder.path, executable: { stopped })
reply = poll(notRunning, after: -1) { _, _, message in message != nil }
check(reply.0 == nil && reply.2 == HostMessage(.rexNotRunning).wire, "exit status 4 reads as Rex not running, sent as a code")
queue.sync { notRunning.stop() }

let huge = try fake("rex-huge", "head -c 4100000 /dev/zero | tr '\\0' x\nexec sleep 30 # rex-huge-marker")
let oversized = RexWatch(queue: queue, home: folder.path, executable: { huge })
reply = poll(oversized, after: -1, seconds: 8) { _, _, message in message != nil }
check(reply.2 == HostMessage(.rexUnreadable).wire, "an oversized line stops the watcher and says so")
queue.sync { oversized.stop() }

let launches = folder.appendingPathComponent("launches")
let lifetime = try fake("rex-lifetime", "echo x >> '\(launches.path)'\necho '\(inventory("done"))'\nsleep 0.2\nexit 0")
let renewing = RexWatch(queue: queue, home: folder.path, executable: { lifetime })
_ = poll(renewing, after: -1, seconds: 8) { _, _, _ in ((try? String(contentsOf: launches, encoding: .utf8)) ?? "").count >= 6 }
reply = read(renewing, after: -1).reply
check(((try? String(contentsOf: launches, encoding: .utf8)) ?? "").count >= 6 && states(reply.0) == ["done"] && reply.2 == nil,
      "a watcher that reaches its lifetime restarts and keeps its panes")
queue.sync { renewing.stop() }

let started = folder.appendingPathComponent("started")
let recorder = try fake("rex-recorder", "last=\"\"\nfor argument in \"$@\"; do last=\"$argument\"; done\nif [ \"$last\" = '{\"preview\":true}' ]; then echo preview >> '\(started.path)'; else echo plain >> '\(started.path)'; fi\necho '\(inventory("idle"))'\nexec sleep 30 # rex-recorder-marker")
let modes = RexWatch(queue: queue, home: folder.path, executable: { recorder })
func startedRuns() -> [String] { ((try? String(contentsOf: started, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init) }
func waitForLaunches(_ count: Int) { let deadline = Date().addingTimeInterval(5); while startedRuns().count < count && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) } }
_ = read(modes, after: -1)
waitForLaunches(1)
check(startedRuns() == ["plain"], "a panes read starts the watcher without previews")
queue.async { modes.read(after: -1, view: .overviewWithPreview) { _, _, _ in } }
waitForLaunches(2)
check(startedRuns() == ["plain", "preview"] && queue.sync { modes.previewing }, "an overview read with previews restarts the watcher reading screens")
queue.async { modes.read(after: -1, view: .overview) { _, _, _ in } }
waitForLaunches(3)
check(startedRuns() == ["plain", "preview", "plain"] && !queue.sync { modes.previewing }, "an overview read without previews stops reading screens at once")
queue.sync { modes.stop() }

if failures > 0 { print("FAIL: \(failures) Rex watcher checks failed"); exit(1) }
print("PASS: Rex watcher supervision")
