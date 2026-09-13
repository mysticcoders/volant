import XCTest
@testable import Volant

final class FileSearchTests: XCTestCase {
    func testNoiseFilter() {
        XCTAssertTrue(FileSearch.isInteresting("/Users/me/Documents/plan.md"))
        XCTAssertFalse(FileSearch.isInteresting("/Users/me/Library/Caches/x"))
        XCTAssertFalse(FileSearch.isInteresting("/Users/me/code/app/node_modules/left-pad/index.js"))
        XCTAssertFalse(FileSearch.isInteresting("/Users/me/.config/thing"))
        XCTAssertFalse(FileSearch.isInteresting("/Users/me/workspace/app/build-release/Products/App"))
        XCTAssertTrue(FileSearch.isInteresting("/Users/me/Documents/Building Plans.pdf"))
    }
}
