import AppKit
import CryptoKit
import VolantCore
import XCTest
@testable import Volant

/// Search Menu Items against a fake input helper: the row while the switch is off, listing and
/// filtering a fictional app's menus, the press flow and its refusals, Accessibility being off,
/// clearing on dismissal, and that nothing about a menu is recorded. No helper runs and no real
/// app is read or pressed.
@MainActor
final class LauncherMenuItemsTests: XCTestCase {
    /// Scripted replies; every call is recorded.
    final class FakeMenuClient: MenuItemsClient {
        var reply: MenuItemsReply?
        var pressReply: MenuPressReply? = MenuPressReply(pressed: true)
        var holdsListing = false
        private(set) var pending: ((MenuItemsReply?) -> Void)?
        private(set) var listings: [(pid: Int32, bundleID: String)] = []
        private(set) var presses: [(pid: Int32, path: [String], bundleID: String)] = []

        init(reply: MenuItemsReply?) { self.reply = reply }

        func menuItems(pid: Int32, bundleID: String, completion: @escaping (MenuItemsReply?) -> Void) {
            listings.append((pid, bundleID))
            if holdsListing { pending = completion; return }
            let reply = reply
            DispatchQueue.main.async { completion(reply) }
        }

        func pressMenuItem(pid: Int32, path: [String], bundleID: String, completion: @escaping (MenuPressReply?) -> Void) {
            presses.append((pid, path, bundleID))
            let reply = pressReply
            DispatchQueue.main.async { completion(reply) }
        }
    }

