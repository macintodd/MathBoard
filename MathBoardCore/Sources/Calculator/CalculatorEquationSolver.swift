//
//  CalculatorEquationSolver.swift
//  MathBoardCore — Calculator module
//
//  Solves single-variable equations and inequalities for the graph
//  calculator's "1 Variable" topic (number-line mode). Pure / SwiftUI-free
//  and unit-tested.
//
//  Approach: split the input on its relation operator into lhs/rhs, build
//  g(x) = lhs − rhs via the existing engine, then:
//    • equality → numerically find roots of g over the domain (sign-change
//      bisection + near-zero sampling), returned as discrete solutions.
//    • inequality → roots partition the domain; test each subinterval's
//      midpoint against the relation and merge the satisfying segments.
//  Solutions are reported within the searched domain (a finite window).
//

import Foundation

public enum CalculatorRelation: String, Sendable, Equatable {
    case equal          // =
    case less           // <
    case lessEqual      // ≤  / <=
    case greater        // >
    case greaterEqual   // ≥  / >=

    var isStrict: Bool { self == .less || self == .greater }
}

public struct SolutionInterval: Equatable, Sendable {
    public var lower: Double
    public var upper: Double
    public var lowerInclusive: Bool
    public var upperInclusive: Bool

    public init(lower: Double, upper: Double, lowerInclusive: Bool, upperInclusive: Bool) {
        self.lower = lower
        self.upper = upper
        self.lowerInclusive = lowerInclusive
        self.upperInclusive = upperInclusive
    }
}

public enum SolutionSet: Equatable, Sendable {
    case discrete([Double])             // equality roots (empty = none in domain)
    case intervals([SolutionInterval])  // inequality regions
    case all                            // relation holds everywhere in domain
    case none                           // relation holds nowhere in domain
    case error(String)
}

// MARK: - Region set algebra (for AND / OR combination)

public enum CombineMode: String, Codable, Sendable, CaseIterable {
    case and
    case or

    public var displayName: String { self == .and ? "And" : "Or" }
}

/// Cell-1 connective dropdown in 1-Variable mode.
public enum OneVarConnective: String, Codable, Sendable, CaseIterable {
    case none
    case and
    case or

    public var displayName: String {
        switch self {
        case .none: return "–"
        case .and: return "and"
        case .or: return "or"
        }
    }

    /// The `CombineMode` for `and`/`or`; nil for `none`.
    public var combineMode: CombineMode? {
        switch self {
        case .none: return nil
        case .and: return .and
        case .or: return .or
        }
    }
}

/// A normalized 1-D solution region as a sorted, disjoint list of
/// intervals (an equality point is a degenerate `[p, p]` interval). Used
/// to intersect/union two solution sets for the "And"/"Or" feature.
public struct SolutionRegion: Equatable, Sendable {
    public var intervals: [SolutionInterval]

    public init(intervals: [SolutionInterval]) { self.intervals = intervals }

    public static func from(_ set: SolutionSet, domain: ClosedRange<Double>) -> SolutionRegion {
        switch set {
        case .all:
            return SolutionRegion(intervals: [SolutionInterval(
                lower: domain.lowerBound, upper: domain.upperBound,
                lowerInclusive: true, upperInclusive: true
            )])
        case .none, .error:
            return SolutionRegion(intervals: [])
        case .intervals(let intervals):
            return SolutionRegion(intervals: intervals)
        case .discrete(let points):
            return SolutionRegion(intervals: points.map {
                SolutionInterval(lower: $0, upper: $0, lowerInclusive: true, upperInclusive: true)
            })
        }
    }

    /// Whether `x` is in the region (respecting endpoint inclusivity).
    public func contains(_ x: Double) -> Bool {
        for interval in intervals {
            let aboveLower = x > interval.lower || (interval.lowerInclusive && x == interval.lower)
            let belowUpper = x < interval.upper || (interval.upperInclusive && x == interval.upper)
            if aboveLower && belowUpper { return true }
        }
        return false
    }

