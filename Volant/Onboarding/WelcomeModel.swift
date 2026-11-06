import AppKit
import AVFoundation
import Combine
import Contacts
import EventKit
import ServiceManagement
import VolantCore

/// A macOS privacy permission the Welcome window can ask for with one click.
enum WelcomePermission: String, CaseIterable, Identifiable {
    case contacts, calendars, microphone
    var id: String { rawValue }

    /// The Privacy & Security pane that holds this permission, for a denied permission's button.
    var settingsURL: URL {
        let anchor: String
        switch self {
        case .contacts: anchor = "Privacy_Contacts"
        case .calendars: anchor = "Privacy_Calendars"
        case .microphone: anchor = "Privacy_Microphone"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?" + anchor)!
    }
}

/// Where one permission stands. Reading it never prompts.
enum WelcomePermissionStatus: Equatable {
    case notDetermined, allowed, denied
}

/// Reads and requests the Welcome window's permissions. Tests inject a fake so no host ever prompts.
protocol WelcomePermissionProvider {
    func status(_ permission: WelcomePermission) -> WelcomePermissionStatus
    func request(_ permission: WelcomePermission, completion: @escaping (WelcomePermissionStatus) -> Void)
}

/// The system's own permission checks: status reads are passive, and only `request` shows a prompt.
struct SystemWelcomePermissions: WelcomePermissionProvider {
    /// Maps each framework's status onto the Welcome window's three states.
    func status(_ permission: WelcomePermission) -> WelcomePermissionStatus {
        switch permission {
        case .contacts:
            switch CNContactStore.authorizationStatus(for: .contacts) {
            case .notDetermined: return .notDetermined
            case .denied, .restricted: return .denied
            default: return .allowed
            }
        case .calendars:
            switch EKEventStore.authorizationStatus(for: .event) {
            case .notDetermined: return .notDetermined
            case .fullAccess: return .allowed
            default: return .denied
            }
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .notDetermined: return .notDetermined
            case .authorized: return .allowed
            default: return .denied
            }
        }
    }

    /// Shows the system prompt for one permission, then reports its new state on the main queue.
    func request(_ permission: WelcomePermission, completion: @escaping (WelcomePermissionStatus) -> Void) {
        let finish: (Bool) -> Void = { granted in
            DispatchQueue.main.async { PermissionGate.end(); completion(granted ? .allowed : .denied) }
        }
        PermissionGate.begin()
        switch permission {
        case .contacts: CNContactStore().requestAccess(for: .contacts) { granted, _ in finish(granted) }
        case .calendars: EKEventStore().requestFullAccessToEvents { granted, _ in finish(granted) }
        case .microphone: AVCaptureDevice.requestAccess(for: .audio) { granted in finish(granted) }
        }
    }
}

/// Open at Login, through the same login-item service as Settings › General.
protocol WelcomeLoginItem {
    var status: SMAppService.Status { get }
    func setEnabled(_ enabled: Bool) throws
}

