import XCTest

@testable import VolantCore

/// The inventory script's output is parsed from fictional sessions shaped like Rex's real replies,
/// including the `{}` Rex writes for an empty Lua table.
final class RexInventoryTests: XCTestCase {
    private func parse(_ json: String) throws -> RexInventory { try RexInventory.parse(Data(json.utf8)) }

    func testParsesPanesWithBlockedFirstAndEmptyLuaTables() throws {
        let inventory = try parse("""
        {"sessions":[
          {"session_id":"session:aaa","label":"website","panes":[
            {"block_id":"block:a1","label":"shell","cwd":"file://mac.local/Users/fictional/site","records":[{"state":"working","app":"cargo","updated_at":"2026-10-20T10:00:00Z"}]},
            {"block_id":"block:a2","label":"shell","records":{}}
          ]},
          {"session_id":"session:bbb","label":"api","panes":[
            {"block_id":"block:b1","label":"agent","cwd":"/Users/fictional/api","records":[{"state":"blocked","kind":"permission","app":"claude-code","msg":"Run the migration?"}]}
          ]},
          {"session_id":"session:ccc","label":"empty","panes":{}}
        ]}
        """)
        XCTAssertEqual(inventory.panes.map(\.id), ["session:bbb/block:b1", "session:aaa/block:a1", "session:aaa/block:a2"])
        let blocked = inventory.panes[0]
        XCTAssertEqual(blocked.state, .blocked)
        XCTAssertEqual(blocked.status?.kind, "permission")
        XCTAssertEqual(blocked.status?.message, "Run the migration?")
        XCTAssertEqual(blocked.program, "Claude Code")
        XCTAssertEqual(blocked.project, "api")
        XCTAssertEqual(inventory.panes[1].cwd, "/Users/fictional/site")
        XCTAssertEqual(inventory.panes[1].project, "site")
        XCTAssertNil(inventory.panes[2].status)
        XCTAssertEqual(inventory.panes[2].state, .idle)
        XCTAssertEqual(inventory.panes[2].project, "website", "a pane with no directory falls back to its session label")
        XCTAssertEqual(inventory.unreadableSessions, 0)
    }

    func testMostUrgentThenNewestRecordRepresentsThePane() throws {
        let inventory = try parse("""
        {"sessions":[{"session_id":"session:aaa","label":"s","panes":[{"block_id":"block:a1","records":[
          {"state":"idle","app":"zsh","updated_at":"2026-10-20T10:05:00Z"},
          {"id":"build/test","state":"error","effective_app":"cargo","msg":"older failure","updated_at":"2026-10-20T10:01:00Z"},
          {"id":"build/lint","state":"error","effective_app":"cargo","msg":"newer failure","updated_at":"2026-10-20T10:02:00Z"}
        ]}]}]}
        """)
        XCTAssertEqual(inventory.panes.first?.state, .error)
        XCTAssertEqual(inventory.panes.first?.status?.message, "newer failure")
        XCTAssertEqual(inventory.panes.first?.status?.app, "cargo")
    }

    func testUnknownValuesAreTreatedAsTheProtocolRequires() throws {
        let inventory = try parse("""
        {"sessions":[{"session_id":"session:aaa","label":"s","panes":[{"block_id":"block:a1","records":[
          {"state":"celebrating","kind":"telepathy","progress":250}
        ]}]}]}
        """)
        let status = try XCTUnwrap(inventory.panes.first?.status)
        XCTAssertEqual(status.state, .idle)
        XCTAssertNil(status.kind)
        XCTAssertNil(status.progress)
    }

    func testMalformedIdentifiersAndUnreadableSessionsAreLeftOut() throws {
        let inventory = try parse("""
        {"sessions":[
          {"session_id":"--focus","label":"bad","panes":[{"block_id":"block:x"}]},
          {"session_id":"session:aaa","label":"ok","panes":[{"block_id":"block:a1"},{"block_id":"block:a 2"},{"block_id":"session:a3"}]},
          {"session_id":"session:bbb","label":"gone","error":"unreadable"}
        ]}
        """)
        XCTAssertEqual(inventory.panes.map(\.blockID), ["block:a1"])
        XCTAssertEqual(inventory.unreadableSessions, 1)
    }

