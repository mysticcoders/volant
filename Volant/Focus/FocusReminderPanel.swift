import AppKit
import Combine
import SwiftUI
import VolantCore

/// The reminder shown when a blocked app or site comes forward: what was blocked, the goal, and
/// Snooze or Back to Work. It floats above other windows near the top of the screen under the
/// pointer, never activates Volant, and closes after a while on its own.
final class FocusReminderPanel: NSPanel {
    static let width: CGFloat = 360
    static let lifetime: TimeInterval = 12
    let controller: FocusController
    private let host: NSHostingView<AnyView>
    private var subscription: AnyCancellable?
    private var shownID: UUID?
    private var expiry: DispatchWorkItem?
    /// Whether another surface, the notch, shows reminders right now; the panel then stays hidden
    /// but still closes the reminder after its lifetime.
    var shownElsewhere: () -> Bool = { false }

    init(controller: FocusController, snoozeMinutes: @escaping () -> Int) {
        self.controller = controller
        host = NSHostingView(rootView: AnyView(ThemedRoot { FocusReminderView(controller: controller, snoozeMinutes: snoozeMinutes) }))
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 120),
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
        contentView = host
        subscription = controller.$reminder.sink { [weak self] reminder in
            DispatchQueue.main.async { self?.show(reminder) }
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private func show(_ reminder: FocusReminder?) {
        guard let reminder else {
            expiry?.cancel()
            shownID = nil
            orderOut(nil)
            return
        }
        guard reminder.id != shownID else { return }
        shownID = reminder.id
        scheduleExpiry(for: reminder.id)
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: String(localized: "\(reminder.name, format: .verbatim) is blocked during your focus session.", comment: "VoiceOver announcement when Focus blocks an app or site"),
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
        guard !shownElsewhere() else { return }
        host.layoutSubtreeIfNeeded()
        let size = NSSize(width: Self.width, height: max(100, host.fittingSize.height))
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        setFrame(NSRect(x: (visible.midX - size.width / 2).rounded(), y: (visible.maxY - size.height - 80).rounded(), width: size.width, height: size.height), display: true)
        orderFrontRegardless()
    }

    /// Closes the reminder after its lifetime unless a newer one replaced it.
    private func scheduleExpiry(for id: UUID) {
        expiry?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.controller.reminder?.id == id else { return }
            self.controller.dismissReminder()
        }
        expiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.lifetime, execute: work)
    }
}

/// The reminder's content, on the theme's window background with an accent edge.
struct FocusReminderView: View {
    @ObservedObject var controller: FocusController
    let snoozeMinutes: () -> Int
    @Environment(\.volantTheme) private var theme

    var body: some View {
        if let reminder = controller.reminder {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "target").foregroundStyle(Color.accentColor).accessibilityHidden(true)
                    Text("\(reminder.name, format: .verbatim) is blocked", comment: "Focus reminder title; the value is an app or website name")
                        .font(.headline).lineLimit(1)
                }
                Text(reminder.goal.isEmpty ? String(localized: "You’re in a focus session.", comment: "Focus reminder text when the session has no goal")
                                           : String(localized: "You’re focusing on: \(reminder.goal, format: .verbatim)", comment: "Focus reminder text; the value is the owner's goal"))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    let minutes = snoozeMinutes()
                    Button(String(localized: "Snooze \(minutes, specifier: "%lld") Minutes", comment: "Focus reminder button: allow the blocked app or site for a few minutes")) {
                        controller.snooze(reminder, minutes: minutes)
                    }
                    Spacer()
                    Button(String(localized: "Back to Work", comment: "Focus reminder button: close the reminder")) { controller.dismissReminder() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(14)
            .frame(width: FocusReminderPanel.width, alignment: .leading)
            .background(theme.windowBackground, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1.5))
            .accessibilityElement(children: .contain)
        }
    }
}
