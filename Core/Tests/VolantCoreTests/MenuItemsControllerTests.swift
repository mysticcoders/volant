import XCTest
@testable import VolantCore

/// A menu element made of plain values. Reading children and pressing are counted so tests can
/// show the helper never touches an item it refused.
private final class FakeNode: MenuNode {
    let title: String?
    var enabled: Bool
    let commandCharacter: String?
    let commandModifiers: Int?
    var items: [FakeNode]
    var pressResult = true
    private(set) var presses = 0

    init(_ title: String?, enabled: Bool = true, key: String? = nil, modifiers: Int? = nil, _ items: [FakeNode] = []) {
        self.title = title
        self.enabled = enabled
        self.commandCharacter = key
        self.commandModifiers = modifiers
        self.items = items
    }

    func children() -> [MenuNode] { items }

    func press() -> Bool {
        presses += 1
        return pressResult
    }
}

private final class FakeMenus: MenuSystem {
    var trusted = true
    var bundles: [Int32: String] = [42: "com.example.Editor"]
    var regular: Set<Int32> = [42]
    var front: Int32? = 42
    var bar: [FakeNode]?
    private(set) var menuReads = 0

    init(bar: [FakeNode]?) { self.bar = bar }

    func isTrusted() -> Bool { trusted }
    func bundleIdentifier(of pid: Int32) -> String? { bundles[pid] }
    func isRegularApp(_ pid: Int32) -> Bool { regular.contains(pid) }
    func frontmostPID() -> Int32? { front }
    func menuBar(of pid: Int32) -> [MenuNode]? {
        menuReads += 1
        return bar
    }
}

final class MenuItemsControllerTests: XCTestCase {
    private var shutDown: FakeNode!
    private var plainText: FakeNode!
    private var pdf: FakeNode!

    /// An Apple menu with system actions, an app menu, File with a nested Export submenu and a
    /// separator, and Format with a disabled item.
    private func editorBar() -> [FakeNode] {
        shutDown = FakeNode("Shut Down…")
        plainText = FakeNode("Make Plain Text", key: "t", modifiers: MenuShortcut.shift)
        pdf = FakeNode("PDF")
        return [
            FakeNode("Apple", [FakeNode("About This Mac"), shutDown, FakeNode("Log Out Andrew…", key: "q", modifiers: MenuShortcut.shift)]),
            FakeNode("Editor", [FakeNode("Quit Editor", key: "q")]),
            FakeNode("File", [FakeNode("New", key: "n"), FakeNode(""), FakeNode("Export", [pdf, FakeNode("HTML")])]),
            FakeNode("Format", [plainText, FakeNode("Make Rich Text", enabled: false)])
        ]
    }

    private func controller(_ menus: FakeMenus, now: @escaping () -> Date = Date.init) -> MenuItemsController {
        MenuItemsController(system: menus, callerPID: 7, now: now)
    }

    func testListsItemsWithPathsShortcutsAndEnabledStateWithoutTheAppleMenu() {
        let reply = controller(FakeMenus(bar: editorBar())).list(pid: 42, bundleID: "com.example.Editor")
        XCTAssertNil(reply.refusal)
        XCTAssertFalse(reply.truncated)
        XCTAssertEqual(reply.items.map(\.path), [["Editor", "Quit Editor"], ["File", "New"], ["File", "Export", "PDF"], ["File", "Export", "HTML"],
                                                  ["Format", "Make Plain Text"], ["Format", "Make Rich Text"]])
        XCTAssertEqual(reply.items[4].shortcut?.display, "⇧⌘T")
        XCTAssertEqual(reply.items[0].shortcut?.display, "⌘Q")
        XCTAssertFalse(reply.items[5].enabled)
        XCTAssertFalse(reply.items.contains { $0.path.first == "Apple" || $0.title.contains("Shut Down") || $0.title.contains("Log Out") })
    }

