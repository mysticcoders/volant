import XCTest
@testable import Vey

final class NotesStoreTests: XCTestCase {
    func testCreateUpdateSearchDelete() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vey-notes-\(UUID().uuidString)")
        let store = NotesStore(directory: dir)
        let note = store.create(initialText: "# Groceries\nmilk")
        XCTAssertEqual(store.notes.first?.title, "Groceries")
        store.update(note.id, text: "# Groceries\nmilk\neggs")
        store.flush()
        XCTAssertEqual(try String(contentsOf: note.url, encoding: .utf8), "# Groceries\nmilk\neggs")
        XCTAssertEqual(store.search("eggs").count, 1)
        XCTAssertEqual(store.search("bread").count, 0)
        store.delete(note.id)
        XCTAssertTrue(store.notes.isEmpty)
        try? FileManager.default.removeItem(at: dir)
    }
}
