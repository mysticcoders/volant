# ADR 0004: Accessibility and event posting only in VolantInputHost

- **Status:** Accepted
- **Date:** 2026-10-11
- **Enforced by:** `tools/check-input-confinement.py`

## Context

Typing dictated text at the cursor and pressing menu items need the Accessibility grant. Once the owner grants Volant, the sandboxed main app also reads as trusted, so the OS would let any code in the app read other apps' windows and post events. That is the most sensitive capability Volant has: it can read secure-adjacent UI and act as the owner.

## Decision

All Accessibility and event-posting calls live in `VolantInputHost/`. This is a **code rule, not an OS rule**, and a check enforces it. The helper's API is small and fixed: no key codes, attribute names, element references, or field or window text reads. Typing reads only role, subrole and character counts, refuses secure fields and secure input, and re-checks the target app per phrase. Menu access re-checks trust, pid, bundle and frontmost state, and refuses Volant, loginwindow and SecurityAgent.

## Consequences

- One small, reviewable surface holds the capability; a feature elsewhere in the app cannot quietly start reading other apps.
- Features that want Accessibility must go through a narrow new method on this helper, with its own limits and tests.
- Fake clients do not verify signed TCC attribution, real insertion or real presses; use `tools/input-host-e2e/run-vm.py` in a disposable clone.
- See docs/dictation-at-cursor-design.md and docs/search-menu-items.md.
