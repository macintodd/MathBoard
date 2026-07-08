//
//  GraphCalculatorView.swift
//  MathBoardCore - GraphCalculator module
//
//  Isolated Desmos-style teaching calculator prototype.
//

import SwiftUI
import Calculator

public struct GraphCalculatorView: View {
    @Bindable private var state: GraphCalculatorState

    @State private var dragStartCenter: CGPoint?
    @State private var detachedDragStartCenter: CGPoint?
    @State private var detachedResizeStart: (size: CGSize, topLeft: CGPoint)?
    @State private var dockedLiveOffset: CGSize = .zero
    @State private var detachedGraphLiveOffset: CGSize = .zero
    @State private var detachedControlLiveOffset: CGSize = .zero
    @State private var detachedResizeLive: (size: CGSize, center: CGPoint)?
    @State private var dragProxy: GraphCalculatorDragProxy?
    @State private var graphPanStart: CGSize = .zero
    @State private var graphMagnifyStartWindow: GraphWindow?
    @State private var functionMenuCategory: FunctionMenuCategory = .basic
    @State private var stylingExpressionIndex: Int?
    @State private var isAlphabetKeypadVisible: Bool = false
    @State private var editingSliderBound: SliderBoundEdit?
    @State private var editingSliderBoundText: String = ""
    @State private var editingSliderBoundReplacesOnInput: Bool = false
    @State private var playingSliders: Set<String> = []
    @State private var sliderPlayDirections: [String: Double] = [:]
    @State private var sliderPlaybackTask: Task<Void, Never>?
    @State private var keypadHiddenEntryExtra: CGFloat = 260
    @State private var entryResizeStartExtra: CGFloat?

    private let engine = CalculatorEngine()
    private let minimumGraphSpan: Double = 0.2
    private let maximumGraphSpan: Double = 240
    private let keypadHeight: CGFloat = 260
    private let baseEntryHeight: CGFloat = 150
    private let baseDetachedEntryHeight: CGFloat = 170
    private let entryHandleHeight: CGFloat = 22

    public init(state: GraphCalculatorState = GraphCalculatorState()) {
        self.state = state
    }

