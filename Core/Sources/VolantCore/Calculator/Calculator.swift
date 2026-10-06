import Foundation

/// Arithmetic evaluator: + - * / ^ mod, parentheses, unary minus, factorial, pi, e, percentages and
/// the functions in `functions`. Pure; no NSExpression.
///
/// Trigonometry takes radians unless an angle is marked in degrees ("sin(90°)", "cos 60 deg").
/// Everyday phrasings read as their symbols: "square root of 625", "cube root of 27", "2 power 10",
/// "2 to the power of 10", "5 squared", "3 cubed", "5 factorial". A function name binds to the
/// value right after it, so "sqrt 16 + 9" is 13. Results that are not real numbers, such as
/// "sqrt(-1)", give no answer.
///
/// Functions in `multiFunctions` take several arguments: "max(3, 7, 5)", "atan2(1, 1)", "nCr(10, 3)",
/// "log(8, 2)", "round(3.14159, 2)". A comma separates arguments when it cannot be thousands
/// grouping, so "max(1,5)" and "max(1, 500)" both work; ";" always separates, which suits locales
/// with a decimal comma. max and min need at least two arguments, so an ambiguous "max(1,500)"
/// gives no answer rather than a wrong one. The list functions avg (average, mean), sum, median,
/// range and stdev (the sample standard deviation, as spreadsheets compute it) follow the same
/// rule, and also read as phrases: "average of 4, 8 and 15", "sum of 3; 5".
///
/// Integers may be written in hexadecimal, binary or octal with a prefix: "0x1F + 0b1010", "0o17".
///
/// `%` is a percentage, as people write it: "52% of 900", "20% off 80", "15% tip on 42", and
/// "19 + 47%" or "100 - 10%" add or subtract that share of the left side. Elsewhere `%` divides by
/// 100, so "200 * 15%" is 30. The words "percent" and "pct" read as `%`. Remainder is `mod`.
public enum Calculator {
    public enum CalcError: Error { case syntax, divisionByZero }

    private enum Token: Equatable {
        case number(Double), op(Character), lparen, rparen, ident(String), comma, call(String, Int)
    }

    /// Numbers follow `locale`: its decimal and grouping separators, plus scientific notation and
    /// magnitudes ("10K", "2.5 million"). See `NumberLiteral`.
    public static func evaluate(_ text: String, locale: Locale = .current) -> Double? {
        guard looksNumeric(text) else { return nil }
        do {
            let tokens = try tokenize(phrases(text), separators: NumberLiteral.Separators(locale))
            guard !tokens.isEmpty else { return nil }
            let rpn = try toRPN(tokens)
            let value = try evalRPN(rpn)
            return value.isFinite ? value : nil
        } catch {
            return nil
        }
    }

    static let functions: [String: (Double) -> Double] = [
        "sqrt": { $0.squareRoot() }, "cbrt": { Foundation.cbrt($0) }, "abs": { Swift.abs($0) },
        "round": { $0.rounded() }, "floor": { $0.rounded(.down) }, "ceil": { $0.rounded(.up) },
        "sin": { snap(Foundation.sin($0)) }, "cos": { snap(Foundation.cos($0)) }, "tan": { snap(Foundation.tan($0)) },
        "cot": { 1 / Foundation.tan($0) }, "sec": { 1 / Foundation.cos($0) }, "csc": { 1 / Foundation.sin($0) },
        "asin": { Foundation.asin($0) }, "acos": { Foundation.acos($0) }, "atan": { Foundation.atan($0) },
        "sinh": { Foundation.sinh($0) }, "cosh": { Foundation.cosh($0) }, "tanh": { Foundation.tanh($0) },
        "asinh": { Foundation.asinh($0) }, "acosh": { Foundation.acosh($0) }, "atanh": { Foundation.atanh($0) },
        "ln": { Foundation.log($0) }, "log": { Foundation.log10($0) }, "log10": { Foundation.log10($0) },
        "log2": { Foundation.log2($0) }, "exp": { Foundation.exp($0) }
    ]

