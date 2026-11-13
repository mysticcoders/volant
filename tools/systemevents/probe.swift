import AppKit
import VolantCore

// Probe for the System Appearance and menu bar toggles: runs the shipped AppleEventSystemEvents
// from a sandboxed, Developer ID signed bundle carrying only the entitlements Volant ships, and
// prints one JSON line. `get` reads both properties; `toggle <appearance|menuBar>` flips one and
// reports what System Events and the global preferences say before and after.

/// Reads the global preferences domain the way the launcher's row description does.
func globalDefaults() -> [String: Any]? {
    UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
}

/// Runs one System Events read and reports its value or error status.
func read(_ toggle: SystemToggle, _ runner: AppleEventSystemEvents) -> Any {
    let (container, property) = toggle.systemEventsProperty
    do { return try runner.readBoolean(container: container, property: property) } catch { return String(describing: error) }
}

let runner = AppleEventSystemEvents()
let arguments = CommandLine.arguments.dropFirst()
var result: [String: Any] = ["sandboxed": ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil]
do { try runner.prepare(); result["prepare"] = "ok" } catch { result["prepare"] = String(describing: error) }
if arguments.first == "toggle", let name = arguments.dropFirst().first, let toggle = SystemToggle(rawValue: name) {
    result["before"] = read(toggle, runner)
    result["defaultsBefore"] = toggle.state(inGlobalDefaults: globalDefaults()).map { $0 as Any } ?? "unknown"
    switch SystemToggleService.perform(toggle, runner: runner) {
    case .success(let value): result["toggled"] = value
    case .failure(let failure): result["failure"] = String(describing: failure)
    }
    Thread.sleep(forTimeInterval: 1)
    result["after"] = read(toggle, runner)
    result["defaultsAfter"] = toggle.state(inGlobalDefaults: globalDefaults()).map { $0 as Any } ?? "unknown"
} else {
    for toggle in SystemToggle.allCases {
        result[toggle.rawValue] = read(toggle, runner)
        result[toggle.rawValue + "Defaults"] = toggle.state(inGlobalDefaults: globalDefaults()).map { $0 as Any } ?? "unknown"
    }
}
let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
