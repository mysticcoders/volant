import XCTest
import VolantCore
@testable import Volant

@MainActor final class AppleShortcutsTests: XCTestCase {
    private let first = VolantCore.AppleShortcut(id: "11111111-1111-4111-8111-111111111111", name: "Recipes (家族)")
    private let second = VolantCore.AppleShortcut(id: "22222222-2222-4222-8222-222222222222", name: "Recipes (家族)")

    func testIdentifiersNamesAndMalformedCatalog() throws {
        let text = "\(first.name) (\(first.id))\n\(second.name) (\(second.id))\n\(first.name) (\(first.id))\n"
        let entries = try VolantCore.AppleShortcut.decodeListing(Data(text.utf8))
        XCTAssertEqual(Set(entries.map(\.id)), [first.id, second.id])
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(try VolantCore.AppleShortcut.decodeListing(Data()).isEmpty)
        for bad in ["name only", "Name (--help)", " (\(first.id))"] {
            XCTAssertThrowsError(try VolantCore.AppleShortcut.decodeListing(Data(bad.utf8)))
        }
        XCTAssertEqual(VolantCore.AppleShortcut.queryTerm(" APPLE SHORTCUTS recipes "), "recipes")
        XCTAssertEqual(VolantCore.AppleShortcut.queryTerm("shortcuts"), "")
        XCTAssertNil(VolantCore.AppleShortcut.queryTerm("shortcutting"))
        XCTAssertTrue(LauncherRouting.isReserved("apple shortcuts recipes"))
    }

    func testCacheRefreshFailureAndRetry() async throws {
        let model = AppleShortcutsModel()
        var callbacks: [([VolantCore.AppleShortcut]?, String?) -> Void] = []
        model.loadOverride = { callbacks.append($0) }
        model.refresh(); model.refresh(); model.refresh(force: true)
        XCTAssertEqual(callbacks.count, 1)
        callbacks[0]([first, second], nil)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(model.matches("recipes").count, 2)
        model.refresh()
        XCTAssertEqual(callbacks.count, 1)
        model.refresh(force: true)
        callbacks[1](nil, "Fixture unavailable")
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(model.entries.count, 2)
        XCTAssertEqual(model.message, "Fixture unavailable")
        model.refresh(force: true)
        callbacks[2]([], nil)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(model.entries.isEmpty)
        XCTAssertNil(model.message)
    }

    func testExactIdentityDuplicateActivationAndStaleCompletion() async throws {
        let model = AppleShortcutsModel()
        model.loadOverride = { $0([self.first, self.second], nil) }
        model.refresh()
        try await Task.sleep(for: .milliseconds(20))
        var ids: [String] = [], completions: [(String?) -> Void] = []
        model.runOverride = { ids.append($0); completions.append($1) }
        model.run(second); model.run(first)
        XCTAssertEqual(ids, [second.id])
        completions[0](nil)
        try await Task.sleep(for: .milliseconds(20))
        model.run(first)
        completions[0]("Stale failure")
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(model.running)
        XCTAssertEqual(model.runMessage, "Running shortcut…")
        completions[1]("Fixture failure")
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertFalse(model.running)
        XCTAssertEqual(model.runMessage, "Fixture failure")
        model.run(VolantCore.AppleShortcut(id: UUID().uuidString, name: "Missing"))
        XCTAssertEqual(ids.count, 2)
    }
}
