//
//  CalculatorEquationSolverTests.swift
//  MathBoardCore — Calculator module tests
//
//  Pure-logic coverage for the 1-Variable equation/inequality solver.
//

import XCTest
@testable import Calculator

final class CalculatorEquationSolverTests: XCTestCase {

    private let solver = CalculatorEquationSolver(variable: "x")
    private let domain = -50.0...50.0

    private func roots(_ input: String) -> [Double] {
        if case .discrete(let values) = solver.solve(input, domain: domain) { return values }
        return []
    }

    // MARK: - Relation splitting

    func testSplitDetectsRelations() {
        XCTAssertEqual(CalculatorEquationSolver.split("x = 3").0, .equal)
        XCTAssertEqual(CalculatorEquationSolver.split("2x < 4").0, .less)
        XCTAssertEqual(CalculatorEquationSolver.split("x <= 1").0, .lessEqual)
        XCTAssertEqual(CalculatorEquationSolver.split("x ≤ 1").0, .lessEqual)
        XCTAssertEqual(CalculatorEquationSolver.split("x > 0").0, .greater)
        XCTAssertEqual(CalculatorEquationSolver.split("x ≥ 0").0, .greaterEqual)
        XCTAssertEqual(CalculatorEquationSolver.split("x^2 - 4").0, .equal) // no operator → = 0
    }

    // MARK: - Equality

    func testLinearEquation() {
        XCTAssertEqual(roots("2x + 1 = 5"), [2])
    }

    func testSimpleEquality() {
        XCTAssertEqual(roots("x = 3"), [3])
    }

    func testQuadraticTwoRoots() {
        XCTAssertEqual(roots("x^2 = 4"), [-2, 2])
    }

    func testAbsoluteValueEquation() {
        // |x - 3| = 2  → x = 1, 5  (the screenshot example)
        XCTAssertEqual(roots("|x-3| = 2"), [1, 5])
    }

    func testNoRealSolution() {
        XCTAssertEqual(roots("x^2 = -1"), [])
    }

    func testNoOperatorSolvesForZero() {
        XCTAssertEqual(roots("x^2 - 9"), [-3, 3])
    }

    // MARK: - Inequalities

    func testStrictLessThanInterval() {
        // 2x < 4  → x < 2
        guard case .intervals(let intervals) = solver.solve("2x < 4", domain: domain) else {
            return XCTFail("expected intervals")
        }
        XCTAssertEqual(intervals.count, 1)
        XCTAssertEqual(intervals[0].upper, 2, accuracy: 1e-4)
        XCTAssertFalse(intervals[0].upperInclusive, "strict < is exclusive at the boundary")
    }

    func testGreaterEqualSplitsIntoTwoIntervals() {
        // x^2 >= 4  → x ≤ -2 OR x ≥ 2
        guard case .intervals(let intervals) = solver.solve("x^2 >= 4", domain: domain) else {
            return XCTFail("expected intervals")
        }
        XCTAssertEqual(intervals.count, 2)
        XCTAssertEqual(intervals[0].upper, -2, accuracy: 1e-4)
        XCTAssertTrue(intervals[0].upperInclusive, "≥ includes the boundary root")
        XCTAssertEqual(intervals[1].lower, 2, accuracy: 1e-4)
        XCTAssertTrue(intervals[1].lowerInclusive)
    }

    func testAlwaysTrueInequality() {
        // x^2 + 1 > 0 is true everywhere
        XCTAssertEqual(solver.solve("x^2 + 1 > 0", domain: domain), .all)
    }

    func testNeverTrueInequality() {
        // x^2 < -1 is true nowhere
        XCTAssertEqual(solver.solve("x^2 < -1", domain: domain), .none)
    }

    // MARK: - Errors / empty

    func testInvalidEquationReportsError() {
        if case .error = solver.solve("x +", domain: domain) {
            // expected
        } else {
            XCTFail("expected error for malformed input")
        }
    }

    func testEmptyInputIsNone() {
        XCTAssertEqual(solver.solve("   ", domain: domain), .none)
    }
}

final class CompoundInequalityTests: XCTestCase {

    private let solver = CalculatorEquationSolver(variable: "x")
    private let domain = -50.0...50.0

