import Foundation

/// SVG row image previews. When a row's `image` URL returns SVG markup (detected as for a copy, see
/// `ExtensionItemCopy.imageKindSVG`), the fetch helper does not draw it: it checks the markup with
/// `check` and hands the bytes, marked as SVG, to Volant, which forwards them unread to the extension
/// helper (no network, sandboxed). That helper checks them again and draws them with the system's SVG
/// renderer into the same small PNG a raster preview becomes, within `renderTimeout`.
///
/// `check` is a token scan, not an XML parser: nothing here resolves entities, reads a DTD or follows a
/// reference. It refuses rather than rewrites. Anything that could reach a file or the network, run
/// script, embed HTML or another image, expand entities, or grow without bound is refused, and the row
/// keeps its placeholder:
/// - a DOCTYPE or any other `<!` declaration, and processing instructions other than a leading XML prolog;
/// - `<script>`, `<foreignObject>`, `<image>`, `<feImage>`, embedded or linked content (`iframe`, `object`,
///   `embed`, `audio`, `video`, `canvas`, `link`, `xi:include`, …), and animation, which can change
///   attributes after the check;
/// - `on…` event attributes, `src` and `xml:base`, and any `href` (with or without a prefix) not starting
///   with `#`;
/// - CSS, in a `<style>` element or any attribute, with `@import`, `@font-face`, a backslash escape, a
///   `url(` other than `url(#…)`, or `image(`, `image-set(`, `cross-fade(` or `src(`;
/// - filters and masks (`<filter>`, any `fe…` primitive, `<mask>`, the `filter` and `mask` attributes, and
///   CSS naming either): the system renderer draws them at the document's own resolution, before scaling
///   down, so a small file with a large canvas or a scale transform makes it allocate gigabytes;
/// - a `<use>` pointing at something that itself contains a `<use>`, which can multiply drawing
///   exponentially;
/// - more than `maximumBytes`, `maximumElements` elements or `maximumDepth` levels, and a `width`,
///   `height` or `viewBox` value over `maximumDimension`;
/// - malformed markup: unbalanced or unterminated tags, unquoted attributes, `<` in attribute values,
///   unknown entities, text or a second element after the root.
public enum ExtensionSVGPreview {
    public static let maximumBytes = ExtensionItemImage.maximumDownloadBytes
    public static let maximumElements = 5_000
    public static let maximumDepth = 64
    public static let maximumDimension = 16_384.0
    /// How long the extension helper may spend drawing one preview before it stops itself.
    public static let renderTimeout: TimeInterval = 1
    /// How long Volant waits for the helper's answer once it sent the SVG, a little more than
    /// `renderTimeout`, before it shows the placeholder.
    public static let replyTimeout: TimeInterval = 1.5

    /// Why `check` refused markup. The raw values are short codes the helpers send for diagnostics.
    public enum Refusal: String, Error, CaseIterable, Sendable {
        case notSVG, tooLarge, malformed, declaration, processingInstruction, forbiddenElement, eventAttribute
        case externalReference, forbiddenStyle, nestedUse, expensiveEffect, tooManyElements, tooDeep, dimensionTooLarge
    }

    /// Elements refused anywhere, by lowercased local name.
    static let forbiddenElements: Set<String> = [
        "script", "foreignobject", "image", "feimage", "iframe", "frame", "frameset", "object", "embed", "applet", "audio", "video",
        "canvas", "img", "html", "body", "link", "meta", "base", "include", "handler", "listener", "animation", "set", "animate",
        "animatemotion", "animatetransform", "animatecolor", "discard", "font-face-uri", "color-profile", "cursor", "tref"
    ]

    /// Elements and attributes, by lowercased local name, that make the renderer draw offscreen at the
    /// document's resolution; any element whose local name starts with `fe` is a filter primitive too.
    static let expensiveElements: Set<String> = ["filter", "mask"]
    static let expensiveAttributes: Set<String> = ["filter", "mask"]

    /// CSS functions that load something, besides `url(`.
    static let fetchingFunctions = ["image(", "image-set(", "cross-fade(", "src("]

    /// Whether downloaded bytes are SVG markup, by the same rule as an `image` copy: no raster
    /// signature, UTF-8 without NUL characters, and an `<svg` root after an optional preamble.
    public static func isSVG(_ data: Data) -> Bool { ExtensionItemCopy.imageKindSVG(data) != nil }

