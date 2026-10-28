import XCTest
import VolantCore
@testable import Volant

/// Text extensions that take JSON requests, and the clipboard permission, with a scripted module in place
/// of the extension helper and a fake clipboard. Every file is temporary and fictional.
@MainActor
final class ExtensionClipboardRunTests: XCTestCase {
    private var root: URL!
    private var config: URL { root.appendingPathComponent("config.json") }
    private var folder: URL { root.appendingPathComponent("decoder", isDirectory: true) }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("clipboard-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"extensions":{},"communityExtensionsAllowed":true}"#.utf8).write(to: config)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// One installed extension, enabled unless `enabled` is false, whose clipboard reads are counted.
    private func manager(output: String? = nil, input: String? = "json", permissions: [String]? = ["clipboard"], storage: Bool? = nil,
                         preferences: [ExtensionPreference]? = nil, enabled: Bool = true) throws -> (ExtensionManager, InstalledExtension, () -> Int) {
        let module = Data([0, 97, 115, 109, 1, 0, 0, 0, 5, 4, 1, 1, 1, 1])
        try module.write(to: folder.appendingPathComponent("decoder.wasm"))
        let manifest = ExtensionManifest(id: "community.fictional.decoder", name: "Fictional Decoder", version: "1", module: "decoder.wasm",
                                         capabilities: [], timeoutSeconds: 2, sha256: Integrity.sha256(module), output: output, storage: storage,
                                         permissions: permissions, preferences: preferences, input: input)
        try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent("manifest.json"))
        let manager = ExtensionManager(configURL: config, roots: [folder], dataDirectory: root.appendingPathComponent("ExtensionData"))
        manager.reload()
        if enabled { try manager.setEnabled(try XCTUnwrap(manager.extensions.first), true) }
        var reads = 0
        manager.readClipboard = { reads += 1; return "SGVsbG8=" }
        return (manager, try XCTUnwrap(manager.extensions.first), { reads })
    }

    /// Replies with each string in turn and records the requests.
    private func script(_ manager: ExtensionManager, _ replies: [String]) -> () -> [String] {
        var queue = replies, requests: [String] = []
        manager.invokeOverride = { _, input, completion in
            requests.append(input)
            completion(.success(queue.isEmpty ? #"{"text":""}"# : queue.removeFirst()))
        }
        return { requests }
    }

    private func text(_ manager: ExtensionManager, _ ext: InstalledExtension, _ input: String) -> Result<ExtensionManager.TextOutcome, Error> {
        var outcome: Result<ExtensionManager.TextOutcome, Error>?
        manager.runText(ext, input: input) { outcome = $0 }
        return outcome!
    }

    private func object(_ request: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(request.utf8)) as? [String: Any])
    }

    func testAJSONTextExtensionGetsItsRequestAndRepliesWithText() throws {
        let toggle = ExtensionPreference(id: "trim", type: .toggle, title: "Trim", defaultValue: .bool(true))
        let (manager, ext, reads) = try manager(storage: true, preferences: [toggle])
        let requests = script(manager, [#"{"text":"Hello","notice":"Decoded","storage":{"last":"Hello"}}"#])
        XCTAssertEqual(try text(manager, ext, "decode").get(), .init(text: "Hello", notice: "Decoded"))
        let sent = try object(requests()[0])
        XCTAssertEqual(sent["phase"] as? String, "run")
        XCTAssertEqual(sent["query"] as? String, "decode")
        XCTAssertEqual(sent["clipboard"] as? String, "SGVsbG8=")
        XCTAssertEqual((sent["preferences"] as? [String: Any])?["trim"] as? Bool, true)
        XCTAssertNotNil(sent["storage"], "An extension with storage gets its saved object")
        XCTAssertEqual(reads(), 1)
        XCTAssertEqual(manager.storedData(ext), .object(["last": .string("Hello")]))
    }

    func testAPlainTextExtensionGetsOnlyTheTypedText() throws {
        let (manager, ext, reads) = try manager(input: nil, permissions: nil)
        let requests = script(manager, ["raw output"])
        XCTAssertEqual(try text(manager, ext, "hello").get(), .init(text: "raw output"))
        XCTAssertEqual(requests(), ["hello"])
        XCTAssertEqual(reads(), 0)
    }

    func testTheClipboardIsReadOnlyForAnAllowedExtension() throws {
        let (manager, ext, reads) = try manager(permissions: nil)
        let requests = script(manager, [#"{"text":"ok"}"#])
        _ = try text(manager, ext, "").get()
        XCTAssertEqual(reads(), 0, "No permission, no read")
        XCTAssertNil(try object(requests()[0])["clipboard"])

        try FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let (off, offExt, offReads) = try self.manager(enabled: false)
        let offRequests = script(off, [])
        _ = text(off, offExt, "")
        XCTAssertEqual(offReads(), 0, "A disabled extension never reads the clipboard")
        XCTAssertNil(try object(offRequests()[0])["clipboard"])
    }

    func testAListRunReadsTheClipboardOnceForEveryRequest() throws {
        let (manager, ext, reads) = try manager(output: "items", input: nil)
        let requests = script(manager, [#"{"items":[{"title":"Decoded"}]}"#])
        var outcome: Result<[ExtensionItem], Error>?
        manager.runItems(ext, query: "", fetch: { _, _, _ in XCTFail("No hosts, no fetch") }) { outcome = $0 }
        XCTAssertEqual(try XCTUnwrap(outcome).get().map(\.title), ["Decoded"])
        XCTAssertEqual(try object(requests()[0])["clipboard"] as? String, "SGVsbG8=")
        XCTAssertEqual(reads(), 1)
    }

    func testAnInvalidReplyIsAnErrorAndSavesNothing() throws {
        let (manager, ext, _) = try manager(storage: true)
        _ = script(manager, ["not json"])
        guard case .failure(let error) = text(manager, ext, "") else { return XCTFail("Plain output from a JSON extension is invalid") }
        XCTAssertEqual(error.localizedDescription, "Extension returned an invalid reply.")
        XCTAssertFalse(manager.hasStoredData(ext))
    }

    func testTheApprovalPromptNamesClipboardReading() throws {
        let (_, ext, _) = try manager()
        XCTAssertEqual(ext.accessDescription, "Read your clipboard’s text when you run it")
    }
}
