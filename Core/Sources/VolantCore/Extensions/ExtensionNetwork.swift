import Foundation

/// Network extensions never touch the network themselves. A run has two phases, each a separate,
/// ordinary invocation of the module with a JSON request as its input:
///
/// 1. `plan`: the module receives the query and returns `{"fetch": [url, …]}`, optionally with a
///    `state` string for the render that follows.
/// 2. `render`: Volant fetches the permitted URLs through its fetch helper and runs the module again
///    with the responses, the current time and that `state`; the module returns `{"items": […]}`. A
///    render may instead return another `{"fetch", "state"}`, for a lookup that needs one answer before
///    it can ask the next question, up to `maximumRounds` fetches in one run.
///
/// A URL is permitted only when it is https on the default port, carries no credentials, and its host
/// is one the manifest declares and the owner approved. Every request also says which measurement
/// system the owner uses. The plan, responses and items pass through `ExtensionLimits`.
public enum ExtensionNetwork {
    public static let maximumHosts = 8
    public static let maximumFetches = 4
    public static let maximumResponseBytes = 512 * 1024
    public static let maximumRounds = 3
    public static let maximumStateBytes = 4096
    public static let maximumItems = 100
    public static let maximumURLLength = 2048

    /// An exact, lowercase DNS hostname with at least two labels: no scheme, port, path, wildcard or IP literal.
    public static func isValidHost(_ host: String) -> Bool {
        guard (4...253).contains(host.count), host == host.lowercased() else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.last?.allSatisfy(\.isLetter) == true else { return false }
        return labels.allSatisfy { label in
            (1...63).contains(label.count) && label.first != "-" && label.last != "-" &&
                label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }

    /// The URL a plan asked for, if Volant may fetch it for an extension allowed to reach `hosts`.
    public static func permittedURL(_ string: String, hosts: Set<String>) -> URL? {
        guard string.count <= maximumURLLength, let components = URLComponents(string: string),
              components.scheme == "https", components.user == nil, components.password == nil,
              components.port == nil || components.port == 443, components.fragment == nil,
              let host = components.host?.lowercased(), hosts.contains(host),
              let url = components.url else { return nil }
        return url
    }

    /// The URLs from a plan's output, in order. Throws when the plan is malformed, asks for too many
    /// URLs, or names any URL outside `hosts`, rather than silently dropping it.
    public static func plannedURLs(from output: String, hosts: Set<String>) throws -> [URL] {
        try plannedFetch(from: output, hosts: hosts).urls
    }

    /// One round of fetching: the permitted URLs and the state to hand the render that follows.
    public struct Fetch: Equatable {
        public let urls: [URL]
        public let state: String?
    }

    /// The URLs and state from a plan, or from a render that asks for another round. A state longer
    /// than `maximumStateBytes` makes the whole plan malformed.
    public static func plannedFetch(from output: String, hosts: Set<String>) throws -> Fetch {
        guard let data = output.data(using: .utf8), let plan = try? JSONDecoder().decode(Plan.self, from: data),
              (plan.state?.utf8.count ?? 0) <= maximumStateBytes else {
            throw ExtensionNetworkError.malformedPlan
        }
        guard plan.fetch.count <= maximumFetches else { throw ExtensionNetworkError.tooManyFetches }
        let urls = try plan.fetch.map { requested in
            guard let url = permittedURL(requested, hosts: hosts) else { throw ExtensionNetworkError.hostNotAllowed(requested) }
            return url
        }
        return Fetch(urls: urls, state: plan.state)
    }

    /// "us" when the owner's system uses US customary units, otherwise "metric". The United Kingdom's
    /// mixed system reads as metric, since its weather and most measures are.
    public static func units(for locale: Locale = .current) -> String {
        locale.measurementSystem == .us ? "us" : "metric"
    }

    /// The JSON a module receives. `responses` is absent in the plan phase. Extensions that use
    /// storage also get their saved object, and the `action` and `opened` phases name the row and action.
    public static func request(phase: String, query: String, now: Date, responses: [Response]? = nil,
                               storage: JSONValue? = nil, action: String? = nil, item: ExtensionItem? = nil,
                               state: String? = nil, units: String = units()) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let body = Request(phase: phase, query: query, now: Int(now.timeIntervalSince1970), responses: responses,
                           storage: storage, action: action, item: item, state: state, units: units)
        return String(decoding: try encoder.encode(body), as: UTF8.self)
    }

