import Foundation

/// The colors the Markdown editor draws with under a palette theme, as `#rrggbb` strings. Text is
/// the prose, syntax the dimmed Markdown such as quotes and fence lines, code the inline-code and
/// fence background, the token colors tint keywords, numbers and strings inside fences, caret the
/// insertion point and selection the selected-text highlight.
public struct EditorColors: Equatable {
    public let text: String
    public let syntax: String
    public let code: String
    public let keyword: String
    public let number: String
    public let string: String
    public let caret: String
    public let selection: String

    /// The smallest contrast that still reads as a separate surface: the code background against
    /// the page, and the selection against both.
    public static let surfaceStep = 1.08

    /// Derives editor colors from a palette. The code background is the first of the palette's
    /// secondary background, a faint mix of text into the background, or growing steps away from
    /// the text that stays distinct from both the page and the selection while text on it keeps WCAG AA. The
    /// syntax and token colors are blended toward the text until they reach AA on the code
    /// background, which also covers the page. The caret is the accent, as macOS draws it.
    public init(palette p: ColorPalette) {
        let away = (ColorPalette.contrast(p.text, "#000000") ?? 0) > (ColorPalette.contrast(p.text, "#ffffff") ?? 0) ? "#000000" : "#ffffff"
        let candidates = [p.secondaryBackground, ColorPalette.blend(p.background, p.text, 0.07)]
            + [0.12, 0.25, 0.4].map { ColorPalette.blend(p.background, away, $0) } + [ColorPalette.blend(p.background, p.text, 0.12)]
        let code = candidates.first { candidate in
            let page = ColorPalette.contrast(candidate, p.background) ?? 1
            let selected = ColorPalette.contrast(candidate, p.selection) ?? 1
            return page >= Self.surfaceStep && selected >= Self.surfaceStep && (ColorPalette.contrast(p.text, candidate) ?? 0) >= 4.5
        } ?? candidates[1]
        func readable(_ color: String) -> String {
            [0.0, 0.15, 0.3, 0.45, 0.6, 0.75, 0.9].lazy.map { ColorPalette.blend(color, p.text, $0) }.first {
                min(ColorPalette.contrast($0, code) ?? 0, ColorPalette.contrast($0, p.background) ?? 0) >= 4.5
            } ?? p.text
        }
        text = p.text
        syntax = readable(p.secondaryText)
        self.code = code
        keyword = readable(p.purple)
        number = readable(p.orange)
        string = readable(p.green)
        caret = p.accent
        selection = p.selection
    }
}
