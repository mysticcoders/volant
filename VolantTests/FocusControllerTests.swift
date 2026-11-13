import XCTest
import CryptoKit
import VolantCore
@testable import Volant

final class FocusControllerTests: XCTestCase {
    private var root: URL!
    private var now = Date(timeIntervalSince1970: 1_800_000_000)
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: "focus-tests-" + UUID().uuidString)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var stateURL: URL { root.appendingPathComponent("focus-session.json") }

    private func controller(restore: Bool = false) -> FocusController {
        FocusController(stateURL: stateURL, defaults: defaults, clock: { [unowned self] in self.now },
                        frontmost: { nil }, automaticTimer: false, restore: restore)
    }

    private let setup = FocusSetup(goal: "Write", minutes: 25, apps: ["com.tinyspeck.slackmacgap"], websites: ["x.com"], categories: [])

    func testHidesBlockedAppsAndRemindsWithTheGoal() {
        let focus = controller()
        focus.start(setup)
        var hidden = 0
        focus.handleActivation(bundleIdentifier: "com.apple.Safari", name: "Safari") { hidden += 1; return true }
        XCTAssertEqual(hidden, 0)
        XCTAssertNil(focus.reminder)
        focus.handleActivation(bundleIdentifier: "com.tinyspeck.slackmacgap", name: "Slack") { hidden += 1; return true }
        XCTAssertEqual(hidden, 1)
        XCTAssertEqual(focus.reminder?.name, "Slack")
        XCTAssertEqual(focus.reminder?.goal, "Write")
    }

    func testSnoozeLetsTheAppThroughForTheSnoozeLength() throws {
        let focus = controller()
        focus.start(setup)
        focus.handleActivation(bundleIdentifier: "com.tinyspeck.slackmacgap", name: "Slack") { true }
        focus.snooze(try XCTUnwrap(focus.reminder), minutes: 3)
        XCTAssertNil(focus.reminder)
        var hidden = false
        now += 120
        focus.handleActivation(bundleIdentifier: "com.tinyspeck.slackmacgap", name: "Slack") { hidden = true; return true }
        XCTAssertFalse(hidden)
        now += 61
        focus.handleActivation(bundleIdentifier: "com.tinyspeck.slackmacgap", name: "Slack") { hidden = true; return true }
        XCTAssertTrue(hidden)
    }

    func testPausedSessionsBlockNothing() {
        let focus = controller()
        focus.start(setup)
        focus.pause()
        var hidden = false
        focus.handleActivation(bundleIdentifier: "com.tinyspeck.slackmacgap", name: "Slack") { hidden = true; return true }
        XCTAssertFalse(hidden)
        XCTAssertEqual(focus.timeText(), "25:00")
    }

    func testRunningOutCompletesAndCelebrates() {
        let focus = controller()
        var celebrated = 0
        focus.onComplete = { celebrated += 1 }
        focus.start(setup)
        now += 24 * 60
        focus.tick()
        XCTAssertEqual(focus.timeText(), "1:00")
        now += 60
        focus.tick()
        XCTAssertFalse(focus.isRunning)
        XCTAssertEqual(celebrated, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stateURL.path))
    }

    func testEndingDoesNotCelebrate() {
        let focus = controller()
        var celebrated = false
        focus.onComplete = { celebrated = true }
        focus.start(setup)
        focus.end()
        XCTAssertFalse(focus.isRunning)
        XCTAssertFalse(celebrated)
    }

    func testSessionSurvivesRelaunchUntilItRunsOut() {
        controller().start(setup)
        now += 10 * 60
        let relaunched = controller(restore: true)
        XCTAssertEqual(relaunched.session?.setup.goal, "Write")
        XCTAssertEqual(relaunched.timeText(), "15:00")
        now += 20 * 60
        XCTAssertNil(controller(restore: true).session)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stateURL.path))
    }

    func testClockText() {
        XCTAssertEqual(FocusController.clockText(59.2), "1:00")
        XCTAssertEqual(FocusController.clockText(25 * 60), "25:00")
        XCTAssertEqual(FocusController.clockText(3_725), "1:02:05")
    }

    func testPlacementIsRememberedAndAnEarlierDockedChoiceKeepsTheMenuBar() {
        XCTAssertEqual(controller().placement, .notch)
        controller().placement = .floating
        XCTAssertEqual(controller().placement, .floating)
        let legacy = UserDefaults(suiteName: "focus-legacy-" + UUID().uuidString)!
        legacy.set(true, forKey: FocusController.legacyDockedKey)
        defaults = legacy
        XCTAssertEqual(controller().placement, .menuBar)
    }

    func testCompletionIsRecordedForTheNotch() {
        let focus = controller()
        focus.start(setup)
        focus.end()
        XCTAssertNil(focus.completedAt)
        focus.start(setup)
        focus.complete()
        XCTAssertEqual(focus.completedAt, now)
    }
}

