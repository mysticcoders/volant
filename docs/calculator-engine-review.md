# Calculator engine review — September 18, 2026

Volant currently has a small in-process arithmetic parser (`Calculator.swift`) and a separate Foundation Measurement converter (`UnitConverter.swift`). Arithmetic supports +, −, ×, ÷, remainder, powers, parentheses, pi/e and sqrt/abs/round/floor/ceil. The converter accepts one numeric quantity and a destination unit across length, mass, temperature, volume, speed, duration, area, storage, energy, power and pressure. There is no mixed-unit expression tree, currency feed, date arithmetic, or timezone expression parser. `%` currently means remainder, not a natural-language percentage.

[SoulverCore](https://github.com/soulverteam/SoulverCore) is a closed-source Swift binary framework distributed through SwiftPM. Its documented families include natural-language percentages, unit expressions, dates, times/time zones, rates, finance and variables. Currency conversion requires a supplied rate provider; it does not remove the need to select, cache and display the age of rate data.

The [license](https://github.com/soulverteam/SoulverCore/blob/master/LICENSE.md) asks publicly available and commercial projects to contact the vendor; free attribution-based arrangements may be available. Volant being MIT does not grant redistribution rights to this separate proprietary dependency. No SoulverCore binary has been added or distributed, and no vendor message was sent.

## Proposed integration boundary

Keep an engine interface returning a display answer plus copyable value, with a native implementation always available. Evaluate the richer engine only for plausible calculator queries, off the launch-critical path, and reject stale results after query edits. Do not allow its permissive natural-language parsing to steal app-name searches. Benchmark cold initialization, warm evaluation, memory and p95/p99 query latency on native hardware before selecting a default; vendor throughput figures are not launcher latency evidence.

Before public adoption: obtain redistribution terms, confirm supported macOS/architectures and binary-update policy, then run a private compatibility corpus. Include `3pm PST in CET`, `3kg + 5lbs + 4oz in oz`, date/DST boundaries, decimal precision, currencies with unavailable/stale rates, remainder-versus-percent semantics, malformed input and ordinary app names. Document whether timezone abbreviations are fixed offsets or date-dependent zones; city names and explicit dates should remove ambiguity. Exact requested syntax has not yet been run against SoulverCore.

Recommendation: investigate SoulverCore as an optional engine; do not silently replace the MIT implementation. The biggest functional gain is combining quantities and time/date concepts in a single expression, not faster basic arithmetic. The fallback roadmap is mixed-unit arithmetic followed by explicit timezone conversions.
