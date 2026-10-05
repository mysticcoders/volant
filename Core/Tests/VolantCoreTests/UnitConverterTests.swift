import XCTest

@testable import VolantCore

final class UnitConverterTests: XCTestCase {
    func testLengthAndCompactForm() {
        let c = UnitConverter.convert("5 km in mi")!
        XCTAssertEqual(c.result, 3.10686, accuracy: 0.001)
        XCTAssertEqual(UnitConverter.convert("5km to mi")!.result, c.result)
    }

    func testTemperatureTouchingUnit() {
        XCTAssertEqual(UnitConverter.convert("72f to c")!.result, 22.222, accuracy: 0.01)
        XCTAssertEqual(UnitConverter.convert("100 c in f")!.result, 212, accuracy: 0.0001)
    }

    func testDataAndSpeed() {
        XCTAssertEqual(UnitConverter.convert("1 gib in mb")!.result, 1073.741824, accuracy: 0.001)
        XCTAssertEqual(UnitConverter.convert("100 kph as mph")!.result, 62.137, accuracy: 0.01)
    }

    private func result(_ query: String) throws -> Double { try XCTUnwrap(UnitConverter.convert(query), query).result }

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

    func testMismatchedDimensionsAndGarbage() {
        XCTAssertNil(UnitConverter.convert("5 km in kg"))
        XCTAssertNil(UnitConverter.convert("Safari"))
        XCTAssertNil(UnitConverter.convert("km in mi"))
        XCTAssertNil(UnitConverter.convert("5 c in km"))
        XCTAssertNil(UnitConverter.convert("5 km in"))
        XCTAssertNil(UnitConverter.convert("5 furlongs in m"))
        XCTAssertNil(UnitConverter.convert("5 km in mi in ft"))
    }

    func testFormat() {
        XCTAssertEqual(UnitConverter.format(UnitConverter.convert("2 lb in kg")!), "2 lb = 0.907185 kg")
        XCTAssertEqual(UnitConverter.formatResult(UnitConverter.convert("1 mi in km")!), "1.609344 km")
        XCTAssertEqual(UnitConverter.formatResult(UnitConverter.convert("-40 c in f")!), "-40 °F")
        XCTAssertEqual(UnitConverter.formatResult(UnitConverter.convert("10 kn in kph")!), "18.52 km/h")
        XCTAssertEqual(UnitConverter.formatResult(UnitConverter.convert("1 tbsp in tsp")!), "3 tsp")
    }
}
