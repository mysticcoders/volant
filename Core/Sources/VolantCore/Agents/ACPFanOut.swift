import Foundation

/// Plans Send to Several: one new ACP conversation per target, each sent the same prompt once.
/// Pure, so its rules are tested without the app or the helper.
public enum ACPFanOut {
    /// How many conversations one send may start when the settings give no number.
    public static let defaultLimit = 4
    /// The range `AIConfiguration.fanOut` is clamped to. More than the live limit could never run
    /// at once.
    public static let limits = 2...ACPConversationLimit.live
    /// The helper's limit for one prompt, checked here so an oversized draft starts nothing.
    public static let promptLimit = 64_000

    public static func clamp(_ value: Int) -> Int {
        min(max(value, limits.lowerBound), limits.upperBound)
    }

    /// Why a send was refused before any conversation started.
    public struct Refusal: LocalizedError, Equatable {
        public let message: String
        public init(_ message: String) { self.message = message }
        public var errorDescription: String? { message }
    }

    /// One configuration per target, in `ACPProvider.allCases` order: `configuration` with the
    /// target's provider. With a working folder every target runs in its own workspace, whatever the
    /// Isolated workspace setting says, because agents editing one checkout change the same files.
    /// Throws a `Refusal` for a connection other than ACP, an empty or oversized prompt, no target,
    /// or more targets than `configuration.fanOut` allows.
    public static func targets(prompt: String, counts: [ACPProvider: Int], configuration: AIConfiguration) throws -> [AIConfiguration] {
        guard configuration.connection == .acp else { throw Refusal("Send to Several starts ACP agents. Choose ACP in AI Settings.") }
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Refusal("Write a prompt first.") }
        guard prompt.utf8.count <= promptLimit else { throw Refusal("Enter a prompt of at most 64 KB.") }
        let limit = clamp(configuration.fanOut)
        guard counts.values.allSatisfy({ $0 >= 0 }) else { throw Refusal("Choose how many of each agent to start.") }
        // Each count is checked before the sum, so no count can overflow it.
        guard counts.values.allSatisfy({ $0 <= limit }) else { throw Refusal("Choose at most \(limit) agents.") }
        let total = counts.values.reduce(0, +)
        guard total > 0 else { throw Refusal("Choose at least one agent.") }
        guard total <= limit else { throw Refusal("Choose at most \(limit) agents.") }
        return ACPProvider.allCases.flatMap { provider -> [AIConfiguration] in
            var target = configuration
            target.provider = provider.rawValue
            target.isolate = !configuration.project.isEmpty
            return Array(repeating: target, count: counts[provider] ?? 0)
        }
    }
}
