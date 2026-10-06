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
## Functions and phrasings — October 6, 2026

- Functions: `sqrt cbrt abs round floor ceil`, `sin cos tan cot sec csc`, `asin acos atan`, `sinh cosh tanh asinh acosh atanh`, `ln`, `log` (base 10), `log10`, `log2`, `exp`. Names are case-insensitive.
- Angles are radians, matching mathematical convention; `°`, `deg`, `degree(s)` mark degrees and `rad`/`radian(s)` is accepted as a no-op: `sin(90°)`, `cos 60 deg`.
- A function name binds to the value right after it, so `sqrt 16 + 9` is 13 and `abs -3 + 1` is 4; parentheses widen the argument.
- Factorial: `5!` and `5 factorial`, for whole numbers 0–170. It binds tighter than unary minus and `^` (`-3!` is -6, `2^3!` is 64).
- Phrasings: `square root of`, `cube root of`, `power`, `to the power of`, `squared`, `cubed`.
- Results that are not real finite numbers (`sqrt(-1)`, `asin(2)`, `ln(0)`, overflow) give no answer instead of "undefined".

## Colors — October 6, 2026

`ColorCalculator` converts CSS colors: hex (`#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`), `rgb()`/`rgba()`, `hsl()`/`hsla()`, `hwb()`, `lab()`, `lch()`, `oklab()` and `oklch()`, in legacy comma or modern space syntax, with percentages, `deg`/`rad`/`grad`/`turn` hues and `/ alpha`.

- Hex answers in `rgb(…)` tagged with `hsl(…)`; other inputs answer in hex tagged with `rgb(…)` (or `hsl(…)` for rgb input). `in`/`to`/`as <format>` picks the target: `#ff6363 in oklch`.
- The card shows a swatch beside the input, outlined so pale and dark colors stay visible in both appearances.
- Math follows CSS Color 4: the sRGB transfer curve, lab/lch relative to D50 via Bradford, OKLab from linear sRGB. Tests check sRGB red against the specification's worked values and round-trip `#3a7bd5` through every format.
- hsl and hwb show one decimal so 8-bit colors survive a round trip (`hsl(0 100% 69.4%)`).
- Colors outside sRGB keep exact values in lab/lch/oklab/oklch and show their clamped sRGB color elsewhere, tagged "Outside sRGB". This clamps channels rather than gamut-mapping in OKLCH.
- Named colors (`red`) and hex without `#` are not read, since they collide with words and numbers.
## CSS and design units — October 6, 2026

`ScreenUnits` converts px, rem, em, pt, pc and the physical in, cm and mm they relate to: `2rem in px`, `32px in rem`, `12pt in px`, `2 inches in px at 72 ppi`, `1.5rem in px at 18px`. CSS fixes 1in = 96px, 1pt = 1/72in and 1pc = 12pt, and rem/em default to 16px; `at <n>px` sets the rem/em base and `at <n> ppi|dpi` switches to print and design math, where a pixel is 1/n inch. The input tag states the assumption (`1rem = 16px`, `72 ppi`). At least one side must be px, rem, em, pt or pc, so `1 pt in ml` stays pints and `5 in in cm` stays a length conversion. Results round to four decimals and copy in CSS form (`32px`).

## Use Answer — October 6, 2026

On any calculator card, Command-Return puts the answer (its Copy text) into the search field and keeps the launcher open, so `2 + 2`, Command-Return, ` * 3` gives 12. The footer labels it "Use Answer". Return still copies. The launcher fixture checks the label, the replaced query and the continued calculation.

## Currency — October 6, 2026

`CurrencyConverter` converts with European Central Bank daily reference rates (about 30 currencies, euro-based, one business day): `100 usd in eur`, `$100 in gbp`, `€50 to yen`, `USD1K in CHF`, `20 pounds in euros`. Cross rates go through the euro. The card tags the rate (`1 USD = 0.8 EUR`) and the rate date (`ECB rates · Oct 5`, or `Old ECB rates · …` after eight days), and Copy gives the formatted amount. Symbols and names map to one currency each ($/dollars to USD, ¥/yen to JPY); other dollars need their code. "pounds" is currency only when the other side is a currency, so `5 pounds in kg` stays a weight. Without rates there is no answer.

Network: the app keeps no network entitlement. `VolantRatesHost` is a sandboxed XPC helper with only `network.client`; its one method takes no input and fetches the fixed ECB URL with an ephemeral session (no cookies or cache), refuses redirects, caps the response at 64 KB and replies only with data that parses as the feed. `CurrencyRatesStore` in the app fetches nothing until a query is shaped like a currency conversion, then refreshes at most every twelve hours while conversions are used, waits an hour after a failure, and caches the rates with their date in the support directory so conversions work offline. When rates arrive for the query still being typed, the launcher redraws while keeping the selected row. `tools/check-rates-xpc.sh` runs the real signed helper from a built app inside a sandboxed client and fetches the live feed once.

