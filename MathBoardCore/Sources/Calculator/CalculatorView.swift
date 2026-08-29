//
//  CalculatorView.swift
//  MathBoardCore — Calculator module
//
//  Floating classroom calculator: a high-contrast 4:3 screen docked to the
//  keypad by default, with an emergency-style eject button that detaches the
//  same screen into a draggable, proportionally resizable canvas object. The
//  keypad continues to operate the active Calc/Graph screen after detaching.
//

import SwiftUI

public struct CalculatorView: View {
    @Bindable private var state: CalculatorState
    private let showsKeyHighlight: Bool
    private let onSnapshot: ((Data, CGSize) -> Void)?

    public init(
        state: CalculatorState = .shared,
        showsKeyHighlight: Bool = false,
        onSnapshot: ((Data, CGSize) -> Void)? = nil
    ) {
        self.state = state
        self.showsKeyHighlight = showsKeyHighlight
        self.onSnapshot = onSnapshot
    }

    public static let paletteSize = CalculatorState.defaultPaletteSize

    @State private var dragStartCenter: CGPoint?
    @State private var screenDragStartCenter: CGPoint?
    @State private var screenResizeStart: (size: CGSize, topLeft: CGPoint)?
    private let engine = CalculatorEngine()

    private var activeScreen: CalculatorScreenMode {
        get { state.mode == .graph ? .graph : .calc }
        nonmutating set {
            state.mode = newValue == .graph ? .graph : .compute
            if newValue == .graph {
                state.graphScreenMode = .plot
            } else {
                state.calculatorScreenMode = .home
            }
        }
    }

    public var body: some View {
        GeometryReader { proxy in
            let keypadSize = resolvedKeypadSize()
            let keypadCenter = resolvedKeypadCenter(keypadSize: keypadSize, in: proxy.size)
            ZStack {
                if state.isScreenDetached && state.isDetachedScreenVisible {
                    detachedScreenPanel(keypadCenter: keypadCenter, in: proxy.size)
                }

                if state.isKeypadVisible {
                    calculatorCard
                        .frame(width: keypadSize.width, height: keypadSize.height)
                        .position(keypadCenter)
                        .gesture(dragGesture(in: proxy.size, currentCenter: keypadCenter))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: state.isScreenDetached)
            .animation(.easeInOut(duration: 0.18), value: state.isKeypadVisible)
        }
    }

    // MARK: - Calculator body

    private var calculatorCard: some View {
        VStack(spacing: 0) {
            titleBar

            if !state.isScreenDetached {
                dockedScreen
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }

            Divider()

            CalculatorFullKeypadView(
                state: state,
                showsKeyHighlight: showsKeyHighlight,
                keyAction: handleKey,
                graphAction: showGraphPlot,
                equationAction: editGraphEquation,
                zoomAction: showZoomMenu,
                mathAction: showMathMenu,
                statAction: showStatMenu,
                navigationAction: handleNavigation,
                windowAction: showWindowEditor,
                traceAction: activateTrace,
                tableAction: showTable,
                storeVarAction: beginStoreVariable,
                quitAction: quitToHome,
                tblSetAction: showTblSet,
                calcAction: showCalcMenu
            )
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .background(CalculatorTheme.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.10), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .environment(\.colorScheme, .dark)
        .tint(CalculatorTheme.accent)
    }

    private var titleBar: some View {
        HStack(spacing: 6) {
            Picker("Screen", selection: screenSelection) {
                ForEach(CalculatorScreenMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 138)

            Text(state.angleMode.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())

            Button {
                takeSnapshot()
            } label: {
                Image(systemName: "camera.viewfinder")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(onSnapshot != nil ? CalculatorTheme.label : CalculatorTheme.label.opacity(0.35))
                    .frame(width: 28, height: 28)
            }
            .disabled(onSnapshot == nil)
            .help("Add calculator snapshot to canvas")

            Button { ejectOrDockScreen() } label: {
                Image(systemName: state.isScreenDetached ? "arrow.down.to.line.compact" : "eject.fill")
                    .font(.title3.weight(.black))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(state.isScreenDetached ? Color.gray : Color.red, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
            }
            .help(state.isScreenDetached ? "Dock screen" : "Eject screen")

            Button { closeKeypadOrCalculator() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 28)
            }
            .help(state.isScreenDetached ? "Close keypad" : "Close calculator")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, state.isScreenDetached ? 16 : 10)
        .background(CalculatorTheme.surface)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18))
        .contentShape(Rectangle())
    }

    private var dockedScreen: some View {
        CalculatorScreenWindow(
            state: state,
            mode: activeScreen,
            isDetached: false,
            selectCalc: { activeScreen = .calc }
        )
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
    }

    private var screenSelection: Binding<CalculatorScreenMode> {
        Binding(
            get: { activeScreen },
            set: { activeScreen = $0 }
        )
    }

    private func detachedScreenPanel(keypadCenter: CGPoint, in containerSize: CGSize) -> some View {
        let contentSize = CalculatorPaletteLayout.clampScreenSize(state.screenSize, in: containerSize)
        let windowSize = CGSize(width: contentSize.width, height: contentSize.height + CalculatorScreenWindow.detachedHeaderHeight)
        let center = resolvedScreenCenter(keypadCenter: keypadCenter, windowSize: windowSize, in: containerSize)

        return CalculatorScreenWindow(
            state: state,
            mode: activeScreen,
            isDetached: true,
            selectCalc: { activeScreen = .calc },
            dock: { state.isScreenDetached = false; state.isKeypadVisible = true },
            close: closeDetachedScreen,
            onSnapshot: takeSnapshot
        )
        .frame(width: windowSize.width, height: windowSize.height)
        .overlay(alignment: .bottomTrailing) {
            screenResizeHandle(currentCenter: center, in: containerSize)
        }
        .position(center)
        .gesture(screenDragGesture(in: containerSize, currentCenter: center, windowSize: windowSize))
    }

    // MARK: - Snapshot

    private func takeSnapshot() {
        guard let onSnapshot else { return }
        #if os(iOS)
        let snapSize = CGSize(width: 480, height: 360)
        let content = CalculatorScreenWindow(
            state: state,
            mode: activeScreen,
            isDetached: false,
            selectCalc: {}
        )
        .frame(width: snapSize.width, height: snapSize.height)
        .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.uiImage, let pngData = image.pngData() else { return }
        onSnapshot(pngData, snapSize)
        #endif
    }

    // MARK: - Actions

    private func handleKey(_ action: CalculatorKeyAction) {
        // STO→ mode: next letter key stores lastAnswer to that variable
        if state.isStoringVariable {
            switch action {
            case .insert(let text) where text.count == 1 && text.first?.isLetter == true:
                storeVariable(text)
                return
            default:
                state.isStoringVariable = false
            }
        }

        // ALPHA + TRACE (F4) → Y-VARS menu
        if case .insert(let text) = action, text == "F4", activeScreen == .calc {
            showYVarsMenu()
            return
        }

        switch action {
        case .toggleSecond:
            state.isSecondActive.toggle()
            state.isAlphaActive = false
            return
        case .toggleAngleMode:
            showModeMenu()
        case .evaluate:
            if activeScreen == .graph, state.graphScreenMode == .calcMenu {
                guard let op = CalcToolOperation(rawValue: state.calcToolMenuSelection) else { return }
                state.beginCalcTool(operation: op)
                return
            }
            if activeScreen == .graph, state.graphScreenMode == .plot, state.calcToolPhase != .none {
                handleCalcToolEnter()
                return
            }
            if activeScreen == .graph, state.graphScreenMode == .windowEditor {
                commitWindowField()
                return
            }
            if activeScreen == .graph, state.graphScreenMode == .equationEditor {
                handleEquationEditorEnter()
                return
            }
            if activeScreen == .graph, state.graphScreenMode == .plot, state.isTraceActive {
                return  // ENTER in trace mode — reserved for future X-jump feature
            }
            if activeScreen == .calc, state.calculatorScreenMode != .home {
                handleCalculatorScreenKey(.evaluate)
                return
            }
            if activeScreen == .calc {
                // ENTER while history line is selected → paste that text as next input
                if let line = state.computeHistoryLine {
                    let text = historyLineText(at: line)
                    state.computeExpression = text
                    state.computeHistoryLine = nil
                } else {
                    evaluateCompute()
                }
            } else {
                showGraphPlot()
            }
        case .insert, .deleteBackward, .clear:
            if activeScreen == .graph, state.graphScreenMode == .calcMenu {
                switch action {
                case .insert(let text):
                    if let d = Int(text), d >= 1, d <= 7, let op = CalcToolOperation(rawValue: d - 1) {
                        state.beginCalcTool(operation: op)
                    }
                case .clear, .deleteBackward:
                    exitCalcTool()
                default: break
                }
                return
            }
            if activeScreen == .graph, state.graphScreenMode == .plot, state.calcToolPhase != .none {
                if case .clear = action { exitCalcTool() }
                return
            }
            // Graph-mode screen-specific routing
            if activeScreen == .graph, state.graphScreenMode == .equationEditor {
                handleEquationEditorTyping(action)
                return
            }
            if activeScreen == .graph, state.graphScreenMode == .windowEditor {
                handleWindowEditorKey(action)
                return
            }
            if activeScreen == .graph, state.graphScreenMode == .tableView {
                if action == .clear { showGraphPlot() }
                return
            }
            if activeScreen == .graph, state.graphScreenMode == .plot, state.isTraceActive {
                if action == .clear { state.isTraceActive = false; return }
            }
            if activeScreen == .graph, state.graphScreenMode == .zoomMenu {
                handleZoomMenuKey(action)
                return
            }
            if activeScreen == .calc, state.calculatorScreenMode != .home {
                handleCalculatorScreenKey(action)
                return
            }
            switch activeScreen {
            case .calc:
                // Any key while history selection is active cancels the selection
                if state.computeHistoryLine != nil {
                    state.computeHistoryLine = nil
                    if action == .clear { return }  // CLEAR just collapses selection
                }
                // Typing anything un-clears the screen
                state.computeScreenCleared = false

                // Implicit Ans: binary operator typed into an empty expression
                let binaryOps: Set<String> = ["+", "-", "*", "/", "^"]
                if case .insert(let text) = action,
                   state.computeExpression.isEmpty,
                   let firstChar = text.first,
                   binaryOps.contains(String(firstChar)) {
                    state.computeExpression = "ans"
                }
                // CLEAR: first press clears expression; second press (on empty) clears screen
                if action == .clear {
                    if state.computeExpression.isEmpty {
                        state.computeScreenCleared = true
                        state.computeResult = ""
                        state.computeIsError = false
                        return
                    }
                    state.computeExpression = ""
                    state.computeResult = ""
                    state.computeIsError = false
                    return
                }
                state.computeExpression = CalculatorExpressionReducer.reduce(
                    expression: state.computeExpression,
                    action: action
                )
            case .graph:
                state.applyGraphKey(action)
            }
        }
    }

    /// Prettify a raw expression for display: pi→π, logBASE→logBASE (already nice), etc.
    private func prettify(_ expr: String) -> String {
        expr
            .replacingOccurrences(of: "pi", with: "π")
            .replacingOccurrences(of: "ans", with: "Ans")
    }

    /// Returns the text for a flat history line index (even=result, odd=expression, from bottom).
    private func historyLineText(at line: Int) -> String {
        let entryIndex = state.computeHistory.count - 1 - line / 2
        guard state.computeHistory.indices.contains(entryIndex) else { return "" }
        let entry = state.computeHistory[entryIndex]
        return line % 2 == 0 ? entry.result : entry.expression
    }

    private func evaluateCompute() {
        let complexEvaluator = CalculatorComplexEvaluator()
        let trimmed = state.computeExpression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state.computeResult = ""
            state.computeIsError = false
            return
        }

        // Detect >Frac / >Dec suffix and strip before evaluating
        var exprToEval = trimmed
        var applyFrac = false
        if exprToEval.hasSuffix(">Frac") {
            applyFrac = true
            exprToEval = String(exprToEval.dropLast(">Frac".count)).trimmingCharacters(in: .whitespaces)
        } else if exprToEval.hasSuffix(">Dec") {
            exprToEval = String(exprToEval.dropLast(">Dec".count)).trimmingCharacters(in: .whitespaces)
        }
        if exprToEval.isEmpty { exprToEval = "ans" }
        // Auto-close unclosed parens so e.g. cbrt(9 evaluates as cbrt(9)
        exprToEval = autoCloseParens(exprToEval)

        do {
            var variables: [String: Double] = state.lastAnswer.map { ["ans": $0] } ?? [:]
            for (key, value) in state.storedVariables { variables[key] = value }

            // Build Y-function closures for Y1–Y9 so Y1(4) etc. work in expressions
            var yFunctions: [String: @Sendable (Double) throws -> Double] = [:]
            for (index, equation) in state.graphEquations.enumerated()
                where equation.isEnabled && !equation.expression.isEmpty && index < 9 {
                let yName = "Y\(index + 1)"
                let expr = equation.expression
                let angleMode = state.angleMode
                let capturedVars = variables
                yFunctions[yName] = { x in
                    var xVars = capturedVars
                    xVars["x"] = x
                    return try CalculatorEngine().evaluate(expr, angleMode: angleMode, variables: xVars)
                }
            }

            let displayExpr = prettify(trimmed)
            var resultStr: String

            // Route to complex evaluator when `i` appears in the expression
            if CalculatorComplexEvaluator.expressionIsComplex(exprToEval) {
                let z = try complexEvaluator.evaluate(exprToEval, angleMode: state.angleMode, variables: variables)
                // In REAL mode, a nonreal result triggers the NONREAL ANSWERS error screen
                if !z.isReal && state.calcComplexMode == .real {
                    triggerNonrealError(expression: trimmed)
                    return
                }
                resultStr = formatCalcComplex(z)
                // Update lastAnswer with real part (for Ans chaining with real results)
                if z.isReal { state.lastAnswer = z.real }
            } else {
                do {
                    let value = try engine.evaluate(exprToEval, angleMode: state.angleMode, variables: variables, yFunctions: yFunctions)
                    resultStr = CalculatorResultFormatter.string(
                        for: value,
                        notation: state.calcNumberNotation,
                        precision: state.calcNumberPrecision
                    )
                    if applyFrac, let frac = CalculatorStatistics.fractionString(for: value) {
                        resultStr = frac
                    }
                    state.lastAnswer = value
                } catch {
                    // Check if the real-evaluator failure is because the result is complex
                    // (e.g. sqrt(-1), log(-5)). If so, show NONREAL ANSWERS in REAL mode.
                    if state.calcComplexMode == .real,
                       let z = try? complexEvaluator.evaluate(exprToEval, angleMode: state.angleMode, variables: variables),
                       !z.isReal {
                        triggerNonrealError(expression: trimmed)
                        return
                    }
                    throw error
                }
            }

            state.computeResult = resultStr
            state.computeIsError = false
            state.computeScreenCleared = false
            // History stores the prettified expression (π instead of pi)
            state.computeHistory.append(CalculatorHistoryEntry(expression: displayExpr, result: resultStr))
            if state.computeHistory.count > 20 { state.computeHistory.removeFirst() }
            state.computeExpression = ""
            state.computeHistoryLine = nil
        } catch {
            state.computeResult = (error as? LocalizedError)?.errorDescription ?? "Error"
            state.computeIsError = true
            // Keep expression on error so the user can edit the typo
        }
    }

    private func autoCloseParens(_ expr: String) -> String {
        var depth = 0
        for c in expr {
            if c == "(" { depth += 1 }
            else if c == ")" && depth > 0 { depth -= 1 }
        }
        return depth > 0 ? expr + String(repeating: ")", count: depth) : expr
    }

    // Show the TI-84-style NONREAL ANSWERS error screen.
    private func triggerNonrealError(expression: String) {
        state.nonrealErrorExpression = expression
        state.calculatorScreenMode = .nonrealError
        state.computeIsError = false
        state.computeResult = ""
    }

    // 1:Quit — clear expression and return to live input.
    private func handleNonrealQuit() {
        state.computeExpression = ""
        state.computeResult = ""
        state.computeIsError = false
        state.nonrealErrorExpression = ""
        state.calculatorScreenMode = .home
    }

    // 2:Goto — position cursor just inside the offending function call.
    private func handleNonrealGoto() {
        let expr = state.nonrealErrorExpression
        // Scan for the first function call that produces complex results
        let suspects = ["sqrt(", "log(", "ln(", "asin(", "acos("]
        var bestEnd = expr.count

        for name in suspects {
            if let r = expr.range(of: name, options: .caseInsensitive) {
                let pos = expr.distance(from: expr.startIndex, to: r.lowerBound)
                let end = expr.distance(from: expr.startIndex, to: r.upperBound)
                if pos < bestEnd - name.count {
                    bestEnd = end
                }
            }
        }

        // Truncate to just after the opening paren — cursor lands inside the call
        if bestEnd < expr.count {
            state.computeExpression = String(expr.prefix(bestEnd))
        } else {
            state.computeExpression = expr
        }
        state.nonrealErrorExpression = ""
        state.computeResult = ""
        state.computeIsError = false
        state.calculatorScreenMode = .home
    }

    private func editGraphEquation() {
        activeScreen = .graph
        state.graphScreenMode = .equationEditor
        state.equationEditorColumn = 2
        state.isEquationStylePickerVisible = false
        ensureGraphEquation(at: 0)
        state.equationEditorCharIndex = state.graphEquations.first(where: { $0.id == state.selectedGraphEquationID })?.expression.count ?? 0
    }

    private func showGraphPlot() {
        activeScreen = .graph
        state.graphScreenMode = .plot
        state.isTraceActive = false
        if state.selectedGraphEquationID == nil {
            state.selectedGraphEquationID = state.graphEquations.first?.id
        }
    }

    private func showZoomMenu() {
        activeScreen = .graph
        state.graphScreenMode = .zoomMenu
        state.zoomMenuOffset = 0
    }

    private func showTblSet() {
        activeScreen = .calc
        state.calculatorScreenMode = .tblSet
        state.tblSetEditorField = 0
        loadTblSetField(0)
    }

    private func showCalcMenu() {
        state.mode = .graph
        state.isTraceActive = false
        state.calcToolPhase = .none
        state.calcToolMenuSelection = 2  // pre-highlight 3:minimum
        state.graphScreenMode = .calcMenu
    }

    private func handleCalcMenuNavigation(_ direction: CalculatorKeypadDirection) {
        let count = CalcToolOperation.allCases.count
        switch direction {
        case .up:   state.calcToolMenuSelection = max(0, state.calcToolMenuSelection - 1)
        case .down: state.calcToolMenuSelection = min(count - 1, state.calcToolMenuSelection + 1)
        case .left, .right: break
        }
    }

