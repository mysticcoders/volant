import XCTest
@testable import VolantCore

/// Building and applying the ACP helper's partial conversation updates.
final class ACPStateUpdateTests: XCTestCase {
    private func state(_ texts: [String]) -> ACPState {
        ACPState(phase: "working", messages: texts.enumerated().map { ACPMessage(id: "m\($0.offset)", role: "Agent", text: $0.element) })
    }

    func testChangesStartAtTheFirstDifferentMessage() {
        let old = state(["a", "b", "c"])
        XCTAssertEqual(ACPStateUpdate.changes(from: old, base: 1, to: state(["a", "b", "c!"])).from, 2)
        XCTAssertEqual(ACPStateUpdate.changes(from: old, base: 1, to: state(["a", "b", "c", "d"])).from, 3)
        XCTAssertEqual(ACPStateUpdate.changes(from: old, base: 1, to: state(["a", "b", "c"])).state.messages, [], "nothing to resend")
        XCTAssertEqual(ACPStateUpdate.changes(from: old, base: 1, to: state(["x", "b", "c"])).from, 0)
        XCTAssertEqual(ACPStateUpdate.changes(from: old, base: 1, to: state(["a"])).from, 1, "a shorter transcript keeps only its prefix")
    }

    func testApplyingRebuildsTheNewConversation() {
        let old = state(["a", "b", "c"])
        for new in [state(["a", "b", "c!"]), state(["a", "b", "c", "d"]), state(["a"]), state([]), state(["x", "y"])] {
            XCTAssertEqual(ACPStateUpdate.changes(from: old, base: 1, to: new).applied(to: old), new)
        }
        var phased = old; phased.phase = "ready"; phased.status = "Ready"
        XCTAssertEqual(ACPStateUpdate.changes(from: old, base: 1, to: phased).applied(to: old), phased, "fields other than messages always travel")
    }

    func testFullUpdatesIgnoreTheReadersTranscriptAndBadOffsetsDoNotApply() {
        let new = state(["n"])
        XCTAssertEqual(ACPStateUpdate.full(new).applied(to: state(["a", "b"])), new)
        XCTAssertNil(ACPStateUpdate(base: 1, from: 3, state: new).applied(to: state(["a", "b"])))
        XCTAssertNil(ACPStateUpdate(base: 1, from: -1, state: new).applied(to: state(["a", "b"])))
    }
}
