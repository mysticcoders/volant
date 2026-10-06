import XCTest

@testable import VolantCore

final class UnitConverterTests: XCTestCase {
    private static let english = Locale(identifier: "en_US")

    func testLengthAndCompactForm() {
        let c = UnitConverter.convert("5 km in mi", locale: Self.english)!
        XCTAssertEqual(c.result, 3.10686, accuracy: 0.001)
        XCTAssertEqual(UnitConverter.convert("5km to mi", locale: Self.english)!.result, c.result)
    }

    func testTemperatureTouchingUnit() {
        XCTAssertEqual(UnitConverter.convert("72f to c", locale: Self.english)!.result, 22.222, accuracy: 0.01)
        XCTAssertEqual(UnitConverter.convert("100 c in f", locale: Self.english)!.result, 212, accuracy: 0.0001)
    }

    func testDataAndSpeed() {
        XCTAssertEqual(UnitConverter.convert("1 gib in mb", locale: Self.english)!.result, 1073.741824, accuracy: 0.001)
        XCTAssertEqual(UnitConverter.convert("100 kph as mph", locale: Self.english)!.result, 62.137, accuracy: 0.01)
    }

    private func result(_ query: String) throws -> Double { try XCTUnwrap(UnitConverter.convert(query, locale: Self.english), query).result }

    func testEveryFamilyAgainstReferenceFactors() throws {
        XCTAssertEqual(try result("1 mi in km"), 1.609344, accuracy: 1e-9)
        XCTAssertEqual(try result("1 nmi in m"), 1852, accuracy: 1e-9)
        XCTAssertEqual(try result("3 ft in in"), 36, accuracy: 1e-9)
        XCTAssertEqual(try result("1 yd in cm"), 91.44, accuracy: 1e-9)
        XCTAssertEqual(try result("1 lb in g"), 453.59237, accuracy: 1e-6)
        XCTAssertEqual(try result("1 st in lb"), 14, accuracy: 1e-9)
        XCTAssertEqual(try result("16 oz in lb"), 1, accuracy: 1e-9)
        XCTAssertEqual(try result("1500 mg in g"), 1.5, accuracy: 1e-9)
        XCTAssertEqual(try result("1 gal in l"), 3.785411784, accuracy: 1e-6)
        XCTAssertEqual(try result("1 cup in ml"), 236.5882365, accuracy: 1e-9)
        XCTAssertEqual(try result("1 floz in ml"), 29.5735295625, accuracy: 1e-9)
        XCTAssertEqual(try result("1 cup in floz"), 8, accuracy: 1e-9)
        XCTAssertEqual(try result("1 gal in qt"), 4, accuracy: 1e-9)
        XCTAssertEqual(try result("1 tbsp in tsp"), 3, accuracy: 1e-6)
        XCTAssertEqual(try result("1 qt in pt"), 2, accuracy: 1e-6)
        XCTAssertEqual(try result("1 acre in m2"), 4046.8564224, accuracy: 0.01)
        XCTAssertEqual(try result("1 ha in m2"), 10_000, accuracy: 1e-6)
        XCTAssertEqual(try result("1 km2 in ha"), 100, accuracy: 1e-6)
        XCTAssertEqual(try result("1 kwh in kj"), 3600, accuracy: 1e-6)
        XCTAssertEqual(try result("1 kcal in kj"), 4.184, accuracy: 1e-6)
        XCTAssertEqual(try result("1 hp in w"), 745.69987158227022, accuracy: 1e-9)
        XCTAssertEqual(try result("760 mmhg in kpa"), 101.325, accuracy: 1e-3)
        XCTAssertEqual(try result("1 bar in kpa"), 100, accuracy: 1e-6)
        XCTAssertEqual(try result("1 psi in kpa"), 6.894757, accuracy: 1e-4)
        XCTAssertEqual(try result("10 kn in kph"), 18.52, accuracy: 1e-6)
        XCTAssertEqual(try result("10 m/s in kph"), 36, accuracy: 1e-6)
        XCTAssertEqual(try result("90 min in h"), 1.5, accuracy: 1e-9)
        XCTAssertEqual(try result("1 h in s"), 3600, accuracy: 1e-9)
    }

