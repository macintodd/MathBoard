//
//  CalculatorToken.swift
//  MathBoardCore — Calculator module
//
//  Tokens produced by `CalculatorTokenizer` and consumed by
//  `CalculatorParser`. The tokenizer does NOT inject implicit-multiply
//  tokens; the parser detects implicit multiplication when it sees a
//  primary-starter immediately after a value/identifier/closing paren.
//

import Foundation

public enum CalculatorToken: Equatable, Sendable {
    case number(Double)
    case identifier(String)
    case plus
    case minus
    case star
    case slash
    case caret
    case bang
    case lparen
    case rparen
    case comma
    case bar          // | … |  absolute-value delimiter

    public var debugDescription: String {
        switch self {
        case .number(let value): return String(value)
        case .identifier(let name): return name
        case .plus: return "+"
        case .minus: return "-"
        case .star: return "*"
        case .slash: return "/"
        case .caret: return "^"
        case .bang: return "!"
        case .lparen: return "("
        case .rparen: return ")"
        case .comma: return ","
        case .bar: return "|"
        }
    }
}
