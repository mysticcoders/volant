import Foundation

/// A tool Volant offers to AI apps over MCP. Its handler runs the same code the launcher and Settings
/// use; the session only validates the request around it.
public struct MCPTool: Sendable {
    public let name: String
    public let title: String
    public let description: String
    public let inputSchema: MCPValue
    public let readOnly: Bool
    public let destructive: Bool
    public let idempotent: Bool
    public let call: @Sendable ([String: MCPValue]) async -> MCPToolResult

    public init(name: String, title: String, description: String, inputSchema: MCPValue, readOnly: Bool,
                destructive: Bool = false, idempotent: Bool = false, call: @escaping @Sendable ([String: MCPValue]) async -> MCPToolResult) {
        self.name = name
        self.title = title
        self.description = description
        self.inputSchema = inputSchema
        self.readOnly = readOnly
        self.destructive = destructive
        self.idempotent = idempotent
        self.call = call
    }

    /// An input schema for a tool without parameters, as the spec recommends.
    public static let noArguments: MCPValue = .object(["type": .string("object"), "additionalProperties": .bool(false)])

    /// An object schema with the given properties, of which `required` must be present.
    public static func schema(_ properties: [String: MCPValue], required: [String] = []) -> MCPValue {
        .object(["type": .string("object"), "properties": .object(properties), "required": .array(required.map(MCPValue.string)),
                 "additionalProperties": .bool(false)])
    }

    /// A string property with a description, and optionally a length limit.
    public static func string(_ description: String, maxLength: Int? = nil) -> MCPValue {
        var property: [String: MCPValue] = ["type": .string("string"), "description": .string(description)]
        if let maxLength { property["maxLength"] = .int(maxLength) }
        return .object(property)
    }

    /// An integer property with a description and bounds.
    public static func integer(_ description: String, minimum: Int, maximum: Int) -> MCPValue {
        .object(["type": .string("integer"), "description": .string(description), "minimum": .int(minimum), "maximum": .int(maximum)])
    }

    /// The tool as `tools/list` describes it.
    var listing: MCPValue {
        .object(["name": .string(name), "title": .string(title), "description": .string(description), "inputSchema": inputSchema,
                 "annotations": .object(["title": .string(title), "readOnlyHint": .bool(readOnly), "destructiveHint": .bool(destructive),
                                         "idempotentHint": .bool(idempotent), "openWorldHint": .bool(false)])])
    }
}

/// What a tool returns: text for the model, the same data structured when there is any, and whether
/// the call failed in a way the model can correct.
public struct MCPToolResult: Equatable, Sendable {
    public var text: String
    public var structured: MCPValue?
    public var isError: Bool

    public init(text: String, structured: MCPValue? = nil, isError: Bool = false) {
        self.text = text
        self.structured = structured
        self.isError = isError
    }

    /// A result carrying data, with the same JSON as its text, as the spec asks for compatibility.
    public static func data(_ value: MCPValue) -> MCPToolResult {
        MCPToolResult(text: String(decoding: value.line(), as: UTF8.self), structured: value)
    }

    /// A tool execution error the model can act on.
    public static func failure(_ message: String) -> MCPToolResult {
        MCPToolResult(text: message, isError: true)
    }
}

/// The resources a session offers: `resources/list` pages, `resources/read` contents, and URI
/// templates. Each listing and content block is already in the spec's shape.
public struct MCPResources: Sendable {
    public var list: @Sendable (_ cursor: String?) async -> (resources: [MCPValue], nextCursor: String?)
    /// The contents for a URI, or nil when no such resource exists.
    public var read: @Sendable (_ uri: String) async -> [MCPValue]?
    public var templates: [MCPValue]

    public init(list: @escaping @Sendable (String?) async -> (resources: [MCPValue], nextCursor: String?),
                read: @escaping @Sendable (String) async -> [MCPValue]?, templates: [MCPValue] = []) {
        self.list = list
        self.read = read
        self.templates = templates
    }
}

/// Why Volant refuses every request on a connection: the server was turned off, or the owner
/// disconnected this app in Settings. Codes are outside JSON-RPC's reserved range, as the spec asks.
public struct MCPRefusal: Equatable, Sendable {
    public let code: Int
    public let message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }

    public static let serverOff = MCPRefusal(code: -31001, message: "Volant's MCP server is off. Turn it on in Volant Settings › AI › Connected Apps.")
    public static let disconnected = MCPRefusal(code: -31002, message: "This app was disconnected in Volant Settings › AI › Connected Apps.")
}

