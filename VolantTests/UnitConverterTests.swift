import XCTest
@testable import Volant

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

    func testMismatchedDimensionsAndGarbage() {
        XCTAssertNil(UnitConverter.convert("5 km in kg"))
        XCTAssertNil(UnitConverter.convert("Safari"))
        XCTAssertNil(UnitConverter.convert("km in mi"))
    }

    func testFormat() {
        XCTAssertEqual(UnitConverter.format(UnitConverter.convert("2 lb in kg")!), "2 lb = 0.907184 kg")
    }
}
