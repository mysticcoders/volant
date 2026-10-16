import AppKit
import VolantCore

struct InstalledExtension: Identifiable, Hashable {
    let id: String
    let manifest: ExtensionManifest
    let directory: URL
    var enabled = false
    var communityBlocked = false
    var isCommunity: Bool { !ExtensionManager.isBundled(directory) }
    var name: String { manifest.name }
    /// The catalog record beside this extension, if the catalog installed it.
    var catalogOrigin: ExtensionCatalogOrigin? {
        let url = directory.appendingPathComponent(ExtensionCatalogOrigin.fileName)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 4096,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ExtensionCatalogOrigin.self, from: data)
    }
    var accessDescription: String {
        Self.accessDescription(capabilities: manifest.capabilities, hosts: manifest.declaredHosts, storage: manifest.usesStorage, secrets: manifest.declaredSecrets,
                               appLinks: manifest.declaredAppLinks, location: manifest.wantsLocation)
    }
    static func accessDescription(capabilities: [String], hosts: [String], storage: Bool = false, secrets: [ExtensionSecret] = [],
                                  appLinks: [String] = [], location: Bool = false) -> String {
        var access: [String] = capabilities.sorted().map { $0 == "clipboard.write" ? "Write to clipboard" : "Send diagnostic messages" }
        if !hosts.isEmpty { access.append("Read " + hosts.joined(separator: ", ")) }
        if storage { access.append("Remember settings and lists on this Mac") }
        access += secrets.map { "Uses your \($0.title)" }
        access += appLinks.map { "Opens \($0): links" }
        if location { access.append("Share your approximate location with the sites it reads") }
        return access.isEmpty ? "No permissions required" : access.joined(separator: ", ")
    }
}

