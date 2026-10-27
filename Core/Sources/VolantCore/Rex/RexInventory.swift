import Foundation

/// What a program in a Rex pane last said it is doing, from the Program Status Protocol (OSC 7501).
/// The cases are ordered by how much they need the owner, most first.
public enum RexState: String, Codable, CaseIterable, Comparable {
    case blocked, error, done, working, idle

    /// An unknown state reads as idle, as the protocol requires, so a state added later never
    /// claims the owner's attention on an older Volant.
    public init(reported: String?) { self = reported.flatMap(RexState.init(rawValue:)) ?? .idle }

    public var title: String {
        switch self {
        case .blocked: return String(localized: "Waiting", table: "Core", comment: "Rex pane state: the program is waiting for the owner")
        case .error: return String(localized: "Failed", table: "Core", comment: "Rex pane state: the program reported an error")
        case .done: return String(localized: "Done", table: "Core", comment: "Rex pane state: the program finished")
        case .working: return String(localized: "Working", table: "Core", comment: "Rex pane state: the program is busy")
        case .idle: return String(localized: "Idle", table: "Core", comment: "Rex pane state: the program is idle")
        }
    }

    private var rank: Int { Self.allCases.firstIndex(of: self) ?? Self.allCases.count }
    public static func < (lhs: RexState, rhs: RexState) -> Bool { lhs.rank < rhs.rank }
}

/// The one status record that represents a pane: its most urgent, then most recent, report.
public struct RexStatus: Codable, Hashable {
    public let state: RexState
    /// For a blocked program: `permission`, `question` or `auth`. Unknown kinds are dropped.
    public let kind: String?
    public let app: String?
    /// One line of program-supplied text, shown as plain text and never logged.
    public let message: String?
    public let progress: Int?
    public let updatedAt: String?

    public init(state: RexState, kind: String? = nil, app: String? = nil, message: String? = nil, progress: Int? = nil, updatedAt: String? = nil) {
        self.state = state; self.kind = kind; self.app = app; self.message = message; self.progress = progress; self.updatedAt = updatedAt
    }
}

/// One terminal pane in a Rex session. Identity is the session and block IDs together; labels are
/// display names that the owner can change at any time.
public struct RexPane: Codable, Hashable, Identifiable {
    public let sessionID: String
    public let sessionLabel: String
    public let blockID: String
    public let label: String
    public let cwd: String?
    public let status: RexStatus?

    public init(sessionID: String, sessionLabel: String, blockID: String, label: String, cwd: String? = nil, status: RexStatus? = nil) {
        self.sessionID = sessionID; self.sessionLabel = sessionLabel; self.blockID = blockID; self.label = label; self.cwd = cwd; self.status = status
    }

    public var id: String { sessionID + "/" + blockID }
    public var state: RexState { status?.state ?? .idle }
    /// The folder name, from the path string alone, so no file system lookup runs on the main thread.
    public var project: String { cwd.map { ($0 as NSString).lastPathComponent }.flatMap { $0.isEmpty ? nil : $0 } ?? sessionLabel }
    /// A readable program name for the `app` identifier a program reported.
    public var program: String? {
        switch status?.app {
        case nil: return nil
        case "claude-code": return "Claude Code"
        case let app?: return app
        }
    }
}

/// Every Rex pane Volant can show, parsed from `RexScript.inventory`'s output.
public struct RexInventory: Codable, Equatable {
    public let panes: [RexPane]
    /// Sessions Rex listed but could not describe; their panes are left out rather than guessed.
    public let unreadableSessions: Int

    public static let maximumPanes = 500
    static let maximumLabel = 200
    static let maximumMessage = 500

    public init(panes: [RexPane], unreadableSessions: Int = 0) {
        self.panes = panes; self.unreadableSessions = unreadableSessions
    }

    /// Parses the inventory script's JSON. Panes with malformed IDs are dropped, text is trimmed to
    /// one bounded line, and panes come back with the ones that need the owner first.
    public static func parse(_ data: Data) throws -> RexInventory {
        let raw = try JSONDecoder().decode(RawInventory.self, from: data)
        var panes: [RexPane] = [], unreadable = 0
        for session in raw.sessions?.values ?? [] {
            guard RexIdentifier.isValid(session.session_id, kind: .session) else { continue }
            if session.error != nil { unreadable += 1; continue }
            let sessionLabel = line(session.label, limit: maximumLabel) ?? String(localized: "Session", table: "Core", comment: "Fallback name for a Rex session that has no label")
            for pane in session.panes?.values ?? [] where panes.count < maximumPanes {
                guard RexIdentifier.isValid(pane.block_id, kind: .block) else { continue }
                panes.append(RexPane(sessionID: session.session_id, sessionLabel: sessionLabel, blockID: pane.block_id,
                                     label: line(pane.label, limit: maximumLabel) ?? String(localized: "Terminal", table: "Core", comment: "Fallback name for a Rex pane that has no label"),
                                     cwd: directory(pane.cwd),
                                     status: representative(pane.records?.values ?? [])))
            }
        }
        return RexInventory(panes: sorted(panes), unreadableSessions: unreadable)
    }

