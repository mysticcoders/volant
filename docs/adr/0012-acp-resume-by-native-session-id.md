# ADR 0012: ACP conversations resume only by recorded session ID

- **Status:** Accepted
- **Date:** 2026-10-08
- **Enforced by:** `tools/check-acp.sh`

## Context

ACP providers keep their own session history. When a conversation is reopened, the easy fallback on a failed resume is to start a fresh session and carry on. The owner would then be talking to an agent that has silently lost its context, possibly in a different working folder or account, while believing it is the same conversation.

## Decision

Volant resumes an ACP conversation only by the provider's recorded native session ID through `session/load`, and only when the agent advertised `loadSession`. A failed or unsupported resume ends the connection and never starts a new session in its place. Each turn owns its native session ID, invalidates stale snapshots, rejects concurrent prompts and cancels pending permission requests explicitly.

## Consequences

- The owner always knows whether they are in the same conversation.
- Providers without `loadSession` cannot resume at all, and a failed resume costs the owner a manual restart.
- Fake-agent checks do not replace a signed installed-provider smoke test.
- See docs/agent-integrations.md.
