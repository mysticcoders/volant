import AVFoundation
import Foundation
import Speech
import VolantCore

/// The app's microphone for keyboard dictation, feeding a `SpeechTranscription`.
///
/// The microphone and the transcription are separate. iOS lets an app keep recording in the
/// background but not start recording there, so the microphone is opened while the app is in the
/// foreground and may stay open after a dictation ends; each dictation then routes the open
/// microphone into a new analyzer. Buffers that arrive while no dictation is running are dropped
/// on the audio thread without being kept.
@MainActor
final class PhoneDictation {
    enum Failure: LocalizedError {
        case microphoneDenied
        case microphoneClosed

        var errorDescription: String? {
            switch self {
            case .microphoneDenied: String(localized: "Microphone access is off. Turn it on in Settings › Apps › Volant.")
            case .microphoneClosed: String(localized: "The microphone closed before dictation could start.")
            }
        }
    }

    let transcription = SpeechTranscription()
    private let engine = AVAudioEngine()
    private var tapFormat: AVAudioFormat?
    private(set) var isMicrophoneOpen = false

    /// The current microphone level in dBFS while a dictation is routed, else the floor.
    var currentLevel: Float { transcription.gate.currentLevel }

    /// Whether the engine is still capturing; a configuration change can stop it underneath us.
    var isCapturing: Bool { engine.isRunning }

    /// Asks for microphone access if needed, then starts capture. Must run while the app is in the
    /// foreground. Safe to call when already open. The session mixes with other audio so music and
    /// podcasts keep playing while the microphone stays open between dictations.
    func openMicrophone() async throws {
        guard !isMicrophoneOpen else { return }
        guard SpeechTranscriber.isAvailable else { throw SpeechTranscription.Failure.unavailable }
        guard await AVAudioApplication.requestRecordPermission() else { throw Failure.microphoneDenied }
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker])
        try audio.setActive(true)
        let format = engine.inputNode.outputFormat(forBus: 0)
        tapFormat = format
        let gate = transcription.gate
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            gate.receive(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            throw error
        }
        isMicrophoneOpen = true
    }

    /// Stops capture and releases the audio session, ending any dictation without a transcript.
    func closeMicrophone() {
        transcription.cancel()
        guard isMicrophoneOpen else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isMicrophoneOpen = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Starts transcribing the open microphone.
    func begin(vocabulary: [DictationVocabularyEntry], removesFillers: Bool,
               onPreparing: @escaping (String) -> Void, onText: @escaping (String) -> Void) async throws {
        guard isMicrophoneOpen, let tapFormat else { throw Failure.microphoneClosed }
        transcription.vocabulary = vocabulary
        transcription.removesFillers = removesFillers
        try await transcription.begin(inputFormat: tapFormat, onPreparing: onPreparing, onText: onText)
    }

    /// Stops transcribing and returns the final transcript; the microphone stays open.
    func finish() async -> String? { await transcription.finish() }

    /// Ends the current dictation without a transcript; the microphone stays open.
    func cancel() { transcription.cancel() }
}
