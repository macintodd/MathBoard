//
//  CalculatorEvaluator.swift
//  MathBoardCore — Calculator module
//
//  Walks the AST and returns a `Double`. Trig functions consult the
//  passed-in angle mode (degrees / radians). Identifiers fall through
//  a two-step lookup: constants first (`pi`, `e`), then user-provided
//  variables; an unmatched identifier is reported as an undefined
//  variable so callers can decide whether to inject a value or surface
//  the error.
//

import Foundation

public struct CalculatorEvaluator: Sendable {

    public init() {}

    public func evaluate(
        _ expression: CalculatorExpression,
        angleMode: CalculatorAngleMode = .degrees,
        variables: [String: Double] = [:]
    ) throws -> Double {
        switch expression {
        case .number(let value):
            return value

        case .identifier(let name):
            if let constant = Self.constant(named: name) {
                return constant
            }
            if let value = variables[name] {
                return value
            }
            throw CalculatorError.undefinedVariable(name)

        case .unary(let op, let inner):
            let value = try evaluate(inner, angleMode: angleMode, variables: variables)
            switch op {
            case .negate: return -value
            }

        case .binary(let op, let lhs, let rhs):
            let left = try evaluate(lhs, angleMode: angleMode, variables: variables)
            let right = try evaluate(rhs, angleMode: angleMode, variables: variables)
            switch op {
            case .add: return left + right
            case .subtract: return left - right
            case .multiply: return left * right
            case .divide:
                guard right != 0 else { throw CalculatorError.divisionByZero }
                return left / right
            case .power: return pow(left, right)
            }

        case .factorial(let inner):
            let value = try evaluate(inner, angleMode: angleMode, variables: variables)
            return try factorial(of: value)

        case .function(let name, let arguments):
            let values = try arguments.map {
                try evaluate($0, angleMode: angleMode, variables: variables)
            }
            return try Self.applyFunction(named: name, to: values, angleMode: angleMode)
        }
    }

    // MARK: - Constants

    private static func constant(named raw: String) -> Double? {
        switch raw.lowercased() {
        case "pi", "π": return .pi
        case "e": return M_E
        default: return nil
        }
    }

    // MARK: - Factorial

    private func factorial(of value: Double) throws -> Double {
        if value < 0 { throw CalculatorError.factorialOfNegative }
        if value.rounded() != value { throw CalculatorError.factorialOfNonInteger }
        if value > 170 { throw CalculatorError.factorialOverflow }
        if value <= 1 { return 1 }

        var product = 1.0
        for index in 2...Int(value) {
            product *= Double(index)
        }
        return product
    }

    // MARK: - Functions

