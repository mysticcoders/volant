import AppKit
import Darwin

/// `--memory-check`: drives a running app through fixed phases (idle after launch, launcher shown,
/// a scripted set of queries, Settings open, everything closed, then the same after a diagnostic
/// `malloc_zone_pressure_relief`, which separates freed memory the allocator still holds from
/// memory the app retains) for memory profiling in a
/// disposable VM with fictional data. At each phase it prints its own physical footprint, resident
/// size and live heap, writes `<phase>.ready` into `memory-check` under its temporary directory
/// and waits up to two minutes for `<phase>.go`, so an outside sampler can inspect the process
/// in that state. It reads no clipboard, note or contact contents and prints no query results.
final class MemoryCheck {
    struct Steps {
        let showLauncher: () -> Void
        let setQuery: (String) -> Void
        let hideLauncher: () -> Void
        let showSettings: () -> Void
        let closeSettings: () -> Void
    }

    static let queries = [
        "s", "sa", "saf", "safari", "te", "terminal", "no", "notes", "sys", "system settings", "cal", "calendar",
        "2 + 2", "2^10 / 3", "18% tip on $65", "5 km in mi", "72f to c", "1 cup flour in grams", "#3a7bd5",
        "rebeccapurple in hex", "3pm lisbon in tokyo", "time in tokyo", "days until christmas", "workdays until Dec 25",
        "0x1F + 0b1010", "2026 in roman", "9am to 5:30pm", ":", ":heart", ":smile", ":cat", "clip", "clip fictional",
        "note ", "note fictional", "emoji", "music", "photos", "preview", "mail", "maps", "messages", "facetime",
        "app store", "activity monitor", "disk utility", "font book", "keychain", "text edit", "weather", "safari"
    ]

    private let steps: Steps
    private let directory: URL

    init(steps: Steps) {
        self.steps = steps
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("memory-check", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Runs every phase in order on the main queue, then terminates the app. A launcher shown at
    /// launch is hidden first, so the launch phase is the app at rest.
    func run() {
        after(1) { self.steps.hideLauncher() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [self] in
            phase("launch") {
                self.steps.showLauncher()
                self.after(2) {
                    self.phase("summon") { self.type(Self.queries[...]) }
                }
            }
        }
    }

    /// Enters each query in turn, leaving time for asynchronous results to arrive.
    private func type(_ remaining: ArraySlice<String>) {
        guard let query = remaining.first else {
            after(2) {
                self.phase("typed") {
                    self.steps.setQuery("")
                    self.steps.hideLauncher()
                    self.steps.showSettings()
                    self.after(3) {
                        self.phase("settings") {
                            self.steps.closeSettings()
                            self.after(8) {
                                self.phase("closed") {
                                    malloc_zone_pressure_relief(nil, 0)
                                    self.phase("relieved") { NSApp.terminate(nil) }
                                }
                            }
                        }
                    }
                }
            }
            return
        }
        steps.setQuery(query)
        after(0.6) { self.type(remaining.dropFirst()) }
    }

    /// Prints the counters for a phase, signals the sampler and continues once it is done.
    private func phase(_ name: String, then next: @escaping () -> Void) {
        let counters = Self.counters()
        print(String(format: "memory-check %@ footprint %.1f MB rss %.1f MB live %.1f MB", name, counters.footprint, counters.resident, counters.live))
        fflush(stdout)
        FileManager.default.createFile(atPath: directory.appendingPathComponent("\(name).ready").path, contents: Data())
        let go = directory.appendingPathComponent("\(name).go").path
        let deadline = Date().addingTimeInterval(120)
        func wait() {
            if FileManager.default.fileExists(atPath: go) || Date() > deadline { next(); return }
            after(0.5, wait)
        }
        wait()
    }

    private func after(_ seconds: TimeInterval, _ body: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: body)
    }

    /// Physical footprint and resident size from `TASK_VM_INFO`, and live malloc bytes across all
    /// zones, in megabytes. These are different measures and do not add up.
    static func counters() -> (footprint: Double, resident: Double, live: Double) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        _ = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        var stats = malloc_statistics_t()
        malloc_zone_statistics(nil, &stats)
        return (Double(info.phys_footprint) / 1_048_576, Double(info.resident_size) / 1_048_576, Double(stats.size_in_use) / 1_048_576)
    }
}
