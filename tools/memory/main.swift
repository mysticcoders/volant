// Opt-in profiling fixture: real production models, fictional data, no normal app startup.
import AppKit
import CryptoKit
import Darwin
import Synchronization
import VolantCore

startProfile()
let root = FileManager.default.temporaryDirectory.appendingPathComponent("volant-memory-" + UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
/// Complete notes search: the immediate matches, then the background file scan, waited for on the main run loop.
func searchAll(_ store: NotesStore, _ term: String) -> [Note] {
    var result: [Note]?
    guard store.searchFiles(term, limit: Int.max, completion: { result = $0 }) != nil else { return store.search(term, limit: Int.max) }
    while result == nil { _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
    return result!
}
func clipboard(_ name: String = "clips") -> ClipboardStore {
    ClipboardStore(retention: 100, storageURL: root.appendingPathComponent(name + ".sqlite"), encryptionKey: SymmetricKey(size: .bits256))
}
func imageData(side: Int, seed: UInt64, noisy: Bool) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: side * 4, bitsPerPixel: 32)!
    var state = seed + 1
    for offset in stride(from: 0, to: side * side * 4, by: 4) {
        state = state &* 6364136223846793005 &+ 1
        for channel in 0..<3 { rep.bitmapData![offset + channel] = noisy ? UInt8(truncatingIfNeeded: state >> (channel * 8 + 24)) : UInt8(truncatingIfNeeded: seed * 17) }
        rep.bitmapData![offset + 3] = 255
    }
    let data = rep.representation(using: .png, properties: [:])!
    precondition(data.count <= 8_000_000)
    return data
}
phase("baseline") {}
autoreleasepool {
switch scenario {
case "idle", "emoji":
    var model: LauncherModel?
    phase("model_loaded") {
        model = LauncherModel(index: AppIndex(entries: []), clipboard: clipboard(), notes: NotesStore(directory: root.appendingPathComponent("notes")), config: Preferences(), usage: UsageStore(url: root.appendingPathComponent("usage.sqlite"))) { _ in }
        model!.searchesSecondarySources = false
        model!.reset()
    }
    if scenario == "emoji" {
        precondition(EmojiIndex.all.count > 1000, "Bundled catalog required")
        for batch in 1...4 {
            phase("cycles_\(batch * 25)", units: 25) {
                for _ in 0..<25 {
                    autoreleasepool {
                        for query in [":", ":cat", ":heart", ":missing-fixture", ":"] {
                            model!.query = query
                            for _ in 0..<20 { model!.moveEmojiSelection(1) }
                        }
                        model!.reset()
                    }
                }
            }
        }
    } else { phase("idle_3s") { Thread.sleep(forTimeInterval: 3) } }
    model = nil; settle("released")
case "clipboard", "image-decode":
    var store: ClipboardStore? = clipboard()
    let count = scenario == "clipboard" ? 12 : 3
    phase("seed_images", units: count) {
        for index in 0..<count {
            autoreleasepool {
                store!.recordImage(imageData(side: scenario == "clipboard" ? 1400 : 4096, seed: UInt64(index), noisy: scenario == "clipboard"))
                _ = store!.recent(limit: 1) // Drain async writes without accumulating queued payloads.
            }
        }
        store!.record("fictional searchable text")
        _ = store!.recent(limit: 1)
    }
    settle("seed_settled")
    var rows: [ClipEntry] = []
    phase("rows_loaded", units: count) { rows = store!.recent(limit: 12) }
    if scenario == "image-decode" {
        var decoded: [CGImage] = []
        phase("decoded_full_size", units: count) {
            for row in rows {
                guard let data = row.imageData, let image = NSImage(data: data), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
                let context = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
                decoded.append(context.makeImage()!)
            }
        }
        withExtendedLifetime(decoded) { settle("decoded_retained") }
        decoded = []
    }
    rows = []; settle("rows_released")
    for batch in 1...3 {
        phase("text_queries_\(batch * 10)", units: 10) {
            for _ in 0..<10 { autoreleasepool { precondition(store!.recent(limit: 12, matching: "searchable").count == 1) } }
        }
    }
    store = nil; settle("released")
case "notes", "notes-small":
    let count = scenario == "notes" ? 1000 : 300
    phase("seed_notebook", units: count) {
        let body = String(repeating: "Fictional profiling text for note search.\n", count: scenario == "notes" ? 1600 : 100)
        for index in 0..<count { try! ("# Fixture \(index)\n" + body).write(to: root.appendingPathComponent("\(index).md"), atomically: false, encoding: .utf8) }
    }
    var store: NotesStore?
    phase("notebook_loaded", units: count) { store = NotesStore(directory: root); precondition(store!.notes.count == count) }
    for batch in 1...3 {
        phase("reload_\(batch)", units: count) { store!.reload(); precondition(store!.search("profiling").count == 8) }
    }
    let typed = "absent fixture phrase"
    phase("main_thread_keystrokes_10", units: 10) {
        for length in 12...21 { autoreleasepool { precondition(store!.search(String(typed.prefix(length))).isEmpty) } }
    }
    phase("search_absent_3", units: count) {
        for _ in 0..<3 { autoreleasepool { precondition(searchAll(store!, "absent fixture phrase").isEmpty) } }
    }
    store = nil; settle("released")
case "acp":
    var state = ACPState()
    phase("transcript_loaded", units: 1800) {
        state.messages = (0..<1800).map { ACPMessage(role: "assistant", text: "Fixture \($0): " + String(repeating: "x", count: 480)) }
    }
    var latest: ACPState?
    for batch in 1...4 {
        phase("snapshots_\(batch * 100)", units: 100) {
            for _ in 0..<100 { autoreleasepool {
                let data = try! JSONEncoder().encode(state)
                let next = try! JSONDecoder().decode(ACPState.self, from: data)
                if latest != next { latest = next }
            } }
        }
    }
    latest = nil; state.messages = []; settle("released")
case "acp-poll-small", "acp-poll-200k", "acp-poll-1m":
    let turns = ["acp-poll-small": 3, "acp-poll-200k": 40, "acp-poll-1m": 190][scenario]!
    var poll: ACPPollFixture! = ACPPollFixture()
    phase("transcript_built", units: turns) { poll.build(turns: turns) }
    phase("first_read") { poll.round(legacy: true) }
    uncounted { FileHandle.standardError.write(Data("\(scenario): \(poll.describe())\n".utf8)) }
    let full = uncounted { try! JSONEncoder().encode(poll.acp.queue.sync { poll.acp.state }) }
    phase("helper_encode_40", units: 40) {
        for _ in 0..<40 { autoreleasepool { _ = poll.acp.queue.sync { try! JSONEncoder().encode(poll.acp.state) } } }
    }
    phase("app_decode_40", units: 40) {
        for _ in 0..<40 { autoreleasepool { precondition(poll.model.receive(full, revision: -1, after: -1) == .applied) } }
    }
    phase("full_idle_40", units: 40) { for _ in 0..<40 { poll.round(legacy: true) } }
    poll.startTurn()
    phase("full_streaming_40", units: 40) { for _ in 0..<40 { poll.stream(); poll.round(legacy: true) } }
    poll.endTurn()
    uncounted { poll.round(legacy: false) }
    phase("revision_idle_40", units: 40) { for _ in 0..<40 { poll.round(legacy: false) } }
    precondition(poll.unchanged == 40, "idle revision polls skip the snapshot")
    poll.startTurn()
    phase("revision_streaming_40", units: 40) { for _ in 0..<40 { poll.stream(); poll.round(legacy: false) } }
    poll.endTurn()
    uncounted { poll.round(legacy: false) }
    precondition(poll.model.state == poll.acp.queue.sync { poll.acp.state }, "app state matches helper")
    poll.close(); poll = nil; settle("released")
default: fatalError("Unknown scenario")
}

}
finishProfile()
