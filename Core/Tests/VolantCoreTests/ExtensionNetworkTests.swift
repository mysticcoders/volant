import Foundation
import XCTest

@testable import VolantCore

/// The network-extension boundary: which hosts a manifest may declare, which planned URLs Volant
/// will fetch, how list output is trimmed, and how shared host approvals are stored and pruned.
final class ExtensionNetworkTests: XCTestCase {
    private func manifest(hosts: [String]? = nil, output: String? = nil, id: String = "community.fictional.reader") -> ExtensionManifest {
        ExtensionManifest(id: id, name: "Fictional Reader", version: "1", module: "reader.wasm", capabilities: [],
                          sha256: String(repeating: "a", count: 64), hosts: hosts, output: output)
    }

    func testHostsMustBeExactLowercaseNames() {
        for host in ["hn.algolia.com", "lobste.rs", "api.example-news.org"] { XCTAssertTrue(ExtensionNetwork.isValidHost(host), host) }
        for host in ["", "localhost", "HN.algolia.com", "*.algolia.com", "https://lobste.rs", "lobste.rs/", "lobste.rs:443",
                     "127.0.0.1", "-bad.example.com", "bad-.example.com", "exa mple.com", "例え.jp", "a..b.com"] {
            XCTAssertFalse(ExtensionNetwork.isValidHost(host), host)
        }
    }

    func testManifestHostsRequireListOutputAndStayBounded() {
        XCTAssertNoThrow(try manifest(hosts: ["lobste.rs"], output: "items").validate())
        XCTAssertNoThrow(try manifest(output: "items").validate())
        XCTAssertNoThrow(try manifest().validate())
        XCTAssertThrowsError(try manifest(hosts: ["lobste.rs"]).validate())
        XCTAssertThrowsError(try manifest(hosts: ["lobste.rs", "lobste.rs"], output: "items").validate())
        XCTAssertThrowsError(try manifest(hosts: ["*.rs"], output: "items").validate())
        XCTAssertThrowsError(try manifest(output: "html").validate())
        let many = (0...ExtensionNetwork.maximumHosts).map { "host\($0).example.com" }
        XCTAssertThrowsError(try manifest(hosts: many, output: "items").validate())
    }

