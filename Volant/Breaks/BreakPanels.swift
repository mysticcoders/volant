import AppKit
import Combine
import SwiftUI
import VolantCore

/// The small notice in the top corner of the screen under the pointer: the heads-up before a
/// break, and for Gentle breaks the reminder and countdown. It floats on every Space, never
/// activates Volant, and becomes key only when the owner clicks it.
final class BreakNoticePanel: NSPanel {
    static let width: CGFloat = 340
    private let host: NSHostingView<AnyView>

    init(controller: BreakController) {
        host = NSHostingView(rootView: AnyView(ThemedRoot { BreakNoticeView(controller: controller) }))
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 100),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        setAccessibilitySubrole(.floatingWindow)
        setAccessibilityLabel(String(localized: "Break", comment: "Accessibility label for the break notice and overlay windows"))
        contentView = host
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Sizes the panel to its content and shows it in the top corner of the screen under the pointer.
    func present() {
        host.layoutSubtreeIfNeeded()
        let size = NSSize(width: Self.width, height: max(60, host.fittingSize.height))
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        setFrame(NSRect(x: (visible.maxX - size.width - 16).rounded(), y: (visible.maxY - size.height - 16).rounded(), width: size.width, height: size.height), display: true)
        if !isVisible { orderFrontRegardless() }
    }
}

/// One display's full-screen break. It joins every Space and sits above full-screen apps, but it
/// is an ordinary window of this process: if Volant quits or crashes it disappears, and its own
/// watchdog closes it shortly after the break's end time even if nothing else does.
final class BreakOverlayWindow: NSPanel {
    /// How long after the break's end the watchdog removes a window nothing else removed.
    static let watchdogSlack: TimeInterval = 3
    let hold: BreakHold
    private let strict: Bool
    private weak var controller: BreakController?
    private var watchdog: DispatchWorkItem?

    init(controller: BreakController, screen: NSScreen, strict: Bool) {
        self.strict = strict
        self.controller = controller
        hold = BreakHold { [weak controller] in controller?.skip() }
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        setAccessibilityLabel(String(localized: "Break", comment: "Accessibility label for the break notice and overlay windows"))
        contentView = NSHostingView(rootView: ThemedRoot { BreakOverlayView(controller: controller, hold: self.hold, strict: strict) })
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Removes the window at `end` plus a little slack, whatever happens to the controller's timer.
    func arm(until end: Date) {
        watchdog?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.orderOut(nil) }
        watchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, end.timeIntervalSinceNow) + Self.watchdogSlack, execute: work)
    }

    /// Holding Return holds Skip on a Strict break once Skip is available; letting go cancels.
    override func keyDown(with event: NSEvent) {
        guard strict, event.keyCode == 36 || event.keyCode == 76 else { return super.keyDown(with: event) }
        guard !event.isARepeat, let controller, let start = controller.schedule.breakStartedAt,
              controller.now.timeIntervalSince(start) >= BreakOverlayView.strictSkipDelay else { return }
        hold.begin()
    }

    override func keyUp(with event: NSEvent) {
        guard strict, event.keyCode == 36 || event.keyCode == 76 else { return super.keyUp(with: event) }
        hold.cancel()
    }

    override func orderOut(_ sender: Any?) {
        watchdog?.cancel()
        hold.cancel()
        super.orderOut(sender)
    }
}

/// Shows what the Break schedule calls for: the notice panel for the heads-up and Gentle breaks,
/// and an overlay on every display for Standard and Strict breaks. VoiceOver hears when a break is
/// a minute away and when one starts.
final class BreakPresenter {
    let controller: BreakController
    private(set) lazy var notice = BreakNoticePanel(controller: controller)
    private(set) var overlays: [BreakOverlayWindow] = []
    private var subscription: AnyCancellable?
    private var screenObserver: NSObjectProtocol?
    private var shown: BreakSchedule.Phase = .working
    private var overlayStrict: Bool?
    private var overlayEnd: Date?

    init(controller: BreakController) {
        self.controller = controller
        subscription = controller.$schedule.combineLatest(controller.$preferences).sink { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, !self.overlays.isEmpty else { return }
            self.removeOverlays()
            self.refresh()
        }
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    /// Matches the windows to the schedule's phase and the strictness.
    func refresh() {
        let schedule = controller.schedule
        let strictness = controller.preferences.strictness
        let covered = schedule.isOnBreak && strictness.coversScreen
        let noticed = schedule.phase == .headsUp || (strictness == .gentle && (schedule.phase == .reminding || schedule.isOnBreak))
        if covered { showOverlays(strict: strictness == .strict, until: schedule.breakEndsAt) } else { removeOverlays() }
        if noticed { notice.present() } else if notice.isVisible { notice.orderOut(nil) }
        if schedule.phase != shown {
            announce(schedule.phase)
            shown = schedule.phase
        }
    }

    /// Ends everything on screen, as when the app quits.
    func close() {
        removeOverlays()
        notice.orderOut(nil)
    }

    /// Covers every display for the break ending at `end`. Windows already showing this break are
    /// left alone, so one its watchdog removed doesn't come back.
    private func showOverlays(strict: Bool, until end: Date?) {
        if overlayStrict != strict || overlayEnd != end { removeOverlays() }
        if overlays.isEmpty {
            overlayStrict = strict
            overlayEnd = end
            overlays = NSScreen.screens.map { BreakOverlayWindow(controller: controller, screen: $0, strict: strict) }
            for window in overlays { window.orderFrontRegardless() }
            let pointer = overlays.first { $0.frame.contains(NSEvent.mouseLocation) } ?? overlays.first
            pointer?.makeKey()
            if let end { overlays.forEach { $0.arm(until: end) } }
        }
    }

    private func removeOverlays() {
        overlays.forEach { $0.orderOut(nil) }
        overlays = []
        overlayStrict = nil
        overlayEnd = nil
    }

    private func announce(_ phase: BreakSchedule.Phase) {
        let text: String
        switch phase {
        case .headsUp: text = BreakCopy.headsUp
        case .onBreak, .reminding: text = BreakCopy.title
        default: return
        }
        let element: Any = overlays.first ?? notice
        NSAccessibility.post(element: element, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}
