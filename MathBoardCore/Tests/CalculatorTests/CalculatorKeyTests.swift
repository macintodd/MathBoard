//
//  CalculatorKeyTests.swift
//  MathBoardCore — Calculator module tests
//
//  Pure-logic coverage for the compute-mode key model: the expression
//  reducer, the result formatter, and a sanity check on the default
//  keypad layout. No SwiftUI host required.
//

import XCTest
@testable import Calculator

final class ExpressionReducerTests: XCTestCase {

    func testInsertAppends() {
        XCTAssertEqual(
            CalculatorExpressionReducer.reduce(expression: "2", action: .insert("+")),
            "2+"
        )
        XCTAssertEqual(
            CalculatorExpressionReducer.reduce(expression: "sin", action: .insert("(")),
            "sin("
        )
    }

    func testBuildUpExpressionByInserts() {
        var expression = ""
        for text in ["2", "sin(", "30", ")"] {
            expression = CalculatorExpressionReducer.reduce(expression: expression, action: .insert(text))
        }
        XCTAssertEqual(expression, "2sin(30)")
    }

    func testDeleteBackwardDropsLastCharacter() {
        XCTAssertEqual(
            CalculatorExpressionReducer.reduce(expression: "12+", action: .deleteBackward),
            "12"
        )
    }

    func testDeleteBackwardOnEmptyIsSafe() {
        XCTAssertEqual(
            CalculatorExpressionReducer.reduce(expression: "", action: .deleteBackward),
            ""
        )
    }

    func testClearEmptiesExpression() {
        XCTAssertEqual(
            CalculatorExpressionReducer.reduce(expression: "1+2+3", action: .clear),
            ""
        )
    }

    func testEvaluateAndToggleLeaveTextUnchanged() {
        XCTAssertEqual(
            CalculatorExpressionReducer.reduce(expression: "5*5", action: .evaluate),
            "5*5"
        )
        XCTAssertEqual(
            CalculatorExpressionReducer.reduce(expression: "5*5", action: .toggleAngleMode),
            "5*5"
        )
    }
}

final class ResultFormatterTests: XCTestCase {

    func testIntegersHaveNoDecimal() {
        XCTAssertEqual(CalculatorResultFormatter.string(for: 3), "3")
        XCTAssertEqual(CalculatorResultFormatter.string(for: 120), "120")
        XCTAssertEqual(CalculatorResultFormatter.string(for: -7), "−7")
    }

    func testZero() {
        XCTAssertEqual(CalculatorResultFormatter.string(for: 0), "0")
    }

    func testFractionalValues() {
        XCTAssertEqual(CalculatorResultFormatter.string(for: 0.5), "0.5")
        XCTAssertEqual(CalculatorResultFormatter.string(for: 2.25), "2.25")
    }

    func testNonFinite() {
        XCTAssertEqual(CalculatorResultFormatter.string(for: .infinity), "∞")
        XCTAssertEqual(CalculatorResultFormatter.string(for: -.infinity), "−∞")
        XCTAssertEqual(CalculatorResultFormatter.string(for: .nan), "NaN")
    }

    func testLargeMagnitudeUsesScientific() {
        let text = CalculatorResultFormatter.string(for: 1e20)
        XCTAssertTrue(text.contains("e"), "Expected scientific notation, got \(text)")
    }

    func testSmallMagnitudeUsesScientific() {
        let text = CalculatorResultFormatter.string(for: 1e-9)
        XCTAssertTrue(text.contains("e"), "Expected scientific notation, got \(text)")
    }

    func testNegativeSignIsUnicodeMinus() {
        XCTAssertFalse(CalculatorResultFormatter.string(for: -2.5).contains("-"))
        XCTAssertTrue(CalculatorResultFormatter.string(for: -2.5).contains("−"))
    }
}

final class KeypadLayoutTests: XCTestCase {

    func testLayoutIsNonEmptyAndRowsHaveKeys() {
        let layout = CalculatorKeypadLayout.compute
        XCTAssertFalse(layout.isEmpty)
        for row in layout {
            XCTAssertFalse(row.isEmpty)
        }
    }

    func testLayoutContainsDigitsZeroThroughNine() {
        let labels = CalculatorKeypadLayout.compute.flatMap { $0 }.map(\.label)
        for digit in 0...9 {
            XCTAssertTrue(labels.contains("\(digit)"), "Missing digit \(digit)")
        }
    }

