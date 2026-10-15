import Foundation

/// How much data passes between Volant and an extension module in one invocation. The module's
/// linear memory stays capped at 16 MiB, so the request, the module's parsed copy of it and its reply
/// all fit well inside that.
public enum ExtensionLimits {
    /// The request a module reads: the query, fetched responses and saved storage together.
    public static let maximumInputBytes = 1024 * 1024
    /// The reply a module writes. A list is at most 100 rows, so a quarter of the input is ample.
    public static let maximumOutputBytes = 256 * 1024
    /// Written in messages, so "1 MiB" rather than a byte count.
    public static let inputDescription = "1 MiB"
    public static let outputDescription = "256 KiB"
}
