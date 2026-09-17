import Foundation

/// Serialized by the helper queue. Every displayed question receives a single-use response token.
final class HerdrResponseController {
    struct Snapshot: Codable {
        let text: String
        let token: String?
        let question: HerdrQuestion?
    }
    private struct Pending {
        let target: AgentSession
        let fingerprint: String
        let created: Date
    }
    private var pending: [String: Pending] = [:]
    private var consumed: [String: String] = [:]
    var now: () -> Date = Date.init
    let run: (HerdrMachine?, [String]) throws -> Data
    init(run: @escaping ([String]) throws -> Data) { self.run = { _, args in try run(args) } }
    init(runOnMachine: @escaping (HerdrMachine?, [String]) throws -> Data) { self.run = runOnMachine }
    private func validate(_ target: AgentSession) throws {
        guard !target.paneID.isEmpty, !target.paneID.hasPrefix("-"), target.paneID.count < 128,
              let current = try AgentSession.decodeList(run(target.machine, ["agent", "list"]), machine: target.machine).first(where: {
                  $0.id == target.id && $0.sessionIdentity == target.sessionIdentity && $0.agentStatus == "blocked"
              }), current.stateChangeSequence == target.stateChangeSequence else {
            throw failure("This pane or question changed. Refresh before answering.")
        }
    }
    private func screen(_ target: AgentSession) throws -> String {
        try validate(target)
        let data = try run(target.machine, ["agent", "read", target.paneID, "--source", "detection", "--lines", "80", "--format", "text"])
        guard data.count <= 128_000, let text = String(data: data, encoding: .utf8) else { throw failure("Couldn’t read the current question.") }
        try validate(target)
        return text
    }
    func read(_ target: AgentSession) throws -> Snapshot {
        let text = try screen(target), question = HerdrQuestion.parse(text, provider: target.agent)
        pending = pending.filter { now().timeIntervalSince($0.value.created) < 30 }
        guard let question else { return Snapshot(text: text, token: nil, question: nil) }
        let identity = target.id + ":" + target.sessionIdentity + ":" + String(target.stateChangeSequence ?? 0) + ":" + question.fingerprint
        guard consumed[target.id] != identity else { return Snapshot(text: text, token: nil, question: question) }
        pending = pending.filter { $0.value.target.id != target.id }
        let token = UUID().uuidString
        pending[token] = Pending(target: target, fingerprint: question.fingerprint, created: now())
        return Snapshot(text: text, token: token, question: question)
    }
    func respond(token: String, choice: Int) throws -> String {
        guard let request = pending.removeValue(forKey: token), now().timeIntervalSince(request.created) < 30 else {
            throw failure("This response expired or was already sent. Refresh the question.")
        }
        let target = request.target
        guard let question = HerdrQuestion.parse(try screen(target), provider: target.agent),
              question.fingerprint == request.fingerprint,
              question.answerChoices.contains(where: { $0.number == choice }) else {
            throw failure("The question changed. Nothing was submitted; refresh to review it.")
        }
        let identity = target.id + ":" + target.sessionIdentity + ":" + String(target.stateChangeSequence ?? 0) + ":" + question.fingerprint
        guard consumed[target.id] != identity else { throw failure("This question was already answered. Review its pane before retrying.") }
        consumed[target.id] = identity
        let delta = choice - question.selected
        if delta != 0 {
            _ = try run(target.machine, ["agent", "send-keys", target.paneID] + Array(repeating: delta > 0 ? "down" : "up", count: abs(delta)))
        }
        // Selection is a separate operation. Re-read before Enter; never blindly append Enter to navigation.
        var selected: HerdrQuestion?
        for _ in 0..<5 {
            let current = HerdrQuestion.parse(try screen(target), provider: target.agent)
            guard current?.fingerprint == request.fingerprint else {
                throw failure("The question changed while selecting. Nothing was submitted; review it in Herdr.")
            }
            if current?.selected == choice { selected = current; break }
            Thread.sleep(forTimeInterval: 0.08)
        }
        guard selected != nil else { throw failure("Couldn’t confirm the selected answer. Review it in Herdr before retrying.") }
        _ = try run(target.machine, ["agent", "send-keys", target.paneID, "enter"])
        // Key delivery is not acknowledgement. Look for an advance; never resend on timeout.
        for _ in 0..<10 {
            Thread.sleep(forTimeInterval: 0.15)
            guard let agents = try? AgentSession.decodeList(run(target.machine, ["agent", "list"]), machine: target.machine) else {
                return "Answer sent, but confirmation is unavailable. Check Herdr before retrying."
            }
            guard let current = agents.first(where: { $0.id == target.id && $0.sessionIdentity == target.sessionIdentity }) else {
                return "Answer sent; the agent changed before confirmation. Review its pane."
            }
            if ["working", "idle", "done"].contains(current.agentStatus) { return "Answer sent; \(target.provider) resumed." }
            guard current.agentStatus == "blocked" else { break }
            // The submitted answer can make the screen disappear between list and read.
            // Retry observation only; never resend Enter or report a pre-submit validation failure.
            guard let text = try? screen(current) else { continue }
            if let next = HerdrQuestion.parse(text, provider: target.agent), next.fingerprint != request.fingerprint {
                return "Answer sent; \(target.provider) advanced to the next question."
            }
            if target.agent == "codex", text.contains("Questions ") && text.contains(" answered") && text.contains("answer: " + question.choices[choice - 1].label) {
                return "Codex acknowledged your answer."
            }
        }
        return "Answer sent, but confirmation is pending. Check Herdr before retrying."
    }
    private func failure(_ message: String) -> NSError { NSError(domain: "VolantHerdrResponse", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