    public static func preview() -> some View {
        GraphCalculatorView(
            state: GraphCalculatorState(
                expressions: [
                    GraphEquation(expression: "f(x)=x^2-4", colorIndex: 0),
                    GraphEquation(expression: "sin(x)", colorIndex: 1)
                ]
            )
        )
        .frame(width: 460, height: 820)
        .padding(40)
        .background(Color(white: 0.93))
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                if state.isGraphDetached {
                    detachedControlPanel(in: proxy.size)
                    detachedGraphPanel(in: proxy.size)
                } else {
                    let size = dockedCalculatorSize(in: proxy.size)
                    let center = dockedCalculatorCenter(size: size, in: proxy.size)
                    calculatorBody(in: proxy.size)
                        .frame(width: size.width, height: size.height)
                        .position(center)
                        .opacity(isDragging(.docked) ? 0.14 : 1)
                }

                if let dragProxy {
                    dragProxyView(dragProxy)
                        .frame(width: dragProxy.size.width, height: dragProxy.size.height)
                        .position(dragProxy.center)
                        .offset(dragProxy.offset)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: state.isGraphDetached)
            .onDisappear {
                sliderPlaybackTask?.cancel()
                sliderPlaybackTask = nil
            }
        }
    }

    private func calculatorBody(in containerSize: CGSize) -> some View {
        let size = dockedCalculatorSize(in: containerSize)
        let center = dockedCalculatorCenter(size: size, in: containerSize)

        return VStack(spacing: 0) {
            topBar
                .gesture(dockedCalculatorDragGesture(currentCenter: center, size: size, in: containerSize))
            graphRegion
                .frame(height: 285)
            graphToolbar
            entryPanel
                .frame(height: dockedEntryHeight)
                .overlay(alignment: .bottom) {
                    if state.isKeypadCollapsed {
                        entryResizeHandle
                    }
                }
            keypad
                .frame(height: state.isKeypadCollapsed ? 0 : keypadHeight)
                .clipped()
        }
        .background(GraphCalculatorTheme.panel, in: Rectangle())
        .overlay(Rectangle().strokeBorder(.black.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        .compositingGroup()
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.xyaxis.line")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))

            Text(state.title)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer()

            Button("Save") {}
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(GraphCalculatorTheme.blue, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button {} label: {
                Image(systemName: "ellipsis")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.88))
                    .frame(width: 32, height: 32)
                    .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 2))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
        .background(GraphCalculatorTheme.header)
    }

    private var graphRegion: some View {
        ZStack {
            if state.isGraphDetached {
                VStack(spacing: 6) {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.title2.weight(.semibold))
                    Text("Graph detached")
                        .font(.headline)
                    Text("Use the keypad and expression rows below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.black.opacity(0.72))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
            } else {
                graphCanvas
            }
        }
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 10) {
                graphIconButton("plus") { zoom(by: 1.35) }
                graphIconButton("minus") { zoom(by: 1 / 1.35) }
            }
            .padding(10)
        }
        .overlay(alignment: .bottomTrailing) {
            graphIconButton("eject.fill", style: .destructive) { ejectGraph() }
                .padding(10)
        }
    }

    private var graphCanvas: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                GraphCalculatorRenderer.draw(
                    in: context,
                    size: size,
                    window: state.graphWindow,
                    expressions: state.expressions,
                    dataTables: state.dataTables,
                    engine: engine,
                    variableValues: graphVariableValues,
                    accent: GraphCalculatorTheme.blue,
                    axisStyle: GraphAxisStyle(
                        axisStrokeWidth: CGFloat(state.axisStrokeWidth),
                        gridlineThickness: CGFloat(state.gridlineThickness),
                        showGrid: state.isGridVisible,
                        xAxisLabel: state.xAxisLabel,
                        yAxisLabel: state.yAxisLabel,
                        handDrawn: state.isHandDrawnStyle
                    )
                )
            }
            .background(state.isHandDrawnStyle ? GraphPaperPalette.paper : Color.white)
            .contentShape(Rectangle())
            .gesture(graphPanGesture(size: proxy.size))
            .simultaneousGesture(graphMagnifyGesture(size: proxy.size))
        }
    }

    private var graphToolbar: some View {
        HStack(spacing: 18) {
            Button { state.isAddMenuVisible.toggle() } label: {
                Image(systemName: "plus")
                    .foregroundStyle(state.isAddMenuVisible ? GraphCalculatorTheme.blue : .black.opacity(0.62))
            }
            Spacer()
            Button {} label: { Image(systemName: "arrow.uturn.backward") }
            Button {} label: { Image(systemName: "arrow.uturn.forward").opacity(0.35) }
            Spacer()
            Button { state.isKeypadCollapsed.toggle() } label: {
                Image(systemName: state.isKeypadCollapsed ? "chevron.up.2" : "chevron.down.2")
                    .foregroundStyle(state.isKeypadCollapsed ? GraphCalculatorTheme.blue : .black.opacity(0.62))
            }
            Button { state.resetWindow() } label: { Image(systemName: "house") }
            Button { toggleGraphSettings() } label: {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(state.isGraphSettingsVisible ? GraphCalculatorTheme.blue : .black.opacity(0.62))
            }
            Button { state.isGraphDetached = false } label: {
                Image(systemName: "arrow.down.to.line.compact")
                    .foregroundStyle(state.isGraphDetached ? GraphCalculatorTheme.blue : .black.opacity(0.32))
            }
            .disabled(!state.isGraphDetached)
        }
        .font(.title2.weight(.semibold))
        .foregroundStyle(.black.opacity(0.62))
        .padding(.horizontal, 24)
        .frame(height: 48)
        .background(GraphCalculatorTheme.toolbar)
    }

    private var tablePanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Table")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button { state.addTableXValue() } label: {
                    Image(systemName: "plus")
                        .font(.headline.weight(.semibold))
                }
                .buttonStyle(.plain)
                Button { state.isTableVisible = false } label: {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.semibold))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.black.opacity(0.72))
            .padding(.horizontal, 14)
            .frame(height: 34)

            HStack(spacing: 0) {
                tableHeaderCell("x")
                tableHeaderCell("y")
                tableHeaderCell("")
            }
            ForEach(Array(tableRows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 0) {
                    editableTableXCell(row.x, index: index)
                    tableValueCell(row.y)
                    Button { state.deleteTableXValue(at: index) } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.black.opacity(0.35))
                            .frame(maxWidth: .infinity, minHeight: 24)
                    }
                    .buttonStyle(.plain)
                    .overlay(Rectangle().stroke(.black.opacity(0.10), lineWidth: 0.5))
                }
            }
            Spacer(minLength: 0)
        }
        .background(Color.white)
    }

    private var entryPanel: some View {
        VStack(spacing: 0) {
            if state.isAddMenuVisible {
                addMenuPanel
            } else if state.isFunctionMenuVisible {
                functionMenuPanel
            } else if state.isGraphSettingsVisible {
                graphSettingsPanel
            } else if state.isTableVisible {
                tablePanel
            } else {
                expressionList
            }

        }
    }

    private func toggleGraphSettings() {
        let newValue = !state.isGraphSettingsVisible
        if newValue {
            state.isAddMenuVisible = false
            state.isFunctionMenuVisible = false
            state.isTableVisible = false
        }
        state.isGraphSettingsVisible = newValue
    }

    private var graphSettingsPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Graph Settings")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button { state.isGraphSettingsVisible = false } label: {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.semibold))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.black.opacity(0.72))
            .padding(.horizontal, 14)
            .frame(height: 34)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    graphSettingSlider(
                        title: "Axis stroke width",
                        value: $state.axisStrokeWidth,
                        range: 0.5...5,
                        display: String(format: "%.1f", state.axisStrokeWidth)
                    )
                    graphSettingSlider(
                        title: "Gridline thickness",
                        value: $state.gridlineThickness,
                        range: 0.25...3,
                        display: String(format: "%.2f", state.gridlineThickness)
                    )

                    Toggle(isOn: $state.isGridVisible) {
                        Text("Show grid")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.black.opacity(0.8))
                    }
                    .tint(GraphCalculatorTheme.blue)

                    Toggle(isOn: $state.isHandDrawnStyle) {
                        Text("Pen & paper style")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.black.opacity(0.8))
                    }
                    .tint(GraphCalculatorTheme.blue)

                    graphSettingTextField(title: "x-axis label", text: $state.xAxisLabel)
                    graphSettingTextField(title: "y-axis label", text: $state.yAxisLabel)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .background(Color.white)
    }

    private func graphSettingSlider(title: String, value: Binding<Double>, range: ClosedRange<Double>, display: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.black.opacity(0.8))
                Spacer()
                Text(display)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.black.opacity(0.55))
            }
            Slider(value: value, in: range)
                .tint(GraphCalculatorTheme.blue)
        }
    }

    private func graphSettingTextField(title: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.black.opacity(0.8))
            Spacer()
            TextField("none", text: text)
                .font(.system(size: 14))
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(width: 130)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.black.opacity(0.14), lineWidth: 0.5))
        }
    }

    /// Docked entry-panel height. With the keypad shown it is the base height; when the keypad is
    /// hidden the entry area expands into the freed keypad space (drag-adjustable) so it fills to a
    /// clean bottom edge instead of leaving empty white space.
    private var dockedEntryHeight: CGFloat {
        guard state.isKeypadCollapsed else { return baseEntryHeight }
        return baseEntryHeight + min(max(keypadHiddenEntryExtra, 0), keypadHeight)
    }

    /// Grab handle shown at the bottom edge of the entry panel while the keypad is hidden.
    /// Dragging it resizes the entry area within the space freed by the hidden keypad.
    private var entryResizeHandle: some View {
        ZStack {
            Color.white
            Capsule()
                .fill(Color.black.opacity(0.28))
                .frame(width: 42, height: 5)
        }
        .frame(maxWidth: .infinity)
        .frame(height: entryHandleHeight)
        .overlay(Rectangle().fill(Color.black.opacity(0.10)).frame(height: 0.5), alignment: .top)
        .overlay(Rectangle().fill(Color.black.opacity(0.20)).frame(height: 1), alignment: .bottom)
        .contentShape(Rectangle())
        .gesture(entryResizeGesture)
    }

    private var entryResizeGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = entryResizeStartExtra ?? keypadHiddenEntryExtra
                if entryResizeStartExtra == nil { entryResizeStartExtra = start }
                keypadHiddenEntryExtra = min(max(start + value.translation.height, 0), keypadHeight)
            }
            .onEnded { _ in entryResizeStartExtra = nil }
    }

    private var addMenuPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button { state.isAddMenuVisible = false } label: {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.semibold))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.black.opacity(0.72))
            .padding(.horizontal, 14)
            .frame(height: 34)

            HStack(spacing: 10) {
                addMenuButton("Function", systemName: "function") { state.addExpression() }
                addMenuButton("Table", systemName: "tablecells") { state.addDataTable() }
                addMenuButton("Folder", systemName: "folder") { state.addFolder() }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            Spacer(minLength: 0)
        }
        .background(Color.white)
    }

    private func addMenuButton(_ label: String, systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: systemName)
                    .font(.title3.weight(.semibold))
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.black.opacity(0.78))
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(Color.black.opacity(0.055), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.black.opacity(0.14), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private var functionMenuPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Functions")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button { state.isFunctionMenuVisible = false } label: {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.semibold))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.black.opacity(0.72))
            .padding(.horizontal, 14)
            .frame(height: 34)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(FunctionMenuCategory.allCases, id: \.self) { category in
                    Button {
                        functionMenuCategory = category
                    } label: {
                        Text(category.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(functionMenuCategory == category ? .white : .black.opacity(0.7))
                            .frame(maxWidth: .infinity, minHeight: 26)
                            .background(functionMenuCategory == category ? GraphCalculatorTheme.blue : Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(functionMenuCategory.items, id: \.label) { item in
                    functionKey(item.label, inserts: item.insertion)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            Spacer(minLength: 0)
        }
        .background(Color.white)
    }

    private func functionKey(_ label: String, inserts text: String) -> some View {
        Button {
            if text.isEmpty {
                state.addDataTable()
            } else {
                insert(text)
            }
            state.isFunctionMenuVisible = false
        } label: {
            Text(label)
                .font(.system(size: 16, weight: .medium, design: .serif))
                .foregroundStyle(.black.opacity(0.86))
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.black.opacity(0.14), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private var sliderPanel: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(sliderNames, id: \.self) { name in
                    HStack(spacing: 8) {
                        Text("\(name)=\(sliderValueText(for: name))")
                            .font(.system(size: 13, weight: .semibold, design: .serif))
                            .foregroundStyle(.black.opacity(0.78))
                            .frame(width: 62, alignment: .leading)
                        Slider(value: sliderBinding(for: name), in: sliderRange(for: name), step: 0.1)
                            .frame(width: 140)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .background(Color.white)
        .overlay(Rectangle().fill(.black.opacity(0.12)).frame(height: 0.5), alignment: .top)
        .onAppear {
            syncSliderDefaults()
        }
        .onChange(of: sliderNames) { _, _ in
            syncSliderDefaults()
        }
    }

    private var sliderNames: [String] {
        sliderCandidateNames.filter { state.sliderDecisions[$0] == true || state.sliderValues[$0] != nil }
    }

    private var sliderCandidateNames: [String] {
        let definedNames = Set(scalarVariableValues.keys)
        return GraphCalculatorVariableScanner.sliderNames(in: state.expressions.map(\.expression))
            .filter { !definedNames.contains($0) }
    }

    private var approvedSliderValues: [String: Double] {
        var values: [String: Double] = [:]
        let approvedNames = Set(state.sliderDecisions.compactMap { $0.value ? $0.key : nil }).union(state.sliderValues.keys)
        for name in approvedNames {
            values[name] = state.sliderValues[name] ?? 0
        }
        return values
    }

    private var scalarVariableValues: [String: Double] {
        GraphCalculatorExpressionResolver.scalarVariableValues(
            in: state.expressions,
            engine: engine,
            variableValues: approvedSliderValues
        )
    }

    private var graphVariableValues: [String: Double] {
        var values = approvedSliderValues
        for name in sliderNames where values[name] == nil {
            values[name] = 0
        }
        values.merge(scalarVariableValues) { _, scalar in scalar }
        return values
    }

    /// Candidate variables in a single expression that have not yet been turned into sliders
    /// or defined elsewhere. Once a variable like `k` is defined in another row (e.g. `k=4`),
    /// it drops out of `sliderCandidateNames`, so the prompt disappears; deleting that
    /// definition makes it a candidate again and the prompt returns.
    private func sliderPromptNames(forExpression text: String) -> [String] {
        let candidates = Set(sliderCandidateNames)
        let active = Set(sliderNames)
        return GraphCalculatorVariableScanner.sliderNames(in: [text])
            .filter { candidates.contains($0) && !active.contains($0) }
    }

    /// The first expression (lowest index) that references a given slider variable "owns" its slider cell.
    private func ownedSliderNames(forExpressionIndex index: Int) -> [String] {
        sliderNames.filter { firstExpressionIndex(referencing: $0) == index }
    }

    private func firstExpressionIndex(referencing name: String) -> Int? {
        for i in state.expressions.indices {
            let referenced = GraphCalculatorVariableScanner.sliderNames(in: [state.expressions[i].expression])
            if referenced.contains(name) { return i }
        }
        return nil
    }

    private func sliderBinding(for name: String) -> Binding<Double> {
        Binding(
            get: { state.sliderValues[name] ?? 0 },
            set: { state.sliderValues[name] = min(max($0, state.sliderMinimum(named: name)), state.sliderMaximum(named: name)) }
        )
    }

    private func sliderRange(for name: String) -> ClosedRange<Double> {
        state.sliderMinimum(named: name)...state.sliderMaximum(named: name)
    }

    private func sliderValueText(for name: String) -> String {
        CalculatorResultFormatter.string(for: state.sliderValues[name] ?? 0)
    }

    private func sliderBoundText(_ value: Double) -> String {
        CalculatorResultFormatter.string(for: value)
    }

    private func beginSliderBoundEdit(name: String, endpoint: SliderBoundEdit.Endpoint) {
        // Commit any bound already being edited before opening a new one.
        if editingSliderBound != nil {
            commitSliderBoundEdit()
        }
        editingSliderBound = SliderBoundEdit(name: name, endpoint: endpoint)
        let value = endpoint == .minimum ? state.sliderMinimum(named: name) : state.sliderMaximum(named: name)
        editingSliderBoundText = sliderBoundText(value)
        // The current value is shown pre-selected; the first keypad press replaces it.
        editingSliderBoundReplacesOnInput = true
    }

    private func commitSliderBoundEdit() {
        guard let editingSliderBound else { return }
        defer {
            self.editingSliderBound = nil
            editingSliderBoundText = ""
            editingSliderBoundReplacesOnInput = false
        }
        guard let value = Double(editingSliderBoundText.replacingOccurrences(of: "−", with: "-")) else { return }
        switch editingSliderBound.endpoint {
        case .minimum:
            state.setSliderMinimum(named: editingSliderBound.name, value: value)
        case .maximum:
            state.setSliderMaximum(named: editingSliderBound.name, value: value)
        }
    }

    private func cancelSliderBoundEdit() {
        editingSliderBound = nil
        editingSliderBoundText = ""
        editingSliderBoundReplacesOnInput = false
    }

    /// Routes a calculator-keypad character into the active slider-bound editor.
    /// Only number-relevant characters are accepted; everything else is ignored.
    private func appendSliderBoundInput(_ text: String) {
        guard editingSliderBound != nil else { return }
        switch text {
        case "-":
            if editingSliderBoundReplacesOnInput {
                editingSliderBoundText = "-"
                editingSliderBoundReplacesOnInput = false
            } else if editingSliderBoundText.hasPrefix("-") || editingSliderBoundText.hasPrefix("−") {
                editingSliderBoundText.removeFirst()
            } else {
                editingSliderBoundText = "-" + editingSliderBoundText
            }
        case ".":
            if editingSliderBoundReplacesOnInput {
                editingSliderBoundText = "0."
                editingSliderBoundReplacesOnInput = false
            } else if !editingSliderBoundText.contains(".") {
                editingSliderBoundText += editingSliderBoundText.isEmpty ? "0." : "."
            }
        default:
            guard text.count == 1, text.first?.isNumber == true else { return }
            if editingSliderBoundReplacesOnInput {
                editingSliderBoundText = text
                editingSliderBoundReplacesOnInput = false
            } else {
                editingSliderBoundText += text
            }
        }
    }

    private func deleteSliderBoundInput() {
        guard editingSliderBound != nil else { return }
        if editingSliderBoundReplacesOnInput {
            editingSliderBoundText = ""
            editingSliderBoundReplacesOnInput = false
        } else if !editingSliderBoundText.isEmpty {
            editingSliderBoundText.removeLast()
        }
    }

    // MARK: Slider self-animation ("play")

    private func toggleSliderPlayback(_ name: String) {
        if playingSliders.contains(name) {
            playingSliders.remove(name)
        } else {
            playingSliders.insert(name)
            if sliderPlayDirections[name] == nil { sliderPlayDirections[name] = 1 }
        }
        restartSliderPlaybackLoop()
    }

    private func restartSliderPlaybackLoop() {
        sliderPlaybackTask?.cancel()
        guard !playingSliders.isEmpty else {
            sliderPlaybackTask = nil
            return
        }
        sliderPlaybackTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 33_000_000)
                if Task.isCancelled || playingSliders.isEmpty { break }
                for name in playingSliders {
                    advancePlayingSlider(name)
                }
            }
        }
    }

    private func advancePlayingSlider(_ name: String) {
        // Stop animating variables that are no longer active sliders.
        guard sliderNames.contains(name) else {
            playingSliders.remove(name)
            return
        }
        let minValue = state.sliderMinimum(named: name)
        let maxValue = state.sliderMaximum(named: name)
        let span = maxValue - minValue
        guard span > 0 else { return }
        let step = span / 120
        var direction = sliderPlayDirections[name] ?? 1
        var value = (state.sliderValues[name] ?? minValue) + direction * step
        if value >= maxValue {
            value = maxValue
            direction = -1
        } else if value <= minValue {
            value = minValue
            direction = 1
        }
        sliderPlayDirections[name] = direction
        state.sliderValues[name] = value
    }

    private func syncSliderDefaults() {
        state.ensureSliderDefaults(for: sliderNames)
    }

    private var tableRows: [(x: String, y: String)] {
        guard let row = resolvedRows.first(where: { $0.index == state.selectedExpressionIndex }),
              let plot = row.plot,
              let source = yValueExpression(from: plot),
              let compiled = try? engine.compile(source) else {
            return [(x: "Select a y-function", y: "")]
        }

        return state.tableXValues.map { x in
            var variables = graphVariableValues
            variables["x"] = x
            let y = try? engine.evaluate(compiled: compiled, angleMode: .radians, variables: variables)
            return (
                x: CalculatorResultFormatter.string(for: x),
                y: y.map(CalculatorResultFormatter.string(for:)) ?? "undefined"
            )
        }
    }

    private func yValueExpression(from plot: GraphCalculatorPlot) -> String? {
        switch plot {
        case .curve(let source), .yRelation(let source, _):
            return source
        case .xRelation, .point:
            return nil
        }
    }

    private func tableHeaderCell(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold, design: .serif))
            .foregroundStyle(.black.opacity(0.7))
            .frame(maxWidth: .infinity, minHeight: 24)
            .background(Color.black.opacity(0.06))
            .overlay(Rectangle().stroke(.black.opacity(0.12), lineWidth: 0.5))
    }

    private func tableValueCell(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .regular, design: .serif))
            .foregroundStyle(.black.opacity(0.82))
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(maxWidth: .infinity, minHeight: 22)
            .overlay(Rectangle().stroke(.black.opacity(0.10), lineWidth: 0.5))
    }

    private func editableTableXCell(_ text: String, index: Int) -> some View {
        HStack(spacing: 4) {
            Button { state.updateTableXValue(at: index, by: -1) } label: {
                Image(systemName: "minus")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)

            TextField(
                "",
                text: Binding(
                    get: { text },
                    set: { newValue in
                        if let value = Double(newValue.replacingOccurrences(of: "−", with: "-")),
                           state.tableXValues.indices.contains(index) {
                            state.tableXValues[index] = value
                        }
                    }
                )
            )
                .font(.system(size: 14, weight: .regular, design: .serif))
                .foregroundStyle(.black.opacity(0.82))
                .multilineTextAlignment(.center)
                .keyboardType(.numbersAndPunctuation)
                .frame(maxWidth: .infinity)

            Button { state.updateTableXValue(at: index, by: 1) } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.black.opacity(0.62))
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 24)
        .overlay(Rectangle().stroke(.black.opacity(0.10), lineWidth: 0.5))
    }

    private var expressionList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(0..<expressionRowCount, id: \.self) { index in
                        expressionRow(index, resolvedRows: resolvedRows)
                            .id(index)
                        ForEach(ownedSliderNames(forExpressionIndex: index), id: \.self) { name in
                            sliderCell(name)
                        }
                    }
                    ForEach(Array(state.dataTables.enumerated()), id: \.element.id) { tableIndex, table in
                        dataTableCard(table, tableIndex: tableIndex)
                    }
                    ForEach(state.folders) { folder in
                        folderRow(folder)
                    }
                }
            }
            .scrollIndicators(.visible)
            .onChange(of: state.selectedExpressionIndex) { _, newValue in
                withAnimation(.easeInOut(duration: 0.16)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .background(Color.white)
    }

    private func dataTableCard(_ table: GraphCalculatorDataTable, tableIndex: Int) -> some View {
        HStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(graphColor(for: tableIndex))
                    .frame(width: 28, height: 28)
                    .overlay(Circle().strokeBorder(.black.opacity(0.08), lineWidth: 1.5))
                Image(systemName: "tablecells")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 52)
            .background(Color.black.opacity(0.06))

            VStack(spacing: 0) {
                HStack {
                    Text("Table")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.62))
                    Spacer()
                    Button { state.addDataTableColumn(tableID: table.id) } label: {
                        Image(systemName: "plus.square")
                            .font(.subheadline.weight(.semibold))
                    }
                    .disabled(table.columnNames.count >= 4)
                    Button { state.addDataTableRow(tableID: table.id) } label: {
                        Image(systemName: "plus")
                            .font(.subheadline.weight(.semibold))
                    }
                    Button { state.deleteDataTable(tableID: table.id) } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.black.opacity(0.6))
                .padding(.horizontal, 10)
                .frame(height: 28)

                HStack(spacing: 0) {
                    ForEach(0..<table.columnNames.count, id: \.self) { columnIndex in
                        dataTableHeader(table: table, columnIndex: columnIndex)
                    }
                    tableHeaderCell("")
                }

                ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(spacing: 0) {
                        ForEach(0..<table.columnNames.count, id: \.self) { columnIndex in
                            dataTableValueCell(table: table, row: row, rowIndex: rowIndex, columnIndex: columnIndex)
                        }
                        Button { state.deleteDataTableRow(tableID: table.id, rowIndex: rowIndex) } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.black.opacity(0.35))
                                .frame(width: 30, height: 26)
                        }
                        .buttonStyle(.plain)
                        .overlay(Rectangle().stroke(.black.opacity(0.10), lineWidth: 0.5))
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.trailing, 8)
        }
        .background(Color.white)
        .overlay(Rectangle().fill(Color.black.opacity(0.12)).frame(height: 0.5), alignment: .top)
    }

    private func dataTableHeader(table: GraphCalculatorDataTable, columnIndex: Int) -> some View {
        ZStack {
            Text(GraphCalculatorExpressionDisplay.variableName(for: table.columnNames.indices.contains(columnIndex) ? table.columnNames[columnIndex] : ""))
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .foregroundStyle(.black.opacity(0.72))
            TextField(
                "",
                text: Binding(
                    get: { table.columnNames.indices.contains(columnIndex) ? table.columnNames[columnIndex] : "" },
                    set: { state.updateDataTableColumnName(tableID: table.id, columnIndex: columnIndex, name: $0) }
                )
            )
            .font(.system(size: 13, weight: .semibold, design: .serif))
            .foregroundStyle(.clear)
            .tint(GraphCalculatorTheme.blue)
            .multilineTextAlignment(.center)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
        .frame(maxWidth: .infinity, minHeight: 26)
        .background(Color.black.opacity(0.055))
        .overlay(Rectangle().stroke(.black.opacity(0.12), lineWidth: 0.5))
    }

    private func dataTableValueCell(table: GraphCalculatorDataTable, row: [Double?], rowIndex: Int, columnIndex: Int) -> some View {
        TextField(
            "",
            text: Binding(
                get: {
                    guard row.indices.contains(columnIndex), let value = row[columnIndex] else { return "" }
                    return CalculatorResultFormatter.string(for: value)
                },
                set: { text in
                    state.updateDataTableValue(tableID: table.id, rowIndex: rowIndex, columnIndex: columnIndex, value: Double(text.replacingOccurrences(of: "−", with: "-")))
                }
            )
        )
        .font(.system(size: 13, weight: .regular, design: .serif))
        .foregroundStyle(.black.opacity(0.82))
        .multilineTextAlignment(.center)
        .keyboardType(.numbersAndPunctuation)
        .frame(maxWidth: .infinity, minHeight: 26)
        .overlay(Rectangle().stroke(.black.opacity(0.10), lineWidth: 0.5))
    }

    private func folderRow(_ folder: GraphCalculatorFolder) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
            Text(folder.name)
                .font(.system(size: 15, weight: .semibold))
            Spacer()
        }
        .foregroundStyle(.black.opacity(0.62))
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(Color.white)
        .overlay(Rectangle().fill(Color.black.opacity(0.12)).frame(height: 0.5), alignment: .top)
    }

    private var expressionRowCount: Int {
        max(state.expressions.count + 1, 4)
    }

    private var resolvedRows: [GraphCalculatorResolvedRow] {
        GraphCalculatorExpressionResolver.resolveRows(
            expressions: state.expressions,
            engine: engine,
            variableValues: graphVariableValues,
            sliderCandidateNames: Set(sliderCandidateNames)
        )
    }

    private func expressionRow(_ index: Int, resolvedRows: [GraphCalculatorResolvedRow]) -> some View {
        let isSelected = state.selectedExpressionIndex == index
        let text = state.expressions.indices.contains(index) ? state.expressions[index].expression : ""
        let resolved = resolvedRows.first { $0.index == index }
        let isInvalid = resolved?.errorMessage != nil
        let displayValue = resolved?.displayValue
        let displayText = GraphCalculatorExpressionDisplay.string(for: text)
        let color = graphColor(for: index)
        let promptNames = sliderPromptNames(forExpression: text)
        let rowHeight: CGFloat = promptNames.isEmpty ? 50 : 82

        return HStack(spacing: 0) {
            expressionStyleCell(index: index, isSelected: isSelected, isInvalid: isInvalid, color: color)
                .frame(height: rowHeight)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    expressionText(text, displayText: displayText, isSelected: isSelected)
                    if let displayValue {
                        Text("= \(displayValue)")
                            .font(.system(size: 17, weight: .medium, design: .serif))
                            .foregroundStyle(.black.opacity(0.62))
                            .lineLimit(1)
                    }
                }
                if let error = resolved?.errorMessage, !text.isEmpty {
                    Text(error)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.red.opacity(0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                if !promptNames.isEmpty {
                    createSliderPrompt(promptNames)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)

            Button { deleteExpression(index) } label: {
                Image(systemName: "xmark")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.black.opacity(0.22))
                    .frame(width: 44, height: rowHeight)
            }
            .buttonStyle(.plain)
        }
        .frame(height: rowHeight)
        .background(Color.white)
        .overlay(Rectangle().fill(isSelected ? GraphCalculatorTheme.blue : Color.black.opacity(0.12)).frame(height: isSelected ? 1.5 : 0.5), alignment: .bottom)
        .contentShape(Rectangle())
        .onTapGesture {
            if editingSliderBound != nil { commitSliderBoundEdit() }
            state.selectExpression(at: index)
        }
    }

    /// Inline "create slider:" prompt shown beneath an equation for each candidate variable.
    private func createSliderPrompt(_ names: [String]) -> some View {
        HStack(spacing: 8) {
            Text("create slider:")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.black.opacity(0.55))
            ForEach(names, id: \.self) { name in
                Button {
                    state.approveSlider(named: name)
                } label: {
                    Text(GraphCalculatorExpressionDisplay.variableName(for: name))
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(GraphCalculatorTheme.blue, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// A standalone slider cell. Mirrors the equation cell layout but, instead of a color circle,
    /// its left gutter holds a play/pause button that animates the slider back and forth.
    private func sliderCell(_ name: String) -> some View {
        HStack(spacing: 0) {
            Button { toggleSliderPlayback(name) } label: {
                Image(systemName: playingSliders.contains(name) ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 27))
                    .foregroundStyle(GraphCalculatorTheme.blue)
                    .frame(width: 52)
                    .frame(maxHeight: .infinity)
                    .background(Color.black.opacity(0.06))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 8) {
                Text("\(GraphCalculatorExpressionDisplay.variableName(for: name)) = \(sliderValueText(for: name))")
                    .font(.system(size: 17, weight: .medium, design: .serif))
                    .foregroundStyle(.black.opacity(0.82))
                    .lineLimit(1)
                HStack(spacing: 10) {
                    sliderBoundButton(name: name, endpoint: .minimum)
                    Slider(value: sliderBinding(for: name), in: sliderRange(for: name), step: 0.1)
                    sliderBoundButton(name: name, endpoint: .maximum)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Button {
                if editingSliderBound?.name == name { cancelSliderBoundEdit() }
                playingSliders.remove(name)
                restartSliderPlaybackLoop()
                state.removeSlider(named: name)
            } label: {
                Image(systemName: "xmark")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.black.opacity(0.22))
                    .frame(width: 44)
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: 78)
        .background(Color.white)
        .overlay(Rectangle().fill(Color.black.opacity(0.12)).frame(height: 0.5), alignment: .bottom)
    }

    /// Tappable slider endpoint. Tapping opens an inline highlighted bubble edited with the
    /// calculator keypad (no system keyboard); tapping again commits the value.
    private func sliderBoundButton(name: String, endpoint: SliderBoundEdit.Endpoint) -> some View {
        let isEditing = editingSliderBound?.name == name && editingSliderBound?.endpoint == endpoint
        let value = endpoint == .minimum ? state.sliderMinimum(named: name) : state.sliderMaximum(named: name)
        let display: String = {
            guard isEditing else { return sliderBoundText(value) }
            let raw = editingSliderBoundText.isEmpty ? "0" : editingSliderBoundText
            return raw.replacingOccurrences(of: "-", with: "−")
        }()

        return Button {
            if isEditing {
                commitSliderBoundEdit()
            } else {
                beginSliderBoundEdit(name: name, endpoint: endpoint)
            }
        } label: {
            Text(display)
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundStyle(isEditing ? .white : GraphCalculatorTheme.blue)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(minWidth: 42)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    isEditing ? GraphCalculatorTheme.blue : Color.white,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(isEditing ? Color.clear : Color.black.opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func expressionText(_ text: String, displayText: String, isSelected: Bool) -> some View {
        if isSelected {
            let splitText = split(text, at: state.cursorOffset)
            HStack(spacing: 1) {
                Text(GraphCalculatorExpressionDisplay.string(for: splitText.before))
                Rectangle()
                    .fill(GraphCalculatorTheme.blue)
                    .frame(width: 2, height: 24)
                Text(GraphCalculatorExpressionDisplay.string(for: splitText.after))
                if text.isEmpty {
                    Spacer(minLength: 0)
                }
            }
            .font(.system(size: 20, weight: .regular, design: .serif))
            .foregroundStyle(.black)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
        } else {
            Text(displayText)
                .font(.system(size: 20, weight: .regular, design: .serif))
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
    }

    private func split(_ text: String, at offset: Int) -> (before: String, after: String) {
        let clamped = min(max(offset, 0), text.count)
        let index = text.index(text.startIndex, offsetBy: clamped, limitedBy: text.endIndex) ?? text.endIndex
        return (String(text[..<index]), String(text[index...]))
    }

    private func expressionStyleCell(index: Int, isSelected: Bool, isInvalid: Bool, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(color.opacity(isInvalid ? 0.35 : 1))
                .frame(width: 28, height: 28)
                .overlay(Circle().strokeBorder(isSelected ? .white.opacity(0.84) : .black.opacity(0.08), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                .contentShape(Circle())
                .onLongPressGesture {
                    state.ensureExpression(at: index)
                    state.selectExpression(at: index)
                    stylingExpressionIndex = index
                }
                .popover(
                    isPresented: Binding(
                        get: { stylingExpressionIndex == index },
                        set: { isPresented in
                            if !isPresented, stylingExpressionIndex == index {
                                stylingExpressionIndex = nil
                            }
                        }
                    )
                ) {
                    expressionStylePopover(index: index)
                }
            if isInvalid {
                Image(systemName: "xmark")
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(.red)
                    .shadow(color: .white.opacity(0.9), radius: 1)
            }
        }
        .frame(width: 52)
        .background(isSelected ? GraphCalculatorTheme.blue : Color.black.opacity(0.06))
    }

    private func expressionStylePopover(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Graph Style")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Color")
                    Spacer()
                    Circle()
                        .fill(graphColor(for: index))
                        .frame(width: 18, height: 18)
                }
                Slider(
                    value: hueBinding(for: index),
                    in: 0...0.80,
                    step: 0.01
                )
                .tint(graphColor(for: index))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.red, .orange, .yellow, .green, .blue, .indigo],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 6)
                HStack {
                    styleStopButton("Red", value: 0.0, binding: hueBinding(for: index))
                    Spacer()
                    styleStopButton("Green", value: 0.36, binding: hueBinding(for: index))
                    Spacer()
                    styleStopButton("Blue", value: 0.58, binding: hueBinding(for: index))
                    Spacer()
                    styleStopButton("Indigo", value: 0.72, binding: hueBinding(for: index))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Line Width")
                    Spacer()
                    Text("\(lineWidthBinding(for: index).wrappedValue, specifier: "%.1f")")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: lineWidthBinding(for: index),
                    in: GraphCalculatorStyleDefaults.minimumLineWidth...GraphCalculatorStyleDefaults.maximumLineWidth,
                    step: 0.25
                )
                HStack {
                    styleStopButton("Thin", value: GraphCalculatorStyleDefaults.minimumLineWidth, binding: lineWidthBinding(for: index))
                    Spacer()
                    styleStopButton("Medium", value: GraphCalculatorStyleDefaults.lineWidth, binding: lineWidthBinding(for: index))
                    Spacer()
                    styleStopButton("Bold", value: GraphCalculatorStyleDefaults.maximumLineWidth, binding: lineWidthBinding(for: index))
                }
            }

            Button("Reset Style") {
                guard state.expressions.indices.contains(index) else { return }
                state.expressions[index].lineHue = nil
                state.expressions[index].lineWidth = nil
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(18)
        .frame(width: 300)
    }

    private func styleStopButton(_ title: String, value: Double, binding: Binding<Double>) -> some View {
        Button {
            binding.wrappedValue = value
        } label: {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(GraphCalculatorTheme.blue)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.05), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func hueBinding(for index: Int) -> Binding<Double> {
        Binding(
            get: {
                guard state.expressions.indices.contains(index) else { return defaultHue(for: index) }
                return state.expressions[index].lineHue ?? defaultHue(for: index)
            },
            set: { value in
                state.ensureExpression(at: index)
                state.expressions[index].lineHue = value
            }
        )
    }

    private func lineWidthBinding(for index: Int) -> Binding<Double> {
        Binding(
            get: {
                guard state.expressions.indices.contains(index) else { return GraphCalculatorStyleDefaults.lineWidth }
                return state.expressions[index].lineWidth ?? GraphCalculatorStyleDefaults.lineWidth
            },
            set: { value in
                state.ensureExpression(at: index)
                state.expressions[index].lineWidth = value
            }
        )
    }

    private func graphColor(for index: Int) -> Color {
        if state.expressions.indices.contains(index), let hue = state.expressions[index].lineHue {
            return Color(hue: hue, saturation: 0.82, brightness: 0.90)
        }
        return graphPaletteColor(for: index)
    }

    private func defaultHue(for index: Int) -> Double {
        let hues = [0.58, 0.0, 0.36, 0.75, 0.09, 0.50]
        return hues[((index % hues.count) + hues.count) % hues.count]
    }

    private func graphPaletteColor(for index: Int) -> Color {
        let rgb = GraphPalette.rgb(for: index)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    private var keypad: some View {
        GeometryReader { proxy in
            let metrics = keypadMetrics(for: proxy.size)
            Group {
                if isAlphabetKeypadVisible {
                    alphabetKeypad(metrics: metrics)
                } else {
                    numberKeypad(metrics: metrics)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .background(GraphCalculatorTheme.keypad)
    }

    /// Computes key sizing so the keys fill the whole keypad frame (no dark bands, no wide center gap).
    /// The overall calculator size is unchanged; only the key area is resized.
    private func keypadMetrics(for size: CGSize) -> KeypadMetrics {
        let spacing: CGFloat = 7
        let groupSpacing: CGFloat = 12
        let horizontalPadding: CGFloat = 10
        let verticalPadding: CGFloat = 9
        let columns: CGFloat = 10          // 4 left keys + 6 right keys
        let interKeyGaps: CGFloat = 8      // 3 gaps in the left group + 5 gaps in the right group
        let rows: CGFloat = 4

        let availableWidth = max(0, size.width - horizontalPadding * 2)
        let availableHeight = max(0, size.height - verticalPadding * 2)
        let columnWidth = max(30, (availableWidth - spacing * interKeyGaps - groupSpacing) / columns)
        let rowHeight = max(38, (availableHeight - spacing * (rows - 1)) / rows)

        return KeypadMetrics(
            columnWidth: columnWidth,
            rowHeight: rowHeight,
            spacing: spacing,
            groupSpacing: groupSpacing,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding
        )
    }

    private func numberKeypad(metrics: KeypadMetrics) -> some View {
        VStack(spacing: metrics.spacing) {
            HStack(spacing: metrics.spacing) {
                key("x", metrics: metrics) { insert("x") }
                key("y", metrics: metrics) { insert("y") }
                key("a²", metrics: metrics) { insert("^2") }
                key("aᵇ", metrics: metrics) { insert("^") }
                Spacer(minLength: metrics.groupSpacing)
                key("7", style: .number, metrics: metrics) { insert("7") }
                key("8", style: .number, metrics: metrics) { insert("8") }
                key("9", style: .number, metrics: metrics) { insert("9") }
                key("÷", metrics: metrics) { insert("/") }
                key("funcs", wide: true, metrics: metrics) { state.isFunctionMenuVisible.toggle() }
            }
            HStack(spacing: metrics.spacing) {
                key("(", metrics: metrics) { insert("(") }
                key(")", metrics: metrics) { insert(")") }
                key("<", metrics: metrics) { insert("<") }
                key(">", metrics: metrics) { insert(">") }
                Spacer(minLength: metrics.groupSpacing)
                key("4", style: .number, metrics: metrics) { insert("4") }
                key("5", style: .number, metrics: metrics) { insert("5") }
                key("6", style: .number, metrics: metrics) { insert("6") }
                key("×", metrics: metrics) { insert("*") }
                key("←", metrics: metrics) { state.moveCursorLeft() }
                key("→", metrics: metrics) { state.moveCursorRight() }
            }
            HStack(spacing: metrics.spacing) {
                key("|a|", metrics: metrics) { insert("abs(") }
                key(",", metrics: metrics) { insert(",") }
                key("≤", metrics: metrics) { insert("<=") }
                key("≥", metrics: metrics) { insert(">=") }
                Spacer(minLength: metrics.groupSpacing)
                key("1", style: .number, metrics: metrics) { insert("1") }
                key("2", style: .number, metrics: metrics) { insert("2") }
                key("3", style: .number, metrics: metrics) { insert("3") }
                key("−", metrics: metrics) { insert("-") }
                key("⌫", wide: true, emphasized: true, metrics: metrics) { keypadDelete() }
            }
            HStack(spacing: metrics.spacing) {
                key("ABC", metrics: metrics) { isAlphabetKeypadVisible = true }
                Menu {
                    Button("g(x)") { insert("g(") }
                    Button("h(x)") { insert("h(") }
                } label: {
                    keyLabel("f(x)", emphasized: true, metrics: metrics)
                } primaryAction: {
                    insert("f(")
                }
                .buttonStyle(GraphKeyButtonStyle(fill: keyFill(style: .plain, emphasized: true), emphasized: true))
                key("√", metrics: metrics) { insert("sqrt(") }
                key("π", metrics: metrics) { insert("pi") }
                Spacer(minLength: metrics.groupSpacing)
                key("0", style: .number, metrics: metrics) { insert("0") }
                key(".", metrics: metrics) { insert(".") }
                key("=", metrics: metrics) { insert("=") }
                key("+", metrics: metrics) { insert("+") }
                key("↵", wide: true, emphasized: true, metrics: metrics) { keypadReturn() }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.vertical, metrics.verticalPadding)
    }

    private func alphabetKeypad(metrics: KeypadMetrics) -> some View {
        let step = metrics.columnWidth + metrics.spacing
        return VStack(spacing: metrics.spacing) {
            alphabetRow(["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"], metrics: metrics)
            alphabetRow(["a", "s", "d", "f", "g", "h", "j", "k", "l"], metrics: metrics, leadingIndent: step * 0.5)
            alphabetRow(["z", "x", "c", "v", "b", "n", "m", "{", "}"], metrics: metrics, leadingIndent: step)
            HStack(spacing: metrics.spacing) {
                key("123", metrics: metrics) { isAlphabetKeypadVisible = false }
                fractionKey(metrics: metrics) { insert("()/()") }
                key("!", metrics: metrics) { insert("!") }
                key("_", metrics: metrics) { insert("_") }
                Spacer(minLength: metrics.groupSpacing)
                key(",", metrics: metrics) { insert(",") }
                key("←", metrics: metrics) { state.moveCursorLeft() }
                key("→", metrics: metrics) { state.moveCursorRight() }
                key("⌫", wide: true, emphasized: true, metrics: metrics) { keypadDelete() }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.vertical, metrics.verticalPadding)
    }

    private func alphabetRow(_ labels: [String], metrics: KeypadMetrics, leadingIndent: CGFloat = 0) -> some View {
        HStack(spacing: metrics.spacing) {
            if leadingIndent > 0 {
                Spacer().frame(width: leadingIndent)
            }
            ForEach(labels, id: \.self) { label in
                key(label, metrics: metrics) { insert(label) }
            }
            Spacer(minLength: 0)
        }
    }

    private func key(
        _ label: String,
        style: KeyStyle = .plain,
        wide: Bool = false,
        emphasized: Bool = false,
        metrics: KeypadMetrics,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            keyLabel(label, wide: wide, emphasized: emphasized, metrics: metrics)
        }
        .buttonStyle(GraphKeyButtonStyle(fill: keyFill(style: style, emphasized: emphasized), emphasized: emphasized))
    }

    private func keyLabel(_ label: String, wide: Bool = false, emphasized: Bool = false, metrics: KeypadMetrics) -> some View {
        Text(label)
            .font(.system(size: keyFontSize(for: label, metrics: metrics), weight: .medium, design: .serif))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(emphasized ? .white : .black.opacity(0.88))
            .frame(width: keyWidth(wide: wide, metrics: metrics), height: metrics.rowHeight)
    }

    /// Scales key glyphs with the (now larger) key size, with a smaller cap for multi-character labels.
    private func keyFontSize(for label: String, metrics: KeypadMetrics) -> CGFloat {
        let base = min(metrics.rowHeight * 0.5, metrics.columnWidth * 0.66)
        if label.count > 3 {
            return min(base * 0.72, 18)
        }
        return min(max(base, 18), 30)
    }

    private func fractionKey(metrics: KeypadMetrics, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text("a")
                Rectangle()
                    .fill(.black.opacity(0.82))
                    .frame(width: metrics.columnWidth * 0.5, height: 1.4)
                Text("b")
            }
            .font(.system(size: min(metrics.rowHeight * 0.32, 17), weight: .semibold, design: .serif))
            .foregroundStyle(.black.opacity(0.88))
            .frame(width: keyWidth(wide: false, metrics: metrics), height: metrics.rowHeight)
        }
        .buttonStyle(GraphKeyButtonStyle(fill: keyFill(style: .plain, emphasized: false), emphasized: false))
    }

    private func keyWidth(wide: Bool, metrics: KeypadMetrics) -> CGFloat {
        wide ? metrics.columnWidth * 2 + metrics.spacing : metrics.columnWidth
    }

    private func keyFill(style: KeyStyle, emphasized: Bool) -> Color {
        if emphasized { return GraphCalculatorTheme.blue }
        switch style {
        case .plain: return Color.white
        case .number: return Color(red: 0.77, green: 0.77, blue: 0.76)
        }
    }

    private enum KeyStyle {
        case plain
        case number
    }

    private struct KeypadMetrics {
        let columnWidth: CGFloat
        let rowHeight: CGFloat
        let spacing: CGFloat
        let groupSpacing: CGFloat
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
    }

    private struct GraphKeyButtonStyle: ButtonStyle {
        let fill: Color
        let emphasized: Bool

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.black.opacity(configuration.isPressed ? 0.10 : 0.22))
                            .offset(y: configuration.isPressed ? 1 : 3)

                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        fill.opacity(configuration.isPressed ? 0.82 : 1.0),
                                        fill.opacity(configuration.isPressed ? 0.98 : 0.84)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .overlay(alignment: .top) {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(.white.opacity(emphasized ? 0.28 : 0.72), lineWidth: 1)
                                    .padding(1)
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(.black.opacity(0.20), lineWidth: 0.6)
                            )
                    }
                )
                .offset(y: configuration.isPressed ? 2 : 0)
                .shadow(color: .black.opacity(configuration.isPressed ? 0.05 : 0.18), radius: configuration.isPressed ? 1 : 2, y: configuration.isPressed ? 0 : 1)
        }
    }

    private func detachedGraphPanel(in containerSize: CGSize) -> some View {
        let size = detachedResizeLive?.size ?? clampGraphSize(state.detachedGraphSize, in: containerSize)
        let center = detachedResizeLive?.center ?? detachedGraphCenter(size: size, in: containerSize)

        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Graph")
                    .font(.headline)
                    .foregroundStyle(.black)
                Spacer()
                Button { state.isGraphDetached = false } label: {
                    Image(systemName: "arrow.down.to.line.compact")
                }
                Button { state.isGraphDetached = false } label: {
                    Image(systemName: "xmark.circle.fill")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.black.opacity(0.72))
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(Color.white)
            .overlay(Rectangle().fill(.black.opacity(0.18)).frame(height: 1), alignment: .bottom)
            .contentShape(Rectangle())
            .gesture(detachedDragGesture(currentCenter: center, size: size, in: containerSize))

            graphCanvas
        }
        .frame(width: size.width, height: size.height)
        .background(Color.white, in: Rectangle())
        .overlay(Rectangle().strokeBorder(.black.opacity(0.32), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
        .compositingGroup()
        .overlay(alignment: .bottomTrailing) {
            ResizeGrip()
                .frame(width: 24, height: 24)
                .padding(7)
                .contentShape(Rectangle())
                .highPriorityGesture(detachedResizeGesture(currentCenter: center, in: containerSize))
        }
        .position(center)
        .opacity(isDragging(.detachedGraph) ? 0.14 : 1)
    }

    private func detachedControlPanel(in containerSize: CGSize) -> some View {
        let width = min(containerSize.width - 24, 440)
        let height = min(containerSize.height - 24, detachedControlHeight)
        let size = CGSize(width: width, height: height)
        let center = detachedControlCenter(size: size, in: containerSize)

        return VStack(spacing: 0) {
            topBar
                .gesture(detachedControlDragGesture(currentCenter: center, size: size, in: containerSize))
            graphToolbar
            entryPanel
                .frame(height: detachedEntryHeight(availableHeight: height))
                .overlay(alignment: .bottom) {
                    if state.isKeypadCollapsed {
                        entryResizeHandle
                    }
                }
            keypad
                .frame(height: state.isKeypadCollapsed ? 0 : keypadHeight)
                .clipped()
        }
        .frame(width: size.width, height: size.height)
        .background(GraphCalculatorTheme.panel, in: Rectangle())
        .overlay(Rectangle().strokeBorder(.black.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.26), radius: 16, y: 7)
        .compositingGroup()
        .position(center)
        .opacity(isDragging(.detachedControl) ? 0.14 : 1)
    }

    private func dragProxyView(_ proxy: GraphCalculatorDragProxy) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: proxy.systemImage)
                    .font(.headline.weight(.semibold))
                Text(proxy.title)
                    .font(.headline)
                Spacer()
            }
            .foregroundStyle(proxy.headerForeground)
            .padding(.horizontal, 14)
            .frame(height: proxy.headerHeight)
            .background(proxy.headerFill)

            Rectangle()
                .fill(proxy.bodyFill)
                .overlay(alignment: .center) {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                            .font(.title2.weight(.semibold))
                        Text("Moving")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(proxy.labelForeground)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: proxy.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: proxy.cornerRadius, style: .continuous).strokeBorder(proxy.stroke, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.24), radius: 12, y: 5)
    }

    private enum GraphIconButtonStyle {
        case standard
        case destructive
    }

    private func graphIconButton(
        _ systemName: String,
        style: GraphIconButtonStyle = .standard,
        action: @escaping () -> Void
    ) -> some View {
        let isDestructive = style == .destructive

        return Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(isDestructive ? .white : .black.opacity(0.65))
                .frame(width: 40, height: 40)
                .background(
                    isDestructive ? Color.red.opacity(0.92) : Color.white.opacity(0.92),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isDestructive ? .white.opacity(0.35) : .black.opacity(0.15), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func insert(_ text: String) {
        if editingSliderBound != nil {
            appendSliderBoundInput(text)
        } else {
            state.insert(text)
        }
    }

    /// Keypad delete: edits the active slider bound if one is open, otherwise the expression.
    private func keypadDelete() {
        if editingSliderBound != nil {
            deleteSliderBoundInput()
        } else {
            state.deleteLastCharacter()
        }
    }

    /// Keypad return: commits an active slider-bound edit, otherwise adds a new expression row.
    private func keypadReturn() {
        if editingSliderBound != nil {
            commitSliderBoundEdit()
        } else {
            state.addExpression()
        }
    }

    private func deleteExpression(_ index: Int) {
        state.deleteExpression(at: index)
    }

    private func ejectGraph() {
        state.detachedGraphPosition = nil
        state.detachedControlPosition = nil
        state.isGraphDetached = true
    }

    private func zoom(by factor: Double) {
        state.graphWindow = limitedGraphWindow(
            CalculatorGraphGeometry.zoom(
                window: state.graphWindow,
                magnification: factor,
                aroundViewPoint: CGPoint(x: 0.5, y: 0.5),
                size: CGSize(width: 1, height: 1)
            )
        )
    }

    private func graphPanGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let delta = CGSize(
                    width: value.translation.width - graphPanStart.width,
                    height: value.translation.height - graphPanStart.height
                )
                graphPanStart = value.translation
                state.graphWindow = CalculatorGraphGeometry.pan(window: state.graphWindow, byViewTranslation: delta, size: size)
            }
            .onEnded { _ in graphPanStart = .zero }
    }

    private func graphMagnifyGesture(size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let startWindow = graphMagnifyStartWindow ?? state.graphWindow
                graphMagnifyStartWindow = startWindow
                let slowedMagnification = pow(max(value.magnification, 0.001), 0.38)
                state.graphWindow = limitedGraphWindow(
                    CalculatorGraphGeometry.zoom(
                        window: startWindow,
                        magnification: slowedMagnification,
                        aroundViewPoint: value.startLocation,
                        size: size
                    )
                )
            }
            .onEnded { _ in
                graphMagnifyStartWindow = nil
            }
    }

    private func limitedGraphWindow(_ window: GraphWindow) -> GraphWindow {
        let xCenter = (window.xMin + window.xMax) / 2
        let yCenter = (window.yMin + window.yMax) / 2
        let xSpan = min(max(window.width, minimumGraphSpan), maximumGraphSpan)
        let ySpan = min(max(window.height, minimumGraphSpan), maximumGraphSpan)

        return GraphWindow(
            xMin: xCenter - xSpan / 2,
            xMax: xCenter + xSpan / 2,
            yMin: yCenter - ySpan / 2,
            yMax: yCenter + ySpan / 2
        )
    }

    private func dockedCalculatorSize(in containerSize: CGSize) -> CGSize {
        CGSize(width: min(containerSize.width, 440), height: min(containerSize.height, 820))
    }

    private func dockedCalculatorCenter(size: CGSize, in containerSize: CGSize) -> CGPoint {
        let fallback = CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)
        return clamp(center: state.calculatorPosition ?? fallback, size: size, in: containerSize)
    }

    private var detachedControlHeight: CGFloat {
        let entry: CGFloat = state.isKeypadCollapsed
            ? baseDetachedEntryHeight + min(max(keypadHiddenEntryExtra, 0), keypadHeight)
            : baseDetachedEntryHeight
        return 58 + 48 + entry + (state.isKeypadCollapsed ? 0 : keypadHeight)
    }

    /// Height for the detached control panel's entry area. When the keypad is hidden the entry
    /// expands into the freed keypad space (drag-adjustable via the grab handle); otherwise it
    /// keeps its normal size above the keypad.
    private func detachedEntryHeight(availableHeight: CGFloat) -> CGFloat {
        if state.isKeypadCollapsed {
            return max(120, availableHeight - 58 - 48)
        }
        return min(baseDetachedEntryHeight, max(120, availableHeight - 58 - 48 - keypadHeight))
    }

    private func dockedCalculatorDragGesture(currentCenter: CGPoint, size: CGSize, in containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let base = dragStartCenter ?? currentCenter
                if dragStartCenter == nil { dragStartCenter = base }
                let proposed = CGPoint(x: base.x + value.translation.width, y: base.y + value.translation.height)
                let clamped = clamp(center: proposed, size: size, in: containerSize)
                setWithoutAnimation {
                    dragProxy = GraphCalculatorDragProxy(
                        kind: .docked,
                        title: state.title,
                        systemImage: "chart.xyaxis.line",
                        center: base,
                        offset: CGSize(width: clamped.x - base.x, height: clamped.y - base.y),
                        size: size
                    )
                }
            }
            .onEnded { _ in
                let offset = dragProxy?.offset ?? .zero
                state.calculatorPosition = CGPoint(x: currentCenter.x + offset.width, y: currentCenter.y + offset.height)
                dockedLiveOffset = .zero
                dragProxy = nil
                dragStartCenter = nil
            }
    }

    private func detachedDragGesture(currentCenter: CGPoint, size: CGSize, in containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let base = detachedDragStartCenter ?? currentCenter
                if detachedDragStartCenter == nil { detachedDragStartCenter = base }
                let proposed = CGPoint(x: base.x + value.translation.width, y: base.y + value.translation.height)
                let clamped = clamp(center: proposed, size: size, in: containerSize)
                setWithoutAnimation {
                    dragProxy = GraphCalculatorDragProxy(
                        kind: .detachedGraph,
                        title: "Graph",
                        systemImage: "chart.xyaxis.line",
                        center: base,
                        offset: CGSize(width: clamped.x - base.x, height: clamped.y - base.y),
                        size: size
                    )
                }
            }
            .onEnded { _ in
                let offset = dragProxy?.offset ?? .zero
                state.detachedGraphPosition = CGPoint(x: currentCenter.x + offset.width, y: currentCenter.y + offset.height)
                detachedGraphLiveOffset = .zero
                dragProxy = nil
                detachedDragStartCenter = nil
            }
    }

    private func detachedControlDragGesture(currentCenter: CGPoint, size: CGSize, in containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let base = dragStartCenter ?? currentCenter
                if dragStartCenter == nil { dragStartCenter = base }
                let proposed = CGPoint(x: base.x + value.translation.width, y: base.y + value.translation.height)
                let clamped = clamp(center: proposed, size: size, in: containerSize)
                setWithoutAnimation {
                    dragProxy = GraphCalculatorDragProxy(
                        kind: .detachedControl,
                        title: state.title,
                        systemImage: "keyboard",
                        center: base,
                        offset: CGSize(width: clamped.x - base.x, height: clamped.y - base.y),
                        size: size
                    )
                }
            }
            .onEnded { _ in
                let offset = dragProxy?.offset ?? .zero
                state.detachedControlPosition = CGPoint(x: currentCenter.x + offset.width, y: currentCenter.y + offset.height)
                detachedControlLiveOffset = .zero
                dragProxy = nil
                dragStartCenter = nil
            }
    }

    private func detachedResizeGesture(currentCenter: CGPoint, in containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let start = detachedResizeStart ?? (
                    size: state.detachedGraphSize,
                    topLeft: CGPoint(x: currentCenter.x - state.detachedGraphSize.width / 2, y: currentCenter.y - state.detachedGraphSize.height / 2)
                )
                if detachedResizeStart == nil { detachedResizeStart = start }
                let proposed = CGSize(width: start.size.width + value.translation.width, height: start.size.height + value.translation.height)
                let clamped = clampGraphSize(proposed, in: containerSize)
                let center = clamp(
                    center: CGPoint(x: start.topLeft.x + clamped.width / 2, y: start.topLeft.y + clamped.height / 2),
                    size: clamped,
                    in: containerSize
                )
                setWithoutAnimation {
                    detachedResizeLive = (size: clamped, center: center)
                }
            }
            .onEnded { _ in
                if let live = detachedResizeLive {
                    state.detachedGraphSize = live.size
                    state.detachedGraphPosition = live.center
                }
                detachedResizeLive = nil
                detachedResizeStart = nil
            }
    }

    private func detachedGraphCenter(size: CGSize, in containerSize: CGSize) -> CGPoint {
        let fallback = CGPoint(
            x: max(size.width / 2 + 16, containerSize.width * 0.34),
            y: max(size.height / 2 + 24, containerSize.height * 0.38)
        )
        return clamp(center: state.detachedGraphPosition ?? fallback, size: size, in: containerSize)
    }

    private func detachedControlCenter(size: CGSize, in containerSize: CGSize) -> CGPoint {
        let fallback = CGPoint(
            x: min(containerSize.width - size.width / 2 - 16, containerSize.width * 0.74),
            y: max(size.height / 2 + 24, containerSize.height * 0.54)
        )
        return clamp(center: state.detachedControlPosition ?? fallback, size: size, in: containerSize)
    }

    private func clampGraphSize(_ size: CGSize, in containerSize: CGSize) -> CGSize {
        CGSize(
            width: min(max(size.width, 300), max(300, containerSize.width - 24)),
            height: min(max(size.height, 240), max(240, containerSize.height - 24))
        )
    }

    private func clamp(center: CGPoint, size: CGSize, in containerSize: CGSize) -> CGPoint {
        let halfW = size.width / 2
        let halfH = size.height / 2
        guard containerSize.width >= size.width, containerSize.height >= size.height else {
            return CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)
        }
        return CGPoint(
            x: min(max(center.x, halfW), containerSize.width - halfW),
            y: min(max(center.y, halfH), containerSize.height - halfH)
        )
    }

    private func setWithoutAnimation(_ updates: () -> Void) {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction, updates)
    }

    private func isDragging(_ kind: GraphCalculatorDragKind) -> Bool {
        dragProxy?.kind == kind
    }
}

