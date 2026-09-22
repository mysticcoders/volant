import AVFoundation
import XCTest
import VolantCore

@testable import Volant

/// Dictation needs macOS 26 and a microphone grant. These assertions hold either way: on an older
/// system the feature must be absent with a reason, never broken.
@MainActor
final class SpeechDictationTests: XCTestCase {
    func testAvailabilityAlwaysExplainsItselfWhenUnavailable() {
        let availability = SpeechDictation.availability
        if availability.isReady {
            XCTAssertNil(availability.reason)
        } else {
            XCTAssertFalse((availability.reason ?? "").isEmpty, "a refusal has to say what to do about it")
        }
    }

    func testOlderSystemsNameTheRequirement() {
        guard #unavailable(macOS 26.0) else { return }
        let reason = SpeechDictation.availability.reason ?? ""
        XCTAssertTrue(reason.contains("macOS"))
        XCTAssertFalse(SpeechDictation.availability.isReady)
    }

    func testANewSessionIsIdleAndEmpty() {
        let dictation = SpeechDictation()
        XCTAssertEqual(dictation.phase, .idle)
        XCTAssertTrue(dictation.transcript.isEmpty)
        XCTAssertFalse(dictation.isListening)
    }

    func testCancelIsSafeWhenNothingIsRunning() {
        let dictation = SpeechDictation()
        dictation.cancel()
        dictation.cancel()
        XCTAssertEqual(dictation.phase, .idle)
    }

    func testStoppingWhenNotListeningReportsNothing() {
        let stopped = expectation(description: "stopped")
        SpeechDictation().stop { transcript in
            XCTAssertNil(transcript)
            stopped.fulfill()
        }
        wait(for: [stopped], timeout: 2)
    }

    func testAnUnavailableSystemFailsWithAReasonRatherThanHanging() {
        guard !SpeechDictation.availability.isReady else { return }
        let dictation = SpeechDictation()
        let finished = expectation(description: "finished")
        dictation.start { transcript in
            XCTAssertNil(transcript)
            finished.fulfill()
        }
        wait(for: [finished], timeout: 3)
        guard case .failed(let reason) = dictation.phase else {
            return XCTFail("an unavailable system must land in failed")
        }
        XCTAssertFalse(reason.isEmpty)
    }
}

/// The crash that shipped in #85: microphone buffers were handed straight to AnalyzerInput, which
/// traps on a format mismatch — on the realtime audio thread, where a trap kills the process.
/// These use synthesized buffers, so they need no microphone and no macOS 26.
final class SpeechDictationConversionTests: XCTestCase {
    private func format(_ rate: Double, _ channels: AVAudioChannelCount = 1) -> AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)!
    }

    private func tone(_ format: AVAudioFormat, frames: AVAudioFrameCount = 4800) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(format.channelCount) {
            guard let data = buffer.floatChannelData?[channel] else { continue }
            for frame in 0..<Int(frames) {
                data[frame] = sin(Float(frame) * 0.05) * 0.25
            }
        }
        return buffer
    }

    func testMicrophoneRateIsResampledToTheAnalyzerRate() throws {
        let input = format(48000), analyzer = format(16000)
        let converter = try XCTUnwrap(AVAudioConverter(from: input, to: analyzer))

        let converted = try XCTUnwrap(SpeechDictation.convert(tone(input), using: converter, to: analyzer))

        XCTAssertEqual(converted.format.sampleRate, 16000, "a mismatched rate is what made AnalyzerInput trap")
        XCTAssertGreaterThan(converted.frameLength, 0)
        XCTAssertLessThan(converted.frameLength, 4800, "downsampling produces fewer frames")
    }

    func testAnEmptyBufferIsDroppedRatherThanConverted() throws {
        let input = format(48000), analyzer = format(16000)
        let converter = try XCTUnwrap(AVAudioConverter(from: input, to: analyzer))
        let empty = AVAudioPCMBuffer(pcmFormat: input, frameCapacity: 4096)!
        empty.frameLength = 0

        XCTAssertNil(SpeechDictation.convert(empty, using: converter, to: analyzer),
                     "the audio thread must not be asked to convert silence-length buffers")
    }

    func testMatchingFormatsStillProduceAUsableBuffer() throws {
        let shared = format(16000)
        let converter = try XCTUnwrap(AVAudioConverter(from: shared, to: shared))

        let converted = try XCTUnwrap(SpeechDictation.convert(tone(shared), using: converter, to: shared))
        XCTAssertEqual(converted.format.sampleRate, 16000)
        XCTAssertGreaterThan(converted.frameLength, 0)
    }

    func testStereoInputIsFoldedToTheAnalyzerChannelCount() throws {
        let input = format(48000, 2), analyzer = format(16000, 1)
        let converter = try XCTUnwrap(AVAudioConverter(from: input, to: analyzer))

        let converted = try XCTUnwrap(SpeechDictation.convert(tone(input), using: converter, to: analyzer))
        XCTAssertEqual(converted.format.channelCount, 1)
    }
}
