import XCTest
import VolantCore
@testable import Volant

@MainActor
final class MCPApprovalsTests: XCTestCase {
    private var shown: [MCPApprovals.Request] = []
    private var hides = 0
    private var remembered: [String] = []
    private var preferences = MCPPreferences(enabled: true)

    /// Approvals whose prompt is recorded instead of drawn, so no window opens.
    private func approvals(timeout: TimeInterval = 60) -> MCPApprovals {
        let approvals = MCPApprovals(timeout: timeout)
        approvals.preferences = { [unowned self] in self.preferences }
        approvals.remember = { [unowned self] client, tool in self.remembered.append(MCPPreferences.grant(client: client, tool: tool)) }
        approvals.show = { [unowned self] in self.shown.append($0.current!) }
        approvals.hide = { [unowned self] _ in self.hides += 1 }
        return approvals
    }

    /// Starts an ask and waits until its prompt is on screen.
    private func start(_ approvals: MCPApprovals, _ tool: String = "search_clipboard") -> Task<Bool, Never> {
        let task = Task { await approvals.ask(client: "claude-code", tool: tool, summary: "Search your clipboard history for “invoice”") }
        return task
    }

    private func settle() async { for _ in 0..<5 { await Task.yield(); RunLoop.main.run(until: Date().addingTimeInterval(0.02)) } }

    func testAllowOnceAlwaysAndDeny() async {
        let approvals = approvals()
        let once = start(approvals)
        await settle()
        XCTAssertEqual(shown.last?.client, "claude-code")
        approvals.decide(.once)
        let onceAllowed = await once.value
        XCTAssertTrue(onceAllowed)
        XCTAssertTrue(remembered.isEmpty)
        let denied = start(approvals)
        await settle()
        approvals.decide(.deny)
        let deniedAllowed = await denied.value
        XCTAssertFalse(deniedAllowed)
        let always = start(approvals)
        await settle()
        approvals.decide(.always)
        let alwaysAllowed = await always.value
        XCTAssertTrue(alwaysAllowed)
        XCTAssertEqual(remembered, ["claude-code/search_clipboard"])
        XCTAssertEqual(hides, 3, "The prompt closes when nothing else waits")
    }

    func testAlwaysAllowedRequestsDontPrompt() async {
        preferences.alwaysAllowed = ["claude-code/search_clipboard"]
        let allowed = await approvals().ask(client: "claude-code", tool: "search_clipboard", summary: "x")
        XCTAssertTrue(allowed)
        XCTAssertTrue(shown.isEmpty)
        let other = start(approvals(), "search_files")
        await settle()
        XCTAssertEqual(shown.count, 1, "Always Allow covers only that tool")
        other.cancel()
    }

    func testOnePromptAtATimeInOrder() async {
        let approvals = approvals()
        let first = start(approvals, "search_clipboard")
        await settle()
        let second = start(approvals, "search_files")
        await settle()
        XCTAssertEqual(shown.map(\.tool), ["search_clipboard"], "The second waits")
        approvals.decide(.deny)
        await settle()
        XCTAssertEqual(shown.map(\.tool), ["search_clipboard", "search_files"])
        approvals.decide(.once)
        let firstAllowed = await first.value
        let secondAllowed = await second.value
        XCTAssertFalse(firstAllowed)
        XCTAssertTrue(secondAllowed)
    }

    func testAnUnansweredPromptIsDenied() async {
        let approvals = approvals(timeout: 0.1)
        let request = start(approvals)
        await settle()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let allowed = await request.value
        XCTAssertFalse(allowed)
        XCTAssertNil(approvals.current)
    }
}

@MainActor
final class MCPSensitiveToolTests: XCTestCase {
    private var asked: [String] = []
    private var allow = true
    private var reads = 0