private struct GraphCalculatorDragProxy: Equatable {
    let kind: GraphCalculatorDragKind
    let title: String
    let systemImage: String
    let center: CGPoint
    let offset: CGSize
    let size: CGSize

    var headerHeight: CGFloat {
        kind == .detachedGraph ? 42 : 58
    }

    var cornerRadius: CGFloat {
        kind == .detachedGraph ? 12 : 24
    }

    var headerFill: Color {
        switch kind {
        case .detachedGraph:
            return Color.white
        case .docked, .detachedControl:
            return GraphCalculatorTheme.header
        }
    }

    var bodyFill: Color {
        switch kind {
        case .detachedGraph:
            return Color.white.opacity(0.86)
        case .docked, .detachedControl:
            return GraphCalculatorTheme.panel.opacity(0.86)
        }
    }

    var stroke: Color {
        switch kind {
        case .detachedGraph:
            return Color.black.opacity(0.35)
        case .docked, .detachedControl:
            return Color.white.opacity(0.32)
        }
    }

    var headerForeground: Color {
        kind == .detachedGraph ? Color.black.opacity(0.78) : Color.white.opacity(0.92)
    }

    var labelForeground: Color {
        kind == .detachedGraph ? Color.black.opacity(0.45) : Color.white.opacity(0.58)
    }
}

