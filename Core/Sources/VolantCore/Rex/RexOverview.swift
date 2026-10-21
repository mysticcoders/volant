import Foundation

/// Every Rex session as tabs of positioned panes, parsed from the same watcher line as
/// `RexInventory`. Tabs are Rex windows; panes carry their place in the tab as fractions, so a
/// view can draw each tab's real layout to scale. `preview` is present only when the owner turned on
/// pane previews, and holds at most `RexScript.previewLines` lines of screen text.
public struct RexOverview: Codable, Equatable {
    public struct Pane: Codable, Equatable, Identifiable {
        public let blockID: String
        public let label: String
        public let title: String?
        public let program: String?
        public let cwd: String?
        public let status: RexStatus?
        /// Where the pane sits in its tab as `[x, y, width, height]` fractions; nil for a pane
        /// outside the tiled layout, such as a floating one.
        public let rect: [Double]?
        public let preview: [String]?

        public init(blockID: String, label: String, title: String? = nil, program: String? = nil, cwd: String? = nil,
                    status: RexStatus? = nil, rect: [Double]? = nil, preview: [String]? = nil) {
            self.blockID = blockID; self.label = label; self.title = title; self.program = program; self.cwd = cwd
            self.status = status; self.rect = rect; self.preview = preview
        }

        public var id: String { blockID }
        public var state: RexState { status?.state ?? .idle }
        /// The best short name: the title a program set, then the folder, then the program.
        public var name: String {
            title ?? cwd.map { ($0 as NSString).lastPathComponent }.flatMap { $0.isEmpty ? nil : $0 } ?? program ?? label
        }
    }

    public struct Tab: Codable, Equatable, Identifiable {
        public let windowID: String
        public let label: String
        public let active: Bool
        public let focusedBlockID: String?
        public let panes: [Pane]

        public init(windowID: String, label: String, active: Bool = false, focusedBlockID: String? = nil, panes: [Pane]) {
            self.windowID = windowID; self.label = label; self.active = active; self.focusedBlockID = focusedBlockID; self.panes = panes
        }

        public var id: String { windowID }
        /// Rex names new tabs "Window" plus a short ID; such a tab is named for its focused pane instead.
        public var name: String {
            if !label.hasPrefix("Window ") { return label }
            return (panes.first { $0.blockID == focusedBlockID } ?? panes.first)?.name ?? label
        }
        public var waiting: Int { panes.filter { $0.state == .blocked }.count }
        /// The pane Return should focus: a waiting one, then the focused one, then the first.
        public var primaryPane: Pane? {
            panes.first { $0.state == .blocked } ?? panes.first { $0.blockID == focusedBlockID } ?? panes.first
        }
    }

    public struct Session: Codable, Equatable, Identifiable {
        public let sessionID: String
        public let label: String
        public let tabs: [Tab]

        public init(sessionID: String, label: String, tabs: [Tab]) {
            self.sessionID = sessionID; self.label = label; self.tabs = tabs
        }

        public var id: String { sessionID }
        public var waiting: Int { tabs.reduce(0) { $0 + $1.waiting } }
    }

    public let sessions: [Session]

    public init(sessions: [Session]) { self.sessions = sessions }

    public static let maximumTabs = 200

