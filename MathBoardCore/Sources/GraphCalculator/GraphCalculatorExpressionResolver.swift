//
//  GraphCalculatorExpressionResolver.swift
//  MathBoardCore - GraphCalculator module
//
//  Desmos-style row interpretation for the native graph calculator.
//

import Foundation
import Calculator

struct GraphCalculatorResolvedRow: Identifiable, Equatable {
    let index: Int
    let source: String
    let plot: GraphCalculatorPlot?
    let displayValue: String?
    let errorMessage: String?

    var id: Int { index }
    var isEmpty: Bool { source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var isValid: Bool { errorMessage == nil }

    var plotExpression: String? {
        switch plot {
        case .curve(let expression), .yRelation(let expression, _), .xRelation(let expression, _), .implicitRelation(let expression):
            return expression
        case .point(let x, let y):
            return "(\(x),\(y))"
        case nil:
            return nil
        }
    }
}

enum GraphCalculatorPlot: Equatable {
    case curve(String)
    case yRelation(String, GraphCalculatorYRelation)
    case xRelation(String, GraphCalculatorXRelation)
    case implicitRelation(String)
    case point(Double, Double)
}

enum GraphCalculatorYRelation: Equatable {
    case equal
    case lessThan
    case lessThanOrEqual
    case greaterThan
    case greaterThanOrEqual

    var shadesBelow: Bool? {
        switch self {
        case .equal: return nil
        case .lessThan, .lessThanOrEqual: return true
        case .greaterThan, .greaterThanOrEqual: return false
        }
    }

    var isStrict: Bool {
        switch self {
        case .lessThan, .greaterThan: return true
        case .equal, .lessThanOrEqual, .greaterThanOrEqual: return false
        }
    }
}

enum GraphCalculatorXRelation: Equatable {
    case equal
    case lessThan
    case lessThanOrEqual
    case greaterThan
    case greaterThanOrEqual

    var shadesLeft: Bool? {
        switch self {
        case .equal: return nil
        case .lessThan, .lessThanOrEqual: return true
        case .greaterThan, .greaterThanOrEqual: return false
        }
    }

    var isStrict: Bool {
        switch self {
        case .lessThan, .greaterThan: return true
        case .equal, .lessThanOrEqual, .greaterThanOrEqual: return false
        }
    }
}

enum GraphCalculatorExpressionResolver {
    private struct FunctionDefinitionContext {
        let definitions: [String: FunctionDefinition]
        let errors: [Int: String]
    }

    static func resolveRows(
        expressions: [GraphEquation],
        engine: CalculatorEngine,
        variableValues: [String: Double] = [:],
        sliderCandidateNames: Set<String> = []
    ) -> [GraphCalculatorResolvedRow] {
        let definitionContext = functionDefinitionContext(from: expressions)
        let scalarValues = scalarVariableValues(in: expressions, engine: engine, variableValues: variableValues, definitionContext: definitionContext)
        let effectiveVariableValues = variableValues.merging(scalarValues) { current, _ in current }

        return expressions.enumerated().map { index, expression in
            resolveRow(
                index: index,
                source: expression.expression,
                definitionContext: definitionContext,
                engine: engine,
                variableValues: effectiveVariableValues,
                sliderCandidateNames: sliderCandidateNames
            )
        }
    }

    static func scalarVariableValues(
        in expressions: [GraphEquation],
        engine: CalculatorEngine,
        variableValues: [String: Double] = [:]
    ) -> [String: Double] {
        scalarVariableValues(
            in: expressions,
            engine: engine,
            variableValues: variableValues,
            definitionContext: functionDefinitionContext(from: expressions)
        )
    }

    private static func scalarVariableValues(
        in expressions: [GraphEquation],
        engine: CalculatorEngine,
        variableValues: [String: Double],
        definitionContext: FunctionDefinitionContext
    ) -> [String: Double] {
        var values = variableValues
        var scalarValues: [String: Double] = [:]

        for _ in 0..<max(expressions.count, 1) {
            var changed = false
            for expression in expressions {
                guard let definition = ScalarDefinition(source: expression.expression),
                      scalarValues[definition.name] == nil,
                      let compiled = try? engine.compile(normalizeImplicitVariableProducts(in: expandFunctionCalls(in: definition.body, definitions: definitionContext.definitions))),
                      let value = try? engine.evaluate(compiled: compiled, angleMode: .radians, variables: values) else {
                    continue
                }
                scalarValues[definition.name] = value
                values[definition.name] = value
                changed = true
            }
            if !changed { break }
        }

        return scalarValues
    }

