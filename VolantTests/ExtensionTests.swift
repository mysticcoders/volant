import XCTest
import VolantCore
@testable import Volant

@MainActor
final class ExtensionTests: XCTestCase {
    private func fixture() throws -> (URL, URL, VolantCore.ExtensionManifest) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let config = root.appendingPathComponent("config.json")
        try Data(#"{"future":{"keep":true},"extensions":{}}"#.utf8).write(to: config)
        // Minimal ABI-compatible memory declaration with initial and max one page.
        let module = Data([0,97,115,109,1,0,0,0,5,4,1,1,1,1])
        try module.write(to: root.appendingPathComponent("hello.wasm"))
        let manifest = VolantCore.ExtensionManifest(id: "fixture.hello", name: "Hello", version: "1", module: "hello.wasm", capabilities: [], timeoutSeconds: 2, sha256: Volant.Integrity.sha256(module))
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
    func testDirectCommandNamesPreserveInputAndDoNotEnableOrLoadCode() async throws {
        let (root, config, original) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var manifest = original; manifest.id = "fixture.base64"; manifest.name = "Base64 Encode"
        try JSONEncoder().encode(manifest).write(to: root.appendingPathComponent("manifest.json"))
        // Discovery must work without reading/compiling executable bytes.
        try FileManager.default.removeItem(at: root.appendingPathComponent("hello.wasm"))
        let manager = ExtensionManager(configURL: config, roots: [root])
        for (query, expected) in [("base64", ""), ("BASE64 café ☕", "café ☕"),
                                  ("Base64 Encode Hello  World", "Hello  World"), ("base64\t日本語", "日本語"),
                                  ("base", ""), ("Base64 Enc", "Enc")] {
            let match = try XCTUnwrap(manager.commandMatches(query).first, query)
            XCTAssertEqual(match.input, expected, query)
            XCTAssertFalse(match.extensionItem.enabled)
            XCTAssertTrue(match.extensionItem.communityBlocked)
        }
        XCTAssertTrue(manager.commandMatches("base64garbage text").isEmpty)
        XCTAssertTrue(manager.commandMatches("").isEmpty)
        XCTAssertFalse(ExtensionApproval.enabled(manifest, at: config))
        // Repeated keystrokes use metadata, not repeated folder/manifest reads.
        try FileManager.default.removeItem(at: root.appendingPathComponent("manifest.json"))
        XCTAssertEqual(manager.commandMatches("base64 another input").count, 1)
        manager.invalidateCatalog()
        XCTAssertTrue(manager.commandMatches("base64").isEmpty)
    }
    func testMemoryMustHaveSmallExplicitMaximum() async throws {
        let prefix: [UInt8] = [0,97,115,109,1,0,0,0]
        XCTAssertNoThrow(try VolantCore.ExtensionMemory.validate(Data(prefix + [5,4,1,1,1,1])))
        XCTAssertThrowsError(try VolantCore.ExtensionMemory.validate(Data(prefix + [5,3,1,0,1])))
        XCTAssertThrowsError(try VolantCore.ExtensionMemory.validate(Data(prefix + [5,5,1,1,1,0x81,0x02])))
        XCTAssertThrowsError(try VolantCore.ExtensionMemory.validate(Data(prefix + [5,99,1])))
        XCTAssertThrowsError(try VolantCore.ExtensionMemory.validate(Data(prefix)))
    }
    func testCommandABIIsExplicitAndCannotRequestLegacyCapabilities() async throws {
        let (root, _, manifest) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var command = manifest; command.abiVersion = 2
        XCTAssertNoThrow(try command.validate())
        command.capabilities = ["clipboard.write"]
        XCTAssertThrowsError(try command.validate())
        command.capabilities = []; command.abiVersion = 3
        XCTAssertThrowsError(try command.validate())
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
    func testFoldersLoadWithOrWithoutATrailingSlash() async throws {
        let (root, config, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let unslashed = URL(fileURLWithPath: root.path, isDirectory: false)
        let slashed = URL(fileURLWithPath: root.path, isDirectory: true)
        XCTAssertFalse(unslashed.absoluteString.hasSuffix("/"))
        XCTAssertTrue(slashed.absoluteString.hasSuffix("/"))
        XCTAssertTrue(ExtensionManager.sameLocation(unslashed, slashed))
        for folder in [unslashed, slashed] {
            let manager = ExtensionManager(configURL: config, roots: [folder]); manager.reload()
            XCTAssertEqual(manager.extensions.map(\.id), ["fixture.hello"], "\(folder.absoluteString): \(manager.loadErrors)")
        }
        let elsewhere = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: elsewhere) }
        try FileManager.default.moveItem(at: root.appendingPathComponent("manifest.json"), to: elsewhere.appendingPathComponent("manifest.json"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("manifest.json"), withDestinationURL: elsewhere.appendingPathComponent("manifest.json"))
        let escaped = ExtensionManager(configURL: config, roots: [unslashed]); escaped.reload()
        XCTAssertTrue(escaped.extensions.isEmpty, "A manifest symlinked out of its folder is still refused")
    }

    /// Two list extensions sharing one host, each in its own folder under `root`.
    private func networkFixture() throws -> (URL, URL, [URL]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let config = root.appendingPathComponent("config.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(#"{"future":{"keep":true},"extensions":{}}"#.utf8).write(to: config)
        let module = Data([0,97,115,109,1,0,0,0,5,4,1,1,1,1])
        let folders = try [("fixture.news", "Fictional News", ["news.example.com", "shared.example.com"]),
                           ("fixture.feed", "Fictional Feed", ["shared.example.com"])].map { id, name, hosts -> URL in
            let folder = root.appendingPathComponent(id, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try module.write(to: folder.appendingPathComponent("reader.wasm"))
            let manifest = VolantCore.ExtensionManifest(id: id, name: name, version: "1", module: "reader.wasm", capabilities: [],
                                                        sha256: Volant.Integrity.sha256(module), hosts: hosts, output: "items")
            try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent("manifest.json"))
            return folder
        }
        return (root, config, folders)
    }

    func testEnablingAllowsHostsAndRemovingAHostAsksAgain() async throws {
        let (root, config, folders) = try networkFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = ExtensionManager(configURL: config, roots: folders); manager.reload()
        try manager.setCommunityAllowed(true, expected: false)
        let news = try XCTUnwrap(manager.extensions.first { $0.id == "fixture.news" })
        XCTAssertEqual(manager.missingHosts(news), ["news.example.com", "shared.example.com"])
        XCTAssertFalse(manager.isReady(news))
        var refusal: Error?
        manager.runItems(news, query: "", fetch: { _, _, _ in XCTFail("must not fetch before approval") }) {
            if case .failure(let error) = $0 { refusal = error }
        }
        XCTAssertNotNil(refusal)

        try manager.setEnabled(news, true)
        let enabled = try XCTUnwrap(manager.extensions.first { $0.id == "fixture.news" })
        XCTAssertTrue(manager.isReady(enabled))
        XCTAssertEqual(ExtensionHostApprovals.approved(at: config), ["news.example.com", "shared.example.com"])
        let feed = try XCTUnwrap(manager.extensions.first { $0.id == "fixture.feed" })
        XCTAssertEqual(manager.missingHosts(feed), [], "a shared host approved for one extension counts for the other")
        XCTAssertFalse(manager.isReady(feed), "the other extension still needs its own enablement")

        try ExtensionHostApprovals.remove("shared.example.com", at: config)
        XCTAssertFalse(manager.isReady(enabled))
        XCTAssertEqual(manager.missingHosts(enabled), ["shared.example.com"])
        try manager.setEnabled(enabled, true)
        XCTAssertTrue(manager.isReady(try XCTUnwrap(manager.extensions.first { $0.id == "fixture.news" })))
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: config)) as! [String: Any]
        XCTAssertNotNil(object["future"])
    }

    /// The news fixture, enabled with its hosts allowed, answering each request with the next reply
    /// in turn; `requests` records what the module received and `fetched` what Volant fetched.
    private func scriptedNews(_ replies: [String]) throws -> (URL, URL, ExtensionManager, InstalledExtension, () -> [String]) {
        let (root, config, folders) = try networkFixture()
        let manager = ExtensionManager(configURL: config, roots: folders); manager.reload()
        try manager.setCommunityAllowed(true, expected: false)
        try manager.setEnabled(try XCTUnwrap(manager.extensions.first { $0.id == "fixture.news" }), true)
        var queue = replies, requests: [String] = []
        manager.invokeOverride = { _, input, completion in
            requests.append(input)
            completion(.success(queue.isEmpty ? #"{"items":[]}"# : queue.removeFirst()))
        }
        return (root, config, manager, try XCTUnwrap(manager.extensions.first { $0.id == "fixture.news" }), { requests })
    }

    func testRendersCanFetchAgainWithStateUpToTheRoundLimit() async throws {
        let (root, _, manager, news, requests) = try scriptedNews([
            #"{"fetch":["https://news.example.com/find?q=paris"],"state":"find"}"#,
            #"{"fetch":["https://news.example.com/forecast?at=1"],"state":"forecast:Paris"}"#,
            #"{"items":[{"title":"Paris"}]}"#,
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        var fetched: [String] = [], outcome: Result<[ExtensionItem], Error>?
        manager.runItems(news, query: "paris", fetch: { urls, _, reply in
            fetched += urls.map(\.absoluteString); reply(urls.map { .init(url: $0.absoluteString, status: 200, body: "{}") })
        }) { outcome = $0 }
        XCTAssertEqual(try XCTUnwrap(outcome).get().map(\.title), ["Paris"])
        XCTAssertEqual(fetched, ["https://news.example.com/find?q=paris", "https://news.example.com/forecast?at=1"])
        XCTAssertTrue(requests()[1].contains(#""state":"find""#), requests()[1])
        XCTAssertTrue(requests()[2].contains(#""state":"forecast:Paris""#), requests()[2])
        XCTAssertTrue(requests().allSatisfy { $0.contains(#""units":"#) })
    }

    func testAFourthRoundIsRefused() async throws {
        let again = #"{"fetch":["https://news.example.com/more"],"state":"more"}"#
        let (root, _, manager, news, _) = try scriptedNews([again, again, again, again])
        defer { try? FileManager.default.removeItem(at: root) }
        var rounds = 0, outcome: Result<[ExtensionItem], Error>?
        manager.runItems(news, query: "", fetch: { urls, _, reply in
            rounds += 1; reply(urls.map { .init(url: $0.absoluteString, status: 200, body: "") })
        }) { outcome = $0 }
        XCTAssertEqual(rounds, ExtensionNetwork.maximumRounds)
        guard case .failure(let error) = try XCTUnwrap(outcome) else { return XCTFail("a fourth round must fail") }
        XCTAssertEqual(error as? ExtensionNetworkError, .tooManyRounds)
    }

    func testRemovingAHostMidRunStopsTheNextRound() async throws {
        let (root, config, manager, news, _) = try scriptedNews([
            #"{"fetch":["https://news.example.com/a"]}"#,
            #"{"fetch":["https://news.example.com/b"],"state":"b"}"#,
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        var rounds = 0, outcome: Result<[ExtensionItem], Error>?
        manager.runItems(news, query: "", fetch: { urls, _, reply in
            rounds += 1
            try? ExtensionHostApprovals.remove("news.example.com", at: config)
            reply(urls.map { .init(url: $0.absoluteString, status: 200, body: "") })
        }) { outcome = $0 }
        XCTAssertEqual(rounds, 1, "the second round must not fetch")
        guard case .failure(let error) = try XCTUnwrap(outcome) else { return XCTFail("a removed host must stop the run") }
        XCTAssertEqual(error as? ExtensionNetworkError, .hostsNotApproved(["news.example.com"]))
    }

    func testUninstallForgetsApprovalAndOnlyOrphanedHosts() async throws {
        let (root, config, folders) = try networkFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = ExtensionManager(configURL: config, roots: folders); manager.reload()
        try manager.setCommunityAllowed(true, expected: false)
        for id in ["fixture.news", "fixture.feed"] { try manager.setEnabled(try XCTUnwrap(manager.extensions.first { $0.id == id }), true) }
        let news = try XCTUnwrap(manager.extensions.first { $0.id == "fixture.news" })
        var removed: [URL] = []
        let pruned = try manager.uninstall(news) { removed.append($0); try FileManager.default.removeItem(at: $0) }
        XCTAssertEqual(removed, [folders[0]])
        XCTAssertEqual(pruned, ["news.example.com"])
        XCTAssertEqual(ExtensionHostApprovals.approved(at: config), ["shared.example.com"], "the feed still uses the shared host")
        XCTAssertEqual(manager.extensions.map(\.id), ["fixture.feed"])
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: config)) as! [String: Any]
        XCTAssertNil((object["extensions"] as? [String: Any])?["fixture.news"])
        XCTAssertNotNil((object["extensions"] as? [String: Any])?["fixture.feed"])
    }
}
