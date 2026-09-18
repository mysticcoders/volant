import Foundation

/// Manifest shipped beside a module. Capabilities are the complete list of host imports the module may call.
struct ExtensionManifest: Codable, Hashable {
    var abiVersion: Int? = 1
    var id: String
    var name: String
    var version: String
    var module: String
    var capabilities: [String]
    var timeoutSeconds: Double?
    var sha256: String?

    func validate() throws {
        guard abiVersion == 1, !id.isEmpty, id.count <= 128, !name.isEmpty, name.count <= 128,
              !version.isEmpty, module.hasSuffix(".wasm"), !module.contains("/"), !module.contains("\\"),
              Set(capabilities).isSubset(of: Self.knownCapabilities), Set(capabilities).count == capabilities.count,
              let hash = sha256, hash.count == 64, hash.allSatisfy({ $0.isHexDigit }),
              (timeoutSeconds ?? 2).isFinite, (0.5...10).contains(timeoutSeconds ?? 2) else {
            throw ExtensionValidationError.invalidManifest
        }
    }
    static let knownCapabilities: Set<String> = ["log", "clipboard.write"]
}

/// What the app can ask the sandboxed service to do.
@objc protocol VolantExtensionHostProtocol {
    func prepare(reply: @escaping () -> Void)
    /// Instantiates `module` with only the imports named in `capabilities`, writes `input` into its memory,
    /// calls `run`, and replies with the extension's output string or an error message.
    func run(module: Data, capabilities: [String], input: String, timeout: Double, reply: @escaping (String?, String?) -> Void)
}

/// What the service may ask the app to do on the extension's behalf. Every call is re-checked against the manifest by the app.
@objc protocol VolantCapabilityClientProtocol {
    func log(_ message: String)
    func clipboardWrite(_ text: String)
}


enum ExtensionValidationError: Error, LocalizedError {
    case invalidManifest, invalidMemory
    var errorDescription: String? {
        switch self {
        case .invalidManifest: return "Extension needs a valid ABI 1 manifest, SHA-256 and supported permissions."
        case .invalidMemory: return "Extension must declare bounded WebAssembly memory (maximum 16 MiB)."
        }
    }
}

/// Enforce the linear-memory limit before JavaScriptCore instantiates untrusted code.
/// ABI 1 permits one defined, non-shared wasm32 memory and no imported memory.
enum ExtensionMemory {
    static func validate(_ data: Data) throws {
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
