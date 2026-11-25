import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VolantCore

/// The sheet behind Settings › Extensions › Activity…: what Volant observed each extension do since it
/// started, newest first, from the shared in-memory `ExtensionActivityRecorder`. It filters by extension
/// and to problems, shows the chosen extension's access with a Turn Off button, and clears or exports the
/// history. Every string from an event is Volant's own (an operation, a phase or a validated host), and
/// is shown verbatim, never looked up.
struct ExtensionActivityView: View {
    let extensions: [InstalledExtension]
    @ObservedObject var recorder: ExtensionActivityRecorder
    let turnOff: (InstalledExtension) -> Void
    let done: () -> Void
    @State private var selection: String?
    @State private var problemsOnly = false
    @State private var confirmingClear = false
    @State private var exportError: String?

    init(extensions: [InstalledExtension], recorder: ExtensionActivityRecorder = .shared, selection: String? = nil,
         turnOff: @escaping (InstalledExtension) -> Void, done: @escaping () -> Void) {
        self.extensions = extensions; self.recorder = recorder; self.turnOff = turnOff; self.done = done
        _selection = State(initialValue: selection)
    }

    /// The chosen extension while it is still a choice; an uninstalled one whose activity was cleared or
    /// aged out falls back to All Extensions, so the picker never holds a tag it no longer lists.
    private var filter: String? {
        guard let selection else { return nil }
        return extensions.contains { $0.id == selection } || recorder.log.events.contains { $0.extensionID == selection } ? selection : nil
    }
    private var events: [ExtensionActivity] { recorder.log.visible(extensionID: filter, problemsOnly: problemsOnly) }
    private var selected: InstalledExtension? { extensions.first { $0.id == filter } }

