//
//  CalculatorEngineTests.swift
//  MathBoardCore — Calculator module tests
//
//  Pure-logic coverage for the tokenizer + parser + evaluator. Does
//  not exercise UI, persistence, or graphing — just the math engine.
//
//  XCTest rather than the Swift Testing framework so the suite runs
//  from both `swift test` on the command line and Xcode's test runner
//  without an extra toolchain dependency.
//

import XCTest
@testable import Calculator

final class ArithmeticTests: XCTestCase {
    let engine = CalculatorEngine()

    func testAddAndSubtract() throws {
        XCTAssertEqual(try engine.evaluate("1 + 2"), 3)
        XCTAssertEqual(try engine.evaluate("10 - 3 - 2"), 5) // left-assoc
        XCTAssertEqual(try engine.evaluate("0 - 5"), -5)
    }

    func testMultiplyDivide() throws {
        XCTAssertEqual(try engine.evaluate("3 * 4"), 12)
        XCTAssertEqual(try engine.evaluate("20 / 4 / 2"), 2.5) // left-assoc
        XCTAssertEqual(try engine.evaluate("7 * 6"), 42)
    }

    func testMixedPrecedence() throws {
        XCTAssertEqual(try engine.evaluate("2 + 3 * 4"), 14)
        XCTAssertEqual(try engine.evaluate("2 * 3 + 4"), 10)
        XCTAssertEqual(try engine.evaluate("(2 + 3) * 4"), 20)
        XCTAssertEqual(try engine.evaluate("12 / 4 - 1"), 2)
    }

    func testUnicodeOperators() throws {
        XCTAssertEqual(try engine.evaluate("3 × 4"), 12)
        XCTAssertEqual(try engine.evaluate("12 ÷ 4"), 3)
        XCTAssertEqual(try engine.evaluate("3 · 4"), 12)
    }

    func testDecimalAndScientific() throws {
        XCTAssertEqual(try engine.evaluate("1.5 + 2.5"), 4)
        XCTAssertEqual(try engine.evaluate(".5 + .5"), 1)
        XCTAssertEqual(try engine.evaluate("1.5e2"), 150)
        XCTAssertEqual(try engine.evaluate("3e-2"), 0.03, accuracy: 1e-15)
        XCTAssertEqual(try engine.evaluate("2E10"), 2e10)
    }
}

final class PowerTests: XCTestCase {
    let engine = CalculatorEngine()

    func testPowerIsRightAssociative() throws {
        // 2 ^ (3 ^ 2) = 2 ^ 9 = 512, not (2 ^ 3) ^ 2 = 64
        XCTAssertEqual(try engine.evaluate("2 ^ 3 ^ 2"), 512)
    }

    func testUnaryMinusLooserThanPower() throws {
        // Math convention: -2^2 = -(2^2) = -4
        XCTAssertEqual(try engine.evaluate("-2 ^ 2"), -4)
        XCTAssertEqual(try engine.evaluate("(-2) ^ 2"), 4)
    }

    func testUnaryMinusDoubleNegation() throws {
        XCTAssertEqual(try engine.evaluate("--3"), 3)
        XCTAssertEqual(try engine.evaluate("-(-3)"), 3)
    }

    func testLeadingPlus() throws {
        XCTAssertEqual(try engine.evaluate("+5"), 5)
        XCTAssertEqual(try engine.evaluate("+5 + +3"), 8)
    }

    func testPowerWithFractionalExponent() throws {
        XCTAssertEqual(try engine.evaluate("4 ^ 0.5"), 2, accuracy: 1e-12)
    }
}

final class ImplicitMultiplicationTests: XCTestCase {
    let engine = CalculatorEngine()

    func testNumberTimesVariable() throws {
        let result = try engine.evaluate("2x", variables: ["x": 5])
        XCTAssertEqual(result, 10)
    }

    func testNumberTimesFunction() throws {
        let result = try engine.evaluate("2sin(30)", angleMode: .degrees)
        XCTAssertEqual(result, 1, accuracy: 1e-12)
    }

    func testNumberTimesConstant() throws {
        let result = try engine.evaluate("2π")
        XCTAssertEqual(result, 2 * .pi, accuracy: 1e-12)
    }

    func testParenAdjacency() throws {
        // (x+1)(x-1) at x = 5 → 6 * 4 = 24
        let result = try engine.evaluate("(x+1)(x-1)", variables: ["x": 5])
        XCTAssertEqual(result, 24)
    }

    func testNumberAdjacentToParen() throws {
        XCTAssertEqual(try engine.evaluate("2(3 + 4)"), 14)
    }