    private func toolbox() -> MCPToolbox {
        let root = FileManager.default.temporaryDirectory
        return MCPToolbox(notes: NotesStore(directory: root.appendingPathComponent(UUID().uuidString)), configURL: root.appendingPathComponent("none.json"),
                          breakHistoryURL: root.appendingPathComponent("none-history.json"),
                          approve: { [unowned self] client, tool, summary in self.asked.append("\(client)|\(tool)|\(summary)"); return self.allow },
                          clipboard: { [unowned self] query, limit in
                              self.reads += 1
                              return [(String(repeating: "x", count: 2_500), Date(timeIntervalSince1970: 0)), ("invoice 42 \(query) \(limit)", Date(timeIntervalSince1970: 1))]
                          },
                          files: { [unowned self] term in self.reads += 1; return [FileEntry(id: "/Users/me/\(term).pdf", name: "\(term).pdf", url: URL(fileURLWithPath: "/Users/me/\(term).pdf"), kind: "PDF document")] },
                          currency: { _ in nil },
                          weather: { place in
                              (WeatherReport(forecast: ExtensionItemForecast(place: place, condition: "Clear", temperature: 21, high: 24, low: 14), legalURL: "https://weatherkit.apple.com/legal-attribution.html"), nil)
                          })
    }

    private func call(_ name: String, _ arguments: [String: MCPValue], preferences: MCPPreferences) async -> MCPToolResult? {
        await toolbox().tools(preferences, client: "claude-code").first { $0.name == name }?.call(arguments)
    }

    private let all = MCPPreferences(enabled: true, sharesClipboard: true, searchesFiles: true, convertsCurrency: true, checksWeather: true)

    func testSensitiveToolsNeedTheirSwitches() {
        let none = toolbox().tools(MCPPreferences(enabled: true), client: "c").map(\.name)
        XCTAssertFalse(none.contains("search_clipboard") || none.contains("search_files") || none.contains("convert_currency") || none.contains("get_weather"))
        let names = toolbox().tools(all, client: "c").map(\.name)
        XCTAssertTrue(["search_clipboard", "search_files", "convert_currency", "get_weather"].allSatisfy(names.contains))
    }

    func testEachCallAsksNamingTheAppAndTheRequest() async {
        let result = await call("search_clipboard", ["query": .string("invoice"), "limit": .int(5)], preferences: all)
        XCTAssertEqual(asked, ["claude-code|search_clipboard|Search your clipboard history for “invoice”"])
        guard case .array(let entries)? = result?.structured?["entries"] else { return XCTFail("no entries") }
        XCTAssertEqual(entries.first?["truncated"], .bool(true))
        XCTAssertEqual(entries.first?["text"]?.string?.count, 2_000)
        XCTAssertEqual(entries.last?["text"], .string("invoice 42 invoice 5"))
    }

    func testDeniedRequestsReadNothing() async {
        allow = false
        for (name, arguments) in [("search_clipboard", ["query": MCPValue.string("pw")]), ("search_files", ["term": .string("taxes")]),
                                  ("get_weather", ["place": .string("Tokyo")]), ("convert_currency", ["query": .string("5 USD in EUR")])] {
            let result = await call(name, arguments, preferences: all)
            XCTAssertEqual(result?.isError, true, name)
            XCTAssertEqual(result?.text, MCPToolbox.denied, name)
        }
        XCTAssertEqual(reads, 0)
    }

    func testInvalidRequestsAreRefusedBeforeAsking() async {
        let empty = await call("search_clipboard", ["query": .string("  ")], preferences: all)
        let short = await call("search_files", ["term": .string("ab")], preferences: all)
        let place = await call("get_weather", ["place": .string(String(repeating: "x", count: 101))], preferences: all)
        XCTAssertEqual([empty?.isError, short?.isError, place?.isError], [true, true, true])
        XCTAssertTrue(asked.isEmpty, "Nothing invalid reaches the owner")
    }

    func testWeatherCarriesAppleAttributionAndCurrencyFailureIsActionable() async {
        let weather = await call("get_weather", ["place": .string("Tokyo")], preferences: all)
        XCTAssertEqual(weather?.structured?["attribution"], .string("Weather data from Apple Weather"))
        XCTAssertEqual(weather?.structured?["legalURL"], .string("https://weatherkit.apple.com/legal-attribution.html"))
        XCTAssertEqual(weather?.structured?["temperatureCelsius"], .double(21))
        let files = await call("search_files", ["term": .string("taxes")], preferences: all)
        XCTAssertEqual(files?.structured?["files"], .array([.object(["name": .string("taxes.pdf"), "path": .string("/Users/me/taxes.pdf")])]))
        let currency = await call("convert_currency", ["query": .string("5 USD in EUR")], preferences: all)
        XCTAssertEqual(currency?.isError, true)
    }
}
