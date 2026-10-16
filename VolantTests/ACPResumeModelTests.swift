import XCTest
import VolantCore
@testable import Volant

/// Resume is offered only for the stored provider and folder, and the record lives in an
/// isolated defaults suite here, never the owner's.
extension XCTestCase {
    /// A model whose resume record lives in a defaults suite unique to this test, never the owner's
    /// defaults; the suite is removed when the test ends.
    func isolatedACPModel() -> ACPModel {
        let suite = "volant.tests.acp." + UUID().uuidString
        let store = UserDefaults(suiteName: suite)!
        addTeardownBlock { store.removePersistentDomain(forName: suite) }
        return ACPModel(resumeStore: store)
    }
}

final class ACPResumeModelTests: XCTestCase {
    private var suite: String!
    private var store: UserDefaults!

    override func setUp() {
        suite = "volant.tests.acp-resume." + UUID().uuidString
        store = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        store.removePersistentDomain(forName: suite)
    }

    private func save(_ record: ACPResumeRecord) throws {
        store.set(try JSONEncoder().encode(record), forKey: ACPModel.resumeKey)
    }

    func testResumeIsOfferedOnlyForTheSameProviderAndFolder() throws {
        try save(ACPResumeRecord(provider: "claude", project: "/tmp/fictional-project", sessionID: "fictional-session"))
        let model = ACPModel(resumeStore: store)
        var config = AIConfiguration(); config.provider = "claude"; config.project = "/tmp/fictional-project"
        model.configure(config)
        XCTAssertTrue(model.canResume)
        config.project = "/tmp/other-project"
        model.configure(config)
        XCTAssertFalse(model.canResume)
        config.provider = "codex"; config.project = "/tmp/fictional-project"
        model.configure(config)
        XCTAssertFalse(model.canResume)
    }

    func testAnActiveConversationIsNeverOfferedResume() throws {
        try save(ACPResumeRecord(provider: "claude", project: "", sessionID: "fictional-session"))
        let model = ACPModel(resumeStore: store)
        var config = AIConfiguration(); config.provider = "claude"
        model.configure(config)
        model.state.phase = "ready"
        XCTAssertFalse(model.canResume)
        model.state.phase = "disconnected"
        XCTAssertTrue(model.canResume)
    }

    func testInvalidOrMissingRecordsOfferNothing() throws {
        XCTAssertNil(ACPModel(resumeStore: store).resumable)
        try save(ACPResumeRecord(provider: "claude", project: "", sessionID: "bad id"))
        XCTAssertNil(ACPModel(resumeStore: store).resumable)
        store.set(Data("broken".utf8), forKey: ACPModel.resumeKey)
        XCTAssertNil(ACPModel(resumeStore: store).resumable)
    }

    func testOpeningTheChatOffersResumeInsteadOfReplacingTheRecord() throws {
        try save(ACPResumeRecord(provider: "claude", project: "", sessionID: "fictional-session"))
        let model = ACPModel(resumeStore: store)
        var config = AIConfiguration(); config.provider = "claude"
        var connects = 0
        XCTAssertTrue(model.openChat(configuration: config) { connects += 1 })
        XCTAssertEqual(connects, 0)
        XCTAssertTrue(model.canResume)
        config.provider = "codex"
        XCTAssertTrue(model.openChat(configuration: config) { connects += 1 })
        XCTAssertEqual(connects, 1)
    }

    func testOnlyAConversationWithAnOwnerTurnReplacesTheRecord() throws {
        try save(ACPResumeRecord(provider: "claude", project: "", sessionID: "fictional-session"))
        let model = ACPModel(resumeStore: store)
        var config = AIConfiguration(); config.provider = "claude"
        model.configure(config)
        model.remember(ACPState(phase: "ready", sessionID: "unused-session"))
        XCTAssertEqual(model.resumable?.sessionID, "fictional-session")
        model.remember(ACPState(phase: "ready", sessionID: "used-session", messages: [ACPMessage(role: "You", text: "Fictional question")]))
        XCTAssertEqual(model.resumable?.sessionID, "used-session")
        XCTAssertEqual(ACPModel(resumeStore: store).resumable?.sessionID, "used-session")
    }

    func testARejectedResumeClearsTheRecord() throws {
        try save(ACPResumeRecord(provider: "claude", project: "", sessionID: "fictional-session"))
        let model = ACPModel(resumeStore: store)
        model.resumedSession = "fictional-session"
        var rejected = ACPState(phase: "failed"); rejected.resumeRejected = true
        model.remember(rejected)
        XCTAssertNil(model.resumable)
        XCTAssertNil(ACPModel(resumeStore: store).resumable)
    }
}
