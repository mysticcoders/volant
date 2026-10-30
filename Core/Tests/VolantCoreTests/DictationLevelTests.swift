import XCTest
@testable import VolantCore

/// The level that decides whether a dictation was silence, from fictional sample buffers.
final class DictationLevelTests: XCTestCase {
    private func level(_ samples: [Float]) -> Float { samples.withUnsafeBufferPointer(DictationLevel.decibels) }

    func testFullScaleIsZeroAndHalfIsAboutMinusSix() {
        XCTAssertEqual(level(Array(repeating: 1, count: 512)), 0, accuracy: 0.01)
        XCTAssertEqual(level(Array(repeating: -0.5, count: 512)), -6.02, accuracy: 0.01)
    }

    func testSilenceAndEmptyBuffersReachTheFloor() {
        XCTAssertEqual(level([]), DictationLevel.floor)
        XCTAssertEqual(level(Array(repeating: 0, count: 512)), DictationLevel.floor)
    }

    func testQuietSpeechPassesAndRoomNoiseIsSilence() {
        let speech = (0..<4800).map { Float(sin(Double($0) / 7)) * 0.03 }
        let hum = (0..<4800).map { Float(sin(Double($0) / 7)) * 0.002 }
        XCTAssertFalse(DictationLevel.isSilent(loudest: level(speech)), "about -33 dBFS is speech")
        XCTAssertTrue(DictationLevel.isSilent(loudest: level(hum)), "about -57 dBFS is silence")
        XCTAssertTrue(DictationLevel.isSilent(loudest: DictationLevel.floor))
    }
}