    private func handleCalcToolNavigation(_ direction: CalculatorKeypadDirection) {
        let step = state.graphWindow.width / 94
        let isIntersectCurvePhase = state.calcToolOperation == .intersect &&
            (state.calcToolPhase == .leftBound || state.calcToolPhase == .rightBound)
        let equationCount = state.graphEquations.filter { $0.isEnabled && !$0.expression.isEmpty }.count

        switch direction {
        case .left:  state.calcToolCursorX = max(state.graphWindow.xMin, state.calcToolCursorX - step)
        case .right: state.calcToolCursorX = min(state.graphWindow.xMax, state.calcToolCursorX + step)
        case .up, .down:
            guard isIntersectCurvePhase, equationCount > 0 else { break }
            let delta = direction == .up ? -1 : 1
            if state.calcToolPhase == .leftBound {
                state.calcToolCurveIndex1 = (state.calcToolCurveIndex1 + delta + equationCount) % equationCount
            } else {
                state.calcToolCurveIndex2 = (state.calcToolCurveIndex2 + delta + equationCount) % equationCount
            }
        }
    }

    private func handleCalcToolEnter() {
        let isIntersect = state.calcToolOperation == .intersect
        switch state.calcToolPhase {
        case .leftBound:
            if state.calcToolOperation.boundPhaseCount == 0 {
                computeCalcToolImmediate(x: state.calcToolCursorX)
            } else if isIntersect {
                // Record curve 1 selection; advance to 2nd Curve? phase
                let equations = state.graphEquations.filter { $0.isEnabled && !$0.expression.isEmpty }
                if equations.count < 2 { exitCalcTool(); return }
                state.calcToolPhase = .rightBound
                // Auto-select a different curve for curve 2
                let next = (state.calcToolCurveIndex1 + 1) % equations.count
                state.calcToolCurveIndex2 = next
            } else {
                state.calcToolLeftBound = state.calcToolCursorX
                state.calcToolPhase = .rightBound
                let advance = state.graphWindow.width / 6
                state.calcToolCursorX = min(state.graphWindow.xMax, state.calcToolCursorX + advance)
            }
        case .rightBound:
            if isIntersect {
                // Record curve 2 selection; advance to Guess? phase
                state.calcToolPhase = .guess
            } else {
                guard let lb = state.calcToolLeftBound, state.calcToolCursorX > lb else { return }
                state.calcToolRightBound = state.calcToolCursorX
                if state.calcToolOperation.needsGuess {
                    state.calcToolPhase = .guess
                    state.calcToolCursorX = (lb + state.calcToolCursorX) / 2
                } else {
                    computeCalcToolWithBounds(lb: lb, rb: state.calcToolCursorX)
                }
            }
        case .guess:
            if isIntersect {
                computeIntersect(guessX: state.calcToolCursorX)
            } else {
                guard let lb = state.calcToolLeftBound, let rb = state.calcToolRightBound else { return }
                computeCalcToolWithBounds(lb: lb, rb: rb)
            }
        case .result:
            exitCalcTool()
        case .none:
            break
        }
    }

    private func exitCalcTool() {
        state.calcToolPhase = .none
        state.calcToolLeftBound = nil
        state.calcToolRightBound = nil
        state.calcToolResultX = nil
        state.calcToolResultY = nil
        state.graphScreenMode = .plot
    }

    // MARK: - CALC tool numerical computation

    private func computeCalcToolImmediate(x: Double) {
        guard let f = buildCalcFunction() else { exitCalcTool(); return }
        switch state.calcToolOperation {
        case .value:
            guard let y = calcSafeEval(f, x) else { exitCalcTool(); return }
            state.calcToolResultX = x
            state.calcToolResultY = y
            state.calcToolResultLabel = "value"
            state.calcToolCursorX = x
        case .dyDx:
            let h = 1e-7
            guard let y1 = calcSafeEval(f, x + h), let y2 = calcSafeEval(f, x - h) else { exitCalcTool(); return }
            state.calcToolResultX = x
            state.calcToolResultY = (y1 - y2) / (2 * h)
            state.calcToolResultLabel = "dy/dx"
            state.calcToolCursorX = x
        default: break
        }
        state.calcToolPhase = .result
    }

    private func computeCalcToolWithBounds(lb: Double, rb: Double) {
        guard let f = buildCalcFunction() else { exitCalcTool(); return }
        switch state.calcToolOperation {
        case .minimum:
            let xOpt = calcGoldenSection(f: { self.calcSafeEval(f, $0) ?? .infinity }, lo: lb, hi: rb, findMin: true)
            guard let y = calcSafeEval(f, xOpt) else { exitCalcTool(); return }
            state.calcToolResultX = xOpt; state.calcToolResultY = y
            state.calcToolResultLabel = "Minimum"
            state.calcToolCursorX = xOpt
        case .maximum:
            let xOpt = calcGoldenSection(f: { self.calcSafeEval(f, $0) ?? .infinity }, lo: lb, hi: rb, findMin: false)
            guard let y = calcSafeEval(f, xOpt) else { exitCalcTool(); return }
            state.calcToolResultX = xOpt; state.calcToolResultY = y
            state.calcToolResultLabel = "Maximum"
            state.calcToolCursorX = xOpt
        case .zero:
            if let xZ = calcBrentsMethod(f: { self.calcSafeEval(f, $0) ?? .nan }, a: lb, b: rb),
               let y = calcSafeEval(f, xZ) {
                state.calcToolResultX = xZ; state.calcToolResultY = y
                state.calcToolResultLabel = "Zero"
                state.calcToolCursorX = xZ
            } else {
                exitCalcTool(); return
            }
        case .integral:
            let area = calcSimpsons(f: { self.calcSafeEval(f, $0) ?? 0 }, a: lb, b: rb)
            state.calcToolResultX = nil
            state.calcToolResultY = area
            state.calcToolResultLabel = "∫f(x)dx"
        case .intersect:
            break  // handled by computeIntersect()
        default: break
        }
        state.calcToolPhase = .result
    }

    private func computeIntersect(guessX: Double) {
        let equations = state.graphEquations.filter { $0.isEnabled && !$0.expression.isEmpty }
        let n = equations.count
        guard n >= 2 else { exitCalcTool(); return }
        let i1 = state.calcToolCurveIndex1 % n
        let i2 = state.calcToolCurveIndex2 % n
        guard i1 != i2 else { exitCalcTool(); return }
        guard let f1 = buildCalcFunction(at: i1), let f2 = buildCalcFunction(at: i2) else { exitCalcTool(); return }

        let diff: (Double) -> Double = { x in
            let y1 = (try? f1(x)) ?? .nan
            let y2 = (try? f2(x)) ?? .nan
            return y1.isFinite && y2.isFinite ? y1 - y2 : .nan
        }

        // Search window: full graph x-range, but bias scan to start near guessX
        let a = state.graphWindow.xMin, b = state.graphWindow.xMax
        if let xI = calcBrentsMethod(f: { diff($0).isFinite ? diff($0) : .nan }, a: a, b: b) {
            let y1 = (try? f1(xI)) ?? .nan
            let y2 = (try? f2(xI)) ?? .nan
            let yI = (y1 + y2) / 2  // average to reduce floating-point asymmetry
            guard yI.isFinite else { exitCalcTool(); return }
            state.calcToolResultX = xI
            state.calcToolResultY = yI
            state.calcToolResultLabel = "Intersection"
            state.calcToolCursorX = xI
            state.calcToolPhase = .result
        } else {
            exitCalcTool()
        }
    }

    private func buildCalcFunction() -> ((Double) throws -> Double)? {
        let equations = state.graphEquations.filter { $0.isEnabled && !$0.expression.isEmpty }
        guard !equations.isEmpty else { return nil }
        let idx = max(0, state.graphTraceEquationIndex) % equations.count
        return buildCalcFunction(at: idx)
    }

    private func buildCalcFunction(at equationIndex: Int) -> ((Double) throws -> Double)? {
        let equations = state.graphEquations.filter { $0.isEnabled && !$0.expression.isEmpty }
        guard !equations.isEmpty else { return nil }
        let idx = equationIndex % equations.count
        let expr = equations[idx].expression
        let angleMode = state.angleMode
        var variables: [String: Double] = state.lastAnswer.map { ["ans": $0] } ?? [:]
        for (k, v) in state.storedVariables { variables[k] = v }
        return { x in
            var vars = variables
            vars["x"] = x
            return try CalculatorEngine().evaluate(expr, angleMode: angleMode, variables: vars)
        }
    }

    private func calcSafeEval(_ f: (Double) throws -> Double, _ x: Double) -> Double? {
        guard let y = try? f(x), y.isFinite else { return nil }
        return y
    }

    private func calcGoldenSection(f: (Double) -> Double, lo: Double, hi: Double, findMin: Bool) -> Double {
        let phi = (3.0 - sqrt(5.0)) / 2.0   // ≈ 0.382
        var a = lo, b = hi
        var c = a + phi * (b - a)
        var d = b - phi * (b - a)
        for _ in 0..<200 {
            guard b - a > 1e-12 else { break }
            let fc = f(c), fd = f(d)
            if findMin ? fc < fd : fc > fd {
                b = d; d = c; c = a + phi * (b - a)
            } else {
                a = c; c = d; d = b - phi * (b - a)
            }
        }
        return (a + b) / 2
    }

    private func calcBrentsMethod(f: (Double) -> Double, a: Double, b: Double) -> Double? {
        var a = a, b = b
        var fa = f(a), fb = f(b)
        guard fa.isFinite && fb.isFinite else { return nil }
        if fa * fb > 0 {
            // Scan the interval for a sign change
            let steps = 200
            let step = (b - a) / Double(steps)
            var found = false
            var prev = fa; var prevX = a
            for i in 1...steps {
                let x = a + Double(i) * step; let fx = f(x)
                if fx.isFinite && prev * fx < 0 { a = prevX; fa = prev; b = x; fb = fx; found = true; break }
                if fx.isFinite { prev = fx; prevX = x }
            }
            guard found else { return nil }
        }
        var c = a, fc = fa, d = 0.0, s = 0.0
        var mflag = true
        for _ in 0..<100 {
            if abs(b - a) < 1e-12 { break }
            if fa != fc && fb != fc {
                s = a * fb * fc / ((fa - fb) * (fa - fc))
                  + b * fa * fc / ((fb - fa) * (fb - fc))
                  + c * fa * fb / ((fc - fa) * (fc - fb))
            } else {
                s = b - fb * (b - a) / (fb - fa)
            }
            let lo = min(a, b), hi = max(a, b)
            let cond1 = s < lo || s > hi
            let cond2 = mflag  && abs(s - b) >= abs(b - c) / 2
            let cond3 = !mflag && abs(s - b) >= abs(c - d) / 2
            if cond1 || cond2 || cond3 { s = (a + b) / 2; mflag = true } else { mflag = false }
            let fs = f(s)
            guard fs.isFinite else { return (a + b) / 2 }
            d = c; c = b; fc = fb
            if fa * fs < 0 { b = s; fb = fs } else { a = s; fa = fs }
            if abs(fa) < abs(fb) { swap(&a, &b); swap(&fa, &fb) }
        }
        return abs(fb) < abs(fa) ? b : a
    }

    private func calcSimpsons(f: (Double) -> Double, a: Double, b: Double) -> Double {
        let n = 1000   // must be even
        let h = (b - a) / Double(n)
        var sum = f(a) + f(b)
        for i in 1..<n { sum += Double(i % 2 == 0 ? 2 : 4) * f(a + Double(i) * h) }
        return sum * h / 3.0
    }

    private func showModeMenu() {
        activeScreen = .calc
        state.modeMenuRow = 0
        state.calculatorScreenMode = .modeMenu
    }

    private func handleModeMenuNavigation(_ direction: CalculatorKeypadDirection) {
        let maxRow = 12  // rows 0-12 are interactive; 13-14 are clock/language display-only
        switch direction {
        case .up:    state.modeMenuRow = max(0, state.modeMenuRow - 1)
        case .down:  state.modeMenuRow = min(maxRow, state.modeMenuRow + 1)
        case .left:  stepModeOption(state.modeMenuRow, delta: -1)
        case .right: stepModeOption(state.modeMenuRow, delta: 1)
        }
    }

    private func handleModeMenuKey(_ action: CalculatorKeyAction) {
        switch action {
        case .evaluate:
            // ENTER: advance to next row (settings already applied live)
            state.modeMenuRow = min(12, state.modeMenuRow + 1)
        case .clear, .deleteBackward:
            state.calculatorScreenMode = .home
        default: break
        }
    }

    private func stepModeOption(_ row: Int, delta: Int) {
        func cycle<T: CaseIterable & Equatable>(_ current: T) -> T {
            let all = Array(T.allCases)
            let idx = all.firstIndex(of: current) ?? 0
            return all[(idx + delta + all.count) % all.count]
        }
        switch row {
        case 0:  state.calcDisplayFormat   = cycle(state.calcDisplayFormat)
        case 1:  state.calcNumberNotation  = cycle(state.calcNumberNotation)
        case 2:
            let next = state.calcNumberPrecision + delta
            state.calcNumberPrecision = max(-1, min(9, next))
        case 3:  state.angleMode           = cycle(state.angleMode)
        case 4:  state.calcGraphType       = cycle(state.calcGraphType)
        case 5:  state.calcDrawMode        = cycle(state.calcDrawMode)
        case 6:  state.calcEvalOrder       = cycle(state.calcEvalOrder)
        case 7:  state.calcComplexMode     = cycle(state.calcComplexMode)
        case 8:  state.calcScreenLayout    = cycle(state.calcScreenLayout)
        case 9:  state.calcFractionType    = cycle(state.calcFractionType)
        case 10: state.calcAnswerMode      = cycle(state.calcAnswerMode)
        case 11: state.calcStatDiagnostics.toggle()
        case 12: state.calcStatWizards.toggle()
        default: break
        }
    }

    private func showMathMenu() {
        activeScreen = .calc
        if state.calculatorScreenMode == .mathMenu, state.isAlphaActive {
            applyMathMenuShortcut("A")
            return
        }
        state.calculatorScreenMode = .mathMenu
        state.mathMenuTab = .math
        state.mathMenuSelection = 0
    }

    private func showStatMenu() {
        activeScreen = .calc
        state.calculatorScreenMode = .statMenu
        state.statMenuTab = .edit
        state.statMenuSelection = 0
    }

    private func handleNavigation(_ direction: CalculatorKeypadDirection) {
        if activeScreen == .calc {
            handleCalculatorNavigation(direction)
            return
        }

        if activeScreen == .graph {
            switch state.graphScreenMode {
            case .zoomMenu:
                switch direction {
                case .down: state.zoomMenuOffset = min(1, state.zoomMenuOffset + 1)
                case .up:   state.zoomMenuOffset = max(0, state.zoomMenuOffset - 1)
                case .left, .right: break
                }
            case .windowEditor:
                switch direction {
                case .up:
                    commitWindowField()
                    state.windowEditorField = max(0, state.windowEditorField - 1)
                case .down:
                    commitWindowField()
                    state.windowEditorField = min(5, state.windowEditorField + 1)
                case .left, .right: break
                }
            case .tableView:
                switch direction {
                case .up:   state.tableStartX -= state.tableStep
                case .down: state.tableStartX += state.tableStep
                case .left, .right: break
                }
            case .equationEditor:
                handleEquationEditorNavigation(direction)
            case .calcMenu:
                handleCalcMenuNavigation(direction)
            case .plot where state.calcToolPhase != .none:
                handleCalcToolNavigation(direction)
            case .plot where state.isTraceActive:
                handleTraceNavigation(direction)
            default: break
            }
        }
    }

    private func handleEquationEditorNavigation(_ direction: CalculatorKeypadDirection) {
        // When picker is open, arrow keys navigate within the picker
        if state.isEquationStylePickerVisible {
            handleStylePickerNavigation(direction)
            return
        }

        let exprCount = selectedEquationExpressionCount()

        switch direction {
        case .left:
            if state.equationEditorColumn == 2 {
                if state.equationEditorCharIndex > 0 {
                    state.equationEditorCharIndex -= 1
                } else {
                    state.equationEditorColumn = 1  // at start of expression → move to = sign
                }
            } else if state.equationEditorColumn == 1 {
                state.equationEditorColumn = 0  // = sign → swatch/style
            }
        case .right:
            if state.equationEditorColumn == 0 {
                state.equationEditorColumn = 1
            } else if state.equationEditorColumn == 1 {
                state.equationEditorColumn = 2
                state.equationEditorCharIndex = 0
            } else if state.equationEditorColumn == 2 {
                state.equationEditorCharIndex = min(exprCount, state.equationEditorCharIndex + 1)
            }
        case .up:
            moveSelectedEquation(by: -1)
        case .down:
            moveSelectedEquation(by: 1)
        }
    }

    private func handleStylePickerNavigation(_ direction: CalculatorKeypadDirection) {
        guard let id = state.selectedGraphEquationID,
              let index = state.graphEquations.firstIndex(where: { $0.id == id }) else { return }
        switch direction {
        case .up:   state.equationPickerField = 0
        case .down: state.equationPickerField = 1
        case .left:
            if state.equationPickerField == 0 {
                let count = GraphPalette.colors.count
                state.graphEquations[index].colorIndex = ((state.graphEquations[index].colorIndex - 1) + count) % count
            } else {
                let count = EquationLineStyle.allCases.count
                state.graphEquations[index].lineStyleIndex = ((state.graphEquations[index].lineStyleIndex - 1) + count) % count
            }
        case .right:
            if state.equationPickerField == 0 {
                state.graphEquations[index].colorIndex = (state.graphEquations[index].colorIndex + 1) % GraphPalette.colors.count
            } else {
                state.graphEquations[index].lineStyleIndex = (state.graphEquations[index].lineStyleIndex + 1) % EquationLineStyle.allCases.count
            }
        }
    }

    private func moveSelectedEquation(by delta: Int) {
        let equations = state.graphEquations
        guard let currentID = state.selectedGraphEquationID,
              let currentIndex = equations.firstIndex(where: { $0.id == currentID }) else { return }
        let newIndex = min(max(0, equations.count - 1), max(0, currentIndex + delta))
        if newIndex != currentIndex {
            state.isEquationStylePickerVisible = false
            state.selectedGraphEquationID = equations[newIndex].id
            resetEquationCursorToEnd()
        }
    }

    private func selectedEquationExpressionCount() -> Int {
        state.graphEquations.first(where: { $0.id == state.selectedGraphEquationID })?.expression.count ?? 0
    }

    private func resetEquationCursorToEnd() {
        state.equationEditorColumn = 2
        state.equationEditorCharIndex = selectedEquationExpressionCount()
    }

