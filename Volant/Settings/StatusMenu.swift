import AppKit

enum StatusMenu {
    static func make(target: AnyObject, show: Selector, settings: Selector, update: Selector, bundle: Bundle = .main) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Volant", action: show, keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: settings, keyEquivalent: ",")
        menu.addItem(.separator())
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        let versionItem = menu.addItem(withTitle: "Volant \(version) (\(build))", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(withTitle: "Check for Updates…", action: update, keyEquivalent: "")
        menu.addItem(withTitle: "Quit Volant", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { $0.target = $0.action == #selector(NSApplication.terminate(_:)) ? NSApp : target }
        return menu
    }
}
