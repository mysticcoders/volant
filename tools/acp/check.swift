import Foundation
import VolantCore

func require(_ condition: @autoclosure () -> Bool, _ message: String) { precondition(condition(), message) }
func frame(_ object: [String: Any]) -> Data {
    var data = try! JSONSerialization.data(withJSONObject: object); data.append(10); return data
}
let client = ACPConnection()
var sent: [[String: Any]] = []
client.testSend = { sent.append($0) }
try client.queue.sync {
    client.beginHandshake(project: "/tmp/fictional-project")
    require(sent.last?["method"] as? String == "initialize", "initialization")
    let initial = frame(["jsonrpc": "2.0", "id": 1, "result": ["protocolVersion": 1, "agentCapabilities": ["loadSession": true]]])
    client.receive(initial.prefix(12)); require(sent.count == 1, "partial frames wait")
    client.receive(initial.dropFirst(12)); require(sent.last?["method"] as? String == "session/new", "new session after handshake")
    client.receive(frame(["jsonrpc": "2.0", "id": 2, "result": ["sessionId": "fictional-session"]]))
    require(client.state.phase == "ready", "ready after session ID")
    try client.prompt("Hello fixture")
    do { try client.prompt("duplicate"); fatalError("duplicate accepted") } catch {}
    let update: (String, String) -> [String: Any] = { session, text in ["jsonrpc": "2.0", "method": "session/update", "params": ["sessionId": session, "update": ["sessionUpdate": "agent_message_chunk", "content": ["type": "text", "text": text]]]] }
    client.receive(frame(update("wrong-session", "must ignore")))
    require(client.state.messages.count == 1, "ignore other session")
    client.receive(frame(update("fictional-session", "Hello ")) + frame(update("fictional-session", "world")))
    require(client.state.messages.last?.text == "Hello world", "coalesced streaming")
    let permission: (Int) -> [String: Any] = { id in ["jsonrpc": "2.0", "id": id, "method": "session/request_permission", "params": ["sessionId": "fictional-session", "toolCall": ["toolCallId": "tool-1"], "options": [["optionId": "once", "name": "Allow once", "kind": "allow_once"], ["optionId": "deny", "name": "Reject", "kind": "reject_once"]]]] }
    client.receive(frame(["jsonrpc": "2.0", "method": "session/update", "params": ["sessionId": "fictional-session", "update": ["sessionUpdate": "tool_call", "toolCallId": "tool-1", "title": "Read fixture", "rawInput": ["path": "fixture.txt"]]]]))
    let count = sent.count
    client.receive(frame(permission(91)))
    require(sent.count == count && client.state.permissions.count == 1, "no automatic approval")
    require(client.state.permissions[0].detail.contains("fixture.txt"), "permissions retain earlier operation details")
    let key = client.state.permissions[0].id
    do { try client.choose(request: key, option: "forged"); fatalError("invalid option accepted") } catch {}
    try client.choose(request: key, option: "deny")
    require(client.state.permissions.isEmpty, "permission resolved")
    do { try client.choose(request: key, option: "once"); fatalError("stale permission accepted") } catch {}
    client.receive(frame(permission(92)))
    client.cancel()
    require(client.state.permissions.isEmpty && client.state.phase == "cancelling", "cancellation clears approvals")
    let cancelled = sent.contains { ($0["id"] as? Int == 92) && (($0["result"] as? [String: Any])?["outcome"] as? [String: Any])?["outcome"] as? String == "cancelled" }
    require(cancelled, "cancel sends required permission outcome")
    client.receive(frame(permission(93)))
    require(client.state.permissions.isEmpty, "late approval while cancelling is cancelled")
    client.receive(frame(["jsonrpc": "2.0", "id": 3, "result": ["stopReason": "cancelled"]]))
    require(client.state.phase == "ready", "cancellation waits for prompt response")
    client.receive(frame(["jsonrpc": "2.0", "id": "extension-request", "method": "terminal/create", "params": [:]]))
    require((sent.last?["error"] as? [String: Any])?["code"] as? Int == -32601, "unsupported methods fail explicitly")
    client.receive(Data("invalid json\n".utf8))
    require(client.state.phase == "failed", "invalid JSON terminates")
}
let version = ACPConnection()
version.testSend = { _ in }
version.queue.sync {
    version.beginHandshake(project: "/tmp/fixture")
    version.receive(frame(["jsonrpc": "2.0", "id": 1, "result": ["protocolVersion": 999]]))
    require(version.state.phase == "failed", "version mismatch")
}
print("Passed ACP checks: framing, negotiation, session routing, streaming, duplicate sends, explicit/rejected/stale permissions, cancellation, unsupported methods, invalid JSON.")

