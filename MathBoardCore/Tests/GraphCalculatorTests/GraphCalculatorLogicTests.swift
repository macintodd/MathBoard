//
//  GraphCalculatorLogicTests.swift
//  MathBoardCore - GraphCalculator tests
//
//  Focused pure-logic coverage for expression scanning, row actions, and
//  user-defined function resolution.
//

import XCTest
import Calculator
@testable import GraphCalculator

final class GraphCalculatorLogicTests: XCTestCase {
    func testSliderScannerFindsFunctionBodyVariablesButExcludesInputAndFunctionNames() {
        let names = GraphCalculatorVariableScanner.sliderNames(in: [
            "f(x)=3x+a",
            "g(x)=f(x)+b"
        ])

        XCTAssertEqual(names, ["a", "b"])
    }

    func testSliderScannerFindsRelationVariablesAndIgnoresDefinedScalarVariables() {
        let definedScalars = GraphCalculatorExpressionResolver.scalarVariableValues(
            in: [
                GraphEquation(expression: "k=4"),
                GraphEquation(expression: "y=a+k")
            ],
            engine: CalculatorEngine()
        )
        let candidateNames = GraphCalculatorVariableScanner.sliderNames(in: [
            "k=4",
            "y=a+k"
        ]).filter { definedScalars[$0] == nil }

        XCTAssertEqual(candidateNames, ["a"])
    }

    func testOrphanedSliderNamesAfterDeletingOnlyReferencingExpression() {
        let expressions = [
            GraphEquation(expression: "f(x)=3x+a"),
            GraphEquation(expression: "y=x+1")
        ]

        let names = GraphCalculatorExpressionActions.orphanedSliderNamesAfterDeletingExpression(
            at: 0,
            expressions: expressions
        )

        XCTAssertEqual(names, ["a"])
    }

    func testOrphanedSliderNamesKeepsVariableReferencedByRemainingExpression() {
        let expressions = [
            GraphEquation(expression: "f(x)=3x+a"),
            GraphEquation(expression: "y=a")
        ]

        let names = GraphCalculatorExpressionActions.orphanedSliderNamesAfterDeletingExpression(
            at: 0,
            expressions: expressions
        )

        XCTAssertEqual(names, [])
    }

    func testPasteDownTargetFillsBlankNextRow() {
        let expressions = [
            GraphEquation(expression: "2+3"),
            GraphEquation(expression: "   ")
        ]

        let target = GraphCalculatorExpressionActions.pasteDownTarget(
            sourceIndex: 0,
            expressions: expressions
        )

        XCTAssertEqual(target, .fillExisting(index: 1))
    }

    func testPasteDownTargetInsertsWhenNextRowHasContent() {
        let expressions = [
            GraphEquation(expression: "2+3"),
            GraphEquation(expression: "y=x")
        ]

        let target = GraphCalculatorExpressionActions.pasteDownTarget(
            sourceIndex: 0,
            expressions: expressions
        )

        XCTAssertEqual(target, .insert(after: 0))
    }

    func testFunctionEvaluationRowsResolveToValuesAndNestedFunctionsStillGraph() {
        let rows = [
            GraphEquation(expression: "f(x)=4x+5"),
            GraphEquation(expression: "f(7)"),
            GraphEquation(expression: "g(x)=f(x)+1"),
            GraphEquation(expression: "h(x)=g(x)+f(x)+a")
        ]

        let resolved = GraphCalculatorExpressionResolver.resolveRows(
            expressions: rows,
            engine: CalculatorEngine(),
            variableValues: ["a": 2],
            sliderCandidateNames: ["a"]
        )

        XCTAssertEqual(resolved[1].displayValue, "33")
        XCTAssertNil(resolved[1].plot)
        XCTAssertEqual(resolved[2].plotExpression, "(4*((x))+5)+1")
        XCTAssertEqual(resolved[3].errorMessage, nil)
        XCTAssertNotNil(resolved[3].plotExpression)
    }
}
