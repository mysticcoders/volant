# ADR 0001: Record architecture decisions and keep a glossary

- **Status:** Accepted
- **Date:** 2026-11-23

## Context

Volant's rules live in AGENTS.md and its reasoning in about ninety design docs. Most of the work is done by coding agents, which start each session knowing only what is in context. AGENTS.md says what to do, often without saying why or what was weighed, so a rule that looks arbitrary invites an agent, or a person, to "fix" it. `docs/cross-platform-core.md` already exists "so the decision is not re-argued from instinct"; nothing else is written that way.

The vocabulary has the same problem. Several words carry more than one meaning (helper/host, agent, session, extension), and new code picks one at random.

## Decision

Keep two documents alongside the code:

- [`docs/glossary.md`](../glossary.md) defines the domain terms, names the collisions and gives a preferred term for each. New concepts are named there in the same change that introduces them.
- `docs/adr/` holds one record per significant decision, in the format and under the criteria in the [README](README.md). Records are superseded, not rewritten.

AGENTS.md points agents at both.

## Consequences

- An agent can find why a fence is there before removing it, and a naming question has one place to be settled.
- A small cost per decision, bounded by the three-part test (not obvious, a real trade-off, hard to reverse).
- AGENTS.md stays the list of rules to follow; design docs stay the detailed shape and evidence. An ADR links to both rather than duplicating them.
- The glossary can drift from the code. It is reviewed whenever a PR introduces a new user-facing or architectural term.
