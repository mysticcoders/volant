import Combine
import CryptoKit
import XCTest
import VolantCore
@testable import Volant

/// Herdr refreshes every five seconds and a slow remote machine replies late. Each change the
/// agents model announces used to redraw the whole launcher, results list included, which made
/// scrolling stutter while a remote was loading.
@MainActor
final class HerdrPublishTests: XCTestCase {
    typealias Reply = (Data?, String?) -> Void
    private let remote = HerdrMachine(id: "studio", label: "Studio", target: "fictional", session: "default", enabled: true)
    private func drain() async { await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } } }
    private func panes(_ machine: HerdrMachine?, count: Int, blocked: Int = 0) throws -> Data {
        try JSONEncoder().encode((0..<count).map { n -> AgentSession in
            var pane = AgentSession(agent: "claude", agentStatus: n < blocked ? "blocked" : "working", paneID: "w1:p\(n)", terminalID: "t\(n)",
                                    cwd: "/fictional/project\(n)", stateChangeSequence: 1)
            pane.machine = machine
            return pane
        })
    }

    /// Ten refresh ticks: Local answers at once with the same four panes, the catalog lists one
    /// remote machine, and the remote stays loading until the last tick, when it answers.
    private func runScenario(_ model: AgentsModel) async throws -> Int {
        var catalog: Reply?, local: Reply?, remoteReply: Reply?
        model.machineReader = { catalog = $0 }
        model.inventoryReader = { machine, reply in if machine == nil { local = reply } else { remoteReply = reply } }
        model.repositoryReader = { _, reply in reply(Data("{}".utf8), nil) }
        var emissions = 0
        let counter = model.objectWillChange.sink { _ in emissions += 1 }
        defer { counter.cancel() }
        model.connected = true
        for tick in 0..<10 {
            model.refresh()
            local?(try panes(nil, count: 4), nil)
            catalog?(try JSONEncoder().encode([remote]), nil)
            await drain()
            if tick == 9 { remoteReply?(try panes(remote, count: 3, blocked: 1), nil); await drain() }
        }
        XCTAssertEqual(model.sessions.count, 7)
        XCTAssertEqual(model.machines.map(\.state), ["connected", "connected"])
        return emissions
    }

    func testRefreshTicksPublishOnlyRealChanges() async throws {
        let emissions = try await runScenario(AgentsModel())
        print("HerdrPublishTests: agents model emissions over 10 ticks with a slow remote: \(emissions)")
        // Before only real changes were assigned, this scenario announced 197 changes; now only the
        // first tick and the remote's late answer change anything (14 changes).
        XCTAssertLessThanOrEqual(emissions, 16)
    }

    /// Clicking the footer status opens the `herdr` list, narrowed to the agent chosen in Settings,
    /// with waiting panes first.
    func testFooterStatusOpensHerdrWithWaitingPanesFirst() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let agents = AgentsModel()
        let model = LauncherModel(index: AppIndex(entries: []), clipboard: ClipboardStore(retention: 2, storageURL: root.appendingPathComponent("clips.sqlite"), encryptionKey: SymmetricKey(size: .bits256)),
                                  notes: NotesStore(directory: root.appendingPathComponent("Notes")), config: Preferences(),
                                  usage: UsageStore(url: root.appendingPathComponent("usage.sqlite")), files: FileSearch(startQuery: { _ in false }), agents: agents) { _ in }
        model.searchesSecondarySources = false
        agents.connected = true
        let working = AgentSession(agent: "codex", agentStatus: "working", paneID: "w1:p1", terminalID: "t1")
        let waiting = AgentSession(agent: "claude", agentStatus: "blocked", paneID: "w1:p2", terminalID: "t2")
        agents.sessions = AgentSession.sorted([working, waiting])
        model.promotedHarness = "all"
        model.showPromotedAgents()
        XCTAssertEqual(model.query, "herdr")
        XCTAssertTrue(model.showingAgents)
        XCTAssertEqual(model.rows.first?.id, ResultRow.agentSession(waiting).id)
        model.promotedHarness = "claude"
        model.showPromotedAgents()
        XCTAssertEqual(model.query, "herdr claude")
        XCTAssertEqual(model.rows.map(\.id), [ResultRow.agentSession(waiting).id])
    }

    func testHerdrChangesDoNotRedrawTheLauncherOutsideHerdr() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let agents = AgentsModel()
        let model = LauncherModel(index: AppIndex(entries: []), clipboard: ClipboardStore(retention: 2, storageURL: root.appendingPathComponent("clips.sqlite"), encryptionKey: SymmetricKey(size: .bits256)),
                                  notes: NotesStore(directory: root.appendingPathComponent("Notes")), config: Preferences(),
                                  usage: UsageStore(url: root.appendingPathComponent("usage.sqlite")), files: FileSearch(startQuery: { _ in false }), agents: agents) { _ in }
        model.searchesSecondarySources = false
        model.query = "safari"
        var launcherEmissions = 0
        let counter = model.objectWillChange.sink { _ in launcherEmissions += 1 }
        defer { counter.cancel() }
        _ = try await runScenario(agents)
        print("HerdrPublishTests: launcher model emissions during Herdr refreshes: \(launcherEmissions)")
        XCTAssertEqual(launcherEmissions, 0)
        let view = LauncherView(model: model, agents: agents)
        XCTAssertFalse(Mirror(reflecting: view).children.contains { String(describing: type(of: $0.value)).contains("ObservedObject<AgentsModel>") },
                       "The launcher view must not observe the agents model; only Herdr's own views do.")
    }
}