struct SystemWelcomeLoginItem: WelcomeLoginItem {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    /// Registers or unregisters Volant as a login item.
    func setEnabled(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

/// An agent or agent terminal found on this Mac, offered on the Welcome window's agents page.
struct WelcomeAgent: Identifiable, Equatable {
    enum Kind: Equatable {
        /// An ACP agent AI Chat can connect to, by provider identifier.
        case chat(String)
        case rex, herdr
    }
    let kind: Kind
    let title: String
    /// Whether AI Chat can connect now; agents that need an adapter or Node are set up in Settings.
    let ready: Bool

    var id: String {
        switch kind {
        case .chat(let provider): return "chat:" + provider
        case .rex: return "rex"
        case .herdr: return "herdr"
        }
    }

    /// The status bar source that Show Status turns on.
    var statusSource: String {
        switch kind {
        case .chat: return "ai-chat"
        case .rex: return "rex"
        case .herdr: return "herdr"
        }
    }
}

/// What the Welcome window asks the rest of the app to do. The window never connects, enables or
/// fetches on its own; each of these follows a click.
struct WelcomeActions {
    /// Closes Welcome and shows the launcher with this text in the search field.
    var tryQuery: (String) -> Void = { _ in }
    /// Closes Welcome and opens AI Chat with this provider, as the chat's own setup card does.
    var connectAgent: (String) -> Void = { _ in }
    /// Closes Welcome and shows the extension catalog in the launcher, fetching it then.
    var browseCatalog: () -> Void = {}
    /// Opens Settings at Dictation, where Type at the Cursor is set up.
    var openDictationSettings: () -> Void = {}
    /// Opens Settings at AI, for agents that need an adapter or Node.
    var openAISettings: () -> Void = {}
    /// Reloads the configuration after the window patches it.
    var configChanged: () -> Void = {}
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
}

/// The Welcome window's state: the page shown, the summon shortcut, permissions, agents found and the
/// extensions to turn on. Every change to configuration is a narrow, stale-checked patch.
final class WelcomeModel: ObservableObject {
    @Published var step: WelcomeStep = .shortcut
    @Published private(set) var config: Preferences
    /// False when macOS or another app kept the summon shortcut from registering.
    @Published var summonRegistered: Bool
    @Published private(set) var permissions: [WelcomePermission: WelcomePermissionStatus] = [:]
    @Published private(set) var loginStatus: SMAppService.Status = .notRegistered
    @Published private(set) var agents: [WelcomeAgent] = []
    @Published private(set) var detectingAgents = false
    @Published private(set) var extensions: [InstalledExtension] = []
    @Published var error: String?

    let configURL: URL
    let actions: WelcomeActions
    let dictationAvailable: Bool
    private let permissionProvider: WelcomePermissionProvider
    private let loginItem: WelcomeLoginItem
    private let runningBundleIDs: () -> [String]
    private let detectChatAgents: (@escaping ([ACPAgentAvailability]) -> Void) -> Void
    private let rexInstalled: () -> Bool
    private let herdrInstalled: () -> Bool
    private let makeExtensionManager: () -> ExtensionManager
    private var detection: ACPAgentDetection?
    private var detectionDone: AnyCancellable?

    /// Every system dependency is injected so tests and render fixtures never prompt, connect, register
    /// a login item or read the owner's data.
    init(configURL: URL = Preferences.configURL, config: Preferences, summonRegistered: Bool = true, actions: WelcomeActions = WelcomeActions(),
         permissions: WelcomePermissionProvider = SystemWelcomePermissions(), loginItem: WelcomeLoginItem = SystemWelcomeLoginItem(),
         dictationAvailable: Bool = ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)),
         runningBundleIDs: @escaping () -> [String] = { NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier) },
         detectChatAgents: ((@escaping ([ACPAgentAvailability]) -> Void) -> Void)? = nil,
         rexInstalled: @escaping () -> Bool = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: RexScript.appBundleIdentifier) != nil },
         herdrInstalled: @escaping () -> Bool = { ["/opt/homebrew/bin/herdr", "/usr/local/bin/herdr"].contains { FileManager.default.isExecutableFile(atPath: $0) } },
         makeExtensionManager: (() -> ExtensionManager)? = nil) {
        self.configURL = configURL
        self.config = config
        self.summonRegistered = summonRegistered
        self.actions = actions
        self.permissionProvider = permissions
        self.loginItem = loginItem
        self.dictationAvailable = dictationAvailable
        self.runningBundleIDs = runningBundleIDs
        self.rexInstalled = rexInstalled
        self.herdrInstalled = herdrInstalled
        self.makeExtensionManager = makeExtensionManager ?? { ExtensionManager(configURL: configURL) }
        self.detectChatAgents = detectChatAgents ?? { _ in }
        if detectChatAgents == nil { useHelperDetection() }
    }

    /// Production detection asks the agent helper, as AI Chat's setup card does. It starts nothing.
    private func useHelperDetection() {
        detection = ACPAgentDetection()
    }

    var showingAgents: Bool { !agents.isEmpty }
    var steps: [WelcomeStep] { WelcomeStep.steps(showingAgents: showingAgents) }
    var isLastStep: Bool { WelcomeStep.next(after: step, showingAgents: showingAgents) == nil }
    var isFirstStep: Bool { WelcomeStep.previous(before: step, showingAgents: showingAgents) == nil }
    var shownPermissions: [WelcomePermission] { WelcomePermission.allCases.filter { $0 != .microphone || dictationAvailable } }

    /// Launchers that commonly hold the same shortcut and are running now.
    var competingLaunchers: [String] { WelcomeCompetingLaunchers.names(running: runningBundleIDs()) }

    /// Reads every passive status and starts looking for agents. Called when the window appears.
    func start() {
        refreshPermissions()
        loginStatus = loginItem.status
        reloadExtensions()
        findAgents()
    }

    func next() {
        guard let following = WelcomeStep.next(after: step, showingAgents: showingAgents) else { return }
        step = following
    }

    func back() {
        guard let earlier = WelcomeStep.previous(before: step, showingAgents: showingAgents) else { return }
        step = earlier
    }

    /// Applies a reloaded configuration and whether the summon shortcut registered with it.
    func refresh(config: Preferences, summonRegistered: Bool) {
        self.config = config
        self.summonRegistered = summonRegistered
    }

    /// Saves a new summon shortcut through the same stale-checked patch as Settings.
    func saveSummon(_ value: String, available: (KeyCombo) -> Bool) throws {
        try GlobalShortcutStore.save(key: "summonHotKey", value: value, expectedValue: config.summonHotKey, at: configURL, available: available)
        if let data = try? Data(contentsOf: configURL), let saved = try? JSONDecoder().decode(Preferences.self, from: data) { config = saved }
        actions.configChanged()
    }

    func refreshPermissions() {
        var statuses: [WelcomePermission: WelcomePermissionStatus] = [:]
        for permission in shownPermissions { statuses[permission] = permissionProvider.status(permission) }
        permissions = statuses
    }

    /// Asks for one permission; this click is the only thing that shows a system prompt.
    func request(_ permission: WelcomePermission) {
        permissionProvider.request(permission) { [weak self] status in
            self?.permissions[permission] = status
        }
    }

    func setOpenAtLogin(_ enabled: Bool) {
        do { try loginItem.setEnabled(enabled) } catch { self.error = error.localizedDescription }
        loginStatus = loginItem.status
    }

    /// Looks for chat agents through the helper and for Rex and Herdr by their install locations,
    /// without running any of them.
    func findAgents() {
        var found: [WelcomeAgent] = []
        if rexInstalled() { found.append(WelcomeAgent(kind: .rex, title: "Rex", ready: true)) }
        if herdrInstalled() { found.append(WelcomeAgent(kind: .herdr, title: "Herdr", ready: true)) }
        agents = found
        detectingAgents = true
        let receive: ([ACPAgentAvailability]) -> Void = { [weak self] available in
            guard let self else { return }
            self.detectingAgents = false
            let chat = available.filter { $0.state != .notInstalled }.map {
                WelcomeAgent(kind: .chat($0.provider), title: $0.title, ready: $0.state == .ready)
            }
            self.agents = chat + self.agents.filter { if case .chat = $0.kind { return false }; return true }
        }
        if let detection { detectWithHelper(detection, receive: receive) } else { detectChatAgents(receive) }
    }

    /// Runs one helper detection and reports what it found, or nothing when the helper can't answer.
    private func detectWithHelper(_ detection: ACPAgentDetection, receive: @escaping ([ACPAgentAvailability]) -> Void) {
        detectionDone = detection.$checking.dropFirst().filter { !$0 }.first().sink { [weak detection] _ in
            receive(detection?.agents ?? [])
        }
        detection.detect()
    }

    /// Stops a helper detection still running when the window closes.
    func stop() {
        detection?.cancel()
        detectionDone = nil
    }

    /// Whether this agent's status already shows in the launcher's status bar.
    func showsStatus(_ agent: WelcomeAgent) -> Bool { config.statusBar.sources.contains(agent.statusSource) }

    /// Turns the agent's status bar source on or off with the same patch as Settings › Status Bar.
    func setShowsStatus(_ agent: WelcomeAgent, _ shown: Bool) {
        do {
            try Preferences.updateStatusBar(source: agent.statusSource, enabled: shown, at: configURL)
            if let data = try? Data(contentsOf: configURL), let saved = try? JSONDecoder().decode(Preferences.self, from: data) { config = saved }
            actions.configChanged()
        } catch { self.error = error.localizedDescription }
    }

    /// Built-in extensions, and community ones only when the owner has allowed community extensions.
    func reloadExtensions() {
        let manager = makeExtensionManager()
        manager.reload()
        extensions = manager.communityAllowed ? manager.extensions : manager.extensions.filter { !$0.isCommunity }
    }

    /// Hosts the extension still needs approved before it may turn on.
    func missingHosts(_ ext: InstalledExtension) -> [String] { ExtensionHostApprovals.missing(ext.manifest, at: configURL) }

    /// Turns an extension on or off through the same manager call as Settings › Extensions. Callers
    /// confirm missing hosts first, as Settings does.
    func setEnabled(_ ext: InstalledExtension, _ enabled: Bool) {
        do { try makeExtensionManager().setEnabled(ext, enabled); actions.configChanged() }
        catch { self.error = error.localizedDescription }
        reloadExtensions()
    }

    /// Records that this Mac has seen the Welcome window; closing it at any page counts.
    static func markCompleted(at url: URL = Preferences.configURL) throws {
        try Preferences.updateBoolean("welcomeCompleted", value: true, at: url)
    }
}
