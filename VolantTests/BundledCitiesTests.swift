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

    func testAppBundleShipsAirportsAndTheirLicense() throws {
        let bundle = Bundle(for: AppDelegate.self)
        XCTAssertEqual(AirportDirectory.bundled(bundle).lookup("JFK")?.zone.identifier, "America/New_York")
        let license = try XCTUnwrap(bundle.url(forResource: "Airports-LICENSE", withExtension: "txt"))
        XCTAssertTrue(try String(contentsOf: license, encoding: .utf8).contains("MIT License"))
    }

    func testMissingTableAnswersNothing() {
        XCTAssertNil(CityDirectory.bundled(Bundle(for: BundledCitiesTests.self)).lookup("Seattle"))
    }
}
