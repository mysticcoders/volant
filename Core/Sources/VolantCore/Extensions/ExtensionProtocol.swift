import Foundation

/// Manifest shipped beside a module. Capabilities are the complete list of host imports the module may call.
/// `hosts` lists the exact hostnames a network extension may read through Volant's fetch helper; the
/// module itself never gets network access (see `ExtensionNetwork`). `output` is "text" (the default) or
/// "items", a list of links the launcher shows as rows. `icon` names an optional square WebP beside the
/// module, pinned by `iconSha256`; both are part of the approval fingerprint when present.
public struct ExtensionManifest: Codable, Hashable {
    public var abiVersion: Int? = 1
    public var id: String
    public var name: String
    public var version: String
    public var module: String
    public var capabilities: [String]
    public var timeoutSeconds: Double?
    public var sha256: String?
    public var hosts: [String]?
    public var output: String?
    public var icon: String?
    public var iconSha256: String?
    /// A list extension that keeps a small JSON object on this Mac (see `ExtensionStorage`). Part of the
    /// approval fingerprint when present, so adding it needs the owner to enable the extension again.
    public var storage: Bool?
    /// Tokens the owner gives once for some of the declared hosts (see `ExtensionSecret`). Part of the
    /// approval fingerprint when present.
    public var secrets: [ExtensionSecret]?
    /// URL schemes of apps a row may open, such as `todoist`, so Return can open a task in its app. Part of
    /// the approval fingerprint when present; system and file schemes are never allowed.
    public var appLinks: [String]?
    /// Owner data the extension asks for, beyond its hosts: today only `"location"` (see
    /// `ExtensionLocation`). Part of the approval fingerprint when present.
    public var permissions: [String]?
    /// How a list extension behaves once the owner enters it: `"list"` (the default) runs at once and
    /// shows rows, `"search"` waits for typed input. Presentation only, so not part of the fingerprint.
    public var mode: String?
    /// The search field's prompt inside a list extension, such as "Search Wikipedia". Presentation only.
    public var placeholder: String?
    /// Choices for a dropdown at the end of the search field inside a list extension, such as Top, New
    /// and Ask; the first is the default, and the chosen one's `id` is sent as `filter`. Presentation
    /// only, so not part of the fingerprint.
    public var filters: [ExtensionFilter]?
    /// Settings the owner chooses in Settings › Extensions, sent as `preferences` with every list request
    /// (see `ExtensionPreference`). The owner's own choices, giving no new access, so not part of the
    /// fingerprint.
    public var preferences: [ExtensionPreference]?

    public var declaredSecrets: [ExtensionSecret] { secrets ?? [] }
    public var declaredAppLinks: [String] { appLinks ?? [] }
    public var declaredPermissions: [String] { permissions ?? [] }
    public var wantsLocation: Bool { declaredPermissions.contains(ExtensionLocation.permission) }
    public static let knownPermissions: Set<String> = [ExtensionLocation.permission]
    public var declaredHosts: [String] { hosts ?? [] }
    public var listsItems: Bool { output == "items" }
    public var usesStorage: Bool { storage == true }
    public var waitsForInput: Bool { mode == "search" }
    public static let maximumPlaceholderLength = 80
    public var declaredFilters: [ExtensionFilter] { filters ?? [] }
    public var declaredPreferences: [ExtensionPreference] { preferences ?? [] }

