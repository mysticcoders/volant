import Foundation

/// Arithmetic on quantities with units, beyond the single conversions `UnitConverter` answers:
/// sums and differences ("5 km + 300 m", "2 lb - 3 oz"), mixed quantities with a target ("5 ft 10 in
/// in cm", "5'10\" in cm"), scaling ("5 km * 3", "10 mi / 4"), ratios of like quantities ("10 km /
/// 2 km"), and speeds or data rates from a quantity over a time ("1 mile / 8 min in kph", "1 GB / 10 s
/// in Mbps").
///
/// A sum answers in its first unit unless a target follows "in", "to" or "as". Mixed quantities with
/// no operator need a target, so a bare "5 ft 10 in" stays a search. A speed with no target answers
/// in mph after imperial lengths and km/h otherwise; a data rate in Mbps. Sums of durations alone are
/// left to `DateCalculator`, and offset scales (temperature) and reciprocal units (fuel economy, pace)
/// do not add.
public enum UnitArithmetic {
    private typealias Spec = UnitConverter.Spec

    private struct Term {
        let value: Double
        let spec: Spec
    }

    private enum Operation {
        case scale(Double)
        case per([Term])
    }

    public static func evaluate(_ text: String, locale: Locale = .current) -> CalculationAnswer? {
        guard text.utf8.count <= 256 else { return nil }
        let input = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        var query = UnitConverter.normalized(text)
        query = query.replacingOccurrences(of: #"([+*×])"#, with: " $1 ", options: .regularExpression)
        query = query.replacingOccurrences(of: #"(?<=[a-z\.])-(?=\s*\d)"#, with: " - ", options: .regularExpression)
        var words = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var target: Spec?
        if let index = words.lastIndex(where: { ["in", "to", "as"].contains($0) }), index + 1 < words.count,
           let spec = UnitConverter.lookup(words[(index + 1)...].joined()) {
            target = spec
            words.removeSubrange(index...)
        }
        let separators = NumberLiteral.Separators(locale)
        var index = 0
        guard let (numerator, explicit) = sum(words, &index, separators), !numerator.isEmpty else { return nil }
        var operation: Operation?
        if index < words.count {
            let word = words[index]
            index += 1
            guard ["*", "x", "×", "times", "/"].contains(word), index < words.count else { return nil }
            if index + 1 == words.count, let factor = NumberLiteral.parse(words[index], locale: locale, magnitudes: false) {
                guard word != "/" || factor != 0 else { return nil }
                operation = .scale(word == "/" ? 1 / factor : factor)
                index += 1
            } else if word == "/", let (denominator, _) = sum(words, &index, separators), index == words.count {
                operation = .per(denominator)
            } else {
                return nil
            }
        }
        guard numerator.count >= 2 || operation != nil, explicit || operation != nil || target != nil else { return nil }
        guard let (total, unit) = combine(numerator) else { return nil }
        let value: Double, result: Spec
        switch operation {
        case .per(let denominator)?:
            guard let (over, overUnit) = combine(denominator), over != 0 else { return nil }
            if UnitConverter.sameDimension(unit.unit, overUnit.unit) {
                guard target == nil else { return nil }
                let ratio = total / UnitConverter.convert(over, from: overUnit.unit, to: unit.unit)
                guard ratio.isFinite else { return nil }
                let text = Calculator.format((ratio * 1e6).rounded() / 1e6, locale: locale)
                return CalculationAnswer(input: input, inputDetail: nil, result: text, resultDetail: nil, copyText: text)
            }
            guard overUnit.unit is UnitDuration else { return nil }
            let seconds = UnitConverter.convert(over, from: overUnit.unit, to: UnitDuration.seconds)
            let base: Double
            let fallback: Spec
            switch unit.unit {
            case is UnitLength:
                base = UnitConverter.convert(total, from: unit.unit, to: UnitLength.meters) / seconds
                let imperial = ["mi", "ft", "yd", "in"].contains(unit.symbol)
                fallback = Spec(unit: imperial ? UnitSpeed.milesPerHour : UnitSpeed.kilometersPerHour, symbol: imperial ? "mph" : "km/h")
                result = target ?? fallback
                guard result.unit is UnitSpeed else { return nil }
                value = UnitConverter.convert(base, from: UnitSpeed.metersPerSecond, to: result.unit)
            case is UnitInformationStorage:
                base = UnitConverter.convert(total, from: unit.unit, to: UnitInformationStorage.bits) / seconds
                fallback = Spec(unit: UnitConverter.Extra.megabitsPerSecond, symbol: "Mbps")
                result = target ?? fallback
                guard result.unit is UnitDataRate else { return nil }
                value = UnitConverter.convert(base, from: UnitConverter.Extra.bitsPerSecond, to: result.unit)
            default:
                return nil
            }
        default:
            guard !(unit.unit is UnitDuration) else { return nil }
            var scaled = total
            if case .scale(let factor)? = operation { scaled *= factor }
            result = target ?? unit
            guard UnitConverter.sameDimension(result.unit, unit.unit) else { return nil }
            value = UnitConverter.convert(scaled, from: unit.unit, to: result.unit)
        }
        guard value.isFinite else { return nil }
        let text = "\(Calculator.format((value * 1e6).rounded() / 1e6, locale: locale)) \(result.symbol)"
        return CalculationAnswer(input: input, inputDetail: nil, result: text,
                                 resultDetail: CalculationAnswer.unitName(result.unit, locale: locale), copyText: text)
    }

    /// Quantities joined by "+", "-" or nothing ("5 ft 10 in"), starting at `index` and leaving it
    /// after the last one. `explicit` says whether any operator joined them.
    private static func sum(_ words: [String], _ index: inout Int, _ separators: NumberLiteral.Separators) -> ([Term], Bool)? {
        var terms: [Term] = [], sign = 1.0, explicit = false
        if index < words.count, words[index] == "-" {
            sign = -1
            index += 1
        }
        while index < words.count {
            guard let term = term(words, &index, separators) else { return nil }
            terms.append(Term(value: sign * term.value, spec: term.spec))
            sign = 1
            guard index < words.count else { break }
            if words[index] == "+" || words[index] == "-" {
                sign = words[index] == "+" ? 1 : -1
                explicit = true
                index += 1
                guard index < words.count else { return nil }
            } else if !(words[index].first?.isNumber ?? false) {
                break
            }
        }
        return terms.isEmpty ? nil : (terms, explicit)
    }

    /// A number and its unit, which may touch ("300m") or span words ("fl oz", "square feet").
    private static func term(_ words: [String], _ index: inout Int, _ separators: NumberLiteral.Separators) -> Term? {
        let chars = Array(words[index])
        guard let (value, end) = NumberLiteral.scan(chars, from: 0, separators, magnitudes: false) else { return nil }
        let attached = String(chars[end...])
        let operators: Set<String> = ["+", "-", "*", "x", "×", "/", "times"]
        var longest: (Spec, Int)?
        for extra in 0...3 where index + extra < words.count {
            let following = words[(index + 1)..<(index + 1 + extra)]
            guard !following.contains(where: { operators.contains($0) || ($0.first?.isNumber ?? false) }) else { break }
            if let spec = UnitConverter.lookup(attached + following.joined()) { longest = (spec, extra) }
        }
        guard let (spec, extra) = longest else { return nil }
        index += 1 + extra
        return Term(value: value, spec: spec)
    }

    /// The total of like, linear quantities in the first one's unit.
    private static func combine(_ terms: [Term]) -> (Double, Spec)? {
        guard let first = terms.first, UnitConverter.factor(first.spec.unit) != nil else { return nil }
        var total = 0.0
        for term in terms {
            guard UnitConverter.sameDimension(term.spec.unit, first.spec.unit), UnitConverter.factor(term.spec.unit) != nil else { return nil }
            total += UnitConverter.convert(term.value, from: term.spec.unit, to: first.spec.unit)
        }
        return (total, first.spec)
    }
}
