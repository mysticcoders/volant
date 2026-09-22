import Foundation

extension HerdrQuestion {
    /// Codex asks two different kinds of question. `parse` handles the numbered survey form with
    /// its "Question 1/1 (1 unanswered)" header; this handles the approval form, which has no such
    /// header and lists its options in a single column.
    ///
    /// Approving one of these runs a command, so the guards match the Claude approval path: the
    /// prompt and the whole command block must be present and unclipped, exactly one option may be
    /// marked, and anything unrecognized is refused rather than guessed at.
    static func parseCodexApproval(_ text: String) -> Self? {
        let raw = text.components(separatedBy: "\n")
        let lines = raw.map { $0.trimmingCharacters(in: .whitespaces) }
        guard let footer = lines.lastIndex(where: { !$0.isEmpty }), isCodexFooter(lines[footer]) else { return nil }

        let rowPattern = try! NSRegularExpression(pattern: #"^(› |❯ )?([1-9])\. (.+)$"#)
        func row(_ line: String) -> (number: Int, label: String, selected: Bool)? {
            let ns = line as NSString
            guard let match = rowPattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
                  let number = Int(ns.substring(with: match.range(at: 2))) else { return nil }
            return (number, ns.substring(with: match.range(at: 3)), match.range(at: 1).location != NSNotFound)
        }
        guard let first = lines[..<footer].lastIndex(where: { row($0)?.number == 1 }) else { return nil }

        var choices: [Choice] = [], selected: Int?
        for index in first..<footer {
            let line = lines[index]
            if line.isEmpty { continue }
            if let parsed = row(line) {
                guard parsed.number == choices.count + 1 else { return nil }
                if parsed.selected {
                    guard selected == nil else { return nil }
                    selected = parsed.number
                }
                choices.append(Choice(number: parsed.number, label: parsed.label, detail: ""))
            } else {
                // A wrapped option continues its label; anything else means this is not the form.
                guard let previous = choices.popLast(), raw[index].prefix(while: { $0 == " " }).count >= 4 else { return nil }
                choices.append(Choice(number: previous.number, label: previous.label + " " + line, detail: ""))
            }
        }
        guard let selected, (2...8).contains(choices.count) else { return nil }

        guard let prompt = lines[..<first].lastIndex(where: { isCodexApprovalPrompt($0) }) else { return nil }
        let context = raw[prompt..<first].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        // Never offer a one-key approval for a command that is only partly shown.
        guard !context.contains("…"), !context.contains("...") else { return nil }
        guard lines[prompt].count <= 500 else { return nil }
        return Self(title: lines[prompt], progress: "Codex approval", choices: choices, selected: selected, context: context)
    }

    /// The prompt wording Herdr's `codex.toml` recognizes, plus the run-command phrasing observed
    /// in the approval screens themselves. Substrings, so a reworded prompt keeps matching.
    static func isCodexApprovalPrompt(_ line: String) -> Bool {
        footerContains(line, ["would you like to run", "allow command?", "do you want to"])
    }
}
