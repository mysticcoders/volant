import Foundation

/// Passes text through unchanged, so a Core string can interpolate text as
/// `"Allow access to \(hosts, format: .verbatim)."`. Core's strings are extracted without the
/// compiler, which skips any interpolation whose format specifier it can't see. An explicit
/// `format:` always reads as `%@` and an explicit `specifier:` as itself, so Core interpolates
/// text this way and numbers as `\(count, specifier: "%lld")`, and the catalog entry matches the
/// key built at run time. See docs/localization.md.
public struct VerbatimFormatStyle: FormatStyle, Sendable {
    public init() {}

    /// The text itself.
    public func format(_ value: String) -> String { value }
}

public extension FormatStyle where Self == VerbatimFormatStyle {
    /// Text interpolated into a Core string as it is.
    static var verbatim: VerbatimFormatStyle { VerbatimFormatStyle() }
}
