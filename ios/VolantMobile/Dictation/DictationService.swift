import AVFoundation
import Foundation
import SwiftUI
import VolantCore

/// Listens for the Volant keyboard. The keyboard opens `volant://dictate` when the microphone is
/// closed, which opens it here in the foreground and starts the request; the owner then returns to
/// the app they were typing in while the app keeps listening in the background. After a dictation
/// the microphone stays open for the owner's chosen time (the orange indicator stays on), so the
/// next request starts from a signal without leaving the keyboard. State goes to the keyboard
/// through `DictationBridge`; nothing is logged or kept once the keyboard has inserted it.
@MainActor
final class DictationService: ObservableObject {
    static let shared = DictationService()

    /// The settings key for how many minutes the microphone stays open after a dictation; 0 closes it at once.
    static let microphoneMinutesKey = "dictationMicrophoneMinutes"
    static let microphoneMinuteChoices = [0, 1, 5, 15]
    /// The longest one dictation may run before it finishes by itself, in case the keyboard went away.
    static let longestDictation: Duration = .seconds(5 * 60)

    @Published private(set) var state = DictationState.idle
    /// Whether the listening screen shows over the app, after the keyboard opened it.
    @Published var showingScreen = false

    private let dictation = PhoneDictation()
    private var observer: DarwinObserver?
    private var closeTask: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?
    private var lastLiveWrite = Date.distantPast
    private var notificationTokens: [NSObjectProtocol] = []
    private var style = DictationStyle.plain
    /// Whether the app was already in the foreground, so a dictation started from the keyboard
    /// inside Volant itself needs no listening screen. Set by the app from its scene phase.
    var sceneIsActive = false
    /// When the keyboard last came on screen, and whether it had Full Access then, for the setup
    /// walkthrough.
    @Published private(set) var keyboardLastShown: (date: Date, fullAccess: Bool)?

    private init() {}

