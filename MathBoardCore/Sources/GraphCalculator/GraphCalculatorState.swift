//
//  GraphCalculatorState.swift
//  MathBoardCore - GraphCalculator module
//
//  Isolated state for the Desmos-style teaching graph calculator prototype.
//

import CoreGraphics
import Foundation
import Observation
import Calculator

enum GraphCalculatorStyleDefaults {
    static let lineWidth: Double = 4.5
    static let minimumLineWidth: Double = 1.25
    static let maximumLineWidth: Double = 9.0
}

/// A point readout the teacher has tapped out on the graph, such as an x-intercept.
/// Rendered on the canvas as a highlighted dot with its ordered-pair label.
public struct GraphCalculatorPointReadout: Equatable, Sendable {
    /// What kind of notable point this is. Each kind gets its own glowing-dot color.
    public enum Kind: Hashable, Sendable {
        case xIntercept
        case yIntercept
        case intersection
        case plottedPoint
    }

    public var x: Double
    public var y: Double
    /// Index of the expression row this point belongs to, used to color the marker.
    public var expressionIndex: Int?
    public var kind: Kind

    public init(x: Double, y: Double, expressionIndex: Int? = nil, kind: Kind = .xIntercept) {
        self.x = x
        self.y = y
        self.expressionIndex = expressionIndex
        self.kind = kind
    }
}

/// A single editable ordered pair in a point row's attached data table. Values are optional so
/// cells can be blank while the teacher is typing.
public struct GraphOrderedPair: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var x: Double?
    public var y: Double?

    public init(id: UUID = UUID(), x: Double? = nil, y: Double? = nil) {
        self.id = id
        self.x = x
        self.y = y
    }
}

/// Start/step settings for a function (`y = f(x)`) table. These also seed the graph trace step.
public struct GraphFunctionTableSettings: Equatable, Sendable {
    public var start: Double
    public var delta: Double

    public init(start: Double = 0, delta: Double = 1) {
        self.start = start
        self.delta = delta
    }
}

/// The single table window that is currently open, tied to the equation row that owns it.
public struct GraphActiveTable: Equatable, Sendable {
    public enum Kind: Sendable, Equatable {
        /// `y = f(x)` — auto-generated x | f(x) rows with a settings gear.
        case function
        /// A typed ordered pair with teacher-added extra points — editable x | y rows, no gear.
        case points
    }

    public var equationID: UUID
    public var kind: Kind

    public init(equationID: UUID, kind: Kind) {
        self.equationID = equationID
        self.kind = kind
    }
}

public struct GraphCalculatorFolder: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String

    public init(id: UUID = UUID(), name: String = "Folder") {
        self.id = id
        self.name = name
    }
}

@MainActor
@Observable
public final class GraphCalculatorState {
    public var title: String = "Untitled Graph"
    public var expressions: [GraphEquation]
    public var folders: [GraphCalculatorFolder] = []
    public var selectedExpressionIndex: Int = 0
    public var graphWindow: GraphWindow = .default
    public var calculatorPosition: CGPoint?
    public var isGraphDetached: Bool = false
    public var detachedGraphPosition: CGPoint?
    public var detachedGraphSize: CGSize = CGSize(width: 520, height: 390)
    public var detachedControlPosition: CGPoint?
    public var isKeypadCollapsed: Bool = false
    public var isFunctionMenuVisible: Bool = false
    public var isAddMenuVisible: Bool = false
    public var isGraphSettingsVisible: Bool = false

    // Graph appearance settings (wired into the renderer).
    public var axisStrokeWidth: Double = 1.4
    public var gridlineThickness: Double = 0.8
    public var gridlineOpacity: Double = 0.24
    public var isGridVisible: Bool = true
    public var xAxisLabel: String = ""
    public var yAxisLabel: String = ""
    public var isHandDrawnStyle: Bool = true
    public var sliderValues: [String: Double] = [:]
    public var sliderDecisions: [String: Bool] = [:]
    public var sliderMinimums: [String: Double] = [:]
    public var sliderMaximums: [String: Double] = [:]
    public var cursorOffset: Int = 0

    /// The graph point the teacher last tapped out (e.g. an x-intercept), shown on the canvas.
    public var selectedPoint: GraphCalculatorPointReadout?

