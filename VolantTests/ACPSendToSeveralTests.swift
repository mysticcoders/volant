import XCTest
import VolantCore
@testable import Volant

/// Send to Several and headless tasks. Models read fresh defaults suites, removed after each test
/// and never the owner's. A start marks the model starting instead of opening an XPC connection,
/// each prompt is recorded instead of reaching a helper, and the tests drive each conversation
/// with the snapshots the helper would send, each under a new revision.
final class ACPSendToSeveralTests: XCTestCase {
    private var suites: [String] = []
    private var started: [ACPModel] = []
    private var prompts: [(model: ACPModel, text: String, attachments: [ChatAttachment])] = []
    private var retries: [() -> Void] = []
    private var retryDelays: [TimeInterval] = []
    private var folders: [URL] = []

    override func tearDown() {
        for suite in suites { UserDefaults().removePersistentDomain(forName: suite) }
        for folder in folders { try? FileManager.default.removeItem(at: folder) }
        suites = []; started = []; prompts = []; retries = []; retryDelays = []; folders = []
    }

    private func isolatedStore() -> UserDefaults {
        let suite = "volant.tests.acp-send-to-several." + UUID().uuidString
        suites.append(suite)
        return UserDefaults(suiteName: suite)!
    }

    /// AI Chat is on screen unless a test hides it. `folderProblem` is what the helper's worktree
    /// check replies.
    private func conversations(folderProblem: String? = nil, sharing store: UserDefaults? = nil) -> ACPConversations {
        let list = ACPConversations(make: { [unowned self] in
            let model = ACPModel(resumeStore: store ?? self.isolatedStore())
            model.promptSender = { [unowned self, unowned model] text, attachments, reply in
                self.prompts.append((model, text, attachments))
                reply(nil)
            }
            return model
        }, start: { [unowned self] model in
            self.started.append(model)
            self.deliver(ACPState(phase: "starting", status: "Connecting…"), to: model)
        })
        list.retryLater = { [unowned self] delay, retry in self.retryDelays.append(delay); self.retries.append(retry) }
        list.worktreeChecker = { _, reply in reply(folderProblem) }
        list.chatShown = true
        return list
    }

    private func settings(project: String = "") -> AIConfiguration {
        var config = AIConfiguration(); config.provider = "claude"; config.project = project
        return config
    }

    private func targets(_ count: Int, project: String = "") -> [AIConfiguration] {
        Array(repeating: settings(project: project), count: count)
    }

    private let note = ChatAttachment(id: "fictional-note", kind: .note, title: "Fictional note", detail: "Notes", text: "Fictional context")

