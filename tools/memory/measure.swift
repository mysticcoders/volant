// Shared counters for the opt-in profiling fixtures: footprint, RSS, sampled peaks, live heap and allocation churn.
import Darwin
import Foundation
import Synchronization

func memory() -> (UInt64, UInt64) {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let status = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    precondition(status == KERN_SUCCESS)
    return (info.phys_footprint, info.resident_size)
}
final class Sampler {
    private let queue = DispatchQueue(label: "volant.memory.sample")
    private var timer: DispatchSourceTimer?
    private var peak: UInt64 = 0
    func start() {
        peak = memory().0
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(5))
        timer.setEventHandler { [weak self] in self?.peak = max(self?.peak ?? 0, memory().0) }
        self.timer = timer; timer.resume()
    }
    func stop() -> UInt64 {
        queue.sync { timer?.cancel(); timer = nil; peak = max(peak, memory().0) }
        return peak
    }
}
let allocatedBytes = Atomic<UInt64>(0)
let allocationCount = Atomic<UInt64>(0)
let countingAllocations = Atomic<Bool>(true)
typealias MallocLogger = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void
/// Counts every allocation and reallocation through libmalloc's logging hook. It must not allocate.
/// Allocation type 2 carries the size in arg2; a reallocation (types 2 and 4) carries it in arg3.
let mallocLogger: MallocLogger = { type, _, size, reallocated, _, _ in
    guard type & 2 != 0, countingAllocations.load(ordering: .relaxed) else { return }
    allocatedBytes.add(UInt64(type & 4 != 0 ? reallocated : size), ordering: .relaxed)
    allocationCount.add(1, ordering: .relaxed)
}
let environment = ProcessInfo.processInfo.environment
/// Installs the counter unless MallocStackLogging is on: it uses the same hook for the stacks
/// malloc_history reads, so a stack-logging run reports no allocation counts.
/// The counters are touched first so that the hook never initializes a global itself.
func countAllocations() {
    guard environment["MallocStackLogging"] == nil else { return }
    _ = (allocatedBytes.load(ordering: .relaxed), allocationCount.load(ordering: .relaxed), countingAllocations.load(ordering: .relaxed))
    dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger")!.assumingMemoryBound(to: Optional<MallocLogger>.self).pointee = mallocLogger
}
/// Runs work whose allocations belong to the fixture rather than the measured path.
func uncounted<T>(_ body: () throws -> T) rethrows -> T {
    countingAllocations.store(false, ordering: .relaxed)
    defer { countingAllocations.store(true, ordering: .relaxed) }
    return try body()
}
let scenario = CommandLine.arguments.dropFirst().first ?? "idle"
let inspectionDirectory = environment["VOLANT_MEMORY_INSPECT"].map { URL(fileURLWithPath: $0) }
let inspectedPhases = Set((environment["VOLANT_MEMORY_INSPECT_PHASES"] ?? "after_relief").split(separator: ",").map(String.init))
/// Runs vmmap and heap, and malloc_history when stack logging is on, against this fixture process
/// only, after the phases named in VOLANT_MEMORY_INSPECT_PHASES. Object contents are never printed.
func inspect(_ name: String) {
    guard let inspectionDirectory, inspectedPhases.contains(name) else { return }
    var tools = [("vmmap", ["-summary"]), ("heap", ["-s", "-q"])]
    if environment["MallocStackLogging"] != nil { tools.append(("malloc_history", ["-q", "-allBySize"])) }
    uncounted {
        for (tool, arguments) in tools {
            let output = inspectionDirectory.appendingPathComponent("\(scenario)-\(name)-\(tool).txt")
            FileManager.default.createFile(atPath: output.path, contents: nil)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/" + tool)
            process.arguments = arguments + [String(getpid())]
            process.standardOutput = try! FileHandle(forWritingTo: output)
            process.standardError = FileHandle.nullDevice
            try! process.run()
            process.waitUntilExit()
        }
    }
}
/// Measures one phase inside its own autorelease pool. Allocated bytes and counts are the total
/// churn during the phase, including memory freed again before it ends.
func phase(_ name: String, units: Int = 0, _ body: () throws -> Void) rethrows {
    let sampler = Sampler(); sampler.start()
    let start = ProcessInfo.processInfo.systemUptime
    let bytesBefore = allocatedBytes.load(ordering: .relaxed), countBefore = allocationCount.load(ordering: .relaxed)
    try autoreleasepool { try body() }
    let bytes = allocatedBytes.load(ordering: .relaxed) - bytesBefore, count = allocationCount.load(ordering: .relaxed) - countBefore
    let peak = sampler.stop(), current = memory()
    var heap = malloc_statistics_t()
    malloc_zone_statistics(nil, &heap)
    let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
    print("\(scenario),\(name),\(current.0),\(current.1),\(max(peak, current.0)),\(heap.size_in_use),\(String(format: "%.3f", elapsed)),\(units),\(bytes),\(count)")
    inspect(name)
}
func settle(_ name: String) { phase(name) { Thread.sleep(forTimeInterval: 0.3) } }
/// Starts counting allocations and prints the CSV header every fixture shares.
func startProfile() {
    countAllocations()
    setbuf(stdout, nil)
    print("scenario,phase,footprint_bytes,rss_bytes,sampled_peak_bytes,heap_in_use_bytes,elapsed_ms,units,allocated_bytes,allocations")
}
/// Ends every workload the same way. The final `malloc_zone_pressure_relief(nil, 0)` is diagnostic only:
/// it distinguishes releasable allocator pages from live allocations and is not a production strategy.
func finishProfile() {
    settle("pool_drained")
    phase("allocator_relief") { _ = malloc_zone_pressure_relief(nil, 0) }
    settle("after_relief")
}
