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

/// Reads until `condition` holds for the latest reply or the deadline passes.
func poll(_ watch: RexWatch, after known: Int, seconds: TimeInterval = 5,
          until condition: (Data?, Int, String?) -> Bool) -> (Data?, Int, String?) {
    let deadline = Date().addingTimeInterval(seconds)
    var reply: (Data?, Int, String?) = (nil, known, nil)
    while Date() < deadline {
        reply = queue.sync { watch.read(after: known) }
        if condition(reply.0, reply.1, reply.2) { return reply }
        Thread.sleep(forTimeInterval: 0.05)
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
var reply = poll(watch, after: -1) { data, _, _ in states(data) == ["blocked"] }
check(states(reply.0) == ["blocked"], "inventory lines replace each other and a non-inventory line is skipped")
let held = reply.1
reply = queue.sync { watch.read(after: held) }
check(reply.0 == nil && reply.1 == held && reply.2 == nil, "a read at the current revision carries nothing")
queue.sync { watch.stop() }
Thread.sleep(forTimeInterval: 1.5)
check(!running("rex-lines-marker"), "stop ends the watcher process")

let stopped = try fake("rex-stopped", "exit 4")
let notRunning = RexWatch(queue: queue, home: folder.path, executable: { stopped })
reply = poll(notRunning, after: -1) { _, _, message in message != nil }
check(reply.0 == nil && reply.2 == "Rex isn’t running. Open Rex, then try again.", "exit status 4 reads as Rex not running")
queue.sync { notRunning.stop() }

let huge = try fake("rex-huge", "head -c 4100000 /dev/zero | tr '\\0' x\nexec sleep 30 # rex-huge-marker")
let oversized = RexWatch(queue: queue, home: folder.path, executable: { huge })
reply = poll(oversized, after: -1, seconds: 8) { _, _, message in message != nil }
check(reply.2 == "Couldn’t read Rex panes.", "an oversized line stops the watcher and says so")
queue.sync { oversized.stop() }

let launches = folder.appendingPathComponent("launches")
let lifetime = try fake("rex-lifetime", "echo x >> '\(launches.path)'\necho '\(inventory("done"))'\nsleep 0.2\nexit 0")
let renewing = RexWatch(queue: queue, home: folder.path, executable: { lifetime })
reply = poll(renewing, after: -1) { _, _, _ in ((try? String(contentsOf: launches, encoding: .utf8)) ?? "").count >= 6 }
check(states(reply.0) == ["done"] && reply.2 == nil, "a watcher that reaches its lifetime restarts and keeps its panes")
queue.sync { renewing.stop() }

if failures > 0 { print("FAIL: \(failures) Rex watcher checks failed"); exit(1) }
print("PASS: Rex watcher supervision")
