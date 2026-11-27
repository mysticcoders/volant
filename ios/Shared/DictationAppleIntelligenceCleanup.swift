import Foundation
import FoundationModels
import Synchronization
import VolantCore

/// One conservative pass of Apple's on-device model over a finished dictation on iPhone: spoken
/// self-corrections ("Tuesday, no wait, Wednesday") resolved and repeats dropped. The answer
/// replaces the transcript only when `DictationEditCheck` can verify every change, and only within
/// `DictationAICleanup.timeBudget`; otherwise the transcript stays as heard. Nothing leaves the
/// device. Shared by the app and the keyboard; off by default.
enum DictationAppleIntelligenceCleanup {
    /// Why the pass cannot run on this device, in words for Settings, or nil when it can.
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(.deviceNotEligible): String(localized: "This device does not support Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled): String(localized: "Turn on Apple Intelligence in Settings to use this.")
        case .unavailable(.modelNotReady): String(localized: "Apple Intelligence is still downloading its model. Try again shortly.")
        case .unavailable: String(localized: "Apple Intelligence is unavailable right now.")
        }
    }

    /// The cleaned transcript, or nil to keep it as heard: Apple Intelligence unavailable, the
    /// language unsupported, the budget run out, or the answer rejected.
    static func clean(_ text: String, locale: Locale, vocabulary: [String] = []) async -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, unavailableReason == nil, SystemLanguageModel.default.supportsLocale(locale) else { return nil }
        return DictationAICleanup.accepted(await respond(to: trimmed), for: trimmed, vocabulary: vocabulary)
    }

    /// Races the model against the budget. A late answer is dropped rather than awaited, and the
    /// model's task is cancelled when the budget wins.
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
