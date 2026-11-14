import Foundation

/// The weather-only XPC helper's interface. It asks Apple's WeatherKit for a forecast and Apple's
/// geocoder for the place, replying with an encoded `WeatherReport` or a message. Its only inputs are
/// coordinates already rounded to 0.1 degrees, or a place name `WeatherQuery` accepted.
@objc public protocol VolantWeatherHostProtocol {
    /// The forecast for the owner's rounded location, labeled with the locality the geocoder names.
    func weather(latitude: Double, longitude: Double, reply: @escaping (Data?, String?) -> Void)
    /// The forecast for the first place Apple's geocoder finds for `place`.
    func weather(place: String, reply: @escaping (Data?, String?) -> Void)
}

/// What the launcher's weather command asks about: `weather` alone for where the owner is, or
/// `weather tokyo`, `weather in tokyo` and `weather for tokyo` for a place.
public enum WeatherQuery: Hashable, Sendable {
    case here
    case place(String)

    public static let keywords: Set<String> = ["weather"]
    static let joiners: Set<String> = ["in", "for", "at"]
    public static let maximumPlaceLength = 100

    /// The weather request a launcher query makes, or nil when it is not a weather query. The keyword
    /// must be the whole first word; a place may not contain control characters or exceed 100 characters.
    public static func parse(_ query: String) -> WeatherQuery? {
        var words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = words.first, keywords.contains(first.lowercased()) else { return nil }
        words.removeFirst()
        // A lone joiner is a place still being typed, so `weather in` keeps showing where the owner is.
        if let joiner = words.first, joiners.contains(joiner.lowercased()) { words.removeFirst() }
        let place = words.joined(separator: " ")
        if place.isEmpty { return .here }
        guard validPlace(place) else { return nil }
        return .place(place)
    }

    /// A place name the helper accepts: 1 to 100 characters, none of them control characters.
    public static func validPlace(_ place: String) -> Bool {
        (1...maximumPlaceLength).contains(place.count) && !place.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    /// The cache key: places compare without case or extra spaces, so `Tokyo` and `tokyo ` share one forecast.
    public var key: String {
        switch self {
        case .here: return "here"
        case .place(let place): return "place:" + place.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
    }
}

/// A forecast from the weather helper with the attribution Apple requires beside it: the Apple Weather
/// mark for light and dark backgrounds, as PNG, and the legal page it links to.
public struct WeatherReport: Codable, Hashable, Sendable {
    public static let maximumBytes = 512 * 1024
    public static let maximumMarkBytes = 128 * 1024

    public var forecast: ExtensionItemForecast
    public var legalURL: String?
    public var markLight: Data?
    public var markDark: Data?

    public init(forecast: ExtensionItemForecast, legalURL: String? = nil, markLight: Data? = nil, markDark: Data? = nil) {
        self.forecast = forecast; self.legalURL = legalURL; self.markLight = markLight; self.markDark = markDark
    }

    /// Decodes a helper reply, keeping the forecast only when it passes the same checks as an
    /// extension's, the legal link only on https at apple.com, and each mark only when it is a PNG of at
    /// most 128 KB.
    public static func decode(_ data: Data) -> WeatherReport? {
        guard data.count <= maximumBytes, let raw = try? JSONDecoder().decode(WeatherReport.self, from: data),
              let forecast = raw.forecast.sanitized() else { return nil }
        let legal = raw.legalURL.flatMap(URL.init(string:)).flatMap { url in isApple(url) ? url.absoluteString : nil }
        return WeatherReport(forecast: forecast, legalURL: legal, markLight: raw.markLight.flatMap(png), markDark: raw.markDark.flatMap(png))
    }

    /// Whether a URL is https on apple.com or one of its subdomains, the only place attribution comes from.
    public static func isApple(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == "apple.com" || host.hasSuffix(".apple.com")
    }

    static func png(_ data: Data) -> Data? {
        data.count <= maximumMarkBytes && data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) ? data : nil
    }
}
