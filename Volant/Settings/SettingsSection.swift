import SwiftUI

/// The Settings sidebar, in order. Core sections come first; features follow under their own heading.
/// Keywords let the sidebar search find a section by a setting it contains, not only by its name.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case appearance = "Appearance"
    case keyboardShortcuts = "Keyboard Shortcuts"
    case appShortcuts = "App Shortcuts"
    case data = "Data & Configuration"
    case whatsNew = "What’s New"
    case about = "About"
    case ai = "AI"
    case dictation = "Dictation"
    case extensions = "Extensions"
    case fileSearch = "File Search"
    case statusBar = "Status Bar"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: String(localized: "General", comment: "Settings sidebar section")
        case .appearance: String(localized: "Appearance", comment: "Settings sidebar section")
        case .keyboardShortcuts: String(localized: "Keyboard Shortcuts", comment: "Settings sidebar section")
        case .appShortcuts: String(localized: "App Shortcuts", comment: "Settings sidebar section")
        case .data: String(localized: "Data & Configuration", comment: "Settings sidebar section")
        case .whatsNew: String(localized: "What’s New", comment: "Settings sidebar section")
        case .about: String(localized: "About", comment: "Settings sidebar section")
        case .ai: String(localized: "AI", comment: "Settings sidebar section")
        case .dictation: String(localized: "Dictation", comment: "Settings sidebar section")
        case .extensions: String(localized: "Extensions", comment: "Settings sidebar section")
        case .fileSearch: String(localized: "File Search", comment: "Settings sidebar section")
        case .statusBar: String(localized: "Status Bar", comment: "Settings sidebar section")
        }
    }
    var isFeature: Bool { [.ai, .dictation, .extensions, .fileSearch, .statusBar].contains(self) }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "paintbrush.fill"
        case .keyboardShortcuts: "keyboard.fill"
        case .appShortcuts: "command"
        case .data: "externaldrive.fill"
        case .whatsNew: "gift.fill"
        case .about: "info"
        case .ai: "sparkles"
        case .dictation: "mic.fill"
        case .extensions: "puzzlepiece.extension.fill"
        case .fileSearch: "doc.text.magnifyingglass"
        case .statusBar: "menubar.rectangle"
        }
    }

    var tint: Color {
        switch self {
        case .general, .keyboardShortcuts, .about: Color(nsColor: .systemGray)
        case .appearance: .indigo
        case .appShortcuts: .teal
        case .data: .blue
        case .whatsNew: .purple
        case .ai: .pink
        case .dictation: .red
        case .extensions: .green
        case .fileSearch: .cyan
        case .statusBar: .orange
        }
    }

    var keywords: [String] {
        switch self {
        case .general: ["login", "startup", "dock", "launch", "caffeinate", "display", "awake", "sleep"]
        case .appearance: ["theme", "color", "dark", "light", "size", "opacity", "raycast theme"]
        case .keyboardShortcuts: ["hotkey", "shortcut", "notes", "emoji", "lock screen", "sleep displays", "dictate"]
        case .appShortcuts: ["alias", "hotkey", "application"]
        case .data: ["config", "json", "icloud", "sync", "backup", "import", "export", "raycast", "coingecko", "crypto"]
        case .whatsNew: ["changelog", "release notes", "new", "changes", "version", "update"]
        case .about: ["version", "acknowledgements", "license", "geonames", "website"]
        case .ai: ["chat", "acp", "claude", "codex", "api key", "model", "apple intelligence", "ollama"]
        case .dictation: ["microphone", "speech", "voice", "type", "filler", "accessibility", "sound", "volume", "vocabulary", "words", "dictionary"]
        case .extensions: ["catalog", "community", "network", "hosts", "install", "wasm"]
        case .fileSearch: ["fsearch", "spotlight", "files", "disk"]
        case .statusBar: ["herdr", "rex", "agents", "footer", "ai chat", "activity"]
        }
    }

    /// Whether a sidebar search matches this section's title or one of its keywords.
    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return ([title] + keywords).contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

/// A sidebar icon: a white symbol on a rounded tile in the section's color, as in System Settings.
struct SettingsIcon: View {
    let section: SettingsSection
    var body: some View {
        Image(systemName: section.symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(section.tint.gradient))
            .accessibilityHidden(true)
    }
}
