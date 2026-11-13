import AppKit
import Combine
import VolantCore

/// The app that was in front when the launcher appeared, which Search Menu Items reads and presses.
/// Captured from NSWorkspace like any app switcher would; the helper checks it again on every call.
struct MenuTarget: Equatable {
    let pid: Int32
    let bundleID: String
    let name: String
    /// The app's bundle path, for the rows' icon.
    let path: String?

    /// The target for the app in front, or nil when that is Volant itself or an app without a bundle
    /// identifier, which the helper could not re-validate.
    static func capture(_ app: NSRunningApplication?, ownPID: Int32 = ProcessInfo.processInfo.processIdentifier) -> MenuTarget? {
        guard let app, app.processIdentifier != ownPID, let bundleID = app.bundleIdentifier else { return nil }
        return MenuTarget(pid: app.processIdentifier, bundleID: bundleID, name: app.localizedName ?? bundleID, path: app.bundleURL?.path)
    }
}

/// A menu item row: the item, and the target app's bundle path for its icon.
struct MenuItemEntry: Hashable {
    let item: MenuItem
    let appPath: String?
}

/// Search Menu Items' data for one launcher session. Menu titles can name documents (Open Recent,
/// the Window menu), so they live only here, in memory, from the first `menus` query until the
/// launcher is dismissed, and are never logged, persisted, synced or ranked.
final class MenuItemsModel: ObservableObject {
    @Published private(set) var items: [MenuItem] = []
    @Published private(set) var loading = false
    @Published private(set) var truncated = false
    @Published private(set) var refusal: MenuRefusal?
    /// Set when the helper did not answer.
    @Published private(set) var unavailable = false
    private(set) var target: MenuTarget?
    private var loadedTarget: MenuTarget?
    private var request = UUID()
    /// The input helper; nil leaves the command without a helper, as in tests that don't inject one.
    var client: MenuItemsClient?
    /// Brings the target app to the front before a press, only while its pid still runs the captured
    /// bundle. Tests replace it.
    var activate: (MenuTarget) -> Void = { target in
        guard let app = NSRunningApplication(processIdentifier: target.pid), app.bundleIdentifier == target.bundleID else { return }
        app.activate()
    }
    /// How long after hiding the launcher and activating the app the press is sent.
    var pressDelay: TimeInterval = 0.2

    static var helperUnavailable: String { String(localized: "The input helper didn’t respond. Try again.", comment: "Search Menu Items message when the input helper could not be reached") }
    static var noTarget: String {
        String(localized: "Search Menu Items works on the app you were using. Switch to an app, then open Volant and type menus.",
               comment: "Search Menu Items notice when no other app was in front; menus is a typed command and stays in English")
    }

    /// The launcher appeared: forget the last session's items and remember the app now in front.
    func capture(_ target: MenuTarget?) {
        clear()
        self.target = target
    }

    /// Reads the target's menus once per session. A failed read is not retried until the launcher is
    /// summoned again, so a refusing helper is never asked in a loop.
    func loadIfNeeded() {
        guard let target, let client, !loading, loadedTarget != target else { return }
        loading = true
        let token = UUID()
        request = token
        client.menuItems(pid: target.pid, bundleID: target.bundleID) { [weak self] reply in
            guard let self, self.request == token else { return }
            self.loading = false
            self.loadedTarget = target
            self.unavailable = reply == nil
            self.refusal = reply?.refusal
            self.truncated = reply?.truncated ?? false
            self.items = reply?.refusal == nil ? Array((reply?.items ?? []).prefix(MenuItemPolicy.maximumItems)) : []
        }
    }

    /// Drops everything read this session and any reply still on its way.
    func clear() {
        request = UUID()
        items = []
        loading = false
        truncated = false
        refusal = nil
        unavailable = false
        loadedTarget = nil
        target = nil
    }

    /// Activates the target and asks the helper to press `item` after `pressDelay`. `completion` gets
    /// nil after a press, or what to tell the owner. The target is read now, so the launcher may be
    /// dismissed (and this model cleared) right after the call.
    func press(_ item: MenuItem, completion: @escaping (String?) -> Void) {
        guard item.enabled else { completion(MenuRefusal.disabled.message); return }
        guard let target, let client else { completion(Self.noTarget); return }
        activate(target)
        DispatchQueue.main.asyncAfter(deadline: .now() + pressDelay) {
            client.pressMenuItem(pid: target.pid, path: item.path, bundleID: target.bundleID) { reply in
                guard let reply else { completion(Self.helperUnavailable); return }
                completion(reply.pressed ? nil : (reply.refusal ?? .failed).message)
            }
        }
    }
}