    private func handleEquationEditorEnter() {
        switch state.equationEditorColumn {
        case 0:
            state.isEquationStylePickerVisible.toggle()
            state.equationPickerField = 0
        case 1:
            guard let id = state.selectedGraphEquationID,
                  let index = state.graphEquations.firstIndex(where: { $0.id == id }) else { return }
            state.graphEquations[index].isEnabled.toggle()
        default:
            // ENTER in expression: move to next equation row
            moveSelectedEquation(by: 1)
        }
    }

    private func handleEquationEditorTyping(_ action: CalculatorKeyAction) {
        guard let id = state.selectedGraphEquationID,
              let index = state.graphEquations.firstIndex(where: { $0.id == id }) else { return }

        // Close picker and reset to expression column on any typing
        state.isEquationStylePickerVisible = false
        if state.equationEditorColumn != 2 {
            state.equationEditorColumn = 2
            state.equationEditorCharIndex = state.graphEquations[index].expression.count
        }

        var expr = state.graphEquations[index].expression
        let charIndex = min(state.equationEditorCharIndex, expr.count)
        let strIndex = expr.index(expr.startIndex, offsetBy: charIndex)

        switch action {
        case .insert(let text):
            expr.insert(contentsOf: text, at: strIndex)
            state.equationEditorCharIndex = charIndex + text.count
        case .deleteBackward:
            if charIndex > 0 {
                let endIdx = strIndex
                let startIdx = expr.index(before: endIdx)
                expr.removeSubrange(startIdx..<endIdx)
                state.equationEditorCharIndex = charIndex - 1
            }
        case .clear:
            expr = ""
            state.equationEditorCharIndex = 0
        default: break
        }

        state.graphEquations[index].expression = expr
    }

    private func handleTraceNavigation(_ direction: CalculatorKeypadDirection) {
        let equations = state.graphEquations.filter { $0.isEnabled && !$0.expression.isEmpty }
        switch direction {
        case .left:
            let step = state.graphWindow.width / 94
            state.graphTraceCursorX = max(state.graphWindow.xMin, state.graphTraceCursorX - step)
        case .right:
            let step = state.graphWindow.width / 94
            state.graphTraceCursorX = min(state.graphWindow.xMax, state.graphTraceCursorX + step)
        case .up:
            if !equations.isEmpty {
                state.graphTraceEquationIndex = (state.graphTraceEquationIndex + 1) % equations.count
            }
        case .down:
            if !equations.isEmpty {
                let count = equations.count
                state.graphTraceEquationIndex = (state.graphTraceEquationIndex - 1 + count) % count
            }
        }
    }

    private func handleCalculatorNavigation(_ direction: CalculatorKeypadDirection) {
        switch state.calculatorScreenMode {
        case .mathMenu:
            handleMathMenuNavigation(direction)
        case .statMenu:
            handleStatMenuNavigation(direction)
        case .statEditor:
            handleStatEditorNavigation(direction)
        case .yVarsMenu:
            let count = yVarsMenuItems.count
            switch direction {
            case .up:   state.yVarsMenuSelection = max(0, state.yVarsMenuSelection - 1)
            case .down: state.yVarsMenuSelection = min(max(0, count - 1), state.yVarsMenuSelection + 1)
            case .left, .right: break
            }
        case .tblSet:
            handleTblSetNavigation(direction)
        case .modeMenu:
            handleModeMenuNavigation(direction)
        case .home:
            handleHomeHistoryNavigation(direction)
        case .regressionResult, .oneVarStats, .twoVarStats, .nonrealError:
            break
        }
    }

    private func handleHomeHistoryNavigation(_ direction: CalculatorKeypadDirection) {
        let totalLines = state.computeHistory.count * 2
        switch direction {
        case .up:
            guard totalLines > 0 else { return }
            let current = state.computeHistoryLine ?? -1
            if current + 1 < totalLines {
                state.computeHistoryLine = current + 1
            }
        case .down:
            guard totalLines > 0 else { return }
            if let current = state.computeHistoryLine {
                state.computeHistoryLine = current > 0 ? current - 1 : nil
            }
        case .right:
            // When in live input (not scrolling history), advance cursor from
            // first slot (index) to second slot (radicand/arg) in multi-slot
            // MathPrint functions by inserting the comma separator.
            guard state.computeHistoryLine == nil else { break }
            let low = state.computeExpression.lowercased()
            for fn in ["root(", "logbase("] where low.contains(fn) {
                if let r = low.range(of: fn, options: .backwards) {
                    let afterOpen = String(low[r.upperBound...])
                    var depth = 0
                    var hasTopLevelComma = false
                    for c in afterOpen {
                        if c == "(" { depth += 1 }
                        else if c == ")" { depth -= 1 }
                        else if c == "," && depth == 0 { hasTopLevelComma = true; break }
                    }
                    if !hasTopLevelComma {
                        state.computeExpression += ","
                        return
                    }
                }
            }
        case .left:
            break
        }
    }

    private func handleCalculatorScreenKey(_ action: CalculatorKeyAction) {
        switch state.calculatorScreenMode {
        case .mathMenu:
            handleMathMenuKey(action)
        case .statMenu:
            handleStatMenuKey(action)
        case .statEditor:
            handleStatEditorKey(action)
        case .tblSet:
            handleTblSetKey(action)
        case .regressionResult, .oneVarStats, .twoVarStats:
            if action == .clear { state.calculatorScreenMode = .home }
        case .yVarsMenu:
            switch action {
            case .evaluate:
                let items = yVarsMenuItems
                guard items.indices.contains(state.yVarsMenuSelection) else { break }
                let name = items[state.yVarsMenuSelection]
                state.computeExpression += "\(name)("
                state.calculatorScreenMode = .home
            case .clear, .deleteBackward:
                state.calculatorScreenMode = .home
            case .insert(let text):
                if let digit = Int(text), digit >= 1, digit <= yVarsMenuItems.count {
                    state.computeExpression += "\(yVarsMenuItems[digit - 1])("
                    state.calculatorScreenMode = .home
                }
            default: break
            }
        case .modeMenu:
            handleModeMenuKey(action)
        case .nonrealError:
            switch action {
            case .insert(let text):
                if text == "1" { handleNonrealQuit() }
                else if text == "2" { handleNonrealGoto() }
            case .clear:
                handleNonrealQuit()
            default: break
            }
        case .home:
            break
        }
    }

    private var yVarsMenuItems: [String] {
        state.graphEquations.enumerated().compactMap { index, eq in
            index < 9 ? "Y\(index + 1)" : nil
        }
    }

    private func handleMathMenuNavigation(_ direction: CalculatorKeypadDirection) {
        switch direction {
        case .left:
            moveMathTab(by: -1)
        case .right:
            moveMathTab(by: 1)
        case .up:
            state.mathMenuSelection = max(0, state.mathMenuSelection - 1)
        case .down:
            state.mathMenuSelection = min(mathMenuItems.count - 1, state.mathMenuSelection + 1)
        }
    }

    private func handleMathMenuKey(_ action: CalculatorKeyAction) {
        switch action {
        case .evaluate:
            applyMathMenuItem(mathMenuItems[state.mathMenuSelection])
        case .clear:
            state.calculatorScreenMode = .home
            state.calculatorMessage = ""
        case .insert(let text):
            if let character = text.first {
                applyMathMenuShortcut(String(character).uppercased())
            }
        case .deleteBackward:
            state.calculatorScreenMode = .home
        case .toggleAngleMode, .toggleSecond:
            break
        }
    }

    private func applyMathMenuShortcut(_ key: String) {
        guard let item = mathMenuItems.first(where: { $0.shortcut == key }) else { return }
        applyMathMenuItem(item)
    }

    private func applyMathMenuItem(_ item: CalculatorMenuItem) {
        guard item.isEnabled else {
            state.calculatorMessage = "\(item.title) DUMMY"
            return
        }

        state.calculatorScreenMode = .home
        state.calculatorMessage = ""

        switch item.output {
        case .insert(let text):
            state.computeExpression += text
        case .fraction:
            // Append >Frac to current expression; user presses ENTER to evaluate
            let prefix = state.computeExpression.isEmpty ? "Ans" : ""
            state.computeExpression = prefix + state.computeExpression + ">Frac"
        case .decimal:
            let prefix = state.computeExpression.isEmpty ? "Ans" : ""
            state.computeExpression = prefix + state.computeExpression + ">Dec"
        case .none, .statEditor, .regression, .oneVarStats, .twoVarStats:
            break
        }
    }

    private func moveMathTab(by delta: Int) {
        let tabs = CalculatorMathMenuTab.allCases
        guard let index = tabs.firstIndex(of: state.mathMenuTab) else { return }
        state.mathMenuTab = tabs[(index + delta + tabs.count) % tabs.count]
        state.mathMenuSelection = min(state.mathMenuSelection, mathMenuItems.count - 1)
    }

    private var mathMenuItems: [CalculatorMenuItem] {
        switch state.mathMenuTab {
        case .math:
            return [
                CalculatorMenuItem("1", "▶Frac", .fraction, isEnabled: true),
                CalculatorMenuItem("2", "▶Dec",  .decimal,  isEnabled: true),
                CalculatorMenuItem("3", "³",     .insert("^3"),        isEnabled: true),
                CalculatorMenuItem("4", "³√(",   .insert("cbrt("),     isEnabled: true),
                CalculatorMenuItem("5", "ˣ√(",   .insert("root("),     isEnabled: true),
                CalculatorMenuItem("6", "fMin("),
                CalculatorMenuItem("7", "fMax("),
                CalculatorMenuItem("8", "nDeriv("),
                CalculatorMenuItem("9", "fnInt("),
                CalculatorMenuItem("0", "summation Σ("),
                CalculatorMenuItem("A", "logBASE(", .insert("logBASE("), isEnabled: true),
                CalculatorMenuItem("B", "piecewise("),
                CalculatorMenuItem("C", "Numeric Solver...")
            ]
        case .num:
            return [
                CalculatorMenuItem("1", "abs(",       .insert("abs("),       isEnabled: true),
                CalculatorMenuItem("2", "round(",      .insert("round("),     isEnabled: true),
                CalculatorMenuItem("3", "iPart(",      .insert("iPart("),     isEnabled: true),
                CalculatorMenuItem("4", "fPart(",      .insert("fPart("),     isEnabled: true),
                CalculatorMenuItem("5", "int(",        .insert("int("),       isEnabled: true),
                CalculatorMenuItem("6", "min(",        .insert("min("),       isEnabled: true),
                CalculatorMenuItem("7", "max(",        .insert("max("),       isEnabled: true),
                CalculatorMenuItem("8", "lcm(",        .insert("lcm("),       isEnabled: true),
                CalculatorMenuItem("9", "gcd(",        .insert("gcd("),       isEnabled: true),
                CalculatorMenuItem("0", "remainder(",  .insert("remainder("), isEnabled: true)
            ]
        case .cmplx:
            return [
                CalculatorMenuItem("1", "conj(",  .insert("conj("),  isEnabled: true),
                CalculatorMenuItem("2", "real(",  .insert("real("),  isEnabled: true),
                CalculatorMenuItem("3", "imag(",  .insert("imag("),  isEnabled: true),
                CalculatorMenuItem("4", "angle(", .insert("angle("), isEnabled: true),
                CalculatorMenuItem("5", "abs(",   .insert("abs("),   isEnabled: true)
            ]
        case .prob:
            return [
                CalculatorMenuItem("1", "rand",     .insert("rand"),     isEnabled: true),
                CalculatorMenuItem("2", "nPr(",     .insert("nPr("),     isEnabled: true),
                CalculatorMenuItem("3", "nCr(",     .insert("nCr("),     isEnabled: true),
                CalculatorMenuItem("4", "!",        .insert("!"),        isEnabled: true),
                CalculatorMenuItem("5", "randInt(", .insert("randInt("), isEnabled: true)
            ]
        case .frac:
            return [
                CalculatorMenuItem("1", "n/d"),
                CalculatorMenuItem("2", "Un/d"),
                CalculatorMenuItem("3", "▶F◀▶D"),
                CalculatorMenuItem("4", "▶n/d◀▶Un/d")
            ]
        }
    }

    private func handleStatMenuNavigation(_ direction: CalculatorKeypadDirection) {
        switch direction {
        case .left:
            moveStatTab(by: -1)
        case .right:
            moveStatTab(by: 1)
        case .up:
            state.statMenuSelection = max(0, state.statMenuSelection - 1)
        case .down:
            state.statMenuSelection = min(statMenuItems.count - 1, state.statMenuSelection + 1)
        }
    }

    private func handleStatMenuKey(_ action: CalculatorKeyAction) {
        switch action {
        case .evaluate:
            applyStatMenuItem(statMenuItems[state.statMenuSelection])
        case .clear:
            state.calculatorScreenMode = .home
            state.calculatorMessage = ""
        case .insert(let text):
            if let character = text.first {
                applyStatMenuShortcut(String(character).uppercased())
            }
        case .deleteBackward:
            state.calculatorScreenMode = .home
        case .toggleAngleMode, .toggleSecond:
            break
        }
    }

    private func applyStatMenuShortcut(_ key: String) {
        guard let item = statMenuItems.first(where: { $0.shortcut == key }) else { return }
        applyStatMenuItem(item)
    }

    private func applyStatMenuItem(_ item: CalculatorMenuItem) {
        guard item.isEnabled else {
            state.calculatorMessage = "\(item.title) DUMMY"
            return
        }

        switch item.output {
        case .statEditor:
            state.calculatorScreenMode = .statEditor
            state.statEntryText = ""
            state.calculatorMessage = ""
        case .regression(let model):
            runRegression(model)
        case .oneVarStats:
            runOneVarStats()
        case .twoVarStats:
            runTwoVarStats()
        default:
            break
        }
    }

    private func runRegression(_ model: CalculatorRegressionModel) {
        let xValues = state.statLists.indices.contains(0) ? state.statLists[0] : []
        let yValues = state.statLists.indices.contains(1) ? state.statLists[1] : []
        if let result = CalculatorStatistics.regression(model: model, xValues: xValues, yValues: yValues) {
            state.regressionResult = result
            state.calculatorMessage = ""
            state.calculatorScreenMode = .regressionResult
        } else {
            state.calculatorMessage = "ERR:DATA"
        }
    }

    private func runOneVarStats() {
        let data = state.statLists.indices.contains(0) ? state.statLists[0].filter { $0.isFinite } : []
        if let result = CalculatorStatistics.oneVarStats(data: data) {
            state.oneVarStatsResult = result
            state.calculatorMessage = ""
            state.calculatorScreenMode = .oneVarStats
        } else {
            state.calculatorMessage = "ERR:DATA"
        }
    }

    private func runTwoVarStats() {
        let xValues = state.statLists.indices.contains(0) ? state.statLists[0].filter { $0.isFinite } : []
        let yValues = state.statLists.indices.contains(1) ? state.statLists[1].filter { $0.isFinite } : []
        if let result = CalculatorStatistics.twoVarStats(xValues: xValues, yValues: yValues) {
            state.twoVarStatsResult = result
            state.calculatorMessage = ""
            state.calculatorScreenMode = .twoVarStats
        } else {
            state.calculatorMessage = "ERR:DATA"
        }
    }

    private func moveStatTab(by delta: Int) {
        let tabs = CalculatorStatMenuTab.allCases
        guard let index = tabs.firstIndex(of: state.statMenuTab) else { return }
        state.statMenuTab = tabs[(index + delta + tabs.count) % tabs.count]
        state.statMenuSelection = min(state.statMenuSelection, statMenuItems.count - 1)
    }

    private var statMenuItems: [CalculatorMenuItem] {
        switch state.statMenuTab {
        case .edit:
            return [
                CalculatorMenuItem("1", "Edit...", .statEditor, isEnabled: true),
                CalculatorMenuItem("2", "SortA("),
                CalculatorMenuItem("3", "SortD("),
                CalculatorMenuItem("4", "ClrList"),
                CalculatorMenuItem("5", "SetUpEditor")
            ]
        case .calc:
            return [
                CalculatorMenuItem("1", "1-Var Stats", .oneVarStats, isEnabled: true),
                CalculatorMenuItem("2", "2-Var Stats", .twoVarStats, isEnabled: true),
                CalculatorMenuItem("3", "Med-Med"),
                CalculatorMenuItem("4", "LinReg(ax+b)", .regression(.linear), isEnabled: true),
                CalculatorMenuItem("5", "QuadReg", .regression(.quadratic), isEnabled: true),
                CalculatorMenuItem("6", "CubicReg", .regression(.cubic), isEnabled: true),
                CalculatorMenuItem("7", "QuartReg", .regression(.quartic), isEnabled: true),
                CalculatorMenuItem("8", "LinReg(a+bx)")
            ]
        case .tests:
            return [
                CalculatorMenuItem("1", "Z-Test..."),
                CalculatorMenuItem("2", "T-Test..."),
                CalculatorMenuItem("3", "2-SampZTest..."),
                CalculatorMenuItem("4", "2-SampTTest...")
            ]
        }
    }

    private func handleStatEditorNavigation(_ direction: CalculatorKeypadDirection) {
        switch direction {
        case .left:
            state.statEditingColumn = max(0, state.statEditingColumn - 1)
        case .right:
            state.statEditingColumn = min(1, state.statEditingColumn + 1)
        case .up:
            commitStatEntryIfNeeded()
            state.statEditingRow = max(0, state.statEditingRow - 1)
        case .down:
            commitStatEntryIfNeeded()
            state.statEditingRow = min(9, state.statEditingRow + 1)
        }
    }

    private func handleStatEditorKey(_ action: CalculatorKeyAction) {
        switch action {
        case .insert(let text):
            if text == "-" {
                if state.statEntryText.hasPrefix("-") {
                    state.statEntryText.removeFirst()
                } else {
                    state.statEntryText = "-" + state.statEntryText
                }
            } else if text.allSatisfy({ $0.isNumber || $0 == "." }) {
                state.statEntryText += text
            }
        case .deleteBackward:
            state.statEntryText = String(state.statEntryText.dropLast())
        case .clear:
            if state.statEntryText.isEmpty {
                setStatValue(nil)
            } else {
                state.statEntryText = ""
            }
        case .evaluate:
            commitStatEntryIfNeeded()
            state.statEditingRow = min(9, state.statEditingRow + 1)
        case .toggleAngleMode, .toggleSecond:
            break
        }
    }

    private func commitStatEntryIfNeeded() {
        guard !state.statEntryText.isEmpty,
              let value = Double(state.statEntryText) else { return }
        setStatValue(value)
        state.statEntryText = ""
    }