    func testPressesTheItemAtThePath() {
        let menus = FakeMenus(bar: editorBar())
        XCTAssertEqual(controller(menus).press(pid: 42, path: ["Format", "Make Plain Text"], bundleID: "com.example.Editor"), MenuPressReply(pressed: true))
        XCTAssertEqual(plainText.presses, 1)
        XCTAssertEqual(controller(menus).press(pid: 42, path: ["File", "Export", "PDF"], bundleID: "com.example.Editor"), MenuPressReply(pressed: true))
        XCTAssertEqual(pdf.presses, 1)
    }

    func testNeverPressesTheAppleMenu() {
        let menus = FakeMenus(bar: editorBar())
        let reply = controller(menus).press(pid: 42, path: ["Apple", "Shut Down…"], bundleID: "com.example.Editor")
        XCTAssertEqual(reply.refusal, .appleMenu)
        XCTAssertEqual(shutDown.presses, 0)
    }

    func testRefusesAChangedMissingDisabledOrSubmenuPath() {
        let menus = FakeMenus(bar: editorBar())
        let refusal = { (path: [String]) in self.controller(menus).press(pid: 42, path: path, bundleID: "com.example.Editor").refusal }
        XCTAssertEqual(refusal(["Format", "Make Plain Text Now"]), .notFound)
        XCTAssertEqual(refusal(["View", "Zoom"]), .notFound)
        XCTAssertEqual(refusal(["File", "Export"]), .notFound, "a submenu is not an item to press")
        XCTAssertEqual(refusal(["Format", "Make Rich Text"]), .disabled)
        plainText.pressResult = false
        XCTAssertEqual(refusal(["Format", "Make Plain Text"]), .failed)
    }

    func testRefusesMalformedPaths() {
        let menus = FakeMenus(bar: editorBar())
        for path in [[], ["File"], ["A", "B", "C", "D", "E"], ["File", ""], ["File", "New\n"], ["File", String(repeating: "x", count: 101)]] {
            XCTAssertEqual(controller(menus).press(pid: 42, path: path, bundleID: "com.example.Editor").refusal, .invalidRequest, "\(path)")
        }
        XCTAssertEqual(menus.menuReads, 0, "a malformed request never reads the menus")
    }

    func testRevalidatesTheTargetForBothCalls() {
        let cases: [(String, (FakeMenus) -> Void, MenuRefusal)] = [
            ("not trusted", { $0.trusted = false }, .notTrusted),
            ("another app in front", { $0.front = 99 }, .appChanged),
            ("nothing in front", { $0.front = nil }, .appChanged),
            ("pid reused by another app", { $0.bundles[42] = "com.example.Other" }, .appChanged),
            ("process gone", { $0.bundles[42] = nil }, .appChanged),
            ("not a regular app", { $0.regular = [] }, .excludedApp)
        ]
        for (name, change, expected) in cases {
            let menus = FakeMenus(bar: editorBar())
            change(menus)
            XCTAssertEqual(controller(menus).list(pid: 42, bundleID: "com.example.Editor").refusal, expected, name)
            XCTAssertEqual(controller(menus).press(pid: 42, path: ["Format", "Make Plain Text"], bundleID: "com.example.Editor").refusal, expected, name)
            XCTAssertEqual(menus.menuReads, 0, name)
            XCTAssertEqual(plainText.presses, 0, name)
        }
    }

    func testRefusesVolantTheLoginWindowAndTheSecurityAgent() {
        for bundle in ["com.apple.loginwindow", "com.apple.SecurityAgent", "com.mysticcoders.volant", "com.mysticcoders.volant.dev", "com.mysticcoders.volant.InputHost"] {
            let menus = FakeMenus(bar: editorBar())
            menus.bundles[42] = bundle
            XCTAssertEqual(controller(menus).list(pid: 42, bundleID: bundle).refusal, .excludedApp, bundle)
            XCTAssertEqual(controller(menus).list(pid: 42, bundleID: "com.example.Editor").refusal, .excludedApp, "actual \(bundle)")
        }
        let menus = FakeMenus(bar: editorBar())
        menus.bundles[7] = "com.example.Editor"
        menus.regular.insert(7)
        menus.front = 7
        XCTAssertEqual(controller(menus).list(pid: 7, bundleID: "com.example.Editor").refusal, .excludedApp, "the caller itself")
        XCTAssertEqual(controller(menus).list(pid: 0, bundleID: "com.example.Editor").refusal, .invalidRequest)
        XCTAssertEqual(controller(menus).list(pid: 42, bundleID: "bad id; rm").refusal, .invalidRequest)
    }

