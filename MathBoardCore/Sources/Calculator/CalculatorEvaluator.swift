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
        variables: [String: Double] = [:],
        yFunctions: [String: @Sendable (Double) throws -> Double] = [:]
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
            let value = try evaluate(inner, angleMode: angleMode, variables: variables, yFunctions: yFunctions)
            switch op {
            case .negate: return -value
            }

        case .binary(let op, let lhs, let rhs):
            let left  = try evaluate(lhs, angleMode: angleMode, variables: variables, yFunctions: yFunctions)
            let right = try evaluate(rhs, angleMode: angleMode, variables: variables, yFunctions: yFunctions)
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
            let value = try evaluate(inner, angleMode: angleMode, variables: variables, yFunctions: yFunctions)
            return try factorial(of: value)

        case .function(let name, let arguments):
            let values = try arguments.map {
                try evaluate($0, angleMode: angleMode, variables: variables, yFunctions: yFunctions)
            }
            // Check user-defined Y-functions (Y1–Y9) before built-ins
            let upperName = name.uppercased()
            if let yFunc = yFunctions[upperName], values.count == 1 {
                return try yFunc(values[0])
            }
            return try Self.applyFunction(named: name, to: values, angleMode: angleMode)
        }
    }

    // MARK: - Constants

    private static func constant(named raw: String) -> Double? {
        switch raw.lowercased() {
        case "pi", "π": return .pi
        case "e": return M_E
        case "rand": return Double.random(in: 0..<1)
        case "i": return .nan   // imaginary unit — real evaluator returns nan; complex path handles it
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

    static func applyFunction(
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
        case "log", "logbase":
            // 1 arg: base-10 log. 2 args: logBASE(base, x) — TI-84 convention, base is first arg.
            if values.count == 1 {
                let v = values[0]
                guard v > 0 else { throw CalculatorError.domain(function: raw, value: v) }
                return log10(v)
            }
            if values.count == 2 {
                let base = values[0]   // TI-84: base is first arg
                let value = values[1]  // value/argument is second
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
            return try two { index, value in  // TI-84: index (degree) is first arg
                guard index != 0 else { throw CalculatorError.domain(function: raw, value: index) }
                if value < 0 && index.rounded() == index && Int(index) % 2 != 0 {
                    return -pow(abs(value), 1 / index)
                }
                guard value >= 0 else { throw CalculatorError.domain(function: raw, value: value) }
                return pow(value, 1 / index)
            }

        // Complex-number stubs (real-number fallbacks; full complex handled by CalculatorComplexEvaluator)
        case "real": return try one { $0 }     // real part of a real number = itself
        case "imag": return try one { _ in 0 } // imaginary part of a real number = 0
        case "conj": return try one { $0 }     // conjugate of a real number = itself
        case "angle": return try one { $0 >= 0 ? 0 : .pi }  // angle is 0 or π for reals

        // Misc numerics
        case "abs": return try one { abs($0) }
        case "floor": return try one { floor($0) }
        case "ceil", "ceiling": return try one { ceil($0) }
        case "round": return try one { $0.rounded() }
        case "ipart":
            // Integer part — truncates toward zero (TI-84 iPart behavior)
            return try one { value in value < 0 ? ceil(value) : floor(value) }
        case "fpart":
            // Fractional part — x minus its integer part
            return try one { value in
                let intPart = value < 0 ? ceil(value) : floor(value)
                return value - intPart
            }
        case "int":
            // Greatest integer / floor function (TI-84 int behavior)
            return try one { floor($0) }
        case "sign":
            return try one { value in
                if value > 0 { return 1 }
                if value < 0 { return -1 }
                return 0
            }

        case "min": return try two { Swift.min($0, $1) }
        case "max": return try two { Swift.max($0, $1) }
        case "mod", "remainder":
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

        // Combinatorics (TI-84 PROB menu)
        case "npr", "perm":
            return try two { n, r in
                guard n >= 0, r >= 0, r <= n else {
                    throw CalculatorError.domain(function: raw, value: n)
                }
                let ni = try integer(from: n, function: raw)
                let ri = try integer(from: r, function: raw)
                guard ni <= 170 else { throw CalculatorError.factorialOverflow }
                if ri == 0 { return 1 }
                var result = 1.0
                for i in (ni - ri + 1)...ni { result *= Double(i) }
                return result
            }
        case "ncr", "comb":
            return try two { n, r in
                guard n >= 0, r >= 0, r <= n else {
                    throw CalculatorError.domain(function: raw, value: n)
                }
                let ni = try integer(from: n, function: raw)
                let riFull = try integer(from: r, function: raw)
                let ri = Swift.min(riFull, ni - riFull)  // choose smaller half for efficiency
                guard ni <= 170 else { throw CalculatorError.factorialOverflow }
                if ri == 0 { return 1 }
                var result = 1.0
                for i in 0..<ri { result = result * Double(ni - i) / Double(i + 1) }
                return result
            }
        case "randint":
            return try two { lo, hi in
                guard lo <= hi else { throw CalculatorError.domain(function: raw, value: lo) }
                let loInt = try integer(from: lo.rounded(), function: raw)
                let hiInt = try integer(from: hi.rounded(), function: raw)
                return Double(Int.random(in: loInt...hiInt))
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

// MARK: - Complex number (used by CalculatorComplexEvaluator)

public struct CalcComplex: Sendable, CustomStringConvertible {
    public var real: Double
    public var imag: Double
    public init(real: Double, imag: Double = 0) { self.real = real; self.imag = imag }
    public static let imagUnit = CalcComplex(real: 0, imag: 1)
    public var magnitude: Double { sqrt(real * real + imag * imag) }
    public var argument:  Double { atan2(imag, real) }
    public var conjugate: CalcComplex { CalcComplex(real: real, imag: -imag) }
    public var isReal: Bool { abs(imag) < 1e-12 }
    public var isZero: Bool { abs(real) < 1e-12 && abs(imag) < 1e-12 }
    public static func + (l: CalcComplex, r: CalcComplex) -> CalcComplex { .init(real: l.real+r.real, imag: l.imag+r.imag) }
    public static func - (l: CalcComplex, r: CalcComplex) -> CalcComplex { .init(real: l.real-r.real, imag: l.imag-r.imag) }
    public static prefix func - (z: CalcComplex) -> CalcComplex { .init(real: -z.real, imag: -z.imag) }
    public static func * (l: CalcComplex, r: CalcComplex) -> CalcComplex {
        .init(real: l.real*r.real - l.imag*r.imag, imag: l.real*r.imag + l.imag*r.real)
    }
    public static func / (l: CalcComplex, r: CalcComplex) -> CalcComplex {
        let d = r.real*r.real + r.imag*r.imag
        return .init(real: (l.real*r.real + l.imag*r.imag)/d, imag: (l.imag*r.real - l.real*r.imag)/d)
    }
    public static func pow(_ base: CalcComplex, _ exp: CalcComplex) -> CalcComplex {
        if exp.isReal, exp.real.rounded() == exp.real, Swift.abs(Int(exp.real)) <= 100 {
            let n = Int(exp.real); if n == 0 { return .init(real: 1) }
            var r = CalcComplex(real: 1); let b = n > 0 ? base : base.reciprocal
            for _ in 0..<Swift.abs(n) { r = r * b }; return r
        }
        return calcExpC(exp * calcLnC(base))
    }
    public var reciprocal: CalcComplex { let d = real*real+imag*imag; return .init(real: real/d, imag: -imag/d) }
    public var description: String { formatCalcComplex(self) }
}

func calcExpC(_ z: CalcComplex) -> CalcComplex {
    let r = Foundation.exp(z.real); return CalcComplex(real: r*cos(z.imag), imag: r*sin(z.imag))
}
func calcLnC(_ z: CalcComplex) -> CalcComplex {
    CalcComplex(real: Foundation.log(z.magnitude), imag: z.argument)
}
public func formatCalcComplex(_ z: CalcComplex) -> String {
    let tol = 1e-10, rZ = abs(z.real) < tol, iZ = abs(z.imag) < tol
    if iZ && rZ { return "0" }
    func fmt(_ v: Double) -> String { CalculatorResultFormatter.string(for: v) }
    if iZ { return fmt(z.real) }
    if rZ {
        if abs(z.imag - 1) < tol { return "i" }
        if abs(z.imag + 1) < tol { return "−i" }
        return fmt(z.imag) + "i"
    }
    let iAbs = abs(z.imag)
    let sign = z.imag < 0 ? "−" : "+"
    let iStr = abs(iAbs - 1) < tol ? "i" : fmt(iAbs) + "i"
    return fmt(z.real) + sign + iStr
}

// MARK: - Complex evaluator

public struct CalculatorComplexEvaluator: Sendable {
    public init() {}
    private let engine = CalculatorEngine()

    /// Returns true if `source` contains the imaginary unit `i` as a standalone token.
    public static func expressionIsComplex(_ source: String) -> Bool {
        // Quick scan: look for bare `i` not part of a longer identifier
        var prev: Character = " "
        for (idx, ch) in source.enumerated() {
            if ch == "i" {
                let next = idx + 1 < source.count ? source[source.index(source.startIndex, offsetBy: idx + 1)] : " "
                let isIdentStart = prev.isLetter || prev.isNumber || prev == "_"
                let isIdentCont  = next.isLetter || next.isNumber || next == "_"
                if !isIdentStart && !isIdentCont { return true }
            }
            prev = ch
        }
        return false
    }

    public func evaluate(
        _ source: String,
        angleMode: CalculatorAngleMode = .degrees,
        variables: [String: Double] = [:]
    ) throws -> CalcComplex {
        let expr = try engine.compile(source)
        return try evaluateExpr(expr, angleMode: angleMode, variables: variables)
    }

    private func evaluateExpr(
        _ expression: CalculatorExpression,
        angleMode: CalculatorAngleMode,
        variables: [String: Double]
    ) throws -> CalcComplex {
        switch expression {
        case .number(let v): return CalcComplex(real: v)
        case .identifier(let name):
            switch name.lowercased() {
            case "i": return .imagUnit
            case "pi", "π": return CalcComplex(real: .pi)
            case "e": return CalcComplex(real: M_E)
            default: break
            }
            if let v = variables[name] { return CalcComplex(real: v) }
            if let v = variables[name.lowercased()] { return CalcComplex(real: v) }
            throw CalculatorError.undefinedVariable(name)
        case .unary(let op, let inner):
            let z = try evaluateExpr(inner, angleMode: angleMode, variables: variables)
            switch op { case .negate: return -z }
        case .binary(let op, let lhs, let rhs):
            let l = try evaluateExpr(lhs, angleMode: angleMode, variables: variables)
            let r = try evaluateExpr(rhs, angleMode: angleMode, variables: variables)
            switch op {
            case .add:      return l + r
            case .subtract: return l - r
            case .multiply: return l * r
            case .divide:
                guard !r.isZero else { throw CalculatorError.divisionByZero }
                return l / r
            case .power: return CalcComplex.pow(l, r)
            }
        case .factorial(let inner):
            let z = try evaluateExpr(inner, angleMode: angleMode, variables: variables)
            guard z.isReal else { throw CalculatorError.domain(function: "!", value: z.imag) }
            return CalcComplex(real: try complexFact(z.real))
        case .function(let name, let args):
            let zArgs = try args.map { try evaluateExpr($0, angleMode: angleMode, variables: variables) }
            return try applyComplexFn(name, zArgs, angleMode: angleMode)
        }
    }

    private func applyComplexFn(_ raw: String, _ args: [CalcComplex], angleMode: CalculatorAngleMode) throws -> CalcComplex {
        let name = raw.lowercased()
        func one(_ f: (CalcComplex) throws -> CalcComplex) throws -> CalcComplex {
            guard args.count == 1 else { throw CalculatorError.wrongArgumentCount(function: raw, expected: 1, got: args.count) }
            return try f(args[0])
        }
        func two(_ f: (CalcComplex, CalcComplex) throws -> CalcComplex) throws -> CalcComplex {
            guard args.count == 2 else { throw CalculatorError.wrongArgumentCount(function: raw, expected: 2, got: args.count) }
            return try f(args[0], args[1])
        }
        func realOne(_ f: (Double) throws -> Double) throws -> CalcComplex {
            guard args.count == 1 else { throw CalculatorError.wrongArgumentCount(function: raw, expected: 1, got: args.count) }
            guard args[0].isReal else { throw CalculatorError.domain(function: raw, value: args[0].imag) }
            return CalcComplex(real: try f(args[0].real))
        }
        let toRad:   (Double) -> Double = { angleMode == .degrees ? $0 * .pi / 180 : $0 }
        let fromRad: (Double) -> Double = { angleMode == .degrees ? $0 * 180 / .pi : $0 }
        switch name {
        case "abs":   return try one { CalcComplex(real: $0.magnitude) }
        case "conj":  return try one { $0.conjugate }
        case "real":  return try one { CalcComplex(real: $0.real) }
        case "imag":  return try one { CalcComplex(real: $0.imag) }
        case "angle": return try one { z in CalcComplex(real: fromRad(z.argument)) }
        case "sin":   return try realOne { sin(toRad($0)) }
        case "cos":   return try realOne { cos(toRad($0)) }
        case "tan":   return try realOne { tan(toRad($0)) }
        case "asin":  return try realOne { fromRad(asin($0)) }
        case "acos":  return try realOne { fromRad(acos($0)) }
        case "atan":  return try realOne { fromRad(atan($0)) }
        case "sqrt":
            return try one { z in
                if z.isReal && z.real >= 0 { return CalcComplex(real: sqrt(z.real)) }
                let r = sqrt(z.magnitude), theta = z.argument / 2
                return CalcComplex(real: r * cos(theta), imag: r * sin(theta))
            }
        case "ln":
            return try one { z in
                guard !z.isZero else { throw CalculatorError.domain(function: raw, value: 0) }
                return calcLnC(z)
            }
        case "log", "logbase":
            if args.count == 1 { return try realOne { v in
                guard v > 0 else { throw CalculatorError.domain(function: raw, value: v) }
                return log10(v)
            }}
            if args.count == 2 {
                guard args[0].isReal, args[1].isReal else { throw CalculatorError.domain(function: raw, value: 0) }
                let b = args[0].real, v = args[1].real    // TI-84: base first, value second
                guard v > 0, b > 0, b != 1 else { throw CalculatorError.domain(function: raw, value: v) }
                return CalcComplex(real: log(v) / log(b))
            }
            throw CalculatorError.wrongArgumentCount(function: raw, expected: 2, got: args.count)
        case "cbrt":  return try realOne { cbrt($0) }
        case "root":
            return try two { idx, base in  // TI-84: index first, value second
                guard base.isReal, idx.isReal else { throw CalculatorError.domain(function: raw, value: 0) }
                let n = idx.real; guard n != 0 else { throw CalculatorError.domain(function: raw, value: n) }
                if base.real < 0, n.rounded() == n, Int(n) % 2 != 0 { return CalcComplex(real: -Foundation.pow(abs(base.real), 1/n)) }
                guard base.real >= 0 else { throw CalculatorError.domain(function: raw, value: base.real) }
                return CalcComplex(real: Foundation.pow(base.real, 1/n))
            }
        default:
            guard args.allSatisfy({ $0.isReal }) else { throw CalculatorError.undefinedVariable(raw) }
            let result = try CalculatorEvaluator.applyFunction(named: raw, to: args.map { $0.real }, angleMode: angleMode)
            return CalcComplex(real: result)
        }
    }
}

private func complexFact(_ v: Double) throws -> Double {
    if v < 0 { throw CalculatorError.factorialOfNegative }
    if v.rounded() != v { throw CalculatorError.factorialOfNonInteger }
    if v > 170 { throw CalculatorError.factorialOverflow }
    if v <= 1 { return 1 }
    var p = 1.0; for i in 2...Int(v) { p *= Double(i) }; return p
}