final class ExtensionManager {
    private(set) var extensions: [InstalledExtension] = []
    private(set) var loadErrors: [String] = []
    var onLog: (String) -> Void = { _ in }
    var configURL: URL { didSet { if configURL != oldValue { invalidateCatalog() } } }
    private var catalogLoaded = false
    private let roots: [URL]?
    private let installRoot: URL?
    let dataStore: ExtensionDataStore
    /// Where declared tokens live; tests replace the Keychain with `ExtensionSecretStore.memory()`.
    var secretStore: ExtensionSecretStore = .keychain
    /// Finds the owner's rounded location for extensions allowed to receive it; tests replace it.
    var locate: (@escaping (ExtensionLocation?) -> Void) -> Void = { completion in
        MainActor.assumeIsolated { ExtensionLocationProvider.shared.locate(completion) }
    }
    /// Replaces the extension helper in tests: given the extension and its request, returns its output.
    var invokeOverride: ((InstalledExtension, String, @escaping (Result<String, Error>) -> Void) -> Void)?
    private var execution: ExtensionExecution?
    private static var running = false
    private static weak var activeExecution: ExtensionExecution?
    /// `roots` lists extension folders to load instead of the bundled example and the Extensions folder.
    /// `directory` replaces the Extensions folder, which is also where the catalog installs.
    init(configURL: URL = Preferences.configURL, roots: [URL]? = nil, directory: URL? = nil, dataDirectory: URL? = nil) {
        self.configURL = configURL; self.roots = roots; self.installRoot = directory
        self.dataStore = ExtensionDataStore(directory: dataDirectory ?? ExtensionDataStore.defaultDirectory)
    }
    var installDirectory: URL { installRoot ?? Self.directory }
    static var directory: URL {
        let dir = Preferences.supportDirectory.appendingPathComponent("Extensions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static func isBundled(_ directory: URL) -> Bool {
        guard let bundled = Bundle.main.url(forResource: "HelloWorld", withExtension: nil) else { return false }
        return sameLocation(directory, bundled)
    }
    /// Compares resolved file paths rather than URLs, so a directory URL with or without a trailing
    /// slash still matches. On macOS 27 an unslashed directory URL can stay unslashed after resolving.
    static func sameLocation(_ first: URL, _ second: URL) -> Bool {
        first.resolvingSymlinksInPath().path == second.resolvingSymlinksInPath().path
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
    func invalidateCatalog() { catalogLoaded = false }
    func loadIfNeeded() { if !catalogLoaded { reload() } }
    func reload() {
        catalogLoaded = true
        let folders = roots ?? ((Bundle.main.url(forResource: "HelloWorld", withExtension: nil).map { [$0] } ?? []) +
            ((try? FileManager.default.contentsOfDirectory(at: installDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []))
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
    /// Search metadata only. Execution and current approval checks happen on activation.
    /// A full display name or final ID component introduces input; partial names only search.
    func commandMatches(_ query: String) -> [(extensionItem: InstalledExtension, input: String)] {
        loadIfNeeded()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        return extensions.compactMap { ext in
            let triggers = [ext.name, String(ext.id.split(separator: ".").last ?? "")]
                .filter { !$0.isEmpty }.sorted { $0.count > $1.count }
            for trigger in triggers {
                guard let range = text.range(of: trigger, options: [.anchored, .caseInsensitive]) else { continue }
                let remainder = text[range.upperBound...]
                if remainder.isEmpty || remainder.first?.isWhitespace == true {
                    return (extensionItem: ext, input: String(remainder.drop(while: \.isWhitespace)))
                }
            }
            if ext.name.localizedCaseInsensitiveContains(text) || ext.id.lowercased().hasSuffix(text.lowercased()) {
                return (extensionItem: ext, input: "")
            }
            return nil
        }
    }
    private func readManifest(_ dir: URL) throws -> ExtensionManifest {
        let url = dir.appendingPathComponent("manifest.json")
        guard Self.sameLocation(url.resolvingSymlinksInPath().deletingLastPathComponent(), dir),
              (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 32_768 else { throw ExtensionValidationError.invalidManifest }
        let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: Data(contentsOf: url))
        try manifest.validate()
        return manifest
    }
    private func verifiedModule(_ ext: InstalledExtension) throws -> Data {
        guard try readManifest(ext.directory) == ext.manifest else { throw ExtensionError.changed }
        let url = ext.directory.appendingPathComponent(ext.manifest.module)
        guard Self.sameLocation(url.resolvingSymlinksInPath().deletingLastPathComponent(), ext.directory),
              (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 2_097_152 else { throw ExtensionError.missingModule }
        let module = try Data(contentsOf: url)
        guard Integrity.sha256(module) == ext.manifest.sha256?.lowercased() else { throw ExtensionError.hashMismatch }
        try ExtensionMemory.validate(module)
        return module
    }
    /// Hosts this extension declares that the owner has not allowed yet. A host removed in Settings
    /// shows up here again, so the next run asks before fetching.
    func missingHosts(_ ext: InstalledExtension) -> [String] { ExtensionHostApprovals.missing(ext.manifest, at: configURL) }
    /// Ready to run without asking: enabled, every declared host allowed and every declared token saved.
    func isReady(_ ext: InstalledExtension) -> Bool {
        ext.enabled && missingHosts(ext).isEmpty && missingSecrets(ext).isEmpty && !missingLocation(ext)
    }

    /// Whether this extension asks for the owner's location and has not been allowed it yet.
    func missingLocation(_ ext: InstalledExtension) -> Bool { ExtensionLocationApprovals.missing(ext.manifest, at: configURL) }
    /// Extensions allowed to receive the owner's location, for Settings.
    func locationApproved(_ ext: InstalledExtension) -> Bool {
        ext.manifest.wantsLocation && ExtensionLocationApprovals.approved(at: configURL).contains(ext.id)
    }
    /// The first-run prompt's grant, for this one extension only.
    func allowLocation(_ ext: InstalledExtension) throws {
        guard ext.manifest.wantsLocation else { return }
        try ExtensionLocationApprovals.approve(ext.id, at: configURL)
    }
    /// Settings → Location → Stop Sharing; the next run asks again.
    func stopSharingLocation(_ ext: InstalledExtension) throws { try ExtensionLocationApprovals.remove(ext.id, at: configURL) }

    /// The location this run may send: looked up only for an extension that declares the permission and
    /// is allowed it, otherwise nil without asking Location Services.
    private func runLocation(_ ext: InstalledExtension, _ completion: @escaping (ExtensionLocation?) -> Void) {
        guard locationApproved(ext) else { completion(nil); return }
        locate(completion)
    }

    /// Declared tokens the owner has not given yet, or that the Keychain cannot read now.
    func missingSecrets(_ ext: InstalledExtension) -> [ExtensionSecret] {
        ext.manifest.declaredSecrets.filter { (try? secretStore.read(ExtensionSecretStore.account(ext.id, $0))) == nil }
    }
    func hasSecrets(_ ext: InstalledExtension) -> Bool { ext.manifest.declaredSecrets.count > missingSecrets(ext).count }

    /// Saves the tokens the owner typed in the first-run prompt, by secret id. Unknown ids are ignored.
    func saveSecrets(_ ext: InstalledExtension, _ values: [String: String]) throws {
        for secret in ext.manifest.declaredSecrets {
            guard let value = values[secret.id]?.trimmingCharacters(in: .whitespacesAndNewlines) else { continue }
            try secretStore.write(ExtensionSecretStore.account(ext.id, secret), value)
        }
    }

    /// Settings → Remove Tokens, and uninstall: deletes every token this extension declared.
    func forgetSecrets(_ ext: InstalledExtension) throws {
        for secret in ext.manifest.declaredSecrets { try secretStore.write(ExtensionSecretStore.account(ext.id, secret), nil) }
    }

    /// The request Volant sends for a URL: the declared token for that exact host, if one is saved, as its
    /// header. A token is never attached to any other host.
    private func authorized(_ request: ExtensionRequest, for ext: InstalledExtension) -> ExtensionRequest {
        var request = request
        let host = request.url.host?.lowercased()
        for secret in ext.manifest.declaredSecrets where secret.host == host {
            if let value = try? secretStore.read(ExtensionSecretStore.account(ext.id, secret)) { request.headers[secret.header] = secret.headerValue(value) }
        }
        return request
    }

    /// Enabling also allows the extension's declared hosts; the caller has shown the owner that list.
    /// Disabling leaves host approvals alone, because other extensions may share them.
    func setEnabled(_ ext: InstalledExtension, _ enabled: Bool) throws {
        if enabled && isBlocked(ext) { throw ExtensionError.communityDisabled }
        if enabled { _ = try verifiedModule(ext) }
        if enabled && ext.enabled { try ExtensionHostApprovals.approve(ext.manifest.declaredHosts, at: configURL); reload(); return }
        try ExtensionApproval.update(ext.manifest, enabled: enabled, expected: ext.enabled, at: configURL)
        if enabled { try ExtensionHostApprovals.approve(ext.manifest.declaredHosts, at: configURL) }
        if !enabled, Self.activeExecution?.extensionID == ext.id, Self.activeExecution?.configURL == configURL {
            Self.activeExecution?.finish(.failure(ExtensionError.disabled))
        }
        reload()
    }
    /// Moves a community extension's folder to the Trash, forgets its approval, and removes any host
    /// approvals that no other installed extension declares. Bundled extensions cannot be removed.
    /// Tests pass `remove` so fixtures are deleted rather than put in the owner's Trash.
    @discardableResult
    func uninstall(_ ext: InstalledExtension,
                   remove: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) throws -> [String] {
        guard ext.isCommunity else { throw ExtensionError.runtime("Extensions bundled with Volant cannot be uninstalled.") }
        if Self.activeExecution?.extensionID == ext.id { Self.activeExecution?.finish(.failure(ExtensionError.disabled)) }
        try remove(ext.directory)
        try ExtensionApproval.forget(ext.manifest.id, at: configURL)
        try? dataStore.clear(ext.id)
        try? forgetSecrets(ext)
        try? stopSharingLocation(ext)
        reload()
        return try ExtensionHostApprovals.pruneAfterRemoving(ext.manifest, remaining: extensions.map(\.manifest), at: configURL)
    }

    /// How a catalog listing relates to what is installed. A listing is current only when its version,
    /// module hash, permissions and hosts all match the installed manifest.
    enum CatalogStatus: Hashable {
        case available, installed, update(from: String), bundled
    }
    static func catalogStatus(_ listing: ExtensionCatalog.Listing, installed: [InstalledExtension]) -> CatalogStatus {
        guard let existing = installed.first(where: { $0.id == listing.id }) else { return .available }
        guard existing.isCommunity else { return .bundled }
        let manifest = existing.manifest
        let iconPresent = manifest.icon.map { FileManager.default.fileExists(atPath: existing.directory.appendingPathComponent($0).path) } ?? true
        let current = manifest.version == listing.version && manifest.sha256?.lowercased() == listing.moduleFile.sha256 &&
            manifest.capabilities == listing.capabilities && manifest.declaredHosts == listing.hosts &&
            manifest.iconSha256 == listing.iconFile?.sha256 && iconPresent
        return current ? .installed : .update(from: manifest.version)
    }

    /// Installs or updates a catalog extension from downloaded bytes. The bytes must match the signed
    /// listing, a bundled extension is never replaced, and an unrelated folder already using the ID's
    /// name is left alone. Files are written to a hidden staging folder and moved into place in one
    /// step; an update moves the old folder aside first and puts it back if the move fails.
    ///
    /// Installing never enables or runs the extension. Approval stays bound to the manifest, so an
    /// update with changed code or permissions needs enabling again, while reinstalling identical bytes
    /// keeps the owner's choice. Hosts only the old version declared are pruned like an uninstall.
    /// Tests pass `move` to fail a step deliberately.
    @discardableResult
    func install(_ listing: ExtensionCatalog.Listing, manifest manifestData: Data, module moduleData: Data, icon iconData: Data? = nil,
                 from catalog: ExtensionCatalog,
                 move: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }) throws -> InstalledExtension {
        _ = try listing.verify(manifest: manifestData, module: moduleData, icon: iconData, sha256: Integrity.sha256)
        reload()
        let existing = extensions.first { $0.id == listing.id }
        if let existing, !existing.isCommunity {
            throw ExtensionCatalogError.conflict("\(listing.name) is bundled with Volant and can’t be replaced.")
        }
        let files = FileManager.default
        let root = installDirectory
        let target = existing?.directory ?? root.appendingPathComponent(listing.id, isDirectory: true)
        if existing == nil, files.fileExists(atPath: target.path) {
            throw ExtensionCatalogError.conflict("A folder named \(listing.id) is already in the Extensions folder. Remove it, then install again.")
        }
        let staging = root.appendingPathComponent(".staging-" + UUID().uuidString, isDirectory: true)
        defer { try? files.removeItem(at: staging) }
        do {
            try files.createDirectory(at: staging, withIntermediateDirectories: true)
            try manifestData.write(to: staging.appendingPathComponent("manifest.json"))
            try moduleData.write(to: staging.appendingPathComponent(listing.module))
            if let icon = listing.icon, let iconData { try iconData.write(to: staging.appendingPathComponent(icon)) }
            let origin = ExtensionCatalogOrigin(id: listing.id, version: listing.version, sequence: catalog.sequence,
                                                revision: catalog.revision, source: listing.source)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(origin).write(to: staging.appendingPathComponent(ExtensionCatalogOrigin.fileName))
            if Self.activeExecution?.extensionID == listing.id, Self.activeExecution?.configURL == configURL {
                Self.activeExecution?.finish(.failure(ExtensionError.changed))
            }
            if let existing {
                let previous = root.appendingPathComponent(".previous-" + UUID().uuidString, isDirectory: true)
                try move(existing.directory, previous)
                do { try move(staging, target) } catch {
                    try? move(previous, target)
                    throw error
                }
                try? files.removeItem(at: previous)
            } else {
                try move(staging, target)
            }
        } catch let error as ExtensionCatalogError {
            reload(); throw error
        } catch {
            reload()
            throw ExtensionCatalogError.conflict("Couldn’t install \(listing.name): \(error.localizedDescription)")
        }
        reload()
        if let existing {
            _ = try? ExtensionHostApprovals.pruneAfterRemoving(existing.manifest, remaining: extensions.map(\.manifest), at: configURL)
        }
        guard let installed = extensions.first(where: { $0.id == listing.id }) else {
            throw ExtensionCatalogError.conflict("\(listing.name) was installed but couldn’t be loaded. Check the Extensions folder.")
        }
        return installed
    }

    /// Runs a list extension. With declared hosts it plans, fetches the permitted URLs through the fetch
    /// helper, then renders; without hosts it renders straight away. A plan may instead return items, for
    /// example a row explaining an unusable query, and those are shown without fetching. A render may ask
    /// for another round of URLs with a `state` for the next render, up to `ExtensionNetwork.maximumRounds`
    /// fetches in one run. Approval and hosts are checked again before every fetch and render, so a change
    /// made mid-run stops it. An extension that uses storage receives its saved object with every request,
    /// and any reply's `storage` replaces it (see `save(_:for:run:)`).
    func runItems(_ ext: InstalledExtension, query: String, filter: String? = nil, now: Date = Date(),
                  fetch: @escaping ([ExtensionRequest], [String], @escaping ([ExtensionNetwork.Response]) -> Void) -> Void = ExtensionFetcher.fetch,
                  completion: @escaping (Result<[ExtensionItem], Error>) -> Void) {
        guard !missingLocation(ext) else { completion(.failure(ExtensionError.locationNotAllowed)); return }
        runLocation(ext) { [self] location in
            runItems(ext, query: query, filter: filter, now: now, location: location, fetch: fetch, completion: completion)
        }
    }

    /// One list run with the location this run may send, which plan and every render receive.
    private func runItems(_ ext: InstalledExtension, query: String, filter: String?, now: Date, location: ExtensionLocation?,
                          fetch: @escaping ([ExtensionRequest], [String], @escaping ([ExtensionNetwork.Response]) -> Void) -> Void,
                          completion: @escaping (Result<[ExtensionItem], Error>) -> Void) {
        let hosts = ext.manifest.declaredHosts
        let sequence = beginRun(ext)
        let storage = ext.manifest.usesStorage ? dataStore.load(ext.id) : nil
        func approvedHosts() -> Set<String> { Set(hosts).intersection(ExtensionHostApprovals.approved(at: configURL)) }
        func fetchRound(_ planned: ExtensionNetwork.Fetch, round: Int) {
            fetch(planned.urls.map { self.authorized(ExtensionRequest(url: $0), for: ext) }, Array(approvedHosts()).sorted()) { responses in
                let missing = self.missingHosts(ext)
                guard missing.isEmpty else { completion(.failure(ExtensionNetworkError.hostsNotApproved(missing))); return }
                render(responses, state: planned.state, round: round)
            }
        }
        func render(_ responses: [ExtensionNetwork.Response], state: String?, round: Int) {
            do {
                let input = try ExtensionNetwork.request(phase: "render", query: query, now: now, responses: hosts.isEmpty ? nil : responses,
                                                         storage: storage, state: state, location: location, filter: filter)
                invoke(ext, input) { [self] result in
                    do {
                        let output = try result.get()
                        if let reply = try? ExtensionNetwork.reply(from: output, appLinks: Set(ext.manifest.declaredAppLinks)) {
                            try self.save(reply.storage, for: ext, run: sequence)
                            guard let items = reply.items else { throw ExtensionNetworkError.malformedItems }
                            completion(.success(items)); return
                        }
                        guard !hosts.isEmpty, let planned = try? ExtensionNetwork.plannedFetch(from: output, hosts: approvedHosts()) else {
                            throw ExtensionNetworkError.malformedItems
                        }
                        guard round < ExtensionNetwork.maximumRounds else { throw ExtensionNetworkError.tooManyRounds }
                        let missing = self.missingHosts(ext)
                        guard missing.isEmpty else { throw ExtensionNetworkError.hostsNotApproved(missing) }
                        fetchRound(planned, round: round + 1)
                    } catch { completion(.failure(error)) }
                }
            } catch { completion(.failure(error)) }
        }
        guard !hosts.isEmpty else { render([], state: nil, round: 0); return }
        let missing = missingHosts(ext)
        guard missing.isEmpty else { completion(.failure(ExtensionNetworkError.hostsNotApproved(missing))); return }
        let secrets = missingSecrets(ext)
        guard secrets.isEmpty else { completion(.failure(ExtensionError.secretsMissing(secrets.map(\.title)))); return }
        do {
            invoke(ext, try ExtensionNetwork.request(phase: "plan", query: query, now: now, storage: storage, location: location, filter: filter)) { [self] result in
                do {
                    let output = try result.get()
                    if let reply = try? ExtensionNetwork.reply(from: output, appLinks: Set(ext.manifest.declaredAppLinks)), let items = reply.items {
                        try self.save(reply.storage, for: ext, run: sequence)
                        completion(.success(items)); return
                    }
                    fetchRound(try ExtensionNetwork.plannedFetch(from: output, hosts: approvedHosts()), round: 1)
                } catch { completion(.failure(error)) }
            }
        } catch { completion(.failure(error)) }
    }

    /// What a row's action produced: rows to show instead of the list, a confirmation to show, or
    /// neither, in which case the list runs again.
    struct ActionOutcome: Equatable {
        var items: [ExtensionItem]?
        var notice: String?
    }

    /// Runs a row's action, or with `action` nil tells the extension a row's link was opened. The module
    /// gets the row, the query that produced it and its saved object. An action, never an `opened` notice,
    /// may reply `{"fetch": [{"url", "method": "POST", "json"}], "state"}`: Volant checks approval, hosts
    /// and tokens again, sends those requests with the declared tokens as headers, and renders with the
    /// responses and that state. A reply's `storage` is saved under the same rules as a list run.
    func runAction(_ ext: InstalledExtension, item: ExtensionItem, action: String?, query: String, filter: String? = nil, now: Date = Date(),
                   fetch: @escaping ([ExtensionRequest], [String], @escaping ([ExtensionNetwork.Response]) -> Void) -> Void = ExtensionFetcher.fetch,
                   completion: @escaping (Result<ActionOutcome, Error>) -> Void) {
        let sequence = beginRun(ext)
        let storage = ext.manifest.usesStorage ? dataStore.load(ext.id) : nil
        func outcome(_ output: String) throws -> ActionOutcome {
            let reply = try ExtensionNetwork.reply(from: output, appLinks: Set(ext.manifest.declaredAppLinks))
            try save(reply.storage, for: ext, run: sequence)
            return ActionOutcome(items: reply.items, notice: reply.notice)
        }
        do {
            let input = try ExtensionNetwork.request(phase: action == nil ? "opened" : "action", query: query, now: now,
                                                     storage: storage, action: action, item: item, filter: filter)
            invoke(ext, input) { [self] result in
                do {
                    let output = try result.get()
                    if let done = try? outcome(output) { completion(.success(done)); return }
                    guard action != nil, !ext.manifest.declaredHosts.isEmpty else { throw ExtensionNetworkError.malformedItems }
                    let approved = Set(ext.manifest.declaredHosts).intersection(ExtensionHostApprovals.approved(at: configURL))
                    let submitted = try ExtensionNetwork.submissions(from: output, hosts: approved)
                    let missing = missingHosts(ext)
                    guard missing.isEmpty else { throw ExtensionNetworkError.hostsNotApproved(missing) }
                    let secrets = missingSecrets(ext)
                    guard secrets.isEmpty else { throw ExtensionError.secretsMissing(secrets.map(\.title)) }
                    fetch(submitted.requests.map { self.authorized($0, for: ext) }, Array(approved).sorted()) { responses in
                        do {
                            let render = try ExtensionNetwork.request(phase: "render", query: query, now: now, responses: responses,
                                                                      storage: storage, action: action, item: item, state: submitted.state,
                                                                      filter: filter)
                            self.invoke(ext, render) { result in completion(result.flatMap { output in Result { try outcome(output) } }) }
                        } catch { completion(.failure(error)) }
                    }
                } catch { completion(.failure(error)) }
            }
        } catch { completion(.failure(error)) }
    }

    /// Saved data for an extension that declares storage; `{}` before its first save.
    func storedData(_ ext: InstalledExtension) -> JSONValue { dataStore.load(ext.id) }
    func hasStoredData(_ ext: InstalledExtension) -> Bool { dataStore.hasData(ext.id) }
    /// Clear Data in Settings: forgets the saved object without changing approval.
    func clearStoredData(_ ext: InstalledExtension) throws { try dataStore.clear(ext.id) }

    private static var runSequence = 0
    private static var lastSaved: [String: Int] = [:]

    private func beginRun(_ ext: InstalledExtension) -> Int {
        Self.runSequence += 1
        return Self.runSequence
    }

    /// Saves a reply's storage only when the extension declares storage, is still approved and not
    /// blocked by the community switch, its manifest is unchanged, and no later run has saved since.
    /// Otherwise the reply's storage is discarded and the saved object stays as it was.
    private func save(_ value: JSONValue?, for ext: InstalledExtension, run sequence: Int) throws {
        guard let value, ext.manifest.usesStorage else { return }
        guard !isBlocked(ext), ExtensionApproval.enabled(ext.manifest, at: configURL),
              (try? readManifest(ext.directory)) == ext.manifest, sequence >= Self.lastSaved[ext.id, default: 0] else { return }
        try dataStore.save(value, for: ext.id)
        Self.lastSaved[ext.id] = sequence
    }

    /// Runs the module through the extension helper; tests replace it to return fixed output.
    private func invoke(_ ext: InstalledExtension, _ input: String, completion: @escaping (Result<String, Error>) -> Void) {
        if let invokeOverride { invokeOverride(ext, input, completion) } else { run(ext, input: input, completion: completion) }
    }

    func run(_ ext: InstalledExtension, input: String, completion: @escaping (Result<String, Error>) -> Void) {
        do {
            guard !isBlocked(ext) else { throw ExtensionError.communityDisabled }
            guard ExtensionApproval.enabled(ext.manifest, at: configURL) else { throw ExtensionError.disabled }
            guard !Self.running else { throw ExtensionError.runtime("An extension is already running.") }
            guard input.utf8.count <= ExtensionLimits.maximumInputBytes else { throw ExtensionError.runtime("Extension input exceeds \(ExtensionLimits.inputDescription).") }
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
        case missingModule, hashMismatch, changed, disabled, communityDisabled, secretsMissing([String]), locationNotAllowed, runtime(String)
        var errorDescription: String? {
            switch self {
            case .missingModule: return "Extension module is missing, too large, or outside its folder."
            case .hashMismatch: return "Extension module does not match its manifest hash."
            case .changed: return "Extension changed. Refresh and review it before enabling."
            case .disabled: return "Extension is disabled. Enable it before running."
            case .communityDisabled: return "Community extensions are off. Allow them in Settings → Extensions."
            case .locationNotAllowed: return "Allow this extension to use your approximate location to run it."
            case .secretsMissing(let titles): return "Add your \(titles.joined(separator: " and ")) to use this extension."
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
            let reply: (String?, String?) -> Void = { [weak self] output, error in
                DispatchQueue.main.async {
                    guard let self, self.attempt == token else { return }
                    guard self.approved else { self.finish(.failure(ExtensionManager.ExtensionError.disabled)); return }
                    if let error { self.finish(.failure(ExtensionManager.ExtensionError.runtime(error))) }
                    else if let output, output.utf8.count <= ExtensionLimits.maximumOutputBytes { self.finish(.success(output)) }
                    else { self.finish(.failure(ExtensionManager.ExtensionError.runtime("Invalid extension output."))) }
                }
            }
            if self.manifest.abiVersion == 2 {
                proxy?.runCommand(module: module, input: input, timeout: self.manifest.timeoutSeconds ?? 2, reply: reply)
            } else {
                proxy?.run(module: module, capabilities: self.manifest.capabilities, input: input, timeout: self.manifest.timeoutSeconds ?? 2, reply: reply)
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
