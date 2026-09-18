import Foundation

/// A saved destination, not an arbitrary SSH target supplied by the UI.
struct HerdrMachine: Codable, Hashable, Identifiable {
    let id: String
    let label: String
    let target: String
    let session: String
    let enabled: Bool
    var routeIdentity: String { [id, target, session].map { "\($0.utf8.count):\($0)" }.joined() }
    static func decode(_ data: Data) throws -> [Self] {
        let profiles = try JSONDecoder().decode([Self].self, from: data)
        guard profiles.count <= 64, Set(profiles.map(\.id)).count == profiles.count,
              profiles.allSatisfy({ !$0.id.isEmpty && !$0.id.hasPrefix("-") && $0.id.count <= 128 &&
                  !$0.target.isEmpty && !$0.session.isEmpty }) else { throw CocoaError(.fileReadCorruptFile) }
        return profiles
    }
}

struct HerdrMachineStatus: Codable, Identifiable {
    let id: String
    let label: String
    let state: String
    let detail: String
    var unavailable: Bool { state == "unavailable" }
}

struct HerdrInventory: Codable {
    let agents: [AgentSession]
    let machines: [HerdrMachineStatus]
}

/// All remote operations recheck the saved profile. Never fall back to Local.
final class HerdrMachineRouter {
    let run: ([String]) throws -> Data
    init(run: @escaping ([String]) throws -> Data) { self.run = run }
    func profiles() throws -> [HerdrMachine] { try HerdrMachine.decode(run(["machine", "list", "--json"])) }
    func execute(_ machine: HerdrMachine?, _ arguments: [String]) throws -> Data {
        guard let machine else { return try run(arguments) }
        guard try profiles().contains(where: { $0.enabled && $0.routeIdentity == machine.routeIdentity }) else {
            throw NSError(domain: "VolantHerdrResponse", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "This saved machine changed or was disabled. Refresh before continuing."])
        }
        return try run(["--machine", machine.id] + arguments)
    }
    func agents(on machine: HerdrMachine?) throws -> [AgentSession] {
        try AgentSession.decodeList(execute(machine, ["agent", "list"]), machine: machine)
    }

    /// Bounded parallel discovery, independent of the serialized answer queue.
    func inventory() -> HerdrInventory {
        var destinations: [HerdrMachine?] = [nil]
        var statuses: [HerdrMachineStatus] = []
        do {
            for machine in try profiles() {
                if machine.enabled { destinations.append(machine) }
                else { statuses.append(.init(id: "remote:" + machine.id, label: machine.label, state: "disabled", detail: "Disabled in Herdr")) }
            }
        } catch {
            statuses.append(.init(id: "catalog", label: "Saved machines", state: "unavailable",
                                  detail: "Couldn’t read saved machines. Check Herdr 0.9.1 or later is installed."))
        }
        let results = InventoryResults(statuses: statuses)
        let workers = OperationQueue()
        workers.maxConcurrentOperationCount = 4
        for machine in destinations {
            workers.addOperation {
                do {
                    let agents = try self.agents(on: machine)
                    results.append(agents, status: .init(id: machine.map { "remote:" + $0.id } ?? "local", label: machine?.label ?? "Local",
                        state: "connected", detail: "\(agents.count) panes"))
                } catch {
                    results.append([], status: .init(id: machine.map { "remote:" + $0.id } ?? "local", label: machine?.label ?? "Local",
                        state: "unavailable", detail: machine == nil ? "Start the local default Herdr session." :
                            "Check SSH access and Herdr 0.9.1 or later on this machine."))
                }
            }
        }
        workers.waitUntilAllOperationsAreFinished()
        return results.snapshot()
    }
}

private final class InventoryResults: @unchecked Sendable {
    private let lock = NSLock()
    private var agents: [AgentSession] = []
    private var statuses: [HerdrMachineStatus]
    init(statuses: [HerdrMachineStatus]) { self.statuses = statuses }
    func append(_ values: [AgentSession], status: HerdrMachineStatus) {
        lock.lock(); defer { lock.unlock() }
        agents += values; statuses.append(status)
    }
    func snapshot() -> HerdrInventory {
        lock.lock(); defer { lock.unlock() }
        return HerdrInventory(agents: AgentSession.sorted(agents), machines: statuses.sorted {
            if $0.id == "local" { return true }; if $1.id == "local" { return false }
            return $0.label == $1.label ? $0.id < $1.id : $0.label.localizedStandardCompare($1.label) == .orderedAscending
        })
    }
}
