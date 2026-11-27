import SwiftUI
import UIKit
import VolantCore

/// The Volant keyboard: a large dictation button, snippets from the Mac, and space, delete, return
/// and the globe key. Regular typing stays on the Apple keyboard. The keyboard cannot use the
/// microphone, so dictation runs in the Volant app (see `DictationBridge`), and this controller
/// only asks for it, follows its state, and types the result.
final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()
    private var heightConstraint: NSLayoutConstraint?

    static let height: CGFloat = 262

    override func viewDidLoad() {
        super.viewDidLoad()
        model.controller = self
        let host = UIHostingController(rootView: KeyboardView(model: model, inputController: self))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        let height = view.heightAnchor.constraint(equalToConstant: Self.height)
        height.priority = .defaultHigh
        height.isActive = true
        heightConstraint = height
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.appeared()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        model.becameVisible()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        model.disappeared()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        model.needsGlobe = needsInputModeSwitchKey
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        model.returnTitle = Self.returnTitle(for: textDocumentProxy.returnKeyType)
    }

    /// Types text at the cursor, with a space before it when it would otherwise run into a word.
    func insertDictation(_ text: String) {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let needsSpace = before.last.map { !$0.isWhitespace && !"([{\"'“‘".contains($0) } ?? false
        textDocumentProxy.insertText(needsSpace ? " " + text : text)
    }

    func insert(_ text: String) { textDocumentProxy.insertText(text) }

    func deleteBackward() { textDocumentProxy.deleteBackward() }

    /// Deletes back to the start of the word before the cursor, with the spaces after it, as the
    /// system keyboard does once delete is held. With nothing readable before the cursor it
    /// deletes one character.
    func deleteWordBackward() {
        let before = Array(textDocumentProxy.documentContextBeforeInput ?? "")
        var end = before.count
        while end > 0, before[end - 1].isWhitespace { end -= 1 }
        while end > 0, !before[end - 1].isWhitespace { end -= 1 }
        for _ in 0..<max(1, before.count - end) { textDocumentProxy.deleteBackward() }
    }

    /// Opens `volant://dictate` in the Volant app. Keyboards have no `openURL`, so this walks the
    /// responder chain to the extension's application object and calls its open method by
    /// selector, the route iOS allows a keyboard with Full Access. Returns false when there is none.
    func openVolant() -> Bool {
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication, application.responds(to: selector) {
                typealias Open = @convention(c) (NSObject, Selector, NSURL, NSDictionary, (@convention(block) (Bool) -> Void)?) -> Void
                let open = unsafeBitCast(application.method(for: selector), to: Open.self)
                open(application, selector, DeepLink.dictate.url as NSURL, NSDictionary(), nil)
                return true
            }
            responder = current.next
        }
        return false
    }

    /// The return key's label for the field's return key type; nil shows the return arrow.
    static func returnTitle(for type: UIReturnKeyType?) -> String? {
        switch type ?? .default {
        case .go: String(localized: "go")
        case .google, .yahoo, .search: String(localized: "search")
        case .join: String(localized: "join")
        case .next: String(localized: "next")
        case .route: String(localized: "route")
        case .send: String(localized: "send")
        case .done: String(localized: "done")
        case .continue: String(localized: "continue")
        default: nil
        }
    }
}

/// The keyboard's state: what the app reports about the dictation, the snippets to offer, and the
/// request this keyboard made, so it inserts only its own transcript, once.
@MainActor
final class KeyboardModel: ObservableObject {
    @Published var state = DictationState.idle
    @Published var snippets: [KeyboardSnippet] = []
    @Published var hasFullAccess = false
    @Published var needsGlobe = true
    @Published var returnTitle: String?
    @Published var starting = false
    @Published var notice: String?
    /// The style the next dictation is laid out in, remembered across keyboards and apps.
    @Published var style: DictationStyle = KeyboardModel.savedStyle {
        didSet { UserDefaults(suiteName: AppGroup.id)?.set(style.rawValue, forKey: Self.styleKey) }
    }

    /// Recent microphone levels from 0 to 1, oldest first, for the waveform while listening.
    @Published var levels = Array(repeating: 0.0, count: KeyboardModel.levelCount)
    /// A dictation recorded in the keyboard itself, when Record in Keyboard works.
    @Published private(set) var local: LocalPhase?
    @Published private(set) var localSince: Date?

    enum LocalPhase: Equatable {
        case starting
        case listening(String)
        case finishing
    }

    private let microphone = WebMicrophone()
    private let transcription = SpeechTranscription()
    private var log: KeyboardDictationLog.Entry?

