import Foundation

/// Why an ACP turn stopped, as far as Volant can tell. ACP defines no stop reason for a provider's
/// usage limit, so Volant reads the text of the message a turn stopped or failed with.
public enum ACPStopReason {
    /// Phrases a provider's message uses when an account has run out of usage. Matched ignoring
    /// case, with hyphens read as spaces. A provider that words its limit differently is shown as
    /// failed or stopped.
    public static let usageLimitPhrases = ["usage limit", "rate limit", "limit reached", "quota exceeded", "out of credits"]

    /// Whether `text`, the message a turn stopped or failed with, reports a provider usage limit.
    public static func isUsageLimit(_ text: String) -> Bool {
        let folded = text.lowercased().replacingOccurrences(of: "-", with: " ")
        return usageLimitPhrases.contains { folded.contains($0) }
    }
}
