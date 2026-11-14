import XCTest
@testable import Volant

/// The updater's gentle reminder state without Sparkle's network: Sparkle shows the update itself when it
/// would be in immediate focus, and leaves it to the launcher otherwise.
final class AppUpdaterTests: XCTestCase {
    func testGentleRemindersAreOnAndABuildWithoutAFeedOffersNothing() {
        let updater = AppUpdater()
        XCTAssertTrue(updater.supportsGentleScheduledUpdateReminders)
        XCTAssertNil(updater.availableVersion, "A build without a feed never offers an update")
    }

    func testTheWaitingVersionNotifiesOnlyWhenItChanges() {
        let updater = AppUpdater()
        var changes = 0
        updater.onChange = { changes += 1 }
        updater.setAvailable("9.9.9")
        updater.setAvailable("9.9.9")
        XCTAssertEqual(updater.availableVersion, "9.9.9")
        XCTAssertEqual(changes, 1)
        updater.standardUserDriverWillFinishUpdateSession()
        XCTAssertNil(updater.availableVersion)
        XCTAssertEqual(changes, 2)
    }
}
