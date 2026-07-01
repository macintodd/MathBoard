//
//  CalculatorEngine.swift
//  MathBoardCore — Calculator module
//
//  Public façade that composes the tokenizer, parser, and evaluator.
//  Two-stage API on purpose: `compile(_:)` returns a reusable
//  `CalculatorExpression` that the graph view can evaluate at many x
//  values without re-parsing the source on every sample point.
//

import Foundation

public struct CalculatorEngine: Sendable {

    private let tokenizer = CalculatorTokenizer()
    private let parser = CalculatorParser()
    private let evaluator = CalculatorEvaluator()

    public init() {}

    /// Tokenize + parse a source expression into a reusable AST.
    public func compile(_ source: String) throws -> CalculatorExpression {
        let tokens = try tokenizer.tokenize(source)
        return try parser.parse(tokens)
    }

    /// Evaluate an already-compiled AST. Use this in graphing loops
    /// where the same expression is sampled over many `x` values.
    public func evaluate(
        compiled expression: CalculatorExpression,
        angleMode: CalculatorAngleMode = .degrees,
        variables: [String: Double] = [:]
    ) throws -> Double {
        try evaluator.evaluate(expression, angleMode: angleMode, variables: variables)
    }

    /// Compile + evaluate in one call. Convenient for the compute-mode
    /// "press equals" code path.
    public func evaluate(
        _ source: String,
        angleMode: CalculatorAngleMode = .degrees,
        variables: [String: Double] = [:]
    ) throws -> Double {
        let expression = try compile(source)
        return try evaluator.evaluate(expression, angleMode: angleMode, variables: variables)
    }
}
