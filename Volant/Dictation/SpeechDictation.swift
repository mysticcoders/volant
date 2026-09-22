import AVFoundation
import Foundation
import VolantCore

#if canImport(Speech)
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

    enum Phase: Equatable {
        case idle, listening, finishing, failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var transcript = ""

    var isListening: Bool { phase == .listening }

    nonisolated static var availability: Availability {
        #if canImport(Speech)
        guard #available(macOS 26.0, *) else { return .unavailable(requiresNewerSystem) }
        guard SpeechTranscriber.isAvailable else {
            return .unavailable("On-device dictation is unavailable on this Mac.")
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted:
            return .unavailable("Microphone access is off. Turn it on in System Settings, Privacy & Security, Microphone.")
        default:
            return .ready
        }
        #else
        return .unavailable(requiresNewerSystem)
        #endif
    }

    private static var requiresNewerSystem: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "Dictation needs macOS 26 or later. This Mac runs macOS \(version.majorVersion).\(version.minorVersion)."
    }

    #if canImport(Speech)
    @available(macOS 26.0, *)
    private final class Session {
        let engine = AVAudioEngine()
        var analyzer: SpeechAnalyzer?
        var transcriber: SpeechTranscriber?
        var stream: AsyncStream<AnalyzerInput>.Continuation?
        var collector: Task<Void, Never>?
    }
    private var session: Any?
    #endif

    /// Starts capture. `finished` receives the final transcript, or nil when nothing was said.
    func start(finished: @escaping (String?) -> Void) {
        guard phase != .listening else { return }
        let availability = Self.availability
        guard availability.isReady else {
            phase = .failed(availability.reason ?? "Dictation is unavailable.")
            finished(nil)
            return
        }
        transcript = ""
        #if canImport(Speech)
        guard #available(macOS 26.0, *) else { phase = .failed(Self.requiresNewerSystem); finished(nil); return }
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard granted else {
                    self.phase = .failed("Dictation needs microphone access.")
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

    #if canImport(Speech)
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
                let analyzer = SpeechAnalyzer(modules: [transcriber])
                session.analyzer = analyzer

                let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
                session.stream = continuation
                let format = session.engine.inputNode.inputFormat(forBus: 0)
                session.engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
                    continuation.yield(AnalyzerInput(buffer: buffer))
                }
                session.engine.prepare()
                try session.engine.start()
                try await analyzer.start(inputSequence: stream)

                session.collector = Task { @MainActor in
                    // Volatile results refine as you speak, so the newest value replaces the last.
                    var settled = ""
                    do {
                        for try await result in transcriber.results {
                            let text = String(result.text.characters)
                            if result.isFinal {
                                settled += text
                                self.transcript = settled
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
                    self.phase = .failed(error.localizedDescription)
                    self.session = nil
                    finished(nil)
                }
            }
        }
    }
    #endif

    /// Stops capture and reports the transcript. Safe to call when not listening.
    func stop(finished: @escaping (String?) -> Void) {
        #if canImport(Speech)
        guard #available(macOS 26.0, *), let session = session as? Session, phase == .listening else {
            finished(nil); return
        }
        phase = .finishing
        session.engine.inputNode.removeTap(onBus: 0)
        session.engine.stop()
        session.stream?.finish()
        Task {
            try? await session.analyzer?.finalizeAndFinishThroughEndOfInput()
            _ = await session.collector?.result
            await MainActor.run {
                self.session = nil
                let text = self.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if case .failed = self.phase {} else { self.phase = .idle }
                finished(text.isEmpty ? nil : text)
            }
        }
        #else
        finished(nil)
        #endif
    }

    func cancel() {
        #if canImport(Speech)
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

    #if canImport(Speech)
    @available(macOS 26.0, *)
    private static func bestLocale() async -> Locale {
        let supported = await SpeechTranscriber.supportedLocales
        let current = Locale.current
        if supported.contains(where: { $0.identifier(.bcp47) == current.identifier(.bcp47) }) { return current }
        return supported.first { $0.identifier(.bcp47) == "en-US" } ?? current
    }
    #endif
}