private enum GraphCalculatorDragKind: Equatable {
    case docked
    case detachedGraph
    case detachedControl
}

private enum GraphCalculatorTheme {
    static let header = Color(red: 0.16, green: 0.16, blue: 0.16)
    static let panel = Color(red: 0.07, green: 0.075, blue: 0.08)
    static let toolbar = Color(red: 0.94, green: 0.94, blue: 0.93)
    static let keypad = Color(red: 0.90, green: 0.90, blue: 0.89)
    static let blue = Color(red: 0.19, green: 0.47, blue: 0.86)
}

private struct FunctionMenuItem: Equatable {
    let label: String
    let insertion: String
}

private enum FunctionMenuCategory: CaseIterable {
    case basic
    case trig
    case stats
    case algebra

    var title: String {
        switch self {
        case .basic: return "Basic"
        case .trig: return "Trig"
        case .stats: return "Stats"
        case .algebra: return "Alg 2"
        }
    }

    var items: [FunctionMenuItem] {
        switch self {
        case .basic:
            return [
                FunctionMenuItem(label: "sqrt", insertion: "sqrt("),
                FunctionMenuItem(label: "abs", insertion: "abs("),
                FunctionMenuItem(label: "log", insertion: "log("),
                FunctionMenuItem(label: "ln", insertion: "ln("),
                FunctionMenuItem(label: "π", insertion: "pi"),
                FunctionMenuItem(label: "e", insertion: "e"),
                FunctionMenuItem(label: "min", insertion: "min("),
                FunctionMenuItem(label: "max", insertion: "max(")
            ]
        case .trig:
            return [
                FunctionMenuItem(label: "sin", insertion: "sin("),
                FunctionMenuItem(label: "cos", insertion: "cos("),
                FunctionMenuItem(label: "tan", insertion: "tan("),
                FunctionMenuItem(label: "sin⁻¹", insertion: "asin("),
                FunctionMenuItem(label: "cos⁻¹", insertion: "acos("),
                FunctionMenuItem(label: "tan⁻¹", insertion: "atan("),
                FunctionMenuItem(label: "sec", insertion: "sec("),
                FunctionMenuItem(label: "csc", insertion: "csc(")
            ]
        case .stats:
            return [
                FunctionMenuItem(label: "point", insertion: "(,)"),
                FunctionMenuItem(label: "table", insertion: ""),
                FunctionMenuItem(label: "min", insertion: "min("),
                FunctionMenuItem(label: "max", insertion: "max("),
                FunctionMenuItem(label: "round", insertion: "round("),
                FunctionMenuItem(label: "floor", insertion: "floor("),
                FunctionMenuItem(label: "ceil", insertion: "ceil("),
                FunctionMenuItem(label: "mod", insertion: "mod(")
            ]
        case .algebra:
            return [
                FunctionMenuItem(label: "line", insertion: "y=mx+b"),
                FunctionMenuItem(label: "quad", insertion: "y=ax^2+bx+c"),
                FunctionMenuItem(label: "cubic", insertion: "y=ax^3+bx^2+cx+d"),
                FunctionMenuItem(label: "vertex", insertion: "y=a(x-h)^2+k"),
                FunctionMenuItem(label: "expo", insertion: "y=ab^x"),
                FunctionMenuItem(label: "root", insertion: "root("),
                FunctionMenuItem(label: "logb", insertion: "log(,)"),
                FunctionMenuItem(label: "piece", insertion: "{")
            ]
        }
    }
}