    private static func resolveRow(
        index: Int,
        source: String,
        definitionContext: FunctionDefinitionContext,
        engine: CalculatorEngine,
        variableValues: [String: Double],
        sliderCandidateNames: Set<String>
    ) -> GraphCalculatorResolvedRow {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return GraphCalculatorResolvedRow(index: index, source: source, plot: nil, displayValue: nil, errorMessage: nil)
        }

        let rawPlot: GraphCalculatorPlot
        if usesReservedYFunctionNotation(trimmed) {
            return GraphCalculatorResolvedRow(index: index, source: source, plot: nil, displayValue: nil, errorMessage: "Use y=, not y( )")
        } else if let error = definitionContext.errors[index] {
            return GraphCalculatorResolvedRow(index: index, source: source, plot: nil, displayValue: nil, errorMessage: error)
        } else if let scalarDefinition = ScalarDefinition(source: trimmed) {
            do {
                let expandedBody = normalizeImplicitVariableProducts(in: expandFunctionCalls(in: scalarDefinition.body, definitions: definitionContext.definitions))
                let compiled = try engine.compile(expandedBody)
                if let value = try? engine.evaluate(compiled: compiled, angleMode: .radians, variables: variableValues) {
                    return GraphCalculatorResolvedRow(index: index, source: source, plot: nil, displayValue: CalculatorResultFormatter.string(for: value), errorMessage: nil)
                }
                return GraphCalculatorResolvedRow(index: index, source: source, plot: nil, displayValue: nil, errorMessage: "Define missing variables")
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? "Cannot define this variable"
                return GraphCalculatorResolvedRow(index: index, source: source, plot: nil, displayValue: nil, errorMessage: message)
            }
        } else if let point = OrderedPairExpression(source: trimmed) {
            rawPlot = .point(point.x, point.y)
        } else if let definition = FunctionDefinition(source: trimmed) {
            let expandedBody = expandFunctionCalls(in: definition.body, definitions: definitionContext.definitions)
            rawPlot = .curve(substitute(variable: definition.variable, in: expandedBody, with: "x"))
        } else if let relation = RelationExpression(source: trimmed) {
            rawPlot = relation.plot
        } else if let equals = trimmed.firstIndex(of: "=") {
            rawPlot = .curve(String(trimmed[trimmed.index(after: equals)...]).trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            rawPlot = .curve(trimmed)
        }

        let plot = normalizeImplicitVariableProducts(in: expandFunctionCalls(in: rawPlot, definitions: definitionContext.definitions))
        if case .point = plot {
            return GraphCalculatorResolvedRow(index: index, source: source, plot: plot, displayValue: nil, errorMessage: nil)
        }
        let expanded = plot.expression
        guard !expanded.isEmpty else {
            return GraphCalculatorResolvedRow(index: index, source: source, plot: nil, displayValue: nil, errorMessage: "Expression is empty")
        }
        let unresolved = unresolvedVariableNames(in: expanded, variableValues: variableValues)
        if !unresolved.isEmpty {
            let message = unresolved.allSatisfy { sliderCandidateNames.contains($0) }
                ? "Define \(unresolved.joined(separator: ", ")) or make slider"
                : "Define \(unresolved.joined(separator: ", "))"
            return GraphCalculatorResolvedRow(index: index, source: source, plot: nil, displayValue: nil, errorMessage: message)
        }

        do {
            let compiled = try engine.compile(expanded)
            let hasX = containsStandaloneX(expanded) || plot.isXRelation
            let displayValue: String?
            if hasX {
                displayValue = nil
            } else if let value = try? engine.evaluate(compiled: compiled, variables: variableValues) {
                displayValue = CalculatorResultFormatter.string(for: value)
            } else {
                displayValue = nil
            }
            if case .curve = plot, !hasX {
                return GraphCalculatorResolvedRow(index: index, source: source, plot: nil, displayValue: displayValue, errorMessage: nil)
            }
            return GraphCalculatorResolvedRow(index: index, source: source, plot: plot, displayValue: displayValue, errorMessage: nil)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "Cannot graph this expression"
            return GraphCalculatorResolvedRow(index: index, source: source, plot: nil, displayValue: nil, errorMessage: message)
        }
    }

    private static func usesReservedYFunctionNotation(_ source: String) -> Bool {
        let compact = source.replacingOccurrences(of: " ", with: "")
        guard let equals = compact.firstIndex(of: "="),
              let openParen = compact.firstIndex(of: "("),
              let closeParen = compact.firstIndex(of: ")"),
              openParen < closeParen,
              closeParen < equals else {
            return false
        }
        return String(compact[..<openParen]).lowercased() == "y"
    }