    func testOlderManifestsKeepTheirFingerprintEncoding() throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let json = String(decoding: try encoder.encode(manifest()), as: UTF8.self)
        XCTAssertFalse(json.contains("hosts"))
        XCTAssertFalse(json.contains("output"))
    }

    func testOnlyHttpsURLsOnApprovedHostsArePermitted() {
        let hosts: Set = ["lobste.rs"]
        XCTAssertNotNil(ExtensionNetwork.permittedURL("https://lobste.rs/hottest.json", hosts: hosts))
        XCTAssertNotNil(ExtensionNetwork.permittedURL("https://LOBSTE.RS/newest.json", hosts: hosts))
        XCTAssertNotNil(ExtensionNetwork.permittedURL("https://lobste.rs:443/t/rust.json", hosts: hosts))
        for url in ["http://lobste.rs/hottest.json", "https://lobste.rs:8443/", "https://user:pass@lobste.rs/",
                    "https://lobste.rs.evil.example/", "https://evil.example/?lobste.rs", "https://sub.lobste.rs/",
                    "file:///etc/hosts", "https://lobste.rs/#frag", "https://" + String(repeating: "a", count: 3000)] {
            XCTAssertNil(ExtensionNetwork.permittedURL(url, hosts: hosts), url)
        }
    }

    func testPlansAreRejectedWholeWhenAnyURLIsOutOfBounds() throws {
        let hosts: Set = ["hn.algolia.com"]
        let urls = try ExtensionNetwork.plannedURLs(from: #"{"fetch":["https://hn.algolia.com/api/v1/search?tags=front_page"]}"#, hosts: hosts)
        XCTAssertEqual(urls.map(\.host), ["hn.algolia.com"])
        XCTAssertEqual(try ExtensionNetwork.plannedURLs(from: #"{"fetch":[]}"#, hosts: hosts), [])
        XCTAssertThrowsError(try ExtensionNetwork.plannedURLs(from: "not json", hosts: hosts)) {
            XCTAssertEqual($0 as? ExtensionNetworkError, .malformedPlan)
        }
        XCTAssertThrowsError(try ExtensionNetwork.plannedURLs(
            from: #"{"fetch":["https://hn.algolia.com/a","https://news.ycombinator.com/"]}"#, hosts: hosts)) {
            XCTAssertEqual($0 as? ExtensionNetworkError, .hostNotAllowed("https://news.ycombinator.com/"))
        }
        let five = (1...5).map { "\"https://hn.algolia.com/\($0)\"" }.joined(separator: ",")
        XCTAssertThrowsError(try ExtensionNetwork.plannedURLs(from: "{\"fetch\":[\(five)]}", hosts: hosts)) {
            XCTAssertEqual($0 as? ExtensionNetworkError, .tooManyFetches)
        }
    }

    func testRequestsCarryPhaseQueryTimeAndResponses() throws {
        let plan = try ExtensionNetwork.request(phase: "plan", query: "new", now: Date(timeIntervalSince1970: 1_791_000_000))
        XCTAssertEqual(plan, #"{"now":1791000000,"phase":"plan","query":"new"}"#)
        let render = try ExtensionNetwork.request(phase: "render", query: "", now: Date(timeIntervalSince1970: 5),
                                                  responses: [.init(url: "https://lobste.rs/hottest.json", status: 200, body: "[]")])
        XCTAssertTrue(render.contains(#""responses":[{"body":"[]","status":200,"url":"https:\/\/lobste.rs\/hottest.json"}]"#), render)
    }

    func testItemsDropUnsafeLinksAndBlankTitlesAndAreCapped() throws {
        let output = #"""
        {"items":[
          {"title":"  Fictional story  ","subtitle":"lobste.rs · 12 points","url":"https://example.com/a","secondaryURL":"https://lobste.rs/s/abc","secondaryTitle":"Open Comments"},
          {"title":"Script link","url":"javascript:alert(1)","secondaryURL":"file:///etc/passwd","secondaryTitle":"Bad"},
          {"title":"   "}
        ]}
        """#
        let items = try ExtensionNetwork.items(from: output)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].title, "Fictional story")
        XCTAssertEqual(items[0].secondaryTitle, "Open Comments")
        XCTAssertNil(items[1].url)
        XCTAssertNil(items[1].secondaryURL)
        XCTAssertNil(items[1].secondaryTitle)
        let many = (0..<150).map { "{\"title\":\"Story \($0)\"}" }.joined(separator: ",")
        XCTAssertEqual(try ExtensionNetwork.items(from: "{\"items\":[\(many)]}").count, ExtensionNetwork.maximumItems)
        XCTAssertThrowsError(try ExtensionNetwork.items(from: #"{"fetch":[]}"#))
    }

    func testHostApprovalsPreserveOtherSettingsAndPruneOnlyOrphans() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("volant-hosts-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"future":{"kept":true},"extensions":{}}"#.utf8).write(to: url)
        let lobsters = manifest(hosts: ["lobste.rs"], output: "items", id: "community.fictional.lobsters")
        let both = manifest(hosts: ["lobste.rs", "hn.algolia.com"], output: "items", id: "community.fictional.both")

        XCTAssertEqual(ExtensionHostApprovals.missing(both, at: url), ["lobste.rs", "hn.algolia.com"])
        try ExtensionHostApprovals.approve(both.declaredHosts, at: url)
        XCTAssertEqual(ExtensionHostApprovals.approved(at: url), ["lobste.rs", "hn.algolia.com"])
        XCTAssertEqual(ExtensionHostApprovals.missing(lobsters, at: url), [])

        let removed = try ExtensionHostApprovals.pruneAfterRemoving(both, remaining: [lobsters], at: url)
        XCTAssertEqual(removed, ["hn.algolia.com"])
        XCTAssertEqual(ExtensionHostApprovals.approved(at: url), ["lobste.rs"])

        try ExtensionHostApprovals.remove("lobste.rs", at: url)
        XCTAssertEqual(ExtensionHostApprovals.missing(lobsters, at: url), ["lobste.rs"])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual((object["future"] as? [String: Bool])?["kept"], true)
        XCTAssertNotNil(object["extensions"])

        try Data(#"{"extensionHosts":"lobste.rs"}"#.utf8).write(to: url)
        XCTAssertThrowsError(try ExtensionHostApprovals.approve(["lobste.rs"], at: url))
    }
}
