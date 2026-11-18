import AppKit
import Foundation
import VolantCore

// volant-mcp: the stdio MCP server AI apps start, `volant-mcp --client <name>`. It holds no MCP logic:
// it connects to the Unix socket the running Volant listens on in the shared app group container,
// sends one handshake line naming its client, then copies bytes both ways until either side closes.
// Volant checks this process's code signature before reading anything. When Volant isn't running, the
// bridge launches it and waits for the socket; if Volant never answers, it replies to each request
// with an MCP error saying why. Only MCP messages go to stdout; nothing is logged.

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

/// Copies everything readable from `source` to `destination` until `source` ends.
func pump(from source: Int32, to destination: Int32) {
    var buffer = [UInt8](repeating: 0, count: 65_536)
    while true {
        let count = read(source, &buffer, buffer.count)
        if count <= 0 { return }
        var offset = 0
        while offset < count {
            let written = buffer.withUnsafeBytes { write(destination, $0.baseAddress! + offset, count - offset) }
            if written <= 0 { return }
            offset += written
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
var descriptor = connectSocket(socketPath)
if descriptor == nil {
    launch(app.url)
    for _ in 0..<50 where descriptor == nil {
        usleep(200_000)
        descriptor = connectSocket(socketPath)
    }
}
guard let connection = descriptor else {
    refuseAll(code: -31001, message: "Volant didn't answer. Open Volant and turn on Connected Apps in Settings › AI.")
}
signal(SIGPIPE, SIG_IGN)
let handshake = MCPValue.object(["volantBridge": .int(MCPEndpoint.handshakeVersion), "client": .string(client)]).line() + Data([0x0A])
_ = handshake.withUnsafeBytes { write(connection, $0.baseAddress!, handshake.count) }
let fromVolant = Thread {
    pump(from: connection, to: STDOUT_FILENO)
    exit(0)
}
fromVolant.start()
pump(from: STDIN_FILENO, to: connection)
shutdown(connection, SHUT_WR)
while true { sleep(60) }
