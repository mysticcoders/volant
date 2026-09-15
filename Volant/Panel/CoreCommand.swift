import Foundation

/// Discoverable entry points. Data rows keep their own identity and aren't branded as apps.
enum CoreCommand: String, CaseIterable, Hashable {
    case translate, caffeinate, emoji, notes, clipboard, agents, wifi, bluetooth, audio
    var title: String {
        switch self {
        case .translate: return "Translate Text"
        case .caffeinate: return "Caffeinate"
        case .emoji: return "Search Emoji"
        case .notes: return "Open Notes"
        case .clipboard: return "Clipboard History"
        case .agents: return "Open Agents"
        case .wifi: return "Wi-Fi Networks"
        case .bluetooth: return "Bluetooth Devices"
        case .audio: return "Audio Devices"
        }
    }
    var query: String {
        switch self {
        case .emoji: return ":"
        case .clipboard: return "clip"
        default: return rawValue
        }
    }
    var symbol: String {
        switch self {
        case .translate: return "character.bubble"
        case .caffeinate: return "cup.and.saucer"
        case .emoji: return "face.smiling"
        case .notes: return "note.text"
        case .clipboard: return "doc.on.clipboard"
        case .agents: return "terminal"
        case .wifi: return "wifi"
        case .bluetooth: return "antenna.radiowaves.left.and.right"
        case .audio: return "speaker.wave.2"
        }
    }
    var detail: String {
        switch self {
        case .translate: return "Translate between languages on your Mac"
        case .caffeinate: return "Keep your Mac awake"
        case .emoji: return "Browse emoji and copy one"
        default: return "Built into Volant"
        }
    }
    static func search(_ query: String) -> [Self] {
        allCases.filter { ($0.title + " " + $0.rawValue).localizedCaseInsensitiveContains(query) }
    }
}
