import Foundation

/// Where the owner is, as a list extension may receive it: rounded to 0.1 degrees (about 11 km of
/// latitude) so it locates a town, not a house. Only an extension whose manifest declares the
/// `location` permission and that the owner allowed gets it, and Volant never stores or logs it.
public struct ExtensionLocation: Codable, Equatable {
    public let latitude: Double
    public let longitude: Double

    /// Rounds raw coordinates to one decimal place; nil for coordinates outside the globe.
    public init?(latitude: Double, longitude: Double) {
        guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        self.latitude = (latitude * 10).rounded() / 10
        self.longitude = (longitude * 10).rounded() / 10
    }

    public static let permission = "location"
}

/// Extensions the owner allowed to receive their approximate location, kept as `extensionLocation` in
/// config.json. Unlike hosts, a grant belongs to one extension and is never shared. Writes patch only
/// that key and preserve every other field. The list is per Mac and is not synced through iCloud.
public enum ExtensionLocationApprovals {
    public static let key = "extensionLocation"

    public static func approved(at url: URL) -> Set<String> {
        guard let object = try? read(url), let ids = object[key] as? [String] else { return [] }
        return Set(ids)
    }

    /// Whether this extension declares the location permission and the owner has not allowed it yet.
    public static func missing(_ manifest: ExtensionManifest, at url: URL) -> Bool {
        manifest.wantsLocation && !approved(at: url).contains(manifest.id)
    }

    public static func approve(_ id: String, at url: URL) throws { try write(at: url) { $0.union([id]) } }
    public static func remove(_ id: String, at url: URL) throws { try write(at: url) { $0.subtracting([id]) } }

    private static func write(at url: URL, _ change: (Set<String>) -> Set<String>) throws {
        var object = try read(url)
        object[key] = change(Set(object[key] as? [String] ?? [])).sorted()
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }

    private static func read(_ url: URL) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
              object[key] == nil || object[key] is [String] else { throw CocoaError(.fileReadCorruptFile) }
        return object
    }
}