The website's privacy page lists the app's network exceptions; the release that ships this must add exchange rates there.

## Named colors — October 6, 2026

The 148 CSS named colors convert when a target format is given: `red in hex`, `RebeccaPurple to rgb`, `light gray in hex` (spaces ignored). The input side is tagged with the color's hex. A bare name (`red`, `orange`) is left to search. The table in `NamedColors.swift` is generated from the color-name package (MIT), which mirrors the CSS Color 4 list.

## More dates — October 6, 2026

- `next friday` is the next Friday that is not today (one to seven days ahead), `this friday` the coming one with today included. Both work alone, in date questions (`days until next monday`) and in time queries (`3pm next friday`); the card always shows the resolved date.
- Workdays are Monday to Friday, without public holidays: `workdays until Dec 25` (also "business days", "working days") counts days after today through the target; `in 10 workdays`, `5 business days ago` and `today + 10 workdays` step over weekends.
- Named holidays work wherever a date does, with an optional year: Christmas and its eve, New Year's Day and Eve, Halloween, Valentine's Day, St Patrick's Day, Independence Day (`4th of July`), US Thanksgiving (fourth Thursday of November) and Western Easter (anonymous Gregorian algorithm). Alone, a holiday name is left to search.
- Durations add and subtract: `2h 20min + 55min` gives `3 hours 15 minutes`, `… in hours` gives `3.25 hours`, `2h 20min in minutes` gives `140 minutes`. A single quantity stays with `UnitConverter` (`90 min in h`), and negative totals give no answer.

## Multi-argument functions — October 6, 2026

`max`, `min` (two or more arguments), `atan2(y, x)`, `hypot`, `pow`, `log(x, base)`, `round(x, digits)`, `gcd`, `lcm`, `nCr`/`choose` and `nPr`/`perm`. A comma separates arguments when it cannot be thousands grouping (`max(1,5)`, `max(1, 500)`); `;` always separates, for locales with a decimal comma (`max(2,5; 7)` in German). Because max and min need two arguments, an ambiguous `max(1,500)` gives no answer instead of a wrong one. Arguments outside a function's domain (`nCr(3, 5)`, `gcd(1.5, 3)`, `log(8, 1)`) give no answer.

## Swap — October 6, 2026

Shift-Command-Return on a conversion card replaces the search with the same conversion the other way, using the answer as the input: `5 km in mi` becomes `3.106856 mi in km`, `100 usd in eur` becomes `80 EUR in USD`, `2rem in px at 18px` becomes `36px in rem at 18px`, and `#ff6363` becomes `rgb(255 99 99) in hex`. The footer shows "Swap ⇧⌘↩" only when a swap exists; arithmetic, dates and time answers have none. The unit converter now reads its own symbols (`ft²`, `°F`), so swapped queries parse. Round trips return to the original value within the six-decimal display rounding.

## Time and date polish — October 6, 2026

- Time conversions swap with Shift-Command-Return: `1pm EST in CET` becomes `7:00pm cet in est`; when the answer falls on another day there, the swap names that date (`2026-10-03 4:00am cet in est`) so the reverse is exact; an implicit local destination swaps as `local`. Clocks, local moments and differences have no swap.
- `time in 4 hours in Tokyo`, `time in 90 minutes in New York`, `time in 1 day in LA`: the clock there after that much elapsed time, tagged `In 4 hours`.
- `last friday` is the most recent Friday before today; `friday after next` is a week after next Friday. Both work alone, in date questions and in time queries, and past local moments read `7 days ago`.
- Locales that group digits with a space (French uses a narrow no-break space) accept a typed space: `1 000 + 5`, `12 345,5 * 2`.

## Public holidays — October 6, 2026

Workdays now skip the public holidays of the Mac's region where `PublicHolidays` knows them: US federal holidays (Saturday holidays observed Friday, Sunday ones Monday), UK bank holidays for England and Wales (substitute weekdays), and the national holidays of Germany, France and Canada (federal, with substitutes). The card says which ("Skips US holidays") or "Weekends only" for other regions. Rules are computed per year, including Easter-based days; one-off proclaimed holidays and regional (state or province) holidays are not included. Tests compare 2026 and 2027 against the OPM, GOV.UK, German and Canadian published lists.

More holidays work in date questions: Good Friday, Easter Monday, Boxing Day, MLK Day, Presidents' Day, Memorial Day, Juneteenth, Labor Day, Columbus Day, Veterans Day, Mother's Day and Father's Day (US dates).
