import Foundation
import VolantCore

/// Accepts connections from Volant and answers each with the weather host.
final class WeatherServiceDelegate: NSObject, NSXPCListenerDelegate {
    private let host = WeatherHost()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: VolantWeatherHostProtocol.self)
        connection.exportedObject = host
        connection.resume()
        return true
    }
}

let delegate = WeatherServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
