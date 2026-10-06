import Foundation
import VolantCore

/// Asks the embedded rates helper for the ECB feed once and reports what came back.
let connection = NSXPCConnection(serviceName: "com.mysticcoders.volant.RatesHost")
connection.remoteObjectInterface = NSXPCInterface(with: VolantRatesHostProtocol.self)
connection.resume()
let proxy = connection.remoteObjectProxyWithErrorHandler { error in
    print("Rates XPC failed: \(error.localizedDescription)"); exit(1)
} as! VolantRatesHostProtocol
proxy.fetchRates { data, error in
    guard let data, let rates = CurrencyRates.parse(data) else { print("Rates fetch failed: \(error ?? "invalid feed")"); exit(1) }
    print("Rates XPC: \(rates.perEuro.count) currencies for \(rates.date); \(data.count) bytes")
    exit(0)
}
DispatchQueue.main.asyncAfter(deadline: .now() + 45) { print("Rates XPC timed out"); exit(1) }
dispatchMain()
