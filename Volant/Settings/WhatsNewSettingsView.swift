import SwiftUI
import VolantCore

/// Settings → What's New: the release notes bundled with this build, newest first, so the changelog
/// reads the same offline as on GitHub. The running version is marked.
struct WhatsNewSettingsView: View {
    var releases: [ReleaseNotes] = WhatsNewSettingsView.bundled
    var current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

    /// The notes copied into the app bundle from docs/releases at build time.
    static var bundled: [ReleaseNotes] {
        Bundle.main.url(forResource: "releases", withExtension: nil).map(ReleaseNotes.load(from:)) ?? []
    }

    @Environment(\.volantTheme) private var theme

    /// A lazy column of release cards rather than the settings form: rebuilding two dozen releases'
    /// sections row by row through `SettingsFormStyle` stalled layout in the native fixture.
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if releases.isEmpty {
                    Text("Release notes aren’t included in this build.").foregroundStyle(.secondary).padding(.horizontal, 16)
                }
                ForEach(releases, id: \.version) { release in
                    VStack(alignment: .leading, spacing: 8) {
                        header(release).padding(.horizontal, 16)
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(release.sections, id: \.title) { section in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(section.title).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                                    ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                                            Text("•").foregroundStyle(.secondary).accessibilityHidden(true)
                                            Text(Self.markdown(item)).frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(theme.settingsCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        if !release.notes.isEmpty {
                            SettingsFooter(release.notes.joined(separator: " ")).padding(.horizontal, 16)
                        }
                    }
                }
                HStack {
                    Text("Full history and downloads")
                    Spacer()
                    Link("Releases on GitHub", destination: LauncherMenuItem.changelogURL)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(theme.settingsCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 24).padding(.top, 4).padding(.bottom, 24)
        }
    }

    private func header(_ release: ReleaseNotes) -> some View {
        HStack(spacing: 8) {
            Text("Volant \(release.version)").font(.system(size: 13, weight: .semibold))
            if release.version == current {
                Text("This version").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
        }
    }

    /// Inline Markdown (bold, links) from the notes, falling back to the plain text.
    private static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}
