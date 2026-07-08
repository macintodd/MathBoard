//
//  CalculatorStateTests.swift
//  MathBoardCore — Calculator module tests
//
//  Pure-logic coverage for `CalculatorState`'s defaults, persistence
//  round-tripping, and "visibility is per-session" rule. Each test
//  creates an isolated `UserDefaults` suite and tears it down at the
//  end so they don't pollute the host's defaults.
//

import XCTest
@testable import Calculator

@MainActor
final class CalculatorStateTests: XCTestCase {

    private var suiteName: String!
    private var store: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "calculator.tests.\(UUID().uuidString)"
        store = UserDefaults(suiteName: suiteName)
        XCTAssertNotNil(store, "Could not create isolated UserDefaults suite")
    }

    override func tearDown() async throws {
        store.removePersistentDomain(forName: suiteName)
        store = nil
        suiteName = nil
        try await super.tearDown()
    }

    // MARK: - Defaults

    func testDefaultsOnFirstLaunch() {
        let state = CalculatorState(store: store)
        XCTAssertFalse(state.isVisible)
        XCTAssertEqual(state.mode, .compute)
        XCTAssertEqual(state.angleMode, .degrees)
        XCTAssertNil(state.position)
        XCTAssertEqual(state.computeExpression, "")
        XCTAssertEqual(state.graphEquations.count, 1)
        XCTAssertEqual(state.graphEquations.first?.expression, "")
        XCTAssertEqual(state.graphWindow, .default)
    }

    func testGraphWindowDefaultIsPlusMinusTen() {
        let window = GraphWindow.default
        XCTAssertEqual(window.xMin, -10)
        XCTAssertEqual(window.xMax, 10)
        XCTAssertEqual(window.yMin, -10)
        XCTAssertEqual(window.yMax, 10)
        XCTAssertEqual(window.width, 20)
        XCTAssertEqual(window.height, 20)
        XCTAssertTrue(window.isValid)
    }

    // MARK: - Mode round-trip

    func testModePersistsAcrossInstances() {
        let writer = CalculatorState(store: store)
        writer.mode = .compute

        let reader = CalculatorState(store: store)
        XCTAssertEqual(reader.mode, .compute)
    }

    func testModeToggledHelper() {
        XCTAssertEqual(CalculatorMode.graph.toggled, .compute)
        XCTAssertEqual(CalculatorMode.compute.toggled, .graph)
    }

    // MARK: - Angle mode round-trip

    func testAngleModePersistsAcrossInstances() {
        let writer = CalculatorState(store: store)
        writer.angleMode = .radians

        let reader = CalculatorState(store: store)
        XCTAssertEqual(reader.angleMode, .radians)
    }

    // MARK: - Position round-trip

    func testPositionPersistsAcrossInstances() {
        let writer = CalculatorState(store: store)
        writer.position = CGPoint(x: 123.5, y: 456.25)

        let reader = CalculatorState(store: store)
        XCTAssertEqual(reader.position?.x, 123.5)
        XCTAssertEqual(reader.position?.y, 456.25)
    }

    func testClearingPositionRemovesItFromDefaults() {
        let writer = CalculatorState(store: store)
        writer.position = CGPoint(x: 50, y: 60)
        writer.position = nil

        let reader = CalculatorState(store: store)
        XCTAssertNil(reader.position)
    }

    // MARK: - Expression round-trip

    func testComputeAndGraphExpressionsPersistIndependently() {
        let writer = CalculatorState(store: store)
        writer.computeExpression = "2 + 3 * 4"
        writer.graphEquations = [GraphEquation(expression: "sin(x) + 1", colorIndex: 0)]

        let reader = CalculatorState(store: store)
        XCTAssertEqual(reader.computeExpression, "2 + 3 * 4")
        XCTAssertEqual(reader.graphEquations.first?.expression, "sin(x) + 1")
    }

    // MARK: - Multiple graph equations

    func testGraphEquationsPersistAndRoundTrip() {
        let writer = CalculatorState(store: store)
        writer.graphEquations = [
            GraphEquation(expression: "x^2", colorIndex: 0),
            GraphEquation(expression: "2x", colorIndex: 1, isEnabled: false)
        ]

        let reader = CalculatorState(store: store)
        XCTAssertEqual(reader.graphEquations.count, 2)
        XCTAssertEqual(reader.graphEquations[0].expression, "x^2")
        XCTAssertEqual(reader.graphEquations[1].expression, "2x")
        XCTAssertEqual(reader.graphEquations[1].isEnabled, false)
    }

    func testAddEquationUsesNextColorIndex() {
        let state = CalculatorState(store: store)
        XCTAssertEqual(state.graphEquations.count, 1)
        state.addEquation()
        XCTAssertEqual(state.graphEquations.count, 2)
        XCTAssertEqual(state.graphEquations[1].colorIndex, 1)
    }

    func testRemoveEquationNeverLeavesListEmpty() {
        let state = CalculatorState(store: store)
        let onlyID = state.graphEquations[0].id
        state.removeEquation(id: onlyID)
        XCTAssertEqual(state.graphEquations.count, 1, "Removing the last equation must leave a fresh empty one")
        XCTAssertEqual(state.graphEquations[0].expression, "")
    }

    func testLegacyGraphExpressionMigratesToEquation() {
        // Simulate a pre-v3 install that stored the old single-expression key.
        store.set("cos(x)", forKey: "calculator.expression.graph")

        let state = CalculatorState(store: store)
        XCTAssertEqual(state.graphEquations.count, 1)
        XCTAssertEqual(state.graphEquations[0].expression, "cos(x)")
    }

    func testGraphFamilyDefaultsToGeneralAndPersists() {
        let fresh = CalculatorState(store: store)
        XCTAssertEqual(fresh.graphKeypadFamily, .general)

        fresh.graphKeypadFamily = .quadratic
        let reader = CalculatorState(store: store)
        XCTAssertEqual(reader.graphKeypadFamily, .quadratic)
    }

    func testOneVarConnectiveDefaultsAndPersists() {
        let fresh = CalculatorState(store: store)
        XCTAssertEqual(fresh.oneVarConnective, .none)
        XCTAssertFalse(fresh.oneVarShowSolution)

        fresh.oneVarConnective = .or
        fresh.oneVarShowSolution = true
        let reader = CalculatorState(store: store)
        XCTAssertEqual(reader.oneVarConnective, .or)
        XCTAssertTrue(reader.oneVarShowSolution)
    }

    func testOneVarConnectiveCombineMapping() {
        XCTAssertNil(OneVarConnective.none.combineMode)
        XCTAssertEqual(OneVarConnective.and.combineMode, .and)
        XCTAssertEqual(OneVarConnective.or.combineMode, .or)
    }

    func testPaletteIndexWraps() {
        let count = GraphPalette.colors.count
        let first = GraphPalette.rgb(for: 0)
        let wrapped = GraphPalette.rgb(for: count)
        XCTAssertEqual(first.red, wrapped.red)
        XCTAssertEqual(first.green, wrapped.green)
        XCTAssertEqual(first.blue, wrapped.blue)
    }

    // MARK: - Graph window round-trip

    func testGraphWindowPersistsAcrossInstances() {
        let writer = CalculatorState(store: store)
        writer.graphWindow = GraphWindow(xMin: -5, xMax: 5, yMin: -2, yMax: 12)

        let reader = CalculatorState(store: store)
        XCTAssertEqual(reader.graphWindow.xMin, -5)
        XCTAssertEqual(reader.graphWindow.xMax, 5)
        XCTAssertEqual(reader.graphWindow.yMin, -2)
        XCTAssertEqual(reader.graphWindow.yMax, 12)
    }

    func testInvalidGraphWindowDetected() {
        var window = GraphWindow.default
        XCTAssertTrue(window.isValid)

        // Reversed axis.
        window.xMin = 5
        window.xMax = -5
        XCTAssertFalse(window.isValid)

        // Non-finite.
        window = GraphWindow.default
        window.yMax = .infinity
        XCTAssertFalse(window.isValid)
    }

    // MARK: - Visibility is per-session

    func testVisibilityDoesNotPersist() {
        let writer = CalculatorState(store: store)
        writer.isVisible = true

        let reader = CalculatorState(store: store)
        XCTAssertFalse(reader.isVisible, "Visibility must reset every session")
    }

    // MARK: - Repeated assignment of same value avoids redundant writes

    func testAssigningSameValueIsNoOp() {
        let state = CalculatorState(store: store)
        state.mode = .graph        // unchanged from default
        state.angleMode = .degrees // unchanged from default
        state.computeExpression = "" // unchanged from default

        // Nothing should have been written to UserDefaults.
        XCTAssertNil(store.string(forKey: "calculator.mode"))
        XCTAssertNil(store.string(forKey: "calculator.angleMode"))
        XCTAssertNil(store.string(forKey: "calculator.expression.compute"))
    }

    // MARK: - Combined round-trip

    func testFullStateRoundTrip() {
        let writer = CalculatorState(store: store)
        writer.mode = .compute
        writer.angleMode = .radians
        writer.position = CGPoint(x: 200, y: 300)
        writer.computeExpression = "sqrt(2)"
        writer.graphEquations = [GraphEquation(expression: "x^2 - 4", colorIndex: 0)]
        writer.graphWindow = GraphWindow(xMin: -3, xMax: 3, yMin: -5, yMax: 5)

        let reader = CalculatorState(store: store)
        XCTAssertEqual(reader.mode, .compute)
        XCTAssertEqual(reader.angleMode, .radians)
        XCTAssertEqual(reader.position, CGPoint(x: 200, y: 300))
        XCTAssertEqual(reader.computeExpression, "sqrt(2)")
        XCTAssertEqual(reader.graphEquations.first?.expression, "x^2 - 4")
        XCTAssertEqual(reader.graphWindow.xMin, -3)
        XCTAssertEqual(reader.graphWindow.xMax, 3)
        XCTAssertEqual(reader.graphWindow.yMin, -5)
        XCTAssertEqual(reader.graphWindow.yMax, 5)
    }
}
