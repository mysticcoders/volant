import AppKit
import Combine
import SwiftUI
import VolantCore

/// Where a running session shows itself.
enum FocusBarPlacement: String, CaseIterable, Identifiable {
    /// Around the camera notch, on the screen in use when it has one; the floating bar otherwise.
    case notch
    case floating
    case menuBar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notch: return String(localized: "Notch", comment: "Focus placement: around the camera notch on MacBook displays")
        case .floating: return String(localized: "Floating Bar", comment: "Focus placement: a small bar floating over windows")
        case .menuBar: return String(localized: "Menu Bar", comment: "Focus placement: the time as text in the menu bar")
        }
    }

    /// The placement actually used, given the notch of the screen in use: the notch falls back to
    /// the floating bar on screens without one.
    func resolved(hasNotch: Bool) -> FocusBarPlacement {
        self == .notch && !hasNotch ? .floating : self
    }
}

/// The camera notch of a screen, in screen coordinates, from the areas macOS reports on either side
/// of it. Separate from `NSScreen` so the arithmetic can be tested with any numbers.
enum NotchGeometry {
    /// The notch's rectangle, or nil when the screen has none.
    static func notch(frame: NSRect, topInset: CGFloat, left: NSRect?, right: NSRect?) -> NSRect? {
        guard topInset > 0, let left, let right, !left.isEmpty, !right.isEmpty, right.minX > left.maxX else { return nil }
        return NSRect(x: left.maxX, y: frame.maxY - topInset, width: right.minX - left.maxX, height: topInset)
    }

    static func notch(of screen: NSScreen) -> NSRect? {
        notch(frame: screen.frame, topInset: screen.safeAreaInsets.top, left: screen.auxiliaryTopLeftArea, right: screen.auxiliaryTopRightArea)
    }

    /// The screen the owner is working on, the one holding the active menu bar and key window, and its notch.
    static func current() -> (screen: NSScreen, notch: NSRect)? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first, let notch = notch(of: screen) else { return nil }
        return (screen, notch)
    }
}

/// What the notch shows: a collapsed pill, the expanded controls, a reminder, or a brief completion.
final class FocusNotchState: ObservableObject {
    @Published var expanded = false
    @Published var notchWidth: CGFloat = 200
    @Published var notchHeight: CGFloat = 32
}

/// The notch form of the focus bar: a black pill that blends into the camera notch, with the Focus
/// symbol on its left and the time on its right. Hovering expands it downward into the session's
/// controls, and reminders drop out of it. It never activates Volant, joins every Space and
/// full-screen app, and stays within the notch and two narrow wings so menu bar items stay visible.
final class FocusNotchPanel: NSPanel {
    static let wing: CGFloat = 72
    static let expandedWidth: CGFloat = 380
    static let completionShown: TimeInterval = 2.5
    let controller: FocusController
    let state = FocusNotchState()
    private let host: NSHostingView<AnyView>
    private var subscriptions: Set<AnyCancellable> = []
    private var completionHide: DispatchWorkItem?
    private let geometry: () -> (screen: NSScreen, notch: NSRect)?

    init(controller: FocusController, actions: FocusBarActions, snoozeMinutes: @escaping () -> Int,
         geometry: @escaping () -> (screen: NSScreen, notch: NSRect)? = NotchGeometry.current) {
        self.controller = controller
        self.geometry = geometry
        let state = self.state
        host = NSHostingView(rootView: AnyView(ThemedRoot {
            FocusNotchView(controller: controller, state: state, actions: actions, snoozeMinutes: snoozeMinutes)
        }))
        super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 32),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        setAccessibilitySubrole(.floatingWindow)
        setAccessibilityLabel(String(localized: "Focus session", comment: "Accessibility label for the floating focus bar"))
        contentView = host
        controller.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.refresh() } }.store(in: &subscriptions)
        state.$expanded.removeDuplicates().sink { [weak self] _ in DispatchQueue.main.async { self?.refresh() } }.store(in: &subscriptions)
        controller.$completedAt.compactMap { $0 }.sink { [weak self] _ in DispatchQueue.main.async { self?.showCompletion() } }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Whether the notch is where the session shows right now, so the bar, menu bar item and
    /// reminder panel stand aside.
    var isShowingSession: Bool { controller.isRunning && controller.placement.resolved(hasNotch: geometry() != nil) == .notch }

    /// Shows, sizes or hides the panel to match the session, the placement and the screen in use.
    func refresh() {
        let completing = completionHide != nil
        guard (isShowingSession || completing), let (_, notch) = geometry() else {
            if isVisible { orderOut(nil) }
            state.expanded = false
            return
        }
        state.notchWidth = notch.width
        state.notchHeight = notch.height
        let open = state.expanded || controller.reminder != nil
        host.layoutSubtreeIfNeeded()
        let width = open ? max(Self.expandedWidth, notch.width + 2 * Self.wing) : notch.width + 2 * Self.wing
        let height = open ? max(notch.height, host.fittingSize.height) : notch.height
        let frame = NSRect(x: (notch.midX - width / 2).rounded(), y: notch.maxY - height, width: width, height: height)
        guard isVisible else {
            setFrame(frame, display: true)
            orderFrontRegardless()
            return
        }
        guard self.frame != frame else { return }
        resize(to: frame, opening: frame.height > self.frame.height)
    }

    /// Grows the black shape out of the notch, or draws it back in, with the window's frame. The
    /// content keeps its final layout and is revealed by the growing edge. Reduce Motion resizes at once.
    private func resize(to frame: NSRect, opening: Bool) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = opening ? 0.32 : 0.22
            context.timingFunction = opening ? CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
                                             : CAMediaTimingFunction(name: .easeIn)
            context.allowsImplicitAnimation = true
            animator().setFrame(frame, display: true)
        }
    }

    /// Keeps the notch showing a green check for a moment after a session completes.
    private func showCompletion() {
        completionHide?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.completionHide = nil
            self?.refresh()
        }
        completionHide = work
        refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.completionShown, execute: work)
    }
}

