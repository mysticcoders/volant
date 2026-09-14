import AppKit

struct InstalledExtension: Identifiable, Hashable {
    let id: String
    let manifest: ExtensionManifest
    let directory: URL
    var name: String { manifest.name }
}

/// Loads extension folders (manifest.json + module), verifies the module hash, and runs modules
/// in the sandboxed XPC service. The app is the only place capabilities are executed, and it checks
/// the manifest again before honoring each callback.
final class ExtensionManager: NSObject, VolantCapabilityClientProtocol {
    private(set) var extensions: [InstalledExtension] = []
    private var active: ExtensionManifest?
    var onLog: (String) -> Void = { NSLog("[volant-ext] %@", $0) }

    static var directory: URL {
        let dir = Preferences.supportDirectory.appendingPathComponent("Extensions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func reload() {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: ExtensionManager.directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        extensions = dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
                  let manifest = try? JSONDecoder().decode(ExtensionManifest.self, from: data),
                  Set(manifest.capabilities).isSubset(of: ExtensionManifest.knownCapabilities) else { return nil }
            return InstalledExtension(id: manifest.id, manifest: manifest, directory: dir)
        }.sorted { $0.name < $1.name }
    }

    func search(_ term: String) -> [InstalledExtension] {
        let t = term.lowercased()
        return extensions.filter { t.isEmpty || $0.name.lowercased().contains(t) || $0.id.lowercased().hasSuffix(t) }
    }

    /// Verifies the pinned hash, then runs the module with exactly the manifest's capabilities.
    func run(_ ext: InstalledExtension, input: String, completion: @escaping (Result<String, Error>) -> Void) {
        let moduleURL = ext.directory.appendingPathComponent(ext.manifest.module)
        guard let module = try? Data(contentsOf: moduleURL) else {
            completion(.failure(ExtensionError.missingModule)); return
        }
        if let pinned = ext.manifest.sha256, Integrity.sha256(module) != pinned.lowercased() {
            completion(.failure(ExtensionError.hashMismatch)); return
        }
        active = ext.manifest
        let connection = NSXPCConnection(serviceName: "com.mysticcoders.volant.ExtensionHost")
        connection.remoteObjectInterface = NSXPCInterface(with: VolantExtensionHostProtocol.self)
        connection.exportedInterface = NSXPCInterface(with: VolantCapabilityClientProtocol.self)
        connection.exportedObject = self
        connection.resume()
        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            DispatchQueue.main.async { completion(.failure(error)) }
            connection.invalidate()
        } as? VolantExtensionHostProtocol
        proxy?.run(module: module, capabilities: ext.manifest.capabilities, input: input, timeout: ext.manifest.timeoutSeconds ?? 2) { output, error in
            DispatchQueue.main.async {
                if let error { completion(.failure(ExtensionError.runtime(error))) }
                else { completion(.success(output ?? "")) }
                connection.invalidate()
            }
        }
    }

    // MARK: capability callbacks, each re-checked against the manifest that is running

    func log(_ message: String) {
        guard active?.capabilities.contains("log") == true else { return }
        DispatchQueue.main.async { self.onLog(message) }
    }

    func clipboardWrite(_ text: String) {
        guard active?.capabilities.contains("clipboard.write") == true else { return }
        DispatchQueue.main.async {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
        }
    }

    enum ExtensionError: Error, LocalizedError {
        case missingModule, hashMismatch, runtime(String)
        var errorDescription: String? {
            switch self {
            case .missingModule: return "Extension module file is missing."
            case .hashMismatch: return "Extension module does not match its manifest hash."
            case .runtime(let m): return m
            }
        }
    }
}

enum Integrity {
    static func sha256(_ data: Data) -> String {
        import_CryptoKit_sha256(data)
    }
}
