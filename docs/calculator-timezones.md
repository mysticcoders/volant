# Calculator timezone conversion

The launcher now recognizes whole-query timezone expressions locally, without a service or new dependency:

- `1pm EST in CET` → `19:00 GMT+1 (UTC+01:00)` plus the source-assumed date.
- `1pm EST` or `1pm in EST` → the Mac's current timezone.
- `5pm ldn in sf`, `17:30 Europe/London to America/Los_Angeles`.
- `time in Tokyo`, `now in Dubai`.
- `2026-03-15 3pm Los Angeles in Berlin` → `23:00 CET (UTC+01:00) · 2026-03-15`.

Results always include the destination date and resolved UTC offset; Return copies the complete result through the existing Calculation row. Date omitted means today's date in the source zone. `local`, `here` and `my time` select the Mac's timezone. Explicit standard/daylight abbreviations are fixed offsets, while named cities and IANA identifiers use OS date-dependent timezone rules. In summer `1pm EST in Paris` therefore differs from `1pm New York in Paris`.

Queries are limited to 256 UTF-8 bytes, consumed entirely, and evaluated only for explicit time forms. Ambiguous CST/IST, broad country names, invalid dates, incomplete syntax, DST gaps and repeated wall times produce no answer. This first slice does not yet present a disambiguation/error row. Supported city aliases are deliberately small and maintained independently; IANA identifiers provide broader coverage.

## Quality decision

Symptom: arithmetic and single-unit conversion could not answer everyday meeting-time questions.
Cause: neither existing evaluator represented a zoned instant.
Prevention: a separate Foundation-only evaluator owns strict grammar and injected clock/local zone. No permissive natural-language fallback steals application searches. Every copied answer carries its date and offset.
Evidence: automated core tests cover fixed offsets, implicit local conversion, city/IANA aliases, winter/summer and differing DST schedules, half-hour offsets, year/day rollover, invalid queries and DST gaps/overlaps. Native launcher fixtures check first-row selection, complete Copy output and incomplete-query behavior, and capture the affected row in light/dark appearances. The shared classifier treats timezone changes as UI-affecting. Actual verification outcomes are recorded in the PR.

## Next concrete work

1. Surface ambiguous/repeated times with explicit choices and nonexistent-time explanations, without error banners during incomplete typing.
2. Implement compatible mixed-unit arithmetic as designed in `calculator-expression-design.md`.
3. Add natural-language percentages and date/duration arithmetic, with explicit calendar policies.
4. Add currency rates only with a provider, timestamps and stale/offline behavior.

This implements the timezone slice, not full Raycast calculator parity. Signed installed-app verification and release distribution remain separate evidence/work.
