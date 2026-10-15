import Darwin
import Foundation

// Probes whether a "what's listening on this port" view can be built from inside App Sandbox.
// Two modes. `listen <port>` stands in for a vibe-coded dev server: it binds 127.0.0.1:<port>,
// listens, prints its pid and sleeps. `probe <port> <pid> <folder>` then looks for that listener
// by every route the feature could use and reports each one independently, so one denial cannot
// hide another. Read-only: signal permission is checked with kill(pid, 0), which sends nothing.

func report(_ probe: String, _ outcome: String) {
    print("\(probe.padding(toLength: 48, withPad: " ", startingAt: 0)) \(outcome)")
}

/// Binds and listens on loopback, then waits to be killed by the script that started it.
func listen(port: UInt16) -> Never {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    var yes: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = port.bigEndian
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    let bound = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
    }
    guard bound == 0, Darwin.listen(fd, 16) == 0 else { print("listen failed errno \(errno)"); exit(1) }
    print(getpid())
    fflush(stdout)
    while true { sleep(60) }
}

/// The TCP ports a process is listening on, read from its file descriptors.
/// Returns nil when the process's descriptor table cannot be read at all.
func listeningPorts(of pid: pid_t) -> [UInt16]? {
    let bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
    guard bytes > 0 else { return nil }
    var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(bytes) / MemoryLayout<proc_fdinfo>.stride)
    let filled = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, bytes)
    guard filled > 0 else { return nil }
    var ports: [UInt16] = []
    for fd in fds.prefix(Int(filled) / MemoryLayout<proc_fdinfo>.stride) where fd.proc_fdtype == PROX_FDTYPE_SOCKET {
        var info = socket_fdinfo()
        let size = Int32(MemoryLayout<socket_fdinfo>.size)
        guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &info, size) == size else { continue }
        guard info.psi.soi_kind == SOCKINFO_TCP, info.psi.soi_proto.pri_tcp.tcpsi_state == TSI_S_LISTEN else { continue }
        ports.append(UInt16(bigEndian: UInt16(truncatingIfNeeded: info.psi.soi_proto.pri_tcp.tcpsi_ini.insi_lport)))
    }
    return ports
}

/// Every pid owned by this user, from the sysctl process table (the route that survives the sandbox).
func userPIDs() -> [pid_t] {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_UID, Int32(getuid())]
    var length = 0
    guard sysctl(&mib, 4, nil, &length, nil, 0) == 0, length > 0 else { return [] }
    var procs = [kinfo_proc](repeating: kinfo_proc(), count: length / MemoryLayout<kinfo_proc>.stride + 8)
    length = procs.count * MemoryLayout<kinfo_proc>.stride
    guard sysctl(&mib, 4, &procs, &length, nil, 0) == 0 else { return [] }
    return procs.prefix(length / MemoryLayout<kinfo_proc>.stride).map(\.kp_proc.p_pid).filter { $0 > 0 }
}