    /// Convert back to a `SolutionSet` for display/rendering.
    public func asSolutionSet(domain: ClosedRange<Double>) -> SolutionSet {
        if intervals.isEmpty { return .none }
        if intervals.count == 1,
           intervals[0].lower <= domain.lowerBound + 1e-9,
           intervals[0].upper >= domain.upperBound - 1e-9 {
            return .all
        }
        // All-degenerate → discrete points.
        if intervals.allSatisfy({ abs($0.upper - $0.lower) < 1e-9 }) {
            return .discrete(intervals.map { ($0.lower + $0.upper) / 2 })
        }
        return .intervals(intervals)
    }

    /// Combine two regions over a domain via AND (intersection) or OR
    /// (union), using boundary + midpoint testing so endpoint inclusivity
    /// falls out of membership tests.
    public static func combine(
        _ a: SolutionRegion,
        _ b: SolutionRegion,
        mode: CombineMode,
        domain: ClosedRange<Double>
    ) -> SolutionRegion {
        func predicate(_ x: Double) -> Bool {
            mode == .and ? (a.contains(x) && b.contains(x)) : (a.contains(x) || b.contains(x))
        }

        // Boundary points from both regions, clipped to the domain.
        var boundaries: [Double] = [domain.lowerBound, domain.upperBound]
        for interval in a.intervals + b.intervals {
            boundaries.append(interval.lower)
            boundaries.append(interval.upper)
        }
        boundaries = boundaries
            .filter { $0 >= domain.lowerBound && $0 <= domain.upperBound }
            .sorted()

        var result: [SolutionInterval] = []
        var i = 0
        while i < boundaries.count - 1 {
            let a0 = boundaries[i]
            let b0 = boundaries[i + 1]
            if b0 - a0 < 1e-12 { i += 1; continue }
            let mid = (a0 + b0) / 2
            if predicate(mid) {
                result.append(SolutionInterval(
                    lower: a0, upper: b0,
                    lowerInclusive: predicate(a0),
                    upperInclusive: predicate(b0)
                ))
            }
            i += 1
        }

        // Merge touching intervals.
        var merged: [SolutionInterval] = []
        for interval in result {
            if var last = merged.last, abs(last.upper - interval.lower) < 1e-9 {
                last.upper = interval.upper
                last.upperInclusive = interval.upperInclusive
                merged[merged.count - 1] = last
            } else {
                merged.append(interval)
            }
        }

        // Preserve isolated included boundary points (degenerate intervals)
        // not already covered — handles equality operands.
        for point in boundaries where predicate(point) {
            let covered = merged.contains { interval in
                point > interval.lower && point < interval.upper
            }
            let alreadyEndpoint = merged.contains { abs($0.lower - point) < 1e-9 || abs($0.upper - point) < 1e-9 }
            if !covered && !alreadyEndpoint {
                merged.append(SolutionInterval(lower: point, upper: point, lowerInclusive: true, upperInclusive: true))
            }
        }
        merged.sort { $0.lower < $1.lower }
        return SolutionRegion(intervals: merged)
    }
}

/// Human-readable description of a solution set (e.g. "x = 1, 5" or
/// "x ≤ −2  or  x ≥ 2"). Pure / testable.
public enum CalculatorSolutionFormatter {

    public static func describe(_ set: SolutionSet, domain: ClosedRange<Double>) -> String {
        switch set {
        case .discrete(let xs):
            guard !xs.isEmpty else { return "No solution in view" }
            return "x = " + xs.map(number).joined(separator: ", ")
        case .all:
            return "All real numbers"
        case .none:
            return "No solution in view"
        case .error(let message):
            return message
        case .intervals(let intervals):
            guard !intervals.isEmpty else { return "No solution in view" }
            return intervals.map { describe($0, domain: domain) }.joined(separator: "  or  ")
        }
    }

    static func describe(_ interval: SolutionInterval, domain: ClosedRange<Double>) -> String {
        let atLow = interval.lower <= domain.lowerBound + 1e-9
        let atHigh = interval.upper >= domain.upperBound - 1e-9
        let lowOp = interval.lowerInclusive ? "≤" : "<"
        let highOp = interval.upperInclusive ? "≤" : "<"

        if atLow && atHigh { return "all x" }
        if atLow { return "x \(highOp) \(number(interval.upper))" }
        if atHigh {
            let op = interval.lowerInclusive ? "≥" : ">"
            return "x \(op) \(number(interval.lower))"
        }
        return "\(number(interval.lower)) \(lowOp) x \(highOp) \(number(interval.upper))"
    }

