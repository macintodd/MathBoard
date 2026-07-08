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

    public init(state: CalculatorState = .shared) {
        self.state = state
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
                keyAction: handleKey,
                graphAction: showGraphPlot,
                equationAction: editGraphEquation,
                zoomAction: showZoomMenu,
                mathAction: showMathMenu,
                statAction: showStatMenu,
                navigationAction: handleNavigation
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
                // Placeholder: later this will place a snapshot of the current
                // graph on the canvas for markup.
            } label: {
                Image(systemName: "camera.viewfinder")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(CalculatorTheme.label)
                    .frame(width: 28, height: 28)
            }
            .help("Add graph snapshot to canvas")

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
            close: closeDetachedScreen
        )
        .frame(width: windowSize.width, height: windowSize.height)
        .overlay(alignment: .bottomTrailing) {
            screenResizeHandle(currentCenter: center, in: containerSize)
        }
        .position(center)
        .gesture(screenDragGesture(in: containerSize, currentCenter: center, windowSize: windowSize))
    }

    // MARK: - Actions

    private func handleKey(_ action: CalculatorKeyAction) {
        switch action {
        case .toggleSecond:
            state.isSecondActive.toggle()
            state.isAlphaActive = false
            return
        case .toggleAngleMode:
            state.angleMode = state.angleMode == .degrees ? .radians : .degrees
            if activeScreen == .calc, !state.computeExpression.isEmpty { evaluateCompute() }
        case .evaluate:
            if activeScreen == .calc {
                evaluateCompute()
            } else {
                showGraphPlot()
            }
        case .insert, .deleteBackward, .clear:
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
                state.computeExpression = CalculatorExpressionReducer.reduce(
                    expression: state.computeExpression,
                    action: action
                )
                if action == .clear {
                    state.computeResult = ""
                    state.computeIsError = false
                }
            case .graph:
                state.applyGraphKey(action)
            }
        }
    }

    private func evaluateCompute() {
        let trimmed = state.computeExpression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state.computeResult = ""
            state.computeIsError = false
            return
        }

        do {
            let variables: [String: Double] = state.lastAnswer.map { ["ans": $0] } ?? [:]
            let value = try engine.evaluate(trimmed, angleMode: state.angleMode, variables: variables)
            state.computeResult = CalculatorResultFormatter.string(for: value)
            state.computeIsError = false
            state.lastAnswer = value
        } catch {
            state.computeResult = (error as? LocalizedError)?.errorDescription ?? "Error"
            state.computeIsError = true
        }
    }

    private func editGraphEquation() {
        activeScreen = .graph
        state.graphScreenMode = .equationEditor
        ensureGraphEquation(at: 0)
    }

    private func showGraphPlot() {
        activeScreen = .graph
        state.graphScreenMode = .plot
        if state.selectedGraphEquationID == nil {
            state.selectedGraphEquationID = state.graphEquations.first?.id
        }
    }

    private func showZoomMenu() {
        activeScreen = .graph
        state.graphScreenMode = .zoomMenu
        state.zoomMenuOffset = 0
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

        if activeScreen == .graph, state.graphScreenMode == .zoomMenu {
            switch direction {
            case .down:
                state.zoomMenuOffset = min(1, state.zoomMenuOffset + 1)
            case .up:
                state.zoomMenuOffset = max(0, state.zoomMenuOffset - 1)
            case .left, .right:
                break
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
        case .home, .regressionResult:
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
        case .regressionResult:
            if action == .clear {
                state.calculatorScreenMode = .home
            }
        case .home:
            break
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
            evaluateCompute()
            if let value = state.lastAnswer,
               let fraction = CalculatorStatistics.fractionString(for: value) {
                state.computeResult = fraction
                state.computeIsError = false
            }
        case .decimal:
            evaluateCompute()
        case .none, .statEditor, .regression:
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
                CalculatorMenuItem("1", ">Frac", .fraction, isEnabled: true),
                CalculatorMenuItem("2", ">Dec", .decimal, isEnabled: true),
                CalculatorMenuItem("3", "^3", .insert("^3"), isEnabled: true),
                CalculatorMenuItem("4", "³√(", .insert("cbrt("), isEnabled: true),
                CalculatorMenuItem("5", "x√(", .insert("root("), isEnabled: true),
                CalculatorMenuItem("A", "logBASE(", .insert("log("), isEnabled: true)
            ]
        case .num:
            return [
                CalculatorMenuItem("1", "abs(", .insert("abs("), isEnabled: true),
                CalculatorMenuItem("2", "round(", .insert("round(")),
                CalculatorMenuItem("3", "iPart("),
                CalculatorMenuItem("4", "fPart("),
                CalculatorMenuItem("5", "int("),
                CalculatorMenuItem("6", "min(", .insert("min(")),
                CalculatorMenuItem("7", "max(", .insert("max(")),
                CalculatorMenuItem("8", "lcm(", .insert("lcm("), isEnabled: true),
                CalculatorMenuItem("9", "gcd(", .insert("gcd("), isEnabled: true)
            ]
        case .cmplx:
            return [
                CalculatorMenuItem("1", "conj("),
                CalculatorMenuItem("2", "real("),
                CalculatorMenuItem("3", "imag("),
                CalculatorMenuItem("4", "angle("),
                CalculatorMenuItem("5", "abs(")
            ]
        case .prob:
            return [
                CalculatorMenuItem("1", "rand"),
                CalculatorMenuItem("2", "nPr"),
                CalculatorMenuItem("3", "nCr"),
                CalculatorMenuItem("4", "!"),
                CalculatorMenuItem("5", "randInt(")
            ]
        case .frac:
            return [
                CalculatorMenuItem("1", "n/d"),
                CalculatorMenuItem("2", "Un/d"),
                CalculatorMenuItem("3", ">F<>D"),
                CalculatorMenuItem("4", ">n/d<>Un/d")
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
                CalculatorMenuItem("1", "1-Var Stats"),
                CalculatorMenuItem("2", "2-Var Stats"),
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
}

// MARK: - Screen window

private struct CalculatorScreenWindow: View {
    @Bindable var state: CalculatorState
    let mode: CalculatorScreenMode
    let isDetached: Bool
    let selectCalc: () -> Void
    var dock: (() -> Void)? = nil
    var close: (() -> Void)? = nil

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
            if mode == .graph {
                Button {
                    // Placeholder: later this will place a snapshot of the
                    // current graph on the canvas for markup.
                } label: {
                    Image(systemName: "camera.viewfinder")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
                .help("Add graph snapshot to canvas")
            }
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
            }
        case .graph:
            switch state.graphScreenMode {
            case .equationEditor:
                CalculatorEquationEditorScreen(state: state)
            case .zoomMenu:
                CalculatorZoomMenuScreen(state: state)
            case .plot:
                CalculatorGraphCanvasOnlyView(state: state)
            }
        }
    }

    private var mathMenuItemsForDisplay: [CalculatorMenuItem] {
        switch state.mathMenuTab {
        case .math:
            return [
                CalculatorMenuItem("1", ">Frac", .fraction, isEnabled: true),
                CalculatorMenuItem("2", ">Dec", .decimal, isEnabled: true),
                CalculatorMenuItem("3", "^3", .insert("^3"), isEnabled: true),
                CalculatorMenuItem("4", "³√(", .insert("cbrt("), isEnabled: true),
                CalculatorMenuItem("5", "x√(", .insert("root("), isEnabled: true),
                CalculatorMenuItem("A", "logBASE(", .insert("log("), isEnabled: true)
            ]
        case .num:
            return [
                CalculatorMenuItem("1", "abs(", .insert("abs("), isEnabled: true),
                CalculatorMenuItem("2", "round(", .insert("round(")),
                CalculatorMenuItem("3", "iPart("),
                CalculatorMenuItem("4", "fPart("),
                CalculatorMenuItem("5", "int("),
                CalculatorMenuItem("6", "min(", .insert("min(")),
                CalculatorMenuItem("7", "max(", .insert("max(")),
                CalculatorMenuItem("8", "lcm(", .insert("lcm("), isEnabled: true),
                CalculatorMenuItem("9", "gcd(", .insert("gcd("), isEnabled: true)
            ]
        case .cmplx:
            return [
                CalculatorMenuItem("1", "conj("),
                CalculatorMenuItem("2", "real("),
                CalculatorMenuItem("3", "imag("),
                CalculatorMenuItem("4", "angle("),
                CalculatorMenuItem("5", "abs(")
            ]
        case .prob:
            return [
                CalculatorMenuItem("1", "rand"),
                CalculatorMenuItem("2", "nPr"),
                CalculatorMenuItem("3", "nCr"),
                CalculatorMenuItem("4", "!"),
                CalculatorMenuItem("5", "randInt(")
            ]
        case .frac:
            return [
                CalculatorMenuItem("1", "n/d"),
                CalculatorMenuItem("2", "Un/d"),
                CalculatorMenuItem("3", ">F<>D"),
                CalculatorMenuItem("4", ">n/d<>Un/d")
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
                CalculatorMenuItem("1", "1-Var Stats"),
                CalculatorMenuItem("2", "2-Var Stats"),
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

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 8) {
                Text("HOME")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.black.opacity(0.72))
                Spacer()
                Text(state.angleMode.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.black.opacity(0.58))
            }

            TextField("Enter expression", text: $state.computeExpression, axis: .vertical)
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(.black)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.plain)
                .lineLimit(1...2)
                .minimumScaleFactor(0.6)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.asciiCapable)
                #endif
                .onTapGesture(perform: selectCalc)

            Spacer(minLength: 0)

            Text(state.computeResult.isEmpty ? " " : state.computeResult)
                .font(.system(.title2, design: .monospaced).weight(.semibold))
                .foregroundStyle(state.computeIsError ? Color.red : Color.black)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .contentShape(Rectangle())
        .onTapGesture(perform: selectCalc)
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
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
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
                    .font(.system(size: 17, weight: index == selection ? .bold : .regular, design: .monospaced))
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
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
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
                .font(.system(size: 12, weight: .bold, design: .monospaced))
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
            .font(.system(size: 18, weight: .bold, design: .monospaced))
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
                .font(.system(size: 16, weight: isSelected ? .bold : .regular, design: .monospaced))
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
                .font(.system(size: 18, weight: .bold, design: .monospaced))
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
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
            } else {
                Text("ERR:DATA")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
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
        .font(.system(size: 16, weight: .regular, design: .monospaced))
        .foregroundStyle(.black)
        .padding(.horizontal, 8)
        .frame(height: 24)
    }
}

