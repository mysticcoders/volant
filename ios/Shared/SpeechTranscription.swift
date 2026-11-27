import AVFoundation
import Foundation
import Speech
import Synchronization
import UIKit
import VolantCore

/// One dictation's transcription through Apple's SpeechAnalyzer, with the Mac's cleanup: filler
/// words removed, the owner's vocabulary applied to every phrase, then spoken numbers and
/// punctuation written as digits and marks, and spoken lists as lines in the finished text. Audio arrives through `gate`
/// from whatever captures it (the app's audio engine, or the keyboard's web capture) and never
/// leaves the device; the transcript is handed back rather than stored. Shared by the app and the
/// keyboard.
@MainActor
final class SpeechTranscription {
    enum Failure: LocalizedError {
        case unavailable
        case noCompatibleAudioFormat
        case needsModelDownload

        var errorDescription: String? {
            switch self {
            case .unavailable: String(localized: "On-device dictation is unavailable on this device.")
            case .noCompatibleAudioFormat: String(localized: "This microphone's format cannot be used for dictation.")
            case .needsModelDownload: String(localized: "The speech model needs to be downloaded first.")
            }
        }
    }

    /// Removes filler sounds from English phrases.
    var removesFillers = true
    /// The owner's words: offered to the recognizer as hints, then corrected in every phrase.
    var vocabulary: [DictationVocabularyEntry] = []
    /// Also replaces words the spell checker doesn't know that sound like a vocabulary word.
    var fixesCloseMatches = true
    /// Writes spoken numbers as digits, punctuation names as marks and spoken lists as lines.
    var formatsSpokenText = true
    /// Whether a missing speech model may be downloaded; the keyboard leaves that to the app.
    var downloadsModel = true

    /// Where captured audio goes; buffers that arrive while nothing is being transcribed are dropped.
    let gate = InputGate()
    private var session: Session?

    private final class Session {
        var analyzer: SpeechAnalyzer?
        var stream: AsyncStream<AnalyzerInput>.Continuation?
        var collector: Task<Void, Never>?
        var transcript = ""
        var locale: Locale?
    }

    /// How long capture continues after stop, so the last word isn't cut off (the Mac's measured tail).
    static let releaseTail: Duration = .milliseconds(200)
    /// Buffers kept while the analyzer is being set up, about a minute of audio.
    static let bufferedInputs = 256

    var isActive: Bool { session != nil }

    /// Starts transcribing audio in `inputFormat` that is fed to `gate`. `onText` receives the
    /// transcript so far each time it changes; `onPreparing` is told when the speech model has to be
    /// downloaded first.
    func begin(inputFormat: AVAudioFormat, onPreparing: @escaping (String) -> Void = { _ in },
               onText: @escaping (String) -> Void) async throws {
        cancel()
        guard SpeechTranscriber.isAvailable else { throw Failure.unavailable }
        let session = Session()
        self.session = session
        let locale = await Self.bestLocale()
        session.locale = locale
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                            reportingOptions: [.volatileResults], attributeOptions: [])
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            guard downloadsModel else { throw Failure.needsModelDownload }
            onPreparing(String(localized: "Downloading the speech model…"))
            try await request.downloadAndInstall()
        }
        guard self.session === session else { return }
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: inputFormat),
              let converter = AVAudioConverter(from: inputFormat, to: analyzerFormat) else {
            throw Failure.noCompatibleAudioFormat
        }
        guard self.session === session else { return }
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingNewest(Self.bufferedInputs))
        session.stream = continuation
        gate.route(to: InputGate.Route(continuation: continuation, converter: converter, format: analyzerFormat))

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        session.analyzer = analyzer
        let vocabulary = self.vocabulary
        let hints = DictationVocabulary.hints(vocabulary)
        if !hints.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = hints
            try? await analyzer.setContext(context)
        }
        try await analyzer.prepareToAnalyze(in: analyzerFormat)
        try await analyzer.start(inputSequence: stream)
        guard self.session === session else {
            continuation.finish()
            await analyzer.cancelAndFinishNow()
            return
        }

        let removesFillers = self.removesFillers
        let closeMatches = fixesCloseMatches && DictationCleanup.supports(locale) && !vocabulary.isEmpty
        let formats = formatsSpokenText
        let protectedTerms = vocabulary.map(\.term)
        session.collector = Task { @MainActor in
            var settled = ""
            var knownWords: [String: Bool] = [:]
            let isKnown = { (word: String) -> Bool in
                if let known = knownWords[word] { return known }
                let known = SpeechTranscription.spellCheckerKnows(word, locale: locale)
                knownWords[word] = known
                return known
            }
            let clean = { (text: String) in
                let exact = DictationVocabulary.applying(vocabulary, to: removesFillers ? DictationCleanup.removingFillers(text, locale: locale) : text)
                let corrected = closeMatches ? DictationCloseMatch.correcting(vocabulary, in: exact, isKnownWord: isKnown) : exact
                return formats ? DictationFormatting.formattingPhrase(corrected, locale: locale, protectedTerms: protectedTerms) : corrected
            }
            do {
                for try await result in transcriber.results {
                    let text = clean(String(result.text.characters))
                    if result.isFinal {
                        settled += text
                        session.transcript = settled
                    } else {
                        session.transcript = settled + text
                    }
                    onText(session.transcript)
                }
            } catch {}
        }
    }

    /// Stops transcribing and returns the final transcript, or nil when nothing was said. Audio
    /// keeps flowing for `releaseTail` first, so the caller should stop capture only afterwards. A
    /// dictation whose loudest moment stayed below the silence threshold is discarded, so an
    /// accidental tap inserts nothing.
    func finish() async -> String? {
        guard let session else { return nil }
        try? await Task.sleep(for: Self.releaseTail)
        guard self.session === session else { return nil }
        let loudest = gate.route(to: nil)
        session.stream?.finish()
        if DictationLevel.isSilent(loudest: loudest) {
            await session.analyzer?.cancelAndFinishNow()
            session.collector?.cancel()
            self.session = nil
            return nil
        }
        try? await session.analyzer?.finalizeAndFinishThroughEndOfInput()
        _ = await session.collector?.result
        if self.session === session { self.session = nil }
        var text = session.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if formatsSpokenText, let locale = session.locale, !text.isEmpty {
            text = DictationFormatting.formattingTranscript(text, locale: locale)
        }
        return text.isEmpty ? nil : text
    }

    /// Ends the current dictation, if any, without a transcript.
    func cancel() {
        guard let session else { return }
        gate.route(to: nil)
        session.stream?.finish()
        session.collector?.cancel()
        if let analyzer = session.analyzer { Task { await analyzer.cancelAndFinishNow() } }
        self.session = nil
    }

    /// Whether the system spell checker accepts a word in the dictation language. Close matches only
    /// ever replace words it does not know.
    static func spellCheckerKnows(_ word: String, locale: Locale) -> Bool {
        let code = locale.language.languageCode?.identifier ?? "en"
        let language = UITextChecker.availableLanguages.first { $0 == locale.identifier } ??
            UITextChecker.availableLanguages.first { $0.hasPrefix(code) } ?? "en_US"
        let range = UITextChecker().rangeOfMisspelledWord(in: word, range: NSRange(location: 0, length: (word as NSString).length),
                                                          startingAt: 0, wrap: false, language: language)
        return range.location == NSNotFound
    }

    /// The device language when SpeechTranscriber supports it, else US English.
    private static func bestLocale() async -> Locale {
        let supported = await SpeechTranscriber.supportedLocales
        let current = Locale.current
        if supported.contains(where: { $0.identifier(.bcp47) == current.identifier(.bcp47) }) { return current }
        return supported.first { $0.identifier(.bcp47) == "en-US" } ?? current
    }
}

