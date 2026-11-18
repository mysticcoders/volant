import Foundation

/// A JSON value for MCP messages (apart from the extensions' `JSONValue`, which stores every number as a double), keeping integers apart from other numbers so a JSON-RPC request id
/// of `1` is answered as `1`, not `1.0`.
public enum MCPValue: Equatable, Sendable, Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([MCPValue])
    case object([String: MCPValue])

    /// Decodes any JSON value, trying the narrowest number type first.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int.self) { self = .int(value) }
        else if let value = try? container.decode(Double.self) { self = .double(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([MCPValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: MCPValue].self)) }
    }

    /// Encodes the value as the JSON type it came from.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    public var string: String? { if case .string(let value) = self { return value } else { return nil } }
    public var object: [String: MCPValue]? { if case .object(let value) = self { return value } else { return nil } }

    /// The value as an integer, accepting a whole double such as `5.0`.
    public var int: Int? {
        switch self {
        case .int(let value): return value
        case .double(let value) where value.rounded() == value && abs(value) < 1e15: return Int(value)
        default: return nil
        }
    }

    public subscript(key: String) -> MCPValue? { object?[key] }

    /// The value as one line of compact JSON with sorted keys, for the newline-delimited stdio framing.
    public func line() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)) ?? Data("null".utf8)
    }
}
