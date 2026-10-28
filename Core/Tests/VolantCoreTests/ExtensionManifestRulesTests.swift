import XCTest

@testable import VolantCore

/// Manifest and module rules checked before an extension can run: a small explicit memory maximum,
/// an explicit command ABI, valid list scope settings, and submissions only to declared hosts.
final class ExtensionManifestRulesTests: XCTestCase {
    private func manifest(output: String? = "items") -> ExtensionManifest {
        ExtensionManifest(id: "community.fictional.reader", name: "Fictional Reader", version: "1", module: "reader.wasm",
                          capabilities: [], sha256: String(repeating: "a", count: 64), output: output)
    }

    func testMemoryMustHaveSmallExplicitMaximum() {
        let prefix: [UInt8] = [0,97,115,109,1,0,0,0]
        XCTAssertNoThrow(try ExtensionMemory.validate(Data(prefix + [5,4,1,1,1,1])))
        XCTAssertThrowsError(try ExtensionMemory.validate(Data(prefix + [5,3,1,0,1])))
        XCTAssertThrowsError(try ExtensionMemory.validate(Data(prefix + [5,5,1,1,1,0x81,0x02])))
        XCTAssertThrowsError(try ExtensionMemory.validate(Data(prefix + [5,99,1])))
        XCTAssertThrowsError(try ExtensionMemory.validate(Data(prefix)))
    }

    func testCommandABIIsExplicitAndCannotRequestLegacyCapabilities() {
        var command = manifest(output: nil); command.abiVersion = 2
        XCTAssertNoThrow(try command.validate())
        command.capabilities = ["clipboard.write"]
        XCTAssertThrowsError(try command.validate())
        command.capabilities = []; command.abiVersion = 3
        XCTAssertThrowsError(try command.validate())
    }

    func testModePlaceholderAndFiltersAreValidated() {
        let base = manifest()
        var scoped = base
        scoped.mode = "search"
        scoped.placeholder = "Search fictional articles"
        XCTAssertNoThrow(try scoped.validate())
        var unknown = base; unknown.mode = "grid"
        XCTAssertThrowsError(try unknown.validate())
        var text = base; text.output = nil; text.mode = "search"
        XCTAssertThrowsError(try text.validate(), "Only list extensions have a scope")
        var empty = base; empty.placeholder = ""
        XCTAssertThrowsError(try empty.validate())
        var long = base; long.placeholder = String(repeating: "x", count: ExtensionManifest.maximumPlaceholderLength + 1)
        XCTAssertThrowsError(try long.validate())
        var filtered = base; filtered.filters = [ExtensionFilter(id: "top", title: "Top"), ExtensionFilter(id: "new", title: "New")]
        XCTAssertNoThrow(try filtered.validate())
        var single = base; single.filters = [ExtensionFilter(id: "top", title: "Top")]
        XCTAssertThrowsError(try single.validate(), "A dropdown needs at least two choices")
        var duplicate = base; duplicate.filters = [ExtensionFilter(id: "top", title: "Top"), ExtensionFilter(id: "top", title: "Again")]
        XCTAssertThrowsError(try duplicate.validate())
        var badID = base; badID.filters = [ExtensionFilter(id: "Top Stories", title: "Top"), ExtensionFilter(id: "new", title: "New")]
        XCTAssertThrowsError(try badID.validate())
        var textFilters = filtered; textFilters.output = nil
        XCTAssertThrowsError(try textFilters.validate(), "Only list extensions have a dropdown")
    }

