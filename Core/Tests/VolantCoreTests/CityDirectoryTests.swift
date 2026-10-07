import XCTest
@testable import VolantCore

final class CityDirectoryTests: XCTestCase {
    private let fixture = """
    America/Los_Angeles\tAmerica/New_York\tAmerica/Chicago\tEurope/Madrid\tAmerica/Caracas\tAmerica/Detroit\tEurope/Warsaw\tAmerica/Toronto\tEurope/London
    Portland\t\tUS\tOR\t652503\t0
    Portland\t\tUS\tME\t66881\t1
    Springfield\t\tUS\tMO\t170188\t2
    Springfield\t\tUS\tMA\t154341\t1
    Barcelona\t\tES\t56\t1686208\t3
    Barcelona\t\tVE\t02\t815141\t4
    Columbus\t\tUS\tOH\t905748\t1
    Columbus\t\tUS\tMI\t800000\t5
    Kraków\tKrakow\tPL\t77\t755050\t6
    London\t\tGB\tENG\t8961989\t8
    London\t\tCA\t08\t422324\t7
    St. Louis\t\tUS\tMO\t315685\t2
    """

    private func directory() -> CityDirectory { CityDirectory(load: { self.fixture }) }

    func testDominantCityWinsAndSameClockRivalsDoNotMatter() {
        let cities = directory()
        XCTAssertEqual(cities.lookup("Portland")?.zone.identifier, "America/Los_Angeles")
        XCTAssertEqual(cities.lookup("barcelona")?.zone.identifier, "Europe/Madrid")
        XCTAssertEqual(cities.lookup("Barcelona")?.name, "Barcelona")
        XCTAssertEqual(cities.lookup("columbus")?.zone.identifier, "America/New_York")
        XCTAssertEqual(cities.lookup("london")?.zone.identifier, "Europe/London")
    }

    func testCloseRivalsOnDifferentClocksNeedAQualifier() {
        let cities = directory()
        XCTAssertNil(cities.lookup("Springfield"))
        XCTAssertEqual(cities.lookup("Springfield, MA")?.zone.identifier, "America/New_York")
        XCTAssertEqual(cities.lookup("springfield mo")?.zone.identifier, "America/Chicago")
        XCTAssertEqual(cities.lookup("Portland, ME")?.zone.identifier, "America/New_York")
        XCTAssertEqual(cities.lookup("barcelona, venezuela")?.zone.identifier, "America/Caracas")
        XCTAssertEqual(cities.lookup("london, ca")?.zone.identifier, "America/Toronto")
        XCTAssertEqual(cities.lookup("London, UK")?.zone.identifier, "Europe/London")
        XCTAssertNil(cities.lookup("Springfield, TX"))
        XCTAssertNil(cities.lookup("Springfield, Atlantis"))
    }

    func testQualifiedMatchesNameTheirQualifier() {
        let cities = directory()
        XCTAssertEqual(cities.lookup("springfield, ma")?.name, "Springfield, MA")
        XCTAssertEqual(cities.lookup("barcelona, venezuela")?.name, "Barcelona, Venezuela")
        XCTAssertEqual(cities.lookup("London, UK")?.name, "London, UK")
        XCTAssertEqual(cities.lookup("Portland")?.name, "Portland")
    }

    func testAlternativesOfferEachResolvableCityLargestFirst() {
        let cities = directory()
        XCTAssertEqual(cities.alternatives("Springfield"), ["Springfield, MO", "Springfield, MA"])
        XCTAssertEqual(cities.alternatives("springfield", limit: 1), ["Springfield, MO"])
        XCTAssertEqual(cities.alternatives("Portland"), [])
        XCTAssertEqual(cities.alternatives("Atlantis"), [])
        for alternative in cities.alternatives("Springfield") { XCTAssertNotNil(cities.lookup(alternative), alternative) }
    }

    func testAmbiguousTimeQueriesSuggestEachCity() {
        let saved = CityDirectory.shared
        CityDirectory.shared = directory()
        defer { CityDirectory.shared = saved }
        let now = ISO8601DateFormatter().date(from: "2026-10-02T09:00:00Z")!
        let paris = TimeZone(identifier: "Europe/Paris")!
        func suggest(_ query: String) -> [String] {
            CalculationAnswer.answers(for: query, now: now, localZone: paris, locale: Locale(identifier: "en_US")).map { "\($0.input) → \($0.result)" }
        }
        XCTAssertEqual(suggest("time in springfield"), ["time in Springfield, MO → 4:00 AM in Springfield, MO",
                                                        "time in Springfield, MA → 5:00 AM in Springfield, MA"])
        XCTAssertEqual(suggest("3pm Springfield in Barcelona").count, 2)
        XCTAssertEqual(suggest("diff springfield").first, "diff Springfield, MO → 7 hours behind")
        XCTAssertEqual(suggest("time in Portland").count, 1, "Unambiguous names answer directly")
        XCTAssertTrue(suggest("springfield").isEmpty, "Only time-shaped queries look for alternatives")
        XCTAssertTrue(suggest("time in atlantis").isEmpty)
    }

    func testAccentsCasePeriodsAndSpacingAreIgnored() {
        let cities = directory()
        XCTAssertEqual(cities.lookup("krakow")?.name, "Kraków")
        XCTAssertEqual(cities.lookup("KRAKÓW")?.name, "Kraków")
        XCTAssertEqual(cities.lookup("st louis")?.zone.identifier, "America/Chicago")
        XCTAssertEqual(cities.lookup("  St.   Louis ")?.zone.identifier, "America/Chicago")
        XCTAssertNil(cities.lookup("Atlantis"))
    }