    private var root: URL!
    private let target = MenuTarget(pid: 4242, bundleID: "com.example.Quill", name: "Quill", path: nil)
    private let fictional = MenuItemsReply(items: [
        MenuItem(path: ["Quill", "Quit Quill"], shortcut: MenuShortcut(key: "Q", modifiers: 0)),
        MenuItem(path: ["File", "Export", "PDF"]),
        MenuItem(path: ["File", "Open Recent", "Harbor Notes.quill"]),
        MenuItem(path: ["Format", "Make Plain Text"], shortcut: MenuShortcut(key: "T", modifiers: MenuShortcut.shift)),
        MenuItem(path: ["Format", "Make Rich Text"], enabled: false)
    ])

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("launcher-menus-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private var actions: [String] = []
    private var dismissals = 0
    private var reopenings = 0
    private var activated: [MenuTarget] = []

    private func model(enabled: Bool = true, client: FakeMenuClient? = nil) -> LauncherModel {
        var config = Preferences()
        config.searchMenuItems = enabled
        let model = LauncherModel(index: AppIndex(entries: []),
            clipboard: ClipboardStore(retention: 10, storageURL: root.appendingPathComponent("clips.sqlite"), encryptionKey: SymmetricKey(size: .bits256)),
            notes: NotesStore(directory: root.appendingPathComponent("Notes")), config: config,
            usage: UsageStore(url: root.appendingPathComponent("usage.sqlite")), files: FileSearch(home: .unavailable)) { [weak self] action in
                self?.actions.append(String(describing: action))
            }
        model.searchesSecondarySources = false
        model.appleShortcuts.loadOverride = { $0([], nil) }
        model.dismiss = { [weak self] in self?.dismissals += 1 }
        model.reopen = { [weak self] in self?.reopenings += 1 }
        model.menuItems.client = client
        model.menuItems.pressDelay = 0
        model.menuItems.activate = { [weak self] in self?.activated.append($0) }
        if enabled { model.menuItems.capture(target) }
        return model
    }

    private func settle() async { try? await Task.sleep(nanoseconds: 80_000_000) }

    func testSwitchOffOffersTheSettingAndNeverCallsTheHelper() async {
        let client = FakeMenuClient(reply: fictional)
        let model = model(enabled: false, client: client)
        model.captureMenuTarget(NSRunningApplication.current)
        model.query = "menus"
        await settle()
        XCTAssertEqual(model.rows.map(\.id), ["command:menu-items-off"])
        XCTAssertNil(model.menuItems.target)
        model.activateSelection()
        XCTAssertEqual(actions, ["menuItemsSettings"])
        XCTAssertEqual(dismissals, 1)
        XCTAssertTrue(client.listings.isEmpty)
        XCTAssertTrue(client.presses.isEmpty)
    }

    func testListsAndFiltersTheCapturedAppsMenus() async throws {
        let client = FakeMenuClient(reply: fictional)
        let model = model(client: client)
        model.query = "menus"
        await settle()
        XCTAssertEqual(client.listings.map(\.pid), [4242])
        XCTAssertEqual(client.listings.map(\.bundleID), ["com.example.Quill"])
        XCTAssertEqual(model.sections.map(\.title), ["Quill Menus"])
        XCTAssertEqual(model.rows.count, 5)
        guard case .menuItem(let last)? = model.rows.last else { return XCTFail("expected a menu item") }
        XCTAssertEqual(last.item.title, "Make Rich Text", "disabled items come last")
        XCTAssertEqual(model.rows.first?.kind, "⌘Q")
        model.query = "menus plain"
        await settle()
        guard case .menuItem(let entry)? = model.selectedRow else { return XCTFail("expected a menu item") }
        XCTAssertEqual(entry.item.path, ["Format", "Make Plain Text"])
        XCTAssertEqual(entry.item.location, "Format")
        XCTAssertEqual(model.selectedRow?.kind, "⇧⌘T")
        model.query = "menu items export"
        await settle()
        XCTAssertEqual(model.rows.compactMap { if case .menuItem(let e) = $0 { return e.item.title }; return nil }.first, "PDF")
        XCTAssertEqual(client.listings.count, 1, "the menus are read once per launcher session")
        model.query = "menus zzzz"
        await settle()
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertEqual(model.notice, "No matching menu items")
    }

    func testReturnHidesActivatesAndPressesByPath() async {
        let client = FakeMenuClient(reply: fictional)
        let model = model(client: client)
        model.query = "menus plain"
        await settle()
        model.activateSelection()
        XCTAssertEqual(dismissals, 1)
        XCTAssertEqual(activated, [target])
        await settle()
        XCTAssertEqual(client.presses.map(\.path), [["Format", "Make Plain Text"]])
        XCTAssertEqual(client.presses.map(\.pid), [4242])
        XCTAssertEqual(client.presses.map(\.bundleID), ["com.example.Quill"])
        XCTAssertEqual(reopenings, 0)
    }

    func testARefusedPressBringsTheLauncherBackWithTheReason() async {
        for refusal in [MenuRefusal.appChanged, .notFound, .appleMenu, .excludedApp] {
            let client = FakeMenuClient(reply: fictional)
            client.pressReply = MenuPressReply(pressed: false, refusal: refusal)
            reopenings = 0
            let model = model(client: client)
            model.query = "menus pdf"
            await settle()
            model.activateSelection()
            model.menuItemsDismissed()
            await settle()
            XCTAssertEqual(reopenings, 1, refusal.rawValue)
            XCTAssertEqual(model.query, "menus")
            XCTAssertEqual(model.actionFeedback, refusal.message)
        }
        let silent = FakeMenuClient(reply: fictional)
        silent.pressReply = nil
        let model = model(client: silent)
        model.query = "menus pdf"
        await settle()
        model.activateSelection()
        await settle()
        XCTAssertEqual(model.actionFeedback, MenuItemsModel.helperUnavailable)
    }

    func testDisabledItemsExplainInsteadOfPressing() async {
        let client = FakeMenuClient(reply: fictional)
        let model = model(client: client)
        model.query = "menus rich"
        await settle()
        model.activateSelection()
        await settle()
        XCTAssertEqual(model.actionFeedback, MenuRefusal.disabled.message)
        XCTAssertTrue(client.presses.isEmpty)
        XCTAssertEqual(dismissals, 0)
    }

    func testAccessibilityOffShowsThePrivacyRow() async {
        let model = model(client: FakeMenuClient(reply: MenuItemsReply(refusal: .notTrusted)))
        model.query = "menus"
        await settle()
        XCTAssertEqual(model.rows.map(\.id), ["privacy:accessibility"])
        XCTAssertEqual(model.actionFeedback, MenuRefusal.notTrusted.message)
    }

    func testRefusalsAndAMissingHelperAreShown() async {
        let refused = model(client: FakeMenuClient(reply: MenuItemsReply(refusal: .excludedApp)))
        refused.query = "menus"
        await settle()
        XCTAssertTrue(refused.rows.isEmpty)
        XCTAssertEqual(refused.notice, MenuRefusal.excludedApp.message)
        let silent = model(client: FakeMenuClient(reply: nil))
        silent.query = "menus"
        await settle()
        XCTAssertEqual(silent.notice, MenuItemsModel.helperUnavailable)
    }

    func testNoAppInFrontExplains() async {
        let client = FakeMenuClient(reply: fictional)
        let model = model(client: client)
        model.captureMenuTarget(NSRunningApplication.current)
        model.query = "menus"
        await settle()
        XCTAssertNil(model.menuItems.target, "Volant itself is never the target")
        XCTAssertEqual(model.notice, MenuItemsModel.noTarget)
        XCTAssertTrue(client.listings.isEmpty)
    }

    func testTruncatedListsSaySo() async {
        var reply = fictional
        reply.truncated = true
        let model = model(client: FakeMenuClient(reply: reply))
        model.query = "menus"
        await settle()
        XCTAssertEqual(model.actionFeedback, "Showing the first 5 menu items.")
    }

    func testDismissalClearsTitlesAndDropsALateReply() async {
        let client = FakeMenuClient(reply: fictional)
        let model = model(client: client)
        model.query = "menus"
        await settle()
        XCTAssertFalse(model.menuItems.items.isEmpty)
        model.menuItemsDismissed()
        XCTAssertTrue(model.menuItems.items.isEmpty)
        XCTAssertNil(model.menuItems.target)
        XCTAssertTrue(model.rows.isEmpty)

        let held = FakeMenuClient(reply: fictional)
        held.holdsListing = true
        let late = self.model(client: held)
        late.query = "menus"
        await settle()
        late.menuItemsDismissed()
        held.pending?(fictional)
        await settle()
        XCTAssertTrue(late.menuItems.items.isEmpty, "a reply after dismissal is dropped")
    }

    func testNothingAboutAMenuIsRecorded() async throws {
        let client = FakeMenuClient(reply: fictional)
        let model = model(client: client)
        model.query = "menus harbor"
        await settle()
        model.activateSelection()
        await settle()
        model.usage.drain()
        XCTAssertEqual(model.usage.score("menu-item:" + fictional.items[2].id), 0)
        XCTAssertNil(model.usage.choice(forQuery: "menus harbor"))
        let stored = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        for file in stored where !file.hasDirectoryPath {
            let bytes = try Data(contentsOf: file)
            XCTAssertNil(bytes.range(of: Data("Harbor Notes".utf8)), file.lastPathComponent)
        }
    }

    func testTheCommandRowOpensTheMenuQuery() async {
        let model = model(client: FakeMenuClient(reply: fictional))
        model.query = "search menu"
        await settle()
        XCTAssertTrue(model.rows.contains { $0.id == "core:menuItems" })
    }

    func testAccessPromptsOnTurningOnAndStopsTheHelperOnlyWhenUnused() {
        final class FakeHost: InputHostClient {
            var prompts: [Bool] = []
            var disconnects = 0
            var trusted = true
            func status(prompt: Bool, completion: @escaping (InputHostStatus?) -> Void) {
                prompts.append(prompt)
                completion(InputHostStatus(trusted: trusted, secureInput: false))
            }
            func beginSession(completion: @escaping (InputSessionStart?) -> Void) {}
            func insert(phrase: String, token: Data, completion: @escaping (InputInsertion?) -> Void) {}
            func endSession(token: Data) {}
            func disconnect() { disconnects += 1 }
        }
        let host = FakeHost()
        var typingUsesHelper = false
        let access = MenuItemsAccess(client: host, canDisconnect: { !typingUsesHelper })
        access.refresh(false)
        XCTAssertTrue(host.prompts.isEmpty, "nothing asks while the switch is off")
        access.chose(true)
        XCTAssertEqual(host.prompts, [true])
        XCTAssertEqual(access.state, .allowed)
        access.refresh(true)
        XCTAssertEqual(host.prompts, [true, false])
        typingUsesHelper = true
        access.chose(false)
        XCTAssertEqual(host.disconnects, 0, "Type at the cursor still uses the helper")
        XCTAssertFalse(access.stoppedHelper)
        access.chose(true)
        typingUsesHelper = false
        access.chose(false)
        XCTAssertEqual(host.disconnects, 1)
        XCTAssertTrue(access.stoppedHelper)
        XCTAssertEqual(access.state, .idle)
    }
}
