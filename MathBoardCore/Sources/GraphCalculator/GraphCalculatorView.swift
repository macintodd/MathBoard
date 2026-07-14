//
//  GraphCalculatorView.swift
//  MathBoardCore - GraphCalculator module
//
//  Isolated Desmos-style teaching calculator prototype.
//

import SwiftUI
import Calculator
@_spi(Textual) import SwiftUIMath
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public struct GraphCalculatorSnapshot: Sendable, Equatable {
    public var pngData: Data
    public var size: CGSize
    public var placementRect: CGRect?
    public var containerSize: CGSize?

    public init(
        pngData: Data,
        size: CGSize,
        placementRect: CGRect? = nil,
        containerSize: CGSize? = nil
    ) {
        self.pngData = pngData
        self.size = size
        self.placementRect = placementRect
        self.containerSize = containerSize
    }
}

public struct GraphCalculatorView: View {
    @Bindable private var state: GraphCalculatorState
    private let onGraphSnapshot: (@MainActor (GraphCalculatorSnapshot) -> Void)?

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
    @State private var swatchActionExpressionIndex: Int?
    @State private var isAlphabetKeypadVisible: Bool = false
    @State private var editingSliderBound: SliderBoundEdit?
    @State private var editingSliderBoundText: String = ""
    @State private var editingSliderBoundReplacesOnInput: Bool = false
    @State private var editingPointCell: PointTableCellEdit?
    @State private var editingPointCellText: String = ""
    @State private var editingPointCellReplacesOnInput: Bool = false
    @State private var playingSliders: Set<String> = []
    @State private var sliderPlayDirections: [String: Double] = [:]
    @State private var sliderPlaybackTask: Task<Void, Never>?
    @State private var keypadHiddenEntryExtra: CGFloat = 260
    @State private var keypadVisibleEntryExtra: CGFloat = 0
    @State private var entryResizeStartExtra: CGFloat?
    @State private var entryResizeStartCenter: CGPoint?
    @State private var entryResizeLive: (extra: CGFloat, center: CGPoint)?
    @State private var tableDragStartCenter: CGPoint?
    @State private var tableResizeStart: (size: CGSize, topLeft: CGPoint)?
    @State private var tableResizeLive: (size: CGSize, center: CGPoint)?
    @State private var isTableSettingsPresented: Bool = false
    @State private var isCalculatorMenuPresented: Bool = false
    @State private var keystrokeWindowDragStart: CGPoint?
    @State private var keystrokeWindowResizeStart: (size: CGSize, topLeft: CGPoint)?
    @State private var keystrokeWindowResizeLive: (size: CGSize, center: CGPoint)?
    @State private var didApplyInitialWindow = false
    @State private var currentGraphPlotSize: CGSize = CGSize(width: 400, height: 400)
    @State private var fractionCursorExitedAt: Int?

    private let engine = CalculatorEngine()
    private let minimumGraphSpan: Double = 0.02
    private let maximumGraphSpan: Double = 2400
    private let keypadHeight: CGFloat = 180
    private let expandedHeaderHeight: CGFloat = 58
    private let compactHeaderHeight: CGFloat = 18
    private let expandedFloatingHeaderHeight: CGFloat = 42
    private let preferredDockedGraphHeight: CGFloat = 440
    private let baseEntryHeight: CGFloat = 58
    private let baseDetachedEntryHeight: CGFloat = 170
    private let entryHandleHeight: CGFloat = 22
    private let visibleTraceTableRows = 10
    private let preferredTraceSlotRange = 4...6
    private let preferredTraceSlotIndex = 5

    public init(
        state: GraphCalculatorState = GraphCalculatorState(),
        onGraphSnapshot: (@MainActor (GraphCalculatorSnapshot) -> Void)? = nil
    ) {
        self.state = state
        self.onGraphSnapshot = onGraphSnapshot
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
                    let layout = dockedCalculatorLayout(in: proxy.size)
                    calculatorBody(in: proxy.size)
                        .frame(width: layout.size.width, height: layout.size.height)
                        .position(layout.center)
                        .opacity(isDragging(.docked) ? 0.14 : 1)
                }

                tableWindow(in: proxy.size)

                if state.isKeystrokeDisplayEnabled {
                    keystrokeWindow(in: proxy.size)
                }

