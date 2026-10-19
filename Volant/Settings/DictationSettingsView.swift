import SwiftUI
import UniformTypeIdentifiers
import VolantCore

/// Settings → Dictation: where dictation's text goes, when typing happens, the Accessibility state
/// while typing is chosen, the cleanup, sound and volume options, and the owner's vocabulary.
struct DictationSettingsView: View {
    let config: Preferences
    @ObservedObject var access: DictationTypingAccess
    let apply: (() throws -> Void) -> Void
    let configURL: URL
    @State private var editing: VocabularyEdit?
    @State private var importNotice: String?

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Picker("Dictation output", selection: Binding(get: { config.dictationOutput }, set: choose)) {
                        Text("Copy to clipboard").tag(DictationOutput.copy)
                        Text("Type at the cursor").tag(DictationOutput.type)
                    }.labelsHidden().fixedSize()
                } label: {
                    Text("Dictation output")
                    Text(config.dictationOutput == .type ? "Types into the app you’re using." : "Copies what you said; press ⌘V to paste it.")
                }
                if config.dictationOutput == .type {
                    LabeledContent("Type") {
                        Picker("Type", selection: Binding(get: { config.dictationTypesWhileSpeaking }, set: { value in
                            apply { try Preferences.updateBoolean("dictationTypesWhileSpeaking", value: value, at: configURL) }
                        })) {
                            Text("While speaking").tag(true)
                            Text("When finished").tag(false)
                        }.labelsHidden().fixedSize()
                    }
                    LabeledContent("Accessibility") { DictationAccessStatus(access: access) }
                } else if access.stoppedHelper {
                    LabeledContent {
                        Button("Open Accessibility Settings") { access.openAccessibilitySettings() }
                    } label: {
                        Text("Volant no longer uses Accessibility. To remove its access, turn off Volant in Privacy & Security → Accessibility.")
                            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            } footer: {
                SettingsFooter(footer)
            }
            Section {
                Toggle(isOn: Binding(get: { config.dictationRemovesFillers }, set: { value in
                    apply { try Preferences.updateBoolean("dictationRemovesFillers", value: value, at: configURL) }
                })) {
                    Text("Remove filler words")
                    Text("Takes um, uh, er and hmm out of English dictation; words like “like” stay.")
                }
                Toggle("Play sounds when dictation starts and stops", isOn: Binding(get: { config.dictationPlaysSounds }, set: { value in
                    apply { try Preferences.updateBoolean("dictationPlaysSounds", value: value, at: configURL) }
                }))
                Toggle(isOn: Binding(get: { config.dictationLowersVolume }, set: { value in
                    apply { try Preferences.updateBoolean("dictationLowersVolume", value: value, at: configURL) }
                })) {
                    Text("Lower volume while dictating")
                    Text("Plays audio at a fifth of its volume while listening, then restores it unless you changed it.")
                }
            } header: {
                Text("While Dictating")
            }
            vocabularySection
        }
        .formStyle(.settings)
        .sheet(item: $editing) { edit in
            VocabularyEntryEditor(edit: edit, cancel: { editing = nil }, save: { entry in
                editing = nil
                var list = config.dictationVocabulary
                if let original = edit.original, let index = list.firstIndex(where: { $0.id == original.id }) { list[index] = entry } else { list.append(entry) }
                saveVocabulary(list)
            })
        }
        .onAppear { access.refresh(config.dictationOutput) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            access.refresh(config.dictationOutput)
        }
    }

    /// The owner's words, each with what dictation tends to hear instead, and how to add or import them.
    @ViewBuilder private var vocabularySection: some View {
        Section {
            if config.dictationVocabulary.isEmpty {
                Text("No words yet. Add names and technical terms dictation gets wrong, such as Kubernetes.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(config.dictationVocabulary) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.term)
                        if !entry.soundsLike.isEmpty {
                            Text("Also heard as " + entry.soundsLike.joined(separator: ", "))
                                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer()
                    Button("Edit…") { editing = VocabularyEdit(original: entry) }.controlSize(.small)
                        .accessibilityIdentifier("dictation-vocabulary-edit-" + entry.id)
                    Button("Remove") { saveVocabulary(config.dictationVocabulary.filter { $0.id != entry.id }) }.controlSize(.small)
                        .accessibilityIdentifier("dictation-vocabulary-remove-" + entry.id)
                }
            }
            if let importNotice { Text(importNotice).font(.callout).foregroundStyle(.secondary) }
        } header: {
            HStack {
                Text("Vocabulary")
                Spacer()
                Button("Import…") { importVocabulary() }.controlSize(.small).font(.callout)
                    .accessibilityIdentifier("dictation-vocabulary-import")
                Button("Add Word…") { editing = VocabularyEdit(original: nil) }.controlSize(.small).font(.callout)
                    .disabled(config.dictationVocabulary.count >= DictationVocabulary.maximumEntries)
                    .accessibilityIdentifier("dictation-vocabulary-add")
            }
        } footer: {
            SettingsFooter("Dictation writes each word as you typed it here, replacing what you list as also heard and any other capitalization of the word. When a word comes out wrong, add what you saw as also heard. Import a text file with one word per line, or a CSV of heard and written pairs. Your list stays in Volant’s settings and syncs with iCloud when settings sync is on.")
        }
    }

    /// Saves the list against the one on screen, so an edit made from a stale list is refused.
    private func saveVocabulary(_ list: [DictationVocabularyEntry]) {
        importNotice = nil
        apply { try Preferences.updateDictationVocabulary(list, expected: config.dictationVocabulary, at: configURL) }
    }

    /// Reads a chosen text or CSV file of at most 1 MB and adds its words to the list.
    private func importVocabulary() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .commaSeparatedText, .tabSeparatedText]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a text file with one word per line, or a CSV of heard and written pairs."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let before = config.dictationVocabulary
        do {
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 1_048_576 else {
                importNotice = "That file is larger than 1 MB, so nothing was imported."; return
            }
            let (entries, skipped) = DictationVocabulary.parse(importing: try String(contentsOf: url, encoding: .utf8))
            let merged = DictationVocabulary.merging(entries, into: before)
            var saved = false
            apply {
                try Preferences.updateDictationVocabulary(merged, expected: before, at: configURL)
                saved = true
            }
            guard saved else { return }
            let added = merged.count - before.count
            importNotice = "Added \(added) \(added == 1 ? "word" : "words")" + (entries.count > added ? " and updated others" : "")
                + (skipped > 0 ? "; skipped \(skipped) \(skipped == 1 ? "line" : "lines") that weren’t a word or a pair." : ".")
        } catch {
            importNotice = "Couldn’t read that file as UTF-8 text."
        }
    }

    /// Saves the choice, then lets the access model connect, prompt once, or stop the helper.
    private func choose(_ output: DictationOutput) {
        guard output != config.dictationOutput else { return }
        var saved = false
        apply {
            try Preferences.updateDictationOutput(output, at: configURL)
            saved = true
        }
        if saved { access.chose(output) }
    }

    private var footer: String {
        guard config.dictationOutput == .type else {
            return "Type at the cursor asks once for Accessibility permission."
        }
        return "Each phrase is typed as soon as it’s final, or everything when you stop. Return finishes and Escape cancels. Volant never types into password fields or while secure input is on, and copies instead. Only Volant’s input helper uses Accessibility; System Settings lists it as Volant."
    }
}

