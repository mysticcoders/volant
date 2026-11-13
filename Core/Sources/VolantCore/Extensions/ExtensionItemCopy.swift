import Foundation

/// What a list extension's row puts on the clipboard when the owner chooses it, for an extension whose
/// manifest declares the `clipboard-write` permission. Either `text`, at most 64 KB of UTF-8 copied as
/// plain text, or a `url` on a declared host with a `type`, which Volant downloads through its fetch
/// helper only when the owner chooses the copy, checks against that type, and copies as text (`svg`,
/// `text`) or as an image (`png`, `jpeg`, `webp`, `ico`, `gif`, `bmp`, `avif`, or `image` for any of
/// those and TIFF and HEIC). The module never sees the downloaded bytes, and nothing is fetched while
/// listing. `title` names the entry in the row's Actions menu.
public struct ExtensionItemCopy: Codable, Hashable, Sendable {
    public static let permission = "clipboard-write"
    public static let maximumTextBytes = 64 * 1024
    public static let maximumTitleLength = 40
    /// The largest download a copy accepts, the same as any extension fetch.
    public static let maximumDownloadBytes = ExtensionNetwork.maximumResponseBytes

    public var text: String?
    public var url: String?
    public var type: String?
    public var title: String?

    public init(text: String? = nil, url: String? = nil, type: String? = nil, title: String? = nil) {
        self.text = text; self.url = url; self.type = type; self.title = title
    }

    /// What a downloaded copy must be. SVG and text are copied as plain text; the others as an image.
    /// Each explicit image kind accepts only its own format. `image` accepts any format Volant decodes,
    /// identified by its signature, and SVG markup, which it copies as text like `svg`.
    public enum Kind: String, CaseIterable, Sendable {
        case svg, png, jpeg, webp, ico, gif, bmp, avif, image, text

        public var isImage: Bool { ![.svg, .text].contains(self) }

        /// The image formats this kind accepts; empty for SVG and text.
        public var formats: Set<ExtensionImageFormat> {
            switch self {
            case .png: [.png]
            case .jpeg: [.jpeg]
            case .webp: [.webp]
            case .ico: [.ico]
            case .gif: [.gif]
            case .bmp: [.bmp]
            case .avif: [.avif]
            case .image: Set(ExtensionImageFormat.allCases)
            case .svg, .text: []
            }
        }

        /// The kind's name in messages, such as "PNG image".
        public var displayName: String {
            switch self {
            case .svg: String(localized: "SVG", table: "Core", comment: "Kind of file an extension row copies")
            case .png: String(localized: "PNG image", table: "Core", comment: "Kind of file an extension row copies")
            case .jpeg: String(localized: "JPEG image", table: "Core", comment: "Kind of file an extension row copies")
            case .webp: String(localized: "WebP image", table: "Core", comment: "Kind of file an extension row copies")
            case .ico: String(localized: "ICO image", table: "Core", comment: "Kind of file an extension row copies")
            case .gif: String(localized: "GIF image", table: "Core", comment: "Kind of file an extension row copies")
            case .bmp: String(localized: "BMP image", table: "Core", comment: "Kind of file an extension row copies")
            case .avif: String(localized: "AVIF image", table: "Core", comment: "Kind of file an extension row copies")
            case .image: String(localized: "image", table: "Core", comment: "Kind of file an extension row copies, in the middle of a sentence")
            case .text: String(localized: "text", table: "Core", comment: "Kind of file an extension row copies, in the middle of a sentence")
            }
        }
    }

    /// The kind of a `url` copy; nil for a `text` copy.
    public var kind: Kind? { url == nil ? nil : type.flatMap(Kind.init(rawValue:)) }

    /// The Actions menu entry's title: the extension's, or "Copy".
    public var displayTitle: String {
        title ?? String(localized: "Copy", table: "Core", comment: "Default Actions menu title for an extension row's copy")
    }

    /// The confirmation shown after copying: "Copied SVG" for a title such as "Copy SVG", otherwise what
    /// was copied.
    public var confirmation: String {
        if let title, title.hasPrefix("Copy "), title.count > 5 {
            let rest = String(title.dropFirst(5))
            return String(localized: "Copied \(rest, format: .verbatim)", table: "Core", comment: "Launcher feedback after copying; the value is the rest of the extension's Copy title, such as SVG")
        }
        switch kind {
        case .svg?: return String(localized: "Copied SVG", table: "Core", comment: "Launcher feedback after an extension row copies SVG markup")
        case let kind? where kind.isImage: return String(localized: "Copied image", table: "Core", comment: "Launcher feedback after an extension row copies an image")
        default: return String(localized: "Copied text", table: "Core", comment: "Launcher feedback after an extension row copies text")
        }
    }

