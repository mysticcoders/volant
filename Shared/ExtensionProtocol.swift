import Foundation

/// Manifest shipped beside a module. Capabilities are the complete list of host imports the module may call.
struct ExtensionManifest: Codable, Hashable {
    var id: String
    var name: String
    var version: String
    var module: String
    var capabilities: [String]
    var timeoutSeconds: Double?
    var sha256: String?

    static let knownCapabilities: Set<String> = ["log", "clipboard.write"]
}

/// What the app can ask the sandboxed service to do.
@objc protocol VeyExtensionHostProtocol {
    /// Instantiates `module` with only the imports named in `capabilities`, writes `input` into its memory,
    /// calls `run`, and replies with the extension's output string or an error message.
    func run(module: Data, capabilities: [String], input: String, timeout: Double, reply: @escaping (String?, String?) -> Void)
}

/// What the service may ask the app to do on the extension's behalf. Every call is re-checked against the manifest by the app.
@objc protocol VeyCapabilityClientProtocol {
    func log(_ message: String)
    func clipboardWrite(_ text: String)
}
