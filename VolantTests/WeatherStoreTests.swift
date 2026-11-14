import XCTest
import VolantCore
@testable import Volant

/// The weather command's store with a fake helper, location and clock: it waits for typing to pause,
/// asks once per place, keeps forecasts ten minutes and failures half a minute, and never shows a
/// reply for a query the owner moved on from.
final class WeatherStoreTests: XCTestCase {
    private var requests: [(WeatherQuery, ExtensionLocation?)] = []
    private var location: ExtensionLocation? = ExtensionLocation(latitude: 45.52, longitude: -122.68)
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private var updates = 0

    private func report(_ place: String) -> Data {
        try! JSONEncoder().encode(WeatherReport(forecast: ExtensionItemForecast(place: place, condition: "Cloudy", temperature: 12)))
    }

    private func store(reply: @escaping (WeatherQuery) -> (Data?, String?)) -> WeatherStore {
        let store = WeatherStore(fetch: { [unowned self] query, location, completion in
            requests.append((query, location))
            let (data, message) = reply(query)
            completion(data, message)
        }, locate: { [unowned self] completion in completion(location) }, now: { [unowned self] in clock })
        store.onUpdate = { [unowned self] in updates += 1 }
        return store
    }

    private func settle() {
        let done = expectation(description: "pause")
        DispatchQueue.main.asyncAfter(deadline: .now() + WeatherStore.pause + 0.2) { done.fulfill() }
        wait(for: [done], timeout: 3)
    }

    func testAPlaceIsAskedOnceAfterTypingPausesAndThenKept() {
        let store = store { _ in (self.report("Fictionville"), nil) }
        XCTAssertNil(store.answer(for: .place("fictionville")))
        XCTAssertNil(store.answer(for: .place("fictionville")))
        XCTAssertTrue(requests.isEmpty, "Nothing is asked while typing")
        settle()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(updates, 1)
        guard case .report(let report)? = store.answer(for: .place("Fictionville ")) else { return XCTFail("The forecast is kept") }
        XCTAssertEqual(report.forecast.place, "Fictionville")
        XCTAssertEqual(requests.count, 1, "A fresh forecast is not asked again")
    }

    func testOnlyTheQueryStillTypedIsAsked() {
        let store = store { _ in (self.report("Fictionville"), nil) }
        _ = store.answer(for: .place("fic"))
        _ = store.answer(for: .place("fictionville"))
        settle()
        XCTAssertEqual(requests.map(\.0), [.place("fictionville")])
    }

    func testHereSendsOnlyTheRoundedLocation() {
        let store = store { _ in (self.report("Portland, Oregon"), nil) }
        _ = store.answer(for: .here)
        settle()
        XCTAssertEqual(requests.first?.1, ExtensionLocation(latitude: 45.5, longitude: -122.7))
        guard case .report? = store.answer(for: .here) else { return XCTFail("Here has a forecast") }
    }

    func testRefusedLocationExplainsWithoutAsking() {
        location = nil
        let store = store { _ in (self.report("Nowhere"), nil) }
        _ = store.answer(for: .here)
        settle()
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(store.answer(for: .here), .needsLocation, "A refused location asks for Location instead")
    }

    func testHelperCodesAreWordedAndFailuresClearAfterHalfAMinute() {
        let store = store { query in (nil, HostMessage(.weatherNoPlace, "Zzqx").wire) }
        _ = store.answer(for: .place("zzqx"))
        settle()
        XCTAssertEqual(store.answer(for: .place("zzqx")), .message(HostMessage(.weatherNoPlace, "Zzqx").text))
        clock.addTimeInterval(WeatherStore.messageLifetime + 1)
        XCTAssertNil(store.answer(for: .place("zzqx")), "An old failure is asked again")
    }

    func testForecastsExpireAfterTenMinutes() {
        let store = store { _ in (self.report("Fictionville"), nil) }
        _ = store.answer(for: .place("fictionville"))
        settle()
        clock.addTimeInterval(WeatherStore.lifetime + 1)
        XCTAssertNil(store.answer(for: .place("fictionville")))
        settle()
        XCTAssertEqual(requests.count, 2)
    }

    func testCancelledQueriesAreNeverAsked() {
        let store = store { _ in (self.report("Fictionville"), nil) }
        _ = store.answer(for: .place("fictionville"))
        store.cancel()
        settle()
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(updates, 0)
    }
}