    private static func functionDefinitionContext(from expressions: [GraphEquation]) -> FunctionDefinitionContext {
        let parsed = expressions.enumerated().compactMap { index, expression -> (index: Int, definition: FunctionDefinition)? in
            guard let definition = FunctionDefinition(source: expression.expression) else { return nil }
            return (index, definition)
        }
        let functionNames = Set(parsed.map(\.definition.name))
        var definitions: [String: FunctionDefinition] = [:]
        var errors: [Int: String] = [:]

        for item in parsed {
            if functionNames.contains(item.definition.variable) {
                errors[item.index] = "\(item.definition.variable)( ) is already a function"
            } else {
                definitions[item.definition.name] = item.definition
            }
        }

        return FunctionDefinitionContext(definitions: definitions, errors: errors)
    }

    private static func unresolvedVariableNames(in expression: String, variableValues: [String: Double]) -> [String] {
        let known = Set(variableValues.keys)
        var names: Set<String> = []
        for identifier in identifiers(in: expression) {
            guard identifier.count == 1,
                  !known.contains(identifier),
                  !["x", "y", "e"].contains(identifier),
                  !reservedFunctionIdentifiers.contains(identifier) else {
                continue
            }
            names.insert(identifier)
        }
        return names.sorted()
    }

    private static func identifiers(in source: String) -> [String] {
        var identifiers: [String] = []
        var current = ""

        func flushCurrent() {
            guard !current.isEmpty else { return }
            let lower = current.lowercased()
            if reservedFunctionIdentifiers.contains(lower) || lower.count == 1 {
                identifiers.append(lower)
            } else {
                identifiers.append(contentsOf: lower.map(String.init))
            }
            current = ""
        }

        for character in source {
            if character.isLetter {
                current.append(character)
            } else {
                flushCurrent()
            }
        }
        flushCurrent()
        return identifiers
    }

    private static func expandFunctionCalls(
        in plot: GraphCalculatorPlot,
        definitions: [String: FunctionDefinition]
    ) -> GraphCalculatorPlot {
        switch plot {
        case .curve(let expression):
            return .curve(expandFunctionCalls(in: expression, definitions: definitions))
        case .yRelation(let expression, let relation):
            return .yRelation(expandFunctionCalls(in: expression, definitions: definitions), relation)
        case .xRelation(let expression, let relation):
            return .xRelation(expandFunctionCalls(in: expression, definitions: definitions), relation)
        case .implicitRelation(let expression):
            return .implicitRelation(expandFunctionCalls(in: expression, definitions: definitions))
        case .point:
            return plot
        }
    }

    private static func normalizeImplicitVariableProducts(in plot: GraphCalculatorPlot) -> GraphCalculatorPlot {
        switch plot {
        case .curve(let expression):
            return .curve(normalizeImplicitVariableProducts(in: expression))
        case .yRelation(let expression, let relation):
            return .yRelation(normalizeImplicitVariableProducts(in: expression), relation)
        case .xRelation(let expression, let relation):
            return .xRelation(normalizeImplicitVariableProducts(in: expression), relation)
        case .implicitRelation(let expression):
            return .implicitRelation(normalizeImplicitVariableProducts(in: expression))
        case .point:
            return plot
        }
    }

    private static func normalizeImplicitVariableProducts(in expression: String) -> String {
        var output = ""
        var currentIdentifier = ""

        func flushIdentifier() {
            guard !currentIdentifier.isEmpty else { return }
            output += normalizedIdentifier(currentIdentifier)
            currentIdentifier = ""
        }

        for character in expression {
            if character.isLetter {
                currentIdentifier.append(character)
            } else {
                flushIdentifier()
                output.append(character)
            }
        }
        flushIdentifier()

        return output
    }

    private static func normalizedIdentifier(_ identifier: String) -> String {
        let lower = identifier.lowercased()
        let reserved: Set<String> = [
            "pi", "theta",
            "sin", "cos", "tan", "asin", "acos", "atan",
            "sqrt", "abs", "log", "ln", "min", "max"
        ]
        guard identifier.count > 1, !reserved.contains(lower) else { return identifier }
        return identifier.map(String.init).joined(separator: "*")
    }