    weak var controller: KeyboardViewController?
    private var meter: Task<Void, Never>?
    private var request: DictationRequest?
    private var observer: DarwinObserver?
    private var fallback: Task<Void, Never>?
    private var visible = false

    static let levelCount = 40
    private static let insertedKey = "keyboardInsertedSession"
    private static let styleKey = "keyboardDictationStyle"

    private static var savedStyle: DictationStyle {
        UserDefaults(suiteName: AppGroup.id)?.string(forKey: styleKey).flatMap(DictationStyle.init(rawValue:)) ?? .plain
    }
    /// How long a signal to an app that said its microphone was open waits for an answer before
    /// the keyboard opens the app instead.
    static let signalTimeout: Duration = .milliseconds(800)

    /// Whether the app's current dictation is the one this keyboard asked for.
    var isMine: Bool {
        guard let session = state.session, let request else { return false }
        return session == request.session && request.isCurrent()
    }

    var isListening: Bool { isMine && state.isActive }

    /// Reads the state before the keyboard shows. Nothing is typed until `becameVisible`, since the
    /// text proxy may not be connected yet.
    func appeared() {
        hasFullAccess = controller?.hasFullAccess ?? false
        returnTitle = KeyboardViewController.returnTitle(for: controller?.textDocumentProxy.returnKeyType)
        notice = nil
        guard hasFullAccess else { return }
        KeyboardPresence.markSeen()
        snippets = KeyboardSnippet.readAll()
        reload()
    }

    /// Starts following the app's state and types a transcript that finished while away. Only a
    /// keyboard on screen listens: iOS keeps the extension process, and an earlier controller, alive
    /// across the switch to Volant, and that controller's text proxy no longer reaches any field.
    func becameVisible() {
        visible = true
        guard hasFullAccess else {
            DictationBridge.post(.keyboardNeedsFullAccess)
            return
        }
        DictationBridge.post(.keyboardReady)
        if local == nil { KeyboardDictationLog.closeAbandoned() }
        if KeyboardDictationSettings.recordsInKeyboard, let view = controller?.view { microphone.attach(to: view) }
        if observer == nil {
            observer = DarwinObserver([DictationBridge.Signal.changed.name]) { [weak self] _ in self?.reload() }
        }
        reload()
    }

    func disappeared() {
        cancelLocal(outcome: String(localized: "the keyboard closed"))
        visible = false
        observer = nil
        updateMeter()
        fallback?.cancel()
        starting = false
    }

    /// Reads the app's state and types a finished transcript this keyboard asked for.
    func reload() {
        state = DictationBridge.readState()
        request = DictationBridge.readRequest()
        if isMine, state.phase != .idle { starting = false }
        updateMeter()
        deliverIfReady()
    }

    /// Samples the app's microphone level about 16 times a second while this keyboard is on screen
    /// and its dictation is listening, and clears the waveform otherwise.
    private func updateMeter() {
        let recordingHere: Bool = { if case .listening = local { return true }; return false }()
        let wanted = visible && (recordingHere || (isMine && state.phase == .listening))
        guard wanted != (meter != nil) else { return }
        meter?.cancel()
        meter = nil
        levels = Array(repeating: 0, count: Self.levelCount)
        guard wanted else { return }
        meter = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let level = self.local != nil
                    ? DictationLevelFile.fraction(decibels: self.transcription.gate.currentLevel)
                    : DictationLevelFile.readFraction()
                self.levels.removeFirst()
                self.levels.append(level)
                self.saveLog(every: 2)
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }

    /// Starts a dictation, unless one this keyboard asked for is already running.
    func dictate() {
        guard hasFullAccess, !isListening, local == nil else { return }
        if KeyboardDictationSettings.recordsInKeyboard {
            Task { await startLocal() }
        } else {
            start()
        }
    }

    func finish() {
        if case .listening = local {
            Task { await finishLocal() }
            return
        }
        guard isListening else { return }
        DictationBridge.post(.stop)
    }

    func cancel() {
        if local != nil { cancelLocal(outcome: String(localized: "cancelled")); return }
        fallback?.cancel()
        DictationBridge.post(.cancel)
        starting = false
    }

    func insertSnippet(_ snippet: KeyboardSnippet) {
        controller?.insert(SnippetText.expand(snippet.body))
    }

