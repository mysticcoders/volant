import XCTest

@testable import VolantCore

final class RepositoryStateTests: XCTestCase {
    func testCountsEntriesAndReadsBranchAndDivergence() {
        let output = """
        # branch.oid 0123456789abcdef
        # branch.head feature/login
        # branch.upstream origin/feature/login
        # branch.ab +2 -1
        1 .M N... 100644 100644 100644 abc abc Sources/App.swift
        1 A. N... 000000 100644 100644 000 abc Sources/New.swift
        2 R. N... 100644 100644 100644 abc abc R100 Sources/Renamed.swift\tSources/Old.swift
        u UU N... 100644 100644 100644 100644 a b c Sources/Conflict.swift
        ? notes.txt
        ! build/output.o
        """
        let state = RepositoryState.parse(porcelainV2: output)
        XCTAssertEqual(state, RepositoryState(branch: "feature/login", ahead: 2, behind: 1, changed: 5))
        XCTAssertEqual(state?.summary, "feature/login · 5 changed · 2 ahead · 1 behind")
    }

    func testCleanBranchWithoutUpstream() {
        let state = RepositoryState.parse(porcelainV2: "# branch.oid abc\n# branch.head main\n")
        XCTAssertEqual(state?.summary, "main · clean")
    }

    func testDetachedHeadAndNonRepositoryOutput() {
        XCTAssertNil(RepositoryState.parse(porcelainV2: "# branch.oid abc\n# branch.head (detached)\n")?.branch)
        XCTAssertNil(RepositoryState.parse(porcelainV2: "fatal: not a git repository"))
        XCTAssertNil(RepositoryState.parse(porcelainV2: ""))
    }
}

/// The helper's exact command against a real repository, so the parser is checked against what
/// git prints rather than only hand-written samples.
final class RepositoryStatusCommandTests: XCTestCase {
    func testNeverChoosesTheInstallerStubAndDisablesRepositoryPrograms() {
        XCTAssertNil(RepositoryStatusCommand.git(isExecutable: { $0 == "/usr/bin/git" }))
        XCTAssertEqual(RepositoryStatusCommand.git(isExecutable: { $0.hasPrefix("/Library/") }), "/Library/Developer/CommandLineTools/usr/bin/git")
        XCTAssertTrue(RepositoryStatusCommand.arguments.contains("core.fsmonitor=false"))
        XCTAssertTrue(RepositoryStatusCommand.arguments.contains("--no-optional-locks"))
        XCTAssertEqual(RepositoryStatusCommand.environment(home: "/h")["GIT_OPTIONAL_LOCKS"], "0")
    }

    private func git(_ arguments: [String], in directory: URL, executable: String) throws -> String {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = RepositoryStatusCommand.environment(home: directory.path)
            .merging(["GIT_AUTHOR_NAME": "Fixture", "GIT_AUTHOR_EMAIL": "fixture@example.com",
                      "GIT_COMMITTER_NAME": "Fixture", "GIT_COMMITTER_EMAIL": "fixture@example.com"]) { $1 }
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    func testRealRepositoryCountsChangesAndUntrackedFiles() throws {
        let executable = try XCTUnwrap(RepositoryStatusCommand.git(), "No git outside the installer stub on this machine")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try git(["init", "-q", "-b", "fixture"], in: root, executable: executable)
        try Data("one\n".utf8).write(to: root.appendingPathComponent("tracked.txt"))
        _ = try git(["add", "tracked.txt"], in: root, executable: executable)
        _ = try git(["commit", "-q", "-m", "Fixture"], in: root, executable: executable)
        XCTAssertEqual(RepositoryState.parse(porcelainV2: try git(RepositoryStatusCommand.arguments, in: root, executable: executable))?.summary,
                       "fixture · clean")
        try Data("two\n".utf8).write(to: root.appendingPathComponent("tracked.txt"))
        try Data("new\n".utf8).write(to: root.appendingPathComponent("untracked.txt"))
        let state = RepositoryState.parse(porcelainV2: try git(RepositoryStatusCommand.arguments, in: root, executable: executable))
        XCTAssertEqual(state, RepositoryState(branch: "fixture", changed: 2))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".git/index.lock").path))
    }
}
