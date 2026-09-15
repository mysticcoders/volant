import Foundation
import Combine
import Translation

enum TranslationPairState: Equatable {
    case installed, downloadable, unsupported
}

struct TranslationRequest: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let source: String
    let target: String
}

struct TranslationResult {
    let text: String
    let source: String
}

/// Memory-only draft. All mutations and completions run on the main thread.
final class TranslationModel: ObservableObject {
    static let textLimit = 16_000
    @Published var text = "" { didSet { if text != oldValue { invalidate() } } }
    @Published var source = "" { didSet { if source != oldValue { invalidate() } } }
    @Published var target = "en" { didSet { if target != oldValue { invalidate() } } }
    @Published private(set) var output = ""
    @Published private(set) var detectedSource: String?
    @Published private(set) var languages: [String] = []
    @Published private(set) var request: TranslationRequest?
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    @Published private(set) var pairState: TranslationPairState?
    @Published private(set) var catalogFailed = false
    private var generation = UUID()
    private var checking: Task<Void, Never>?
    private var loadingCatalog = false

    var loadLanguages: () async throws -> [String] = {
        await LanguageAvailability().supportedLanguages.map(\.minimalIdentifier)
    }
    var availability: (TranslationRequest) async throws -> TranslationPairState = { request in
        let service = LanguageAvailability()
        let target = Locale.Language(identifier: request.target)
        let status: LanguageAvailability.Status
        if request.source.isEmpty { status = try await service.status(for: request.text, to: target) }
        else { status = await service.status(from: Locale.Language(identifier: request.source), to: target) }
        switch status {
        case .installed: return .installed
        case .supported: return .downloadable
        case .unsupported: return .unsupported
        @unknown default: return .unsupported
        }
    }
    /// Fixtures replace the native session without using models, downloads or personal text.
    var translateFixture: ((TranslationRequest) async throws -> TranslationResult)?

    var canTranslate: Bool { !busy && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= Self.textLimit }
    var canSwap: Bool { (detectedSource != nil || !source.isEmpty) && !busy }
    var hasDraft: Bool { !text.isEmpty || busy }
    var status: String {
        if let message { return message }
        if text.count > Self.textLimit { return "Use up to 16,000 characters per translation." }
        if busy { return pairState == .downloadable ? "Language download may be required…" : "Translating…" }
        switch pairState {
        case .installed: return "Languages installed · On-device translation"
        case .downloadable: return "Languages available to download from macOS"
        case .unsupported: return "This language pair is not supported. Choose another language."
        case nil: return "On-device translation · macOS may ask to download languages"
        }
    }
    static func languageName(_ id: String) -> String {
        Locale.current.localizedString(forIdentifier: id) ?? id
    }

    @MainActor func loadCatalog() async {
        guard languages.isEmpty, !loadingCatalog else { return }
        loadingCatalog = true
        defer { loadingCatalog = false }
        do {
            let loaded = try await loadLanguages()
            guard !Task.isCancelled else { return }
            languages = Array(Set(loaded)).sorted { Self.languageName($0).localizedStandardCompare(Self.languageName($1)) == .orderedAscending }
            catalogFailed = languages.isEmpty
        } catch { catalogFailed = true }
    }

    func invalidate() {
        generation = UUID()
        checking?.cancel(); checking = nil
        request = nil; busy = false
        output = ""; detectedSource = nil; pairState = nil; message = nil
    }

    func cancel() { invalidate(); message = "Translation canceled. Your text is still here." }
    func clear() { text = ""; invalidate() }

    @MainActor func start() {
        guard canTranslate else { return }
        invalidate()
        let current = TranslationRequest(text: text, source: source, target: target)
        let token = generation
        busy = true
        checking = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let state = try await self.availability(current)
                guard self.generation == token, !Task.isCancelled else { return }
                self.pairState = state
                guard state != .unsupported else { self.busy = false; return }
                self.request = current
            } catch {
                guard self.generation == token, !Task.isCancelled else { return }
                self.busy = false
                self.message = "Couldn't check these languages. Choose a source language or try again."
            }
        }
    }

    @MainActor func perform(_ current: TranslationRequest, translate: (TranslationRequest) async throws -> TranslationResult) async {
        guard request?.id == current.id else { return }
        do {
            let result = try await translate(current)
            guard request?.id == current.id, !Task.isCancelled else { return }
            output = result.text; detectedSource = result.source
            pairState = .installed; busy = false; request = nil
        } catch {
            guard request?.id == current.id else { return }
            busy = false; request = nil
            // Framework errors can contain input. Never log them or echo raw payloads.
            message = error is CancellationError ? "Translation canceled. Try again when ready." : "Translation couldn't finish. Check language downloads and your connection, then try again."
        }
    }

    func swap() {
        guard canSwap, let newTarget = detectedSource ?? (source.isEmpty ? nil : source) else { return }
        let translated = output.isEmpty ? text : output
        let oldTarget = target
        text = translated; source = oldTarget; target = newTarget
    }

    func copy(using action: (String) -> Void) {
        guard !output.isEmpty, !busy else { return }
        action(output); message = "Translation copied"
    }
}
