import Foundation

/// A fixed message an XPC helper sends the app. Helpers have no string catalog, so a message
/// worded there would reach the app in English. Instead a helper replies with `wire`, a stable
/// code, and the app shows `HostMessage.display(_:)`, which is the message in the owner's
/// language. Replies that aren't codes, such as an agent's or provider's own error text, are
/// shown as they arrive. The XPC methods are unchanged: a code travels in the same string reply.
public struct HostMessage: Error, LocalizedError, Equatable, Sendable {
    public enum Code: String, CaseIterable, Sendable {
        case shortcutsUnreadable = "shortcuts-unreadable"
        case shortcutInvalid = "shortcut-invalid"
        case shortcutRunning = "shortcut-running"
        case shortcutFailed = "shortcut-failed"
        case shortcutsUnavailable = "shortcuts-unavailable"
        case agentsUndetected = "agents-undetected"
        case serversUnreadable = "servers-unreadable"
        case repositoriesUnreadable = "repositories-unreadable"
        case notAFilePath = "not-a-file-path"
        case herdrNotFound = "herdr-not-found"
        case herdrUnavailable = "herdr-unavailable"
        case savedMachinesUnreadable = "saved-machines-unreadable"
        case savedMachineChanged = "saved-machine-changed"
        case savedMachineRemoved = "saved-machine-removed"
        case localHerdrUnavailable = "local-herdr-unavailable"
        case remoteHerdrUnavailable = "remote-herdr-unavailable"
        case questionUnreadable = "question-unreadable"
        case paneOrQuestionChanged = "pane-or-question-changed"
        case currentQuestionUnreadable = "current-question-unreadable"
        case responseExpired = "response-expired"
        case questionChanged = "question-changed"
        case questionAlreadyAnswered = "question-already-answered"
        case questionChangedWhileSelecting = "question-changed-while-selecting"
        case answerUnconfirmed = "answer-unconfirmed"
        case answerSentUnconfirmed = "answer-sent-unconfirmed"
        case answerSentAgentChanged = "answer-sent-agent-changed"
        case answerSentResumed = "answer-sent-resumed"
        case answerSentAdvanced = "answer-sent-advanced"
        case answerAcknowledgedByCodex = "answer-acknowledged-by-codex"
        case answerSentPending = "answer-sent-pending"
        case deliveryUnconfirmed = "delivery-unconfirmed"
        case paneChanged = "pane-changed"
        case rexNotFound = "rex-not-found"
        case rexNotRunning = "rex-not-running"
        case rexUnreadable = "rex-unreadable"
        case rexPaneChanged = "rex-pane-changed"
        case rexFocusRefused = "rex-focus-refused"
        case rexFocusNoApp = "rex-focus-no-app"
        case rexFocusFailed = "rex-focus-failed"
        case fsearchNotRunning = "fsearch-not-running"
        case fsearchTimedOut = "fsearch-timed-out"
        case fsearchTooLarge = "fsearch-too-large"
        case fsearchMalformed = "fsearch-malformed"
        case aiConfiguration = "ai-configuration"
        case aiKey = "ai-key"
        case aiResponse = "ai-response"
        case aiLimit = "ai-limit"
        case aiIncomplete = "ai-incomplete"
        case aiUnsupported = "ai-unsupported"
        case aiRejected = "ai-rejected"
        case aiRateLimited = "ai-rate-limited"
        case aiHTTPStatus = "ai-http-status"
        case aiUnreachable = "ai-unreachable"
        case aiConversationUnreadable = "ai-conversation-unreadable"
        case aiReady = "ai-ready"
        case aiResponding = "ai-responding"
        case aiStopped = "ai-stopped"
    }

    /// What every code starts with, so a reply can't be mistaken for one by accident.
    public static let prefix = "volant-host:"
    /// The `NSError` user-info key that carries a message's `wire` beside its English description.
    public static let userInfoKey = "VolantHostMessage"
    private static let separator: Character = "\u{1F}"

    public let code: Code
    /// The one value some messages name: an agent such as Claude Code, or an HTTP status.
    public let argument: String?

    public init(_ code: Code, _ argument: String? = nil) {
        self.code = code
        self.argument = argument
    }