    /// Records in the keyboard through the web microphone. The transcription starts first so no
    /// words are lost while the analyzer sets up; any failure falls back to dictating in the app,
    /// and the outcome is noted for Settings.
    private func startLocal() async {
        local = .starting
        notice = nil
        transcription.vocabulary = KeyboardDictationSettings.readVocabulary()
        transcription.removesFillers = KeyboardDictationSettings.removesFillers
        transcription.formatsSpokenText = KeyboardDictationSettings.formatsSpokenText
        transcription.cleansUpWithAppleIntelligence = KeyboardDictationSettings.cleansUpWithAppleIntelligence
        transcription.downloadsModel = false
        let gate = transcription.gate
        microphone.onBuffer = { [weak self] buffer in
            gate.receive(buffer)
            self?.log?.chunks += 1
        }
        microphone.onStop = { [weak self] in
            guard let self, case .listening = self.local else { return }
            Task { await self.finishLocal(stoppedByPage: true) }
        }
        do {
            if let view = controller?.view { microphone.attach(to: view) }
            try await transcription.begin(inputFormat: WebMicrophone.format) { [weak self] text in
                guard let self, case .listening = self.local else { return }
                self.local = .listening(text)
                if var entry = self.log {
                    entry.characters = max(entry.characters, text.count)
                    self.log = entry
                }
            }
            guard local == .starting else { transcription.cancel(); return }
            try await microphone.start()
            guard local == .starting else { microphone.stop(); transcription.cancel(); return }
            local = .listening("")
            localSince = Date()
            log = KeyboardDictationLog.Entry(started: Date(), updated: Date(), chunks: 0, characters: 0, outcome: nil)
            saveLog()
            Self.noteRecordResult(nil)
            updateMeter()
        } catch {
            microphone.stop()
            transcription.cancel()
            let wasStarting = local == .starting
            local = nil
            Self.noteRecordResult(error.localizedDescription)
            if wasStarting { start() }
        }
    }

    /// Ends the in-keyboard dictation and types its transcript in the chosen style.
    private func finishLocal(stoppedByPage: Bool = false) async {
        guard case .listening = local else { return }
        local = .finishing
        let text = await transcription.finish()
        microphone.stop()
        local = nil
        localSince = nil
        updateMeter()
        let ending = stoppedByPage ? String(localized: "the microphone stopped by itself") : String(localized: "finished")
        endLog(text.map { String(localized: "\(ending), typed \($0.count) characters") }
               ?? String(localized: "\(ending), nothing was recognized"))
        if let text {
            let formatted = style.format(text)
            if !formatted.isEmpty { controller?.insertDictation(formatted) }
        }
    }

    private func cancelLocal(outcome: String) {
        guard local != nil else { return }
        endLog(outcome)
        microphone.stop()
        transcription.cancel()
        local = nil
        localSince = nil
        updateMeter()
    }

    /// Saves the running dictation's counts, at most once every `seconds`, so a keyboard iOS closes
    /// mid-dictation leaves a recent record behind.
    private func saveLog(every seconds: TimeInterval = 0) {
        guard var entry = log, Date().timeIntervalSince(entry.updated) >= seconds else { return }
        entry.updated = Date()
        log = entry
        KeyboardDictationLog.write(entry)
    }

    private func endLog(_ outcome: String) {
        guard var entry = log else { return }
        entry.updated = Date()
        entry.outcome = outcome
        KeyboardDictationLog.write(entry)
        log = nil
    }

    /// Notes whether the last in-keyboard recording started, with the reason when it did not.
    private static func noteRecordResult(_ failure: String?) {
        let result: [String: Any] = ["date": Date(), "ok": failure == nil, "reason": failure ?? ""]
        KeyboardDictationSettings.defaults?.set(result, forKey: KeyboardDictationSettings.recordResultKey)
    }

    /// Makes a new request. An app that says its microphone is open is signaled; one that does not
    /// answer in time, or a closed microphone, means opening the app.
    private func start() {
        notice = nil
        let request = DictationRequest.new(style: style.rawValue)
        DictationBridge.writeRequest(request)
        self.request = request
        starting = true
        fallback?.cancel()
        guard state.microphoneIsOpen() else { openApp(); return }
        DictationBridge.post(.start)
        fallback = Task { [weak self] in
            try? await Task.sleep(for: Self.signalTimeout)
            guard !Task.isCancelled, let self else { return }
            self.state = DictationBridge.readState()
            if self.state.session != request.session { self.openApp() }
        }
    }

    private func openApp() {
        guard controller?.openVolant() == true else {
            starting = false
            notice = String(localized: "Volant could not be opened. Open it once, then try again.")
            return
        }
    }

    private func deliverIfReady() {
        guard visible, controller?.view.window != nil, isMine, state.phase == .done, !state.text.isEmpty, let session = state.session else { return }
        let defaults = UserDefaults(suiteName: AppGroup.id)
        guard defaults?.string(forKey: Self.insertedKey) != session else { return }
        defaults?.set(session, forKey: Self.insertedKey)
        controller?.insertDictation(state.text)
        DictationBridge.post(.consumed)
    }
}