    func testTemperatureEdgesAndSpellings() throws {
        XCTAssertEqual(try result("-40 c in f"), -40, accuracy: 1e-9)
        XCTAssertEqual(try result("0 k in c"), -273.15, accuracy: 1e-9)
        XCTAssertEqual(try result("98.6°f to c"), 37, accuracy: 1e-9)
        XCTAssertEqual(try result("100 celsius in fahrenheit"), 212, accuracy: 1e-9)
    }

    func testDecimalAndBinaryStorageStayDistinct() throws {
        XCTAssertEqual(try result("1 gb in mb"), 1000, accuracy: 1e-9)
        XCTAssertEqual(try result("1 gib in mib"), 1024, accuracy: 1e-9)
        XCTAssertEqual(try result("1 kib in b"), 1024, accuracy: 1e-9)
        XCTAssertEqual(try result("1 tb in gb"), 1000, accuracy: 1e-9)
    }

    func testLongNamesPluralsAndCase() throws {
        XCTAssertEqual(try result("5 Kilometres to Miles"), try result("5 km in mi"), accuracy: 1e-12)
        XCTAssertEqual(try result("2 feet as meters"), 0.6096, accuracy: 1e-9)
        XCTAssertEqual(try result("3 teaspoons = ml"), try result("3 tsp in ml"), accuracy: 1e-12)
        XCTAssertEqual(try result("1.5 hours in minutes"), 90, accuracy: 1e-9)
    }

    func testUnitNamesWithSpacesAndInchesAsTheSourceUnit() throws {
        XCTAssertEqual(try result("5 sq ft in m2"), 0.4645152, accuracy: 1e-9)
        XCTAssertEqual(try result("2 square feet to square meters"), 0.18580608, accuracy: 1e-9)
        XCTAssertEqual(try result("1 sq mi in acres"), 640, accuracy: 1e-6)
        XCTAssertEqual(try result("9 sq ft in sq yd"), 1, accuracy: 1e-9)
        XCTAssertEqual(try result("1 sq in in sq cm"), 6.4516, accuracy: 1e-9)
        XCTAssertEqual(try result("8 fl oz in cups"), 1, accuracy: 1e-9)
        XCTAssertEqual(try result("5 in in cm"), 12.7, accuracy: 1e-9)
        XCTAssertEqual(try result("12 in to ft"), 1, accuracy: 1e-9)
        XCTAssertEqual(try result("5 nautical miles in km"), 9.26, accuracy: 1e-9)
    }

    func testNumbersFollowTheLocaleWithoutMagnitudes() throws {
        XCTAssertEqual(try result("1,000 m in km"), 1, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(UnitConverter.convert("2,5 km in m", locale: Locale(identifier: "de_DE"))).result, 2500, accuracy: 1e-9)
        XCTAssertEqual(try result("100k in c"), -173.15, accuracy: 1e-9)
        XCTAssertEqual(try result("-3.5 c in f"), 25.7, accuracy: 1e-9)
        XCTAssertNil(UnitConverter.convert("1,5 km in m", locale: Self.english))
        XCTAssertNil(UnitConverter.convert("10K km in mi", locale: Self.english))
    }

    func testMismatchedDimensionsAndGarbage() {
        XCTAssertNil(UnitConverter.convert("5 km in kg", locale: Self.english))
        XCTAssertNil(UnitConverter.convert("Safari", locale: Self.english))
        XCTAssertNil(UnitConverter.convert("km in mi", locale: Self.english))
        XCTAssertNil(UnitConverter.convert("5 c in km", locale: Self.english))
        XCTAssertNil(UnitConverter.convert("5 km in", locale: Self.english))
        XCTAssertNil(UnitConverter.convert("5 furlongs in m", locale: Self.english))
        XCTAssertNil(UnitConverter.convert("5 km in mi in ft", locale: Self.english))
    }

    func testFormat() {
        XCTAssertEqual(UnitConverter.format(UnitConverter.convert("2 lb in kg", locale: Self.english)!), "2 lb = 0.907185 kg")
        XCTAssertEqual(UnitConverter.formatResult(UnitConverter.convert("1 mi in km", locale: Self.english)!), "1.609344 km")
        XCTAssertEqual(UnitConverter.formatResult(UnitConverter.convert("-40 c in f", locale: Self.english)!), "-40 °F")
        XCTAssertEqual(UnitConverter.formatResult(UnitConverter.convert("10 kn in kph", locale: Self.english)!), "18.52 km/h")
        XCTAssertEqual(UnitConverter.formatResult(UnitConverter.convert("1 tbsp in tsp", locale: Self.english)!), "3 tsp")
    }

