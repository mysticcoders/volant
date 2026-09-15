import SwiftUI
import Translation

struct TranslationView: View {
    @ObservedObject var model: TranslationModel
    let caffeinate: CaffeinateService
    let back: () -> Void
    let copy: (String) -> Void
    @FocusState private var editing: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: back) { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain).help("Back to search (⌘[)")
                    .accessibilityLabel("Back to search").keyboardShortcut("[", modifiers: .command)
                languagePicker("Source language", selection: $model.source, auto: true)
                Spacer(minLength: 8)
                languagePicker("Target language", selection: $model.target, auto: false)
            }.padding(16)
            Divider()
            HStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    if model.text.isEmpty {
                        Text("Enter text…").foregroundStyle(.secondary).padding(.horizontal, 5).padding(.top, 1)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                    TextEditor(text: $model.text).scrollContentBackground(.hidden)
                        .focused($editing).accessibilityLabel("Text to translate")
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.primary.opacity(0.035))
                Divider()
                ScrollView {
                    Text(model.output.isEmpty ? "Translation" : model.output)
                        .foregroundStyle(model.output.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .accessibilityLabel(model.output.isEmpty ? "Translation result is empty" : "Translation: " + model.output)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .font(.system(size: 18))
            .overlay {
                Button { model.swap(); editing = true } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .frame(width: 34, height: 34)
                        .background(.regularMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.12)))
                }
                .buttonStyle(.plain).disabled(!model.canSwap)
                .help("Swap languages and use the translation as input")
                .accessibilityLabel("Swap languages")
            }
            HStack(spacing: 8) {
                if model.busy { ProgressView().controlSize(.small) }
                Text(model.status).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).accessibilityLabel("Translation status: " + model.status)
                Spacer(minLength: 0)
                if !model.text.isEmpty {
                    Button("Clear") { model.clear(); editing = true }.buttonStyle(.plain).font(.system(size: 12))
                }
            }.padding(.horizontal, 16).padding(.vertical, 8)
            if model.catalogFailed {
                HStack {
                    Text("Language list unavailable").font(.caption)
                    Button("Retry Languages") { Task { await model.loadCatalog() } }
                }.padding(.bottom, 8)
            }
            Divider()
            HStack(spacing: 12) {
                Image("VolantWing").renderingMode(.template).resizable().scaledToFit()
                    .frame(width: 16, height: 16).foregroundStyle(Color.accentColor)
                    .overlay(LauncherDragHandle()).help("Drag to position Volant")
                CaffeinateStatusView(service: caffeinate)
                Text("Translate").font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
                if model.busy {
                    Button("Cancel") { model.cancel() }
                } else {
                    Button("Translate ⌘T") { model.start() }
                        .keyboardShortcut("t", modifiers: .command).disabled(!model.canTranslate)
                }
                Button("Copy Translation ⌘↩") { model.copy(using: copy) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.output.isEmpty || model.busy)
            }.controlSize(.small).padding(.horizontal, 16).padding(.vertical, 10)
        }
        .task { editing = true; await model.loadCatalog() }
        .onDisappear { if model.busy { model.cancel() } }
        .background {
            if let request = model.request {
                TranslationSessionView(model: model, request: request).id(request.id)
            }
        }
    }

    private func languagePicker(_ title: String, selection: Binding<String>, auto: Bool) -> some View {
        let choices = Array(Set(model.languages + [selection.wrappedValue].filter { !$0.isEmpty }))
            .sorted { TranslationModel.languageName($0).localizedStandardCompare(TranslationModel.languageName($1)) == .orderedAscending }
        return Picker(title, selection: selection) {
            if auto { Text("Detect Language").tag("") }
            ForEach(choices, id: \.self) { id in Text(TranslationModel.languageName(id)).tag(id) }
        }
        .labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity)
        .accessibilityLabel(title)
    }
}

/// A fresh view owns each session so removing it cancels the SwiftUI translation task.
private struct TranslationSessionView: View {
    let model: TranslationModel
    let request: TranslationRequest
    var body: some View {
        if let fixture = model.translateFixture {
            Color.clear.task { await model.perform(request, translate: fixture) }
        } else {
            Color.clear.translationTask(TranslationSession.Configuration(
                source: request.source.isEmpty ? nil : Locale.Language(identifier: request.source),
                target: Locale.Language(identifier: request.target))) { session in
                await model.perform(request) { current in
                    let result = try await session.translate(current.text)
                    return TranslationResult(text: result.targetText, source: result.sourceLanguage.minimalIdentifier)
                }
            }
        }
    }
}
