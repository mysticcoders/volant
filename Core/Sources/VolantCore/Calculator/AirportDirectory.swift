import Foundation

/// IATA airport codes and their time zones, from mwgg/Airports (MIT): "time in JFK",
/// "3pm LAX in LHR". Loaded on the first code the city names cannot answer, so a three-letter
/// city such as Nice stays the city.
public final class AirportDirectory {
    public struct Match: Equatable {
        public let zone: TimeZone
        public let city: String
        public let code: String
    }

    /// Installed by the app with its bundled table; empty until then, as in tests and fixtures.
    public static var shared = AirportDirectory(load: { nil })

    private let load: () -> String?
    private let lock = NSLock()
    private var loaded = false
    private var airports: [String: (zone: String, city: String)] = [:]

    /// `load` returns the decompressed table: one line per airport with code, IANA zone and city.
    public init(load: @escaping () -> String?) {
        self.load = load
    }

    public func lookup(_ text: String) -> Match? {
        let code = text.trimmingCharacters(in: .whitespaces).uppercased()
        guard code.count == 3, code.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if !loaded {
            loaded = true
            for line in (load() ?? "").split(separator: "\n") {
                let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard fields.count == 3 else { continue }
                airports[String(fields[0])] = (String(fields[1]), String(fields[2]))
            }
        }
        guard let airport = airports[code], let zone = TimeZone(identifier: airport.zone) else { return nil }
        return Match(zone: zone, city: airport.city, code: code)
    }
}
