# ADR 0003: Unsandboxed helpers expose fixed, caller-checked APIs

- **Status:** Accepted
- **Date:** 2026-09-13 (VolantAgentHost); 2026-10-11 (VolantInputHost)
- **Enforced by:** `setCodeSigningRequirement` on each listener; `tools/check-input-confinement.py`; `tools/check-rex.sh`

## Context

Some features cannot work inside the sandbox. Herdr and Rex are separate CLIs with sockets outside the container; ACP providers are CLIs that need the owner's Keychain login and project folders; sandboxed Spotlight returns none of the owner's files; Accessibility and event posting need a process the owner can grant. The alternatives were to drop those features or loosen the main app's sandbox. Loosening the sandbox would undo [ADR 0002](0002-sandboxed-app-with-capability-helpers.md) for everything.

## Decision

Two helpers run unsandboxed, `VolantAgentHost` and `VolantInputHost`. Because the OS no longer limits them, their APIs do:

- Each listener accepts only callers that pass a code-signing requirement for Volant's bundle and team.
- Each method takes validated, bounded inputs and returns bounded outputs. No method accepts an arbitrary command, shell string, key code, attribute name or file path to act on.
- External tools are run by absolute path without a shell, with timeouts; Rex runs only a fixed Lua script against a `rex` signed by the expected team.
- `VolantInputHost` launches only after the owner chooses Type at the cursor or turns on Search Menu Items, never at startup, and disconnects when neither uses it. The Rex watcher stops when reads stop or the connection ends.

## Consequences

- Herdr, Rex, ACP, home-folder search, fsearch, Servers, dictation typing and Search Menu Items are possible without weakening the app sandbox.
- Every new capability added to these helpers is a security review, not a convenience. Adding a generic method ("run this", "read this attribute") would turn the helper into an unsandboxed proxy for the app.
- Project folders given to ACP providers are working context, not confinement; providers keep their own credentials and permissions (docs/agent-integrations.md).
- Fixtures and fake clients cannot verify signed caller checks or TCC attribution; that needs the signed installed app.