let oversized = ACPConnection()
oversized.testSend = { _ in }
oversized.queue.sync {
    oversized.receive(Data(repeating: 65, count: 2_000_001))
    require(oversized.state.phase == "failed", "unterminated frame limit")
}
print("Passed: retained approval details and oversized unterminated frame rejection.")

/// Attachments are shaped by what the agent advertised and re-checked here, not trusted from the app.
func contextSession(_ capabilities: [String: Any]) -> (ACPConnection, () -> [String: Any]?) {
    let connection = ACPConnection()
    var log: [[String: Any]] = []
    connection.testSend = { log.append($0) }
    connection.queue.sync {
        connection.beginHandshake(project: "/tmp/fictional-project")
        connection.receive(frame(["jsonrpc": "2.0", "id": 1, "result": ["protocolVersion": 1, "agentCapabilities": capabilities]]))
        connection.receive(frame(["jsonrpc": "2.0", "id": 2, "result": ["sessionId": "context-session"]]))
    }
    return (connection, { log.last })
}
let note = ChatAttachment(id: "Plan.md", kind: .note, title: "Plan", detail: "Note", text: "Ship the fixture.")
let (embedded, lastEmbedded) = contextSession(["promptCapabilities": ["embeddedContext": true]])
try embedded.queue.sync {
    try embedded.prompt("Summarize", attachments: [note])
    let blocks = (lastEmbedded()?["params"] as? [String: Any])?["prompt"] as? [[String: Any]] ?? []
    require(blocks.count == 2 && blocks[0]["type"] as? String == "resource", "embedded context sends a resource block")
    require(((blocks[0]["resource"] as? [String: Any])?["text"] as? String) == "Ship the fixture.", "resource carries the snapshot text")
    require(blocks[1]["text"] as? String == "Summarize", "prompt follows its attachments")
    require(embedded.state.messages.last?.text == "Summarize" && embedded.state.messages.last?.attachments == ["Plan"], "transcript shows the prompt and titles only")
}
let (plain, lastPlain) = contextSession(["loadSession": true])
try plain.queue.sync {
    try plain.prompt("Summarize", attachments: [note])
    let blocks = (lastPlain()?["params"] as? [String: Any])?["prompt"] as? [[String: Any]] ?? []
    require(blocks.count == 1 && blocks[0]["type"] as? String == "text", "agents without embedded context get one text block")
    require((blocks[0]["text"] as? String)?.contains("<attachment kind=\"note\" title=\"Plan\">") == true, "inline form labels the note")
}
let (limited, lastLimited) = contextSession(["promptCapabilities": ["embeddedContext": true]])
limited.queue.sync {
    let huge = ChatAttachment(id: "big", kind: .clipboard, title: "Big", detail: "", text: String(repeating: "x", count: ChatAttachmentLimits.perItem + 1))
    do { try limited.prompt("Too much", attachments: [huge]); fatalError("oversized attachment accepted") } catch {}
    require(lastLimited()?["method"] as? String == "session/new" && limited.state.phase == "ready", "refused prompts send nothing")
}
print("Passed: attachments follow embeddedContext, keep the transcript short, and are re-checked before sending.")
