import Foundation
import VolantCore

/// The slice of NSUbiquitousKeyValueStore the sync uses, so tests can substitute an in-memory store.
protocol SettingsKeyValueStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: SettingsKeyValueStore {}

/// Mirrors the SettingsSync keys of config.json through iCloud key-value storage while the per-Mac
/// switch is on. Runs after every configuration reload and whenever iCloud delivers a change; a
/// received change is written with the same stale-file check as other config patches and then
/// handed back to the app to reload.
final class ICloudSettingsSync {
    enum Status: Equatable {
        case off
        case unavailable
        case synced(Date)
        case attention(String)

        var text: String {
            switch self {
            case .off: return "Off"
            case .unavailable: return "iCloud is unavailable. Check that this Mac is signed in to iCloud."
            case .synced(let date): return "Up to date as of " + date.formatted(date: .omitted, time: .shortened)
            case .attention(let message): return message
            }
        }
    }

    private static let prefix = "settings."
    private let makeStore: () -> SettingsKeyValueStore
    private let configURL: URL
    private let stateURL: URL
    private let onApplied: () -> Void
    private var store: SettingsKeyValueStore?
    private var observer: NSObjectProtocol?
    private var enabled = false
    private var syncing = false
    var onStatus: (Status) -> Void = { _ in }
    private(set) var status: Status = .off { didSet { if status != oldValue { onStatus(status) } } }

    init(store: @escaping () -> SettingsKeyValueStore = { NSUbiquitousKeyValueStore.default },
         configURL: URL = Preferences.configURL, stateURL: URL = SettingsSync.stateURL, onApplied: @escaping () -> Void) {
        self.makeStore = store
        self.configURL = configURL
        self.stateURL = stateURL
        self.onApplied = onApplied
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    /// Follows the switch in config.json. Turning it off forgets the agreed baseline, so turning it
    /// on again adopts whatever iCloud holds, after keeping a copy of the local file.
    func update(enabled: Bool) {
        self.enabled = enabled
        guard enabled else {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            try? FileManager.default.removeItem(at: stateURL)
            status = .off
            return
        }
        let store = self.store ?? makeStore()
        self.store = store
        if observer == nil, let ubiquitous = store as? NSUbiquitousKeyValueStore {
            observer = NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                                              object: ubiquitous, queue: .main) { [weak self] note in
                self?.cloudChanged(reason: note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int)
            }
        }
        sync()
    }

    /// An account change means the store now belongs to a different Apple Account, so the old
    /// baseline is dropped and the next pass treats it as a first run, copy included. A quota
    /// violation is reported rather than retried.
    func cloudChanged(reason: Int?) {
        guard enabled else { return }
        if reason == NSUbiquitousKeyValueStoreQuotaViolationChange {
            status = .attention("Synced settings exceed iCloud's 1 MB limit. Remove large snippets to resume syncing.")
            return
        }
        if reason == NSUbiquitousKeyValueStoreAccountChange { try? FileManager.default.removeItem(at: stateURL) }
        sync()
    }

    /// One reconcile pass. Nothing is written if config.json is unreadable or changes while the
    /// pass runs; the next reload or iCloud change tries again.
    func sync() {
        guard enabled, !syncing, let store else { return }
        syncing = true
        var applied = false
        defer {
            syncing = false
            if applied { onApplied() }
        }
        guard store.synchronize() else { status = .unavailable; return }
        do {
            let data = try Data(contentsOf: configURL)
            let modified = (try? configURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let state: SettingsSync.State
            if let saved = SettingsSync.loadState(at: stateURL) {
                state = saved
            } else {
                try SettingsSync.preserve(configAt: configURL)
                state = .init()
            }
            var remote: [String: SettingsSync.Entry] = [:]
            for key in SettingsSync.keys {
                remote[key] = SettingsSync.Entry(propertyList: store.object(forKey: Self.prefix + key))
            }
            let outcome = try SettingsSync.reconcile(config: data, modified: modified, remote: remote, state: state)
            if let updated = outcome.config {
                guard try Data(contentsOf: configURL) == data else { return }
                try updated.write(to: configURL, options: .atomic)
                applied = true
            }
            for (key, entry) in outcome.uploads { store.set(entry.propertyList, forKey: Self.prefix + key) }
            try SettingsSync.saveState(outcome.state, at: stateURL)
            if outcome.overBudget {
                status = .attention("Synced settings exceed iCloud's 1 MB limit. Remove large snippets to resume syncing.")
            } else if !outcome.rejected.isEmpty {
                status = .attention("Some settings from iCloud were not valid and were not applied: " + outcome.rejected.joined(separator: ", "))
            } else {
                status = .synced(Date())
            }
        } catch {
            status = .attention(error.localizedDescription)
        }
    }
}
