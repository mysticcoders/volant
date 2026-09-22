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

    func testConfettiIsThrownUpwardFromTheBottomCorners() {
        let emitters = ConfettiWindow.emitters(width: 1440)
        XCTAssertEqual(emitters.count, 2, "two cannons read as a throw; one reads as a fountain")
        XCTAssertEqual(emitters.map(\.emitterPosition.y), [0, 0], "confetti is thrown from the floor, not dropped from the ceiling")
        XCTAssertEqual(emitters.map(\.emitterPosition.x), [0, 1440], "one cannon per bottom corner")
    }

    /// The first version had gravity pushing pieces up the screen while they were fired sideways,
    /// which is why it looked wrong. These pin the signs.
    func testPiecesAreLaunchedUpAndPulledBackDown() {
        for emitter in ConfettiWindow.emitters(width: 1440) {
            for cell in emitter.emitterCells ?? [] {
                XCTAssertGreaterThan(cell.velocity, 0, "a throw needs launch speed")
                XCTAssertLessThan(cell.yAcceleration, 0, "+y is up on an unflipped layer, so gravity is negative")
                XCTAssertGreaterThan(sin(Double(cell.emissionLongitude)), 0.5,
                                     "the cannon aims upward rather than sideways")
            }
        }
    }

    func testTheCannonsAimInwardFromOppositeCorners() throws {
        let emitters = ConfettiWindow.emitters(width: 1440)
        let left = try XCTUnwrap(emitters.first?.emitterCells?.first)
        let right = try XCTUnwrap(emitters.last?.emitterCells?.first)
        // Angles are measured from +x, so the left cannon leans right and the right one leans left.
        XCTAssertLessThan(left.emissionLongitude, .pi / 2)
        XCTAssertGreaterThan(right.emissionLongitude, .pi / 2)
    }

    func testTheBurstRisesHighEnoughToReadAsAThrow() {
        // Peak of a vertical launch is v² / 2g; anything low would look like a fizzle.
        XCTAssertGreaterThan(ConfettiWindow.peakHeight, 200,
                             "the arc has to clear enough screen to be visible")
        let timeToPeak = Double(ConfettiWindow.launchSpeed / abs(ConfettiWindow.gravity))
        XCTAssertLessThan(timeToPeak * 2, ConfettiWindow.settleDuration,
                          "pieces must land before the window closes over them")
    }

    func testEveryPieceFadesWithinItsLifetime() {
        for emitter in ConfettiWindow.emitters(width: 1440) {
            let cells = try? XCTUnwrap(emitter.emitterCells)
            XCTAssertEqual(cells?.count, ConfettiWindow.colors.count, "one cell per colour")
            for cell in cells ?? [] {
                XCTAssertNotNil(cell.contents, "a cell with no image draws nothing")
                XCTAssertGreaterThan(cell.birthRate, 0)
                XCTAssertLessThan(cell.alphaSpeed, 0, "pieces fade rather than vanishing")
                XCTAssertEqual(Double(cell.lifetime), ConfettiWindow.settleDuration, accuracy: 0.01,
                               "nothing outlives the window that closes over it")
            }
        }
    }

    func testTheBurstIsShortEnoughToBeDecoration() {
        XCTAssertLessThanOrEqual(ConfettiWindow.emitDuration, 1, "a throw is a burst, not a stream")
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
