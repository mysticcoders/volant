import XCTest

@testable import VolantCore

/// The `shortcuts list --show-identifiers` listing decodes to unique shortcuts by identifier,
/// rejects malformed lines, and the launcher command reserves its prefix.
final class AppleShortcutListingTests: XCTestCase {
    private let first = AppleShortcut(id: "11111111-1111-4111-8111-111111111111", name: "Recipes (家族)")
    private let second = AppleShortcut(id: "22222222-2222-4222-8222-222222222222", name: "Recipes (家族)")

    func testIdentifiersNamesAndMalformedCatalog() throws {
        let text = "\(first.name) (\(first.id))\n\(second.name) (\(second.id))\n\(first.name) (\(first.id))\n"
        let entries = try AppleShortcut.decodeListing(Data(text.utf8))
        XCTAssertEqual(Set(entries.map(\.id)), [first.id, second.id])
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(try AppleShortcut.decodeListing(Data()).isEmpty)
        for bad in ["name only", "Name (--help)", " (\(first.id))"] {
            XCTAssertThrowsError(try AppleShortcut.decodeListing(Data(bad.utf8)))
        }
        XCTAssertEqual(AppleShortcut.queryTerm(" APPLE SHORTCUTS recipes "), "recipes")
        XCTAssertEqual(AppleShortcut.queryTerm("shortcuts"), "")
        XCTAssertNil(AppleShortcut.queryTerm("shortcutting"))
        XCTAssertTrue(LauncherRouting.isReserved("apple shortcuts recipes"))
    }
}
