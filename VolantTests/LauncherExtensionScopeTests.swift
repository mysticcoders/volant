import CryptoKit
import VolantCore
import XCTest
@testable import Volant

/// Entering a list extension from the launcher: Return clears the field and hands it to the extension,
/// typing runs it again once typing pauses, a search extension waits for input, and Escape or Back
/// returns to the launcher. A scripted module stands in for the extension helper; every file is
/// temporary and fictional.
@MainActor
final class LauncherExtensionScopeTests: XCTestCase {
    private var root: URL!
    private var config: URL { root.appendingPathComponent("config.json") }
    private var folder: URL { root.appendingPathComponent("reader", isDirectory: true) }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("extension-scope-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"extensions":{},"communityExtensionsAllowed":true}"#.utf8).write(to: config)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// A launcher with one enabled list extension, Fictional Reader, in the given mode.
    private func model(mode: String? = nil, placeholder: String? = nil, filters: [ExtensionFilter]? = nil) throws -> LauncherModel {
        let module = Data([0, 97, 115, 109, 1, 0, 0, 0, 5, 4, 1, 1, 1, 1])
        try module.write(to: folder.appendingPathComponent("reader.wasm"))
        let manifest = ExtensionManifest(id: "community.fictional.reader", name: "Fictional Reader", version: "1", module: "reader.wasm",
                                         capabilities: [], timeoutSeconds: 2, sha256: Integrity.sha256(module), output: "items",
                                         mode: mode, placeholder: placeholder, filters: filters)
        try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent("manifest.json"))
        let model = LauncherModel(index: AppIndex(entries: []),
            clipboard: ClipboardStore(retention: 10, storageURL: root.appendingPathComponent("clips.sqlite"), encryptionKey: SymmetricKey(size: .bits256)),
            notes: NotesStore(directory: root.appendingPathComponent("Notes")), config: Preferences(),
            usage: UsageStore(url: root.appendingPathComponent("usage.sqlite")), files: FileSearch(startQuery: { _ in false })) { _ in }
        model.searchesSecondarySources = false
        model.appleShortcuts.loadOverride = { $0([], nil) }
        model.actionConfigURL = config
        model.extensions = ExtensionManager(configURL: config, roots: [folder], dataDirectory: root.appendingPathComponent("ExtensionData"))
        model.extensions.reload()
        try model.extensions.setEnabled(try XCTUnwrap(model.extensions.extensions.first), true)
        model.dismiss = {}
        return model
    }

