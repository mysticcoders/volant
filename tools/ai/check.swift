import Foundation
import VolantCore
@main struct Check {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
    static func ready(_ host: AIHTTPConversation) async throws -> ACPState {
        for _ in 0..<200 {
            let state = try JSONDecoder().decode(ACPState.self, from: await host.snapshot())
            if state.phase == "ready" { return state }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        fatalError("Fixture response timed out")
    }
    static func main() async throws {
        let endpoint = CommandLine.arguments[1]
        let config = AIHTTPConfiguration(provider: .compatible, endpoint: endpoint + "/v1", model: "fixture-model", local: true)
        let transport = AIHTTPTransport()
        let models = try await transport.models(config, key: "")
        check(models == ["fixture-model"], "Real HTTP model discovery")
        var redirect = config; redirect.endpoint = endpoint + "/redirect"
        do { _ = try await transport.models(redirect, key: "fictional-key"); fatalError("Redirect accepted") }
        catch AIHTTPError.http(let code) { check(code == 302, "Redirect must remain blocked") }
        let host = AIHTTPConversation(transport: transport)
        try await host.start(config, key: "")
        try await host.prompt("normal")
        let first = try await ready(host)
        check(first.messages.last?.text == "Hello café ☕", "Real HTTP Unicode streaming")
        try await host.prompt("slow")
        do { try await host.prompt("concurrent"); fatalError("Concurrent prompt accepted") } catch AIHTTPError.configuration {}
        await host.cancel()
        try await host.prompt("new turn")
        _ = try await ready(host)
        try await Task.sleep(nanoseconds: 1_200_000_000)
        let afterCancel = try await ready(host)
        check(!afterCancel.messages.contains { $0.text.contains("OLD") }, "Late cancelled response rejected")
        try await host.prompt("truncated")
        let truncated = try await ready(host)
        check(truncated.status == AIHTTPError.incomplete.errorDescription, "Truncation reported")
        try await host.prompt("unauthorized")
        let unauthorized = try await ready(host)
        check(unauthorized.status == AIHTTPError.http(401).errorDescription, "Authentication error is generic")
        check(!unauthorized.status.contains("secret"), "Provider bodies never surfaced")
        await host.stop()
        let context = AIHTTPConversation(transport: transport)
        try await context.start(config, key: "")
        try await context.prompt("what is attached?", attachments: [ChatAttachment(id: "note:Plan.md", kind: .note, title: "Plan", detail: "Note", text: "Ship the fixture.")])
        let seen = try await ready(context)
        check(seen.messages.last?.text == "SAW 1 ATTACHMENTS", "Model receives attachments inline")
        check(seen.messages.first?.text == "what is attached?" && seen.messages.first?.attachments == ["Plan"], "Transcript shows the prompt and titles only")
        try await context.prompt("history?")
        let history = try await ready(context)
        check(history.messages.last?.text == "HISTORY HAS ATTACHMENT", "Later turns keep the attached context")
        do {
            try await context.prompt("too much", attachments: [ChatAttachment(id: "big", kind: .clipboard, title: "Big", detail: "", text: String(repeating: "x", count: ChatAttachmentLimits.perItem + 1))])
            fatalError("Oversized attachment accepted")
        } catch AIHTTPError.limit {}
        await context.stop()
        print("PASS: attachments reach the model inline, stay in history, keep the transcript short, and oversized ones are refused")
        print("PASS: real loopback HTTP discovery, Unicode streaming, denied redirects, concurrent prompts, cancellation, stale chunks, truncation and generic authentication errors")
    }
}
