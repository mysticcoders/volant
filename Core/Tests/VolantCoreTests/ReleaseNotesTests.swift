import XCTest
@testable import VolantCore

final class ReleaseNotesTests: XCTestCase {
    func testSectionsItemsAndClosingNotes() {
        let notes = ReleaseNotes(version: "0.3.3", markdown: """
        ## New

        - **Redesigned Settings.** A searchable sidebar. (#236)
        - **fsearch.** Whole-disk results, if you run it. (#224, #225, #230)

        ## Changed

        - Extensions that are off no longer appear
          in everyday search. (#230)

        Requires macOS 15 or later.
        """)
        XCTAssertEqual(notes.version, "0.3.3")
        XCTAssertEqual(notes.sections.map(\.title), ["New", "Changed"])
        XCTAssertEqual(notes.sections[0].items, ["**Redesigned Settings.** A searchable sidebar.", "**fsearch.** Whole-disk results, if you run it."])
        XCTAssertEqual(notes.sections[1].items, ["Extensions that are off no longer appear in everyday search."])
        XCTAssertEqual(notes.notes, ["Requires macOS 15 or later."])
    }

    func testKeepsLinksAndParenthesesThatAreNotReferences() {
        let notes = ReleaseNotes(version: "1", markdown: "## New\n- Uses [fsearch](https://example.com) (optional).")
        XCTAssertEqual(notes.sections[0].items, ["Uses [fsearch](https://example.com) (optional)."])
    }

    func testVersionsCompareNumerically() {
        XCTAssertTrue(ReleaseNotes.isNewer("0.3.10", than: "0.3.9"))
        XCTAssertTrue(ReleaseNotes.isNewer("0.4", than: "0.3.9"))
        XCTAssertFalse(ReleaseNotes.isNewer("0.3.1", than: "0.3.1"))
        XCTAssertFalse(ReleaseNotes.isNewer("0.2.7", than: "0.3.0"))
    }

    func testLoadsAFolderNewestFirst() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for version in ["0.2.7", "0.3.10", "0.3.9"] {
            try "## New\n- Item".write(to: folder.appendingPathComponent(version + ".md"), atomically: true, encoding: .utf8)
        }
        try "ignored".write(to: folder.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
        XCTAssertEqual(ReleaseNotes.load(from: folder).map(\.version), ["0.3.10", "0.3.9", "0.2.7"])
    }

    func testEveryShippedReleaseNoteParses() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../docs/releases").standardized
        let releases = ReleaseNotes.load(from: folder)
        XCTAssertFalse(releases.isEmpty)
        for release in releases {
            XCTAssertFalse(release.sections.isEmpty, "\(release.version) has no sections")
            XCTAssertFalse(release.sections.flatMap(\.items).contains { $0.contains("(#") }, "\(release.version) keeps a PR reference")
        }
    }
}