    /// The single open floating table window (one at a time), or nil when none is open.
    public var activeTable: GraphActiveTable?
    /// Persisted position/size of the floating table window.
    public var tableWindowPosition: CGPoint?
    public var tableWindowSize: CGSize = CGSize(width: 340, height: 420)
    /// Per-equation function-table settings, keyed by `GraphEquation.id`.
    public var functionTableSettings: [UUID: GraphFunctionTableSettings] = [:]
    /// Extra teacher-added points for a point row, keyed by `GraphEquation.id`. Does not include
    /// the ordered pair typed into the equation cell itself.
    public var pointRows: [UUID: [GraphOrderedPair]] = [:]
    /// Whether trace mode is on for the open function table. A finger drag on the graph then sets
    /// the table start value, keeping the traced points and the table rows in sync.
    public var isTraceActive: Bool = false
    /// The x of the currently highlighted trace point (a table value `start + n·delta`). May differ
    /// from the table start when the teacher selects a later shown point.
    public var traceSelectedX: Double?

    public init(expressions: [GraphEquation] = [GraphEquation(expression: "", colorIndex: 0)]) {
        self.expressions = expressions.isEmpty ? [GraphEquation(expression: "", colorIndex: 0)] : expressions
    }

    public var selectedExpression: String {
        get {
            guard expressions.indices.contains(selectedExpressionIndex) else { return "" }
            return expressions[selectedExpressionIndex].expression
        }
        set {
            ensureExpression(at: selectedExpressionIndex)
            expressions[selectedExpressionIndex].expression = newValue
            cursorOffset = min(cursorOffset, newValue.count)
        }
    }

    public func ensureExpression(at index: Int) {
        guard index >= 0 else { return }
        while expressions.count <= index {
            expressions.append(GraphEquation(expression: "", colorIndex: expressions.count))
        }
    }

    public func addExpression() {
        expressions.append(GraphEquation(expression: "", colorIndex: expressions.count))
        selectedExpressionIndex = expressions.count - 1
        cursorOffset = 0
        isAddMenuVisible = false
    }

    public func addFolder() {
        folders.append(GraphCalculatorFolder(name: "Folder \(folders.count + 1)"))
        isAddMenuVisible = false
    }

    public func selectExpression(at index: Int) {
        ensureExpression(at: index)
        selectedExpressionIndex = index
        cursorOffset = expressions[selectedExpressionIndex].expression.count
    }

    public func selectPreviousExpression() {
        selectExpression(at: max(0, selectedExpressionIndex - 1))
    }

    public func selectNextExpression() {
        selectExpression(at: selectedExpressionIndex + 1)
    }

    public func deleteExpression(at index: Int) {
        guard expressions.indices.contains(index) else {
            selectExpression(at: index)
            return
        }

        if expressions.count == 1 {
            expressions[0].expression = ""
            selectedExpressionIndex = 0
            cursorOffset = 0
            return
        }

        expressions.remove(at: index)
        selectedExpressionIndex = min(max(0, index), expressions.count - 1)
        cursorOffset = expressions[selectedExpressionIndex].expression.count
    }

    public func clearSelectedExpression() {
        ensureExpression(at: selectedExpressionIndex)
        expressions[selectedExpressionIndex].expression = ""
        cursorOffset = 0
    }

    public func deleteLastCharacter() {
        let text = selectedExpression
        guard cursorOffset > 0, !text.isEmpty else { return }
        let safeOffset = clampedCursorOffset(in: text)
        guard safeOffset > 0,
              let removeIndex = text.index(text.startIndex, offsetBy: safeOffset - 1, limitedBy: text.endIndex) else {
            cursorOffset = 0
            return
        }
        var updated = text
        updated.remove(at: removeIndex)
        selectedExpression = updated
        cursorOffset = max(0, safeOffset - 1)
    }

    public func insert(_ text: String) {
        let expression = selectedExpression
        let insertionOffset = clampedCursorOffset(in: expression)
        let insertionIndex = expression.index(expression.startIndex, offsetBy: insertionOffset, limitedBy: expression.endIndex) ?? expression.endIndex
        selectedExpression = String(expression[..<insertionIndex]) + text + String(expression[insertionIndex...])
        cursorOffset = insertionOffset + text.count
    }

    public func moveCursorLeft() {
        cursorOffset = max(0, cursorOffset - 1)
    }

