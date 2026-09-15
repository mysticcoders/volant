import Foundation
import Combine

/// Transient lookup state, never stored in history or configuration.
final class DictionaryModel: ObservableObject {
    @Published var input = "" { didSet { if input != oldValue { search() } } }
    @Published private(set) var entry: DictionaryEntry?
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    @Published private(set) var searched = false
    @Published private(set) var failed = false
    private var generation = UUID()
    private var work: Task<Void, Never>?
    var debounce: Duration = .milliseconds(200)
    var lookup: (String) async throws -> DictionaryEntry? = { try await NativeDictionaryLookup.shared.lookup($0) }
    var openApplication: (String) async throws -> Void = { try await DictionaryApplication.open($0) }
    var term: String { input.trimmingCharacters(in: .whitespacesAndNewlines) }
    var canLookup: Bool { !term.isEmpty && term.count <= DictionaryQuery.limit }

    func search(immediate: Bool = false) {
        generation = UUID(); work?.cancel(); work = nil
        entry = nil; message = nil; searched = false; failed = false; busy = false
        guard canLookup else { return }
        let token = generation, text = term, delay = immediate ? Duration.zero : debounce
        let provider = lookup
        busy = true
        work = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
                let result = try await provider(text)
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.entry = result; self.busy = false; self.searched = true
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.busy = false; self.searched = true; self.failed = true
                self.message = "Dictionary lookup couldn't finish. Try again or open Dictionary."
            }
        }
    }
    func clear() {
        input = ""
        generation = UUID(); work?.cancel(); work = nil
        entry = nil; message = nil; busy = false; searched = false; failed = false
    }
    func copy(using action: (String) -> Void) {
        guard let entry, !busy else { return }
        action(entry.definition); message = "Definition copied"
    }
    func open() {
        guard canLookup else { return }
        message = nil
        let token = generation, text = term, open = openApplication
        Task { @MainActor [weak self] in
            do { try await open(text) }
            catch {
                guard let self, self.generation == token else { return }
                self.message = "Couldn't open Dictionary. Check that the app is installed, then try again."
            }
        }
    }
    deinit { work?.cancel() }
}