    /// Why the markup in `data` may not be drawn, or nil when it may.
    public static func check(_ data: Data) -> Refusal? {
        if case .failure(let refusal) = sanitized(data) { return refusal }
        return nil
    }

    /// The markup to draw: `data` as UTF-8 without a byte order mark, unchanged otherwise, when `check`
    /// accepts it; the refusal when it does not.
    public static func sanitized(_ data: Data) -> Result<Data, Refusal> {
        guard data.count <= maximumBytes else { return .failure(.tooLarge) }
        guard let text = ExtensionItemCopy.imageKindSVG(data) else { return .failure(.notSVG) }
        let bytes = Array(text.utf8)
        var scanner = Scanner(bytes)
        do { try scanner.scan() } catch let refusal as Refusal { return .failure(refusal) } catch { return .failure(.malformed) }
        return .success(Data(bytes))
    }

    /// One pass over the markup's bytes. Names are ASCII; anything else in a name is malformed.
    struct Scanner {
        private let bytes: [UInt8]
        private var index = 0
        private var open: [(name: String, id: String?, containsUse: Bool)] = []
        private var elements = 0
        private var sawMarkup = false
        private var rootClosed = false
        private var style: [UInt8]?
        private var idsContainingUse: [String: Bool] = [:]
        private var useTargets: [String] = []

        init(_ bytes: [UInt8]) { self.bytes = bytes }

        /// Scans the whole document, throwing the first `Refusal`.
        mutating func scan() throws {
            while index < bytes.count {
                if bytes[index] != UInt8(ascii: "<") { try text(); continue }
                if starts(with: "<!--") { try comment() } else if starts(with: "<![CDATA[") { try cdata() } else if starts(with: "<!") {
                    throw Refusal.declaration
                } else if starts(with: "<?") { try processingInstruction() } else if starts(with: "</") { try endTag() } else { try startTag() }
                sawMarkup = true
            }
            guard rootClosed, open.isEmpty else { throw Refusal.malformed }
            for target in useTargets where idsContainingUse[target] == true { throw Refusal.nestedUse }
        }

        private func starts(with prefix: String) -> Bool {
            let pattern = Array(prefix.utf8)
            return bytes.count - index >= pattern.count && bytes[index..<index + pattern.count].elementsEqual(pattern)
        }

        /// The index just past the next `terminator`, searching from `from`, or nil.
        private func end(of terminator: String, from: Int) -> Int? {
            let pattern = Array(terminator.utf8)
            var position = from
            while position + pattern.count <= bytes.count {
                if bytes[position..<position + pattern.count].elementsEqual(pattern) { return position + pattern.count }
                position += 1
            }
            return nil
        }

        /// Character data: only whitespace outside the root, valid references inside it, and collected for
        /// the CSS check inside `<style>`.
        private mutating func text() throws {
            let start = index
            while index < bytes.count, bytes[index] != UInt8(ascii: "<") { index += 1 }
            let run = bytes[start..<index]
            if open.isEmpty {
                guard run.allSatisfy(Self.isWhitespace) else { throw Refusal.malformed }
                return
            }
            let decoded = try Self.decodeReferences(run)
            style?.append(contentsOf: decoded)
        }

        private mutating func comment() throws {
            guard let next = end(of: "-->", from: index + 4) else { throw Refusal.malformed }
            index = next
        }

        private mutating func cdata() throws {
            guard !open.isEmpty, let next = end(of: "]]>", from: index + 9) else { throw Refusal.malformed }
            style?.append(contentsOf: bytes[(index + 9)..<(next - 3)])
            index = next
        }

        /// Only `<?xml …?>`, and only before any other markup.
        private mutating func processingInstruction() throws {
            index += 2
            let target = name()
            guard target == "xml", !sawMarkup, index < bytes.count, Self.isWhitespace(bytes[index]),
                  let next = end(of: "?>", from: index) else { throw Refusal.processingInstruction }
            index = next
        }

        private mutating func endTag() throws {
            index += 2
            let closing = name()
            skipWhitespace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: ">"), let element = open.popLast(), element.name == closing else {
                throw Refusal.malformed
            }
            index += 1
            try close(element)
        }