    private func setStatValue(_ value: Double?) {
        while state.statLists.count <= state.statEditingColumn {
            state.statLists.append([])
        }
        while state.statLists[state.statEditingColumn].count <= state.statEditingRow {
            state.statLists[state.statEditingColumn].append(.nan)
        }
        state.statLists[state.statEditingColumn][state.statEditingRow] = value ?? .nan
    }

    private func handleZoomMenuKey(_ action: CalculatorKeyAction) {
        guard case .insert(let text) = action,
              let character = text.first,
              let choice = Int(String(character)) else { return }
        applyZoomChoice(choice)
    }

    private func applyZoomChoice(_ choice: Int) {
        switch choice {
        case 6:
            state.graphWindow = .default
            showGraphPlot()
        case 0, 1, 2, 3, 4, 5, 7, 8, 9:
            showGraphPlot()
        default:
            break
        }
    }

    private func showWindowEditor() {
        activeScreen = .graph
        state.graphScreenMode = .windowEditor
        state.windowEditorField = 0
        loadWindowField(0)
    }

    private func activateTrace() {
        showGraphPlot()
        let equations = state.graphEquations.filter { $0.isEnabled && !$0.expression.isEmpty }
        guard !equations.isEmpty else { return }
        state.isTraceActive = true
        state.graphTraceCursorX = (state.graphWindow.xMin + state.graphWindow.xMax) / 2
        state.graphTraceEquationIndex = 0
    }

    private func showTable() {
        activeScreen = .graph
        state.graphScreenMode = .tableView
    }

    private func quitToHome() {
        activeScreen = .calc
        state.calculatorScreenMode = .home
        state.isTraceActive = false
        state.isStoringVariable = false
        state.calculatorMessage = ""
    }

    private func showYVarsMenu() {
        activeScreen = .calc
        state.calculatorScreenMode = .yVarsMenu
        state.yVarsMenuSelection = 0
    }

    private func beginStoreVariable() {
        state.isStoringVariable = true
    }

    private func storeVariable(_ varName: String) {
        guard let value = state.lastAnswer else {
            state.isStoringVariable = false
            return
        }
        let key = varName.uppercased()
        state.storedVariables[key] = value
        let valStr = CalculatorResultFormatter.string(for: value)
        state.computeHistory.append(CalculatorHistoryEntry(expression: "Ans→\(key)", result: valStr))
        if state.computeHistory.count > 20 { state.computeHistory.removeFirst() }
        state.computeIsError = false
        state.isStoringVariable = false
    }

    // MARK: - TBLSET editor

    private func handleTblSetNavigation(_ direction: CalculatorKeypadDirection) {
        switch direction {
        case .up:
            commitTblSetField()
            state.tblSetEditorField = max(0, state.tblSetEditorField - 1)
            loadTblSetField(state.tblSetEditorField)
        case .down:
            commitTblSetField()
            state.tblSetEditorField = min(3, state.tblSetEditorField + 1)
            loadTblSetField(state.tblSetEditorField)
        case .left:
            if state.tblSetEditorField == 2 { state.tableIndpntMode = .auto }
            if state.tblSetEditorField == 3 { state.tableDependMode = .auto }
        case .right:
            if state.tblSetEditorField == 2 { state.tableIndpntMode = .ask }
            if state.tblSetEditorField == 3 { state.tableDependMode = .ask }
        }
    }

    private func handleTblSetKey(_ action: CalculatorKeyAction) {
        switch action {
        case .evaluate:
            if state.tblSetEditorField < 2 {
                commitTblSetField()
                state.tblSetEditorField = min(3, state.tblSetEditorField + 1)
                loadTblSetField(state.tblSetEditorField)
            } else {
                if state.tblSetEditorField == 2 {
                    state.tableIndpntMode = state.tableIndpntMode == .auto ? .ask : .auto
                } else {
                    state.tableDependMode = state.tableDependMode == .auto ? .ask : .auto
                }
            }
        case .clear:
            commitTblSetField()
            state.calculatorScreenMode = .home
        case .deleteBackward:
            state.tblSetEditorText = String(state.tblSetEditorText.dropLast())
        case .insert(let text):
            guard state.tblSetEditorField < 2 else { break }
            if text == "-" {
                if state.tblSetEditorText.hasPrefix("-") {
                    state.tblSetEditorText.removeFirst()
                } else {
                    state.tblSetEditorText = "-" + state.tblSetEditorText
                }
            } else if text.allSatisfy({ $0.isNumber || $0 == "." }) {
                state.tblSetEditorText += text
            }
        case .toggleAngleMode, .toggleSecond:
            break
        }
    }

    private func commitTblSetField() {
        guard state.tblSetEditorField < 2 else { return }
        let text = state.tblSetEditorText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, let value = Double(text) else { return }
        switch state.tblSetEditorField {
        case 0: state.tableStartX = value
        case 1: state.tableStep = max(1e-10, abs(value))
        default: break
        }
        state.tblSetEditorText = ""
    }

    private func loadTblSetField(_ field: Int) {
        switch field {
        case 0: state.tblSetEditorText = CalculatorResultFormatter.string(for: state.tableStartX)
        case 1: state.tblSetEditorText = CalculatorResultFormatter.string(for: state.tableStep)
        default: state.tblSetEditorText = ""
        }
    }

    private func handleWindowEditorKey(_ action: CalculatorKeyAction) {
        switch action {
        case .insert(let text):
            if text == "-" {
                if state.windowEditorText.hasPrefix("-") {
                    state.windowEditorText.removeFirst()
                } else {
                    state.windowEditorText = "-" + state.windowEditorText
                }
            } else if text.allSatisfy({ $0.isNumber || $0 == "." }) {
                state.windowEditorText += text
            }
        case .deleteBackward:
            state.windowEditorText = String(state.windowEditorText.dropLast())
        case .clear:
            state.windowEditorText = ""
        default:
            break
        }
    }

    private func commitWindowField() {
        guard !state.windowEditorText.isEmpty,
              let value = Double(state.windowEditorText), value.isFinite else {
            loadWindowField(state.windowEditorField)
            return
        }
        switch state.windowEditorField {
        case 0: state.graphWindow.xMin = value
        case 1: state.graphWindow.xMax = value
        case 2: state.graphWindow.xScl = max(0.001, value)
        case 3: state.graphWindow.yMin = value
        case 4: state.graphWindow.yMax = value
        case 5: state.graphWindow.yScl = max(0.001, value)
        default: break
        }
        state.windowEditorText = ""
    }

    private func loadWindowField(_ field: Int) {
        let value: Double
        switch field {
        case 0: value = state.graphWindow.xMin
        case 1: value = state.graphWindow.xMax
        case 2: value = state.graphWindow.xScl
        case 3: value = state.graphWindow.yMin
        case 4: value = state.graphWindow.yMax
        case 5: value = state.graphWindow.yScl
        default: return
        }
        state.windowEditorText = CalculatorResultFormatter.string(for: value)
    }

    private func ensureGraphEquation(at index: Int) {
        guard index >= 0 else { return }
        while state.graphEquations.count <= index {
            state.addEquation()
        }
        state.selectedGraphEquationID = state.graphEquations[index].id
    }

    private func ejectOrDockScreen() {
        if state.isScreenDetached {
            state.isScreenDetached = false
            state.isKeypadVisible = true
        } else {
            if !state.hasDetachedScreenSizeMemory {
                let contentWidth = max(220, CalculatorState.defaultPaletteSize.width - 28)
                state.screenSize = CGSize(width: contentWidth, height: contentWidth * 0.75)
            }
            state.screenPosition = nil
            state.isDetachedScreenVisible = true
            state.isKeypadVisible = true
            state.isScreenDetached = true
        }
    }

    private func closeKeypadOrCalculator() {
        if state.isScreenDetached {
            state.isKeypadVisible = false
            if !state.isDetachedScreenVisible {
                state.isVisible = false
            }
        } else {
            state.isVisible = false
        }
    }

    private func closeDetachedScreen() {
        state.isDetachedScreenVisible = false
        if !state.isKeypadVisible {
            state.isVisible = false
        }
    }

    // MARK: - Resize / drag

    private func screenResizeHandle(currentCenter: CGPoint, in containerSize: CGSize) -> some View {
        ResizeGrip(color: .black.opacity(0.58))
            .frame(width: 22, height: 22)
            .padding(8)
            .contentShape(Rectangle())
            .gesture(screenResizeGesture(currentCenter: currentCenter, in: containerSize))
            .help("Drag to resize screen")
    }

    private func dragGesture(in containerSize: CGSize, currentCenter: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                let base = dragStartCenter ?? currentCenter
                if dragStartCenter == nil { dragStartCenter = base }
                let proposed = CGPoint(x: base.x + value.translation.width, y: base.y + value.translation.height)
                state.position = CalculatorPaletteLayout.clamp(
                    center: proposed,
                    paletteSize: resolvedKeypadSize(),
                    in: containerSize
                )
            }
            .onEnded { _ in dragStartCenter = nil }
    }

    private func screenDragGesture(in containerSize: CGSize, currentCenter: CGPoint, windowSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                let base = screenDragStartCenter ?? currentCenter
                if screenDragStartCenter == nil { screenDragStartCenter = base }
                let proposed = CGPoint(x: base.x + value.translation.width, y: base.y + value.translation.height)
                state.screenPosition = CalculatorPaletteLayout.clamp(
                    center: proposed,
                    paletteSize: windowSize,
                    in: containerSize
                )
            }
            .onEnded { _ in screenDragStartCenter = nil }
    }

    private func screenResizeGesture(currentCenter: CGPoint, in containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let start = screenResizeStart ?? (
                    size: state.screenSize,
                    topLeft: CGPoint(x: currentCenter.x - state.screenSize.width / 2, y: currentCenter.y - (state.screenSize.height + CalculatorScreenWindow.detachedHeaderHeight) / 2)
                )
                if screenResizeStart == nil { screenResizeStart = start }

                let widthDrivenSize = CGSize(width: start.size.width + value.translation.width, height: (start.size.width + value.translation.width) * 0.75)
                let clamped = CalculatorPaletteLayout.clampScreenSize(widthDrivenSize, in: containerSize)
                state.screenSize = clamped
                state.hasDetachedScreenSizeMemory = true

                let windowSize = CGSize(width: clamped.width, height: clamped.height + CalculatorScreenWindow.detachedHeaderHeight)
                state.screenPosition = CalculatorPaletteLayout.clamp(
                    center: CGPoint(x: start.topLeft.x + windowSize.width / 2, y: start.topLeft.y + windowSize.height / 2),
                    paletteSize: windowSize,
                    in: containerSize
                )
            }
            .onEnded { _ in screenResizeStart = nil }
    }

    private func resolvedKeypadSize() -> CGSize {
        if state.isScreenDetached {
            return CGSize(
                width: CalculatorState.defaultPaletteSize.width,
                height: CalculatorFullKeypadView.height + 66
            )
        }
        return CalculatorState.defaultPaletteSize
    }

    private func resolvedKeypadCenter(keypadSize: CGSize, in containerSize: CGSize) -> CGPoint {
        let stored = state.position ?? CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)
        return CalculatorPaletteLayout.clamp(center: stored, paletteSize: keypadSize, in: containerSize)
    }

    private func resolvedScreenCenter(keypadCenter: CGPoint, windowSize: CGSize, in containerSize: CGSize) -> CGPoint {
        let keypadSize = resolvedKeypadSize()
        let gap: CGFloat = 14
        let keypadTop = keypadCenter.y - keypadSize.height / 2
        let leftAligned = CGPoint(
            x: keypadCenter.x - keypadSize.width / 2 - gap - windowSize.width / 2,
            y: keypadTop + windowSize.height / 2
        )
        return CalculatorPaletteLayout.clamp(
            center: state.screenPosition ?? leftAligned,
            paletteSize: windowSize,
            in: containerSize
        )
    }
}

private enum CalculatorScreenMode: String, CaseIterable, Equatable {
    case calc
    case graph

    var title: String {
        switch self {
        case .calc: return "Calc"
        case .graph: return "Graph"
        }
    }
}

private struct CalculatorMenuItem: Identifiable, Equatable {
    let shortcut: String
    let title: String
    let output: CalculatorMenuOutput
    let isEnabled: Bool

    init(_ shortcut: String, _ title: String, _ output: CalculatorMenuOutput = .none, isEnabled: Bool = false) {
        self.shortcut = shortcut
        self.title = title
        self.output = output
        self.isEnabled = isEnabled
    }

    var id: String { "\(shortcut):\(title)" }
}

private enum CalculatorMenuOutput: Equatable {
    case none
    case insert(String)
    case fraction
    case decimal
    case statEditor
    case regression(CalculatorRegressionModel)
    case oneVarStats
    case twoVarStats
}

// MARK: - Screen window

private struct CalculatorScreenWindow: View {
    @Bindable var state: CalculatorState
    let mode: CalculatorScreenMode
    let isDetached: Bool
    let selectCalc: () -> Void
    var dock: (() -> Void)? = nil
    var close: (() -> Void)? = nil
    var onSnapshot: (() -> Void)? = nil

    static let detachedHeaderHeight: CGFloat = 48

    var body: some View {
        VStack(spacing: 0) {
            if isDetached { detachedHeader }
            screenContent
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: isDetached ? 12 : 10))
        .overlay(
            RoundedRectangle(cornerRadius: isDetached ? 12 : 10)
                .strokeBorder(isDetached ? .black.opacity(0.35) : .black.opacity(0.45), lineWidth: isDetached ? 1.5 : 2)
        )
        .shadow(color: .black.opacity(isDetached ? 0.28 : 0), radius: isDetached ? 14 : 0, y: isDetached ? 6 : 0)
    }

    private var detachedHeader: some View {
        HStack(spacing: 8) {
            Text(mode.title)
                .font(.headline)
                .foregroundStyle(.black)
            Spacer()
            Button {
                onSnapshot?()
            } label: {
                Image(systemName: "camera.viewfinder")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(onSnapshot != nil ? Color.black : Color.black.opacity(0.3))
            }
            .buttonStyle(.plain)
            .disabled(onSnapshot == nil)
            .help("Add calculator snapshot to canvas")
            Button { dock?() } label: {
                Image(systemName: "arrow.down.to.line.compact")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            .help("Dock screen")
            Button { close?() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.black.opacity(0.65))
            }
            .buttonStyle(.plain)
            .help("Close screen")
        }
        .padding(.horizontal, 12)
        .frame(height: Self.detachedHeaderHeight)
        .background(Color.white)
        .overlay(alignment: .bottom) { Rectangle().fill(.black.opacity(0.18)).frame(height: 1) }
    }

    @ViewBuilder
    private var screenContent: some View {
        switch mode {
        case .calc:
            switch state.calculatorScreenMode {
            case .home:
                CalculatorComputeScreen(state: state, selectCalc: selectCalc)
            case .mathMenu:
                CalculatorTabbedMenuScreen(
                    tabs: CalculatorMathMenuTab.allCases.map(\.rawValue),
                    selectedTab: state.mathMenuTab.rawValue,
                    items: mathMenuItemsForDisplay,
                    selection: state.mathMenuSelection,
                    message: state.calculatorMessage
                )
            case .statMenu:
                CalculatorTabbedMenuScreen(
                    tabs: CalculatorStatMenuTab.allCases.map(\.rawValue),
                    selectedTab: state.statMenuTab.rawValue,
                    items: statMenuItemsForDisplay,
                    selection: state.statMenuSelection,
                    message: state.calculatorMessage
                )
            case .statEditor:
                CalculatorStatEditorScreen(state: state)
            case .regressionResult:
                CalculatorRegressionResultScreen(state: state)
            case .oneVarStats:
                CalculatorOneVarStatsScreen(state: state)
            case .twoVarStats:
                CalculatorTwoVarStatsScreen(state: state)
            case .yVarsMenu:
                CalculatorYVarsMenuScreen(state: state)
            case .tblSet:
                CalculatorTblSetScreen(state: state)
            case .modeMenu:
                CalculatorModeMenuScreen(state: state)
            case .nonrealError:
                CalculatorNonrealErrorScreen(state: state)
            }
        case .graph:
            switch state.graphScreenMode {
            case .equationEditor:
                CalculatorEquationEditorScreen(state: state)
            case .zoomMenu:
                CalculatorZoomMenuScreen(state: state)
            case .plot:
                CalculatorGraphCanvasOnlyView(state: state)
            case .windowEditor:
                CalculatorWindowEditorScreen(state: state)
            case .tableView:
                CalculatorTableScreen(state: state)
            case .calcMenu:
                CalculatorCalcMenuScreen(state: state)
            }
        }
    }

    private var mathMenuItemsForDisplay: [CalculatorMenuItem] {
        switch state.mathMenuTab {
        case .math:
            return [
                CalculatorMenuItem("1", "▶Frac", .fraction, isEnabled: true),
                CalculatorMenuItem("2", "▶Dec",  .decimal,  isEnabled: true),
                CalculatorMenuItem("3", "³",     .insert("^3"),        isEnabled: true),
                CalculatorMenuItem("4", "³√(",   .insert("cbrt("),     isEnabled: true),
                CalculatorMenuItem("5", "ˣ√(",   .insert("root("),     isEnabled: true),
                CalculatorMenuItem("6", "fMin("),
                CalculatorMenuItem("7", "fMax("),
                CalculatorMenuItem("8", "nDeriv("),
                CalculatorMenuItem("9", "fnInt("),
                CalculatorMenuItem("0", "summation Σ("),
                CalculatorMenuItem("A", "logBASE(", .insert("logBASE("), isEnabled: true),
                CalculatorMenuItem("B", "piecewise("),
                CalculatorMenuItem("C", "Numeric Solver...")
            ]
        case .num:
            return [
                CalculatorMenuItem("1", "abs(",       .insert("abs("),       isEnabled: true),
                CalculatorMenuItem("2", "round(",      .insert("round("),     isEnabled: true),
                CalculatorMenuItem("3", "iPart(",      .insert("iPart("),     isEnabled: true),
                CalculatorMenuItem("4", "fPart(",      .insert("fPart("),     isEnabled: true),
                CalculatorMenuItem("5", "int(",        .insert("int("),       isEnabled: true),
                CalculatorMenuItem("6", "min(",        .insert("min("),       isEnabled: true),
                CalculatorMenuItem("7", "max(",        .insert("max("),       isEnabled: true),
                CalculatorMenuItem("8", "lcm(",        .insert("lcm("),       isEnabled: true),
                CalculatorMenuItem("9", "gcd(",        .insert("gcd("),       isEnabled: true),
                CalculatorMenuItem("0", "remainder(",  .insert("remainder("), isEnabled: true)
            ]
        case .cmplx:
            return [
                CalculatorMenuItem("1", "conj(",  .insert("conj("),  isEnabled: true),
                CalculatorMenuItem("2", "real(",  .insert("real("),  isEnabled: true),
                CalculatorMenuItem("3", "imag(",  .insert("imag("),  isEnabled: true),
                CalculatorMenuItem("4", "angle(", .insert("angle("), isEnabled: true),
                CalculatorMenuItem("5", "abs(",   .insert("abs("),   isEnabled: true)
            ]
        case .prob:
            return [
                CalculatorMenuItem("1", "rand",     .insert("rand"),     isEnabled: true),
                CalculatorMenuItem("2", "nPr(",     .insert("nPr("),     isEnabled: true),
                CalculatorMenuItem("3", "nCr(",     .insert("nCr("),     isEnabled: true),
                CalculatorMenuItem("4", "!",        .insert("!"),        isEnabled: true),
                CalculatorMenuItem("5", "randInt(", .insert("randInt("), isEnabled: true)
            ]
        case .frac:
            return [
                CalculatorMenuItem("1", "n/d"),
                CalculatorMenuItem("2", "Un/d"),
                CalculatorMenuItem("3", "▶F◀▶D"),
                CalculatorMenuItem("4", "▶n/d◀▶Un/d")
            ]
        }
    }

    private var statMenuItemsForDisplay: [CalculatorMenuItem] {
        switch state.statMenuTab {
        case .edit:
            return [
                CalculatorMenuItem("1", "Edit...", .statEditor, isEnabled: true),
                CalculatorMenuItem("2", "SortA("),
                CalculatorMenuItem("3", "SortD("),
                CalculatorMenuItem("4", "ClrList"),
                CalculatorMenuItem("5", "SetUpEditor")
            ]
        case .calc:
            return [
                CalculatorMenuItem("1", "1-Var Stats", .oneVarStats, isEnabled: true),
                CalculatorMenuItem("2", "2-Var Stats", .twoVarStats, isEnabled: true),
                CalculatorMenuItem("3", "Med-Med"),
                CalculatorMenuItem("4", "LinReg(ax+b)", .regression(.linear), isEnabled: true),
                CalculatorMenuItem("5", "QuadReg", .regression(.quadratic), isEnabled: true),
                CalculatorMenuItem("6", "CubicReg", .regression(.cubic), isEnabled: true),
                CalculatorMenuItem("7", "QuartReg", .regression(.quartic), isEnabled: true),
                CalculatorMenuItem("8", "LinReg(a+bx)")
            ]
        case .tests:
            return [
                CalculatorMenuItem("1", "Z-Test..."),
                CalculatorMenuItem("2", "T-Test..."),
                CalculatorMenuItem("3", "2-SampZTest..."),
                CalculatorMenuItem("4", "2-SampTTest...")
            ]
        }
    }
}

