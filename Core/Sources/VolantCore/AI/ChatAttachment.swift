import Foundation

/// A snapshot of something the owner chose to attach to a chat prompt. The text is copied at the
/// moment of choosing, so editing the note or copying something else afterwards does not change
/// what is sent. Attachments live in memory only.
public struct ChatAttachment: Codable, Equatable, Identifiable {
    public enum Kind: String, Codable { case clipboard, note }

    public let id: String
    public let kind: Kind
    public let title: String
    public let detail: String
    public let text: String

    public init(id: String, kind: Kind, title: String, detail: String, text: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.text = text
    }

    public var mimeType: String { kind == .note ? "text/markdown" : "text/plain" }
    public var size: Int { text.utf8.count }
    /// A stable name for the resource; agents see it but cannot resolve it, which is why the text
    /// always travels with it.
    public var uri: String {
        "volant://\(kind.rawValue)/" + (id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])) ?? "item")
    }
}

/// Limits sized to fit the existing 64 KB prompt limit with room for the prompt itself. Apple's
/// on-device model has a much smaller context window, so it gets a much smaller budget.
public enum ChatAttachmentLimits {
    public static let perItem = 32_000
    public static let total = 48_000
    public static let count = 8
    public static let appleTotal = 6_000

    /// Returns the reason a set of attachments cannot be sent, or nil when it can. Oversized items
    /// are refused rather than cut short, so an agent never answers from a silently truncated note.
    public static func problem(_ attachments: [ChatAttachment], apple: Bool = false) -> String? {
        guard attachments.count <= count else { return "Attach at most \(count) items." }
        if let large = attachments.first(where: { $0.size > perItem }) {
            return "“\(large.title)” is too large to attach (over \(perItem / 1000) KB)."
        }
        let budget = apple ? appleTotal : total
        guard attachments.reduce(0, { $0 + $1.size }) <= budget else {
            return apple ? "Apple Intelligence can take about \(appleTotal / 1000) KB of attachments. Remove one and try again."
                         : "Attachments are limited to \(total / 1000) KB in one message. Remove one and try again."
        }
        return nil
    }
}

/// Turns a prompt and its attachments into what each kind of connection accepts.
public enum ChatPromptComposer {
    /// For connections without structured context: each attachment in a labeled block before the
    /// prompt. A closing tag inside the content is escaped so it cannot end its block early.
    public static func inline(prompt: String, attachments: [ChatAttachment]) -> String {
        guard !attachments.isEmpty else { return prompt }
        let blocks = attachments.map { attachment in
            let title = attachment.title.replacingOccurrences(of: "\"", with: "'")
            let body = attachment.text.replacingOccurrences(of: "</attachment>", with: "<\\/attachment>")
            return "<attachment kind=\"\(attachment.kind.rawValue)\" title=\"\(title)\">\n\(body)\n</attachment>"
        }
        return blocks.joined(separator: "\n\n") + "\n\n" + prompt
    }

    /// ACP prompt content. Agents that declare `embeddedContext` receive each attachment as a
    /// resource block; every other agent receives the inline form as one text block, which the
    /// protocol requires all agents to accept.
    public static func acpBlocks(prompt: String, attachments: [ChatAttachment], embeddedContext: Bool) -> [[String: Any]] {
        guard !attachments.isEmpty else { return [["type": "text", "text": prompt]] }
        guard embeddedContext else { return [["type": "text", "text": inline(prompt: prompt, attachments: attachments)]] }
        return attachments.map { attachment in
            ["type": "resource", "resource": ["uri": attachment.uri, "mimeType": attachment.mimeType, "text": attachment.text]]
        } + [["type": "text", "text": prompt]]
    }

    /// Reads `promptCapabilities.embeddedContext` from the agent's advertised capabilities.
    public static func supportsEmbeddedContext(capabilities: String) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: Data(capabilities.utf8)) as? [String: Any],
              let prompt = object["promptCapabilities"] as? [String: Any] else { return false }
        return prompt["embeddedContext"] as? Bool ?? false
    }
}