private struct CalculatorEquationEditorScreen: View {
    @Bindable var state: CalculatorState

    private let rowCount = 8

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            plotHeader
            equationRows
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
        .font(.system(size: 12, weight: .bold, design: .monospaced))
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
        .font(.system(size: 18, weight: .bold, design: .monospaced))
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

        return HStack(spacing: 5) {
            Rectangle()
                .fill(color(for: index))
                .frame(width: 10, height: 18)
            Path { path in
                path.move(to: CGPoint(x: 2, y: 3))
                path.addLine(to: CGPoint(x: 16, y: 17))
            }
            .stroke(.black.opacity(0.62), style: StrokeStyle(lineWidth: 3, lineCap: .square))
            .frame(width: 18, height: 20)

            Text("Y\(index + 1)=")
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .frame(width: 58, alignment: .leading)

            Text(expression)
                .font(.system(size: 21, weight: .regular, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .frame(height: 28)
        .background(isSelected ? Color.black.opacity(0.08) : Color.white)
        .contentShape(Rectangle())
        .onTapGesture {
            ensureEquation(at: index)
        }
    }

    private func ensureEquation(at index: Int) {
        while state.graphEquations.count <= index {
            state.addEquation()
        }
        state.selectedGraphEquationID = state.graphEquations[index].id
    }

    private func color(for index: Int) -> Color {
        let rgb = GraphPalette.rgb(for: index)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
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
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(Color.black)

            Text("MEMORY")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
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
                .font(.system(size: 18, weight: choice.isTaught ? .bold : .regular, design: .monospaced))
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
            .overlay(alignment: .bottomLeading) { equationBadge }
        }
        .background(Color.white)
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