private struct CalculatorComputeScreen: View {
    @Bindable var state: CalculatorState
    let selectCalc: () -> Void

    private static let exprFont  = Font.system(size: 20, design: .monospaced)
    private static let ansFont   = Font.system(size: 20, weight: .semibold, design: .monospaced)
    private static let errorFont = Font.system(size: 18, weight: .semibold, design: .monospaced)

    @State private var cursorVisible = true

    var body: some View {
        VStack(spacing: 0) {
            // TI-84 style status bar
            statusBar

            // Scrollable history + live input
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        if !state.computeScreenCleared {
                            ForEach(Array(state.computeHistory.enumerated()), id: \.element.id) { index, entry in
                                let lineFromBottom = state.computeHistory.count - 1 - index
                                let exprLineIdx = lineFromBottom * 2 + 1
                                let resultLineIdx = lineFromBottom * 2
                                let exprHighlighted = state.computeHistoryLine == exprLineIdx
                                let resultHighlighted = state.computeHistoryLine == resultLineIdx
                                let isMathPrint = state.calcDisplayFormat == .mathPrint

                                // Expression row
                                if isMathPrint && !exprHighlighted {
                                    MPLineView(tokens: parseMathPrint(entry.expression), em: 18)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.top, 2)
                                        .id("expr-\(index)")
                                } else {
                                    exprLine(entry.expression, highlighted: exprHighlighted)
                                        .id("expr-\(index)")
                                }

                                // Result row
                                if isMathPrint && !resultHighlighted {
                                    mpAnswerLine(entry.result, isError: false)
                                        .id("result-\(index)")
                                } else {
                                    answerLine(entry.result, isError: false, highlighted: resultHighlighted)
                                        .id("result-\(index)")
                                }
                            }
                        }

                        // Live input line + blinking block cursor
                        HStack(alignment: .bottom, spacing: 0) {
                            let displayExpr = prettifyDisplay(state.computeExpression)
                            if state.calcDisplayFormat == .mathPrint {
                                let showCursor = state.computeHistoryLine == nil
                                MPLineView(
                                    tokens: parseMathPrint(displayExpr, addCursor: showCursor),
                                    em: 20,
                                    cursorVisible: cursorVisible
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                if !displayExpr.isEmpty {
                                    Text(displayExpr)
                                        .font(Self.exprFont)
                                        .foregroundStyle(Color.black)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.75)
                                }
                                // Cursor visible only when not scrolling through history
                                if state.computeHistoryLine == nil {
                                    Rectangle()
                                        .fill(Color(white: 0.28))
                                        .frame(width: 12, height: 19)
                                        .opacity(cursorVisible ? 1 : 0)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .padding(.top, 2)

                        // Inline error (if present)
                        if state.computeIsError, !state.computeResult.isEmpty {
                            answerLine(state.computeResult, isError: true, highlighted: false)
                        }

                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
                .onChange(of: state.computeHistory.count) { _, _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                .onChange(of: state.computeExpression) { _, _ in
                    if state.computeHistoryLine == nil { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: state.computeIsError) { _, _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                .onChange(of: state.computeHistoryLine) { _, newLine in
                    guard let line = newLine else {
                        proxy.scrollTo("bottom", anchor: .bottom)
                        return
                    }
                    let entryIndex = state.computeHistory.count - 1 - line / 2
                    let scrollID = line % 2 == 0 ? "result-\(entryIndex)" : "expr-\(entryIndex)"
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(scrollID, anchor: .center)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .contentShape(Rectangle())
        .onTapGesture(perform: selectCalc)
        .overlay(alignment: .bottomLeading) {
            // Hidden TextField so system keyboard stays functional
            TextField("", text: $state.computeExpression)
                .opacity(0)
                .frame(width: 1, height: 1)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.asciiCapable)
                #endif
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(530))
                cursorVisible.toggle()
            }
        }
    }

    // TI-84 status bar: gray bar with mode indicators
    private var statusBar: some View {
        HStack(spacing: 4) {
            Text(state.calcNumberNotation.rawValue)
            Text(state.calcNumberPrecision < 0 ? "FLOAT" : "\(state.calcNumberPrecision)")
            Text(state.angleMode == .degrees ? "DEGREE" : "RADIAN")
            Spacer(minLength: 0)
            if state.isStoringVariable {
                Text("STO→")
                    .padding(.horizontal, 4)
                    .background(Color.white.opacity(0.3), in: RoundedRectangle(cornerRadius: 3))
            }
        }
        .font(.system(size: 10, weight: .bold, design: .monospaced))
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 6)
        .frame(height: 18)
        .background(Color(red: 0.42, green: 0.45, blue: 0.52))
    }

    private func prettifyDisplay(_ expr: String) -> String {
        expr
            .replacingOccurrences(of: "pi", with: "π")
            .replacingOccurrences(of: "ans", with: "Ans")
    }

    // Expression row — left-aligned; inverted when highlighted
    private func exprLine(_ text: String, highlighted: Bool) -> some View {
        Text(text)
            .font(Self.exprFont)
            .foregroundStyle(highlighted ? Color.white : Color.black)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(2)
            .minimumScaleFactor(0.75)
            .padding(.top, 2)
            .padding(.horizontal, highlighted ? 2 : 0)
            .background(highlighted ? Color.black : Color.clear)
    }

    // Answer row — dotted rule fills left, value right-aligned; inverted when highlighted
    private func answerLine(_ text: String, isError: Bool, highlighted: Bool) -> some View {
        ZStack(alignment: .trailing) {
            if highlighted {
                Color.black
            } else {
                // Dotted separator drawn across the full row height
                Canvas { ctx, size in
                    let y = size.height / 2
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(p, with: .color(.black.opacity(0.35)),
                               style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [2, 5]))
                }
            }
            // Value text
            Text(text)
                .font(isError ? Self.errorFont : Self.ansFont)
                .foregroundStyle(highlighted ? Color.white : (isError ? Color.red : Color.black))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.leading, 4)
                .background(highlighted ? Color.black : Color.white)
        }
        .frame(maxWidth: .infinity, minHeight: 22)
        .padding(.bottom, 2)
    }

    // MathPrint answer row: detects fraction results and renders as stacked fraction.
    private func mpAnswerLine(_ text: String, isError: Bool) -> some View {
        ZStack(alignment: .trailing) {
            Canvas { ctx, size in
                let y = size.height / 2
                var p = Path()
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(p, with: .color(.black.opacity(0.35)),
                           style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [2, 5]))
            }
            if let (num, den) = parseFractionResult(text), !isError {
                MPFractionView(num: [.text(num)], den: [.text(den)], em: 18)
                    .padding(.leading, 4)
                    .background(Color.white)
            } else {
                Text(text)
                    .font(isError ? Self.errorFont : Self.ansFont)
                    .foregroundStyle(isError ? Color.red : Color.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.leading, 4)
                    .background(Color.white)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 22)
        .padding(.bottom, 2)
    }

    // Detects a simple fraction string like "3/4" or "-1/2" and splits it.
    private func parseFractionResult(_ s: String) -> (num: String, den: String)? {
        let parts = s.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let num = String(parts[0]).trimmingCharacters(in: .whitespaces)
        let den = String(parts[1]).trimmingCharacters(in: .whitespaces)
        guard !num.isEmpty, !den.isEmpty,
              num.allSatisfy({ $0.isNumber || $0 == "-" }),
              den.allSatisfy({ $0.isNumber }) else { return nil }
        return (num, den)
    }
}

// MARK: - ERR: NONREAL ANSWERS screen

private struct CalculatorNonrealErrorScreen: View {
    @Bindable var state: CalculatorState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Inverted title bar
            Text("ERROR: NONREAL ANSWERS")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background(Color.black)

            // Options
            Button(action: quit) {
                Text("1:Quit")
                    .font(.system(size: 16, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
            Button(action: goto) {
                Text("2:Goto")
                    .font(.system(size: 16, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }

            Rectangle()
                .fill(Color.black)
                .frame(maxWidth: .infinity)
                .frame(height: 1)

            // Explanation
            Text("In REAL MODE, all\n  calculations must result\n  in a real number.")
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
        .buttonStyle(.plain)
    }

    private func quit() {
        state.computeExpression = ""
        state.computeResult = ""
        state.computeIsError = false
        state.nonrealErrorExpression = ""
        state.calculatorScreenMode = .home
    }

    private func goto() {
        let expr = state.nonrealErrorExpression
        let suspects = ["sqrt(", "log(", "ln(", "asin(", "acos("]
        var bestEnd = expr.count
        for name in suspects {
            if let r = expr.range(of: name, options: .caseInsensitive) {
                let pos = expr.distance(from: expr.startIndex, to: r.lowerBound)
                let end = expr.distance(from: expr.startIndex, to: r.upperBound)
                if pos < bestEnd - (bestEnd == expr.count ? 0 : name.count) {
                    bestEnd = end
                }
            }
        }
        state.computeExpression = bestEnd < expr.count ? String(expr.prefix(bestEnd)) : expr
        state.nonrealErrorExpression = ""
        state.computeResult = ""
        state.computeIsError = false
        state.calculatorScreenMode = .home
    }
}

private struct CalculatorTabbedMenuScreen: View {
    let tabs: [String]
    let selectedTab: String
    let items: [CalculatorMenuItem]
    let selection: Int
    let message: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(tabs, id: \.self) { tab in
                    Text(tab)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(tab == selectedTab ? .white : .black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(tab == selectedTab ? Color.black : Color.white)
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.black).frame(height: 1)
            }

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 8) {
                        Text("\(item.shortcut):")
                            .frame(width: 34, alignment: .trailing)
                        Text(item.title)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !item.isEnabled {
                            Text("DUMMY")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.black.opacity(0.58))
                        }
                    }
                    .font(.system(size: 21, weight: index == selection ? .bold : .regular, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .padding(.horizontal, 8)
                    .frame(height: 25)
                    .background(index == selection ? Color.black.opacity(0.1) : Color.white)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)

            Spacer(minLength: 0)

            if !message.isEmpty {
                Text(message)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.08))
            }
        }
        .foregroundStyle(.black)
        .background(Color.white)
    }
}

private struct CalculatorStatEditorScreen: View {
    @Bindable var state: CalculatorState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                header("L1", column: 0)
                header("L2", column: 1)
            }

            ForEach(0..<7, id: \.self) { row in
                HStack(spacing: 0) {
                    cell(column: 0, row: row)
                    cell(column: 1, row: row)
                }
            }

            Spacer(minLength: 0)
            Text("STAT EDIT  \(entryLabel)")
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundStyle(.black.opacity(0.75))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Color.black.opacity(0.08))
        }
        .background(Color.white)
    }

    private func header(_ text: String, column: Int) -> some View {
        Text(text)
            .font(.system(size: 21, weight: .bold, design: .monospaced))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(column == state.statEditingColumn ? Color.black.opacity(0.12) : Color.white)
            .overlay(Rectangle().strokeBorder(Color.black.opacity(0.35), lineWidth: 0.5))
    }

    private func cell(column: Int, row: Int) -> some View {
        let isSelected = state.statEditingColumn == column && state.statEditingRow == row
        return HStack(spacing: 4) {
            Text("\(row + 1)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.black.opacity(0.55))
                .frame(width: 16, alignment: .trailing)
            Text(cellText(column: column, row: row, isSelected: isSelected))
                .font(.system(size: 19, weight: isSelected ? .bold : .regular, design: .monospaced))
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .frame(height: 24)
        .background(isSelected ? Color.black.opacity(0.12) : Color.white)
        .overlay(Rectangle().strokeBorder(Color.black.opacity(0.18), lineWidth: 0.5))
    }

    private var entryLabel: String {
        let listName = state.statEditingColumn == 0 ? "L1" : "L2"
        return "\(listName)(\(state.statEditingRow + 1))=\(state.statEntryText)"
    }

    private func cellText(column: Int, row: Int, isSelected: Bool) -> String {
        if isSelected, !state.statEntryText.isEmpty {
            return state.statEntryText
        }
        guard state.statLists.indices.contains(column),
              state.statLists[column].indices.contains(row) else { return "" }
        let value = state.statLists[column][row]
        guard value.isFinite else { return "" }
        return CalculatorResultFormatter.string(for: value)
    }
}

private struct CalculatorRegressionResultScreen: View {
    @Bindable var state: CalculatorState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(result?.model.title ?? "Regression")
                .font(.system(size: 21, weight: .bold, design: .monospaced))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .frame(height: 32)
                .background(Color.black.opacity(0.08))

            if let result {
                ForEach(Array(result.model.coefficientNames.enumerated()), id: \.offset) { index, name in
                    if result.coefficients.indices.contains(index) {
                        resultRow(name: name, value: result.coefficients[index])
                    }
                }
                if let rSquared = result.rSquared {
                    resultRow(name: "R²", value: rSquared)
                }
                Text("y=\(result.model.expression(coefficients: result.coefficients))")
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
            } else {
                Text("ERR:DATA")
                    .font(.system(size: 21, weight: .bold, design: .monospaced))
                    .foregroundStyle(.black)
                    .padding(8)
            }

            Spacer(minLength: 0)
        }
        .background(Color.white)
    }

    private var result: CalculatorRegressionResult? {
        state.regressionResult
    }

    private func resultRow(name: String, value: Double) -> some View {
        HStack {
            Text("\(name)=")
                .frame(width: 34, alignment: .trailing)
            Text(CalculatorResultFormatter.string(for: value))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 19, weight: .regular, design: .monospaced))
        .foregroundStyle(.black)
        .padding(.horizontal, 8)
        .frame(height: 24)
    }
}

private struct CalculatorEquationEditorScreen: View {
    @Bindable var state: CalculatorState
    @State private var cursorVisible = true
    @State private var stylePickerPresented = false

