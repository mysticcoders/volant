import AppKit
import VolantCore

/// A browser Focus can ask for its current tab, with the codes from its scripting dictionary.
/// Safari names the tab `current tab` and indexes it within its window; Chromium browsers name it
/// `active tab` and give it a unique ID.
struct FocusBrowser: Hashable {
    let bundleIdentifier: String
    let name: String
    let currentTab: String
    let tabClass: String
    let address: String
    let tabByID: Bool

    static func chromium(_ bundleIdentifier: String, _ name: String) -> FocusBrowser {
        FocusBrowser(bundleIdentifier: bundleIdentifier, name: name, currentTab: "acTa", tabClass: "CrTb", address: "URL ", tabByID: true)
    }

    static func safari(_ bundleIdentifier: String, _ name: String) -> FocusBrowser {
        FocusBrowser(bundleIdentifier: bundleIdentifier, name: name, currentTab: "cTab", tabClass: "bTab", address: "pURL", tabByID: false)
    }

    /// Every browser Focus knows how to ask. Each also needs its bundle identifier in the
    /// `temporary-exception.apple-events` entitlement, and is listed to owners only once verified.
    static let all: [FocusBrowser] = [
        .safari("com.apple.Safari", "Safari"),
        .safari("com.apple.SafariTechnologyPreview", "Safari Technology Preview"),
        .chromium("com.google.Chrome", "Google Chrome"),
        .chromium("com.brave.Browser", "Brave"),
        .chromium("com.brave.Browser.origin", "Brave Origin"),
        .chromium("com.vivaldi.Vivaldi", "Vivaldi"),
        .chromium("com.microsoft.edgemac", "Microsoft Edge"),
        .chromium("company.thebrowser.Browser", "Arc"),
        .chromium("org.chromium.Chromium", "Chromium")
    ]

    static func named(_ bundleIdentifier: String) -> FocusBrowser? {
        all.first { $0.bundleIdentifier == bundleIdentifier }
    }
}

/// A browser tab Focus read or blanked: which browser, window and tab, and the address it showed.
/// Held in memory only, and only for tabs Focus blanked, so they can be put back.
struct FocusOpenTab {
    let browser: FocusBrowser
    let window: NSAppleEventDescriptor
    let tab: NSAppleEventDescriptor
    let address: String

    /// Identifies the tab across reads, so one tab is blanked and restored once.
    var key: String { [browser.bundleIdentifier, Self.text(window), Self.text(tab)].joined(separator: "|") }

    private static func text(_ descriptor: NSAppleEventDescriptor) -> String {
        descriptor.stringValue ?? String(descriptor.int32Value)
    }
}

/// Why a browser didn't answer.
enum FocusBrowserFailure: Error, Equatable {
    /// The owner refused Volant's Automation access to this browser (`errAEEventNotPermitted`).
    case denied
    case unavailable
    case failed(Int)

    init(status: Int) {
        switch status {
        case -1743: self = .denied
        case -600, -609, -1712, -1728: self = .unavailable
        default: self = .failed(status)
        }
    }
}

/// Reads and changes a browser's current tab, apart from Apple Events so tests can use a fake.
/// Every method blocks and runs off the main thread.
protocol FocusBrowserAccess {
    /// The front window's current tab, or nil when the browser has no window.
    func currentTab(of browser: FocusBrowser) throws -> FocusOpenTab?
    /// Replaces the tab's page with a blank one.
    func blank(_ tab: FocusOpenTab) throws
    /// Puts the tab's address back if the tab still shows the blank page; returns whether it did.
    func restore(_ tab: FocusOpenTab) throws -> Bool
}

/// Apple Events to supported browsers, built directly rather than compiled from AppleScript so
/// they can be sent off the main thread. The sandbox allows them through the browsers' Apple
/// Events exception, and macOS asks the owner once per browser. Nothing here launches a browser:
/// Focus only asks the browser that is already in front.
struct AppleEventFocusBrowsers: FocusBrowserAccess {
    static let blankAddress = "about:blank"
    static let replyTimeout: TimeInterval = 30

