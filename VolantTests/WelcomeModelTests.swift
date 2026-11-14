import CryptoKit
import XCTest
import ServiceManagement
import VolantCore
@testable import Volant

/// The Welcome window's model with every system dependency faked: no permission prompt, login item,
/// helper connection or owner file is touched. Configuration and extensions live in a temporary folder.
@MainActor
final class WelcomeModelTests: XCTestCase {
    private var root: URL!
    private var config: URL { root.appendingPathComponent("config.json") }
    private var folder: URL { root.appendingPathComponent("weather", isDirectory: true) }

    /// Permission states set by the test; requests record what was asked and answer with `grants`.
    final class FakePermissions: WelcomePermissionProvider {
        var statuses: [WelcomePermission: WelcomePermissionStatus] = [:]
        var grants = true
        private(set) var requested: [WelcomePermission] = []
        func status(_ permission: WelcomePermission) -> WelcomePermissionStatus { statuses[permission] ?? .notDetermined }
        func request(_ permission: WelcomePermission, completion: @escaping (WelcomePermissionStatus) -> Void) {
            requested.append(permission)
            completion(grants ? .allowed : .denied)
        }
    }

    final class FakeLoginItem: WelcomeLoginItem {
        var status: SMAppService.Status = .notRegistered
        func setEnabled(_ enabled: Bool) throws { status = enabled ? .enabled : .notRegistered }
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("welcome-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"summonHotKey":"option+space","extensions":{},"futureSetting":7}"#.utf8).write(to: config)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func makeModel(permissions: FakePermissions = FakePermissions(), loginItem: FakeLoginItem = FakeLoginItem(), dictation: Bool = true,
                           running: [String] = [], chat: [ACPAgentAvailability] = [], rex: Bool = false, herdr: Bool = false,
                           actions: WelcomeActions = WelcomeActions()) -> WelcomeModel {
        let preferences = try! JSONDecoder().decode(Preferences.self, from: Data(contentsOf: config))
        let configURL = config, roots = [folder], data = root.appendingPathComponent("ExtensionData")
        return WelcomeModel(configURL: configURL, config: preferences, actions: actions, permissions: permissions, loginItem: loginItem,
                            dictationAvailable: dictation, runningBundleIDs: { running }, detectChatAgents: { reply in reply(chat) },
                            rexInstalled: { rex }, herdrInstalled: { herdr },
                            makeExtensionManager: { ExtensionManager(configURL: configURL, roots: roots, dataDirectory: data) })
    }

    /// A fictional extension; with `hosts` it needs host approval before it may turn on.
    private func writeExtension(hosts: [String]? = nil) throws {
        let module = Data([0, 97, 115, 109, 1, 0, 0, 0, 5, 4, 1, 1, 1, 1])
        try module.write(to: folder.appendingPathComponent("weather.wasm"))
        let manifest = ExtensionManifest(id: "community.fictional.weather", name: "Fictional Weather", version: "1", module: "weather.wasm",
                                         capabilities: [], timeoutSeconds: 2, sha256: Integrity.sha256(module), hosts: hosts, output: "items")
        try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent("manifest.json"))
    }

    func testPermissionsShowTheirStateWithoutPromptingUntilClicked() {
        let permissions = FakePermissions()
        permissions.statuses = [.contacts: .allowed, .calendars: .denied]
        let model = makeModel(permissions: permissions)
        model.start()
        XCTAssertEqual(model.permissions[.contacts], .allowed)
        XCTAssertEqual(model.permissions[.calendars], .denied)
        XCTAssertEqual(model.permissions[.microphone], .notDetermined)
        XCTAssertEqual(permissions.requested, [], "opening the page never prompts")
        model.request(.microphone)
        XCTAssertEqual(permissions.requested, [.microphone])
        XCTAssertEqual(model.permissions[.microphone], .allowed)
        permissions.grants = false
        model.request(.calendars)
        XCTAssertEqual(model.permissions[.calendars], .denied)
    }

    func testMicrophoneIsHiddenWithoutDictation() {
        let model = makeModel(dictation: false)
        model.start()
        XCTAssertEqual(model.shownPermissions, [.contacts, .calendars])
        XCTAssertNil(model.permissions[.microphone])
    }

    func testAgentsPageIsHiddenWhenNothingIsFound() {
        let model = makeModel()
        model.start()
        XCTAssertTrue(model.agents.isEmpty)
        XCTAssertEqual(model.steps, [.shortcut, .typing, .access, .extensions])
        model.step = .access
        model.next()
        XCTAssertEqual(model.step, .extensions)
    }

    func testFoundAgentsAddTheAgentsPageAndConnectOnlyOnClick() {
        var connected: [String] = []
        let chat = [ACPAgentAvailability(provider: "claude", state: .ready, detail: "", path: "/fictional/claude"),
                    ACPAgentAvailability(provider: "codex", state: .needsAdapter, detail: "Needs an adapter", path: nil),
                    ACPAgentAvailability(provider: "opencode", state: .notInstalled, detail: "", path: nil)]
        let model = makeModel(chat: chat, rex: true, actions: WelcomeActions(connectAgent: { connected.append($0) }))
        model.start()
        XCTAssertEqual(model.agents.map(\.id), ["chat:claude", "chat:codex", "rex"], "agents that aren't installed are left out")
        XCTAssertEqual(model.agents.first?.ready, true)
        XCTAssertEqual(model.agents.dropFirst().first?.ready, false)
        XCTAssertEqual(model.steps, [.shortcut, .typing, .access, .agents, .extensions])
        XCTAssertEqual(connected, [], "finding an agent never connects to it")
        model.actions.connectAgent("claude")
        XCTAssertEqual(connected, ["claude"])
    }

