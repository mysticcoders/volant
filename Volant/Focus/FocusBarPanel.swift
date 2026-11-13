import AppKit
import Combine
import SwiftUI
import VolantCore

/// What the focus bar and its menu-bar form can ask the app to do beyond the controller itself.
/// The app sets these after creating the bar, so the bar can point back at itself.
final class FocusBarActions {
    var edit: () -> Void = {}
    var resetPosition: () -> Void = {}
}

/// The small floating bar that shows the goal and the time left while a session runs. It never
/// activates Volant and becomes key only for its menu, so the owner keeps typing where they were. It can be
/// dragged anywhere; the position is remembered and clamped back on screen after display changes.
/// It shows only while the placement resolves to the floating bar: the notch and menu bar item take
/// over otherwise.
final class FocusBarPanel: NSPanel, NSWindowDelegate {
    static let positionKey = "focusBarPosition"
    static let width: CGFloat = 300
    let controller: FocusController
    private let positions: UserDefaults
    private let host: NSHostingView<AnyView>
    private var subscription: AnyCancellable?
    private var restoringPosition = false

    init(controller: FocusController, actions: FocusBarActions, positions: UserDefaults = .standard) {
        self.controller = controller
        self.positions = positions
        host = NSHostingView(rootView: AnyView(ThemedRoot { FocusBarView(controller: controller, actions: actions) }))
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 44),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .utilityWindow
        setAccessibilitySubrole(.floatingWindow)
        setAccessibilityLabel(String(localized: "Focus session", comment: "Accessibility label for the floating focus bar"))
        contentView = host
        delegate = self
        subscription = controller.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Shows the bar while a session runs with the floating placement, or the notch placement on a
    /// screen without a notch, and hides it otherwise.
    func refresh() {
        guard controller.isRunning, controller.placement.resolved(hasNotch: NotchGeometry.current() != nil) == .floating else {
            if isVisible { orderOut(nil) }
            return
        }
        host.layoutSubtreeIfNeeded()
        let size = NSSize(width: Self.width, height: max(40, host.fittingSize.height))
        if !isVisible {
            setContentSize(size)
            restorePosition()
            orderFrontRegardless()
        } else if frame.size != size {
            setFrame(NSRect(origin: NSPoint(x: frame.minX, y: frame.maxY - size.height), size: size), display: true)
        }
    }

    /// Forgets the dragged position and puts the bar back at the top center of the screen.
    func resetPosition() {
        positions.removeObject(forKey: Self.positionKey)
        restorePosition()
    }

    func windowDidMove(_ notification: Notification) {
        guard isVisible, !restoringPosition else { return }
        positions.set(["x": frame.origin.x, "y": frame.origin.y], forKey: Self.positionKey)
    }

    /// The saved position, clamped to the screen it mostly overlaps, or the top center of the
    /// screen under the pointer.
    private func restorePosition() {
        restoringPosition = true
        defer { restoringPosition = false }
        let screens = NSScreen.screens.map(\.visibleFrame)
        let fallback = screens.first { $0.contains(NSEvent.mouseLocation) } ?? NSScreen.main?.visibleFrame
        guard let fallback else { return }
        if let saved = positions.dictionary(forKey: Self.positionKey),
           let x = saved["x"] as? Double, let y = saved["y"] as? Double, x.isFinite, y.isFinite {
            let proposed = NSRect(origin: NSPoint(x: x, y: y), size: frame.size)
            let screen = screens.max {
                $0.intersection(proposed).width * $0.intersection(proposed).height < $1.intersection(proposed).width * $1.intersection(proposed).height
            }.flatMap { $0.intersects(proposed) ? $0 : nil } ?? fallback
            setFrameOrigin(NSPoint(x: min(max(x, screen.minX), max(screen.minX, screen.maxX - frame.width)),
                                   y: min(max(y, screen.minY), max(screen.minY, screen.maxY - frame.height))))
        } else {
            setFrameOrigin(NSPoint(x: (fallback.midX - frame.width / 2).rounded(), y: (fallback.maxY - frame.height - 12).rounded()))
        }
    }
}

/// The bar's content: the goal, the time left, Pause or Resume, Complete, and a menu.
struct FocusBarView: View {
    @ObservedObject var controller: FocusController
    let actions: FocusBarActions
    @Environment(\.volantTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: controller.session?.isPaused == true ? "pause.circle.fill" : "target")
                .foregroundStyle(controller.session?.isPaused == true ? Color.secondary : Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(goal).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(status).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            FocusSessionButtons(controller: controller, actions: actions)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(width: FocusBarPanel.width)
        .background(theme.windowBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.separator(0.12)))
        .accessibilityElement(children: .contain)
    }

    private var goal: String {
        let text = controller.session?.setup.goal ?? ""
        return text.isEmpty ? String(localized: "Focus", comment: "Focus bar title when the session has no goal") : text
    }

    private var status: String {
        let time = controller.timeText()
        if controller.session?.isPaused == true { return String(localized: "Paused · \(time, format: .verbatim) left", comment: "Focus bar status while paused; the value is the time left, such as 12:30") }
        if controller.session?.setup.minutes == nil { return String(localized: "\(time, format: .verbatim) so far", comment: "Focus bar status for a session without a time limit; the value is the time spent, such as 12:30") }
        return String(localized: "\(time, format: .verbatim) left", comment: "Focus bar status; the value is the time left, such as 12:30")
    }
}

/// Pause or Resume, Complete, and the menu, shared by the bar and the menu bar popover.
struct FocusSessionButtons: View {
    @ObservedObject var controller: FocusController
    let actions: FocusBarActions

    var body: some View {
        HStack(spacing: 4) {
            if controller.session?.isPaused == true {
                iconButton("play.fill", String(localized: "Resume", comment: "Focus button")) { controller.resume() }
            } else {
                iconButton("pause.fill", String(localized: "Pause", comment: "Focus button")) { controller.pause() }
            }
            iconButton("checkmark", String(localized: "Complete", comment: "Focus button: finish the session as done")) { controller.complete() }
            Menu {
                Button(String(localized: "Edit Session…", comment: "Focus menu item")) { actions.edit() }
                Picker(String(localized: "Show In", comment: "Focus menu: where the session shows (notch, floating bar or menu bar)"), selection: $controller.placement) {
                    ForEach(FocusBarPlacement.allCases) { Text($0.title).tag($0) }
                }
                Button(String(localized: "Reset Position", comment: "Focus menu item: put the floating bar back in its default place")) { actions.resetPosition() }
                .disabled(controller.placement != .floating)
                Divider()
                Button(String(localized: "End Session", comment: "Focus menu item: stop without completing"), role: .destructive) { controller.end() }
            } label: {
                Image(systemName: "ellipsis").frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel(String(localized: "Focus options", comment: "Accessibility label for the focus bar menu"))
        }
    }

    private func iconButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 22, height: 22).contentShape(Rectangle()) }
            .buttonStyle(.borderless)
            .help(label)
            .accessibilityLabel(label)
    }
}
