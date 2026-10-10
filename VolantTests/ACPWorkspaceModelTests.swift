import XCTest
import VolantCore
@testable import Volant

/// Isolated workspaces without a helper: what the model asks the helper for, when Resume is offered,
/// and removal through a fake remover. Records live in a per-test defaults suite, never the owner's.
final class ACPWorkspaceModelTests: XCTestCase {
    private var suite: String!
    private var store: UserDefaults!
    private var folder: URL!

    override func setUpWithError() throws {
        suite = "volant.tests.acp-workspace." + UUID().uuidString
        store = UserDefaults(suiteName: suite)
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("volant-workspace-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        store.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: folder)
    }

    private func configuration(isolate: Bool, project: String = "/tmp/fictional-project") -> AIConfiguration {
        var config = AIConfiguration(); config.provider = "claude"; config.project = project; config.isolate = isolate
        return config
    }

    private func record(workspace: String?) -> ACPResumeRecord {
        ACPResumeRecord(provider: "claude", project: "/tmp/fictional-project", sessionID: "fictional-session", workspace: workspace)
    }

    private func save(_ record: ACPResumeRecord) throws {
        store.set(try JSONEncoder().encode(record), forKey: ACPModel.resumeKey)
    }

    /// Removal replies on the main queue, so the run loop turns until it has.
    private func waitForRemoval(_ model: ACPModel) {
        let deadline = Date().addingTimeInterval(2)
        while model.removingWorkspace && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }

    func testOnlyAnACPConversationWithAFolderIsIsolated() {
        let model = ACPModel(resumeStore: store)
        model.configure(configuration(isolate: true))
        XCTAssertTrue(model.isolate)
        XCTAssertEqual(model.helperStart(resume: nil), .isolated(project: "/tmp/fictional-project", profile: ""))
        model.configure(configuration(isolate: true, project: ""))
        XCTAssertFalse(model.isolate)
        XCTAssertEqual(model.helperStart(resume: nil), .start(project: "", profile: ""))
        var api = configuration(isolate: true); api.connection = .byok
        model.configure(api)
        XCTAssertFalse(model.isolate)
        model.configure(configuration(isolate: false))
        XCTAssertEqual(model.helperStart(resume: nil), .start(project: "/tmp/fictional-project", profile: ""))
    }

    func testResumeRunsInTheFolderTheConversationRanIn() {
        let model = ACPModel(resumeStore: store)
        model.configure(configuration(isolate: true))
        XCTAssertEqual(model.helperStart(resume: record(workspace: folder.path)), .resume(folder: folder.path, profile: "", session: "fictional-session"))
        // A conversation recorded without a workspace resumes in the project, never in a new workspace.
        XCTAssertEqual(model.helperStart(resume: record(workspace: nil)), .resume(folder: "/tmp/fictional-project", profile: "", session: "fictional-session"))
    }

    func testRememberStoresTheWorkspace() {
        let model = ACPModel(resumeStore: store)
        model.configure(configuration(isolate: true))
        model.workspace = folder.path
        model.remember(ACPState(phase: "ready", sessionID: "used-session", messages: [ACPMessage(role: "You", text: "Fictional question")]))
        XCTAssertEqual(ACPModel(resumeStore: store).resumable?.workspace, folder.path)
    }

    func testResumeIsOfferedWhileTheWorkspaceExists() throws {
        try save(record(workspace: folder.path))
        let model = ACPModel(resumeStore: store)
        model.configure(configuration(isolate: true))
        XCTAssertTrue(model.canResume)
        try FileManager.default.removeItem(at: folder)
        // Checked again when a conversation ends, and by every new model.
        model.disconnect()
        XCTAssertFalse(model.canResume)
        let later = ACPModel(resumeStore: store)
        later.configure(configuration(isolate: true))
        XCTAssertFalse(later.canResume)
    }

    func testOnlyAFolderKnownToBeGoneCountsAsMissing() throws {
        XCTAssertFalse(ACPModel.workspaceMissing(nil))
        XCTAssertFalse(ACPModel.workspaceMissing(folder.path))
        XCTAssertTrue(ACPModel.workspaceMissing(folder.appendingPathComponent("missing").path))
        let file = folder.appendingPathComponent("file")
        try Data().write(to: file)
        XCTAssertTrue(ACPModel.workspaceMissing(file.path))
        XCTAssertTrue(ACPModel.workspaceMissing(file.appendingPathComponent("below").path))
        // A folder this process may not look into is unknown, like a path the sandbox refuses.
        let closed = folder.appendingPathComponent("closed"), inner = closed.appendingPathComponent("workspace")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: closed.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: closed.path) }
        XCTAssertFalse(ACPModel.workspaceMissing(inner.path))
    }

    func testTheWorkspaceIsReadWhenTheConversationBecomesReadyAndAfterEachTurn() {
        XCTAssertTrue(ACPModel.turnEnded(from: "starting", to: "ready"))
        XCTAssertTrue(ACPModel.turnEnded(from: "working", to: "ready"))
        XCTAssertTrue(ACPModel.turnEnded(from: "cancelling", to: "ready"))
        XCTAssertFalse(ACPModel.turnEnded(from: "ready", to: "ready"))
        XCTAssertFalse(ACPModel.turnEnded(from: "ready", to: "working"))
        XCTAssertFalse(ACPModel.turnEnded(from: "working", to: "failed"))
    }

    func testRemovalKeepsTheBranchAndClearsTheRecord() throws {
        try save(record(workspace: folder.path))
        let model = ACPModel(resumeStore: store)
        model.configure(configuration(isolate: true))
        var refused: [String] = [], removed: [String] = []
        model.resumeRefused = { refused.append($0) }
        model.worktreeRemover = { path, reply in removed.append(path); reply("volant/ab12cd34", nil) }
        XCTAssertFalse(model.canRemoveWorkspace)
        model.workspace = folder.path
        model.workspaceState = RepositoryState(branch: "volant/ab12cd34")
        model.state.phase = "ready"
        XCTAssertFalse(model.canRemoveWorkspace)
        model.state.phase = "disconnected"
        XCTAssertTrue(model.canRemoveWorkspace)
        model.removeWorkspace()
        XCTAssertFalse(model.canRemoveWorkspace)
        waitForRemoval(model)
        XCTAssertEqual(removed, [folder.path])
        XCTAssertNil(model.workspace)
        XCTAssertNil(model.workspaceState)
        XCTAssertEqual(model.state.status, "Removed the workspace. Its branch volant/ab12cd34 keeps its commits.")
        XCTAssertNil(model.resumable)
        XCTAssertNil(store.data(forKey: ACPModel.resumeKey))
        XCTAssertEqual(refused, ["fictional-session"])
    }

    func testARefusedRemovalKeepsTheWorkspaceAndItsRecord() throws {
        try save(record(workspace: folder.path))
        let model = ACPModel(resumeStore: store)
        model.configure(configuration(isolate: true))
        let refusal = "This workspace has uncommitted or untracked changes. Commit or discard them first."
        model.worktreeRemover = { _, reply in reply(nil, refusal) }
        model.workspace = folder.path
        model.removeWorkspace()
        waitForRemoval(model)
        XCTAssertEqual(model.workspace, folder.path)
        XCTAssertEqual(model.error, refusal)
        XCTAssertTrue(model.canRemoveWorkspace)
        XCTAssertEqual(model.resumable?.workspace, folder.path)
        XCTAssertTrue(model.canResume)
    }

    func testAWorkspaceThatIsAlreadyGoneCountsAsRemoved() throws {
        try save(record(workspace: folder.path))
        let model = ACPModel(resumeStore: store)
        model.configure(configuration(isolate: true))
        var refused: [String] = []
        model.resumeRefused = { refused.append($0) }
        model.worktreeRemover = { _, reply in reply(nil, nil) }
        model.workspace = folder.path
        model.removeWorkspace()
        waitForRemoval(model)
        XCTAssertNil(model.workspace)
        XCTAssertNil(model.error)
        XCTAssertEqual(model.state.status, "The workspace’s folder was already gone.")
        XCTAssertNil(store.data(forKey: ACPModel.resumeKey))
        XCTAssertEqual(refused, ["fictional-session"])
        XCTAssertFalse(model.canResume)
    }

    func testResumeWaitsWhileARemovalRuns() throws {
        try save(record(workspace: folder.path))
        let model = ACPModel(resumeStore: store)
        model.configure(configuration(isolate: true))
        var pending: ((String?, String?) -> Void)?
        model.worktreeRemover = { _, reply in pending = reply }
        model.workspace = folder.path
        XCTAssertTrue(model.canResume)
        model.removeWorkspace()
        XCTAssertTrue(model.removingWorkspace)
        XCTAssertFalse(model.canResume, "Resume would start the agent in a folder git is deleting")
        pending?(nil, "Fictional refusal.")
        waitForRemoval(model)
        XCTAssertTrue(model.canResume)
    }

    func testOpeningAChatThatKeptAWorkspaceShowsItWithoutConnecting() {
        let model = ACPModel(resumeStore: store)
        model.workspace = folder.path
        model.state.phase = "failed"
        var connects = 0
        XCTAssertTrue(model.openChat(configuration: configuration(isolate: true)) { connects += 1 })
        XCTAssertEqual(connects, 0, "connecting would replace the only handle on the kept workspace")
        model.workspace = nil
        XCTAssertTrue(model.openChat(configuration: configuration(isolate: true)) { connects += 1 })
        XCTAssertEqual(connects, 1)
    }
}
