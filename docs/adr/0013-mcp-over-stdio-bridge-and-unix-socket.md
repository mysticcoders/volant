# ADR 0013: MCP over a stdio bridge and an app-group Unix socket

- **Status:** Accepted
- **Date:** 2026-11-18
- **Enforced by:** `MCPListenerTests`; the MCP test suites listed in AGENTS.md

## Context

AI apps should be able to use Volant's notes, launcher entries, Focus and Breaks through MCP. A local HTTP or TCP server is the common way to do that, but it needs a network entitlement on the main app ([ADR 0002](0002-sandboxed-app-with-capability-helpers.md)) and exposes a listener to browsers and DNS rebinding. A transport spike on 2026-11-18 showed that the sandboxed app can listen on a Unix socket in its app group with no network entitlement, and can read each peer's code signature from its audit token; the socket alone is not access control.

## Decision

AI apps start `volant-mcp`, a sandboxed stdio bridge in the app bundle that only copies bytes to a Unix socket in Volant's app group. The socket exists only while the owner's MCP switch is on. The app checks every peer's audit token before reading a byte and serves only the bridge signed by Volant's own team. The protocol and every tool live in the app, calling the same code paths as the launcher and Settings. Sensitive tools ask in Volant on every call unless the owner chose Always Allow for that app and tool.

## Consequences

- No TCP listener and no network entitlement anywhere in the MCP path.
- Every major AI app supports stdio servers, so setup is a command line.
- Requires the app-group entitlement, shared with Volant Dev.
- The bridge and other sandboxed helpers must never be launched from the unit-test host, which would show the owner a container consent prompt.
- See docs/mcp-server-design.md.