private enum GraphCalculatorExpressionDisplay {
    static func string(for source: String) -> String {
        var display = superscriptExponents(in: source)
        display = display.replacingOccurrences(of: "()/()", with: "□⁄□")
        display = display.replacingOccurrences(of: "sqrt(", with: "√(")
        display = display.replacingOccurrences(of: "theta", with: "θ")
        display = display.replacingOccurrences(of: "pi", with: "π")
        display = display.replacingOccurrences(of: "<=", with: "≤")
        display = display.replacingOccurrences(of: ">=", with: "≥")
        display = display.replacingOccurrences(of: "*", with: "×")
        display = display.replacingOccurrences(of: "/", with: "⁄")
        return display
    }

    static func variableName(for source: String) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let cleaned = trimmed.replacingOccurrences(of: "_", with: "")
        let suffix = cleaned.reversed().prefix { $0.isNumber }.reversed()
        guard !suffix.isEmpty else { return trimmed }
        let prefix = cleaned.dropLast(suffix.count)
        return String(prefix) + subscriptText(String(suffix))
    }

    private static func superscriptExponents(in source: String) -> String {
        var output = ""
        var index = source.startIndex

        while index < source.endIndex {
            guard source[index] == "^" else {
                output.append(source[index])
                index = source.index(after: index)
                continue
            }

            let next = source.index(after: index)
            guard next < source.endIndex else {
                output.append("^")
                index = next
                continue
            }

            if source[next] == "(",
               let close = matchingCloseParen(in: source, openIndex: next) {
                let exponent = String(source[source.index(after: next)..<close])
                output += superscript("(\(exponent))")
                index = source.index(after: close)
            } else {
                var exponent = ""
                var scan = next
                while scan < source.endIndex, isExponentCharacter(source[scan], position: exponent.count) {
                    exponent.append(source[scan])
                    scan = source.index(after: scan)
                }
                if exponent.isEmpty {
                    output.append("^")
                    index = next
                } else {
                    output += superscript(exponent)
                    index = scan
                }
            }
        }

        return output
    }

    private static func matchingCloseParen(in source: String, openIndex: String.Index) -> String.Index? {
        var depth = 0
        var index = openIndex
        while index < source.endIndex {
            if source[index] == "(" {
                depth += 1
            } else if source[index] == ")" {
                depth -= 1
                if depth == 0 { return index }
            }
            index = source.index(after: index)
        }
        return nil
    }

    private static func isExponentCharacter(_ character: Character, position: Int) -> Bool {
        character.isNumber || (position == 0 && (character == "-" || character == "+"))
    }

    private static func superscript(_ value: String) -> String {
        value.map { character in
            switch character {
            case "0": return "⁰"
            case "1": return "¹"
            case "2": return "²"
            case "3": return "³"
            case "4": return "⁴"
            case "5": return "⁵"
            case "6": return "⁶"
            case "7": return "⁷"
            case "8": return "⁸"
            case "9": return "⁹"
            case "+": return "⁺"
            case "-": return "⁻"
            case "(": return "⁽"
            case ")": return "⁾"
            default: return String(character)
            }
        }.joined()
    }

    private static func subscriptText(_ value: String) -> String {
        value.map { character in
            switch character {
            case "0": return "₀"
            case "1": return "₁"
            case "2": return "₂"
            case "3": return "₃"
            case "4": return "₄"
            case "5": return "₅"
            case "6": return "₆"
            case "7": return "₇"
            case "8": return "₈"
            case "9": return "₉"
            default: return String(character)
            }
        }.joined()
    }
}

