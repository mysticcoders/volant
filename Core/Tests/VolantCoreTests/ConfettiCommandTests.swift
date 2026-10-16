import XCTest

@testable import VolantCore

/// Confetti is a command like any other, so the routing rules apply to it too.
final class ConfettiCommandTests: XCTestCase {
    func testConfettiIsDiscoverableAndReserved() {
        XCTAssertEqual(CoreCommand.confetti.query, "confetti")
        XCTAssertTrue(LauncherRouting.isReserved("confetti"))
        XCTAssertFalse(LauncherRouting.isReserved("confettis"), "only the whole first word is reserved")
    }
}
