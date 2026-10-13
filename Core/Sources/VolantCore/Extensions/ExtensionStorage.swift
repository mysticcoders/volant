import Foundation

/// A JSON value as list extensions save and receive it. Numbers decode as `Double`; object keys are
/// written sorted, so the same value always encodes to the same bytes.
public indirect enum JSONValue: Codable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// How deeply arrays and objects nest; a scalar is depth 0.
    var depth: Int {
        switch self {
        case .array(let values): return 1 + (values.map(\.depth).max() ?? 0)
        case .object(let values): return 1 + (values.values.map(\.depth).max() ?? 0)
        default: return 0
        }
    }
}

/// The rules for what a list extension may save on this Mac: one JSON object of at most 16 KB, nested
/// at most 8 levels. Volant keeps it per extension, sends it with every request, and replaces it when a
/// reply includes `storage`. Stored values are never logged; errors describe only size or shape.
public enum ExtensionStorage {
    public static let maximumBytes = 16 * 1024
    public static let maximumDepth = 8
    public static let empty = JSONValue.object([:])

    /// The canonical bytes for a value an extension asked to save, or an error explaining why not.
    public static func encode(_ value: JSONValue) throws -> Data {
        guard case .object = value else { throw ExtensionStorageError.notObject }
        guard value.depth <= maximumDepth else { throw ExtensionStorageError.tooDeep }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(value)
        guard data.count <= maximumBytes else { throw ExtensionStorageError.tooLarge(data.count) }
        return data
    }

    /// Saved bytes read back, or the empty object when they are missing or no longer valid.
    public static func decode(_ data: Data?) -> JSONValue {
        guard let data, data.count <= maximumBytes, let value = try? JSONDecoder().decode(JSONValue.self, from: data),
              case .object = value, value.depth <= maximumDepth else { return empty }
        return value
    }
}

public enum ExtensionStorageError: Error, LocalizedError, Equatable {
    case notObject, tooDeep, tooLarge(Int)
    public var errorDescription: String? {
        switch self {
        case .notObject: return "Extension tried to save something other than a JSON object. Its saved data was kept."
        case .tooDeep: return "Extension tried to save data nested more than \(ExtensionStorage.maximumDepth) levels deep. Its saved data was kept."
        case .tooLarge(let bytes): return "Extension tried to save \(bytes / 1024) KB; the limit is \(ExtensionStorage.maximumBytes / 1024) KB. Its saved data was kept."
        }
    }
}
