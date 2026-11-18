import CloudKit
import SwiftUI
import UIKit
import UserNotifications
import VolantCore

/// Break Alerts: when Volant on the Mac starts a break or one is over, this iPhone shows a
/// notification, and a paired Apple Watch shows it too. The Mac writes one CloudKit record per kind
/// to the owner's private database; two query subscriptions here ask CloudKit to push a visible
/// notification for each write, so nothing in this app needs to run. Off by default, per device.
@MainActor
final class BreakAlerts: ObservableObject {
    enum State: Equatable {
        case off, working, on
        case failed(String)
    }

    @Published private(set) var state: State
    @AppStorage("breakAlerts") private var enabled = false

    init() {
        state = UserDefaults.standard.bool(forKey: "breakAlerts") ? .on : .off
    }

    private var database: CKDatabase { CKContainer(identifier: BreakAlert.containerIdentifier).privateCloudDatabase }

    /// Asks for notification permission, registers for pushes and saves both subscriptions.
    func turnOn() async {
        state = .working
        do {
            let center = UNUserNotificationCenter.current()
            guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                return fail(String(localized: "Allow notifications for Volant in Settings › Notifications, then try again."))
            }
            UIApplication.shared.registerForRemoteNotifications()
            let (saved, _) = try await database.modifySubscriptions(saving: [BreakAlert.started, .over].map(Self.subscription), deleting: [])
            for result in saved.values { _ = try result.get() }
            enabled = true
            state = .on
        } catch {
            fail(Self.describe(error))
        }
    }

    /// Removes both subscriptions, so CloudKit stops pushing break alerts to this device's account.
    func turnOff() async {
        state = .working
        do {
            let (_, deleted) = try await database.modifySubscriptions(saving: [], deleting: [BreakAlert.started.subscriptionID, BreakAlert.over.subscriptionID])
            for result in deleted.values {
                if case .failure(let error) = result, (error as? CKError)?.code != .unknownItem { throw error }
            }
            enabled = false
            state = .off
        } catch let error as CKError where error.code == .unknownItem {
            enabled = false
            state = .off
        } catch {
            fail(Self.describe(error))
        }
    }

    /// Registers for pushes again at launch while on, so a new device token reaches CloudKit.
    func refreshRegistration() {
        guard enabled else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    private func fail(_ reason: String) {
        state = .failed(reason)
    }

    /// A subscription that fires on every write of the alert's record and shows its text.
    private static func subscription(_ alert: BreakAlert) -> CKQuerySubscription {
        let subscription = CKQuerySubscription(recordType: alert.recordType, predicate: NSPredicate(value: true),
                                               subscriptionID: alert.subscriptionID, options: [.firesOnRecordCreation, .firesOnRecordUpdate])
        let info = CKSubscription.NotificationInfo()
        info.title = alert.notificationTitle
        info.alertBody = alert.notificationBody
        info.soundName = "default"
        info.shouldBadge = false
        subscription.notificationInfo = info
        return subscription
    }

    /// A short reason for Settings. When iCloud asks Volant to wait, it says for how long.
    static func describe(_ error: Error) -> String {
        let ckError = error as? CKError
        if let seconds = ckError?.retryAfterSeconds, seconds > 60 {
            let minutes = Int((seconds / 60).rounded(.up))
            return String(localized: "iCloud asked Volant to wait. Try again in about \(minutes) minutes.")
        }
        switch ckError?.code {
        case .notAuthenticated: return String(localized: "Sign in to iCloud on this iPhone to get break alerts.")
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return String(localized: "iCloud couldn’t be reached. Try again in a moment.")
        default: return String(localized: "Break alerts couldn’t be turned on. Try again in a moment.")
        }
    }
}

/// Shows break alerts as banners while Volant is open; otherwise iOS shows them as usual.
final class BreakAlertsAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

/// The Settings section: one switch, what it does, and why it failed when it did.
struct BreakAlertsSection: View {
    @ObservedObject var alerts: BreakAlerts

    var body: some View {
        Section {
            HStack {
                Toggle(isOn: Binding(get: { alerts.state == .on },
                                     set: { on in Task { on ? await alerts.turnOn() : await alerts.turnOff() } })) {
                    Label("Break Alerts", systemImage: "cup.and.heat.waves")
                }
                if alerts.state == .working { ProgressView() }
            }
            .disabled(alerts.state == .working)
        } header: {
            Text("Mac Breaks")
        } footer: {
            if case .failed(let reason) = alerts.state {
                Text(reason).foregroundStyle(.red)
            } else {
                Text("When Volant on your Mac starts a break and when it’s over, this iPhone and your Apple Watch alert you. Turn on Alert my iPhone and Apple Watch in Volant’s Breaks settings on the Mac too. Only those two moments go through your iCloud.")
            }
        }
    }
}
