import CryptoKit
import XCTest
import VolantCore

@testable import Volant

/// Covers the `herdr machine` route end to end in the launcher: which rows appear, what Return
/// does, and what happens while a toggle is in flight. The router's own rules are covered by the
/// package's HerdrMachineToggleTests.
@MainActor
final class HerdrMachineToggleFlowTests: XCTestCase {
    typealias Reply = (Data?, String?) -> Void

    private let acubed = HerdrMachine(id: "acubed", label: "Acubed", target: "fictional-target", session: "default", enabled: true)
    private func disabled(_ machine: HerdrMachine) -> HerdrMachine {
        HerdrMachine(id: machine.id, label: machine.label, target: machine.target, session: machine.session, enabled: false)
    }
    private func drain() async {
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    }

    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("volant-machine-flow-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// A connected agents model whose catalog already holds the given saved machines.
    private func connected(_ machines: [HerdrMachine]) async throws -> AgentsModel {
        let model = AgentsModel()
        var catalog: Reply?
        model.machineReader = { catalog = $0 }
        model.inventoryReader = { _, reply in reply(Data("{\"result\":{\"agents\":[]}}".utf8), nil) }
        model.connected = true
        model.refresh()
        catalog?(try JSONEncoder().encode(machines), nil)
        await drain()
        return model
    }

    private func launcher(_ agents: AgentsModel) -> LauncherModel {
        LauncherModel(index: AppIndex(entries: []),
                      clipboard: ClipboardStore(retention: 10, storageURL: root.appendingPathComponent("clipboard.sqlite"), encryptionKey: SymmetricKey(size: .bits256)),
                      notes: NotesStore(directory: root.appendingPathComponent("Notes")),
                      config: Preferences(),
                      usage: UsageStore(url: root.appendingPathComponent("usage.sqlite")),
                      agents: agents) { _ in }
    }

    func testMachineRouteListsLocalAndEachSavedMachine() async throws {
        let agents = try await connected([acubed])
        let model = launcher(agents)

        model.query = "herdr machine"
        await drain()

        XCTAssertTrue(model.showingMachines)
        XCTAssertEqual(model.sections.first?.title, "Herdr machines")
        XCTAssertEqual(model.rows.map(\.id), ["herdr-machine:local", "herdr-machine:acubed"])
    }

    func testLocalIsListedButOffersNoToggle() async throws {
        let agents = try await connected([acubed])
        let model = launcher(agents)
        model.query = "herdr machine"
        await drain()

        let local = try XCTUnwrap(model.rows.first)
        XCTAssertEqual(local.primaryAction, "Always on")

        var wrote = false
        agents.machineWriter = { _, _, _ in wrote = true }
        model.selection = 0
        model.activateSelection()
        await drain()
        XCTAssertFalse(wrote, "Local is not a saved machine and cannot be disabled")
    }

    func testReturnOnAnEnabledMachineAsksHerdrToDisableIt() async throws {
        let agents = try await connected([acubed])
        let model = launcher(agents)
        model.query = "herdr machine"
        await drain()

        var requested: (HerdrMachine, Bool)?
        var reply: Reply?
        agents.machineWriter = { machine, enabled, callback in requested = (machine, enabled); reply = callback }

        model.selection = 1
        XCTAssertEqual(model.selectedRow?.primaryAction, "Disable Machine")
        model.activateSelection()
        await drain()

        XCTAssertEqual(requested?.0.id, "acubed")
        XCTAssertEqual(requested?.1, false)

        reply?(try JSONEncoder().encode([disabled(acubed)]), nil)
        await drain()
        XCTAssertEqual(agents.profiles.first?.enabled, false)
    }

    func testADisabledMachineOffersToEnableItAgain() async throws {
        let agents = try await connected([disabled(acubed)])
        let model = launcher(agents)
        model.query = "herdr machine"
        await drain()

        model.selection = 1
        XCTAssertEqual(model.selectedRow?.primaryAction, "Enable Machine")
        XCTAssertEqual(model.selectedRow?.kind, "Disabled")

        var requested: Bool?
        agents.machineWriter = { _, enabled, _ in requested = enabled }
        model.activateSelection()
        await drain()
        XCTAssertEqual(requested, true)
    }

    func testTheCatalogFromHerdrWinsOverTheRequestedValue() async throws {
        let agents = try await connected([acubed])
        let model = launcher(agents)
        model.query = "herdr machine"
        await drain()

        var reply: Reply?
        agents.machineWriter = { _, _, callback in reply = callback }
        model.selection = 1
        model.activateSelection()
        await drain()

        // Herdr reports the machine still enabled, whatever the launcher asked for.
        reply?(try JSONEncoder().encode([acubed]), nil)
        await drain()
        XCTAssertEqual(agents.profiles.first?.enabled, true)
        XCTAssertEqual(model.rows.last?.kind, "Enabled")
    }

    func testASecondToggleIsIgnoredWhileOneIsInFlight() async throws {
        let agents = try await connected([acubed])
        let model = launcher(agents)
        model.query = "herdr machine"
        await drain()

        var calls = 0
        agents.machineWriter = { _, _, _ in calls += 1 }
        model.selection = 1
        model.activateSelection()
        model.activateSelection()
        await drain()

        XCTAssertEqual(calls, 1)
        XCTAssertEqual(agents.machineToggleInFlight, "acubed")
        XCTAssertEqual(model.rows.last?.primaryAction, "Working…")
    }

    func testAFailureSurfacesTheErrorAndClearsTheInFlightState() async throws {
        let agents = try await connected([acubed])
        let model = launcher(agents)
        model.query = "herdr machine"
        await drain()

        var reply: Reply?
        agents.machineWriter = { _, _, callback in reply = callback }
        model.selection = 1
        model.activateSelection()
        await drain()

        reply?(nil, "This saved machine changed or was removed. Refresh before continuing.")
        await drain()

        XCTAssertNil(agents.machineToggleInFlight)
        XCTAssertEqual(agents.actionMessage, "This saved machine changed or was removed. Refresh before continuing.")
        XCTAssertEqual(agents.profiles.first?.enabled, true, "a failed toggle must not move the row")
    }

    func testATrailingTermFiltersTheMachineList() async throws {
        let agents = try await connected([acubed])
        let model = launcher(agents)

        model.query = "herdr machine acu"
        await drain()
        XCTAssertEqual(model.rows.map(\.id), ["herdr-machine:acubed"])

        model.query = "herdr machine loc"
        await drain()
        XCTAssertEqual(model.rows.map(\.id), ["herdr-machine:local"])
    }
}
