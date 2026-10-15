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
        XCTAssertFalse(json.contains("secrets"))
        XCTAssertFalse(json.contains("appLinks"))
        XCTAssertFalse(json.contains("permissions"))
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
        let plan = try ExtensionNetwork.request(phase: "plan", query: "new", now: Date(timeIntervalSince1970: 1_791_000_000), units: "metric")
        XCTAssertEqual(plan, #"{"now":1791000000,"phase":"plan","query":"new","units":"metric"}"#)
        let render = try ExtensionNetwork.request(phase: "render", query: "", now: Date(timeIntervalSince1970: 5),
                                                  responses: [.init(url: "https://lobste.rs/hottest.json", status: 200, body: "[]")])
        XCTAssertTrue(render.contains(#""responses":[{"body":"[]","status":200,"url":"https:\/\/lobste.rs\/hottest.json"}]"#), render)
    }

    func testRendersReceiveTheStateTheirPlanReturned() throws {
        let render = try ExtensionNetwork.request(phase: "render", query: "paris", now: Date(timeIntervalSince1970: 0),
                                                  responses: [], state: "geocode", units: "us")
        XCTAssertTrue(render.contains(#""state":"geocode""#), render)
        XCTAssertTrue(render.contains(#""units":"us""#), render)
    }

    func testRoundsCarryStateAndRejectOversizedState() throws {
        let hosts: Set = ["api.open-meteo.com"]
        let round = try ExtensionNetwork.plannedFetch(from: #"{"fetch":["https://api.open-meteo.com/v1/forecast"],"state":"forecast:Paris"}"#, hosts: hosts)
        XCTAssertEqual(round.urls.map(\.host), ["api.open-meteo.com"])
        XCTAssertEqual(round.state, "forecast:Paris")
        XCTAssertNil(try ExtensionNetwork.plannedFetch(from: #"{"fetch":[]}"#, hosts: hosts).state)
        let huge = String(repeating: "x", count: ExtensionNetwork.maximumStateBytes + 1)
        XCTAssertThrowsError(try ExtensionNetwork.plannedFetch(from: "{\"fetch\":[],\"state\":\"\(huge)\"}", hosts: hosts)) {
            XCTAssertEqual($0 as? ExtensionNetworkError, .malformedPlan)
        }
    }

    func testUnitsFollowTheMeasurementSystem() {
        XCTAssertEqual(ExtensionNetwork.units(for: Locale(identifier: "en_US")), "us")
        XCTAssertEqual(ExtensionNetwork.units(for: Locale(identifier: "en_GB")), "metric")
        XCTAssertEqual(ExtensionNetwork.units(for: Locale(identifier: "fr_FR")), "metric")
    }

    func testSecretsMustNameADeclaredHostAndASafeHeader() {
        func withSecret(_ secret: ExtensionSecret) -> ExtensionManifest {
            var manifest = manifest(hosts: ["api.tasks.example.com"], output: "items"); manifest.secrets = [secret]; return manifest
        }
        let token = ExtensionSecret(id: "token", title: "Fictional API token", host: "api.tasks.example.com", header: "Authorization", prefix: "Bearer ")
        XCTAssertNoThrow(try withSecret(token).validate())
        var other = token; other.host = "elsewhere.example.com"
        XCTAssertThrowsError(try withSecret(other).validate(), "a secret's host must be declared")
        var cookie = token; cookie.header = "Cookie"
        XCTAssertThrowsError(try withSecret(cookie).validate(), "only Authorization and X-API-Key")
        var newline = token; newline.prefix = "Bearer\n"
        XCTAssertThrowsError(try withSecret(newline).validate())
        var shouty = token; shouty.id = "Token"
        XCTAssertThrowsError(try withSecret(shouty).validate())
        XCTAssertEqual(token.headerValue("abc"), "Bearer abc")
        XCTAssertTrue(ExtensionSecret.isValidValue("fictional-token-123"))
        for bad in ["", "has space", "line\nbreak", String(repeating: "a", count: ExtensionSecret.maximumValueBytes + 1)] {
            XCTAssertFalse(ExtensionSecret.isValidValue(bad), bad)
        }
    }

    func testAppLinksAreDeclaredSchemesThatAreNeverSystemOrFileLinks() throws {
        var todoist = manifest(hosts: ["api.todoist.com"], output: "items"); todoist.appLinks = ["todoist"]
        XCTAssertNoThrow(try todoist.validate())
        for refused in ["file", "javascript", "https", "x-apple.systempreferences", "x-apple-reminderkit", "ssh", "Todoist", "t", "1abc", "to do"] {
            var bad = todoist; bad.appLinks = [refused]
            XCTAssertThrowsError(try bad.validate(), refused)
        }
        var text = manifest(); text.appLinks = ["todoist"]
        XCTAssertThrowsError(try text.validate(), "app links belong to list extensions")
        let output = #"{"items":[{"title":"Task","url":"todoist://task?id=6Xa","secondaryURL":"https://app.todoist.com/app/task/6Xa"},{"title":"Sneaky","url":"file:///etc/hosts","secondaryURL":"slack://open"}]}"#
        let declared = try ExtensionNetwork.items(from: output, appLinks: ["todoist"])
        XCTAssertEqual(declared[0].url, "todoist://task?id=6Xa")
        XCTAssertNil(declared[1].url)
        XCTAssertNil(declared[1].secondaryURL, "an undeclared app's link is dropped")
        XCTAssertNil(try ExtensionNetwork.items(from: output)[0].url, "without the declaration the app link is dropped")
        XCTAssertNil(try ExtensionNetwork.items(from: #"{"items":[{"title":"x","url":"file:///etc/hosts"}]}"#, appLinks: ["file"])[0].url,
                     "a refused scheme stays refused even if a reply claims it")
    }

    func testLocationIsRoundedPerExtensionAndOnlyForListExtensions() throws {
        let here = try XCTUnwrap(ExtensionLocation(latitude: 37.8734, longitude: -122.2711))
        XCTAssertEqual(here, ExtensionLocation(latitude: 37.9, longitude: -122.3))
        XCTAssertNil(ExtensionLocation(latitude: 91, longitude: 0))
        XCTAssertNil(ExtensionLocation(latitude: .nan, longitude: 0))
        var weather = manifest(hosts: ["api.open-meteo.com"], output: "items", id: "community.fictional.weather"); weather.permissions = ["location"]
        XCTAssertNoThrow(try weather.validate())
        XCTAssertTrue(weather.wantsLocation)
        var unknown = weather; unknown.permissions = ["contacts"]
        XCTAssertThrowsError(try unknown.validate())
        var text = manifest(); text.permissions = ["location"]
        XCTAssertThrowsError(try text.validate(), "only list extensions may ask for location")
        let request = try ExtensionNetwork.request(phase: "plan", query: "", now: Date(timeIntervalSince1970: 0), units: "us", location: here)
        XCTAssertTrue(request.contains(#""location":{"latitude":37.9,"longitude":-122.3}"#), request)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("volant-location-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"future":{"kept":true},"extensionHosts":["api.open-meteo.com"]}"#.utf8).write(to: url)
        XCTAssertTrue(ExtensionLocationApprovals.missing(weather, at: url))
        try ExtensionLocationApprovals.approve(weather.id, at: url)
        XCTAssertFalse(ExtensionLocationApprovals.missing(weather, at: url))
        var other = weather; other.id = "community.fictional.other"
        XCTAssertTrue(ExtensionLocationApprovals.missing(other, at: url), "a grant is never shared with another extension")
        let restored = BackupFolder.withoutPerMacGrants(try Data(contentsOf: url))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: restored) as? [String: Any])
        XCTAssertNil(object[ExtensionLocationApprovals.key], "a restored backup asks again for location")
        XCTAssertNotNil(object["future"]); XCTAssertNotNil(object["extensionHosts"])
        let plain = Data(#"{"a":1}"#.utf8)
        XCTAssertEqual(BackupFolder.withoutPerMacGrants(plain), plain, "config without a grant is restored byte for byte")
        try ExtensionLocationApprovals.remove(weather.id, at: url)
        XCTAssertTrue(ExtensionLocationApprovals.missing(weather, at: url))
    }

    func testNoticesAndPrimaryActionsAreBounded() throws {
        let reply = try ExtensionNetwork.reply(from: "{\"notice\":\"  " + String(repeating: "n", count: 200) + "  \"}")
        XCTAssertEqual(reply.notice?.count, ExtensionNetwork.maximumNoticeLength)
        XCTAssertNil(reply.items)
        XCTAssertThrowsError(try ExtensionNetwork.reply(from: #"{"notice":"   "}"#), "a blank notice alone is malformed")
        let items = try ExtensionNetwork.items(from: #"{"items":[{"title":"Add","primaryAction":"add"},{"title":"Bad","primaryAction":"Not An Id"}]}"#)
        XCTAssertEqual(items.map(\.primaryAction), ["add", nil])
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
