import SwiftUI
import VolantCore

/// What Send to Several needs from the launcher: the stored AI settings, read when the picker opens,
/// the call that starts the conversations, and the call that drops a send still checking its folder
/// when the picker closes.
struct ACPFanOutHost {
    let settings: () -> AIConfiguration?
    let send: (ACPModel, AIConfiguration, [ACPProvider: Int], Bool, @escaping (String?) -> Void) -> Void
    let cancel: () -> Void
}

/// Send to Several's inline picker: how many conversations of each ACP agent to start with the
/// composer's prompt, and whether they run headless. Shown above the composer, as the @ picker is.
struct ACPFanOutPicker: View {
    /// Nil when AI Settings could not be read.
    let settings: AIConfiguration?
    /// Starts the conversations and replies with the reason when nothing started.
    let send: (AIConfiguration, [ACPProvider: Int], Bool, @escaping (String?) -> Void) -> Void
    let close: () -> Void
    @State private var counts: [ACPProvider: Int] = [:]
    @State private var headless = false
    @State private var sending = false
    @State private var problem: String?

    private var limit: Int { ACPFanOut.clamp(settings?.fanOut ?? ACPFanOut.defaultLimit) }
    private var total: Int { counts.values.reduce(0, +) }
    private var folder: String { settings?.project ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "square.stack").foregroundStyle(.secondary)
                Text("Send to Several").fontWeight(.medium)
                Spacer()
                Button(action: close) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).help("Close").accessibilityLabel("Close Send to Several")
            }
            Text(placement).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 4) {
                ForEach(ACPProvider.allCases) { provider in stepper(provider) }
            }
            Toggle("Headless", isOn: $headless).toggleStyle(.checkbox)
                .help("Start without opening; each conversation ends after its first turn and keeps its transcript")
            if let problem { Text(problem).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Text("\(total) of \(limit)").font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel("\(total) of at most \(limit) conversations")
                Spacer()
                Button("Cancel", action: close)
                Button("Send", action: submit).disabled(total == 0 || sending || settings == nil)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        .background(ControlAnchor("chat.fan-out"))
        .onAppear { if settings == nil { problem = "Couldn’t read AI Settings. Open them to choose an agent." } }
    }

    /// Where the conversations run: each in its own workspace of the folder, or in general chat.
    private var placement: String {
        if folder.isEmpty { return "Each conversation starts in general chat with this prompt and any attachments." }
        return "Each conversation gets its own workspace of “\((folder as NSString).lastPathComponent)” and is sent this prompt and any attachments."
    }

    /// The range stops at what the other agents leave of the limit, so the total can never pass it.
    private func stepper(_ provider: ACPProvider) -> some View {
        let count = counts[provider] ?? 0
        let binding = Binding(get: { counts[provider] ?? 0 }, set: { counts[provider] = $0; problem = nil })
        return Stepper(value: binding, in: 0...(count + max(0, limit - total))) {
            HStack(spacing: 4) {
                Text(provider.title).lineLimit(1)
                Text("\(count)").monospacedDigit().foregroundStyle(count == 0 ? Color.secondary : Color.primary)
            }
        }
        .font(.system(size: 12))
        .accessibilityLabel(provider.title)
        .accessibilityValue("\(count)")
    }

    private func submit() {
        guard let settings, !sending else { return }
        sending = true; problem = nil
        send(settings, counts, headless) { reason in
            sending = false
            if let reason { problem = reason } else { close() }
        }
    }
}