        /// Records what a closed element contained, checks a finished `<style>`, and ends the root.
        private mutating func close(_ element: (name: String, id: String?, containsUse: Bool)) throws {
            if let id = element.id { idsContainingUse[id] = (idsContainingUse[id] ?? false) || element.containsUse }
            if element.containsUse, !open.isEmpty { open[open.count - 1].containsUse = true }
            if Self.localName(element.name) == "style", let css = style {
                style = nil
                try Self.checkCSS(css, stylesheet: true)
            }
            if open.isEmpty { rootClosed = true }
        }

        private mutating func startTag() throws {
            index += 1
            let element = name()
            let local = Self.localName(element)
            guard !element.isEmpty, !rootClosed, style == nil else { throw Refusal.malformed }
            if open.isEmpty, element != "svg" { throw Refusal.notSVG }
            guard !ExtensionSVGPreview.forbiddenElements.contains(local) else { throw Refusal.forbiddenElement }
            guard !ExtensionSVGPreview.expensiveElements.contains(local), !local.hasPrefix("fe") else { throw Refusal.expensiveEffect }
            elements += 1
            guard elements <= maximumElements else { throw Refusal.tooManyElements }
            var id: String?
            var selfClosing = false
            while true {
                let hadSpace = skipWhitespace()
                guard index < bytes.count else { throw Refusal.malformed }
                if bytes[index] == UInt8(ascii: ">") { index += 1; break }
                if starts(with: "/>") { index += 2; selfClosing = true; break }
                guard hadSpace else { throw Refusal.malformed }
                let attribute = name()
                guard !attribute.isEmpty else { throw Refusal.malformed }
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: "=") else { throw Refusal.malformed }
                index += 1
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") || bytes[index] == UInt8(ascii: "'") else { throw Refusal.malformed }
                let quote = bytes[index]
                let start = index + 1
                guard let close = bytes[start...].firstIndex(of: quote) else { throw Refusal.malformed }
                let raw = bytes[start..<close]
                guard !raw.contains(UInt8(ascii: "<")) else { throw Refusal.malformed }
                index = close + 1
                let value = String(decoding: try Self.decodeReferences(raw), as: UTF8.self)
                try Self.checkAttribute(attribute, value)
                let attributeLocal = Self.localName(attribute)
                if attribute == "id" || attribute == "xml:id" { id = value }
                if local == "use", attributeLocal == "href" { useTargets.append(String(value.trimmingCharacters(in: .whitespaces).dropFirst())) }
            }
            let usesSelf = local == "use"
            if usesSelf, !open.isEmpty { open[open.count - 1].containsUse = true }
            if selfClosing {
                try close((element, id, usesSelf))
            } else {
                open.append((element, id, usesSelf))
                guard open.count <= maximumDepth else { throw Refusal.tooDeep }
                if local == "style" { style = [] }
            }
        }

        /// Reads an ASCII name of letters, digits, `:`, `_`, `-` and `.`; empty when none is there.
        private mutating func name() -> String {
            let start = index
            while index < bytes.count, Self.isNameByte(bytes[index]) { index += 1 }
            return String(decoding: bytes[start..<index], as: UTF8.self)
        }

        @discardableResult
        private mutating func skipWhitespace() -> Bool {
            let start = index
            while index < bytes.count, Self.isWhitespace(bytes[index]) { index += 1 }
            return index > start
        }

        static func isWhitespace(_ byte: UInt8) -> Bool { [0x20, 0x09, 0x0A, 0x0D].contains(byte) }

        static func isNameByte(_ byte: UInt8) -> Bool {
            (byte >= 0x61 && byte <= 0x7A) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x30 && byte <= 0x39) || [0x3A, 0x5F, 0x2D, 0x2E].contains(byte)
        }

        /// The lowercased part of a name after its namespace prefix.
        static func localName(_ name: String) -> String {
            String(name.split(separator: ":", omittingEmptySubsequences: false).last ?? "").lowercased()
        }

        /// Replaces the five predefined entities and numeric character references, so later checks see
        /// what a renderer would. Any other entity is refused, since without a DTD it is undefined.
        static func decodeReferences(_ run: ArraySlice<UInt8>) throws -> [UInt8] {
            guard run.contains(UInt8(ascii: "&")) else { return Array(run) }
            var output: [UInt8] = []
            var position = run.startIndex
            while position < run.endIndex {
                guard run[position] == UInt8(ascii: "&") else { output.append(run[position]); position += 1; continue }
                guard let semicolon = run[position...].prefix(12).firstIndex(of: UInt8(ascii: ";")) else { throw Refusal.malformed }
                let reference = String(decoding: run[(position + 1)..<semicolon], as: UTF8.self)
                switch reference {
                case "lt": output.append(UInt8(ascii: "<"))
                case "gt": output.append(UInt8(ascii: ">"))
                case "amp": output.append(UInt8(ascii: "&"))
                case "quot": output.append(UInt8(ascii: "\""))
                case "apos": output.append(UInt8(ascii: "'"))
                default:
                    guard reference.hasPrefix("#") else { throw Refusal.malformed }
                    let digits = reference.dropFirst()
                    let value = digits.hasPrefix("x") ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits, radix: 10)
                    guard let value, value != 0, let scalar = Unicode.Scalar(value) else { throw Refusal.malformed }
                    output.append(contentsOf: Array(String(Character(scalar)).utf8))
                }
                position = semicolon + 1
            }
            return output
        }

        /// Refuses event handlers, URL attributes and references outside the document, checks every value
        /// as CSS, and bounds sizes.
        static func checkAttribute(_ attribute: String, _ value: String) throws {
            let local = localName(attribute)
            if local.hasPrefix("on") { throw Refusal.eventAttribute }
            if local == "src" || attribute.lowercased() == "xml:base" { throw Refusal.externalReference }
            if local == "href", !value.trimmingCharacters(in: .whitespaces).hasPrefix("#") { throw Refusal.externalReference }
            if expensiveAttributes.contains(local) { throw Refusal.expensiveEffect }
            try checkCSS(Array(value.utf8), stylesheet: local == "style")
            switch local {
            case "width", "height": try checkLength(value)
            case "viewbox": try checkViewBox(value)
            default: break
            }
        }

        /// Refuses CSS that could load anything or hide what it says behind escapes, and in a stylesheet (a
        /// `<style>` element or `style` attribute) any mention of filters or masks.
        static func checkCSS(_ css: [UInt8], stylesheet: Bool) throws {
            guard !css.contains(UInt8(ascii: "\\")) else { throw Refusal.forbiddenStyle }
            var text = String(decoding: css, as: UTF8.self).lowercased()
            while let open = text.range(of: "/*") {
                guard let close = text.range(of: "*/", range: open.upperBound..<text.endIndex) else { throw Refusal.forbiddenStyle }
                text.replaceSubrange(open.lowerBound..<close.upperBound, with: " ")
            }
            if text.contains("@import") || text.contains("@font-face") { throw Refusal.forbiddenStyle }
            if fetchingFunctions.contains(where: text.contains) { throw Refusal.externalReference }
            var rest = Substring(text)
            while let found = rest.range(of: "url") {
                var after = rest[found.upperBound...].drop(while: \.isWhitespace)
                if after.first == "(" {
                    after = after.dropFirst().drop { $0.isWhitespace || $0 == "\"" || $0 == "'" }
                    guard after.first == "#" else { throw Refusal.externalReference }
                }
                rest = rest[found.upperBound...]
            }
            if stylesheet, expensiveAttributes.contains(where: text.contains) { throw Refusal.expensiveEffect }
        }

        /// The CSS units a length may use, in pixels each. A percentage is relative and never grows the canvas.
        static let units: [(suffix: String, pixels: Double)] = [
            ("px", 1), ("pt", 4.0 / 3), ("pc", 16), ("mm", 96 / 25.4), ("cm", 96 / 2.54), ("in", 96), ("em", 16), ("ex", 8), ("%", 0)
        ]

        static func checkLength(_ value: String) throws {
            let trimmed = value.trimmingCharacters(in: .whitespaces).lowercased()
            if trimmed == "auto" { return }
            let unit = units.first { trimmed.hasSuffix($0.suffix) }
            guard let number = Double(trimmed.dropLast(unit?.suffix.count ?? 0)), number.isFinite else { throw Refusal.malformed }
            guard abs(number) * (unit.map { max($0.pixels, 1) } ?? 1) <= maximumDimension else { throw Refusal.dimensionTooLarge }
        }

        static func checkViewBox(_ value: String) throws {
            let numbers = value.split { $0.isWhitespace || $0 == "," }.map { Double($0) }
            guard numbers.count == 4, numbers.allSatisfy({ $0?.isFinite == true }) else { throw Refusal.malformed }
            guard numbers.allSatisfy({ abs($0 ?? .infinity) <= maximumDimension }) else { throw Refusal.dimensionTooLarge }
        }
    }
}