    private static let exprFont = Font.system(size: 24, weight: .regular, design: .monospaced)
    private static let labelFont = Font.system(size: 27, weight: .bold, design: .monospaced)
    private static let cursorW: CGFloat = 14
    private static let cursorH: CGFloat = 22
    private let rowCount = 8

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            plotHeader
            equationRows
                .popover(isPresented: $stylePickerPresented, arrowEdge: .leading) {
                    if let id = state.selectedGraphEquationID,
                       let eqIdx = state.graphEquations.firstIndex(where: { $0.id == id }) {
                        EquationStylePickerPopover(
                            colorIndex: $state.graphEquations[eqIdx].colorIndex,
                            lineStyleIndex: $state.graphEquations[eqIdx].lineStyleIndex
                        )
                    }
                }
            Spacer(minLength: 0)
        }
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(.black)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
        .onAppear {
            if state.selectedGraphEquationID == nil {
                ensureEquation(at: 0)
            }
        }
        .onChange(of: state.isEquationStylePickerVisible) { _, new in
            stylePickerPresented = new
        }
        .onChange(of: stylePickerPresented) { _, new in
            state.isEquationStylePickerVisible = new
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(530))
                cursorVisible.toggle()
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 5) {
            Text("NORMAL")
            Text("FLOAT")
            Text(state.angleMode == .degrees ? "DEG" : "RAD")
            Text("AUTO")
            Text("REAL")
            Text("MP")
            Spacer(minLength: 0)
        }
        .font(.system(size: 17, weight: .bold, design: .monospaced))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .frame(height: 22)
        .background(Color(red: 0.45, green: 0.48, blue: 0.55))
    }

    private var plotHeader: some View {
        HStack(spacing: 0) {
            Text("Plot1")
                .frame(maxWidth: .infinity)
            Text("Plot2")
                .frame(maxWidth: .infinity)
            Text("Plot3")
                .frame(maxWidth: .infinity)
        }
        .font(.system(size: 21, weight: .bold, design: .monospaced))
        .frame(height: 34)
        .background(Color.white)
    }

    private var equationRows: some View {
        VStack(spacing: 0) {
            ForEach(0..<rowCount, id: \.self) { index in
                equationRow(index: index)
            }
        }
    }

    private func equationRow(index: Int) -> some View {
        let equation = index < state.graphEquations.count ? state.graphEquations[index] : nil
        let isSelected = equation?.id == state.selectedGraphEquationID
        let expression = equation?.expression ?? ""
        let col = state.equationEditorColumn

        // ONLY the = sign is highlighted, never Y or the number.
        // Lit (black bg) when equation has content and isEnabled.
        // Blinks when cursor is on col=1 for this row.
        let equalsEnabled = (equation?.isEnabled ?? false) && !expression.isEmpty
        let equalsLit: Bool
        if isSelected && col == 1 {
            equalsLit = cursorVisible
        } else {
            equalsLit = equalsEnabled
        }

        let swatchInverted = isSelected && col == 0
        let charIdx = isSelected && col == 2 ? min(state.equationEditorCharIndex, expression.count) : expression.count
        let before = String(expression.prefix(charIdx))
        let after = String(expression.dropFirst(charIdx))

        return HStack(spacing: 0) {
            // Swatch + line style — tappable to open style popover
            HStack(spacing: 3) {
                Rectangle()
                    .fill(swatchInverted ? Color.white : equationColor(for: equation))
                    .frame(width: 10, height: 18)
                lineStyleIcon(for: equation, inverted: swatchInverted)
            }
            .padding(.horizontal, 3)
            .frame(height: 26)
            .background(swatchInverted ? Color.black : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture {
                ensureEquation(at: index)
                state.equationEditorColumn = 0
                stylePickerPresented = true
            }

            // Y + row number — never highlighted (plain text always)
            Text("Y\(index + 1)")
                .font(Self.labelFont)
                .foregroundStyle(Color.black)
                .padding(.leading, 2)
                .frame(width: 38, alignment: .leading)

            // = sign — ONLY this gets the enabled highlight; tappable to toggle on/off
            Text("=")
                .font(Self.labelFont)
                .foregroundStyle(equalsLit ? Color.white : Color.black)
                .padding(.horizontal, 2)
                .background(equalsLit ? Color.black : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    ensureEquation(at: index)
                    guard let id = equation?.id ?? state.selectedGraphEquationID,
                          let idx = state.graphEquations.firstIndex(where: { $0.id == id }) else { return }
                    state.graphEquations[idx].isEnabled.toggle()
                }

            // Expression with character-level cursor — tappable to position cursor at end
            HStack(alignment: .center, spacing: 0) {
                if !before.isEmpty {
                    Text(before)
                        .font(Self.exprFont)
                        .foregroundStyle(Color.black)
                }
                if isSelected && col == 2 {
                    Rectangle()
                        .fill(Color(white: 0.28))
                        .frame(width: Self.cursorW, height: Self.cursorH)
                        .opacity(cursorVisible ? 1 : 0)
                }
                if !after.isEmpty {
                    Text(after)
                        .font(Self.exprFont)
                        .foregroundStyle(Color.black)
                }
                Spacer(minLength: 0)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 2)
            .contentShape(Rectangle())
            .onTapGesture {
                let didChangeRow = state.selectedGraphEquationID != equation?.id
                ensureEquation(at: index)
                state.equationEditorColumn = 2
                state.isEquationStylePickerVisible = false
                state.equationEditorCharIndex = didChangeRow ? expression.count : min(state.equationEditorCharIndex, expression.count)
            }
        }
        .frame(height: 28)
        .background(Color.white)
    }

    // MARK: - Helpers

    private func ensureEquation(at index: Int) {
        while state.graphEquations.count <= index {
            state.addEquation()
        }
        state.selectedGraphEquationID = state.graphEquations[index].id
    }

    private func equationColor(for equation: GraphEquation?) -> Color {
        guard let equation else { return color(for: 0) }
        let rgb = GraphPalette.rgb(for: equation.colorIndex)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    private func color(for index: Int) -> Color {
        let rgb = GraphPalette.rgb(for: index)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    @ViewBuilder
    private func lineStyleIcon(for equation: GraphEquation?, inverted: Bool) -> some View {
        let style = EquationLineStyle(rawValue: equation?.lineStyleIndex ?? 0) ?? .solid
        let strokeColor: Color = inverted ? .white.opacity(0.9) : .black.opacity(0.75)
        switch style {
        case .solid:
            // TI-84 default: diagonal segment going up and to the right (/)
            Path { path in
                path.move(to: CGPoint(x: 2, y: 17))
                path.addLine(to: CGPoint(x: 16, y: 3))
            }
            .stroke(strokeColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .frame(width: 18, height: 20)
        case .thick:
            Path { path in
                path.move(to: CGPoint(x: 2, y: 17))
                path.addLine(to: CGPoint(x: 16, y: 3))
            }
            .stroke(strokeColor, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
            .frame(width: 18, height: 20)
        case .dotted:
            Path { path in
                path.move(to: CGPoint(x: 2, y: 17))
                path.addLine(to: CGPoint(x: 16, y: 3))
            }
            .stroke(strokeColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [2, 3]))
            .frame(width: 18, height: 20)
        case .dashed:
            Path { path in
                path.move(to: CGPoint(x: 2, y: 17))
                path.addLine(to: CGPoint(x: 16, y: 3))
            }
            .stroke(strokeColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [5, 3]))
            .frame(width: 18, height: 20)
        case .shadeAbove:
            Path { path in
                path.move(to: CGPoint(x: 2, y: 10))
                path.addLine(to: CGPoint(x: 16, y: 10))
            }
            .stroke(strokeColor, lineWidth: 2)
            .frame(width: 18, height: 20)
            .overlay(alignment: .topLeading) {
                Text("▲").font(.system(size: 7)).foregroundStyle(strokeColor).offset(x: 3, y: 0)
            }
        case .shadeBelow:
            Path { path in
                path.move(to: CGPoint(x: 2, y: 10))
                path.addLine(to: CGPoint(x: 16, y: 10))
            }
            .stroke(strokeColor, lineWidth: 2)
            .frame(width: 18, height: 20)
            .overlay(alignment: .bottomLeading) {
                Text("▼").font(.system(size: 7)).foregroundStyle(strokeColor).offset(x: 3, y: 0)
            }
        }
    }
}

private struct EquationStylePickerPopover: View {
    @Binding var colorIndex: Int
    @Binding var lineStyleIndex: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Equation Style")
                .font(.headline)
                .padding(.bottom, 12)

            Text("Color")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("Color", selection: $colorIndex) {
                ForEach(0..<GraphPalette.colors.count, id: \.self) { ci in
                    let rgb = GraphPalette.colors[ci]
                    Label {
                        Text(GraphPalette.colorNames[ci])
                    } icon: {
                        Circle()
                            .fill(Color(red: rgb.red, green: rgb.green, blue: rgb.blue))
                            .frame(width: 14, height: 14)
                    }
                    .tag(ci)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .padding(.bottom, 14)

            Text("Line Style")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("Line Style", selection: $lineStyleIndex) {
                ForEach(EquationLineStyle.allCases, id: \.rawValue) { style in
                    Text("\(style.displaySymbol)  \(style.name)")
                        .tag(style.rawValue)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .padding(20)
        .frame(minWidth: 200)
    }
}

// MARK: - MODE menu screen

private struct CalculatorModeMenuScreen: View {
    @Bindable var state: CalculatorState

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                header
                modeRow(0, label: nil,              options: CalcDisplayFormat.allCases.map(\.rawValue),       selected: state.calcDisplayFormat.rawValue,  onTap: { v in state.calcDisplayFormat  = CalcDisplayFormat(rawValue: v)!  })
                modeRow(1, label: nil,              options: CalcNumberNotation.allCases.map(\.rawValue),      selected: state.calcNumberNotation.rawValue, onTap: { v in state.calcNumberNotation = CalcNumberNotation(rawValue: v)! })
                precisionRow
                modeRow(3, label: nil,              options: ["RADIAN", "DEGREE"],                            selected: state.angleMode == .radians ? "RADIAN" : "DEGREE", onTap: { v in state.angleMode = v == "RADIAN" ? .radians : .degrees })
                modeRow(4, label: nil,              options: CalcGraphType.allCases.map(\.rawValue),          selected: state.calcGraphType.rawValue,      onTap: { v in state.calcGraphType     = CalcGraphType(rawValue: v)!     })
                modeRow(5, label: nil,              options: CalcDrawMode.allCases.map(\.rawValue),           selected: state.calcDrawMode.rawValue,       onTap: { v in state.calcDrawMode      = CalcDrawMode(rawValue: v)!      })
                modeRow(6, label: nil,              options: CalcEvalOrder.allCases.map(\.rawValue),          selected: state.calcEvalOrder.rawValue,      onTap: { v in state.calcEvalOrder     = CalcEvalOrder(rawValue: v)!     })
                modeRow(7, label: nil,              options: CalcComplexMode.allCases.map(\.rawValue),        selected: state.calcComplexMode.rawValue,    onTap: { v in state.calcComplexMode   = CalcComplexMode(rawValue: v)!   })
                modeRow(8, label: nil,              options: CalcScreenLayout.allCases.map(\.rawValue),       selected: state.calcScreenLayout.rawValue,   onTap: { v in state.calcScreenLayout  = CalcScreenLayout(rawValue: v)!  })
                modeRow(9, label: "FRACTION TYPE:", options: CalcFractionType.allCases.map(\.rawValue),       selected: state.calcFractionType.rawValue,   onTap: { v in state.calcFractionType  = CalcFractionType(rawValue: v)!  })
                modeRow(10, label: "ANSWERS:",      options: CalcAnswerMode.allCases.map(\.rawValue),         selected: state.calcAnswerMode.rawValue,     onTap: { v in state.calcAnswerMode    = CalcAnswerMode(rawValue: v)!    })
                modeRow(11, label: "STAT DIAGNOSTICS:", options: ["OFF", "ON"],                               selected: state.calcStatDiagnostics ? "ON" : "OFF", onTap: { v in state.calcStatDiagnostics = v == "ON" })
                modeRow(12, label: "STAT WIZARDS:", options: ["ON", "OFF"],                                   selected: state.calcStatWizards ? "ON" : "OFF",     onTap: { v in state.calcStatWizards     = v == "ON" })
                staticRow("SET CLOCK")
                staticRow("LANGUAGE:  ENGLISH")
            }
        }
        .foregroundStyle(.black)
        .background(Color.white)
        .contentShape(Rectangle())
        .onTapGesture { /* absorb */ }
    }

    private var header: some View {
        Text("MODE")
            .font(.system(size: 15, weight: .bold, design: .monospaced))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .frame(height: 22)
            .background(Color.black.opacity(0.08))
    }

    private var precisionRow: some View {
        let options: [(label: String, value: Int)] = [("FLOAT", -1)] + (0...9).map { ("\($0)", $0) }
        let isCurrentRow = state.modeMenuRow == 2
        return HStack(spacing: 0) {
            ForEach(options, id: \.value) { opt in
                let isSelected = state.calcNumberPrecision == opt.value
                Text(opt.label)
                    .font(.system(size: isCurrentRow && isSelected ? 12 : 11,
                                  weight: isSelected ? .bold : .regular,
                                  design: .monospaced))
                    .foregroundStyle(isSelected ? Color.white : Color.black)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 1)
                    .background(isSelected ? Color.black : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { state.calcNumberPrecision = opt.value; state.modeMenuRow = 2 }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .frame(height: 16)
        .background(isCurrentRow ? Color.black.opacity(0.06) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { state.modeMenuRow = 2 }
    }

    private func modeRow(_ rowIdx: Int, label: String?, options: [String], selected: String, onTap: @escaping (String) -> Void) -> some View {
        let isCurrentRow = state.modeMenuRow == rowIdx
        return HStack(spacing: 0) {
            if let label {
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.black)
                    .padding(.trailing, 3)
            }
            ForEach(options, id: \.self) { opt in
                let isSelected = opt == selected
                Text(opt)
                    .font(.system(size: 11, weight: isSelected ? .bold : .regular, design: .monospaced))
                    .foregroundStyle(isSelected ? Color.white : Color.black)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(isSelected ? Color.black : Color.clear)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentShape(Rectangle())
                    .onTapGesture { onTap(opt); state.modeMenuRow = rowIdx }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .frame(height: 16)
        .background(isCurrentRow ? Color.black.opacity(0.06) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { state.modeMenuRow = rowIdx }
    }

    private func staticRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundStyle(.black.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .frame(height: 16)
    }
}

// MARK: - CALC menu screen (2nd+TRACE)

private struct CalculatorCalcMenuScreen: View {
    @Bindable var state: CalculatorState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("CALCULATE")
                    .font(.system(size: 19, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(Color.black)
            }
            .overlay(alignment: .bottom) { Rectangle().fill(Color.black).frame(height: 1) }

            ForEach(CalcToolOperation.allCases, id: \.rawValue) { op in
                let isSelected = state.calcToolMenuSelection == op.rawValue
                HStack(spacing: 8) {
                    Text("\(op.rawValue + 1):")
                        .frame(width: 26, alignment: .trailing)
                    Text(op.menuTitle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 21, weight: isSelected ? .bold : .regular, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(isSelected ? Color.white : Color.black)
                .padding(.horizontal, 8)
                .frame(height: 25)
                .background(isSelected ? Color.black : Color.white)
                .contentShape(Rectangle())
                .onTapGesture { state.beginCalcTool(operation: op) }
            }

            Spacer(minLength: 0)
        }
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(.black)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
    }
}

private struct CalculatorZoomMenuScreen: View {
    @Bindable var state: CalculatorState

    private let zoomChoices: [ZoomChoice] = [
        ZoomChoice(number: 1, title: "ZBox"),
        ZoomChoice(number: 2, title: "Zoom In"),
        ZoomChoice(number: 3, title: "Zoom Out"),
        ZoomChoice(number: 4, title: "ZDecimal"),
        ZoomChoice(number: 5, title: "ZSquare"),
        ZoomChoice(number: 6, title: "ZStandard", isTaught: true),
        ZoomChoice(number: 7, title: "ZTrig"),
        ZoomChoice(number: 8, title: "ZInteger"),
        ZoomChoice(number: 9, title: "ZoomStat"),
        ZoomChoice(number: 0, title: "ZoomFit")
    ]

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            menuRows
            Spacer(minLength: 0)
        }
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(.black)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            Text("ZOOM")
                .font(.system(size: 19, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(Color.black)

            Text("MEMORY")
                .font(.system(size: 19, weight: .bold, design: .monospaced))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(Color.white)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black)
                .frame(height: 1)
        }
    }

    private var menuRows: some View {
        VStack(spacing: 0) {
            ForEach(visibleChoices) { choice in
                HStack(spacing: 8) {
                    Text("\(choice.number):")
                        .frame(width: 32, alignment: .trailing)
                    Text(choice.title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if choice.isTaught {
                        Text("ready")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black, in: Capsule())
                    }
                }
                .font(.system(size: 21, weight: choice.isTaught ? .bold : .regular, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(choice.isTaught ? Color.black.opacity(0.08) : Color.white)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if state.zoomMenuOffset == 0 {
                Image(systemName: "arrow.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black.opacity(0.62))
                    .padding(.trailing, 8)
                    .padding(.bottom, 4)
            } else {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black.opacity(0.62))
                    .padding(.trailing, 8)
                    .padding(.bottom, 4)
            }
        }
    }

    private var visibleChoices: [ZoomChoice] {
        let offset = min(max(state.zoomMenuOffset, 0), 1)
        return Array(zoomChoices.dropFirst(offset).prefix(9))
    }

    private struct ZoomChoice: Identifiable {
        let number: Int
        let title: String
        var isTaught = false

        var id: Int { number }
    }
}

private struct CalculatorGraphCanvasOnlyView: View {
    @Bindable var state: CalculatorState

    private let engine = CalculatorEngine()
    @State private var zoomStartWindow: GraphWindow?
    @State private var lastPanTranslation: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            Canvas { context, _ in
                CalculatorGraphRenderer.draw(
                    in: context,
                    size: size,
                    window: state.graphWindow,
                    equations: state.graphEquations,
                    angleMode: state.angleMode,
                    engine: engine
                )
                if state.isTraceActive {
                    drawTraceCursor(in: context, size: size)
                }
                if state.calcToolPhase != .none {
                    drawCalcToolOverlay(in: context, size: size)
                }
            }
            .background(Color.white)
            .contentShape(Rectangle())
            .gesture(panGesture(size: size))
            .simultaneousGesture(zoomGesture(size: size))
            .overlay(alignment: .topTrailing) {
                VStack(spacing: 8) {
                    zoomButton("plus.magnifyingglass") { zoomBy(1.4) }
                    zoomButton("minus.magnifyingglass") { zoomBy(1 / 1.4) }
                }
                .padding(8)
            }
            .overlay(alignment: .bottomLeading) {
                if state.calcToolPhase == .result {
                    calcResultReadout
                } else if state.calcToolPhase != .none {
                    calcPromptOverlay
                } else if state.isTraceActive {
                    traceReadout(size: size)
                } else {
                    equationBadge
                }
            }
        }
        .background(Color.white)
    }

    private func drawTraceCursor(in context: GraphicsContext, size: CGSize) {
        let equations = state.graphEquations.filter { $0.isEnabled && !$0.expression.isEmpty }
        guard !equations.isEmpty else { return }
        let eqIndex = state.graphTraceEquationIndex % equations.count
        let equation = equations[eqIndex]

        var variables: [String: Double] = state.lastAnswer.map { ["ans": $0] } ?? [:]
        for (k, v) in state.storedVariables { variables[k] = v }
        let compiled = try? engine.compile(equation.expression)
        let y: Double?
        if let compiled {
            y = try? engine.evaluate(compiled: compiled, angleMode: state.angleMode, variables: variables.merging(["x": state.graphTraceCursorX]) { _, new in new })
        } else {
            y = nil
        }

        guard let cursorY = y, cursorY.isFinite,
              cursorY >= state.graphWindow.yMin, cursorY <= state.graphWindow.yMax else { return }

        let viewPt = CalculatorGraphGeometry.viewPoint(
            forGraph: CGPoint(x: state.graphTraceCursorX, y: cursorY),
            window: state.graphWindow,
            size: size
        )

        let rgb = GraphPalette.rgb(for: equation.colorIndex)
        let cursorColor = Color(red: rgb.red, green: rgb.green, blue: rgb.blue)

        // Crosshair lines
        var h = Path()
        h.move(to: CGPoint(x: 0, y: viewPt.y))
        h.addLine(to: CGPoint(x: size.width, y: viewPt.y))
        context.stroke(h, with: .color(.black.opacity(0.25)), lineWidth: 0.5)

        var v = Path()
        v.move(to: CGPoint(x: viewPt.x, y: 0))
        v.addLine(to: CGPoint(x: viewPt.x, y: size.height))
        context.stroke(v, with: .color(.black.opacity(0.25)), lineWidth: 0.5)

        // Cursor dot
        let dot = Path(ellipseIn: CGRect(x: viewPt.x - 5, y: viewPt.y - 5, width: 10, height: 10))
        context.fill(dot, with: .color(cursorColor))
        context.stroke(dot, with: .color(.black), lineWidth: 1.5)
    }

    // MARK: - CALC tool canvas drawing

    private func drawCalcToolOverlay(in context: GraphicsContext, size: CGSize) {
        let equations = state.graphEquations.filter { $0.isEnabled && !$0.expression.isEmpty }
        guard !equations.isEmpty else { return }

        // Choose which curve the crosshair cursor snaps to
        let eqIdx: Int
        if state.calcToolOperation == .intersect {
            switch state.calcToolPhase {
            case .rightBound: eqIdx = state.calcToolCurveIndex2 % equations.count
            default:          eqIdx = state.calcToolCurveIndex1 % equations.count
            }
        } else {
            eqIdx = max(0, state.graphTraceEquationIndex) % equations.count
        }
        let equation = equations[eqIdx]
        let rgb = GraphPalette.rgb(for: equation.colorIndex)
        let cursorColor = Color(red: rgb.red, green: rgb.green, blue: rgb.blue)

        var variables: [String: Double] = state.lastAnswer.map { ["ans": $0] } ?? [:]
        for (k, v) in state.storedVariables { variables[k] = v }

        func evalY(_ x: Double) -> Double? {
            guard let compiled = try? engine.compile(equation.expression) else { return nil }
            let vars = variables.merging(["x": x]) { _, new in new }
            return try? engine.evaluate(compiled: compiled, angleMode: state.angleMode, variables: vars)
        }

        // Left bound marker — small solid downward-pointing triangle at top of screen
        if let lb = state.calcToolLeftBound {
            let vx = CalculatorGraphGeometry.viewPoint(
                forGraph: CGPoint(x: lb, y: state.graphWindow.yMax),
                window: state.graphWindow, size: size).x
            var p = Path()
            p.move(to: CGPoint(x: vx, y: 0))
            p.addLine(to: CGPoint(x: vx - 6, y: 11))
            p.addLine(to: CGPoint(x: vx + 6, y: 11))
            p.closeSubpath()
            context.fill(p, with: .color(.black))
        }

        // Right bound marker
        if let rb = state.calcToolRightBound {
            let vx = CalculatorGraphGeometry.viewPoint(
                forGraph: CGPoint(x: rb, y: state.graphWindow.yMax),
                window: state.graphWindow, size: size).x
            var p = Path()
            p.move(to: CGPoint(x: vx, y: 0))
            p.addLine(to: CGPoint(x: vx - 6, y: 11))
            p.addLine(to: CGPoint(x: vx + 6, y: 11))
            p.closeSubpath()
            context.fill(p, with: .color(.black))
        }

        let cx = state.calcToolCursorX

        // In result phase: draw result point and return (no moving cursor)
        if state.calcToolPhase == .result {
            if let rx = state.calcToolResultX, let ry = state.calcToolResultY {
                let rPt = CalculatorGraphGeometry.viewPoint(
                    forGraph: CGPoint(x: rx, y: ry),
                    window: state.graphWindow, size: size)
                if ry >= state.graphWindow.yMin && ry <= state.graphWindow.yMax {
                    var h = Path(); h.move(to: CGPoint(x: 0, y: rPt.y)); h.addLine(to: CGPoint(x: size.width, y: rPt.y))
                    var v = Path(); v.move(to: CGPoint(x: rPt.x, y: 0)); v.addLine(to: CGPoint(x: rPt.x, y: size.height))
                    context.stroke(h, with: .color(.black.opacity(0.25)), lineWidth: 0.5)
                    context.stroke(v, with: .color(.black.opacity(0.25)), lineWidth: 0.5)
                    let dot = Path(ellipseIn: CGRect(x: rPt.x - 5, y: rPt.y - 5, width: 10, height: 10))
                    context.fill(dot, with: .color(cursorColor))
                    context.stroke(dot, with: .color(.black), lineWidth: 1.5)
                }
            }
            return
        }

        // Moving cursor: snap to the curve, draw crosshair
        guard let cursorY = evalY(cx), cursorY.isFinite else {
            // Still draw a vertical guide even when off-curve
            let vx = CalculatorGraphGeometry.viewPoint(
                forGraph: CGPoint(x: cx, y: 0), window: state.graphWindow, size: size).x
            var v = Path(); v.move(to: CGPoint(x: vx, y: 0)); v.addLine(to: CGPoint(x: vx, y: size.height))
            context.stroke(v, with: .color(.black.opacity(0.3)), lineWidth: 0.5)
            return
        }

        let viewPt = CalculatorGraphGeometry.viewPoint(
            forGraph: CGPoint(x: cx, y: cursorY), window: state.graphWindow, size: size)

        var h = Path(); h.move(to: CGPoint(x: 0, y: viewPt.y)); h.addLine(to: CGPoint(x: size.width, y: viewPt.y))
        var v = Path(); v.move(to: CGPoint(x: viewPt.x, y: 0)); v.addLine(to: CGPoint(x: viewPt.x, y: size.height))
        context.stroke(h, with: .color(.black.opacity(0.25)), lineWidth: 0.5)
        context.stroke(v, with: .color(.black.opacity(0.25)), lineWidth: 0.5)

        let dot = Path(ellipseIn: CGRect(x: viewPt.x - 5, y: viewPt.y - 5, width: 10, height: 10))
        context.fill(dot, with: .color(cursorColor))
        context.stroke(dot, with: .color(.black), lineWidth: 1.5)
    }

    private var calcPromptOverlay: some View {
        let equations = state.graphEquations.filter { $0.isEnabled && !$0.expression.isEmpty }
        let hasFunc = !equations.isEmpty
        let isIntersect = state.calcToolOperation == .intersect

        let promptText: String
        var curveLabel: String? = nil
        switch state.calcToolPhase {
        case .leftBound:
            if state.calcToolOperation.boundPhaseCount == 0 {
                promptText = state.calcToolOperation.menuTitle.uppercased()
            } else if isIntersect {
                promptText = "1st Curve?"
                if hasFunc {
                    let idx = state.calcToolCurveIndex1 % equations.count
                    curveLabel = "Y\(idx + 1)"
                }
            } else {
                promptText = "Left Bound?"
            }
        case .rightBound:
            if isIntersect {
                promptText = "2nd Curve?"
                if hasFunc {
                    let idx = state.calcToolCurveIndex2 % equations.count
                    curveLabel = "Y\(idx + 1)"
                }
            } else {
                promptText = "Right Bound?"
            }
        case .guess:      promptText = "Guess?"
        default:          promptText = ""
        }

        let xLabel: String
        if hasFunc {
            xLabel = "X=" + CalculatorResultFormatter.string(for: state.calcToolCursorX)
        } else {
            xLabel = "ERR:no function"
        }

        return VStack(alignment: .leading, spacing: 1) {
            Text(promptText)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
            if let label = curveLabel {
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
            Text(xLabel)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.black.opacity(0.22), lineWidth: 0.5))
        .padding(8)
    }

    private var calcResultReadout: some View {
        VStack(alignment: .leading, spacing: 1) {
            if !state.calcToolResultLabel.isEmpty {
                Text(state.calcToolResultLabel)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
            }
            if let rx = state.calcToolResultX {
                Text("X=" + CalculatorResultFormatter.string(for: rx))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
            if let ry = state.calcToolResultY {
                Text("Y=" + CalculatorResultFormatter.string(for: ry))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.black.opacity(0.22), lineWidth: 0.5))
        .padding(8)
    }

    private func traceReadout(size: CGSize) -> some View {
        let equations = state.graphEquations.filter { $0.isEnabled && !$0.expression.isEmpty }
        let eqIndex = equations.isEmpty ? 0 : state.graphTraceEquationIndex % equations.count
        let expression = equations.indices.contains(eqIndex) ? equations[eqIndex].expression : ""

        var variables: [String: Double] = state.lastAnswer.map { ["ans": $0] } ?? [:]
        for (k, v) in state.storedVariables { variables[k] = v }
        let allVars = variables.merging(["x": state.graphTraceCursorX]) { _, new in new }
        let y = (try? engine.evaluate(expression, angleMode: state.angleMode, variables: allVars)).flatMap { $0.isFinite ? $0 : nil }

        let xStr = "X=" + CalculatorResultFormatter.string(for: state.graphTraceCursorX)
        let yStr = y.map { "Y=" + CalculatorResultFormatter.string(for: $0) } ?? "Y=undefined"

        return VStack(alignment: .leading, spacing: 2) {
            Text(expression.isEmpty ? "Y\(eqIndex + 1)" : expression)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(xStr)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
            Text(yStr)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.black.opacity(0.22), lineWidth: 0.5))
        .padding(8)
    }

    private var equationBadge: some View {
        let expression = state.graphEquations.first?.expression ?? ""
        return Text(expression.isEmpty ? "y =" : "y = \(expression)")
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.88), in: Capsule())
            .overlay(Capsule().strokeBorder(.black.opacity(0.18), lineWidth: 0.5))
            .padding(8)
    }

    private func zoomButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.88), in: Circle())
                .overlay(Circle().strokeBorder(.black.opacity(0.22), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.black)
    }

    private func panGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let delta = CGSize(
                    width: value.translation.width - lastPanTranslation.width,
                    height: value.translation.height - lastPanTranslation.height
                )
                lastPanTranslation = value.translation
                state.graphWindow = CalculatorGraphGeometry.pan(
                    window: state.graphWindow,
                    byViewTranslation: delta,
                    size: size
                )
            }
            .onEnded { _ in lastPanTranslation = .zero }
    }

    private func zoomGesture(size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = zoomStartWindow ?? state.graphWindow
                if zoomStartWindow == nil { zoomStartWindow = start }
                state.graphWindow = CalculatorGraphGeometry.zoom(
                    window: start,
                    magnification: value.magnification,
                    aroundViewPoint: value.startLocation,
                    size: size
                )
            }
            .onEnded { _ in zoomStartWindow = nil }
    }

    private func zoomBy(_ factor: Double) {
        state.graphWindow = CalculatorGraphGeometry.zoom(
            window: state.graphWindow,
            magnification: factor,
            aroundViewPoint: CGPoint(x: 0.5, y: 0.5),
            size: CGSize(width: 1, height: 1)
        )
    }
}

