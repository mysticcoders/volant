import Foundation
import VolantCore

/// Accepts connections from Volant and hands each one its own fetcher for network extensions.
final class FetchServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let host = FetchHost()
        connection.exportedInterface = NSXPCInterface(with: VolantFetchHostProtocol.self)
        connection.exportedObject = host
        connection.invalidationHandler = { host.stop() }
        connection.interruptionHandler = connection.invalidationHandler
        connection.resume()
        return true
    }
}

let delegate = FetchServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
