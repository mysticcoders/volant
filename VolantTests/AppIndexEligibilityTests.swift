import XCTest
@testable import Volant

final class AppIndexEligibilityTests: XCTestCase {
    func testApplicationFoldersAndOneSubfolderAreIndexed() {
        XCTAssertTrue(AppIndex.isUserFacingApp("/Applications/Safari.app"))
        XCTAssertTrue(AppIndex.isUserFacingApp("/Applications/Setapp/Fixture.app"))
        XCTAssertTrue(AppIndex.isUserFacingApp("/System/Applications/Utilities/Screen Sharing.app"))
        XCTAssertTrue(AppIndex.isUserFacingApp(NSHomeDirectory() + "/Applications/Fixture.app"))
        XCTAssertFalse(AppIndex.isUserFacingApp("/Applications/Vendor/Suite/Fixture.app"))
        XCTAssertFalse(AppIndex.isUserFacingApp("/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app"))
        XCTAssertFalse(AppIndex.isUserFacingApp(NSHomeDirectory() + "/Downloads/Fixture.app"))
    }

    func testFinderAndCoreServicesApplicationsAreIndexedButAgentsAreNot() {
        XCTAssertTrue(AppIndex.isUserFacingApp("/System/Library/CoreServices/Finder.app"))
        XCTAssertTrue(AppIndex.isUserFacingApp("/System/Library/CoreServices/Applications/Archive Utility.app"))
        XCTAssertTrue(AppIndex.isUserFacingApp("/System/Library/CoreServices/Applications/Keychain Access.app"))
        XCTAssertFalse(AppIndex.isUserFacingApp("/System/Library/CoreServices/Dock.app"))
        XCTAssertFalse(AppIndex.isUserFacingApp("/System/Library/CoreServices/SystemUIServer.app"))
        XCTAssertFalse(AppIndex.isUserFacingApp("/System/Library/CoreServices/Finder.app/Contents/Applications/AirDrop.app"))
    }
}