final class FocusNotchTests: XCTestCase {
    func testNotchSitsBetweenTheAreasBesideIt() {
        let frame = NSRect(x: 0, y: 0, width: 1512, height: 982)
        let notch = NotchGeometry.notch(frame: frame, topInset: 32, left: NSRect(x: 0, y: 950, width: 661, height: 32),
                                        right: NSRect(x: 851, y: 950, width: 661, height: 32))
        XCTAssertEqual(notch, NSRect(x: 661, y: 950, width: 190, height: 32))
    }

    func testScreensWithoutANotchHaveNone() {
        let frame = NSRect(x: 0, y: 0, width: 2560, height: 1440)
        XCTAssertNil(NotchGeometry.notch(frame: frame, topInset: 0, left: nil, right: nil))
        XCTAssertNil(NotchGeometry.notch(frame: frame, topInset: 32, left: .zero, right: .zero))
    }

    func testNotchPlacementFallsBackToTheFloatingBar() {
        XCTAssertEqual(FocusBarPlacement.notch.resolved(hasNotch: true), .notch)
        XCTAssertEqual(FocusBarPlacement.notch.resolved(hasNotch: false), .floating)
        XCTAssertEqual(FocusBarPlacement.menuBar.resolved(hasNotch: true), .menuBar)
    }
}

final class FocusRowTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testIdleRowsOfferSetupAndQuickStart() {
        XCTAssertEqual(FocusRow.rows(for: .menu, session: nil), [.setUp, .quickStart(minutes: nil, goal: nil)])
        XCTAssertEqual(FocusRow.rows(for: .start(.minutes(45), goal: "Read"), session: nil), [.quickStart(minutes: 45, goal: "Read"), .setUp])
        XCTAssertEqual(FocusRow.rows(for: .pause, session: nil), [.setUp, .quickStart(minutes: nil, goal: nil)])
    }

    func testRunningRowsControlTheSessionAndPutTheAskedOneFirst() {
        var session = FocusSession(setup: FocusSetup(goal: "Write", categories: [.social]), at: start)
        XCTAssertEqual(FocusRow.rows(for: .menu, session: session), [.pause, .complete, .edit, .end])
        XCTAssertEqual(FocusRow.rows(for: .end, session: session), [.end, .pause, .complete, .edit])
        session.pause(at: start)
        XCTAssertEqual(FocusRow.rows(for: .pause, session: session), [.resume, .complete, .edit, .end])
    }

    func testSummaryNamesGoalLengthAndCount() {
        XCTAssertEqual(FocusRow.summary(FocusSetup(goal: "Write", minutes: 25, apps: ["com.a"], websites: ["x.com"], categories: [])), "Write · 25 min · 2 blocked")
        XCTAssertEqual(FocusRow.summary(FocusSetup(goal: "", minutes: nil, categories: [])), "No goal · Until ended · 0 blocked")
    }
}

final class FocusDraftTests: XCTestCase {
    func testBuildsTheSetupFromItsChips() {
        let draft = FocusDraft(setup: FocusSetup(goal: "Old", minutes: 30, apps: ["com.a"], websites: ["x.com"], categories: [.news]),
                               expected: FocusPreferences(), appName: { _ in "App A" })
        XCTAssertEqual(draft.blocks.map(\.title), ["News", "App A", "x.com"])
        draft.remove(.website("x.com"))
        draft.add(.website("reddit.com"))
        draft.add(.website("reddit.com"))
        draft.minutes = nil
        let setup = draft.setup(goal: " New ")
        XCTAssertEqual(setup, FocusSetup(goal: "New", minutes: nil, apps: ["com.a"], websites: ["reddit.com"], categories: [.news]))
    }