    /// Functions of several arguments; nil marks arguments outside the function's domain.
    static let multiFunctions: [String: ([Double]) -> Double?] = [
        "max": { $0.count >= 2 ? $0.max() : nil }, "min": { $0.count >= 2 ? $0.min() : nil },
        "atan2": { $0.count == 2 ? Foundation.atan2($0[0], $0[1]) : nil }, "hypot": { $0.count == 2 ? Foundation.hypot($0[0], $0[1]) : nil },
        "pow": { $0.count == 2 ? Foundation.pow($0[0], $0[1]) : nil },
        "log": { $0.count == 2 && $0[1] > 0 && $0[1] != 1 ? Foundation.log($0[0]) / Foundation.log($0[1]) : nil },
        "round": { args in
            guard args.count == 2, let digits = whole(args[1]), (-10...15).contains(digits) else { return nil }
            let scale = Foundation.pow(10, Double(digits))
            return (args[0] * scale).rounded() / scale
        },
        "gcd": { args in
            guard args.count == 2, let a = whole(args[0]), let b = whole(args[1]) else { return nil }
            return Double(gcd(abs(a), abs(b)))
        },
        "lcm": { args in
            guard args.count == 2, let a = whole(args[0]), let b = whole(args[1]) else { return nil }
            let divisor = gcd(abs(a), abs(b))
            return divisor == 0 ? 0 : Double(abs(a) / divisor) * Double(abs(b))
        },
        "ncr": { choose($0, ordered: false) }, "choose": { choose($0, ordered: false) },
        "npr": { choose($0, ordered: true) }, "perm": { choose($0, ordered: true) },
        "avg": { mean($0) }, "average": { mean($0) }, "mean": { mean($0) },
        "sum": { $0.count >= 2 ? $0.reduce(0, +) : nil },
        "median": { median($0) },
        "range": { $0.count >= 2 ? $0.max()! - $0.min()! : nil },
        "stdev": { deviation($0) }, "stddev": { deviation($0) }
    ]

    /// Names that read as list phrases: "average of 1, 2 and 3".
    private static let listNames = ["avg", "average", "mean", "sum", "median", "range", "stdev", "stddev"]

    private static func mean(_ values: [Double]) -> Double? {
        values.count >= 2 ? values.reduce(0, +) / Double(values.count) : nil
    }

    private static func median(_ values: [Double]) -> Double? {
        guard values.count >= 2 else { return nil }
        let sorted = values.sorted(), middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }

    /// Sample standard deviation, dividing by n - 1.
    private static func deviation(_ values: [Double]) -> Double? {
        guard let average = mean(values) else { return nil }
        let squares = values.reduce(0) { $0 + ($1 - average) * ($1 - average) }
        return (squares / Double(values.count - 1)).squareRoot()
    }

    /// A prefixed integer literal at `start`: "0x1F", "0b1010", "0o17". Returns nil when no prefix
    /// starts there, and throws when the digits after one are malformed or too large to be exact.
    static func prefixedInteger(_ chars: [Character], from start: Int) throws -> (Double, Int)? {
        guard chars[start] == "0", start + 1 < chars.count else { return nil }
        let radix: Int
        switch chars[start + 1] {
        case "x", "X": radix = 16
        case "b", "B": radix = 2
        case "o", "O": radix = 8
        default: return nil
        }
        var end = start + 2
        while end < chars.count, chars[end].isASCII, chars[end].hexDigitValue.map({ $0 < radix }) ?? false { end += 1 }
        guard end > start + 2 else { return nil }
        guard end == chars.count || !(chars[end].isLetter || chars[end].isNumber),
              end - start - 2 <= 64, let value = UInt64(String(chars[(start + 2)..<end]), radix: radix),
              value <= 1 << 53 else { throw CalcError.syntax }
        return (Double(value), end)
    }

    /// Trigonometry of multiples of pi lands a rounding error away from zero ("sin(pi)" is about
    /// 1.2e-16); those read as zero, so tiny results can show in scientific notation without noise.
    private static func snap(_ value: Double) -> Double {
        abs(value) < 1e-15 ? 0 : value
    }

    private static func whole(_ value: Double) -> Int? {
        value == value.rounded() && abs(value) < 9e15 ? Int(value) : nil
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }

    /// Combinations ("nCr") or permutations ("nPr") of whole numbers with 0 ≤ r ≤ n.
    private static func choose(_ args: [Double], ordered: Bool) -> Double? {
        guard args.count == 2, let n = whole(args[0]), let r = whole(args[1]), n >= 0, (0...n).contains(r), n <= 10_000 else { return nil }
        var result = 1.0
        for step in 0..<r {
            result *= Double(n - step)
            if !ordered { result /= Double(step + 1) }
        }
        return ordered ? result : result.rounded()
    }

