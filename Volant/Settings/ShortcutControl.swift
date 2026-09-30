import SwiftUI

/// Recording and removal commit immediately. A failed write stays pending for retry.
struct ShortcutControl: View {
    let title: String
    let value: String
    let onSave: (String) throws -> Void
    @State private var saved = false
    @State private var removed = false
    @State private var pending: String?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            ShortcutRecorder(value: Binding(get: { value }, set: { persist($0) }), removable: true)
                .frame(height: 26)
                .accessibilityLabel(title + " shortcut: " + (value.isEmpty ? "Not set" : value))
                .accessibilityAction(named: "Remove shortcut") { persist("") }
            if let error {
                Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                if let pending { Button("Retry") { persist(pending) }.font(.callout) }
            } else if saved {
                Label(removed ? "Removed" : "Saved", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel(title + (removed ? " shortcut removed" : " shortcut saved"))
            }
        }
    }
    private func persist(_ replacement: String) {
        saved = false
        pending = replacement
        do {
            try onSave(replacement)
            pending = nil
            error = nil
            removed = replacement.isEmpty
            saved = true
        } catch { self.error = error.localizedDescription }
    }
}
