import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The share extension's entry point: collects the shared text or link, then hosts the compose view.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let model = ShareModel(context: extensionContext)
        let host = UIHostingController(rootView: ShareComposeView(model: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        Task { await model.load() }
    }
}

/// What was shared and the note being written from it.
@MainActor
final class ShareModel: ObservableObject {
    @Published var title = ""
    @Published var body = ""
    @Published var saving = false
    @Published var error: String?
    private let context: NSExtensionContext?

    init(context: NSExtensionContext?) {
        self.context = context
    }

    /// Reads the shared items: a page link with its title, or plain text whose first line becomes the title.
    func load() async {
        let providers = (context?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        let pageTitle = (context?.inputItems.first as? NSExtensionItem)?.attributedContentText?.string
        var link: URL?
        var text: String?
        for provider in providers {
            if link == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                link = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL
            } else if text == nil, provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String
            }
        }
        if let link {
            title = pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? link.host() ?? ""
            body = [text, link.absoluteString].compactMap { $0 }.joined(separator: "\n\n")
        } else if let text {
            let lines = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            if lines.count > 1, lines[0].count <= 80 {
                title = String(lines[0])
                body = String(lines[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                body = text
            }
        }
    }

    func save() {
        saving = true
        let text = NoteWriter.markdown(title: title, body: body)
        Task.detached {
            do {
                _ = try NoteWriter.save(text)
                await MainActor.run { self.context?.completeRequest(returningItems: nil) }
            } catch {
                await MainActor.run {
                    self.saving = false
                    self.error = String(localized: "The note couldn’t be saved: \(error.localizedDescription)")
                }
            }
        }
    }

    func cancel() {
        context?.cancelRequest(withError: CocoaError(.userCancelled))
    }
}

/// A compact note composer branded like the app: title, body, Cancel and Save.
struct ShareComposeView: View {
    @ObservedObject var model: ShareModel
    @FocusState private var focus: Field?

    private enum Field { case title, body }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Title", text: $model.title)
                    .font(.title2.weight(.bold))
                    .focused($focus, equals: .title)
                    .submitLabel(.next)
                    .onSubmit { focus = .body }
                TextEditor(text: $model.body)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .focused($focus, equals: .body)
                    .overlay(alignment: .topLeading) {
                        if model.body.isEmpty {
                            Text("Write something…").foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
                        }
                    }
                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.red)
                }
            }
            .padding(20)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        VolantMark(size: 18)
                        Text("Save to Volant").font(.headline)
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: model.cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: model.save)
                        .disabled(model.saving || (model.title.isEmpty && model.body.isEmpty))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { focus = .body }
        }
        .tint(Brand.rust)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