/// One MCP connection, as a dual-era server: requests carrying `_meta` with a modern protocol version
/// (2026-07-28) are served statelessly, and an `initialize` handshake selects legacy semantics
/// (2025-11-25 and earlier) for the rest of the connection. It handles one newline-delimited message
/// at a time and returns the line to send back, or nil for notifications and stray responses.
public final class MCPSession {
    public static let modernVersions = ["2026-07-28"]
    public static let legacyVersions = ["2025-11-25", "2025-06-18", "2025-03-26"]
    /// Longer lines are refused unread.
    public static let maximumLineBytes = 1_048_576
    /// Tool calls allowed per connection in any `rateWindow`, as the spec asks servers to rate limit.
    public static let rateLimit = 30
    public static let rateWindow: TimeInterval = 10

    private let version: String
    private let instructions: String
    private let tools: () -> [MCPTool]
    private let resources: () -> MCPResources?
    private let refusal: () -> MCPRefusal?
    private let clock: () -> Date
    private var legacyVersion: String?
    private var recentCalls: [Date] = []

    /// `tools` returns the tools the owner shares right now; `refusal` says whether to refuse
    /// everything, and both are read on every request so a Settings change applies at once.
    public init(version: String, instructions: String, tools: @escaping () -> [MCPTool], resources: @escaping () -> MCPResources? = { nil },
                refusal: @escaping () -> MCPRefusal? = { nil }, clock: @escaping () -> Date = Date.init) {
        self.version = version
        self.instructions = instructions
        self.tools = tools
        self.resources = resources
        self.refusal = refusal
        self.clock = clock
    }

    /// Handles one message and returns its reply line, without the trailing newline.
    public func handle(_ line: Data) async -> Data? {
        guard line.count <= Self.maximumLineBytes else { return error(id: .null, code: -32700, message: "Message too large") }
        guard let message = try? JSONDecoder().decode(MCPValue.self, from: line), let fields = message.object else {
            return error(id: .null, code: -32700, message: "Parse error")
        }
        if fields["method"] == nil, fields["result"] != nil || fields["error"] != nil { return nil }
        let id = fields["id"]
        guard fields["jsonrpc"]?.string == "2.0", let method = fields["method"]?.string else {
            return error(id: id ?? .null, code: -32600, message: "Invalid request")
        }
        guard let id, id != .null else {
            if method == "notifications/initialized" { legacyVersion = legacyVersion ?? Self.legacyVersions[0] }
            return nil
        }
        return await request(id: id, method: method, params: fields["params"])
    }

