//
//  CalculatorGraphView.swift
//  MathBoardCore — Calculator module
//
//  Graph-mode body. A Topic dropdown selects a function family that drives
//  the entry keypad and the render mode:
//    • "1 Variable" → number-line view + equation/inequality solver.
//    • Linear / Quadratic / … → the 2D y = f(x) plot (multiple colored
//      curves), with pan (drag) + zoom (magnify).
//  Keypad-only entry (no system keyboard); tap an equation row to select it.
//  DEG/RAD shows only for Trig. A photo button snapshots the graph
//  (pending the MathBoard image-object layer).
//

import SwiftUI

struct CalculatorGraphView: View {
    @Bindable var state: CalculatorState

    var onSnapshot: (@MainActor () -> Void)?
    var showsKeypad = true
    var showsFullKeypadButton = true

    private let engine = CalculatorEngine()

    @State private var zoomStartWindow: GraphWindow?
    @State private var lastPanTranslation: CGSize = .zero
    @State private var showKeypad = true

    /// The compact keypad shows only when it's toggled on AND the full
    /// slide-out keypad isn't taking over. When the full keypad is out, the
    /// graph gets the extra room the compact keypad would have used.
    private var keypadVisible: Bool { showsKeypad && showKeypad && !state.showFullKeypad }

    var body: some View {
        VStack(spacing: 6) {
            if state.graphKeypadFamily.isOneVariable {
                oneVariableBody
            } else {
                plot
                equationList
                actionRow
            }
            topicRow
            if keypadVisible { keypad }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .onAppear {
            if state.selectedGraphEquationID == nil {
                state.selectedGraphEquationID = state.graphEquations.first?.id
            }
        }
    }

    // MARK: - 1 Variable mode

    /// The two equations 1-Variable mode works with: cell 1 always, cell 2
    /// only when a connective (and/or) is chosen.
    private var oneVarEquations: [GraphEquation] {
        var result = [state.graphEquations.first].compactMap { $0 }
        if state.oneVarConnective != .none, state.graphEquations.count >= 2 {
            result.append(state.graphEquations[1])
        }
        return result
    }

    @ViewBuilder
    private var oneVariableBody: some View {
        // One graph window (zoom + pan), showing each active inequality.
        GeometryReader { proxy in
            let size = proxy.size
            CalculatorNumberLineView(
                domain: domain,
                layers: oneVarEquations.map { NumberLineLayer(solution: solution(for: $0), color: color(for: $0)) }
            )
            .background(CalculatorTheme.graphBackground)
            .contentShape(Rectangle())
            .gesture(panGesture(size: size))
            .simultaneousGesture(zoomGesture(size: size))
        }
        .frame(height: keypadVisible ? 110 : 220)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary, lineWidth: 0.5))

        // Cell 1 with connective dropdown.
        equationCell(index: 0, trailing: AnyView(connectiveMenu))

        // Cell 2 appears once a connective is chosen.
        if state.oneVarConnective != .none {
            equationCell(index: 1, trailing: AnyView(solutionMenu))
        }

