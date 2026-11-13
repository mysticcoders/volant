import SwiftUI
import VolantCore

/// Settings: the Volant mark and version, iCloud status for notes and for what the Mac shares,
/// appearance, and links about Volant and its privacy.
struct SettingsView: View {
    @ObservedObject var themes: ThemeStore
    let store: NotesStore
    let location: NotesLocation.Resolved
    @EnvironmentObject private var mac: MacSettings
    @AppStorage("onboardingComplete") private var onboardingComplete = true
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return String(localized: "Version \(short) (\(build))")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 4) {
                        HeroMark(size: 96)
                        Text("Volant").font(.system(.title, design: .rounded).weight(.bold))
                        Text(version).font(.footnote).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section {
                    SettingsRow(symbol: location.isICloud ? "checkmark.icloud" : "iphone", title: "Notes",
                                value: location.isICloud ? String(localized: "iCloud Drive") : String(localized: "On This iPhone"))
                    SettingsRow(symbol: "desktopcomputer", title: "Snippets & Quicklinks", value: macStatus)
                } header: {
                    Text("iCloud")
                } footer: {
                    Text(location.isICloud
                         ? "Notes are in iCloud Drive › Volant › Notes, shared with Volant on your Mac. Snippets and quicklinks you add or edit here reach your Mac when Sync settings and notes with iCloud is on there."
                         : "iCloud Drive is off for Volant, so notes stay on this iPhone. Turn it on in Settings › Apple Account › iCloud, then reopen Volant to move them.")
                }

                Section("Appearance") {
                    NavigationLink {
                        ThemePicker(themes: themes)
                    } label: {
                        SettingsRow(symbol: "paintpalette", title: "Theme", value: ColorTheme.named(themes.theme.id).name)
                    }
                }

                Section("About") {
                    LinkRow(symbol: "globe", title: "Volant", url: "https://usevolant.com")
                    LinkRow(symbol: "lock.shield", title: "Privacy & Security", url: "https://usevolant.com/docs/privacy-and-security")
                    LinkRow(symbol: "chevron.left.forwardslash.chevron.right", title: "Source Code", url: "https://github.com/mysticcoders/volant")
                    Button {
                        dismiss()
                        onboardingComplete = false
                    } label: {
                        SettingsRow(symbol: "sparkles", title: "Show Welcome", value: nil)
                    }
                    .buttonStyle(.row)
                }

                Section {
                    HStack(spacing: 8) {
                        VolantMark(size: 14)
                        Text(Brand.privacyLine)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
    }

    private var macStatus: String {
        switch mac.state {
        case .loading: String(localized: "Checking…")
        case .unavailable: String(localized: "iCloud Off")
        case .empty: String(localized: "Not Shared Yet")
        case .ready: mac.updated.map { String(localized: "Updated \($0.formatted(.relative(presentation: .named)))") } ?? String(localized: "On")
        }
    }
}

/// A settings row: a tinted symbol, a title, and an optional value on the trailing side.
struct SettingsRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let value: String?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .foregroundStyle(.tint)
                .frame(width: 26)
            Text(title).foregroundStyle(.primary)
            Spacer()
            if let value { Text(value).foregroundStyle(.secondary) }
        }
    }
}

/// A row that opens a web page, styled like the other rows rather than as tinted link text.
struct LinkRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let url: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let destination = URL(string: url) {
            Button { openURL(destination) } label: {
                HStack {
                    SettingsRow(symbol: symbol, title: title, value: nil)
                    Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.row)
        }
    }
}

/// Every Volant color theme with a swatch, the same catalog as the Mac.
struct ThemePicker: View {
    @ObservedObject var themes: ThemeStore

    var body: some View {
        List {
            Section {
                ForEach(themes.themes) { theme in
                    Button { themes.select(theme.id) } label: {
                        HStack(spacing: 12) {
                            ThemeSwatch(theme: theme)
                            Text(theme.name).foregroundStyle(.primary)
                            Spacer()
                            if theme.id == themes.theme.id {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.row)
                }
            } footer: {
                Text("The same themes as Volant for Mac, read from VolantCore.")
            }
        }
        .navigationTitle("Theme")
    }
}

/// A small preview of a theme: its background with an accent dot, or the system look.
struct ThemeSwatch: View {
    let theme: ColorTheme

    var body: some View {
        let resolved = ResolvedTheme(theme)
        ZStack {
            Circle().fill(resolved.palette.flatMap { Color(hex: $0.background) } ?? Color(uiColor: .secondarySystemBackground))
            Circle().fill(resolved.accent ?? .accentColor).frame(width: 10, height: 10)
        }
        .frame(width: 26, height: 26)
        .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
    }
}
