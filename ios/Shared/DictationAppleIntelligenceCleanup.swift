import Foundation
import FoundationModels
import Synchronization
import VolantCore

/// One conservative pass of Apple's on-device model over a finished dictation on iPhone: spoken
/// self-corrections ("Tuesday, no wait, Wednesday") resolved and repeats dropped. The answer
/// replaces the transcript only when `DictationEditCheck` can verify every change, and only within
/// `DictationAICleanup.timeBudget`; otherwise the transcript stays as heard. Nothing leaves the
/// device. Shared by the app and the keyboard; off by default.
///
/// The model may need to load first, which can take longer than the budget on its own, so
/// `prepare()` prewarms a session when dictation starts and `clean` answers with that session.
@MainActor
enum DictationAppleIntelligenceCleanup {
    /// What a cleanup did, for the dictation log.
    struct Result {
        enum Outcome: String {
            case accepted, unchanged, rejected, timedOut, failed, unavailable, unsupportedLanguage
        }

        var text: String?
        var outcome: Outcome
        var milliseconds: Int

        /// A short account for Settings, never including what was said.
        var summary: String {
            switch outcome {
            case .accepted: String(localized: "cleaned up in \(milliseconds) ms")
            case .unchanged: String(localized: "nothing to clean up (\(milliseconds) ms)")
            case .rejected: String(localized: "cleanup rejected by the edit check (\(milliseconds) ms)")
            case .timedOut: String(localized: "cleanup took longer than \(milliseconds) ms")
            case .failed: String(localized: "cleanup failed (\(milliseconds) ms)")
            case .unavailable: String(localized: "cleanup unavailable: \(DictationAppleIntelligenceCleanup.unavailableReason ?? "")")
            case .unsupportedLanguage: String(localized: "cleanup does not support this language")
            }
        }
    }

    private static var prepared: LanguageModelSession?

    /// Why the pass cannot run on this device, in words for Settings, or nil when it can.
    nonisolated static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(.deviceNotEligible): String(localized: "This device does not support Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled): String(localized: "Turn on Apple Intelligence in Settings to use this.")
        case .unavailable(.modelNotReady): String(localized: "Apple Intelligence is still downloading its model. Try again shortly.")
        case .unavailable: String(localized: "Apple Intelligence is unavailable right now.")
        }
    }

    /// Loads the model into a session while the owner is still speaking.
    static func prepare() {
        guard prepared == nil, unavailableReason == nil else { return }
        let session = LanguageModelSession(model: .default, instructions: DictationAICleanup.instructions)
        session.prewarm()
        prepared = session
    }

    /// The cleaned transcript, if any, and what happened.
    static func clean(_ text: String, locale: Locale, vocabulary: [String] = []) async -> Result {
        let started = ContinuousClock.now
        func result(_ text: String?, _ outcome: Result.Outcome) -> Result {
            let elapsed = (ContinuousClock.now - started).components
            return Result(text: text, outcome: outcome,
                          milliseconds: Int(elapsed.seconds) * 1000 + Int(elapsed.attoseconds / 1_000_000_000_000_000))
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard unavailableReason == nil else { return result(nil, .unavailable) }
        guard SystemLanguageModel.default.supportsLocale(locale) else { return result(nil, .unsupportedLanguage) }
        let session = prepared ?? LanguageModelSession(model: .default, instructions: DictationAICleanup.instructions)
        prepared = nil
        switch await respond(to: trimmed, with: session) {
        case .timedOut: return result(nil, .timedOut)
        case .failed: return result(nil, .failed)
        case .answer(let answer):
            if answer.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed { return result(nil, .unchanged) }
            guard let cleaned = DictationAICleanup.accepted(answer, for: trimmed, vocabulary: vocabulary) else { return result(nil, .rejected) }
            return result(cleaned, .accepted)
        }
    }

    enum Reply: Sendable {
        case answer(String)
        case failed
        case timedOut
    }

    /// Races the model against the budget. A late answer is dropped rather than awaited, and the
    /// model's task is cancelled when the budget wins.
    private static func respond(to text: String, with session: LanguageModelSession) async -> Reply {
        await withCheckedContinuation { (continuation: CheckedContinuation<Reply, Never>) in
            let once = ResumeOnce(continuation)
            let work = Task {
                let options = GenerationOptions(temperature: DictationAICleanup.temperature,
                                                maximumResponseTokens: DictationAICleanup.maximumResponseTokens)
                if let content = try? await session.respond(to: text, options: options).content {
                    once.resume(.answer(content))
                } else {
                    once.resume(.failed)
                }
            }
            Task {
                try? await Task.sleep(for: DictationAICleanup.timeBudget)
                work.cancel()
                once.resume(.timedOut)
            }
        }
    }
}

/// Resumes a continuation for the first caller only, whichever of the model or the budget is first.
private final class ResumeOnce: Sendable {
    private let continuation: Mutex<CheckedContinuation<DictationAppleIntelligenceCleanup.Reply, Never>?>

    init(_ continuation: CheckedContinuation<DictationAppleIntelligenceCleanup.Reply, Never>) {
        self.continuation = Mutex(continuation)
    }

    func resume(_ value: DictationAppleIntelligenceCleanup.Reply) {
        let pending = continuation.withLock { stored -> CheckedContinuation<DictationAppleIntelligenceCleanup.Reply, Never>? in
            defer { stored = nil }
            return stored
        }
        pending?.resume(returning: value)
    }
}