    /// A reply that may carry rows, data to save, or both. Missing parts are nil; a reply with neither,
    /// or that is not JSON, is malformed.
    public struct Reply: Equatable {
        public var items: [ExtensionItem]?
        public var storage: JSONValue?
    }

    public static func reply(from output: String) throws -> Reply {
        guard let data = output.data(using: .utf8), let raw = try? JSONDecoder().decode(RawReply.self, from: data),
              raw.items != nil || raw.storage != nil else { throw ExtensionNetworkError.malformedItems }
        return Reply(items: raw.items.map { Array($0.prefix(maximumItems)).compactMap { $0.sanitized() } }, storage: raw.storage)
    }

    /// The rows a render returned, trimmed to the launcher's limits. Links other than http and https
    /// are dropped so a row can never open another scheme.
    public static func items(from output: String) throws -> [ExtensionItem] {
        guard let data = output.data(using: .utf8), let list = try? JSONDecoder().decode(ItemList.self, from: data) else {
            throw ExtensionNetworkError.malformedItems
        }
        return list.items.prefix(maximumItems).compactMap { $0.sanitized() }
    }

    private struct Plan: Decodable { let fetch: [String]; let state: String? }
    private struct ItemList: Decodable { let items: [ExtensionItem] }
    private struct RawReply: Decodable { let items: [ExtensionItem]?; let storage: JSONValue? }
    private struct Request: Encodable {
        let phase: String
        let query: String
        let now: Int
        let responses: [Response]?
        let storage: JSONValue?
        let action: String?
        let item: ExtensionItem?
        let state: String?
        let units: String
    }

    /// One fetched URL as the module sees it. A failed fetch has status 0 and an empty body.
    public struct Response: Codable, Equatable {
        public let url: String
        public let status: Int
        public let body: String
        public init(url: String, status: Int, body: String) { self.url = url; self.status = status; self.body = body }
    }
}

/// One row a list extension returns: Return opens `url`, Command-Return opens `secondaryURL`. A row
/// may offer `actions` in its Actions menu, and `onOpen` asks Volant to tell the extension after Return
/// opens the link; both run the module again with its saved data, never fetching.
public struct ExtensionItem: Codable, Hashable {
    public var title: String
    public var subtitle: String?
    public var url: String?
    public var secondaryURL: String?
    public var secondaryTitle: String?
    public var actions: [ExtensionItemAction]?
    public var onOpen: Bool?

    public init(title: String, subtitle: String? = nil, url: String? = nil, secondaryURL: String? = nil, secondaryTitle: String? = nil,
                actions: [ExtensionItemAction]? = nil, onOpen: Bool? = nil) {
        self.title = title; self.subtitle = subtitle; self.url = url; self.secondaryURL = secondaryURL; self.secondaryTitle = secondaryTitle
        self.actions = actions; self.onOpen = onOpen
    }

    /// Trims text to display limits and drops links that are not http or https. A row without a
    /// title is dropped.
    func sanitized() -> ExtensionItem? {
        let title = String(title.prefix(300)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        func link(_ value: String?) -> String? {
            guard let value, value.count <= ExtensionNetwork.maximumURLLength, let url = URL(string: value),
                  ["http", "https"].contains(url.scheme?.lowercased()), url.host != nil else { return nil }
            return value
        }
        let secondary = link(secondaryURL)
        var seen = Set<String>()
        let unique = (actions ?? []).compactMap { $0.sanitized() }.filter { seen.insert($0.id).inserted }.prefix(ExtensionItemAction.maximumPerItem)
        return ExtensionItem(title: title, subtitle: subtitle.map { String($0.prefix(300)) }, url: link(url),
                             secondaryURL: secondary, secondaryTitle: secondary == nil ? nil : secondaryTitle.map { String($0.prefix(40)) },
                             actions: unique.isEmpty ? nil : Array(unique), onOpen: onOpen == true ? true : nil)
    }
}

/// An action a row offers in its Actions menu, such as Pin Story. `id` is what the module receives.
public struct ExtensionItemAction: Codable, Hashable {
    public static let maximumPerItem = 6
    public var id: String
    public var title: String
    public init(id: String, title: String) { self.id = id; self.title = title }

