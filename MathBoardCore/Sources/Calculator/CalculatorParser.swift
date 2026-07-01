//
//  CalculatorParser.swift
//  MathBoardCore — Calculator module
//
//  Recursive-descent parser. Implicit multiplication is recognized by
//  `parseTerm`: after a Power expression, if the next token can start a
//  new Primary (number, identifier, or open paren) and is not an
//  explicit `*` / `/`, treat it as multiplication. This handles
//  `2x`, `2sin(x)`, `2π`, `(x+1)(x-1)` uniformly.
//
//  Precedence (lowest → highest):
//      Expression  : Term  (('+' | '-') Term)*           left-assoc
//      Term        : Unary (('*' | '/' | implicit) Unary)*  left-assoc
//      Unary       : ('+' | '-') Unary | Power
//      Power       : Postfix ('^' Power)?                right-assoc
//      Postfix     : Primary ('!')*
//      Primary     : Number
//                  | Identifier ( '(' ArgList ')' )?
//                  | '(' Expression ')'
//      ArgList     : Expression (',' Expression)*
//
//  Note on unary minus vs power: math convention is `-2^2 = -(2^2) = -4`,
//  i.e. `^` binds tighter than unary minus. Hence `parseUnary` calls
//  `parsePower`, not `parsePostfix` directly.
//

import Foundation

public struct CalculatorParser: Sendable {

    public init() {}

    public func parse(_ tokens: [CalculatorToken]) throws -> CalculatorExpression {
        var state = ParseState(tokens: tokens)
        let expression = try state.parseExpression()
        if let leftover = state.peek() {
            throw CalculatorError.unexpectedToken(description: leftover.debugDescription)
        }
        return expression
    }
}

// MARK: - Parse state

private struct ParseState {
    let tokens: [CalculatorToken]
    var position: Int = 0
    /// How many `|…|` groups we're currently inside. A bar only *opens* a
    /// new abs group at depth 0; at depth > 0 a bar means "close", so it
    /// must not be treated as an implicit-multiply primary-starter.
    var barDepth: Int = 0

    func peek() -> CalculatorToken? {
        position < tokens.count ? tokens[position] : nil
    }

    func peek(at offset: Int) -> CalculatorToken? {
        let target = position + offset
        return target < tokens.count ? tokens[target] : nil
    }

    @discardableResult
    mutating func advance() -> CalculatorToken? {
        guard position < tokens.count else { return nil }
        defer { position += 1 }
        return tokens[position]
    }

    mutating func parseExpression() throws -> CalculatorExpression {
        var left = try parseTerm()
        while let token = peek() {
            switch token {
            case .plus:
                advance()
                left = .binary(.add, left, try parseTerm())
            case .minus:
                advance()
                left = .binary(.subtract, left, try parseTerm())
            default:
                return left
            }
        }
        return left
    }

    mutating func parseTerm() throws -> CalculatorExpression {
        var left = try parseUnary()
        while let token = peek() {
            switch token {
            case .star:
                advance()
                left = .binary(.multiply, left, try parseUnary())
            case .slash:
                advance()
                left = .binary(.divide, left, try parseUnary())
            case .number, .identifier, .lparen:
                // Implicit multiplication: a primary-starter follows a value.
                left = .binary(.multiply, left, try parseUnary())
            case .bar where barDepth == 0:
                // A bar at depth 0 opens a new abs group → implicit multiply
                // (e.g. `2|x|`). At depth > 0 the bar closes the current
                // group, so fall through to `default` and stop here.
                left = .binary(.multiply, left, try parseUnary())
            default:
                return left
            }
        }
        return left
    }

    mutating func parseUnary() throws -> CalculatorExpression {
        if case .minus = peek() {
            advance()
            return .unary(.negate, try parseUnary())
        }
        if case .plus = peek() {
            // Leading + is just identity; skip it.
            advance()
            return try parseUnary()
        }
        return try parsePower()
    }

    mutating func parsePower() throws -> CalculatorExpression {
        let base = try parsePostfix()
        if case .caret = peek() {
            advance()
            // Right-associative: `2^3^2` parses as `2^(3^2)`.
            let exponent = try parsePower()
            return .binary(.power, base, exponent)
        }
        return base
    }

    mutating func parsePostfix() throws -> CalculatorExpression {
        var expression = try parsePrimary()
        while case .bang = peek() {
            advance()
            expression = .factorial(expression)
        }
        return expression
    }

    mutating func parsePrimary() throws -> CalculatorExpression {
        guard let token = peek() else { throw CalculatorError.unexpectedEnd }

        switch token {
        case .number(let value):
            advance()
            return .number(value)

        case .identifier(let name):
            advance()
            // Function call if immediately followed by `(`.
            if case .lparen = peek() {
                advance() // consume (
                var arguments: [CalculatorExpression] = []

                if case .rparen = peek() {
                    advance() // empty arg list — let the evaluator reject as wrong arity.
                    return .function(name: name, arguments: arguments)
                }

                arguments.append(try parseExpression())
                while case .comma = peek() {
                    advance()
                    arguments.append(try parseExpression())
                }

                guard case .rparen = peek() else {
                    throw CalculatorError.missingClosingParenthesis
                }
                advance() // consume )
                return .function(name: name, arguments: arguments)
            }
            return .identifier(name)

        case .lparen:
            advance()
            let inner = try parseExpression()
            guard case .rparen = peek() else {
                throw CalculatorError.missingClosingParenthesis
            }
            advance()
            return inner

        case .bar:
            // |expr| → abs(expr). `barDepth` keeps the inner parse from
            // treating the closing bar as a new opening bar.
            advance()
            barDepth += 1
            let inner = try parseExpression()
            guard case .bar = peek() else {
                throw CalculatorError.unmatchedAbsBar
            }
            advance()
            barDepth -= 1
            return .function(name: "abs", arguments: [inner])

        case .rparen, .comma, .plus, .minus, .star, .slash, .caret, .bang:
            throw CalculatorError.unexpectedToken(description: token.debugDescription)
        }
    }
}