    func testSuggestsCategoriesAndTypedWebsitesNotYetAdded() {
        let draft = FocusDraft(setup: FocusSetup(categories: [.social]), expected: FocusPreferences(), appName: { $0 })
        XCTAssertFalse(draft.suggestions(apps: { _ in [] }).contains(.category(.social)))
        XCTAssertEqual(draft.suggestions(apps: { _ in [] }).first, .category(.news))
        draft.addText = "https://www.youtube.com/watch"
        XCTAssertEqual(draft.suggestions(apps: { _ in [] }).first, .website("youtube.com"))
        draft.addText = "news"
        XCTAssertEqual(draft.suggestions(apps: { _ in [] }), [.category(.news)])
    }
}

final class LauncherFocusTests: XCTestCase {
    private var root: URL!
    private var model: LauncherModel!
    private var focus: FocusController!
    private var config: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        config = root.appendingPathComponent("config.json")
        try Data(#"{"future":1,"focus":{"lastSetup":{"goal":"Write","minutes":30,"categories":["social"]}}}"#.utf8).write(to: config)
        focus = FocusController(stateURL: root.appendingPathComponent("focus.json"), defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                frontmost: { nil }, automaticTimer: false, restore: false)
        model = LauncherModel(index: AppIndex(entries: []),
                              clipboard: ClipboardStore(retention: 2, storageURL: root.appendingPathComponent("clipboard.sqlite"), encryptionKey: SymmetricKey(size: .bits256)),
                              notes: NotesStore(directory: root.appendingPathComponent("Notes")),
                              config: try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: config)),
                              usage: UsageStore(url: root.appendingPathComponent("usage.sqlite")), focus: focus) { _ in }
        model.searchesSecondarySources = false
        model.actionConfigURL = config
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testQuickStartUsesTheRememberedBlockListAndRemembersTheGoal() throws {
        model.query = "focus 45m Read the spec"
        XCTAssertEqual(model.selectedRow?.id, "focus:start:45:Read the spec")
        model.activateSelection()
        XCTAssertEqual(focus.session?.setup.goal, "Read the spec")
        XCTAssertEqual(focus.session?.setup.minutes, 45)
        XCTAssertEqual(focus.session?.setup.categories, [.social])
        let saved = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: config))
        XCTAssertEqual(saved.focus.lastSetup.goal, "Read the spec")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any])
        XCTAssertEqual(object["future"] as? Int, 1)
    }

    func testRunningSessionRowsControlIt() {
        focus.start(FocusSetup(goal: "Write", categories: [.social]))
        model.query = "focus"
        XCTAssertEqual(model.selectedRow?.id, "focus:pause")
        model.activateSelection()
        XCTAssertEqual(focus.session?.isPaused, true)
        XCTAssertEqual(model.selectedRow?.id, "focus:resume")
        model.query = "focus stop"
        model.activateSelection()
        XCTAssertFalse(focus.isRunning)
    }

    func testFormRequiresSomethingToBlockThenStarts() throws {
        model.query = "focus"
        model.activateSelection()
        let draft = try XCTUnwrap(model.entryForm)
        XCTAssertEqual(draft.kind, .focus)
        XCTAssertEqual(draft.name, "Write")
        let form = try XCTUnwrap(draft.focus)
        form.blocks = []
        XCTAssertFalse(model.saveEntry(draft))
        XCTAssertNotNil(draft.error)
        form.add(.website("youtube.com"))
        draft.name = "Edit the video"
        XCTAssertTrue(model.saveEntry(draft))
        XCTAssertNil(model.entryForm)
        XCTAssertEqual(focus.session?.setup.websites, ["youtube.com"])
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: config)).focus.lastSetup.goal, "Edit the video")
    }

    func testFocusIsAReservedWordAndACommand() {
        XCTAssertTrue(LauncherRouting.isReserved("focus 25m"))
        XCTAssertTrue(CoreCommand.search("block websites").contains(.focus))
    }
}

/// A browser stand-in that shows one tab per address and records what Focus did to it.
final class FakeFocusBrowsers: FocusBrowserAccess {
    var address = "https://x.com/home"
    var denied = false
    var blanked: [String] = []
    var restored: [String] = []
    var showing: [String: String] = [:]