private enum GraphCalculatorVariableScanner {
    static func sliderNames(in sources: [String]) -> [String] {
        var names: Set<String> = []
        let functionDefinitions = sources.compactMap(FunctionSignature.init(source:))
        let functionNames = Set(functionDefinitions.map(\.name))
        let inputVariables = Set(functionDefinitions.map(\.variable))
        let calledFunctionNames = Set(sources.flatMap(functionCallNames(in:))

        )

        for source in sources {
            guard let scanSource = sliderEligibleExpressionBody(in: source) else { continue }
            for identifier in identifiers(in: scanSource)
            where isSliderCandidate(
                identifier,
                functionNames: functionNames,
                inputVariables: inputVariables,
                calledFunctionNames: calledFunctionNames
            ) {
                names.insert(identifier)
            }
        }
        return names.sorted()
    }

    private static func sliderEligibleExpressionBody(in source: String) -> String? {
        if let function = FunctionSignature(source: source) {
            return function.body
        }

        let compact = source.replacingOccurrences(of: " ", with: "")
        guard let relation = firstRelationRange(in: compact) else { return nil }
        let left = String(compact[..<relation.lowerBound])
        let right = String(compact[relation.upperBound...])
        if left == "y", !right.isEmpty {
            return right
        }
        if right == "y", !left.isEmpty {
            return left
        }
        return nil
    }