    /// Lowercase ASCII identifiers of at most 32 characters and titles of at most 40; others are dropped.
    func sanitized() -> ExtensionItemAction? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...32).contains(id.count), id.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber || "-_.".contains($0)) }),
              (1...40).contains(title.count) else { return nil }
        return ExtensionItemAction(id: id, title: title)
    }
}

public enum ExtensionNetworkError: Error, LocalizedError, Equatable {
    case malformedPlan, tooManyFetches, tooManyRounds, hostNotAllowed(String), malformedItems, hostsNotApproved([String])
    public var errorDescription: String? {
        switch self {
        case .malformedPlan: return "Extension returned an invalid fetch plan."
        case .tooManyFetches: return "Extension asked for more than \(ExtensionNetwork.maximumFetches) URLs."
        case .tooManyRounds: return "Extension kept asking for more pages after \(ExtensionNetwork.maximumRounds) rounds."
        case .hostNotAllowed(let url): return "Extension asked for a URL it is not allowed to reach: \(url)"
        case .malformedItems: return "Extension returned an invalid list."
        case .hostsNotApproved(let hosts): return "Allow access to \(hosts.joined(separator: ", ")) to use this extension."
        }
    }
}

/// Hosts the owner allowed network extensions to reach, kept as `extensionHosts` in config.json. A host
/// is shared: removing it affects every extension that declares it. Writes patch only that key and
/// preserve every other field. The list is per Mac and is not synced through iCloud.
public enum ExtensionHostApprovals {
    public static let key = "extensionHosts"

    public static func approved(at url: URL) -> Set<String> {
        guard let object = try? read(url), let hosts = object[key] as? [String] else { return [] }
        return Set(hosts.filter(ExtensionNetwork.isValidHost))
    }

    public static func missing(_ manifest: ExtensionManifest, at url: URL) -> [String] {
        let approved = approved(at: url)
        return manifest.declaredHosts.filter { !approved.contains($0) }
    }

    public static func approve(_ hosts: [String], at url: URL) throws {
        try write(at: url) { $0.union(hosts.filter(ExtensionNetwork.isValidHost)) }
    }

    public static func remove(_ host: String, at url: URL) throws {
        try write(at: url) { $0.subtracting([host]) }
    }

    /// After an extension is removed, drops hosts it declared that no remaining extension declares.
    /// Hosts the removed extension did not declare are left alone.
    @discardableResult
    public static func pruneAfterRemoving(_ removed: ExtensionManifest, remaining: [ExtensionManifest], at url: URL) throws -> [String] {
        let stillUsed = Set(remaining.flatMap(\.declaredHosts))
        let orphaned = removed.declaredHosts.filter { !stillUsed.contains($0) && approved(at: url).contains($0) }
        if !orphaned.isEmpty { try write(at: url) { $0.subtracting(orphaned) } }
        return orphaned
    }

    private static func write(at url: URL, _ change: (Set<String>) -> Set<String>) throws {
        var object = try read(url)
        let current = Set((object[key] as? [String] ?? []).filter(ExtensionNetwork.isValidHost))
        object[key] = change(current).sorted()
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }

    private static func read(_ url: URL) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
              object[key] == nil || object[key] is [String] else { throw CocoaError(.fileReadCorruptFile) }
        return object
    }
}

/// What the app asks the sandboxed fetch helper to do. The helper re-checks every URL against
/// `allowedHosts`, refuses redirects, sends no cookies and stops reading past `maximumBytes`.
/// `fetchCatalogFile` reads only the fixed extension catalog paths that `ExtensionCatalog.url(for:)` accepts.
@objc public protocol VolantFetchHostProtocol {
    func fetch(url: String, allowedHosts: [String], maximumBytes: Int, reply: @escaping (Data?, Int, String?) -> Void)
    func fetchCatalogFile(path: String, maximumBytes: Int, reply: @escaping (Data?, Int, String?) -> Void)
}
