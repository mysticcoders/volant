import Foundation
import Security
import VolantCore

/// Listens on a Unix socket in the shared app group container while the owner has Connected Apps on,
/// for the `volant-mcp` bridges AI apps start. Before reading a byte it checks each peer's code
/// signature: only the bridge's identifier signed by Volant's own team is served. Each connection
/// gets its own `MCPSession`; its first line is the bridge's handshake naming the client. Nothing it
/// reads or writes is logged. See docs/mcp-server-design.md.
final class MCPListener {
    /// A connected peer's signing team and identifier, from its audit token.
    struct Peer: Equatable {
        let team: String?
        let identifier: String?
    }

    static let maximumConnections = 8

    /// The tools to offer, the current settings, and what to do when a new client connects. Set by
    /// the app; read on the listener's threads.
    /// The tools for one client, so sensitive tools can name it when they ask the owner.
    var makeTools: (MCPPreferences, String) -> [MCPTool] = { _, _ in [] }
    var makeResources: (MCPPreferences) -> MCPResources? = { _ in nil }
    var onNewClient: (String) -> Void = { _ in }

    private let socketURL: URL?
    private let identify: (Int32) -> Peer?
    private let ownTeam: String?
    private let version: String
    private let lock = NSLock()
    private var preferences = MCPPreferences()
    private var listener: Int32 = -1
    private var connections = Set<Int32>()
    private var acceptThread: Thread?

    /// `socketURL` defaults to the app group container's socket for this app; tests pass their own,
    /// with an `identify` that stands in for the signature check.
    init(socketURL: URL? = MCPListener.defaultSocketURL, identify: @escaping (Int32) -> Peer? = MCPListener.peer, ownTeam: String? = MCPListener.ownTeam,
         version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0") {
        self.socketURL = socketURL
        self.identify = identify
        self.ownTeam = ownTeam
        self.version = version
    }

