import XCTest

@testable import VolantCore

/// Keyboard selection in the Rex Overview, over fictional sessions: two tabs in one session, one in
/// another, a split tab, and waiting panes in different sessions.
final class RexOverviewNavigationTests: XCTestCase {
    private func pane(_ id: String, _ rect: [Double], waiting: Bool = false) -> RexOverview.Pane {
        .init(blockID: "block:" + id, label: "shell", status: waiting ? RexStatus(state: .blocked) : nil, rect: rect)
    }
    private func at(_ session: String, _ block: String) -> RexOverview.Selection {
        .init(sessionID: "session:" + session, blockID: "block:" + block)
    }
    private lazy var overview = RexOverview(sessions: [
        .init(sessionID: "session:orbit", label: "orbit", tabs: [
            .init(windowID: "window:api", label: "api", focusedBlockID: "block:logs", panes: [
                pane("shell", [0.6, 0.5, 0.4, 0.5]), pane("agent", [0, 0, 0.6, 1]), pane("logs", [0.6, 0, 0.4, 0.5]),
            ]),
            .init(windowID: "window:web", label: "web", focusedBlockID: "block:web", panes: [pane("web", [0, 0, 1, 1])]),
        ]),
        .init(sessionID: "session:ops", label: "ops", tabs: [
            .init(windowID: "window:deploy", label: "deploy", panes: [pane("deploy", [0, 0, 1, 1], waiting: true)]),
        ]),
    ])

    func testReadingOrderIsTopToBottomThenLeftToRight() {
        let order = RexOverview.readingOrder(overview.sessions[0].tabs[0].panes).map(\.blockID)
        XCTAssertEqual(order, ["block:agent", "block:logs", "block:shell"])
    }

    func testStartsOnTheFirstWaitingPane() {
        XCTAssertEqual(overview.initialSelection, at("ops", "deploy"))
        let quiet = RexOverview(sessions: [overview.sessions[0]])
        XCTAssertEqual(quiet.initialSelection, at("orbit", "logs"), "with nothing waiting, the first tab's focused pane")
    }

    func testTabMovesCrossSessionsAndStopAtTheEnds() {
        XCTAssertEqual(overview.move(.nextTab, from: at("orbit", "agent")), at("orbit", "web"))
        XCTAssertEqual(overview.move(.nextTab, from: at("orbit", "web")), at("ops", "deploy"))
        XCTAssertEqual(overview.move(.nextTab, from: at("ops", "deploy")), at("ops", "deploy"))
        XCTAssertEqual(overview.move(.previousTab, from: at("orbit", "web")), at("orbit", "logs"), "a tab is entered at its main pane")
        XCTAssertEqual(overview.move(.previousTab, from: at("orbit", "agent")), at("orbit", "agent"))
    }

    func testPaneMovesStayInTheTabInReadingOrder() {
        XCTAssertEqual(overview.move(.nextPane, from: at("orbit", "agent")), at("orbit", "logs"))
        XCTAssertEqual(overview.move(.nextPane, from: at("orbit", "logs")), at("orbit", "shell"))
        XCTAssertEqual(overview.move(.nextPane, from: at("orbit", "shell")), at("orbit", "shell"))
        XCTAssertEqual(overview.move(.previousPane, from: at("orbit", "logs")), at("orbit", "agent"))
        XCTAssertEqual(overview.move(.nextPane, from: at("orbit", "web")), at("orbit", "web"), "a single-pane tab has nowhere to go")
    }

    func testWaitingMovesWrapAndStayWhenNothingElseWaits() {
        XCTAssertEqual(overview.move(.nextWaiting, from: at("orbit", "web")), at("ops", "deploy"))
        XCTAssertEqual(overview.move(.previousWaiting, from: at("orbit", "agent")), at("ops", "deploy"), "wraps backwards")
        XCTAssertEqual(overview.move(.nextWaiting, from: at("ops", "deploy")), at("ops", "deploy"), "the only waiting pane")
        let twoWaiting = RexOverview(sessions: [
            .init(sessionID: "session:a", label: "a", tabs: [.init(windowID: "window:1", label: "1", panes: [pane("one", [0, 0, 1, 1], waiting: true)])]),
            .init(sessionID: "session:b", label: "b", tabs: [.init(windowID: "window:2", label: "2", panes: [pane("two", [0, 0, 1, 1], waiting: true)])]),
        ])
        XCTAssertEqual(twoWaiting.move(.nextWaiting, from: at("b", "two")), at("a", "one"), "wraps forwards")
    }

