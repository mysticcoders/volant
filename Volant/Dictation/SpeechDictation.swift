import AppKit
import AVFoundation
import Foundation
import VolantCore

// Speech has existed since macOS 10.15, so canImport(Speech) is true even on the macOS 15 SDK
// where SpeechAnalyzer, SpeechTranscriber and AnalyzerInput do not exist. FoundationModels only
// ships in the macOS 26 SDK, so it stands in for "this was built against an SDK new enough to see
// those symbols". Without it the whole feature compiles out and reports that it needs macOS 26.
#if canImport(Speech) && canImport(FoundationModels)
import Speech
#endif

/// On-device dictation through Apple's SpeechAnalyzer. Audio never leaves this Mac, the models are
/// system-managed, and the transcript is handed back to the caller rather than written anywhere.
///
/// Speech transcription needs no entitlement of its own, but capturing the microphone does:
/// `com.apple.security.device.audio-input`, plus the usual microphone permission prompt. Both were
/// measured before this was written. The framework is macOS 26 and later while Volant supports
/// macOS 15, so this follows the pattern `AppleFoundationModel` established: absent, not broken.
final class SpeechDictation: ObservableObject {
    enum Availability: Equatable {
        case ready
        case unavailable(String)

        var isReady: Bool { self == .ready }
        var reason: String? { if case .unavailable(let text) = self { return text }; return nil }
    }

    enum DictationError: LocalizedError {
        case noCompatibleAudioFormat
        var errorDescription: String? {
            String(localized: "This Mac's microphone format cannot be used for dictation.")
        }
    }

    enum Phase: Equatable {
        case idle, listening, finishing, failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var transcript = ""

    var isListening: Bool { phase == .listening }

    /// Called on the main actor with each finalized phrase, in order, for typing while speaking.
    /// Volatile text that may still change is never passed here.
    var onFinalPhrase: ((String) -> Void)?
    /// Removes filler sounds from English phrases before they are shown, typed or copied.
    var removesFillers = true
    /// The owner's words: offered to the recognizer as hints, then corrected in every phrase.
    var vocabulary: [DictationVocabularyEntry] = []
    /// Also replaces words the spell checker doesn't know that sound like a vocabulary word.
    var fixesCloseMatches = true

    nonisolated static var availability: Availability {
        #if canImport(Speech) && canImport(FoundationModels)
        guard #available(macOS 26.0, *) else { return .unavailable(requiresNewerSystem) }
        guard SpeechTranscriber.isAvailable else {
            return .unavailable(String(localized: "On-device dictation is unavailable on this Mac."))
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted:
            return .unavailable(String(localized: "Microphone access is off. Turn it on in System Settings, Privacy & Security, Microphone."))
        default:
            return .ready
        }
        #else
        return .unavailable(requiresNewerSystem)
        #endif
    }

    private static var requiresNewerSystem: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return String(localized: "Dictation needs macOS 26 or later. This Mac runs macOS \(version.majorVersion).\(version.minorVersion).")
    }

    #if canImport(Speech) && canImport(FoundationModels)
    @available(macOS 26.0, *)
    private final class Session {
        let engine = AVAudioEngine()
        var analyzer: SpeechAnalyzer?
        var transcriber: SpeechTranscriber?
        var stream: AsyncStream<AnalyzerInput>.Continuation?
        var collector: Task<Void, Never>?
        var converter: AVAudioConverter?
        let meter = LevelMeter()
    }
    private var session: Any?
    #endif

    /// The loudest audio buffer so far, written only by the realtime tap and read only after the tap is
    /// removed.
    private final class LevelMeter {
        var loudest = DictationLevel.floor
    }

    /// How long capture continues after the owner releases the key, so the last word isn't cut off.
    /// hex measured that stopping at release lost the final word in 3 of 10 clips (issue #323).
    static let releaseTail: TimeInterval = 0.2
    /// Microphone buffers kept while the analyzer is still being set up, about a minute of audio.
    static let bufferedInputs = 256

