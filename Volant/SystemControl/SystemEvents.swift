import AppKit
import VolantCore

/// Why a System Events change did not happen, from the Apple Event Manager's status codes.
enum SystemEventsFailure: Error, Equatable {
    /// The owner turned off Volant's Automation access to System Events (`errAEEventNotPermitted`).
    case denied
    /// System Events could not be started or reached (`procNotFound` and similar).
    case unavailable
    /// Neither the consent prompt nor System Events answered in time (`errAETimeout`).
    case noAnswer
    /// System Events accepted the change, but reading it back shows the old value.
    case notApplied
    case failed(Int)

    static let notPermitted = -1743
    static let wouldRequireConsent = -1744
    static let timedOut = -1712
    static let processNotFound = -600
    static let connectionInvalid = -609

    init(status: Int) {
        switch status {
        case Self.notPermitted: self = .denied
        case Self.timedOut: self = .noAnswer
        case Self.processNotFound, Self.connectionInvalid: self = .unavailable
        default: self = .failed(status)
        }
    }

    /// Whether the launcher should offer Privacy & Security › Automation.
    var needsPrivacySettings: Bool { self == .denied }

    var message: String {
        switch self {
        case .denied: return String(localized: "Volant isn’t allowed to control System Events. Turn it on in System Settings › Privacy & Security › Automation.", comment: "Launcher message when Automation access to System Events is off")
        case .unavailable: return String(localized: "Couldn’t reach System Events. Try again.", comment: "Launcher message when System Events could not be started")
        case .noAnswer: return String(localized: "macOS didn’t answer in time. Try again, and allow Volant to control System Events if asked.", comment: "Launcher message when the Automation prompt or System Events timed out")
        case .notApplied: return String(localized: "macOS didn’t apply the change.", comment: "Launcher message when System Events accepted a change but the setting did not change")
        case .failed(let status): return String(localized: "System Events reported error \(status, specifier: "%lld").", comment: "Launcher message for an unexpected System Events error; the value is a numeric error code")
        }
    }
}

/// The three steps a toggle takes with System Events, apart from Apple Events so tests can run
/// them against a fake. Every method blocks and must run off the main thread.
protocol SystemEventsRunning {
    /// Starts System Events if needed and asks for Automation consent the first time.
    func prepare() throws
    func readBoolean(container: String, property: String) throws -> Bool
    func writeBoolean(container: String, property: String, value: Bool) throws
}

/// Flips a `SystemToggle` by reading its System Events property, writing the opposite and reading
/// it back, so a change macOS ignores is reported rather than shown as done.
final class SystemToggleService {
    private let runner: SystemEventsRunning
    private let queue: DispatchQueue?

    /// Runs on a private queue; tests pass `queue: nil` to run synchronously.
    init(runner: SystemEventsRunning = AppleEventSystemEvents(),
         queue: DispatchQueue? = DispatchQueue(label: "com.mysticcoders.volant.system-events")) {
        self.runner = runner
        self.queue = queue
    }

    /// Toggles the setting and reports its new value, or why it did not change, on the main
    /// thread. Keeps the launcher visible while macOS may show its Automation prompt.
    func toggle(_ toggle: SystemToggle, completion: @escaping (Result<Bool, SystemEventsFailure>) -> Void) {
        guard let queue else { completion(Self.perform(toggle, runner: runner)); return }
        PermissionGate.begin()
        queue.async { [runner] in
            let result = Self.perform(toggle, runner: runner)
            DispatchQueue.main.async {
                PermissionGate.end()
                completion(result)
            }
        }
    }

    /// The blocking read, write and confirm sequence.
    static func perform(_ toggle: SystemToggle, runner: SystemEventsRunning) -> Result<Bool, SystemEventsFailure> {
        let (container, property) = toggle.systemEventsProperty
        do {
            try runner.prepare()
            let current = try runner.readBoolean(container: container, property: property)
            try runner.writeBoolean(container: container, property: property, value: !current)
            guard try runner.readBoolean(container: container, property: property) == !current else { return .failure(.notApplied) }
            return .success(!current)
        } catch let failure as SystemEventsFailure {
            return .failure(failure)
        } catch {
            return .failure(SystemEventsFailure(status: (error as NSError).code))
        }
    }
}

