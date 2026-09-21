import Foundation
import VolantCore

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device model, reached through FoundationModels. It needs no network, no API key and
/// no helper process, so unlike BYOK and local servers this runs inside the sandboxed app itself.
///
/// The framework is macOS 26 and later while Volant supports macOS 15, so every entry point is
/// gated and the feature is absent rather than broken on older systems. `Availability` is what the
/// rest of the app asks; it never needs to know whether the framework exists.
enum AppleFoundationModel {
    enum Availability: Equatable {
        case ready
        /// The reason is shown verbatim, so it has to explain what the owner can do about it.
        case unavailable(String)

        var isReady: Bool { self == .ready }
        var reason: String? { if case .unavailable(let text) = self { return text }; return nil }
    }

    /// The minimum macOS that ships FoundationModels.
    static let minimumSystemVersion = "26.0"

    static var availability: Availability {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else { return .unavailable(requiresNewerSystem) }
        switch SystemLanguageModel.default.availability {
        case .available:
            return .ready
        case .unavailable(.deviceNotEligible):
            return .unavailable("This Mac does not support Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Turn on Apple Intelligence in System Settings to use this.")
        case .unavailable(.modelNotReady):
            return .unavailable("Apple Intelligence is still downloading its model. Try again shortly.")
        case .unavailable:
            return .unavailable("Apple Intelligence is unavailable on this Mac right now.")
        }
        #else
        return .unavailable(requiresNewerSystem)
        #endif
    }

    private static var requiresNewerSystem: String {
        "Apple Intelligence needs macOS \(minimumSystemVersion) or later. This Mac runs macOS \(systemVersion)."
    }

    static var systemVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion)"
    }

    /// A single conversation. Transcript ownership stays with the caller, matching the other
    /// connection kinds: nothing here is written to disk.
    final class Conversation {
        #if canImport(FoundationModels)
        @available(macOS 26.0, *)
        private final class Box {
            let session = LanguageModelSession()
            var task: Task<Void, Never>?
        }
        private let box: Any?
        #endif

        init() {
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) { box = Box() } else { box = nil }
            #endif
        }

        /// Streams a reply on the main queue. `snapshot` carries the complete text so far, not a
        /// delta: FoundationModels emits cumulative values that grow, repeat, and may be rewritten,
        /// so the caller replaces its assistant message rather than appending. `finished` reports
        /// the outcome once, and a cancelled turn reports no error, matching a cancelled ACP turn.
        func send(_ prompt: String,
                  snapshot: @escaping (String) -> Void,
                  finished: @escaping (String?) -> Void) {
            #if canImport(FoundationModels)
            guard #available(macOS 26.0, *), let box = box as? Box else {
                finished(requiresNewerSystem); return
            }
            box.task?.cancel()
            box.task = Task {
                do {
                    var delivered = ""
                    for try await chunk in box.session.streamResponse(to: prompt) {
                        if Task.isCancelled { return }
                        let text = chunk.content
                        guard text != delivered else { continue }
                        delivered = text
                        await MainActor.run { snapshot(text) }
                    }
                    if Task.isCancelled { return }
                    await MainActor.run { finished(nil) }
                } catch {
                    if Task.isCancelled { return }
                    await MainActor.run { finished(error.localizedDescription) }
                }
            }
            #else
            finished(requiresNewerSystem)
            #endif
        }

        func cancel() {
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *), let box = box as? Box {
                box.task?.cancel()
                box.task = nil
            }
            #endif
        }
    }
}
