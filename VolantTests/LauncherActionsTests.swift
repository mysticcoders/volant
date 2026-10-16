import XCTest
import CryptoKit
import VolantCore
@testable import Volant

final class LauncherActionsTests: XCTestCase {
    func testRankingResetDrainsWritesAndSurvivesReload() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = UsageStore(url: url)
        store.record(key: "app:fixture", query: "fi")
        store.record(key: "app:fixture", query: "fixture")
        store.record(key: "app:other", query: "other")
        XCTAssertTrue(store.resetRanking(for: "app:fixture"))
        XCTAssertEqual(store.score("app:fixture"), 0)
        XCTAssertNil(store.choice(forQuery: "fi"))
        let loaded = UsageStore(url: url)
        XCTAssertEqual(loaded.score("app:fixture"), 0)
        XCTAssertNil(loaded.choice(forQuery: "fixture"))
        XCTAssertEqual(loaded.choice(forQuery: "other"), "app:other")
        XCTAssertGreaterThan(loaded.score("app:other"), 0)
    }

    /// A launcher over two fictional apps whose clipboard, notes, usage and action config all live
    /// in a temporary folder that is removed after the test.
    private func makeModel(_ apps: [AppEntry]) throws -> LauncherModel {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let model = LauncherModel(index: AppIndex(entries: apps), clipboard: ClipboardStore(retention: 2, storageURL: root.appendingPathComponent("clipboard.sqlite"), encryptionKey: SymmetricKey(size: .bits256)), notes: NotesStore(directory: root.appendingPathComponent("Notes")), config: Preferences(), usage: UsageStore(url: root.appendingPathComponent("usage.sqlite"))) { _ in }
        model.searchesSecondarySources = false
        model.actionConfigURL = root.appendingPathComponent("config.json")
        try Data("{}".utf8).write(to: model.actionConfigURL)
        return model
    }

    func testChatStartsOnlyOnCommandActivation() throws {
        let model = try makeModel([])
        model.query = "ai"
        XCTAssertFalse(model.showingACP, "Searching must not start a chat while typing names such as AirDrop")
        XCTAssertTrue(model.rows.contains(.core(.ai)))
        model.activate(rowID: ResultRow.core(.ai).id)
        XCTAssertTrue(model.showingACP)
        model.query = "airdrop"
        XCTAssertFalse(model.showingACP)
    }

    func testStaleActionCannotCopyOrFavoriteAnotherApp() throws {
        let first = AppEntry(id: "/Fixture.app", name: "Fixture", url: URL(fileURLWithPath: "/Fixture.app"), lastUsed: nil)
        let second = AppEntry(id: "/Other.app", name: "Other", url: URL(fileURLWithPath: "/Other.app"), lastUsed: nil)
        let model = try makeModel([first, second])
        var copied: [String] = []
        model.copyText = { copied.append($0) }
        model.sections = [ResultSection(title: "Apps", rows: [.app(first), .app(second)])]
        model.toggleActions()
        XCTAssertEqual(model.actionTarget?.id, "app:/Fixture.app")
        model.selection = 1
        XCTAssertNil(model.actionTarget)
        model.performAction(.copyName, target: .app(first))
        model.performAction(.favorite, target: .app(first))
        XCTAssertTrue(copied.isEmpty)
        XCTAssertTrue(model.config.favoriteApps.isEmpty)
        model.performAction(.copyName, target: .app(second))
        XCTAssertEqual(copied, ["Other"])
        model.performAction(.favorite, target: .app(second))
        XCTAssertEqual(model.sections.first?.title, "Favorites")
        XCTAssertEqual(model.sections.first?.rows.map(\.id), ["app:/Other.app"])
        model.toggleActions()
        model.sections = []
        XCTAssertNil(model.actionTarget)
    }
}
