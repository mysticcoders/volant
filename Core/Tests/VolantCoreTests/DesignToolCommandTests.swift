import XCTest

@testable import VolantCore

/// The portable halves of Pick Color, Open Camera and the System Events toggles: names, search,
/// the formats a picked color copies as, and how preferences are read for the row descriptions.
final class DesignToolCommandTests: XCTestCase {
    func testPickedColorUsesTheCalculatorsFormats() {
        let color = PickedColor(red: 1, green: 99.0 / 255, blue: 99.0 / 255)
        XCTAssertEqual(color.value(.hex), "#ff6363")
        XCTAssertEqual(color.value(.rgb), "rgb(255 99 99)")
        XCTAssertEqual(color.value(.hsl), ColorCalculator.evaluate("#ff6363 in hsl")?.result)
        XCTAssertEqual(color.value(.oklch), ColorCalculator.evaluate("#ff6363 in oklch")?.result)
        XCTAssertEqual(PickedColor.Format.allCases.map(\.label), ["HEX", "RGB", "HSL", "OKLCH"])
    }

    func testPickedColorClampsSamplerNoise() {
        let color = PickedColor(red: 1.0004, green: -0.0002, blue: 0.5)
        XCTAssertEqual(color.red, 1)
        XCTAssertEqual(color.green, 0)
        XCTAssertEqual(color.value(.hex), "#ff0080")
    }

    func testCommandsAreFoundByTheirTriggerWords() {
        for word in ["color picker", "pick color", "eyedropper", "Pick Col"] {
            XCTAssertTrue(CoreCommand.search(word).contains(.colorPicker), word)
        }
        for word in ["camera", "open camera", "webcam"] {
            XCTAssertTrue(CoreCommand.search(word).contains(.camera), word)
        }
        XCTAssertEqual(SystemToggle.search("dark mode"), [.appearance])
        XCTAssertEqual(SystemToggle.search("light mode"), [.appearance])
        XCTAssertEqual(SystemToggle.search("toggle appearance"), [.appearance])
        XCTAssertEqual(SystemToggle.search("menu bar"), [.menuBar])
        XCTAssertEqual(SystemToggle.search("hide menu bar"), [.menuBar])
        XCTAssertEqual(SystemToggle.search("show menu bar"), [.menuBar])
        XCTAssertTrue(SystemToggle.search("da").isEmpty, "short queries do not list toggles")
        XCTAssertTrue(SystemToggle.search("display").isEmpty)
    }

    func testCommandWordsAreNotReservedSoAliasesKeepWorking() {
        for word in ["camera", "color picker", "dark mode", "menu bar"] {
            XCTAssertFalse(LauncherRouting.isReserved(word), word)
        }
    }

    func testStateIsReadFromGlobalPreferences() {
        XCTAssertEqual(SystemToggle.appearance.state(inGlobalDefaults: ["AppleInterfaceStyle": "Dark"]), true)
        XCTAssertEqual(SystemToggle.appearance.state(inGlobalDefaults: [:]), false, "Light stores no style")
        XCTAssertNil(SystemToggle.appearance.state(inGlobalDefaults: nil))
        XCTAssertEqual(SystemToggle.menuBar.state(inGlobalDefaults: ["_HIHideMenuBar": true]), true)
        XCTAssertEqual(SystemToggle.menuBar.state(inGlobalDefaults: ["_HIHideMenuBar": NSNumber(value: 0)]), false)
        XCTAssertEqual(SystemToggle.menuBar.state(inGlobalDefaults: [:]), false)
    }

    func testEachToggleNamesOneSystemEventsProperty() {
        XCTAssertTrue(SystemToggle.appearance.systemEventsProperty == ("aprp", "thme"))
        XCTAssertTrue(SystemToggle.menuBar.systemEventsProperty == ("dpas", "dahm"))
        XCTAssertNotEqual(SystemToggle.appearance.actionTitle(on: true), SystemToggle.appearance.actionTitle(on: false))
    }
}
