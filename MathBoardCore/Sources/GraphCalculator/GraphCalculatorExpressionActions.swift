//
//  GraphCalculatorExpressionActions.swift
//  MathBoardCore - GraphCalculator module
//
//  Pure row-action planning for behavior that is triggered from GraphCalculatorView.
//

import Foundation
import Calculator

enum GraphCalculatorExpressionActions {
    enum PasteDownTarget: Equatable {
        case fillExisting(index: Int)
        case insert(after: Int)
    }

    static func pasteDownTarget(sourceIndex: Int, expressions: [GraphEquation]) -> PasteDownTarget {
        let targetIndex = sourceIndex + 1
        if expressions.indices.contains(targetIndex),
           expressions[targetIndex].expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .fillExisting(index: targetIndex)
        }
        return .insert(after: sourceIndex)
    }

    static func orphanedSliderNamesAfterDeletingExpression(
        at index: Int,
        expressions: [GraphEquation]
    ) -> [String] {
        guard expressions.indices.contains(index) else { return [] }
        let deletedNames = Set(GraphCalculatorVariableScanner.sliderNames(in: [expressions[index].expression]))
        guard !deletedNames.isEmpty else { return [] }

        let remainingExpressions = expressions.enumerated()
            .filter { $0.offset != index }
            .map(\.element.expression)
        let remainingNames = Set(GraphCalculatorVariableScanner.sliderNames(in: remainingExpressions))

        return deletedNames
            .filter { !remainingNames.contains($0) }
            .sorted()
    }
}