    /// The copy as Volant keeps it, or nil to drop it: exactly one of `text` (non-empty, at most 64 KB of
    /// UTF-8) or `url` (permitted for `hosts`, the manifest's declared hosts, with a known `type`). The
    /// title becomes one trimmed line of at most 40 characters, or nil for the default.
    public func sanitized(hosts: Set<String>) -> ExtensionItemCopy? {
        let title = title.map { line in
            String(line.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces).prefix(Self.maximumTitleLength))
                .trimmingCharacters(in: .whitespaces)
        }.flatMap { $0.isEmpty ? nil : $0 }
        switch (text, url) {
        case (let text?, nil):
            guard !text.isEmpty, text.utf8.count <= Self.maximumTextBytes else { return nil }
            return ExtensionItemCopy(text: text, title: title)
        case (nil, let url?):
            guard let type, let kind = Kind(rawValue: type), ExtensionNetwork.permittedURL(url, hosts: hosts) != nil else { return nil }
            return ExtensionItemCopy(url: url, type: kind.rawValue, title: title)
        default:
            return nil
        }
    }

    static let utf8ByteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]

    /// The text to copy from downloaded `svg` or `text` bytes: valid UTF-8 without NUL characters, and for
    /// SVG an `<svg` root element (see `startsWithSVGRoot`). A leading byte order mark is removed here,
    /// since Foundation keeps it on some macOS versions and drops it on others. Nil when the bytes are not
    /// that. The markup is never parsed or rendered.
    public static func downloadedText(_ data: Data, kind: Kind) -> String? {
        let body = data.starts(with: utf8ByteOrderMark) ? data.dropFirst(utf8ByteOrderMark.count) : data[...]
        guard !kind.isImage, !body.isEmpty, !body.contains(0), let text = String(data: Data(body), encoding: .utf8) else { return nil }
        guard kind == .svg else { return text }
        return startsWithSVGRoot(text) ? text : nil
    }

    /// The most XML prologs, DOCTYPEs and comments allowed before the root, so a scan stays short.
    static let maximumSVGPreambleItems = 16

    /// Whether `text`'s root element is `<svg`. Before it may come whitespace and up to
    /// `maximumSVGPreambleItems` of: an XML prolog (`<?xml … ?>`), comments (`<!-- … -->`) and a
    /// `<!DOCTYPE svg …>` naming `svg` as its root. A DOCTYPE with an internal subset (`[ … ]`) is refused,
    /// since it can declare entities for whatever later reads the copy, and so is any other DOCTYPE, such
    /// as HTML's. This only scans text; the markup is never parsed.
    static func startsWithSVGRoot(_ text: String) -> Bool {
        var rest = Substring(text)
        func skipWhitespace() { rest = rest.drop { $0.isWhitespace } }
        func skip(past terminator: String) -> Bool {
            guard let end = rest.range(of: terminator) else { return false }
            rest = rest[end.upperBound...]; return true
        }
        skipWhitespace()
        for _ in 0..<maximumSVGPreambleItems {
            if rest.hasPrefix("<?xml") {
                guard skip(past: "?>") else { return false }
            } else if rest.hasPrefix("<!--") {
                rest = rest.dropFirst(4)
                guard skip(past: "-->") else { return false }
            } else if rest.hasPrefix("<!DOCTYPE") {
                let declaration = rest.dropFirst(9)
                guard let end = declaration.firstIndex(of: ">"), !declaration[..<end].contains("["),
                      declaration[..<end].split(whereSeparator: \.isWhitespace).first == "svg" else { return false }
                rest = declaration[declaration.index(after: end)...]
            } else {
                break
            }
            skipWhitespace()
        }
        guard rest.hasPrefix("<svg"), let next = rest.dropFirst(4).first else { return false }
        return next.isWhitespace || next == ">" || next == "/"
    }

    /// Whether downloaded bytes start with the signature of a format `kind` accepts. The app then decodes
    /// them with ImageIO, which must report that format, before copying; this refuses mismatches early.
    public static func hasImageSignature(_ data: Data, kind: Kind) -> Bool {
        ExtensionImageFormat.detect(data).map(kind.formats.contains) ?? false
    }

    /// The text to copy for an `image` download that is SVG markup rather than a raster image, under the
    /// same rules as an `svg` copy; nil for anything else, including bytes with an image signature.
    public static func imageKindSVG(_ data: Data) -> String? {
        ExtensionImageFormat.detect(data) == nil ? downloadedText(data, kind: .svg) : nil
    }
}

/// Why a row's copy put nothing on the clipboard.
public enum ExtensionCopyError: Error, LocalizedError, Equatable {
    case notAllowed, hostNotApproved(String), unavailable(Int), tooLarge, wrongType(ExtensionItemCopy.Kind)
    public var errorDescription: String? {
        switch self {
        case .notAllowed:
            return String(localized: "This extension isn’t allowed to copy to your clipboard.", table: "Core", comment: "Extension copy error")
        case .hostNotApproved(let host):
            return String(localized: "Allow access to \(host, format: .verbatim) to copy this.", table: "Core", comment: "Extension copy error; the value is a web host")
        case .unavailable(let status) where status > 0:
            return String(localized: "Couldn’t download it: the server answered \(status, specifier: "%lld"). Nothing was copied.", table: "Core",
                          comment: "Extension copy error; the number is an HTTP status code")
        case .unavailable:
            return String(localized: "Couldn’t download it. Check your connection; files over 512 KB can’t be copied. Nothing was copied.", table: "Core",
                          comment: "Extension copy error")
        case .tooLarge:
            return String(localized: "It’s larger than 512 KB, so nothing was copied.", table: "Core", comment: "Extension copy error")
        case .wrongType(let kind):
            return String(localized: "The download isn’t a valid \(kind.displayName, format: .verbatim), so nothing was copied.", table: "Core",
                          comment: "Extension copy error; the value is a kind of file such as PNG image")
        }
    }
}

extension ExtensionItem {
    /// Whether Return performs the row's copy: it has one, no link to open and no action Return runs
    /// instead. A row with a link keeps opening it, and its copy is in the Actions menu.
    public var returnCopies: Bool { copy != nil && url == nil && primaryAction == nil }
}

extension ExtensionManifest {
    /// The hosts a row's `copy` may download from, or nil when the manifest does not declare
    /// `clipboard-write`, so every row's copy is dropped while sanitizing.
    public var rowCopyHosts: Set<String>? { wantsClipboardWrite ? Set(declaredHosts) : nil }
}
