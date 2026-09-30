import XCTest

@testable import VolantCore

final class SystemActionTests: XCTestCase {
    func testSearchFindsActionsByTitleAndCommonNames() {
        XCTAssertEqual(SystemAction.search("lock"), [.lockScreen])
        XCTAssertEqual(SystemAction.search("reboot"), [.restart])
        XCTAssertEqual(SystemAction.search("power off"), [.shutDown])
        XCTAssertEqual(SystemAction.search("sign out"), [.logOut])
        XCTAssertEqual(SystemAction.search("screensaver"), [.screenSaver])
        XCTAssertEqual(Set(SystemAction.search("sleep")), [.sleep, .sleepDisplays])
    }

    func testMatchesOnlyFromTheStartSoSettingsPanesKeepTheirNames() {
        XCTAssertTrue(SystemAction.search("displays").isEmpty)
        XCTAssertTrue(SystemAction.search("screen").contains(.screenSaver))
        XCTAssertEqual(SystemAction.search("Sleep D"), [.sleepDisplays])
    }

    func testShortQueriesDoNotListPowerActions() {
        XCTAssertTrue(SystemAction.search("sl").isEmpty)
        XCTAssertTrue(SystemAction.search("  ").isEmpty)
    }

    func testOnlyConfirmingActionsUseLoginwindowDialogs() {
        XCTAssertEqual(SystemAction.restart.loginwindowEvent, "rrst")
        XCTAssertEqual(SystemAction.shutDown.loginwindowEvent, "rsdn")
        XCTAssertEqual(SystemAction.logOut.loginwindowEvent, "logo")
        XCTAssertTrue([SystemAction.lockScreen, .sleep, .sleepDisplays, .screenSaver].allSatisfy { $0.loginwindowEvent == nil })
        XCTAssertTrue(SystemAction.allCases.filter { $0.loginwindowEvent != nil }.allSatisfy { $0.title.hasSuffix("…") },
                      "actions that ask first say so with an ellipsis")
    }
}
