import Foundation

/// Website rules for Focus sessions. A rule is a bare host such as `x.com`; it blocks that host
/// and every subdomain, never a host that merely contains it (`notx.com`, `x.com.example.test`).
/// Rules and visited hosts go through the same normalization: lowercase, no trailing dot, and
/// internationalized labels in their ASCII (`xn--`) form, so `bücher.de` matches `xn--bcher-kva.de`.
public enum FocusHost {
    static let maximumLength = 253

    /// The rule for what the owner typed (`https://www.x.com/home`, `X.com`, `*.reddit.com`), or nil
    /// when it is not a usable host. A leading `www.` is dropped, so the rule also covers the bare domain.
    public static func rule(from input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let scheme = text.range(of: "://") { text = String(text[scheme.upperBound...]) }
        if let end = text.firstIndex(where: { "/?#".contains($0) }) { text = String(text[..<end]) }
        if let at = text.lastIndex(of: "@") { text = String(text[text.index(after: at)...]) }
        if let colon = text.lastIndex(of: ":") { text = String(text[..<colon]) }
        if text.hasPrefix("*.") { text.removeFirst(2) }
        guard var host = normalized(text) else { return nil }
        if host.hasPrefix("www."), host.split(separator: ".").count > 2 { host.removeFirst(4) }
        return host
    }

    /// The normalized host of a page address, for http and https pages only.
    public static func host(ofPageAddress address: String) -> String? {
        guard let components = URLComponents(string: address),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host else { return nil }
        return normalized(host)
    }

    /// Whether `host` is `rule` or one of its subdomains. Both must already be normalized.
    public static func matches(_ host: String, rule: String) -> Bool {
        host == rule || host.hasSuffix("." + rule)
    }

    /// Lowercases, drops one trailing dot, converts non-ASCII labels to Punycode and checks every
    /// label; nil for anything that is not a dotted host name.
    static func normalized(_ raw: String) -> String? {
        var text = raw.precomposedStringWithCompatibilityMapping.lowercased()
        if text.hasSuffix(".") { text.removeLast() }
        guard !text.isEmpty, text.count <= maximumLength else { return nil }
        var labels: [String] = []
        for part in text.split(separator: ".", omittingEmptySubsequences: false) {
            guard let label = asciiLabel(String(part)) else { return nil }
            labels.append(label)
        }
        guard labels.count >= 2 else { return nil }
        let host = labels.joined(separator: ".")
        return host.count <= maximumLength ? host : nil
    }

    /// One label in ASCII form, or nil when it is empty, too long or has characters a host can't.
    static func asciiLabel(_ label: String) -> String? {
        guard !label.isEmpty else { return nil }
        let ascii: String
        if label.unicodeScalars.allSatisfy(\.isASCII) {
            ascii = label
        } else {
            guard label.unicodeScalars.allSatisfy({ $0.isASCII ? isHostCharacter($0) : isLetterOrMark($0) }),
                  let encoded = Punycode.encode(label) else { return nil }
            ascii = "xn--" + encoded
        }
        guard ascii.count <= 63, ascii.unicodeScalars.allSatisfy(isHostCharacter),
              !ascii.hasPrefix("-"), !ascii.hasSuffix("-") else { return nil }
        return ascii
    }

    static func isHostCharacter(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "-"
    }

    /// Non-ASCII characters an internationalized label may hold: letters, combining marks and digits.
    static func isLetterOrMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .lowercaseLetter, .uppercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .nonspacingMark, .spacingMark, .decimalNumber: return true
        default: return false
        }
    }
}

/// RFC 3492 Punycode encoding of a single label, enough to compare internationalized host names.
enum Punycode {
    static let base = 36, tMin = 1, tMax = 26, skew = 38, damp = 700, initialBias = 72, initialN = 128

    /// The encoded label without its `xn--` prefix, or nil on overflow.
    static func encode(_ input: String) -> String? {
        let scalars = input.unicodeScalars.map { Int($0.value) }
        var output = scalars.filter { $0 < 0x80 }.map { Character(Unicode.Scalar(UInt8($0))) }
        let basicCount = output.count
        var handled = basicCount
        if basicCount > 0 { output.append("-") }
        var n = initialN, delta = 0, bias = initialBias
        while handled < scalars.count {
            guard let m = scalars.filter({ $0 >= n }).min() else { return nil }
            let (product, overflow) = (m - n).multipliedReportingOverflow(by: handled + 1)
            guard !overflow else { return nil }
            delta += product
            n = m
            for c in scalars {
                if c < n { delta += 1 }
                if c == n {
                    var q = delta, k = base
                    while true {
                        let t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias)
                        if q < t { break }
                        output.append(digit(t + (q - t) % (base - t)))
                        q = (q - t) / (base - t)
                        k += base
                    }
                    output.append(digit(q))
                    bias = adapt(delta, handled + 1, handled == basicCount)
                    delta = 0
                    handled += 1
                }
            }
            delta += 1
            n += 1
        }
        return String(output)
    }

    static func digit(_ value: Int) -> Character {
        Character(Unicode.Scalar(UInt8(value < 26 ? value + 97 : value + 22)))
    }

    static func adapt(_ delta: Int, _ count: Int, _ first: Bool) -> Int {
        var delta = first ? delta / damp : delta / 2
        delta += delta / count
        var k = 0
        while delta > ((base - tMin) * tMax) / 2 {
            delta /= base - tMin
            k += base
        }
        return k + (base - tMin + 1) * delta / (delta + skew)
    }
}