    func testSubmissionsOnlyPostToDeclaredHosts() {
        let hosts: Set = ["api.tasks.example.com"]
        XCTAssertThrowsError(try ExtensionNetwork.submissions(from: #"{"fetch":[{"url":"https://evil.example.com/x","method":"POST"}]}"#, hosts: hosts))
        XCTAssertThrowsError(try ExtensionNetwork.submissions(from: #"{"fetch":[{"url":"https://api.tasks.example.com/x","method":"DELETE"}]}"#, hosts: hosts))
        XCTAssertFalse(ExtensionRequest.isAllowed(method: "GET", body: Data("x".utf8), headers: [:]), "a GET never carries a body")
        XCTAssertFalse(ExtensionRequest.isAllowed(method: "POST", body: nil, headers: ["Cookie": "a=b"]), "only declared secret headers")
        XCTAssertFalse(ExtensionRequest.isAllowed(method: "POST", body: nil, headers: ["Authorization": "Bearer a\r\nX: y"]))
    }

    func testJSONInputIsForTextExtensionsAndOpensRequestFeatures() {
        var text = manifest(output: nil)
        text.input = "json"; text.storage = true; text.permissions = ["clipboard"]
        XCTAssertNoThrow(try text.validate())
        XCTAssertTrue(text.receivesRequests)
        var list = manifest(); list.input = "json"
        XCTAssertThrowsError(try list.validate(), "List extensions always get JSON")
        var unknown = manifest(output: nil); unknown.input = "xml"
        XCTAssertThrowsError(try unknown.validate())
        var plain = manifest(output: nil); plain.permissions = ["clipboard"]
        XCTAssertThrowsError(try plain.validate(), "Plain text input has no request to carry the clipboard")
        plain.permissions = nil; plain.storage = true
        XCTAssertThrowsError(try plain.validate(), "Plain text input has no request to carry storage")
        var located = text; located.permissions = ["location"]
        XCTAssertThrowsError(try located.validate(), "Location is only for list extensions, which read hosts")
        var listClipboard = manifest(); listClipboard.permissions = ["clipboard", "location"]
        XCTAssertNoThrow(try listClipboard.validate())
    }

    func testClipboardPermissionNeedsApprovalAgainOnUpdate() {
        var old = manifest(output: nil); old.input = "json"
        var new = old; new.permissions = ["clipboard"]
        XCTAssertFalse(new.requestsNoMoreThan(old), "Reading the clipboard is new access")
        XCTAssertTrue(old.requestsNoMoreThan(new))
    }

    func testClipboardTextSkipsConcealedOversizedAndEmptyItems() {
        XCTAssertEqual(ExtensionClipboard.text("SGVsbG8=", types: ["public.utf8-plain-text"]), "SGVsbG8=")
        XCTAssertNil(ExtensionClipboard.text("hunter2", types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        XCTAssertNil(ExtensionClipboard.text("one-time", types: ["org.nspasteboard.TransientType"]))
        XCTAssertNil(ExtensionClipboard.text("vault", types: ["com.agilebits.onepassword"]))
        XCTAssertNil(ExtensionClipboard.text("", types: []))
        XCTAssertNil(ExtensionClipboard.text(nil, types: []))
        XCTAssertNil(ExtensionClipboard.text(String(repeating: "a", count: ExtensionClipboard.maximumBytes + 1), types: []))
        XCTAssertNotNil(ExtensionClipboard.text(String(repeating: "a", count: ExtensionClipboard.maximumBytes), types: []))
    }

    func testRequestsCarryTheClipboardAndRepliesMayCarryText() throws {
        let request = try ExtensionNetwork.request(phase: "run", query: "decode", now: Date(timeIntervalSince1970: 0), clipboard: "SGk=")
        XCTAssertTrue(request.contains(#""clipboard":"SGk=""#), request)
        XCTAssertTrue(request.contains(#""phase":"run""#))
        let without = try ExtensionNetwork.request(phase: "run", query: "", now: Date(timeIntervalSince1970: 0))
        XCTAssertFalse(without.contains("clipboard"))
        XCTAssertEqual(try ExtensionNetwork.reply(from: #"{"text":"Hi"}"#).text, "Hi")
        XCTAssertNil(try ExtensionNetwork.reply(from: #"{"notice":"Saved"}"#).text)
    }
}
