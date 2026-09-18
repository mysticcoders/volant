import XCTest
@testable import Volant

final class AppHotKeysTests: XCTestCase {
    func testInactiveTargetUsesLaunchServicesIncludingAlreadyRunningApps() {
        let url = URL(fileURLWithPath: "/Applications/Fictional.app")
        var opened: [URL] = []
        var completion: ((Bool) -> Void)?
        var failures: [String] = []
        AppHotKeys.perform(isActive: false, hide: { XCTFail("Must not hide an inactive app"); return false },
                           applicationURL: { url }, open: { target, callback in opened.append(target); completion = callback },
                           onFailure: { failures.append($0) })
        XCTAssertEqual(opened, [url])
        XCTAssertTrue(failures.isEmpty)
        completion?(false)
        XCTAssertEqual(failures.count, 1, "Asynchronous launch failure must not disappear")
    }

    func testFrontmostTargetHidesWithoutReopening() {
        var hidden = 0
        AppHotKeys.perform(isActive: true, hide: { hidden += 1; return true },
                           applicationURL: { XCTFail("No lookup needed to hide"); return nil },
                           open: { _, _ in XCTFail("Must not reopen frontmost app") }, onFailure: { XCTFail($0) })
        XCTAssertEqual(hidden, 1)
    }

    func testMissingApplicationAndRejectedHideReportFailures() {
        var failures: [String] = []
        AppHotKeys.perform(isActive: false, hide: { false }, applicationURL: { nil },
                           open: { _, _ in XCTFail("Cannot launch a missing app") }, onFailure: { failures.append($0) })
        AppHotKeys.perform(isActive: true, hide: { false }, applicationURL: { nil },
                           open: { _, _ in XCTFail("Cannot reopen after failed hide") }, onFailure: { failures.append($0) })
        XCTAssertEqual(failures.count, 2)
        XCTAssertNotEqual(failures[0], failures[1])
    }

    func testSuccessfulOpenDoesNotReportFailure() {
        AppHotKeys.perform(isActive: false, hide: { false }, applicationURL: { URL(fileURLWithPath: "/Fixture.app") },
                           open: { _, completion in completion(true) }, onFailure: { XCTFail($0) })
    }
}