    /// Rewrites everyday phrasings into the symbols the tokenizer reads. A list phrase ("sum of
    /// 3, 5 and 8") becomes a call, with "and" separating like ";".
    private static func phrases(_ text: String) -> String {
        var value = text
        let list = "^\\s*(?:the\\s+)?(" + listNames.joined(separator: "|") + ")\\s+of\\s+(.+?)\\s*$"
        if let match = value.range(of: list, options: [.regularExpression, .caseInsensitive]) {
            let name = value[match].replacingOccurrences(of: list, with: "$1", options: [.regularExpression, .caseInsensitive])
            let items = value[match].replacingOccurrences(of: list, with: "$2", options: [.regularExpression, .caseInsensitive])
            value = name + "(" + items.replacingOccurrences(of: #"\s+and\s+"#, with: "; ", options: [.regularExpression, .caseInsensitive]) + ")"
        }
        for (pattern, replacement) in [(#"\bsquare\s+root\s+of\b"#, " sqrt "), (#"\bcube\s+root\s+of\b"#, " cbrt "),
                                       (#"\bto\s+the\s+power\s+of\b"#, " ^ "), (#"\bpower\b"#, " ^ "),
                                       (#"\bsquared\b"#, " ^ 2 "), (#"\bcubed\b"#, " ^ 3 "), (#"\bfactorial\b"#, " ! "),
                                       (#"\b(percent|pct)\b"#, " % ")] {
            value = value.replacingOccurrences(of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive])
        }
        return value
    }

    /// Closes parentheses left open at the end, as people type "2 * (3 + 4" and stop. Extra
    /// closing parentheses are left alone, so they still give no answer.
    public static func closingParentheses(_ text: String) -> String {
        let open = text.filter { $0 == "(" }.count - text.filter { $0 == ")" }.count
        return open > 0 ? text + String(repeating: ")", count: open) : text
    }

    /// Cheap gate so ordinary app names never reach the parser.
    public static func looksNumeric(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return false }
        let allowed = CharacterSet(charactersIn: "0123456789.,;+-*/^%()!°").union(.letters).union(.whitespaces)
        guard t.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        return t.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) } || t.lowercased().contains("pi")
            || t.range(of: #"\be\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Whole numbers print in full while a Double holds them exactly (up to 2^53). Larger values and
    /// non-zero values below a millionth use scientific notation with ten decimals at most
    /// ("1.8446744074e19", "1.5e-9"), which the calculator reads back, so no digit is invented.
    public static func format(_ value: Double, locale: Locale = .current) -> String {
        if value.isNaN || value.isInfinite { return "undefined" }
        if value == value.rounded() && abs(value) <= exactIntegers { return String(Int64(value)) }
        if let (mantissa, exponent) = scientific(value) { return format(mantissa, locale: locale) + "e\(exponent)" }
        let f = NumberFormatter()
        f.maximumFractionDigits = 10
        f.minimumFractionDigits = 0
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.locale = locale
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// The largest magnitude below which every whole number is exact in a Double.
    static let exactIntegers = 9_007_199_254_740_992.0

    /// A mantissa from 1 to 10 (rounded to ten decimals) and its power of ten, for values too large
    /// to print exactly or too small to show in ten decimal places; nil for everything else.
    static func scientific(_ value: Double) -> (Double, Int)? {
        let magnitude = abs(value)
        guard magnitude > exactIntegers || (magnitude > 0 && magnitude < 1e-6) else { return nil }
        var exponent = Int(Foundation.floor(Foundation.log10(magnitude)))
        var mantissa = (value / Foundation.pow(10, Double(exponent)) * 1e10).rounded() / 1e10
        if abs(mantissa) >= 10 {
            mantissa /= 10
            exponent += 1
        }
        return (mantissa, exponent)
    }

    /// Word operators, each one character on the operator stack: "of", "off", "on" ("tip on" reads the
    /// same) and "mod".
    private static let words: [String: Character] = ["of": "o", "off": "f", "on": "n", "mod": "m"]

    private static func tokenize(_ text: String, separators: NumberLiteral.Separators) throws -> [Token] {
        var tokens: [Token] = []
        var calls: [Bool] = []
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch.isWhitespace { i += 1; continue }
            if let (v, j) = try prefixedInteger(chars, from: i) {
                tokens.append(.number(v)); i = j; continue
            }
            if ch.isNumber || ch == separators.decimal {
                let inCall = calls.last == true
                guard let (v, j) = NumberLiteral.scan(chars, from: i, separators)
                        ?? (inCall ? NumberLiteral.scan(chars, from: i, separators, grouping: false) : nil),
                      j == chars.count || !(chars[j].isNumber || chars[j] == separators.decimal || (chars[j] == separators.grouping && !inCall)) else {
                    throw CalcError.syntax
                }
                tokens.append(.number(v)); i = j; continue
            }
            if ch.isLetter {
                var j = i
                while j < chars.count && chars[j].isLetter { j += 1 }
                var k = j
                while k < chars.count && chars[k].isASCII && chars[k].isNumber { k += 1 }
                if k > j, functions[String(chars[i..<k]).lowercased()] != nil || multiFunctions[String(chars[i..<k]).lowercased()] != nil { j = k }
                let word = String(chars[i..<j]).lowercased()
                i = j
                if word == "tip" {
                    while i < chars.count && chars[i].isWhitespace { i += 1 }
                    var k = i
                    while k < chars.count && chars[k].isLetter { k += 1 }
                    guard String(chars[i..<k]).lowercased() == "on" else { throw CalcError.syntax }
                    tokens.append(.op("n")); i = k; continue
                }
                if ["deg", "degree", "degrees"].contains(word) { tokens.append(.op("d")); continue }
                if ["rad", "radian", "radians"].contains(word) { continue }
                if let scale = NumberLiteral.words[word] {
                    guard case .number(let v)? = tokens.last else { throw CalcError.syntax }
                    tokens[tokens.count - 1] = .number(v * scale); continue
                }
                tokens.append(words[word].map { .op($0) } ?? .ident(word)); continue
            }
            switch ch {
            case "(":
                if case .ident(let name)? = tokens.last, functions[name] != nil || multiFunctions[name] != nil { calls.append(true) }
                else { calls.append(false) }
                tokens.append(.lparen)
            case ")":
                guard calls.popLast() != nil else { throw CalcError.syntax }
                tokens.append(.rparen)
            case ",", ";":
                guard calls.last == true else { throw CalcError.syntax }
                tokens.append(.comma)
            case "+", "-", "*", "/", "^": tokens.append(.op(ch))
            case "%": tokens.append(.op("p"))
            case "!": tokens.append(.op("!"))
            case "°": tokens.append(.op("d"))
            default: throw CalcError.syntax
            }
            i += 1
        }
        return tokens
    }

    /// Unary minus sits between exponent and multiplication, so "-2^2" is -(2^2) as in written
    /// math, while "-2 * 3" and "2^-1" still read naturally.
    private static func precedence(_ op: Character) -> Int {
        switch op {
        case "^": return 4
        case "u": return 3
        case "*", "/", "o", "f", "n", "m": return 2
        default: return 1
        }
    }

    /// Shunting-yard ordering. Postfix operators (%, !, °) apply to the operand just completed,
    /// before any pending operator. Unary minus is a prefix operator with no left operand, so it
    /// pops nothing. A function name without parentheses binds to the next value; with
    /// parentheses, commas count its arguments and the closing parenthesis emits the call.
    private static func toRPN(_ tokens: [Token]) throws -> [Token] {
        var output: [Token] = []
        var stack: [Token] = []
        var arity: [Int] = []
        var prev: Token? = nil
        for token in tokens {
            switch token {
            case .number:
                output.append(token)
            case .ident(let name):
                if ["pi", "e"].contains(name) { output.append(token) } else { stack.append(token) }
            case .op("p"), .op("!"), .op("d"):
                switch prev {
                case .number?, .rparen?, .ident?, .op("p")?, .op("!")?, .op("d")?: output.append(token)
                default: throw CalcError.syntax
                }
            case .op(let op):
                var op = op
                let unary = op == "-" && (prev == nil || prev == .lparen || prev == .comma || {
                    if case .op(let last) = prev!, !["p", "!", "d"].contains(last) { return true }
                    if case .ident(let name) = prev!, functions[name] != nil { return true }
                    return false
                }())
                if unary { op = "u" }
                while !unary, let top = stack.last {
                    if case .ident = top { output.append(stack.removeLast()); continue }
                    guard case .op(let t) = top,
                          precedence(t) > precedence(op) || (precedence(t) == precedence(op) && op != "^" && op != "u") else { break }
                    output.append(stack.removeLast())
                }
                stack.append(.op(op))
            case .lparen:
                if case .ident? = stack.last, case .ident? = prev { arity.append(0) } else { arity.append(-1) }
                stack.append(token)
            case .comma:
                while let top = stack.last, top != .lparen { output.append(stack.removeLast()) }
                guard stack.last == .lparen, let count = arity.last, count >= 0, prev != .lparen, prev != .comma else { throw CalcError.syntax }
                arity[arity.count - 1] = count + 1
            case .rparen:
                while let top = stack.last, top != .lparen { output.append(stack.removeLast()) }
                guard stack.popLast() == .lparen, let commas = arity.popLast(), prev != .comma else { throw CalcError.syntax }
                if let top = stack.last, case .ident(let name) = top {
                    stack.removeLast()
                    if commas > 0 || (functions[name] == nil && multiFunctions[name] != nil) {
                        guard multiFunctions[name] != nil else { throw CalcError.syntax }
                        output.append(.call(name, commas + 1))
                    } else {
                        output.append(top)
                    }
                } else if commas > 0 {
                    throw CalcError.syntax
                }
            case .call: throw CalcError.syntax
            }
            prev = token
        }
        while let top = stack.popLast() {
            if top == .lparen { throw CalcError.syntax }
            output.append(top)
        }
        return output
    }

    /// A value remembers whether it was written as a percentage, so "+" and "-" can take that
    /// share of the left side and the word operators can insist on a percentage.
    private struct Value {
        var number: Double
        var percent = false
    }

    private static func evalRPN(_ rpn: [Token]) throws -> Double {
        var stack: [Value] = []
        func pop() throws -> Value { guard let v = stack.popLast() else { throw CalcError.syntax }; return v }
        for token in rpn {
            switch token {
            case .number(let v): stack.append(Value(number: v))
            case .ident("pi"): stack.append(Value(number: Double.pi))
            case .ident("e"): stack.append(Value(number: M_E))
            case .ident(let fn):
                guard let function = functions[fn] else { throw CalcError.syntax }
                stack.append(Value(number: function(try pop().number)))
            case .call(let name, let count):
                guard let function = multiFunctions[name], stack.count >= count else { throw CalcError.syntax }
                let args = stack.suffix(count).map(\.number)
                stack.removeLast(count)
                guard let value = function(args) else { throw CalcError.syntax }
                stack.append(Value(number: value))
            case .op("!"):
                let x = try pop().number
                guard x >= 0, x == x.rounded(), x <= 170 else { throw CalcError.syntax }
                stack.append(Value(number: tgamma(x + 1).rounded()))
            case .op("d"):
                stack.append(Value(number: try pop().number * .pi / 180))
            case .op("p"):
                let x = try pop()
                guard !x.percent else { throw CalcError.syntax }
                stack.append(Value(number: x.number / 100, percent: true))
            case .op("u"):
                let x = try pop()
                stack.append(Value(number: -x.number, percent: x.percent))
            case .op(let op):
                let b = try pop(), a = try pop()
                switch op {
                case "+": stack.append(Value(number: b.percent && !a.percent ? a.number * (1 + b.number) : a.number + b.number))
                case "-": stack.append(Value(number: b.percent && !a.percent ? a.number * (1 - b.number) : a.number - b.number))
                case "*": stack.append(Value(number: a.number * b.number))
                case "/": guard b.number != 0 else { throw CalcError.divisionByZero }; stack.append(Value(number: a.number / b.number))
                case "m": guard b.number != 0 else { throw CalcError.divisionByZero }
                    stack.append(Value(number: a.number.truncatingRemainder(dividingBy: b.number)))
                case "^": stack.append(Value(number: pow(a.number, b.number)))
                case "o", "f", "n":
                    guard a.percent, !b.percent else { throw CalcError.syntax }
                    let share = op == "o" ? a.number : op == "f" ? 1 - a.number : 1 + a.number
                    stack.append(Value(number: b.number * share))
                default: throw CalcError.syntax
                }
            default: throw CalcError.syntax
            }
        }
        guard stack.count == 1 else { throw CalcError.syntax }
        return stack[0].number
    }
}
