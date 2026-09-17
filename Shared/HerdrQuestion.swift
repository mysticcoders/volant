import Foundation
import CryptoKit

/// A verified provider question or approval screen, never an arbitrary terminal command.
struct HerdrQuestion: Codable, Equatable {
    struct Choice: Codable, Equatable, Identifiable {
        let number: Int
        let label: String
        let detail: String
        var id: Int { number }
    }
    let title: String
    let progress: String
    let choices: [Choice]
    let selected: Int
    var context: String? = nil
    var fingerprint: String {
        let content = [progress, title, context ?? ""] + choices.map { "\($0.number):\($0.label):\($0.detail)" }
        return SHA256.hash(data: Data(content.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func parse(_ text: String, provider: String) -> Self? {
        guard text.utf8.count <= 128_000 else { return nil }
        if provider == "claude" { return parseClaude(text) }
        guard provider == "codex" else { return nil }
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let header = lines.lastIndex(where: { $0.range(of: #"^Question [1-9][0-9]*/[1-9][0-9]* \([1-9][0-9]* unanswered\)$"#, options: .regularExpression) != nil }),
              let footer = lines[(header + 1)...].firstIndex(of: "tab to add notes | enter to submit answer | esc to interrupt"),
              lines[(footer + 1)...].allSatisfy({ $0.isEmpty }) else { return nil }
        let body = lines[(header + 1)..<footer].filter { !$0.isEmpty }
        guard let title = body.first, title.count <= 500 else { return nil }
        let pattern = try! NSRegularExpression(pattern: #"^(› )?([1-9])\. (.+?)\s{2,}(.+)$"#)
        var choices: [Choice] = [], selected: Int?
        for line in body.dropFirst() {
            let ns = line as NSString
            guard let match = pattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
            let number = Int(ns.substring(with: match.range(at: 2)))!
            guard number == choices.count + 1 else { return nil }
            if match.range(at: 1).location != NSNotFound {
                guard selected == nil else { return nil }
                selected = number
            }
            choices.append(Choice(number: number, label: ns.substring(with: match.range(at: 3)), detail: ns.substring(with: match.range(at: 4))))
        }
        guard (2...8).contains(choices.count), let selected,
              choices.last?.label == "None of the above" else { return nil }
        // Notes require their own form. Never turn that row into an implicit blank answer.
        return Self(title: title, progress: lines[header], choices: choices, selected: selected)
    }
    var displayContext: String? {
        context.map { text in
            text.components(separatedBy: "\n").filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty || !trimmed.allSatisfy { $0 == "─" || $0 == "╌" }
            }.joined(separator: "\n")
        }
    }
    var answerChoices: [Choice] { choices.filter { !["None of the above", "Type something.", "Chat about this"].contains($0.label) } }
}
