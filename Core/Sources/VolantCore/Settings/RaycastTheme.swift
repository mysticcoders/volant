import Foundation

/// A Raycast theme as Raycast's Theme Studio and themes.ray.so share it: a downloaded JSON file,
/// or a `raycast://theme?…` link (also accepted on themes.ray.so) whose `colors` parameter lists
/// the twelve colors in a fixed order. Parsing only decodes what the owner opened or pasted; a
/// themes.ray.so link that names a theme without its colors is refused rather than fetched.
public struct RaycastTheme: Equatable {
    public static let maximumBytes = 65_536
    public static let maximumNameLength = 80
    /// Raycast's color keys in the order its links list them.
    public static let colorKeys = ["background", "backgroundSecondary", "text", "selection", "loader",
                                   "red", "orange", "yellow", "green", "blue", "purple", "magenta"]

    public var name: String
    public var author: String?
    public var mode: ColorTheme.Mode
    /// `#rrggbb` colors keyed by Raycast's names.
    public var colors: [String: String]

    public enum ParseError: LocalizedError, Equatable {
        case tooLarge, notATheme, missingColors, invalidColor(String), shareLinkWithoutColors

        public var errorDescription: String? {
            switch self {
            case .tooLarge: return "That theme is larger than a Raycast theme can be."
            case .notATheme: return "That isn’t a Raycast theme. Use a theme JSON file, or a theme link from Raycast or themes.ray.so."
            case .missingColors: return "That Raycast theme is missing a name, appearance or one of its twelve colors."
            case .invalidColor(let key): return "That Raycast theme’s \(key) color isn’t a hex color."
            case .shareLinkWithoutColors:
                return "That themes.ray.so link names a theme without its colors, and Volant doesn’t download themes. On themes.ray.so choose Download JSON or Copy JSON, then import that."
            }
        }
    }

    public init(name: String, author: String?, mode: ColorTheme.Mode, colors: [String: String]) {
        self.name = name
        self.author = author
        self.mode = mode
        self.colors = colors
    }

    /// Reads pasted text: JSON when it starts with a brace, otherwise a theme link.
    public static func parse(_ text: String) throws -> RaycastTheme {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count <= maximumBytes else { throw ParseError.tooLarge }
        if trimmed.hasPrefix("{") { return try parse(json: Data(trimmed.utf8)) }
        return try parse(link: trimmed)
    }