    func testEmptyDirectoryAnswersNothingAndLoadsOnce() {
        var loads = 0
        let cities = CityDirectory(load: { loads += 1; return nil })
        XCTAssertNil(cities.lookup("Portland"))
        XCTAssertNil(cities.lookup("Seattle"))
        XCTAssertEqual(loads, 1)
    }

    func testTimeQueriesUseDirectoryCitiesAndTheirOwnNames() {
        let saved = CityDirectory.shared
        CityDirectory.shared = directory()
        defer { CityDirectory.shared = saved }
        let now = ISO8601DateFormatter().date(from: "2026-10-02T09:00:00Z")!
        let paris = TimeZone(identifier: "Europe/Paris")!
        func answer(_ query: String) -> String? {
            TimeCalculator.evaluate(query, now: now, localZone: paris, locale: Locale(identifier: "en_US"))?.text
        }
        XCTAssertEqual(answer("9am Portland in Barcelona"), "6:00 PM in Barcelona")
        XCTAssertEqual(answer("9am Portland, ME in Barcelona"), "3:00 PM in Barcelona")
        XCTAssertEqual(answer("time in Springfield, MA"), answer("time in New York")?.replacingOccurrences(of: "New York", with: "Springfield, MA"))
        XCTAssertNil(answer("9am Springfield in Barcelona"))
    }

    func testAccentedCitiesResolveThroughTheDirectoryWithTheirOwnSpelling() {
        let saved = CityDirectory.shared
        defer { CityDirectory.shared = saved }
        let now = ISO8601DateFormatter().date(from: "2026-10-02T09:00:00Z")!
        let paris = TimeZone(identifier: "Europe/Paris")!
        func answer(_ query: String) -> String? {
            TimeCalculator.evaluate(query, now: now, localZone: paris, locale: Locale(identifier: "en_US"))?.text
        }
        CityDirectory.shared = CityDirectory(load: { nil })
        XCTAssertEqual(answer("time in sao paulo"), "6:00 AM in Sao Paulo")
        XCTAssertNil(answer("time in são paulo"))
        CityDirectory.shared = CityDirectory(load: { "America/Sao_Paulo\nSão Paulo\tSao Paulo\tBR\t27\t10021295\t0\n" })
        XCTAssertEqual(answer("time in São Paulo"), "6:00 AM in São Paulo")
        XCTAssertEqual(answer("time in SÃO PAULO"), "6:00 AM in São Paulo")
    }

    /// The generated table from tools/cities/build.py, read as the app reads it.
    func testBundledTableResolvesWellKnownCities() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Volant/Resources/cities.tsv.deflate")
        let data = try (Data(contentsOf: url) as NSData).decompressed(using: .zlib) as Data
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        let cities = CityDirectory(load: { text })
        let start = Date()
        XCTAssertEqual(cities.lookup("Seattle")?.zone.identifier, "America/Los_Angeles")
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0, "First lookup loads the whole table")
        XCTAssertEqual(cities.lookup("Barcelona")?.zone.identifier, "Europe/Madrid")
        XCTAssertEqual(cities.lookup("Portland")?.zone.identifier, "America/Los_Angeles")
        XCTAssertEqual(cities.lookup("Portland, ME")?.zone.identifier, "America/New_York")
        XCTAssertNil(cities.lookup("Springfield"))
        XCTAssertEqual(cities.lookup("Munich")?.zone.identifier, "Europe/Berlin")
        XCTAssertEqual(cities.lookup("sao paulo")?.zone.identifier, "America/Sao_Paulo")
        XCTAssertEqual(cities.lookup("Austin")?.zone.identifier, "America/Chicago")
        XCTAssertEqual(cities.lookup("Bangalore")?.zone.identifier ?? cities.lookup("Bengaluru")?.zone.identifier, "Asia/Kolkata")
    }

    /// The tables cost several megabytes once loaded, so arithmetic, units, colors, dates, clock
    /// spans and plain searches must never load them; only a time question naming a place the
    /// built-in names don't cover may.
    func testOnlyPlaceQuestionsLoadTheTables() {
        let savedCities = CityDirectory.shared, savedAirports = AirportDirectory.shared
        defer { CityDirectory.shared = savedCities; AirportDirectory.shared = savedAirports }
        var loads: [String] = []
        var current = ""
        let installFresh = {
            CityDirectory.shared = CityDirectory(load: { loads.append("city: \(current)"); return self.fixture })
            AirportDirectory.shared = AirportDirectory(load: { loads.append("airport: \(current)"); return nil })
        }
        installFresh()
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        let locale = Locale(identifier: "en_US")
        for query in ["2 + 2", "safari", "visual studio code", "10:30 + 2:45", "5 km", "5 km in mi", "12 apples", "18% tip on $65",
                      "2h 20min + 55min", "#3a7bd5", "rebeccapurple in hex", "workdays until christmas", "1 cup flour in grams",
                      "9am to 5:30pm", "3pm - 9am", "45 min * 4", "7:30pm tomorrow", "days until next friday", "0x1F + 0b1010",
                      "time in tokyo", "noon in Denver", "1pm EST in CET", "3pm lisbon in tokyo", "time", "time in 90 minutes",
                      "3:45pm + 5", "what's 7 * 6?", "3 * (4 + 5"] {
            current = query
            _ = CalculationAnswer.answers(for: query, now: now, localZone: zone, locale: locale)
        }
        XCTAssertEqual(loads, [])
        for query in ["3pm springfield in tokyo", "time diff Kraków"] {
            installFresh()
            loads = []
            current = query
            _ = CalculationAnswer.answers(for: query, now: now, localZone: zone, locale: locale)
            XCTAssertEqual(loads.first, "city: \(query)", query)
        }
    }
}