    public func validate() throws {
        guard [1, 2].contains(abiVersion ?? 0), abiVersion != 2 || capabilities.isEmpty,
              !id.isEmpty, id.count <= 128, !name.isEmpty, name.count <= 128,
              !version.isEmpty, module.hasSuffix(".wasm"), !module.contains("/"), !module.contains("\\"),
              Set(capabilities).isSubset(of: Self.knownCapabilities), Set(capabilities).count == capabilities.count,
              let hash = sha256, hash.count == 64, hash.allSatisfy({ $0.isHexDigit }),
              (timeoutSeconds ?? 2).isFinite, (0.5...10).contains(timeoutSeconds ?? 2),
              [nil, "text", "items"].contains(output), declaredHosts.count <= ExtensionNetwork.maximumHosts,
              Set(declaredHosts).count == declaredHosts.count, declaredHosts.allSatisfy(ExtensionNetwork.isValidHost),
              declaredHosts.isEmpty || listsItems, Self.isValidIcon(icon, sha256: iconSha256), !usesStorage || listsItems,
              declaredSecrets.count <= ExtensionSecret.maximumPerExtension, Set(declaredSecrets.map(\.id)).count == declaredSecrets.count,
              Set(declaredSecrets.map(\.host)).count == declaredSecrets.count, declaredSecrets.allSatisfy({ $0.isValid(hosts: declaredHosts) }),
              declaredAppLinks.count <= Self.maximumAppLinks, Set(declaredAppLinks).count == declaredAppLinks.count,
              declaredAppLinks.allSatisfy(Self.isAllowedAppLink), declaredAppLinks.isEmpty || listsItems,
              Set(declaredPermissions).isSubset(of: Self.knownPermissions), Set(declaredPermissions).count == declaredPermissions.count,
              declaredPermissions.isEmpty || listsItems, [nil, "list", "search"].contains(mode), mode == nil || listsItems,
              placeholder.map({ (1...Self.maximumPlaceholderLength).contains($0.count) && listsItems }) ?? true,
              filters == nil || (listsItems && (2...ExtensionFilter.maximumCount).contains(declaredFilters.count)),
              declaredFilters.allSatisfy(\.isValid), Set(declaredFilters.map(\.id)).count == declaredFilters.count,
              ExtensionPreferences.isValid(declaredPreferences, listsItems: listsItems) else {
            throw ExtensionValidationError.invalidManifest
        }
    }
    public static let knownCapabilities: Set<String> = ["log", "clipboard.write"]
    public static let maximumAppLinks = 4
    /// Schemes no extension may open: files, scripts, inline data, the web (rows use http and https
    /// directly), network shares and remote sessions, and Apple's system URLs.
    static let refusedAppLinks: Set<String> = ["file", "javascript", "data", "blob", "about", "http", "https", "ftp", "sftp", "smb", "afp", "nfs",
                                                "vnc", "ssh", "telnet", "rdp", "applescript", "prefs", "x-apple.systempreferences", "itms-services"]

    /// A lowercase scheme of 2 to 32 letters, digits, `+`, `-` or `.`, starting with a letter, that is not
    /// refused and not one of Apple's `x-apple` system schemes.
    public static func isAllowedAppLink(_ scheme: String) -> Bool {
        (2...32).contains(scheme.count) && scheme.first?.isLetter == true &&
            scheme.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || "+-.".contains($0)) } &&
            !refusedAppLinks.contains(scheme) && !scheme.hasPrefix("x-apple")
    }
    public static let maximumIconBytes = 32_768

    /// No icon, or a plain `.webp` file name in the extension's folder with a lowercase SHA-256.
    static func isValidIcon(_ icon: String?, sha256: String?) -> Bool {
        guard let icon else { return sha256 == nil }
        return isSafeIconName(icon) && sha256?.count == 64 && sha256?.allSatisfy({ $0.isASCII && $0.isHexDigit && !$0.isUppercase }) == true
    }

    static func isSafeIconName(_ icon: String) -> Bool {
        let stem = icon.dropLast(5)
        return icon.hasSuffix(".webp") && (1...64).contains(stem.count) &&
            stem.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }

    /// Whether `data` starts like a WebP file (`RIFF`, a length, `WEBP`). Decoding happens in the app.
    public static func looksLikeWebP(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(12))
        return bytes.count == 12 && bytes[0..<4] == [82, 73, 70, 70] && bytes[8..<12] == [87, 69, 66, 80]
    }

    public init(abiVersion: Int? = 1, id: String, name: String, version: String, module: String, capabilities: [String], timeoutSeconds: Double? = nil, sha256: String? = nil,
                hosts: [String]? = nil, output: String? = nil, icon: String? = nil, iconSha256: String? = nil, storage: Bool? = nil,
                secrets: [ExtensionSecret]? = nil, appLinks: [String]? = nil, permissions: [String]? = nil,
                mode: String? = nil, placeholder: String? = nil, filters: [ExtensionFilter]? = nil, preferences: [ExtensionPreference]? = nil) {
        self.preferences = preferences
        self.abiVersion = abiVersion
        self.id = id
        self.name = name
        self.version = version
        self.module = module
        self.capabilities = capabilities
        self.timeoutSeconds = timeoutSeconds
        self.sha256 = sha256
        self.hosts = hosts
        self.output = output
        self.icon = icon
        self.iconSha256 = iconSha256
        self.storage = storage
        self.secrets = secrets
        self.appLinks = appLinks
        self.permissions = permissions
        self.mode = mode
        self.placeholder = placeholder
        self.filters = filters
    }
}

