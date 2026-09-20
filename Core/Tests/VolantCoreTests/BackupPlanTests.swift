import XCTest

@testable import VolantCore

final class BackupPlanTests: XCTestCase {
    private var root: URL!
    private var source: URL!
    private var notesDestination: URL!
    private var configURL: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("volant-backup-tests-" + UUID().uuidString, isDirectory: true)
        source = root.appendingPathComponent("Volant-Backup-2026-09-20", isDirectory: true)
        notesDestination = root.appendingPathComponent("Support/Notes", isDirectory: true)
        configURL = root.appendingPathComponent("Support/config.json")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("Notes"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: notesDestination, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func writeConfig(_ object: [String: Any] = ["summonHotKey": "option+space"]) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        try data.write(to: source.appendingPathComponent("config.json"))
    }

    private func writeNote(_ name: String, _ body: String, in directory: URL) throws {
        try body.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    func testMissingOrCorruptConfigIsRejectedBeforeAnythingIsWritten() throws {
        XCTAssertThrowsError(try BackupFolder.plan(source: source, notesDestination: notesDestination)) { error in
            XCTAssertEqual(error as? BackupError, .unreadableConfig)
        }
        try "not json".write(to: source.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try BackupFolder.plan(source: source, notesDestination: notesDestination)) { error in
            XCTAssertEqual(error as? BackupError, .unreadableConfig)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: configURL.path))
    }

    func testPlanReadsPreferencesAndCountsOnlyMarkdownNotes() throws {
        try writeConfig(["summonHotKey": "control+space", "aliases": ["vs": "code"]])
        let incoming = source.appendingPathComponent("Notes")
        try writeNote("one.md", "first", in: incoming)
        try writeNote("two.md", "second", in: incoming)
        try writeNote("notes.txt", "ignored", in: incoming)
        try writeNote(".DS_Store", "ignored", in: incoming)

        let plan = try BackupFolder.plan(source: source, notesDestination: notesDestination)

        XCTAssertEqual(plan.preferences.summonHotKey, "control+space")
        XCTAssertEqual(plan.preferences.aliases, ["vs": "code"])
        XCTAssertEqual(plan.notes.map(\.source), ["one.md", "two.md"])
        XCTAssertEqual(plan.renamedCount, 0)
        XCTAssertTrue(plan.report.isEmpty)
    }

    func testCollidingNotesAreRenamedRatherThanReplacingExistingOnes() throws {
        try writeConfig()
        try writeNote("shared.md", "incoming", in: source.appendingPathComponent("Notes"))
        try writeNote("shared.md", "existing", in: notesDestination)

        let plan = try BackupFolder.plan(source: source, notesDestination: notesDestination)
        XCTAssertEqual(plan.notes.map(\.destination), ["imported-shared.md"])
        XCTAssertEqual(plan.renamedCount, 1)
        XCTAssertEqual(plan.report, ["1 note already exist by name and will be added alongside the originals."])

        try BackupFolder.apply(plan, source: source, configURL: configURL, notesDestination: notesDestination)
        XCTAssertEqual(try String(contentsOf: notesDestination.appendingPathComponent("shared.md"), encoding: .utf8), "existing")
        XCTAssertEqual(try String(contentsOf: notesDestination.appendingPathComponent("imported-shared.md"), encoding: .utf8), "incoming")
    }

    func testRepeatedImportKeepsCountingRatherThanFailingOnTheSecondCollision() throws {
        try writeConfig()
        try writeNote("shared.md", "incoming", in: source.appendingPathComponent("Notes"))
        try writeNote("shared.md", "existing", in: notesDestination)
        try writeNote("imported-shared.md", "first import", in: notesDestination)

        let plan = try BackupFolder.plan(source: source, notesDestination: notesDestination)
        XCTAssertEqual(plan.notes.map(\.destination), ["imported-2-shared.md"])

        try BackupFolder.apply(plan, source: source, configURL: configURL, notesDestination: notesDestination)
        XCTAssertEqual(try String(contentsOf: notesDestination.appendingPathComponent("imported-shared.md"), encoding: .utf8), "first import")
        XCTAssertEqual(try String(contentsOf: notesDestination.appendingPathComponent("imported-2-shared.md"), encoding: .utf8), "incoming")
    }

    func testTwoIncomingNotesCannotCollideWithEachOther() throws {
        XCTAssertEqual(BackupFolder.freeName(for: "a.md", taken: []), "a.md")
        XCTAssertEqual(BackupFolder.freeName(for: "a.md", taken: ["a.md"]), "imported-a.md")
        XCTAssertEqual(BackupFolder.freeName(for: "a.md", taken: ["a.md", "imported-a.md"]), "imported-2-a.md")
        XCTAssertEqual(BackupFolder.freeName(for: "a.md", taken: ["a.md", "imported-a.md", "imported-2-a.md"]), "imported-3-a.md")
    }

    func testApplyWritesTheOriginalBytesSoUnknownConfigFieldsSurvive() throws {
        try writeConfig(["summonHotKey": "option+space", "futureFeature": ["enabled": true]])

        let plan = try BackupFolder.plan(source: source, notesDestination: notesDestination)
        try BackupFolder.apply(plan, source: source, configURL: configURL, notesDestination: notesDestination)

        let written = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: Any]
        XCTAssertEqual((written?["futureFeature"] as? [String: Any])?["enabled"] as? Bool, true)
        XCTAssertEqual(written?["summonHotKey"] as? String, "option+space")
    }

    func testImportWithNoNotesFolderStillRestoresConfig() throws {
        try FileManager.default.removeItem(at: source.appendingPathComponent("Notes"))
        try writeConfig(["summonHotKey": "option+j"])

        let plan = try BackupFolder.plan(source: source, notesDestination: notesDestination)
        XCTAssertTrue(plan.notes.isEmpty)

        try BackupFolder.apply(plan, source: source, configURL: configURL, notesDestination: notesDestination)
        XCTAssertEqual(plan.preferences.summonHotKey, "option+j")
        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path))
    }

    func testExportFolderNameIsDatedAndSortable() {
        let date = Date(timeIntervalSince1970: 1_789_000_000)
        XCTAssertEqual(BackupFolder.exportName(on: date), "Volant-Backup-" + date.formatted(.iso8601.year().month().day()))
        XCTAssertTrue(BackupFolder.exportName(on: date).hasPrefix("Volant-Backup-20"))
    }
}
