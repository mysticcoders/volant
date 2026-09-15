# Calculator expression design review

Reviewed Numen at revision `36338ae87a8dfbdd0869d70eb6e7cd6c9c8f8771`. This is a capability and behavior review followed by an independent Volant design. No library dependency, implementation, parser, unit table, geography database or test code was copied. Volant functionality is unchanged by this document.

## What the review establishes

Numen emphasizes everyday expressions with units, dates, time zones, percentages and pluggable currency rates. Its README also describes programmer operators, English natural-language syntax, floating-point limits and locale inconsistencies. Those are useful product ideas, not a reason to import its implementation. [README](https://github.com/vicinaehq/numen/blob/36338ae87a8dfbdd0869d70eb6e7cd6c9c8f8771/README.md)

The README's statement that implicit conversion only works for currencies is stale relative to the reviewed tests: unit tests exercise addition across compatible units and mixed durations. They also demonstrate compound dimensions, target conversions and contextual unit interpretation. This review inspected assertions, not a running Numen build; test presence is evidence of intended behavior, not independent verification. [Unit behavior tests](https://github.com/vicinaehq/numen/blob/36338ae87a8dfbdd0869d70eb6e7cd6c9c8f8771/tests/unit.cpp)

Time-zone tests cover IANA identifiers, case/spacing variants, city aliases and geographically qualified places. They also assign some broad region/country names a single zone and treat EST as a New York alias. Volant should avoid those silent assumptions. [Time-zone behavior tests](https://github.com/vicinaehq/numen/blob/36338ae87a8dfbdd0869d70eb6e7cd6c9c8f8771/tests/timezone.cpp)

Date tests cover relative anchors, local-day boundaries, month-end clamping, leap-year shifts and machine-readable timestamps. These are useful acceptance categories for our own independently chosen examples. [Date behavior tests](https://github.com/vicinaehq/numen/blob/36338ae87a8dfbdd0869d70eb6e7cd6c9c8f8771/tests/datetime.cpp)

## Current Volant gap

`Calculator.swift` evaluates numeric expressions using its own tokens and reverse-Polish evaluator. `UnitConverter.swift` separately accepts one numeric measurement followed by one target unit. The launcher invokes both and formats their output into strings. There is no date/time value or quantity arithmetic. Consequently neither owner example can currently be evaluated.

The existing aliases and Foundation dimensions are useful, but the converter's split-on-text and lowercasing cannot be the grammar for a larger calculator. For example, `in` can mean inches or introduce a conversion, and unit case eventually matters for bits versus bytes.

## Prioritized behavior

| Priority | Capability | Independently chosen example | Expected behavior |
| --- | --- | --- | --- |
| First | Compatible mixed-unit arithmetic | `3kg + 5lbs + 4oz in oz` | `189.821886 oz`, rounded only for display |
| First | Explicit zone conversion | `3pm PST in CET` | `00:00 CET · next day`, using literal UTC−08:00 → UTC+01:00 |
| First | Date-aware regional time | `2026-03-15 3pm Los Angeles in Berlin` | Resolve both named zones for that date and show the destination date/offset |
| Next | Duration arithmetic | `2h 20min + 55min in hours` | `3.25 h` |
| Next | Everyday percentages | `18% of 240` | `43.2`; add unambiguous `off` and percentage-change forms separately |
| Next | Date arithmetic | `2028-02-29 + 1 year` | A documented end-of-month policy; calendar years are not fixed seconds |
| Next | Rates and compound units | `150km / 2h in mph` | Dimension-checked speed; incompatible dimensions fail clearly |
| Existing #4 | Currency arithmetic | `45 USD + 20 EUR in GBP` | Explicit rate provider, timestamp and stale/offline behavior |
| Later | Developer conveniences | Scientific notation, base conversions, modulo/bitwise | Preserve numeric precedence; add only with unambiguous syntax |

Mass reference: international avoirdupois pound = 0.45359237 kg and ounce = 0.028349523125 kg. The result above was independently calculated from those factors, not obtained from Numen. [NIST conversion tables](https://www.nist.gov/document/2026-nist-handbook-44-appendix-c)

## Independent implementation approach

Introduce a small calculation result type: number, quantity, duration, or zoned date/time, plus structured incomplete/error results. Keep the existing numeric functions and precedence tests. Add quantity-aware tokens and evaluation instead of replacing unit strings with numbers and hoping the scalar parser preserves meaning. Route explicit date/time forms to a dedicated date parser using Foundation `Calendar`, `DateComponents` and `TimeZone`. The launcher should receive typed results and a distinct copy value, not recover data from a display string.

A quantity carries its dimension, magnitude and display unit. Addition/subtraction require compatible dimensions, normalize operands consistently, then perform the operation and convert the final result to the requested unit. The first slice can support compatible addition/subtraction, scalar multiplication/division and parentheses; dimension-producing multiplication/division can follow. An explicit trailing conversion binds to the complete preceding expression. Without a target, preserve the first explicit operand's unit so display selection is predictable.

Use the current Foundation unit coverage where it passes reference checks; verify coefficients against exact standard factors for mass/length instead of assuming all library conversion factors have enough precision. Keep precision internally and round only in formatting. Decimal arithmetic is suitable for finite decimal factors and everyday monetary values; scientific functions may remain Double-based with documented tolerances. Do not promise arbitrary precision.

Define temperature separately: absolute Celsius/Fahrenheit conversions are affine, so adding two absolute temperatures must not be treated as ordinary mass addition. Initially retain single-temperature conversions and reject ambiguous temperature arithmetic. Distinguish ounces of mass from fluid ounces and US from imperial volume. Do not infer a missing unit in `3kg + 5`; do not reinterpret meters as minutes merely to make an expression succeed.

## Time-zone decisions

- Literal, explicitly supported standard/daylight abbreviations map to stated fixed offsets (PST −08:00, PDT −07:00, CET +01:00, CEST +02:00). Their result labels include the offset. This is a proposed Volant rule, deliberately distinct from treating a standard abbreviation as a regional zone.
- City/IANA forms use date-dependent rules from the OS time-zone database. Begin with a small independently maintained alias list plus IANA identifiers. Do not copy Numen's place database or silently choose a zone for a multi-zone country/state.
- Date omitted: use today's calendar date in the source zone and show that assumed date in the result. Preserve next/previous-day rollover and the resolved source/destination offsets. Support explicit ISO dates first; ambiguous numeric dates need locale-aware handling or a clearer input.
- Ambiguous abbreviations such as CST/IST and duplicate city names need disambiguation rather than a guessed answer. Offer explicit zones/offsets.
- Nonexistent spring-forward times should report that the local time does not exist. Repeated fall-back times should expose the two possible instants/offsets. Foundation provides matching/repeated-time policies; the UI must communicate the chosen interpretation. [Apple Calendar policy](https://developer.apple.com/documentation/foundation/calendar/repeatedtimepolicy)
- Inject the reference clock, source zone and locale into evaluation so DST and midnight tests are deterministic. Keep calendar days/months separate from elapsed durations: one local calendar day is not always 24 hours.

## Launcher and validation

Evaluate only recognizable calculator input, consume the whole expression, and impose input/token/depth limits. Incomplete typing is not an error banner. Do not let plain app names, unknown suffixes or malformed trailing input produce plausible numeric answers. Show the normalized interpretation with the result; Copy returns a deliberate value, including units or date/zone when relevant.

Backend work should first add pure tests without opening UI: the two requested examples, mixed dimensions, precedence/parentheses, negative quantities, division by zero, incomplete expressions, exact reference factors, DST gaps/overlaps, midnight/year rollover, ambiguous zones and locale variants. The clock and any currency provider must be injected. Wire results into launcher rows in a separate UI-affecting change, then run scoped keyboard, copy and light/dark checks. That makes the new conditional CI policy useful immediately.

No need to build a programming language, equation solver, variables or a broad natural-language interpreter for the first release. Start with the owner's two concrete expressions and make their semantics reliable.