    func testLayoutContainsCoreActions() {
        let actions = CalculatorKeypadLayout.compute.flatMap { $0 }.map(\.action)
        XCTAssertTrue(actions.contains(.evaluate))
        XCTAssertTrue(actions.contains(.clear))
        XCTAssertTrue(actions.contains(.deleteBackward))
        XCTAssertTrue(actions.contains(.toggleAngleMode))
    }

    func testKeyIdsAreUnique() {
        let ids = CalculatorKeypadLayout.compute.flatMap { $0 }.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Keypad has duplicate key ids: \(ids)")
    }

    func testFunctionKeysInsertCallSyntax() {
        let keys = CalculatorKeypadLayout.compute.flatMap { $0 }
        let sinKey = keys.first { $0.label == "sin" }
        XCTAssertEqual(sinKey?.action, .insert("sin("))
        let sqrtKey = keys.first { $0.label == "√" }
        XCTAssertEqual(sqrtKey?.action, .insert("sqrt("))
    }

    // MARK: - v2 TI-84-style additions

    func testLayoutHasSecondModifier() {
        let actions = CalculatorKeypadLayout.compute.flatMap { $0 }.map(\.action)
        XCTAssertTrue(actions.contains(.toggleSecond))
    }

    func testTrigKeysHaveInverseSecondary() {
        let keys = CalculatorKeypadLayout.compute.flatMap { $0 }
        XCTAssertEqual(keys.first { $0.label == "sin" }?.secondAction, .insert("asin("))
        XCTAssertEqual(keys.first { $0.label == "cos" }?.secondAction, .insert("acos("))
        XCTAssertEqual(keys.first { $0.label == "tan" }?.secondAction, .insert("atan("))
    }

    func testLogKeysHaveSecondary() {
        let keys = CalculatorKeypadLayout.compute.flatMap { $0 }
        XCTAssertEqual(keys.first { $0.label == "log" }?.secondAction, .insert("10^("))
        XCTAssertEqual(keys.first { $0.label == "ln" }?.secondAction, .insert("e^("))
    }

    func testAnsAndConstantsPresent() {
        let keys = CalculatorKeypadLayout.compute.flatMap { $0 }
        XCTAssertTrue(keys.contains { $0.action == .insert("ans") })
        XCTAssertTrue(keys.contains { $0.label == "π" && $0.action == .insert("pi") })
        XCTAssertTrue(keys.contains { $0.label == "e" && $0.action == .insert("e") })
    }

    func testPowerAndSquareKeysPresent() {
        let keys = CalculatorKeypadLayout.compute.flatMap { $0 }
        XCTAssertTrue(keys.contains { $0.label == "x²" && $0.action == .insert("^2") })
        XCTAssertTrue(keys.contains { $0.label == "xⁿ" && $0.action == .insert("^") })
    }

    func testVariableReciprocalAndCubeRootKeysPresent() {
        let keys = CalculatorKeypadLayout.compute.flatMap { $0 }
        XCTAssertTrue(keys.contains { $0.label == "x" && $0.action == .insert("x") })
        XCTAssertTrue(keys.contains { $0.label == "x⁻¹" && $0.action == .insert("^-1") })
        XCTAssertTrue(keys.contains { $0.label == "∛" && $0.action == .insert("cbrt(") })
    }

    func testKeysWithoutSecondaryReportNoSecond() {
        let keys = CalculatorKeypadLayout.compute.flatMap { $0 }
        XCTAssertEqual(keys.first { $0.label == "7" }?.hasSecond, false)
        XCTAssertEqual(keys.first { $0.label == "sin" }?.hasSecond, true)
    }
}

final class GraphKeypadLayoutTests: XCTestCase {

    private func labels(_ family: GraphFunctionFamily) -> [String] {
        GraphKeypadLayout.keys(for: family).flatMap { $0 }.map(\.label)
    }

    func testEveryFamilyHasBaseKeys() {
        for family in GraphFunctionFamily.allCases {
            let labels = labels(family)
            XCTAssertTrue(labels.contains("x"), "\(family) missing x")
            XCTAssertTrue(labels.contains("⌫"), "\(family) missing backspace")
            for digit in 0...9 {
                XCTAssertTrue(labels.contains("\(digit)"), "\(family) missing digit \(digit)")
            }
        }
    }

    func testLinearHasNoPowerKeys() {
        let labels = labels(.linear)
        XCTAssertFalse(labels.contains("x²"))
        XCTAssertFalse(labels.contains("^"))
        XCTAssertFalse(labels.contains("sin"))
    }

    func testQuadraticHasSquareNotCube() {
        let labels = labels(.quadratic)
        XCTAssertTrue(labels.contains("x²"))
        XCTAssertFalse(labels.contains("x³"))
    }

