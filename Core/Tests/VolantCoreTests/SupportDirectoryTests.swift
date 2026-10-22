import XCTest

@testable import VolantCore

final class SupportDirectoryTests: XCTestCase {
    private var base: URL!

    override func setUpWithError() throws {
        base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("volant-support-tests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    private var current: URL { base.appendingPathComponent("Volant", isDirectory: true) }
    private var legacy: URL { base.appendingPathComponent("Vey", isDirectory: true) }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func testOnlyLegacyFolderMovesWhole() throws {
        try write("{}", to: legacy.appendingPathComponent("config.json"))
        try write("fictional note", to: legacy.appendingPathComponent("Notes/a.md"))
        let resolved = SupportDirectory.resolve(in: base)
        XCTAssertEqual(resolved.url, current)
        XCTAssertEqual(resolved.outcome, .moved(from: legacy))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertEqual(try String(contentsOf: current.appendingPathComponent("Notes/a.md"), encoding: .utf8), "fictional note")
        XCTAssertEqual(SupportDirectory.resolve(in: base).outcome, .current)
    }

    func testExistingCurrentFolderIsNeverMergedOrReplaced() throws {
        try write("new", to: current.appendingPathComponent("config.json"))
        try write("old", to: legacy.appendingPathComponent("config.json"))
        let resolved = SupportDirectory.resolve(in: base)
        XCTAssertEqual(resolved, SupportDirectory(url: current, outcome: .current))
        XCTAssertEqual(try String(contentsOf: current.appendingPathComponent("config.json"), encoding: .utf8), "new")
        XCTAssertEqual(try String(contentsOf: legacy.appendingPathComponent("config.json"), encoding: .utf8), "old")
    }

    func testFreshInstallUsesCurrentFolder() {
        XCTAssertEqual(SupportDirectory.resolve(in: base), SupportDirectory(url: current, outcome: .current))
    }

    func testFailedMoveKeepsLegacyFolderForThisLaunch() throws {
        final class RefusingFileManager: FileManager {
            override func moveItem(at srcURL: URL, to dstURL: URL) throws { throw CocoaError(.fileWriteNoPermission) }
        }
        try write("{}", to: legacy.appendingPathComponent("config.json"))
        let resolved = SupportDirectory.resolve(in: base, fileManager: RefusingFileManager())
        XCTAssertEqual(resolved, SupportDirectory(url: legacy, outcome: .kept(legacy: legacy)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("config.json").path))
    }

    func testLegacyDefaultsFollowTheMove() throws {
        let suite = "volant-support-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["a.md"], forKey: "notes." + legacy.path + "/Notes.pinned")
        defaults.set(["elsewhere.md"], forKey: "notes./Users/fictional/Notes.pinned")
        defaults.set("frame", forKey: "NSWindow Frame VeyNotes")
        defaults.set("kept", forKey: "NSWindow Frame VolantNotes")
        SupportDirectory(url: current, outcome: .moved(from: legacy)).moveLegacyDefaults(in: defaults)
        XCTAssertEqual(defaults.stringArray(forKey: "notes." + current.path + "/Notes.pinned"), ["a.md"])
        XCTAssertNil(defaults.object(forKey: "notes." + legacy.path + "/Notes.pinned"))
        XCTAssertEqual(defaults.stringArray(forKey: "notes./Users/fictional/Notes.pinned"), ["elsewhere.md"])
        XCTAssertEqual(defaults.string(forKey: "NSWindow Frame VolantNotes"), "kept")
        XCTAssertNil(defaults.object(forKey: "NSWindow Frame VeyNotes"))
    }

    func testKeptLegacyFolderLeavesPathKeyedDefaults() throws {
        let suite = "volant-support-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["a.md"], forKey: "notes." + legacy.path + "/Notes.pinned")
        SupportDirectory(url: legacy, outcome: .kept(legacy: legacy)).moveLegacyDefaults(in: defaults)
        XCTAssertEqual(defaults.stringArray(forKey: "notes." + legacy.path + "/Notes.pinned"), ["a.md"])
    }
}