    /// Routes one request after settling its protocol era.
    private func request(id: MCPValue, method: String, params: MCPValue?) async -> Data {
        switch id {
        case .string, .int: break
        default: return error(id: .null, code: -32600, message: "Request ids must be strings or integers")
        }
        if let refused = refusal() { return error(id: id, code: refused.code, message: refused.message) }
        if method == "initialize" { return initialize(id: id, params: params) }
        let meta = params?["_meta"]?.object
        let modern: Bool
        if let requested = meta?["io.modelcontextprotocol/protocolVersion"]?.string {
            guard Self.modernVersions.contains(requested) else {
                return error(id: id, code: -32022, message: "Unsupported protocol version",
                             data: .object(["supported": .array((Self.modernVersions + Self.legacyVersions).map(MCPValue.string)),
                                            "requested": .string(requested)]))
            }
            guard meta?["io.modelcontextprotocol/clientCapabilities"]?.object != nil else {
                return error(id: id, code: -32602, message: "Missing _meta io.modelcontextprotocol/clientCapabilities")
            }
            modern = true
        } else if legacyVersion != nil {
            modern = false
        } else {
            return error(id: id, code: -32602, message: "Missing _meta io.modelcontextprotocol/protocolVersion. Volant supports "
                         + (Self.modernVersions + Self.legacyVersions).joined(separator: ", ") + ".")
        }
        switch method {
        case "server/discover":
            return result(id: id, modern: modern, [
                "supportedVersions": .array(Self.modernVersions.map(MCPValue.string)),
                "capabilities": capabilities(legacy: false),
                "instructions": .string(instructions)
            ])
        case "ping":
            return result(id: id, modern: modern, [:])
        case "tools/list":
            return result(id: id, modern: modern, ["tools": .array(tools().map(\.listing))])
        case "tools/call":
            return await call(id: id, modern: modern, params: params)
        case "resources/list", "resources/read", "resources/templates/list":
            guard let resources = resources() else { return error(id: id, code: -32601, message: "Method not found: \(method)") }
            return await resource(method, id: id, modern: modern, params: params, resources: resources)
        default:
            return error(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    /// Answers the legacy handshake with the client's version when Volant speaks it, else the newest
    /// legacy version, and remembers it for the rest of the connection.
    private func initialize(id: MCPValue, params: MCPValue?) -> Data {
        let requested = params?["protocolVersion"]?.string ?? ""
        let chosen = Self.legacyVersions.contains(requested) ? requested : Self.legacyVersions[0]
        legacyVersion = chosen
        return result(id: id, modern: false, [
            "protocolVersion": .string(chosen),
            "capabilities": capabilities(legacy: true),
            "serverInfo": serverInfo,
            "instructions": .string(instructions)
        ])
    }

    /// Runs a tool after checking its name, its arguments' shape and the rate limit.
    private func call(id: MCPValue, modern: Bool, params: MCPValue?) async -> Data {
        guard let name = params?["name"]?.string, let tool = tools().first(where: { $0.name == name }) else {
            return error(id: id, code: -32602, message: "Unknown tool: \(params?["name"]?.string ?? "")")
        }
        let arguments: [String: MCPValue]
        switch params?["arguments"] {
        case nil, .null?: arguments = [:]
        case .object(let value)?: arguments = value
        default: return error(id: id, code: -32602, message: "Tool arguments must be an object")
        }
        let now = clock()
        recentCalls = recentCalls.filter { now.timeIntervalSince($0) < Self.rateWindow }
        let outcome: MCPToolResult
        if recentCalls.count >= Self.rateLimit {
            outcome = .failure("Too many Volant tool calls at once. Wait a few seconds and try again.")
        } else {
            recentCalls.append(now)
            outcome = await tool.call(arguments)
        }
        var fields: [String: MCPValue] = ["content": .array([.object(["type": .string("text"), "text": .string(outcome.text)])]),
                                           "isError": .bool(outcome.isError)]
        if let structured = outcome.structured { fields["structuredContent"] = structured }
        return result(id: id, modern: modern, fields)
    }

    /// Tools always; resources while the owner shares them.
    private func capabilities(legacy: Bool) -> MCPValue {
        var fields: [String: MCPValue] = ["tools": legacy ? .object(["listChanged": .bool(false)]) : .object([:])]
        if resources() != nil { fields["resources"] = .object([:]) }
        return .object(fields)
    }

    /// Lists, reads or lists templates. An unknown resource is `-32602` in 2026-07-28 and `-32002`
    /// in the legacy revisions, and never an empty `contents`.
    private func resource(_ method: String, id: MCPValue, modern: Bool, params: MCPValue?, resources: MCPResources) async -> Data {
        switch method {
        case "resources/list":
            let page = await resources.list(params?["cursor"]?.string)
            var fields: [String: MCPValue] = ["resources": .array(page.resources)]
            if let next = page.nextCursor { fields["nextCursor"] = .string(next) }
            return result(id: id, modern: modern, fields)
        case "resources/templates/list":
            return result(id: id, modern: modern, ["resourceTemplates": .array(resources.templates)])
        default:
            guard let uri = params?["uri"]?.string, !uri.isEmpty else { return error(id: id, code: -32602, message: "Missing resource uri") }
            guard let contents = await resources.read(uri), !contents.isEmpty else {
                return error(id: id, code: modern ? -32602 : -32002, message: "Resource not found", data: .object(["uri": .string(uri)]))
            }
            return result(id: id, modern: modern, ["contents": .array(contents)])
        }
    }

    private var serverInfo: MCPValue { .object(["name": .string("Volant"), "version": .string(version)]) }

    /// A result line, marked complete, naming the server in `_meta` for modern requests.
    private func result(id: MCPValue, modern: Bool, _ fields: [String: MCPValue]) -> Data {
        var body = fields
        body["resultType"] = .string("complete")
        if modern { body["_meta"] = .object(["io.modelcontextprotocol/serverInfo": serverInfo]) }
        return MCPValue.object(["jsonrpc": .string("2.0"), "id": id, "result": .object(body)]).line()
    }

    /// An error line.
    private func error(id: MCPValue, code: Int, message: String, data: MCPValue? = nil) -> Data {
        var body: [String: MCPValue] = ["code": .int(code), "message": .string(message)]
        if let data { body["data"] = data }
        return MCPValue.object(["jsonrpc": .string("2.0"), "id": id, "error": .object(body)]).line()
    }
}

/// Names and paths the app and its `volant-mcp` bridge agree on.
public enum MCPEndpoint {
    /// The app group both sign with; its container holds the socket.
    public static let appGroup = "REMBT6JY4N.com.mysticcoders.volant"
    /// The bridge's code signing identifier, which the app requires of every peer.
    public static let bridgeIdentifier = "com.mysticcoders.volant.mcp"
    /// The bridge's first line names its client: `{"volantBridge":1,"client":"claude-code"}`.
    public static let handshakeVersion = 1

    /// The socket's file name for an app, kept short because Unix socket paths are limited to 104
    /// bytes. Volant Dev and the release app share the app group, so each has its own name.
    public static func socketName(appBundleID: String) -> String {
        appBundleID == "com.mysticcoders.volant" ? "mcp" : "mcp-dev"
    }

    /// A client name from a bridge's `--client`, lowercased, or nil when it isn't 1 to 40 ASCII letters,
    /// digits and hyphens.
    public static func clientName(_ raw: String) -> String? {
        let name = raw.lowercased()
        guard (1...40).contains(name.count), name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { return nil }
        return name
    }
}