    /// Reads a theme JSON file: `name`, `appearance`, optional `author` and a `colors` object.
    public static func parse(json data: Data) throws -> RaycastTheme {
        guard data.count <= maximumBytes else { throw ParseError.tooLarge }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ParseError.notATheme }
        guard let colors = object["colors"] as? [String: Any] else { throw ParseError.missingColors }
        var values: [String: String] = [:]
        for key in colorKeys {
            guard let value = colors[key] as? String else { throw ParseError.missingColors }
            values[key] = value
        }
        return try make(name: object["name"] as? String, author: object["author"] as? String,
                        appearance: object["appearance"] as? String, colors: values)
    }

    /// Reads a `raycast://theme?…` link, or the same query on themes.ray.so or ray.so/themes.
    public static func parse(link: String) throws -> RaycastTheme {
        guard link.utf8.count <= maximumBytes, let components = URLComponents(string: link),
              let scheme = components.scheme?.lowercased() else { throw ParseError.notATheme }
        let host = components.host?.lowercased() ?? ""
        let isRaycast = scheme.hasPrefix("raycast") && host == "theme"
        let isWeb = scheme == "https" && (host == "themes.ray.so" || (host == "ray.so" && components.path.hasPrefix("/themes")))
        guard isRaycast || isWeb else { throw ParseError.notATheme }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard let list = value("colors") else {
            if isWeb { throw ParseError.shareLinkWithoutColors }
            throw ParseError.missingColors
        }
        let parts = list.split(separator: ",", omittingEmptySubsequences: false).map { String($0) }
        guard parts.count == colorKeys.count else { throw ParseError.missingColors }
        return try make(name: value("name"), author: value("author"), appearance: value("appearance"),
                        colors: Dictionary(uniqueKeysWithValues: zip(colorKeys, parts)))
    }

    /// Validates fields and normalizes colors to lowercase `#rrggbb`, dropping a legacy alpha byte.
    private static func make(name: String?, author: String?, appearance: String?, colors: [String: String]) throws -> RaycastTheme {
        let trimmedName = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, let appearance, let mode = ColorTheme.Mode(rawValue: appearance.lowercased()) else {
            throw ParseError.missingColors
        }
        var normalized: [String: String] = [:]
        for key in colorKeys {
            guard let hex = colors[key].flatMap(normalize) else { throw ParseError.invalidColor(key) }
            normalized[key] = hex
        }
        let cleanAuthor = author?.trimmingCharacters(in: .whitespacesAndNewlines)
        return RaycastTheme(name: String(trimmedName.prefix(maximumNameLength)),
                            author: cleanAuthor?.isEmpty == false ? String(cleanAuthor!.prefix(maximumNameLength)) : nil,
                            mode: mode, colors: normalized)
    }

    /// Six hex digits with an optional leading `#`, or eight with a trailing alpha byte that is dropped.
    private static func normalize(_ value: String) -> String? {
        let digits = value.trimmingCharacters(in: .whitespaces).drop { $0 == "#" }
        guard digits.count == 6 || digits.count == 8, digits.allSatisfy(\.isHexDigit) else { return nil }
        return "#" + digits.prefix(6).lowercased()
    }

    /// The Volant palette for this theme. Raycast has no secondary text, accent or separator, and
    /// draws its selection translucently, so those roles are derived: secondary text and selection
    /// are blended toward the background as far as text stays at WCAG AA, the accent is the first
    /// of blue, purple, magenta, green, orange, red and yellow that reaches 3:1, and the separator is
    /// a faint mix of text into the background.
    public var palette: ColorPalette {
        let c = colors
        let background = c["background"]!, text = c["text"]!
        let secondary = [0.4, 0.3, 0.2, 0.1].lazy.map { Self.blend(text, background, $0) }
            .first { (ColorPalette.contrast($0, background) ?? 0) >= 4.5 } ?? text
        let selection = [1.0, 0.7, 0.5, 0.35, 0.25, 0.15].lazy.map { Self.blend(background, c["selection"]!, $0) }
            .first { (ColorPalette.contrast(text, $0) ?? 0) >= 4.5 } ?? Self.blend(background, c["selection"]!, 0.1)
        let accent = ["blue", "purple", "magenta", "green", "orange", "red", "yellow"].lazy.compactMap { c[$0] }
            .first { (ColorPalette.contrast($0, background) ?? 0) >= 3 } ?? text
        return ColorPalette(background: background, secondaryBackground: c["backgroundSecondary"]!, text: text,
                            secondaryText: secondary, selection: selection, accent: accent,
                            separator: Self.blend(background, text, 0.15), red: c["red"]!, orange: c["orange"]!,
                            yellow: c["yellow"]!, green: c["green"]!, blue: c["blue"]!, purple: c["purple"]!)
    }

    /// The color a fraction `amount` of the way from `from` to `to`, in sRGB.
    static func blend(_ from: String, _ to: String, _ amount: Double) -> String {
        guard let a = ColorPalette.components(from), let b = ColorPalette.components(to) else { return from }
        func channel(_ x: Double, _ y: Double) -> Int { Int(((x + (y - x) * amount) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", channel(a.red, b.red), channel(a.green, b.green), channel(a.blue, b.blue))
    }

    /// The theme as stored in config.json, identified by its name.
    public var customTheme: CustomColorTheme {
        CustomColorTheme(id: CustomColorTheme.identifier(for: name), name: name, mode: mode, palette: palette,
                         source: "raycast", author: author)
    }
}

/// An imported color theme kept in the appearance block's `customThemes` list.
public struct CustomColorTheme: Codable, Equatable, Identifiable {
    public static let maximumCount = 50
    public var id: String
    public var name: String
    public var mode: ColorTheme.Mode
    public var palette: ColorPalette
    public var source: String?
    public var author: String?

    public init(id: String, name: String, mode: ColorTheme.Mode, palette: ColorPalette, source: String? = nil, author: String? = nil) {
        self.id = id
        self.name = name
        self.mode = mode
        self.palette = palette
        self.source = source
        self.author = author
    }

    /// `custom-` and a lowercase slug of the name, so re-importing a theme replaces it.
    public static func identifier(for name: String) -> String {
        let slug = name.lowercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) && $0.isASCII ? String($0) : "-" }
            .joined().split(separator: "-").joined(separator: "-")
        return "custom-" + (slug.isEmpty ? "theme" : String(slug.prefix(56)))
    }

    /// Whether the entry can be shown: a custom identifier, a name and a valid palette.
    public var isValid: Bool {
        id.hasPrefix("custom-") && !name.trimmingCharacters(in: .whitespaces).isEmpty && palette.isValid
    }

    public var colorTheme: ColorTheme { ColorTheme(id: id, name: name, mode: mode, palette: palette) }
}
