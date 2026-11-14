import Foundation

/// Discoverable entry points. Data rows keep their own identity and aren't branded as apps.
public enum CoreCommand: String, CaseIterable, Hashable {
    case define, translate, caffeinate, emoji, notes, clipboard, contacts, files, shortcuts, agents, servers, ai, talk, confetti, wifi, bluetooth, audio, colorPicker, camera, newSnippet, newQuicklink, catalog, welcome, menuItems, focus, breaks
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
        case .clipboard: return LocalizedStringResource("Search Clipboard", table: "Core", comment: "Launcher command name")
        case .contacts: return LocalizedStringResource("Search Contacts", table: "Core", comment: "Launcher command name")
        case .files: return LocalizedStringResource("Search Files", table: "Core", comment: "Launcher command name")
        case .agents: return LocalizedStringResource("Open Agents", table: "Core", comment: "Launcher command name")
        case .servers: return LocalizedStringResource("Listening Servers", table: "Core", comment: "Launcher command name")
        case .wifi: return LocalizedStringResource("Wi-Fi Networks", table: "Core", comment: "Launcher command name")
        case .bluetooth: return LocalizedStringResource("Bluetooth Devices", table: "Core", comment: "Launcher command name")
        case .audio: return LocalizedStringResource("Audio Devices", table: "Core", comment: "Launcher command name")
        case .colorPicker: return LocalizedStringResource("Pick Color", table: "Core", comment: "Launcher command name: sample a color from the screen")
        case .camera: return LocalizedStringResource("Open Camera", table: "Core", comment: "Launcher command name: show a small camera preview window")
        case .newSnippet: return LocalizedStringResource("Create Snippet", table: "Core", comment: "Launcher command name")
        case .newQuicklink: return LocalizedStringResource("Create Quicklink", table: "Core", comment: "Launcher command name")
        case .catalog: return LocalizedStringResource("Extension Catalog", table: "Core", comment: "Launcher command name")
        case .menuItems: return LocalizedStringResource("Search Menu Items", table: "Core", comment: "Launcher command name: search the menu bar of the app that was in front")
        case .focus: return LocalizedStringResource("Focus Session", table: "Core", comment: "Launcher command name: start or control a session that blocks distracting apps and websites")
        case .breaks: return LocalizedStringResource("Breaks", table: "Core", comment: "Launcher command name: reminders to step away from the Mac after a stretch of work")
        case .welcome: return LocalizedStringResource("Show Welcome", table: "Core", comment: "Launcher command name; opens the first-run Welcome window again")
        }
    }
    public var query: String {
        switch self {
        case .emoji: return ":"
        case .clipboard: return "clip"
        case .contacts: return "@"
        case .files: return "/"
        case .newSnippet: return "new snippet"
        case .newQuicklink: return "new quicklink"
        case .menuItems: return "menus"
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
        case .contacts: return "person.crop.circle"
        case .files: return "doc.text.magnifyingglass"
        case .agents: return "terminal"
        case .servers: return "server.rack"
        case .wifi: return "wifi"
        case .bluetooth: return "antenna.radiowaves.left.and.right"
        case .audio: return "speaker.wave.2"
        case .colorPicker: return "eyedropper"
        case .camera: return "camera"
        case .newSnippet: return "text.badge.plus"
        case .newQuicklink: return "link.badge.plus"
        case .catalog: return "puzzlepiece.extension"
        case .menuItems: return "filemenu.and.selection"
        case .focus: return "target"
        case .breaks: return "figure.walk"
        case .welcome: return "hand.wave"
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
        case .colorPicker: return LocalizedStringResource("Sample a color on screen and copy it as HEX, RGB, HSL or OKLCH", table: "Core", comment: "Launcher command description, shown under its name")
        case .camera: return LocalizedStringResource("Show a small mirrored camera preview", table: "Core", comment: "Launcher command description, shown under its name")
        case .newSnippet: return LocalizedStringResource("Save text to copy by keyword", table: "Core", comment: "Launcher command description, shown under its name")
        case .newQuicklink: return LocalizedStringResource("Save a link to open by name", table: "Core", comment: "Launcher command description, shown under its name")
        case .catalog: return LocalizedStringResource("Browse and install reviewed extensions", table: "Core", comment: "Launcher command description, shown under its name")
        case .clipboard: return LocalizedStringResource("Find something you copied", table: "Core", comment: "Launcher command description, shown under its name")
        case .contacts: return LocalizedStringResource("Find people in your Contacts", table: "Core", comment: "Launcher command description, shown under its name")
        case .files: return LocalizedStringResource("Find files on your Mac", table: "Core", comment: "Launcher command description, shown under its name")
        case .menuItems: return LocalizedStringResource("Find and choose a menu command in the app you were using", table: "Core", comment: "Launcher command description, shown under its name")
        case .focus: return LocalizedStringResource("Block distracting apps and websites while you work", table: "Core", comment: "Launcher command description, shown under its name")
        case .breaks: return LocalizedStringResource("Remind you to step away after a stretch of work", table: "Core", comment: "Launcher command description, shown under its name")
        case .welcome: return LocalizedStringResource("Set up your shortcut, access and extensions again", table: "Core", comment: "Launcher command description, shown under its name")
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
        case .clipboard: return "clipboard history | clip | copied | paste"
        case .contacts: return "people | person | address book"
        case .files: return "file | documents | finder"
        case .menuItems: return MenuItemsQuery.phrases.joined(separator: " | ") + " | menu commands"
        case .servers: return "ports | localhost | listening | dev server"
        case .colorPicker: return LauncherRouting.colorPickerPhrases.sorted().joined(separator: " | ") + " | eyedropper | colour"
        case .camera: return "webcam | facetime camera | mirror | open camera"
        case .welcome: return "getting started | onboarding | setup | tour"
        case .newSnippet: return LauncherRouting.snippetCreatePhrases.sorted().joined(separator: " | ")
        case .newQuicklink: return LauncherRouting.quicklinkCreatePhrases.sorted().joined(separator: " | ") + " | new link"
        case .focus: return "start focus session | toggle focus session | block apps | block websites | distractions | pomodoro"
        case .breaks: return "take a break | break reminder | rest | stretch | eye strain | stand up"
        default: return ""
        }
    }

    public static func search(_ query: String) -> [Self] {
        allCases.filter { ($0.title + " " + $0.englishTitle + " " + $0.rawValue + " " + $0.searchTerms).localizedCaseInsensitiveContains(query) }
    }
}