    func testShowStatusPatchesTheStatusBarAndKeepsOtherFields() throws {
        let model = makeModel(rex: true)
        model.start()
        let rex = try XCTUnwrap(model.agents.first)
        XCTAssertFalse(model.showsStatus(rex))
        model.setShowsStatus(rex, true)
        XCTAssertTrue(model.showsStatus(rex))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any])
        XCTAssertEqual((object["statusBar"] as? [String: Any])?["sources"] as? [String], ["rex"])
        XCTAssertEqual(object["futureSetting"] as? Int, 7)
    }

    func testSummonShortcutSavesThroughTheStaleCheckedPatch() throws {
        var reloads = 0
        let model = makeModel(actions: WelcomeActions(configChanged: { reloads += 1 }))
        try model.saveSummon("ctrl+space", available: { _ in true })
        XCTAssertEqual(model.config.summonHotKey, "ctrl+space")
        XCTAssertEqual(reloads, 1)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any])
        XCTAssertEqual(object["futureSetting"] as? Int, 7)
        XCTAssertThrowsError(try model.saveSummon("ctrl+k", available: { _ in false }), "a shortcut another app holds is refused")
        XCTAssertEqual(model.config.summonHotKey, "ctrl+space")
    }

    func testRunningLaunchersAreNamed() {
        XCTAssertEqual(makeModel(running: ["com.raycast.macos", "com.apple.Safari"]).competingLaunchers, ["Raycast"])
        XCTAssertEqual(makeModel().competingLaunchers, [])
    }

    /// Coming back from System Settings reads permissions and Open at Login again, without prompting,
    /// so a row turned on there no longer offers Open System Settings.
    func testReturningToVolantRereadsAccess() {
        let permissions = FakePermissions()
        permissions.statuses[.contacts] = .denied
        let login = FakeLoginItem()
        let model = makeModel(permissions: permissions, loginItem: login)
        model.start()
        XCTAssertEqual(model.permissions[.contacts], .denied)
        permissions.statuses[.contacts] = .allowed
        login.status = .requiresApproval
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        XCTAssertEqual(model.permissions[.contacts], .allowed)
        XCTAssertEqual(model.loginStatus, .requiresApproval)
        XCTAssertTrue(permissions.requested.isEmpty, "Reading access never prompts")
        model.stop()
        permissions.statuses[.contacts] = .denied
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        XCTAssertEqual(model.permissions[.contacts], .allowed, "A closed Welcome window stops listening")
    }

    func testOpenAtLoginUsesTheLoginItem() {
        let login = FakeLoginItem()
        let model = makeModel(loginItem: login)
        model.start()
        XCTAssertEqual(model.loginStatus, .notRegistered)
        model.setOpenAtLogin(true)
        XCTAssertEqual(model.loginStatus, .enabled)
    }

    func testCommunityExtensionsStayHiddenUntilAllowed() throws {
        try writeExtension()
        let model = makeModel()
        model.start()
        XCTAssertEqual(model.extensions.count, 0, "the community gate stays in Settings, as there")
    }

    func testExtensionsStartOffAndHostsAreConfirmedFirst() throws {
        try Data(#"{"summonHotKey":"option+space","extensions":{},"communityExtensionsAllowed":true,"futureSetting":7}"#.utf8).write(to: config)
        try writeExtension(hosts: ["weather.example.com"])
        let model = makeModel()
        model.start()
        let ext = try XCTUnwrap(model.extensions.first)
        XCTAssertFalse(ext.enabled, "the Welcome window never enables anything on its own")
        XCTAssertEqual(model.missingHosts(ext), ["weather.example.com"])
        model.setEnabled(ext, true)
        XCTAssertEqual(model.extensions.first?.enabled, true)
        XCTAssertEqual(model.missingHosts(try XCTUnwrap(model.extensions.first)), [])
    }

    func testCompletionIsRecordedAndOtherFieldsSurvive() throws {
        try WelcomeModel.markCompleted(at: config)
        let saved = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: config))
        XCTAssertEqual(saved.welcomeCompleted, true)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any])
        XCTAssertEqual(object["futureSetting"] as? Int, 7)
    }

    func testWelcomeCommandClosesTheLauncherAndAsksForTheWindow() throws {
        final class Notes { var welcome = 0; var dismissed = 0 }
        let notes = Notes()
        let clipboard = ClipboardStore(retention: 1, storageURL: root.appendingPathComponent("clip.sqlite"), encryptionKey: SymmetricKey(size: .bits256))
        let model = LauncherModel(index: AppIndex(entries: []), clipboard: clipboard, notes: NotesStore(directory: root.appendingPathComponent("Notes")),
                                  config: Preferences(), usage: UsageStore(url: root.appendingPathComponent("usage.sqlite"))) { action in
            if case .welcome = action { notes.welcome += 1 }
        }
        model.searchesSecondarySources = false
        model.dismiss = { notes.dismissed += 1 }
        model.query = "welcome"
        XCTAssertTrue(model.rows.contains { $0.id == "core:welcome" }, "typing welcome finds the command")
        model.activate(rowID: "core:welcome")
        XCTAssertEqual(notes.welcome, 1)
        XCTAssertEqual(notes.dismissed, 1)
    }
}
