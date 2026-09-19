import Foundation
final class AIServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let host = AIHTTPHost()
        connection.exportedInterface = NSXPCInterface(with: VolantAIHostProtocol.self)
        connection.exportedObject = host
        connection.invalidationHandler = { host.stop() }
        connection.interruptionHandler = connection.invalidationHandler
        connection.resume(); return true
    }
}
let delegate = AIServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