    func testAndProducesBoundedInterval() {
        // x > 2 and x < 5  →  2 < x < 5
        guard case .intervals(let intervals) = solver.solve("x > 2 and x < 5", domain: domain) else {
            return XCTFail("expected intervals")
        }
        XCTAssertEqual(intervals.count, 1)
        XCTAssertEqual(intervals[0].lower, 2, accuracy: 1e-4)
        XCTAssertEqual(intervals[0].upper, 5, accuracy: 1e-4)
        XCTAssertFalse(intervals[0].lowerInclusive)
        XCTAssertFalse(intervals[0].upperInclusive)
    }

    func testOrProducesTwoRays() {
        // x < 1 or x > 3  →  two intervals
        guard case .intervals(let intervals) = solver.solve("x < 1 or x > 3", domain: domain) else {
            return XCTFail("expected intervals")
        }
        XCTAssertEqual(intervals.count, 2)
        XCTAssertEqual(intervals[0].upper, 1, accuracy: 1e-4)
        XCTAssertEqual(intervals[1].lower, 3, accuracy: 1e-4)
    }

    func testContradictoryAndIsNone() {
        // x < 1 and x > 3  →  no solution
        XCTAssertEqual(solver.solve("x < 1 and x > 3", domain: domain), .none)
    }

    func testAndOfBoundsCollapsesToPoint() {
        // x >= 2 and x <= 2  →  x = 2
        XCTAssertEqual(solver.solve("x >= 2 and x <= 2", domain: domain), .discrete([2]))
    }
}

final class SolutionRegionTests: XCTestCase {

    private let domain = -50.0...50.0

    private func interval(_ lo: Double, _ hi: Double, _ loInc: Bool = true, _ hiInc: Bool = true) -> SolutionInterval {
        SolutionInterval(lower: lo, upper: hi, lowerInclusive: loInc, upperInclusive: hiInc)
    }

    func testIntersectionOverlap() {
        let a = SolutionRegion(intervals: [interval(0, 10)])
        let b = SolutionRegion(intervals: [interval(5, 15)])
        let result = SolutionRegion.combine(a, b, mode: .and, domain: domain)
        XCTAssertEqual(result.intervals.count, 1)
        XCTAssertEqual(result.intervals[0].lower, 5, accuracy: 1e-9)
        XCTAssertEqual(result.intervals[0].upper, 10, accuracy: 1e-9)
    }

    func testDisjointUnionStaysTwoIntervals() {
        let a = SolutionRegion(intervals: [interval(0, 2)])
        let b = SolutionRegion(intervals: [interval(5, 8)])
        let result = SolutionRegion.combine(a, b, mode: .or, domain: domain)
        XCTAssertEqual(result.intervals.count, 2)
    }

    func testDisjointIntersectionIsEmpty() {
        let a = SolutionRegion(intervals: [interval(0, 2)])
        let b = SolutionRegion(intervals: [interval(5, 8)])
        let result = SolutionRegion.combine(a, b, mode: .and, domain: domain)
        XCTAssertTrue(result.intervals.isEmpty)
    }

    func testContainsRespectsInclusivity() {
        let region = SolutionRegion(intervals: [interval(0, 5, true, false)])
        XCTAssertTrue(region.contains(0))
        XCTAssertTrue(region.contains(2.5))
        XCTAssertFalse(region.contains(5))   // upper exclusive
        XCTAssertFalse(region.contains(-1))
    }
}

final class AbsoluteValueBarTests: XCTestCase {
    let engine = CalculatorEngine()

    func testAbsBarsEvaluate() throws {
        XCTAssertEqual(try engine.evaluate("|x - 3|", variables: ["x": 1]), 2)
        XCTAssertEqual(try engine.evaluate("|-5|"), 5)
    }

    func testImplicitMultiplyWithBars() throws {
        // 2|x| at x = -4 → 8
        XCTAssertEqual(try engine.evaluate("2|x|", variables: ["x": -4]), 8)
    }

    func testUnmatchedBarThrows() {
        XCTAssertThrowsError(try engine.evaluate("|x - 3")) { error in
            XCTAssertEqual(error as? CalculatorError, .unmatchedAbsBar)
        }
    }
}
