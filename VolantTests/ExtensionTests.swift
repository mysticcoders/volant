import XCTest
@testable import Volant

@MainActor
final class ExtensionTests: XCTestCase {
    private func fixture() throws -> (URL, URL, Volant.ExtensionManifest) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let config = root.appendingPathComponent("config.json")
        try Data(#"{"future":{"keep":true},"extensions":{}}"#.utf8).write(to: config)
        // Minimal ABI-compatible memory declaration with initial and max one page.
        let module = Data([0,97,115,109,1,0,0,0,5,4,1,1,1,1])
        try module.write(to: root.appendingPathComponent("hello.wasm"))
        let manifest = Volant.ExtensionManifest(id: "fixture.hello", name: "Hello", version: "1", module: "hello.wasm", capabilities: [], timeoutSeconds: 2, sha256: Volant.Integrity.sha256(module))
        try JSONEncoder().encode(manifest).write(to: root.appendingPathComponent("manifest.json"))
        return (root, config, manifest)
    }
    func testExplicitApprovalPreservesConfigAndChangedCodeNeedsApproval() async throws {
        let (root, config, manifest) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = ExtensionManager(configURL: config, roots: [root]); manager.reload()
        try manager.setCommunityAllowed(true, expected: false)
        XCTAssertEqual(manager.extensions.count, 1)
        let ext = try XCTUnwrap(manager.extensions.first)
        XCTAssertFalse(ext.enabled)
        var refused = false
        manager.run(ext, input: "fictional") { if case .failure = $0 { refused = true } }
        XCTAssertTrue(refused)
        try manager.setEnabled(ext, true)
        XCTAssertTrue(try XCTUnwrap(manager.extensions.first).enabled)
        XCTAssertThrowsError(try manager.setEnabled(ext, true)) // stale toggle snapshot
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: config)) as! [String: Any]
        XCTAssertNotNil(object["future"])
        var changed = manifest; changed.capabilities = ["clipboard.write"]
        XCTAssertFalse(ExtensionApproval.enabled(changed, at: config))
        try manager.setEnabled(try XCTUnwrap(manager.extensions.first), false)
        XCTAssertFalse(try XCTUnwrap(manager.extensions.first).enabled)
    }
    func testIntegrityPathsAndDuplicateIDsAreRejected() async throws {
        let (root, config, manifest) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = ExtensionManager(configURL: config, roots: [root]); manager.reload()
        try manager.setCommunityAllowed(true, expected: false)
        let ext = try XCTUnwrap(manager.extensions.first)
        try Data([0]).write(to: root.appendingPathComponent("hello.wasm"))
        XCTAssertThrowsError(try manager.setEnabled(ext, true))
        var changed = manifest; changed.module = "../hello.wasm"
        XCTAssertThrowsError(try changed.validate())
        changed = manifest; changed.abiVersion = nil
        XCTAssertThrowsError(try changed.validate())
        let duplicate = ExtensionManager(configURL: config, roots: [root, root]); duplicate.reload()
        XCTAssertTrue(duplicate.extensions.isEmpty)
        XCTAssertFalse(duplicate.loadErrors.isEmpty)
    }
    func testMemoryMustHaveSmallExplicitMaximum() async throws {
        let prefix: [UInt8] = [0,97,115,109,1,0,0,0]
        XCTAssertNoThrow(try Volant.ExtensionMemory.validate(Data(prefix + [5,4,1,1,1,1])))
        XCTAssertThrowsError(try Volant.ExtensionMemory.validate(Data(prefix + [5,3,1,0,1])))
        XCTAssertThrowsError(try Volant.ExtensionMemory.validate(Data(prefix + [5,5,1,1,1,0x81,0x02])))
        XCTAssertThrowsError(try Volant.ExtensionMemory.validate(Data(prefix + [5,99,1])))
        XCTAssertThrowsError(try Volant.ExtensionMemory.validate(Data(prefix)))
    }
    func testCommunityMasterSwitchPreservesIndividualApprovalsAndRejectsStaleRuns() async throws {
        let (root, config, manifest) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = ExtensionManager(configURL: config, roots: [root]); manager.reload()
        let disabled = try XCTUnwrap(manager.extensions.first)
        XCTAssertFalse(manager.communityAllowed)
        XCTAssertTrue(disabled.isCommunity)
        XCTAssertTrue(disabled.communityBlocked)
        XCTAssertThrowsError(try manager.setEnabled(disabled, true))
        try manager.setCommunityAllowed(true, expected: false)
        XCTAssertThrowsError(try manager.setCommunityAllowed(true, expected: false))
        XCTAssertFalse(try XCTUnwrap(manager.extensions.first).enabled)
        try manager.setEnabled(try XCTUnwrap(manager.extensions.first), true)
        let staleEnabled = try XCTUnwrap(manager.extensions.first)
        try manager.setCommunityAllowed(false, expected: true)
        XCTAssertTrue(ExtensionApproval.enabled(manifest, at: config))
        XCTAssertTrue(try XCTUnwrap(manager.extensions.first).enabled)
        XCTAssertTrue(try XCTUnwrap(manager.extensions.first).communityBlocked)
        var blocked = false
        manager.run(staleEnabled, input: "fictional") {
            if case .failure(ExtensionManager.ExtensionError.communityDisabled) = $0 { blocked = true }
        }
        XCTAssertTrue(blocked, "Saved row cannot bypass the current master switch or start XPC")
        try manager.setCommunityAllowed(true, expected: false)
        XCTAssertTrue(try XCTUnwrap(manager.extensions.first).enabled)
        XCTAssertFalse(try XCTUnwrap(manager.extensions.first).communityBlocked)
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: config)) as! [String: Any]
        XCTAssertNotNil(object["future"])
    }
}
