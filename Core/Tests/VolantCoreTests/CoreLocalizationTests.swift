import XCTest

@testable import VolantCore

/// VolantCore's strings resolve from the "Core" table of whatever bundle carries it, which in the app
/// is the main bundle. A wrong table name would fall back to English silently, so this checks a real
/// lookup against a temporary bundle with a fictional French table, and the English fallback without one.
final class CoreLocalizationTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("core-localization-" + UUID().uuidString + ".bundle")
        let french = root.appendingPathComponent("Contents/Resources/fr.lproj", isDirectory: true)
        try FileManager.default.createDirectory(at: french, withIntermediateDirectories: true)
        try Data(#""Listening Servers" = "Serveurs à l’écoute";"#.utf8).write(to: french.appendingPathComponent("Core.strings"))
        let english = root.appendingPathComponent("Contents/Resources/en.lproj", isDirectory: true)
        try FileManager.default.createDirectory(at: english, withIntermediateDirectories: true)
        try Data(#"<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.mysticcoders.volant.localization-test</string><key>CFBundleDevelopmentRegion</key><string>en</string></dict></plist>"#.utf8)
            .write(to: root.appendingPathComponent("Contents/Info.plist"))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testCommandTitlesResolveFromTheCoreTable() throws {
        for command in CoreCommand.allCases {
            XCTAssertEqual(command.titleResource.table, "Core", "\(command) title")
            XCTAssertEqual(command.detailResource.table, "Core", "\(command) detail")
            XCTAssertEqual(command.titleResource.key, command.title, "\(command) is keyed by its English name")
        }
        let bundle = try XCTUnwrap(Bundle(url: root))
        let path = try XCTUnwrap(bundle.path(forResource: "Core", ofType: "strings", inDirectory: nil, forLocalization: "fr"))
        let french = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
        XCTAssertEqual(french[CoreCommand.servers.titleResource.key], "Serveurs à l’écoute")
    }

    func testEnglishIsTheFallbackAndStaysSearchable() {
        XCTAssertEqual(CoreCommand.servers.title, "Listening Servers")
        XCTAssertEqual(CoreCommand.servers.englishTitle, "Listening Servers")
        XCTAssertEqual(CoreCommand.caffeinate.detail, "Keep your Mac awake")
        XCTAssertTrue(CoreCommand.search("dictate").contains(.talk), "The English name finds a command whatever the language")
    }
}
