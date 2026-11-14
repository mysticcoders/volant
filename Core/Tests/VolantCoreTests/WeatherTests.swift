import XCTest
@testable import VolantCore

final class WeatherTests: XCTestCase {
    func testQueriesNameHereOrAPlace() {
        XCTAssertEqual(WeatherQuery.parse("weather"), .here)
        XCTAssertEqual(WeatherQuery.parse("Weather  "), .here)
        XCTAssertEqual(WeatherQuery.parse("weather in"), .here)
        XCTAssertEqual(WeatherQuery.parse("weather tokyo"), .place("tokyo"))
        XCTAssertEqual(WeatherQuery.parse("weather in Tokyo"), .place("Tokyo"))
        XCTAssertEqual(WeatherQuery.parse("weather for new york"), .place("new york"))
        XCTAssertEqual(WeatherQuery.parse("weather inverness"), .place("inverness"))
    }

    func testOtherQueriesAreNotWeather() {
        XCTAssertNil(WeatherQuery.parse("weatherman"))
        XCTAssertNil(WeatherQuery.parse("the weather"))
        XCTAssertNil(WeatherQuery.parse(""))
        XCTAssertNil(WeatherQuery.parse("weather " + String(repeating: "a", count: 101)))
    }

    func testPlacesShareACacheKeyRegardlessOfCaseAndSpacing() {
        XCTAssertEqual(WeatherQuery.parse("weather Tokyo")?.key, WeatherQuery.parse("weather in  tokyo")?.key)
        XCTAssertNotEqual(WeatherQuery.here.key, WeatherQuery.place("here").key)
        XCTAssertFalse(WeatherQuery.validPlace("tokyo\u{0007}"))
    }

    func testReportsKeepAppleAttributionAndDropAnythingElse() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])
        let forecast = ExtensionItemForecast(place: "Fictionville", temperature: 12)
        let good = try JSONEncoder().encode(WeatherReport(forecast: forecast, legalURL: "https://developer.apple.com/weatherkit/data-source-attribution/",
                                                          markLight: png, markDark: Data("<svg/>".utf8)))
        let report = try XCTUnwrap(WeatherReport.decode(good))
        XCTAssertEqual(report.legalURL, "https://developer.apple.com/weatherkit/data-source-attribution/")
        XCTAssertEqual(report.markLight, png)
        XCTAssertNil(report.markDark)
        let elsewhere = try JSONEncoder().encode(WeatherReport(forecast: forecast, legalURL: "https://apple.com.example.com/legal"))
        XCTAssertNil(try XCTUnwrap(WeatherReport.decode(elsewhere)).legalURL)
        let empty = try JSONEncoder().encode(WeatherReport(forecast: ExtensionItemForecast(place: "Fictionville")))
        XCTAssertNil(WeatherReport.decode(empty))
        XCTAssertNil(WeatherReport.decode(Data(repeating: 0, count: WeatherReport.maximumBytes + 1)))
    }
}
