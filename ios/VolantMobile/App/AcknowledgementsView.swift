import SwiftUI

/// Settings › Acknowledgements: the third-party work Volant for iPhone ships, each with a link and
/// its full license, read from the license files bundled with the app (the same files the Mac app
/// bundles, from `Volant/Resources/Licenses`). `-fixtureAcknowledgements YES` opens it on launch.
struct AcknowledgementsView: View {
    struct Credit: Identifiable {
        let title: LocalizedStringKey
        let detail: String
        /// The project's page, when there is one project to link; the color themes' license file
        /// names each of its projects instead.
        let url: String?
        let licenseFile: String
        var id: String { licenseFile }
    }

    static let credits = [
        Credit(title: "Dictation Formatting", detail: "Hex by Christopher Langton · MIT License",
               url: "https://github.com/anomalyco/hex", licenseFile: "Hex-LICENSE"),
        Credit(title: "Color Themes", detail: "Catppuccin, Nord, Dracula, Gruvbox, Solarized, Tokyo Night, Rosé Pine, One Dark · MIT License",
               url: nil, licenseFile: "ColorThemes-LICENSES"),
    ]

    var body: some View {
        List {
            ForEach(Self.credits) { credit in
                Section {
                    NavigationLink {
                        LicenseText(title: credit.title, file: credit.licenseFile)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(credit.title).foregroundStyle(.primary)
                            Text(credit.detail).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    if let url = credit.url {
                        LinkRow(symbol: "arrow.up.right.square", title: "Project Page", url: url)
                    }
                }
            }
        }
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A bundled license file shown in full, selectable.
private struct LicenseText: View {
    let title: LocalizedStringKey
    let file: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var text: String {
        Bundle.main.url(forResource: file, withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            ?? String(localized: "The license file is missing from this build.")
    }
}
