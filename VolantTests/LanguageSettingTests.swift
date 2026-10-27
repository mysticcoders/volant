import XCTest
@testable import Volant

/// The language choice is Volant's own `AppleLanguages`, the value System Settings writes per app.
/// Uses a throwaway defaults suite, never Volant's real preferences.
final class LanguageSettingTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suite = "volant-language-tests-" + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDownWithError() throws { defaults.removePersistentDomain(forName: suite) }

    private func setting() -> LanguageSetting {
        LanguageSetting(defaults: defaults, domain: suite, available: ["Base", "de", "en", "es", "ja", "pt-BR"])
    }

    func testEnglishFirstThenTranslationsByOwnName() {
        XCTAssertEqual(setting().choices.first, "en")
        XCTAssertFalse(setting().choices.contains("Base"))
        XCTAssertEqual(Set(setting().choices), ["de", "en", "es", "ja", "pt-BR"])
        XCTAssertEqual(LanguageSetting.name("de"), "Deutsch")
        XCTAssertEqual(LanguageSetting.name("es"), "Español")
    }

    func testChoosingWritesAppleLanguagesAndSystemRemovesIt() {
        XCTAssertNil(setting().chosen, "No choice follows the Mac")
        setting().choose("ja")
        XCTAssertEqual(defaults.persistentDomain(forName: suite)?["AppleLanguages"] as? [String], ["ja"])
        XCTAssertEqual(setting().chosen, "ja")
        setting().choose(nil)
        XCTAssertNil(defaults.persistentDomain(forName: suite)?["AppleLanguages"])
        XCTAssertNil(setting().chosen)
    }

    func testRegionalChoiceFromSystemSettingsMapsToTheShippedLanguage() {
        defaults.set(["de-AT"], forKey: "AppleLanguages")
        XCTAssertEqual(setting().chosen, "de", "System Settings may store a regional variant")
    }
}
