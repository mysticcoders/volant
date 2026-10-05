import Foundation

/// Arithmetic evaluator: + - * / ^ mod, parentheses, unary minus, pi, e, sqrt, abs, round, floor, ceil, and
/// percentages. Pure; no NSExpression.
///
/// `%` is a percentage, as people write it: "52% of 900", "20% off 80", "15% tip on 42", and
/// "19 + 47%" or "100 - 10%" add or subtract that share of the left side. Elsewhere `%` divides by
/// 100, so "200 * 15%" is 30. Remainder is `mod`.
public enum Calculator {
    public enum CalcError: Error { case syntax, divisionByZero }

    private enum Token: Equatable {
        case number(Double), op(Character), lparen, rparen, ident(String)
    }

    public static func evaluate(_ text: String) -> Double? {
        guard looksNumeric(text) else { return nil }
        do {
            let tokens = try tokenize(text)
            guard !tokens.isEmpty else { return nil }
            let rpn = try toRPN(tokens)
            return try evalRPN(rpn)
        } catch {
            return nil
        }
    }

    /// Cheap gate so ordinary app names never reach the parser.
    public static func looksNumeric(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return false }
        let allowed = CharacterSet(charactersIn: "0123456789.+-*/^%() ").union(.letters)
        guard t.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        return t.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) } || t.contains("pi") || t == "e"
    }

    public static func format(_ value: Double) -> String {
        if value.isNaN || value.isInfinite { return "undefined" }
        if value == value.rounded() && abs(value) < 1e15 { return String(Int64(value)) }
        let f = NumberFormatter()
        f.maximumFractionDigits = 10
        f.minimumFractionDigits = 0
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// Word operators, each one character on the operator stack: "of", "off", "on" ("tip on" reads the
    /// same) and "mod".
    private static let words: [String: Character] = ["of": "o", "off": "f", "on": "n", "mod": "m"]

    private static func tokenize(_ text: String) throws -> [Token] {
        var tokens: [Token] = []
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch.isWhitespace { i += 1; continue }
            if ch.isNumber || ch == "." {
                var j = i
                while j < chars.count && (chars[j].isNumber || chars[j] == ".") { j += 1 }
                guard let v = Double(String(chars[i..<j])) else { throw CalcError.syntax }
                tokens.append(.number(v)); i = j; continue
            }
            if ch.isLetter {
                var j = i
                while j < chars.count && chars[j].isLetter { j += 1 }
                let word = String(chars[i..<j]).lowercased()
                i = j
                if word == "tip" {
                    while i < chars.count && chars[i].isWhitespace { i += 1 }
                    var k = i
                    while k < chars.count && chars[k].isLetter { k += 1 }
                    guard String(chars[i..<k]).lowercased() == "on" else { throw CalcError.syntax }
                    tokens.append(.op("n")); i = k; continue
                }
                tokens.append(words[word].map { .op($0) } ?? .ident(word)); continue
            }
            switch ch {
            case "(": tokens.append(.lparen)
            case ")": tokens.append(.rparen)
            case "+", "-", "*", "/", "^": tokens.append(.op(ch))
            case "%": tokens.append(.op("p"))
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

    private static func toRPN(_ tokens: [Token]) throws -> [Token] {
        var output: [Token] = []
        var stack: [Token] = []
        var prev: Token? = nil
        for token in tokens {
            switch token {
            case .number:
                output.append(token)
            case .ident(let name):
                if ["pi", "e"].contains(name) { output.append(token) } else { stack.append(token) }
            case .op("p"):
                // Postfix: applies to the operand just completed, before any pending operator.
                switch prev {
                case .number?, .rparen?, .ident?, .op("p")?: output.append(token)
                default: throw CalcError.syntax
                }
            case .op(let op):
                var op = op
                let unary = op == "-" && (prev == nil || prev == .lparen || { if case .op(let last) = prev!, last != "p" { return true }; return false }())
                if unary { op = "u" }
                // A prefix operator has no left operand, so nothing on the stack can be complete yet.
                while !unary, let top = stack.last, case .op(let t) = top,
                      precedence(t) > precedence(op) || (precedence(t) == precedence(op) && op != "^" && op != "u") {
                    output.append(stack.removeLast())
                }
                stack.append(.op(op))
            case .lparen:
                stack.append(token)
            case .rparen:
                while let top = stack.last, top != .lparen { output.append(stack.removeLast()) }
                guard stack.popLast() == .lparen else { throw CalcError.syntax }
                if let top = stack.last, case .ident = top { output.append(stack.removeLast()) }
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
                let x = try pop().number
                switch fn {
                case "sqrt": stack.append(Value(number: x.squareRoot()))
                case "abs": stack.append(Value(number: abs(x)))
                case "round": stack.append(Value(number: x.rounded()))
                case "floor": stack.append(Value(number: x.rounded(.down)))
                case "ceil": stack.append(Value(number: x.rounded(.up)))
                default: throw CalcError.syntax
                }
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
