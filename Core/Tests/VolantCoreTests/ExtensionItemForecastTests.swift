import XCTest
@testable import VolantCore

final class ExtensionItemForecastTests: XCTestCase {
    private static let english = Locale(identifier: "en_US")

    /// A fictional forecast as a list extension returns it, decoded through the same path as real replies.
    private func forecast(_ json: String) throws -> ExtensionItemForecast? {
        try ExtensionNetwork.reply(from: #"{"items":[{"title":"Fictionville","forecast":"# + json + "}]}").items?.first?.forecast
    }

    func testAForecastSurvivesWithItsHoursAndDays() throws {
        let card = try XCTUnwrap(forecast(#"""
        {"place":"Fictionville, Exampleland","condition":"Cloudy","symbol":"cloud","temperature":13.2,"high":19,"low":9,
         "hours":[{"time":"2026-11-14T09:00","temperature":13,"symbol":"cloud"},{"time":"2026-11-14T10:00","temperature":15,"symbol":"cloud-sun"}],
         "days":[{"date":"2026-11-14","high":19,"low":9,"symbol":"sun"},{"date":"2026-11-15","high":17,"low":8,"symbol":"rain"}]}
        """#))
        XCTAssertEqual(card.place, "Fictionville, Exampleland")
        XCTAssertEqual(card.condition, "Cloudy")
        XCTAssertEqual(card.symbol, "cloud")
        XCTAssertEqual(card.temperature, 13.2)
        XCTAssertEqual(card.hours?.map(\.time), ["2026-11-14T09:00", "2026-11-14T10:00"])
        XCTAssertEqual(card.days?.map(\.symbol), ["sun", "rain"])
    }

    func testUnknownSymbolsImplausibleTemperaturesAndBadTimesAreDropped() throws {
        let card = try XCTUnwrap(forecast(#"""
        {"place":"  Fictionville\nEast  ","symbol":"../../icon.png","temperature":500,"high":19,"low":-300,
         "hours":[{"time":"tomorrow","temperature":10},{"time":"2026-11-14T10:00","temperature":15,"symbol":"tornado"},
                  {"time":"2026-11-14T11:00","temperature":90}],
         "days":[{"date":"2026-11-14","high":19,"low":9},{"date":"14/11/2026","high":19,"low":9}]}
        """#))
        XCTAssertEqual(card.place, "Fictionville East")
        XCTAssertNil(card.symbol)
        XCTAssertNil(card.temperature)
        XCTAssertNil(card.low)
        XCTAssertEqual(card.high, 19)
        XCTAssertEqual(card.hours, [ExtensionItemForecast.Hour(time: "2026-11-14T10:00", temperature: 15)])
        XCTAssertEqual(card.days?.map(\.date), ["2026-11-14"])
    }

    func testAForecastWithoutAPlaceOrAnythingToShowIsDropped() throws {
        XCTAssertNil(try forecast(#"{"place":" ","temperature":10}"#))
        XCTAssertNil(try forecast(#"{"place":"Fictionville","condition":"Cloudy"}"#))
    }

    func testHoursAndDaysAreCapped() throws {
        let hours = (0..<30).map { #"{"time":"2026-11-14T\#(String(format: "%02d", $0 % 24)):00","temperature":10}"# }.joined(separator: ",")
        let days = (1...14).map { #"{"date":"2026-11-\#(String(format: "%02d", $0))","high":10,"low":5}"# }.joined(separator: ",")
        let card = try XCTUnwrap(forecast(#"{"place":"Fictionville","hours":[\#(hours)],"days":[\#(days)]}"#))
        XCTAssertEqual(card.hours?.count, ExtensionItemForecast.maximumHours)
        XCTAssertEqual(card.days?.count, ExtensionItemForecast.maximumDays)
    }

    func testDegreesFollowTheOwnersUnits() {
        XCTAssertEqual(ExtensionItemForecast.degrees(13.4, units: "metric"), "13°")
        XCTAssertEqual(ExtensionItemForecast.degrees(13.4, units: "us"), "56°")
        XCTAssertEqual(ExtensionItemForecast.degrees(-0.4, units: "metric"), "0°")
        XCTAssertEqual(ExtensionItemForecast.degrees(-17.8, units: "us"), "0°")
    }

    func testLabelsUseThePlacesWallClockInTheOwnersStyle() {
        let hour = ExtensionItemForecast.Hour(time: "2026-11-14T15:00", temperature: 10)
        XCTAssertEqual(ExtensionItemForecast.hourLabel(hour, index: 0, locale: Self.english), String(localized: "Now", table: "Core"))
        XCTAssertEqual(ExtensionItemForecast.hourLabel(hour, index: 3, locale: Self.english).replacingOccurrences(of: "\u{202F}", with: " "), "3 PM")
        XCTAssertEqual(ExtensionItemForecast.hourLabel(hour, index: 3, locale: Locale(identifier: "de_DE")), "15 Uhr")
        let day = ExtensionItemForecast.Day(date: "2026-11-16", high: 10, low: 5)
        XCTAssertEqual(ExtensionItemForecast.dayLabel(day, index: 0, locale: Self.english), String(localized: "Today", table: "Core"))
        XCTAssertEqual(ExtensionItemForecast.dayLabel(day, index: 2, locale: Self.english), "Mon")
    }

    func testRowsWithoutAForecastAreUnchanged() throws {
        let items = try ExtensionNetwork.items(from: #"{"items":[{"title":"Tomorrow · Rain","symbol":"rain"}]}"#)
        XCTAssertNil(items.first?.forecast)
        XCTAssertEqual(items.first?.symbol, "rain")
    }
}