/// One choice in a list extension's dropdown, such as `{"id": "new", "title": "New"}`.
public struct ExtensionFilter: Codable, Hashable, Sendable {
    public static let maximumCount = 8
    public static let maximumTitleLength = 24
    public var id: String
    public var title: String
    public init(id: String, title: String) { self.id = id; self.title = title }

    /// A lowercase ASCII id of at most 32 characters (letters, digits, `-`, `_`, `.`) and a one-line title
    /// of at most 24 characters.
    public var isValid: Bool {
        (1...32).contains(id.count) && id.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber || "-_.".contains($0)) }) &&
            (1...Self.maximumTitleLength).contains(title.count) && !title.contains(where: \.isNewline) &&
            title.trimmingCharacters(in: .whitespaces) == title
    }
}

/// What the app can ask the sandboxed service to do.
@objc public protocol VolantExtensionHostProtocol {
    func prepare(reply: @escaping () -> Void)
    /// Instantiates `module` with only the imports named in `capabilities`, writes `input` into its memory,
    /// calls `run`, and replies with the extension's output string or an error message.
    func run(module: Data, capabilities: [String], input: String, timeout: Double, reply: @escaping (String?, String?) -> Void)
    /// ABI 2: restricted WASI command with in-memory stdin/stdout only.
    func runCommand(module: Data, input: String, timeout: Double, reply: @escaping (String?, String?) -> Void)
}

/// What the service may ask the app to do on the extension's behalf. Every call is re-checked against the manifest by the app.
@objc public protocol VolantCapabilityClientProtocol {
    func log(_ message: String)
    func clipboardWrite(_ text: String)
}


public enum ExtensionValidationError: Error, LocalizedError {
    case invalidManifest, invalidMemory
    public var errorDescription: String? {
        switch self {
        case .invalidManifest: return String(localized: "Extension needs a valid ABI 1 or 2 manifest, SHA-256 and supported permissions.", table: "Core", comment: "Extension error; ABI and SHA-256 are not translated")
        case .invalidMemory: return String(localized: "Extension must declare bounded WebAssembly memory (maximum 16 MiB).", table: "Core", comment: "Extension error")
        }
    }
}

/// Enforce the linear-memory limit before JavaScriptCore instantiates untrusted code.
/// ABI 1 permits one defined, non-shared wasm32 memory and no imported memory.
public enum ExtensionMemory {
    public static func validate(_ data: Data) throws {
        let bytes = [UInt8](data)
        guard bytes.count <= 2_097_152, bytes.starts(with: [0, 97, 115, 109, 1, 0, 0, 0]) else { throw ExtensionValidationError.invalidMemory }
        var offset = 8, found = false
        func number(_ end: Int) throws -> Int {
            var value = 0
            for shift in stride(from: 0, through: 28, by: 7) {
                guard offset < end else { throw ExtensionValidationError.invalidMemory }
                let byte = Int(bytes[offset]); offset += 1
                if shift == 28 && byte > 15 { throw ExtensionValidationError.invalidMemory }
                value |= (byte & 127) << shift
                if byte < 128 { return value }
            }
            throw ExtensionValidationError.invalidMemory
        }
        while offset < bytes.count {
            let section = bytes[offset]; offset += 1
            let count = try number(bytes.count)
            guard count <= bytes.count - offset else { throw ExtensionValidationError.invalidMemory }
            let end = offset + count
            if section == 5 {
                guard !found, try number(end) == 1, try number(end) == 1 else { throw ExtensionValidationError.invalidMemory }
                let initial = try number(end), maximum = try number(end)
                guard initial <= maximum, maximum <= 256, offset == end else { throw ExtensionValidationError.invalidMemory }
                found = true
            }
            offset = end
        }
        guard found else { throw ExtensionValidationError.invalidMemory }
    }
}
