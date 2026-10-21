import XCTest

@testable import VolantCore

/// The overview is parsed from the same fictional watcher lines as the pane list, with tabs, rects,
/// titles, programs and bounded previews.
final class RexOverviewTests: XCTestCase {
    private func parse(_ json: String) throws -> RexOverview { try RexOverview.parse(Data(json.utf8)) }

    func testGroupsPanesIntoTabsWithTheirPlaces() throws {
        let overview = try parse("""
        {"sessions":[{"session_id":"session:a","label":"orbit",
          "windows":[{"window_id":"window:one","label":"api","active":true,"focused_block_id":"block:two"},
                     {"window_id":"window:two","label":"Window 3f2a91c0","focused_block_id":"block:three"},
                     {"window_id":"window:empty","label":"nothing here"}],
          "panes":[
            {"block_id":"block:one","label":"shell","window_id":"window:one","rect":[0,0,0.5,1],"title":"orbit-api","program":"/opt/homebrew/bin/claude","records":[{"state":"blocked","msg":"Allow?"}]},
            {"block_id":"block:two","label":"logs","window_id":"window:one","rect":[0.5,0,0.5,1],"program":"-zsh"},
            {"block_id":"block:three","label":"shell","window_id":"window:two","cwd":"/Users/fictional/notes"}
          ]}]}
        """)
        let tabs = try XCTUnwrap(overview.sessions.first?.tabs)
        XCTAssertEqual(tabs.map(\.windowID), ["window:one", "window:two"], "a tab with no terminal panes is left out")
        XCTAssertEqual(tabs[0].panes.map(\.rect), [[0, 0, 0.5, 1], [0.5, 0, 0.5, 1]])
        XCTAssertEqual(tabs[0].panes.map(\.program), ["claude", "zsh"])
        XCTAssertEqual(tabs[0].waiting, 1)
        XCTAssertEqual(tabs[0].primaryPane?.blockID, "block:one", "a waiting pane wins over the focused one")
        XCTAssertEqual(tabs[1].name, "notes", "a tab Rex named Window is named for its focused pane")
        XCTAssertTrue(tabs[0].active)
        XCTAssertNil(tabs[0].panes[0].preview, "no previews unless the watcher sent them")
    }

    func testPreviewsAreBoundedAndRectsClamped() throws {
        let lines = (1...30).map { "\"line \($0) " + String(repeating: "x", count: 300) + "\"" }.joined(separator: ",")
        let overview = try parse("""
        {"sessions":[{"session_id":"session:a","label":"s","windows":[{"window_id":"window:w","label":"t"}],
          "panes":[{"block_id":"block:b","window_id":"window:w","rect":[0.5,0.5,2,2],"preview":[\(lines),"bell\\u0007here"]}]}]}
        """)
        let pane = try XCTUnwrap(overview.sessions.first?.tabs.first?.panes.first)
        XCTAssertEqual(pane.rect, [0.5, 0.5, 0.5, 0.5])
        XCTAssertEqual(pane.preview?.count, RexScript.previewLines)
        XCTAssertTrue(pane.preview?.allSatisfy { $0.count <= RexScript.previewColumns } == true)
        XCTAssertEqual(pane.preview?.last, "bell here", "control characters are flattened")
    }

    func testMalformedIdentifiersAndEmptyLuaTables() throws {
        let overview = try parse("""
        {"sessions":[
          {"session_id":"session:a","label":"ok","windows":[{"window_id":"window:w"},{"window_id":"--bad"}],
           "panes":[{"block_id":"block:b","window_id":"window:w","rect":[0,0,"x",1]},{"block_id":"block:c","window_id":"--bad"}]},
          {"session_id":"session:empty","label":"empty","windows":{},"panes":{}}
        ]}
        """)
        XCTAssertEqual(overview.sessions.map(\.sessionID), ["session:a"])
        XCTAssertEqual(overview.sessions[0].tabs.map(\.windowID), ["window:w"])
        XCTAssertNil(overview.sessions[0].tabs[0].panes[0].rect, "a malformed rect draws as the whole tab")
    }

    func testPanePreviewsAreOffByDefaultPatchableAndNeverSynced() throws {
        XCTAssertFalse(Preferences().rexPanePreviews)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"summonHotKey":"cmd+space","futureField":{"kept":true}}"#.utf8).write(to: url)
        XCTAssertFalse(try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url)).rexPanePreviews)
        try Preferences.updateBoolean("rexPanePreviews", value: true, at: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(object["rexPanePreviews"] as? Bool, true)
        XCTAssertEqual(object["summonHotKey"] as? String, "cmd+space")
        XCTAssertNotNil(object["futureField"], "unknown fields survive the patch")
        XCTAssertFalse(SettingsSync.keys.contains("rexPanePreviews"), "reading screens is a per-Mac choice")
    }

    func testPreviewArgumentsAreOnlyAddedWhenAsked() {
        XCTAssertEqual(RexScript.watchArguments(home: "/Users/fictional", preview: true).suffix(2), ["--args", #"{"preview":true}"#])
        XCTAssertTrue(RexScript.watch.contains("rex.every(preview and 2 or 30"), "previews refresh every two seconds, status every thirty")
    }
}
