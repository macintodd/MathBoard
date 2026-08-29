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

    /// Scrollable history of past expression/result pairs (most recent last).
    /// Capped at 20 entries. Ephemeral (not persisted).
    public var computeHistory: [CalculatorHistoryEntry] = []

    /// When true, the history is hidden from the home screen (CLEAR on empty line).
    /// History entries are retained in memory for UP-arrow recall.
    public var computeScreenCleared: Bool = false

    /// The raw expression that triggered the NONREAL ANSWERS error screen.
    /// Used by the Goto action to position the cursor at the offending function.
    public var nonrealErrorExpression: String = ""

    /// Selected history line while UP/DOWN scrolling the home screen.
    /// nil = live input active. Flat index from the bottom:
    ///   even index → result of entry (history.count - 1 - index/2)
    ///   odd index  → expression of entry (history.count - 1 - index/2)
    public var computeHistoryLine: Int? = nil

    /// Result from the last 1-Var Stats run. Ephemeral.
    public var oneVarStatsResult: CalculatorOneVarStatsResult?

    /// Result from the last 2-Var Stats run. Ephemeral.
    public var twoVarStatsResult: CalculatorTwoVarStatsResult?

    /// Currently selected field index in the WINDOW editor (0=Xmin … 5=Yscl).
    public var windowEditorField: Int = 0

    /// Text being typed for the current WINDOW field.
    public var windowEditorText: String = ""

    /// Whether TRACE mode is active on the graph plot.
    public var isTraceActive: Bool = false

    /// X coordinate of the trace cursor in graph space.
    public var graphTraceCursorX: Double = 0

    /// Which enabled equation the trace cursor rides (0-based).
    public var graphTraceEquationIndex: Int = 0

    /// Whether the calculator is waiting for the user to press a variable
    /// letter key after pressing STO→.
    public var isStoringVariable: Bool = false

    /// Active highlighted row in the Y-VARS menu.
    public var yVarsMenuSelection: Int = 0

    /// Label of the most recently pressed key. The TV overlay uses this to
    /// highlight the last pressed button in pink. Nil until first key press.
    public var lastPressedKeyLabel: String? = nil

    // MARK: - Equation editor cursor (per-session)

    /// Horizontal cursor column in the equation editor.
    /// 0 = color swatch + line style, 1 = Y= label, 2 = expression (default).
    public var equationEditorColumn: Int = 2

    /// Character index within the expression where the cursor sits (0 = before first char).
    public var equationEditorCharIndex: Int = 0

    /// Whether the color/line-style picker is visible for the selected equation.
    public var isEquationStylePickerVisible: Bool = false

    /// Which row within the style picker is active (0 = color, 1 = line style).
    public var equationPickerField: Int = 0

    // MARK: - MODE screen (per-session)

    /// Which row of the MODE menu the cursor is on (0-based, rows 0-12 are interactive).
    public var modeMenuRow: Int = 0

    /// Output display style (MathPrint shows stacked fractions; Classic is legacy text).
    public var calcDisplayFormat: CalcDisplayFormat = .mathPrint
    /// Current graph type (Function / Parametric / Polar / Seq).
    public var calcGraphType: CalcGraphType = .function_
    /// Connected vs dotted, thin vs thick drawing mode.
    public var calcDrawMode: CalcDrawMode = .thin
    /// Whether functions are evaluated sequentially or simultaneously during animation.
    public var calcEvalOrder: CalcEvalOrder = .sequential
    /// Complex number display format.
    public var calcComplexMode: CalcComplexMode = .real
    /// Screen layout (full / horiz split / graph-table).
    public var calcScreenLayout: CalcScreenLayout = .full
    /// Fraction display type (proper vs mixed).
    public var calcFractionType: CalcFractionType = .nOverD
    /// Numeric answer format (Auto / Decimal).
    public var calcAnswerMode: CalcAnswerMode = .auto
    /// Whether r and r² appear in regression output.
    public var calcStatDiagnostics: Bool = false
    /// Whether Stat setup wizards are shown.
    public var calcStatWizards: Bool = true

    // MARK: - CALC tool (2nd+TRACE, per-session)

    /// Current phase of the CALC tool workflow.
    public var calcToolPhase: CalcToolPhase = .none
    /// Which CALC operation is active (value/zero/min/max/intersect/dy∕dx/integral).
    public var calcToolOperation: CalcToolOperation = .minimum
    /// Highlighted row in the CALC menu (0-based = operation rawValue).
    public var calcToolMenuSelection: Int = 2
    /// Cursor X in graph coordinates during bound/guess prompts and result display.
    public var calcToolCursorX: Double = 0
    /// Left bound set by the user (nil until locked).
    public var calcToolLeftBound: Double? = nil
    /// Right bound set by the user (nil until locked).
    public var calcToolRightBound: Double? = nil
    /// Computed result X coordinate (nil for integral).
    public var calcToolResultX: Double? = nil
    /// Computed result Y value (or integral area).
    public var calcToolResultY: Double? = nil
    /// Label shown with the result (e.g. "Minimum", "∫f(x)dx").
    public var calcToolResultLabel: String = ""
    /// Index into the filtered enabled-equation array for intersect "1st Curve".
    public var calcToolCurveIndex1: Int = 0
    /// Index into the filtered enabled-equation array for intersect "2nd Curve".
    public var calcToolCurveIndex2: Int = 1

    /// Transition from the CALC menu into the interactive workflow for `operation`.
    /// Resets all bounds/results and positions the cursor at window midpoint.
    public func beginCalcTool(operation: CalcToolOperation) {
        calcToolOperation = operation
        calcToolMenuSelection = operation.rawValue
        calcToolLeftBound = nil
        calcToolRightBound = nil
        calcToolResultX = nil
        calcToolResultY = nil
        calcToolResultLabel = ""
        calcToolCursorX = (graphWindow.xMin + graphWindow.xMax) / 2
        calcToolCurveIndex1 = 0
        let enabledCount = graphEquations.filter { $0.isEnabled && !$0.expression.isEmpty }.count
        calcToolCurveIndex2 = enabledCount > 1 ? 1 : 0
        calcToolPhase = .leftBound
        graphScreenMode = .plot
    }

    // MARK: - TBLSET editor (per-session)

    /// Currently selected field in the TBLSET screen (0=TblStart, 1=ΔTbl, 2=Indpnt, 3=Depend).
    public var tblSetEditorField: Int = 0

    /// Text being typed for the current TBLSET numeric field.
    public var tblSetEditorText: String = ""

    /// Independent variable control mode (Auto = auto-generate X; Ask = user enters X).
    public var tableIndpntMode: TableControlMode = .auto

    /// Dependent variable control mode (Auto = compute Y; Ask = hide Y until revealed).
    public var tableDependMode: TableControlMode = .auto

    /// Which TI-style calculator screen is visible while the Calc tab is active.
    public var calculatorScreenMode: CalculatorHomeScreenMode = .home

    /// Active tab in the `math` menu.
    public var mathMenuTab: CalculatorMathMenuTab = .math

    /// Active highlighted row in the current `math` menu tab.
    public var mathMenuSelection: Int = 0

    /// Active tab in the `stat` menu.
    public var statMenuTab: CalculatorStatMenuTab = .edit

    /// Active highlighted row in the current `stat` menu tab.
    public var statMenuSelection: Int = 0

    /// Modifier flags matching TI-style keystrokes. These are one-shot flags
    /// consumed by the next eligible key.
    public var isSecondActive: Bool = false
    public var isAlphaActive: Bool = false

    /// Simple L1/L2 editor state for class regression workflows.
    public var statLists: [[Double]] = [
        [1, 2, 3, 4],
        [2, 4, 6, 8]
    ]
    public var statEditingColumn: Int = 0
    public var statEditingRow: Int = 0
    public var statEntryText: String = ""
    public var regressionResult: CalculatorRegressionResult?
    public var calculatorMessage: String = ""

    /// Last successful numeric result, injected as the `ans` variable so
    /// expressions can reference the previous answer (TI-style). Ephemeral.
    public var lastAnswer: Double?

    /// Kept for compatibility with older graph UI paths. The full keypad is
    /// now always part of the calculator body.
    public var showFullKeypad: Bool = false

    /// Whether the keypad half of the calculator is visible. When the screen
    /// is detached, the keypad can be closed while the graph/screen remains.
    public var isKeypadVisible: Bool = true

    /// Whether the calculator screen is detached from the keypad. When
    /// detached, it remains driven by the same keypad but can be dragged and
    /// resized independently.
    public var isScreenDetached: Bool = false

    /// Whether the detached screen object is currently visible. The docked
    /// screen is always visible as part of the keypad card.
    public var isDetachedScreenVisible: Bool = true

    /// True after the detached screen has been sized by the user at least once.
    /// Until then, first eject derives the screen size from the docked screen.
    public var hasDetachedScreenSizeMemory: Bool = false

    /// Which graph-related calculator screen is currently shown. `y=` opens
    /// the equation editor; `graph` opens the plot.
    public var graphScreenMode: CalculatorGraphScreenMode = .plot

    /// Scroll offset for the Zoom menu. The TI menu shows 1-9 first, then the
    /// down arrow reveals 0:ZoomFit.
    public var zoomMenuOffset: Int = 0

    /// Last detached screen center in viewport-space points. `nil` means the
    /// view should choose a default spot near the keypad.
    public var screenPosition: CGPoint?

    /// User-adjustable detached screen content size. The view preserves the
    /// calculator display's 4:3 aspect ratio when resizing.
    public var screenSize: CGSize = CGSize(width: 292, height: 219)

    /// The graph equation the keypads currently edit. Shared state (rather
    /// than view-local) so both the compact keypad and the slide-out full
    /// keypad target the same row. Ephemeral.
    public var selectedGraphEquationID: UUID?

    /// Apply a keypad action to the selected graph equation (falling back to
    /// the first). Shared by the compact and full keypads so their editing
    /// behaves identically.
    public func applyGraphKey(_ action: CalculatorKeyAction) {
        let targetID = selectedGraphEquationID ?? graphEquations.first?.id
        guard let id = targetID,
              let index = graphEquations.firstIndex(where: { $0.id == id }) else { return }
        graphEquations[index].expression = CalculatorExpressionReducer.reduce(
            expression: graphEquations[index].expression,
            action: action
        )
        if selectedGraphEquationID == nil { selectedGraphEquationID = id }
    }

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

    /// Default palette dimensions used on first launch and by the "reset"
    /// affordance. The view clamps the live size between
    /// `CalculatorPaletteLayout.minSize`/`maxSize`.
    public static let defaultPaletteSize = CGSize(width: 320, height: 790)

    /// User-adjustable palette dimensions (points). Persisted so a resized
    /// calculator reopens at the same size; the TV overlay mirrors it.
    public var paletteSize: CGSize {
        didSet {
            guard oldValue != paletteSize else { return }
            store.set(Double(paletteSize.width), forKey: Keys.paletteWidth)
            store.set(Double(paletteSize.height), forKey: Keys.paletteHeight)
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

    /// Number notation (Normal / Sci / Eng). Persisted.
    public var calcNumberNotation: CalcNumberNotation {
        didSet {
            guard oldValue != calcNumberNotation else { return }
            store.set(calcNumberNotation.rawValue, forKey: Keys.calcNumberNotation)
        }
    }

    /// Fixed decimal places (-1 = Float auto, 0-9 = fixed). Persisted.
    public var calcNumberPrecision: Int {
        didSet {
            guard oldValue != calcNumberPrecision else { return }
            store.set(calcNumberPrecision, forKey: Keys.calcNumberPrecision)
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

    /// Variables A–Z stored via STO→. Persisted as JSON.
    public var storedVariables: [String: Double] {
        didSet {
            guard oldValue != storedVariables else { return }
            if let data = try? JSONEncoder().encode(storedVariables) {
                store.set(data, forKey: Keys.storedVariables)
            }
        }
    }

    /// Starting X value for the TABLE view. Persisted.
    public var tableStartX: Double {
        didSet {
            guard oldValue != tableStartX else { return }
            store.set(tableStartX, forKey: Keys.tableStartX)
        }
    }

    /// Step size for the TABLE view. Persisted.
    public var tableStep: Double {
        didSet {
            guard oldValue != tableStep else { return }
            store.set(tableStep, forKey: Keys.tableStep)
        }
    }

    // MARK: - Init

    private let store: UserDefaults

    public init(store: UserDefaults = .standard) {
        self.store = store

        // Restore mode (default: compute)
        let modeRaw = store.string(forKey: Keys.mode)
        self.mode = modeRaw.flatMap { CalculatorMode(rawValue: $0) } ?? .compute

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

        // Restore palette size (default: 360×540)
        if let w = store.object(forKey: Keys.paletteWidth) as? Double,
           let h = store.object(forKey: Keys.paletteHeight) as? Double {
            self.paletteSize = CGSize(width: w, height: h)
        } else {
            self.paletteSize = Self.defaultPaletteSize
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

        // Restore STO→ variables
        if let data = store.data(forKey: Keys.storedVariables),
           let vars = try? JSONDecoder().decode([String: Double].self, from: data) {
            self.storedVariables = vars
        } else {
            self.storedVariables = [:]
        }

        // Restore TABLE settings (defaults: start=0, step=1)
        self.tableStartX = store.object(forKey: Keys.tableStartX) as? Double ?? 0
        self.tableStep = (store.object(forKey: Keys.tableStep) as? Double).map { max(1e-10, $0) } ?? 1

        // Restore MODE notation/precision (defaults: Normal, Float)
        let notationRaw = store.string(forKey: Keys.calcNumberNotation)
        self.calcNumberNotation = notationRaw.flatMap { CalcNumberNotation(rawValue: $0) } ?? .normal
        let rawPrecision = store.object(forKey: Keys.calcNumberPrecision) as? Int
        self.calcNumberPrecision = rawPrecision ?? -1
    }

    // MARK: - UserDefaults keys

    private enum Keys {
        static let mode = "calculator.mode"
        static let angleMode = "calculator.angleMode"
        static let positionX = "calculator.position.x"
        static let positionY = "calculator.position.y"
        static let computeExpression = "calculator.expression.compute"
        static let paletteWidth = "calculator.palette.width"
        static let paletteHeight = "calculator.palette.height"
        static let graphExpression = "calculator.expression.graph" // legacy (migrated)
        static let graphEquations = "calculator.graph.equations"
        static let graphWindow = "calculator.graph.window"
        static let graphFamily = "calculator.graph.family"
        static let graphCombine = "calculator.graph.combine"
        static let oneVarConnective = "calculator.graph.onevar.connective"
        static let oneVarShowSolution = "calculator.graph.onevar.showSolution"
        static let storedVariables = "calculator.storedVariables"
        static let tableStartX = "calculator.table.startX"
        static let tableStep = "calculator.table.step"
        static let calcNumberNotation = "calculator.mode.notation"
        static let calcNumberPrecision = "calculator.mode.precision"
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

public enum CalculatorGraphScreenMode: String, Sendable, Equatable {
    case equationEditor
    case zoomMenu
    case plot
    case windowEditor
    case tableView
    case calcMenu
}

public enum CalculatorHomeScreenMode: String, Sendable, Equatable {
    case home
    case mathMenu
    case statMenu
    case statEditor
    case regressionResult
    case oneVarStats
    case twoVarStats
    case yVarsMenu
    case tblSet
    case modeMenu
    case nonrealError
}

public enum TableControlMode: String, Sendable, Equatable {
    case auto, ask
}

public enum CalcToolPhase: String, Sendable, Equatable {
    case none
    case leftBound
    case rightBound
    case guess
    case result
}

public enum CalcToolOperation: Int, CaseIterable, Sendable, Equatable {
    case value     = 0
    case zero      = 1
    case minimum   = 2
    case maximum   = 3
    case intersect = 4
    case dyDx      = 5
    case integral  = 6

    public var menuTitle: String {
        switch self {
        case .value:     return "value"
        case .zero:      return "zero"
        case .minimum:   return "minimum"
        case .maximum:   return "maximum"
        case .intersect: return "intersect"
        case .dyDx:      return "dy/dx"
        case .integral:  return "∫f(x)dx"
        }
    }

    /// 0 = cursor-only (compute immediately on ENTER), 2 = lb+rb, 3 = lb+rb+guess
    public var boundPhaseCount: Int {
        switch self {
        case .value, .dyDx:                          return 0
        case .integral:                              return 2
        case .zero, .minimum, .maximum, .intersect: return 3
        }
    }

    public var needsGuess: Bool { boundPhaseCount == 3 }
    public var needsBounds: Bool { boundPhaseCount >= 2 }
}

public enum CalculatorMathMenuTab: String, CaseIterable, Sendable, Equatable {
    case math = "MATH"
    case num = "NUM"
    case cmplx = "CMPLX"
    case prob = "PROB"
    case frac = "FRAC"
}

public enum CalculatorStatMenuTab: String, CaseIterable, Sendable, Equatable {
    case edit = "EDIT"
    case calc = "CALC"
    case tests = "TESTS"
}

// MARK: - Graph window

public struct GraphWindow: Codable, Sendable, Equatable {
    public var xMin: Double
    public var xMax: Double
    /// Tick-mark spacing on the x-axis (used by the WINDOW editor; drawn as gridlines).
    public var xScl: Double
    public var yMin: Double
    public var yMax: Double
    /// Tick-mark spacing on the y-axis.
    public var yScl: Double

    public init(
        xMin: Double = -10,
        xMax: Double = 10,
        xScl: Double = 1,
        yMin: Double = -10,
        yMax: Double = 10,
        yScl: Double = 1
    ) {
        self.xMin = xMin
        self.xMax = xMax
        self.xScl = xScl
        self.yMin = yMin
        self.yMax = yMax
        self.yScl = yScl
    }

    private enum CodingKeys: String, CodingKey {
        case xMin, xMax, xScl, yMin, yMax, yScl
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        xMin = try c.decode(Double.self, forKey: .xMin)
        xMax = try c.decode(Double.self, forKey: .xMax)
        xScl = (try? c.decode(Double.self, forKey: .xScl)) ?? 1
        yMin = try c.decode(Double.self, forKey: .yMin)
        yMax = try c.decode(Double.self, forKey: .yMax)
        yScl = (try? c.decode(Double.self, forKey: .yScl)) ?? 1
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
    /// Optional custom hue for teaching graph style controls.
    public var lineHue: Double?
    /// Optional custom plotted line width.
    public var lineWidth: Double?
    /// Whether this equation is currently plotted.
    public var isEnabled: Bool
    /// Index into `EquationLineStyle.allCases` (0 = solid, default).
    public var lineStyleIndex: Int

    public init(
        id: UUID = UUID(),
        expression: String = "",
        colorIndex: Int = 0,
        lineHue: Double? = nil,
        lineWidth: Double? = nil,
        isEnabled: Bool = true,
        lineStyleIndex: Int = 0
    ) {
        self.id = id
        self.expression = expression
        self.colorIndex = colorIndex
        self.lineHue = lineHue
        self.lineWidth = lineWidth
        self.isEnabled = isEnabled
        self.lineStyleIndex = lineStyleIndex
    }

    private enum CodingKeys: String, CodingKey {
        case id, expression, colorIndex, lineHue, lineWidth, isEnabled, lineStyleIndex
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(UUID.self, forKey: .id)
        expression     = try c.decode(String.self, forKey: .expression)
        colorIndex     = try c.decode(Int.self, forKey: .colorIndex)
        lineHue        = try c.decodeIfPresent(Double.self, forKey: .lineHue)
        lineWidth      = try c.decodeIfPresent(Double.self, forKey: .lineWidth)
        isEnabled      = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        lineStyleIndex = try c.decodeIfPresent(Int.self, forKey: .lineStyleIndex) ?? 0
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

// MARK: - History entry

/// One expression/result pair in the home-screen history scroll.
public struct CalculatorHistoryEntry: Identifiable, Sendable {
    public let id: UUID
    public let expression: String
    public let result: String

    public init(expression: String, result: String) {
        self.id = UUID()
        self.expression = expression
        self.result = result
    }
}

/// Fixed curve-color palette, shared by the graph view and TV overlay.
/// Pure data (no SwiftUI) so it lives with the SwiftUI-free state layer;
/// the views convert `(red, green, blue)` to `Color`.
public enum GraphPalette {
    public static let colors: [(red: Double, green: Double, blue: Double)] = [
        (0.00, 0.45, 0.90), // 0 BLUE
        (0.85, 0.20, 0.20), // 1 RED
        (0.10, 0.60, 0.25), // 2 GREEN
        (0.55, 0.25, 0.80), // 3 PURPLE
        (0.95, 0.55, 0.00), // 4 ORANGE
        (0.00, 0.60, 0.65), // 5 TEAL
        (0.05, 0.05, 0.05), // 6 BLACK
        (0.80, 0.10, 0.80), // 7 MAGENTA
        (0.55, 0.30, 0.10), // 8 BROWN
        (0.95, 0.90, 0.00), // 9 YELLOW
    ]

    public static let colorNames: [String] = [
        "BLUE", "RED", "GREEN", "PURPLE", "ORANGE", "TEAL",
        "BLACK", "MAGENTA", "BROWN", "YELLOW"
    ]

    public static func rgb(for index: Int) -> (red: Double, green: Double, blue: Double) {
        let count = colors.count
        return colors[((index % count) + count) % count]
    }

    public static func name(for index: Int) -> String {
        let count = colorNames.count
        return colorNames[((index % count) + count) % count]
    }
}

// MARK: - MODE screen setting enums

public enum CalcDisplayFormat: String, CaseIterable, Sendable, Equatable {
    case mathPrint = "MathPrint"
    case classic   = "Classic"
}

public enum CalcNumberNotation: String, CaseIterable, Sendable, Equatable {
    case normal = "NORMAL"
    case sci    = "SCI"
    case eng    = "ENG"
}

public enum CalcGraphType: String, CaseIterable, Sendable, Equatable {
    case function_  = "FUNCTION"
    case parametric = "PARAMETRIC"
    case polar      = "POLAR"
    case seq        = "SEQ"
}

public enum CalcDrawMode: String, CaseIterable, Sendable, Equatable {
    case thick    = "THICK"
    case dotThick = "DOT-THICK"
    case thin     = "THIN"
    case dotThin  = "DOT-THIN"
}

public enum CalcEvalOrder: String, CaseIterable, Sendable, Equatable {
    case sequential = "SEQUENTIAL"
    case simul      = "SIMUL"
}

public enum CalcComplexMode: String, CaseIterable, Sendable, Equatable {
    case real    = "REAL"
    case abi     = "a+bi"
    case reTheta = "re^(θi)"
}

public enum CalcScreenLayout: String, CaseIterable, Sendable, Equatable {
    case full       = "FULL"
    case horizontal = "HORIZONTAL"
    case graphTable = "GRAPH-TABLE"
}

public enum CalcFractionType: String, CaseIterable, Sendable, Equatable {
    case nOverD = "n/d"
    case mixed  = "Un/d"
}

public enum CalcAnswerMode: String, CaseIterable, Sendable, Equatable {
    case auto = "AUTO"
    case dec  = "DEC"
}

/// TI-84-style line styles for graphed equations.
public enum EquationLineStyle: Int, CaseIterable, Sendable {
    case solid     = 0
    case thick     = 1
    case dotted    = 2
    case dashed    = 3
    case shadeAbove = 4
    case shadeBelow = 5

    public var displaySymbol: String {
        switch self {
        case .solid:      return "─────"
        case .thick:      return "━━━━━"
        case .dotted:     return "·····"
        case .dashed:     return "– – –"
        case .shadeAbove: return "▲ ────"
        case .shadeBelow: return "▼ ────"
        }
    }

    public var name: String {
        switch self {
        case .solid:      return "Thin"
        case .thick:      return "Thick"
        case .dotted:     return "Dotted"
        case .dashed:     return "Dashed"
        case .shadeAbove: return "Above"
        case .shadeBelow: return "Below"
        }
    }
}
