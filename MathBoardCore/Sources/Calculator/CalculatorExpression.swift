//
//  CalculatorExpression.swift
//  MathBoardCore — Calculator module
//
//  AST produced by `CalculatorParser` and consumed by
//  `CalculatorEvaluator`. Indirect so the recursive cases compose.
//

import Foundation

public indirect enum CalculatorExpression: Equatable, Sendable {
    case number(Double)
    case identifier(String)           // constant (pi, e) or variable (x, y, a, …)
    case unary(CalculatorUnaryOp, CalculatorExpression)
    case binary(CalculatorBinaryOp, CalculatorExpression, CalculatorExpression)
    case factorial(CalculatorExpression)
    case function(name: String, arguments: [CalculatorExpression])
}

public enum CalculatorBinaryOp: String, Sendable, Equatable {
    case add, subtract, multiply, divide, power
}

public enum CalculatorUnaryOp: String, Sendable, Equatable {
    case negate
}
