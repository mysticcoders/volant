import Foundation
import XCTest
#if canImport(Darwin)
import Darwin
#endif

@testable import VolantCore

/// The fsearch client against a fake daemon on a temporary socket: requests, reply validation,
/// errors, and the bounds on time and size. Nothing here reaches a real fsearch.
final class FSearchTests: XCTestCase {
    private var socketPath = ""

    override func setUp() {
        socketPath = "/tmp/vfs-\(UUID().uuidString.prefix(8)).sock"
    }

    override func tearDown() { unlink(socketPath) }

    /// Serves one connection: records the request line, then sends `reply` (or nothing).
    private func serve(_ reply: Data?, received: @escaping (Data) -> Void = { _ in }) {
        let server = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(socketPath.utf8)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes); $0[bytes.count] = 0 }
        _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(server, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        Darwin.listen(server, 1)
        Thread.detachNewThread {
            let client = accept(server, nil, nil)
            var buffer = [UInt8](repeating: 0, count: 4096)
            let count = recv(client, &buffer, buffer.count, 0)
            received(Data(buffer[0..<max(0, count)]))
            if let reply { _ = reply.withUnsafeBytes { send(client, $0.baseAddress, reply.count, 0) } }
            else { Thread.sleep(forTimeInterval: 1.5) }
            close(client); close(server)
        }
    }

    func testRequestsAreSingleBoundedLines() throws {
        let search = try XCTUnwrap(FSearch.searchRequest("  main.rs ", limit: 500))
        XCTAssertEqual(String(decoding: search, as: UTF8.self), #"{"limit":50,"op":"search","q":"main.rs"}"# + "\n")
        XCTAssertNil(FSearch.searchRequest("", limit: 5))
        XCTAssertNil(FSearch.searchRequest("two\nlines", limit: 5))
        XCTAssertNil(FSearch.searchRequest(String(repeating: "x", count: 257), limit: 5))
        XCTAssertEqual(String(decoding: try XCTUnwrap(FSearch.openedRequest("/Users/me/a.txt")), as: UTF8.self), #"{"op":"open","path":"\/Users\/me\/a.txt"}"# + "\n")
        XCTAssertNil(FSearch.openedRequest("relative/a.txt"))
        XCTAssertEqual(FSearch.socketPath(home: "/Users/me"), "/Users/me/Library/Application Support/FSearch/fsearch.sock")
    }

    func testHitsKeepOnlyUsableAbsolutePathsAndBoundedFields() throws {
        let reply = Data(#"{"hits":[{"kind":"file","mtime":1,"path":"/a/main.rs","score":441,"size":9},{"kind":"dir","path":"/a/src"},{"path":"relative"},{"kind":"file"}],"ok":true}"#.utf8)
        let hits = try FSearch.hits(from: reply)
        XCTAssertEqual(hits.map(\.path), ["/a/main.rs", "/a/src"])
        XCTAssertTrue(hits[1].isFolder)
        XCTAssertEqual(hits[0].score, 441)
        let many = Data(("{\"hits\":[" + (0..<80).map { "{\"path\":\"/f\($0)\"}" }.joined(separator: ",") + "]}").utf8)
        XCTAssertEqual(try FSearch.hits(from: many).count, FSearch.maximumHits)
        XCTAssertThrowsError(try FSearch.hits(from: Data("nope".utf8))) { XCTAssertEqual($0 as? FSearchError, .malformed) }
        XCTAssertThrowsError(try FSearch.hits(from: Data(#"{"ok":false,"error":"indexing: 0.0M entries so far"}"#.utf8))) {
            XCTAssertEqual($0 as? FSearchError, .daemon("indexing: 0.0M entries so far"))
        }
        XCTAssertEqual(try FSearch.status(from: Data(#"{"entries":9483489,"full_disk_access":false,"ok":true}"#.utf8)),
                       FSearch.Status(entries: 9_483_489, fullDiskAccess: false))
    }

    func testExchangeSendsOneLineAndReadsOneReply() throws {
        var sent = Data()
        let done = expectation(description: "request received")
        serve(Data(#"{"hits":[{"kind":"file","path":"/x/y.swift"}],"ok":true}"#.utf8) + Data([0x0A]) + Data("ignored".utf8)) { sent = $0; done.fulfill() }
        let reply = try FSearch.exchange(socket: socketPath, request: try XCTUnwrap(FSearch.searchRequest("y", limit: 5)))
        wait(for: [done], timeout: 2)
        XCTAssertEqual(String(decoding: sent, as: UTF8.self), #"{"limit":5,"op":"search","q":"y"}"# + "\n")
        XCTAssertEqual(try FSearch.hits(from: reply).map(\.path), ["/x/y.swift"])
    }

    func testMissingDaemonSilenceAndOversizedRepliesAreErrors() throws {
        XCTAssertThrowsError(try FSearch.exchange(socket: socketPath, request: FSearch.statusRequest)) { XCTAssertEqual($0 as? FSearchError, .notRunning) }
        serve(nil)
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertThrowsError(try FSearch.exchange(socket: socketPath, request: FSearch.statusRequest, timeout: 0.3)) { XCTAssertEqual($0 as? FSearchError, .timedOut) }
        unlink(socketPath)
        serve(Data(repeating: 0x41, count: 4096))
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertThrowsError(try FSearch.exchange(socket: socketPath, request: FSearch.statusRequest, maximumBytes: 1024)) { XCTAssertEqual($0 as? FSearchError, .tooLarge) }
    }
}
