import Foundation

/// The two fixed Lua scripts the agent helper runs with `rex do -e`, and the arguments they take.
/// The app never supplies script text or a method name: only a session and block ID, checked by
/// `RexIdentifier`, reach `focus` as JSON arguments. Neither script reads a terminal's screen,
/// scrollback or clipboard, or types into a pane.
public enum RexScript {
    /// The Rex app's bundle identifier, activated after a pane is focused.
    public static let appBundleIdentifier = "com.superlogical.rex"

    /// Global CLI options: never start a server, bound each request, and talk to this Mac's server
    /// rather than whichever home server the owner configured.
    public static func globalArguments(home: String) -> [String] {
        ["--autostart=false", "--timeout", "5s", "-S", socketAddress(home: home)]
    }

    /// `unix://` plus the percent-encoded path of the local server's socket.
    public static func socketAddress(home: String) -> String {
        let path = home + "/Library/Application Support/rex/server.sock"
        return "unix://" + (path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path)
    }

    /// The exit status `rex` uses when no server is running and autostart is off.
    public static let notRunningStatus: Int32 = 4

    /// Arguments for the inventory script.
    public static func inventoryArguments(home: String) -> [String] {
        globalArguments(home: home) + ["do", "-e", inventory]
    }

    /// Arguments for the focus script, or nil when either ID is malformed.
    public static func focusArguments(home: String, session: String, block: String) -> [String]? {
        guard RexIdentifier.isValid(session, kind: .session), RexIdentifier.isValid(block, kind: .block),
              let data = try? JSONSerialization.data(withJSONObject: ["session_id": session, "block_id": block], options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return globalArguments(home: home) + ["do", "-e", focus, "--args", json]
    }

    /// Every session's terminal panes with their status records and reported directory. Attaching
    /// is how a connection may read a session's view; the script detaches again before moving on.
    public static let inventory = """
    local terminal = "com.superlogical.terminal"
    local out = {}
    local list, err = rex.call("session.list", {})
    if err ~= nil then error(err, 0) end
    for _, s in ipairs(list.sessions or {}) do
      local entry = { session_id = s.session_id, label = s.label, panes = {} }
      local attached, aerr = rex.call("session.attach", { session_id = s.session_id })
      if aerr ~= nil or attached == nil or attached.view == nil then
        entry.error = "unreadable"
      else
        for _, w in ipairs(attached.view.windows or {}) do
          for _, layer in ipairs(w.layers or {}) do
            for _, b in ipairs(layer.blocks or {}) do
              if b.creator_name == terminal then
                local ids = { session_id = s.session_id, block_id = b.block_id }
                local status = rex.call("block.method", { session_id = s.session_id, block_id = b.block_id, method = "program_status" })
                local dir = rex.call("block.method", { session_id = s.session_id, block_id = b.block_id, method = "pwd" })
                table.insert(entry.panes, {
                  block_id = b.block_id,
                  label = b.label,
                  cwd = dir and dir.pwd,
                  records = status and status.records,
                })
              end
            end
          end
        end
        rex.call("session.detach", { session_id = s.session_id })
      end
      table.insert(out, entry)
    end
    return { sessions = out }
    """

    /// Focuses a pane only if it is still a terminal in a window of that session, then asks the Rex
    /// app to show the session, preferring an app window that already has it open.
    public static let focus = """
    local terminal = "com.superlogical.terminal"
    local sid, bid = rex.args.session_id, rex.args.block_id
    local attached, aerr = rex.call("session.attach", { session_id = sid })
    if aerr ~= nil or attached == nil or attached.view == nil then error("missing", 0) end
    local window
    for _, w in ipairs(attached.view.windows or {}) do
      for _, layer in ipairs(w.layers or {}) do
        for _, b in ipairs(layer.blocks or {}) do
          if b.block_id == bid and b.creator_name == terminal then window = w.window_id end
        end
      end
    end
    if window == nil then
      rex.call("session.detach", { session_id = sid })
      error("missing", 0)
    end
    local _, ferr = rex.call("session.focus_block", { session_id = sid, block_id = bid })
    rex.call("session.detach", { session_id = sid })
    if ferr ~= nil then error("unfocused", 0) end
    local preferred, others = {}, {}
    local clients = rex.call("client.list", {})
    for _, c in ipairs((clients and clients.clients) or {}) do
      local inspected = rex.call("client.inspect", { client_id = c.client_id })
      local offers = false
      for _, a in ipairs((inspected and inspected.actions) or {}) do
        if a.name == "session.select" then offers = true end
      end
      if offers then
        local showing = false
        for _, id in ipairs((inspected.client and inspected.client.session_ids) or {}) do
          if id == sid then showing = true end
        end
        table.insert(showing and preferred or others, c.client_id)
      end
    end
    for _, id in ipairs(others) do table.insert(preferred, id) end
    for _, id in ipairs(preferred) do
      local _, perr = rex.call("client.perform", {
        client_id = id, action = "session.select", origin = "api",
        args = { session_id = sid, window_id = window }, timeout_ms = 3000,
      })
      if perr == nil then return { shown = true } end
    end
    return { shown = false }
    """
}
