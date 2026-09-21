import Foundation

extension HerdrQuestion {
    /// Only complete, observed Claude single-question and file-approval screens.
    static func parseClaude(_ text: String) -> Self? {
        let raw = text.components(separatedBy: "\n")
        let lines = raw.map { $0.trimmingCharacters(in: .whitespaces) }
        guard let footer = lines.lastIndex(where: { !$0.isEmpty }) else { return nil }
        let permission = isClaudeApprovalFooter(lines[footer])
        guard permission || isClaudeSelectFooter(lines[footer]) else { return nil }
        let rowPattern = try! NSRegularExpression(pattern: #"^(❯ )?([1-9])\. (.+)$"#)
        func row(_ line: String) -> (Int, String, Bool)? {
            let ns = line as NSString
            guard let match = rowPattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
                  let number = Int(ns.substring(with: match.range(at: 2))) else { return nil }
            return (number, ns.substring(with: match.range(at: 3)), match.range(at: 1).location != NSNotFound)
        }
        guard let first = lines[..<footer].lastIndex(where: { row($0)?.0 == 1 }) else { return nil }
        var choices: [Choice] = [], selected: Int?
        for index in first..<footer {
            let line = lines[index]
            if line.isEmpty || line.allSatisfy({ $0 == "─" }) { continue }
            if let (number, label, highlighted) = row(line) {
                guard number == choices.count + 1 else { return nil }
                if highlighted {
                    guard selected == nil else { return nil }
                    selected = number
                }
                choices.append(Choice(number: number, label: label, detail: ""))
            } else {
                guard let previous = choices.popLast(), raw[index].prefix(while: { $0 == " " }).count >= 5 else { return nil }
                choices.append(Choice(number: previous.number,
                    label: permission ? previous.label + " " + line : previous.label,
                    detail: permission ? "" : [previous.detail, line].filter { !$0.isEmpty }.joined(separator: "\n")))
            }
        }
        guard let selected, (2...8).contains(choices.count) else { return nil }
        if permission {
            guard choices.first?.label == "Yes", choices.last?.label == "No",
                  let questionLine = lines[..<first].lastIndex(where: { !$0.isEmpty }),
                  let start = lines[..<questionLine].lastIndex(where: { ["Create file", "Bash command"].contains($0) }),
                  questionLine - start >= 3 else { return nil }
            let context = raw[start..<questionLine].joined(separator: "\n")
            // Never approve clipped content or an unrecognized approval type.
            guard !context.contains("…"), !context.contains("...") else { return nil }
            if lines[start] == "Create file" {
                guard lines[questionLine].hasPrefix("Do you want to create "), lines[questionLine].hasSuffix("?"),
                      lines[start..<questionLine].filter({ $0.hasPrefix("╌╌╌") }).count == 2 else { return nil }
            } else {
                guard lines[questionLine] == "Do you want to proceed?",
                      lines[(start + 1)..<questionLine].contains(where: { !$0.isEmpty }) else { return nil }
            }
            return Self(title: lines[questionLine], progress: "Claude " + lines[start], choices: choices, selected: selected, context: context)
        }
        guard choices.count >= 4, choices.suffix(2).map(\.label) == ["Type something.", "Chat about this"],
              let header = lines[..<first].lastIndex(where: { $0.hasPrefix("☐ ") }),
              lines[header].filter({ $0 == "☐" || $0 == "✓" }).count == 1 else { return nil }
        let title = lines[(header + 1)..<first].filter { !$0.isEmpty }.joined(separator: " ")
        guard !title.isEmpty, title.count <= 500 else { return nil }
        return Self(title: title, progress: lines[header], choices: choices, selected: selected)
    }
}
