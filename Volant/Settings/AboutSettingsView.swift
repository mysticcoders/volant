import AppKit
import SwiftUI
import VolantCore

/// Settings → About: the app's version and links, and credits for the data and palettes Volant ships.
struct AboutSettingsView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String
        return build.map { String(localized: "Version \(short) (\($0))", comment: "About settings; the values are the version and build number") } ?? String(localized: "Version \(short)", comment: "About settings; the value is the version number")
    }

    /// Whether Volant is showing a translation rather than its English source text. Every translation
    /// so far is an unreviewed beta (docs/localization.md), which About says plainly.
    private var showsTranslation: Bool {
        Bundle.main.preferredLocalizations.first.map { !$0.hasPrefix("en") } ?? false
    }

    var body: some View {
        Form {
            if showsTranslation {
                Section {
                    LabeledContent(String(localized: "Translation", comment: "About settings row naming the language Volant is shown in")) {
                        Link(String(localized: "Report a problem", comment: "About settings link to report a translation mistake"),
                             destination: URL(string: "https://github.com/mysticcoders/volant/issues")!)
                    }
                } footer: {
                    SettingsFooter(String(localized: "This translation is a beta. It was drafted without review by a native speaker, so some wording may be wrong or unnatural.",
                                          comment: "About settings footer, shown only when Volant runs in a translated language"))
                }
            }
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Volant").font(.title2.weight(.semibold))
                        Text(version).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Spacer()
                    Link("Website", destination: URL(string: "https://usevolant.com")!)
                    Link("GitHub", destination: URL(string: "https://github.com/mysticcoders/volant")!)
                }
                .padding(.vertical, 4)
            }
            Section {
                LabeledContent("City time zones") {
                    Link("GeoNames", destination: URL(string: "https://www.geonames.org")!)
                }
                LabeledContent("Airport codes") {
                    Link("mwgg/Airports", destination: URL(string: "https://github.com/mwgg/Airports")!)
                }
                LabeledContent("Exchange rates") {
                    Link("Rates By Exchange Rate API", destination: WorldRates.attribution)
                }
                LabeledContent("Crypto prices") {
                    Link("Data provided by CoinGecko", destination: URL(string: "https://www.coingecko.com")!)
                }
                LabeledContent("Runtime logos") {
                    Link("Simple Icons", destination: URL(string: "https://simpleicons.org")!)
                }
                LabeledContent("Color themes") {
                    Text("Catppuccin, Nord, Dracula, Gruvbox, Solarized, Tokyo Night, Rosé Pine, One Dark")
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text("Acknowledgements")
            } footer: {
                SettingsFooter(String(localized: "GeoNames city names are licensed under Creative Commons Attribution 4.0. Airport codes from mwgg/Airports and the color theme palettes are MIT licensed; their licenses are included with Volant. Runtime logos are trademarks of their owners, shown only to identify a server's runtime; the Ruby and PHP logos are licensed under Creative Commons Attribution-ShareAlike, and their licenses and notices are included with Volant."))
            }
        }
        .formStyle(.settings)
    }
}
