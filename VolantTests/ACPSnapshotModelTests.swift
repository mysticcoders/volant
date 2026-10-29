import XCTest
import VolantCore
@testable import Volant

/// The app decodes a helper snapshot only when its revision is new, patches its transcript with only
/// the messages that changed since the revision it holds, and any change it makes to the
/// conversation itself forces the next read to fetch the helper's full state.
final class ACPSnapshotModelTests: XCTestCase {
    private var suite: String!
    private var store: UserDefaults!

    override func setUp() {
        suite = "volant.tests.acp-snapshot." + UUID().uuidString
        store = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        store.removePersistentDomain(forName: suite)
    }

    private func encoded(_ state: ACPState) throws -> Data { try JSONEncoder().encode(ACPStateUpdate.full(state)) }
    private func encoded(_ update: ACPStateUpdate) throws -> Data { try JSONEncoder().encode(update) }

    func testANewRevisionIsAppliedAndAnUnchangedOneIsSkipped() throws {
        let model = ACPModel(resumeStore: store)
        let snapshot = ACPState(phase: "ready", status: "Ready", sessionID: "fictional-session", messages: [ACPMessage(role: "Agent", text: "Hello")])
        XCTAssertEqual(model.receive(try encoded(snapshot), revision: 5, after: -1), .applied)
        XCTAssertEqual(model.state, snapshot)
        XCTAssertEqual(model.helperRevision, 5)
        XCTAssertEqual(model.receive(nil, revision: 5, after: 5), .unchanged)
        XCTAssertEqual(model.state, snapshot)
        var next = snapshot; next.messages[0].text += " world"
        XCTAssertEqual(model.receive(try encoded(next), revision: 6, after: 5), .applied)
        XCTAssertEqual(model.state.messages.last?.text, "Hello world")
        XCTAssertEqual(model.helperRevision, 6)
    }

    func testALocalChangeForgetsTheHelperRevision() throws {
        let model = ACPModel(resumeStore: store)
        XCTAssertEqual(model.receive(try encoded(ACPState(phase: "ready", sessionID: "fictional-session")), revision: 3, after: -1), .applied)
        model.state.phase = "working"
        XCTAssertEqual(model.helperRevision, -1)
        XCTAssertEqual(model.receive(try encoded(ACPState(phase: "ready", sessionID: "fictional-session")), revision: 3, after: -1), .applied)
        XCTAssertEqual(model.state.phase, "ready")
        model.disconnect()
        XCTAssertEqual(model.helperRevision, -1)
    }

    func testAnUnchangedReplyToAReadStartedBeforeALocalChangeIsStale() throws {
        let model = ACPModel(resumeStore: store)
        XCTAssertEqual(model.receive(try encoded(ACPState(phase: "ready", sessionID: "fictional-session")), revision: 3, after: -1), .applied)
        model.state.phase = "working"
        XCTAssertEqual(model.receive(nil, revision: 3, after: 3), .stale, "the app's own change must not be confirmed by an old revision")
        XCTAssertEqual(model.state.phase, "working")
    }

    func testRepliesWithoutAUsableSnapshotAreInvalid() throws {
        let model = ACPModel(resumeStore: store)
        XCTAssertEqual(model.receive(nil, revision: -1, after: -1), .invalid)
        XCTAssertEqual(model.receive(nil, revision: 4, after: 2), .invalid)
        XCTAssertEqual(model.receive(Data("not json".utf8), revision: 2, after: -1), .invalid)
        XCTAssertEqual(model.state, ACPState())
    }

    func testAppliedSnapshotsAreStillRememberedForResume() throws {
        let model = ACPModel(resumeStore: store)
        var config = AIConfiguration(); config.provider = "claude"
        model.configure(config)
        let used = ACPState(phase: "ready", sessionID: "used-session", messages: [ACPMessage(role: "You", text: "Fictional question")])
        XCTAssertEqual(model.receive(try encoded(used), revision: 9, after: -1), .applied)
        XCTAssertEqual(model.resumable?.sessionID, "used-session")
    }

    private func transcript(_ count: Int) -> ACPState {
        ACPState(phase: "working", status: "Working…", sessionID: "fictional-session",
                 messages: (0..<count).map { ACPMessage(id: "m\($0)", role: $0 % 2 == 0 ? "You" : "Agent", text: "Fictional message \($0) " + String(repeating: "lorem ", count: 80)) })
    }

    func testOnlyTheChangedMessagesPatchTheRevisionTheAppHolds() throws {
        let model = ACPModel(resumeStore: store)
        let held = transcript(40)
        XCTAssertEqual(model.receive(try encoded(held), revision: 7, after: -1), .applied)
        var streamed = held; streamed.messages[39].text += " and more"; streamed.messages.append(ACPMessage(id: "m40", role: "Tool", text: "Read fixture"))
        streamed.status = "Needs your permission"
        let update = ACPStateUpdate.changes(from: held, base: 7, to: streamed)
        XCTAssertEqual(update.from, 39)
        XCTAssertEqual(update.state.messages.count, 2, "only the streamed message and the new one are sent")
        XCTAssertLessThan(try encoded(update).count, try encoded(streamed).count / 10)
        XCTAssertEqual(model.receive(try encoded(update), revision: 8, after: 7), .applied)
        XCTAssertEqual(model.state, streamed)
        XCTAssertEqual(model.helperRevision, 8)
    }

    func testAnUpdateForAnotherRevisionIsStaleAndForcesTheFullState() throws {
        let model = ACPModel(resumeStore: store)
        let held = transcript(4)
        XCTAssertEqual(model.receive(try encoded(held), revision: 7, after: -1), .applied)
        var next = held; next.messages[3].text += "!"
        XCTAssertEqual(model.receive(try encoded(ACPStateUpdate.changes(from: held, base: 6, to: next)), revision: 8, after: 6), .stale)
        XCTAssertEqual(model.state, held, "a delta from another base never patches the transcript")
        XCTAssertEqual(model.helperRevision, -1, "the next read asks for the full state")
    }

    func testAnUpdateAfterALocalChangeIsStale() throws {
        let model = ACPModel(resumeStore: store)
        let held = transcript(4)
        XCTAssertEqual(model.receive(try encoded(held), revision: 7, after: -1), .applied)
        model.state.phase = "cancelling"
        var next = held; next.messages[3].text += "!"
        XCTAssertEqual(model.receive(try encoded(ACPStateUpdate.changes(from: held, base: 7, to: next)), revision: 8, after: 7), .stale)
        XCTAssertEqual(model.state.phase, "cancelling")
    }

    func testAnUpdateBeyondTheHeldTranscriptIsStale() throws {
        let model = ACPModel(resumeStore: store)
        XCTAssertEqual(model.receive(try encoded(transcript(2)), revision: 7, after: -1), .applied)
        let broken = ACPStateUpdate(base: 7, from: 5, state: ACPState(phase: "working"))
        XCTAssertEqual(model.receive(try encoded(broken), revision: 8, after: 7), .stale)
        XCTAssertEqual(model.state, transcript(2))
        XCTAssertEqual(model.helperRevision, -1)
    }

    func testTheAIHelpersPlainStateStillApplies() throws {
        let model = ACPModel(resumeStore: store)
        let plain = try JSONEncoder().encode(ACPState(phase: "ready", messages: [ACPMessage(role: "Agent", text: "From the AI helper")]))
        XCTAssertEqual(model.receive(plain, revision: -1, after: -1), .applied)
        XCTAssertEqual(model.state.messages.last?.text, "From the AI helper")
    }
}
