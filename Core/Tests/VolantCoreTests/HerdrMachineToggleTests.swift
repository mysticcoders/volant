import XCTest

@testable import VolantCore

/// Stands in for the Herdr CLI: holds the saved machines and mutates them when told to,
/// so a test reads the same state the router would see on its next call.
private final class FakeHerdr {
    struct Saved {
        var id: String
        var target: String
        var enabled: Bool
    }

    var saved: [Saved]
    private(set) var calls: [[String]] = []

    init(_ saved: [Saved]) { self.saved = saved }

    var toggleCalls: [[String]] { calls.filter { $0.count == 3 && $0[0] == "machine" && ["enable", "disable"].contains($0[1]) } }

    func run(_ arguments: [String]) throws -> Data {
        calls.append(arguments)
        if arguments == ["machine", "list", "--json"] {
            let rows = saved.map {
                "{\"id\":\"\($0.id)\",\"label\":\"\($0.id.capitalized)\",\"target\":\"\($0.target)\",\"session\":\"main\",\"enabled\":\($0.enabled)}"
            }
            return Data("[\(rows.joined(separator: ","))]".utf8)
        }
        if arguments.count == 3, arguments[0] == "machine", ["enable", "disable"].contains(arguments[1]) {
            guard let index = saved.firstIndex(where: { $0.id == arguments[2] }) else {
                throw CocoaError(.fileNoSuchFile)
            }
            saved[index].enabled = arguments[1] == "enable"
            return Data("{}".utf8)
        }
        return Data("{}".utf8)
    }
}

final class HerdrMachineToggleTests: XCTestCase {
    private func machine(_ id: String, target: String = "", enabled: Bool) -> HerdrMachine {
        HerdrMachine(id: id, label: id.capitalized, target: target.isEmpty ? "user@\(id)" : target,
                     session: "main", enabled: enabled)
    }

    func testDisablingRunsHerdrsOwnCommandWithTheSavedIdentifier() throws {
        let herdr = FakeHerdr([.init(id: "acubed", target: "user@acubed", enabled: true)])
        let router = HerdrMachineRouter(run: herdr.run)

        let profiles = try router.setEnabled(machine("acubed", enabled: true), false)

        XCTAssertEqual(herdr.toggleCalls, [["machine", "disable", "acubed"]])
        XCTAssertEqual(profiles.first?.enabled, false, "the refreshed catalog is what the caller renders")
        XCTAssertEqual(herdr.saved.first?.enabled, false)
    }

    func testEnablingUsesTheEnableVerb() throws {
        let herdr = FakeHerdr([.init(id: "acubed", target: "user@acubed", enabled: false)])
        let router = HerdrMachineRouter(run: herdr.run)

        let profiles = try router.setEnabled(machine("acubed", enabled: false), true)

        XCTAssertEqual(herdr.toggleCalls, [["machine", "enable", "acubed"]])
        XCTAssertEqual(profiles.first?.enabled, true)
    }

    func testAlreadyInTheRequestedStateRunsNoCommand() throws {
        let herdr = FakeHerdr([.init(id: "acubed", target: "user@acubed", enabled: true)])
        let router = HerdrMachineRouter(run: herdr.run)

        try router.setEnabled(machine("acubed", enabled: true), true)

        XCTAssertTrue(herdr.toggleCalls.isEmpty, "a no-op must not run enable or disable")
    }

    func testARemovedMachineIsRefusedRatherThanEditedByIdentifier() {
        let herdr = FakeHerdr([.init(id: "other", target: "user@other", enabled: true)])
        let router = HerdrMachineRouter(run: herdr.run)

        XCTAssertThrowsError(try router.setEnabled(machine("acubed", enabled: true), false)) { error in
            XCTAssertTrue((error as NSError).localizedDescription.contains("changed or was removed"))
        }
        XCTAssertTrue(herdr.toggleCalls.isEmpty)
    }

    func testAMachineWhoseTargetChangedIsRefused() {
        let herdr = FakeHerdr([.init(id: "acubed", target: "user@acubed", enabled: true)])
        let router = HerdrMachineRouter(run: herdr.run)
        let stale = machine("acubed", target: "user@elsewhere", enabled: true)

        XCTAssertThrowsError(try router.setEnabled(stale, false)) { error in
            XCTAssertTrue((error as NSError).localizedDescription.contains("changed or was removed"))
        }
        XCTAssertTrue(herdr.toggleCalls.isEmpty, "route identity covers the SSH target, not just the id")
    }

    func testADisabledMachineCanStillBeSwitchedBackOn() throws {
        let herdr = FakeHerdr([.init(id: "acubed", target: "user@acubed", enabled: false)])
        let router = HerdrMachineRouter(run: herdr.run)
        let disabled = machine("acubed", enabled: false)

        // execute() deliberately refuses a disabled machine; setEnabled must not share that rule,
        // or a machine turned off could never be turned back on from the launcher.
        XCTAssertThrowsError(try router.execute(disabled, ["agent", "list"]))
        try router.setEnabled(disabled, true)

        XCTAssertEqual(herdr.toggleCalls, [["machine", "enable", "acubed"]])
        XCTAssertEqual(herdr.saved.first?.enabled, true)
    }

    func testTogglingOneMachineLeavesTheOthersAlone() throws {
        let herdr = FakeHerdr([
            .init(id: "acubed", target: "user@acubed", enabled: true),
            .init(id: "build", target: "user@build", enabled: true),
        ])
        let router = HerdrMachineRouter(run: herdr.run)

        let profiles = try router.setEnabled(machine("acubed", enabled: true), false)

        XCTAssertEqual(profiles.first { $0.id == "acubed" }?.enabled, false)
        XCTAssertEqual(profiles.first { $0.id == "build" }?.enabled, true)
    }
}
