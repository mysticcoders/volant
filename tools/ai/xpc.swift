import Foundation
import AppKit
import VolantCore

func verify(_ condition: Bool, _ message: String) { if !condition { fputs("FAIL: \(message)\n", stderr); exit(1) } }
func waitUntil(_ test: () -> Bool) {
    let deadline = Date().addingTimeInterval(20)
    while !test() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    verify(test(), "Timed out waiting for signed API helper")
}
let credentialAccount = "fixture:" + UUID().uuidString
try AICredentials.keychain.write(credentialAccount, "fictional-first-key")
defer { try? AICredentials.keychain.write(credentialAccount, nil) }
verify(try AICredentials.keychain.read(credentialAccount) == "fictional-first-key", "Sandboxed Keychain save/read")
try AICredentials.keychain.write(credentialAccount, "fictional-replacement-key")
verify(try AICredentials.keychain.read(credentialAccount) == "fictional-replacement-key", "Keychain replacement")
try AICredentials.keychain.write(credentialAccount, nil)
verify(try AICredentials.keychain.read(credentialAccount) == nil, "Keychain removal")
let endpoint = CommandLine.arguments[1]
var config = AIConfiguration(); config.connection = .local
config.localAPI.endpoint = endpoint + "/v1"; config.localAPI.model = "fixture-model"
let model = ACPModel(); model.credentials = AICredentials(read: { _ in nil }, write: { _, _ in fatalError("No credential writes") })
verify(model.openChat(configuration: config, connect: model.start), "Configured local chat activates")
waitUntil { model.state.phase == "ready" || model.error != nil }
verify(model.error == nil, "Signed helper starts")
model.draft = "normal"; model.send()
waitUntil { !model.submitting && model.state.phase == "ready" && !model.state.messages.isEmpty }
verify(model.state.messages.last?.text == "Hello café ☕", "Signed helper streams through production chat model")
model.draft = "Keep draft"
var changed = AIConfiguration(); changed.provider = "claude"
model.configure(changed)
verify(model.usesAPI && model.draft == "Keep draft", "Active API conversation survives settings changes")
let discovery = AIModelDiscovery()
discovery.refresh(config.localAPI, key: "")
waitUntil { !discovery.loading }
verify(discovery.models == ["fixture-model"], "Signed Settings discovery lists models")
model.disconnect(); discovery.cancel()
print("PASS: signed sandboxed AI helper, loopback network access, production chat dispatch, Unicode streaming, retained active session and Settings model discovery and isolated Keychain save/read/replace/remove")
