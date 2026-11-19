import AppKit
import SwiftUI
import VolantCore

/// Settings › AI › Connected Apps: the MCP server switch, one switch per write capability, the setup
/// for each AI app to copy, and the apps that have connected, each with Disconnect. Every change is a
/// narrow, stale-checked patch of `mcpServer` in config.json. See docs/mcp-server-design.md.
struct MCPSettingsSection: View {
    let configURL: URL
    let onChange: () -> Void
    @State private var server = MCPPreferences()
    @State private var loaded = false
    @State private var client = MCPClientSetup.claudeCode
    @State private var failed = false

    var body: some View {
        Section {
            Toggle(isOn: binding(\.enabled)) {
                Text("Let AI apps use Volant", comment: "Settings › AI › Connected Apps switch")
                Text("Apps such as Claude, Codex and Cursor can search your notes, snippets and quicklinks, calculate, and check Breaks and Focus. It all stays on this Mac.",
                     comment: "Settings › AI › Connected Apps switch description")
            }
            .disabled(!loaded)
            .accessibilityIdentifier("settings-mcp-enabled")
            if server.enabled {
                Toggle(isOn: binding(\.writesNotes)) {
                    Text("Create and add to notes", comment: "Settings › AI › Connected Apps write permission")
                }
                Toggle(isOn: binding(\.writesSnippets)) {
                    Text("Add snippets", comment: "Settings › AI › Connected Apps write permission")
                }
                Toggle(isOn: binding(\.writesQuicklinks)) {
                    Text("Add quicklinks", comment: "Settings › AI › Connected Apps write permission")
                }
                Toggle(isOn: binding(\.controlsFocus)) {
                    Text("Start, pause and end Focus", comment: "Settings › AI › Connected Apps permission to control Focus sessions")
                }
                Toggle(isOn: binding(\.controlsBreaks)) {
                    Text("Take, skip and pause breaks", comment: "Settings › AI › Connected Apps permission to control Breaks")
                }
                Toggle(isOn: binding(\.sharesClipboard)) {
                    Text("Search clipboard history", comment: "Settings › AI › Connected Apps sensitive permission")
                    Text("Volant asks you before every search, unless you choose Always Allow for that app.", comment: "Settings › AI › Connected Apps: explains that sensitive permissions ask each time")
                }
                .accessibilityIdentifier("settings-mcp-clipboard")
                Toggle(isOn: binding(\.searchesFiles)) {
                    Text("Search file names", comment: "Settings › AI › Connected Apps sensitive permission: search names of files in the home folder")
                }
                Toggle(isOn: binding(\.convertsCurrency)) {
                    Text("Convert currency", comment: "Settings › AI › Connected Apps sensitive permission")
                }
                Toggle(isOn: binding(\.checksWeather)) {
                    Text("Check the weather", comment: "Settings › AI › Connected Apps sensitive permission")
                }
                Picker(selection: $client) {
                    ForEach(MCPClientSetup.allCases) { Text(verbatim: $0.title).tag($0) }
                } label: {
                    Text("Connect an app", comment: "Settings › AI › Connected Apps: choose which AI app to set up")
                    Text(client.instructions)
                }
                HStack(alignment: .top) {
                    Text(verbatim: client.configuration(bridge: Self.bridgePath))
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(String(localized: "Copy", comment: "Copies the Connected Apps setup text")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(client.configuration(bridge: Self.bridgePath), forType: .string)
                    }
                }
                ForEach(server.knownClients, id: \.self) { name in
                    let disconnected = server.disconnectedClients.contains(name)
                    HStack {
                        Text(verbatim: MCPClientSetup.displayName(name))
                        if disconnected {
                            Text("Disconnected", comment: "Settings › AI › Connected Apps: an app the owner disconnected").foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !disconnected, server.alwaysAllowed.contains(where: { $0.hasPrefix(name + "/") }) {
                            Button(String(localized: "Ask Again", comment: "Forgets an AI app's Always Allow choices, so Volant asks before each sensitive request")) {
                                update { $0.askAgain(name) }
                            }
                        }
                        Button(disconnected ? String(localized: "Allow Again", comment: "Lets a disconnected AI app use Volant again")
                                            : String(localized: "Disconnect", comment: "Stops an AI app from using Volant")) {
                            update { if disconnected { $0.disconnectedClients.removeAll { $0 == name } } else { $0.disconnect(name) } }
                        }
                    }
                }
            }
        } header: {
            Text("Connected Apps", comment: "Settings › AI section header for the MCP server")
        } footer: {
            if failed {
                SettingsFooter(String(localized: "Volant couldn’t save this change because the configuration changed. Try again.", comment: "Settings › AI › Connected Apps save error"))
            } else if server.enabled {
                SettingsFooter(String(localized: "AI apps start Volant’s bridge themselves and reach Volant only through it. Apps appear above after they connect.", comment: "Settings › AI › Connected Apps footer"))
            }
        }
        .onAppear(perform: load)
    }

    /// The bridge inside this copy of Volant.
    static var bridgePath: String { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/volant-mcp").path }

    private func load() {
        server = (try? JSONDecoder().decode(Preferences.self, from: Data(contentsOf: configURL)))?.mcpServer ?? MCPPreferences()
        loaded = true
    }

    private func binding(_ keyPath: WritableKeyPath<MCPPreferences, Bool>) -> Binding<Bool> {
        Binding(get: { server[keyPath: keyPath] }, set: { value in update { $0[keyPath: keyPath] = value } })
    }

    /// Saves one change against the settings this view shows, then reloads Volant's configuration.
    private func update(_ change: (inout MCPPreferences) -> Void) {
        var updated = server
        change(&updated)
        guard updated != server else { return }
        do {
            try Preferences.updateMCPServer(updated, expected: server, at: configURL)
            server = updated
            failed = false
            onChange()
        } catch {
            failed = true
            load()
        }
    }
}

/// The AI apps Settings offers setup text for, and what each needs.
enum MCPClientSetup: String, CaseIterable, Identifiable {
    case claudeCode, claudeDesktop, codex, cursor, other

    var id: String { rawValue }

    /// Product names stay as their makers write them.
    var title: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .claudeDesktop: return "Claude Desktop"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .other: return String(localized: "Other App", comment: "Settings › AI › Connected Apps: an AI app not listed")
        }
    }