    public func moveCursorRight() {
        cursorOffset = min(selectedExpression.count, cursorOffset + 1)
    }

    public func resetWindow() {
        graphWindow = .default
    }

    public func ensureSliderDefaults(for names: [String], defaultValue: Double = 0) {
        for name in names where sliderValues[name] == nil {
            sliderValues[name] = defaultValue
        }
    }

    public func approveSlider(named name: String, defaultValue: Double = 0) {
        sliderDecisions[name] = true
        if sliderValues[name] == nil {
            sliderValues[name] = defaultValue
        }
    }

    public func denySlider(named name: String) {
        sliderDecisions[name] = false
        sliderValues.removeValue(forKey: name)
    }

    /// Fully removes a slider so the "create slider" prompt reappears for the variable.
    public func removeSlider(named name: String) {
        sliderDecisions.removeValue(forKey: name)
        sliderValues.removeValue(forKey: name)
        sliderMinimums.removeValue(forKey: name)
        sliderMaximums.removeValue(forKey: name)
    }

    public func sliderMinimum(named name: String) -> Double {
        sliderMinimums[name] ?? -5
    }

    public func sliderMaximum(named name: String) -> Double {
        sliderMaximums[name] ?? 5
    }

    public func setSliderMinimum(named name: String, value: Double) {
        let maximum = sliderMaximum(named: name)
        let adjusted = min(value, maximum - 0.1)
        sliderMinimums[name] = adjusted
        clampSliderValue(named: name)
    }

    public func setSliderMaximum(named name: String, value: Double) {
        let minimum = sliderMinimum(named: name)
        let adjusted = max(value, minimum + 0.1)
        sliderMaximums[name] = adjusted
        clampSliderValue(named: name)
    }

    private func clampSliderValue(named name: String) {
        guard let value = sliderValues[name] else { return }
        sliderValues[name] = min(max(value, sliderMinimum(named: name)), sliderMaximum(named: name))
    }

    private func clampedCursorOffset(in text: String) -> Int {
        min(max(cursorOffset, 0), text.count)
    }

    // MARK: Floating table window

    /// Opens the table window for the given equation, or closes it if it is already open for that
    /// equation. Only one table window is open at a time.
    public func toggleTable(for equationID: UUID, kind: GraphActiveTable.Kind) {
        if activeTable?.equationID == equationID {
            activeTable = nil
        } else {
            activeTable = GraphActiveTable(equationID: equationID, kind: kind)
        }
        isTraceActive = false
        traceSelectedX = nil
    }

    public func closeTable() {
        activeTable = nil
        isTraceActive = false
        traceSelectedX = nil
    }

    // MARK: Function-table settings

    public func functionTableSettings(for id: UUID) -> GraphFunctionTableSettings {
        functionTableSettings[id] ?? GraphFunctionTableSettings()
    }

    public func setFunctionTableStart(_ value: Double, for id: UUID) {
        var settings = functionTableSettings(for: id)
        settings.start = value
        functionTableSettings[id] = settings
    }

    public func setFunctionTableDelta(_ value: Double, for id: UUID) {
        // A zero step would generate an infinite column of the same x; ignore it.
        guard value != 0 else { return }
        var settings = functionTableSettings(for: id)
        settings.delta = value
        functionTableSettings[id] = settings
    }

    // MARK: Point-row attached points

    public func extraPoints(for id: UUID) -> [GraphOrderedPair] {
        pointRows[id] ?? []
    }

    public func addExtraPoint(for id: UUID) {
        pointRows[id, default: []].append(GraphOrderedPair())
    }

    public func updateExtraPointX(for id: UUID, pairID: UUID, value: Double?) {
        guard let index = pointRows[id]?.firstIndex(where: { $0.id == pairID }) else { return }
        pointRows[id]?[index].x = value
    }

    public func updateExtraPointY(for id: UUID, pairID: UUID, value: Double?) {
        guard let index = pointRows[id]?.firstIndex(where: { $0.id == pairID }) else { return }
        pointRows[id]?[index].y = value
    }

    public func deleteExtraPoint(for id: UUID, pairID: UUID) {
        pointRows[id]?.removeAll { $0.id == pairID }
        if pointRows[id]?.isEmpty == true {
            pointRows.removeValue(forKey: id)
        }
    }
}
