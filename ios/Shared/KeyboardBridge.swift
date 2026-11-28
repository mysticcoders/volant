import Foundation
import UIKit

/// What the Volant keyboard and the app exchange to dictate. A keyboard cannot use the microphone,
/// so the app listens for it: the keyboard writes a request, then either signals an app that still
/// has the microphone open or opens `volant://dictate` so the app can open it. The app writes the
/// dictation's state, with the live and then final transcript, and the keyboard inserts the text of
/// the request it made. Signals are Darwin notifications, which carry no data; everything else is in
/// small files in the App Group container. A transcript is cleared once the keyboard has inserted it.
enum DictationBridge {
    /// A signal between the two processes.
    enum Signal: String, CaseIterable {
        /// Keyboard to app: a new request is waiting; start listening if the microphone is open.
        case start
        /// Keyboard to app: stop listening and finish the transcript.
        case stop
        /// Keyboard to app: stop listening and discard what was heard.
        case cancel
        /// Keyboard to app: the final transcript was inserted and can be cleared.
        case consumed
        /// App to keyboard: the dictation state changed.
        case changed
        /// Keyboard to app: the keyboard came on screen with Full Access, for the setup walkthrough.
        case keyboardReady
        /// Keyboard to app: the keyboard came on screen without Full Access. iOS may not deliver this
        /// from a keyboard without Full Access, so the walkthrough treats it as a hint only.
        case keyboardNeedsFullAccess

        var name: String { "com.mysticcoders.volant.dictation.\(rawValue)" }
    }

    static var stateURL: URL? { AppGroup.container?.appendingPathComponent("dictation-state.json") }
    static var requestURL: URL? { AppGroup.container?.appendingPathComponent("dictation-request.json") }

    /// Posts a signal to the other process.
    static func post(_ signal: Signal) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(signal.name as CFString), nil, nil, true)
    }

    /// The state the app last wrote, or idle when there is none.
    static func readState() -> DictationState {
        read(DictationState.self, from: stateURL) ?? .idle
    }

    /// Replaces the state and tells the keyboard.
    static func writeState(_ state: DictationState) {
        write(state, to: stateURL)
        post(.changed)
    }

    /// The request the keyboard last made.
    static func readRequest() -> DictationRequest? {
        read(DictationRequest.self, from: requestURL)
    }

    static func writeRequest(_ request: DictationRequest) {
        write(request, to: requestURL)
    }

    private static func read<T: Decodable>(_ type: T.Type, from url: URL?) -> T? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func write<T: Encodable>(_ value: T, to url: URL?) {
        guard let url, let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

/// The microphone level while the app listens, for the keyboard's waveform: a dBFS value and the
/// time it was written, rewritten in place several times a second. Torn or stale reads are harmless,
/// so there is no locking; a level older than `freshness` reads as silence.
enum DictationLevelFile {
    static var url: URL? { AppGroup.container?.appendingPathComponent("dictation-level") }
    static let freshness: TimeInterval = 0.5
    private static var handle: FileHandle?

    /// Overwrites the level. Called by the app on the main thread.
    static func write(_ decibels: Float, now: Date = Date()) {
        guard let url else { return }
        if handle == nil {
            if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
            handle = try? FileHandle(forWritingTo: url)
        }
        var level = decibels
        var time = now.timeIntervalSinceReferenceDate
        var data = Data(bytes: &level, count: MemoryLayout<Float>.size)
        data.append(Data(bytes: &time, count: MemoryLayout<Double>.size))
        try? handle?.seek(toOffset: 0)
        try? handle?.write(contentsOf: data)
    }

    /// The level as a fraction from 0 (silence) to 1 (loud speech), or 0 when stale or unreadable.
    static func readFraction(now: Date = Date()) -> Double {
        guard let url, let data = try? Data(contentsOf: url), data.count >= 12 else { return 0 }
        let level = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: Float.self) }
        let time = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: Double.self) }
        guard now.timeIntervalSinceReferenceDate - time < freshness, level.isFinite else { return 0 }
        return fraction(decibels: level)
    }

    /// Maps dBFS onto 0...1: the room's hum around -55 is silence and loud speech around -10 fills
    /// the bar; the square root lifts quiet speech so the waveform moves with it.
    static func fraction(decibels: Float) -> Double {
        let linear = min(max((Double(decibels) + 55) / 45, 0), 1)
        return linear.squareRoot()
    }
}

/// One dictation the keyboard asked for, named so the keyboard inserts only its own transcript.
struct DictationRequest: Codable, Equatable {
    var session: String
    var requested: Date
    /// The `DictationStyle` raw value to lay the transcript out in; nil is plain.
    var style: String?