// MARK: - TBLSET screen

private struct CalculatorTblSetScreen: View {
    @Bindable var state: CalculatorState

    var body: some View {
        VStack(spacing: 0) {
            Text("TABLE SETUP")
                .font(.system(size: 19, weight: .bold, design: .monospaced))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .frame(height: 30)
                .background(Color.black.opacity(0.08))

            numericRow(label: "TblStart=", fieldIndex: 0,
                       value: state.tableStartX)
            numericRow(label: "ΔTbl=",     fieldIndex: 1,
                       value: state.tableStep)
            toggleRow(label: "Indpnt:",    fieldIndex: 2,
                      mode: state.tableIndpntMode,
                      onTap: { state.tableIndpntMode = $0 })
            toggleRow(label: "Depend:",    fieldIndex: 3,
                      mode: state.tableDependMode,
                      onTap: { state.tableDependMode = $0 })

            Spacer(minLength: 0)
        }
        .background(Color.white)
        .foregroundStyle(.black)
    }

    private func numericRow(label: String, fieldIndex: Int, value: Double) -> some View {
        let isSelected = state.tblSetEditorField == fieldIndex
        let display = isSelected
            ? state.tblSetEditorText + "_"
            : CalculatorResultFormatter.string(for: value)
        return HStack(spacing: 0) {
            Text(label)
                .frame(width: 90, alignment: .leading)
            Text(display)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
        }
        .font(.system(size: 19, weight: isSelected ? .bold : .regular, design: .monospaced))
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(isSelected ? Color.black.opacity(0.10) : Color.white)
    }

    private func toggleRow(
        label: String,
        fieldIndex: Int,
        mode: TableControlMode,
        onTap: @escaping (TableControlMode) -> Void
    ) -> some View {
        let isSelected = state.tblSetEditorField == fieldIndex
        return HStack(spacing: 10) {
            Text(label)
                .frame(width: 90, alignment: .leading)
            option("Auto", active: mode == .auto) { onTap(.auto) }
            option("Ask",  active: mode == .ask)  { onTap(.ask)  }
            Spacer(minLength: 0)
        }
        .font(.system(size: 19, weight: isSelected ? .bold : .regular, design: .monospaced))
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(isSelected ? Color.black.opacity(0.06) : Color.white)
    }

    private func option(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Text(title)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(active ? Color.black : Color.clear, in: RoundedRectangle(cornerRadius: 3))
            .foregroundStyle(active ? Color.white : Color.black)
            .onTapGesture(perform: action)
    }
}

// MARK: - Y-VARS menu screen

private struct CalculatorYVarsMenuScreen: View {
    @Bindable var state: CalculatorState

    var body: some View {
        VStack(spacing: 0) {
            Text("Y-VARS  Function")
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(Color.black.opacity(0.08))

            ForEach(Array(state.graphEquations.prefix(9).enumerated()), id: \.offset) { index, eq in
                let isSelected = state.yVarsMenuSelection == index
                HStack(spacing: 6) {
                    Text("\(index + 1):")
                        .frame(width: 22, alignment: .trailing)
                    Text("Y\(index + 1)")
                        .frame(width: 28, alignment: .leading)
                    Text(eq.expression.isEmpty ? "(empty)" : eq.expression)
                        .foregroundStyle(eq.expression.isEmpty ? Color.black.opacity(0.4) : Color.black)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 19, weight: isSelected ? .bold : .regular, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(.black)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(isSelected ? Color.black.opacity(0.1) : Color.white)
            }

            Spacer(minLength: 0)
        }
        .background(Color.white)
    }
}

// MARK: - 1-Var Stats screen

private struct CalculatorOneVarStatsScreen: View {
    @Bindable var state: CalculatorState

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                header("1-Var Stats")
                if let r = state.oneVarStatsResult {
                    resultRow("x̄", value: r.mean)
                    resultRow("Σx", value: r.sumX)
                    resultRow("Σx²", value: r.sumXSq)
                    resultRow("Sx", value: r.sampleStdDev)
                    resultRow("σx", value: r.popStdDev)
                    intRow("n", value: r.n)
                    resultRow("minX", value: r.minX)
                    resultRow("Q1", value: r.q1)
                    resultRow("Med", value: r.median)
                    resultRow("Q3", value: r.q3)
                    resultRow("maxX", value: r.maxX)
                } else {
                    Text("ERR:DATA")
                        .font(.system(size: 19, weight: .bold, design: .monospaced))
                        .foregroundStyle(.black)
                        .padding(8)
                }
                Spacer(minLength: 0)
            }
        }
        .background(Color.white)
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 19, weight: .bold, design: .monospaced))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(Color.black.opacity(0.08))
    }

    private func resultRow(_ name: String, value: Double) -> some View {
        HStack {
            Text("\(name)=")
                .frame(width: 42, alignment: .trailing)
            Text(CalculatorResultFormatter.string(for: value))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 18, weight: .regular, design: .monospaced))
        .foregroundStyle(.black)
        .padding(.horizontal, 8)
        .frame(height: 23)
    }

    private func intRow(_ name: String, value: Int) -> some View {
        HStack {
            Text("\(name)=")
                .frame(width: 42, alignment: .trailing)
            Text("\(value)")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 18, weight: .regular, design: .monospaced))
        .foregroundStyle(.black)
        .padding(.horizontal, 8)
        .frame(height: 23)
    }
}

// MARK: - 2-Var Stats screen

private struct CalculatorTwoVarStatsScreen: View {
    @Bindable var state: CalculatorState

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                header("2-Var Stats")
                if let r = state.twoVarStatsResult {
                    resultRow("x̄", value: r.meanX)
                    resultRow("Σx", value: r.sumX)
                    resultRow("Σx²", value: r.sumXSq)
                    resultRow("Sx", value: r.sampleStdDevX)
                    resultRow("σx", value: r.popStdDevX)
                    resultRow("ȳ", value: r.meanY)
                    resultRow("Σy", value: r.sumY)
                    resultRow("Σy²", value: r.sumYSq)
                    resultRow("Sy", value: r.sampleStdDevY)
                    resultRow("σy", value: r.popStdDevY)
                    resultRow("Σxy", value: r.sumXY)
                    intRow("n", value: r.n)
                    if let rVal = r.r { resultRow("r", value: rVal) }
                    if let r2 = r.rSquared { resultRow("R²", value: r2) }
                } else {
                    Text("ERR:DATA")
                        .font(.system(size: 19, weight: .bold, design: .monospaced))
                        .foregroundStyle(.black)
                        .padding(8)
                }
                Spacer(minLength: 0)
            }
        }
        .background(Color.white)
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 19, weight: .bold, design: .monospaced))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(Color.black.opacity(0.08))
    }

    private func resultRow(_ name: String, value: Double) -> some View {
        HStack {
            Text("\(name)=")
                .frame(width: 42, alignment: .trailing)
            Text(CalculatorResultFormatter.string(for: value))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 18, weight: .regular, design: .monospaced))
        .foregroundStyle(.black)
        .padding(.horizontal, 8)
        .frame(height: 23)
    }

    private func intRow(_ name: String, value: Int) -> some View {
        HStack {
            Text("\(name)=")
                .frame(width: 42, alignment: .trailing)
            Text("\(value)")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 18, weight: .regular, design: .monospaced))
        .foregroundStyle(.black)
        .padding(.horizontal, 8)
        .frame(height: 23)
    }
}

// MARK: - WINDOW editor screen

private struct CalculatorWindowEditorScreen: View {
    @Bindable var state: CalculatorState

    private let fieldNames = ["Xmin", "Xmax", "Xscl", "Ymin", "Ymax", "Yscl"]

    var body: some View {
        VStack(spacing: 0) {
            Text("WINDOW")
                .font(.system(size: 19, weight: .bold, design: .monospaced))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .frame(height: 30)
                .background(Color.black.opacity(0.08))

            ForEach(0..<6, id: \.self) { index in
                fieldRow(index: index)
            }
            Spacer(minLength: 0)
        }
        .background(Color.white)
        .onAppear { loadCurrentField() }
    }

