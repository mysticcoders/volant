import AppKit
import VolantCore

/// Curated pane links, not a mirror of Apple's private Settings search index.
struct SystemSettingsDestination: Hashable, Identifiable {
    let title: String
    let id: String
    let keywords: String
    var url: URL { URL(string: "x-apple.systempreferences:" + id)! }

    static let all: [Self] = [
        .init(title: "Displays", id: "com.apple.Displays-Settings.extension", keywords: "monitor resolution brightness display"),
        .init(title: "Keyboard", id: "com.apple.Keyboard-Settings.extension", keywords: "typing shortcuts keyboard"),
        .init(title: "Login Items & Extensions", id: "com.apple.LoginItems-Settings.extension", keywords: "startup launch background login"),
        .init(title: "Software Update", id: "com.apple.Software-Update-Settings.extension", keywords: "macos upgrade updates"),
        .init(title: "Privacy & Security", id: "com.apple.settings.PrivacySecurity.extension", keywords: "permissions privacy security camera microphone location"),
        .init(title: "Accessibility", id: "com.apple.Accessibility-Settings.extension", keywords: "voiceover zoom accessibility"),
        .init(title: "Desktop & Dock", id: "com.apple.Desktop-Settings.extension", keywords: "mission control stage manager dock desktop"),
        .init(title: "Appearance", id: "com.apple.Appearance-Settings.extension", keywords: "dark light mode accent colors appearance"),
        .init(title: "Sound", id: "com.apple.Sound-Settings.extension", keywords: "speakers microphone sound"),
        .init(title: "Wi-Fi", id: "com.apple.wifi-settings-extension", keywords: "wifi wireless internet"),
        .init(title: "Bluetooth", id: "com.apple.BluetoothSettings", keywords: "bluetooth paired devices"),
        .init(title: "Trackpad", id: "com.apple.Trackpad-Settings.extension", keywords: "gestures scrolling trackpad"),
        .init(title: "Mouse", id: "com.apple.Mouse-Settings.extension", keywords: "mouse pointer scrolling"),
        .init(title: "Wallpaper", id: "com.apple.Wallpaper-Settings.extension", keywords: "wallpaper background picture"),
        .init(title: "Storage", id: "com.apple.settings.Storage", keywords: "disk space storage"),
        .init(title: "Time Machine", id: "com.apple.Time-Machine-Settings.extension", keywords: "backup time machine"),
        .init(title: "Lock Screen", id: "com.apple.Lock-Screen-Settings.extension", keywords: "lock screen sleep password"),
        .init(title: "Date & Time", id: "com.apple.Date-Time-Settings.extension", keywords: "clock timezone date time")
    ]

    static func search(_ query: String) -> [Self] {
        let terms = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
            .filter { !["settings", "setting", "system", "preferences", "&"].contains($0) }
        guard !terms.isEmpty else { return [] }
        return all.filter { destination in
            let text = (destination.title + " " + destination.keywords).lowercased()
            return terms.allSatisfy { text.contains($0) }
        }.sorted { left, right in
            let phrase = terms.joined(separator: " ")
            let lhs = left.title.lowercased().hasPrefix(phrase)
            let rhs = right.title.lowercased().hasPrefix(phrase)
            return lhs != rhs ? lhs : left.title < right.title
        }
    }
}
