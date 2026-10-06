import XCTest
@testable import VolantCore

final class AirportDirectoryTests: XCTestCase {
    private let fixture = "JFK\tAmerica/New_York\tNew York\nLHR\tEurope/London\tLondon\nELY\tAmerica/Los_Angeles\tEly\nBAD\tNot/AZone\tNowhere\n"
    private let now = ISO8601DateFormatter().date(from: "2026-10-02T09:00:00Z")!
    private let paris = TimeZone(identifier: "Europe/Paris")!

    private func answer(_ query: String) -> TimeCalculator.Result? {
        TimeCalculator.evaluate(query, now: now, localZone: paris, locale: Locale(identifier: "en_US"))
    }

    private func installed(_ body: () throws -> Void) rethrows {
        let saved = AirportDirectory.shared
        AirportDirectory.shared = AirportDirectory(load: { self.fixture })
        defer { AirportDirectory.shared = saved }
        try body()
    }

    func testCodesResolveCaseInsensitively() {
        let airports = AirportDirectory(load: { self.fixture })
        XCTAssertEqual(airports.lookup("JFK"), .init(zone: TimeZone(identifier: "America/New_York")!, city: "New York", code: "JFK"))
        XCTAssertEqual(airports.lookup(" lhr ")?.zone.identifier, "Europe/London")
        for code in ["JF", "JFKX", "J1K", "XXX", "BAD", ""] { XCTAssertNil(airports.lookup(code), code) }
    }

    func testTimeQueriesUseAirportsAfterCities() {
        installed {
            XCTAssertEqual(answer("time in JFK")?.headline, "5:00 AM in New York (JFK)")
            XCTAssertEqual(answer("3pm LHR in JFK")?.text, "10:00 AM in New York (JFK)")
            XCTAssertEqual(answer("diff jfk")?.text, "New York (JFK) is 6 hours behind")
            XCTAssertEqual(answer("time in ely")?.headline, "2:00 AM in Ely (ELY)")
            let savedCities = CityDirectory.shared
            CityDirectory.shared = CityDirectory(load: { "Europe/London\nEly\t\tGB\tENG\t20000\t0\n" })
            defer { CityDirectory.shared = savedCities }
            XCTAssertEqual(answer("time in ely")?.headline, "10:00 AM in Ely")
            XCTAssertEqual(answer("time in la")?.headline, "2:00 AM in Los Angeles")
        }
    }

    func testEmptyDirectoryLoadsOnce() {
        var loads = 0
        let airports = AirportDirectory(load: { loads += 1; return nil })
        XCTAssertNil(airports.lookup("JFK"))
        XCTAssertNil(airports.lookup("LAX"))
        XCTAssertEqual(loads, 1)
    }

    /// The generated table from tools/cities/airports.py, read as the app reads it.
    func testBundledTableResolvesMajorAirports() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Volant/Resources/airports.tsv.deflate")
        let data = try (Data(contentsOf: url) as NSData).decompressed(using: .zlib) as Data
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        let airports = AirportDirectory(load: { text })
        for (code, zone) in [("JFK", "America/New_York"), ("LAX", "America/Los_Angeles"), ("LHR", "Europe/London"), ("NRT", "Asia/Tokyo"),
                             ("CDG", "Europe/Paris"), ("SYD", "Australia/Sydney"), ("DXB", "Asia/Dubai"), ("PDX", "America/Los_Angeles")] {
            XCTAssertEqual(airports.lookup(code)?.zone.identifier, zone, code)
        }
    }
}