    func testImplicitWithPower() throws {
        // 2x^2 at x = 3 → 2 * 9 = 18 (power binds tighter than implicit mult)
        let result = try engine.evaluate("2x^2", variables: ["x": 3])
        XCTAssertEqual(result, 18)
    }
}

final class TrigModeTests: XCTestCase {
    let engine = CalculatorEngine()

    func testSinDegrees() throws {
        XCTAssertEqual(try engine.evaluate("sin(30)", angleMode: .degrees), 0.5, accuracy: 1e-12)
    }

    func testSinRadians() throws {
        XCTAssertEqual(try engine.evaluate("sin(pi/6)", angleMode: .radians), 0.5, accuracy: 1e-12)
    }

    func testCosAndTanDegrees() throws {
        XCTAssertEqual(try engine.evaluate("cos(60)", angleMode: .degrees), 0.5, accuracy: 1e-12)
        XCTAssertEqual(try engine.evaluate("tan(45)", angleMode: .degrees), 1, accuracy: 1e-12)
    }

    func testInverseTrigDegrees() throws {
        XCTAssertEqual(try engine.evaluate("asin(0.5)", angleMode: .degrees), 30, accuracy: 1e-12)
    }

    func testInverseTrigRadians() throws {
        XCTAssertEqual(try engine.evaluate("asin(0.5)", angleMode: .radians), .pi / 6, accuracy: 1e-12)
    }

    func testReciprocalTrig() throws {
        XCTAssertEqual(try engine.evaluate("csc(30)", angleMode: .degrees), 2, accuracy: 1e-12)
        XCTAssertEqual(try engine.evaluate("sec(60)", angleMode: .degrees), 2, accuracy: 1e-12)
    }

    func testHyperbolic() throws {
        XCTAssertEqual(try engine.evaluate("sinh(0)"), 0)
        XCTAssertEqual(try engine.evaluate("cosh(0)"), 1)
        XCTAssertEqual(try engine.evaluate("tanh(0)"), 0)
    }
}

final class LogTests: XCTestCase {
    let engine = CalculatorEngine()

    func testBase10LogOneArg() throws {
        XCTAssertEqual(try engine.evaluate("log(100)"), 2)
        XCTAssertEqual(try engine.evaluate("log(1000)"), 3)
    }

    func testArbitraryBaseLogTwoArgs() throws {
        XCTAssertEqual(try engine.evaluate("log(8, 2)"), 3, accuracy: 1e-12)
    }

    func testNaturalLog() throws {
        XCTAssertEqual(try engine.evaluate("ln(e)"), 1, accuracy: 1e-12)
    }

    func testLog2Function() throws {
        XCTAssertEqual(try engine.evaluate("log2(8)"), 3, accuracy: 1e-12)
    }

    func testExpFunction() throws {
        XCTAssertEqual(try engine.evaluate("exp(0)"), 1)
    }
}

final class MiscFunctionTests: XCTestCase {
    let engine = CalculatorEngine()

    func testSquareRoot() throws {
        XCTAssertEqual(try engine.evaluate("sqrt(9)"), 3)
        XCTAssertEqual(try engine.evaluate("sqrt(2)"), Foundation.sqrt(2.0))
        XCTAssertEqual(try engine.evaluate("√(16)"), 4)
    }

    func testCubeRoot() throws {
        XCTAssertEqual(try engine.evaluate("cbrt(27)"), 3, accuracy: 1e-12)
    }

    func testAbsoluteValue() throws {
        XCTAssertEqual(try engine.evaluate("abs(-5)"), 5)
        XCTAssertEqual(try engine.evaluate("abs(7)"), 7)
    }

    func testRoundingFunctions() throws {
        XCTAssertEqual(try engine.evaluate("floor(2.9)"), 2)
        XCTAssertEqual(try engine.evaluate("ceil(2.1)"), 3)
        // Swift's default `.rounded()` rounds half away from zero, which
        // matches what teachers/students expect: 2.5 → 3, 3.5 → 4.
        XCTAssertEqual(try engine.evaluate("round(2.5)"), 3)
        XCTAssertEqual(try engine.evaluate("round(3.5)"), 4)
        XCTAssertEqual(try engine.evaluate("round(-2.5)"), -3)
    }

    func testSignFunction() throws {
        XCTAssertEqual(try engine.evaluate("sign(-3)"), -1)
        XCTAssertEqual(try engine.evaluate("sign(0)"), 0)
        XCTAssertEqual(try engine.evaluate("sign(4)"), 1)
    }