    private static func expandFunctionCalls(
        in expression: String,
        definitions: [String: FunctionDefinition],
        depth: Int = 0
    ) -> String {
        guard depth < 6, !definitions.isEmpty else { return expression }

        var output = ""
        var index = expression.startIndex

        while index < expression.endIndex {
            let character = expression[index]
            if character.isLetter,
               let openParen = expression.index(index, offsetBy: 1, limitedBy: expression.endIndex),
               openParen < expression.endIndex,
               expression[openParen] == "(",
               let definition = definitions[String(character)],
               let closeParen = matchingCloseParen(in: expression, openIndex: openParen) {
                let rawArgument = String(expression[expression.index(after: openParen)..<closeParen])
                let expandedArgument = expandFunctionCalls(in: rawArgument, definitions: definitions, depth: depth + 1)
                let substituted = substitute(variable: definition.variable, in: definition.body, with: expandedArgument)
                output += "(\(expandFunctionCalls(in: substituted, definitions: definitions, depth: depth + 1)))"
                index = expression.index(after: closeParen)
            } else {
                output.append(character)
                index = expression.index(after: index)
            }
        }

        return output
    }

    private static func matchingCloseParen(in expression: String, openIndex: String.Index) -> String.Index? {
        var depth = 0
        var index = openIndex
        while index < expression.endIndex {
            if expression[index] == "(" {
                depth += 1
            } else if expression[index] == ")" {
                depth -= 1
                if depth == 0 { return index }
            }
            index = expression.index(after: index)
        }
        return nil
    }

    private static func substitute(variable: String, in body: String, with argument: String) -> String {
        var output = ""
        var index = body.startIndex

        while index < body.endIndex {
            let character = body[index]
            if String(character) == variable,
               !isInsideReservedIdentifier(at: index, in: body) {
                if needsImplicitProduct(before: index, in: body) {
                    output += "*"
                }
                output += "(\(argument))"
                if needsImplicitProduct(after: index, in: body) {
                    output += "*"
                }
            } else {
                output.append(character)
            }
            index = body.index(after: index)
        }

        return output
    }

    private static func isInsideReservedIdentifier(at index: String.Index, in text: String) -> Bool {
        guard text[index].isLetter else { return false }
        var start = index
        var end = text.index(after: index)

        while start > text.startIndex {
            let previous = text.index(before: start)
            guard text[previous].isLetter else { break }
            start = previous
        }

        while end < text.endIndex, text[end].isLetter {
            end = text.index(after: end)
        }

        let identifier = String(text[start..<end]).lowercased()
        return identifier.count > 1 && reservedFunctionIdentifiers.contains(identifier)
    }

    private static func needsImplicitProduct(before index: String.Index, in text: String) -> Bool {
        guard index > text.startIndex else { return false }
        let previous = text[text.index(before: index)]
        return previous.isLetter || previous.isNumber || previous == ")"
    }

    private static func needsImplicitProduct(after index: String.Index, in text: String) -> Bool {
        let next = text.index(after: index)
        guard next < text.endIndex else { return false }
        let character = text[next]
        return character.isLetter || character.isNumber || character == "("
    }

    private static func containsStandaloneX(_ expression: String) -> Bool {
        var index = expression.startIndex
        while index < expression.endIndex {
            if expression[index] == "x",
               isIdentifierBoundary(before: index, in: expression),
               isIdentifierBoundary(after: index, in: expression) {
                return true
            }
            index = expression.index(after: index)
        }
        return false
    }

    private static func isIdentifierBoundary(before index: String.Index, in text: String) -> Bool {
        guard index > text.startIndex else { return true }
        let previous = text[text.index(before: index)]
        return !previous.isLetter && !previous.isNumber
    }

    private static func isIdentifierBoundary(after index: String.Index, in text: String) -> Bool {
        let next = text.index(after: index)
        guard next < text.endIndex else { return true }
        let character = text[next]
        return !character.isLetter && !character.isNumber
    }

    private static let reservedFunctionIdentifiers: Set<String> = [
        "pi", "theta",
        "sin", "cos", "tan", "asin", "acos", "atan",
        "sqrt", "abs", "log", "ln", "min", "max"
    ]

    private struct RelationExpression {
        let plot: GraphCalculatorPlot

        init?(source: String) {
            let compact = source.replacingOccurrences(of: " ", with: "")
            guard let match = Self.firstRelation(in: compact) else { return nil }

            let left = String(compact[..<match.range.lowerBound])
            let right = String(compact[match.range.upperBound...])
            guard !left.isEmpty, !right.isEmpty else { return nil }

            if left == "y" {
                plot = .yRelation(right, match.relation)
            } else if right == "y" {
                plot = .yRelation(left, match.relation.inverted)
            } else if left == "x" {
                plot = .xRelation(right, GraphCalculatorXRelation(match.relation))
            } else if right == "x" {
                plot = .xRelation(left, GraphCalculatorXRelation(match.relation.inverted))
            } else if match.relation == .equal,
                      Self.isXYOnlyRelation(left: left, right: right) {
                plot = .implicitRelation("(\(left))-(\(right))")
            } else {
                return nil
            }
        }