    /// The most urgent record wins, then the most recently updated one.
    static func representative(_ records: [RawRecord]) -> RexStatus? {
        let statuses = records.map { record in
            RexStatus(state: RexState(reported: record.state),
                      kind: record.kind.flatMap { ["permission", "question", "auth"].contains($0) ? $0 : nil },
                      app: (record.effective_app ?? record.app).flatMap { line($0, limit: 32) },
                      message: line(record.msg ?? record.title, limit: maximumMessage),
                      progress: record.progress.flatMap { (0...100).contains($0) ? $0 : nil },
                      updatedAt: record.updated_at.flatMap { line($0, limit: 64) })
        }
        return statuses.min { $0.state != $1.state ? $0.state < $1.state : ($0.updatedAt ?? "") > ($1.updatedAt ?? "") }
    }

    /// Rex reports a directory as a `file://` URL when the shell used OSC 7, or as a plain path.
    /// Only absolute paths are kept; the URL is parsed as a string and never touches the file system.
    static func directory(_ reported: String?) -> String? {
        guard let reported, let value = line(reported, limit: 1024) else { return nil }
        let path = value.hasPrefix("file://") ? URL(string: value)?.path : value
        return path.flatMap { $0.hasPrefix("/") ? $0 : nil }
    }

    /// Panes that need the owner first, then by session and pane label.
    public static func sorted(_ panes: [RexPane]) -> [RexPane] {
        panes.sorted {
            if $0.state != $1.state { return $0.state < $1.state }
            if $0.sessionLabel != $1.sessionLabel { return $0.sessionLabel.localizedStandardCompare($1.sessionLabel) == .orderedAscending }
            return $0.id < $1.id
        }
    }

    /// Program text is meant to be one line already; anything else is flattened and cut, not trusted.
    static func line(_ text: String?, limit: Int) -> String? {
        guard let text else { return nil }
        let flat = String(String.UnicodeScalarView(text.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : $0 }))
            .trimmingCharacters(in: .whitespaces)
        return flat.isEmpty ? nil : String(flat.prefix(limit))
    }

    /// A Lua list. Rex encodes an empty Lua table as `{}`, so an empty object also reads as no items.
    struct LuaList<Element: Decodable>: Decodable {
        let values: [Element]
        init(from decoder: Decoder) throws {
            if let values = try? [Element](from: decoder) { self.values = values; return }
            let object = try decoder.container(keyedBy: AnyKey.self)
            guard object.allKeys.isEmpty else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Expected a list"))
            }
            values = []
        }
    }
    struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
    struct RawInventory: Decodable { let sessions: LuaList<RawSession>? }
    struct RawSession: Decodable {
        let session_id: String
        let label: String?
        let error: String?
        let panes: LuaList<RawPane>?
    }
    struct RawPane: Decodable {
        let block_id: String
        let label: String?
        let cwd: String?
        let records: LuaList<RawRecord>?
    }
    struct RawRecord: Decodable {
        let state: String?
        let kind: String?
        let app: String?
        let effective_app: String?
        let msg: String?
        let title: String?
        let progress: Int?
        let updated_at: String?
    }
}

/// Rex session and block IDs, checked before they reach a script argument or a focus request.
public enum RexIdentifier {
    public enum Kind: String { case session, block, window }

    public static func isValid(_ value: String, kind: Kind) -> Bool {
        let prefix = kind.rawValue + ":"
        guard value.hasPrefix(prefix), value.count > prefix.count, value.count <= 128 else { return false }
        return value.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || ":-_".unicodeScalars.contains($0)) }
    }
}

/// The launcher footer's one-line Rex status, such as "Rex: 2 waiting".
public struct RexStatusSummary: Equatable {
    public let text: String
    public let waiting: Bool
    public let help: String

    public init(panes: [RexPane], connected: Bool, loading: Bool, problem: String?) {
        let blocked = panes.filter { $0.state == .blocked }.count
        if !connected {
            text = String(localized: "Rex: not connected", table: "Core", comment: "Launcher footer status for the Rex terminal app"); waiting = false; help = String(localized: "Rex isn’t connected.\nClick to show Rex panes.", table: "Core", comment: "Launcher footer Rex status tooltip")
        } else if blocked > 0 {
            text = "Rex: \(blocked) waiting"; waiting = true
            help = "\(blocked) \(blocked == 1 ? "pane needs" : "panes need") you.\nClick to show Rex panes."
        } else if let problem {
            text = String(localized: "Rex: unavailable", table: "Core", comment: "Launcher footer status for the Rex terminal app"); waiting = false; help = problem + "\n" + String(localized: "Click to show Rex panes.", table: "Core", comment: "Launcher footer Rex status tooltip, last line")
        } else if loading && panes.isEmpty {
            text = String(localized: "Rex: loading…", table: "Core", comment: "Launcher footer status for the Rex terminal app"); waiting = false; help = String(localized: "Loading panes from Rex.\nClick to show Rex panes.", table: "Core", comment: "Launcher footer Rex status tooltip")
        } else {
            text = String(localized: "Rex: none waiting", table: "Core", comment: "Launcher footer status for the Rex terminal app"); waiting = false
            help = "\(panes.count) \(panes.count == 1 ? "pane" : "panes"), none waiting.\nClick to show Rex panes."
        }
    }
}
