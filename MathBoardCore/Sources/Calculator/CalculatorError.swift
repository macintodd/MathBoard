//
//  CalculatorError.swift
//  MathBoardCore — Calculator module
//
//  Typed errors emitted by the tokenizer, parser, and evaluator.
//  `errorDescription` is a short human-readable message intended for
//  display in the calculator's result area or as inline validation
//  text under the equation entry field.
//

import Foundation

public enum CalculatorError: Error, Equatable, LocalizedError {
    // Tokenizer
    case unexpectedCharacter(Character)
    case malformedNumber(String)

    // Parser
    case unexpectedToken(description: String)
    case unexpectedEnd
    case missingClosingParenthesis
    case unmatchedAbsBar

    // Evaluator
    case unknownFunction(String)
    case unknownIdentifier(String)
    case wrongArgumentCount(function: String, expected: Int, got: Int)
    case divisionByZero
    case domain(function: String, value: Double)
    case undefinedVariable(String)
    case factorialOfNegative
    case factorialOfNonInteger
    case factorialOverflow

    public var errorDescription: String? {
        switch self {
        case .unexpectedCharacter(let character):
            return "Unexpected character '\(character)'."
        case .malformedNumber(let text):
            return "Couldn’t read a number from '\(text)'."
        case .unexpectedToken(let description):
            return "Unexpected '\(description)'."
        case .unexpectedEnd:
            return "Expression ends too early."
        case .missingClosingParenthesis:
            return "Missing closing parenthesis."
        case .unmatchedAbsBar:
            return "Missing closing | for absolute value."
        case .unknownFunction(let name):
            return "Unknown function '\(name)'."
        case .unknownIdentifier(let name):
            return "Unknown name '\(name)'."
        case .wrongArgumentCount(let function, let expected, let got):
            let plural = expected == 1 ? "" : "s"
            return "\(function) expects \(expected) argument\(plural); got \(got)."
        case .divisionByZero:
            return "Division by zero."
        case .domain(let function, let value):
            return "\(function) is undefined at \(formatValue(value))."
        case .undefinedVariable(let name):
            return "Variable '\(name)' has no value."
        case .factorialOfNegative:
            return "Factorial is only defined for non-negative integers."
        case .factorialOfNonInteger:
            return "Factorial requires an integer."
        case .factorialOverflow:
            return "Factorial result is too large."
        }
    }

    private func formatValue(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 1e15 {
            return String(Int64(value))
        }
        return String(value)
    }
}
