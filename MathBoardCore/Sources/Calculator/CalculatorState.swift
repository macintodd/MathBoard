//
//  CalculatorState.swift
//  MathBoardCore — Calculator module
//
//  Observable state container for the calculator palette. UI views
//  read and mutate it; the integration glue makes a single shared
//  instance available to both the iPad palette and the TV overlay.
//
//  Persistence model (locked in by design):
//    • `isVisible` is NOT persisted — calculator is closed at every
//      fresh lesson open and only the user's tap re-opens it.
//    • Every other property persists across app launches via
//      `UserDefaults`. Each property writes its own key in `didSet`,
//      and the keys are namespaced under "calculator.*".
//    • Position is optional: nil means "never moved" and the view
//      should fall back to its own "center of viewport" default.
//
//  Concurrency: `@MainActor` so the SwiftUI side can mutate it from
//  view callbacks without `await`. Tests pass a custom `UserDefaults`
//  suite name for isolation.
//

import Foundation
import CoreGraphics
import Observation

@MainActor
@Observable
public final class CalculatorState {

    /// App-level shared instance the eventual integration glue will use.
    /// Tests construct their own with a custom `UserDefaults` suite.
    public static let shared = CalculatorState()

    // MARK: - Per-session (not persisted)

    /// Whether the calculator palette is currently shown on the canvas.
    /// Reset to `false` at every fresh lesson open; flipped by the
    /// toolbar button.
    public var isVisible: Bool = false

    /// Last compute-mode result, shared so the external-display mirror
    /// shows the same answer the iPad does. Ephemeral (not persisted).
    public var computeResult: String = ""

    /// Whether `computeResult` represents an error (for red styling).
    /// Ephemeral (not persisted).
    public var computeIsError: Bool = false

    /// Last successful numeric result, injected as the `ans` variable so
    /// expressions can reference the previous answer (TI-style). Ephemeral.
    public var lastAnswer: Double?

    // MARK: - Persisted preferences

    public var mode: CalculatorMode {
        didSet {
            guard oldValue != mode else { return }
            store.set(mode.rawValue, forKey: Keys.mode)
        }
    }

    public var angleMode: CalculatorAngleMode {
        didSet {
            guard oldValue != angleMode else { return }
            store.set(angleMode.rawValue, forKey: Keys.angleMode)
        }
    }

    /// Last drag position in iPad viewport-space points. `nil` means
    /// the user has never moved the palette — the view layer should
    /// place it at the center of its container on first open.
    public var position: CGPoint? {
        didSet {
            guard oldValue != position else { return }
            if let position {
                store.set(Double(position.x), forKey: Keys.positionX)
                store.set(Double(position.y), forKey: Keys.positionY)
            } else {
                store.removeObject(forKey: Keys.positionX)
                store.removeObject(forKey: Keys.positionY)
            }
        }
    }

    /// Last expression entered in compute mode. Restored verbatim into
    /// the entry field when the calculator reopens.
    public var computeExpression: String {
        didSet {
            guard oldValue != computeExpression else { return }
            store.set(computeExpression, forKey: Keys.computeExpression)
        }
    }

    /// The list of `y = f(x)` equations plotted in graph mode (Desmos-style;
    /// each drawn in its palette color). Always has at least one entry.
    public var graphEquations: [GraphEquation] {
        didSet {
            guard oldValue != graphEquations else { return }
            if let data = try? Self.jsonEncoder.encode(graphEquations) {
                store.set(data, forKey: Keys.graphEquations)
            }
        }
    }

    /// Append a new empty equation, colored with the next palette slot.
    public func addEquation() {
        graphEquations.append(GraphEquation(colorIndex: graphEquations.count))
    }

    /// Remove an equation by id. Never leaves the list empty — if the last
    /// one is removed, a fresh empty equation takes its place.
    public func removeEquation(id: UUID) {
        graphEquations.removeAll { $0.id == id }
        if graphEquations.isEmpty {
            graphEquations = [GraphEquation()]
        }
    }

    public var graphWindow: GraphWindow {
        didSet {
            guard oldValue != graphWindow else { return }
            if let data = try? Self.jsonEncoder.encode(graphWindow) {
                store.set(data, forKey: Keys.graphWindow)
            }
        }
    }

