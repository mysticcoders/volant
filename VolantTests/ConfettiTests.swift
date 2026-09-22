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

    func testConfettiIsThrownUpwardFromAcrossTheBottomEdge() {
        let emitters = ConfettiWindow.emitters(size: screen)
        XCTAssertGreaterThanOrEqual(emitters.count, 5, "two corner cannons read as a pair of hoses")
        XCTAssertTrue(emitters.allSatisfy { $0.emitterPosition.y == 0 },
                      "confetti is thrown from the floor, not dropped from the ceiling")
        let xs = emitters.map(\.emitterPosition.x)
        XCTAssertEqual(xs.min(), 0)
        XCTAssertEqual(xs.max(), screen.width, "the sources span the full width")
    }

    /// The first version had gravity pushing pieces up the screen while they were fired sideways.
    /// The second launched too slowly to leave the corners. These pin both.
    func testPiecesAreLaunchedUpAndPulledBackDown() {
        for emitter in ConfettiWindow.emitters(size: screen) {
            for cell in emitter.emitterCells ?? [] {
                XCTAssertGreaterThan(cell.velocity, 0, "a throw needs launch speed")
                XCTAssertLessThan(cell.yAcceleration, 0, "+y is up on an unflipped layer, so gravity is negative")
                XCTAssertGreaterThan(sin(Double(cell.emissionLongitude)), 0.5,
                                     "the cannon aims upward rather than sideways")
            }
        }
    }

    func testTheBurstReachesTheTopOfWhateverScreenItIsOn() {
        for height in [800.0, 982.0, 1440.0, 2160.0] {
            let peak = ConfettiWindow.peakHeight(forHeight: height)
            XCTAssertGreaterThan(peak, height,
                                 "confetti must clear the top of a \(Int(height))pt display, not die in the corners")
        }
    }

    func testSpeedsVaryEnoughToFillTheMiddleRatherThanFormingABand() throws {
        let emitter = try XCTUnwrap(ConfettiWindow.emitters(size: screen).first)
        let cell = try XCTUnwrap(emitter.emitterCells?.first)
        XCTAssertGreaterThan(cell.velocityRange, cell.velocity * 0.4,
                             "a narrow speed range leaves every piece at the same height")
        XCTAssertGreaterThanOrEqual(Double(cell.emissionRange), Double.pi / 4,
                                    "a narrow cone is a hose")
    }

    func testTheCannonsLeanOutwardFromTheMiddle() throws {
        let emitters = ConfettiWindow.emitters(size: screen)
        let left = try XCTUnwrap(emitters.first?.emitterCells?.first)
        let middle = try XCTUnwrap(emitters[emitters.count / 2].emitterCells?.first)
        let right = try XCTUnwrap(emitters.last?.emitterCells?.first)
        XCTAssertLessThan(left.emissionLongitude, middle.emissionLongitude, "the left cannon leans right")
        XCTAssertGreaterThan(right.emissionLongitude, middle.emissionLongitude, "the right cannon leans left")
        XCTAssertEqual(Double(middle.emissionLongitude), .pi / 2, accuracy: 0.01, "the middle fires straight up")
    }

    func testPiecesLandBeforeTheWindowClosesOverThem() {
        let speed = ConfettiWindow.launchSpeed(forHeight: screen.height)
        let upAndBack = 2 * Double(speed / abs(ConfettiWindow.gravity))
        XCTAssertLessThan(upAndBack, ConfettiWindow.settleDuration,
                          "the arc has to complete inside the window's lifetime")
    }

    /// The first pass threw roughly 1,960 pieces, which filled the screen solid instead of
    /// reading as a handful of confetti in the air.
    func testTheBurstThrowsAReadableNumberOfPieces() {
        let emitters = ConfettiWindow.emitters(size: screen)
        let total = ConfettiWindow.totalPieces(cannons: emitters.count)
        XCTAssertEqual(total, ConfettiWindow.pieceCount, accuracy: 2,
                       "the derived birth rate has to produce the piece count that was asked for")
        XCTAssertLessThan(total, 600, "more than this stops looking like individual pieces")
        XCTAssertGreaterThan(total, 80, "fewer than this does not read as a celebration")
    }

    func testDensityDoesNotDriftWhenCannonsOrColoursChange() {
        // Birth rate is per cell, so it has to fall as cells are added or the burst silently
        // gets denser every time a cannon or a colour is introduced.
        XCTAssertGreaterThan(ConfettiWindow.birthRate(cannons: 2), ConfettiWindow.birthRate(cannons: 5))
        XCTAssertEqual(ConfettiWindow.totalPieces(cannons: 2), ConfettiWindow.pieceCount, accuracy: 2)
        XCTAssertEqual(ConfettiWindow.totalPieces(cannons: 8), ConfettiWindow.pieceCount, accuracy: 2)
    }

    func testEveryPieceFadesWithinItsLifetime() {
        for emitter in ConfettiWindow.emitters(size: screen) {
            let cells = emitter.emitterCells ?? []
            XCTAssertEqual(cells.count, ConfettiWindow.colors.count, "one cell per colour")
            for cell in cells {
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