    /// A connected client's name as Settings and the approval prompt show it: the product name for the
    /// apps Volant offers setup for, the bridge's client name otherwise.
    static func displayName(_ client: String) -> String {
        allCases.first { $0 != .other && $0.clientName == client }?.title ?? client
    }

    /// The client name the bridge reports, shown in Settings once it connects.
    var clientName: String {
        switch self {
        case .claudeCode: return "claude-code"
        case .claudeDesktop: return "claude-desktop"
        case .codex: return "codex"
        case .cursor: return "cursor"
        case .other: return "other-app"
        }
    }

    var instructions: String {
        switch self {
        case .claudeCode: return String(localized: "Run this in Terminal.", comment: "Settings › AI › Connected Apps setup instructions")
        case .claudeDesktop: return String(localized: "Add this to claude_desktop_config.json, then restart Claude.", comment: "Settings › AI › Connected Apps setup instructions; the file name is not translated")
        case .codex: return String(localized: "Add this to ~/.codex/config.toml.", comment: "Settings › AI › Connected Apps setup instructions; the path is not translated")
        case .cursor: return String(localized: "Add this to ~/.cursor/mcp.json.", comment: "Settings › AI › Connected Apps setup instructions; the path is not translated")
        case .other: return String(localized: "Add this as a stdio MCP server in the app’s settings, and rename other-app.", comment: "Settings › AI › Connected Apps setup instructions; other-app is not translated")
        }
    }

    /// The name the AI app registers the server under: `volant`, or `volant-dev` for Volant Dev, so
    /// both can be set up side by side and a request about Volant Dev matches its server.
    static var serverName: String { Bundle.main.bundleIdentifier == "com.mysticcoders.volant" ? "volant" : "volant-dev" }

    /// The exact text to copy.
    func configuration(bridge: String, server: String = MCPClientSetup.serverName) -> String {
        switch self {
        case .claudeCode:
            return "claude mcp add \(server) -- \"\(bridge)\" --client \(clientName)"
        case .codex:
            return "[mcp_servers.\(server)]\ncommand = \"\(bridge)\"\nargs = [\"--client\", \"\(clientName)\"]"
        case .claudeDesktop, .cursor, .other:
            let entry = MCPValue.object(["mcpServers": .object([server: .object(["command": .string(bridge),
                                                                                  "args": .array([.string("--client"), .string(clientName)])])])])
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            return String(decoding: (try? encoder.encode(entry)) ?? Data(), as: UTF8.self)
        }
    }
}