    func testNoMenuBar() {
        XCTAssertEqual(controller(FakeMenus(bar: nil)).list(pid: 42, bundleID: "com.example.Editor").refusal, .noMenuBar)
        XCTAssertEqual(controller(FakeMenus(bar: [FakeNode("Apple")])).list(pid: 42, bundleID: "com.example.Editor").refusal, .noMenuBar)
    }

    func testStopsAtTheItemLimit() {
        let many = (0..<(MenuItemPolicy.maximumItems + 50)).map { FakeNode("Item \($0)") }
        let reply = controller(FakeMenus(bar: [FakeNode("Apple"), FakeNode("Big", many)])).list(pid: 42, bundleID: "com.example.Editor")
        XCTAssertTrue(reply.truncated)
        XCTAssertEqual(reply.items.count, MenuItemPolicy.maximumItems)
    }

    func testSkipsMenusBelowTheDepthLimit() {
        let deep = FakeNode("Deep", [FakeNode("One", [FakeNode("Two", [FakeNode("Three", [FakeNode("Four")])]), FakeNode("Shallow")])])
        let reply = controller(FakeMenus(bar: [FakeNode("Apple"), deep])).list(pid: 42, bundleID: "com.example.Editor")
        XCTAssertEqual(reply.items.map(\.path), [["Deep", "One", "Shallow"]])
        XCTAssertTrue(reply.items.allSatisfy { $0.path.count <= MenuItemPolicy.maximumDepth })
    }

    func testStopsWhenTheTimeBudgetRunsOut() {
        var clock = Date(timeIntervalSince1970: 0)
        let items = (0..<10).map { FakeNode("Item \($0)") }
        let reply = controller(FakeMenus(bar: [FakeNode("Apple"), FakeNode("Slow", items)]), now: {
            clock = clock.addingTimeInterval(1)
            return clock
        }).list(pid: 42, bundleID: "com.example.Editor")
        XCTAssertTrue(reply.truncated)
        XCTAssertLessThan(reply.items.count, 10)
    }

    func testCutsLongTitlesAndPressesByTheCutTitle() {
        let long = String(repeating: "Recent Document ", count: 20)
        let item = FakeNode(long)
        let menus = FakeMenus(bar: [FakeNode("Apple"), FakeNode("File", [FakeNode("Open Recent", [item])])])
        let reply = controller(menus).list(pid: 42, bundleID: "com.example.Editor")
        let path = reply.items[0].path
        XCTAssertEqual(path[2].utf16.count, MenuItemPolicy.maximumTitleUTF16)
        XCTAssertTrue(MenuItemPolicy.isValid(path: path))
        XCTAssertEqual(controller(menus).press(pid: 42, path: path, bundleID: "com.example.Editor"), MenuPressReply(pressed: true))
        XCTAssertEqual(item.presses, 1)
    }

    func testDuplicatePathsAreListedOnce() {
        let menus = FakeMenus(bar: [FakeNode("Apple"), FakeNode("Window", [FakeNode("Notes.txt"), FakeNode("Notes.txt")])])
        XCTAssertEqual(controller(menus).list(pid: 42, bundleID: "com.example.Editor").items.count, 1)
    }

    func testRepliesRoundTripThroughJSON() throws {
        let reply = controller(FakeMenus(bar: editorBar())).list(pid: 42, bundleID: "com.example.Editor")
        XCTAssertEqual(try JSONDecoder().decode(MenuItemsReply.self, from: JSONEncoder().encode(reply)), reply)
    }
}

