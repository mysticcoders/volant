import AppKit
import Sparkle

/// Sparkle owns consent, scheduling, signature verification, and installation. Volant runs in the
/// background, so a scheduled check that finds an update while another app is in front uses Sparkle's
/// gentle reminders: instead of an alert behind other windows, the launcher's first row offers the
/// update, and Return brings Sparkle's own update window forward. Sparkle still shows the update itself
/// when it would have focus anyway, such as right after launch, and every user-initiated check.
final class AppUpdater: NSObject, SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController?
    /// Called on the main queue when `availableVersion` changes.
    var onChange: () -> Void = {}
    /// The version a scheduled check found and left to the launcher, until the owner gives Sparkle's
    /// update window attention or the update session ends.
    private(set) var availableVersion: String?

    func start() {
        guard controller == nil,
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32,
              let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              URL(string: feed)?.scheme == "https" else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
    }

    func checkForUpdates() {
        guard let controller else {
            let alert = NSAlert()
            alert.messageText = String(localized: "Updates aren’t configured in this build", comment: "Alert title")
            alert.informativeText = String(localized: "Use a release build with a signed update feed.", comment: "Alert message when updates aren't configured")
            alert.runModal()
            return
        }
        controller.checkForUpdates(nil)
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Sparkle shows the update itself only when it would be in immediate focus; otherwise the launcher does.
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard !handleShowingUpdate else { return }
        setAvailable(update.displayVersionString)
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) { setAvailable(nil) }

    func standardUserDriverWillFinishUpdateSession() { setAvailable(nil) }

    /// Records the waiting version, for the launcher row and tests that stand in for Sparkle.
    func setAvailable(_ version: String?) {
        guard availableVersion != version else { return }
        availableVersion = version
        onChange()
    }
}