    /// The function family that drives which keys the graph entry keypad
    /// shows (e.g. Linear hides `x²`/`^`). Persisted.
    public var graphKeypadFamily: GraphFunctionFamily {
        didSet {
            guard oldValue != graphKeypadFamily else { return }
            store.set(graphKeypadFamily.rawValue, forKey: Keys.graphFamily)
        }
    }

    /// In 1-Variable mode with ≥2 equations, whether the combined number
    /// line shows the intersection (And) or union (Or). Persisted.
    public var graphCombineMode: CombineMode {
        didSet {
            guard oldValue != graphCombineMode else { return }
            store.set(graphCombineMode.rawValue, forKey: Keys.graphCombine)
        }
    }

    /// 1-Variable cell-1 connective dropdown: none (just graph cell 1), or
    /// `and`/`or` which reveals cell 2. Persisted.
    public var oneVarConnective: OneVarConnective {
        didSet {
            guard oldValue != oneVarConnective else { return }
            store.set(oneVarConnective.rawValue, forKey: Keys.oneVarConnective)
        }
    }

    /// 1-Variable cell-2 `=` dropdown: whether the combined solution (3rd)
    /// number line is shown. Persisted.
    public var oneVarShowSolution: Bool {
        didSet {
            guard oldValue != oneVarShowSolution else { return }
            store.set(oneVarShowSolution, forKey: Keys.oneVarShowSolution)
        }
    }

    // MARK: - Init

    private let store: UserDefaults

    public init(store: UserDefaults = .standard) {
        self.store = store

        // Restore mode (default: graph)
        let modeRaw = store.string(forKey: Keys.mode)
        self.mode = modeRaw.flatMap { CalculatorMode(rawValue: $0) } ?? .graph

        // Restore angle mode (default: degrees)
        let angleRaw = store.string(forKey: Keys.angleMode)
        self.angleMode = angleRaw.flatMap { CalculatorAngleMode(rawValue: $0) } ?? .degrees

        // Restore position (default: nil)
        if let x = store.object(forKey: Keys.positionX) as? Double,
           let y = store.object(forKey: Keys.positionY) as? Double {
            self.position = CGPoint(x: x, y: y)
        } else {
            self.position = nil
        }

        // Restore compute expression (default: empty)
        self.computeExpression = store.string(forKey: Keys.computeExpression) ?? ""

        // Restore graph equations. Migrate the old single-expression key
        // into equations[0] if the new key isn't present yet.
        if let data = store.data(forKey: Keys.graphEquations),
           let equations = try? Self.jsonDecoder.decode([GraphEquation].self, from: data),
           !equations.isEmpty {
            self.graphEquations = equations
        } else if let legacy = store.string(forKey: Keys.graphExpression), !legacy.isEmpty {
            self.graphEquations = [GraphEquation(expression: legacy, colorIndex: 0)]
        } else {
            self.graphEquations = [GraphEquation()]
        }

        // Restore graph window (default: ±10 each axis)
        if let data = store.data(forKey: Keys.graphWindow),
           let window = try? Self.jsonDecoder.decode(GraphWindow.self, from: data) {
            self.graphWindow = window
        } else {
            self.graphWindow = .default
        }

        // Restore graph family/topic (default: general)
        let familyRaw = store.string(forKey: Keys.graphFamily)
        self.graphKeypadFamily = familyRaw.flatMap { GraphFunctionFamily(rawValue: $0) } ?? .general

        // Restore And/Or combine mode (default: and)
        let combineRaw = store.string(forKey: Keys.graphCombine)
        self.graphCombineMode = combineRaw.flatMap { CombineMode(rawValue: $0) } ?? .and

        // Restore 1-Variable connective + solution-visibility (defaults)
        let connectiveRaw = store.string(forKey: Keys.oneVarConnective)
        self.oneVarConnective = connectiveRaw.flatMap { OneVarConnective(rawValue: $0) } ?? .none
        self.oneVarShowSolution = store.bool(forKey: Keys.oneVarShowSolution)
    }

    // MARK: - UserDefaults keys