    private static func applyFunction(
        named raw: String,
        to values: [Double],
        angleMode: CalculatorAngleMode
    ) throws -> Double {
        let name = raw.lowercased()

        func one(_ transform: (Double) throws -> Double) throws -> Double {
            guard values.count == 1 else {
                throw CalculatorError.wrongArgumentCount(function: raw, expected: 1, got: values.count)
            }
            return try transform(values[0])
        }

        func two(_ transform: (Double, Double) throws -> Double) throws -> Double {
            guard values.count == 2 else {
                throw CalculatorError.wrongArgumentCount(function: raw, expected: 2, got: values.count)
            }
            return try transform(values[0], values[1])
        }

        func toRadians(_ value: Double) -> Double {
            angleMode == .degrees ? value * .pi / 180 : value
        }

        func fromRadians(_ radians: Double) -> Double {
            angleMode == .degrees ? radians * 180 / .pi : radians
        }

        switch name {
        // Trig
        case "sin": return try one { sin(toRadians($0)) }
        case "cos": return try one { cos(toRadians($0)) }
        case "tan": return try one { tan(toRadians($0)) }
        case "csc":
            return try one { value in
                let s = sin(toRadians(value))
                guard s != 0 else { throw CalculatorError.domain(function: raw, value: value) }
                return 1 / s
            }
        case "sec":
            return try one { value in
                let c = cos(toRadians(value))
                guard c != 0 else { throw CalculatorError.domain(function: raw, value: value) }
                return 1 / c
            }
        case "cot":
            return try one { value in
                let t = tan(toRadians(value))
                guard t != 0 else { throw CalculatorError.domain(function: raw, value: value) }
                return 1 / t
            }

        // Inverse trig
        case "asin", "arcsin":
            return try one { value in
                guard (-1...1).contains(value) else { throw CalculatorError.domain(function: raw, value: value) }
                return fromRadians(asin(value))
            }
        case "acos", "arccos":
            return try one { value in
                guard (-1...1).contains(value) else { throw CalculatorError.domain(function: raw, value: value) }
                return fromRadians(acos(value))
            }
        case "atan", "arctan":
            return try one { fromRadians(atan($0)) }

        // Hyperbolic
        case "sinh": return try one { sinh($0) }
        case "cosh": return try one { cosh($0) }
        case "tanh": return try one { tanh($0) }
        case "asinh", "arcsinh": return try one { asinh($0) }
        case "acosh", "arccosh":
            return try one { value in
                guard value >= 1 else { throw CalculatorError.domain(function: raw, value: value) }
                return acosh(value)
            }
        case "atanh", "arctanh":
            return try one { value in
                guard value > -1 && value < 1 else { throw CalculatorError.domain(function: raw, value: value) }
                return atanh(value)
            }

        // Logs / exponentials
        case "ln":
            return try one { value in
                guard value > 0 else { throw CalculatorError.domain(function: raw, value: value) }
                return log(value)
            }
        case "log":
            // 1 arg: base-10. 2 args: log(x, b).
            if values.count == 1 {
                let v = values[0]
                guard v > 0 else { throw CalculatorError.domain(function: raw, value: v) }
                return log10(v)
            }
            if values.count == 2 {
                let value = values[0]
                let base = values[1]
                guard value > 0, base > 0, base != 1 else {
                    throw CalculatorError.domain(function: raw, value: value)
                }
                return log(value) / log(base)
            }
            throw CalculatorError.wrongArgumentCount(function: raw, expected: 1, got: values.count)
        case "log2":
            return try one { value in
                guard value > 0 else { throw CalculatorError.domain(function: raw, value: value) }
                return log2(value)
            }
        case "exp": return try one { exp($0) }

        // Roots / powers
        case "sqrt", "√":
            return try one { value in
                guard value >= 0 else { throw CalculatorError.domain(function: raw, value: value) }
                return sqrt(value)
            }
        case "cbrt": return try one { cbrt($0) }
        case "root":
            return try two { value, index in
                guard index != 0 else { throw CalculatorError.domain(function: raw, value: index) }
                if value < 0 && index.rounded() == index && Int(index) % 2 != 0 {
                    return -pow(abs(value), 1 / index)
                }
                guard value >= 0 else { throw CalculatorError.domain(function: raw, value: value) }
                return pow(value, 1 / index)
            }

        // Misc numerics
        case "abs": return try one { abs($0) }
        case "floor": return try one { floor($0) }
        case "ceil", "ceiling": return try one { ceil($0) }
        case "round": return try one { $0.rounded() }
        case "sign":
            return try one { value in
                if value > 0 { return 1 }
                if value < 0 { return -1 }
                return 0
            }

        case "min": return try two { Swift.min($0, $1) }
        case "max": return try two { Swift.max($0, $1) }
        case "mod":
            return try two { dividend, divisor in
                guard divisor != 0 else { throw CalculatorError.divisionByZero }
                return dividend.truncatingRemainder(dividingBy: divisor)
            }
        case "gcd":
            return try two { left, right in
                try Double(gcd(integer(from: left, function: raw), integer(from: right, function: raw)))
            }
        case "lcm":
            return try two { left, right in
                let a = try integer(from: left, function: raw)
                let b = try integer(from: right, function: raw)
                guard a != 0 && b != 0 else { return 0 }
                return Double(abs(a / gcd(a, b) * b))
            }

        default:
            throw CalculatorError.unknownFunction(raw)
        }
    }

    private static func integer(from value: Double, function: String) throws -> Int {
        guard value.isFinite, value.rounded() == value, abs(value) <= Double(Int.max) else {
            throw CalculatorError.domain(function: function, value: value)
        }
        return Int(value)
    }

    private static func gcd(_ left: Int, _ right: Int) -> Int {
        var a = abs(left)
        var b = abs(right)
        while b != 0 {
            let remainder = a % b
            a = b
            b = remainder
        }
        return a
    }
}