    /// Installed extensions by name, then any extension that has activity but is no longer installed.
    private var choices: [(id: String, name: String)] {
        let installed = extensions.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.map { (id: $0.id, name: $0.name) }
        let gone = recorder.log.extensionIDs.filter { id in !extensions.contains { $0.id == id } }.map { (id: $0, name: $0) }
        return installed + gone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Extension Activity").font(.title2.bold())
            HStack {
                Picker(selection: Binding(get: { filter }, set: { selection = $0 })) {
                    Text("All Extensions").tag(String?.none)
                    ForEach(choices, id: \.id) { choice in Text(verbatim: choice.name).tag(String?.some(choice.id)) }
                } label: { Text("Extension") }
                    .fixedSize().accessibilityIdentifier("extension-activity-filter")
                Spacer()
                Toggle("Show only problems", isOn: $problemsOnly).toggleStyle(.checkbox)
                    .accessibilityIdentifier("extension-activity-problems")
            }
            if let selected { accessRow(selected) }
            list
            if recorder.log.dropped > 0 {
                Label(String(localized: "Older events dropped: \(recorder.log.dropped)",
                             comment: "Extension Activity warning that the in-memory history reached its limit; the value is a count"),
                      systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange).accessibilityIdentifier("extension-activity-dropped")
            }
            Text("Volant records what it sees extensions do: runs, network requests by host, the clipboard, location and saved data. It never records what you type, clipboard text, results or full addresses. The history stays in memory and is gone when Volant quits.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let exportError {
                Text(verbatim: exportError).font(.callout).foregroundStyle(.red)
            }
            HStack {
                Button("Clear…") { confirmingClear = true }.disabled(recorder.log.events.isEmpty)
                    .accessibilityIdentifier("extension-activity-clear")
                Button("Export…") { export() }.disabled(events.isEmpty)
                    .accessibilityIdentifier("extension-activity-export")
                Spacer()
                Button("Done") { done() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 580, height: 560).background(Color(nsColor: .windowBackgroundColor))
        .alert("Clear extension activity?", isPresented: $confirmingClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { recorder.clear() }
        } message: {
            Text("Volant forgets the activity it recorded since it started. Extensions and their permissions don’t change.")
        }
    }

    /// The chosen extension's access, as its row in Settings describes it, with a way to turn it off.
    private func accessRow(_ ext: InstalledExtension) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: ext.accessDescription).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Turn Off") { turnOff(ext) }.controlSize(.small).disabled(!ext.enabled)
                .accessibilityIdentifier("extension-activity-turn-off")
        }
    }

    @ViewBuilder private var list: some View {
        if events.isEmpty {
            Text(problemsOnly ? "No problems recorded." : "No activity yet.")
                .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.offset) { index, event in
                        row(event).padding(.horizontal, 10).padding(.vertical, 5)
                            .background(index.isMultiple(of: 2) ? Color.clear : Color(nsColor: .alternatingContentBackgroundColors[1]))
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))
            .accessibilityIdentifier("extension-activity-list")
        }
    }

    private func row(_ event: ExtensionActivity) -> some View {
        let outcome = Self.outcome(event.outcome)
        return HStack(spacing: 8) {
            Image(systemName: outcome.symbol).foregroundStyle(outcome.color).frame(width: 16).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: Self.summary(event))
                Text(verbatim: details(event)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(verbatim: outcome.label).font(.caption).foregroundStyle(outcome.color)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// The line under an event: which extension (when showing all), when, how long and which run.
    private func details(_ event: ExtensionActivity) -> String {
        var parts: [String] = []
        if filter == nil { parts.append(extensions.first { $0.id == event.extensionID }?.name ?? event.extensionID) }
        parts.append(event.time.formatted(date: .omitted, time: .standard))
        if let duration = event.duration {
            parts.append(Duration.milliseconds(Int64((duration * 1000).rounded()))
                .formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow)))
        }
        parts.append(String(localized: "Run \(event.invocation)", comment: "Extension Activity detail: the number of the run an event belongs to"))
        return parts.joined(separator: " · ")
    }

    /// What an event was, in words: a module call by its phase, a request by its host, or the operation.
    static func summary(_ event: ExtensionActivity) -> String {
        switch event.operation {
        case .module:
            switch event.detail {
            case "plan": return String(localized: "Planning requests", comment: "Extension Activity event: the extension decided which addresses to fetch")
            case "render": return String(localized: "Showing results", comment: "Extension Activity event: the extension turned fetched data into rows")
            case "action": return String(localized: "Row action", comment: "Extension Activity event: the owner chose an action on an extension's row")
            case "opened": return String(localized: "Opening a result", comment: "Extension Activity event: the owner opened an extension's row")
            case "run": return String(localized: "Run", comment: "Extension Activity event: a text extension ran once")
            default: return String(localized: "Extension call", comment: "Extension Activity event: a call into the extension of another kind")
            }
        case .fetch:
            return event.detail.map { String(localized: "Request to \($0)", comment: "Extension Activity event: a GET request; the value is a host name") }
                ?? String(localized: "Request to an unlisted address", comment: "Extension Activity event: a request whose host was not valid")
        case .post:
            return event.detail.map { String(localized: "Action request to \($0)", comment: "Extension Activity event: a row action's POST; the value is a host name") }
                ?? String(localized: "Action request to an unlisted address", comment: "Extension Activity event: a POST whose host was not valid")
        case .clipboardRead: return String(localized: "Clipboard read", comment: "Extension Activity event")
        case .clipboardWrite: return String(localized: "Clipboard write", comment: "Extension Activity event")
        case .log: return String(localized: "Log message", comment: "Extension Activity event: the extension wrote to Volant's log")
        case .location: return String(localized: "Location request", comment: "Extension Activity event: the extension asked for approximate location")
        case .storageSave: return String(localized: "Saving its data", comment: "Extension Activity event: the extension saved its stored data")
        case .svgRender: return String(localized: "Image preview", comment: "Extension Activity event: Volant drew a row image's SVG preview")
        }
    }

    /// How an outcome reads and looks: a label, a symbol and a color.
    static func outcome(_ outcome: ExtensionActivity.Outcome) -> (label: String, symbol: String, color: Color) {
        switch outcome {
        case .completed: return (String(localized: "Completed", comment: "Extension Activity outcome"), "checkmark.circle", .secondary)
        case .failed: return (String(localized: "Failed", comment: "Extension Activity outcome"), "exclamationmark.triangle", .orange)
        case .denied: return (String(localized: "Denied", comment: "Extension Activity outcome: Volant refused the request"), "hand.raised", .red)
        case .cancelled: return (String(localized: "Cancelled", comment: "Extension Activity outcome"), "xmark.circle", .secondary)
        case .timedOut: return (String(localized: "Timed out", comment: "Extension Activity outcome"), "clock.badge.exclamationmark", .orange)
        }
    }

    /// Saves exactly the events on screen, through a Save panel, to a file the owner names.
    private func export() {
        exportError = nil
        let shown = events, dropped = recorder.log.dropped
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = String(localized: "Extension Activity.json", comment: "Default file name for an exported extension activity history")
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try ExtensionActivityExport.json(shown, dropped: dropped, exportedAt: Date()).write(to: url, options: .atomic)
            } catch {
                exportError = String(localized: "Couldn’t save the activity file.", comment: "Extension Activity export error")
            }
        }
    }
}
