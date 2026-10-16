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
}
