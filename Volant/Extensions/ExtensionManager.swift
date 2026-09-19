import AppKit

struct InstalledExtension: Identifiable, Hashable {
    let id: String
    let manifest: ExtensionManifest
    let directory: URL
    var enabled = false
    var communityBlocked = false
    var isCommunity: Bool { !ExtensionManager.isBundled(directory) }
    var name: String { manifest.name }
    var accessDescription: String {
        manifest.capabilities.isEmpty ? "No permissions required" : manifest.capabilities.sorted().map {
            $0 == "clipboard.write" ? "Write to clipboard" : "Send diagnostic messages"
        }.joined(separator: ", ")
    }
}

final class ExtensionManager {
    private(set) var extensions: [InstalledExtension] = []
    private(set) var loadErrors: [String] = []
    var onLog: (String) -> Void = { _ in }
    var configURL: URL
    private let roots: [URL]?
    private var execution: ExtensionExecution?
    private static var running = false
    private static weak var activeExecution: ExtensionExecution?
    init(configURL: URL = Preferences.configURL, roots: [URL]? = nil) {
        self.configURL = configURL; self.roots = roots
    }
    static var directory: URL {
        let dir = Preferences.supportDirectory.appendingPathComponent("Extensions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static func isBundled(_ directory: URL) -> Bool {
        guard let bundled = Bundle.main.url(forResource: "HelloWorld", withExtension: nil) else { return false }
        return directory.resolvingSymlinksInPath() == bundled.resolvingSymlinksInPath()
    }
    var communityAllowed: Bool { ExtensionApproval.communityAllowed(at: configURL) }
    func isBlocked(_ ext: InstalledExtension) -> Bool { ext.isCommunity && !communityAllowed }
    func setCommunityAllowed(_ allowed: Bool, expected: Bool) throws {
        try ExtensionApproval.updateCommunityAllowed(allowed, expected: expected, at: configURL)
        if !allowed, let active = Self.activeExecution, active.isCommunity, active.configURL == configURL {
            active.finish(.failure(ExtensionError.communityDisabled))
        }
        reload()
    }
    func reload() {
        let folders = roots ?? ((Bundle.main.url(forResource: "HelloWorld", withExtension: nil).map { [$0] } ?? []) +
            ((try? FileManager.default.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []))
        loadErrors = []
        let candidates = folders.compactMap { dir -> InstalledExtension? in
            do {
                let manifest = try readManifest(dir)
                return InstalledExtension(id: manifest.id, manifest: manifest, directory: dir,
                    enabled: ExtensionApproval.enabled(manifest, at: configURL),
                    communityBlocked: !Self.isBundled(dir) && !communityAllowed)
            } catch { loadErrors.append("\(dir.lastPathComponent): \(error.localizedDescription)"); return nil }
        }
        let counts = Dictionary(grouping: candidates, by: \.id)
        extensions = candidates.filter { counts[$0.id]?.count == 1 }.sorted { $0.name < $1.name }
        if counts.values.contains(where: { $0.count > 1 }) { loadErrors.append("Duplicate extension IDs are disabled. Remove the duplicate folder.") }
    }
    func search(_ term: String) -> [InstalledExtension] {
        extensions.filter { term.isEmpty || $0.name.localizedCaseInsensitiveContains(term) || $0.id.lowercased().hasSuffix(term.lowercased()) }
    }
    private func readManifest(_ dir: URL) throws -> ExtensionManifest {
        let url = dir.appendingPathComponent("manifest.json")
        guard url.resolvingSymlinksInPath().deletingLastPathComponent() == dir.resolvingSymlinksInPath(),
              (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 32_768 else { throw ExtensionValidationError.invalidManifest }
        let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: Data(contentsOf: url))
        try manifest.validate()
        return manifest
    }
    private func verifiedModule(_ ext: InstalledExtension) throws -> Data {
        guard try readManifest(ext.directory) == ext.manifest else { throw ExtensionError.changed }
        let url = ext.directory.appendingPathComponent(ext.manifest.module)
        guard url.resolvingSymlinksInPath().deletingLastPathComponent() == ext.directory.resolvingSymlinksInPath(),
              (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 2_097_152 else { throw ExtensionError.missingModule }
        let module = try Data(contentsOf: url)
        guard Integrity.sha256(module) == ext.manifest.sha256?.lowercased() else { throw ExtensionError.hashMismatch }
        try ExtensionMemory.validate(module)
        return module
    }
    func setEnabled(_ ext: InstalledExtension, _ enabled: Bool) throws {
        if enabled && isBlocked(ext) { throw ExtensionError.communityDisabled }
        if enabled { _ = try verifiedModule(ext) }
        try ExtensionApproval.update(ext.manifest, enabled: enabled, expected: ext.enabled, at: configURL)
        if !enabled, Self.activeExecution?.extensionID == ext.id, Self.activeExecution?.configURL == configURL {
            Self.activeExecution?.finish(.failure(ExtensionError.disabled))
        }
        reload()
    }
    func run(_ ext: InstalledExtension, input: String, completion: @escaping (Result<String, Error>) -> Void) {
        do {
            guard !isBlocked(ext) else { throw ExtensionError.communityDisabled }
            guard ExtensionApproval.enabled(ext.manifest, at: configURL) else { throw ExtensionError.disabled }
            guard !Self.running else { throw ExtensionError.runtime("An extension is already running.") }
            guard input.utf8.count <= 65_536 else { throw ExtensionError.runtime("Extension input exceeds 64 KiB.") }
            let module = try verifiedModule(ext)
            Self.running = true
            let execution = ExtensionExecution(manifest: ext.manifest, configURL: configURL, isCommunity: ext.isCommunity, onLog: onLog) { [self] result in
                Self.running = false; Self.activeExecution = nil; self.execution = nil; completion(result)
            }
            self.execution = execution
            Self.activeExecution = execution
            execution.start(module: module, input: input)
        } catch { completion(.failure(error)) }
    }
    enum ExtensionError: Error, LocalizedError {
        case missingModule, hashMismatch, changed, disabled, communityDisabled, runtime(String)
        var errorDescription: String? {
            switch self {
            case .missingModule: return "Extension module is missing, too large, or outside its folder."
            case .hashMismatch: return "Extension module does not match its manifest hash."
            case .changed: return "Extension changed. Refresh and review it before enabling."
            case .disabled: return "Extension is disabled. Enable it before running."
            case .communityDisabled: return "Community extensions are off. Allow them in Settings → Extensions."
            case .runtime(let message): return message
            }
        }
    }
}

/// One connection, one permission snapshot, one completion. No shared active manifest.
private final class ExtensionExecution: NSObject, VolantCapabilityClientProtocol {
    private let manifest: ExtensionManifest
    var extensionID: String { manifest.id }
    let configURL: URL
    let isCommunity: Bool
    private let onLog: (String) -> Void
    private var completion: ((Result<String, Error>) -> Void)?
    private var connection: NSXPCConnection?
    private var deadline: DispatchWorkItem?
    init(manifest: ExtensionManifest, configURL: URL, isCommunity: Bool, onLog: @escaping (String) -> Void, completion: @escaping (Result<String, Error>) -> Void) {
        self.manifest = manifest; self.configURL = configURL; self.isCommunity = isCommunity; self.onLog = onLog; self.completion = completion
    }
    private var approved: Bool {
        (!isCommunity || ExtensionApproval.communityAllowed(at: configURL)) && ExtensionApproval.enabled(manifest, at: configURL)
    }
    private var attempt = UUID()
    private var connectionAttempts = 0
    private var submitted = false
    func start(module: Data, input: String) {
        // launchd normally throttles rapid service restarts for up to ten seconds.
        armDeadline(15, message: "Extension service could not start. Try again.")
        connect(module: module, input: input)
    }
    private func armDeadline(_ seconds: Double, message: String) {
        deadline?.cancel()
        let deadline = DispatchWorkItem { [weak self] in
            self?.finish(.failure(ExtensionManager.ExtensionError.runtime(message)))
        }
        self.deadline = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: deadline)
    }
    private func connect(module: Data, input: String) {
        guard completion != nil else { return }
        connectionAttempts += 1
        let token = UUID(); attempt = token
        let connection = NSXPCConnection(serviceName: "com.mysticcoders.volant.ExtensionHost")
        self.connection = connection
        connection.remoteObjectInterface = NSXPCInterface(with: VolantExtensionHostProtocol.self)
        connection.exportedInterface = NSXPCInterface(with: VolantCapabilityClientProtocol.self)
        connection.exportedObject = self
        let failure = { [weak self] in DispatchQueue.main.async {
            guard let self, self.completion != nil, self.attempt == token else { return }
            self.attempt = UUID()
            // Retry only service readiness. A submitted module is never replayed.
            if !self.submitted && self.connectionAttempts < 4 {
                self.clearConnection()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.connect(module: module, input: input) }
            } else {
                self.finish(.failure(ExtensionManager.ExtensionError.runtime("Extension stopped or exceeded its time limit.")))
            }
        } }
        connection.interruptionHandler = failure; connection.invalidationHandler = failure
        connection.resume()
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in failure() } as? VolantExtensionHostProtocol
        proxy?.prepare { [weak self] in DispatchQueue.main.async {
            guard let self, self.completion != nil, self.attempt == token else { return }
            guard self.approved else { self.finish(.failure(ExtensionManager.ExtensionError.disabled)); return }
            self.submitted = true
            self.armDeadline((self.manifest.timeoutSeconds ?? 2) + 1, message: "Extension exceeded its time limit.")
            proxy?.run(module: module, capabilities: self.manifest.capabilities, input: input, timeout: self.manifest.timeoutSeconds ?? 2) { [weak self] output, error in
                DispatchQueue.main.async {
                    guard let self, self.attempt == token else { return }
                    guard self.approved else { self.finish(.failure(ExtensionManager.ExtensionError.disabled)); return }
                    if let error { self.finish(.failure(ExtensionManager.ExtensionError.runtime(error))) }
                    else if let output, output.utf8.count <= 65_536 { self.finish(.success(output)) }
                    else { self.finish(.failure(ExtensionManager.ExtensionError.runtime("Invalid extension output."))) }
                }
            }
        } }
    }
    private func clearConnection() {
        connection?.invalidationHandler = nil; connection?.interruptionHandler = nil
        connection?.invalidate(); connection = nil
    }
    func finish(_ result: Result<String, Error>) {
        guard let completion else { return }
        self.completion = nil
        deadline?.cancel(); deadline = nil
        clearConnection()
        completion(result)
    }
    private func permitted(_ capability: String) -> Bool {
        completion != nil && manifest.capabilities.contains(capability) && approved
    }
    func log(_ message: String) {
        guard message.utf8.count <= 4096 else { return }
        DispatchQueue.main.async { if self.permitted("log") { self.onLog(message) } }
    }
    func clipboardWrite(_ text: String) {
        guard text.utf8.count <= 65_536 else { return }
        DispatchQueue.main.async {
            guard self.permitted("clipboard.write") else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }
}

enum Integrity {
    static func sha256(_ data: Data) -> String { import_CryptoKit_sha256(data) }
}
