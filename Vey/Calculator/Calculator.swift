import Foundation

/// Arithmetic evaluator: + - * / ^ %, parentheses, unary minus, pi, e, sqrt, abs, round, floor, ceil. Pure; no NSExpression.
enum Calculator {
    enum CalcError: Error { case syntax, divisionByZero }

    private enum Token: Equatable {
        case number(Double), op(Character), lparen, rparen, ident(String)
    }

    static func evaluate(_ text: String) -> Double? {
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
    static func looksNumeric(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return false }
        let allowed = CharacterSet(charactersIn: "0123456789.+-*/^%() ").union(.letters)
        guard t.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        return t.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) } || t.contains("pi") || t == "e"
    }

    static func format(_ value: Double) -> String {
        if value.isNaN || value.isInfinite { return "undefined" }
        if value == value.rounded() && abs(value) < 1e15 { return String(Int64(value)) }
        let f = NumberFormatter()
        f.maximumFractionDigits = 10
        f.minimumFractionDigits = 0
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }

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
                tokens.append(.ident(String(chars[i..<j]).lowercased())); i = j; continue
            }
            switch ch {
            case "(": tokens.append(.lparen)
            case ")": tokens.append(.rparen)
            case "+", "-", "*", "/", "^", "%": tokens.append(.op(ch))
            default: throw CalcError.syntax
            }
            i += 1
        }
        return tokens
    }

    private static func precedence(_ op: Character) -> Int {
        switch op {
        case "u": return 4
        case "^": return 3
        case "*", "/", "%": return 2
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
            case .op(let op):
                var op = op
                let unary = op == "-" && (prev == nil || { if case .op = prev! { return true }; return prev == .lparen }())
                if unary { op = "u" }
                while let top = stack.last, case .op(let t) = top,
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

    private static func evalRPN(_ rpn: [Token]) throws -> Double {
        var stack: [Double] = []
        func pop() throws -> Double { guard let v = stack.popLast() else { throw CalcError.syntax }; return v }
        for token in rpn {
            switch token {
            case .number(let v): stack.append(v)
            case .ident("pi"): stack.append(Double.pi)
            case .ident("e"): stack.append(M_E)
            case .ident(let fn):
                let x = try pop()
                switch fn {
                case "sqrt": stack.append(x.squareRoot())
                case "abs": stack.append(abs(x))
                case "round": stack.append(x.rounded())
                case "floor": stack.append(x.rounded(.down))
                case "ceil": stack.append(x.rounded(.up))
                default: throw CalcError.syntax
                }
            case .op("u"): stack.append(-(try pop()))
            case .op(let op):
                let b = try pop(), a = try pop()
                switch op {
                case "+": stack.append(a + b)
                case "-": stack.append(a - b)
                case "*": stack.append(a * b)
                case "/": guard b != 0 else { throw CalcError.divisionByZero }; stack.append(a / b)
                case "%": guard b != 0 else { throw CalcError.divisionByZero }; stack.append(a.truncatingRemainder(dividingBy: b))
                case "^": stack.append(pow(a, b))
                default: throw CalcError.syntax
                }
            default: throw CalcError.syntax
            }
        }
        guard stack.count == 1 else { throw CalcError.syntax }
        return stack[0]
    }
}
