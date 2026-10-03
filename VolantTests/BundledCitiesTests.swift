import XCTest
import VolantCore
@testable import Volant

final class BundledCitiesTests: XCTestCase {
    func testAppBundleTableDecompressesAndResolvesCities() {
        let cities = CityDirectory.bundled(Bundle(for: AppDelegate.self))
        XCTAssertEqual(cities.lookup("Seattle")?.zone.identifier, "America/Los_Angeles")
        XCTAssertEqual(cities.lookup("Barcelona")?.name, "Barcelona")
        XCTAssertNil(cities.lookup("Springfield"))
    }

    func testMissingTableAnswersNothing() {
        XCTAssertNil(CityDirectory.bundled(Bundle(for: BundledCitiesTests.self)).lookup("Seattle"))
    }
}