    func testPaneMovesReachFloatingAndHiddenPanes() {
        let floating = RexOverview(sessions: [.init(sessionID: "session:s", label: "s", tabs: [
            .init(windowID: "window:w", label: "w", panes: [
                .init(blockID: "block:float", label: "f", rect: [0.6, 0.6, 0.3, 0.3], layer: 1),
                .init(blockID: "block:tile", label: "t", rect: [0, 0, 1, 1]),
            ]),
            .init(windowID: "window:z", label: "z", panes: [
                .init(blockID: "block:behind", label: "b", status: RexStatus(state: .blocked), rect: [0, 0, 0.5, 1]),
                .init(blockID: "block:front", label: "f", rect: [0.5, 0, 0.5, 1]),
            ], zoomedBlockID: "block:front"),
        ])])
        XCTAssertEqual(floating.move(.nextPane, from: at("s", "tile")), at("s", "float"), "down reaches a floating pane after the tiles")
        XCTAssertEqual(floating.initialSelection, at("s", "behind"), "a waiting pane behind a zoom is where selection starts")
        XCTAssertEqual(floating.move(.nextPane, from: at("s", "behind")), at("s", "front"))
    }

    func testAMinimizedSessionIsOneStop() {
        let minimized: Set<String> = ["session:orbit"]
        XCTAssertEqual(overview.move(.previousTab, from: at("ops", "deploy"), minimized: minimized), at("orbit", "logs"),
                       "Left lands on the minimized session's first tab's main pane when nothing in it waits")
        XCTAssertEqual(overview.move(.nextTab, from: at("orbit", "logs"), minimized: minimized), at("ops", "deploy"),
                       "Right leaves the whole minimized session in one step, past its second tab")
        XCTAssertEqual(overview.move(.nextPane, from: at("orbit", "agent"), minimized: minimized), at("orbit", "agent"), "Down stays put inside it")
        XCTAssertEqual(overview.move(.nextWaiting, from: at("orbit", "web"), minimized: minimized), at("ops", "deploy"))
        let waitingInside: Set<String> = ["session:ops"]
        XCTAssertEqual(overview.move(.nextTab, from: at("orbit", "web"), minimized: waitingInside), at("ops", "deploy"),
                       "a minimized session with a waiting pane is entered at that pane")
        XCTAssertEqual(overview.move(.nextWaiting, from: at("orbit", "agent"), minimized: waitingInside), at("ops", "deploy"),
                       "Tab still reaches a waiting pane in a minimized session")
    }

    func testSelectionSurvivesRefreshesByIdentity() {
        XCTAssertEqual(overview.resolve(at("orbit", "shell")), at("orbit", "shell"))
        let shellClosed = RexOverview(sessions: [
            .init(sessionID: "session:orbit", label: "orbit", tabs: [
                .init(windowID: "window:api", label: "api", focusedBlockID: "block:logs", panes: [pane("agent", [0, 0, 0.6, 1]), pane("logs", [0.6, 0, 0.4, 1])]),
            ]),
        ])
        XCTAssertEqual(shellClosed.resolve(at("orbit", "shell")), at("orbit", "logs"), "a closed pane hands selection to the tab Rex focuses")
        XCTAssertEqual(shellClosed.resolve(at("gone", "deploy")), at("orbit", "logs"), "a closed session falls back to the start")
        XCTAssertEqual(shellClosed.resolve(nil), at("orbit", "logs"))
        XCTAssertNil(RexOverview(sessions: []).resolve(at("orbit", "shell")))
        XCTAssertEqual(overview.resolve(.init(sessionID: "session:ops", blockID: "block:agent")), overview.initialSelection,
                       "the same block ID in another session is not the same pane")
    }
}
