import Foundation

// Foundation for WASI (swift-corelibs) has no String(localized:table:comment:) or String Catalogs,
// so this browser build of the calculator answers in English: each localized string is its source
// text, with the two interpolation forms the calculator uses (verbatim text and %lld integers).

/// The `.verbatim` marker in `\(text, format: .verbatim)`.
enum WASIVerbatim { case verbatim }

/// A localization key's English text, built from the same interpolations the String Catalog sees.
struct WASILocalized: ExpressibleByStringInterpolation {
    var text: String

    init(stringLiteral value: String) { text = value }
    init(stringInterpolation: Interpolation) { text = stringInterpolation.text }

    /// Collects literal segments and interpolated values in order.
    struct Interpolation: StringInterpolationProtocol {
        var text = ""
        init(literalCapacity: Int, interpolationCount: Int) { text.reserveCapacity(literalCapacity) }
        mutating func appendLiteral(_ literal: String) { text += literal }
        mutating func appendInterpolation(_ value: String, format: WASIVerbatim) { text += value }
        mutating func appendInterpolation<T: BinaryInteger>(_ value: T, specifier: String) { text += String(value) }
        mutating func appendInterpolation<T>(_ value: T) { text += String(describing: value) }
    }
}

extension String {
    /// The English source text of a localized string; `table` and `comment` are ignored.
    init(localized value: WASILocalized, table: String? = nil, comment: StaticString? = nil) {
        self = value.text
    }
}
