import AppKit
import SwiftUI
import VolantCore

/// Asks the owner in Volant before a sensitive MCP tool runs: a small non-activating prompt names the
/// AI app and exactly what it wants, with Deny, Always Allow and Allow Once. One prompt shows at a time;
/// the rest wait their turn. An unanswered prompt is denied after `timeout`. Always Allow is remembered
/// per app and tool until the owner chooses Ask Again or disconnects the app. Nothing about a request
/// is logged. Everything but `ask` runs on the main queue. See docs/mcp-server-design.md.
final class MCPApprovals: ObservableObject {
    struct Request: Identifiable, Equatable {
        let id = UUID()
        let client: String
        let tool: String
        let summary: String
    }

    enum Decision: Equatable { case once, always, deny }

    static let timeout: TimeInterval = 60

    /// The request on screen, for the panel's view.
    @Published private(set) var current: Request?
    /// The current settings, read on every request so a new Always Allow or a disconnection applies at once.
    var preferences: () -> MCPPreferences = { MCPPreferences() }
    /// Saves Always Allow for one app and tool.
    var remember: (_ client: String, _ tool: String) -> Void = { _, _ in }
    /// Shows and hides the prompt; tests stand in for the panel.
    var show: (MCPApprovals) -> Void = { $0.panel.present() }
    var hide: (MCPApprovals) -> Void = { $0.panel.orderOut(nil) }
    private let timeout: TimeInterval
    private var waiting: [(Request, CheckedContinuation<Bool, Never>)] = []
    private var answer: CheckedContinuation<Bool, Never>?
    private var timer: Timer?
    private lazy var panel = MCPApprovalPanel(approvals: self)

    init(timeout: TimeInterval = MCPApprovals.timeout) { self.timeout = timeout }

    /// Whether the tool may run: at once for an app the owner always allows, otherwise after the
    /// owner's answer, or false once the prompt times out.
    func ask(client: String, tool: String, summary: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                if self.preferences().alwaysAllows(client: client, tool: tool) { return continuation.resume(returning: true) }
                self.waiting.append((Request(client: client, tool: tool, summary: summary), continuation))
                self.showNext()
            }
        }
    }

    /// Puts a request on screen without anyone waiting on the answer, for render fixtures that run
    /// inside a main-queue block, where `ask`'s hop to the main queue would arrive only afterwards.
    func showForFixture(client: String, tool: String, summary: String) {
        current = Request(client: client, tool: tool, summary: summary)
    }

    /// The owner's answer to the request on screen.
    func decide(_ decision: Decision) {
        guard let request = current, let answer else { return }
        timer?.invalidate()
        timer = nil
        current = nil
        self.answer = nil
        if decision == .always { remember(request.client, request.tool) }
        answer.resume(returning: decision != .deny)
        if waiting.isEmpty { hide(self) } else { showNext() }
    }

    private func showNext() {
        guard current == nil, !waiting.isEmpty else { return }
        let (request, continuation) = waiting.removeFirst()
        if preferences().alwaysAllows(client: request.client, tool: request.tool) {
            continuation.resume(returning: true)
            return showNext()
        }
        current = request
        answer = continuation
        show(self)
        let timer = Timer(timeInterval: timeout, repeats: false) { [weak self] _ in self?.decide(.deny) }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}

/// The approval prompt's window: borderless, non-activating, in the top corner of the screen under the
/// pointer, above full-screen apps and on every Space, like the Breaks heads-up.
final class MCPApprovalPanel: NSPanel {
    static let width: CGFloat = 360
    private let host: NSHostingView<AnyView>

    init(approvals: MCPApprovals) {
        host = NSHostingView(rootView: AnyView(ThemedRoot { MCPApprovalView(approvals: approvals) }))
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
        setAccessibilityLabel(String(localized: "AI app request", comment: "Accessibility label for the Connected Apps approval prompt"))
        contentView = host
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Sizes the panel to its content and shows it without taking focus from the app in front.
    func present() {
        host.layoutSubtreeIfNeeded()
        let size = NSSize(width: Self.width, height: max(80, host.fittingSize.height))
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        setFrame(NSRect(x: (visible.maxX - size.width - 16).rounded(), y: (visible.maxY - size.height - 16).rounded(), width: size.width, height: size.height), display: true)
        if !isVisible { orderFrontRegardless() }
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: String(localized: "An AI app is asking to use Volant", comment: "VoiceOver announcement when an approval prompt appears"),
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}

/// The prompt's content. No button is a default action, so a Return meant for another app can't approve.
struct MCPApprovalView: View {
    @ObservedObject var approvals: MCPApprovals
    @Environment(\.volantTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let request = approvals.current {
                HStack(spacing: 8) {
                    Image(systemName: "hand.raised").foregroundStyle(Color.accentColor).accessibilityHidden(true)
                    Text("\(request.client, format: .verbatim) wants to", comment: "Connected Apps approval prompt title; the value is the AI app's name")
                        .font(.headline).lineLimit(1)
                }
                Text(verbatim: request.summary).font(.callout).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(String(localized: "Deny", comment: "Connected Apps approval prompt button")) { approvals.decide(.deny) }
                    Spacer()
                    Button(String(localized: "Always Allow", comment: "Connected Apps approval prompt button: allow this app this kind of request from now on")) { approvals.decide(.always) }
                    Button(String(localized: "Allow Once", comment: "Connected Apps approval prompt button")) { approvals.decide(.once) }
                }
            }
        }
        .padding(14)
        .frame(width: MCPApprovalPanel.width, alignment: .leading)
        .background(theme.windowBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1.5))
        .accessibilityElement(children: .contain)
    }
}
