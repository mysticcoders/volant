import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// A TCP port one of the owner's processes is listening on. Read by the agent helper, which runs
/// outside App Sandbox because the sandboxed app can read no other process's sockets. Carries the
/// executable path and working folder, never the process's arguments or environment.
public struct ListeningServer: Codable, Hashable, Identifiable {
    public let pid: Int32
    public let port: Int
    /// The executable's file name, or the kernel's short process name when its path is unreadable.
    public let process: String
    public let executable: String?
    /// The process's working folder, or nil when it is the root folder, as for launchd-started apps.
    public let directory: String?
    /// Whether it accepts connections beyond this Mac: bound to a wildcard or non-loopback address.
    public let exposed: Bool
    /// When the process started, if readable.
    public var started: Date?

    public var id: String { "\(pid):\(port)" }
    public var url: URL { URL(string: "http://localhost:\(port)")! }
    public var kind: Kind { Kind(process: process, executable: executable) }
    /// The runtime's name for a recognized runtime, otherwise the process name.
    public var displayName: String {
        if case .runtime(let name) = kind { return name }
        return process
    }
    /// The working folder's last component, the usual project name.
    public var folderName: String? { directory.map { ($0 as NSString).lastPathComponent } }

    public init(pid: Int32, port: Int, process: String, executable: String?, directory: String?, exposed: Bool, started: Date? = nil) {
        self.pid = pid; self.port = port; self.process = process
        self.executable = executable; self.directory = directory; self.exposed = exposed; self.started = started
    }

    /// How long it has been running, as `45s`, `12m`, `3h` or `2d`, or nil without a start time.
    public func age(now: Date = Date()) -> String? {
        guard let started else { return nil }
        let seconds = max(0, Int(now.timeIntervalSince(started)))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86400)d"
    }

    /// The row's second line: the process name when a runtime name replaced it, the working
    /// folder, the pid and how long it has run.
    public func detail(home: String, now: Date = Date()) -> String {
        var parts: [String] = []
        if displayName != process { parts.append(process) }
        if let folder = abbreviatedDirectory(home: home) { parts.append(folder) }
        parts.append("pid \(pid)")
        if let age = age(now: now) { parts.append(age) }
        return parts.joined(separator: " · ")
    }

    /// The working folder with the home folder shortened to `~`.
    public func abbreviatedDirectory(home: String) -> String? {
        guard let directory else { return nil }
        let base = home.hasSuffix("/") ? String(home.dropLast()) : home
        if directory == base { return "~" }
        return directory.hasPrefix(base + "/") ? "~" + directory.dropFirst(base.count) : directory
    }

    public enum Kind: Hashable {
        /// A language runtime, web server or database a developer starts by hand.
        case runtime(String)
        /// Any other process of the owner's, such as an app with a local port.
        case other
        /// A macOS service, such as AirPlay Receiver or Rapport.
        case system

        /// Executable file-name prefixes matched case-insensitively, most specific first.
        static let runtimes: [(prefix: String, name: String)] = [
            ("node", "Node.js"), ("bun", "Bun"), ("deno", "Deno"),
            ("python", "Python"), ("ruby", "Ruby"), ("java", "Java"), ("php", "PHP"),
            ("dotnet", ".NET"), ("beam.smp", "Erlang"), ("perl", "Perl"),
            ("nginx", "nginx"), ("httpd", "Apache"), ("caddy", "Caddy"),
            ("postgres", "PostgreSQL"), ("mysqld", "MySQL"), ("mariadbd", "MariaDB"),
            ("redis-server", "Redis"), ("mongod", "MongoDB"), ("memcached", "Memcached"),
            ("ollama", "Ollama"), ("workerd", "workerd"),
        ]

        /// Each runtime's logo in the app's `Runtimes` asset folder, from Simple Icons 16.35.0, and
        /// its brand color as RGB hex. Java and Memcached have no icon there and use the generic tile.
        static let logos: [String: (asset: String, hex: String)] = [
            "Node.js": ("nodedotjs", "5FA04E"), "Bun": ("bun", "000000"), "Deno": ("deno", "000000"),
            "Python": ("python", "3776AB"), "Ruby": ("ruby", "CC342D"), "PHP": ("php", "777BB4"),
            ".NET": ("dotnet", "512BD4"), "Erlang": ("erlang", "A90533"), "Perl": ("perl", "0073A1"),
            "nginx": ("nginx", "009639"), "Apache": ("apache", "D22128"), "Caddy": ("caddy", "1F88C0"),
            "PostgreSQL": ("postgresql", "4169E1"), "MySQL": ("mysql", "4479A1"), "MariaDB": ("mariadb", "003545"),
            "Redis": ("redis", "FF4438"), "MongoDB": ("mongodb", "47A248"), "Ollama": ("ollama", "000000"),
            "workerd": ("cloudflareworkers", "F38020"),
        ]

        /// The runtime's logo asset name and brand color, when there is one.
        public var logo: (asset: String, hex: String)? {
            guard case .runtime(let name) = self else { return nil }
            return Self.logos[name]
        }
        static let systemPrefixes = ["/System/", "/usr/libexec/", "/usr/sbin/", "/usr/bin/", "/sbin/", "/bin/", "/Library/Apple/"]

        public init(process: String, executable: String?) {
            let name = (executable.map { ($0 as NSString).lastPathComponent } ?? process).lowercased()
            if let match = Self.runtimes.first(where: { name.hasPrefix($0.prefix) }) { self = .runtime(match.name); return }
            if let executable, Self.systemPrefixes.contains(where: { executable.hasPrefix($0) }) { self = .system; return }
            self = .other
        }
    }
}