    private func fieldRow(index: Int) -> some View {
        let isSelected = state.windowEditorField == index
        let displayValue: String
        if isSelected {
            displayValue = state.windowEditorText + (isSelected ? "_" : "")
        } else {
            displayValue = CalculatorResultFormatter.string(for: windowValue(at: index))
        }
        return HStack(spacing: 4) {
            Text(fieldNames[index] + "=")
                .frame(width: 50, alignment: .leading)
            Text(displayValue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
        }
        .font(.system(size: 19, weight: isSelected ? .bold : .regular, design: .monospaced))
        .foregroundStyle(.black)
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(isSelected ? Color.black.opacity(0.1) : Color.white)
    }

    private func windowValue(at index: Int) -> Double {
        switch index {
        case 0: return state.graphWindow.xMin
        case 1: return state.graphWindow.xMax
        case 2: return state.graphWindow.xScl
        case 3: return state.graphWindow.yMin
        case 4: return state.graphWindow.yMax
        case 5: return state.graphWindow.yScl
        default: return 0
        }
    }

    private func loadCurrentField() {
        if state.windowEditorText.isEmpty {
            state.windowEditorText = CalculatorResultFormatter.string(for: windowValue(at: state.windowEditorField))
        }
    }
}

// MARK: - TABLE screen

private struct CalculatorTableScreen: View {
    @Bindable var state: CalculatorState
    private let engine = CalculatorEngine()
    private let rowCount = 9

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            ForEach(0..<rowCount, id: \.self) { rowIndex in
                tableRow(rowIndex: rowIndex)
            }
            Spacer(minLength: 0)
        }
        .background(Color.white)
        .font(.system(size: 17, design: .monospaced))
        .foregroundStyle(.black)
    }

    private var activeEquations: [GraphEquation] {
        state.graphEquations.filter { $0.isEnabled && !$0.expression.isEmpty }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("X")
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background(Color.black.opacity(0.12))
                .overlay(Rectangle().strokeBorder(.black.opacity(0.3), lineWidth: 0.5))
            ForEach(Array(activeEquations.prefix(3).enumerated()), id: \.offset) { i, _ in
                Text("Y\(i + 1)")
                    .frame(maxWidth: .infinity)
                    .frame(height: 26)
                    .background(Color.black.opacity(0.08))
                    .overlay(Rectangle().strokeBorder(.black.opacity(0.3), lineWidth: 0.5))
            }
            if activeEquations.isEmpty {
                Text("Y1")
                    .frame(maxWidth: .infinity)
                    .frame(height: 26)
                    .background(Color.black.opacity(0.08))
                    .overlay(Rectangle().strokeBorder(.black.opacity(0.3), lineWidth: 0.5))
            }
        }
        .font(.system(size: 17, weight: .bold, design: .monospaced))
    }

    private func tableRow(rowIndex: Int) -> some View {
        let x = state.tableStartX + Double(rowIndex) * state.tableStep
        let equations = activeEquations.prefix(3)
        return HStack(spacing: 0) {
            Text(CalculatorResultFormatter.string(for: x))
                .frame(maxWidth: .infinity)
                .frame(height: 22)
                .overlay(Rectangle().strokeBorder(.black.opacity(0.15), lineWidth: 0.5))
            ForEach(Array(equations.enumerated()), id: \.offset) { _, eq in
                let y = evalY(expression: eq.expression, x: x)
                Text(y)
                    .frame(maxWidth: .infinity)
                    .frame(height: 22)
                    .overlay(Rectangle().strokeBorder(.black.opacity(0.15), lineWidth: 0.5))
            }
            if equations.isEmpty {
                Text("---")
                    .frame(maxWidth: .infinity)
                    .frame(height: 22)
                    .overlay(Rectangle().strokeBorder(.black.opacity(0.15), lineWidth: 0.5))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.65)
    }

    private func evalY(expression: String, x: Double) -> String {
        guard !expression.isEmpty else { return "---" }
        var variables: [String: Double] = state.lastAnswer.map { ["ans": $0] } ?? [:]
        for (k, v) in state.storedVariables { variables[k] = v }
        variables["x"] = x
        guard let value = try? engine.evaluate(expression, angleMode: state.angleMode, variables: variables),
              value.isFinite else { return "ERROR" }
        return CalculatorResultFormatter.string(for: value)
    }
}

// MARK: - Resize grip

private struct ResizeGrip: View {
    var color: Color

    var body: some View {
        Canvas { context, size in
            for fraction in [0.45, 0.68, 0.9] as [CGFloat] {
                var path = Path()
                path.move(to: CGPoint(x: size.width * fraction, y: size.height))
                path.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                context.stroke(
                    path,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
            }
        }
    }
}

// MARK: - Layout math (pure, testable)

public enum CalculatorPaletteLayout {
    public static let minSize = CGSize(width: 300, height: 520)
    public static let maxSize = CGSize(width: 720, height: 1040)
    public static let minScreenSize = CGSize(width: 220, height: 165)
    public static let maxScreenSize = CGSize(width: 900, height: 675)

    public static func clampSize(_ size: CGSize, in containerSize: CGSize) -> CGSize {
        let maxW = max(minSize.width, min(maxSize.width, containerSize.width))
        let maxH = max(minSize.height, min(maxSize.height, containerSize.height))
        return CGSize(
            width: min(max(size.width, minSize.width), maxW),
            height: min(max(size.height, minSize.height), maxH)
        )
    }

    public static func clampScreenSize(_ size: CGSize, in containerSize: CGSize) -> CGSize {
        let proposedWidth = size.width.isFinite ? size.width : minScreenSize.width
        let maxW = max(minScreenSize.width, min(maxScreenSize.width, containerSize.width))
        let width = min(max(proposedWidth, minScreenSize.width), maxW)
        let height = width * 0.75
        return CGSize(width: width, height: height)
    }

    public static func clamp(center: CGPoint, paletteSize: CGSize, in containerSize: CGSize) -> CGPoint {
        CGPoint(
            x: clampAxis(center.x, palette: paletteSize.width, container: containerSize.width),
            y: clampAxis(center.y, palette: paletteSize.height, container: containerSize.height)
        )
    }

    private static func clampAxis(_ value: CGFloat, palette: CGFloat, container: CGFloat) -> CGFloat {
        let half = palette / 2
        guard container >= palette else { return container / 2 }
        return min(max(value, half), container - half)
    }
}

// MARK: - MathPrint token model

private indirect enum MPToken {
    case text(String)
    case superscript(exponent: [MPToken])
    case cubeRoot(radicand: [MPToken])
    case nthRoot(index: [MPToken], radicand: [MPToken])
    case logBase(base: [MPToken], arg: [MPToken])
    case fraction(num: [MPToken], den: [MPToken])
    case cursor
}

// Parse a prettified expression string into a MathPrint token tree.
// Pass addCursor:true for the live input line to embed a .cursor token at
// the current insertion point (always the end of the string).
private func parseMathPrint(_ expr: String, addCursor: Bool = false) -> [MPToken] {
    var tokens: [MPToken] = []
    var pos = expr.startIndex
    var textStart = expr.startIndex
    var cursorConsumed = false

    func flush(to end: String.Index) {
        guard textStart < end else { return }
        let t = String(expr[textStart..<end])
        if !t.isEmpty { tokens.append(.text(t)) }
        textStart = end
    }

    while pos < expr.endIndex {
        let rest = String(expr[pos...]).lowercased()
        if rest.hasPrefix("cbrt(") {
            flush(to: pos)
            let innerStart = expr.index(pos, offsetBy: 5)
            let (inner, end, complete) = mpExtract(expr, from: innerStart)
            let childCursor = !complete && addCursor
            if childCursor { cursorConsumed = true }
            tokens.append(.cubeRoot(radicand: parseMathPrint(inner, addCursor: childCursor)))
            pos = end; textStart = pos
        } else if rest.hasPrefix("root(") {
            flush(to: pos)
            let innerStart = expr.index(pos, offsetBy: 5)
            let (inner, end, complete) = mpExtract(expr, from: innerStart)
            let childCursor = !complete && addCursor
            if childCursor { cursorConsumed = true }
            let (idxPart, valPart, hasComma) = mpSplitComma(inner)
            let indexTokens: [MPToken]
            let radicandTokens: [MPToken]
            if childCursor {
                if hasComma {
                    indexTokens = parseMathPrint(idxPart)
                    radicandTokens = parseMathPrint(valPart, addCursor: true)
                } else {
                    indexTokens = parseMathPrint(idxPart, addCursor: true)
                    radicandTokens = []
                }
            } else {
                indexTokens = parseMathPrint(idxPart)
                radicandTokens = parseMathPrint(valPart)
            }
            tokens.append(.nthRoot(index: indexTokens, radicand: radicandTokens))
            pos = end; textStart = pos
        } else if rest.hasPrefix("logbase(") {
            flush(to: pos)
            let innerStart = expr.index(pos, offsetBy: 8)
            let (inner, end, complete) = mpExtract(expr, from: innerStart)
            let childCursor = !complete && addCursor
            if childCursor { cursorConsumed = true }
            let (basePart, argPart, hasComma) = mpSplitComma(inner)
            let baseTokens: [MPToken]
            let argTokens: [MPToken]
            if childCursor {
                if hasComma {
                    baseTokens = parseMathPrint(basePart)
                    argTokens = parseMathPrint(argPart, addCursor: true)
                } else {
                    baseTokens = parseMathPrint(basePart, addCursor: true)
                    argTokens = []
                }
            } else {
                baseTokens = parseMathPrint(basePart)
                argTokens = parseMathPrint(argPart)
            }
            tokens.append(.logBase(base: baseTokens, arg: argTokens))
            pos = end; textStart = pos
        } else if rest.hasPrefix("^") {
            flush(to: pos)
            let expStart = expr.index(after: pos)
            let (expStr, expEnd) = mpExtractExponent(expr, from: expStart)
            let childCursor = expEnd >= expr.endIndex && addCursor && !cursorConsumed
            if childCursor { cursorConsumed = true }
            tokens.append(.superscript(exponent: parseMathPrint(expStr, addCursor: childCursor)))
            pos = expEnd; textStart = pos
        } else {
            pos = expr.index(after: pos)
        }
    }

    flush(to: expr.endIndex)
    if addCursor && !cursorConsumed { tokens.append(.cursor) }
    return tokens
}

// Extract the content between the current position and the matching ')'.
// Returns (content, indexAfterClose, didFindClose). When no matching ')' is
// found the caller is inside an incomplete construct — cursor is inside.
private func mpExtract(_ s: String, from start: String.Index) -> (String, String.Index, Bool) {
    var depth = 0
    var i = start
    while i < s.endIndex {
        let c = s[i]
        if c == "(" { depth += 1 }
        else if c == ")" {
            if depth == 0 { return (String(s[start..<i]), s.index(after: i), true) }
            depth -= 1
        }
        i = s.index(after: i)
    }
    return (String(s[start...]), s.endIndex, false)
}

// Split at the first top-level comma (not inside parentheses).
private func mpSplitComma(_ s: String) -> (String, String, Bool) {
    var depth = 0
    var i = s.startIndex
    while i < s.endIndex {
        let c = s[i]
        if c == "(" { depth += 1 }
        else if c == ")" { depth -= 1 }
        else if c == "," && depth == 0 {
            let after = s.index(after: i)
            return (String(s[..<i]), after <= s.endIndex ? String(s[after...]) : "", true)
        }
        i = s.index(after: i)
    }
    return (s, "", false)
}

// Extract the exponent after a ^ character.
// If it starts with (, takes the full parenthesized group.
// Otherwise takes an optional leading minus and then alphanumeric/decimal chars.
private func mpExtractExponent(_ s: String, from start: String.Index) -> (String, String.Index) {
    guard start < s.endIndex else { return ("", start) }
    var i = start
    if s[i] == "(" {
        var depth = 0
        while i < s.endIndex {
            if s[i] == "(" { depth += 1 }
            else if s[i] == ")" {
                depth -= 1
                if depth == 0 {
                    i = s.index(after: i)
                    return (String(s[start..<i]), i)
                }
            }
            i = s.index(after: i)
        }
        return (String(s[start...]), s.endIndex)
    }
    if i < s.endIndex && s[i] == "-" { i = s.index(after: i) }
    while i < s.endIndex {
        let c = s[i]
        if c.isLetter || c.isNumber || c == "." { i = s.index(after: i) } else { break }
    }
    return (String(s[start..<i]), i)
}

// MARK: - MathPrint views

private struct MPLineView: View {
    let tokens: [MPToken]
    var em: CGFloat = 20
    var cursorVisible: Bool = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                tokenView(token)
            }
        }
    }

    @ViewBuilder
    private func tokenView(_ token: MPToken) -> some View {
        switch token {
        case .text(let s):
            Text(s)
                .font(.system(size: em, design: .monospaced))
                .foregroundStyle(Color.black)
        case .superscript(let exp):
            // Raised by adding bottom padding so the exponent sits above the text baseline
            MPLineView(tokens: exp, em: em * 0.6, cursorVisible: cursorVisible)
                .padding(.bottom, em * 0.5)
        case .cursor:
            Rectangle()
                .fill(Color(white: 0.28))
                .frame(width: max(6, em * 0.55), height: em)
                .opacity(cursorVisible ? 1 : 0)
        case .cubeRoot(let radicand):
            MPRadicalView(indexTokens: [.text("3")], radicand: radicand, em: em, cursorVisible: cursorVisible)
        case .nthRoot(let index, let radicand):
            MPRadicalView(indexTokens: index, radicand: radicand, em: em, cursorVisible: cursorVisible)
        case .logBase(let base, let arg):
            MPLogBaseView(base: base, arg: arg, em: em, cursorVisible: cursorVisible)
        case .fraction(let num, let den):
            MPFractionView(num: num, den: den, em: em, cursorVisible: cursorVisible)
        }
    }
}

// Draws the radical symbol using a Canvas overlay over the radicand.
private struct MPRadicalView: View {
    let indexTokens: [MPToken]
    let radicand: [MPToken]
    var em: CGFloat = 20
    var cursorVisible: Bool = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            // Small index floats to upper-left of the tick
            if !indexTokens.isEmpty {
                MPLineView(tokens: indexTokens, em: em * 0.55, cursorVisible: cursorVisible)
                    .padding(.bottom, em * 0.38)
            }
            // Radicand padded to make room for the radical symbol drawn via overlay
            Group {
                if radicand.isEmpty {
                    MPSlotPlaceholder(em: em)
                } else {
                    MPLineView(tokens: radicand, em: em, cursorVisible: cursorVisible)
                }
            }
            .padding(.top, 4)
            .padding(.leading, em * 0.6)
            .padding(.trailing, 3)
            .overlay(alignment: .topLeading) {
                // Canvas renders the tick + overbar that frames the radicand
                Canvas { ctx, size in
                    let tickW = em * 0.6
                    let barY: CGFloat = 2
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: size.height * 0.58))
                    p.addLine(to: CGPoint(x: tickW * 0.32, y: size.height * 0.78))
                    p.addLine(to: CGPoint(x: tickW, y: barY))
                    p.addLine(to: CGPoint(x: size.width, y: barY))
                    ctx.stroke(p, with: .color(.black),
                               style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                }
            }
        }
    }
}

// Renders log with subscript base and parenthesized argument.
private struct MPLogBaseView: View {
    let base: [MPToken]
    let arg: [MPToken]
    var em: CGFloat = 20
    var cursorVisible: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("log")
                .font(.system(size: em, design: .monospaced))
                .foregroundStyle(Color.black)

            // Subscript base — shifted down from the baseline
            Group {
                if base.isEmpty {
                    MPSlotPlaceholder(em: em * 0.62)
                } else {
                    MPLineView(tokens: base, em: em * 0.62, cursorVisible: cursorVisible)
                }
            }
            .offset(y: em * 0.28)

            Text("(")
                .font(.system(size: em, design: .monospaced))
                .foregroundStyle(Color.black)

            if arg.isEmpty {
                MPSlotPlaceholder(em: em)
            } else {
                MPLineView(tokens: arg, em: em, cursorVisible: cursorVisible)
            }

            Text(")")
                .font(.system(size: em, design: .monospaced))
                .foregroundStyle(Color.black)
        }
    }
}

// Renders a stacked fraction with a horizontal bar.
private struct MPFractionView: View {
    let num: [MPToken]
    let den: [MPToken]
    var em: CGFloat = 20
    var cursorVisible: Bool = false

    var body: some View {
        VStack(alignment: .center, spacing: 1) {
            MPLineView(tokens: num, em: em * 0.82, cursorVisible: cursorVisible)
                .frame(maxWidth: .infinity, alignment: .center)
            Rectangle()
                .fill(Color.black)
                .frame(height: 1.5)
            MPLineView(tokens: den, em: em * 0.82, cursorVisible: cursorVisible)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
    }
}

// Dotted placeholder box for an unfilled MathPrint slot.
private struct MPSlotPlaceholder: View {
    var em: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            .foregroundStyle(Color.black)
            .frame(width: max(8, em * 0.65), height: max(6, em * 0.82))
    }
}

#if DEBUG
#Preview("Calculator palette") {
    ZStack {
        Color(white: 0.95)
        CalculatorView(
            state: {
                let state = CalculatorState(store: UserDefaults(suiteName: "preview.palette")!)
                state.mode = .compute
                state.computeExpression = "2sin(30) + sqrt(9)"
                state.graphEquations = [GraphEquation(expression: "sin(x)", colorIndex: 0)]
                return state
            }()
        )
    }
    .frame(width: 900, height: 900)
}

#Preview("Detached calculator screen") {
    ZStack {
        Color(white: 0.95)
        CalculatorView(
            state: {
                let state = CalculatorState(store: UserDefaults(suiteName: "preview.palette.detached")!)
                state.mode = .graph
                state.isScreenDetached = true
                state.screenSize = CGSize(width: 292, height: 219)
                state.screenPosition = nil
                state.graphEquations = [GraphEquation(expression: "sin(x)", colorIndex: 0)]
                return state
            }()
        )
    }
    .frame(width: 900, height: 900)
}

#Preview("Y= equation editor") {
    ZStack {
        Color(white: 0.95)
        CalculatorView(
            state: {
                let state = CalculatorState(store: UserDefaults(suiteName: "preview.palette.yeditor")!)
                state.mode = .graph
                state.graphScreenMode = .equationEditor
                state.graphEquations = [
                    GraphEquation(expression: "sin(x)", colorIndex: 0),
                    GraphEquation(expression: "0.5x+2", colorIndex: 1)
                ]
                state.selectedGraphEquationID = state.graphEquations.first?.id
                return state
            }()
        )
    }
    .frame(width: 900, height: 900)
}

#Preview("Zoom menu") {
    ZStack {
        Color(white: 0.95)
        CalculatorView(
            state: {
                let state = CalculatorState(store: UserDefaults(suiteName: "preview.palette.zoom")!)
                state.mode = .graph
                state.graphScreenMode = .zoomMenu
                state.zoomMenuOffset = 0
                state.graphEquations = [GraphEquation(expression: "sin(x)", colorIndex: 0)]
                return state
            }()
        )
    }
    .frame(width: 900, height: 900)
}
#endif