    /// How long a request stays wanted: a transcript finished later than this is never inserted.
    static let lifetime: TimeInterval = 15 * 60

    static func new(style: String? = nil, now: Date = Date()) -> DictationRequest {
        DictationRequest(session: UUID().uuidString, requested: now, style: style)
    }

    func isCurrent(now: Date = Date()) -> Bool {
        now.timeIntervalSince(requested) < Self.lifetime
    }
}

/// The app's side of a dictation, as the keyboard reads it.
struct DictationState: Codable, Equatable {
    enum Phase: String, Codable {
        case idle, preparing, listening, finishing, done, failed
    }

    var session: String?
    var phase: Phase
    /// The transcript so far while listening, and the final text once done.
    var text: String
    /// Why the dictation failed, or what preparing is waiting for, in words for the owner.
    var message: String?
    /// While the app keeps the microphone open after a dictation, the time it will close it. A
    /// keyboard request before then can start without opening the app.
    var microphoneOpenUntil: Date?
    var updated: Date
    /// When listening began, for the keyboard's timer.
    var listeningSince: Date?

    static let idle = DictationState(session: nil, phase: .idle, text: "", message: nil, microphoneOpenUntil: nil, updated: .distantPast, listeningSince: nil)

    var isActive: Bool { phase == .preparing || phase == .listening || phase == .finishing }

    /// Whether the app said it still had the microphone open at this moment.
    func microphoneIsOpen(now: Date = Date()) -> Bool {
        if isActive { return now.timeIntervalSince(updated) < 10 * 60 }
        return (microphoneOpenUntil ?? .distantPast) > now
    }
}

/// Observes Darwin notifications on the main thread for as long as it is alive.
final class DarwinObserver {
    private let handler: (String) -> Void

    init(_ names: [String], handler: @escaping (String) -> Void) {
        self.handler = handler
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        for name in names {
            CFNotificationCenterAddObserver(center, observer, { _, observer, name, _, _ in
                guard let observer, let name else { return }
                let target = Unmanaged<DarwinObserver>.fromOpaque(observer).takeUnretainedValue()
                let value = name.rawValue as String
                Task { @MainActor in target.handler(value) }
            }, name as CFString, nil, .deliverImmediately)
        }
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque())
    }
}

/// The snippets the keyboard offers, copied from the Mac's synced snippets by the app whenever it
/// reads them, since the keyboard cannot read the iCloud key-value store itself.
struct KeyboardSnippet: Codable, Equatable, Identifiable {
    var name: String
    var body: String
    var id: String { name + "\u{1F}" + body }

    static var fileURL: URL? { AppGroup.container?.appendingPathComponent("keyboard-snippets.json") }

    static func readAll() -> [KeyboardSnippet] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([KeyboardSnippet].self, from: data)) ?? []
    }

    /// Writes the list when it differs from the stored one.
    static func writeAll(_ snippets: [KeyboardSnippet]) {
        guard let url = fileURL, snippets != readAll(), let data = try? JSONEncoder().encode(snippets) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

/// What the keyboard last reported about itself, so the app's setup screen can tell whether it is
/// installed with Full Access. Only a keyboard with Full Access can reach the App Group, so a report
/// at all means it has it.
enum KeyboardPresence {
    private static let key = "keyboardLastSeen"

    static var lastSeen: Date? {
        UserDefaults(suiteName: AppGroup.id)?.object(forKey: key) as? Date
    }

    static func markSeen(now: Date = Date()) {
        UserDefaults(suiteName: AppGroup.id)?.set(now, forKey: key)
    }

    /// Forgets the report, once the keyboard is gone from the enabled keyboards, so adding it
    /// again has to show Full Access again.
    static func clear() {
        UserDefaults(suiteName: AppGroup.id)?.removeObject(forKey: key)
    }
}

/// Snippet text with the Mac's placeholders filled in the same way the Mac expands them.
enum SnippetText {
    static func expand(_ body: String, now: Date = Date()) -> String {
        var s = body
        s = s.replacingOccurrences(of: "{date}", with: now.formatted(date: .abbreviated, time: .omitted))
        s = s.replacingOccurrences(of: "{isodate}", with: now.formatted(.iso8601.year().month().day()))
        s = s.replacingOccurrences(of: "{time}", with: now.formatted(date: .omitted, time: .shortened))
        s = s.replacingOccurrences(of: "{datetime}", with: now.formatted(date: .abbreviated, time: .shortened))
        s = s.replacingOccurrences(of: "{uuid}", with: UUID().uuidString)
        if s.contains("{clipboard}") { s = s.replacingOccurrences(of: "{clipboard}", with: UIPasteboard.general.string ?? "") }
        return s
    }
}
