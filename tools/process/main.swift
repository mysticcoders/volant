import AppKit
import Darwin

// Probes what a process-management command could actually do from inside App Sandbox.
// Every probe is independent: one denial must not hide the result of another.
// Read-only throughout. Termination permission is checked with signal 0, which performs
// the kernel's access check without sending a signal. Nothing is terminated.

let sandboxed = FileManager.default.homeDirectoryForCurrentUser.path.contains("/Library/Containers/")

func report(_ probe: String, _ outcome: String) {
    print("\(probe.padding(toLength: 44, withPad: " ", startingAt: 0)) \(outcome)")
}

print("=== process capability probe ===")
print("sandboxed: \(sandboxed)   uid: \(getuid())   pid: \(getpid())")
print("")

// 1. Application enumeration through AppKit.
let apps = NSWorkspace.shared.runningApplications
let appPIDs = apps.map(\.processIdentifier).filter { $0 > 0 && $0 != getpid() }
report("NSWorkspace.runningApplications", "\(apps.count) apps")
report("  with bundleIdentifier", "\(apps.filter { $0.bundleIdentifier != nil }.count)")
report("  with icon", "\(apps.filter { $0.icon != nil }.count)")

// 2. Full process table through libproc.
var allPIDs = [pid_t](repeating: 0, count: 8192)
let listBytes = proc_listallpids(&allPIDs, Int32(allPIDs.count * MemoryLayout<pid_t>.size))
var libprocPIDs: [pid_t] = []
if listBytes <= 0 {
    report("proc_listallpids", "DENIED errno \(errno)")
} else {
    libprocPIDs = Array(allPIDs.prefix(Int(listBytes) / MemoryLayout<pid_t>.size)).filter { $0 > 1 && $0 != getpid() }
    report("proc_listallpids", "\(libprocPIDs.count) foreign pids")
}

// 3. Full process table through sysctl, the other route. Sized by the kernel's own reply.
var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
var sysctlPIDs: [pid_t] = []
var length = 0
if sysctl(&mib, 4, nil, &length, nil, 0) == 0, length > 0 {
    var buffer = [UInt8](repeating: 0, count: length)
    if sysctl(&mib, 4, &buffer, &length, nil, 0) == 0 {
        let stride = MemoryLayout<kinfo_proc>.stride
        let count = length / stride
        buffer.withUnsafeBytes { raw in
            let base = raw.baseAddress!.assumingMemoryBound(to: kinfo_proc.self)
            for index in 0..<count {
                let pid = base[index].kp_proc.p_pid
                if pid > 1 && pid != getpid() { sysctlPIDs.append(pid) }
            }
        }
        report("sysctl KERN_PROC_ALL", "\(count) entries, \(sysctlPIDs.count) foreign pids")
    } else {
        report("sysctl KERN_PROC_ALL read", "DENIED errno \(errno)")
    }
} else {
    report("sysctl KERN_PROC_ALL size", "DENIED errno \(errno)")
}

// The widest pid list any route gave us, for the per-process probes below.
let probePIDs = !libprocPIDs.isEmpty ? libprocPIDs : (!sysctlPIDs.isEmpty ? sysctlPIDs : appPIDs)
let source = !libprocPIDs.isEmpty ? "libproc" : (!sysctlPIDs.isEmpty ? "sysctl" : "NSWorkspace")
print("")
report("per-process probes use", "\(probePIDs.count) pids from \(source)")

// 4. Names and paths for foreign pids.
var namedCount = 0, pathCount = 0
for pid in probePIDs {
    var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    if proc_name(pid, &buffer, UInt32(buffer.count)) > 0 { namedCount += 1 }
    var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    if proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count)) > 0 { pathCount += 1 }
}
report("  proc_name", "\(namedCount)/\(probePIDs.count) readable")
report("  proc_pidpath", "\(pathCount)/\(probePIDs.count) readable")

// 5. CPU and memory per process. This is what a sortable process table needs.
var infoCount = 0
var sampleMemory = ""
for pid in probePIDs {
    var info = proc_taskinfo()
    let size = Int32(MemoryLayout<proc_taskinfo>.size)
    if proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size {
        infoCount += 1
        if sampleMemory.isEmpty { sampleMemory = "rss \(info.pti_resident_size / 1_048_576) MiB" }
    }
}
report("  proc_pidinfo TASKINFO (cpu/mem)", "\(infoCount)/\(probePIDs.count) readable")
if !sampleMemory.isEmpty { report("    sample", sampleMemory) }

// 6. Permission to signal. kill(pid, 0) runs the access check and sends nothing.
var permitted = 0, denied = 0, gone = 0
for pid in probePIDs {
    if kill(pid, 0) == 0 { permitted += 1 } else if errno == EPERM { denied += 1 } else { gone += 1 }
}
report("  kill(pid, 0) permitted", "\(permitted)")
report("  kill(pid, 0) EPERM", "\(denied)")
report("  kill(pid, 0) ESRCH/other", "\(gone)")

// 7. The same check limited to GUI applications, which is all a launcher would list.
var appPermitted = 0, appDenied = 0
for pid in appPIDs {
    if kill(pid, 0) == 0 { appPermitted += 1 } else if errno == EPERM { appDenied += 1 }
}
report("  kill(GUI app, 0) permitted", "\(appPermitted)/\(appPIDs.count)")

// 8. Per-app metadata a row would show, via AppKit rather than libproc.
if let sample = apps.first(where: { $0.bundleIdentifier != nil && $0.processIdentifier != getpid() }) {
    var info = proc_taskinfo()
    let size = Int32(MemoryLayout<proc_taskinfo>.size)
    let ok = proc_pidinfo(sample.processIdentifier, PROC_PIDTASKINFO, 0, &info, size) == size
    report("  sample app memory via proc_pidinfo", ok ? "\(info.pti_resident_size / 1_048_576) MiB" : "DENIED errno \(errno)")
}

print("")
print("=== end probe ===")

// 9. Destructive probe, opt-in. Attempts to quit a named bundle identifier and reports which
// path worked. Only runs with an explicit argument so the read-only probe stays safe.
if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "terminate" {
    let target = CommandLine.arguments[2]
    print("")
    print("=== termination probe: \(target) ===")
    func find() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == target }
    }
    func settle(_ app: NSRunningApplication, _ seconds: Double) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            if app.isTerminated || find() == nil { return true }
        }
        return app.isTerminated || find() == nil
    }
    guard let app = find() else {
        report("target running", "NOT FOUND — launch it first")
        exit(2)
    }
    report("target running", "pid \(app.processIdentifier)")
    report("kill(pid, 0) permission", kill(app.processIdentifier, 0) == 0 ? "permitted" : "EPERM")

    let requested = app.terminate()
    report("terminate() returned", "\(requested)")
    if settle(app, 5) {
        report("RESULT", "terminate() QUIT THE APP")
        exit(0)
    }
    report("terminate() outcome", "still running after 5s")

    let forced = app.forceTerminate()
    report("forceTerminate() returned", "\(forced)")
    if settle(app, 5) {
        report("RESULT", "forceTerminate() QUIT THE APP")
        exit(0)
    }
    report("RESULT", "BOTH PATHS FAILED — app still running")
    exit(1)
}
