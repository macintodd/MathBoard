//
//  GraphCalculatorVariableScanner.swift
//  MathBoardCore - GraphCalculator module
//
//  Pure expression scanning helpers used by the graph calculator UI and tests.
//

import Foundation

enum GraphCalculatorVariableScanner {
    static func sliderNames(in sources: [String]) -> [String] {
        var names: Set<String> = []
        let functionDefinitions = sources.compactMap(FunctionSignature.init(source:))
        let functionNames = Set(functionDefinitions.map(\.name))
        let inputVariables = Set(functionDefinitions.map(\.variable))
        let calledFunctionNames = Set(sources.flatMap(functionCallNames(in:)))

        for source in sources {
            guard let scanSource = sliderEligibleExpressionBody(in: source) else { continue }
            for identifier in identifiers(in: scanSource)
            where isSliderCandidate(
                identifier,
                functionNames: functionNames,
                inputVariables: inputVariables,
                calledFunctionNames: calledFunctionNames
            ) {
                names.insert(identifier)
            }
        }
        return names.sorted()
    }

    private static func sliderEligibleExpressionBody(in source: String) -> String? {
        if let function = FunctionSignature(source: source) {
            return function.body
        }

        let compact = source.replacingOccurrences(of: " ", with: "")
        guard let relation = firstRelationRange(in: compact) else { return nil }
        let left = String(compact[..<relation.lowerBound])
        let right = String(compact[relation.upperBound...])
        if left == "y", !right.isEmpty {
            return right
        }
        if right == "y", !left.isEmpty {
            return left
        }
        return nil
    }

    private static func firstRelationRange(in source: String) -> Range<String.Index>? {
        ["<=", "≥", "≤", ">=", "<", ">", "="]
            .compactMap { source.range(of: $0) }
            .min { $0.lowerBound < $1.lowerBound }
    }

    private static func identifiers(in source: String) -> [String] {
        var identifiers: [String] = []
        var current = ""

        func flushCurrent() {
            guard !current.isEmpty else { return }
            let lower = current.lowercased()
            if reservedFunctionNames.contains(lower) || lower.count == 1 {
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

    private static func functionCallNames(in source: String) -> [String] {
        let compact = source.replacingOccurrences(of: " ", with: "")
        var names: [String] = []
        var index = compact.startIndex

        while index < compact.endIndex {
            let character = compact[index]
            if character.isLetter,
               let next = compact.index(index, offsetBy: 1, limitedBy: compact.endIndex),
               next < compact.endIndex,
               compact[next] == "(" {
                names.append(String(character).lowercased())
            }
            index = compact.index(after: index)
        }

        return names
    }

    private static func isSliderCandidate(
        _ identifier: String,
        functionNames: Set<String>,
        inputVariables: Set<String>,
        calledFunctionNames: Set<String>
    ) -> Bool {
        let reserved = Set(["x", "y", "pi", "e"]).union(reservedFunctionNames)
        return identifier.count == 1
            && !reserved.contains(identifier)
            && !functionNames.contains(identifier)
            && !inputVariables.contains(identifier)
            && !calledFunctionNames.contains(identifier)
    }

    private static let reservedFunctionNames: Set<String> = [
        "sin", "cos", "tan", "asin", "acos", "atan",
        "sqrt", "abs", "log", "ln", "min", "max"
    ]

    private struct FunctionSignature {
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

            let name = String(trimmed[..<openParen]).lowercased()
            let variable = String(trimmed[trimmed.index(after: openParen)..<closeParen]).lowercased()
            let body = String(trimmed[trimmed.index(after: equals)...])

            guard name.count == 1,
                  name.first?.isLetter == true,
                  name != "y",
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
}
