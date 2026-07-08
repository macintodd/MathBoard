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
    static let lineWidth: Double = 3.0
    static let minimumLineWidth: Double = 1.25
    static let maximumLineWidth: Double = 7.5
}

public struct GraphCalculatorDataTable: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var columnNames: [String]
    public var rows: [[Double?]]

    public init(
        id: UUID = UUID(),
        columnNames: [String] = ["x_1", "y_1"],
        rows: [[Double?]] = [
            [nil, nil],
            [nil, nil],
            [nil, nil],
            [nil, nil],
            [nil, nil]
        ]
    ) {
        self.id = id
        self.columnNames = Array(columnNames.prefix(4))
        self.rows = rows.map { Array($0.prefix(4)) }
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
    public var dataTables: [GraphCalculatorDataTable] = []
    public var folders: [GraphCalculatorFolder] = []
    public var selectedExpressionIndex: Int = 0
    public var graphWindow: GraphWindow = .default
    public var calculatorPosition: CGPoint?
    public var isGraphDetached: Bool = false
    public var detachedGraphPosition: CGPoint?
    public var detachedGraphSize: CGSize = CGSize(width: 520, height: 390)
    public var detachedControlPosition: CGPoint?
    public var isKeypadCollapsed: Bool = false
    public var isTableVisible: Bool = false
    public var isFunctionMenuVisible: Bool = false
    public var isAddMenuVisible: Bool = false
    public var isGraphSettingsVisible: Bool = false

    // Graph appearance settings (wired into the renderer).
    public var axisStrokeWidth: Double = 1.4
    public var gridlineThickness: Double = 0.8
    public var isGridVisible: Bool = true
    public var xAxisLabel: String = ""
    public var yAxisLabel: String = ""
    public var isHandDrawnStyle: Bool = true
    public var sliderValues: [String: Double] = [:]
    public var sliderDecisions: [String: Bool] = [:]
    public var sliderMinimums: [String: Double] = [:]
    public var sliderMaximums: [String: Double] = [:]
    public var tableXValues: [Double] = [-2, -1, 0, 1, 2]
    public var cursorOffset: Int = 0

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

    public func addDataTable() {
        dataTables.append(GraphCalculatorDataTable())
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

    public func updateTableXValue(at index: Int, by delta: Double) {
        guard tableXValues.indices.contains(index) else { return }
        tableXValues[index] += delta
    }

    public func addTableXValue() {
        let next = (tableXValues.last ?? 0) + 1
        tableXValues.append(next)
    }

    public func deleteTableXValue(at index: Int) {
        guard tableXValues.indices.contains(index), tableXValues.count > 1 else { return }
        tableXValues.remove(at: index)
    }

    public func updateDataTableColumnName(tableID: UUID, columnIndex: Int, name: String) {
        guard let tableIndex = dataTables.firstIndex(where: { $0.id == tableID }),
              dataTables[tableIndex].columnNames.indices.contains(columnIndex) else {
            return
        }
        dataTables[tableIndex].columnNames[columnIndex] = name
    }

    public func updateDataTableValue(tableID: UUID, rowIndex: Int, columnIndex: Int, value: Double?) {
        guard let tableIndex = dataTables.firstIndex(where: { $0.id == tableID }) else { return }
        while dataTables[tableIndex].rows.count <= rowIndex {
            dataTables[tableIndex].rows.append(Array(repeating: nil, count: dataTables[tableIndex].columnNames.count))
        }
        while dataTables[tableIndex].rows[rowIndex].count < dataTables[tableIndex].columnNames.count {
            dataTables[tableIndex].rows[rowIndex].append(nil)
        }
        guard dataTables[tableIndex].rows[rowIndex].indices.contains(columnIndex) else { return }
        dataTables[tableIndex].rows[rowIndex][columnIndex] = value
    }

    public func addDataTableColumn(tableID: UUID) {
        guard let tableIndex = dataTables.firstIndex(where: { $0.id == tableID }),
              dataTables[tableIndex].columnNames.count < 4 else {
            return
        }
        let next = dataTables[tableIndex].columnNames.count + 1
        dataTables[tableIndex].columnNames.append("x\(next)")
        for rowIndex in dataTables[tableIndex].rows.indices {
            dataTables[tableIndex].rows[rowIndex].append(nil)
        }
    }

    public func addDataTableRow(tableID: UUID) {
        guard let tableIndex = dataTables.firstIndex(where: { $0.id == tableID }) else { return }
        dataTables[tableIndex].rows.append(Array(repeating: nil, count: dataTables[tableIndex].columnNames.count))
    }

    public func deleteDataTableRow(tableID: UUID, rowIndex: Int) {
        guard let tableIndex = dataTables.firstIndex(where: { $0.id == tableID }),
              dataTables[tableIndex].rows.indices.contains(rowIndex),
              dataTables[tableIndex].rows.count > 1 else {
            return
        }
        dataTables[tableIndex].rows.remove(at: rowIndex)
    }

    public func deleteDataTable(tableID: UUID) {
        dataTables.removeAll { $0.id == tableID }
    }
}