    func testProgramTextIsFlattenedAndBounded() throws {
        let long = String(repeating: "x", count: 900)
        let inventory = try parse("""
        {"sessions":[{"session_id":"session:aaa","label":"line\\none","panes":[{"block_id":"block:a1","cwd":"relative/path","records":[
          {"state":"blocked","msg":"\(long)"}
        ]}]}]}
        """)
        let pane = try XCTUnwrap(inventory.panes.first)
        XCTAssertEqual(pane.sessionLabel, "line one")
        XCTAssertEqual(pane.status?.message?.count, RexInventory.maximumMessage)
        XCTAssertNil(pane.cwd, "only absolute directories are kept")
    }

    func testRejectsANonListWhereAListBelongs() {
        XCTAssertThrowsError(try parse(#"{"sessions":{"session_id":"session:aaa"}}"#))
    }

    func testFocusArgumentsCarryOnlyCheckedIdentifiers() throws {
        let arguments = try XCTUnwrap(RexScript.focusArguments(home: "/Users/fictional", session: "session:aaa-1", block: "block:b_2"))
        XCTAssertEqual(Array(arguments.prefix(5)), ["--autostart=false", "--timeout", "5s", "-S", "unix:///Users/fictional/Library/Application%20Support/rex/server.sock"])
        XCTAssertEqual(arguments.last, #"{"block_id":"block:b_2","session_id":"session:aaa-1"}"#)
        XCTAssertNil(RexScript.focusArguments(home: "/Users/fictional", session: "session:aaa\"}", block: "block:b"))
        XCTAssertNil(RexScript.focusArguments(home: "/Users/fictional", session: "block:aaa", block: "block:b"))
        XCTAssertNil(RexScript.focusArguments(home: "/Users/fictional", session: "session:", block: "block:b"))
    }

    func testScriptsNeverReadScreensOrTypeInput() {
        for script in [RexScript.watch, RexScript.focus] {
            for forbidden in ["format", "clipboard_read", "write", "send", "client.key", "block.event", "rex.exec", "io.", "os."] {
                XCTAssertFalse(script.contains(forbidden), "\(forbidden) must not appear in a Rex script")
            }
        }
    }

    func testWatcherHearsEverySessionForABoundedTime() {
        let arguments = RexScript.watchArguments(home: "/Users/fictional")
        XCTAssertEqual(Array(arguments.dropFirst(5).prefix(4)), ["do", "--all", "--for", RexScript.watchLifetime])
        XCTAssertTrue(arguments.contains("--autostart=false"))
        XCTAssertFalse(RexScript.watch.contains("session.attach"), "a watcher is attached to every session already")
        XCTAssertFalse(RexScript.watch.contains("session.detach"), "detaching would stop that session's events")
    }

    func testFocusOutcomeNeverReadsAFailureAsShown() {
        func outcome(_ json: String) -> RexScript.FocusOutcome { RexScript.FocusOutcome(output: Data(json.utf8)) }
        XCTAssertEqual(outcome(#"{"shown":true}"#), .shown)
        XCTAssertNil(outcome(#"{"shown":true}"#).message)
        XCTAssertEqual(outcome(#"{"shown":false,"reason":"refused"}"#), .refused)
        XCTAssertTrue(outcome(#"{"shown":false,"reason":"refused"}"#).message?.contains("Remote Control") == true)
        XCTAssertEqual(outcome(#"{"shown":false,"reason":"noApp"}"#), .noApp)
        XCTAssertEqual(outcome(#"{"shown":false}"#), .failed)
        XCTAssertEqual(outcome("not json"), .failed)
        XCTAssertEqual(outcome(""), .failed)
        XCTAssertTrue(RexScript.focus.contains("code=refused"), "the script tells a Remote Control refusal apart")
    }

    func testFooterSummary() {
        let blocked = RexPane(sessionID: "session:a", sessionLabel: "a", blockID: "block:1", label: "shell", status: RexStatus(state: .blocked))
        let idle = RexPane(sessionID: "session:a", sessionLabel: "a", blockID: "block:2", label: "shell")
        XCTAssertEqual(RexStatusSummary(panes: [], connected: false, loading: false, problem: nil).text, "Rex: not connected")
        XCTAssertEqual(RexStatusSummary(panes: [blocked, idle], connected: true, loading: false, problem: "Rex isn’t running.").text, "Rex: 1 waiting")
        XCTAssertEqual(RexStatusSummary(panes: [], connected: true, loading: false, problem: "Rex isn’t running.").text, "Rex: unavailable")
        XCTAssertEqual(RexStatusSummary(panes: [], connected: true, loading: true, problem: nil).text, "Rex: loading…")
        XCTAssertEqual(RexStatusSummary(panes: [idle], connected: true, loading: false, problem: nil).text, "Rex: none waiting")
    }
}
