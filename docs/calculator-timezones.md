# Calculator timezone conversion

The launcher now recognizes whole-query timezone expressions locally, without a service or new dependency:

- `1pm EST in CET` → `7:00 PM CET`.
- `1pm EST` or `1pm in EST` → the Mac's current timezone.
- `5pm ldn in sf`, `17:30 Europe/London to America/Los_Angeles`.
- `time in Tokyo`, `now in Dubai`.
- `2026-03-15 3pm Los Angeles in Berlin` → `11:00 PM in Berlin · Mar 15, 2026` (with localized date order).

Results use a readable AM/PM clock, Midnight/Noon for exact boundaries, the requested abbreviation or city, and “your time” for the local destination. Same-day implicit conversions omit the date; day rollover adds tomorrow/yesterday relative to the user's local calendar day. Explicit-date queries retain a localized calendar date. Current-time queries compare destination day with the injected local day. Return copies the same readable answer through the existing Calculation row. Date omitted means today's date in the source zone. `local`, `here` and `my time` select the Mac's timezone. Explicit standard/daylight abbreviations are fixed offsets, while named cities and IANA identifiers use OS date-dependent timezone rules. In summer `1pm EST in Paris` therefore differs from `1pm New York in Paris`.

Queries are limited to 256 UTF-8 bytes, consumed entirely, and evaluated only for explicit time forms. Ambiguous CST/IST, broad country names, invalid dates, incomplete syntax, DST gaps and repeated wall times produce no answer. This first slice does not yet present a disambiguation/error row. Supported city aliases are deliberately small and maintained independently; IANA identifiers provide broader coverage.

## Quality decision

Symptom: arithmetic and single-unit conversion could not answer everyday meeting-time questions.
Cause: neither existing evaluator represented a zoned instant.
Prevention: a separate Foundation-only evaluator owns strict grammar and injected clock/local zone. No permissive natural-language fallback steals application searches. Every copied answer retains the human-readable zone and relevant day context.
Evidence: automated core tests cover fixed offsets, implicit local conversion, city/IANA aliases, winter/summer and differing DST schedules, half-hour offsets, year/day rollover, invalid queries and DST gaps/overlaps. Native launcher fixtures check first-row selection, complete Copy output and incomplete-query behavior, and capture the affected row in light/dark appearances. The shared classifier treats timezone changes as UI-affecting. Actual verification outcomes are recorded in the PR.

## Presentation correction

Symptom: duplicate GMT/UTC offsets and ISO dates made a simple answer difficult to scan.
Cause: diagnostic detail was treated as the primary product answer.
Prevention: show the requested timezone abbreviation or a city name, natural clock text and only relevant day context. Keep exact instants in the typed result; do not put programmer diagnostics in the primary answer. This supersedes the earlier design proposal to always display date/offset metadata.
Evidence: exact output tests cover ordinary conversions, local destination, Midnight/Noon, tomorrow/yesterday and dated conversions. Native light/dark captures verify the actual result row; outcomes are in the PR.

## Next concrete work

1. Surface ambiguous/repeated times with explicit choices and nonexistent-time explanations, without error banners during incomplete typing.
2. Implement compatible mixed-unit arithmetic as designed in `calculator-expression-design.md`.
3. Add natural-language percentages and date/duration arithmetic, with explicit calendar policies.
4. Add currency rates only with a provider, timestamps and stale/offline behavior.

This implements the timezone slice, not full Raycast calculator parity. Signed installed-app verification and release distribution remain separate evidence/work.