    /// Parses a reply that is a code, or returns nil for any other text.
    public init?(wire: String) {
        guard wire.hasPrefix(Self.prefix) else { return nil }
        let body = wire.dropFirst(Self.prefix.count)
        let parts = body.split(separator: Self.separator, maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first, let code = Code(rawValue: String(first)) else { return nil }
        self.init(code, parts.count > 1 ? String(parts[1]) : nil)
    }

    /// The reply a helper sends: the prefix, the code and any argument.
    public var wire: String { Self.prefix + code.rawValue + (argument.map { String(Self.separator) + $0 } ?? "") }

    public var errorDescription: String? { text }

    /// An `NSError` in `domain` that describes itself with `text` and carries `wire`, for helper
    /// code whose callers already check an error's domain.
    public func error(domain: String, code: Int = 1) -> NSError {
        NSError(domain: domain, code: code, userInfo: [NSLocalizedDescriptionKey: text, Self.userInfoKey: wire])
    }

    /// What the app shows for a helper's reply: the message in the owner's language for a code,
    /// otherwise the reply unchanged.
    public static func display(_ reply: String) -> String { HostMessage(wire: reply)?.text ?? reply }

    /// `display(_:)` for an optional reply.
    public static func display(_ reply: String?) -> String? { reply.map { display($0) } }

    /// The reply a helper sends for an error: the code of a known message, otherwise the error's
    /// own description, which may be an agent's or provider's text.
    public static func wire(for error: Error) -> String {
        if let message = error as? HostMessage { return message.wire }
        if let message = (error as? FSearchError)?.hostMessage { return message.wire }
        if let message = (error as? AIHTTPError)?.hostMessage { return message.wire }
        if let wire = (error as NSError).userInfo[userInfoKey] as? String { return wire }
        return error.localizedDescription
    }

    /// The message worded for the owner. Looked up in the helper it is English, which is why
    /// helpers send `wire` instead.
    public var text: String {
        let value = argument ?? ""
        switch code {
        case .shortcutsUnreadable: return String(localized: "Couldn’t read Apple Shortcuts. Open Shortcuts and try again.", table: "Core", comment: "Apple Shortcuts error")
        case .shortcutInvalid: return String(localized: "Invalid shortcut identifier. Refresh and try again.", table: "Core", comment: "Apple Shortcuts error")
        case .shortcutRunning: return String(localized: "A shortcut is already running.", table: "Core", comment: "Apple Shortcuts error")
        case .shortcutFailed: return String(localized: "Shortcut did not finish successfully. Open Shortcuts to review its permissions and actions.", table: "Core", comment: "Apple Shortcuts error")
        case .shortcutsUnavailable: return String(localized: "Couldn’t start Shortcuts. Open the Shortcuts app and try again.", table: "Core", comment: "Apple Shortcuts error")
        case .agentsUndetected: return String(localized: "Couldn’t check for installed agents.", table: "Core", comment: "AI Settings error while looking for installed coding agents")
        case .serversUnreadable: return String(localized: "Couldn’t read listening servers.", table: "Core", comment: "Servers command error")
        case .repositoriesUnreadable: return String(localized: "Couldn’t read repository changes.", table: "Core", comment: "Herdr pane error while reading Git status")
        case .notAFilePath: return String(localized: "Not a file path.", table: "Core", comment: "File search error")
        case .herdrNotFound: return String(localized: "Herdr was not found. Install Herdr, start a local session, then reconnect.", table: "Core", comment: "Herdr error; Herdr is a program name")
        case .herdrUnavailable: return String(localized: "Herdr is unavailable or the connection timed out.", table: "Core", comment: "Herdr error; Herdr is a program name")
        case .savedMachinesUnreadable: return String(localized: "Couldn’t read saved machines. Check Herdr 0.9.1 or later is installed.", table: "Core", comment: "Herdr machine status detail")
        case .savedMachineChanged: return String(localized: "This saved machine changed or was disabled. Refresh before continuing.", table: "Core", comment: "Herdr remote machine error")
        case .savedMachineRemoved: return String(localized: "This saved machine changed or was removed. Refresh before continuing.", table: "Core", comment: "Herdr remote machine error")
        case .localHerdrUnavailable: return String(localized: "Start the local default Herdr session.", table: "Core", comment: "Herdr machine status detail when this Mac's Herdr isn't reachable")
        case .remoteHerdrUnavailable: return String(localized: "Check SSH access and Herdr 0.9.1 or later on this machine.", table: "Core", comment: "Herdr machine status detail when a remote machine isn't reachable")
        case .questionUnreadable: return String(localized: "This question or machine changed or could not be read. Open Herdr to review it.", table: "Core", comment: "Herdr question error")
        case .paneOrQuestionChanged: return String(localized: "This pane or question changed. Refresh before answering.", table: "Core", comment: "Herdr question error")
        case .currentQuestionUnreadable: return String(localized: "Couldn’t read the current question.", table: "Core", comment: "Herdr question error")
        case .responseExpired: return String(localized: "This response expired or was already sent. Refresh the question.", table: "Core", comment: "Herdr question error")
        case .questionChanged: return String(localized: "The question changed. Nothing was submitted; refresh to review it.", table: "Core", comment: "Herdr question error")
        case .questionAlreadyAnswered: return String(localized: "This question was already answered. Review its pane before retrying.", table: "Core", comment: "Herdr question error")
        case .questionChangedWhileSelecting: return String(localized: "The question changed while selecting. Nothing was submitted; review it in Herdr.", table: "Core", comment: "Herdr question error")
        case .answerUnconfirmed: return String(localized: "Couldn’t confirm the selected answer. Review it in Herdr before retrying.", table: "Core", comment: "Herdr question error")
        case .answerSentUnconfirmed: return String(localized: "Answer sent, but confirmation is unavailable. Check Herdr before retrying.", table: "Core", comment: "Herdr question result")
        case .answerSentAgentChanged: return String(localized: "Answer sent; the agent changed before confirmation. Review its pane.", table: "Core", comment: "Herdr question result")
        case .answerSentResumed:
            return String(localized: "Answer sent; \(value, format: .verbatim) resumed.", table: "Core", comment: "Herdr question result; the agent's name, such as Claude Code")
        case .answerSentAdvanced:
            return String(localized: "Answer sent; \(value, format: .verbatim) advanced to the next question.", table: "Core", comment: "Herdr question result; the agent's name, such as Claude Code")
        case .answerAcknowledgedByCodex: return String(localized: "Codex acknowledged your answer.", table: "Core", comment: "Herdr question result; Codex is a product name")
        case .answerSentPending: return String(localized: "Answer sent, but confirmation is pending. Check Herdr before retrying.", table: "Core", comment: "Herdr question result")
        case .deliveryUnconfirmed: return String(localized: "Couldn’t confirm delivery. Review the pane before retrying.", table: "Core", comment: "Herdr question error")
        case .paneChanged: return String(localized: "This pane or machine changed or is unavailable. Refresh before continuing.", table: "Core", comment: "Herdr pane error")
        case .rexNotFound: return String(localized: "Rex was not found. Install Rex, then try again.", table: "Core", comment: "Rex error; Rex is a terminal app's name")
        case .rexNotRunning: return String(localized: "Rex isn’t running. Open Rex, then try again.", table: "Core", comment: "Rex error; Rex is a terminal app's name")
        case .rexUnreadable: return String(localized: "Couldn’t read Rex panes.", table: "Core", comment: "Rex error; Rex is a terminal app's name")
        case .rexPaneChanged: return String(localized: "This pane changed or closed. Refresh before continuing.", table: "Core", comment: "Rex pane error")
        case .rexFocusRefused:
            return String(localized: "Rex focused the pane but can’t switch to its session until Remote Control is on in Rex Settings › Rex Server.", table: "Core",
                          comment: "Notice after focusing a Rex pane; Remote Control, Rex Settings and Rex Server are Rex's own names")
        case .rexFocusNoApp: return String(localized: "Rex focused the pane. Open the Rex app to see it.", table: "Core", comment: "Notice after focusing a Rex pane")
        case .rexFocusFailed: return String(localized: "Rex focused the pane but couldn’t switch to its session.", table: "Core", comment: "Notice after focusing a Rex pane")
        case .fsearchNotRunning:
            return String(localized: "fsearch isn’t running. Run fsearch once in Terminal, or start it at login with fsearch install --login.", table: "Core",
                          comment: "File search error; fsearch and its command are not translated")
        case .fsearchTimedOut: return String(localized: "fsearch didn’t answer in time.", table: "Core", comment: "File search error; fsearch is a program name")
        case .fsearchTooLarge: return String(localized: "fsearch sent more than Volant reads.", table: "Core", comment: "File search error; fsearch is a program name")
        case .fsearchMalformed: return String(localized: "fsearch sent a reply Volant couldn’t read.", table: "Core", comment: "File search error; fsearch is a program name")
        case .aiConfiguration: return String(localized: "Choose a model and a valid HTTPS API URL, or a loopback URL for local models.", table: "Core", comment: "AI connection error")
        case .aiKey: return String(localized: "Add an API key in AI Settings before connecting.", table: "Core", comment: "AI connection error")
        case .aiResponse: return String(localized: "The server returned an unsupported response. Check the provider and endpoint.", table: "Core", comment: "AI connection error")
        case .aiLimit: return String(localized: "This conversation reached its size limit. Start a new conversation.", table: "Core", comment: "AI connection error")
        case .aiIncomplete: return String(localized: "The response stopped before completion. You can try again.", table: "Core", comment: "AI connection error")
        case .aiUnsupported: return String(localized: "This connection supports text chat only; the server requested an unsupported operation.", table: "Core", comment: "AI connection error")
        case .aiRejected: return String(localized: "The server rejected access. Check your API key and model permissions.", table: "Core", comment: "AI connection error for HTTP 401 or 403")
        case .aiRateLimited: return String(localized: "The server's rate or usage limit was reached. Try again later.", table: "Core", comment: "AI connection error for HTTP 429")
        case .aiHTTPStatus:
            return String(localized: "The AI server returned HTTP \(value, format: .verbatim). Check your connection settings.", table: "Core", comment: "AI connection error; an HTTP status number")
        case .aiUnreachable: return String(localized: "Couldn’t reach the AI server. Check its address and whether it is running.", table: "Core", comment: "AI connection error")
        case .aiConversationUnreadable: return String(localized: "Couldn’t read conversation.", table: "Core", comment: "AI Chat error")
        case .aiReady: return String(localized: "Ready", table: "Core", comment: "AI Chat status for an API connection")
        case .aiResponding: return String(localized: "Responding…", table: "Core", comment: "AI Chat status for an API connection")
        case .aiStopped: return String(localized: "Stopped", table: "Core", comment: "AI Chat status for an API connection")
        }
    }
}
