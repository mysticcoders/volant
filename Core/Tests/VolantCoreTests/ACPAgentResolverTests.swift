import XCTest

@testable import VolantCore

/// Detection and connection share one lookup, exercised against a fictional file system.
final class ACPAgentResolverTests: XCTestCase {
    private let home = "/Users/fixture"

    private func resolver(_ executables: Set<String>, files: Set<String> = [], directories: [String: [String]] = [:]) -> ACPAgentResolver {
        ACPAgentResolver(home: home, isExecutable: { executables.contains($0) }, exists: { files.contains($0) },
                         contents: { directories[$0] ?? [] })
    }

    func testNothingInstalledReportsEveryProviderMissing() {
        let found = resolver([]).detectAll()
        XCTAssertEqual(found.map(\.provider), ACPProvider.allCases.map(\.rawValue))
        XCTAssertTrue(found.allSatisfy { $0.state == .notInstalled && $0.path == nil })
    }

    func testClaudeNeedsItsCLIThenTheAdapterThenNode() throws {
        let cli = home + "/.local/bin/claude"
        let adapter = home + "/.local/share/volant/acp/node_modules/@agentclientprotocol/claude-agent-acp/dist/index.js"
        XCTAssertEqual(resolver([]).availability(.claude).state, .notInstalled)
        XCTAssertEqual(resolver([cli]).availability(.claude).state, .needsAdapter)
        XCTAssertEqual(resolver([cli], files: [adapter]).availability(.claude).state, .needsNode)
        let ready = resolver([cli, "/opt/homebrew/bin/node"], files: [adapter])
        XCTAssertEqual(ready.availability(.claude).state, .ready)
        XCTAssertEqual(ready.availability(.claude).detail, "Found at ~/.local/bin/claude")
        let launch = try ready.launch(.claude)
        XCTAssertEqual(launch, ACPLaunch(executable: "/opt/homebrew/bin/node", arguments: [adapter], environment: ["CLAUDE_CODE_EXECUTABLE": cli]))
    }

    func testNodeFromAVersionManagerPrefersTheNewestVersion() throws {
        let root = home + "/.nvm/versions/node"
        let adapter = home + "/.local/share/volant/acp/node_modules/@agentclientprotocol/codex-acp/dist/index.js"
        let found = resolver(["/usr/local/bin/codex", root + "/v22.1.0/bin/node", root + "/v24.2.0/bin/node"], files: [adapter],
                             directories: [root: ["v22.1.0", "v24.2.0"]])
        XCTAssertEqual(try found.launch(.codex).executable, root + "/v24.2.0/bin/node")
    }

    func testGeminiAndQwenStartWithTheACPFlag() throws {
        let found = resolver(["/opt/homebrew/bin/qwen", home + "/.local/bin/gemini"])
        XCTAssertEqual(try found.launch(.qwen), ACPLaunch(executable: "/opt/homebrew/bin/qwen", arguments: ["--acp"], environment: [:]))
        XCTAssertEqual(try found.launch(.gemini).executable, home + "/.local/bin/gemini")
        XCTAssertEqual(ACPProvider.gemini.title, "Gemini CLI")
    }

    func testGlobalNPMInstallsUnderAVersionManagerAreFound() throws {
        let root = home + "/.local/share/mise/installs/node"
        let found = resolver([root + "/24.0.0/bin/gemini"], directories: [root: ["24.0.0"]])
        XCTAssertEqual(found.availability(.gemini).state, .ready)
    }

    func testOpenCodeKeepsItsOriginalSearchOrder() throws {
        let found = resolver(["/opt/homebrew/bin/opencode", home + "/.local/bin/opencode"])
        XCTAssertEqual(try found.launch(.opencode), ACPLaunch(executable: "/opt/homebrew/bin/opencode", arguments: ["acp"], environment: [:]))
    }
}