    /// Starts listening for keyboard signals and audio interruptions. Called once at launch.
    func activate() {
        guard observer == nil else { return }
        observer = DarwinObserver([DictationBridge.Signal.start, .stop, .cancel, .consumed, .keyboardReady, .keyboardNeedsFullAccess].map(\.name)) { [weak self] name in
            guard let self else { return }
            switch name {
            case DictationBridge.Signal.start.name: Task { await self.startRequest(fromKeyboardLink: false) }
            case DictationBridge.Signal.stop.name: Task { await self.stop() }
            case DictationBridge.Signal.cancel.name: self.cancel()
            case DictationBridge.Signal.consumed.name: self.clearTranscript()
            case DictationBridge.Signal.keyboardReady.name: self.keyboardLastShown = (Date(), true)
            case DictationBridge.Signal.keyboardNeedsFullAccess.name: self.keyboardLastShown = (Date(), false)
            default: break
            }
        }
        let center = NotificationCenter.default
        notificationTokens = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
                let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
                guard type == .began else { return }
                MainActor.assumeIsolated { self?.interrupted() }
            },
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.interrupted() }
            },
            center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.dictation.isCapturing else { return }
                    self.interrupted()
                }
            },
        ]
        let stored = DictationBridge.readState()
        if stored.isActive || stored.microphoneOpenUntil != nil || !stored.text.isEmpty {
            publish(DictationState(session: stored.session, phase: stored.isActive ? .failed : stored.phase,
                                   text: stored.isActive ? "" : stored.text,
                                   message: stored.isActive ? String(localized: "Volant closed before dictation finished.") : stored.message,
                                   microphoneOpenUntil: nil, updated: Date()))
        } else {
            state = stored
        }
    }

    /// The keyboard opened the app with `volant://dictate`.
    func openedFromKeyboard() {
        showingScreen = !sceneIsActive
        Task { await startRequest(fromKeyboardLink: true) }
    }

    /// Starts the keyboard's latest request. Without an open microphone it can only start from the
    /// keyboard's link, while the app is in the foreground; a signal then gets no answer, and the
    /// keyboard opens the app instead.
    private func startRequest(fromKeyboardLink: Bool) async {
        guard let request = DictationBridge.readRequest(), request.isCurrent() else {
            if fromKeyboardLink { showingScreen = false }
            return
        }
        if state.session == request.session && (state.isActive || state.phase == .done) { return }
        guard fromKeyboardLink || dictation.isMicrophoneOpen else { return }
        closeTask?.cancel()
        dictation.cancel()
        let session = request.session
        style = request.style.flatMap(DictationStyle.init(rawValue:)) ?? .plain
        publish(DictationState(session: session, phase: .preparing, text: "", message: nil, microphoneOpenUntil: nil, updated: Date()))
        do {
            try await dictation.openMicrophone()
            try await dictation.begin(
                vocabulary: MacSettings.dictationVocabulary(),
                removesFillers: KeyboardDictationSettings.removesFillers,
                formatsSpokenText: KeyboardDictationSettings.formatsSpokenText,
                onPreparing: { [weak self] message in self?.update(session) { $0.message = message } },
                onText: { [weak self] text in self?.live(text, session: session) })
            guard state.session == session, state.phase == .preparing else { return }
            update(session) { $0.phase = .listening; $0.message = nil; $0.listeningSince = Date() }
            publishLevels(session)
            watchdog?.cancel()
            watchdog = Task { [weak self] in
                try? await Task.sleep(for: Self.longestDictation)
                guard !Task.isCancelled, let self, self.state.session == session, self.state.phase == .listening else { return }
                await self.stop()
            }
        } catch {
            guard state.session == session else { return }
            update(session) { $0.phase = .failed; $0.message = error.localizedDescription }
            scheduleClose()
        }
    }

    /// Writes the microphone level for the keyboard's waveform about 15 times a second while this
    /// dictation is listening.
    private func publishLevels(_ session: String) {
        levelTask?.cancel()
        levelTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.state.session == session, self.state.phase == .listening else { break }
                DictationLevelFile.write(self.dictation.currentLevel)
                try? await Task.sleep(for: .milliseconds(66))
            }
            DictationLevelFile.write(DictationLevel.floor)
        }
    }

    /// Finishes the current dictation and hands the final text to the keyboard.
    func stop() async {
        guard let session = state.session, state.phase == .listening || state.phase == .preparing else { return }
        watchdog?.cancel()
        update(session) { $0.phase = .finishing }
        let text = await dictation.finish()
        guard state.session == session, state.phase == .finishing else { return }
        let formatted = text.map { style.format($0) } ?? ""
        update(session) { $0.phase = .done; $0.text = formatted }
        scheduleClose()
    }

    /// Ends the current dictation and discards what was heard.
    func cancel() {
        guard let session = state.session, state.isActive else { return }
        watchdog?.cancel()
        dictation.cancel()
        update(session) { $0.phase = .idle; $0.text = "" }
        scheduleClose()
    }

    /// Closes the microphone now, from the listening screen or Settings.
    func closeMicrophone() {
        closeTask?.cancel()
        watchdog?.cancel()
        dictation.closeMicrophone()
        var next = state
        if next.isActive { next.phase = .idle; next.text = "" }
        next.microphoneOpenUntil = nil
        next.updated = Date()
        publish(next)
    }

    /// Whether the microphone is open between dictations.
    var microphoneIsOpen: Bool { dictation.isMicrophoneOpen }

    /// Keeps the microphone open for the chosen time after a dictation, then closes it.
    private func scheduleClose() {
        closeTask?.cancel()
        let minutes = UserDefaults.standard.object(forKey: Self.microphoneMinutesKey) as? Int ?? 5
        guard minutes > 0, dictation.isMicrophoneOpen else { closeMicrophone(); return }
        let until = Date().addingTimeInterval(TimeInterval(minutes * 60))
        var next = state
        next.microphoneOpenUntil = until
        next.updated = Date()
        publish(next)
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled, let self, !self.state.isActive else { return }
            self.closeMicrophone()
        }
    }

    /// A call, Siri or another app took the audio session, or the route changed under the engine.
    private func interrupted() {
        guard dictation.isMicrophoneOpen else { return }
        let wasActive = state.isActive
        closeMicrophone()
        if wasActive, let session = state.session {
            update(session) { $0.phase = .failed; $0.message = String(localized: "Dictation stopped because another app took the microphone.") }
        }
    }

    private func clearTranscript() {
        guard state.phase == .done, !state.text.isEmpty else { return }
        var next = state
        next.text = ""
        next.updated = Date()
        publish(next)
    }

    /// Publishes live text at most a few times a second; the keyboard only previews it.
    private func live(_ text: String, session: String) {
        guard state.session == session, state.phase == .listening || state.phase == .preparing else { return }
        state.text = text
        let now = Date()
        guard now.timeIntervalSince(lastLiveWrite) > 0.2 else { return }
        lastLiveWrite = now
        update(session) { $0.text = text }
    }

    private func update(_ session: String, _ change: (inout DictationState) -> Void) {
        guard state.session == session else { return }
        var next = state
        change(&next)
        next.updated = Date()
        publish(next)
    }

    private func publish(_ next: DictationState) {
        state = next
        DictationBridge.writeState(next)
    }
}
