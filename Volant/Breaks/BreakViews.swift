import SwiftUI
import VolantCore

/// The words and suggestions breaks share between the notice panel and the overlay.
enum BreakCopy {
    static var title: String { String(localized: "Time for a Break", comment: "Breaks title when a break is due or running") }
    static var headsUp: String { String(localized: "Break in 1 minute", comment: "Breaks heads-up notice shown a minute before a break") }
    static var skip: String { String(localized: "Skip", comment: "Breaks button: skip this break") }
    static var holdToSkip: String { String(localized: "Hold to Skip", comment: "Strict break button: press and hold to skip the break") }
    static var endBreak: String { String(localized: "End Break", comment: "Breaks button: end the running break early") }
    static var startBreak: String { String(localized: "Start Break", comment: "Gentle break reminder button: start the break now") }

    static var postpone: String {
        String(localized: "Postpone \(BreakPreferences.postponeMinutes, specifier: "%lld") Minutes", comment: "Breaks button: move the break a few minutes later")
    }

    /// A short suggestion for what to do during a break, chosen by when it started so it stays
    /// the same for the whole break.
    static func suggestion(for start: Date?) -> String {
        let suggestions = [
            String(localized: "Look 20 feet away. Stand up and stretch.", comment: "Break suggestion"),
            String(localized: "Roll your shoulders and take a few slow breaths.", comment: "Break suggestion"),
            String(localized: "Get a glass of water and rest your eyes.", comment: "Break suggestion")
        ]
        let seed = Int(start?.timeIntervalSince1970 ?? 0) / 60
        return suggestions[abs(seed) % suggestions.count]
    }
}

/// The small panel's content: the heads-up a minute before a break, the Gentle reminder when one
/// is due, and the Gentle countdown while it runs.
struct BreakNoticeView: View {
    @ObservedObject var controller: BreakController
    @Environment(\.volantTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "figure.walk").foregroundStyle(Color.accentColor).accessibilityHidden(true)
                Text(verbatim: title).font(.headline).lineLimit(1)
                Spacer(minLength: 0)
                if let remaining = controller.schedule.breakRemaining(at: controller.now) {
                    Text(verbatim: BreakController.clockText(remaining)).font(.headline.monospacedDigit()).foregroundStyle(.secondary)
                        .accessibilityLabel(Text(verbatim: controller.statusText()))
                }
            }
            if controller.schedule.phase != .headsUp {
                Text(verbatim: BreakCopy.suggestion(for: controller.schedule.breakStartedAt ?? controller.schedule.cycleStart))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                switch controller.schedule.phase {
                case .onBreak:
                    Spacer()
                    Button(BreakCopy.endBreak) { controller.endBreak() }
                case .reminding:
                    Button(BreakCopy.postpone) { controller.postpone() }
                    Button(BreakCopy.skip) { controller.skip() }
                    Spacer()
                    Button(BreakCopy.startBreak) { controller.takeBreakNow() }.keyboardShortcut(.defaultAction)
                default:
                    Button(BreakCopy.postpone) { controller.postpone() }
                    Spacer()
                    Button(BreakCopy.skip) { controller.skip() }
                }
            }
        }
        .padding(14)
        .frame(width: BreakNoticePanel.width, alignment: .leading)
        .background(theme.windowBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1.5))
        .accessibilityElement(children: .contain)
    }

    private var title: String {
        switch controller.schedule.phase {
        case .headsUp: return BreakCopy.headsUp
        case .onBreak: return String(localized: "On a Break", comment: "Gentle break panel title while a break runs")
        default: return BreakCopy.title
        }
    }
}

/// Tracks a press-and-hold on the Strict break's Skip, by pointer or by holding Return, and
/// skips once it has been held long enough. Letting go early cancels it.
final class BreakHold: ObservableObject {
    static let duration: TimeInterval = 3
    @Published private(set) var progress: Double = 0
    private var startedAt: Date?
    private var timer: Timer?
    private let completed: () -> Void

    init(completed: @escaping () -> Void) {
        self.completed = completed
    }

    deinit { timer?.invalidate() }

    var isHolding: Bool { startedAt != nil }

    /// Starts the hold; a second call while holding changes nothing.
    func begin() {
        guard startedAt == nil else { return }
        startedAt = Date()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.advance() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Lets go before the hold completed.
    func cancel() {
        timer?.invalidate()
        timer = nil
        startedAt = nil
        progress = 0
    }

    private func advance() {
        guard let startedAt else { return }
        progress = min(1, Date().timeIntervalSince(startedAt) / Self.duration)
        if progress >= 1 {
            cancel()
            completed()
        }
    }
}

/// The full-screen break on one display: the theme's background, dimmed content behind it, the
/// countdown, a suggestion, and Postpone and Skip. Strict breaks hide Postpone, and Skip works
/// only after a short delay and a three-second hold.
struct BreakOverlayView: View {
    /// Buttons ignore presses this soon after a break starts, so keys already in flight don't skip it.
    static let grace: TimeInterval = 1
    /// How long a Strict break runs before Skip can be held.
    static let strictSkipDelay: TimeInterval = 10

    @ObservedObject var controller: BreakController
    @ObservedObject var hold: BreakHold
    let strict: Bool
    @Environment(\.volantTheme) private var theme

    var body: some View {
        let elapsed = controller.schedule.breakStartedAt.map { controller.now.timeIntervalSince($0) } ?? 0
        ZStack {
            theme.windowBackground.opacity(0.94).ignoresSafeArea()
            VStack(spacing: 22) {
                Image(systemName: "figure.walk").font(.system(size: 56, weight: .light)).foregroundStyle(Color.accentColor).accessibilityHidden(true)
                Text(verbatim: BreakCopy.title).font(.system(size: 34, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: BreakController.clockText(controller.schedule.breakRemaining(at: controller.now) ?? 0))
                    .font(.system(size: 64, weight: .medium).monospacedDigit())
                    .accessibilityLabel(Text(verbatim: controller.statusText()))
                Text(verbatim: BreakCopy.suggestion(for: controller.schedule.breakStartedAt))
                    .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
                HStack(spacing: 14) {
                    if strict {
                        holdButton(available: elapsed >= Self.strictSkipDelay)
                    } else {
                        Button(BreakCopy.postpone) { controller.postpone() }
                        Button(BreakCopy.skip) { controller.skip() }
                    }
                }
                .controlSize(.large)
                .disabled(elapsed < Self.grace)
                .padding(.top, 8)
            }
            .padding(40)
            .frame(maxWidth: 560)
        }
        .accessibilityElement(children: .contain)
    }

    /// Skip for Strict breaks: press and hold with the pointer, or hold Return, for three seconds.
    /// VoiceOver's press skips at once, since it is already a deliberate action.
    private func holdButton(available: Bool) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.secondary.opacity(0.18))
            Capsule().fill(Color.accentColor.opacity(0.45)).frame(width: 180 * hold.progress)
            Text(verbatim: BreakCopy.holdToSkip).font(.body.weight(.medium)).frame(width: 180)
        }
        .frame(width: 180, height: 36)
        .opacity(available ? 1 : 0.4)
        .contentShape(Capsule())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in if available { hold.begin() } }
            .onEnded { _ in hold.cancel() })
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(verbatim: BreakCopy.holdToSkip))
        .accessibilityHint(Text("Hold for three seconds, or hold Return.", comment: "Accessibility hint for the Strict break's Hold to Skip button"))
        .accessibilityAction { if available { controller.skip() } }
    }
}
