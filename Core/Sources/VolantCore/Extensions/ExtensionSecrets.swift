import Foundation

/// A token a list extension needs for one of its hosts, such as a personal API token. The manifest
/// declares it; the owner types it once in the first-run prompt; Volant keeps it in the Keychain and the
/// fetch helper adds it as a header to requests for `host`. The module never receives it: not in a
/// request, not in a response, not in storage. Declaring one is part of the approval fingerprint.
public struct ExtensionSecret: Codable, Hashable {
    public var id: String
    public var title: String
    public var help: String?
    public var host: String
    public var header: String
    public var prefix: String?

    public init(id: String, title: String, help: String? = nil, host: String, header: String, prefix: String? = nil) {
        self.id = id; self.title = title; self.help = help; self.host = host; self.header = header; self.prefix = prefix
    }

    public static let maximumPerExtension = 4
    public static let maximumValueBytes = 8192
    /// Headers a secret may set. Anything that changes routing, caching or cookies stays out.
    public static let allowedHeaders: Set<String> = ["Authorization", "X-API-Key"]

    /// A lowercase id, a short title and help, a header from `allowedHeaders`, a printable prefix of at
    /// most 16 characters, and a host the manifest also declares.
    func isValid(hosts: [String]) -> Bool {
        (1...32).contains(id.count) && id.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber || "-_".contains($0)) }) &&
            (1...60).contains(title.count) && (help?.count ?? 0) <= 200 && hosts.contains(host) &&
            Self.allowedHeaders.contains(header) && (prefix?.count ?? 0) <= 16 &&
            (prefix ?? "").allSatisfy { $0.isASCII && !$0.isNewline && ($0 == " " || !$0.isWhitespace) }
    }

    /// Whether a value the owner typed can be sent in a header: non-empty, no whitespace or control
    /// characters, and at most `maximumValueBytes`.
    public static func isValidValue(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= maximumValueBytes && !value.contains { $0.isWhitespace || $0.isNewline || $0.asciiValue.map { $0 < 32 || $0 == 127 } == true }
    }

    /// The header a stored value becomes.
    public func headerValue(_ value: String) -> String { (prefix ?? "") + value }
}

/// One request Volant sends for an extension: a planned GET, or a POST an action submitted. Headers are
/// only those a declared secret adds; the fetch helper checks names and host again.
public struct ExtensionRequest: Equatable {
    public let url: URL
    public let method: String
    public let body: Data?
    public var headers: [String: String]

    public init(url: URL, method: String = "GET", body: Data? = nil, headers: [String: String] = [:]) {
        self.url = url; self.method = method; self.body = body; self.headers = headers
    }

    public static let methods: Set<String> = ["GET", "POST"]
    public static let maximumBodyBytes = 64 * 1024

    /// Whether the fetch helper may send this method, body and these headers. A body needs POST.
    public static func isAllowed(method: String, body: Data?, headers: [String: String]) -> Bool {
        methods.contains(method) && (body == nil || method == "POST") && (body?.count ?? 0) <= maximumBodyBytes &&
            headers.allSatisfy { ExtensionSecret.allowedHeaders.contains($0.key) && !$0.value.contains(where: \.isNewline) && $0.value.utf8.count <= 8192 }
    }
}

extension ExtensionNetwork {
    /// Requests an `action` reply asks Volant to send, with the state for the render that follows. Only
    /// POST is accepted, only to `hosts`, with at most `maximumFetches` requests and a JSON body of at
    /// most 64 KiB each. Anything else makes the whole reply malformed.
    public static func submissions(from output: String, hosts: Set<String>) throws -> (requests: [ExtensionRequest], state: String?) {
        guard let data = output.data(using: .utf8), let raw = try? JSONDecoder().decode(RawSubmission.self, from: data),
              (raw.state?.utf8.count ?? 0) <= maximumStateBytes else { throw ExtensionNetworkError.malformedPlan }
        guard raw.fetch.count <= maximumFetches else { throw ExtensionNetworkError.tooManyFetches }
        let requests = try raw.fetch.map { entry -> ExtensionRequest in
            guard entry.method == "POST" else { throw ExtensionNetworkError.malformedPlan }
            guard let url = permittedURL(entry.url, hosts: hosts) else { throw ExtensionNetworkError.hostNotAllowed(entry.url) }
            let body = try entry.json.map { value -> Data in
                let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
                return try encoder.encode(value)
            }
            guard (body?.count ?? 0) <= ExtensionRequest.maximumBodyBytes else { throw ExtensionNetworkError.malformedPlan }
            return ExtensionRequest(url: url, method: entry.method, body: body)
        }
        return (requests, raw.state)
    }

    private struct RawSubmission: Decodable {
        struct Entry: Decodable { let url: String; let method: String; let json: JSONValue? }
        let fetch: [Entry]
        let state: String?
    }
}
