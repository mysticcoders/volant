import XCTest
@testable import Volant

final class AppIndexEligibilityTests: XCTestCase {
    func testApplicationFoldersAndOneSubfolderAreIndexed() {
        XCTAssertTrue(AppIndex.isUserFacingApp("/Applications/Safari.app"))
        XCTAssertTrue(AppIndex.isUserFacingApp("/Applications/Setapp/Fixture.app"))
        XCTAssertTrue(AppIndex.isUserFacingApp("/System/Applications/Utilities/Screen Sharing.app"))
        XCTAssertTrue(AppIndex.isUserFacingApp(UserHome.path + "/Applications/Fixture.app"))
        XCTAssertFalse(AppIndex.isUserFacingApp("/Applications/Vendor/Suite/Fixture.app"))
        XCTAssertFalse(AppIndex.isUserFacingApp("/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app"))
        XCTAssertFalse(AppIndex.isUserFacingApp(UserHome.path + "/Downloads/Fixture.app"))
    }

    /// #392: apps in the owner's ~/Applications, such as JetBrains Toolbox's IntelliJ IDEA, were never found
    /// because the index used the sandbox container as home. The account's home comes from the user
    /// database here, independently of `UserHome`, so the test cannot pass by agreeing with itself.
    func testOwnersHomeApplicationsFolderIsIndexedNotTheSandboxContainer() throws {
        let accountHome = try XCTUnwrap(getpwuid(getuid())?.pointee.pw_dir.map { String(cString: $0) })
        XCTAssertEqual(UserHome.path, accountHome)
        XCTAssertTrue(AppIndex.applicationRoots.contains(accountHome + "/Applications/"))
        XCTAssertTrue(AppIndex.isUserFacingApp(accountHome + "/Applications/IntelliJ IDEA.app"))
        XCTAssertTrue(AppIndex.isUserFacingApp(accountHome + "/Applications/JetBrains Toolbox/IntelliJ IDEA Ultimate.app"))
        XCTAssertTrue(AppIndex.isUserFacingApp(accountHome + "/Applications/Chrome Apps.localized/Fixture.app"))
        if NSHomeDirectory() != accountHome {
            XCTAssertFalse(AppIndex.applicationRoots.contains(NSHomeDirectory() + "/Applications/"), "the sandbox container is not an application folder")
        }
    }

    func testHomeThatIsALinkAlsoIndexesItsTarget() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("volant-home-\(UUID().uuidString)")
        let target = base.appendingPathComponent("Volumes-Data-home")
        let link = base.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        defer { try? FileManager.default.removeItem(at: base) }
        let roots = AppIndex.roots(home: link.path)
        XCTAssertTrue(roots.contains(link.path + "/Applications/"))
        XCTAssertTrue(roots.contains(target.path + "/Applications/"))
    }

    func testPathAliasResolvesNestedCopyWithoutWideningSearch() {
        let nested = "/Applications/Vendor/Suite/Fixture.app"
        let present: Set<String> = [nested, "/Applications/Vendor/Suite/Fixture.app/Contents/Helper.app", UserHome.path + "/Downloads/Fixture.app"]
        let index = AppIndex(entries: [], startQuery: { _ in false }, bundleExists: { present.contains($0) })
        XCTAssertEqual(index.resolveAlias(nested)?.url.path, nested)
        XCTAssertEqual(index.resolveAlias(nested)?.name, "Fixture")
        XCTAssertNil(index.resolveAlias("/Applications/Vendor/Suite/Moved.app"), "a missing bundle never resolves")
        XCTAssertNil(index.resolveAlias("/Applications/Vendor/Suite/Fixture.app/Contents/Helper.app"))
        XCTAssertNil(index.resolveAlias(UserHome.path + "/Downloads/Fixture.app"), "only application folders resolve")
        XCTAssertFalse(AppIndex.isUserFacingApp(nested), "fuzzy search keeps its depth limit")
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
