import AppKit
import SwiftUI

/// Volant's own display language. It reads and writes `AppleLanguages` in Volant's preferences, the
/// per-app setting System Settings › General › Language & Region › Applications also uses, so the two
/// always agree. Removing it means "follow the Mac". A change applies after Volant relaunches.
struct LanguageSetting {
    let defaults: UserDefaults
    let domain: String
    let available: [String]

    init(defaults: UserDefaults = .standard, domain: String = Bundle.main.bundleIdentifier ?? "", available: [String] = Bundle.main.localizations) {
        self.defaults = defaults
        self.domain = domain
        self.available = available
    }

    /// The languages Volant ships, English first, then the translations by their own names.
    var choices: [String] {
        let codes = available.filter { $0 != "Base" }
        return codes.filter { $0 == "en" } + codes.filter { $0 != "en" }.sorted { Self.name($0).localizedStandardCompare(Self.name($1)) == .orderedAscending }
    }

    /// The chosen language, or nil to follow the Mac. Only Volant's own domain counts: the merged
    /// value would report the Mac's list as if it were a choice.
    var chosen: String? {
        guard let codes = defaults.persistentDomain(forName: domain)?["AppleLanguages"] as? [String], let first = codes.first else { return nil }
        return choices.first { first == $0 || first.hasPrefix($0 + "-") } ?? first
    }

    func choose(_ code: String?) {
        if let code { defaults.set([code], forKey: "AppleLanguages") } else { defaults.removeObject(forKey: "AppleLanguages") }
    }

    /// A language's name in that language, such as Deutsch or 日本語, so each reader finds their own.
    static func name(_ code: String) -> String {
        let locale = Locale(identifier: code)
        let name = locale.localizedString(forIdentifier: code) ?? code
        return name.prefix(1).uppercased(with: locale) + name.dropFirst()
    }
}

/// Settings › General › Language: a menu of System and the shipped languages, translations marked
/// beta, and a relaunch button once the choice differs from what Volant is showing.
struct LanguageSettingSection: View {
    private let setting = LanguageSetting()
    private let launchedWith = LanguageSetting().chosen
    @State private var choice: String?

    var body: some View {
        Section {
            Picker(selection: Binding(get: { choice }, set: { choice = $0; setting.choose($0) })) {
                Text("System", comment: "Language menu item: follow the Mac's preferred languages").tag(String?.none)
                Divider()
                ForEach(setting.choices, id: \.self) { code in
                    Text(code == "en" ? LanguageSetting.name(code) : String(localized: "\(LanguageSetting.name(code)) (beta)",
                                                                            comment: "Language menu item for an unreviewed translation; the value is the language's own name"))
                        .tag(String?.some(code))
                }
            } label: {
                Text("Language", comment: "Settings row choosing Volant's display language")
            }
            if choice != launchedWith {
                LabeledContent {
                    Button(String(localized: "Relaunch Volant", comment: "Button that restarts Volant to apply a language change")) { Self.relaunch() }
                } label: {
                    Text("Volant uses the new language after it relaunches.", comment: "Shown after changing the language").foregroundStyle(.secondary)
                }
            }
        } footer: {
            SettingsFooter(String(localized: "System follows your Mac’s language. Translations other than English are betas drafted without review by native speakers. You can also choose this in System Settings › General › Language & Region › Applications.",
                                  comment: "Language settings footer"))
        }
        .onAppear { choice = setting.chosen }
    }

    /// Opens a fresh copy of Volant, then quits this one once that has started.
    private static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            DispatchQueue.main.async { if error == nil { NSApp.terminate(nil) } }
        }
    }
}
