import XCTest
@testable import VolantCore

final class UnitArithmeticTests: XCTestCase {
    private static let english = Locale(identifier: "en_US")

    private func card(_ query: String, locale: Locale = english) -> [String?] {
        guard let a = UnitArithmetic.evaluate(query, locale: locale) else { return [] }
        return [a.result, a.resultDetail]
    }

    private func converted(_ query: String) -> String? {
        UnitConverter.convert(query, locale: Self.english).map { UnitConverter.formatResult($0, locale: Self.english) }
    }

    func testSumsAnswerInTheFirstUnitOrTheTarget() {
        XCTAssertEqual(card("5 km + 300 m"), ["5.3 km", "Kilometers"])
        XCTAssertEqual(card("5km+300m"), ["5.3 km", "Kilometers"])
        XCTAssertEqual(card("5 km + 300 m in mi").first, "3.293267 mi")
        XCTAssertEqual(card("2 lb - 3 oz"), ["1.8125 lb", "Pounds"])
        XCTAssertEqual(card("1 gal + 2 qt + 1 pt in l").first, "6.151294 L")
        XCTAssertEqual(card("1 kg - 1500 g").first, "-0.5 kg")
    }

    func testMixedQuantitiesNeedATarget() {
        XCTAssertEqual(card("5 ft 10 in in cm"), ["177.8 cm", "Centimeters"])
        XCTAssertEqual(card("5'10\" in cm").first, "177.8 cm")
        XCTAssertEqual(card("5’10” in cm").first, "177.8 cm")
        XCTAssertEqual(card("6 ft 2.5 in to m").first, "1.8923 m")
        XCTAssertEqual(card("1 lb 4 oz in g").first, "566.990463 g")
        XCTAssertEqual(card("5 ft 10 in"), [])
    }

    func testScalingAndRatios() {
        XCTAssertEqual(card("5 km * 3").first, "15 km")
        XCTAssertEqual(card("5 km x 3 in mi").first, "9.320568 mi")
        XCTAssertEqual(card("10 mi / 4").first, "2.5 mi")
        XCTAssertEqual(card("10 km / 2 km"), ["5", nil])
        XCTAssertEqual(card("1 mi / 1 km").first, "1.609344")
        XCTAssertEqual(card("10 km / 0"), [])
    }

    func testSpeedsAndRatesFromAQuantityOverATime() {
        XCTAssertEqual(card("1 mile / 8 min in kph"), ["12.07008 km/h", "Kilometers per hour"])
        XCTAssertEqual(card("1 mile / 8 min").first, "7.5 mph")
        XCTAssertEqual(card("10 km / 50 min").first, "12 km/h")
        XCTAssertEqual(card("42.195 km / 3 h 30 min in min/km").first, "4.976893 min/km")
        XCTAssertEqual(card("1 GB / 10 s in Mbps").first, "800 Mbps")
        XCTAssertEqual(card("1 GB / 10 s").first, "800 Mbps")
        XCTAssertEqual(card("10 km / 50 min in kg"), [])
        XCTAssertEqual(card("10 kg / 5 min"), [])
    }

    func testNoAnswerForWhatOtherCalculatorsOwnOrCannotAdd() {
        XCTAssertEqual(card("5 km in mi"), [])
        XCTAssertEqual(card("2h 20min + 55min"), [])
        XCTAssertEqual(card("90 min * 3"), [])
        XCTAssertEqual(card("10 c + 5 c"), [])
        XCTAssertEqual(card("30 mpg + 5 mpg"), [])
        XCTAssertEqual(card("5 km + 3 kg"), [])
        XCTAssertEqual(card("5 km + "), [])
        XCTAssertEqual(card("2 + 2"), [])
        XCTAssertEqual(card("5 km apples"), [])
    }

    func testDurationUnitsUseAnAverageGregorianYear() {
        XCTAssertEqual(converted("3 weeks in days"), "21 d")
        XCTAssertEqual(converted("1 year in seconds"), "31556952 s")
        XCTAssertEqual(converted("1 year in days"), "365.2425 d")
        XCTAssertEqual(converted("36 hours in days"), "1.5 d")
        let answer = CalculationAnswer.answers(for: "1 year in seconds", locale: Self.english).first
        XCTAssertEqual(answer?.inputDetail, "Years of 365.2425 days")
        XCTAssertEqual(answer?.resultDetail, "Seconds")
    }

    func testDataRatesReadBitsAndBytesByCase() {
        XCTAssertEqual(converted("100 Mbps in MB/s"), "12.5 MB/s")
        XCTAssertEqual(converted("100 Mb/s in MB/s"), "12.5 MB/s")
        XCTAssertEqual(converted("100 mbps in mb/s"), "12.5 MB/s")
        XCTAssertEqual(converted("1 Gbps in Mbps"), "1000 Mbps")
        XCTAssertEqual(converted("1 GB/s in Gbps"), "8 Gbps")
        XCTAssertEqual(converted("1 MiB/s in kbps"), "8388.608 kbps")
        XCTAssertEqual(converted("100 Mbit/s in MByte/s"), "12.5 MB/s")
        XCTAssertEqual(converted("12.5 MB/s in Mbps"), "100 Mbps")
        XCTAssertEqual(converted("10 mb in gb"), "0.01 GB")
        XCTAssertEqual(converted("10 lbs in kg"), "4.535924 kg")
    }

    func testFuelEconomyIsReciprocal() {
        XCTAssertEqual(converted("30 mpg in l/100km"), "7.840486 L/100 km")
        XCTAssertEqual(converted("8 l/100km in mpg"), "29.401823 mpg")
        XCTAssertEqual(converted("30 mpg in mpg imp"), "36.028498 mpg (imp)")
        XCTAssertEqual(converted("15 km/l in l/100 km"), "6.666667 L/100 km")
        XCTAssertNil(converted("0 mpg in l/100km"))
        XCTAssertEqual(converted("7.840486 L/100 km in mpg"), "30 mpg")
    }

    func testPaceIsReciprocalToSpeed() {
        XCTAssertEqual(converted("8 min/mile in kph"), "12.07008 km/h")
        XCTAssertEqual(converted("6 mph in min/mi"), "10 min/mi")
        XCTAssertEqual(converted("5 min/km in mph"), "7.456454 mph")
        XCTAssertEqual(converted("12 km/h in min/km"), "5 min/km")
    }

    func testPrimesReadAsFeetAndInches() {
        XCTAssertEqual(converted("6' in cm"), "182.88 cm")
        XCTAssertEqual(converted("10\" in cm"), "25.4 cm")
        XCTAssertEqual(converted("5 in in cm"), "12.7 cm")
    }

    func testDecimalCommaLocales() {
        XCTAssertEqual(card("2,5 km + 500 m", locale: Locale(identifier: "de_DE")).first, "3 km")
    }
}
