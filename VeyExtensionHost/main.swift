import Foundation

/// The extension host is a separate, sandboxed process with no entitlements beyond the sandbox itself.
/// It has no network, no file access outside its container, and no UI. A misbehaving module can only
/// hurt this process, and a watchdog kills the process if a run overstays its timeout.
final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: VeyExtensionHostProtocol.self)
        connection.remoteObjectInterface = NSXPCInterface(with: VeyCapabilityClientProtocol.self)
        connection.exportedObject = ExtensionHost(connection: connection)
        connection.resume()
        return true
    }
}

let delegate = ServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