    func currentTab(of browser: FocusBrowser) throws -> FocusOpenTab? {
        if denied { throw FocusBrowserFailure.denied }
        let key = NSAppleEventDescriptor(string: address)
        return FocusOpenTab(browser: browser, window: NSAppleEventDescriptor(int32: 1), tab: key, address: showing[address] ?? address)
    }

    func blank(_ tab: FocusOpenTab) throws {
        blanked.append(tab.address)
        showing[tab.address] = "about:blank"
    }

    func restore(_ tab: FocusOpenTab) throws -> Bool {
        restored.append(tab.address)
        showing[tab.address] = nil
        return true
    }
}

final class FocusBrowserTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 1_800_000_000)
    private var front: String? = "com.google.Chrome"
    private let fake = FakeFocusBrowsers()

    private func controller() -> FocusController {
        FocusController(stateURL: FileManager.default.temporaryDirectory.appendingPathComponent("focus-\(UUID().uuidString).json"),
                        defaults: UserDefaults(suiteName: "focus-browser-" + UUID().uuidString)!, clock: { [unowned self] in self.now },
                        frontmost: { nil }, automaticTimer: false, restore: false, browsers: fake, browserQueue: nil,
                        frontmostBundle: { [unowned self] in self.front })
    }

    private let setup = FocusSetup(goal: "Write", minutes: 25, websites: ["x.com"], categories: [])

    func testBlanksABlockedTabAndRemindsWithTheSite() {
        let focus = controller()
        focus.start(setup)
        focus.tick()
        XCTAssertEqual(fake.blanked, ["https://x.com/home"])
        XCTAssertEqual(focus.reminder?.target, .website("x.com"))
        XCTAssertEqual(focus.reminder?.name, "x.com")
        focus.tick()
        XCTAssertEqual(fake.blanked.count, 1, "A blank page is never blanked again")
    }

    func testLeavesOtherSitesAndOtherAppsAlone() {
        let focus = controller()
        focus.start(setup)
        fake.address = "https://notx.com/"
        focus.tick()
        front = "com.apple.TextEdit"
        fake.address = "https://x.com/"
        focus.tick()
        front = "org.mozilla.firefox"
        focus.tick()
        XCTAssertTrue(fake.blanked.isEmpty)
    }

    func testSnoozeRestoresThatSitesTabsAndLetsItThrough() throws {
        let focus = controller()
        focus.start(setup)
        focus.tick()
        focus.snooze(try XCTUnwrap(focus.reminder), minutes: 3)
        XCTAssertEqual(fake.restored, ["https://x.com/home"])
        focus.tick()
        XCTAssertEqual(fake.blanked.count, 1)
        now += 181
        focus.tick()
        XCTAssertEqual(fake.blanked.count, 2)
    }

    func testEndingPausingOrEditingRestoresTabs() {
        let focus = controller()
        focus.start(setup)
        focus.tick()
        focus.pause()
        XCTAssertEqual(fake.restored.count, 1)
        focus.tick()
        XCTAssertEqual(fake.blanked.count, 1, "A paused session asks nothing")
        focus.resume()
        focus.tick()
        focus.edit(FocusSetup(goal: "Write", minutes: 25, websites: ["reddit.com"], categories: []))
        XCTAssertEqual(fake.restored.count, 2)
        fake.address = "https://reddit.com/"
        focus.tick()
        focus.end()
        XCTAssertEqual(fake.restored.count, 3)
    }

    func testARefusedBrowserIsNotAskedAgain() {
        let focus = controller()
        fake.denied = true
        focus.start(setup)
        focus.tick()
        XCTAssertEqual(focus.refusedBrowsers, ["com.google.Chrome"])
        fake.denied = false
        focus.tick()
        XCTAssertTrue(fake.blanked.isEmpty)
    }

    func testSessionsWithoutWebsitesNeverAsk() {
        let focus = controller()
        focus.start(FocusSetup(goal: "Write", apps: ["com.example.chat"], categories: []))
        focus.tick()
        XCTAssertTrue(fake.blanked.isEmpty)
    }

    func testEverySupportedBrowserHasAnAppleEventsException() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Volant/Volant.entitlements"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let allowed = Set(plist["com.apple.security.temporary-exception.apple-events"] as? [String] ?? [])
        for browser in FocusBrowser.all { XCTAssertTrue(allowed.contains(browser.bundleIdentifier), browser.name) }
    }
}
