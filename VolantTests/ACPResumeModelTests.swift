import XCTest
import VolantCore
@testable import Volant

/// Resume is offered only for the stored provider and folder, and the record lives in an
/// isolated defaults suite here, never the owner's.
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
}
