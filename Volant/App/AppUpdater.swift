import AppKit
import Sparkle

/// Sparkle owns consent, scheduling, signature verification, and installation.
final class AppUpdater: NSObject {
    private var controller: SPUStandardUpdaterController?

    func start() {
        guard controller == nil,
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32,
              let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              URL(string: feed)?.scheme == "https" else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    func checkForUpdates() {
        guard let controller else {
            let alert = NSAlert()
            alert.messageText = "Updates aren’t configured in this build"
            alert.informativeText = "Use a release build with a signed update feed."
            alert.runModal()
            return
        }
        controller.checkForUpdates(nil)
    }
}
