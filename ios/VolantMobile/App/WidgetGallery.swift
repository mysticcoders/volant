import SwiftUI
import WidgetKit

/// A fixture screen, opened with `-fixtureWidgets YES`, that draws the widget views at their Home
/// Screen sizes from the snapshot the app wrote, so they can be checked without adding widgets.
struct WidgetGallery: View {
    @State private var snapshot = AppGroup.readSnapshot()

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 18) {
                    tile(width: 170, height: 170) { RecentNotesWidgetView(snapshot: snapshot, family: .systemSmall) }
                    tile(width: 170, height: 170) { QuickActionsWidgetView(family: .systemSmall) }
                }
                tile(width: 358, height: 170) { RecentNotesWidgetView(snapshot: snapshot, family: .systemMedium) }
                tile(width: 358, height: 170) { QuickActionsWidgetView(family: .systemMedium) }
                tile(width: 358, height: 376) { RecentNotesWidgetView(snapshot: snapshot, family: .systemLarge) }
            }
            .padding(.vertical, 20)
        }
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.25))
        .task {
            try? await Task.sleep(for: .seconds(1.5))
            snapshot = AppGroup.readSnapshot()
        }
    }

    private func tile<Content: View>(width: CGFloat, height: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(width: width, height: height)
            .background(WidgetBackground())
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