        private static func isXYOnlyRelation(left: String, right: String) -> Bool {
            let names = Set(GraphCalculatorExpressionResolver.identifiers(in: "\(left) \(right)"))
            return !names.isEmpty
                && names.isSubset(of: ["x", "y", "e", "pi"])
                && (names.contains("x") || names.contains("y"))
        }

        private static func firstRelation(in source: String) -> (range: Range<String.Index>, relation: GraphCalculatorYRelation)? {
            let operators: [(String, GraphCalculatorYRelation)] = [
                ("<=", .lessThanOrEqual),
                ("≥", .greaterThanOrEqual),
                ("≤", .lessThanOrEqual),
                (">=", .greaterThanOrEqual),
                ("<", .lessThan),
                (">", .greaterThan),
                ("=", .equal)
            ]

            return operators
                .compactMap { symbol, relation in
                    source.range(of: symbol).map { (range: $0, relation: relation) }
                }
                .min { $0.range.lowerBound < $1.range.lowerBound }
        }
    }

    private struct FunctionDefinition: Equatable {
        let name: String
        let variable: String
        let body: String

        init?(source: String) {
            let trimmed = source.replacingOccurrences(of: " ", with: "")
            guard trimmed.count >= 6,
                  let equals = trimmed.firstIndex(of: "="),
                  let openParen = trimmed.firstIndex(of: "("),
                  let closeParen = trimmed.firstIndex(of: ")"),
                  openParen < closeParen,
                  closeParen < equals else {
                return nil
            }

            let name = String(trimmed[..<openParen])
            let variable = String(trimmed[trimmed.index(after: openParen)..<closeParen])
            let body = String(trimmed[trimmed.index(after: equals)...])

            guard name.count == 1,
                  name.first?.isLetter == true,
                  name.lowercased() != "y",
                  variable.count == 1,
                  variable.first?.isLetter == true,
                  !body.isEmpty else {
                return nil
            }

            self.name = name
            self.variable = variable
            self.body = body
        }
    }

    private struct ScalarDefinition: Equatable {
        let name: String
        let body: String

        init?(source: String) {
            let trimmed = source.replacingOccurrences(of: " ", with: "")
            guard !trimmed.contains("("),
                  let equals = trimmed.firstIndex(of: "=") else {
                return nil
            }

            let name = String(trimmed[..<equals]).lowercased()
            let body = String(trimmed[trimmed.index(after: equals)...])
            guard name.count == 1,
                  name.first?.isLetter == true,
                  !["x", "y"].contains(name),
                  !body.isEmpty else {
                return nil
            }

            self.name = name
            self.body = body
        }
    }

    private struct OrderedPairExpression: Equatable {
        let x: Double
        let y: Double

        init?(source: String) {
            let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.first == "(",
                  trimmed.last == ")" else {
                return nil
            }

            let contents = trimmed.dropFirst().dropLast()
            let pieces = contents.split(separator: ",", omittingEmptySubsequences: false)
            guard pieces.count == 2,
                  let x = Double(pieces[0].trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "−", with: "-")),
                  let y = Double(pieces[1].trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "−", with: "-")),
                  x.isFinite,
                  y.isFinite else {
                return nil
            }

            self.x = x
            self.y = y
        }
    }
}

private extension GraphCalculatorPlot {
    var expression: String {
        switch self {
        case .curve(let expression), .yRelation(let expression, _), .xRelation(let expression, _), .implicitRelation(let expression):
            return expression
        case .point(let x, let y):
            return "(\(x),\(y))"
        }
    }

    var isXRelation: Bool {
        if case .xRelation = self { return true }
        return false
    }
}

private extension GraphCalculatorYRelation {
    var inverted: GraphCalculatorYRelation {
        switch self {
        case .equal: return .equal
        case .lessThan: return .greaterThan
        case .lessThanOrEqual: return .greaterThanOrEqual
        case .greaterThan: return .lessThan
        case .greaterThanOrEqual: return .lessThanOrEqual
        }
    }
}

private extension GraphCalculatorXRelation {
    init(_ relation: GraphCalculatorYRelation) {
        switch relation {
        case .equal: self = .equal
        case .lessThan: self = .lessThan
        case .lessThanOrEqual: self = .lessThanOrEqual
        case .greaterThan: self = .greaterThan
        case .greaterThanOrEqual: self = .greaterThanOrEqual
        }
    }
}
