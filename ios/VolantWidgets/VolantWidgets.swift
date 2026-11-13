import SwiftUI
import WidgetKit

/// Volant's widgets: recent notes, quick actions, and a Control Center control for a new note.
@main
struct VolantWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RecentNotesWidget()
        QuickActionsWidget()
        NewNoteControl()
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: NotesSnapshot
}

/// Reads the snapshot the app writes to the App Group. The app reloads timelines whenever its
/// notes change, so the widget needs no schedule of its own beyond a daily refresh for relative dates.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let stored = AppGroup.readSnapshot()
        completion(SnapshotEntry(date: Date(), snapshot: context.isPreview && stored.recent.isEmpty ? .placeholder : stored))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(), snapshot: AppGroup.readSnapshot())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(6 * 3600))))
    }
}

struct RecentNotesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RecentNotes", provider: SnapshotProvider()) { entry in
            RecentNotesEntryView(entry: entry)
        }
        .configurationDisplayName("Recent Notes")
        .description("Your latest Volant notes, one tap from the Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

private struct RecentNotesEntryView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        RecentNotesWidgetView(snapshot: entry.snapshot, family: family)
            .containerBackground(for: .widget) { WidgetBackground() }
    }
}

struct QuickActionsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickActions", provider: SnapshotProvider()) { _ in
            QuickActionsEntryView()
        }
        .configurationDisplayName("Quick Actions")
        .description("Start a note, search, copy a snippet or calculate.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

private struct QuickActionsEntryView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        QuickActionsWidgetView(family: family)
            .containerBackground(for: .widget) { WidgetBackground() }
    }
}

/// A Control Center, Lock Screen and Action button control that opens a new note.
struct NewNoteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.mysticcoders.volant.mobile.new-note") {
            ControlWidgetButton(action: NewNoteInAppIntent()) {
                Label("New Note", systemImage: "square.and.pencil")
            }
        }
        .displayName("New Volant Note")
        .description("Opens Volant to a new note.")
    }
}

extension NotesSnapshot {
    /// Fictional notes for the widget gallery before the app has written a snapshot.
    static let placeholder = NotesSnapshot(recent: [
        .init(id: "a", title: "Weekend plan", preview: "Pick up the bikes on Saturday morning.", modified: Date().addingTimeInterval(-1800), pinned: true),
        .init(id: "b", title: "Reading list", preview: "A Pattern Language", modified: Date().addingTimeInterval(-86_400), pinned: false),
        .init(id: "c", title: "Coffee order", preview: "Oat flat white, extra hot.", modified: Date().addingTimeInterval(-200_000), pinned: false)
    ], all: [], inICloud: true)
}