func probe(port: UInt16, pid: pid_t, folder: String) {
    let sandboxed = FileManager.default.homeDirectoryForCurrentUser.path.contains("/Library/Containers/")
    print("=== port ownership probe ===")
    print("sandboxed: \(sandboxed)   target: port \(port), pid \(pid)")
    print("")

    // 1. The target's own descriptors: does it own a listening socket on the port?
    if let ports = listeningPorts(of: pid) {
        report("PROC_PIDLISTFDS + PROC_PIDFDSOCKETINFO", ports.contains(port) ? "found port \(port) on pid \(pid)" : "readable, port not found (\(ports))")
    } else {
        report("PROC_PIDLISTFDS on target", "DENIED errno \(errno)")
    }

    // 2. The whole user: can every listener be found without knowing the pid first?
    let started = Date()
    let pids = userPIDs()
    var readable = 0, listeners: [(pid_t, UInt16)] = []
    for candidate in pids {
        guard let ports = listeningPorts(of: candidate) else { continue }
        readable += 1
        listeners += ports.map { (candidate, $0) }
    }
    report("user pids from sysctl KERN_PROC_UID", "\(pids.count), whole scan \(Int(Date().timeIntervalSince(started) * 1000)) ms")
    report("  descriptor tables readable", "\(readable)/\(pids.count)")
    report("  listening TCP sockets found", "\(listeners.count)")
    report("  target found by scanning", listeners.contains { $0.0 == pid && $0.1 == port } ? "yes" : "no")

    // 3. The kernel's TCP control-block list, which carries ports but is not tied to a pid here.
    var length = 0
    if sysctlbyname("net.inet.tcp.pcblist_n", nil, &length, nil, 0) == 0 {
        var buffer = [UInt8](repeating: 0, count: length + 4096)
        length = buffer.count
        let read = sysctlbyname("net.inet.tcp.pcblist_n", &buffer, &length, nil, 0)
        report("sysctl net.inet.tcp.pcblist_n", read == 0 ? "readable, \(length) bytes" : "DENIED errno \(errno)")
    } else {
        report("sysctl net.inet.tcp.pcblist_n", "DENIED errno \(errno)")
    }

    // 4. lsof as a child process, which inherits the sandbox.
    let lsof = Process()
    lsof.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
    lsof.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-Fp"]
    let pipe = Pipe()
    lsof.standardOutput = pipe
    lsof.standardError = Pipe()
    do {
        try lsof.run()
        lsof.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        report("lsof -iTCP -sTCP:LISTEN (child)", output.contains("p\(pid)") ? "found pid \(pid) (exit \(lsof.terminationStatus))"
               : "no owner in output (exit \(lsof.terminationStatus))")
    } catch {
        report("lsof -iTCP -sTCP:LISTEN (child)", "could not launch: \(error.localizedDescription)")
    }

    // 5. Row details: name, working directory (the project folder) and age.
    var name = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    report("proc_name", proc_name(pid, &name, UInt32(name.count)) > 0 ? String(cString: name) : "DENIED errno \(errno)")
    var vnode = proc_vnodepathinfo()
    let vnodeSize = Int32(MemoryLayout<proc_vnodepathinfo>.size)
    if proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnode, vnodeSize) == vnodeSize {
        let cwd = withUnsafeBytes(of: vnode.pvi_cdir.vip_path) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
        let resolved = (cwd as NSString).resolvingSymlinksInPath, expected = (folder as NSString).resolvingSymlinksInPath
        report("PROC_PIDVNODEPATHINFO (cwd)", resolved == expected ? "matches the project folder" : "readable, differs: \(cwd)")
    } else {
        report("PROC_PIDVNODEPATHINFO (cwd)", "DENIED errno \(errno)")
    }
    var bsd = proc_bsdinfo()
    let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.size)
    if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, bsdSize) == bsdSize {
        let age = Int(Date().timeIntervalSince1970) - Int(bsd.pbi_start_tvsec)
        report("PROC_PIDTBSDINFO (start time, uid)", "age \(age)s, uid \(bsd.pbi_uid == getuid() ? "same user" : "\(bsd.pbi_uid)")")
    } else {
        report("PROC_PIDTBSDINFO (start time, uid)", "DENIED errno \(errno)")
    }

    // 6. Could this process stop it? kill(pid, 0) runs the access check and sends no signal.
    report("kill(pid, 0) on the listener", kill(pid, 0) == 0 ? "permitted" : (errno == EPERM ? "EPERM" : "errno \(errno)"))
}

let arguments = CommandLine.arguments
if arguments.count == 3, arguments[1] == "listen", let port = UInt16(arguments[2]) {
    listen(port: port)
} else if arguments.count == 5, arguments[1] == "probe", let port = UInt16(arguments[2]), let pid = pid_t(arguments[3]) {
    probe(port: port, pid: pid, folder: arguments[4])
} else {
    print("usage: ports listen <port> | ports probe <port> <pid> <folder>")
    exit(2)
}
