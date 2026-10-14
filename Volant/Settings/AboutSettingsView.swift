import AppKit
import SwiftUI
import VolantCore

/// Settings → About: the app's version and links, and credits for the data and palettes Volant ships.
struct AboutSettingsView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String
        return "Version \(short)" + (build.map { " (\($0))" } ?? "")
    }

    var body: some View {
        Form {
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
                LabeledContent("Color themes") {
                    Text("Catppuccin, Nord, Dracula, Gruvbox, Solarized, Tokyo Night, Rosé Pine, One Dark")
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text("Acknowledgements")
            } footer: {
                SettingsFooter("GeoNames city names are licensed under Creative Commons Attribution 4.0. Airport codes from mwgg/Airports and the color theme palettes are MIT licensed; their licenses are included with Volant.")
            }
        }
        .formStyle(.settings)
    }
}
