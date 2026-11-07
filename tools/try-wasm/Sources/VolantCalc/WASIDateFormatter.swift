import Foundation

// On WASI, swift-corelibs-foundation's DateFormatter traps (wasm `unreachable` in
// DateFormatter.State._setFormatterAttributes) when given a named time zone such as
// America/Los_Angeles, while TimeZone itself works: offsets, daylight saving and identifiers are
// right, and a fixed-offset zone formats fine. This module-local stand-in shadows DateFormatter for
// the calculator's uses and formats each date through its named zone's offset at that moment, so
// wall-clock times match; zone names in a format pattern would read as GMT offsets.

/// The members of DateFormatter the calculator uses, forwarding to Foundation's formatter.
final class DateFormatter {
    private let inner = Foundation.DateFormatter()
    var timeZone: TimeZone! = TimeZone(secondsFromGMT: 0)
    var calendar: Calendar!
    var locale: Locale! {
        get { inner.locale }
        set { inner.locale = newValue }
    }
    var dateFormat: String! {
        get { inner.dateFormat }
        set { inner.dateFormat = newValue }
    }

    /// Resolves the template against the locale now, as Foundation does when it is set.
    func setLocalizedDateFormatFromTemplate(_ template: String) {
        inner.dateFormat = Foundation.DateFormatter.dateFormat(fromTemplate: template, options: 0, locale: inner.locale)
    }

    /// Points the inner formatter at the fixed offset `timeZone` has at `date`.
    private func pin(to date: Date) {
        let zone = timeZone ?? TimeZone(secondsFromGMT: 0)!
        let fixed = TimeZone(secondsFromGMT: zone.secondsFromGMT(for: date)) ?? TimeZone(secondsFromGMT: 0)!
        // Assigning any calendar to corelibs' DateFormatter on WASI switches it to ICU's root
        // symbols ("Sat, M11 7"), even with a locale; the calculator only uses the Gregorian
        // calendar, which is the formatter's default, so only the zone is set.
        inner.timeZone = fixed
    }

    /// Formats `date` as wall-clock time in `timeZone`.
    func string(from date: Date) -> String {
        pin(to: date)
        return inner.string(from: date)
    }

    /// Parses `text` as wall-clock time in `timeZone`: once with the offset in effect now, then
    /// again with the offset in effect at the parsed moment, so dates across a DST change land right.
    func date(from text: String) -> Date? {
        pin(to: Date())
        guard let first = inner.date(from: text) else { return nil }
        pin(to: first)
        return inner.date(from: text)
    }
}
