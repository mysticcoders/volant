import Foundation

/// One setting a list extension declares for the owner to choose in Settings, such as domains to hide or
/// how many rows to show. Values are the owner's own choices about the extension's output, so they give
/// it no new access: hosts, tokens and capabilities are enforced separately, and declarations are not part
/// of the approval fingerprint. Never use a preference for a password or token; declare a secret instead.
public struct ExtensionPreference: Codable, Hashable {
    public enum Kind: String, Codable, Hashable {
        case toggle, text, dropdown, number
    }

    public static let maximumTitleLength = 60
    public static let maximumDescriptionLength = 200
    public static let maximumTextLength = 1000
    public static let defaultTextLength = 200
    public static let maximumChoices = 20

    public var id: String
    public var type: Kind
    public var title: String
    public var description: String?
    public var defaultValue: JSONValue?
    /// The text field's prompt, for `text`.
    public var placeholder: String?
    /// The longest text accepted, for `text`; 200 when absent, at most 1,000.
    public var maxLength: Int?
    /// The menu's choices, for `dropdown`, using the same id and title rules as list filters.
    public var choices: [ExtensionFilter]?
    /// The allowed range, for `number`.
    public var min: Double?
    public var max: Double?

    enum CodingKeys: String, CodingKey {
        case id, type, title, description, placeholder, maxLength, choices, min, max
        case defaultValue = "default"
    }

    public init(id: String, type: Kind, title: String, description: String? = nil, defaultValue: JSONValue? = nil,
                placeholder: String? = nil, maxLength: Int? = nil, choices: [ExtensionFilter]? = nil, min: Double? = nil, max: Double? = nil) {
        self.id = id; self.type = type; self.title = title; self.description = description; self.defaultValue = defaultValue
        self.placeholder = placeholder; self.maxLength = maxLength; self.choices = choices; self.min = min; self.max = max
    }

    var textLimit: Int { maxLength ?? Self.defaultTextLength }

    /// An ASCII id of letters, digits, `-` and `_`, a one-line title, and the fields its type needs, with a
    /// default that the type itself would accept.
    public var isValid: Bool {
        guard (1...32).contains(id.count), id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_".contains($0)) }),
              (1...Self.maximumTitleLength).contains(title.count), !title.contains(where: \.isNewline),
              (description?.count ?? 0) <= Self.maximumDescriptionLength,
              (placeholder?.count ?? 0) <= ExtensionManifest.maximumPlaceholderLength else { return false }
        switch type {
        case .toggle:
            guard choices == nil, min == nil, max == nil, maxLength == nil else { return false }
        case .text:
            guard (1...Self.maximumTextLength).contains(textLimit), choices == nil, min == nil, max == nil else { return false }
        case .dropdown:
            guard let choices, (2...Self.maximumChoices).contains(choices.count), choices.allSatisfy(\.isValid),
                  Set(choices.map(\.id)).count == choices.count, min == nil, max == nil, maxLength == nil else { return false }
        case .number:
            guard let min, let max, min.isFinite, max.isFinite, min < max, choices == nil, maxLength == nil else { return false }
        }
        return defaultValue.map { accepted($0) != nil } ?? true
    }

    /// The value the extension gets when the owner hasn't chosen one: the declared default, or off, empty
    /// text, the first choice, or the minimum.
    public var fallback: JSONValue {
        if let defaultValue, let value = accepted(defaultValue) { return value }
        switch type {
        case .toggle: return .bool(false)
        case .text: return .string("")
        case .dropdown: return .string(choices?.first?.id ?? "")
        case .number: return .number(min ?? 0)
        }
    }

    /// `value` if it fits this preference as declared now, otherwise nil: a stored value from an older
    /// declaration, or one edited by hand in config.json, falls back instead of reaching the extension.
    public func accepted(_ value: JSONValue) -> JSONValue? {
        switch (type, value) {
        case (.toggle, .bool): return value
        case (.text, .string(let text)): return text.count <= textLimit && !text.contains(where: \.isNewline) ? value : nil
        case (.dropdown, .string(let choice)): return choices?.contains { $0.id == choice } == true ? value : nil
        case (.number, .number(let number)):
            guard let min, let max, number.isFinite, (min...max).contains(number) else { return nil }
            return value
        default: return nil
        }
    }
}

public enum ExtensionPreferences {
    public static let maximumCount = 12

    /// Every declared preference's value for one run: the stored value when it still fits, otherwise the
    /// fallback. Stored keys the extension no longer declares are dropped.
    public static func resolve(_ declared: [ExtensionPreference], stored: [String: JSONValue]) -> [String: JSONValue] {
        Dictionary(uniqueKeysWithValues: declared.map { preference in
            (preference.id, stored[preference.id].flatMap(preference.accepted) ?? preference.fallback)
        })
    }

    /// Whether a manifest's declarations are usable: at most 12, unique ids, each valid, and only on list
    /// extensions, which are the ones whose requests can carry them.
    public static func isValid(_ declared: [ExtensionPreference], listsItems: Bool) -> Bool {
        declared.isEmpty || (listsItems && declared.count <= maximumCount
            && Set(declared.map(\.id)).count == declared.count && declared.allSatisfy(\.isValid))
    }
}