/// Apple Events to System Events, the only app Volant automates besides loginwindow. The sandbox
/// allows them through the `com.apple.systemevents` Apple Events exception; macOS asks the owner
/// once for Automation consent. Events are built directly, not compiled from AppleScript, so they
/// can be sent off the main thread.
struct AppleEventSystemEvents: SystemEventsRunning {
    static let bundleIdentifier = "com.apple.systemevents"
    static let applicationURL = URL(fileURLWithPath: "/System/Library/CoreServices/System Events.app")
    static let replyTimeout: TimeInterval = 15
    static let launchTimeout: TimeInterval = 10

    func prepare() throws {
        if NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).isEmpty { try launch() }
        let target = NSAppleEventDescriptor(bundleIdentifier: Self.bundleIdentifier)
        guard let desc = target.aeDesc else { throw SystemEventsFailure.unavailable }
        let status = Int(AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, true))
        // A status other than a refusal is left to the event itself, which reports the real outcome.
        if status == SystemEventsFailure.notPermitted || status == SystemEventsFailure.processNotFound {
            throw SystemEventsFailure(status: status)
        }
    }

    func readBoolean(container: String, property: String) throws -> Bool {
        let event = Self.event(AEEventID(kAEGetData))
        event.setParam(Self.specifier(property, in: container), forKeyword: keyDirectObject)
        let reply = try Self.send(event)
        guard let value = reply.paramDescriptor(forKeyword: keyDirectObject) else { throw SystemEventsFailure.failed(0) }
        return value.booleanValue
    }

    func writeBoolean(container: String, property: String, value: Bool) throws {
        let event = Self.event(AEEventID(kAESetData))
        event.setParam(Self.specifier(property, in: container), forKeyword: keyDirectObject)
        event.setParam(NSAppleEventDescriptor(boolean: value), forKeyword: AEKeyword(keyAEData))
        _ = try Self.send(event)
    }

    /// Opens System Events without activating it and waits until it is running.
    private func launch() throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        let launched = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: Self.applicationURL, configuration: configuration) { _, _ in launched.signal() }
        _ = launched.wait(timeout: .now() + Self.launchTimeout)
        let deadline = Date().addingTimeInterval(Self.launchTimeout)
        while NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).isEmpty {
            guard Date() < deadline else { throw SystemEventsFailure.unavailable }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    private static func event(_ id: AEEventID) -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(eventClass: AEEventClass(kAECoreSuite), eventID: id,
                               targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier),
                               returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
    }

    /// `property <code> of property <container> of application "System Events"`.
    static func specifier(_ property: String, in container: String) -> NSAppleEventDescriptor {
        propertySpecifier(code(property), of: propertySpecifier(code(container), of: NSAppleEventDescriptor.null()))
    }

    private static func propertySpecifier(_ code: FourCharCode, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let specifier = NSAppleEventDescriptor.record().coerce(toDescriptorType: DescType(typeObjectSpecifier))!
        specifier.setDescriptor(NSAppleEventDescriptor(typeCode: DescType(cProperty)), forKeyword: AEKeyword(keyAEDesiredClass))
        specifier.setDescriptor(NSAppleEventDescriptor(enumCode: DescType(formPropertyID)), forKeyword: AEKeyword(keyAEKeyForm))
        specifier.setDescriptor(NSAppleEventDescriptor(typeCode: code), forKeyword: AEKeyword(keyAEKeyData))
        specifier.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
        return specifier
    }

    /// A four-character code such as `thme` as its 32-bit value.
    static func code(_ text: String) -> FourCharCode {
        text.utf8.reduce(FourCharCode(0)) { $0 << 8 | FourCharCode($1) }
    }

    /// Sends and waits for the reply, turning a send error or an error in the reply into a failure.
    private static func send(_ event: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        let reply: NSAppleEventDescriptor
        do { reply = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: replyTimeout) }
        catch { throw SystemEventsFailure(status: (error as NSError).code) }
        if let number = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber))?.int32Value, number != 0 {
            throw SystemEventsFailure(status: Int(number))
        }
        return reply
    }
}
