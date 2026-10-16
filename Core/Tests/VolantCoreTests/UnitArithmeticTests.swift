import XCTest
@testable import VolantCore

final class UnitArithmeticTests: XCTestCase {
    private static let english = Locale(identifier: "en_US")

    private func card(_ query: String, locale: Locale = english) -> [String?] {
        guard let a = UnitArithmetic.evaluate(query, locale: locale) else { return [] }
        return [a.result, a.resultDetail]
    }

    func testSumsAnswerInTheFirstUnitOrTheTarget() {
        XCTAssertEqual(card("5 km + 300 m"), ["5.3 km", "Kilometers"])
        XCTAssertEqual(card("5km+300m"), ["5.3 km", "Kilometers"])
        XCTAssertEqual(card("5 km + 300 m in mi").first, "3.293267 mi")
        XCTAssertEqual(card("2 lb - 3 oz"), ["1.8125 lb", "Pounds"])
        XCTAssertEqual(card("1 gal + 2 qt + 1 pt in l").first, "6.151294 L")
        XCTAssertEqual(card("1 kg - 1500 g").first, "-0.5 kg")
    }

    func testAvoirdupoisReferenceSum() {
        XCTAssertEqual(card("3kg + 5lbs + 4oz in oz"), ["189.821886 oz", "Ounces"])
        XCTAssertEqual(card("3 kg + 5 lb + 4 oz in kg").first, "5.38136 kg")
        XCTAssertEqual(card("3kg + 5lbs + 4oz").first, "5.38136 kg")
    }

    func testMassAndFluidOuncesStayApart() {
        XCTAssertEqual(card("8 oz + 4 fl oz"), [])
        XCTAssertEqual(card("8 fl oz + 4 oz"), [])
        XCTAssertEqual(card("1 lb + 4 fl oz in oz"), [])
        XCTAssertEqual(card("(8 oz + 4 fl oz) * 2"), [])
        XCTAssertEqual(card("8 fl oz + 4 fl oz in ml").first, "354.882355 mL")
        XCTAssertEqual(card("1 cup + 2 fl oz in fl oz").first, "10 fl oz")
        XCTAssertEqual(card("1 lb + 4 oz in oz").first, "20 oz")
    }

    func testParenthesesGroupWithPrecedence() {
        XCTAssertEqual(card("(3kg + 5lbs) * 2 in oz"), ["371.643772 oz", "Ounces"])
        XCTAssertEqual(card("2 * (1 ft + 6 in) in cm"), ["91.44 cm", "Centimeters"])
        XCTAssertEqual(card("2 * (1 ft + 6 in)").first, "3 ft")
        XCTAssertEqual(card("2*(1ft+6in) in cm").first, "91.44 cm")
        XCTAssertEqual(card("1 ft + 6 in * 2 in cm").first, "60.96 cm")
        XCTAssertEqual(card("5 km + 300 m * 3").first, "5.9 km")
        XCTAssertEqual(card("(1 ft + 6 in) * 2 - 1 ft").first, "2 ft")
        XCTAssertEqual(card("10 km - (2 km + 500 m)").first, "7.5 km")
        XCTAssertEqual(card("10km-(2km+500m)").first, "7.5 km")
        XCTAssertEqual(card("((1 m + 50 cm) * 2) / 3").first, "1 m")
        XCTAssertEqual(card("(10 km + 2 km) / 3 km"), ["4", nil])
        XCTAssertEqual(card("(10 km / 1 h) / (5 km / 1 h)"), ["2", nil])
        XCTAssertEqual(card("(5 ft 10 in) * 2 in cm").first, "355.6 cm")
        XCTAssertEqual(card("-(1 kg - 1500 g)").first, "0.5 kg")
        XCTAssertEqual(card("(2 + 3) * 1 km").first, "5 km")
        XCTAssertEqual(card("(2,5 km + 500 m) * 2", locale: Locale(identifier: "de_DE")).first, "6 km")
    }

    func testGroupedQuantitiesOverATimeGiveRates() {
        XCTAssertEqual(card("(1 mi + 1 km) / 8 min"), ["12.160284 mph", "Miles per hour"])
        XCTAssertEqual(card("(1 km + 1 mi) / 8 min").first, "19.57008 km/h")
        XCTAssertEqual(card("(10 km + 2 km) / 1 h").first, "12 km/h")
        XCTAssertEqual(card("(10 km + 2 km) / 1 h in mph"), ["7.456454 mph", "Miles per hour"])
        XCTAssertEqual(card("(10 km + 2 km) / 1 h in min/km").first, "5 min/km")
        XCTAssertEqual(card("(10 km + 2 km) / (30 min + 30 min)").first, "12 km/h")
        XCTAssertEqual(card("(10 km + 2 km) / 1 h * 2").first, "24 km/h")
        XCTAssertEqual(card("(1 GB + 500 MB) / 10 s").first, "1200 Mbps")
        XCTAssertEqual(card("(1 GB + 500 MB) / 10 s in MB/s").first, "150 MB/s")
        XCTAssertEqual(card("1 mi + 1 km / 8 min"), [])
        XCTAssertEqual(card("(10 km + 2 km) / 1 h in kg"), [])
        XCTAssertEqual(card("(10 kg + 2 kg) / 1 h"), [])
        XCTAssertEqual(card("(10 km + 2 km) / (1 h - 60 min)"), [])
        XCTAssertEqual(card("(10 km + 2 km) / 1 h + 1 km"), [])
        XCTAssertEqual(card("(10 km + 2 km) / 1 h / 1 h"), [])
    }

    func testParenthesesKeepDimensionChecks() {
        XCTAssertEqual(card("(5 km + 3 kg) * 2"), [])
        XCTAssertEqual(card("(5 km + 3) * 2"), [])
        XCTAssertEqual(card("(5 km) * (2 km)"), [])
        XCTAssertEqual(card("(10 km + 2 km) / 3 km in mi"), [])
        XCTAssertEqual(card("2 * (1 ft + 6 in) in kg"), [])
        XCTAssertEqual(card("(10 c + 5 c) * 2"), [])
        XCTAssertEqual(card("(30 mpg + 5 mpg) * 2"), [])
        XCTAssertEqual(card("(1 h + 30 min) * 2"), [])
        XCTAssertEqual(card("(5 km) / (2 - 2)"), [])
        XCTAssertEqual(card("(5 km + 2 km"), [])
        XCTAssertEqual(card("5 km + 2 km)"), [])
        XCTAssertEqual(card("(5 km)"), [])
        XCTAssertEqual(card("(5 km) in mi"), [])
        XCTAssertEqual(card("(2 + 3) * 4"), [])
        XCTAssertEqual(card("(5 km apples) * 2"), [])
        XCTAssertEqual(card(String(repeating: "(", count: 40) + "1 km" + String(repeating: ")", count: 40) + " * 2"), [])
    }

    func testParenthesizedUnitsReachTheLauncherOnce() {
        let answers = CalculationAnswer.answers(for: "(3kg + 5lbs) * 2 in oz", locale: Self.english)
        XCTAssertEqual(answers.map(\.result), ["371.643772 oz"])
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

    func testDecimalCommaLocales() {
        XCTAssertEqual(card("2,5 km + 500 m", locale: Locale(identifier: "de_DE")).first, "3 km")
    }
}
