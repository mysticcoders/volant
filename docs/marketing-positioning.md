# Marketing positioning — 2026-09-13

Symptom: the homepage hero showed only Live Notes and described the rest of Volant as small utilities. Agent copy still described implemented ACP conversations as planned.

Decision: lead with “Your Mac. Your agents. One shortcut away.” Present agents, Mac navigation, and personal tools as the product's three pillars. Preserve the graphite/coral visual system. The launcher illustration uses fictional activity and is explicitly labeled; it is not a screenshot. Live Notes remains a supporting development screenshot.

Claims: Herdr discovery, pane focus, and pinned status are implemented. OpenCode, Claude Code, and Codex have native ACP conversations; Claude/Codex use adapters. Cursor verification and reviewed note/snippet handoff remain unfinished. Agent accounts/network access are distinct from local Volant storage. There is no public download yet.

Validation: production build and lint of changed page/layout pass. Desktop 1440px and mobile 390px were rendered and visually inspected, with dark and light OS preferences respectively; the intentional dark site stays consistent. Anchor targets, FAQ transitions, browser errors, and horizontal overflow checked. Repository-wide lint still reports existing shared component issues. These browser checks were task-local scripts, not CI.

Prevention: review marketing claims whenever an integration status changes. Never use a successful native build alone as proof that a provider or UI flow works.

Next gaps:
- Verify Cursor end to end before removing its qualification.
- Implement reviewed note/snippet context handoff.
- Replace the illustrative hero with a representative native launcher capture when the release UI settles.
- Resolve existing shared-component lint failures separately.

## October 7, 2026 — show the broader product

Symptom: the homepage reduced the calculator to a utility, omitted API/local/on-device chat and explicit attachments, and described implemented note context as future work. Download-facing docs also mixed newer calculator work with the public 0.1.5 artifact.

Cause: homepage positioning and release status did not advance with feature documentation.

Decision: retain the hero/brand and lead the feature stories with answers, actionable agent attention, AI choices and explicit context, Mac controls, and local notes/toolkit. Label the expanded calculator, themes, new system actions, and iCloud settings sync Coming next. Keep provider/remote/device verification limits in linked docs. The claim-to-release matrix and backlog are in [marketing claims](marketing-claims.md).

Prevention: review the claims matrix against the distributed release commit whenever changing the download or feature copy. A native capture proves what the view renders, not that a live integration or public download includes it. Existing PR gate and scope checks are automated; website visual inspection and release-claim review remain manual.