final class MenuItemsQueryTests: XCTestCase {
    func testPhrasesAndFilters() {
        XCTAssertEqual(MenuItemsQuery.term("menus"), "")
        XCTAssertEqual(MenuItemsQuery.term("  Menus  "), "")
        XCTAssertEqual(MenuItemsQuery.term("menus export pdf"), "export pdf")
        XCTAssertEqual(MenuItemsQuery.term("menu items Export"), "Export")
        XCTAssertEqual(MenuItemsQuery.term("search menus zoom"), "zoom")
        XCTAssertEqual(MenuItemsQuery.term("search menu items"), "")
        XCTAssertNil(MenuItemsQuery.term("menu bar"), "menu bar stays the menu bar hiding toggle")
        XCTAssertNil(MenuItemsQuery.term("menuslate"))
        XCTAssertNil(MenuItemsQuery.term("menu"))
    }

    func testPhrasesAreReservedFromShortcutsAndAliases() {
        XCTAssertTrue(LauncherRouting.isReserved("menus"))
        XCTAssertTrue(LauncherRouting.isReserved("menu items export"))
        XCTAssertTrue(LauncherRouting.isReserved("search menus"))
        XCTAssertFalse(LauncherRouting.isReserved("menu bar"))
    }

    func testTheCommandIsFindableByItsPhrases() {
        XCTAssertEqual(CoreCommand.menuItems.query, "menus")
        XCTAssertTrue(CoreCommand.search("menu items").contains(.menuItems))
        XCTAssertTrue(CoreCommand.search("search menus").contains(.menuItems))
    }

    func testRankingPrefersTitlesThenEnabledItems() {
        let items = [MenuItem(path: ["File", "Export", "PDF"]), MenuItem(path: ["Format", "Make Plain Text"]),
                     MenuItem(path: ["Format", "Make Rich Text"], enabled: false), MenuItem(path: ["Edit", "Paste and Match Style"])]
        XCTAssertEqual(MenuItemSearch.rank(items, term: "").map(\.title), ["PDF", "Make Plain Text", "Paste and Match Style", "Make Rich Text"])
        XCTAssertEqual(MenuItemSearch.rank(items, term: "plain").map(\.title), ["Make Plain Text"])
        XCTAssertEqual(MenuItemSearch.rank(items, term: "export").first?.title, "PDF", "the path finds items by their menu")
        XCTAssertEqual(MenuItemSearch.rank(items, term: "make").map(\.title), ["Make Plain Text", "Make Rich Text"])
        XCTAssertEqual(MenuItemSearch.rank(items, term: "zzz"), [])
        XCTAssertEqual(MenuItemSearch.rank(items, term: "", limit: 2).count, 2)
    }

    func testShortcutDisplay() {
        XCTAssertEqual(MenuShortcut.make(character: "s", modifiers: 0)?.display, "⌘S")
        XCTAssertEqual(MenuShortcut.make(character: "z", modifiers: MenuShortcut.shift)?.display, "⇧⌘Z")
        XCTAssertEqual(MenuShortcut.make(character: "f", modifiers: MenuShortcut.control)?.display, "⌃⌘F")
        XCTAssertEqual(MenuShortcut.make(character: "a", modifiers: MenuShortcut.option | MenuShortcut.noCommand)?.display, "⌥A")
        XCTAssertEqual(MenuShortcut.make(character: "\r", modifiers: 0)?.display, "⌘↩")
        XCTAssertEqual(MenuShortcut.make(character: " ", modifiers: MenuShortcut.control)?.display, "⌃⌘Space")
        XCTAssertNil(MenuShortcut.make(character: nil, modifiers: 0))
        XCTAssertNil(MenuShortcut.make(character: "", modifiers: 0))
        XCTAssertNil(MenuShortcut.make(character: "\u{1}", modifiers: 0))
        XCTAssertNil(MenuShortcut.make(character: "toolong", modifiers: 0))
    }

    func testTheSettingIsOffByDefaultAndNotSynced() throws {
        XCTAssertFalse(Preferences().searchMenuItems)
        XCTAssertFalse(try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8)).searchMenuItems)
        XCTAssertFalse(SettingsSync.keys.contains("searchMenuItems"), "Accessibility features are per-Mac")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("menus-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"unknownField":1}"#.utf8).write(to: url)
        try Preferences.updateBoolean("searchMenuItems", value: true, at: url)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(object["searchMenuItems"] as? Bool, true)
        XCTAssertEqual(object["unknownField"] as? Int, 1)
    }
}
