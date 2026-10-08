import VolantCore
import XCTest
import AppKit
import CryptoKit
@testable import Volant

final class LauncherAppMenuTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// A launcher model whose links and app commands are recorded instead of performed.
    private func makeModel(notes: @escaping (LauncherAction) -> Void) -> (LauncherModel, () -> [URL], () -> Int) {
        let entry = AppEntry(id: "/Applications/Fixture.app", name: "Fixture", url: URL(fileURLWithPath: "/Applications/Fixture.app"), lastUsed: nil)
        let model = LauncherModel(index: AppIndex(entries: [entry]),
            clipboard: ClipboardStore(retention: 10, storageURL: root.appendingPathComponent("clips.sqlite"), encryptionKey: SymmetricKey(size: .bits256)),
            notes: NotesStore(directory: root.appendingPathComponent("Notes")), config: Preferences(),
            usage: UsageStore(url: root.appendingPathComponent("usage.sqlite")), files: FileSearch(startQuery: { _ in false }), onNote: notes)
        model.searchesSecondarySources = false
        model.appleShortcuts.loadOverride = { $0([], nil) }
        var opened: [URL] = []
        var dismissed = 0
        model.openURL = { opened.append($0) }
        model.dismiss = { dismissed += 1 }
        return (model, { opened }, { dismissed })
    }

    func testItemsAreInMenuOrderAndFilterByTitle() {
        XCTAssertEqual(LauncherMenuItem.matching(""), [.feedback, .manual, .changelog, .updates, .about, .settings, .quit])
        XCTAssertEqual(LauncherMenuItem.matching(" updates "), [.updates])
        XCTAssertEqual(LauncherMenuItem.matching("VOLANT"), [.about, .quit])
        XCTAssertEqual(LauncherMenuItem.matching("nothing like this"), [])
        XCTAssertEqual(LauncherMenuItem.settings.keys, ["⌘", ","])
        XCTAssertEqual(LauncherMenuItem.quit.keys, ["⌘", "Q"])
    }

    func testHeaderAndFeedbackCarryTheVersionAndNothingPersonal() throws {
        let bundle = try XCTUnwrap(Bundle(for: LauncherModel.self))
        let version = try XCTUnwrap(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        XCTAssertEqual(LauncherMenuItem.versionTitle(bundle: bundle), "Volant v" + version)
        let url = LauncherMenuItem.feedbackURL(bundle: bundle, system: OperatingSystemVersion(majorVersion: 27, minorVersion: 1, patchVersion: 0))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "github.com")
        XCTAssertEqual(components.path, "/mysticcoders/volant/issues/new")
        let body = try XCTUnwrap(components.queryItems?.first { $0.name == "body" }?.value)
        XCTAssertTrue(body.contains("Volant \(version) (build"))
        XCTAssertTrue(body.contains("macOS 27.1.0"))
        XCTAssertEqual(components.queryItems?.count, 1)
        XCTAssertFalse(body.contains(NSUserName()))
    }

    func testLinksOpenInTheBrowserAndAppCommandsGoToTheDelegate() {
        var notes: [String] = []
        let (model, opened, dismissed) = makeModel { notes.append(String(describing: $0)) }
        for item in [LauncherMenuItem.manual, .changelog, .feedback] {
            model.showingAppMenu = true
            model.performMenuItem(item)
            XCTAssertFalse(model.showingAppMenu)
        }
        XCTAssertEqual(opened().map(\.absoluteString).prefix(2), [LauncherMenuItem.manualURL.absoluteString, LauncherMenuItem.changelogURL.absoluteString])
        XCTAssertEqual(opened().last?.path, "/mysticcoders/volant/issues/new")
        model.performMenuItem(.updates)
        model.performMenuItem(.about)
        model.performMenuItem(.settings)
        model.performMenuItem(.quit)
        XCTAssertEqual(notes, ["checkForUpdates", "about", "settings", "quit"])
        XCTAssertEqual(dismissed(), 6)
    }

    func testMenuAndItemActionsNeverShowTogetherAndTypingClosesTheMenu() {
        let (model, _, _) = makeModel { _ in }
        model.query = "fix"
        XCTAssertEqual(model.selectedRow?.id, "app:/Applications/Fixture.app")
        model.toggleActions()
        XCTAssertNotNil(model.actionTarget)
        model.toggleAppMenu()
        XCTAssertTrue(model.showingAppMenu)
        XCTAssertNil(model.actionTarget)
        model.toggleActions()
        XCTAssertFalse(model.showingAppMenu)
        XCTAssertNotNil(model.actionTarget)
        model.actionTarget = nil
        model.toggleAppMenu()
        model.query = "fixt"
        XCTAssertFalse(model.showingAppMenu)
        model.toggleAppMenu()
        model.toggleAppMenu()
        XCTAssertFalse(model.showingAppMenu)
    }
}