    func testMinMaxMod() throws {
        XCTAssertEqual(try engine.evaluate("min(3, 7)"), 3)
        XCTAssertEqual(try engine.evaluate("max(3, 7)"), 7)
        XCTAssertEqual(try engine.evaluate("mod(10, 3)"), 1)
    }
}

final class FactorialTests: XCTestCase {
    let engine = CalculatorEngine()

    func testSmallFactorials() throws {
        XCTAssertEqual(try engine.evaluate("0!"), 1)
        XCTAssertEqual(try engine.evaluate("1!"), 1)
        XCTAssertEqual(try engine.evaluate("5!"), 120)
    }

    func testFactorialWithMultiplication() throws {
        // 2 * 3! = 12, not (2*3)! = 720 — postfix `!` binds tighter than `*`.
        XCTAssertEqual(try engine.evaluate("2 * 3!"), 12)
    }

    func testFactorialOfNegativeRejected() {
        XCTAssertThrowsError(try engine.evaluate("(-3)!")) { error in
            XCTAssertEqual(error as? CalculatorError, .factorialOfNegative)
        }
    }

    func testFactorialOfNonIntegerRejected() {
        XCTAssertThrowsError(try engine.evaluate("2.5!")) { error in
            XCTAssertEqual(error as? CalculatorError, .factorialOfNonInteger)
        }
    }

    func testFactorialOverflow() {
        XCTAssertThrowsError(try engine.evaluate("171!")) { error in
            XCTAssertEqual(error as? CalculatorError, .factorialOverflow)
        }
    }
}

final class ConstantsAndVariablesTests: XCTestCase {
    let engine = CalculatorEngine()

    func testPiConstant() throws {
        XCTAssertEqual(try engine.evaluate("pi"), .pi)
        XCTAssertEqual(try engine.evaluate("π"), .pi)
    }

    func testEulerConstant() throws {
        XCTAssertEqual(try engine.evaluate("e"), M_E)
    }

    func testVariableEvaluation() throws {
        XCTAssertEqual(try engine.evaluate("x + 1", variables: ["x": 4]), 5)
        XCTAssertEqual(try engine.evaluate("x * y", variables: ["x": 3, "y": 4]), 12)
    }

    func testUndefinedVariableThrows() {
        XCTAssertThrowsError(try engine.evaluate("x + 1")) { error in
            XCTAssertEqual(error as? CalculatorError, .undefinedVariable("x"))
        }
    }

    func testCompileEvaluateLoop() throws {
        // Simulates the graphing pipeline: compile once, evaluate at many x.
        let compiled = try engine.compile("x^2 + 1")
        let xs = stride(from: -2.0, through: 2.0, by: 1.0)
        let ys = try xs.map { try engine.evaluate(compiled: compiled, variables: ["x": $0]) }
        XCTAssertEqual(ys, [5, 2, 1, 2, 5])
    }
}

final class ErrorTests: XCTestCase {
    let engine = CalculatorEngine()

    func testDivisionByZero() {
        XCTAssertThrowsError(try engine.evaluate("1 / 0")) { error in
            XCTAssertEqual(error as? CalculatorError, .divisionByZero)
        }
    }

    func testSqrtOfNegative() {
        XCTAssertThrowsError(try engine.evaluate("sqrt(-1)"))
    }

    func testLnOfZero() {
        XCTAssertThrowsError(try engine.evaluate("ln(0)"))
    }

    func testAsinOutOfRange() {
        XCTAssertThrowsError(try engine.evaluate("asin(2)"))
    }

    func testUnknownFunction() {
        XCTAssertThrowsError(try engine.evaluate("foo(1)")) { error in
            XCTAssertEqual(error as? CalculatorError, .unknownFunction("foo"))
        }
    }

    func testWrongArity() {
        XCTAssertThrowsError(try engine.evaluate("sin(1, 2)")) { error in
            XCTAssertEqual(
                error as? CalculatorError,
                .wrongArgumentCount(function: "sin", expected: 1, got: 2)
            )
        }
    }

    func testUnbalancedParens() {
        XCTAssertThrowsError(try engine.evaluate("(1 + 2")) { error in
            XCTAssertEqual(error as? CalculatorError, .missingClosingParenthesis)
        }
    }

    func testUnexpectedCharacter() {
        XCTAssertThrowsError(try engine.evaluate("1 @ 2")) { error in
            XCTAssertEqual(error as? CalculatorError, .unexpectedCharacter("@"))
        }
    }

    func testEmptyExpression() {
        XCTAssertThrowsError(try engine.evaluate("")) { error in
            XCTAssertEqual(error as? CalculatorError, .unexpectedEnd)
        }
    }
}