    private static func firstRelationRange(in source: String) -> Range<String.Index>? {
        ["<=", "≥", "≤", ">=", "<", ">", "="]
            .compactMap { source.range(of: $0) }
            .min { $0.lowerBound < $1.lowerBound }
    }

    private static func identifiers(in source: String) -> [String] {
        var identifiers: [String] = []
        var current = ""

        func flushCurrent() {
            guard !current.isEmpty else { return }
            let lower = current.lowercased()
            if reservedFunctionNames.contains(lower) || lower.count == 1 {
                identifiers.append(lower)
            } else {
                identifiers.append(contentsOf: lower.map(String.init))
            }
            current = ""
        }

        for character in source {
            if character.isLetter {
                current.append(character)
            } else {
                flushCurrent()
            }
        }

        flushCurrent()

        return identifiers
    }

    private static func functionCallNames(in source: String) -> [String] {
        let compact = source.replacingOccurrences(of: " ", with: "")
        var names: [String] = []
        var index = compact.startIndex

        while index < compact.endIndex {
            let character = compact[index]
            if character.isLetter,
               let next = compact.index(index, offsetBy: 1, limitedBy: compact.endIndex),
               next < compact.endIndex,
               compact[next] == "(" {
                names.append(String(character).lowercased())
            }
            index = compact.index(after: index)
        }

        return names
    }