    func testAstronomicalLengthsUseExactDefinitions() throws {
        XCTAssertEqual(try result("1 ly in km"), 9_460_730_472_580.8, accuracy: 1e-3)
        XCTAssertEqual(try result("1 light year in m"), 9_460_730_472_580_800, accuracy: 1)
        XCTAssertEqual(try result("1 au in km"), 149_597_870.7, accuracy: 1e-6)
        XCTAssertEqual(try result("1 parsec in au"), 648_000 / Double.pi, accuracy: 1e-6)
        XCTAssertEqual(try result("1 pc in ly"), 3.261563777, accuracy: 1e-8)
    }

    func testPressureEnergyAndMachUnits() throws {
        XCTAssertEqual(try result("1 atm in pa"), 101_325, accuracy: 1e-9)
        XCTAssertEqual(try result("1 atmosphere in psi"), 14.6959488, accuracy: 1e-6)
        XCTAssertEqual(try result("760 torr in atm"), 1, accuracy: 1e-12)
        XCTAssertEqual(try result("1 atm in mmhg"), 760, accuracy: 1e-3)
        XCTAssertEqual(try result("1013.25 hpa in atm"), 1, accuracy: 1e-12)
        XCTAssertEqual(try result("1000 mbar in bar"), 1, accuracy: 1e-12)
        XCTAssertEqual(try result("1 btu in j"), 1055.05585262, accuracy: 1e-9)
        XCTAssertEqual(try result("3412.14163 btu in kwh"), 1, accuracy: 1e-6)
        XCTAssertEqual(try result("1 mach in m/s"), 340.29, accuracy: 1e-9)
        XCTAssertEqual(try result("mach 2 in km/h"), 2450.088, accuracy: 1e-6)
        XCTAssertEqual(try result("1225.044 kph in mach"), 1, accuracy: 1e-9)
        XCTAssertNil(UnitConverter.convert("mach two in kph", locale: Self.english))
    }

    func testCountsConvertFromABareNumber() throws {
        XCTAssertEqual(try result("30 in dozens"), 2.5, accuracy: 1e-12)
        XCTAssertEqual(try result("288 to gross"), 2, accuracy: 1e-12)
        XCTAssertEqual(try result("2 gross in dozen"), 24, accuracy: 1e-12)
        XCTAssertEqual(try result("3 dozen in each"), 36, accuracy: 1e-12)
        let bare = try XCTUnwrap(UnitConverter.convert("30 in dozens", locale: Self.english))
        XCTAssertEqual(UnitConverter.formatSource(bare, locale: Self.english), "30")
        XCTAssertEqual(UnitConverter.swapQuery(bare, locale: Self.english), "2.5 dozen in each")
        let back = try XCTUnwrap(UnitConverter.convert("3 dozen in each", locale: Self.english))
        XCTAssertEqual(UnitConverter.formatResult(back, locale: Self.english), "36")
        XCTAssertNil(UnitConverter.convert("30 in km", locale: Self.english))
    }

    func testSpeedOfLightOnlyWhereCelsiusCannotFit() throws {
        XCTAssertEqual(try result("speed of light"), 299_792_458, accuracy: 0)
        XCTAssertEqual(try result("speed of light in km/h"), 1_079_252_848.8, accuracy: 1e-3)
        XCTAssertEqual(try result("c in m/s"), 299_792_458, accuracy: 0)
        XCTAssertEqual(try result("0.5 c in m/s"), 149_896_229, accuracy: 0)
        XCTAssertEqual(try result("670616629.384395 mph in c"), 1, accuracy: 1e-12)
        XCTAssertEqual(try result("100 c in f"), 212, accuracy: 1e-9)
        XCTAssertEqual(try result("300 k in c"), 26.85, accuracy: 1e-9)
        XCTAssertNil(UnitConverter.convert("c in f", locale: Self.english))
    }
}
