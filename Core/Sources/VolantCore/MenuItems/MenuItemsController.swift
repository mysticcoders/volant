import Foundation

/// One element of an app's menu bar as the input helper sees it: a menu bar title or a menu item.
/// It exposes only the title, the enabled state, the command character and modifiers, the items of
/// its submenu, and a press. The real one reads exactly those Accessibility attributes and the
/// structural children list; tests use plain values.
public protocol MenuNode {
    var title: String? { get }
    var enabled: Bool { get }
    var commandCharacter: String? { get }
    var commandModifiers: Int? { get }
    /// The items of this element's submenu, or none for a plain item.
    func children() -> [MenuNode]
    /// Performs the item's action. Returns whether the app accepted the press.
    func press() -> Bool
}

/// The system calls behind `MenuItemsController`. The real one lives in `VolantInputHost`.
public protocol MenuSystem {
    func isTrusted() -> Bool
    /// The bundle identifier of a running process, or nil when it has none or is gone.
    func bundleIdentifier(of pid: Int32) -> String?
    /// Whether the process is an ordinary app with a Dock presence, not an agent or a daemon.
    func isRegularApp(_ pid: Int32) -> Bool
    func frontmostPID() -> Int32?
    /// The menu bar titles of an app, left to right, the Apple menu first; nil when it has no menu bar.
    func menuBar(of pid: Int32) -> [MenuNode]?
}

/// The helper's rules for Search Menu Items, independent of Accessibility so they can be tested
/// with fakes. Both calls re-check trust and the target at the moment of use: the pid must belong
/// to an ordinary app that is in front, whose bundle identifier is still the one Volant captured,
/// and that is not excluded. The Apple menu is never listed or pressed, because its items act on
/// the whole Mac (Shut Down, Restart, Log Out, Force Quit, Lock Screen) rather than on the app.
public final class MenuItemsController {
    private let system: MenuSystem
    private let callerPID: Int32
    private let now: () -> Date
    private let budget: TimeInterval

    public init(system: MenuSystem, callerPID: Int32, now: @escaping () -> Date = Date.init,
                budget: TimeInterval = MenuItemPolicy.listingBudget) {
        self.system = system
        self.callerPID = callerPID
        self.now = now
        self.budget = budget
    }

    /// The app's choosable menu items, depth first in menu order, without the Apple menu, separators
    /// or duplicate paths, cut short at the item, depth and time limits.
    public func list(pid: Int32, bundleID: String) -> MenuItemsReply {
        if let refusal = refusal(pid: pid, bundleID: bundleID) { return MenuItemsReply(refusal: refusal) }
        guard let bar = system.menuBar(of: pid), bar.count > 1 else { return MenuItemsReply(refusal: .noMenuBar) }
        let deadline = now().addingTimeInterval(budget)
        var items: [MenuItem] = []
        var seen = Set<String>()
        var truncated = false

        func walk(_ node: MenuNode, path: [String]) {
            guard !truncated else { return }
            guard items.count < MenuItemPolicy.maximumItems, now() < deadline else { truncated = true; return }
            let children = node.children()
            if children.isEmpty {
                let item = MenuItem(path: path, shortcut: MenuShortcut.make(character: node.commandCharacter, modifiers: node.commandModifiers),
                                    enabled: node.enabled)
                if seen.insert(item.id).inserted { items.append(item) }
                return
            }
            guard path.count < MenuItemPolicy.maximumDepth else { return }
            for child in children {
                guard let title = MenuItemPolicy.title(child.title) else { continue }
                walk(child, path: path + [title])
                if truncated { return }
            }
        }

        for top in bar.dropFirst() {
            guard let title = MenuItemPolicy.title(top.title) else { continue }
            let children = top.children()
            for child in children {
                guard let childTitle = MenuItemPolicy.title(child.title) else { continue }
                walk(child, path: [title, childTitle])
                if truncated { break }
            }
            if truncated { break }
        }
        return MenuItemsReply(items: items, truncated: truncated)
    }

    /// Presses the item at `path` after re-checking the target, that the path still leads to a plain
    /// item with the same titles, and that the item is enabled.
    public func press(pid: Int32, path: [String], bundleID: String) -> MenuPressReply {
        guard MenuItemPolicy.isValid(path: path), path.count >= 2 else { return MenuPressReply(pressed: false, refusal: .invalidRequest) }
        if let refusal = refusal(pid: pid, bundleID: bundleID) { return MenuPressReply(pressed: false, refusal: refusal) }
        guard let bar = system.menuBar(of: pid), let apple = bar.first else { return MenuPressReply(pressed: false, refusal: .noMenuBar) }
        guard let top = bar.dropFirst().first(where: { MenuItemPolicy.title($0.title) == path[0] }) else {
            let refusal: MenuRefusal = MenuItemPolicy.title(apple.title) == path[0] ? .appleMenu : .notFound
            return MenuPressReply(pressed: false, refusal: refusal)
        }
        var node = top
        for title in path.dropFirst() {
            guard let next = node.children().first(where: { MenuItemPolicy.title($0.title) == title }) else {
                return MenuPressReply(pressed: false, refusal: .notFound)
            }
            node = next
        }
        guard node.children().isEmpty else { return MenuPressReply(pressed: false, refusal: .notFound) }
        guard node.enabled else { return MenuPressReply(pressed: false, refusal: .disabled) }
        return node.press() ? MenuPressReply(pressed: true) : MenuPressReply(pressed: false, refusal: .failed)
    }

    /// Why the pid cannot be read or pressed right now, or nil when it can.
    private func refusal(pid: Int32, bundleID: String) -> MenuRefusal? {
        guard pid > 0, MenuItemPolicy.isValid(bundleID: bundleID) else { return .invalidRequest }
        guard pid != callerPID, !MenuItemPolicy.isExcluded(bundleID) else { return .excludedApp }
        guard system.isTrusted() else { return .notTrusted }
        guard let actual = system.bundleIdentifier(of: pid) else { return .appChanged }
        guard !MenuItemPolicy.isExcluded(actual) else { return .excludedApp }
        guard actual == bundleID else { return .appChanged }
        guard system.isRegularApp(pid) else { return .excludedApp }
        guard system.frontmostPID() == pid else { return .appChanged }
        return nil
    }
}