    private static func number(_ value: Double) -> String {
        CalculatorResultFormatter.string(for: value)
    }
}

public struct CalculatorEquationSolver {

    private let engine = CalculatorEngine()
    private let variable: String

    public init(variable: String = "x") {
        self.variable = variable
    }

    public func solve(
        _ input: String,
        domain: ClosedRange<Double>,
        angleMode: CalculatorAngleMode = .degrees
    ) -> SolutionSet {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }

        // Compound: "A or B", "A and B" (and binds tighter than or).
        let lowered = trimmed.lowercased()
        if lowered.contains(" or ") || lowered.contains(" and ") {
            return solveCompound(lowered, domain: domain, angleMode: angleMode)
        }
        return solveSingle(trimmed, domain: domain, angleMode: angleMode)
    }

    private func solveCompound(
        _ input: String,
        domain: ClosedRange<Double>,
        angleMode: CalculatorAngleMode
    ) -> SolutionSet {
        let orParts = input.components(separatedBy: " or ")
        var orRegion = SolutionRegion(intervals: [])
        for (orIndex, orPart) in orParts.enumerated() {
            let andParts = orPart.components(separatedBy: " and ")
            var andRegion: SolutionRegion?
            for andPart in andParts {
                let sub = solveSingle(andPart.trimmingCharacters(in: .whitespaces), domain: domain, angleMode: angleMode)
                if case .error(let message) = sub { return .error(message) }
                let region = SolutionRegion.from(sub, domain: domain)
                andRegion = andRegion.map { SolutionRegion.combine($0, region, mode: .and, domain: domain) } ?? region
            }
            let groupRegion = andRegion ?? SolutionRegion(intervals: [])
            orRegion = orIndex == 0 ? groupRegion : SolutionRegion.combine(orRegion, groupRegion, mode: .or, domain: domain)
        }
        return orRegion.asSolutionSet(domain: domain)
    }

    private func solveSingle(
        _ input: String,
        domain: ClosedRange<Double>,
        angleMode: CalculatorAngleMode
    ) -> SolutionSet {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }

        let (relation, lhsText, rhsText) = Self.split(trimmed)

        let compiledLHS: CalculatorExpression
        let compiledRHS: CalculatorExpression
        do {
            compiledLHS = try engine.compile(lhsText)
            compiledRHS = try engine.compile(rhsText)
        } catch {
            return .error((error as? LocalizedError)?.errorDescription ?? "Invalid equation")
        }

        // g(x) = lhs − rhs
        let g: (Double) -> Double? = { x in
            let vars = [self.variable: x]
            guard
                let l = try? self.engine.evaluate(compiled: compiledLHS, angleMode: angleMode, variables: vars),
                let r = try? self.engine.evaluate(compiled: compiledRHS, angleMode: angleMode, variables: vars),
                l.isFinite, r.isFinite
            else { return nil }
            return l - r
        }

        let roots = Self.findRoots(of: g, in: domain)

        if relation == .equal {
            return .discrete(roots)
        }
        return Self.intervals(for: relation, g: g, roots: roots, domain: domain)
    }

    // MARK: - Relation splitting

    static func split(_ input: String) -> (CalculatorRelation, lhs: String, rhs: String) {
        // Normalize unicode to ASCII for detection.
        let normalized = input
            .replacingOccurrences(of: "≤", with: "<=")
            .replacingOccurrences(of: "≥", with: ">=")

        func parts(_ separator: String) -> (String, String)? {
            guard let range = normalized.range(of: separator) else { return nil }
            let lhs = String(normalized[normalized.startIndex..<range.lowerBound])
            let rhs = String(normalized[range.upperBound...])
            return (lhs, rhs)
        }

        if let (l, r) = parts("<=") { return (.lessEqual, l, r) }
        if let (l, r) = parts(">=") { return (.greaterEqual, l, r) }
        if let (l, r) = parts("<") { return (.less, l, r) }
        if let (l, r) = parts(">") { return (.greater, l, r) }
        if let (l, r) = parts("=") { return (.equal, l, r) }
        // No relation operator → treat as "expression = 0" (find zeros).
        return (.equal, input, "0")
    }

    // MARK: - Root finding

    static func findRoots(
        of g: (Double) -> Double?,
        in domain: ClosedRange<Double>,
        samples: Int = 2000
    ) -> [Double] {
        let lower = domain.lowerBound
        let upper = domain.upperBound
        guard upper > lower, samples > 1 else { return [] }

        let step = (upper - lower) / Double(samples)
        var roots: [Double] = []

        var prevX = lower
        var prevY = g(prevX)

        for index in 1...samples {
            let x = lower + step * Double(index)
            let y = g(x)

            if let py = prevY, let cy = y {
                if py == 0 { roots.append(prevX) }
                if py * cy < 0 {
                    roots.append(bisect(g, prevX, x))
                }
            }
            prevX = x
            prevY = y
        }
        if let last = g(upper), last == 0 { roots.append(upper) }

        return dedupe(roots.sorted(), tolerance: step)
    }

    private static func bisect(_ g: (Double) -> Double?, _ a0: Double, _ b0: Double) -> Double {
        var a = a0, b = b0
        guard let fa0 = g(a) else { return (a + b) / 2 }
        var fa = fa0
        for _ in 0..<80 {
            let m = (a + b) / 2
            guard let fm = g(m) else { return m }
            if fm == 0 || (b - a) < 1e-12 { return m }
            if fa * fm < 0 {
                b = m
            } else {
                a = m
                fa = fm
            }
        }
        return (a + b) / 2
    }

    private static func dedupe(_ sorted: [Double], tolerance: Double) -> [Double] {
        var result: [Double] = []
        for value in sorted {
            let cleaned = cleanup(value)
            if let last = result.last, abs(cleaned - last) <= tolerance * 1.5 { continue }
            result.append(cleaned)
        }
        return result
    }

    /// Snap values extremely close to a round number to that number, so
    /// `x^2 = 4` reports `2`, not `1.9999999998`.
    private static func cleanup(_ value: Double) -> Double {
        let rounded = (value * 1e6).rounded() / 1e6
        return rounded == 0 ? 0 : rounded
    }

    // MARK: - Inequality intervals

    static func intervals(
        for relation: CalculatorRelation,
        g: (Double) -> Double?,
        roots: [Double],
        domain: ClosedRange<Double>
    ) -> SolutionSet {
        let lower = domain.lowerBound
        let upper = domain.upperBound
        let boundaries = [lower] + roots.filter { $0 > lower && $0 < upper } + [upper]

        var included: [SolutionInterval] = []
        for i in 0..<(boundaries.count - 1) {
            let a = boundaries[i]
            let b = boundaries[i + 1]
            let mid = (a + b) / 2
            guard let value = g(mid), holds(value, relation) else { continue }

            // Endpoint inclusivity: an interior boundary that is a root is
            // included for non-strict relations, excluded for strict ones.
            let lowerIsRoot = roots.contains { abs($0 - a) < 1e-9 }
            let upperIsRoot = roots.contains { abs($0 - b) < 1e-9 }
            included.append(SolutionInterval(
                lower: a,
                upper: b,
                lowerInclusive: lowerIsRoot && !relation.isStrict,
                upperInclusive: upperIsRoot && !relation.isStrict
            ))
        }

        if included.isEmpty { return .none }
        let merged = merge(included)
        if merged.count == 1,
           merged[0].lower == lower, merged[0].upper == upper {
            return .all
        }
        return .intervals(merged)
    }

    private static func holds(_ value: Double, _ relation: CalculatorRelation) -> Bool {
        switch relation {
        case .equal: return value == 0
        case .less: return value < 0
        case .lessEqual: return value <= 0
        case .greater: return value > 0
        case .greaterEqual: return value >= 0
        }
    }

    private static func merge(_ intervals: [SolutionInterval]) -> [SolutionInterval] {
        var result: [SolutionInterval] = []
        for interval in intervals {
            if var last = result.last, abs(last.upper - interval.lower) < 1e-9 {
                last.upper = interval.upper
                last.upperInclusive = interval.upperInclusive
                result[result.count - 1] = last
            } else {
                result.append(interval)
            }
        }
        return result
    }
}
