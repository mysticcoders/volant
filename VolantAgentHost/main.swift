import Foundation
import Security

/// Local Herdr discovery and typed ACP conversations. No shell or arbitrary-command API.
/// This service intentionally runs outside App Sandbox to reach the user's Herdr socket.
final class AgentHost: NSObject, VolantAgentHostProtocol {
    private let acp = ACPConnection()
    func acpStart(provider: String, project: String, reply: @escaping (String?) -> Void) {
        acp.queue.async { do { try self.acp.start(provider: provider, project: project); reply(nil) } catch { reply(error.localizedDescription) } }
    }
    func acpRead(reply: @escaping (Data?, String?) -> Void) {
        acp.queue.async { do { reply(try JSONEncoder().encode(self.acp.state), nil) } catch { reply(nil, error.localizedDescription) } }
    }
    func acpPrompt(text: String, reply: @escaping (String?) -> Void) {
        acp.queue.async { do { try self.acp.prompt(text); reply(nil) } catch { reply(error.localizedDescription) } }
    }
    func acpCancel(reply: @escaping (String?) -> Void) { acp.queue.async { self.acp.cancel(); reply(nil) } }
    func acpPermission(request: String, option: String, reply: @escaping (String?) -> Void) {
        acp.queue.async { do { try self.acp.choose(request: request, option: option); reply(nil) } catch { reply(error.localizedDescription) } }
    }
    func acpStop(reply: @escaping () -> Void) { acp.queue.async { self.acp.stop(); reply() } }
    func invalidate() { acp.queue.async { self.acp.stop() } }
    private let queue = DispatchQueue(label: "com.mysticcoders.volant.agent-host")
    private func run(_ arguments: [String]) throws -> Data {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [home + "/.local/bin/herdr", "/opt/homebrew/bin/herdr", "/usr/local/bin/herdr"]
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw NSError(domain: "VolantAgents", code: 1, userInfo: [NSLocalizedDescriptionKey: "Herdr was not found. Install Herdr, start a local session, then reconnect."])
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        task.currentDirectoryURL = URL(fileURLWithPath: home)
        // Do not inherit the caller's focused pane, shell startup files or provider credentials.
        task.environment = ["HOME": home, "USER": NSUserName(), "PATH": home + "/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", "LANG": "en_US.UTF-8"]
        let output = Pipe()
        task.standardOutput = output
        task.standardError = FileHandle.nullDevice
        try task.run()
        let timeout = DispatchWorkItem { if task.isRunning { task.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: timeout)
        defer { timeout.cancel() }
        var data = Data()
        while true {
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            data.append(chunk)
            if data.count > 2_000_000 {
                task.terminate()
                throw NSError(domain: "VolantAgents", code: 2, userInfo: [NSLocalizedDescriptionKey: "Herdr returned too much data."])
            }
        }
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw NSError(domain: "VolantAgents", code: 3, userInfo: [NSLocalizedDescriptionKey: "Herdr is unavailable or the session changed. Start the local default Herdr session, then reconnect."])
        }
        return data
    }
    func listAgents(reply: @escaping (Data?, String?) -> Void) {
        queue.async {
            do {
                let data = try self.run(["agent", "list"])
                _ = try AgentSession.decodeList(data)
                reply(data, nil)
            } catch { reply(nil, error.localizedDescription) }
        }
    }
    func focusAgent(paneID: String, terminalID: String, sessionIdentity: String, reply: @escaping (String?) -> Void) {
        queue.async {
            do {
                // Revalidate the current occupant; a stale UI must not focus a replacement agent.
                let agents = try AgentSession.decodeList(self.run(["agent", "list"]))
                guard agents.contains(where: { $0.paneID == paneID && $0.terminalID == terminalID && $0.sessionIdentity == sessionIdentity }),
                      !paneID.hasPrefix("-"), paneID.count < 128 else {
                    throw NSError(domain: "VolantAgents", code: 4, userInfo: [NSLocalizedDescriptionKey: "This pane has changed. Refresh and select the agent again."])
                }
                _ = try self.run(["agent", "focus", paneID])
                reply(nil)
            } catch { reply(error.localizedDescription) }
        }
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Only the signed Volant application from this team may request local automation.
        var code: SecCode?
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: connection.processIdentifier)] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code else { return false }
        var requirement: SecRequirement?
        let text = "anchor apple generic and identifier \"com.mysticcoders.vey\" and certificate leaf[subject.OU] = \"REMBT6JY4N\""
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
              let requirement, SecCodeCheckValidity(code, [], requirement) == errSecSuccess else { return false }
        connection.exportedInterface = NSXPCInterface(with: VolantAgentHostProtocol.self)
        let host = AgentHost()
        connection.exportedObject = host
        connection.invalidationHandler = { host.invalidate() }
        connection.interruptionHandler = { host.invalidate() }
        connection.resume()
        return true
    }
}
let delegate = ListenerDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