        // Solution (3rd) graph appears when cell 2's "=" is chosen.
        if state.oneVarConnective != .none && state.oneVarShowSolution {
            VStack(spacing: 2) {
                CalculatorNumberLineView(domain: domain, solution: combinedSolution, color: .primary)
                    .frame(height: 56)
                    .background(CalculatorTheme.graphBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary, lineWidth: 0.5))
                Text(CalculatorSolutionFormatter.describe(combinedSolution, domain: domain))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
        }
    }

    private func equationCell(index: Int, trailing: AnyView) -> some View {
        let equation = index < state.graphEquations.count ? state.graphEquations[index] : nil
        let isSelected = equation?.id == state.selectedGraphEquationID
        let color = equation.map(color(for:)) ?? .secondary
        return HStack(spacing: 8) {
            Circle().fill(color).frame(width: 14, height: 14)
            Text((equation?.expression.isEmpty ?? true) ? "tap, then use the keypad" : equation!.expression)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle((equation?.expression.isEmpty ?? true) ? .secondary : .primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? color.opacity(0.12) : CalculatorTheme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? color : .clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onTapGesture {
            if let id = equation?.id { state.selectedGraphEquationID = id; showKeypad = true }
        }
    }

    /// Cell 1's right-end dropdown: − / and / or.
    private var connectiveMenu: some View {
        Menu {
            ForEach(OneVarConnective.allCases, id: \.self) { option in
                Button {
                    selectConnective(option)
                } label: {
                    if option == state.oneVarConnective {
                        Label(option.displayName, systemImage: "checkmark")
                    } else {
                        Text(option.displayName)
                    }
                }
            }
        } label: {
            menuLabel(state.oneVarConnective.displayName)
        }
    }

    /// Cell 2's right-end dropdown: − / = (= reveals the solution graph).
    private var solutionMenu: some View {
        Menu {
            Button { state.oneVarShowSolution = false } label: {
                if !state.oneVarShowSolution { Label("–", systemImage: "checkmark") } else { Text("–") }
            }
            Button { state.oneVarShowSolution = true } label: {
                if state.oneVarShowSolution { Label("=", systemImage: "checkmark") } else { Text("=") }
            }
        } label: {
            menuLabel(state.oneVarShowSolution ? "=" : "–")
        }
    }

    private func menuLabel(_ text: String) -> some View {
        HStack(spacing: 2) {
            Text(text).fontWeight(.semibold)
            Image(systemName: "chevron.down").font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    private func selectConnective(_ option: OneVarConnective) {
        state.oneVarConnective = option
        if option != .none, state.graphEquations.count < 2 {
            state.addEquation()
        }
        if let mode = option.combineMode { state.graphCombineMode = mode }
    }

    private var plot: some View {
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
            .background(CalculatorTheme.graphBackground)
            .contentShape(Rectangle())
            .gesture(panGesture(size: size))
            .simultaneousGesture(zoomGesture(size: size))
        }
        .frame(minHeight: keypadVisible ? 150 : 280)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary, lineWidth: 0.5))
        .overlay(alignment: .topTrailing) { zoomControls }
    }

    /// Vertical zoom in / out stack floating over the plot's right edge.
    private var zoomControls: some View {
        VStack(spacing: 8) {
            zoomButton("plus.magnifyingglass") { zoomBy(1.4) }
            zoomButton("minus.magnifyingglass") { zoomBy(1 / 1.4) }
        }
        .padding(8)
    }

    private func zoomButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .foregroundStyle(CalculatorTheme.label)
    }

    // MARK: - Equation list

    /// Approximate height of a single equation row (circle/text + vertical
    /// padding) and the inter-row spacing — used to size the entry section so
    /// it grows one row at a time as equations are added.
    private static let equationRowHeight: CGFloat = 34
    private static let equationRowSpacing: CGFloat = 4

    private var equationList: some View {
        // Start at one equation's height and expand per added equation. Only
        // once the list would crowd the plot/keypad does it cap and scroll.
        let maxVisibleRows = keypadVisible ? 3 : 5
        let count = max(state.graphEquations.count, 1)
        let visibleRows = min(count, maxVisibleRows)
        let height = CGFloat(visibleRows) * Self.equationRowHeight
            + CGFloat(visibleRows - 1) * Self.equationRowSpacing
        return ScrollView {
            VStack(spacing: Self.equationRowSpacing) {
                ForEach(state.graphEquations) { equation in
                    equationRow(equation)
                }
            }
        }
        .frame(height: height)
        .scrollDisabled(count <= maxVisibleRows)
        .animation(.easeInOut(duration: 0.2), value: count)
    }

    private func equationRow(_ equation: GraphEquation) -> some View {
        let rgb = GraphPalette.rgb(for: equation.colorIndex)
        let color = Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
        let isSelected = equation.id == state.selectedGraphEquationID
        let prefix = state.graphKeypadFamily.isOneVariable ? "" : "y = "
        let placeholder = state.graphKeypadFamily.isOneVariable ? "tap to enter equation" : "tap to enter f(x)"
        return HStack(spacing: 8) {
            Circle().fill(color).frame(width: 16, height: 16)
            Text(equation.expression.isEmpty ? placeholder : "\(prefix)\(equation.expression)")
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(equation.expression.isEmpty ? .secondary : .primary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button {
                state.removeEquation(id: equation.id)
                if state.selectedGraphEquationID == equation.id {
                    state.selectedGraphEquationID = state.graphEquations.first?.id
                }
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isSelected ? color.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? color : .clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onTapGesture {
            state.selectedGraphEquationID = equation.id
            showKeypad = true
        }
    }

    // MARK: - Topic dropdown (own full-width row so names never truncate)

    private var topicRow: some View {
        Menu {
            ForEach(GraphFunctionFamily.allCases, id: \.self) { family in
                Button {
                    state.graphKeypadFamily = family
                } label: {
                    if family == state.graphKeypadFamily {
                        Label(family.displayName, systemImage: "checkmark")
                    } else {
                        Text(family.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("Topic:").foregroundStyle(.secondary)
                Text(state.graphKeypadFamily.displayName).fontWeight(.semibold)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.caption)
            }
            .lineLimit(1)
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions / controls

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button { state.addEquation(); state.selectedGraphEquationID = state.graphEquations.last?.id } label: {
                Image(systemName: "plus")
            }
            Button { onSnapshot?() } label: { Image(systemName: "camera") }
                .disabled(onSnapshot == nil)
                .help("Place graph on whiteboard")
            if showsKeypad {
                Button { showKeypad.toggle() } label: {
                    Image(systemName: showKeypad ? "keyboard.chevron.compact.down" : "keyboard")
                }
                .disabled(state.showFullKeypad)
            }
            if showsFullKeypadButton {
                Button {
                    withAnimation(.easeInOut(duration: 0.28)) { state.showFullKeypad.toggle() }
                } label: {
                    Image(systemName: state.showFullKeypad ? "square.grid.3x3.fill" : "square.grid.3x3")
                }
                .help("Full slide-out keypad")
            }

            Spacer()

            // Zoom lives on the plot's right edge now; only reset stays here.
            Button { state.graphWindow = .default } label: { Image(systemName: "arrow.counterclockwise") }

            if state.graphKeypadFamily.showsAngleToggle {
                Button {
                    state.angleMode = state.angleMode == .degrees ? .radians : .degrees
                } label: {
                    Text(state.angleMode.displayName).font(.caption.weight(.semibold))
                }
            }
        }
        .font(.callout)
        .buttonStyle(.bordered)
    }

    // MARK: - Family keypad

    private var keypad: some View {
        VStack(spacing: 4) {
            ForEach(Array(GraphKeypadLayout.keys(for: state.graphKeypadFamily).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 4) {
                    ForEach(row) { key in
                        Button { state.applyGraphKey(key.action) } label: {
                            Text(key.label).font(.callout.weight(.medium))
                        }
                        .buttonStyle(CalculatorKeyButtonStyle(fill: CalculatorTheme.keyFill(for: key.style), minHeight: 30))
                    }
                }
            }
        }
    }

    // MARK: - Solving (1 Variable)

    private var domain: ClosedRange<Double> {
        let window = state.graphWindow
        return window.xMin < window.xMax ? window.xMin...window.xMax : -10...10
    }

    private func color(for equation: GraphEquation) -> Color {
        let rgb = GraphPalette.rgb(for: equation.colorIndex)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    private func solution(for equation: GraphEquation) -> SolutionSet {
        guard !equation.expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .none
        }
        return CalculatorEquationSolver(variable: "x")
            .solve(equation.expression, domain: domain, angleMode: state.angleMode)
    }

    /// Combine the first two equations' solution sets per the And/Or toggle.
    private var combinedSolution: SolutionSet {
        guard state.graphEquations.count >= 2 else { return .none }
        let a = SolutionRegion.from(solution(for: state.graphEquations[0]), domain: domain)
        let b = SolutionRegion.from(solution(for: state.graphEquations[1]), domain: domain)
        return SolutionRegion
            .combine(a, b, mode: state.graphCombineMode, domain: domain)
            .asSolutionSet(domain: domain)
    }

    // MARK: - Gestures

    private func panGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let delta = CGSize(
                    width: value.translation.width - lastPanTranslation.width,
                    height: value.translation.height - lastPanTranslation.height
                )
                lastPanTranslation = value.translation
                state.graphWindow = CalculatorGraphGeometry.pan(
                    window: state.graphWindow, byViewTranslation: delta, size: size
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

#if DEBUG
#Preview("1 Variable") {
    CalculatorGraphView(state: {
        let state = CalculatorState(store: UserDefaults(suiteName: "preview.onevar")!)
        state.graphKeypadFamily = .oneVariable
        state.graphEquations = [GraphEquation(expression: "|x-3| = 2", colorIndex: 0)]
        return state
    }())
    .frame(width: 360, height: 620)
    .padding()
}
#endif
