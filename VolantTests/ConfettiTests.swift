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

    private let screen = CGSize(width: 1512, height: 982)
    private let displays = [CGSize(width: 1512, height: 982), CGSize(width: 1800, height: 1169),
                            CGSize(width: 2560, height: 1440), CGSize(width: 1440, height: 2560)]

    func testConfettiComesFromTheTwoBottomCornersOnly() {
        let emitters = ConfettiWindow.emitters(size: screen)
        XCTAssertEqual(emitters.count, 2, "sources elsewhere make it look like it comes from everywhere")
        XCTAssertEqual(emitters.map(\.emitterPosition), [CGPoint(x: 0, y: 0), CGPoint(x: screen.width, y: 0)])
    }

    /// Earlier versions had gravity pushing pieces up the screen and cannons aimed off-screen.
    /// These pin the signs.
    func testPiecesAreLaunchedUpAndPulledBackDown() {
        for emitter in ConfettiWindow.emitters(size: screen) {
            for cell in emitter.emitterCells ?? [] {
                XCTAssertGreaterThan(cell.velocity, 0, "a throw needs launch speed")
                XCTAssertLessThan(cell.yAcceleration, 0, "+y is up on an unflipped layer, so gravity is negative")
                XCTAssertGreaterThan(sin(Double(cell.emissionLongitude)), 0.5, "the cannon aims upward")
            }
        }
    }

    func testEachCornerSpraysInwardAsAMirrorOfTheOther() throws {
        let emitters = ConfettiWindow.emitters(size: screen)
        let left = try XCTUnwrap(emitters.first?.emitterCells?.first)
        let right = try XCTUnwrap(emitters.last?.emitterCells?.first)
        // Angles run counterclockwise from +x: below .pi/2 leans right, above it leans left.
        XCTAssertLessThan(left.emissionLongitude, .pi / 2, "the left corner sprays towards the right")
        XCTAssertGreaterThan(right.emissionLongitude, .pi / 2, "the right corner sprays towards the left")
        XCTAssertEqual(Double(left.emissionLongitude + right.emissionLongitude), .pi, accuracy: 0.0001,
                       "the two cannons are mirror images")
    }

    func testTheSprayIsAConeThatNeverFiresBackwardsOffScreen() {
        for size in displays {
            let aim = ConfettiWindow.aimElevation(for: size)
            // Treat the cone as a half-angle, the widest reading of emissionRange.
            XCTAssertLessThan(aim + ConfettiWindow.sprayCone, .pi / 2,
                              "a corner cannon must not throw pieces behind itself on \(size)")
            XCTAssertGreaterThan(aim - ConfettiWindow.sprayCone, 0, "nor into the floor")
        }
        XCTAssertGreaterThan(ConfettiWindow.sprayCone, .pi / 12, "too narrow a cone is a hose, not a spray")
    }

    func testTheArcRisesHighAndPeaksAroundTheMiddle() {
        for size in displays where size.width >= size.height {
            let peak = ConfettiWindow.peakHeight(for: size)
            XCTAssertEqual(Double(peak), Double(size.height * ConfettiWindow.peakFraction), accuracy: 1)
            let apex = ConfettiWindow.apexDistance(for: size)
            XCTAssertGreaterThan(apex, size.width * 0.35, "the sprays should reach towards the middle")
            XCTAssertLessThan(apex, size.width * 0.7, "and not overshoot to the far corner")
        }
    }

    func testEveryPieceLandsBeforeTheWindowCloses() {
        for size in displays {
            XCTAssertLessThan(ConfettiWindow.longestFlight(for: size), ConfettiWindow.settleDuration,
                              "pieces must fall back through the bottom edge before the window closes on \(size)")
        }
    }

    func testPiecesStaySolidInTheAirLikePaper() {
        for emitter in ConfettiWindow.emitters(size: screen) {
            let cells = emitter.emitterCells ?? []
            XCTAssertEqual(cells.count, ConfettiWindow.colors.count, "one cell per colour")
            for cell in cells {
                XCTAssertNotNil(cell.contents, "a cell with no image draws nothing")
                XCTAssertGreaterThan(cell.birthRate, 0)
                XCTAssertEqual(cell.alphaSpeed, 0, "confetti falls off the screen rather than dissolving")
                XCTAssertEqual(Double(cell.lifetime), ConfettiWindow.settleDuration, accuracy: 0.01)
            }
        }
    }

    func testTheBurstThrowsAReadableNumberOfPieces() {
        let total = ConfettiWindow.totalPieces(cannons: ConfettiWindow.emitters(size: screen).count)
        XCTAssertEqual(total, ConfettiWindow.pieceCount, accuracy: 2)
        XCTAssertLessThan(total, 600, "more than this stops looking like individual pieces")
        XCTAssertGreaterThan(total, 80, "fewer than this does not read as a celebration")
    }

    func testDensityDoesNotDriftWhenCannonsOrColoursChange() {
        XCTAssertGreaterThan(ConfettiWindow.birthRate(cannons: 2), ConfettiWindow.birthRate(cannons: 5))
        XCTAssertEqual(ConfettiWindow.totalPieces(cannons: 2), ConfettiWindow.pieceCount, accuracy: 2)
        XCTAssertEqual(ConfettiWindow.totalPieces(cannons: 8), ConfettiWindow.pieceCount, accuracy: 2)
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
