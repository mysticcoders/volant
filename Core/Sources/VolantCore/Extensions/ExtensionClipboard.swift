import Foundation

/// The clipboard text an extension may receive. Only an extension whose manifest declares the
/// `clipboard` permission gets it, read once when a run starts and sent as `clipboard` with each of that
/// run's requests. It is plain text of at most 64 KB, and nothing when the clipboard holds an item marked
/// concealed, transient or from a password manager (`PasteboardFilter`). Volant never stores or logs it.
public enum ExtensionClipboard {
    public static let permission = "clipboard"
    public static let maximumBytes = 64 * 1024

    /// The text to send for the clipboard's current string and types, or nil.
    public static func text(_ string: String?, types: [String]) -> String? {
        guard let string, !string.isEmpty, string.utf8.count <= maximumBytes, PasteboardFilter.shouldRecord(types: types) else { return nil }
        return string
    }
}
