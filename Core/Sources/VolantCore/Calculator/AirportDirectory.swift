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
    private var zones: [String] = []
    private var airports: [String: (zone: UInt16, city: String)] = [:]

    /// `load` returns the decompressed table: one line per airport with code, IANA zone and city.
    public init(load: @escaping () -> String?) {
        self.load = load
    }

    public func lookup(_ text: String) -> Match? {
        let code = text.trimmingCharacters(in: .whitespaces).uppercased()
        guard code.count == 3, code.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        guard let airport = airports[code], let zone = TimeZone(identifier: zones[Int(airport.zone)]) else { return nil }
        return Match(zone: zone, city: airport.city, code: code)
    }

    /// Reads the table once, keeping each distinct zone name a single time: thousands of airports
    /// share a few hundred zones.
    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        var zoneIndex: [Substring: UInt16] = [:]
        for line in (load() ?? "").split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 3 else { continue }
            let zone: UInt16
            if let known = zoneIndex[fields[1]] {
                zone = known
            } else {
                zone = UInt16(clamping: zones.count)
                zoneIndex[fields[1]] = zone
                zones.append(String(fields[1]))
            }
            airports[String(fields[0])] = (zone, String(fields[2]))
        }
    }
}
