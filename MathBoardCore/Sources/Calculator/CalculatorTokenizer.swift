//
//  CalculatorTokenizer.swift
//  MathBoardCore — Calculator module
//
//  Lexer. Walks a source string and emits a flat `[CalculatorToken]`.
//  Does not interpret meaning — that's the parser's job. Implicit
//  multiplication is NOT inserted here; the parser detects it from
//  token-class adjacency.
//
//  Recognizes:
//    - Decimal numbers including scientific notation (`1.5e-3`)
//    - Identifiers (letters then letters/digits) — function names,
//      constants, and variables all flow through the same `identifier`
//      token; the parser distinguishes by context.
//    - Operators: + - * / ^ ! ( ) ,
//    - Unicode synonyms: × · for multiply, ÷ for divide, π for pi,
//      [ ] for parentheses.
//

import Foundation

public struct CalculatorTokenizer: Sendable {

    public init() {}

    public func tokenize(_ source: String) throws -> [CalculatorToken] {
        var tokens: [CalculatorToken] = []
        let characters = Array(source)
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character.isWhitespace {
                index += 1
                continue
            }

            if character.isNumber || character == "." {
                let (token, nextIndex) = try scanNumber(from: characters, startingAt: index)
                tokens.append(token)
                index = nextIndex
                continue
            }

            if character.isLetter {
                let (token, nextIndex) = scanIdentifier(from: characters, startingAt: index)
                tokens.append(token)
                index = nextIndex
                continue
            }

            switch character {
            case "+":
                tokens.append(.plus)
            case "-", "−":
                tokens.append(.minus)
            case "*", "×", "·", "⋅":
                tokens.append(.star)
            case "/", "÷":
                tokens.append(.slash)
            case "^":
                tokens.append(.caret)
            case "!":
                tokens.append(.bang)
            case "(", "[":
                tokens.append(.lparen)
            case ")", "]":
                tokens.append(.rparen)
            case ",":
                tokens.append(.comma)
            case "|":
                tokens.append(.bar)
            case "π":
                tokens.append(.identifier("pi"))
            case "√":
                tokens.append(.identifier("sqrt"))
            default:
                throw CalculatorError.unexpectedCharacter(character)
            }
            index += 1
        }

        return tokens
    }

    // MARK: - Number scanning

    private func scanNumber(
        from characters: [Character],
        startingAt start: Int
    ) throws -> (CalculatorToken, Int) {
        var index = start
        var raw = ""

        // Integer part / leading decimal point.
        while index < characters.count, characters[index].isNumber {
            raw.append(characters[index])
            index += 1
        }

        if index < characters.count, characters[index] == "." {
            raw.append(".")
            index += 1
            while index < characters.count, characters[index].isNumber {
                raw.append(characters[index])
                index += 1
            }
        }

        // Scientific exponent: e / E with optional sign.
        if index < characters.count, characters[index] == "e" || characters[index] == "E" {
            // Peek ahead — only consume as exponent if followed by sign or digit.
            let after = index + 1
            let hasExponentBody = after < characters.count && (
                characters[after] == "+"
                || characters[after] == "-"
                || characters[after].isNumber
            )
            if hasExponentBody {
                raw.append("e")
                index += 1
                if characters[index] == "+" || characters[index] == "-" {
                    raw.append(characters[index])
                    index += 1
                }
                while index < characters.count, characters[index].isNumber {
                    raw.append(characters[index])
                    index += 1
                }
            }
        }

        guard let value = Double(raw) else {
            throw CalculatorError.malformedNumber(raw)
        }
        return (.number(value), index)
    }

    // MARK: - Identifier scanning

    private func scanIdentifier(
        from characters: [Character],
        startingAt start: Int
    ) -> (CalculatorToken, Int) {
        var index = start
        var name = ""
        while index < characters.count, characters[index].isLetter || characters[index].isNumber {
            name.append(characters[index])
            index += 1
        }
        return (.identifier(name), index)
    }
}
