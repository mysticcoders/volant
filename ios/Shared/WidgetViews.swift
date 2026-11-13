import SwiftUI
import WidgetKit
import AppIntents

/// Opens Volant to a new note. Shared with the widget extension so a Control Center control and
/// widget buttons can run it; it always runs in the app, which reads the posted link.
struct NewNoteInAppIntent: AppIntent {
    static let title: LocalizedStringResource = "New Volant Note"
    static let description = IntentDescription("Opens Volant to a new, empty note.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DeepLinkCenter.post(.newNote)
        return .result()
    }
}

/// Recent notes for the Home Screen: the latest note on the small size, a list on larger sizes,
/// one line on the Lock Screen. Every row opens its note.
struct RecentNotesWidgetView: View {
    let snapshot: NotesSnapshot
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryRectangular: lockScreen
        case .systemSmall: small
        default: list(limit: family == .systemLarge ? 7 : 3)
        }
    }

    private var lockScreen: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("Volant", systemImage: "note.text").font(.caption2.weight(.semibold))
            Text(snapshot.recent.first?.title ?? String(localized: "No notes yet")).font(.headline).lineLimit(1)
            if let note = snapshot.recent.first { Text(note.modified, style: .relative).font(.caption2).foregroundStyle(.secondary) }
        }
        .widgetURL(snapshot.recent.first.map { DeepLink.note($0.id).url } ?? DeepLink.newNote.url)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: String(localized: "Notes"))
            Spacer(minLength: 0)
            if let note = snapshot.recent.first {
                Text(note.title).font(.headline).lineLimit(2)
                Text(note.preview).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text(note.modified, style: .relative).font(.caption2).foregroundStyle(.tertiary)
            } else {
                Text("A little space to think").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(snapshot.recent.first.map { DeepLink.note($0.id).url } ?? DeepLink.newNote.url)
    }

    private func list(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                WidgetHeader(title: String(localized: "Notes"))
                Spacer()
                Link(destination: DeepLink.newNote.url) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Brand.rust)
                        .frame(width: 30, height: 30)
                        .background(.quaternary, in: .circle)
                }
            }
            if snapshot.recent.isEmpty {
                Spacer()
                Text("A little space to think").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(snapshot.recent.prefix(limit)) { note in
                    Link(destination: DeepLink.note(note.id).url) {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 2).fill(note.pinned ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(.quaternary))
                                .frame(width: 3)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(note.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(note.preview.isEmpty ? note.modified.formatted(.relative(presentation: .named)) : note.preview)
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(Color.primary, Color.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The wing and a label at the top of a widget.
struct WidgetHeader: View {
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            VolantMark(size: 16)
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
    }
}

/// One-tap ways into Volant: a new note, search, snippets and the calculator.
struct QuickActionsWidgetView: View {
    let family: WidgetFamily

    private let actions: [(Tool, String, DeepLink)] = [
        (.notes, String(localized: "New Note"), .newNote),
        (.quicklinks, String(localized: "Search"), .search),
        (.snippets, String(localized: "Snippets"), .tool(Tool.snippets.rawValue)),
        (.calculator, String(localized: "Calculator"), .tool(Tool.calculator.rawValue))
    ]

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    VolantMarkShape().frame(width: 20, height: 20)
                    Image(systemName: "plus").font(.caption.weight(.bold))
                }
            }
            .widgetURL(DeepLink.newNote.url)
        case .systemSmall:
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow { tile(actions[0], labeled: false); tile(actions[1], labeled: false) }
                GridRow { tile(actions[2], labeled: false); tile(actions[3], labeled: false) }
            }
        default:
            VStack(alignment: .leading, spacing: 10) {
                WidgetHeader(title: "Volant")
                HStack(spacing: 10) {
                    ForEach(actions.indices, id: \.self) { tile(actions[$0], labeled: true) }
                }
            }
        }
    }

    private func tile(_ action: (Tool, String, DeepLink), labeled: Bool) -> some View {
        Link(destination: action.2.url) {
            VStack(spacing: 6) {
                ToolIcon(tool: action.0, size: labeled ? 44 : 52, symbol: action.2 == .search ? "magnifyingglass" : nil)
                if labeled { Text(action.1).font(.caption2.weight(.medium)).lineLimit(1).foregroundStyle(Color.primary) }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// The background every Volant widget shares: the system surface with a faint wash of the brand.
struct WidgetBackground: View {
    var body: some View {
        ZStack {
            Color(uiColor: .secondarySystemBackground)
            LinearGradient(colors: [Brand.coral.opacity(0.14), .clear], startPoint: .topLeading, endPoint: .center)
        }
    }
}