    /// Runs what the model queued on the main queue, such as a prompt's reply.
    private func drain() {
        let done = expectation(description: "main queue")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 2)
    }

    /// Stands in for the helper's revision, which every change to its state advances.
    private var snapshotRevision = 0

    /// Hands `model` a snapshot as the helper's reply to a read does: encoded, with a new revision,
    /// for a read that asked for changes after the revision the model holds. `handleRead` is the
    /// path every poll's reply takes, so the revision rules and the rules that follow a change of
    /// phase both run.
    private func deliver(_ state: ACPState, to model: ACPModel) {
        snapshotRevision += 1
        XCTAssertEqual(model.handleRead(try? JSONEncoder().encode(state), revision: snapshotRevision, after: model.helperRevision), .applied)
    }

    private func ready(_ model: ACPModel, session: String = "fictional-session") {
        deliver(ACPState(phase: "ready", status: "Ready", sessionID: session), to: model)
    }

    /// The prompt goes out on ready; its turn then ends with `status` and an agent reply.
    private func finishTurn(_ model: ACPModel, status: String = "Ready") {
        drain()
        XCTAssertEqual(model.state.phase, "working", "the prompt's reply marks the turn as working")
        deliver(ACPState(phase: "working", status: "Working…", sessionID: "fictional-session"), to: model)
        deliver(ACPState(phase: "ready", status: status, sessionID: "fictional-session",
                         messages: [ACPMessage(role: "You", text: "Fictional task"), ACPMessage(role: "Agent", text: "Fictional result")]), to: model)
    }

    private func sentCount(_ model: ACPModel) -> Int { prompts.filter { $0.model === model }.count }

    /// A temporary folder standing in for a workspace, so Resume finds it; removed after the test.
    private func workspaceFolder() throws -> String {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("volant-fan-out-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        folders.append(folder)
        return folder.path
    }

    // MARK: Queue

    func testTargetsPastTheLimitWaitAndStartInOrderAsOthersEnd() {
        let list = conversations()
        for _ in 0..<4 { XCTAssertTrue(list.newConversation(configuration: settings())) }
        let running = list.live
        started = []
        let models = list.fanOut(prompt: "Fictional task", attachments: [], targets: targets(4), headless: false)
        XCTAssertEqual(started.map(\.id), models.prefix(2).map(\.id), "two slots were free")
        XCTAssertEqual(list.waiting.map(\.id), models.suffix(2).map(\.id))
        XCTAssertTrue(list.current === models[0], "the first target that started is shown")
        XCTAssertTrue(running.allSatisfy(\.active), "the conversations already running keep running")

        running[1].disconnect()
        XCTAssertEqual(started.map(\.id), models.prefix(3).map(\.id), "an ended conversation frees a slot for the next target")
        XCTAssertEqual(list.waiting.map(\.id), [models[3].id])
        running[2].fail("Agent process exited. Check the provider’s terminal login and reconnect.")
        XCTAssertEqual(started.map(\.id), models.map(\.id), "so does a failed one")
        XCTAssertTrue(list.waiting.isEmpty)
        running[3].disconnect()
        XCTAssertEqual(started.count, 4, "nothing starts with nothing waiting")
    }

    func testEachTargetStartsOnce() {
        let list = conversations()
        for _ in 0..<5 { list.newConversation(configuration: settings()) }
        started = []
        let models = list.fanOut(prompt: "Fictional task", attachments: [], targets: targets(3), headless: true)
        list.live[0].disconnect()
        list.live[0].disconnect()
        models[0].disconnect()
        XCTAssertEqual(started.map(\.id), models.map(\.id), "each target started once, in order")
        XCTAssertEqual(Set(started.map(\.id)).count, started.count)
    }

    func testCancelDropsOnlyTheWaitingTargets() {
        let list = conversations()
        for _ in 0..<5 { list.newConversation(configuration: settings()) }
        started = []
        let models = list.fanOut(prompt: "Fictional task", attachments: [], targets: targets(3), headless: true)
        XCTAssertEqual(list.waiting.count, 2)
        list.cancelWaiting()
        XCTAssertTrue(list.waiting.isEmpty)
        XCTAssertTrue(models[0].active, "the target that started keeps running")
        XCTAssertNotNil(models[0].pendingPrompt)
        XCTAssertNil(models[1].pendingPrompt)
        XCTAssertNil(models[2].pendingPrompt)
        list.live[0].disconnect()
        XCTAssertEqual(started.map(\.id), [models[0].id], "a freed slot starts no target that was dropped")
    }

    func testAHeadlessSendKeepsTheShownConversation() {
        let list = conversations()
        let shown = list.current
        let models = list.fanOut(prompt: "Fictional task", attachments: [], targets: targets(2), headless: true)
        XCTAssertTrue(list.current === shown)
        XCTAssertTrue(models.allSatisfy { $0.background && $0.headless && $0.fanOutTarget })
    }

    // MARK: Sent once

    func testThePromptIsSentOnceAcrossRepeatedReadySnapshots() {
        let list = conversations()
        let model = list.fanOut(prompt: "Fictional task", attachments: [note], targets: targets(1), headless: false)[0]
        XCTAssertTrue(prompts.isEmpty, "nothing is sent before the conversation is ready")
        ready(model)
        XCTAssertEqual(prompts.count, 1)
        XCTAssertEqual(prompts.first?.text, "Fictional task")
        XCTAssertEqual(prompts.first?.attachments, [note], "the attachments travel with the prompt")
        XCTAssertNil(model.pendingPrompt, "cleared as the prompt goes out")
        let known = model.helperRevision
        XCTAssertEqual(model.handleRead(nil, revision: known, after: known), .unchanged)
        ready(model)
        ready(model)
        XCTAssertEqual(prompts.count, 1, "an unchanged reply or a repeated ready snapshot sends nothing")
        let last = model.helperRevision
        drain()
        XCTAssertEqual(model.handleRead(nil, revision: last, after: last), .stale,
                       "the prompt's reply marked the turn working, so an older revision does not confirm ready")
        XCTAssertEqual(model.state.phase, "working")
        finishTurn(model)
        XCTAssertEqual(prompts.count, 1, "nor does the end of the turn")
        model.disconnect()
        deliver(ACPState(phase: "starting"), to: model)
        ready(model, session: "fictional-second")
        XCTAssertEqual(prompts.count, 1, "nor does a later start of the same conversation")
    }

    func testAFailureAfterTheSendIsMarkedAndNothingIsSentAgain() {
        let list = conversations()
        let models = list.fanOut(prompt: "Fictional task", attachments: [], targets: targets(2), headless: false)
        ready(models[0])
        // The helper fails before the prompt's reply arrives.
        models[0].fail("Agent helper disconnected. Start a new conversation to reconnect.")
        XCTAssertEqual(models[0].error, "Agent helper disconnected. Start a new conversation to reconnect.")
        XCTAssertTrue(models[0].taskMayHaveRun, "shown after the failure as \(ACPModel.mayHaveRun)")
        XCTAssertEqual(models[0].state.phase, "failed")
        deliver(ACPState(phase: "starting"), to: models[0])
        ready(models[0], session: "fictional-second")
        XCTAssertEqual(sentCount(models[0]), 1, "a failed task is never sent again")

        ready(models[1])
        drain()
        models[1].error = "This permission request has expired."
        deliver(ACPState(phase: "failed", status: "Agent process exited."), to: models[1])
        XCTAssertEqual(models[1].error, "Agent process exited.", "a failure the helper reports names that failure rather than an earlier error")
        XCTAssertTrue(models[1].taskMayHaveRun, "and is marked too")
        XCTAssertEqual(models[1].state.status, "Agent process exited.", "the status keeps the agent's message")
        // A later disconnect must not replace the failure.
        models[1].fail("Agent helper disconnected. Start a new conversation to reconnect.")
        XCTAssertEqual(models[1].error, "Agent process exited.")
        XCTAssertEqual(models[1].state.status, "Agent process exited.")
        // Attaching a note or a refused removal replaces the error, never the mark.
        XCTAssertTrue(models[1].attach(note))
        XCTAssertNil(models[1].error)
        models[1].workspace = "/tmp/fictional-worktrees/fictional-project-00000001"
        models[1].workspaceRemoved("/tmp/fictional-worktrees/fictional-project-00000001", branch: nil,
                                   error: "This workspace has uncommitted or untracked changes. Commit or discard them first.")
        XCTAssertEqual(models[1].state.status, "Workspace kept.")
        XCTAssertTrue(models[1].taskMayHaveRun)
    }

    func testAReportedFailureClosesTheConnectionAndIgnoresLateReplies() {
        let model = ACPModel(resumeStore: isolatedStore())
        var reply: ((String?) -> Void)?
        model.promptSender = { _, _, done in reply = done }
        model.configure(settings())
        model.assign(ACPModel.PendingPrompt(text: "Fictional task", attachments: []), headless: false)
        deliver(ACPState(phase: "starting"), to: model)
        ready(model)
        XCTAssertTrue(model.submitting)
        deliver(ACPState(phase: "failed", status: "Agent process exited."), to: model)
        XCTAssertFalse(model.submitting, "the connection is closed, so no reply is awaited")
        reply?(nil)
        drain()
        XCTAssertEqual(model.state.phase, "failed", "a reply from the closed connection changes nothing")
        XCTAssertTrue(model.taskMayHaveRun)
    }

    /// A poll sent before the prompt's reply is answered after it, with no data at the ready
    /// revision. The prompt's reply marked the turn working, so that answer is stale and the model
    /// reads the helper's full state; a read the helper could not answer then fails the target.
    func testAStaleReplyReadsTheFullStateAndAnUnreadableOneFails() throws {
        let list = conversations()
        let model = list.fanOut(prompt: "Fictional task", attachments: [], targets: targets(1), headless: false)[0]
        var reads: [(after: Int, reply: (Data?, Int, String?) -> Void)] = []
        model.reader = { reads.append(($0, $1)) }
        ready(model)
        let readyRevision = model.helperRevision
        model.read()
        let poll = try XCTUnwrap(reads.first)
        XCTAssertEqual(poll.after, readyRevision, "a poll asks for changes after the revision the model holds")
        drain()
        XCTAssertEqual(model.state.phase, "working", "the prompt's reply marks the turn working")
        XCTAssertEqual(reads.count, 1, "and its read waits for the poll's")
        poll.reply(nil, readyRevision, nil)
        drain()
        XCTAssertEqual(reads.map(\.after), [readyRevision, -1], "the stale reply reads the helper's full state")
        XCTAssertEqual(model.state.phase, "working")
        let full = try XCTUnwrap(reads.dropFirst().first)
        full.reply(nil, -1, "Fictional encoding failure.")
        drain()
        XCTAssertEqual(model.state.phase, "failed")
        XCTAssertEqual(model.error, "Fictional encoding failure.")
        XCTAssertTrue(model.taskMayHaveRun, "the prompt went out before the failure")
    }

    func testAPromptWhoseReplyNeverCameIsNotSentAgain() {
        let model = ACPModel(resumeStore: isolatedStore())
        var sends = 0
        model.promptSender = { _, _, _ in sends += 1 }
        model.configure(settings())
        model.assign(ACPModel.PendingPrompt(text: "Fictional task", attachments: []), headless: false)
        deliver(ACPState(phase: "starting"), to: model)
        ready(model)
        model.fail("Agent helper disconnected. Start a new conversation to reconnect.")
        XCTAssertTrue(model.taskMayHaveRun)
        deliver(ACPState(phase: "starting"), to: model)
        ready(model, session: "fictional-second")
        drain()
        XCTAssertEqual(sends, 1, "cleared as it went out, before the helper replied")
    }

    func testAFailureBeforeTheSendIsNotMarkedAndDropsThePrompt() {
        let list = conversations()
        let model = list.fanOut(prompt: "Fictional task", attachments: [], targets: targets(1), headless: false)[0]
        model.fail("Agent process exited. Check the provider’s terminal login and reconnect.")
        XCTAssertEqual(model.error, "Agent process exited. Check the provider’s terminal login and reconnect.")
        XCTAssertFalse(model.taskMayHaveRun)
        XCTAssertNil(model.pendingPrompt, "a start that failed for another reason does not keep the prompt")
        deliver(ACPState(phase: "starting"), to: model)
        ready(model)
        XCTAssertTrue(prompts.isEmpty, "so a later start never sends it")
    }

    func testAPromptTheHelperRefusedEndsAHeadlessTarget() {
        let list = conversations()
        let model = list.fanOut(prompt: "Fictional task", attachments: [], targets: targets(1), headless: true)[0]
        model.promptSender = { _, _, reply in reply("The conversation is not ready for another prompt.") }
        ready(model)
        drain()
        XCTAssertEqual(model.state.phase, "disconnected")
        XCTAssertEqual(model.state.status, "The conversation is not ready for another prompt.")
        XCTAssertEqual(model.error, "The conversation is not ready for another prompt.", "refused before the agent saw it, so not marked")
        XCTAssertFalse(model.taskMayHaveRun)
        XCTAssertTrue(model.unread, "a headless conversation that stopped is unread")
    }

    /// A store holding an earlier conversation's record, with no workspace.
    private func recordedStore(project: String = "") throws -> UserDefaults {
        let store = isolatedStore()
        store.set(try JSONEncoder().encode(ACPResumeRecord(provider: "claude", project: project, sessionID: "fictional-earlier")), forKey: ACPModel.resumeKey)
        return store
    }

    func testATargetResumesOnlyTheSessionItRecorded() throws {
        let list = conversations(sharing: try recordedStore(project: "/tmp/fictional-project"))
        let models = list.fanOut(prompt: "Fictional task", attachments: [], targets: targets(2, project: "/tmp/fictional-project"), headless: false)
        var requests: [ACPModel.HelperStart] = []
        let workspace = "/tmp/fictional-worktrees/fictional-project-00000000"
        models[0].workspace = workspace
        models[0].connector = { requests.append($0) }
        XCTAssertFalse(models[0].canResume, "the stored record is an earlier conversation's")
        ready(models[0])
        drain()
        deliver(ACPState(phase: "failed", status: "Agent process exited."), to: models[0])
        XCTAssertFalse(models[0].canResume, "nor after a failure before it recorded a session of its own")
        models[0].resume()
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(models[0].workspace, workspace, "its workspace stays its own")
        XCTAssertEqual(models[0].error, "Agent process exited.")
        XCTAssertTrue(models[0].taskMayHaveRun)

        // A target that recorded its own session resumes that one, in its own workspace, and sends nothing again.
        let own = try workspaceFolder()
        models[1].workspace = own
        models[1].connector = { requests.append($0) }
        ready(models[1])
        finishTurn(models[1])
        models[1].disconnect()
        XCTAssertTrue(models[1].canResume)
        models[1].resume()
        XCTAssertEqual(requests, [.resume(folder: own, session: "fictional-session")])
        ready(models[1])
        drain()
        XCTAssertEqual(sentCount(models[1]), 1)
    }

    // MARK: Headless

    func testAHeadlessTargetEndsAfterItsFirstTurnAndKeepsItsTranscript() {
        let list = conversations()
        let models = list.fanOut(prompt: "Fictional task", attachments: [], targets: targets(3), headless: true)
        for model in models { ready(model) }
        finishTurn(models[0])
        XCTAssertEqual(models[0].state.phase, "disconnected", "the session ends after the first turn")
        XCTAssertEqual(models[0].state.status, "Finished after its first turn.")
        XCTAssertEqual(models[0].state.messages.last?.text, "Fictional result", "the transcript is kept")
        XCTAssertTrue(models[0].unread)

        deliver(ACPState(phase: "working", sessionID: "fictional-session"), to: models[1])
        deliver(ACPState(phase: "ready", status: "Stopped: max_tokens", sessionID: "fictional-session"), to: models[1])
        XCTAssertEqual(models[1].state.phase, "disconnected", "any stop reason ends it")
        XCTAssertEqual(models[1].state.status, "Stopped: max_tokens")

        deliver(ACPState(phase: "working", sessionID: "fictional-session"), to: models[2])
        deliver(ACPState(phase: "cancelling", sessionID: "fictional-session"), to: models[2])
        XCTAssertTrue(models[2].active, "a turn being canceled has not ended")
        deliver(ACPState(phase: "ready", status: "Cancelled", sessionID: "fictional-session"), to: models[2])
        XCTAssertEqual(models[2].state.status, "Cancelled")
        XCTAssertFalse(models[2].active)
        XCTAssertEqual(prompts.count, 3)
    }

    func testAShownTargetKeepsRunningAfterItsFirstTurn() {
        let list = conversations()
        let model = list.fanOut(prompt: "Fictional task", attachments: [], targets: targets(1), headless: false)[0]
        ready(model)
        finishTurn(model)
        XCTAssertEqual(model.state.phase, "ready")
        XCTAssertTrue(model.active)
    }

    // MARK: Unread and limited

    func testOnlyAConversationInTheBackgroundIsMarkedUnread() {
        let list = conversations()
        let models = list.fanOut(prompt: "Fictional task", attachments: [], targets: targets(3), headless: false)
        XCTAssertTrue(list.current === models[0])
        for model in models { ready(model) }
        XCTAssertFalse(models[1].unread, "becoming ready is not a finished turn")
        finishTurn(models[0])
        finishTurn(models[1])
        XCTAssertFalse(models[0].unread, "the shown conversation is read")
        XCTAssertTrue(models[1].unread)
        models[2].fail("Agent process exited.")
        XCTAssertTrue(models[2].unread, "a failure in the background is unread too")
        list.select(models[1])
        XCTAssertFalse(models[1].unread, "showing a conversation clears its mark")
        XCTAssertTrue(list.all.contains { $0 === models[2] }, "an unread conversation that ended is kept")
        XCTAssertEqual(list.listed.map(\.id), [models[0].id, models[1].id, models[2].id])
        list.select(models[2])
        list.select(models[0])
        XCTAssertFalse(list.all.contains { $0 === models[2] }, "once read and left, it is dropped like any ended conversation")
    }

    func testAPlainConversationThatStopsUnseenIsNotMarked() {
        let plain = ACPModel(resumeStore: isolatedStore())
        plain.configure(settings())
        deliver(ACPState(phase: "starting"), to: plain)
        plain.fail("Agent process exited.")
        XCTAssertFalse(plain.unread, "opening it connects it again, so no dot leads to it")
        let isolated = ACPModel(resumeStore: isolatedStore())
        isolated.configure(settings(project: "/tmp/fictional-project"))
        isolated.workspace = "/tmp/fictional-worktrees/fictional-project-00000000"
        deliver(ACPState(phase: "starting"), to: isolated)
        isolated.fail("Agent process exited.")
        XCTAssertTrue(isolated.unread, "one with a workspace opens as it is")
    }

    func testTheLauncherOpensAnUnreadResultWhenNothingRuns() {
        let list = conversations()
        let shown = list.current
        let models = list.fanOut(prompt: "Fictional task", attachments: [], targets: targets(2), headless: true)
        for model in models { ready(model); finishTurn(model) }
        XCTAssertTrue(list.live.isEmpty)
        XCTAssertTrue(list.nextToOpen === models[0])
        XCTAssertEqual(list.shown.map(\.id), [shown.id, models[0].id, models[1].id])
    }

    func testAResultThatEndsWhileAIChatIsHiddenStaysUnreadAndListed() {
        let list = conversations()
        let models = list.fanOut(prompt: "Fictional task", attachments: [], targets: targets(2), headless: true)
        for model in models { ready(model) }
        list.select(models[0])
        // The owner goes back to search or hides the launcher while watching the first result.
        list.chatShown = false
        finishTurn(models[0])
        finishTurn(models[1])
        XCTAssertTrue(models[0].unread, "the current conversation was not on screen when it finished")
        XCTAssertTrue(list.listed.contains { $0 === models[0] })
        list.select(models[1])
        list.chatShown = true
        XCTAssertTrue(list.all.contains { $0 === models[0] }, "opening another result keeps the one not yet read")
        XCTAssertTrue(models[0].unread)
        XCTAssertFalse(models[1].unread, "showing a conversation clears its mark")
    }

    func testLimitedReadsTheProviderMessage() {
        let model = ACPModel(resumeStore: isolatedStore())
        model.state = ACPState(phase: "ready", status: "You have reached your usage limit. It resets at 3 PM.")
        XCTAssertTrue(model.limited)
        model.state.phase = "working"
        XCTAssertFalse(model.limited, "not while a turn runs")
        model.state = ACPState(phase: "ready", status: "Stopped: max_tokens")
        XCTAssertFalse(model.limited)
        model.fail("Rate-limited by the fictional provider.")
        XCTAssertTrue(model.limited)
        XCTAssertEqual(model.state.status, "Rate-limited by the fictional provider.", "the provider's message is kept")
        model.disconnect()
        model.fail(ACPConversationLimit.refusal())
        XCTAssertFalse(model.limited, "Volant's own conversation limit is not a provider's usage limit")
    }

    func testAHeadlessTargetStoppedByAUsageLimitKeepsTheMessage() {
        let list = conversations()
        let model = list.fanOut(prompt: "Fictional task", attachments: [], targets: targets(1), headless: true)[0]
        ready(model)
        drain()
        // The helper reports a session/prompt error as a ready conversation whose status is the error.
        deliver(ACPState(phase: "ready", status: "Claude AI usage limit reached.", sessionID: "fictional-session"), to: model)
        XCTAssertEqual(model.state.phase, "disconnected")
        XCTAssertEqual(model.state.status, "Claude AI usage limit reached.")
        XCTAssertTrue(model.limited)
    }

    // MARK: Helper limit

    func testATargetRefusedAtTheHelperLimitWaitsAndIsTriedAgain() {
        let list = conversations()
        let other = list.current
        list.newConversation(configuration: settings())
        let models = list.fanOut(prompt: "Fictional task", attachments: [], targets: targets(2), headless: true)
        XCTAssertEqual(started.filter { $0 === models[0] }.count, 1)
        models[0].fail(ACPConversationLimit.refusal())
        XCTAssertEqual(list.waiting.map(\.id), [models[0].id], "back at the front of the queue")
        XCTAssertFalse(list.all.contains { $0 === models[0] })
        XCTAssertFalse(models[0].unread)
        XCTAssertNotNil(models[0].pendingPrompt)
        other.disconnect()
        XCTAssertEqual(started.filter { $0 === models[0] }.count, 1, "nothing starts until the retry")
        XCTAssertEqual(retries.count, 1)
        retries.removeFirst()()
        XCTAssertEqual(started.filter { $0 === models[0] }.count, 2)
        XCTAssertTrue(list.waiting.isEmpty)

        for attempt in 2...ACPConversations.retryLimit {
            models[0].fail(ACPConversationLimit.refusal())
            XCTAssertEqual(list.waiting.count, 1)
            retries.removeFirst()()
            XCTAssertEqual(started.filter { $0 === models[0] }.count, attempt + 1)
        }
        XCTAssertEqual(retryDelays, Array(repeating: 1, count: ACPConversations.retryLimit))
        // The helper can refuse for longer, while it makes the workspace of a conversation the app ended.
        for attempt in 1...2 {
            models[0].fail(ACPConversationLimit.refusal())
            XCTAssertEqual(list.waiting.map(\.id), [models[0].id], "it keeps its place")
            XCTAssertNotNil(models[0].pendingPrompt, "and its prompt")
            XCTAssertEqual(retryDelays.last, ACPConversations.slowRetry)
            retries.removeFirst()()
            XCTAssertEqual(started.filter { $0 === models[0] }.count, ACPConversations.retryLimit + 1 + attempt)
        }
        ready(models[0])
        XCTAssertEqual(sentCount(models[0]), 1, "sent once the helper accepts it")
    }

    func testTargetsTheHelperRefusedTogetherKeepTheirOrderWithOneRetry() {
        let list = conversations()
        for _ in 0..<3 { list.newConversation(configuration: settings()) }
        started = []
        let models = list.fanOut(prompt: "Fictional task", attachments: [], targets: targets(4), headless: true)
        XCTAssertEqual(started.map(\.id), models.prefix(3).map(\.id))
        // The helper refuses two, as it can while the slots it is freeing are still on their way.
        models[0].fail(ACPConversationLimit.refusal())
        models[1].fail(ACPConversationLimit.refusal())
        XCTAssertEqual(list.waiting.map(\.id), [models[0].id, models[1].id, models[3].id],
                       "back in their places, ahead of the target that never started")
        XCTAssertEqual(retries.count, 1, "one retry is pending at a time")
        started = []
        retries.removeFirst()()
        XCTAssertEqual(started.map(\.id), [models[0].id, models[1].id], "tried again in their order")
        XCTAssertEqual(list.waiting.map(\.id), [models[3].id])
    }

    func testATargetWaitingAfterALimitRefusalOffersNoResume() throws {
        let list = conversations(sharing: try recordedStore())
        let model = list.fanOut(prompt: "Fictional task", attachments: [], targets: targets(1), headless: false)[0]
        model.fail(ACPConversationLimit.refusal())
        XCTAssertEqual(list.waiting.map(\.id), [model.id])
        XCTAssertTrue(list.current === model)
        XCTAssertFalse(model.canResume, "it has recorded no session, and the stored one is another conversation's")
        retries.removeFirst()()
        XCTAssertEqual(started.filter { $0 === model }.count, 2, "the retry starts it")
        ready(model)
        XCTAssertEqual(sentCount(model), 1)
    }

    // MARK: Folder

    func testAFolderGivesEveryTargetItsOwnWorkspace() {
        let list = conversations()
        let source = list.current
        source.draft = "Fictional task"
        XCTAssertTrue(source.attach(note))
        var checked: [String] = []
        list.worktreeChecker = { path, reply in checked.append(path); reply(nil) }
        var result: String?? = .none
        list.sendToSeveral(from: source, settings: settings(project: "/tmp/fictional-project"), counts: [.claude: 1, .codex: 1], headless: true) { result = .some($0) }
        drain()
        XCTAssertEqual(result, .some(nil))
        XCTAssertEqual(checked, ["/tmp/fictional-project"])
        XCTAssertEqual(started.map(\.provider), ["claude", "codex"])
        XCTAssertTrue(started.allSatisfy { $0.helperStart(resume: nil) == .isolated(project: "/tmp/fictional-project") },
                      "isolated with the setting off")
        XCTAssertEqual(source.draft, "", "the composer's prompt went to the targets")
        XCTAssertTrue(source.attachments.isEmpty)
    }

    func testAFolderTheHelperWouldRefuseStartsNothing() {
        let refusal = "The working folder isn’t a Git repository, so Volant can’t create an isolated workspace for it."
        let list = conversations(folderProblem: refusal)
        let source = list.current
        source.draft = "Fictional task"
        var result: String?
        list.sendToSeveral(from: source, settings: settings(project: "/tmp/fictional-folder"), counts: [.claude: 2], headless: false) { result = $0 }
        drain()
        XCTAssertEqual(result, refusal, "the helper's reason is shown")
        XCTAssertTrue(started.isEmpty)
        XCTAssertTrue(list.waiting.isEmpty)
        XCTAssertEqual(source.draft, "Fictional task", "the prompt stays in the composer")
    }

    func testClosingThePickerDuringTheFolderCheckStartsNothing() {
        let list = conversations()
        let source = list.current
        source.draft = "Fictional task"
        var checks: [(String?) -> Void] = []
        list.worktreeChecker = { _, reply in checks.append(reply) }
        var results: [String?] = []
        let folder = settings(project: "/tmp/fictional-project")
        list.sendToSeveral(from: source, settings: folder, counts: [.claude: 4], headless: true) { results.append($0) }
        list.sendToSeveral(from: source, settings: folder, counts: [.claude: 4], headless: true) { results.append($0) }
        XCTAssertEqual(results, ["Send to Several is still checking the folder."], "a second send while one check is out is refused")
        XCTAssertEqual(checks.count, 1)
        list.cancelSend()
        checks.removeFirst()(nil)
        drain()
        XCTAssertTrue(started.isEmpty, "a check that passes after the picker closed starts nothing")
        XCTAssertTrue(list.waiting.isEmpty)
        XCTAssertEqual(results.count, 1, "and does not reply")
        XCTAssertEqual(source.draft, "Fictional task", "the draft stays")
        list.sendToSeveral(from: source, settings: folder, counts: [.claude: 4], headless: true) { results.append($0) }
        checks.removeFirst()(nil)
        drain()
        XCTAssertEqual(started.count, 4, "a later send checks again and starts its targets once")
        XCTAssertEqual(source.draft, "")
    }

    func testGeneralChatNeedsNoRepository() {
        let list = conversations()
        var checks = 0
        list.worktreeChecker = { _, reply in checks += 1; reply("Fictional refusal") }
        list.current.draft = "Fictional task"
        var result: String?? = .none
        list.sendToSeveral(from: list.current, settings: settings(), counts: [.gemini: 1], headless: true) { result = .some($0) }
        drain()
        XCTAssertEqual(result, .some(nil))
        XCTAssertEqual(checks, 0)
        XCTAssertEqual(started.map { $0.helperStart(resume: nil) }, [.start(project: "")])
    }

    func testAPlanRefusalStartsNothing() {
        let list = conversations()
        list.current.draft = "Fictional task"
        var result: String?
        list.sendToSeveral(from: list.current, settings: settings(), counts: [.claude: 5], headless: true) { result = $0 }
        XCTAssertEqual(result, "Choose at most 4 agents.")
        XCTAssertTrue(started.isEmpty)
    }

    // MARK: Results stay bound

    func testAnEndedTargetOpensAsItIsAndNewStartsBesideIt() {
        let list = conversations()
        let model = list.fanOut(prompt: "Fictional task", attachments: [], targets: targets(1), headless: false)[0]
        ready(model)
        finishTurn(model)
        model.disconnect()
        var connects = 0
        var codex = settings(); codex.provider = "codex"
        XCTAssertTrue(model.openChat(configuration: codex) { connects += 1 })
        XCTAssertEqual(connects, 0, "opening AI Chat shows the result without connecting")
        model.configure(codex)
        XCTAssertEqual(model.provider, "claude", "the agent that produced the transcript is kept")
        XCTAssertTrue(list.newConversation(configuration: codex))
        XCTAssertFalse(list.current === model, "New starts a conversation beside the result")
        XCTAssertEqual(list.current.provider, "codex")
        XCTAssertEqual(model.state.messages.last?.text, "Fictional result")
    }

    func testATargetKeepsItsButtonUntilItsWorkspaceIsRemoved() {
        let list = conversations()
        let models = list.fanOut(prompt: "Fictional task", attachments: [], targets: targets(2, project: "/tmp/fictional-project"), headless: true)
        for (index, model) in models.enumerated() {
            model.workspace = "/tmp/fictional-worktrees/fictional-project-0000000\(index)"
            ready(model)
            finishTurn(model)
        }
        list.select(models[0])
        list.select(models[1])
        XCTAssertTrue(list.shown.contains { $0 === models[0] }, "read and left, it keeps its button while its workspace remains")
        models[0].workspaceRemoved("/tmp/fictional-worktrees/fictional-project-00000000", branch: "volant/00000000", error: nil)
        XCTAssertNil(models[0].workspace)
        list.select(models[1])
        XCTAssertFalse(list.all.contains { $0 === models[0] }, "once its workspace is removed it is dropped like any read conversation")
    }

    func testRemoveWorkspaceWaitsWhileAnotherConversationRunsThere() throws {
        let workspace = try workspaceFolder()
        let list = conversations(sharing: isolatedStore())
        let target = list.fanOut(prompt: "Fictional task", attachments: [], targets: targets(1, project: "/tmp/fictional-project"), headless: true)[0]
        target.workspace = workspace
        ready(target)
        finishTurn(target)
        XCTAssertFalse(target.active)
        XCTAssertTrue(target.canRemoveWorkspace)
        // New reads the record the target wrote, and its Resume loads that session in the target's workspace.
        list.select(target)
        XCTAssertTrue(list.newConversation(configuration: settings(project: "/tmp/fictional-project")))
        let other = list.current
        XCTAssertFalse(other === target)
        other.disconnect()
        var requests: [ACPModel.HelperStart] = []
        other.connector = { requests.append($0) }
        other.resume()
        XCTAssertEqual(requests, [.resume(folder: workspace, session: "fictional-session")])
        list.select(target)
        XCTAssertFalse(target.canRemoveWorkspace, "a live conversation runs in its workspace")
        other.disconnect()
        XCTAssertTrue(target.canRemoveWorkspace)
    }

    func testATargetThatFailedToStartIsNotReusedByNew() {
        let list = conversations()
        let model = list.fanOut(prompt: "Fictional task", attachments: [], targets: targets(1), headless: false)[0]
        model.fail("Agent process exited. Check the provider’s terminal login and reconnect.")
        XCTAssertTrue(list.current === model)
        var codex = settings(); codex.provider = "codex"
        XCTAssertTrue(list.newConversation(configuration: codex))
        XCTAssertFalse(list.current === model, "an unused conversation is started in place, a Send to Several one is not")
        XCTAssertEqual(list.current.provider, "codex")
        XCTAssertEqual(model.provider, "claude")
    }
}
