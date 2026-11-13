import SwiftUI
import VolantCore

/// The Focus fields of the launcher's entry form: the goal in the shared name field, the length,
/// and the block list as removable chips with an add field that suggests categories, apps and
/// websites. Return in the add field adds its first suggestion rather than starting the session.
struct FocusFormFields<Goal: View>: View {
    @ObservedObject var focus: FocusDraft
    let appSearch: (String) -> [AppEntry]
    let goalField: Goal
    @FocusState private var addFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 12) {
                labeled(String(localized: "Goal", comment: "Focus form field label")) { goalField }
                labeled(String(localized: "Length", comment: "Focus form field label")) {
                    Picker(String(localized: "Length", comment: "Focus form field label"), selection: $focus.minutes) {
                        ForEach(lengthChoices, id: \.self) { minutes in
                            Text(minutes.map { String(localized: "\($0, specifier: "%lld") minutes", comment: "Focus length choice") }
                                 ?? String(localized: "Until ended", comment: "Focus length choice without a time limit")).tag(minutes)
                        }
                    }
                    .labelsHidden().fixedSize()
                    .accessibilityIdentifier("focus-length")
                }
            }
            labeled(String(localized: "Block", comment: "Focus form field label: apps and websites to block")) {
                VStack(alignment: .leading, spacing: 6) {
                    if !focus.blocks.isEmpty { chips }
                    TextField(String(localized: "Add an app, website or category", comment: "Focus form placeholder"), text: $focus.addText)
                        .focused($addFocused)
                        .onSubmit { if let first = suggestions.first { focus.add(first) } }
                        .accessibilityIdentifier("focus-add")
                    if addFocused || !focus.addText.isEmpty { suggestionList }
                }
            }
        }
    }

    private var lengthChoices: [Int?] {
        var choices: [Int?] = FocusSetup.durationChoices.map(Optional.some)
        if let minutes = focus.minutes, !FocusSetup.durationChoices.contains(minutes) { choices.append(minutes) }
        return choices + [nil]
    }

    private var suggestions: [FocusBlockItem] { focus.suggestions(apps: appSearch) }

    private var chips: some View {
        FocusChipLayout(spacing: 6) {
            ForEach(focus.blocks) { item in
                HStack(spacing: 4) {
                    Image(systemName: item.symbol).font(.system(size: 10)).foregroundStyle(.secondary).accessibilityHidden(true)
                    Text(item.title).font(.system(size: 12)).lineLimit(1)
                    Button { focus.remove(item) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)) }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(String(localized: "Remove \(item.title, format: .verbatim)", comment: "Accessibility label for removing an item from the Focus block list"))
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.secondary.opacity(0.14), in: Capsule())
            }
        }
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(suggestions) { item in
                Button { focus.add(item) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.symbol).frame(width: 14).foregroundStyle(.secondary).accessibilityHidden(true)
                        Text(item.title)
                        Spacer()
                        if case .category(let category) = item {
                            Text("\(category.websites.count + category.apps.count, specifier: "%lld") items", comment: "Focus form: how many apps and websites a category adds")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .font(.system(size: 12))
            }
        }
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            content().textFieldStyle(.roundedBorder)
        }
    }
}

/// Lays chips out in rows, wrapping to the next row when one doesn't fit.
struct FocusChipLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(widest, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
