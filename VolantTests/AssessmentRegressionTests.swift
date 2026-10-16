import XCTest
import VolantCore
@testable import Volant

final class AssessmentRegressionTests: XCTestCase {
    private func tempStore() -> (NotesStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("volant-notes-\(UUID().uuidString)")
        return (NotesStore(directory: dir), dir)
    }

    func testRapidCreationNeverCollides() {
        let (store, dir) = tempStore()
        for i in 0..<10 { store.create(initialText: "note \(i)") }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        XCTAssertEqual(files.count, 10)
        XCTAssertEqual(Set(store.notes.map(\.id)).count, 10)
        try? FileManager.default.removeItem(at: dir)
    }

    func testMarkdownBlockIdentitiesAreStableAndUnique() {
        let a = MarkdownBlocks.parseIndexed("same\n\nsame\n\n---\n\n---")
        let b = MarkdownBlocks.parseIndexed("same\n\nsame\n\n---\n\n---")
        XCTAssertEqual(a.map(\.id), b.map(\.id))
        XCTAssertEqual(Set(a.map(\.id)).count, a.count)
    }

    func testMeetingHostMatchingIsExact() {
        XCTAssertTrue(CalendarAgenda.isMeetingURL(URL(string: "https://us02web.zoom.us/j/123")!))
        XCTAssertFalse(CalendarAgenda.isMeetingURL(URL(string: "https://notzoom.us/j/123")!))
        XCTAssertFalse(CalendarAgenda.isMeetingURL(URL(string: "http://zoom.us/j/123")!))
        XCTAssertFalse(CalendarAgenda.isMeetingURL(URL(string: "https://example.com/zoom.us")!))
    }
}
