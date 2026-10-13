import XCTest
@testable import Volant

/// When dictation's start and stop sounds play, and how they order with lowering the volume.
final class DictationSoundsTests: XCTestCase {
    func testStartingPlaysTheStartSoundBeforeLoweringTheVolume() {
        XCTAssertEqual(DictationSounds.plan(from: .idle, to: .listening, sounds: true, lowersVolume: true),
                       .init(sound: .start, lowerAfter: DictationSounds.startDuration))
        XCTAssertEqual(DictationSounds.plan(from: .idle, to: .listening, sounds: false, lowersVolume: true), .init(sound: nil, lowerAfter: 0))
        XCTAssertEqual(DictationSounds.plan(from: .idle, to: .listening, sounds: true, lowersVolume: false), .init(sound: .start, lowerAfter: nil))
    }

    func testFinishingOrCancellingPlaysTheStopSoundAfterRestoring() {
        XCTAssertEqual(DictationSounds.plan(from: .listening, to: .finishing, sounds: true, lowersVolume: true), .init(sound: .stop, restore: true))
        XCTAssertEqual(DictationSounds.plan(from: .listening, to: .idle, sounds: true, lowersVolume: true), .init(sound: .stop, restore: true))
        XCTAssertEqual(DictationSounds.plan(from: .listening, to: .finishing, sounds: false, lowersVolume: true), .init(sound: nil, restore: true))
    }

    func testFailuresAndUnrelatedChangesAreSilent() {
        XCTAssertEqual(DictationSounds.plan(from: .listening, to: .failed("x"), sounds: true, lowersVolume: true), .init(sound: nil, restore: true))
        XCTAssertEqual(DictationSounds.plan(from: .finishing, to: .idle, sounds: true, lowersVolume: true), .init(sound: nil, restore: true))
        XCTAssertEqual(DictationSounds.plan(from: .idle, to: .idle, sounds: true, lowersVolume: true), .init(sound: nil, restore: true))
    }

    func testBothSystemSoundsExist() {
        XCTAssertNotNil(NSSound(named: "Tink"))
        XCTAssertNotNil(NSSound(named: "Pop"))
    }
}
