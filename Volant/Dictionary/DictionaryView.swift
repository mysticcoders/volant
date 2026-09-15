import SwiftUI

struct DictionaryView: View {
    @ObservedObject var model: DictionaryModel
    let caffeinate: CaffeinateService
    let back: () -> Void
    let copy: (String) -> Void
    @FocusState private var editing: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button(action: back) { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain).accessibilityLabel("Back to search")
                    .keyboardShortcut("[", modifiers: .command).help("Back to search (⌘[)")
                TextField("Word or phrase…", text: $model.input)
                    .textFieldStyle(.plain).font(.system(size: 22)).focused($editing)
                    .accessibilityLabel("Word or phrase to define")
                    .onSubmit { model.search(immediate: true) }
                if !model.input.isEmpty {
                    Button { model.clear(); editing = true } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear definition search")
                }
            }.padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if model.busy {
                        HStack { ProgressView().controlSize(.small); Text("Looking up definition…").foregroundStyle(.secondary) }
                    } else if let entry = model.entry {
                        Text(entry.term).font(.title2.weight(.semibold)).textSelection(.enabled)
                        Text(entry.definition).font(.system(size: 16)).lineSpacing(4).textSelection(.enabled)
                            .accessibilityLabel("Definition: " + entry.definition)
                    } else if model.term.count > DictionaryQuery.limit {
                        Text("Keep the lookup to 256 characters or fewer.").foregroundStyle(.secondary)
                    } else if model.searched {
                        Text(model.failed ? "Lookup unavailable" : "No definition found").font(.title3.weight(.semibold))
                        Text("Try another spelling, or check the enabled dictionaries in Dictionary → Settings.").foregroundStyle(.secondary)
                        Button("Try Again") { model.search(immediate: true) }
                    } else {
                        Label("Define a word or phrase", systemImage: "book.closed").font(.title3.weight(.semibold))
                        Text("Search the dictionaries enabled on your Mac. Results stay here until you leave this command.").foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if let message = model.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 8)
                    .accessibilityLabel("Dictionary status: " + message)
            }
            Divider()
            HStack(spacing: 12) {
                Image("VolantWing").renderingMode(.template).resizable().scaledToFit()
                    .frame(width: 16, height: 16).foregroundStyle(Color.accentColor).overlay(LauncherDragHandle())
                    .help("Drag to position Volant")
                CaffeinateStatusView(service: caffeinate)
                Text("Dictionary").font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
                Button("Open in Dictionary ⌘O") { model.open() }
                    .keyboardShortcut("o", modifiers: .command).disabled(!model.canLookup)
                Button("Copy Definition ⌘↩") { model.copy(using: copy) }
                    .keyboardShortcut(.return, modifiers: .command).disabled(model.entry == nil || model.busy)
            }.controlSize(.small).padding(.horizontal, 16).padding(.vertical, 10)
        }
        .onAppear { editing = true }
        .onDisappear { model.clear() }
    }
}
