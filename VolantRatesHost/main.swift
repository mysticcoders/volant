import Foundation
import VolantCore

/// Accepts connections from Volant and hands each one its own rates fetcher.
final class RatesServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let host = RatesHost()
        connection.exportedInterface = NSXPCInterface(with: VolantRatesHostProtocol.self)
        connection.exportedObject = host
        connection.invalidationHandler = { host.stop() }
        connection.interruptionHandler = connection.invalidationHandler
        connection.resume()
        return true
    }
}

let delegate = RatesServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