/// The Servers command: its query words, ordering, filtering and, on Darwin, the scan itself.
public enum ListeningServers {
    /// The most servers one reply carries.
    public static let maximumServers = 256

    /// What follows a Servers query word, or nil when `query` isn't a Servers query. `all` as the
    /// first word also shows macOS services.
    public static func queryTerm(_ query: String) -> (text: String, all: Bool)? {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for word in ["servers", "server", "ports", "listening"] {
            let rest: String
            if value == word { rest = "" } else if value.hasPrefix(word + " ") { rest = String(value.dropFirst(word.count + 1)) } else { continue }
            let trimmed = rest.trimmingCharacters(in: .whitespaces)
            if trimmed == "all" { return ("", true) }
            if trimmed.hasPrefix("all ") { return (String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces), true) }
            return (trimmed, false)
        }
        return nil
    }

    /// Runtimes first, then other processes, each by port then pid. macOS services appear only with
    /// `all`. Text matches the port, the process or runtime name, or the working folder.
    public static func arrange(_ servers: [ListeningServer], matching text: String = "", all: Bool = false) -> [ListeningServer] {
        let term = text.trimmingCharacters(in: .whitespaces)
        func rank(_ server: ListeningServer) -> Int {
            switch server.kind { case .runtime: return 0; case .other: return 1; case .system: return 2 }
        }
        return servers
            .filter { all || $0.kind != .system }
            .filter { server in
                term.isEmpty || String(server.port).hasPrefix(term) || server.process.localizedCaseInsensitiveContains(term)
                    || server.displayName.localizedCaseInsensitiveContains(term) || (server.directory?.localizedCaseInsensitiveContains(term) ?? false)
            }
            .sorted { (rank($0), $0.port, $0.pid) < (rank($1), $1.port, $1.pid) }
    }

    #if canImport(Darwin)
    /// Every TCP port in the listening state held by a process owned by `uid`, one entry per process
    /// and port however many addresses it is bound to, at most `maximumServers`. Processes whose
    /// descriptors can't be read are skipped. Reads only the kernel's process table, descriptor and
    /// socket records, executable path and working folder.
    public static func scan(uid: uid_t = getuid()) -> [ListeningServer] {
        var found: [String: ListeningServer] = [:]
        for pid in pids(uid: uid) {
            let ports = listeningPorts(pid)
            guard !ports.isEmpty else { continue }
            let executable = path(pid)
            let process = executable.map { ($0 as NSString).lastPathComponent } ?? name(pid)
            let directory = workingDirectory(pid), started = startTime(pid)
            for (port, exposed) in ports {
                found["\(pid):\(port)"] = ListeningServer(pid: pid, port: port, process: process, executable: executable,
                                                         directory: directory, exposed: exposed, started: started)
            }
            if found.count >= maximumServers { break }
        }
        return Array(found.values.sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }.prefix(maximumServers))
    }

    /// Processes owned by `uid`, from the kernel's process table.
    static func pids(uid: uid_t) -> [pid_t] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_UID, Int32(bitPattern: uid)]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride + 16)
        size = procs.count * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return [] }
        return procs.prefix(size / MemoryLayout<kinfo_proc>.stride).map(\.kp_proc.p_pid).filter { $0 > 0 }
    }

    /// The process's listening TCP ports, each with whether any of its bindings is non-loopback.
    static func listeningPorts(_ pid: pid_t) -> [(port: Int, exposed: Bool)] {
        let bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bytes > 0 else { return [] }
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(bytes) / MemoryLayout<proc_fdinfo>.stride)
        let read = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, bytes)
        guard read > 0 else { return [] }
        var ports: [Int: Bool] = [:]
        for fd in fds.prefix(Int(read) / MemoryLayout<proc_fdinfo>.stride) where fd.proc_fdtype == PROX_FDTYPE_SOCKET {
            var info = socket_fdinfo()
            let size = Int32(MemoryLayout<socket_fdinfo>.size)
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &info, size) == size,
                  info.psi.soi_kind == SOCKINFO_TCP, info.psi.soi_proto.pri_tcp.tcpsi_state == TSI_S_LISTEN else { continue }
            let address = info.psi.soi_proto.pri_tcp.tcpsi_ini
            let port = Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: address.insi_lport)))
            guard port > 0 else { continue }
            ports[port] = (ports[port] ?? false) || !isLoopback(address)
        }
        return ports.map { ($0.key, $0.value) }
    }

    /// Whether a socket's local address is loopback only: 127.0.0.0/8 or ::1.
    static func isLoopback(_ address: in_sockinfo) -> Bool {
        if address.insi_vflag & UInt8(INI_IPV4) != 0 {
            return UInt32(bigEndian: address.insi_laddr.ina_46.i46a_addr4.s_addr) >> 24 == 127
        }
        var v6 = address.insi_laddr.ina_6
        var loopback = in6addr_loopback
        return memcmp(&v6, &loopback, MemoryLayout<in6_addr>.size) == 0
    }

    static func path(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    static func name(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 64)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return "pid \(pid)" }
        return String(cString: buffer)
    }

    static func startTime(_ pid: pid_t) -> Date? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1_000_000)
    }

    static func workingDirectory(_ pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let directory = withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return directory.isEmpty || directory == "/" ? nil : directory
    }
    #endif
}
