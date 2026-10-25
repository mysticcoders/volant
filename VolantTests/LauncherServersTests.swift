import CryptoKit
import VolantCore
import XCTest
@testable import Volant

/// The Servers command against a scripted helper: rows by kind and port, Return opens localhost,
/// Command-Return and the Actions menu copy, a late reply for an old query is dropped, and a read
/// failure is shown. Every server is fictional.
@MainActor
final class LauncherServersTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("launcher-servers-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private let fictional = [
        ListeningServer(pid: 4102, port: 8000, process: "python3.12", executable: "/opt/fictional/bin/python3.12", directory: "/Users/fictional/api", exposed: true),
        ListeningServer(pid: 4101, port: 3000, process: "node", executable: "/opt/fictional/bin/node", directory: "/Users/fictional/site", exposed: false),
        ListeningServer(pid: 4104, port: 7000, process: "ControlCenter", executable: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter", directory: nil, exposed: true),
    ]

    private func model() -> LauncherModel {
        let model = LauncherModel(index: AppIndex(entries: []),
            clipboard: ClipboardStore(retention: 10, storageURL: root.appendingPathComponent("clips.sqlite"), encryptionKey: SymmetricKey(size: .bits256)),
            notes: NotesStore(directory: root.appendingPathComponent("Notes")), config: Preferences(),
            usage: UsageStore(url: root.appendingPathComponent("usage.sqlite")), files: FileSearch(startQuery: { _ in false })) { _ in }
        model.searchesSecondarySources = false
        model.appleShortcuts.loadOverride = { $0([], nil) }
        model.dismiss = {}
        return model
    }

    private func settle() async { try? await Task.sleep(nanoseconds: 50_000_000) }

    func testRowsReturnAndCopies() async throws {
        let model = model()
        var opened: [URL] = [], copied: [String] = []
        model.openURL = { opened.append($0) }
        model.copyText = { copied.append($0) }
        model.servers.loadOverride = { [fictional] in $0(fictional, nil) }
        model.query = "servers"
        await settle()
        XCTAssertEqual(model.rows.map(\.id), ["server:4101:3000", "server:4102:8000"])
        XCTAssertEqual(model.sections.map(\.title), ["Dev Servers"])
        XCTAssertEqual(model.rows.first?.kind, "Local")
        XCTAssertEqual(model.rows.last?.kind, "Network")
        model.activateSelection()
        XCTAssertEqual(opened, [URL(string: "http://localhost:3000")!])
        model.selection = 1
        model.activateSecondary()
        XCTAssertEqual(copied, ["http://localhost:8000"])
        let row = try XCTUnwrap(model.selectedRow)
        XCTAssertEqual(row.itemActions, [.open, .reveal, .copyURL, .copyPort, .copyPID])
        model.performAction(.copyPort, target: row)
        model.performAction(.copyPID, target: row)
        XCTAssertEqual(copied.suffix(2), ["8000", "4102"])
        model.query = "servers all"
        await settle()
        XCTAssertEqual(model.sections.map(\.title), ["Dev Servers", "macOS Services"])
    }

    func testLateReplyForAnOldReadIsDroppedAndFailureIsShown() async throws {
        let model = model()
        var pending: [([ListeningServer]?, String?) -> Void] = []
        model.servers.loadOverride = { pending.append($0) }
        model.query = "servers"
        await settle()
        XCTAssertEqual(model.notice, "Reading listening servers…")
        model.servers.refresh(force: true)
        XCTAssertEqual(pending.count, 1, "A read already in flight is not started twice")
        pending[0](nil, "Fictional read failure")
        await settle()
        XCTAssertEqual(model.notice, "Fictional read failure")
        model.servers.loadOverride = { [fictional] in $0(fictional, nil) }
        model.servers.refresh(force: true)
        model.query = "caffeinate"
        await settle()
        XCTAssertFalse(model.rows.contains { $0.id.hasPrefix("server:") }, "Servers never replace a newer query's results")
    }
}