    func currentTab(of browser: FocusBrowser) throws -> FocusOpenTab? {
        let frontWindow = Self.element("cwin", position: 1, of: .null())
        guard let window = try? Self.get(Self.property("ID  ", of: frontWindow), browser: browser) else { return nil }
        let windowSpecifier = Self.element("cwin", uniqueID: window, of: .null())
        let current = Self.property(browser.currentTab, of: windowSpecifier)
        let tab = try Self.get(Self.property(browser.tabByID ? "ID  " : "pidx", of: current), browser: browser)
        let address = try Self.get(Self.property(browser.address, of: Self.tab(tab, in: windowSpecifier, browser: browser)), browser: browser)
        return FocusOpenTab(browser: browser, window: window, tab: tab, address: address.stringValue ?? "")
    }

    func blank(_ tab: FocusOpenTab) throws {
        try Self.set(Self.addressSpecifier(tab), to: NSAppleEventDescriptor(string: Self.blankAddress), browser: tab.browser)
    }

    func restore(_ tab: FocusOpenTab) throws -> Bool {
        let specifier = Self.addressSpecifier(tab)
        let shown = try Self.get(specifier, browser: tab.browser).stringValue ?? ""
        guard shown == Self.blankAddress || shown.isEmpty else { return false }
        try Self.set(specifier, to: NSAppleEventDescriptor(string: tab.address), browser: tab.browser)
        return true
    }

    private static func addressSpecifier(_ tab: FocusOpenTab) -> NSAppleEventDescriptor {
        let window = element("cwin", uniqueID: tab.window, of: .null())
        return property(tab.browser.address, of: self.tab(tab.tab, in: window, browser: tab.browser))
    }

    /// A tab by its unique ID in Chromium browsers, or by its index in Safari.
    private static func tab(_ key: NSAppleEventDescriptor, in window: NSAppleEventDescriptor, browser: FocusBrowser) -> NSAppleEventDescriptor {
        browser.tabByID ? element(browser.tabClass, uniqueID: key, of: window) : element(browser.tabClass, position: Int(key.int32Value), of: window)
    }

    private static func get(_ specifier: NSAppleEventDescriptor, browser: FocusBrowser) throws -> NSAppleEventDescriptor {
        let event = event(AEEventID(kAEGetData), browser: browser)
        event.setParam(specifier, forKeyword: keyDirectObject)
        guard let value = try send(event).paramDescriptor(forKeyword: keyDirectObject) else { throw FocusBrowserFailure.unavailable }
        return value
    }

    private static func set(_ specifier: NSAppleEventDescriptor, to value: NSAppleEventDescriptor, browser: FocusBrowser) throws {
        let event = event(AEEventID(kAESetData), browser: browser)
        event.setParam(specifier, forKeyword: keyDirectObject)
        event.setParam(value, forKeyword: AEKeyword(keyAEData))
        _ = try send(event)
    }

    private static func event(_ id: AEEventID, browser: FocusBrowser) -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(eventClass: AEEventClass(kAECoreSuite), eventID: id,
                               targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: browser.bundleIdentifier),
                               returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
    }

    private static func send(_ event: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        let reply: NSAppleEventDescriptor
        do { reply = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: replyTimeout) }
        catch { throw FocusBrowserFailure(status: (error as NSError).code) }
        if let number = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber))?.int32Value, number != 0 {
            throw FocusBrowserFailure(status: Int(number))
        }
        return reply
    }

    private static func property(_ code: String, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        specifier(class: "prop", form: DescType(formPropertyID), data: NSAppleEventDescriptor(typeCode: Self.code(code)), of: container)
    }

    private static func element(_ elementClass: String, position: Int, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        specifier(class: elementClass, form: DescType(formAbsolutePosition), data: NSAppleEventDescriptor(int32: Int32(position)), of: container)
    }

    private static func element(_ elementClass: String, uniqueID: NSAppleEventDescriptor, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        specifier(class: elementClass, form: DescType(formUniqueID), data: uniqueID, of: container)
    }

    private static func specifier(class desiredClass: String, form: DescType, data: NSAppleEventDescriptor, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let specifier = NSAppleEventDescriptor.record().coerce(toDescriptorType: DescType(typeObjectSpecifier))!
        specifier.setDescriptor(NSAppleEventDescriptor(typeCode: code(desiredClass)), forKeyword: AEKeyword(keyAEDesiredClass))
        specifier.setDescriptor(NSAppleEventDescriptor(enumCode: form), forKeyword: AEKeyword(keyAEKeyForm))
        specifier.setDescriptor(data, forKeyword: AEKeyword(keyAEKeyData))
        specifier.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
        return specifier
    }

    private static func code(_ text: String) -> FourCharCode {
        text.utf8.reduce(FourCharCode(0)) { $0 << 8 | FourCharCode($1) }
    }
}