    static var defaultSocketURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: MCPEndpoint.appGroup)?
            .appendingPathComponent(MCPEndpoint.socketName(appBundleID: Bundle.main.bundleIdentifier ?? ""))
    }

    var isListening: Bool { lock.withLock { listener >= 0 } }

    /// Applies new settings: listens while the server is on, stops and closes every connection when
    /// it is turned off. Connections already open see the new settings on their next request.
    func apply(_ updated: MCPPreferences) {
        lock.withLock { preferences = updated }
        if updated.enabled { start() } else { stop() }
    }

    private func current() -> MCPPreferences { lock.withLock { preferences } }

    /// Binds the socket, replacing a stale one a previous run left, and starts accepting.
    private func start() {
        guard !isListening, let path = socketURL?.path else { return }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        var status = stat()
        if lstat(path, &status) == 0, status.st_mode & S_IFMT == S_IFSOCK { unlink(path) }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(descriptor, 4) == 0 else {
            close(descriptor)
            return
        }
        lock.withLock { listener = descriptor }
        let thread = Thread { [weak self] in self?.acceptLoop(descriptor) }
        thread.name = "Volant MCP"
        acceptThread = thread
        thread.start()
    }

    /// Stops listening, closes every connection, and removes the socket file.
    func stop() {
        let (descriptor, open) = lock.withLock { () -> (Int32, Set<Int32>) in
            let value = (listener, connections)
            listener = -1
            connections = []
            return value
        }
        guard descriptor >= 0 else { return }
        Darwin.shutdown(descriptor, SHUT_RDWR)
        close(descriptor)
        for connection in open { Darwin.shutdown(connection, SHUT_RDWR) }
        if let path = socketURL?.path { unlink(path) }
    }

    deinit { stop() }

    private func acceptLoop(_ descriptor: Int32) {
        while true {
            let connection = accept(descriptor, nil, nil)
            guard connection >= 0 else { return }
            var on: Int32 = 1
            setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            guard allowed(identify(connection)), admit(connection) else {
                close(connection)
                continue
            }
            Thread { [weak self] in self?.serve(connection) }.start()
        }
    }

    /// Only the bridge, signed by the team that signed this app, may connect.
    private func allowed(_ peer: Peer?) -> Bool {
        guard let peer, let ownTeam, let team = peer.team else { return false }
        return team == ownTeam && peer.identifier == MCPEndpoint.bridgeIdentifier
    }

    private func admit(_ connection: Int32) -> Bool {
        lock.withLock {
            guard listener >= 0, connections.count < Self.maximumConnections else { return false }
            connections.insert(connection)
            return true
        }
    }

    /// Reads the handshake, then answers one line at a time until the bridge closes.
    private func serve(_ connection: Int32) {
        defer {
            lock.withLock { _ = connections.remove(connection) }
            close(connection)
        }
        var reader = LineReader(descriptor: connection)
        guard let first = reader.next(), let handshake = try? JSONDecoder().decode(MCPValue.self, from: first),
              handshake["volantBridge"]?.int == MCPEndpoint.handshakeVersion, let client = handshake["client"]?.string.flatMap(MCPEndpoint.clientName) else { return }
        if !current().knownClients.contains(client) { DispatchQueue.main.async { [onNewClient] in onNewClient(client) } }
        let session = MCPSession(version: version, instructions: Self.instructions, tools: { [weak self] in
            guard let self else { return [] }
            return self.makeTools(self.current(), client)
        }, resources: { [weak self] in
            guard let self else { return nil }
            return self.makeResources(self.current())
        }, refusal: { [weak self] in
            guard let self else { return .serverOff }
            return self.current().refusal(for: client)
        })
        while let line = reader.next() {
            let done = DispatchSemaphore(value: 0)
            var reply: Data?
            Task {
                reply = await session.handle(line)
                done.signal()
            }
            done.wait()
            guard let reply else { continue }
            let framed = reply + Data([0x0A])
            let sent = framed.withUnsafeBytes { buffer -> Bool in
                var offset = 0
                while offset < framed.count {
                    let written = write(connection, buffer.baseAddress! + offset, framed.count - offset)
                    if written <= 0 { return false }
                    offset += written
                }
                return true
            }
            if !sent { return }
        }
    }

    static let instructions = "Volant is a Mac launcher. These tools read the owner's Volant notes (Markdown files), snippets and quicklinks, "
        + "calculate units, time zones, dates and arithmetic, and report Breaks and Focus. Notes, snippets and quicklinks are also resources "
        + "(volant://notes/<id>, volant://snippets, volant://quicklinks). Tools that add notes, snippets or quicklinks, or control Focus and "
        + "Breaks, appear only when the owner allowed them in Volant Settings › AI › Connected Apps."

    /// The connected peer's signing team and identifier, read from its audit token.
    static func peer(_ connection: Int32) -> Peer? {
        var token = audit_token_t()
        var length = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getsockopt(connection, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &length) == 0 else { return nil }
        let data = withUnsafeBytes(of: &token) { Data($0) } as CFData
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: data] as CFDictionary, [], &code) == errSecSuccess, let code,
              SecCodeCheckValidity(code, [], nil) == errSecSuccess else { return nil }
        return signing(of: code)
    }

    /// The team that signed this app, or nil for an unsigned build, which then serves no one.
    static let ownTeam: String? = {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        return signing(of: code)?.team
    }()

    private static func signing(of code: SecCode) -> Peer? {
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let fields = info as? [String: Any] else { return nil }
        return Peer(team: fields[kSecCodeInfoTeamIdentifier as String] as? String, identifier: fields[kSecCodeInfoIdentifier as String] as? String)
    }
}

/// Splits a socket's bytes into lines, refusing any longer than `MCPSession.maximumLineBytes`.
struct LineReader {
    let descriptor: Int32
    private var buffer = Data()
    private var ended = false

    init(descriptor: Int32) { self.descriptor = descriptor }

    /// The next line without its newline, or nil at the end of the stream or after an oversized line.
    mutating func next() -> Data? {
        var chunk = [UInt8](repeating: 0, count: 65_536)
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                buffer = Data(buffer[buffer.index(after: newline)...])
                if line.isEmpty { continue }
                return Data(line)
            }
            guard !ended, buffer.count <= MCPSession.maximumLineBytes else { return nil }
            let count = read(descriptor, &chunk, chunk.count)
            if count <= 0 {
                ended = true
                guard !buffer.isEmpty else { return nil }
                let line = buffer
                buffer = Data()
                return line
            }
            buffer.append(contentsOf: chunk[0..<count])
        }
    }
}
