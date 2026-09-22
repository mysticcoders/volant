import AppKit
import XCTest
import VolantCore

@testable import Volant

/// Confetti is decoration, so the things worth pinning are the ones that would make it a nuisance:
/// stealing focus, swallowing clicks, or staying on screen.
@MainActor
final class ConfettiTests: XCTestCase {
    func testConfettiIsADiscoverableCommand() {
        XCTAssertTrue(CoreCommand.allCases.contains(.confetti))
        XCTAssertEqual(CoreCommand.confetti.title, "Throw Confetti")
        XCTAssertEqual(CoreCommand.confetti.query, "confetti")
        XCTAssertEqual(CoreCommand.confetti.symbol, "party.popper")
        XCTAssertTrue(LauncherRouting.isReserved("confetti"))
    }

    func testTheEmitterCoversTheScreenWidthAndStartsAtTheTopEdge() {
        let emitter = ConfettiWindow.emitter(width: 1440)
        XCTAssertEqual(emitter.emitterSize.width, 1440, "confetti spans the display, not a corner")
        XCTAssertEqual(emitter.emitterPosition.x, 720)
        XCTAssertEqual(emitter.emitterShape, .line)
        XCTAssertFalse(emitter.emitterCells?.isEmpty ?? true)
    }

    func testEveryPieceFallsAndFadesWithinItsLifetime() throws {
        let cells = ConfettiWindow.cells()
        XCTAssertEqual(cells.count, ConfettiWindow.colors.count, "one cell per colour")
        for cell in cells {
            XCTAssertNotNil(cell.contents, "a cell with no image draws nothing")
            XCTAssertGreaterThan(cell.birthRate, 0)
            XCTAssertGreaterThan(cell.yAcceleration, 0, "gravity pulls pieces down the screen")
            XCTAssertLessThan(cell.alphaSpeed, 0, "pieces fade rather than vanishing")
            XCTAssertEqual(Double(cell.lifetime), ConfettiWindow.settleDuration, accuracy: 0.01,
                           "nothing outlives the window that closes over it")
        }
    }

    func testTheBurstIsShortEnoughToBeDecoration() {
        XCTAssertLessThanOrEqual(ConfettiWindow.emitDuration, 2, "a burst, not a screensaver")
        XCTAssertLessThanOrEqual(ConfettiWindow.emitDuration + ConfettiWindow.settleDuration, 6,
                                 "the whole thing is over quickly")
    }

    func testTheWindowNeverTakesFocusOrSwallowsClicks() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        ConfettiWindow.celebrate(on: screen)
        let window = try XCTUnwrap(NSApp.windows.compactMap { $0 as? ConfettiWindow }.last)

        XCTAssertFalse(window.canBecomeKey, "confetti must not steal the launcher's keyboard focus")
        XCTAssertFalse(window.canBecomeMain)
        XCTAssertTrue(window.ignoresMouseEvents, "clicks belong to whatever is underneath")
        XCTAssertFalse(window.isOpaque)
        XCTAssertEqual(window.backgroundColor, .clear)
        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertEqual(window.frame.size, screen.frame.size)

        window.close()
    }
}
