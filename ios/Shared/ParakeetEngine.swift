import CoreML
import Darwin
import FluidAudio
import Foundation

/// The optional Parakeet speech model: Parakeet Ultra (Moondream's retraining of NVIDIA Parakeet
/// TDT 0.6B v3, 25 European languages, CC BY 4.0) as FluidAudio's Core ML build, about 595 MB,
/// downloaded once into the App Group so the app and the keyboard share one copy. Off by default;
/// when on and downloaded, Apple's engine still shows words while the owner speaks and Parakeet
/// writes the final text from the recording. Nothing leaves the device but the download itself.
enum ParakeetModel {
    static let version: AsrModelVersion = .ultra
    static let enabledKey = "dictationUsesParakeet"
    static let approximateSize = "595 MB"

    static var isEnabled: Bool { KeyboardDictationSettings.defaults?.bool(forKey: enabledKey) ?? false }

    /// The model's folder in the App Group: the Hugging Face repo folder FluidAudio expects.
    static var directory: URL? {
        AppGroup.container?.appendingPathComponent("Models/parakeet-ultra-coreml", isDirectory: true)
    }

    static var isDownloaded: Bool {
        directory.map { AsrModels.modelsExist(at: $0, version: version) } ?? false
    }

    /// Removes the downloaded model.
    static func delete() throws {
        guard let directory, FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }
}

/// Parakeet in this process, loaded once and kept while the process lives. In the keyboard it loads
/// and transcribes only within `ParakeetBudget`, measured by Hex on an iPhone 17 Pro: the model
/// itself sits on the Neural Engine outside the keyboard's memory limit, but its first load and
/// each transcription raise the keyboard's own footprint. Any failure leaves Apple's transcript.
@MainActor
final class ParakeetTranscriber {
    static let shared = ParakeetTranscriber()

    /// What one dictation's Parakeet pass did, for the dictation log; never what was said.
    struct Result {
        var text: String?
        var note: String
    }

    private var manager: AsrManager?
    private var loading: Task<Void, Never>?
    private var loadNote: String?

    private init() {}

    /// Starts loading the downloaded model if it is enabled and fits, so a dictation does not wait
    /// for the first load (about 12 s the first time Core ML prepares it on a device, then well
    /// under a second).
    func warmUp(inKeyboard: Bool) {
        guard manager == nil, loading == nil, ParakeetModel.isEnabled, let directory = ParakeetModel.directory,
              ParakeetModel.isDownloaded else { return }
        if inKeyboard, !ParakeetBudget.allowsLoad() {
            loadNote = String(localized: "not enough memory in the keyboard to load")
            return
        }
        let started = ContinuousClock.now
        loading = Task { [weak self] in
            do {
                let models = try await AsrModels.load(from: directory, version: ParakeetModel.version)
                let manager = AsrManager(config: .default)
                try await manager.loadModels(models)
                self?.manager = manager
                self?.loadNote = String(localized: "loaded in \(Self.milliseconds(since: started)) ms")
            } catch {
                self?.loadNote = String(localized: "could not load: \(error.localizedDescription)")
            }
            self?.loading = nil
        }
    }

    /// The text of `samples` (16 kHz mono), or nil with the reason Apple's transcript stays.
    func transcribe(_ samples: [Float], inKeyboard: Bool) async -> Result {
        let seconds = Double(samples.count) / 16_000
        guard let manager else {
            return Result(text: nil, note: loading != nil ? String(localized: "still loading") : (loadNote ?? String(localized: "not loaded")))
        }
        guard seconds <= ParakeetBudget.longestAudio else {
            return Result(text: nil, note: String(localized: "longer than \(Int(ParakeetBudget.longestAudio)) s"))
        }
        if inKeyboard, !ParakeetBudget.allowsTranscription(seconds: seconds) {
            return Result(text: nil, note: String(localized: "not enough memory in the keyboard to transcribe"))
        }
        let started = ContinuousClock.now
        do {
            var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
            let text = try await manager.transcribe(samples, decoderState: &state).text
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let elapsed = Self.milliseconds(since: started)
            return text.isEmpty
                ? Result(text: nil, note: String(localized: "heard nothing (\(elapsed) ms)"))
                : Result(text: text, note: String(localized: "transcribed in \(elapsed) ms"))
        } catch {
            return Result(text: nil, note: String(localized: "failed: \(error.localizedDescription)"))
        }
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        let elapsed = (ContinuousClock.now - start).components
        return Int(elapsed.seconds) * 1000 + Int(elapsed.attoseconds / 1_000_000_000_000_000)
    }
}

/// How much keyboard memory Parakeet needs, from Hex's measurements in its keyboard on an iPhone 17
/// Pro on iOS 27.2 (limit 177 MB): the first load raised the footprint 42 MB, a transcription 16 MB
/// plus about half a megabyte per second of audio while the recording is held. Volant asks for the
/// same room left before each, and caps a keyboard dictation Parakeet transcribes at 90 seconds.
enum ParakeetBudget {
    static let megabyte = 1_048_576
    static let loadHeadroom = 58 * megabyte
    static let transcribeHeadroom = 24 * megabyte
    static let audioCostPerSecond = megabyte / 2
    static let longestAudio: TimeInterval = 90

    /// Memory iOS still allows this process; 0 where it sets no limit, such as the simulator.
    static var available: Int { os_proc_available_memory() }

    static func allowsLoad() -> Bool {
        available == 0 || available >= loadHeadroom
    }

    static func allowsTranscription(seconds: Double) -> Bool {
        available == 0 || available >= transcribeHeadroom + Int(seconds * Double(audioCostPerSecond))
    }
}