    /// Starts capture. `finished` receives the final transcript, or nil when nothing was said.
    func start(finished: @escaping (String?) -> Void) {
        guard phase != .listening else { return }
        let availability = Self.availability
        guard availability.isReady else {
            phase = .failed(availability.reason ?? String(localized: "Dictation is unavailable."))
            finished(nil)
            return
        }
        transcript = ""
        #if canImport(Speech) && canImport(FoundationModels)
        guard #available(macOS 26.0, *) else { phase = .failed(Self.requiresNewerSystem); finished(nil); return }
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard granted else {
                    self.phase = .failed(String(localized: "Dictation needs microphone access."))
                    finished(nil)
                    return
                }
                self.begin(finished: finished)
            }
        }
        #else
        phase = .failed(Self.requiresNewerSystem)
        finished(nil)
        #endif
    }

    #if canImport(Speech) && canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func begin(finished: @escaping (String?) -> Void) {
        let session = Session()
        self.session = session
        phase = .listening
        Task {
            do {
                let locale = await Self.bestLocale()
                let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                                    reportingOptions: [.volatileResults], attributeOptions: [])
                session.transcriber = transcriber
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    try await request.downloadAndInstall()
                }
                let vocabulary = self.vocabulary

                // The microphone runs at the hardware rate, typically 48 kHz, while the analyzer
                // wants its own format, typically 16 kHz. AnalyzerInput traps on a mismatched
                // buffer, and the tap runs on the realtime audio thread where a trap kills the
                // process, so the conversion happens before anything is handed over.
                let inputFormat = session.engine.inputNode.inputFormat(forBus: 0)
                guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                    compatibleWith: [transcriber], considering: inputFormat) else {
                    throw DictationError.noCompatibleAudioFormat
                }
                guard let converter = AVAudioConverter(from: inputFormat, to: analyzerFormat) else {
                    throw DictationError.noCompatibleAudioFormat
                }
                session.converter = converter

                // Capture starts before the analyzer is built, so words spoken while it is set up are
                // kept in the stream instead of lost.
                let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingNewest(Self.bufferedInputs))
                session.stream = continuation
                let meter = session.meter
                session.engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
                    // Nothing in here may trap: this is the realtime audio thread, where a trap
                    // takes the whole process down rather than surfacing as an error.
                    if let channels = buffer.floatChannelData, buffer.frameLength > 0 {
                        let level = DictationLevel.decibels(UnsafeBufferPointer(start: channels[0], count: Int(buffer.frameLength)))
                        if level > meter.loudest { meter.loudest = level }
                    }
                    guard let converted = SpeechDictation.convert(buffer, using: converter, to: analyzerFormat)
                    else { return }
                    continuation.yield(AnalyzerInput(buffer: converted))
                }
                session.engine.prepare()
                try session.engine.start()

                let analyzer = SpeechAnalyzer(modules: [transcriber])
                session.analyzer = analyzer
                // The terms go to the analyzer as contextual strings too. On macOS 27.0.1 SpeechTranscriber
                // ignored them in every measured clip (docs/dictation-vocabulary.md), so the
                // corrections below are what the owner relies on; the hints cost nothing if a later
                // system honors them.
                let hints = DictationVocabulary.hints(vocabulary)
                if !hints.isEmpty {
                    let context = AnalysisContext()
                    context.contextualStrings[.general] = hints
                    try? await analyzer.setContext(context)
                }
                try await analyzer.prepareToAnalyze(in: analyzerFormat)
                try await analyzer.start(inputSequence: stream)

                session.collector = Task { @MainActor in
                    // Volatile results refine as you speak, so the newest value replaces the last.
                    // Each phrase is cleaned and corrected before it is shown or typed, so a filler or
                    // a known mishearing never appears.
                    var settled = ""
                    let closeMatches = self.fixesCloseMatches && DictationCleanup.supports(locale) && !vocabulary.isEmpty
                    var knownWords: [String: Bool] = [:]
                    let isKnown = { (word: String) -> Bool in
                        if let known = knownWords[word] { return known }
                        let known = SpeechDictation.spellCheckerKnows(word, locale: locale)
                        knownWords[word] = known
                        return known
                    }
                    let clean = { (text: String) in
                        let exact = DictationVocabulary.applying(vocabulary, to: self.removesFillers ? DictationCleanup.removingFillers(text, locale: locale) : text)
                        return closeMatches ? DictationCloseMatch.correcting(vocabulary, in: exact, isKnownWord: isKnown) : exact
                    }
                    do {
                        for try await result in transcriber.results {
                            let text = clean(String(result.text.characters))
                            if result.isFinal {
                                settled += text
                                self.transcript = settled
                                if !text.isEmpty { self.onFinalPhrase?(text) }
                            } else {
                                self.transcript = settled + text
                            }
                        }
                    } catch {
                        self.phase = .failed(error.localizedDescription)
                    }
                }
            } catch {
                await MainActor.run {
                    session.engine.inputNode.removeTap(onBus: 0)
                    session.engine.stop()
                    session.stream?.finish()
                    self.phase = .failed(error.localizedDescription)
                    self.session = nil
                    finished(nil)
                }
            }
        }
    }
    #endif


    /// Whether the system spell checker accepts a word in the dictation language, including words the
    /// owner taught it. Close matches only ever replace words it does not know.
    static func spellCheckerKnows(_ word: String, locale: Locale) -> Bool {
        let language = locale.language.languageCode?.identifier ?? "en"
        return NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0, language: language, wrap: false,
                                                   inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
    }

    /// Resamples a microphone buffer into the analyzer's format. `AnalyzerInput` traps on a buffer
    /// whose format does not match, and the caller is the realtime audio thread, so this returns
    /// nil for anything it cannot convert rather than raising.
    static func convert(_ buffer: AVAudioPCMBuffer,
                        using converter: AVAudioConverter,
                        to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard buffer.frameLength > 0 else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var error: NSError?
        var supplied = false
        converter.convert(to: converted, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, converted.frameLength > 0 else { return nil }
        return converted
    }

    /// Stops capture and reports the transcript. Safe to call when not listening. Capture continues for
    /// `releaseTail` after the call so the last word isn't cut off. A dictation whose loudest moment
    /// stayed below `DictationLevel.silenceThreshold` is discarded without finishing its transcription,
    /// so an accidental tap of the key types nothing.
    func stop(finished: @escaping (String?) -> Void) {
        #if canImport(Speech) && canImport(FoundationModels)
        guard #available(macOS 26.0, *), let session = session as? Session, phase == .listening else {
            finished(nil); return
        }
        phase = .finishing
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.releaseTail) { [weak self] in
            guard let self, let current = self.session as? Session, current === session else { finished(nil); return }
            session.engine.inputNode.removeTap(onBus: 0)
            session.engine.stop()
            session.stream?.finish()
            let silent = DictationLevel.isSilent(loudest: session.meter.loudest)
            Task {
                if silent {
                    await session.analyzer?.cancelAndFinishNow()
                    session.collector?.cancel()
                } else {
                    try? await session.analyzer?.finalizeAndFinishThroughEndOfInput()
                }
                _ = await session.collector?.result
                await MainActor.run {
                    self.session = nil
                    if silent { self.transcript = "" }
                    let text = self.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    if case .failed = self.phase {} else { self.phase = .idle }
                    finished(text.isEmpty ? nil : text)
                }
            }
        }
        #else
        finished(nil)
        #endif
    }

    func cancel() {
        #if canImport(Speech) && canImport(FoundationModels)
        if #available(macOS 26.0, *), let session = session as? Session {
            session.engine.inputNode.removeTap(onBus: 0)
            session.engine.stop()
            session.stream?.finish()
            session.collector?.cancel()
        }
        session = nil
        #endif
        transcript = ""
        phase = .idle
    }

    #if canImport(Speech) && canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func bestLocale() async -> Locale {
        let supported = await SpeechTranscriber.supportedLocales
        let current = Locale.current
        if supported.contains(where: { $0.identifier(.bcp47) == current.identifier(.bcp47) }) { return current }
        return supported.first { $0.identifier(.bcp47) == "en-US" } ?? current
    }
    #endif
}