/// Hands audio buffers from the capture thread to the current dictation, if there is one,
/// converted to the analyzer's format and metered for silence. Nothing in `receive` may trap: a
/// trap on the realtime audio thread takes the whole process down.
final class InputGate: Sendable {
    struct Route {
        let continuation: AsyncStream<AnalyzerInput>.Continuation
        let converter: AVAudioConverter
        let format: AVAudioFormat
    }

    private struct State {
        var current: Route?
        var loudest = DictationLevel.floor
        var latest = DictationLevel.floor
    }

    private let state = Mutex(State())

    /// The level of the most recent buffer routed to a dictation, in dBFS, for the waveform.
    var currentLevel: Float {
        state.withLock { $0.current == nil ? DictationLevel.floor : $0.latest }
    }

    /// Sends buffers to a new route, or to none, and returns the loudest level the old route heard.
    @discardableResult
    func route(to route: Route?) -> Float {
        state.withLock { state in
            let heard = state.loudest
            state = State(current: route)
            return heard
        }
    }

    func receive(_ buffer: AVAudioPCMBuffer) {
        var level: Float?
        if let channels = buffer.floatChannelData, buffer.frameLength > 0 {
            level = DictationLevel.decibels(UnsafeBufferPointer(start: channels[0], count: Int(buffer.frameLength)))
        }
        let route: Route? = state.withLock { state in
            guard let current = state.current else { return nil }
            if let level {
                state.latest = level
                if level > state.loudest { state.loudest = level }
            }
            return current
        }
        guard let route, let converted = Self.convert(buffer, using: route.converter, to: route.format) else { return }
        route.continuation.yield(AnalyzerInput(buffer: converted))
    }

    /// Resamples a buffer into the analyzer's format, or returns nil when it cannot.
    /// `AnalyzerInput` traps on a buffer whose format does not match.
    static func convert(_ buffer: AVAudioPCMBuffer, using converter: AVAudioConverter, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
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
}

/// Dictation settings the keyboard needs but cannot read itself, kept in the App Group: the
/// vocabulary the app reads from the Mac's settings sync, filler removal, and whether to record in
/// the keyboard. The app's Settings writes the switches here, so both processes see one value.
enum KeyboardDictationSettings {
    static let removesFillersKey = "dictationRemovesFillers"
    static let recordsInKeyboardKey = "keyboardRecordsInKeyboard"
    static let formatsSpokenTextKey = "dictationFormatsSpokenText"
    /// How the keyboard's last in-keyboard recording went: its date, whether it started, and why not.
    static let recordResultKey = "keyboardRecordResult"

    static var defaults: UserDefaults? { UserDefaults(suiteName: AppGroup.id) }
    private static var vocabularyURL: URL? { AppGroup.container?.appendingPathComponent("keyboard-vocabulary.json") }

    static var removesFillers: Bool { defaults?.object(forKey: removesFillersKey) as? Bool ?? true }
    static var formatsSpokenText: Bool { defaults?.object(forKey: formatsSpokenTextKey) as? Bool ?? true }
    /// On by default; the app switch stays as the fallback either way.
    static var recordsInKeyboard: Bool { defaults?.object(forKey: recordsInKeyboardKey) as? Bool ?? true }

    static func readVocabulary() -> [DictationVocabularyEntry] {
        guard let url = vocabularyURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([DictationVocabularyEntry].self, from: data)) ?? []
    }

    /// Writes the vocabulary when it differs from the stored copy.
    static func writeVocabulary(_ entries: [DictationVocabularyEntry]) {
        guard let url = vocabularyURL, entries != readVocabulary(), let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