    private static func isSliderCandidate(
        _ identifier: String,
        functionNames: Set<String>,
        inputVariables: Set<String>,
        calledFunctionNames: Set<String>
    ) -> Bool {
        // Note: single letters like f/g/h are NOT blanket-reserved here — when they are actually
        // used as functions they are already excluded via functionNames / inputVariables /
        // calledFunctionNames, so a bare `h` used as a value stays slider-eligible.
        let reserved = Set(["x", "y", "pi", "e"]).union(reservedFunctionNames)
        return identifier.count == 1
            && !reserved.contains(identifier)
            && !functionNames.contains(identifier)
            && !inputVariables.contains(identifier)
            && !calledFunctionNames.contains(identifier)
    }

    private static let reservedFunctionNames: Set<String> = [
        "sin", "cos", "tan", "asin", "acos", "atan",
        "sqrt", "abs", "log", "ln", "min", "max"
    ]

    private struct FunctionSignature {
        let name: String
        let variable: String
        let body: String

        init?(source: String) {
            let trimmed = source.replacingOccurrences(of: " ", with: "")
            guard trimmed.count >= 6,
                  let equals = trimmed.firstIndex(of: "="),
                  let openParen = trimmed.firstIndex(of: "("),
                  let closeParen = trimmed.firstIndex(of: ")"),
                  openParen < closeParen,
                  closeParen < equals else {
                return nil
            }

            let name = String(trimmed[..<openParen]).lowercased()
            let variable = String(trimmed[trimmed.index(after: openParen)..<closeParen]).lowercased()
            let body = String(trimmed[trimmed.index(after: equals)...])

            guard name.count == 1,
                  name.first?.isLetter == true,
                  name != "y",
                  variable.count == 1,
                  variable.first?.isLetter == true,
                  !body.isEmpty else {
                return nil
            }

            self.name = name
            self.variable = variable
            self.body = body
        }
    }

    private struct ScalarSignature {
        let name: String
        let body: String

        init?(source: String) {
            let trimmed = source.replacingOccurrences(of: " ", with: "")
            guard !trimmed.contains("("),
                  let equals = trimmed.firstIndex(of: "=") else {
                return nil
            }

            let name = String(trimmed[..<equals]).lowercased()
            let body = String(trimmed[trimmed.index(after: equals)...])
            guard name.count == 1,
                  name.first?.isLetter == true,
                  !["x", "y"].contains(name),
                  !body.isEmpty else {
                return nil
            }

            self.name = name
            self.body = body
        }
    }
}

private struct ResizeGrip: View {
    var body: some View {
        Canvas { context, size in
            for fraction in [0.45, 0.68, 0.9] as [CGFloat] {
                var path = Path()
                path.move(to: CGPoint(x: size.width * fraction, y: size.height))
                path.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                context.stroke(path, with: .color(.black.opacity(0.48)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
    }
}

private struct SliderBoundEdit: Identifiable, Equatable {
    enum Endpoint {
        case minimum
        case maximum
    }

    let name: String
    let endpoint: Endpoint

    var id: String {
        "\(name)-\(endpoint)"
    }

    var title: String {
        endpoint == .minimum ? "\(name) minimum" : "\(name) maximum"
    }
}

#if DEBUG
#Preview("Graph Calculator") {
    GraphCalculatorView.preview()
}

#Preview("Detached Graph Calculator") {
    GraphCalculatorView(
        state: {
            let state = GraphCalculatorState(expressions: [GraphEquation(expression: "f(x)=x^2-4", colorIndex: 0)])
            state.isGraphDetached = true
            return state
        }()
    )
    .frame(width: 900, height: 820)
    .padding()
    .background(Color(white: 0.93))
}
#endif
