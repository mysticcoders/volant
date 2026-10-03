import Foundation

/// City names beyond the IANA database, from GeoNames cities over 15,000 people (CC BY 4.0). The
/// table loads on the first lookup the built-in names cannot answer, so launcher start-up and
/// ordinary searches never pay for it.
///
/// A bare name resolves only when it is unambiguous in time: every same-named city keeps the same
/// clock, or the largest is at least twice the size of any that does not. Otherwise the owner adds
/// a qualifier, a US state or a country: "Portland, ME", "Springfield MA", "Paris, France".
public final class CityDirectory {
    public struct Match: Equatable {
        public let zone: TimeZone
        public let name: String
    }

    struct Entry {
        let name: String
        let country: String
        let admin1: String
        let population: Int
        let zone: Int
    }

    /// Installed by the app with its bundled table; empty until then, as in tests and fixtures.
    public static var shared = CityDirectory(load: { nil })

    private static let countryAliases = ["uk": "GB", "usa": "US", "uae": "AE", "england": "GB", "scotland": "GB", "wales": "GB"]
    private let load: () -> String?
    private let lock = NSLock()
    private var loaded = false
    private var zones: [TimeZone?] = []
    private var entries: [Entry] = []
    /// Most names belong to one city, so a name maps straight to its entry; the few shared names
    /// map to a negative number that selects a group, which keeps the loaded table small.
    private var index: [String: Int32] = [:]
    private var groups: [[Int32]] = []
    private var clocks: [Int: [Int]] = [:]
    private lazy var countries: [String: String] = {
        let english = Locale(identifier: "en_US")
        var names = Self.countryAliases
        for region in Locale.Region.isoRegions where region.identifier.count == 2 {
            if let name = english.localizedString(forRegionCode: region.identifier) { names[Self.key(name)] = region.identifier }
            names[region.identifier.lowercased()] = region.identifier
        }
        return names
    }()

    /// `load` returns the decompressed table text: a tab-separated zone list, then one line per
    /// city with name, ASCII name, country, admin1, population and zone index.
    public init(load: @escaping () -> String?) {
        self.load = load
    }

    public func lookup(_ text: String) -> Match? {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        guard !index.isEmpty else { return nil }
        let name = Self.key(text)
        if let candidates = candidates(name) { return choose(candidates) }
        let (place, qualifier) = split(name)
        guard let place, let qualifier, let candidates = candidates(place) else { return nil }
        let upper = qualifier.uppercased()
        let inState = qualifier.count == 2 ? candidates.filter { $0.country == "US" && $0.admin1 == upper } : []
        if !inState.isEmpty { return choose(inState) }
        guard let country = countries[qualifier] else { return nil }
        let inCountry = candidates.filter { $0.country == country }
        return inCountry.isEmpty ? nil : choose(inCountry)
    }

    private func candidates(_ key: String) -> [Entry]? {
        guard let slot = index[key] else { return nil }
        return slot >= 0 ? [entries[Int(slot)]] : groups[Int(-slot - 1)].map { entries[Int($0)] }
    }

    private func add(_ key: String, entry: Int32) {
        guard !key.isEmpty else { return }
        guard let slot = index[key] else { index[key] = entry; return }
        if slot >= 0 {
            guard slot != entry else { return }
            groups.append([slot, entry])
            index[key] = -Int32(groups.count)
        } else if !groups[Int(-slot - 1)].contains(entry) {
            groups[Int(-slot - 1)].append(entry)
        }
    }

    /// Splits a trailing qualifier after the last comma, or after the last space when the rest
    /// names a known city.
    private func split(_ name: String) -> (String?, String?) {
        if let comma = name.lastIndex(of: ",") {
            return (name[..<comma].trimmingCharacters(in: .whitespaces), name[name.index(after: comma)...].trimmingCharacters(in: .whitespaces))
        }
        guard let space = name.lastIndex(of: " ") else { return (nil, nil) }
        let place = String(name[..<space])
        return index[place] == nil ? (nil, nil) : (place, String(name[name.index(after: space)...]))
    }

    /// The largest wins unless a city on a different clock is more than half its size.
    private func choose(_ candidates: [Entry]) -> Match? {
        let ranked = candidates.sorted { $0.population > $1.population }
        guard let top = ranked.first, let zone = zones[top.zone] else { return nil }
        let rivals = ranked.dropFirst().filter { clock($0.zone) != clock(top.zone) }
        guard rivals.allSatisfy({ $0.population * 2 <= top.population }) else { return nil }
        return Match(zone: zone, name: top.name)
    }

    /// Offsets in mid-January and mid-July, so zones with different names but the same clock
    /// count as one.
    private func clock(_ index: Int) -> [Int] {
        if let cached = clocks[index] { return cached }
        let year = Calendar(identifier: .gregorian).component(.year, from: Date())
        let samples = [1, 7].compactMap { DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(identifier: "UTC"),
                                                        year: year, month: $0, day: 15).date }
        let offsets = samples.map { zones[index]?.secondsFromGMT(for: $0) ?? Int.min }
        clocks[index] = offsets
        return offsets
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let text = load() else { return }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard !lines.isEmpty else { return }
        zones = lines.removeFirst().split(separator: "\t").map { TimeZone(identifier: String($0)) }
        for line in lines {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 6, let population = Int(fields[4]), let zone = Int(fields[5]), zones.indices.contains(zone) else { continue }
            let position = Int32(entries.count)
            entries.append(Entry(name: String(fields[0]), country: String(fields[2]), admin1: String(fields[3]), population: population, zone: zone))
            add(Self.tableKey(fields[0]), entry: position)
            if !fields[1].isEmpty { add(Self.tableKey(fields[1]), entry: position) }
        }
    }

    /// Table names are single-spaced and mostly ASCII, so only the rest pay for accent folding.
    private static func tableKey(_ field: Substring) -> String {
        guard field.utf8.allSatisfy({ $0 < 128 }) else { return key(String(field)) }
        let lowered = field.lowercased()
        return lowered.contains(".") ? key(lowered) : lowered
    }

    /// Case, accents, periods and extra spaces never matter: "St. Louis", "st louis" and "Kraków",
    /// "krakow" match.
    static func key(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: ".", with: "")
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