    func testPolynomialHasCubeAndPower() {
        let labels = labels(.polynomial)
        XCTAssertTrue(labels.contains("x²"))
        XCTAssertTrue(labels.contains("x³"))
        XCTAssertTrue(labels.contains("^"))
    }

    func testTrigHasTrigKeys() {
        let labels = labels(.trig)
        XCTAssertTrue(labels.contains("sin"))
        XCTAssertTrue(labels.contains("cos"))
        XCTAssertTrue(labels.contains("tan"))
        XCTAssertTrue(labels.contains("π"))
    }

    func testExponentialHasLogKeys() {
        let labels = labels(.exponential)
        XCTAssertTrue(labels.contains("ln"))
        XCTAssertTrue(labels.contains("log"))
        XCTAssertTrue(labels.contains("eˣ"))
    }

    func testOnlyTrigShowsAngleToggle() {
        XCTAssertTrue(GraphFunctionFamily.trig.showsAngleToggle)
        XCTAssertFalse(GraphFunctionFamily.linear.showsAngleToggle)
        XCTAssertFalse(GraphFunctionFamily.general.showsAngleToggle)
    }

    func testOneVariableKeypadHasRelationsAndConnectives() {
        let keys = GraphKeypadLayout.keys(for: .oneVariable).flatMap { $0 }
        XCTAssertTrue(keys.contains { $0.action == .insert("=") })
        XCTAssertTrue(keys.contains { $0.action == .insert("<") })
        XCTAssertTrue(keys.contains { $0.action == .insert("<=") })
        XCTAssertTrue(keys.contains { $0.action == .insert(">") })
        XCTAssertTrue(keys.contains { $0.action == .insert(">=") })
        XCTAssertTrue(keys.contains { $0.action == .insert(" and ") })
        XCTAssertTrue(keys.contains { $0.action == .insert(" or ") })
        XCTAssertTrue(keys.contains { $0.label == "x" })
        // Per the redesign: no abs-bar, parens, or arithmetic operators.
        XCTAssertFalse(keys.contains { $0.action == .insert("|") })
        XCTAssertFalse(keys.contains { $0.label == "(" })
    }

    func testOneVariableIsFlaggedAndNotAngleToggle() {
        XCTAssertTrue(GraphFunctionFamily.oneVariable.isOneVariable)
        XCTAssertFalse(GraphFunctionFamily.oneVariable.showsAngleToggle)
        XCTAssertFalse(GraphFunctionFamily.linear.isOneVariable)
    }
}

final class SolutionFormatterTests: XCTestCase {
    private let domain = -50.0...50.0

    func testDiscreteFormatting() {
        XCTAssertEqual(
            CalculatorSolutionFormatter.describe(.discrete([1, 5]), domain: domain),
            "x = 1, 5"
        )
    }

    func testEmptyDiscreteIsNoSolution() {
        XCTAssertEqual(
            CalculatorSolutionFormatter.describe(.discrete([]), domain: domain),
            "No solution in view"
        )
    }

    func testIntervalOneSidedUpper() {
        // x < 2 : interval spans from the domain's bottom up to 2 (exclusive)
        let interval = SolutionInterval(lower: -50, upper: 2, lowerInclusive: false, upperInclusive: false)
        XCTAssertEqual(
            CalculatorSolutionFormatter.describe(.intervals([interval]), domain: domain),
            "x < 2"
        )
    }

    func testTwoSidedIntervalsJoinedWithOr() {
        let left = SolutionInterval(lower: -50, upper: -2, lowerInclusive: false, upperInclusive: true)
        let right = SolutionInterval(lower: 2, upper: 50, lowerInclusive: true, upperInclusive: false)
        XCTAssertEqual(
            CalculatorSolutionFormatter.describe(.intervals([left, right]), domain: domain),
            "x ≤ −2  or  x ≥ 2"
        )
    }
}

final class AnsEvaluationTests: XCTestCase {
    let engine = CalculatorEngine()

    func testAnsVariableInjection() throws {
        // Simulates the compute view passing the previous answer as `ans`.
        let result = try engine.evaluate("ans + 1", variables: ["ans": 41])
        XCTAssertEqual(result, 42)
    }

    func testAnsChainedExpression() throws {
        let result = try engine.evaluate("ans * 2", variables: ["ans": 21])
        XCTAssertEqual(result, 42)
    }

    func testAnsUndefinedWithoutPriorAnswer() {
        XCTAssertThrowsError(try engine.evaluate("ans + 1")) { error in
            XCTAssertEqual(error as? CalculatorError, .undefinedVariable("ans"))
        }
    }
}
