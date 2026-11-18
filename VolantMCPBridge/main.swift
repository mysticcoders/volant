import AppKit
import Foundation
import VolantCore

// volant-mcp: the stdio MCP server AI apps start, `volant-mcp --client <name>`. It holds no MCP logic:
// it connects to the Unix socket the running Volant listens on in the shared app group container,
// sends one handshake line naming its client, then relays lines both ways until the AI app closes
// stdin. Volant checks this process's code signature before reading anything. When Volant isn't
// running, or quits mid-session, the bridge launches it, waits for the socket, and replays a legacy
// client's `initialize` (`MCPBridgeReplay`) before the next request, so the AI app never has to
// reconnect. If Volant never answers, the request gets an MCP error saying why. Only MCP messages go
// to stdout; nothing is logged.

/// Writes one line to stdout.
func emit(_ line: Data) {
    FileHandle.standardOutput.write(line + Data([0x0A]))
}

/// Answers every request on stdin with the same error, so the AI app shows the reason, until stdin closes.
func refuseAll(code: Int, message: String) -> Never {
    while let line = readLine(strippingNewline: true) {
        guard let request = try? JSONDecoder().decode(MCPValue.self, from: Data(line.utf8)), let id = request["id"], id != .null else { continue }
        emit(MCPValue.object(["jsonrpc": .string("2.0"), "id": id, "error": .object(["code": .int(code), "message": .string(message)])]).line())
    }
    exit(0)
}

/// The Volant app this bridge ships inside: `Volant.app/Contents/MacOS/volant-mcp`.
func enclosingApp() -> (url: URL, bundleID: String)? {
    let app = Bundle.main.bundleURL.resolvingSymlinksInPath()
    let candidate = Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() ?? app
    guard candidate.pathExtension == "app", let bundleID = Bundle(url: candidate)?.bundleIdentifier else { return nil }
    return (candidate, bundleID)
}

/// Connects to the socket at `path`, or returns nil.
func connectSocket(_ path: String) -> Int32? {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
        buffer.copyBytes(from: bytes)
        buffer[bytes.count] = 0
    }
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { return nil }
    let connected = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    if connected == 0 { return descriptor }
    close(descriptor)
    return nil
}

/// Launches Volant without bringing it forward, and waits until it opens.
func launch(_ app: URL) {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    configuration.addsToRecentItems = false
    let done = DispatchSemaphore(value: 0)
    NSWorkspace.shared.openApplication(at: app, configuration: configuration) { _, _ in done.signal() }
    _ = done.wait(timeout: .now() + 10)
}

/// Writes all of `data` to `descriptor`; false when the other side has gone.
func send(_ data: Data, to descriptor: Int32) -> Bool {
    data.withUnsafeBytes { buffer -> Bool in
        var offset = 0
        while offset < data.count {
            let written = write(descriptor, buffer.baseAddress! + offset, data.count - offset)
            if written <= 0 { return false }
            offset += written
        }
        return true
    }
}

/// Splits a descriptor's bytes into lines.
struct Lines {
    let descriptor: Int32
    var buffer = Data()

    /// The next line without its newline, or nil when the stream ends.
    mutating func next() -> Data? {
        var chunk = [UInt8](repeating: 0, count: 65_536)
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[buffer.startIndex..<newline])
                buffer = Data(buffer[buffer.index(after: newline)...])
                if line.isEmpty { continue }
                return line
            }
            let count = read(descriptor, &chunk, chunk.count)
            if count <= 0 {
                guard !buffer.isEmpty else { return nil }
                defer { buffer = Data() }
                return buffer
            }
            buffer.append(contentsOf: chunk[0..<count])
        }
    }
}

let arguments = CommandLine.arguments
guard let index = arguments.firstIndex(of: "--client"), index + 1 < arguments.count, let client = MCPEndpoint.clientName(arguments[index + 1]) else {
    FileHandle.standardError.write(Data("usage: volant-mcp --client <name>  (1 to 40 letters, digits and hyphens)\n".utf8))
    refuseAll(code: -31003, message: "Volant's MCP bridge needs --client <name> in this app's MCP configuration. Copy it again from Volant Settings › AI › Connected Apps.")
}
guard let app = enclosingApp(),
      let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: MCPEndpoint.appGroup) else {
    refuseAll(code: -31003, message: "Run volant-mcp from inside Volant.app, as Volant Settings › AI › Connected Apps shows.")
}
let socketPath = container.appendingPathComponent(MCPEndpoint.socketName(appBundleID: app.bundleID)).path
let handshake = MCPValue.object(["volantBridge": .int(MCPEndpoint.handshakeVersion), "client": .string(client)]).line() + Data([0x0A])
let outputLock = NSLock()
let connectionLock = NSLock()
var connection: Int32?
var replay = MCPBridgeReplay()
signal(SIGPIPE, SIG_IGN)

/// Writes one line to stdout, never interleaved with another.
func output(_ line: Data) {
    outputLock.withLock { _ = send(line + Data([0x0A]), to: STDOUT_FILENO) }
}

/// Relays Volant's replies to stdout, dropping replies to a replayed handshake, until Volant closes;
/// then forgets the connection so the next request reconnects.
func relay(from descriptor: Int32) {
    var lines = Lines(descriptor: descriptor)
    while let line = lines.next() {
        if !MCPBridgeReplay.isReplayReply(line) { output(line) }
    }
    connectionLock.withLock { if connection == descriptor { connection = nil } }
    close(descriptor)
}

/// Connects to the running Volant, launching it when the socket isn't there, then sends the handshake
/// and any replay. Returns nil when Volant never answers.
func establish() -> Int32? {
    var descriptor = connectSocket(socketPath)
    if descriptor == nil {
        launch(app.url)
        for _ in 0..<50 where descriptor == nil {
            usleep(200_000)
            descriptor = connectSocket(socketPath)
        }
    }
    guard let descriptor else { return nil }
    var on: Int32 = 1
    setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    guard send(handshake, to: descriptor), replay.lines().allSatisfy({ send($0 + Data([0x0A]), to: descriptor) }) else {
        close(descriptor)
        return nil
    }
    Thread { relay(from: descriptor) }.start()
    return descriptor
}

/// Sends one client line to Volant, reconnecting once if Volant went away; a request that can't be
/// delivered gets an error naming the problem.
func forward(_ line: Data) {
    let delivered = connectionLock.withLock { () -> Bool in
        for _ in 0..<2 {
            if connection == nil { connection = establish() }
            guard let current = connection else { return false }
            if send(line + Data([0x0A]), to: current) { return true }
            shutdown(current, SHUT_RDWR)
            connection = nil
        }
        return false
    }
    replay.observe(line)
    guard !delivered, let request = try? JSONDecoder().decode(MCPValue.self, from: line), let id = request["id"], id != .null else { return }
    output(MCPValue.object(["jsonrpc": .string("2.0"), "id": id, "error": .object(["code": .int(-31001),
        "message": .string("Volant didn't answer. Open Volant and turn on Connected Apps in Settings › AI.")])]).line())
}

var input = Lines(descriptor: STDIN_FILENO)
while let line = input.next() { forward(line) }
connectionLock.withLock { if let current = connection { shutdown(current, SHUT_WR) } }
usleep(500_000)
exit(0)