    /// Answers every run with one row titled after its query, and records each query.
    private func echo(_ model: LauncherModel) -> () -> [String] {
        var queries: [String] = []
        model.extensions.invokeOverride = { _, input, completion in
            let query = Self.query(in: input)
            queries.append(query)
            completion(.success(#"{"items":[{"title":"Row for \#(query)","url":"https://example.com/\#(queries.count)"}]}"#))
        }
        return { queries }
    }

    private static func filter(in request: String) -> String? {
        let object = try? JSONSerialization.jsonObject(with: Data(request.utf8)) as? [String: Any]
        return object?["filter"] as? String
    }

    private static func query(in request: String) -> String {
        let object = try? JSONSerialization.jsonObject(with: Data(request.utf8)) as? [String: Any]
        return object?["query"] as? String ?? ""
    }

    /// Types `query`, then chooses the extension's row.
    private func enter(_ model: LauncherModel, typing query: String) throws {
        model.query = query
        let row = try XCTUnwrap(model.rows.first { if case .extensionRun = $0 { return true }; return false })
        model.activate(rowID: row.id)
    }

    private func titles(_ model: LauncherModel) -> [String] {
        model.rows.compactMap { if case .extensionItem(let item, _) = $0 { return item.title }; return nil }
    }

    private func wait(_ seconds: TimeInterval) async {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { await Task.yield(); try? await Task.sleep(nanoseconds: 20_000_000) }
    }

    func testReturnEntersAListExtensionAndTypingRunsItAgain() async throws {
        let model = try model()
        let queries = echo(model)
        try enter(model, typing: "Fictional Reader")
        XCTAssertEqual(model.scopedExtension?.id, "community.fictional.reader")
        XCTAssertEqual(model.query, "", "Entering clears the field")
        XCTAssertEqual(model.searchPlaceholder, "Search Fictional Reader…")
        await wait(0.1)
        XCTAssertEqual(titles(model), ["Row for"], "A list extension runs as soon as it is entered")
        model.query = "n"
        model.query = "ne"
        model.query = "new"
        await wait(0.1)
        XCTAssertEqual(queries(), [""], "Typing waits for a pause before running")
        await wait(LauncherModel.scopeDelay + 0.1)
        XCTAssertEqual(queries(), ["", "new"], "Only the text at the pause runs")
        XCTAssertEqual(titles(model), ["Row for new"])
        model.query = "translate"
        XCTAssertFalse(model.showingTranslation, "Inside an extension the text is its own, never a launcher command")
        XCTAssertFalse(model.canTabToAIChat, "Tab stays in the extension")
    }

    func testTextAfterTheKeywordCarriesIntoTheExtension() async throws {
        let model = try model()
        let queries = echo(model)
        try enter(model, typing: "Fictional Reader hello")
        XCTAssertEqual(model.query, "hello")
        await wait(0.1)
        XCTAssertEqual(queries(), ["hello"], "The keyword's text runs at once")
        XCTAssertEqual(titles(model), ["Row for hello"])
    }

    func testASearchExtensionWaitsForInput() async throws {
        let model = try model(mode: "search", placeholder: "Search fictional articles")
        let queries = echo(model)
        try enter(model, typing: "Fictional Reader")
        await wait(0.1)
        XCTAssertEqual(queries(), [], "Nothing runs before something is typed")
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertEqual(model.notice, "Search fictional articles")
        XCTAssertEqual(model.searchPlaceholder, "Search fictional articles")
        model.query = "moon"
        await wait(LauncherModel.scopeDelay + 0.1)
        XCTAssertEqual(queries(), ["moon"])
        model.query = ""
        await wait(LauncherModel.scopeDelay + 0.1)
        XCTAssertEqual(queries(), ["moon"], "Clearing the field shows the prompt again without running")
        XCTAssertTrue(model.rows.isEmpty)
    }

    func testEscapeClearsTheFieldThenLeaves() async throws {
        let model = try model()
        _ = echo(model)
        try enter(model, typing: "Fictional Reader")
        model.query = "new"
        XCTAssertTrue(model.backOutOfScope())
        XCTAssertEqual(model.query, "")
        XCTAssertNotNil(model.scopedExtension, "The first Escape only clears the text")
        XCTAssertTrue(model.backOutOfScope())
        XCTAssertNil(model.scopedExtension)
        XCTAssertFalse(model.backOutOfScope(), "Outside an extension Escape is the launcher's own")
        XCTAssertEqual(model.searchPlaceholder, "Search for apps, files, contacts, or calculate…")
        XCTAssertTrue(model.sections.contains { $0.title == "Commands" }, "Back shows the launcher's suggestions")
        await wait(LauncherModel.scopeDelay + 0.1)
        XCTAssertTrue(titles(model).isEmpty, "A run scheduled before leaving never shows its rows")
    }

    func testTypingDuringARunRunsTheNewTextAfterIt() async throws {
        let model = try model()
        var pending: [(String, (Result<String, Error>) -> Void)] = []
        model.extensions.invokeOverride = { _, input, completion in pending.append((Self.query(in: input), completion)) }
        try enter(model, typing: "Fictional Reader")
        await wait(0.1)
        XCTAssertEqual(pending.map(\.0), [""])
        model.query = "ask"
        await wait(LauncherModel.scopeDelay + 0.1)
        XCTAssertEqual(pending.count, 1, "A second run waits for the first")
        pending[0].1(.success(#"{"items":[{"title":"Stale"}]}"#))
        await wait(0.1)
        XCTAssertEqual(pending.map(\.0), ["", "ask"], "The new text runs once the first finishes")
        XCTAssertTrue(titles(model).isEmpty, "The first run's rows are dropped")
        pending[1].1(.success(#"{"items":[{"title":"Ask rows"}]}"#))
        await wait(0.1)
        XCTAssertEqual(titles(model), ["Ask rows"])
    }

    func testTheDropdownSendsItsFilterAndRemembersTheChoice() async throws {
        let pages = [ExtensionFilter(id: "top", title: "Top"), ExtensionFilter(id: "new", title: "New"), ExtensionFilter(id: "ask", title: "Ask")]
        let model = try model(filters: pages)
        var requests: [(query: String, filter: String?)] = []
        model.extensions.invokeOverride = { _, input, completion in
            requests.append((Self.query(in: input), Self.filter(in: input)))
            completion(.success(#"{"items":[{"title":"Row","url":"https://example.com/\#(requests.count)"}]}"#))
        }
        try enter(model, typing: "Fictional Reader")
        XCTAssertEqual(model.scopeFilter, "top", "The first filter is the default")
        await wait(0.1)
        XCTAssertEqual(requests.last?.filter, "top")
        model.query = "rust"
        await wait(LauncherModel.scopeDelay + 0.1)
        model.chooseScopeFilter("new")
        await wait(0.1)
        XCTAssertEqual(requests.last?.query, "rust", "Choosing a filter keeps the typed text")
        XCTAssertEqual(requests.last?.filter, "new", "and runs at once with the new filter")
        XCTAssertTrue(model.cycleScopeFilter())
        XCTAssertEqual(model.scopeFilter, "ask")
        XCTAssertTrue(model.cycleScopeFilter())
        XCTAssertEqual(model.scopeFilter, "top", "Command-P wraps to the first filter")
        model.chooseScopeFilter("missing")
        XCTAssertEqual(model.scopeFilter, "top", "Only declared filters can be chosen")
        model.chooseScopeFilter("ask")
        model.exitScope()
        XCTAssertNil(model.scopeFilter)
        XCTAssertFalse(model.cycleScopeFilter(), "Outside an extension Command-P is not claimed")
        try enter(model, typing: "Fictional Reader")
        XCTAssertEqual(model.scopeFilter, "ask", "Entering again keeps the last choice")
    }

    func testExtensionsWithoutFiltersSendNone() async throws {
        let model = try model()
        var filters: [String?] = []
        model.extensions.invokeOverride = { _, input, completion in
            filters.append(Self.filter(in: input))
            completion(.success(#"{"items":[]}"#))
        }
        try enter(model, typing: "Fictional Reader")
        await wait(0.1)
        XCTAssertEqual(filters, [nil])
        XCTAssertNil(model.scopeFilter)
        XCTAssertFalse(model.cycleScopeFilter())
    }

    func testResetLeavesTheExtension() throws {
        let model = try model()
        _ = echo(model)
        try enter(model, typing: "Fictional Reader")
        model.reset()
        XCTAssertNil(model.scopedExtension)
    }

    func testModeAndPlaceholderAreValidatedAndLeaveApprovalAlone() throws {
        let base = ExtensionManifest(id: "community.fictional.reader", name: "Fictional Reader", version: "1", module: "reader.wasm",
                                     capabilities: [], sha256: String(repeating: "a", count: 64), output: "items")
        var scoped = base
        scoped.mode = "search"
        scoped.placeholder = "Search fictional articles"
        XCTAssertNoThrow(try scoped.validate())
        XCTAssertEqual(try ExtensionApproval.fingerprint(scoped), try ExtensionApproval.fingerprint(base),
                       "Changing how an extension looks never asks to enable it again")
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
        XCTAssertEqual(try ExtensionApproval.fingerprint(filtered), try ExtensionApproval.fingerprint(base), "Filters never ask to enable again")
        var single = base; single.filters = [ExtensionFilter(id: "top", title: "Top")]
        XCTAssertThrowsError(try single.validate(), "A dropdown needs at least two choices")
        var duplicate = base; duplicate.filters = [ExtensionFilter(id: "top", title: "Top"), ExtensionFilter(id: "top", title: "Again")]
        XCTAssertThrowsError(try duplicate.validate())
        var badID = base; badID.filters = [ExtensionFilter(id: "Top Stories", title: "Top"), ExtensionFilter(id: "new", title: "New")]
        XCTAssertThrowsError(try badID.validate())
        var textFilters = filtered; textFilters.output = nil
        XCTAssertThrowsError(try textFilters.validate(), "Only list extensions have a dropdown")
    }
}
