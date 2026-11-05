import AppKit
import SwiftUI
import VolantCore

/// Settings › Your Volant: the owner's own usage, read from `usage.sqlite` on this Mac and shown only
/// here. Nothing is sent anywhere, logged or kept beyond the counts `UsageStore` already holds.
struct YourVolantSettingsView: View {
    var usageURL: URL = UsageStore.defaultURL
    var now: () -> Date = Date.init

    @Environment(\.volantTheme) private var theme
    @State private var summary: UsageStats.Summary?
    @State private var lists: [(kind: UsageStats.Kind, entries: [Entry])] = []
    @State private var confirmingClear = false
    @State private var clearFailed = false

    /// A ranked item with the name and icon Settings shows for it.
    struct Entry: Identifiable {
        let id: String
        let name: String
        let icon: NSImage?
        let symbol: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let summary {
                    activity(summary)
                    favorites
                    footer(summary)
                }
            }
            .padding(.horizontal, 24).padding(.top, 4).padding(.bottom, 24)
        }
        .onAppear(perform: load)
        .confirmationDialog("Clear activity history?", isPresented: $confirmingClear) {
            Button("Clear", role: .destructive) {
                if UsageStore.clearActivity(url: usageURL) { load() } else { clearFailed = true }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This forgets the daily counts on this Mac. App and command rankings stay.")
        }
        .alert("Couldn’t clear activity history.", isPresented: $clearFailed) {
            Button("OK") {}
        }
    }

    /// The last 30 days: four numbers over a bar per day.
    private func activity(_ summary: UsageStats.Summary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last 30 days").font(.system(size: 13, weight: .semibold)).padding(.horizontal, 16)
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    tile(value: summary.total.formatted(), label: Text("Launcher choices"))
                    tile(value: summary.activeDays.formatted(), label: Text("Active days"))
                    tile(value: summary.streak.formatted(), label: Text("Day streak"))
                    tile(value: summary.busiest.map { Self.shortDate($0.day) } ?? "–", label: Text("Busiest day"))
                }
                bars(summary.days)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.settingsCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func tile(value: String, label: Text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: value).font(.system(size: 20, weight: .semibold).monospacedDigit())
            label.font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// One bar per day, scaled to the busiest day, with the first and last dates under the row.
    private func bars(_ days: [UsageStats.Day]) -> some View {
        let peak = max(days.map(\.uses).max() ?? 0, 1)
        return VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(days, id: \.day) { day in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(day.uses > 0 ? Color.accentColor : Color.primary.opacity(0.08))
                        .frame(maxWidth: .infinity)
                        .frame(height: day.uses > 0 ? max(4, 64 * CGFloat(day.uses) / CGFloat(peak)) : 4)
                }
            }
            .frame(height: 64, alignment: .bottom)
            HStack {
                Text(verbatim: days.first.map { Self.shortDate($0.day) } ?? "")
                Spacer()
                Text(verbatim: days.last.map { Self.shortDate($0.day) } ?? "")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Launcher choices per day"))
    }

    /// Apps, commands and extensions by recent use, each its own card; kinds with nothing are left out.
    @ViewBuilder private var favorites: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Most used lately").font(.system(size: 13, weight: .semibold)).padding(.horizontal, 16)
            if lists.isEmpty {
                Text("Nothing yet. What you open from the launcher shows up here.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.settingsCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            ForEach(lists, id: \.kind) { list in
                VStack(alignment: .leading, spacing: 0) {
                    Text(Self.title(list.kind)).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 16).padding(.top, 11).padding(.bottom, 4)
                    ForEach(Array(list.entries.enumerated()), id: \.element.id) { index, entry in
                        HStack(spacing: 10) {
                            Text(verbatim: (index + 1).formatted()).monospacedDigit().foregroundStyle(.secondary).frame(width: 16, alignment: .trailing)
                            if let icon = entry.icon {
                                Image(nsImage: icon).resizable().frame(width: 20, height: 20).accessibilityHidden(true)
                            } else {
                                Image(systemName: entry.symbol).frame(width: 20, height: 20).foregroundStyle(.secondary).accessibilityHidden(true)
                            }
                            Text(verbatim: entry.name).lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 16).padding(.vertical, 6)
                    }
                }
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.settingsCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func footer(_ summary: UsageStats.Summary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsFooter(String(localized: "Counted only on this Mac, from what you choose in the launcher, and never sent anywhere. Rankings fade over about a week, so they show what you use lately.", comment: "Settings › Your Volant footer"))
            if let since = summary.since {
                SettingsFooter(String(localized: "Daily counts began \(Self.longDate(since), format: .verbatim).", comment: "Settings › Your Volant footer; the value is a date"))
            }
            Button("Clear Activity History…") { confirmingClear = true }
                .disabled(summary.since == nil)
        }
        .padding(.horizontal, 16)
    }

    /// Reads the store once each time the section appears; Settings never holds a live connection.
    private func load() {
        let snapshot = UsageStore.snapshot(url: usageURL)
        let date = now()
        let manager = ExtensionManager()
        manager.reload()
        let extensions = manager.extensions
        summary = UsageStats.summary(daily: snapshot.daily, now: date)
        lists = UsageStats.Kind.allCases.compactMap { kind in
            let entries = UsageStats.top(kind, records: snapshot.records, now: date, limit: 10).compactMap { Self.entry($0, extensions: extensions) }.prefix(5)
            return entries.isEmpty ? nil : (kind, Array(entries))
        }
    }

    /// Names a ranked key, or nil for one Settings can't name any more, such as a deleted app or an
    /// uninstalled extension.
    static func entry(_ ranked: UsageStats.Ranked, extensions: [InstalledExtension]) -> Entry? {
        let key = ranked.key
        if key.hasPrefix("app:") {
            let path = String(key.dropFirst("app:".count))
            guard path.hasPrefix("/"), FileManager.default.fileExists(atPath: path) else { return nil }
            let name = (FileManager.default.displayName(atPath: path) as NSString).deletingPathExtension
            return Entry(id: key, name: name, icon: NSWorkspace.shared.icon(forFile: path), symbol: "app")
        }
        if key.hasPrefix("core:"), let command = CoreCommand(rawValue: String(key.dropFirst("core:".count))) {
            return Entry(id: key, name: command.title, icon: nil, symbol: "command")
        }
        if key.hasPrefix("system-action:"), let action = SystemAction(rawValue: String(key.dropFirst("system-action:".count))) {
            return Entry(id: key, name: action.title, icon: nil, symbol: "power")
        }
        switch key {
        case "command:settings": return Entry(id: key, name: String(localized: "Volant Settings", comment: "Launcher row title"), icon: nil, symbol: "gearshape")
        case "command:reload": return Entry(id: key, name: String(localized: "Reload Configuration", comment: "Launcher row title"), icon: nil, symbol: "arrow.clockwise")
        case "command:agents": return Entry(id: key, name: String(localized: "Open Agents", comment: "Launcher row title"), icon: nil, symbol: "terminal")
        case "command:rex-overview": return Entry(id: key, name: String(localized: "Open Rex Overview", comment: "Launcher row title"), icon: nil, symbol: "rectangle.3.group")
        default: break
        }
        if key.hasPrefix("ext:") {
            let id = String(key.dropFirst("ext:".count))
            guard let installed = extensions.first(where: { $0.id == id }) else { return nil }
            return Entry(id: key, name: installed.name, icon: nil, symbol: "puzzlepiece.extension")
        }
        return nil
    }

    private static func title(_ kind: UsageStats.Kind) -> String {
        switch kind {
        case .apps: String(localized: "Apps", comment: "Settings › Your Volant list title")
        case .commands: String(localized: "Commands", comment: "Launcher section title for Volant commands")
        case .extensions: SettingsSection.extensions.title
        }
    }

    private static func date(_ day: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: day)
    }

    private static func shortDate(_ day: String) -> String {
        date(day)?.formatted(.dateTime.month(.abbreviated).day()) ?? day
    }

    private static func longDate(_ day: String) -> String {
        date(day)?.formatted(date: .long, time: .omitted) ?? day
    }
}
