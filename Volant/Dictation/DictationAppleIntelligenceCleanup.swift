import Foundation
import Synchronization
import VolantCore

#if canImport(FoundationModels)
import FoundationModels
#endif

/// One conservative pass of Apple's on-device model over a finished dictation: spoken
/// self-corrections ("Tuesday, no wait, Wednesday") resolved and repeats dropped. The answer
/// replaces the transcript only when `DictationEditCheck` can verify every change, and only within
/// `DictationAICleanup.timeBudget`; otherwise the transcript stays as heard. Nothing leaves the Mac.
/// Off by default (`Preferences.dictationCleansUpWithAppleIntelligence`); adapted from Hex.
enum DictationAppleIntelligenceCleanup {
    /// The cleaned transcript, or nil to keep it as heard: Apple Intelligence unavailable, the
    /// language unsupported, the budget run out, or the answer rejected.
    static func clean(_ text: String, locale: Locale, vocabulary: [String] = []) async -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, AppleFoundationModel.availability.isReady else { return nil }
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *), SystemLanguageModel.default.supportsLocale(locale) else { return nil }
        return DictationAICleanup.accepted(await respond(to: trimmed), for: trimmed, vocabulary: vocabulary)
        #else
        return nil
        #endif
    }

    #if canImport(FoundationModels)
    /// Races the model against the budget. A late answer is dropped rather than awaited, and the
    /// model's task is cancelled when the budget wins.
    @available(macOS 26.0, *)
    private static func respond(to text: String) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let once = ResumeOnce(continuation)
            let work = Task {
                let session = LanguageModelSession(model: .default, instructions: DictationAICleanup.instructions)
                let options = GenerationOptions(temperature: DictationAICleanup.temperature,
                                                maximumResponseTokens: DictationAICleanup.maximumResponseTokens)
                once.resume(try? await session.respond(to: text, options: options).content)
            }
            Task {
                try? await Task.sleep(for: DictationAICleanup.timeBudget)
                work.cancel()
                once.resume(nil)
            }
        }
    }
    #endif
}

/// Resumes a continuation for the first caller only, whichever of the model or the budget is first.
private final class ResumeOnce: Sendable {
    private let continuation: Mutex<CheckedContinuation<String?, Never>?>

    init(_ continuation: CheckedContinuation<String?, Never>) {
        self.continuation = Mutex(continuation)
    }

    func resume(_ value: String?) {
        let pending = continuation.withLock { stored -> CheckedContinuation<String?, Never>? in
            defer { stored = nil }
            return stored
        }
        pending?.resume(returning: value)
    }
}
