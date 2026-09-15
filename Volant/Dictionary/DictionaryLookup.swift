import AppKit
import CoreServices

struct DictionaryEntry: Equatable, Sendable {
    let term: String
    let definition: String
}

enum DictionaryQuery {
    static let limit = 256
    static func term(_ query: String) -> String? {
        let parts = query.trimmingCharacters(in: .whitespacesAndNewlines).split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard parts.first?.lowercased() == "define" else { return nil }
        return parts.count == 2 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }
    static func string(in text: String, range: CFRange) -> String? {
        let count = text.utf16.count
        guard range.location >= 0, range.location <= count, range.length > 0,
              range.length <= count - range.location,
              let valid = Range(NSRange(location: range.location, length: range.length), in: text),
              NSRange(valid, in: text) == NSRange(location: range.location, length: range.length) else { return nil }
        let units = Array(text.utf16)
        let end = range.location + range.length
        guard !(0xDC00...0xDFFF).contains(units[range.location]),
              end == units.count || !(0xDC00...0xDFFF).contains(units[end]) else { return nil }
        return String(text[valid])
    }
    static func url(for term: String) -> URL? {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, term.count <= limit,
              let encoded = term.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")) else { return nil }
        return URL(string: "dict://" + encoded)
    }
}

/// Dictionary Services is synchronous. An actor serializes calls away from the UI executor.
actor NativeDictionaryLookup {
    static let shared = NativeDictionaryLookup()
    func lookup(_ text: String) throws -> DictionaryEntry? {
        try Task.checkCancellation()
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, term.count <= DictionaryQuery.limit else { return nil }
        return autoreleasepool {
            let fullRange = CFRange(location: 0, length: term.utf16.count)
            let detected = DCSGetTermRangeInString(nil, term as CFString, 0)
            // The input is an explicit word/phrase. Never silently define only its first word.
            let range = DictionaryQuery.string(in: term, range: detected) == term ? detected : fullRange
            guard let owned = DCSCopyTextDefinition(nil, term as CFString, range) else { return nil }
            let definition = (owned.takeRetainedValue() as String).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !definition.isEmpty else { return nil }
            return DictionaryEntry(term: term, definition: definition)
        }
    }
}

enum DictionaryApplication {
    @MainActor static func open(_ term: String) async throws {
        guard let url = DictionaryQuery.url(for: term),
              let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Dictionary") else {
            throw CocoaError(.fileNoSuchFile)
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }
}
