import XCTest
import VolantCore
@testable import Volant

/// Attaching is local to the model: it never sends, and a refused item leaves the draft alone.
final class ChatAttachmentModelTests: XCTestCase {
    private func item(_ id: String, size: Int = 10) -> ChatAttachment {
        ChatAttachment(id: id, kind: .note, title: "Note " + id, detail: "Note", text: String(repeating: "x", count: size))
    }

    func testAttachIsIdempotentAndDetachRemovesOnlyThatItem() {
        let model = ACPModel.isolated()
        model.draft = "Keep this draft"
        XCTAssertTrue(model.attach(item("a")))
        XCTAssertTrue(model.attach(item("a")), "attaching the same item again is not an error")
        XCTAssertTrue(model.attach(item("b")))
        XCTAssertEqual(model.attachments.map(\.id), ["a", "b"])
        model.detach("a")
        XCTAssertEqual(model.attachments.map(\.id), ["b"])
        XCTAssertEqual(model.draft, "Keep this draft")
        XCTAssertFalse(model.submitting)
    }

    func testARefusedAttachmentExplainsWhyAndKeepsTheRest() {
        let model = ACPModel.isolated()
        XCTAssertTrue(model.attach(item("a", size: 30_000)))
        XCTAssertFalse(model.attach(item("b", size: 30_000)), "together they exceed the total")
        XCTAssertEqual(model.attachments.map(\.id), ["a"])
        XCTAssertNotNil(model.error)
        XCTAssertTrue(model.attach(item("c", size: 100)))
        XCTAssertNil(model.error, "a later successful attach clears the message")
    }
}
