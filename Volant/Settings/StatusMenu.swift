import AppKit

enum StatusMenu {
    static func make(target: AnyObject, show: Selector, settings: Selector, update: Selector, bundle: Bundle = .main) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: String(localized: "Show Volant", comment: "Status bar menu item"), action: show, keyEquivalent: "")
        menu.addItem(withTitle: String(localized: "Settings…", comment: "Status bar menu item"), action: settings, keyEquivalent: ",")
        menu.addItem(.separator())
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? String(localized: "Development", comment: "Version shown in the status bar menu for a build without a version number")
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        let versionItem = menu.addItem(withTitle: String(localized: "Volant \(version) (\(build))", comment: "Status bar menu item showing the version and build number"), action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(withTitle: String(localized: "Check for Updates…", comment: "Status bar menu item"), action: update, keyEquivalent: "")
        menu.addItem(withTitle: String(localized: "Quit Volant", comment: "Status bar menu item"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { $0.target = $0.action == #selector(NSApplication.terminate(_:)) ? NSApp : target }
        return menu
    }
}