    private enum Keys {
        static let mode = "calculator.mode"
        static let angleMode = "calculator.angleMode"
        static let positionX = "calculator.position.x"
        static let positionY = "calculator.position.y"
        static let computeExpression = "calculator.expression.compute"
        static let graphExpression = "calculator.expression.graph" // legacy (migrated)
        static let graphEquations = "calculator.graph.equations"
        static let graphWindow = "calculator.graph.window"
        static let graphFamily = "calculator.graph.family"
        static let graphCombine = "calculator.graph.combine"
        static let oneVarConnective = "calculator.graph.onevar.connective"
        static let oneVarShowSolution = "calculator.graph.onevar.showSolution"
    }

    private static let jsonEncoder = JSONEncoder()
    private static let jsonDecoder = JSONDecoder()
}

// MARK: - Mode

public enum CalculatorMode: String, Codable, Sendable, CaseIterable, Equatable {
    case graph
    case compute

    public var displayName: String {
        switch self {
        case .graph: return "Graph"
        case .compute: return "Compute"
        }
    }

    /// Toggle between the two modes. Convenience for the mode-toggle
    /// button on the palette title bar.
    public var toggled: CalculatorMode {
        switch self {
        case .graph: return .compute
        case .compute: return .graph
        }
    }
}

// MARK: - Graph window

public struct GraphWindow: Codable, Sendable, Equatable {
    public var xMin: Double
    public var xMax: Double
    public var yMin: Double
    public var yMax: Double

    public init(
        xMin: Double = -10,
        xMax: Double = 10,
        yMin: Double = -10,
        yMax: Double = 10
    ) {
        self.xMin = xMin
        self.xMax = xMax
        self.yMin = yMin
        self.yMax = yMax
    }

    public var width: Double { xMax - xMin }
    public var height: Double { yMax - yMin }

    /// Numeric sanity check used by the graph view to refuse to plot
    /// when the user has typed a degenerate window.
    public var isValid: Bool {
        xMax > xMin
            && yMax > yMin
            && xMin.isFinite && xMax.isFinite
            && yMin.isFinite && yMax.isFinite
    }

    public static let `default` = GraphWindow()
}

// MARK: - Graph equation + color palette

public struct GraphEquation: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    /// The `f(x)` right-hand side to plot (no `y =` prefix).
    public var expression: String
    /// Index into `GraphPalette.colors` (wraps).
    public var colorIndex: Int
    /// Whether this equation is currently plotted.
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        expression: String = "",
        colorIndex: Int = 0,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.expression = expression
        self.colorIndex = colorIndex
        self.isEnabled = isEnabled
    }
}

/// Graph "topic" / function family. Drives which keys the entry keypad
/// shows and (for `.oneVariable`, future) which render mode is used.
/// The 2D-graph families all use the existing plot; `.oneVariable` (number
/// line + solver) is specced but not yet built — see Calculator_status.md.
public enum GraphFunctionFamily: String, Codable, CaseIterable, Sendable {
    case oneVariable
    case linear
    case quadratic
    case polynomial
    case trig
    case exponential
    case general

    public var displayName: String {
        switch self {
        case .oneVariable: return "1 Variable"
        case .linear: return "Linear"
        case .quadratic: return "Quadratic"
        case .polynomial: return "Polynomial"
        case .trig: return "Trigonometric"
        case .exponential: return "Exponential / Log"
        case .general: return "General"
        }
    }

    /// `.oneVariable` solves equations/inequalities on a number line; the
    /// rest plot `y = f(x)` on the 2D graph.
    public var isOneVariable: Bool { self == .oneVariable }

    /// Only trig needs the degree/radian toggle visible.
    public var showsAngleToggle: Bool { self == .trig }
}

/// Fixed curve-color palette, shared by the graph view and TV overlay.
/// Pure data (no SwiftUI) so it lives with the SwiftUI-free state layer;
/// the views convert `(red, green, blue)` to `Color`.
public enum GraphPalette {
    public static let colors: [(red: Double, green: Double, blue: Double)] = [
        (0.00, 0.45, 0.90), // blue
        (0.85, 0.20, 0.20), // red
        (0.10, 0.60, 0.25), // green
        (0.55, 0.25, 0.80), // purple
        (0.95, 0.55, 0.00), // orange
        (0.00, 0.60, 0.65)  // teal
    ]

    public static func rgb(for index: Int) -> (red: Double, green: Double, blue: Double) {
        let count = colors.count
        return colors[((index % count) + count) % count]
    }
}
