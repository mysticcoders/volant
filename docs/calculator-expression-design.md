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

- Superseded: regional abbreviations now select their region's clock and label the abbreviation in effect; see `calculator-timezones.md`. The original proposal mapped them to fixed offsets (PST −08:00, CET +01:00), which put summer answers an hour away from what people mean.
- City/IANA forms use date-dependent rules from the OS time-zone database. Begin with a small independently maintained alias list plus IANA identifiers. Do not copy Numen's place database or silently choose a zone for a multi-zone country/state.
- Date omitted: use today's calendar date in the source zone and show that assumed date in the result. Preserve next/previous-day rollover and the resolved source/destination offsets. Support explicit ISO dates first; ambiguous numeric dates need locale-aware handling or a clearer input.
- Ambiguous abbreviations such as CST/IST and duplicate city names need disambiguation rather than a guessed answer. Offer explicit zones/offsets.
- Nonexistent spring-forward times should report that the local time does not exist. Repeated fall-back times should expose the two possible instants/offsets. Foundation provides matching/repeated-time policies; the UI must communicate the chosen interpretation. [Apple Calendar policy](https://developer.apple.com/documentation/foundation/calendar/repeatedtimepolicy)
- Inject the reference clock, source zone and locale into evaluation so DST and midnight tests are deterministic. Keep calendar days/months separate from elapsed durations: one local calendar day is not always 24 hours.

## Launcher and validation

Evaluate only recognizable calculator input, consume the whole expression, and impose input/token/depth limits. Incomplete typing is not an error banner. Do not let plain app names, unknown suffixes or malformed trailing input produce plausible numeric answers. Show the normalized interpretation with the result; Copy returns a deliberate value, including units or date/zone when relevant.

Backend work should first add pure tests without opening UI: the two requested examples, mixed dimensions, precedence/parentheses, negative quantities, division by zero, incomplete expressions, exact reference factors, DST gaps/overlaps, midnight/year rollover, ambiguous zones and locale variants. The clock and any currency provider must be injected. Wire results into launcher rows in a separate UI-affecting change, then run scoped keyboard, copy and light/dark checks. That makes the new conditional CI policy useful immediately.

No need to build a programming language, equation solver, variables or a broad natural-language interpreter for the first release. Start with the owner's two concrete expressions and make their semantics reliable.

## Correctness pass — October 5, 2026

A comparison with Raycast's advertised calculator found one arithmetic defect and several conversion-precision defects in existing behavior, all of which lacked tests.

- **Unary minus:** `-2^2` gave 4. Unary minus outranked `^`. It now sits between `^` and multiplication and is pushed without popping, so `-2^2` is -4, while `2^-1`, `2 * -3` and `-2 * 3` are unchanged.
- **Unit factors:** Foundation rounds several coefficients to about six digits (pound, ounce, stone, US gallon/quart/pint, fluid ounce, tablespoon, teaspoon, km/h, knot, horsepower, psi, mmHg). That surfaced in answers: `10 kn in kph` gave 18.519969, and `1 tbsp in tsp` gave 3.000008. `UnitConverter` now uses exact legal definitions for those units and Foundation for everything else, including the affine temperature scales. Cup is the US customary cup (236.5882365 mL); Foundation's 0.24 L is the US nutrition-label cup.
- **Coverage now tested:** remainder, floor/ceil/round of negatives, constants, nested functions, malformed numbers and unknown functions, number formatting (negative, fractional, infinity), every unit family against reference factors, temperature edges (-40, absolute zero, `°F`, spelled names), decimal versus binary storage, long and plural unit names, and accented city names with and without the city directory.

## Percentages — October 5, 2026

`%` is a percentage rather than remainder, matching how people write it and Raycast's calculator; remainder is `mod`. A percentage is a value that remembers it was written with `%`:

- `52% of 900` → 468, `20% off 80` → 64, `15% on 42` and `15% tip on 42` → 48.3. The card tags a tip with its amount ("Tip 6.3"); Copy gives the total.
- `+` and `-` with a percentage on the right take that share of the left side: `19 + 47%` → 27.93, `100 - 10% - 10%` → 81.
- Elsewhere `%` divides by 100: `200 * 15%` → 30, `50%` → 0.5.
- `of`, `off` and `on` require a percentage on the left and a plain number on the right; `52 of 900`, `50% of 20%` and `10 % 3` give no answer.
- The word operators share multiplication's precedence and associate left: `20% of 50 + 10` → 20.

## Dates and durations — October 6, 2026

`DateCalculator` answers date questions in the owner's local calendar and produces card content directly:

| Form | Example | Answer |
| --- | --- | --- |
| Day words alone | `now`, `today`, `tomorrow`, `yesterday` | the clock or date, tagged Today/Tomorrow |
| Counting | `days until 31 Mar`, `days since Jan 1`, `weeks until 2026-12-25`, `days between Jan 1 and Mar 1` | `176 days`, tagged with the target date; past targets read `643 days ago` |
| Offsets | `in 3 weeks`, `10 days from now`, `35 days ago`, `in 4 hours` | a date tagged `In 21 days`, or a clock tagged Today/Tomorrow |
| Weekday in N weeks | `monday in 3 weeks` | that weekday in the Monday-to-Sunday week N weeks from today |
| Date arithmetic | `August 5 + 5`, `5 Aug 2027 - 2 weeks`, `2028-01-31 + 1 month` | a plain number means days; months clamp to the month's last day |
| Clock arithmetic | `3:45pm + 5`, `9am + 90 min` | a plain number means hours |
| Timespans | `145 mins to timespan`, `100000 s as duration` | `2 hours 25 minutes` |

Rules: hours, minutes and seconds are elapsed time; days, weeks, months and years are calendar steps, so across the October 25 fall-back "in 1 day" still lands on midnight while "in 24 hours" lands at 11 PM. A date without a year means its next occurrence after "until", its last after "since", and this year elsewhere. Dates are `Mar 31`, `31 Mar`, `March 31st 2027` or ISO `2027-03-31`; numeric dates such as `12/25` are rejected because their order depends on locale. Day words count from the local day, and a weekday means its next occurrence with today included. Copy gives the headline, or the full date and time when an elapsed-time answer falls on another day.

Not yet: workdays, "next friday", month-name-only queries ("days until March"), holidays by name, durations added together (`2h 20min + 55min`), and time-zone-qualified date arithmetic.

## Number input — October 6, 2026

`NumberLiteral` reads numbers for both the calculator and the unit converter, following the Mac's locale:

- Grouping is accepted only in real groups of three: `1,000`, `12,345,678`, `1,234.5` in English; `1,5`, `1,00` and `1,000,00` are rejected rather than guessed. The decimal separator is the locale's, so German reads `2,5` and `1.000` (a thousand) and rejects `1.5`. Spaces as grouping (French) are not supported.
- Scientific notation: `1e3`, `2.5E-3`, `1e+2`.
- Magnitudes in the calculator only: suffixes `k`/`K`, `M`, `B` and the words `thousand`, `million`, `billion` (`10K`, `2.5M`, `2.5 million`). Lowercase `m` and `b` stay meters and bytes, and the unit converter takes no suffixes, so `100k in c` is kelvin.
- Unit names ignore spacing: `sq ft`, `square feet`, `fl oz`, `nautical miles`. Square miles, yards, inches and centimeters were added.
- The converter tries every separator position, so `5 in in cm` reads inches.
- Calculator and converter tests now pass an explicit locale instead of depending on the machine's.

## Timestamps — October 6, 2026

`DateCalculator` also shows timestamps in local time. ISO 8601 with a zone (`2024-03-15T14:30:00Z`, `…-04:00`, fractional seconds, a space instead of `T`) or without one (`2026-10-07T08:00`, already local) gives the local clock, tagged with its date and, on the input side, how long ago or ahead it is. Unix time reads `unix 1700000000`, `1700000000 unix` or `epoch …`, as seconds, or milliseconds at 13 digits; `unix now` and `now in unix` give the current value. Bare numbers are never treated as timestamps, so arithmetic stays arithmetic.