/// The Accessibility state for typing, with the action that fixes it.
struct DictationAccessStatus: View {
    @ObservedObject var access: DictationTypingAccess

    var body: some View {
        HStack(spacing: 8) {
            switch access.state {
            case .idle, .checking:
                ProgressView().controlSize(.small)
                Text("Checking…").foregroundStyle(.secondary)
            case .allowed:
                Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
            case .notAllowed:
                Text("Not allowed").foregroundStyle(.secondary)
                Button("Open Accessibility Settings") { access.openAccessibilitySettings() }
            case .unavailable:
                Text("Input helper unavailable").foregroundStyle(.secondary)
                Button("Check Again") { access.refresh(.type) }
            }
        }
    }
}

/// A vocabulary word being added (no original) or edited.
struct VocabularyEdit: Identifiable {
    let id = UUID()
    let original: DictationVocabularyEntry?
}

/// The sheet for one vocabulary word: how to write it and what dictation hears instead.
struct VocabularyEntryEditor: View {
    let edit: VocabularyEdit
    let cancel: () -> Void
    let save: (DictationVocabularyEntry) -> Void
    @State private var term: String
    @State private var heard: String

    init(edit: VocabularyEdit, cancel: @escaping () -> Void, save: @escaping (DictationVocabularyEntry) -> Void) {
        self.edit = edit; self.cancel = cancel; self.save = save
        _term = State(initialValue: edit.original?.term ?? "")
        _heard = State(initialValue: edit.original?.soundsLike.joined(separator: ", ") ?? "")
    }

    private var entry: DictationVocabularyEntry? {
        DictationVocabulary.normalized([DictationVocabularyEntry(term: term, soundsLike: heard.split(separator: ",").map(String.init))]).first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(edit.original == nil ? "Add Word" : "Edit Word").font(.title2.bold())
            VStack(alignment: .leading, spacing: 6) {
                Text("Write it as").font(.headline)
                TextField("Kubernetes", text: $term).textFieldStyle(.roundedBorder).labelsHidden()
                    .accessibilityIdentifier("dictation-vocabulary-term")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Also heard as").font(.headline)
                TextField("cooper netties, cuber nettis", text: $heard).textFieldStyle(.roundedBorder).labelsHidden()
                    .accessibilityIdentifier("dictation-vocabulary-heard")
                Text("Optional. Separate with commas. Each is replaced with the word above, as whole words.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Save") { if let entry { save(entry) } }.keyboardShortcut(.defaultAction).disabled(entry == nil)
            }
        }
        .padding(24).frame(width: 400)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
