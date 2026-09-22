import AppKit
import SwiftUI

/// Grouped-form footers default to trailing, primary text on macOS 15; explanatory copy reads as
/// a caption under its section instead.
struct SettingsFooter: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// An empty AppKit view behind a SwiftUI control, so native fixtures can find the control's frame
/// by identifier. SwiftUI builds its accessibility tree only for an assistive client, and form
/// buttons have no NSButton to search for.
struct ControlAnchor: NSViewRepresentable {
    let identifier: String
    init(_ identifier: String) { self.identifier = identifier }
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.identifier = NSUserInterfaceItemIdentifier(identifier)
        view.setAccessibilityElement(false)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