/// The notch's content. Collapsed, the notch itself stays empty between the symbol and the time;
/// expanded, the controls or the reminder sit below the notch line on the same black shape.
struct FocusNotchView: View {
    @ObservedObject var controller: FocusController
    @ObservedObject var state: FocusNotchState
    let actions: FocusBarActions
    let snoozeMinutes: () -> Int
    @State private var hoverWork: DispatchWorkItem?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                wingSymbol.frame(width: FocusNotchPanel.wing)
                Spacer(minLength: state.notchWidth)
                Text(wingText)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(completed ? Color.green : Color.white)
                    .frame(width: FocusNotchPanel.wing)
            }
            .frame(height: state.notchHeight)
            if let reminder = controller.reminder {
                FocusNotchReminder(controller: controller, reminder: reminder, snoozeMinutes: snoozeMinutes)
                    .transition(reveal)
            } else if state.expanded, controller.isRunning {
                FocusNotchControls(controller: controller, actions: actions)
                    .transition(reveal)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: open)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(Color.black, in: UnevenRoundedRectangle(bottomLeadingRadius: open ? 18 : 10, bottomTrailingRadius: open ? 18 : 10))
        .environment(\.colorScheme, .dark)
        .onHover(perform: hover)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Focus session, \(controller.timeText(), format: .verbatim)", comment: "Accessibility label for the Focus menu bar item; the value is the time"))
    }

    private var open: Bool { state.expanded || controller.reminder != nil }
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// Controls fade in while sliding down from under the notch, and fade out on the way back.
    private var reveal: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(y: -8)), removal: .opacity)
    }
    private var completed: Bool { !controller.isRunning && controller.completedAt != nil }

    @ViewBuilder private var wingSymbol: some View {
        let paused = controller.session?.isPaused == true
        Image(systemName: completed ? "checkmark.circle.fill" : paused ? "pause.circle.fill" : "target")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(completed ? Color.green : paused ? Color.gray : Color.accentColor)
            .accessibilityHidden(true)
    }

    private var wingText: String {
        if completed { return String(localized: "Done", comment: "Focus notch: shown briefly when a session completes") }
        return controller.timeText()
    }

    /// Expands after the pointer rests on the notch for a moment and collapses soon after it
    /// leaves, so passing over the menu bar doesn't flicker it open.
    private func hover(_ inside: Bool) {
        hoverWork?.cancel()
        let work = DispatchWorkItem { state.expanded = inside }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (inside ? 0.25 : 0.6), execute: work)
    }
}

/// The expanded notch: goal, time and the session's buttons.
struct FocusNotchControls: View {
    @ObservedObject var controller: FocusController
    let actions: FocusBarActions

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(goal).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(controller.session?.isPaused == true
                     ? String(localized: "Paused · \(controller.timeText(), format: .verbatim) left", comment: "Focus bar status while paused; the value is the time left, such as 12:30")
                     : String(localized: "\(controller.timeText(), format: .verbatim) left", comment: "Focus bar status; the value is the time left, such as 12:30"))
                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            FocusSessionButtons(controller: controller, actions: actions)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 12)
    }

    private var goal: String {
        let text = controller.session?.setup.goal ?? ""
        return text.isEmpty ? String(localized: "Focus", comment: "Focus bar title when the session has no goal") : text
    }
}

/// A reminder dropped out of the notch: what was blocked, the goal, Snooze and Back to Work.
struct FocusNotchReminder: View {
    @ObservedObject var controller: FocusController
    let reminder: FocusReminder
    let snoozeMinutes: () -> Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(reminder.name, format: .verbatim) is blocked", comment: "Focus reminder title; the value is an app or website name")
                .font(.system(size: 13, weight: .semibold)).lineLimit(1)
            if !reminder.goal.isEmpty {
                Text(String(localized: "You’re focusing on: \(reminder.goal, format: .verbatim)", comment: "Focus reminder text; the value is the owner's goal"))
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack {
                let minutes = snoozeMinutes()
                Button(String(localized: "Snooze \(minutes, specifier: "%lld") Minutes", comment: "Focus reminder button: allow the blocked app or site for a few minutes")) {
                    controller.snooze(reminder, minutes: minutes)
                }
                Spacer()
                Button(String(localized: "Back to Work", comment: "Focus reminder button: close the reminder")) { controller.dismissReminder() }
            }
            .controlSize(.small)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 12)
    }
}
