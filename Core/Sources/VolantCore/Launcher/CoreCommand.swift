import Foundation

/// Discoverable entry points. Data rows keep their own identity and aren't branded as apps.
public enum CoreCommand: String, CaseIterable, Hashable {
    case define, translate, caffeinate, emoji, notes, clipboard, shortcuts, agents, servers, ai, talk, confetti, wifi, bluetooth, audio, newSnippet, newQuicklink, catalog
    /// The command's name in the launcher, translated in the Core table.
    public var titleResource: LocalizedStringResource {
        switch self {
        case .ai: return LocalizedStringResource("AI Chat", table: "Core", comment: "Launcher command name")
        case .talk: return LocalizedStringResource("Dictate Text", table: "Core", comment: "Launcher command name")
        case .confetti: return LocalizedStringResource("Throw Confetti", table: "Core", comment: "Launcher command name")
        case .shortcuts: return LocalizedStringResource("Apple Shortcuts", table: "Core", comment: "Launcher command name")
        case .define: return LocalizedStringResource("Define Word", table: "Core", comment: "Launcher command name")
        case .translate: return LocalizedStringResource("Translate Text", table: "Core", comment: "Launcher command name")
        case .caffeinate: return LocalizedStringResource("Caffeinate", table: "Core", comment: "Launcher command name")
        case .emoji: return LocalizedStringResource("Search Emoji", table: "Core", comment: "Launcher command name")
        case .notes: return LocalizedStringResource("Open Notes", table: "Core", comment: "Launcher command name")
        case .clipboard: return LocalizedStringResource("Clipboard History", table: "Core", comment: "Launcher command name")
        case .agents: return LocalizedStringResource("Open Agents", table: "Core", comment: "Launcher command name")
        case .servers: return LocalizedStringResource("Listening Servers", table: "Core", comment: "Launcher command name")
        case .wifi: return LocalizedStringResource("Wi-Fi Networks", table: "Core", comment: "Launcher command name")
        case .bluetooth: return LocalizedStringResource("Bluetooth Devices", table: "Core", comment: "Launcher command name")
        case .audio: return LocalizedStringResource("Audio Devices", table: "Core", comment: "Launcher command name")
        case .newSnippet: return LocalizedStringResource("Create Snippet", table: "Core", comment: "Launcher command name")
        case .newQuicklink: return LocalizedStringResource("Create Quicklink", table: "Core", comment: "Launcher command name")
        case .catalog: return LocalizedStringResource("Extension Catalog", table: "Core", comment: "Launcher command name")
        }
    }
    public var query: String {
        switch self {
        case .emoji: return ":"
        case .clipboard: return "clip"
        case .newSnippet: return "new snippet"
        case .newQuicklink: return "new quicklink"
        default: return rawValue
        }
    }
    public var symbol: String {
        switch self {
        case .ai: return "bubble.left.and.bubble.right"
        case .talk: return "mic"
        case .confetti: return "party.popper"
        case .shortcuts: return "square.stack.3d.up"
        case .define: return "book.closed"
        case .translate: return "character.bubble"
        case .caffeinate: return "cup.and.saucer"
        case .emoji: return "face.smiling"
        case .notes: return "note.text"
        case .clipboard: return "doc.on.clipboard"
        case .agents: return "terminal"
        case .servers: return "server.rack"
        case .wifi: return "wifi"
        case .bluetooth: return "antenna.radiowaves.left.and.right"
        case .audio: return "speaker.wave.2"
        case .newSnippet: return "text.badge.plus"
        case .newQuicklink: return "link.badge.plus"
        case .catalog: return "puzzlepiece.extension"
        }
    }
    /// The command's one-line description, translated in the Core table.
    public var detailResource: LocalizedStringResource {
        switch self {
        case .shortcuts: return LocalizedStringResource("Find and run your Apple Shortcuts", table: "Core", comment: "Launcher command description, shown under its name")
        case .define: return LocalizedStringResource("Look up words in your Mac’s dictionaries", table: "Core", comment: "Launcher command description, shown under its name")
        case .translate: return LocalizedStringResource("Translate between languages on your Mac", table: "Core", comment: "Launcher command description, shown under its name")
        case .caffeinate: return LocalizedStringResource("Keep your Mac awake", table: "Core", comment: "Launcher command description, shown under its name")
        case .emoji: return LocalizedStringResource("Browse emoji and copy one", table: "Core", comment: "Launcher command description, shown under its name")
        case .servers: return LocalizedStringResource("See which local servers are listening, and open one", table: "Core", comment: "Launcher command description, shown under its name")
        case .newSnippet: return LocalizedStringResource("Save text to copy by keyword", table: "Core", comment: "Launcher command description, shown under its name")
        case .newQuicklink: return LocalizedStringResource("Save a link to open by name", table: "Core", comment: "Launcher command description, shown under its name")
        case .catalog: return LocalizedStringResource("Browse and install reviewed extensions", table: "Core", comment: "Launcher command description, shown under its name")
        default: return LocalizedStringResource("Built into Volant", table: "Core", comment: "Launcher command description, shown under its name")
        }
    }
    public var title: String { String(localized: titleResource) }
    public var detail: String { String(localized: detailResource) }
    /// The English name, so a command stays findable by the name in the docs whatever the language.
    var englishTitle: String {
        var resource = titleResource
        resource.locale = Locale(identifier: "en")
        return String(localized: resource)
    }
    /// Extra words a command answers to besides its title and raw value.
    var searchTerms: String {
        switch self {
        case .ai: return "acp"
        case .catalog: return "extensions | store | marketplace | install"
        case .servers: return "ports | localhost | listening | dev server"
        case .newSnippet: return LauncherRouting.snippetCreatePhrases.sorted().joined(separator: " | ")
        case .newQuicklink: return LauncherRouting.quicklinkCreatePhrases.sorted().joined(separator: " | ") + " | new link"
        default: return ""
        }
    }

    public static func search(_ query: String) -> [Self] {
        allCases.filter { ($0.title + " " + $0.englishTitle + " " + $0.rawValue + " " + $0.searchTerms).localizedCaseInsensitiveContains(query) }
    }
}