                if let dragProxy {
                    dragProxyView(dragProxy)
                        .frame(width: dragProxy.size.width, height: dragProxy.size.height)
                        .position(dragProxy.center)
                        .offset(dragProxy.offset)
                        .allowsHitTesting(false)
                } else if let dragPresentation = state.activeDragPresentation {
                    dragProxyView(GraphCalculatorDragProxy(presentation: dragPresentation))
                        .frame(width: dragPresentation.size.width, height: dragPresentation.size.height)
                        .position(dragPresentation.center)
                        .offset(dragPresentation.offset)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: state.isGraphDetached)
            .onDisappear {
                sliderPlaybackTask?.cancel()
                sliderPlaybackTask = nil
            }
            .onAppear {
                applyInitialGraphWindowIfNeeded()
            }
        }
    }

    private func calculatorBody(in containerSize: CGSize) -> some View {
        let layout = dockedCalculatorLayout(in: containerSize)
        let size = layout.size
        let center = layout.center
        let graphHeight = dockedGraphHeight(in: containerSize)
        let placementRect = CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )

        return VStack(spacing: 0) {
            calculatorTopBar(.docked)
                .gesture(dockedCalculatorDragGesture(currentCenter: center, size: size, expandedSize: layout.expandedSize, in: containerSize))
            if !state.isDockedHeaderCollapsed {
                graphRegion(placementRect: placementRect, containerSize: containerSize)
                    .frame(height: graphHeight)
                graphToolbar(placementRect: placementRect, containerSize: containerSize)
                entryPanel
                    .frame(height: dockedEntryHeight)
                    .overlay(alignment: .bottom) {
                        if state.isKeypadCollapsed {
                            entryResizeHandle()
                        }
                    }
                keypad
                    .frame(height: state.isKeypadCollapsed ? 0 : keypadHeight)
                    .clipped()
            }
        }
        .background(GraphCalculatorTheme.panel, in: Rectangle())
        .overlay(Rectangle().strokeBorder(.black.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        .compositingGroup()
    }

    private func calculatorTopBar(_ kind: CalculatorHeaderKind) -> some View {
        let isCollapsed = isCalculatorHeaderCollapsed(kind)
        return Group {
            if isCollapsed {
                collapsedDragBar(tint: .white.opacity(0.74), background: GraphCalculatorTheme.header) {
                    setCalculatorHeaderCollapsed(false, kind: kind)
                }
                .frame(height: compactHeaderHeight)
            } else {
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

                }
                .padding(.horizontal, 14)
                .frame(height: expandedHeaderHeight)
                .background(GraphCalculatorTheme.header)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    setCalculatorHeaderCollapsed(true, kind: kind)
                }
            }
        }
    }

    private var calculatorMenu: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Graph Display")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.black.opacity(0.82))

            graphSettingSlider(
                title: "Axis boldness",
                value: $state.axisStrokeWidth,
                range: 0.5...5,
                display: String(format: "%.1f", state.axisStrokeWidth)
            )

            graphSettingSlider(
                title: "Grid darkness",
                value: $state.gridlineOpacity,
                range: 0.08...0.75,
                display: String(format: "%.2f", state.gridlineOpacity)
            )

            Toggle(isOn: Binding(
                get: { state.isKeystrokeDisplayEnabled },
                set: { isEnabled in
                    state.isKeystrokeDisplayEnabled = isEnabled
                    if isEnabled {
                        state.isKeystrokeRecordingPaused = false
                    }
                }
            )) {
                Text("Display keystrokes")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.black.opacity(0.8))
            }
            .tint(GraphCalculatorTheme.blue)
        }
        .padding(16)
        .frame(width: 300)
        .background(Color.white)
    }

    private func graphRegion(placementRect: CGRect?, containerSize: CGSize?) -> some View {
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
                graphCanvas(keepsSquarePlot: true)
            }
        }
        .overlay(alignment: .topTrailing) {
            graphControlOverlay(placementRect: placementRect, containerSize: containerSize)
        }
        .overlay(alignment: .bottomTrailing) {
            graphIconButton("eject.fill", style: .destructive) { ejectGraph() }
                .padding(10)
        }
    }

    private func graphCanvas(keepsSquarePlot: Bool) -> some View {
        GeometryReader { proxy in
            let plotSize = keepsSquarePlot
                ? CGSize(width: min(proxy.size.width, proxy.size.height), height: min(proxy.size.width, proxy.size.height))
                : proxy.size
            Canvas { context, size in
                drawGraph(in: context, size: size)
            }
            .frame(width: plotSize.width, height: plotSize.height)
            .background(state.isHandDrawnStyle ? GraphPaperPalette.paper : Color.white)
            .contentShape(Rectangle())
            .gesture(graphPanGesture(size: plotSize))
            .simultaneousGesture(graphMagnifyGesture(size: plotSize))
            .simultaneousGesture(graphTapGesture(size: plotSize))
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(state.isHandDrawnStyle ? GraphPaperPalette.paper : Color.white)
            .onAppear {
                currentGraphPlotSize = plotSize
            }
            .onChange(of: plotSize) { _, newValue in
                currentGraphPlotSize = newValue
            }
        }
    }

    private func drawGraph(in context: GraphicsContext, size: CGSize) {
        GraphCalculatorRenderer.draw(
            in: context,
            size: size,
            window: state.graphWindow,
            expressions: state.expressions,
            engine: engine,
            variableValues: graphVariableValues,
            accent: GraphCalculatorTheme.blue,
            axisStyle: GraphAxisStyle(
                axisStrokeWidth: CGFloat(state.axisStrokeWidth),
                gridlineThickness: CGFloat(state.gridlineThickness),
                gridlineOpacity: CGFloat(state.gridlineOpacity),
                showGrid: state.isGridVisible,
                xAxisLabel: state.xAxisLabel,
                yAxisLabel: state.yAxisLabel,
                handDrawn: state.isHandDrawnStyle
            ),
            highlightedPoint: state.selectedPoint,
            attachedPoints: attachedPointSets,
            trace: traceOverlay
        )
    }

    private func graphSnapshotView(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            drawGraph(in: context, size: canvasSize)
        }
        .frame(width: size.width, height: size.height)
        .background(state.isHandDrawnStyle ? GraphPaperPalette.paper : Color.white)
        .overlay(alignment: .topLeading) {
            detachedGraphEquationOverlay
        }
        .overlay(Rectangle().strokeBorder(Color.black, lineWidth: 1))
    }

    private func captureGraphSnapshot(placementRect: CGRect?, containerSize: CGSize?) {
        guard let onGraphSnapshot else { return }
        #if os(iOS)
        let side = max(1, min(currentGraphPlotSize.width, currentGraphPlotSize.height).rounded())
        let size = CGSize(width: side, height: side)
        let renderer = ImageRenderer(content: graphSnapshotView(size: size))
        renderer.scale = 3
        guard let image = renderer.uiImage,
              let pngData = image.pngData() else {
            return
        }
        onGraphSnapshot(GraphCalculatorSnapshot(
            pngData: pngData,
            size: size,
            placementRect: placementRect,
            containerSize: containerSize
        ))
        #endif
    }

    private func graphToolbar(placementRect: CGRect? = nil, containerSize: CGSize? = nil) -> some View {
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
                Image(systemName: state.isKeypadCollapsed ? "keyboard.badge.eye" : "keyboard.badge.eye.fill")
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

    private var entryPanel: some View {
        VStack(spacing: 0) {
            if state.isAddMenuVisible {
                addMenuPanel
            } else if state.isFunctionMenuVisible {
                functionMenuPanel
            } else if state.isGraphSettingsVisible {
                graphSettingsPanel
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

    private var detachedVisibleEntryExtra: CGFloat {
        min(max(entryResizeLive?.extra ?? keypadVisibleEntryExtra, 0), keypadHeight)
    }

    private var detachedHiddenEntryExtra: CGFloat {
        min(max(entryResizeLive?.extra ?? keypadHiddenEntryExtra, 0), keypadHeight)
    }

    /// Grab handle at the entry panel edge. Dragging down expands the entry area; in detached mode
    /// the panel center shifts down by half the height change so the top edge stays fixed.
    private func entryResizeHandle(anchoredCenter: CGPoint? = nil, containerSize: CGSize? = nil) -> some View {
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
        .gesture(entryResizeGesture(isKeypadVisible: !state.isKeypadCollapsed, anchoredCenter: anchoredCenter, containerSize: containerSize))
    }

    private func entryResizeGesture(isKeypadVisible: Bool, anchoredCenter: CGPoint?, containerSize: CGSize?) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let start = entryResizeStartExtra ?? (isKeypadVisible ? keypadVisibleEntryExtra : keypadHiddenEntryExtra)
                if entryResizeStartExtra == nil {
                    entryResizeStartExtra = start
                    entryResizeStartCenter = anchoredCenter
                }
                let next = min(max(start + value.translation.height, 0), keypadHeight)

                if let startCenter = entryResizeStartCenter, containerSize != nil {
                    let delta = next - start
                    entryResizeLive = (
                        extra: next,
                        center: CGPoint(x: startCenter.x, y: startCenter.y + delta / 2)
                    )
                } else if isKeypadVisible {
                    keypadVisibleEntryExtra = next
                } else {
                    keypadHiddenEntryExtra = next
                }
            }
            .onEnded { _ in
                if let live = entryResizeLive {
                    if isKeypadVisible {
                        keypadVisibleEntryExtra = live.extra
                    } else {
                        keypadHiddenEntryExtra = live.extra
                    }
                    if let containerSize {
                        let size = CGSize(width: min(containerSize.width - 24, 440), height: min(containerSize.height - 24, detachedControlHeight))
                        state.detachedControlPosition = clamp(center: live.center, size: size, in: containerSize)
                    }
                }
                entryResizeLive = nil
                entryResizeStartExtra = nil
                entryResizeStartCenter = nil
            }
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
            insert(text)
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

    private func tableHeaderCell(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold, design: .serif))
            .foregroundStyle(.black.opacity(0.7))
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(Color.black.opacity(0.06))
            .overlay(Rectangle().stroke(.black.opacity(0.12), lineWidth: 0.5))
    }

    private func tableValueCell(_ text: String, highlightColor: Color? = nil) -> some View {
        let isHighlighted = highlightColor != nil
        let color = highlightColor ?? GraphCalculatorTheme.blue
        return Text(text)
            .font(.system(size: 18, weight: isHighlighted ? .semibold : .regular, design: .serif))
            .foregroundStyle(isHighlighted ? color : .black.opacity(0.82))
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(isHighlighted ? color.opacity(0.12) : Color.clear)
            .overlay(Rectangle().stroke(isHighlighted ? color.opacity(0.55) : .black.opacity(0.10), lineWidth: isHighlighted ? 1 : 0.5))
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

    /// Trace is active only while the open table is a function table and the trace toggle is on.
    private var isTracing: Bool {
        state.isTraceActive && state.activeTable?.kind == .function
    }

    /// The live trace overlay: the table-start anchor point plus a dot at each table row along the
    /// curve, all computed from the same start/delta the function table shows.
    private var traceOverlay: GraphTraceOverlay? {
        guard isTracing,
              let active = state.activeTable,
              let index = state.expressions.firstIndex(where: { $0.id == active.equationID }),
              let primary = functionTableDescriptor(for: active.equationID),
              let compiled = try? engine.compile(primary.source) else {
            return nil
        }

        let settings = state.functionTableSettings(for: active.equationID)
        let variables = graphVariableValues
        guard settings.delta != 0 else {
            return nil
        }

        let selectedX = state.traceSelectedX ?? settings.start
        guard let anchorY = evaluate(compiled: compiled, at: selectedX, variableValues: variables) else {
            return nil
        }
        let specialKind = traceSpecialKind(x: selectedX, y: anchorY)

        // Dots match the table rows currently visible on the calculator screen.
        var points: [GraphTracePoint] = []
        for n in 0..<visibleTraceTableRows {
            let x = settings.start + Double(n) * settings.delta
            if let y = evaluate(compiled: compiled, at: x, variableValues: variables) {
                points.append(GraphTracePoint(point: CGPoint(x: x, y: y), rowIndex: n))
            }
        }

        let width = CGFloat(state.expressions[index].lineWidth ?? GraphCalculatorStyleDefaults.lineWidth)
        let label = "\(primary.label)=\(CalculatorResultFormatter.string(for: anchorY))"
        let secondarySeries = secondaryTraceSeries(
            primaryID: active.equationID,
            selectedX: selectedX,
            settings: settings,
            variables: variables
        )
        return GraphTraceOverlay(
            anchor: CGPoint(x: selectedX, y: anchorY),
            points: points,
            color: graphColor(for: index),
            lineWidth: width,
            label: label,
            specialKind: specialKind,
            secondary: secondarySeries
        )
    }

    private func secondaryTraceSeries(
        primaryID: UUID,
        selectedX: Double,
        settings: GraphFunctionTableSettings,
        variables: [String: Double]
    ) -> GraphTraceSeries? {
        guard let secondary = secondaryFunctionTableDescriptor(for: primaryID),
              let compiled = try? engine.compile(secondary.source),
              let anchorY = evaluate(compiled: compiled, at: selectedX, variableValues: variables) else {
            return nil
        }

        var points: [GraphTracePoint] = []
        for n in 0..<visibleTraceTableRows {
            let x = settings.start + Double(n) * settings.delta
            if let y = evaluate(compiled: compiled, at: x, variableValues: variables) {
                points.append(GraphTracePoint(point: CGPoint(x: x, y: y), rowIndex: n))
            }
        }

        let width = state.expressions.indices.contains(secondary.index)
            ? CGFloat(state.expressions[secondary.index].lineWidth ?? GraphCalculatorStyleDefaults.lineWidth)
            : CGFloat(GraphCalculatorStyleDefaults.lineWidth)
        let label = "\(secondary.label)=\(CalculatorResultFormatter.string(for: anchorY))"
        return GraphTraceSeries(
            anchor: CGPoint(x: selectedX, y: anchorY),
            points: points,
            color: graphColor(for: secondary.index),
            lineWidth: width,
            label: label,
            specialKind: traceSpecialKind(x: selectedX, y: anchorY)
        )
    }

    /// Moves the trace when the touch is on a visible trace point or close to the curve.
    /// Returns false for off-curve drags so normal graph panning can continue.
    @discardableResult
    private func updateTrace(at viewPoint: CGPoint, size: CGSize) -> Bool {
        guard let active = state.activeTable,
              active.kind == .function,
              let source = functionTableSource(for: active.equationID),
              let compiled = try? engine.compile(source) else {
            return false
        }
        let settings = state.functionTableSettings(for: active.equationID)
        guard settings.delta != 0 else { return false }

        if let nearest = nearestTracePoint(to: viewPoint, size: size) {
            state.selectedPoint = nil
            selectVisibleTracePoint(nearest, settings: settings, equationID: active.equationID)
            return true
        }

        let graphX = CalculatorGraphGeometry.graphPoint(forView: viewPoint, window: state.graphWindow, size: size).x
        guard let graphY = evaluate(compiled: compiled, at: graphX, variableValues: graphVariableValues) else { return false }

        let curvePoint = CalculatorGraphGeometry.viewPoint(
            forGraph: CGPoint(x: graphX, y: graphY),
            window: state.graphWindow,
            size: size
        )
        guard curvePoint.x.isFinite,
              curvePoint.y.isFinite,
              hypot(curvePoint.x - viewPoint.x, curvePoint.y - viewPoint.y) <= interceptTapTolerance else {
            return false
        }

        let selectedX = snappedTraceStart(for: graphX, delta: settings.delta)
        state.selectedPoint = nil
        state.traceSelectedX = selectedX
        // A non-shown curve touch becomes the new first table value, matching the manual step precision.
        state.setFunctionTableStart(selectedX, for: active.equationID)
        return true
    }

    private func nearestTracePoint(to viewPoint: CGPoint, size: CGSize) -> (x: Double, rowIndex: Int)? {
        guard let points = traceOverlay?.points, !points.isEmpty else { return nil }
        var best: (x: Double, rowIndex: Int, distance: CGFloat)?

        for tracePoint in points {
            let screen = CalculatorGraphGeometry.viewPoint(forGraph: tracePoint.point, window: state.graphWindow, size: size)
            guard screen.x.isFinite, screen.y.isFinite else { continue }
            let distance = hypot(screen.x - viewPoint.x, screen.y - viewPoint.y)
            guard distance <= interceptTapTolerance else { continue }
            if best == nil || distance < best!.distance {
                best = (Double(tracePoint.point.x), tracePoint.rowIndex, distance)
            }
        }

        guard let best else { return nil }
        return (best.x, best.rowIndex)
    }

    private func selectVisibleTracePoint(
        _ point: (x: Double, rowIndex: Int),
        settings: GraphFunctionTableSettings,
        equationID: UUID
    ) {
        state.traceSelectedX = point.x
        guard !preferredTraceSlotRange.contains(point.rowIndex) else { return }
        let start = point.x - Double(preferredTraceSlotIndex) * settings.delta
        state.setFunctionTableStart(snappedTraceStart(for: start, delta: settings.delta), for: equationID)
    }

    private func traceSpecialKind(
        x: Double,
        y: Double
    ) -> GraphCalculatorPointReadout.Kind? {
        if abs(y) <= notablePointYTolerance {
            return .xIntercept
        }
        if abs(x) <= notablePointXTolerance {
            return .yIntercept
        }
        return isTracePointIntersection(x: x, y: y) ? .intersection : nil
    }

    private var notablePointXTolerance: Double {
        max(state.graphWindow.width * 1e-4, 1e-6)
    }

    private var notablePointYTolerance: Double {
        max(state.graphWindow.height * 1e-4, 1e-6)
    }

    private func isTracePointIntersection(x: Double, y: Double) -> Bool {
        let variables = graphVariableValues
        var matchingCurveCount = 0

        for row in resolvedRows {
            guard state.expressions.indices.contains(row.index),
                  let source = interceptSourceExpression(for: row.plot),
                  let compiled = try? engine.compile(source),
                  let value = evaluate(compiled: compiled, at: x, variableValues: variables),
                  abs(value - y) <= notablePointYTolerance else {
                continue
            }
            matchingCurveCount += 1
            if matchingCurveCount >= 2 {
                return true
            }
        }

        return false
    }

    private func snappedTraceStart(for x: Double, delta: Double) -> Double {
        let scale = pow(10, Double(decimalPlaces(for: delta)))
        return (x * scale).rounded() / scale
    }

    private func applyInitialGraphWindowIfNeeded() {
        guard !didApplyInitialWindow else { return }
        didApplyInitialWindow = true
        state.graphWindow = .default
    }

    private func decimalPlaces(for value: Double) -> Int {
        let text = String(format: "%.8f", abs(value))
            .trimmingCharacters(in: CharacterSet(charactersIn: "0"))
        guard let decimalIndex = text.firstIndex(of: ".") else { return 0 }
        return text.distance(from: text.index(after: decimalIndex), to: text.endIndex)
    }

    private var dockedHeaderHeight: CGFloat {
        state.isDockedHeaderCollapsed ? compactHeaderHeight : expandedHeaderHeight
    }

    private var detachedControlHeaderHeight: CGFloat {
        state.isDetachedControlHeaderCollapsed ? compactHeaderHeight : expandedHeaderHeight
    }

    private func isCalculatorHeaderCollapsed(_ kind: CalculatorHeaderKind) -> Bool {
        switch kind {
        case .docked:
            return state.isDockedHeaderCollapsed
        case .detachedControl:
            return state.isDetachedControlHeaderCollapsed
        }
    }

    private func setCalculatorHeaderCollapsed(_ isCollapsed: Bool, kind: CalculatorHeaderKind) {
        switch kind {
        case .docked:
            state.isDockedHeaderCollapsed = isCollapsed
        case .detachedControl:
            state.isDetachedControlHeaderCollapsed = isCollapsed
        }
    }

    private func collapsedDragBar(tint: Color, background: Color, onDoubleTap: @escaping () -> Void) -> some View {
        Rectangle()
            .fill(background)
            .overlay {
                Capsule()
                    .fill(tint)
                    .frame(width: 66, height: 4)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: onDoubleTap)
    }

    /// Teacher-added points (from point-row tables) prepared for the renderer, styled per owning row.
    private var attachedPointSets: [GraphAttachedPoints] {
        state.pointRows.compactMap { id, pairs in
            guard let index = state.expressions.firstIndex(where: { $0.id == id }) else { return nil }
            let points = pairs.compactMap { pair -> CGPoint? in
                guard let x = pair.x, let y = pair.y else { return nil }
                return CGPoint(x: x, y: y)
            }
            guard !points.isEmpty else { return nil }
            let width = CGFloat(state.expressions[index].lineWidth ?? GraphCalculatorStyleDefaults.lineWidth)
            return GraphAttachedPoints(points: points, color: graphColor(for: index), lineWidth: width)
        }
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
        let equationID = state.expressions.indices.contains(index) ? state.expressions[index].id : nil
        let formalFraction = formalFractionExpression(text)
        let fractionCandidate = fractionConversionCandidate(source: text, resolved: resolved)
        let isFractionResultShown = equationID.map { state.fractionResultRowIDs.contains($0) } ?? false
        let regressionRow = equationID.flatMap { state.regressionRows[$0] }
        let expressionTokens = editableExpressionTokens(for: text)
        let hasStackedMath = formalFraction != nil
            || (expressionTokens?.contains { token in
                if case .fraction = token { return true }
                return false
            } ?? false)
            || isFractionResultShown
        let baseRowHeight: CGFloat = promptNames.isEmpty ? (hasStackedMath ? 74 : 50) : 82
        let rowHeight: CGFloat = regressionRow == nil ? baseRowHeight : max(baseRowHeight, 72)
        let tableKind = tableKind(for: resolved?.plot)
        let hasExtraPoints = equationID.map { !state.extraPoints(for: $0).isEmpty } ?? false
        let completePointCount = equationID.map { completePointTablePoints(for: $0).count } ?? 0

        return HStack(spacing: 0) {
            expressionStyleCell(index: index, isSelected: isSelected, isInvalid: isInvalid, color: color)
                .frame(height: rowHeight)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            if isPureNumericCalculation(text), let displayValue {
                                numericExpressionLine(
                                    text: text,
                                    displayText: displayText,
                                    displayValue: displayValue,
                                    isSelected: isSelected,
                                    formalFraction: formalFraction,
                                    tokens: expressionTokens,
                                    fractionResult: isFractionResultShown ? fractionCandidate ?? numericValue(for: text).flatMap(rationalFraction(for:)) : nil
                                )
                            } else {
                                expressionText(text, displayText: displayText, isSelected: isSelected, formalFraction: formalFraction)
                                if let displayValue {
                                    Text("= \(displayValue)")
                                        .font(.system(size: 17, weight: .medium, design: .serif))
                                        .foregroundStyle(.black.opacity(0.62))
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
                    // A point row with attached table points shows an ellipsis to signal "more points".
                    if tableKind == .points, hasExtraPoints {
                        Text("…")
                            .font(.system(size: 20, weight: .semibold, design: .serif))
                            .foregroundStyle(.black.opacity(0.55))
                    }
                    if let equationID, canShowFractionButton(source: text, resolved: resolved, isFractionResultShown: isFractionResultShown) {
                        Button {
                            toggleFractionDisplay(index: index, equationID: equationID, candidate: fractionCandidate)
                        } label: {
                            Image(systemName: "textformat.123")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 26)
                                .background(
                                    fractionButtonColor(isFractionResultShown: isFractionResultShown, source: text),
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let regressionRow {
                    Text("R² = \(regressionCoefficientNumber(regressionRow.rSquared))")
                        .font(.system(size: 13, weight: .semibold, design: .serif))
                        .foregroundStyle(color.opacity(0.82))
                        .lineLimit(1)
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

            if let equationID, let tableKind {
                tableIconButton(equationID: equationID, kind: tableKind, rowHeight: rowHeight)
                if tableKind == .points, completePointCount >= 2 {
                    fitPointDataButton(equationID: equationID, rowHeight: rowHeight)
                }
                if tableKind == .points, canShowRegressionMenu(equationID: equationID) {
                    regressionMenuButton(equationID: equationID, sourceIndex: index, rowHeight: rowHeight)
                }
            }

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

    /// The kind of table a resolved row qualifies for, or nil if it does not get a table icon.
    /// Single-valued functions of x get a function table; ordered pairs get a points table.
    private func tableKind(for plot: GraphCalculatorPlot?) -> GraphActiveTable.Kind? {
        switch plot {
        case .curve, .yRelation(_, .equal):
            return .function
        case .point:
            return .points
        case .yRelation, .xRelation, .implicitRelation, .none:
            return nil
        }
    }

    /// The per-row table icon. Tapping it opens (or closes) that row's floating table window.
    private func tableIconButton(equationID: UUID, kind: GraphActiveTable.Kind, rowHeight: CGFloat) -> some View {
        let isOpen = state.activeTable?.equationID == equationID
        return Button {
            if editingPointCell != nil {
                finishPointCellEdit()
            }
            state.toggleTable(for: equationID, kind: kind)
            if kind == .points, state.activeTable?.equationID == equationID {
                preparePointTableForEntry(equationID: equationID)
            }
        } label: {
            Image(systemName: "tablecells")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(isOpen ? .white : GraphCalculatorTheme.blue)
                .frame(width: 40, height: 34)
                .background(
                    isOpen ? GraphCalculatorTheme.blue : GraphCalculatorTheme.blue.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(GraphCalculatorTheme.blue.opacity(isOpen ? 0 : 0.35), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .frame(height: rowHeight)
        .padding(.trailing, 2)
    }

    private func fitPointDataButton(equationID: UUID, rowHeight: CGFloat) -> some View {
        Button {
            zoomToDataPoints(equationID: equationID)
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(GraphCalculatorTheme.blue)
                .frame(width: 36, height: 34)
                .background(GraphCalculatorTheme.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(GraphCalculatorTheme.blue.opacity(0.30), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .frame(height: rowHeight)
        .padding(.trailing, 2)
    }

    private func regressionMenuButton(equationID: UUID, sourceIndex: Int, rowHeight: CGFloat) -> some View {
        Menu {
            Button("Linear") {
                insertRegression(.linear, equationID: equationID, after: sourceIndex)
            }
            let completePointCount = completePointTablePoints(for: equationID).count
            if completePointCount >= 3 {
                Button("Quadratic") {
                    insertRegression(.quadratic, equationID: equationID, after: sourceIndex)
                }
            }
            if completePointCount >= 4 {
                Button("Cubic") {
                    insertRegression(.cubic, equationID: equationID, after: sourceIndex)
                }
            }
            if completePointCount >= 5 {
                Button("Quartic") {
                    insertRegression(.quartic, equationID: equationID, after: sourceIndex)
                }
            }
        } label: {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(GraphCalculatorTheme.blue)
                .frame(width: 36, height: 34)
                .background(GraphCalculatorTheme.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(GraphCalculatorTheme.blue.opacity(0.30), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .frame(height: rowHeight)
        .padding(.trailing, 2)
    }

    private func toggleFractionDisplay(index: Int, equationID: UUID, candidate: RationalFraction?) {
        state.ensureExpression(at: index)
        state.selectExpression(at: index)
        let source = state.expressions[index].expression.trimmingCharacters(in: .whitespacesAndNewlines)
        if state.fractionResultRowIDs.contains(equationID) {
            state.fractionResultRowIDs.remove(equationID)
            return
        }
        if let formalFraction = formalFractionExpression(source),
           let value = numericValue(for: source) {
            let decimal = CalculatorResultFormatter.string(for: value)
            state.expressions[index].expression = decimal
            state.cursorOffset = decimal.count
            state.fractionResultRowIDs.remove(equationID)
            _ = formalFraction
            return
        }
        guard candidate != nil else { return }
        state.fractionResultRowIDs.insert(equationID)
        state.cursorOffset = state.expressions[index].expression.count
    }

    private func canShowFractionButton(
        source: String,
        resolved: GraphCalculatorResolvedRow?,
        isFractionResultShown: Bool
    ) -> Bool {
        isFractionResultShown
            || fractionConversionCandidate(source: source, resolved: resolved) != nil
            || formalFractionExpression(source.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }

    private func fractionButtonColor(isFractionResultShown: Bool, source: String) -> Color {
        if isFractionResultShown || formalFractionExpression(source.trimmingCharacters(in: .whitespacesAndNewlines)) != nil {
            return Color(red: 0.94, green: 0.58, blue: 0.16)
        }
        return GraphCalculatorTheme.blue
    }

    private func fractionConversionCandidate(source: String, resolved: GraphCalculatorResolvedRow?) -> RationalFraction? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard formalFractionExpression(trimmed) == nil,
              isPureNumericCalculation(trimmed),
              let value = numericValue(for: trimmed),
              hasRationalDecimalShape(source: trimmed, resolved: resolved) else {
            return nil
        }
        return rationalFraction(for: value)
    }

    private func hasRationalDecimalShape(source: String, resolved: GraphCalculatorResolvedRow?) -> Bool {
        if source.contains(".") { return true }
        guard let displayValue = resolved?.displayValue else { return false }
        return displayValue.contains(".") || displayValue.contains("−")
    }

    private func isPureNumericCalculation(_ source: String) -> Bool {
        guard !source.isEmpty else { return false }
        let allowed = CharacterSet(charactersIn: "0123456789.+-*/^() ")
        return source.unicodeScalars.allSatisfy { allowed.contains($0) }
            && !source.contains(",")
            && !source.contains("=")
    }

    private func numericValue(for source: String) -> Double? {
        guard let compiled = try? engine.compile(source),
              let value = try? engine.evaluate(compiled: compiled, angleMode: .radians, variables: [:]),
              value.isFinite else {
            return nil
        }
        return value
    }

    private func numericExpressionTokens(for source: String) -> [NumericExpressionToken]? {
        let compact = source.replacingOccurrences(of: " ", with: "")
        guard isPureNumericCalculation(compact), !compact.isEmpty else { return nil }
        var tokens: [NumericExpressionToken] = []
        var index = compact.startIndex

        func isOperatorBeforeFraction(_ character: Character) -> Bool {
            character == "+" || character == "-" || character == "*" || character == "/" || character == "^" || character == "("
        }

        while index < compact.endIndex {
            let character = compact[index]
            let isSignedNumber = (character == "-" || character == "+")
                && (index == compact.startIndex || isOperatorBeforeFraction(compact[compact.index(before: index)]))
                && compact.index(after: index) < compact.endIndex
                && compact[compact.index(after: index)].isNumber

            if character.isNumber || isSignedNumber {
                let start = index
                index = compact.index(after: index)
                while index < compact.endIndex, compact[index].isNumber {
                    index = compact.index(after: index)
                }

                if index < compact.endIndex, compact[index] == "/" {
                    let denominatorStart = compact.index(after: index)
                    var denominatorEnd = denominatorStart
                    while denominatorEnd < compact.endIndex, compact[denominatorEnd].isNumber {
                        denominatorEnd = compact.index(after: denominatorEnd)
                    }
                    if denominatorEnd > denominatorStart,
                       let numerator = Int(compact[start..<index]),
                       let denominator = Int(compact[denominatorStart..<denominatorEnd]),
                       denominator != 0 {
                        let normalized = normalizedFraction(numerator: numerator, denominator: denominator)
                        tokens.append(.fraction(normalized))
                        index = denominatorEnd
                        continue
                    }
                }

                tokens.append(.text(GraphCalculatorExpressionDisplay.string(for: String(compact[start..<index]))))
                continue
            }

            tokens.append(.text(GraphCalculatorExpressionDisplay.string(for: String(character))))
            index = compact.index(after: index)
        }

        return tokens
    }

    private func normalizedFraction(numerator: Int, denominator: Int) -> RationalFraction {
        let divisor = greatestCommonDivisor(abs(numerator), abs(denominator))
        let normalizedSign = denominator < 0 ? -1 : 1
        return RationalFraction(
            numerator: normalizedSign * numerator / divisor,
            denominator: abs(denominator) / divisor
        )
    }

    private func editableExpressionTokens(for source: String) -> [EditableExpressionToken]? {
        guard source.contains("/") else { return nil }
        let characters = Array(source)
        var tokens: [EditableExpressionToken] = []
        var scanIndex = 0
        var textStart = 0

        while scanIndex < characters.count {
            guard characters[scanIndex] == "/" else {
                scanIndex += 1
                continue
            }

            let fraction = editableFractionToken(aroundSlashAt: scanIndex, in: characters)
            if textStart < fraction.sourceRange.lowerBound {
                tokens.append(.text(String(characters[textStart..<fraction.sourceRange.lowerBound])))
            }
            tokens.append(.fraction(fraction))
            scanIndex = max(fraction.sourceRange.upperBound, scanIndex + 1)
            textStart = scanIndex
        }

        if textStart < characters.count {
            tokens.append(.text(String(characters[textStart..<characters.count])))
        }

        return tokens.isEmpty ? nil : tokens
    }

    private func editableFractionToken(aroundSlashAt slashOffset: Int, in characters: [Character]) -> EditableFractionToken {
        let numeratorBounds = numeratorBounds(beforeSlashAt: slashOffset, in: characters)
        let denominatorBounds = denominatorBounds(afterSlashAt: slashOffset, in: characters)
        return EditableFractionToken(
            numerator: String(characters[numeratorBounds.displayRange]),
            denominator: String(characters[denominatorBounds]),
            numeratorRange: numeratorBounds.editRange,
            denominatorRange: denominatorBounds,
            slashOffset: slashOffset,
            sourceRange: numeratorBounds.sourceRange.lowerBound..<denominatorBounds.upperBound
        )
    }

    private func numeratorBounds(
        beforeSlashAt slashOffset: Int,
        in characters: [Character]
    ) -> (sourceRange: Range<Int>, displayRange: Range<Int>, editRange: Range<Int>) {
        guard slashOffset > 0 else {
            return (slashOffset..<slashOffset, slashOffset..<slashOffset, slashOffset..<slashOffset)
        }

        if isFractionBoundaryOperator(characters[slashOffset - 1]) {
            return (slashOffset..<slashOffset, slashOffset..<slashOffset, slashOffset..<slashOffset)
        }

        if characters[slashOffset - 1] == ")",
           let openParen = matchingOpenParen(before: slashOffset - 1, in: characters) {
            let functionStart = functionIdentifierStart(before: openParen, in: characters) ?? openParen
            if functionStart < openParen {
                return (
                    functionStart..<slashOffset,
                    functionStart..<slashOffset,
                    functionStart..<slashOffset
                )
            }
            return (
                openParen..<slashOffset,
                min(openParen + 1, slashOffset)..<max(openParen + 1, slashOffset - 1),
                min(openParen + 1, slashOffset)..<max(openParen + 1, slashOffset - 1)
            )
        }

        var start = slashOffset - 1
        var depth = 0
        while start > 0 {
            let previousIndex = start - 1
            let character = characters[previousIndex]
            if character == ")" {
                depth += 1
            } else if character == "(" {
                if depth == 0 { break }
                depth -= 1
            } else if depth == 0 && isFractionBoundaryOperator(character) {
                break
            }
            start = previousIndex
        }

        return (start..<slashOffset, start..<slashOffset, start..<slashOffset)
    }

    private func denominatorBounds(afterSlashAt slashOffset: Int, in characters: [Character]) -> Range<Int> {
        let start = min(slashOffset + 1, characters.count)
        var end = start
        var depth = 0

        while end < characters.count {
            let character = characters[end]
            if character == "(" {
                depth += 1
            } else if character == ")" {
                if depth == 0 { break }
                depth -= 1
            } else if depth == 0 && isFractionBoundaryOperator(character) {
                break
            }
            end += 1
        }

        return start..<end
    }

    private func functionIdentifierStart(before openParenIndex: Int, in characters: [Character]) -> Int? {
        guard openParenIndex > 0 else { return nil }
        var start = openParenIndex
        while start > 0, characters[start - 1].isLetter {
            start -= 1
        }
        guard start < openParenIndex else { return nil }
        return start
    }

    private func matchingOpenParen(before closeParenIndex: Int, in characters: [Character]) -> Int? {
        var depth = 0
        var index = closeParenIndex
        while index >= 0 {
            let character = characters[index]
            if character == ")" {
                depth += 1
            } else if character == "(" {
                depth -= 1
                if depth == 0 { return index }
            }
            index -= 1
        }
        return nil
    }

    private func isFractionBoundaryOperator(_ character: Character) -> Bool {
        character == "+" || character == "-" || character == "*" || character == "=" || character == "," || character == "<" || character == ">"
    }

    private func displayString(_ characters: [Character], in range: Range<Int>) -> String {
        guard range.lowerBound >= 0,
              range.upperBound <= characters.count,
              range.lowerBound <= range.upperBound else {
            return ""
        }
        return GraphCalculatorExpressionDisplay.string(for: String(characters[range]))
    }

    private func rationalFraction(for value: Double) -> RationalFraction? {
        let maxDenominator = 10_000
        let sign = value < 0 ? -1 : 1
        let target = abs(value)
        guard abs(target.rounded() - target) > 1e-10 else { return nil }

        var lowerN = 0
        var lowerD = 1
        var upperN = 1
        var upperD = 0

        while true {
            let middleN = lowerN + upperN
            let middleD = lowerD + upperD
            guard middleD <= maxDenominator else { break }
            let middle = Double(middleN) / Double(middleD)
            if abs(middle - target) <= 1e-10 {
                return RationalFraction(numerator: sign * middleN, denominator: middleD)
            }
            if middle < target {
                lowerN = middleN
                lowerD = middleD
            } else {
                upperN = middleN
                upperD = middleD
            }
        }

        let lower = Double(lowerN) / Double(lowerD)
        let upper = upperD == 0 ? Double.infinity : Double(upperN) / Double(upperD)
        let best = abs(lower - target) <= abs(upper - target)
            ? RationalFraction(numerator: sign * lowerN, denominator: lowerD)
            : RationalFraction(numerator: sign * upperN, denominator: upperD)
        let approximation = Double(best.numerator) / Double(best.denominator)
        guard abs(approximation - value) <= 1e-8 else { return nil }
        return best
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
    private func expressionText(
        _ text: String,
        displayText: String,
        isSelected: Bool,
        formalFraction: RationalFraction?
    ) -> some View {
        if let tokens = editableExpressionTokens(for: text), tokens.contains(where: { token in
            if case .fraction = token { return true }
            return false
        }) {
            editableTokenSequence(tokens, isSelected: isSelected, color: .black)
        } else if let formalFraction {
            formalFractionView(formalFraction)
        } else if isSelected {
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
            GraphCalculatorMathDisplay(source: text, fallback: displayText, fontSize: 20)
                .foregroundStyle(.black)
        }
    }

    private func numericExpressionLine(
        text: String,
        displayText: String,
        displayValue: String,
        isSelected: Bool,
        formalFraction: RationalFraction?,
        tokens: [EditableExpressionToken]?,
        fractionResult: RationalFraction?
    ) -> some View {
        let hasEditableFraction = tokens?.contains { token in
            if case .fraction = token { return true }
            return false
        } ?? false
        return HStack(alignment: .center, spacing: 5) {
            if let tokens, hasEditableFraction {
                editableTokenSequence(tokens, isSelected: isSelected, color: .black)
            } else {
                expressionText(text, displayText: displayText, isSelected: false, formalFraction: formalFraction)
            }

            if isSelected && (!hasEditableFraction || isCursorVisuallyAfterEditableFraction(tokens)) {
                Rectangle()
                    .fill(GraphCalculatorTheme.blue)
                    .frame(width: 2, height: 24)
            }

            Text("=")
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .foregroundStyle(.red.opacity(0.82))

            if let fractionResult {
                formalFractionView(fractionResult, color: Color(red: 0.07, green: 0.63, blue: 0.36))
            } else {
                Text(displayValue)
                    .font(.system(size: 18, weight: .medium, design: .serif))
                    .foregroundStyle(Color(red: 0.07, green: 0.63, blue: 0.36))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.65)
    }

    private func editableTokenSequence(_ tokens: [EditableExpressionToken], isSelected: Bool, color: Color) -> some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                switch token {
                case .text(let value):
                    GraphCalculatorMathDisplay(
                        source: value,
                        fallback: GraphCalculatorExpressionDisplay.string(for: value),
                        fontSize: 20
                    )
                    .foregroundStyle(color)
                case .fraction(let fraction):
                    editableFractionView(fraction, isSelected: isSelected, color: color)
                }
            }
        }
    }

    private func editableFractionView(_ fraction: EditableFractionToken, isSelected: Bool, color: Color) -> some View {
        let numeratorText = GraphCalculatorExpressionDisplay.string(for: fraction.numerator)
        let denominatorText = GraphCalculatorExpressionDisplay.string(for: fraction.denominator)
        let characterCount = max(max(numeratorText.count, denominatorText.count), 1)
        let barWidth = max(28, CGFloat(characterCount) * 11 + 14)
        let numeratorActive = isSelected
            && state.cursorOffset >= fraction.numeratorRange.lowerBound
            && state.cursorOffset <= fraction.slashOffset
        let denominatorIsEmpty = fraction.denominatorRange.isEmpty
        let denominatorActive = isSelected
            && fractionCursorExitedAt != state.cursorOffset
            && state.cursorOffset >= fraction.denominatorRange.lowerBound
            && (denominatorIsEmpty ? state.cursorOffset == fraction.denominatorRange.lowerBound : state.cursorOffset <= fraction.denominatorRange.upperBound)

        return VStack(spacing: 2) {
            editableFractionPart(
                sourceText: fraction.numerator,
                displayText: numeratorText,
                range: fraction.numeratorRange,
                isActive: numeratorActive,
                placeholderHeight: 22,
                color: color
            )
            Rectangle()
                .fill(color.opacity(0.86))
                .frame(width: barWidth, height: 1.4)
            editableFractionPart(
                sourceText: fraction.denominator,
                displayText: denominatorText,
                range: fraction.denominatorRange,
                isActive: denominatorActive,
                placeholderHeight: 22,
                color: color
            )
        }
        .frame(width: barWidth)
        .padding(.vertical, 3)
    }

    private func editableFractionPart(
        sourceText: String,
        displayText: String,
        range: Range<Int>,
        isActive: Bool,
        placeholderHeight: CGFloat,
        color: Color
    ) -> some View {
        let cursorOffset = min(max(state.cursorOffset - range.lowerBound, 0), displayText.count)
        let splitText = split(displayText, at: cursorOffset)

        return HStack(spacing: 1) {
            if sourceText.isEmpty {
                if isActive {
                    Rectangle()
                        .fill(GraphCalculatorTheme.blue)
                        .frame(width: 2, height: placeholderHeight)
                }
                Rectangle()
                    .fill(Color.black.opacity(0.14))
                    .frame(width: 16, height: placeholderHeight)
            } else if isActive {
                Text(splitText.before)
                Rectangle()
                    .fill(GraphCalculatorTheme.blue)
                    .frame(width: 2, height: placeholderHeight)
                Text(splitText.after)
            } else {
                GraphCalculatorMathDisplay(source: sourceText, fallback: displayText, fontSize: 20)
            }
        }
        .font(.system(size: 20, weight: .regular, design: .serif))
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.65)
        .frame(minWidth: 18, minHeight: placeholderHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            fractionCursorExitedAt = nil
            state.cursorOffset = range.upperBound
        }
    }

    private func isCursorVisuallyAfterEditableFraction(_ tokens: [EditableExpressionToken]?) -> Bool {
        guard let tokens, fractionCursorExitedAt == state.cursorOffset else { return false }
        return tokens.contains { token in
            guard case .fraction(let fraction) = token else { return false }
            return !fraction.denominatorRange.isEmpty && state.cursorOffset == fraction.denominatorRange.upperBound
        }
    }

    private func formalFractionView(_ fraction: RationalFraction, color: Color = .black) -> some View {
        let numeratorText = "\(fraction.numerator)"
        let denominatorText = "\(fraction.denominator)"
        let characterCount = max(numeratorText.count, denominatorText.count)
        let barWidth = max(24, CGFloat(characterCount) * 11 + 12)

        return VStack(spacing: 2) {
            Text(numeratorText)
            Rectangle()
                .fill(color.opacity(0.86))
                .frame(width: barWidth, height: 1.4)
            Text(denominatorText)
        }
        .font(.system(size: 20, weight: .regular, design: .serif))
        .foregroundStyle(color)
        .lineLimit(1)
        .frame(width: barWidth)
        .padding(.vertical, 3)
    }

    private func formalFractionExpression(_ text: String) -> RationalFraction? {
        let compact = text.replacingOccurrences(of: " ", with: "")
        let parts = compact.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let numerator = Int(parts[0]),
              let denominator = Int(parts[1]),
              denominator != 0 else {
            return nil
        }
        let divisor = greatestCommonDivisor(abs(numerator), abs(denominator))
        let normalizedSign = denominator < 0 ? -1 : 1
        return RationalFraction(
            numerator: normalizedSign * numerator / divisor,
            denominator: abs(denominator) / divisor
        )
    }

    private func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
        var x = a
        var y = b
        while y != 0 {
            let remainder = x % y
            x = y
            y = remainder
        }
        return max(x, 1)
    }

    private func split(_ text: String, at offset: Int) -> (before: String, after: String) {
        let clamped = min(max(offset, 0), text.count)
        let index = text.index(text.startIndex, offsetBy: clamped, limitedBy: text.endIndex) ?? text.endIndex
        return (String(text[..<index]), String(text[index...]))
    }

    private func expressionStyleCell(index: Int, isSelected: Bool, isInvalid: Bool, color: Color) -> some View {
        let isEnabled = state.expressions.indices.contains(index) ? state.expressions[index].isEnabled : true
        return ZStack {
            Circle()
                .fill(color.opacity(isInvalid || !isEnabled ? 0.35 : 1))
                .frame(width: 28, height: 28)
                .overlay(Circle().strokeBorder(isSelected ? .white.opacity(0.84) : .black.opacity(0.08), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                .contentShape(Circle())
                .overlay {
                    swatchWaveMark(isEnabled: isEnabled)
                        .frame(width: 20, height: 13)
                }
                .onTapGesture {
                    state.ensureExpression(at: index)
                    if isSelected {
                        swatchActionExpressionIndex = index
                    } else {
                        state.selectExpression(at: index)
                    }
                }
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
                .popover(
                    isPresented: Binding(
                        get: { swatchActionExpressionIndex == index },
                        set: { isPresented in
                            if !isPresented, swatchActionExpressionIndex == index {
                                swatchActionExpressionIndex = nil
                            }
                        }
                    )
                ) {
                    swatchActionPopover(index: index)
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

    private func swatchWaveMark(isEnabled: Bool) -> some View {
        Canvas { context, size in
            var path = Path()
            let midY = size.height * 0.5
            path.move(to: CGPoint(x: 0, y: midY))
            path.addCurve(
                to: CGPoint(x: size.width * 0.5, y: midY),
                control1: CGPoint(x: size.width * 0.18, y: -size.height * 0.15),
                control2: CGPoint(x: size.width * 0.32, y: size.height * 1.15)
            )
            path.addCurve(
                to: CGPoint(x: size.width, y: midY),
                control1: CGPoint(x: size.width * 0.68, y: -size.height * 0.15),
                control2: CGPoint(x: size.width * 0.82, y: size.height * 1.15)
            )
            context.stroke(
                path,
                with: .color(.white.opacity(isEnabled ? 0.95 : 0.55)),
                style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
            )
            if !isEnabled {
                var slash = Path()
                slash.move(to: CGPoint(x: size.width * 0.08, y: size.height * 0.92))
                slash.addLine(to: CGPoint(x: size.width * 0.92, y: size.height * 0.08))
                context.stroke(slash, with: .color(.white.opacity(0.82)), style: StrokeStyle(lineWidth: 2.1, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
    }

    private func toggleExpressionEnabled(_ index: Int) {
        state.ensureExpression(at: index)
        state.expressions[index].isEnabled.toggle()
        state.selectExpression(at: index)
    }

    private func swatchActionPopover(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                toggleExpressionEnabled(index)
                swatchActionExpressionIndex = nil
            } label: {
                Label(
                    state.expressions.indices.contains(index) && state.expressions[index].isEnabled ? "Turn Off" : "Turn On",
                    systemImage: "power"
                )
            }
            Button {
                copyExpression(at: index)
                swatchActionExpressionIndex = nil
            } label: {
                Label("Copy Equation", systemImage: "doc.on.doc")
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 15, weight: .semibold))
        .padding(14)
        .frame(minWidth: 170, alignment: .leading)
    }

    private func copyExpression(at index: Int) {
        guard state.expressions.indices.contains(index) else { return }
        let expression = state.expressions[index].expression
        #if os(iOS)
        UIPasteboard.general.string = expression
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(expression, forType: .string)
        #endif
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

    /// Computes key sizing so normal keys are square. Wide keys span two columns but keep the same
    /// height as the rest of the row.
    private func keypadMetrics(for size: CGSize) -> KeypadMetrics {
        let spacing: CGFloat = 7
        let groupSpacing: CGFloat = 12
        let horizontalPadding: CGFloat = 10
        let verticalPadding: CGFloat = 9
        let columns: CGFloat = 10          // 4 left keys + 6 right keys
        let interKeyGaps: CGFloat = 8      // 3 gaps in the left group + 5 gaps in the right group

        let availableWidth = max(0, size.width - horizontalPadding * 2)
        let columnWidth = max(30, (availableWidth - spacing * interKeyGaps - groupSpacing) / columns)
        let rowHeight = columnWidth

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
                key("→", metrics: metrics) { moveExpressionCursorRight() }
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
                functionKey(metrics: metrics)
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

    private func functionKey(metrics: KeypadMetrics) -> some View {
        key("f(x)", emphasized: true, metrics: metrics) { insert("f(") }
            .contextMenu {
                Button("g(x)") { insert("g(") }
                Button("h(x)") { insert("h(") }
            }
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
                key("→", metrics: metrics) { moveExpressionCursorRight() }
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
        Button {
            recordKeyStroke(label: label, style: style, wide: wide, emphasized: emphasized)
            action()
        } label: {
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
        Button {
            recordKeyStroke(label: "a⁄b", style: .plain, wide: false, emphasized: false)
            action()
        } label: {
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
        let expandedSize = detachedResizeLive?.size ?? clampGraphSize(state.detachedGraphSize, in: containerSize)
        let expandedCenter = detachedResizeLive?.center ?? detachedGraphCenter(size: expandedSize, in: containerSize)
        let size = state.isDetachedGraphHeaderCollapsed
            ? collapsedPanelSize(forExpandedSize: expandedSize, in: containerSize)
            : expandedSize
        let center = state.isDetachedGraphHeaderCollapsed
            ? collapsedCenterPreservingTop(expandedCenter: expandedCenter, expandedSize: expandedSize, collapsedSize: size, in: containerSize)
            : expandedCenter
        let placementRect = CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )

        return detachedGraphPanelContent(size: size, center: center, placementRect: placementRect, containerSize: containerSize)
        .frame(width: size.width, height: size.height)
        .background(Color.white, in: Rectangle())
        .overlay(Rectangle().strokeBorder(.black.opacity(0.32), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
        .compositingGroup()
        .overlay(alignment: .bottomTrailing) {
            if !state.isDetachedGraphHeaderCollapsed {
                ResizeGrip()
                    .frame(width: 24, height: 24)
                    .padding(7)
                    .contentShape(Rectangle())
                    .highPriorityGesture(detachedResizeGesture(currentCenter: center, in: containerSize))
            }
        }
        .position(center)
        .opacity(isDragging(.detachedGraph) ? 0.14 : 1)
    }

    private func detachedGraphPanelContent(
        size: CGSize,
        center: CGPoint,
        placementRect: CGRect,
        containerSize: CGSize
    ) -> some View {
        VStack(spacing: 0) {
            detachedGraphTopBar
            .gesture(detachedDragGesture(currentCenter: center, size: size, expandedSize: size.height == compactHeaderHeight ? state.detachedGraphSize : size, in: containerSize))

            if !state.isDetachedGraphHeaderCollapsed {
                graphCanvas(keepsSquarePlot: false)
                    .overlay(alignment: .topLeading) {
                        detachedGraphEquationOverlay
                    }
                    .overlay(alignment: .topTrailing) {
                        graphControlOverlay(placementRect: placementRect, containerSize: containerSize) {
                            squareDetachedGraphWindow(currentSize: size, currentCenter: center, in: containerSize)
                        }
                    }
            }
        }
    }

    private var detachedGraphTopBar: some View {
        Group {
            if state.isDetachedGraphHeaderCollapsed {
                collapsedDragBar(tint: .black.opacity(0.45), background: .white) {
                    state.isDetachedGraphHeaderCollapsed = false
                }
                .frame(height: compactHeaderHeight)
                .overlay(Rectangle().fill(.black.opacity(0.18)).frame(height: 1), alignment: .bottom)
            } else {
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
                .frame(height: expandedFloatingHeaderHeight)
                .background(Color.white)
                .overlay(Rectangle().fill(.black.opacity(0.18)).frame(height: 1), alignment: .bottom)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    state.isDetachedGraphHeaderCollapsed = true
                }
            }
        }
    }

    private var detachedGraphEquationOverlay: some View {
        let rows = state.expressions.enumerated().compactMap { index, equation -> (index: Int, source: String, fallback: String)? in
            let text = equation.expression.trimmingCharacters(in: .whitespacesAndNewlines)
            guard equation.isEnabled, !text.isEmpty else { return nil }
            return (index, text, GraphCalculatorExpressionDisplay.string(for: text))
        }

        return VStack(alignment: .leading, spacing: 6) {
            ForEach(rows.prefix(6), id: \.index) { row in
                GraphCalculatorMathDisplay(source: row.source, fallback: row.fallback, fontSize: 18)
                    .foregroundStyle(graphColor(for: row.index))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 230, alignment: .leading)
        .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.black.opacity(0.14), lineWidth: 0.5))
        .padding(10)
        .allowsHitTesting(false)
    }

    private func detachedControlPanel(in containerSize: CGSize) -> some View {
        let width = min(containerSize.width - 24, 440)
        let expandedHeight = min(containerSize.height - 24, detachedControlHeight)
        let expandedSize = CGSize(width: width, height: expandedHeight)
        let size = state.isDetachedControlHeaderCollapsed
            ? collapsedPanelSize(forExpandedSize: expandedSize, in: containerSize)
            : expandedSize
        let expandedCenter = detachedControlCenter(size: expandedSize, in: containerSize)
        let center = state.isDetachedControlHeaderCollapsed
            ? collapsedCenterPreservingTop(expandedCenter: expandedCenter, expandedSize: expandedSize, collapsedSize: size, in: containerSize)
            : entryResizeLive?.center ?? expandedCenter
        let height = size.height
        let placementRect = CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )

        return detachedControlPanelContent(size: size, height: height, center: center, placementRect: placementRect, containerSize: containerSize)
        .frame(width: size.width, height: size.height)
        .background(GraphCalculatorTheme.panel, in: Rectangle())
        .overlay(Rectangle().strokeBorder(.black.opacity(0.14), lineWidth: 1))
        .overlay(detachedControlPanelBorder)
        .shadow(color: .black.opacity(0.26), radius: 16, y: 7)
        .compositingGroup()
        .position(center)
        .opacity(isDragging(.detachedControl) ? 0.14 : 1)
    }

    private func detachedControlPanelContent(
        size: CGSize,
        height: CGFloat,
        center: CGPoint,
        placementRect: CGRect,
        containerSize: CGSize
    ) -> some View {
        VStack(spacing: 0) {
            calculatorTopBar(.detachedControl)
                .gesture(detachedControlDragGesture(currentCenter: center, size: size, expandedHeight: detachedControlHeight, in: containerSize))
            if !state.isDetachedControlHeaderCollapsed {
                graphToolbar(placementRect: placementRect, containerSize: containerSize)
                entryPanel
                    .frame(height: detachedEntryHeight(availableHeight: height))
                entryResizeHandle(anchoredCenter: center, containerSize: containerSize)
                keypad
                    .frame(height: state.isKeypadCollapsed ? 0 : keypadHeight)
                    .clipped()
            }
        }
    }

    private var detachedControlPanelBorder: some View {
        GeometryReader { proxy in
            let lineWidth: CGFloat = 3
            let size = proxy.size
            Path { path in
                path.move(to: CGPoint(x: lineWidth / 2, y: 0))
                path.addLine(to: CGPoint(x: lineWidth / 2, y: size.height - lineWidth / 2))
                path.addLine(to: CGPoint(x: size.width - lineWidth / 2, y: size.height - lineWidth / 2))
                path.addLine(to: CGPoint(x: size.width - lineWidth / 2, y: 0))
            }
            .stroke(.black.opacity(0.9), style: StrokeStyle(lineWidth: lineWidth, lineCap: .square, lineJoin: .miter))
        }
        .allowsHitTesting(false)
    }

    // MARK: - Keystroke display window

    private func keystrokeWindow(in containerSize: CGSize) -> some View {
        let size = keystrokeWindowResizeLive?.size ?? clampKeystrokeWindowSize(state.keystrokeWindowSize, in: containerSize)
        let center = keystrokeWindowResizeLive?.center ?? keystrokeWindowCenter(size: size, in: containerSize)

        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "keyboard")
                    .font(.headline.weight(.semibold))
                Text("Key Strokes")
                    .font(.headline)
                Spacer()
                Button {
                    state.isKeystrokeRecordingPaused.toggle()
                } label: {
                    Image(systemName: state.isKeystrokeRecordingPaused ? "record.circle" : "pause.fill")
                        .foregroundStyle(state.isKeystrokeRecordingPaused ? GraphCalculatorTheme.blue : .black.opacity(0.7))
                }
                Button {
                    if !state.recordedKeystrokes.isEmpty {
                        state.recordedKeystrokes.removeLast()
                    }
                } label: {
                    Image(systemName: "delete.left")
                }
                .disabled(state.recordedKeystrokes.isEmpty)
                Button {
                    state.recordedKeystrokes.removeAll()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(state.recordedKeystrokes.isEmpty)
                Button {
                    makeKeystrokeSticker(size: size)
                } label: {
                    Image(systemName: "square.on.square")
                }
                .disabled(onGraphSnapshot == nil || state.recordedKeystrokes.isEmpty)
                Button {
                    state.isKeystrokeDisplayEnabled = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.black.opacity(0.72))
            .padding(.horizontal, 12)
            .frame(height: expandedFloatingHeaderHeight)
            .background(Color.white)
            .overlay(Rectangle().fill(.black.opacity(0.18)).frame(height: 1), alignment: .bottom)
            .contentShape(Rectangle())
            .gesture(keystrokeWindowDragGesture(currentCenter: center, size: size, in: containerSize))

            keystrokeSequenceContent(size: CGSize(width: size.width, height: max(1, size.height - expandedFloatingHeaderHeight)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.985, green: 0.985, blue: 0.975))
        }
        .frame(width: size.width, height: size.height)
        .background(Color.white, in: Rectangle())
        .overlay(Rectangle().strokeBorder(.black.opacity(0.32), lineWidth: 1))
        .shadow(color: .black.opacity(0.24), radius: 12, y: 6)
        .overlay(alignment: .bottomTrailing) {
            ResizeGrip()
                .frame(width: 24, height: 24)
                .padding(7)
                .contentShape(Rectangle())
                .highPriorityGesture(keystrokeWindowResizeGesture(currentCenter: center, in: containerSize))
        }
        .position(center)
    }

    private func keystrokeSequenceContent(size: CGSize) -> some View {
        let isVertical = size.height > size.width * 0.92
        let items = keystrokeDisplayItems()
        return Group {
            if isVertical {
                ScrollView(.horizontal) {
                    LazyHGrid(rows: [GridItem(.adaptive(minimum: 58), spacing: 10, alignment: .center)], spacing: 10) {
                        ForEach(items) { item in
                            keystrokeDisplayItemView(item, isVertical: true)
                        }
                    }
                    .padding(14)
                    .frame(minHeight: size.height, alignment: .leading)
                }
            } else {
                ScrollView(.vertical) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 10, alignment: .center)], spacing: 10) {
                        ForEach(items) { item in
                            keystrokeDisplayItemView(item, isVertical: false)
                        }
                    }
                    .padding(14)
                    .frame(minWidth: size.width, alignment: .topLeading)
                }
            }
        }
    }

    private func keystrokeDisplayItems() -> [KeystrokeDisplayItem] {
        var items: [KeystrokeDisplayItem] = [
            KeystrokeDisplayItem(kind: .start(1))
        ]
        if state.recordedKeystrokes.isEmpty {
            items.append(KeystrokeDisplayItem(kind: .placeholder))
        } else {
            for (index, stroke) in state.recordedKeystrokes.enumerated() {
                items.append(KeystrokeDisplayItem(id: stroke.id, kind: .key(stroke)))
                items.append(KeystrokeDisplayItem(kind: .connector(index + 2)))
            }
            items.append(KeystrokeDisplayItem(kind: .placeholder))
        }
        return items
    }

    @ViewBuilder
    private func keystrokeDisplayItemView(_ item: KeystrokeDisplayItem, isVertical: Bool) -> some View {
        switch item.kind {
        case .start(let number):
            numberedStartCircle(number)
        case .key(let stroke):
            recordedKeystrokeView(stroke)
        case .connector(let number):
            keystrokeConnector(number: number, isVertical: isVertical)
        case .placeholder:
            keystrokePlaceholder()
        }
    }

    private struct KeystrokeDisplayItem: Identifiable {
        enum Kind {
            case start(Int)
            case key(GraphRecordedKeyStroke)
            case connector(Int)
            case placeholder
        }

        var id: UUID = UUID()
        var kind: Kind
    }

    private func numberedStartCircle(_ number: Int) -> some View {
        Text("\(number)")
            .font(.system(size: 14, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(GraphCalculatorTheme.blue, in: Circle())
    }

    private func keystrokeConnector(number: Int, isVertical: Bool) -> some View {
        VStack(spacing: 2) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold).monospacedDigit())
                .foregroundStyle(.black.opacity(0.58))
            Image(systemName: isVertical ? "arrow.down" : "arrow.right")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.black.opacity(0.48))
        }
        .frame(width: isVertical ? 70 : 34, height: isVertical ? 34 : 54)
    }

    private func keystrokePlaceholder() -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(.black.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            .frame(width: 70, height: 54)
    }

    private func recordedKeystrokeView(_ stroke: GraphRecordedKeyStroke) -> some View {
        let metrics = KeypadMetrics(
            columnWidth: 62,
            rowHeight: 46,
            spacing: 7,
            groupSpacing: 12,
            horizontalPadding: 0,
            verticalPadding: 0
        )
        return keyLabel(stroke.label, wide: stroke.isWide, emphasized: stroke.isEmphasized, metrics: metrics)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.black.opacity(0.22))
                        .offset(y: 3)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    keyFill(style: stroke.style == .number ? .number : .plain, emphasized: stroke.isEmphasized),
                                    keyFill(style: stroke.style == .number ? .number : .plain, emphasized: stroke.isEmphasized).opacity(0.84)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(alignment: .top) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(.white.opacity(stroke.isEmphasized ? 0.28 : 0.72), lineWidth: 1)
                                .padding(1)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(.black.opacity(0.20), lineWidth: 0.6)
                        )
                }
            }
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
    }

    private func recordKeyStroke(label: String, style: KeyStyle, wide: Bool, emphasized: Bool) {
        guard state.isKeystrokeDisplayEnabled, !state.isKeystrokeRecordingPaused else { return }
        let recordedStyle: GraphRecordedKeyStyle = style == .number ? .number : .plain
        state.recordedKeystrokes.append(GraphRecordedKeyStroke(
            label: label,
            style: recordedStyle,
            isWide: wide,
            isEmphasized: emphasized
        ))
    }

    private func keystrokeWindowCenter(size: CGSize, in containerSize: CGSize) -> CGPoint {
        let fallback = CGPoint(x: containerSize.width * 0.52, y: max(size.height / 2 + 32, containerSize.height * 0.22))
        return clamp(center: state.keystrokeWindowPosition ?? fallback, size: size, in: containerSize)
    }

    private func clampKeystrokeWindowSize(_ proposed: CGSize, in containerSize: CGSize) -> CGSize {
        CGSize(
            width: min(max(proposed.width, 180), max(180, containerSize.width - 24)),
            height: min(max(proposed.height, 120), max(120, containerSize.height - 24))
        )
    }

    private func keystrokeWindowDragGesture(currentCenter: CGPoint, size: CGSize, in containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let base = keystrokeWindowDragStart ?? currentCenter
                if keystrokeWindowDragStart == nil { keystrokeWindowDragStart = base }
                state.keystrokeWindowPosition = clamp(
                    center: CGPoint(x: base.x + value.translation.width, y: base.y + value.translation.height),
                    size: size,
                    in: containerSize
                )
            }
            .onEnded { _ in
                keystrokeWindowDragStart = nil
            }
    }

    private func keystrokeWindowResizeGesture(currentCenter: CGPoint, in containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let start = keystrokeWindowResizeStart ?? (
                    size: state.keystrokeWindowSize,
                    topLeft: CGPoint(x: currentCenter.x - state.keystrokeWindowSize.width / 2, y: currentCenter.y - state.keystrokeWindowSize.height / 2)
                )
                if keystrokeWindowResizeStart == nil { keystrokeWindowResizeStart = start }
                let size = clampKeystrokeWindowSize(
                    CGSize(width: start.size.width + value.translation.width, height: start.size.height + value.translation.height),
                    in: containerSize
                )
                let center = clamp(center: CGPoint(x: start.topLeft.x + size.width / 2, y: start.topLeft.y + size.height / 2), size: size, in: containerSize)
                keystrokeWindowResizeLive = (size, center)
            }
            .onEnded { _ in
                if let live = keystrokeWindowResizeLive {
                    state.keystrokeWindowSize = live.size
                    state.keystrokeWindowPosition = live.center
                }
                keystrokeWindowResizeLive = nil
                keystrokeWindowResizeStart = nil
            }
    }

    private func makeKeystrokeSticker(size: CGSize) {
        guard let onGraphSnapshot, !state.recordedKeystrokes.isEmpty else { return }
        #if os(iOS)
        let stickerSize = CGSize(width: max(220, size.width), height: max(120, size.height - expandedFloatingHeaderHeight))
        let renderer = ImageRenderer(content: keystrokeSequenceContent(size: stickerSize).frame(width: stickerSize.width, height: stickerSize.height).background(Color.white))
        renderer.scale = 3
        guard let image = renderer.uiImage, let pngData = image.pngData() else { return }
        onGraphSnapshot(GraphCalculatorSnapshot(pngData: pngData, size: stickerSize, placementRect: nil, containerSize: nil))
        #endif
    }

    // MARK: - Floating table window

    @ViewBuilder
    private func tableWindow(in containerSize: CGSize) -> some View {
        if let active = state.activeTable,
           let equation = state.expressions.first(where: { $0.id == active.equationID }) {
            let expandedSize = tableResizeLive?.size ?? clampTableSize(state.tableWindowSize, in: containerSize)
            let size = state.isTableHeaderCollapsed
                ? CGSize(width: expandedSize.width, height: compactHeaderHeight)
                : expandedSize
            let center = tableResizeLive?.center ?? tableWindowCenter(size: size, in: containerSize)

            tableWindowContent(active: active, equation: equation, currentCenter: center, size: size, in: containerSize)
            .frame(width: size.width, height: size.height)
            .background(Color.white, in: Rectangle())
            .overlay(Rectangle().strokeBorder(.black.opacity(0.32), lineWidth: 1))
            .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
            .compositingGroup()
            .overlay(alignment: .bottomTrailing) {
                if !state.isTableHeaderCollapsed {
                    ResizeGrip()
                        .frame(width: 24, height: 24)
                        .padding(7)
                        .contentShape(Rectangle())
                        .highPriorityGesture(tableResizeGesture(currentCenter: center, in: containerSize))
                }
            }
            .position(center)
            .opacity(isDragging(.table) ? 0.14 : 1)
        }
    }

    private func tableWindowContent(
        active: GraphActiveTable,
        equation: GraphEquation,
        currentCenter: CGPoint,
        size: CGSize,
        in containerSize: CGSize
    ) -> some View {
        VStack(spacing: 0) {
            tableMenuBar(active: active, equation: equation, currentCenter: currentCenter, size: size, in: containerSize)
            if !state.isTableHeaderCollapsed {
                Divider()
                if active.kind == .function {
                    functionTableBody(equationID: active.equationID)
                } else {
                    pointsTableBody(equationID: active.equationID)
                }
            }
        }
    }

    private func tableMenuBar(
        active: GraphActiveTable,
        equation: GraphEquation,
        currentCenter: CGPoint,
        size: CGSize,
        in containerSize: CGSize
    ) -> some View {
        Group {
            if state.isTableHeaderCollapsed {
                collapsedDragBar(tint: .black.opacity(0.45), background: .white) {
                    state.isTableHeaderCollapsed = false
                }
                .frame(height: compactHeaderHeight)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "tablecells")
                        .font(.headline.weight(.semibold))
                    Text(GraphCalculatorExpressionDisplay.string(for: equation.expression))
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer()

                    if active.kind == .function {
                        Button { state.isTraceActive.toggle() } label: {
                            Image(systemName: "scope")
                                .foregroundStyle(state.isTraceActive ? GraphCalculatorTheme.blue : .black.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        Menu {
                            if state.secondaryFunctionTableEquationIDs[active.equationID] != nil {
                                Button("Remove second column") {
                                    state.secondaryFunctionTableEquationIDs.removeValue(forKey: active.equationID)
                                }
                                Divider()
                            }
                            let candidates = secondaryFunctionTableCandidates(for: active.equationID)
                            if candidates.isEmpty {
                                Text("No compatible rows")
                            } else {
                                ForEach(candidates) { candidate in
                                    Button(candidate.label) {
                                        state.secondaryFunctionTableEquationIDs[active.equationID] = candidate.equationID
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "rectangle.split.3x1")
                                .foregroundStyle(state.secondaryFunctionTableEquationIDs[active.equationID] == nil ? .black.opacity(0.6) : GraphCalculatorTheme.blue)
                        }
                        .buttonStyle(.plain)
                        Button { isTableSettingsPresented.toggle() } label: {
                            Image(systemName: "gearshape.fill")
                                .foregroundStyle(isTableSettingsPresented ? GraphCalculatorTheme.blue : .black.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $isTableSettingsPresented) {
                            tableSettingsPopover(equationID: active.equationID)
                        }
                    } else {
                        Button { addPointRowAndBeginEditing(equationID: active.equationID) } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        finishPointCellEdit()
                        state.closeTable()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
                .font(.title3.weight(.semibold))
                .foregroundStyle(.black.opacity(0.72))
                .padding(.horizontal, 12)
                .frame(height: expandedFloatingHeaderHeight)
                .background(Color.white)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    state.isTableHeaderCollapsed = true
                }
            }
        }
        .gesture(tableDragGesture(currentCenter: currentCenter, size: size, in: containerSize))
    }

    /// Function (`y = f(x)`) table: read-only x column generated from start/delta, computed f(x).
    private func functionTableBody(equationID: UUID) -> some View {
        let settings = state.functionTableSettings(for: equationID)
        let primary = functionTableDescriptor(for: equationID)
        let secondary = secondaryFunctionTableDescriptor(for: equationID)
        let compiled = primary.flatMap { try? engine.compile($0.source) }
        let secondaryCompiled = secondary.flatMap { try? engine.compile($0.source) }
        let variables = graphVariableValues
        let selectedRowIndex = selectedTraceTableRowIndex(equationID: equationID, settings: settings)
        let selectedKind = selectedTraceTableKind(equationID: equationID, settings: settings, compiled: compiled, variables: variables)

        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                tableHeaderCell("x")
                tableHeaderCell(primary?.label ?? "f(x)")
                if let secondary {
                    tableHeaderCell(secondary.label)
                }
            }
            if let compiled {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        // Generous count; LazyVStack only builds visible rows.
                        ForEach(0..<200, id: \.self) { n in
                            let x = settings.start + Double(n) * settings.delta
                            let isSelected = selectedRowIndex == n
                            let highlightColor = isSelected ? tableHighlightColor(for: selectedKind) : nil
                            let y = evaluate(compiled: compiled, at: x, variableValues: variables)
                            let secondaryY = secondaryCompiled.flatMap { evaluate(compiled: $0, at: x, variableValues: variables) }
                            HStack(spacing: 0) {
                                tableValueCell(CalculatorResultFormatter.string(for: x), highlightColor: highlightColor)
                                tableValueCell(functionTableValue(y), highlightColor: highlightColor)
                                if secondary != nil {
                                    tableValueCell(functionTableValue(secondaryY), highlightColor: highlightColor)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectTraceTablePoint(x: x, y: y, secondaryY: secondaryY, equationID: equationID)
                            }
                        }
                    }
                }
            } else {
                Text("Select a y-function")
                    .font(.system(size: 13))
                    .foregroundStyle(.black.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func functionTableValue(_ value: Double?) -> String {
        guard let value else { return "undefined" }
        return CalculatorResultFormatter.string(for: value)
    }

    private func selectTraceTablePoint(x: Double, y: Double?, secondaryY: Double?, equationID: UUID) {
        guard isTracing,
              state.activeTable?.equationID == equationID,
              let y else {
            return
        }
        state.selectedPoint = nil
        state.traceSelectedX = x
        ensureTracePointVisible(x: x, y: y)
        if let secondaryY {
            ensureTracePointVisible(x: x, y: secondaryY)
        }
    }

    private func ensureTracePointVisible(x: Double, y: Double) {
        let window = state.graphWindow
        guard x.isFinite, y.isFinite else { return }
        let containsX = x >= window.xMin && x <= window.xMax
        let containsY = y >= window.yMin && y <= window.yMax
        guard !containsX || !containsY else { return }

        let centerX = (window.xMin + window.xMax) / 2
        let centerY = (window.yMin + window.yMax) / 2
        let marginFactor = 1.14
        let halfWidth = max(window.width / 2, abs(x - centerX) * marginFactor, minimumGraphSpan / 2)
        let halfHeight = max(window.height / 2, abs(y - centerY) * marginFactor, minimumGraphSpan / 2)

        state.graphWindow = limitedGraphWindow(GraphWindow(
            xMin: centerX - halfWidth,
            xMax: centerX + halfWidth,
            yMin: centerY - halfHeight,
            yMax: centerY + halfHeight
        ))
    }

    private func selectedTraceTableRowIndex(equationID: UUID, settings: GraphFunctionTableSettings) -> Int? {
        guard isTracing,
              state.activeTable?.equationID == equationID,
              settings.delta != 0 else {
            return nil
        }
        let selectedX = state.traceSelectedX ?? settings.start
        let rawIndex = (selectedX - settings.start) / settings.delta
        let roundedIndex = rawIndex.rounded()
        guard abs(rawIndex - roundedIndex) < 1e-6 else { return nil }
        let index = Int(roundedIndex)
        return index >= 0 ? index : nil
    }

    private func selectedTraceTableKind(
        equationID: UUID,
        settings: GraphFunctionTableSettings,
        compiled: CalculatorExpression?,
        variables: [String: Double]
    ) -> GraphCalculatorPointReadout.Kind? {
        guard isTracing,
              state.activeTable?.equationID == equationID,
              let compiled else {
            return nil
        }
        let selectedX = state.traceSelectedX ?? settings.start
        guard let selectedY = evaluate(compiled: compiled, at: selectedX, variableValues: variables) else {
            return nil
        }
        return traceSpecialKind(x: selectedX, y: selectedY)
    }

    private func tableHighlightColor(for kind: GraphCalculatorPointReadout.Kind?) -> Color {
        guard let kind else { return GraphCalculatorTheme.blue }
        return GraphHighlightPalette.color(for: kind)
    }

    /// Points table: the typed ordered pair (read-only) followed by editable teacher-added points.
    private func pointsTableBody(equationID: UUID) -> some View {
        let typed = typedPoint(for: equationID)
        let extras = state.extraPoints(for: equationID)

        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                tableHeaderCell("x")
                tableHeaderCell("y")
                tableHeaderCell("")
            }
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    if let typed {
                        HStack(spacing: 0) {
                            tableValueCell(CalculatorResultFormatter.string(for: typed.0))
                            tableValueCell(CalculatorResultFormatter.string(for: typed.1))
                            Color.clear.frame(maxWidth: .infinity, minHeight: 44)
                                .overlay(Rectangle().stroke(.black.opacity(0.10), lineWidth: 0.5))
                        }
                        .background(Color.black.opacity(0.03))
                    }
                    ForEach(extras) { pair in
                        pointsTableEditRow(equationID: equationID, pair: pair)
                    }
                    Button { addPointRowAndBeginEditing(equationID: equationID) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                            Text("Add point")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(GraphCalculatorTheme.blue)
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func pointsTableEditRow(equationID: UUID, pair: GraphOrderedPair) -> some View {
        HStack(spacing: 0) {
            pointsEditCell(
                equationID: equationID,
                pairID: pair.id,
                column: .x,
                value: pair.x,
                placeholder: "x"
            )
            pointsEditCell(
                equationID: equationID,
                pairID: pair.id,
                column: .y,
                value: pair.y,
                placeholder: "y"
            )
            Button { state.deleteExtraPoint(for: equationID, pairID: pair.id) } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.black.opacity(0.35))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .overlay(Rectangle().stroke(.black.opacity(0.10), lineWidth: 0.5))
        }
    }

    private func pointsEditCell(
        equationID: UUID,
        pairID: UUID,
        column: PointTableCellEdit.Column,
        value: Double?,
        placeholder: String
    ) -> some View {
        let cell = PointTableCellEdit(equationID: equationID, pairID: pairID, column: column)
        let isEditing = editingPointCell == cell
        let display = isEditing ? editingPointCellText : value.map { CalculatorResultFormatter.string(for: $0) } ?? ""

        return Button {
            beginPointCellEdit(cell, currentValue: value)
        } label: {
            Text(display.isEmpty ? placeholder : display)
                .font(.system(size: 18, weight: isEditing ? .semibold : .regular, design: .serif))
                .foregroundStyle(display.isEmpty ? .black.opacity(0.30) : .black.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 2)
                .background(isEditing ? GraphCalculatorTheme.blue.opacity(0.16) : Color.clear)
        }
        .buttonStyle(.plain)
        .overlay(
            Rectangle()
                .stroke(isEditing ? GraphCalculatorTheme.blue.opacity(0.95) : .black.opacity(0.10), lineWidth: isEditing ? 1.5 : 0.5)
        )
    }

    private func beginPointCellEdit(_ cell: PointTableCellEdit, currentValue: Double?) {
        if editingPointCell != nil {
            commitPointCellEdit()
        }
        editingPointCell = cell
        editingPointCellText = currentValue.map { CalculatorResultFormatter.string(for: $0) } ?? ""
        editingPointCellReplacesOnInput = true
    }

    private func commitPointCellEdit() {
        guard let editingPointCell else { return }
        let value = Double(editingPointCellText.replacingOccurrences(of: "−", with: "-"))
        switch editingPointCell.column {
        case .x:
            state.updateExtraPointX(for: editingPointCell.equationID, pairID: editingPointCell.pairID, value: value)
        case .y:
            state.updateExtraPointY(for: editingPointCell.equationID, pairID: editingPointCell.pairID, value: value)
        }
    }

    private func cancelPointCellEdit() {
        editingPointCell = nil
        editingPointCellText = ""
        editingPointCellReplacesOnInput = false
    }

    private func finishPointCellEdit() {
        commitPointCellEdit()
        cancelPointCellEdit()
    }

    private func commitPointCellEditAndAdvance() {
        guard let editingPointCell else { return }
        commitPointCellEdit()
        advancePointCellEdit(from: editingPointCell)
    }

    private func appendPointCellInput(_ text: String) {
        guard editingPointCell != nil else { return }
        switch text {
        case "0"..."9", ".":
            if editingPointCellReplacesOnInput {
                editingPointCellText = text
            } else {
                editingPointCellText += text
            }
            editingPointCellReplacesOnInput = false
        case "-":
            if editingPointCellReplacesOnInput {
                editingPointCellText = "-"
                editingPointCellReplacesOnInput = false
            } else if editingPointCellText.hasPrefix("-") || editingPointCellText.hasPrefix("−") {
                editingPointCellText.removeFirst()
            } else {
                editingPointCellText = "-" + editingPointCellText
            }
        default:
            break
        }
    }

    private func deletePointCellInput() {
        guard editingPointCell != nil else { return }
        if editingPointCellReplacesOnInput {
            editingPointCellText = ""
            editingPointCellReplacesOnInput = false
        } else if !editingPointCellText.isEmpty {
            editingPointCellText.removeLast()
        }
    }

    private func advancePointCellEdit(from cell: PointTableCellEdit) {
        guard let rows = state.pointRows[cell.equationID],
              let index = rows.firstIndex(where: { $0.id == cell.pairID }) else {
            cancelPointCellEdit()
            return
        }

        switch cell.column {
        case .x:
            beginNextPointCellEdit(equationID: cell.equationID, after: index, column: .x)
        case .y:
            let nextIndex = rows.index(after: index)
            if rows.indices.contains(nextIndex) {
                let nextRow = rows[nextIndex]
                let next = PointTableCellEdit(equationID: cell.equationID, pairID: nextRow.id, column: .y)
                beginPointCellEdit(next, currentValue: nextRow.y)
            } else {
                cancelPointCellEdit()
            }
        }
    }

    private func preparePointTableForEntry(equationID: UUID) {
        let rows = state.extraPoints(for: equationID)
        if rows.isEmpty {
            addPointRowAndBeginEditing(equationID: equationID)
            return
        }
        if let incomplete = rows.first(where: { $0.x == nil || $0.y == nil }) {
            let column: PointTableCellEdit.Column = incomplete.x == nil ? .x : .y
            let cell = PointTableCellEdit(equationID: equationID, pairID: incomplete.id, column: column)
            beginPointCellEdit(cell, currentValue: column == .x ? incomplete.x : incomplete.y)
        }
    }

    private func addPointRowAndBeginEditing(equationID: UUID) {
        state.addExtraPoint(for: equationID)
        guard let newRow = state.pointRows[equationID]?.last else { return }
        let cell = PointTableCellEdit(equationID: equationID, pairID: newRow.id, column: .x)
        beginPointCellEdit(cell, currentValue: newRow.x)
    }

    private func beginNextPointCellEdit(equationID: UUID, after index: Int, column: PointTableCellEdit.Column) {
        let predictedX = column == .x ? nextPredictedX(for: equationID) : nil
        let nextIndex = index + 1
        if let rows = state.pointRows[equationID], rows.indices.contains(nextIndex) {
            let nextRow = rows[nextIndex]
            if column == .x, nextRow.x == nil, let predictedX {
                state.updateExtraPointX(for: equationID, pairID: nextRow.id, value: predictedX)
            }
            let next = PointTableCellEdit(equationID: equationID, pairID: nextRow.id, column: column)
            let value = column == .x ? (state.pointRows[equationID]?[nextIndex].x ?? nextRow.x) : nextRow.y
            beginPointCellEdit(next, currentValue: value)
            return
        }

        state.addExtraPoint(for: equationID)
        guard let newRow = state.pointRows[equationID]?.last else {
            cancelPointCellEdit()
            return
        }
        if column == .x, let predictedX {
            state.updateExtraPointX(for: equationID, pairID: newRow.id, value: predictedX)
        }
        let next = PointTableCellEdit(equationID: equationID, pairID: newRow.id, column: column)
        let value = column == .x ? predictedX : newRow.y
        beginPointCellEdit(next, currentValue: value)
    }

    private func pointTableXValuesInDisplayOrder(for equationID: UUID) -> [Double] {
        var values: [Double] = []
        if let typed = typedPoint(for: equationID) {
            values.append(typed.0)
        }
        values.append(contentsOf: state.extraPoints(for: equationID).compactMap(\.x))
        return values
    }

    private func nextPredictedX(for equationID: UUID) -> Double? {
        let values = pointTableXValuesInDisplayOrder(for: equationID)
        guard values.count >= 3 else { return nil }
        let tail = Array(values.suffix(3))
        let firstDelta = tail[1] - tail[0]
        let secondDelta = tail[2] - tail[1]
        let tolerance = max(abs(firstDelta), abs(secondDelta), 1) * 1e-8
        guard abs(firstDelta - secondDelta) <= tolerance else { return nil }
        return tail[2] + secondDelta
    }

    private func completePointTablePoints(for equationID: UUID) -> [CGPoint] {
        var points: [CGPoint] = []
        if let typed = typedPoint(for: equationID) {
            points.append(CGPoint(x: typed.0, y: typed.1))
        }
        points.append(contentsOf: state.extraPoints(for: equationID).compactMap { pair in
            guard let x = pair.x, let y = pair.y else { return nil }
            return CGPoint(x: x, y: y)
        })
        return points
    }

    private func hasIncompletePointRows(for equationID: UUID) -> Bool {
        state.extraPoints(for: equationID).contains { pair in
            pair.x == nil || pair.y == nil
        }
    }

    private func canShowRegressionMenu(equationID: UUID) -> Bool {
        completePointTablePoints(for: equationID).count >= 2 && !hasIncompletePointRows(for: equationID)
    }

    private func zoomToDataPoints(equationID: UUID) {
        let points = completePointTablePoints(for: equationID)
        guard points.count >= 2 else { return }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let minX = xs.min() ?? -10
        let maxX = xs.max() ?? 10
        let minY = ys.min() ?? -10
        let maxY = ys.max() ?? 10
        let xSpan = max(maxX - minX, 2)
        let ySpan = max(maxY - minY, 2)
        let xPadding = xSpan * 0.18
        let yPadding = ySpan * 0.18
        state.graphWindow = limitedGraphWindow(
            GraphWindow(
                xMin: minX - xPadding,
                xMax: maxX + xPadding,
                yMin: minY - yPadding,
                yMax: maxY + yPadding
            )
        )
    }

    private func insertRegression(_ kind: RegressionKind, equationID: UUID, after sourceIndex: Int) {
        let points = completePointTablePoints(for: equationID)
        guard !hasIncompletePointRows(for: equationID),
              let result = regressionResult(kind, points: points) else {
            return
        }
        let regressionID = state.insertExpression(result.expression, after: sourceIndex, matchingStyleOf: sourceIndex)
        state.regressionRows[regressionID] = GraphRegressionRow(rSquared: result.rSquared, sourceEquationID: equationID)
    }

    private func regressionResult(_ kind: RegressionKind, points: [CGPoint]) -> (expression: String, rSquared: Double)? {
        guard points.count >= kind.minimumPointCount,
              let coefficients = polynomialRegression(points, degree: kind.degree) else {
            return nil
        }
        let expression = polynomialExpression(coefficients)
        let rSquared = regressionRSquared(points: points, coefficients: coefficients)
        return (expression, rSquared)
    }

    private func polynomialRegression(_ points: [CGPoint], degree: Int) -> [Double]? {
        let size = degree + 1
        var matrix = Array(repeating: Array(repeating: 0.0, count: size + 1), count: size)

        for row in 0..<size {
            for column in 0..<size {
                matrix[row][column] = points.reduce(0) { partial, point in
                    partial + pow(point.x, Double(row + column))
                }
            }
            matrix[row][size] = points.reduce(0) { partial, point in
                partial + point.y * pow(point.x, Double(row))
            }
        }

        guard let ascending = solveLinearSystem(matrix) else { return nil }
        return ascending.reversed()
    }

    private func solveLinearSystem(_ input: [[Double]]) -> [Double]? {
        guard let width = input.first?.count, width == input.count + 1 else { return nil }
        var matrix = input
        let size = matrix.count

        for pivot in 0..<size {
            guard let bestRow = (pivot..<size).max(by: { abs(matrix[$0][pivot]) < abs(matrix[$1][pivot]) }),
                  abs(matrix[bestRow][pivot]) > 1e-10 else {
                return nil
            }
            if bestRow != pivot {
                matrix.swapAt(bestRow, pivot)
            }

            let divisor = matrix[pivot][pivot]
            for column in pivot...size {
                matrix[pivot][column] /= divisor
            }
            for row in 0..<size where row != pivot {
                let factor = matrix[row][pivot]
                for column in pivot...size {
                    matrix[row][column] -= factor * matrix[pivot][column]
                }
            }
        }

        return matrix.map { $0[size] }
    }

    private func polynomialExpression(_ descendingCoefficients: [Double]) -> String {
        let degree = descendingCoefficients.count - 1
        var expression = "y="
        var hasTerm = false
        for (offset, coefficient) in descendingCoefficients.enumerated() {
            guard abs(coefficient) >= 1e-10 else { continue }
            let power = degree - offset
            if power == 0 {
                expression += hasTerm ? regressionConstantText(coefficient) : regressionCoefficientNumber(coefficient)
            } else {
                let variable = power == 1 ? "x" : "x^\(power)"
                expression += regressionCoefficientText(coefficient, variable: variable, includesLeadingSign: hasTerm)
            }
            hasTerm = true
        }
        return hasTerm ? expression : "y=0"
    }

    private func regressionCoefficientText(_ value: Double, variable: String, includesLeadingSign: Bool = false) -> String {
        let rounded = abs(value) < 0.00005 ? 0 : value
        let magnitude = abs(rounded)
        let number = regressionCoefficientNumber(magnitude)
        let sign: String
        if includesLeadingSign {
            sign = rounded < 0 ? "-" : "+"
        } else {
            sign = rounded < 0 ? "-" : ""
        }
        if abs(magnitude - 1) < 0.00005 {
            return "\(sign)\(variable)"
        }
        return "\(sign)\(number)*\(variable)"
    }

    private func regressionConstantText(_ value: Double) -> String {
        guard abs(value) >= 0.00005 else { return "" }
        let sign = value < 0 ? "-" : "+"
        return "\(sign)\(regressionCoefficientNumber(abs(value)))"
    }

    private func regressionCoefficientNumber(_ value: Double) -> String {
        let rounded = (value * 10_000).rounded() / 10_000
        return String(format: "%.4f", rounded)
            .trimmingCharacters(in: CharacterSet(charactersIn: "0"))
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private func regressionRSquared(points: [CGPoint], coefficients: [Double]) -> Double {
        let meanY = points.reduce(0) { $0 + $1.y } / Double(points.count)
        let total = points.reduce(0) { $0 + pow($1.y - meanY, 2) }
        guard total > 1e-12 else { return 1 }
        let residual = points.reduce(0) { partial, point in
            let predicted = evaluatePolynomial(coefficients, at: point.x)
            return partial + pow(point.y - predicted, 2)
        }
        return min(max(1 - residual / total, 0), 1)
    }

    private func evaluatePolynomial(_ descendingCoefficients: [Double], at x: Double) -> Double {
        descendingCoefficients.reduce(0) { partial, coefficient in
            partial * x + coefficient
        }
    }

    private func coefficientText(_ value: Double, variable: String, includesLeadingSign: Bool = false) -> String {
        let rounded = abs(value) < 1e-10 ? 0 : value
        let magnitude = abs(rounded)
        let number = CalculatorResultFormatter.string(for: magnitude)
        let sign: String
        if includesLeadingSign {
            sign = rounded < 0 ? "-" : "+"
        } else {
            sign = rounded < 0 ? "-" : ""
        }
        if abs(magnitude - 1) < 1e-10 {
            return "\(sign)\(variable)"
        }
        return "\(sign)\(number)*\(variable)"
    }

    private func constantText(_ value: Double) -> String {
        guard abs(value) >= 1e-10 else { return "" }
        let sign = value < 0 ? "-" : "+"
        return "\(sign)\(CalculatorResultFormatter.string(for: abs(value)))"
    }

    private func tableSettingsPopover(equationID: UUID) -> some View {
        let settings = state.functionTableSettings(for: equationID)
        return VStack(alignment: .leading, spacing: 14) {
            Text("Table Settings")
                .font(.headline)
            tableSettingField(
                title: "Table start",
                value: settings.start,
                set: { state.setFunctionTableStart($0, for: equationID) }
            )
            tableSettingField(
                title: "Table step (Δ)",
                value: settings.delta,
                set: { state.setFunctionTableDelta($0, for: equationID) }
            )
            Text("These also set the graph trace step.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 260)
    }

    private func tableSettingField(title: String, value: Double, set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.black.opacity(0.8))
            Spacer()
            TextField(
                "",
                text: Binding(
                    get: { CalculatorResultFormatter.string(for: value) },
                    set: { if let v = Double($0.replacingOccurrences(of: "−", with: "-")) { set(v) } }
                )
            )
            .font(.system(size: 15, weight: .semibold, design: .serif))
            .multilineTextAlignment(.trailing)
            .keyboardType(.numbersAndPunctuation)
            .frame(width: 90)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.black.opacity(0.14), lineWidth: 0.5))
        }
    }

    private struct FunctionTableDescriptor: Identifiable {
        enum Kind: Equatable {
            case yEquation
            case namedFunction(String)
            case expression
        }

        var equationID: UUID
        var index: Int
        var label: String
        var source: String
        var kind: Kind

        var id: UUID { equationID }
    }

    /// The graphable `y = f(x)` source for a row that qualifies for a function table.
    private func functionTableSource(for equationID: UUID) -> String? {
        functionTableDescriptor(for: equationID)?.source
    }

    private func functionTableDescriptor(for equationID: UUID) -> FunctionTableDescriptor? {
        guard let index = state.expressions.firstIndex(where: { $0.id == equationID }) else { return nil }
        let expression = state.expressions[index].expression
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedFunction = parsedFunctionDefinition(from: trimmed)
        let isYEquation = isYEquationSource(trimmed)

        switch resolvedRows.first(where: { $0.index == index })?.plot {
        case .yRelation(let source, .equal):
            return FunctionTableDescriptor(
                equationID: equationID,
                index: index,
                label: "y",
                source: source,
                kind: .yEquation
            )
        case .curve(let source):
            if isYEquation {
                return FunctionTableDescriptor(
                    equationID: equationID,
                    index: index,
                    label: "y",
                    source: source,
                    kind: .yEquation
                )
            }
            if let parsedFunction, parsedFunction.variable == "x" {
                return FunctionTableDescriptor(
                    equationID: equationID,
                    index: index,
                    label: "\(parsedFunction.name)(x)",
                    source: source,
                    kind: .namedFunction(parsedFunction.name)
                )
            }
            return FunctionTableDescriptor(
                equationID: equationID,
                index: index,
                label: "f(x)",
                source: source,
                kind: .expression
            )
        default:
            return nil
        }
    }

    private func isYEquationSource(_ source: String) -> Bool {
        let compact = source.replacingOccurrences(of: " ", with: "")
        guard let equals = compact.firstIndex(of: "=") else { return false }
        let left = String(compact[..<equals])
        let right = String(compact[compact.index(after: equals)...])
        return left == "y" || right == "y"
    }

    private func secondaryFunctionTableDescriptor(for primaryID: UUID) -> FunctionTableDescriptor? {
        guard let secondaryID = state.secondaryFunctionTableEquationIDs[primaryID] else { return nil }
        guard let descriptor = functionTableDescriptor(for: secondaryID),
              secondaryFunctionTableCandidates(for: primaryID).contains(where: { $0.equationID == secondaryID }) else { return nil }
        return descriptor
    }

    private func secondaryFunctionTableCandidates(for primaryID: UUID) -> [FunctionTableDescriptor] {
        guard let primary = functionTableDescriptor(for: primaryID) else { return [] }
        return state.expressions.compactMap { equation -> FunctionTableDescriptor? in
            guard equation.id != primaryID,
                  equation.isEnabled,
                  let candidate = functionTableDescriptor(for: equation.id),
                  isCompatibleSecondaryFunctionTableColumn(primary: primary, candidate: candidate) else {
                return nil
            }
            return candidate
        }
    }

    private func isCompatibleSecondaryFunctionTableColumn(
        primary: FunctionTableDescriptor,
        candidate: FunctionTableDescriptor
    ) -> Bool {
        switch candidate.kind {
        case .namedFunction(let candidateName):
            if case .namedFunction(let primaryName) = primary.kind {
                return primaryName != candidateName
            }
            return true
        case .yEquation:
            if case .yEquation = primary.kind { return false }
            return true
        case .expression:
            return false
        }
    }

    private func parsedFunctionDefinition(from source: String) -> (name: String, variable: String)? {
        let compact = source.replacingOccurrences(of: " ", with: "")
        guard let equals = compact.firstIndex(of: "="),
              let openParen = compact.firstIndex(of: "("),
              let closeParen = compact.firstIndex(of: ")"),
              openParen < closeParen,
              closeParen < equals else {
            return nil
        }

        let name = String(compact[..<openParen])
        let variable = String(compact[compact.index(after: openParen)..<closeParen])
        guard name.count == 1,
              variable == "x" else {
            return nil
        }
        return (name, variable)
    }

    /// The ordered pair typed into a point row, if the row resolves to a point.
    private func typedPoint(for equationID: UUID) -> (Double, Double)? {
        guard let index = state.expressions.firstIndex(where: { $0.id == equationID }) else { return nil }
        if case .point(let x, let y)? = resolvedRows.first(where: { $0.index == index })?.plot {
            return (x, y)
        }
        return nil
    }

    private func clampTableSize(_ size: CGSize, in containerSize: CGSize) -> CGSize {
        CGSize(
            width: min(max(size.width, 260), max(260, containerSize.width - 24)),
            height: min(max(size.height, 240), max(240, containerSize.height - 24))
        )
    }

    private func tableWindowCenter(size: CGSize, in containerSize: CGSize) -> CGPoint {
        let fallback = CGPoint(x: containerSize.width * 0.5, y: containerSize.height * 0.42)
        return clamp(center: state.tableWindowPosition ?? fallback, size: size, in: containerSize)
    }

    private func tableDragGesture(currentCenter: CGPoint, size: CGSize, in containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let base = tableDragStartCenter ?? currentCenter
                if tableDragStartCenter == nil { tableDragStartCenter = base }
                let proposed = CGPoint(x: base.x + value.translation.width, y: base.y + value.translation.height)
                let clamped = clamp(center: proposed, size: size, in: containerSize)
                let snapshotImage = dragProxy?.snapshotImage ?? tableDragSnapshot(size: size, center: currentCenter, in: containerSize)
                let presentation = GraphCalculatorDragPresentation(
                    kind: .table,
                    title: "Table",
                    systemImage: "tablecells",
                    center: base,
                    offset: CGSize(width: clamped.x - base.x, height: clamped.y - base.y),
                    size: size,
                    snapshotPNGData: state.activeDragPresentation?.snapshotPNGData ?? snapshotPNGData(from: snapshotImage)
                )
                setWithoutAnimation {
                    state.activeDragPresentation = presentation
                    dragProxy = GraphCalculatorDragProxy(
                        presentation: presentation,
                        snapshotImage: snapshotImage
                    )
                }
            }
            .onEnded { _ in
                let offset = dragProxy?.offset ?? .zero
                state.tableWindowPosition = CGPoint(
                    x: currentCenter.x + offset.width,
                    y: currentCenter.y + offset.height
                )
                dragProxy = nil
                state.activeDragPresentation = nil
                tableDragStartCenter = nil
            }
    }

    private func tableResizeGesture(currentCenter: CGPoint, in containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let start = tableResizeStart ?? (
                    size: state.tableWindowSize,
                    topLeft: CGPoint(x: currentCenter.x - state.tableWindowSize.width / 2, y: currentCenter.y - state.tableWindowSize.height / 2)
                )
                if tableResizeStart == nil { tableResizeStart = start }
                let proposed = CGSize(width: start.size.width + value.translation.width, height: start.size.height + value.translation.height)
                let clamped = clampTableSize(proposed, in: containerSize)
                let center = clamp(
                    center: CGPoint(x: start.topLeft.x + clamped.width / 2, y: start.topLeft.y + clamped.height / 2),
                    size: clamped,
                    in: containerSize
                )
                setWithoutAnimation {
                    tableResizeLive = (size: clamped, center: center)
                }
            }
            .onEnded { _ in
                if let live = tableResizeLive {
                    state.tableWindowSize = live.size
                    state.tableWindowPosition = live.center
                }
                tableResizeLive = nil
                tableResizeStart = nil
            }
    }

    private func dragProxyView(_ proxy: GraphCalculatorDragProxy) -> some View {
        Group {
            #if os(iOS)
            if let snapshotImage = proxy.snapshotImage {
                Image(uiImage: snapshotImage)
                    .resizable()
                    .scaledToFill()
            } else {
                fallbackDragProxyView(proxy)
            }
            #else
            fallbackDragProxyView(proxy)
            #endif
        }
        .clipShape(RoundedRectangle(cornerRadius: proxy.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: proxy.cornerRadius, style: .continuous).strokeBorder(proxy.stroke, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.24), radius: 12, y: 5)
    }

    private func fallbackDragProxyView(_ proxy: GraphCalculatorDragProxy) -> some View {
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
    }

    private enum GraphIconButtonStyle {
        case standard
        case destructive
    }

    private func graphControlOverlay(
        placementRect: CGRect? = nil,
        containerSize: CGSize? = nil,
        onHome: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 10) {
            Button { isCalculatorMenuPresented.toggle() } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.black.opacity(0.65))
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.black.opacity(0.15), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isCalculatorMenuPresented, arrowEdge: .trailing) {
                calculatorMenu
                    .presentationCompactAdaptation(.popover)
            }

            graphIconButton("camera.fill") {
                captureGraphSnapshot(placementRect: placementRect, containerSize: containerSize)
            }
            .disabled(onGraphSnapshot == nil)
            .opacity(onGraphSnapshot == nil ? 0.45 : 1)

            graphIconButton("plus") { zoom(by: 1.35) }
            graphIconButton("minus") { zoom(by: 1 / 1.35) }
            if let onHome {
                graphIconButton("house.fill") { onHome() }
            }
        }
        .padding(10)
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
        if editingPointCell != nil {
            appendPointCellInput(text)
        } else if editingSliderBound != nil {
            appendSliderBoundInput(text)
        } else if text == "/" {
            fractionCursorExitedAt = nil
            insertDivision()
        } else {
            fractionCursorExitedAt = nil
            state.insert(text)
        }
    }

    private func insertDivision() {
        let expression = state.selectedExpression
        if expression.isEmpty {
            state.insert("/")
            state.cursorOffset = 0
        } else {
            state.insert("/")
        }
    }

    private func moveExpressionCursorRight() {
        let expression = state.selectedExpression
        let currentOffset = min(max(state.cursorOffset, 0), expression.count)
        let fractions = editableExpressionTokens(for: expression)?.compactMap { token -> EditableFractionToken? in
            if case .fraction(let fraction) = token { return fraction }
            return nil
        } ?? []
        if let fraction = fractions.first(where: { fraction in
            !fraction.denominatorRange.isEmpty && currentOffset == fraction.denominatorRange.upperBound
        }) {
            fractionCursorExitedAt = fraction.denominatorRange.upperBound
            return
        }
        if let fraction = editableExpressionTokens(for: expression)?.compactMap({ token -> EditableFractionToken? in
            if case .fraction(let fraction) = token { return fraction }
            return nil
        }).first(where: { fraction in
            currentOffset >= fraction.numeratorRange.lowerBound && currentOffset <= fraction.slashOffset
        }) {
            fractionCursorExitedAt = nil
            state.cursorOffset = fraction.denominatorRange.lowerBound
            return
        }
        fractionCursorExitedAt = nil
        state.moveCursorRight()
    }

    /// Keypad delete: edits the active slider bound if one is open, otherwise the expression.
    private func keypadDelete() {
        if editingPointCell != nil {
            deletePointCellInput()
        } else if editingSliderBound != nil {
            deleteSliderBoundInput()
        } else {
            state.deleteLastCharacter()
        }
    }

    /// Keypad return: commits an active slider-bound edit, otherwise adds a new expression row.
    private func keypadReturn() {
        if editingPointCell != nil {
            commitPointCellEditAndAdvance()
        } else if editingSliderBound != nil {
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
                // While tracing, drags on the curve/trace points move the trace; off-curve drags pan.
                if isTracing, updateTrace(at: value.location, size: size) {
                    graphPanStart = value.translation
                    return
                }
                let delta = CGSize(
                    width: value.translation.width - graphPanStart.width,
                    height: value.translation.height - graphPanStart.height
                )
                graphPanStart = value.translation
                state.graphWindow = CalculatorGraphGeometry.pan(window: state.graphWindow, byViewTranslation: delta, size: size)
            }
            .onEnded { _ in graphPanStart = .zero }
    }

    /// Tapping on or near an x-intercept of a graphed curve shows its ordered pair.
    /// Tapping elsewhere on the graph clears the readout.
    private func graphTapGesture(size: CGSize) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                handleGraphTap(at: value.location, size: size)
            }
    }

    /// Screen-space tolerance (points) for treating a tap as "on" an x-intercept.
    private let interceptTapTolerance: CGFloat = 34

    private func handleGraphTap(at viewPoint: CGPoint, size: CGSize) {
        if isTracing {
            updateTrace(at: viewPoint, size: size)
            return
        }

        state.selectedPoint = nearestGraphReadout(
            at: viewPoint,
            size: size,
            including: [.xIntercept, .yIntercept, .intersection, .plottedPoint]
        )
    }

    private func nearestGraphReadout(
        at viewPoint: CGPoint,
        size: CGSize,
        including includedKinds: Set<GraphCalculatorPointReadout.Kind>
    ) -> GraphCalculatorPointReadout? {
        let window = state.graphWindow
        let variables = graphVariableValues
        var best: (point: GraphCalculatorPointReadout, distance: CGFloat)?

        func consider(x: Double, y: Double, index: Int?, kind: GraphCalculatorPointReadout.Kind) {
            guard includedKinds.contains(kind) else { return }
            let screen = CalculatorGraphGeometry.viewPoint(
                forGraph: CGPoint(x: x, y: y),
                window: window,
                size: size
            )
            guard screen.x.isFinite, screen.y.isFinite else { return }
            let distance = hypot(screen.x - viewPoint.x, screen.y - viewPoint.y)
            guard distance <= interceptTapTolerance else { return }
            if best == nil || distance < best!.distance {
                best = (GraphCalculatorPointReadout(x: x, y: y, expressionIndex: index, kind: kind), distance)
            }
        }

        // Compile graphable rows once so intercepts and intersections can share the same inputs.
        let curves: [(index: Int, source: String, compiled: CalculatorExpression)] = resolvedRows.compactMap { row in
            guard let source = interceptSourceExpression(for: row.plot),
                  let compiled = try? engine.compile(source) else {
                return nil
            }
            return (row.index, source, compiled)
        }
        let implicitCurves: [(index: Int, source: String, compiled: CalculatorExpression)] = resolvedRows.compactMap { row in
            guard case .implicitRelation(let source)? = row.plot,
                  let compiled = try? engine.compile(source) else {
                return nil
            }
            return (row.index, source, compiled)
        }

        for curve in curves {
            // x-intercepts: where the curve crosses y = 0.
            for root in xIntercepts(of: curve.compiled, in: window, variableValues: variables) {
                consider(x: root, y: 0, index: curve.index, kind: .xIntercept)
            }

            // y-intercept: the single point (0, f(0)), if the curve is defined at x = 0.
            if let yValue = evaluate(compiled: curve.compiled, at: 0, variableValues: variables) {
                consider(x: 0, y: yValue, index: curve.index, kind: .yIntercept)
            }
        }

        for implicit in implicitCurves {
            for root in implicitAxisRoots(of: implicit.compiled, fixedY: 0, in: window, variableValues: variables) {
                consider(x: root, y: 0, index: implicit.index, kind: .xIntercept)
            }
            for root in implicitAxisRoots(of: implicit.compiled, fixedX: 0, in: window, variableValues: variables) {
                consider(x: 0, y: root, index: implicit.index, kind: .yIntercept)
            }
        }

        if includedKinds.contains(.intersection) {
            // Intersections: for each pair of explicit curves, f(x) = g(x) where f(x) - g(x) crosses zero.
            for i in curves.indices {
                for j in (i + 1)..<curves.count {
                    let a = curves[i]
                    let b = curves[j]
                    guard let difference = try? engine.compile("(\(a.source))-(\(b.source))") else { continue }
                    for root in xIntercepts(of: difference, in: window, variableValues: variables) {
                        guard let y = evaluate(compiled: a.compiled, at: root, variableValues: variables) else { continue }
                        consider(x: root, y: y, index: nil, kind: .intersection)
                    }
                }
            }

            for curve in curves {
                for implicit in implicitCurves {
                    for point in intersections(of: curve.compiled, withImplicit: implicit.compiled, in: window, variableValues: variables) {
                        consider(x: point.x, y: point.y, index: nil, kind: .intersection)
                    }
                }
            }

            for i in implicitCurves.indices {
                for j in (i + 1)..<implicitCurves.count {
                    for point in intersections(ofImplicit: implicitCurves[i].compiled, and: implicitCurves[j].compiled, in: window, variableValues: variables) {
                        consider(x: point.x, y: point.y, index: nil, kind: .intersection)
                    }
                }
            }
        }

        if includedKinds.contains(.plottedPoint) {
            // Plotted points: typed ordered-pair rows plus any extra points attached from that row's table.
            for row in resolvedRows {
                guard state.expressions.indices.contains(row.index) else { continue }
                let index = row.index
                if case .point(let x, let y)? = row.plot {
                    consider(x: x, y: y, index: index, kind: .plottedPoint)
                }

                let equationID = state.expressions[index].id
                for pair in state.extraPoints(for: equationID) {
                    guard let x = pair.x, let y = pair.y else { continue }
                    consider(x: x, y: y, index: index, kind: .plottedPoint)
                }
            }
        }

        return best?.point
    }

    /// Evaluates a compiled `y = f(x)` at a specific x, returning nil when undefined or non-finite.
    private func evaluate(
        compiled: CalculatorExpression,
        at x: Double,
        variableValues: [String: Double]
    ) -> Double? {
        var variables = variableValues
        variables["x"] = x
        let value = try? engine.evaluate(compiled: compiled, angleMode: .radians, variables: variables)
        guard let value, value.isFinite else { return nil }
        return value
    }

    private func evaluateImplicit(
        compiled: CalculatorExpression,
        x: Double,
        y: Double,
        variableValues: [String: Double]
    ) -> Double? {
        var variables = variableValues
        variables["x"] = x
        variables["y"] = y
        let value = try? engine.evaluate(compiled: compiled, angleMode: .radians, variables: variables)
        guard let value, value.isFinite else { return nil }
        return value
    }

    private func implicitAxisRoots(
        of compiled: CalculatorExpression,
        fixedY y: Double,
        in window: GraphWindow,
        variableValues: [String: Double]
    ) -> [Double] {
        zeroes(in: window.xMin...window.xMax, window: window) { x in
            evaluateImplicit(compiled: compiled, x: x, y: y, variableValues: variableValues)
        }
    }

    private func implicitAxisRoots(
        of compiled: CalculatorExpression,
        fixedX x: Double,
        in window: GraphWindow,
        variableValues: [String: Double]
    ) -> [Double] {
        zeroes(in: window.yMin...window.yMax, window: window) { y in
            evaluateImplicit(compiled: compiled, x: x, y: y, variableValues: variableValues)
        }
    }

    private func intersections(
        of curve: CalculatorExpression,
        withImplicit implicit: CalculatorExpression,
        in window: GraphWindow,
        variableValues: [String: Double]
    ) -> [CGPoint] {
        let roots = zeroes(in: window.xMin...window.xMax, window: window) { x in
            guard let y = evaluate(compiled: curve, at: x, variableValues: variableValues) else { return nil }
            return evaluateImplicit(compiled: implicit, x: x, y: y, variableValues: variableValues)
        }
        return roots.compactMap { x in
            guard let y = evaluate(compiled: curve, at: x, variableValues: variableValues),
                  y >= window.yMin,
                  y <= window.yMax else {
                return nil
            }
            return CGPoint(x: x, y: y)
        }
    }

    private func intersections(
        ofImplicit first: CalculatorExpression,
        and second: CalculatorExpression,
        in window: GraphWindow,
        variableValues: [String: Double]
    ) -> [CGPoint] {
        let segments = implicitContourSegments(of: first, in: window, variableValues: variableValues)
        var points: [CGPoint] = []
        for segment in segments {
            guard let aValue = evaluateImplicit(compiled: second, x: segment.start.x, y: segment.start.y, variableValues: variableValues),
                  let bValue = evaluateImplicit(compiled: second, x: segment.end.x, y: segment.end.y, variableValues: variableValues) else {
                continue
            }
            if abs(aValue) < 1e-8 {
                appendPoint(segment.start, to: &points, window: window)
            } else if abs(bValue) < 1e-8 {
                appendPoint(segment.end, to: &points, window: window)
            } else if (aValue < 0) != (bValue < 0) {
                let t = abs(aValue) / (abs(aValue) + abs(bValue))
                let x = segment.start.x + (segment.end.x - segment.start.x) * t
                let y = segment.start.y + (segment.end.y - segment.start.y) * t
                appendPoint(CGPoint(x: x, y: y), to: &points, window: window)
            }
        }
        return points
    }

    private func implicitContourSegments(
        of compiled: CalculatorExpression,
        in window: GraphWindow,
        variableValues: [String: Double]
    ) -> [(start: CGPoint, end: CGPoint)] {
        let columns = 140
        let rows = 140
        let dx = window.width / Double(columns)
        let dy = window.height / Double(rows)
        guard dx.isFinite, dy.isFinite, dx > 0, dy > 0 else { return [] }

        var values = Array(repeating: Array<Double?>(repeating: nil, count: rows + 1), count: columns + 1)
        for ix in 0...columns {
            let x = window.xMin + Double(ix) * dx
            for iy in 0...rows {
                let y = window.yMin + Double(iy) * dy
                values[ix][iy] = evaluateImplicit(compiled: compiled, x: x, y: y, variableValues: variableValues)
            }
        }

        var segments: [(start: CGPoint, end: CGPoint)] = []
        for ix in 0..<columns {
            for iy in 0..<rows {
                guard let bottomLeft = values[ix][iy],
                      let bottomRight = values[ix + 1][iy],
                      let topRight = values[ix + 1][iy + 1],
                      let topLeft = values[ix][iy + 1] else {
                    continue
                }

                let x0 = window.xMin + Double(ix) * dx
                let x1 = x0 + dx
                let y0 = window.yMin + Double(iy) * dy
                let y1 = y0 + dy
                let corners = [
                    (value: bottomLeft, point: CGPoint(x: x0, y: y0)),
                    (value: bottomRight, point: CGPoint(x: x1, y: y0)),
                    (value: topRight, point: CGPoint(x: x1, y: y1)),
                    (value: topLeft, point: CGPoint(x: x0, y: y1))
                ]
                let edgePairs = [(0, 1), (1, 2), (2, 3), (3, 0)]
                let crossings = edgePairs.compactMap { a, b -> CGPoint? in
                    zeroCrossing(from: corners[a], to: corners[b])
                }
                guard crossings.count >= 2 else { continue }
                for pairIndex in stride(from: 0, to: crossings.count - 1, by: 2) {
                    segments.append((crossings[pairIndex], crossings[pairIndex + 1]))
                }
            }
        }
        return segments
    }

    /// The `y = f(x)` expression body to search for x-intercepts, if this plot has one.
    private func interceptSourceExpression(for plot: GraphCalculatorPlot?) -> String? {
        switch plot {
        case .curve(let source):
            return source
        case .yRelation(let source, .equal):
            return source
        default:
            return nil
        }
    }

    /// Finds x values where the compiled `y = f(x)` crosses zero within the visible window.
    /// Samples densely, detects sign changes, and refines each with bisection. Sign changes
    /// across asymptotes (where the refined value is not near zero) are discarded.
    private func xIntercepts(
        of compiled: CalculatorExpression,
        in window: GraphWindow,
        variableValues: [String: Double]
    ) -> [Double] {
        func evaluate(_ x: Double) -> Double? {
            self.evaluate(compiled: compiled, at: x, variableValues: variableValues)
        }

        let samples = CalculatorGraphGeometry.sample(window: window, count: 600, eval: evaluate)
        // A real root must refine to a value very close to zero. This rejects asymptote
        // crossings (e.g. 1/x, tan x), where bisection lands on the asymptote x but |f| stays large.
        let acceptTolerance = window.height * 1e-4
        var roots: [Double] = []
        var previous: CalculatorGraphGeometry.Sample?

        for sample in samples {
            defer { previous = sample }
            guard let y = sample.y else { continue }
            // Exact-zero sample: it is already the crossing, no refinement needed.
            if y == 0 {
                appendRoot(sample.x, to: &roots, window: window)
                continue
            }
            guard let previous, let previousY = previous.y, previousY != 0 else { continue }
            // Only a strict sign change brackets a crossing; always bisect to the true root
            // rather than accepting a nearby sample, so the marker lands exactly on the line.
            if (previousY < 0) != (y < 0) {
                let root = bisectRoot(x0: previous.x, x1: sample.x, evaluate: evaluate)
                if let value = evaluate(root), abs(value) < acceptTolerance {
                    appendRoot(root, to: &roots, window: window)
                }
            }
        }
        return roots
    }

    private func zeroes(
        in range: ClosedRange<Double>,
        window: GraphWindow,
        sampleCount: Int = 720,
        evaluate: (Double) -> Double?
    ) -> [Double] {
        guard range.lowerBound.isFinite,
              range.upperBound.isFinite,
              range.upperBound > range.lowerBound else {
            return []
        }

        let step = (range.upperBound - range.lowerBound) / Double(sampleCount)
        let acceptTolerance = max(window.width, window.height) * 1e-4
        var roots: [Double] = []
        var previousX: Double?
        var previousValue: Double?

        for sampleIndex in 0...sampleCount {
            let x = range.lowerBound + Double(sampleIndex) * step
            guard let value = evaluate(x), value.isFinite else {
                previousX = nil
                previousValue = nil
                continue
            }
            if abs(value) < acceptTolerance {
                appendRoot(x, to: &roots, window: window)
            } else if let previousX, let previousValue, (previousValue < 0) != (value < 0) {
                let root = bisectRoot(x0: previousX, x1: x, evaluate: evaluate)
                if let refinedValue = evaluate(root), abs(refinedValue) < acceptTolerance {
                    appendRoot(root, to: &roots, window: window)
                }
            }
            previousX = x
            previousValue = value
        }
        return roots
    }

    private func appendPoint(_ point: CGPoint, to points: inout [CGPoint], window: GraphWindow) {
        let minimumSeparation = min(window.width, window.height) * 1e-3
        guard !points.contains(where: { hypot($0.x - point.x, $0.y - point.y) <= minimumSeparation }) else { return }
        points.append(point)
    }

    private func zeroCrossing(
        from a: (value: Double, point: CGPoint),
        to b: (value: Double, point: CGPoint)
    ) -> CGPoint? {
        if abs(a.value) < 1e-9 { return a.point }
        if abs(b.value) < 1e-9 { return b.point }
        guard (a.value < 0) != (b.value < 0) else { return nil }
        let t = abs(a.value) / (abs(a.value) + abs(b.value))
        return CGPoint(
            x: a.point.x + (b.point.x - a.point.x) * t,
            y: a.point.y + (b.point.y - a.point.y) * t
        )
    }

    /// Adds a root, skipping ones effectively coincident with an already-found root.
    private func appendRoot(_ root: Double, to roots: inout [Double], window: GraphWindow) {
        let minimumSeparation = window.width * 1e-4
        if roots.contains(where: { abs($0 - root) <= minimumSeparation }) { return }
        roots.append(root)
    }

    private func bisectRoot(x0: Double, x1: Double, evaluate: (Double) -> Double?) -> Double {
        var low = x0
        var high = x1
        guard var lowValue = evaluate(low) else { return (x0 + x1) / 2 }

        for _ in 0..<48 {
            let mid = (low + high) / 2
            guard let midValue = evaluate(mid) else { return mid }
            if midValue == 0 { return mid }
            if (lowValue < 0) == (midValue < 0) {
                low = mid
                lowValue = midValue
            } else {
                high = mid
            }
        }
        return (low + high) / 2
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
        if state.isDockedHeaderCollapsed { return collapsedPanelSize(forExpandedSize: dockedCalculatorExpandedSize(in: containerSize), in: containerSize) }
        return dockedCalculatorExpandedSize(in: containerSize)
    }

    private func dockedCalculatorExpandedSize(in containerSize: CGSize) -> CGSize {
        let verticalMargin: CGFloat = 28
        let graphHeight = dockedGraphHeight(in: containerSize)
        let preferredHeight = expandedHeaderHeight + graphHeight + 48 + baseEntryHeight + keypadHeight
        return CGSize(
            width: min(containerSize.width, 440),
            height: min(max(containerSize.height - verticalMargin * 2, 0), preferredHeight)
        )
    }

    private func dockedCalculatorLayout(in containerSize: CGSize) -> (size: CGSize, center: CGPoint, expandedSize: CGSize) {
        let expandedSize = dockedCalculatorExpandedSize(in: containerSize)
        let expandedCenter = dockedCalculatorCenter(size: expandedSize, in: containerSize)
        let size = state.isDockedHeaderCollapsed
            ? collapsedPanelSize(forExpandedSize: expandedSize, in: containerSize)
            : expandedSize
        let center = state.isDockedHeaderCollapsed
            ? collapsedCenterPreservingTop(expandedCenter: expandedCenter, expandedSize: expandedSize, collapsedSize: size, in: containerSize)
            : expandedCenter
        return (size, center, expandedSize)
    }

    private func collapsedPanelSize(forExpandedSize expandedSize: CGSize, in containerSize: CGSize) -> CGSize {
        let maximumWidth = max(1, containerSize.width - 24)
        return CGSize(
            width: min(maximumWidth, expandedSize.width * 1.5),
            height: compactHeaderHeight
        )
    }

    private func dockedGraphHeight(in containerSize: CGSize) -> CGFloat {
        let verticalMargin: CGFloat = 28
        let fixedHeight = dockedHeaderHeight + 48 + baseEntryHeight + keypadHeight
        let availableHeight = max(containerSize.height - verticalMargin * 2 - fixedHeight, 220)
        let availableWidth = min(containerSize.width, 440)
        return min(preferredDockedGraphHeight, availableWidth, availableHeight)
    }

    private func dockedCalculatorCenter(size: CGSize, in containerSize: CGSize) -> CGPoint {
        let fallback = CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)
        return clamp(center: state.calculatorPosition ?? fallback, size: size, in: containerSize)
    }

    private var detachedControlHeight: CGFloat {
        let entry: CGFloat = state.isKeypadCollapsed
            ? baseDetachedEntryHeight + detachedHiddenEntryExtra
            : baseDetachedEntryHeight + detachedVisibleEntryExtra
        return detachedControlHeaderHeight + 48 + entryHandleHeight + entry + (state.isKeypadCollapsed ? 0 : keypadHeight)
    }

    /// Height for the detached control panel's entry area. The handle just above the keypad can
    /// expand this section vertically so more expression cells remain visible while typing.
    private func detachedEntryHeight(availableHeight: CGFloat) -> CGFloat {
        if state.isKeypadCollapsed {
            return max(120, availableHeight - detachedControlHeaderHeight - 48 - entryHandleHeight)
        }
        let availableEntryHeight = availableHeight - detachedControlHeaderHeight - 48 - entryHandleHeight - keypadHeight
        return min(baseDetachedEntryHeight + detachedVisibleEntryExtra, max(120, availableEntryHeight))
    }

    private func dockedCalculatorDragSnapshot(size: CGSize, in containerSize: CGSize) -> GraphCalculatorDragSnapshotImage? {
        renderedDragSnapshot(size: size) {
            calculatorBody(in: containerSize)
        }
    }

    private func detachedGraphDragSnapshot(size: CGSize, center: CGPoint, in containerSize: CGSize) -> GraphCalculatorDragSnapshotImage? {
        let placementRect = CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        return renderedDragSnapshot(size: size) {
            detachedGraphPanelContent(size: size, center: center, placementRect: placementRect, containerSize: containerSize)
                .background(Color.white)
                .overlay(Rectangle().strokeBorder(.black.opacity(0.32), lineWidth: 1))
        }
    }

    private func detachedControlDragSnapshot(size: CGSize, center: CGPoint, height: CGFloat, in containerSize: CGSize) -> GraphCalculatorDragSnapshotImage? {
        let placementRect = CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        return renderedDragSnapshot(size: size) {
            detachedControlPanelContent(size: size, height: height, center: center, placementRect: placementRect, containerSize: containerSize)
                .background(GraphCalculatorTheme.panel)
                .overlay(Rectangle().strokeBorder(.black.opacity(0.14), lineWidth: 1))
                .overlay(detachedControlPanelBorder)
        }
    }

    private func tableDragSnapshot(size: CGSize, center: CGPoint, in containerSize: CGSize) -> GraphCalculatorDragSnapshotImage? {
        guard let active = state.activeTable,
              let equation = state.expressions.first(where: { $0.id == active.equationID }) else {
            return nil
        }

        return renderedDragSnapshot(size: size) {
            tableWindowContent(active: active, equation: equation, currentCenter: center, size: size, in: containerSize)
                .background(Color.white)
                .overlay(Rectangle().strokeBorder(.black.opacity(0.32), lineWidth: 1))
        }
    }

    private func renderedDragSnapshot<Content: View>(
        size: CGSize,
        @ViewBuilder content: () -> Content
    ) -> GraphCalculatorDragSnapshotImage? {
        #if os(iOS)
        let renderer = ImageRenderer(content: content().frame(width: size.width, height: size.height))
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
        #else
        return nil
        #endif
    }

    private func snapshotPNGData(from image: GraphCalculatorDragSnapshotImage?) -> Data? {
        #if os(iOS)
        image?.pngData()
        #else
        nil
        #endif
    }

    private func dockedCalculatorDragGesture(currentCenter: CGPoint, size: CGSize, expandedSize: CGSize, in containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let base = dragStartCenter ?? currentCenter
                if dragStartCenter == nil { dragStartCenter = base }
                let proposed = CGPoint(x: base.x + value.translation.width, y: base.y + value.translation.height)
                let clamped = clamp(center: proposed, size: size, in: containerSize)
                let snapshotImage = dragProxy?.snapshotImage ?? dockedCalculatorDragSnapshot(size: size, in: containerSize)
                let presentation = GraphCalculatorDragPresentation(
                    kind: .docked,
                    title: state.title,
                    systemImage: "chart.xyaxis.line",
                    center: base,
                    offset: CGSize(width: clamped.x - base.x, height: clamped.y - base.y),
                    size: size,
                    snapshotPNGData: state.activeDragPresentation?.snapshotPNGData ?? snapshotPNGData(from: snapshotImage)
                )
                setWithoutAnimation {
                    state.activeDragPresentation = presentation
                    dragProxy = GraphCalculatorDragProxy(
                        presentation: presentation,
                        snapshotImage: snapshotImage
                    )
                }
            }
            .onEnded { _ in
                let offset = dragProxy?.offset ?? .zero
                let finalCenter = CGPoint(x: currentCenter.x + offset.width, y: currentCenter.y + offset.height)
                state.calculatorPosition = state.isDockedHeaderCollapsed
                    ? expandedCenterPreservingTop(collapsedCenter: finalCenter, expandedSize: expandedSize, collapsedSize: size, in: containerSize)
                    : finalCenter
                dockedLiveOffset = .zero
                dragProxy = nil
                state.activeDragPresentation = nil
                dragStartCenter = nil
            }
    }

    private func detachedDragGesture(currentCenter: CGPoint, size: CGSize, expandedSize: CGSize, in containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let base = detachedDragStartCenter ?? currentCenter
                if detachedDragStartCenter == nil { detachedDragStartCenter = base }
                let proposed = CGPoint(x: base.x + value.translation.width, y: base.y + value.translation.height)
                let clamped = clamp(center: proposed, size: size, in: containerSize)
                let snapshotImage = dragProxy?.snapshotImage ?? detachedGraphDragSnapshot(size: size, center: currentCenter, in: containerSize)
                let presentation = GraphCalculatorDragPresentation(
                    kind: .detachedGraph,
                    title: "Graph",
                    systemImage: "chart.xyaxis.line",
                    center: base,
                    offset: CGSize(width: clamped.x - base.x, height: clamped.y - base.y),
                    size: size,
                    snapshotPNGData: state.activeDragPresentation?.snapshotPNGData ?? snapshotPNGData(from: snapshotImage)
                )
                setWithoutAnimation {
                    state.activeDragPresentation = presentation
                    dragProxy = GraphCalculatorDragProxy(
                        presentation: presentation,
                        snapshotImage: snapshotImage
                    )
                }
            }
            .onEnded { _ in
                let offset = dragProxy?.offset ?? .zero
                let finalCenter = CGPoint(x: currentCenter.x + offset.width, y: currentCenter.y + offset.height)
                state.detachedGraphPosition = state.isDetachedGraphHeaderCollapsed
                    ? expandedCenterPreservingTop(collapsedCenter: finalCenter, expandedSize: expandedSize, collapsedSize: size, in: containerSize)
                    : finalCenter
                detachedGraphLiveOffset = .zero
                dragProxy = nil
                state.activeDragPresentation = nil
                detachedDragStartCenter = nil
            }
    }

    private func detachedControlDragGesture(currentCenter: CGPoint, size: CGSize, expandedHeight: CGFloat, in containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let base = dragStartCenter ?? currentCenter
                if dragStartCenter == nil { dragStartCenter = base }
                let proposed = CGPoint(x: base.x + value.translation.width, y: base.y + value.translation.height)
                let clamped = clamp(center: proposed, size: size, in: containerSize)
                let snapshotImage = dragProxy?.snapshotImage ?? detachedControlDragSnapshot(
                    size: size,
                    center: currentCenter,
                    height: min(containerSize.height - 24, detachedControlHeight),
                    in: containerSize
                )
                let presentation = GraphCalculatorDragPresentation(
                    kind: .detachedControl,
                    title: state.title,
                    systemImage: "keyboard",
                    center: base,
                    offset: CGSize(width: clamped.x - base.x, height: clamped.y - base.y),
                    size: size,
                    snapshotPNGData: state.activeDragPresentation?.snapshotPNGData ?? snapshotPNGData(from: snapshotImage)
                )
                setWithoutAnimation {
                    state.activeDragPresentation = presentation
                    dragProxy = GraphCalculatorDragProxy(
                        presentation: presentation,
                        snapshotImage: snapshotImage
                    )
                }
            }
            .onEnded { _ in
                let offset = dragProxy?.offset ?? .zero
                let finalCenter = CGPoint(x: currentCenter.x + offset.width, y: currentCenter.y + offset.height)
                let expandedSize = CGSize(width: size.width, height: min(containerSize.height - 24, expandedHeight))
                state.detachedControlPosition = state.isDetachedControlHeaderCollapsed
                    ? expandedCenterPreservingTop(collapsedCenter: finalCenter, expandedSize: expandedSize, collapsedSize: size, in: containerSize)
                    : finalCenter
                detachedControlLiveOffset = .zero
                dragProxy = nil
                state.activeDragPresentation = nil
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

    private func collapsedCenterPreservingTop(
        expandedCenter: CGPoint,
        expandedSize: CGSize,
        collapsedSize: CGSize,
        in containerSize: CGSize
    ) -> CGPoint {
        let topY = expandedCenter.y - expandedSize.height / 2
        return clamp(
            center: CGPoint(x: expandedCenter.x, y: topY + collapsedSize.height / 2),
            size: collapsedSize,
            in: containerSize
        )
    }

    private func expandedCenterPreservingTop(
        collapsedCenter: CGPoint,
        expandedSize: CGSize,
        collapsedSize: CGSize,
        in containerSize: CGSize
    ) -> CGPoint {
        let topY = collapsedCenter.y - collapsedSize.height / 2
        return clamp(
            center: CGPoint(x: collapsedCenter.x, y: topY + expandedSize.height / 2),
            size: expandedSize,
            in: containerSize
        )
    }

    private func squareDetachedGraphWindow(currentSize: CGSize, currentCenter: CGPoint, in containerSize: CGSize) {
        state.resetWindow()
        let headerHeight: CGFloat = state.isDetachedGraphHeaderCollapsed ? compactHeaderHeight : expandedFloatingHeaderHeight
        let graphHeight = max(currentSize.height - headerHeight, 1)
        let side = min(currentSize.width, graphHeight)
        let squaredSize = clampGraphSize(
            CGSize(width: side, height: side + headerHeight),
            in: containerSize
        )
        state.detachedGraphSize = squaredSize
        state.detachedGraphPosition = clamp(center: currentCenter, size: squaredSize, in: containerSize)
        detachedResizeLive = nil
        detachedResizeStart = nil
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
        dragProxy?.kind == kind || state.activeDragPresentation?.kind == kind
    }
}

#if os(iOS)
private typealias GraphCalculatorDragSnapshotImage = UIImage
#else
private struct GraphCalculatorDragSnapshotImage {}
#endif

private struct GraphCalculatorDragProxy {
    let kind: GraphCalculatorDragKind
    let title: String
    let systemImage: String
    let center: CGPoint
    let offset: CGSize
    let size: CGSize
    let snapshotImage: GraphCalculatorDragSnapshotImage?

    init(
        kind: GraphCalculatorDragKind,
        title: String,
        systemImage: String,
        center: CGPoint,
        offset: CGSize,
        size: CGSize,
        snapshotImage: GraphCalculatorDragSnapshotImage?
    ) {
        self.kind = kind
        self.title = title
        self.systemImage = systemImage
        self.center = center
        self.offset = offset
        self.size = size
        self.snapshotImage = snapshotImage
    }

    init(presentation: GraphCalculatorDragPresentation, snapshotImage: GraphCalculatorDragSnapshotImage? = nil) {
        self.kind = presentation.kind
        self.title = presentation.title
        self.systemImage = presentation.systemImage
        self.center = presentation.center
        self.offset = presentation.offset
        self.size = presentation.size
        #if os(iOS)
        self.snapshotImage = snapshotImage ?? presentation.snapshotPNGData.flatMap { UIImage(data: $0) }
        #else
        self.snapshotImage = snapshotImage
        #endif
    }

    var headerHeight: CGFloat {
        switch kind {
        case .detachedGraph, .table:
            return 42
        case .docked, .detachedControl:
            return 58
        }
    }

    var cornerRadius: CGFloat {
        switch kind {
        case .detachedGraph, .table:
            return 12
        case .docked, .detachedControl:
            return 24
        }
    }

    var headerFill: Color {
        switch kind {
        case .detachedGraph, .table:
            return Color.white
        case .docked, .detachedControl:
            return GraphCalculatorTheme.header
        }
    }

    var bodyFill: Color {
        switch kind {
        case .detachedGraph, .table:
            return Color.white.opacity(0.86)
        case .docked, .detachedControl:
            return GraphCalculatorTheme.panel.opacity(0.86)
        }
    }

    var stroke: Color {
        switch kind {
        case .detachedGraph, .table:
            return Color.black.opacity(0.35)
        case .docked, .detachedControl:
            return Color.white.opacity(0.32)
        }
    }

    var headerForeground: Color {
        switch kind {
        case .detachedGraph, .table:
            return Color.black.opacity(0.78)
        case .docked, .detachedControl:
            return Color.white.opacity(0.92)
        }
    }

    var labelForeground: Color {
        switch kind {
        case .detachedGraph, .table:
            return Color.black.opacity(0.45)
        case .docked, .detachedControl:
            return Color.white.opacity(0.58)
        }
    }
}

private typealias GraphCalculatorDragKind = GraphCalculatorDragPresentation.Kind

private enum CalculatorHeaderKind {
    case docked
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

private struct GraphCalculatorMathDisplay: View {
    let source: String
    let fallback: String
    let fontSize: CGFloat

    private var latex: String {
        GraphCalculatorLaTeXConverter.latex(for: source)
    }

    private var mathFont: Math.Font {
        Math.Font(name: .latinModern, size: fontSize)
    }

    private var canTypeset: Bool {
        guard !latex.isEmpty else { return false }
        let bounds = Math.typographicBounds(
            for: latex,
            fitting: ProposedViewSize(width: 2_000, height: 200),
            font: mathFont,
            style: .display
        )
        return bounds.size.width > 0 && bounds.size.height > 0
    }

    @ViewBuilder
    var body: some View {
        if canTypeset {
            Math(latex)
                .mathTypesettingStyle(.display)
                .mathFont(mathFont)
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxHeight: fontSize * 1.8, alignment: .center)
        } else {
            Text(fallback)
                .font(.system(size: fontSize, weight: .regular, design: .serif))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
    }
}

private enum GraphCalculatorLaTeXConverter {
    static func latex(for source: String) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return convert(trimmed)
    }

    private static func convert(_ source: String) -> String {
        var output = ""
        var index = source.startIndex

        while index < source.endIndex {
            if let argument = functionArgument(named: "sqrt", in: source, at: index) {
                output += "\\sqrt{" + convert(argument.body) + "}"
                index = argument.end
                continue
            }

            if let argument = functionArgument(named: "abs", in: source, at: index) {
                output += "\\left|" + convert(argument.body) + "\\right|"
                index = argument.end
                continue
            }

            if hasPrefix("<=", in: source, at: index) {
                output += "\\le "
                index = source.index(index, offsetBy: 2)
                continue
            }

            if hasPrefix(">=", in: source, at: index) {
                output += "\\ge "
                index = source.index(index, offsetBy: 2)
                continue
            }

            if hasIdentifier("theta", in: source, at: index) {
                output += "\\theta "
                index = source.index(index, offsetBy: 5)
                continue
            }

            if hasIdentifier("pi", in: source, at: index) {
                output += "\\pi "
                index = source.index(index, offsetBy: 2)
                continue
            }

            let character = source[index]
            switch character {
            case "^":
                let next = source.index(after: index)
                if let exponent = groupedArgument(in: source, startingAt: next) {
                    output += "^{" + convert(exponent.body) + "}"
                    index = exponent.end
                } else if let exponent = simpleArgument(in: source, startingAt: next) {
                    output += "^{" + convert(exponent.body) + "}"
                    index = exponent.end
                } else {
                    output.append("^")
                    index = next
                }
            case "*", "×":
                output += "\\cdot "
                index = source.index(after: index)
            case "≤":
                output += "\\le "
                index = source.index(after: index)
            case "≥":
                output += "\\ge "
                index = source.index(after: index)
            case "π":
                output += "\\pi "
                index = source.index(after: index)
            case "θ":
                output += "\\theta "
                index = source.index(after: index)
            case "_":
                output += "\\_"
                index = source.index(after: index)
            default:
                output += String(character)
                index = source.index(after: index)
            }
        }

        return output
    }

    private static func functionArgument(named name: String, in source: String, at index: String.Index) -> (body: String, end: String.Index)? {
        let prefix = name + "("
        guard hasPrefix(prefix, in: source, at: index) else { return nil }
        let openParen = source.index(index, offsetBy: name.count)
        return groupedArgument(in: source, startingAt: openParen)
    }

    private static func groupedArgument(in source: String, startingAt index: String.Index) -> (body: String, end: String.Index)? {
        guard index < source.endIndex, source[index] == "(" else { return nil }
        var depth = 0
        var scan = index
        while scan < source.endIndex {
            if source[scan] == "(" {
                depth += 1
            } else if source[scan] == ")" {
                depth -= 1
                if depth == 0 {
                    let bodyStart = source.index(after: index)
                    let body = String(source[bodyStart..<scan])
                    return (body, source.index(after: scan))
                }
            }
            scan = source.index(after: scan)
        }
        return nil
    }

    private static func simpleArgument(in source: String, startingAt index: String.Index) -> (body: String, end: String.Index)? {
        var scan = index
        while scan < source.endIndex, source[scan].isWhitespace {
            scan = source.index(after: scan)
        }
        guard scan < source.endIndex else { return nil }

        let start = scan
        if source[scan] == "-" || source[scan] == "+" {
            scan = source.index(after: scan)
        }
        while scan < source.endIndex, source[scan].isNumber || source[scan].isLetter || source[scan] == "." || source[scan] == "π" || source[scan] == "θ" {
            scan = source.index(after: scan)
        }

        if scan == start {
            scan = source.index(after: start)
        }
        return (String(source[start..<scan]), scan)
    }

    private static func hasPrefix(_ prefix: String, in source: String, at index: String.Index) -> Bool {
        source[index...].hasPrefix(prefix)
    }

    private static func hasIdentifier(_ identifier: String, in source: String, at index: String.Index) -> Bool {
        guard hasPrefix(identifier, in: source, at: index) else { return false }
        let end = source.index(index, offsetBy: identifier.count)
        let beforeIsIdentifier = index > source.startIndex && isIdentifierCharacter(source[source.index(before: index)])
        let afterIsIdentifier = end < source.endIndex && isIdentifierCharacter(source[end])
        return !beforeIsIdentifier && !afterIsIdentifier
    }

    private static func isIdentifierCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
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
        display = display.replacingOccurrences(of: "*", with: "·")
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

private struct PointTableCellEdit: Identifiable, Equatable {
    enum Column {
        case x
        case y
    }

    let equationID: UUID
    let pairID: UUID
    let column: Column

    var id: String {
        "\(equationID)-\(pairID)-\(column)"
    }
}

private enum RegressionKind {
    case linear
    case quadratic
    case cubic
    case quartic

    var degree: Int {
        switch self {
        case .linear: return 1
        case .quadratic: return 2
        case .cubic: return 3
        case .quartic: return 4
        }
    }

    var minimumPointCount: Int { degree + 1 }
}

private struct RationalFraction: Equatable {
    let numerator: Int
    let denominator: Int
}

private enum NumericExpressionToken: Equatable {
    case text(String)
    case fraction(RationalFraction)
}

private enum EditableExpressionToken: Equatable {
    case text(String)
    case fraction(EditableFractionToken)
}

private struct EditableFractionToken: Equatable {
    let numerator: String
    let denominator: String
    let numeratorRange: Range<Int>
    let denominatorRange: Range<Int>
    let slashOffset: Int
    let sourceRange: Range<Int>
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

#Preview("Function Table Window") {
    GraphCalculatorView(
        state: {
            let equation = GraphEquation(expression: "y=x^2-5", colorIndex: 0)
            let state = GraphCalculatorState(expressions: [equation])
            state.activeTable = GraphActiveTable(equationID: equation.id, kind: .function)
            return state
        }()
    )
    .frame(width: 560, height: 900)
    .padding()
    .background(Color(white: 0.93))
}

#Preview("Trace") {
    GraphCalculatorView(
        state: {
            let equation = GraphEquation(expression: "y=x^2-5", colorIndex: 0)
            let state = GraphCalculatorState(expressions: [equation])
            state.activeTable = GraphActiveTable(equationID: equation.id, kind: .function)
            state.isTraceActive = true
            state.functionTableSettings[equation.id] = GraphFunctionTableSettings(start: -3, delta: 1)
            state.tableWindowPosition = CGPoint(x: 280, y: 720)
            return state
        }()
    )
    .frame(width: 560, height: 900)
    .padding()
    .background(Color(white: 0.93))
}

#Preview("Points Table Window") {
    GraphCalculatorView(
        state: {
            let equation = GraphEquation(expression: "(3,4)", colorIndex: 1)
            let state = GraphCalculatorState(expressions: [equation])
            state.pointRows[equation.id] = [GraphOrderedPair(x: 5, y: 6), GraphOrderedPair(x: -2, y: 1)]
            state.activeTable = GraphActiveTable(equationID: equation.id, kind: .points)
            return state
        }()
    )
    .frame(width: 560, height: 900)
    .padding()
    .background(Color(white: 0.93))
}
#endif