    /// Parses the watcher's JSON line. Malformed IDs are dropped, text is one bounded line, rects
    /// are clamped to the tab, and preview lines are flattened and cut again here, whatever the
    /// script sent.
    public static func parse(_ data: Data) throws -> RexOverview {
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        var sessions: [Session] = [], tabCount = 0
        for session in raw.sessions?.values ?? [] {
            guard RexIdentifier.isValid(session.session_id, kind: .session), session.error == nil else { continue }
            var panesByWindow: [String: [Pane]] = [:]
            for pane in session.panes?.values ?? [] {
                guard RexIdentifier.isValid(pane.block_id, kind: .block), let window = pane.window_id,
                      RexIdentifier.isValid(window, kind: .window) else { continue }
                panesByWindow[window, default: []].append(Pane(
                    blockID: pane.block_id,
                    label: RexInventory.line(pane.label, limit: RexInventory.maximumLabel) ?? "Terminal",
                    title: RexInventory.line(pane.title, limit: RexInventory.maximumLabel),
                    program: programName(pane.program),
                    cwd: RexInventory.directory(pane.cwd),
                    status: RexInventory.representative(pane.records?.values ?? []),
                    rect: rect(pane.rect),
                    preview: pane.preview.map { lines in
                        Array(lines.values.suffix(RexScript.previewLines).map { RexInventory.line($0, limit: RexScript.previewColumns) ?? "" })
                    }))
            }
            var tabs: [Tab] = []
            for window in session.windows?.values ?? [] where tabCount < maximumTabs && RexIdentifier.isValid(window.window_id, kind: .window) {
                guard let panes = panesByWindow[window.window_id], !panes.isEmpty else { continue }
                tabs.append(Tab(windowID: window.window_id, label: RexInventory.line(window.label, limit: RexInventory.maximumLabel) ?? "Tab",
                                active: window.active ?? false,
                                focusedBlockID: window.focused_block_id.flatMap { RexIdentifier.isValid($0, kind: .block) ? $0 : nil },
                                panes: panes))
                tabCount += 1
            }
            if !tabs.isEmpty {
                sessions.append(Session(sessionID: session.session_id, label: RexInventory.line(session.label, limit: RexInventory.maximumLabel) ?? "Session", tabs: tabs))
            }
        }
        return RexOverview(sessions: sessions)
    }

    /// A program's label from what Rex reports: the file name of a script or executable path,
    /// without the dash a login shell puts before its name.
    static func programName(_ reported: String?) -> String? {
        guard let value = RexInventory.line(reported, limit: 256) else { return nil }
        let name = (value as NSString).lastPathComponent
        let trimmed = name.hasPrefix("-") ? String(name.dropFirst()) : name
        return trimmed.isEmpty ? nil : String(trimmed.prefix(64))
    }

    /// Four finite fractions inside the tab, or nil.
    static func rect(_ values: [Double]?) -> [Double]? {
        guard let values, values.count == 4, values.allSatisfy(\.isFinite) else { return nil }
        let x = min(max(values[0], 0), 1), y = min(max(values[1], 0), 1)
        let width = min(max(values[2], 0), 1 - x), height = min(max(values[3], 0), 1 - y)
        return width > 0 && height > 0 ? [x, y, width, height] : nil
    }

    struct Raw: Decodable { let sessions: RexInventory.LuaList<RawSession>? }
    struct RawSession: Decodable {
        let session_id: String
        let label: String?
        let error: String?
        let panes: RexInventory.LuaList<RawPane>?
        let windows: RexInventory.LuaList<RawWindow>?
    }
    struct RawWindow: Decodable {
        let window_id: String
        let label: String?
        let active: Bool?
        let focused_block_id: String?
    }
    /// One pane as the script printed it. A malformed rect reads as none, so one odd pane draws
    /// as the whole tab instead of failing the overview.
    struct RawPane: Decodable {
        let block_id: String
        let label: String?
        let cwd: String?
        let title: String?
        let program: String?
        let window_id: String?
        let rect: [Double]?
        let records: RexInventory.LuaList<RexInventory.RawRecord>?
        let preview: RexInventory.LuaList<String>?

        private enum CodingKeys: String, CodingKey { case block_id, label, cwd, title, program, window_id, rect, records, preview }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            block_id = try c.decode(String.self, forKey: .block_id)
            label = try? c.decodeIfPresent(String.self, forKey: .label)
            cwd = try? c.decodeIfPresent(String.self, forKey: .cwd)
            title = try? c.decodeIfPresent(String.self, forKey: .title)
            program = try? c.decodeIfPresent(String.self, forKey: .program)
            window_id = try? c.decodeIfPresent(String.self, forKey: .window_id)
            rect = try? c.decodeIfPresent([Double].self, forKey: .rect)
            records = try? c.decodeIfPresent(RexInventory.LuaList<RexInventory.RawRecord>.self, forKey: .records)
            preview = try? c.decodeIfPresent(RexInventory.LuaList<String>.self, forKey: .preview)
        }
    }
}
