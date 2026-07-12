//
//  CompactToolPaletteView.swift
//  MathBoardCore - ToolPalette module
//
//  A compact, professional teaching-whiteboard tool palette — an alternative to
//  the radial dial (`RadialToolPaletteView`). It is a slim vertical dock of tool
//  buttons with a contextual controls drawer that only appears for the active
//  tool, so it never blocks much of the canvas.
//
//  It reuses the *existing* model end-to-end:
//   - `ToolPaletteState` / `ToolPaletteCommand`             (single command model)
//   - `ToolPaletteDefinitions.definition(for:).configuration(for:)`  (per-tool UI)
//   - `ToolPaletteReducer.reduce(_:command:)`               (state transitions)
//
//  The dock is intentionally driven by the same `ToolPaletteConfiguration`
//  (topOrbit + leftArc/rightArc) the radial dial consumes, so every tool
//  definition works here unchanged and new tools/controls extend automatically.
//
//  This is a standalone prototype — it is NOT wired into the live canvas. Use
//  `CompactToolPalettePrototypeView` (or the #Previews below) to compare it with
//  the radial palette.
//

import SwiftUI

public enum CompactPaletteDockEdge: Equatable, Sendable {
    case left
    case right
}

public struct FloatingCompactToolPaletteView: View {
    @Binding private var state: ToolPaletteState
    @Binding private var center: CGPoint?
    private let onCommand: (ToolPaletteCommand) -> Void
    private let onResolvedCommand: (ToolPaletteCommand, ToolPaletteState) -> Void

    @State private var measuredSize: CGSize = .zero
    @State private var dragStartCenter: CGPoint?

    public init(
        state: Binding<ToolPaletteState>,
        center: Binding<CGPoint?>,
        onCommand: @escaping (ToolPaletteCommand) -> Void = { _ in },
        onResolvedCommand: @escaping (ToolPaletteCommand, ToolPaletteState) -> Void = { _, _ in }
    ) {
        self._state = state
        self._center = center
        self.onCommand = onCommand
        self.onResolvedCommand = onResolvedCommand
    }

    public var body: some View {
        GeometryReader { proxy in
            let containerSize = proxy.size
            let measuredHeight = measuredSize == .zero ? Self.fallbackSize.height : measuredSize.height
            let paletteSize = CGSize(width: Self.expandedWidth, height: measuredHeight)
            let railCenter = center ?? Self.defaultRailCenter(in: containerSize, paletteSize: paletteSize)
            let dockEdge = railCenter.x <= containerSize.width / 2 ? CompactPaletteDockEdge.left : .right
            let paletteCenter = Self.paletteCenter(forRailCenter: railCenter, paletteSize: paletteSize, edge: dockEdge)

            VStack(alignment: dockEdge == .left ? .leading : .trailing, spacing: 0) {
                CompactToolPaletteView(
                    state: $state,
                    dockEdge: dockEdge,
                    dragHandle: AnyView(
                        dragHandle(edge: dockEdge)
                            .gesture(dragGesture(in: containerSize, currentRailCenter: railCenter, paletteSize: paletteSize))
                    ),
                    onCommand: onCommand,
                    onResolvedCommand: onResolvedCommand
                )
            }
            .frame(width: Self.expandedWidth, alignment: dockEdge == .left ? .leading : .trailing)
            .background(
                GeometryReader { paletteProxy in
                    Color.clear
                        .onAppear {
                            measuredSize = paletteProxy.size
                        }
                        .onChange(of: paletteProxy.size) { _, newSize in
                            measuredSize = newSize
                            if let center {
                                let edge = center.x <= containerSize.width / 2 ? CompactPaletteDockEdge.left : .right
                                self.center = Self.clampRailCenter(center, in: containerSize, paletteSize: newSize, edge: edge)
                            }
                        }
                }
            )
            .position(paletteCenter)
        }
    }

    private func dragHandle(edge: CompactPaletteDockEdge) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .bold))
        }
        .foregroundStyle(Color(red: 0.05, green: 0.11, blue: 0.18).opacity(0.86))
        .frame(width: Self.railWidth, height: 30)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: edge == .left ? 22 : 12,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: edge == .right ? 22 : 12,
                style: .continuous
            )
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.98), Color(red: 0.84, green: 0.90, blue: 0.96)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .shadow(color: .white.opacity(0.4), radius: 3, x: -1, y: -1)
            .shadow(color: .black.opacity(0.12), radius: 4, x: 2, y: 2)
        )
        .contentShape(Rectangle())
        .accessibilityLabel("Move compact tool palette")
    }

    private func dragGesture(in containerSize: CGSize, currentRailCenter: CGPoint, paletteSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                let base = dragStartCenter ?? currentRailCenter
                if dragStartCenter == nil {
                    dragStartCenter = base
                }
                let proposed = CGPoint(x: base.x + value.translation.width, y: base.y + value.translation.height)
                let edge = proposed.x <= containerSize.width / 2 ? CompactPaletteDockEdge.left : .right
                center = Self.clampRailCenter(
                    proposed,
                    in: containerSize,
                    paletteSize: paletteSize,
                    edge: edge
                )
            }
            .onEnded { _ in
                dragStartCenter = nil
            }
    }

    private static let expandedWidth: CGFloat = 396
    private static let fallbackSize = CGSize(width: expandedWidth, height: 420)
    private static let railWidth: CGFloat = 68
    private static let margin: CGFloat = 16

    private static func defaultRailCenter(in containerSize: CGSize, paletteSize: CGSize) -> CGPoint {
        clampRailCenter(
            CGPoint(
                x: railWidth / 2 + margin,
                y: containerSize.height / 2
            ),
            in: containerSize,
            paletteSize: paletteSize,
            edge: .left
        )
    }

    private static func paletteCenter(forRailCenter railCenter: CGPoint, paletteSize: CGSize, edge: CompactPaletteDockEdge) -> CGPoint {
        let horizontalOffset = max((paletteSize.width - railWidth) / 2, 0)
        switch edge {
        case .left:
            return CGPoint(x: railCenter.x + horizontalOffset, y: railCenter.y)
        case .right:
            return CGPoint(x: railCenter.x - horizontalOffset, y: railCenter.y)
        }
    }

    private static func clampRailCenter(_ point: CGPoint, in containerSize: CGSize, paletteSize: CGSize, edge: CompactPaletteDockEdge) -> CGPoint {
        let halfHeight = max(paletteSize.height / 2, 1)
        let minX: CGFloat
        let maxX: CGFloat
        switch edge {
        case .left:
            minX = railWidth / 2 + margin
            maxX = max(minX, containerSize.width - paletteSize.width + railWidth / 2 - margin)
        case .right:
            minX = max(railWidth / 2 + margin, paletteSize.width - railWidth / 2 + margin)
            maxX = max(minX, containerSize.width - railWidth / 2 - margin)
        }
        let minY = halfHeight + margin
        let maxY = max(minY, containerSize.height - halfHeight - margin)
        return CGPoint(
            x: min(max(point.x, minX), maxX),
            y: min(max(point.y, minY), maxY)
        )
    }
}

public struct CompactToolPaletteView: View {
    @Binding private var state: ToolPaletteState
    private let onCommand: (ToolPaletteCommand) -> Void
    private let onResolvedCommand: (ToolPaletteCommand, ToolPaletteState) -> Void
    private let dockEdge: CompactPaletteDockEdge
    private let dragHandle: AnyView?

    // Contextual drawer visibility now lives in `ToolPaletteState.isCompactDrawerOpen`
    // (shared, mirror-synced state) instead of local @State, so the external display
    // reflects the mini-strip vs. full-drawer choice rather than always showing the
    // full drawer. Collapsing leaves only the slim tool rail while teaching.

    // Popover hosts, mirroring the radial palette's "open…" command handling.
    @State private var isColorPickerPresented = false
    @State private var isPaletteChooserPresented = false
    @State private var isLatexEditorPresented = false
    @State private var isFontPickerPresented = false
    @State private var colorPickerTarget: CompactColorTarget = .stroke
    @State private var editingColorSlot: Int?
    @State private var editingColorTool: ToolID?
    @State private var latexDraft = ""

    public init(
        state: Binding<ToolPaletteState>,
        dockEdge: CompactPaletteDockEdge = .left,
        dragHandle: AnyView? = nil,
        onCommand: @escaping (ToolPaletteCommand) -> Void = { _ in },
        onResolvedCommand: @escaping (ToolPaletteCommand, ToolPaletteState) -> Void = { _, _ in }
    ) {
        self._state = state
        self.dockEdge = dockEdge
        self.dragHandle = dragHandle
        self.onCommand = onCommand
        self.onResolvedCommand = onResolvedCommand
    }

    public var body: some View {
        let configuration = ToolPaletteDefinitions.definition(for: state.activeTool).configuration(for: state)
        let isDrawerVisible = state.isCompactDrawerOpen && state.activeTool.hasCompactDrawer

        HStack(alignment: .top, spacing: 0) {
            if dockEdge == .right, isDrawerVisible {
                drawerPanel(configuration)
                    .transition(drawerTransition)
            }
            if dockEdge == .right, isQuickStripVisible {
                quickStrip
                    .transition(drawerTransition)
            }
            toolRail
                .zIndex(1)
            if dockEdge == .left, isDrawerVisible {
                drawerPanel(configuration)
                    .transition(drawerTransition)
            }
            if dockEdge == .left, isQuickStripVisible {
                quickStrip
                    .transition(drawerTransition)
            }
        }
        .animation(Self.drawerAnimation, value: state.isCompactDrawerOpen)
        .animation(Self.drawerAnimation, value: isQuickStripVisible)
        .environment(\.colorScheme, .dark)
        .onChange(of: state.activeTool) { _, newTool in
            guard newTool.hasCompactDrawer else {
                state.isCompactDrawerOpen = false
                return
            }
            if !newTool.hasCompactQuickStrip || newTool == .equation {
                state.isCompactDrawerOpen = true
            }
        }
        // Popovers reuse the shared reducer via `send`, just like the radial dial.
        .popover(isPresented: $isColorPickerPresented) {
            VStack(alignment: .leading, spacing: 12) {
                Text(colorPickerTarget.title).font(.headline)
                ColorPicker("Custom", selection: customColorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 220)
            }
            .padding(16)
            .presentationCompactAdaptation(.popover)
        }
        .popover(isPresented: $isPaletteChooserPresented) {
            CompactPaletteChooser(selectedPreset: state.activePalettePreset) { preset in
                send(.setPalettePreset(preset))
                editingColorSlot = activeColorSlotIndex
                editingColorTool = state.activeTool
                isPaletteChooserPresented = false
            }
            .padding(14)
            .presentationCompactAdaptation(.popover)
        }
        .popover(isPresented: $isLatexEditorPresented) {
            CompactLatexEditor(latexSource: $latexDraft) {
                send(.setLatexSource(latexDraft))
                isLatexEditorPresented = false
            }
            .padding(14)
            .presentationCompactAdaptation(.popover)
        }
        .popover(isPresented: $isFontPickerPresented) {
            CompactFontChooser(selectedFontName: state.textFontName) { fontName in
                send(.setTextFontName(fontName))
                isFontPickerPresented = false
            }
            .padding(14)
            .presentationCompactAdaptation(.popover)
        }
    }

    private var drawerTransition: AnyTransition {
        .asymmetric(
            insertion: .offset(x: dockEdge == .left ? -28 : 28).combined(with: .opacity),
            removal: .offset(x: dockEdge == .left ? -28 : 28).combined(with: .opacity)
        )
    }

    private static let drawerAnimation = Animation.easeInOut(duration: 0.16)
    private static let dragHandleHeight: CGFloat = 30
    private static let railSectionSpacing: CGFloat = 8
    private static let railSectionPadding: CGFloat = 4
    private static let toolButtonHeight: CGFloat = 46
    private static let toolButtonSpacing: CGFloat = 4

    // MARK: - Tool rail

    private var toolRail: some View {
        VStack(spacing: Self.railSectionSpacing) {
            if let dragHandle {
                dragHandle
            }

            ForEach(toolSections.indices, id: \.self) { sectionIndex in
                VStack(spacing: Self.toolButtonSpacing) {
                    ForEach(toolSections[sectionIndex], id: \.self) { toolID in
                        CompactToolButton(
                            toolID: toolID,
                            iconSystemName: state.iconSystemName(for: toolID),
                            isActive: toolID == state.activeTool,
                            accentColor: railAccentColor(for: toolID),
                            outlineColor: state.strokeColor.swiftUIColor,
                            fillColor: state.fillColor.swiftUIColor.opacity(state.geometryFillOpacity)
                        ) {
                            handleToolTap(toolID)
                        }
                    }
                }
                .padding(Self.railSectionPadding)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.42))
                        .shadow(color: .white.opacity(0.45), radius: 3, x: -1, y: -1)
                        .shadow(color: .black.opacity(0.22), radius: 5, x: 2, y: 2)
                )
            }

            Divider()
                .overlay(Color.black.opacity(0.12))
                .padding(.horizontal, 10)

            // Explicit drawer toggle for discoverability.
            Button {
                withAnimation(Self.drawerAnimation) { state.isCompactDrawerOpen.toggle() }
            } label: {
                Image(systemName: state.isCompactDrawerOpen ? "chevron.left" : "chevron.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(red: 0.05, green: 0.11, blue: 0.18).opacity(0.82))
                    .frame(width: 44, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(state.isCompactDrawerOpen ? "Hide tool options" : "Show tool options")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .frame(width: 68)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.92, green: 0.97, blue: 1.0),
                            Color(red: 0.68, green: 0.79, blue: 0.90)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .white.opacity(0.48), radius: 3, x: -1, y: -1)
                .shadow(color: .black.opacity(0.26), radius: 12, x: 3, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.74), lineWidth: 1.2)
        )
    }

    private func handleToolTap(_ toolID: ToolID) {
        let wasActive = state.activeTool == toolID
        if toolID == .selection && wasActive {
            send(.setSelectionBehavior(state.selectionBehavior.toggled))
        } else {
            send(.selectTool(toolID))
        }

        if !toolID.hasCompactDrawer {
            withAnimation(Self.drawerAnimation) {
                state.isCompactDrawerOpen = false
            }
        } else if toolID.hasCompactQuickStrip {
            withAnimation(Self.drawerAnimation) {
                state.isCompactDrawerOpen = wasActive ? !state.isCompactDrawerOpen : false
            }
        } else if wasActive {
            withAnimation(Self.drawerAnimation) { state.isCompactDrawerOpen.toggle() }
        } else {
            state.isCompactDrawerOpen = true
        }
    }

    private var toolSections: [[ToolID]] {
        [
            [.selection, .extract],
            [.pen, .marker, .laser, .eraser],
            [.geometry, .reserved, .equation, .cover]
        ]
    }

    private var isQuickStripVisible: Bool {
        state.activeTool.hasCompactQuickStrip && !state.isCompactDrawerOpen
    }

    @ViewBuilder
    private var quickStrip: some View {
        if state.activeTool.isCompactInkTool {
            quickColorStrip
        } else if state.activeTool == .selection || state.activeTool == .extract || state.activeTool == .eraser || state.activeTool == .cover {
            quickModeStrip
        } else if state.activeTool == .geometry {
            quickShapeStrip
        }
    }

    private var quickShapeStrip: some View {
        VStack(spacing: 10) {
            ForEach(GeometryType.allCases, id: \.rawValue) { shape in
                CompactQuickModeButton(
                    iconSystemName: shape.iconSystemName,
                    label: shape.displayName,
                    isSelected: state.geometryType == shape
                ) {
                    send(.setGeometryType(shape))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.78))
                .shadow(color: .white.opacity(0.3), radius: 3, x: -1, y: -1)
                .shadow(color: .black.opacity(0.16), radius: 8, x: 3, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.62), lineWidth: 1)
        )
        .padding(.top, drawerTopOffset)
        .padding(.horizontal, 8)
    }

    private var quickColorStrip: some View {
        VStack(spacing: 10) {
            ForEach(Array(quickPaletteColors.enumerated()), id: \.offset) { index, color in
                CompactQuickColorButton(
                    color: color,
                    isSelected: isQuickColorSelected(index)
                ) {
                    selectQuickColor(color, at: index)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.78))
                .shadow(color: .white.opacity(0.3), radius: 3, x: -1, y: -1)
                .shadow(color: .black.opacity(0.16), radius: 8, x: 3, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.62), lineWidth: 1)
        )
        .padding(.top, drawerTopOffset)
        .padding(.horizontal, 8)
    }

    private var quickModeStrip: some View {
        VStack(spacing: 10) {
            ForEach(quickModeItems) { item in
                CompactQuickModeButton(
                    iconSystemName: item.iconSystemName,
                    label: item.label,
                    isSelected: item.isSelected
                ) {
                    send(item.command)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.78))
                .shadow(color: .white.opacity(0.3), radius: 3, x: -1, y: -1)
                .shadow(color: .black.opacity(0.16), radius: 8, x: 3, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.62), lineWidth: 1)
        )
        .padding(.top, drawerTopOffset)
        .padding(.horizontal, 8)
    }

    private var quickModeItems: [CompactQuickModeItem] {
        switch state.activeTool {
        case .selection:
            return []
        case .extract:
            return [
                CompactQuickModeItem(
                    id: "extract.quick.paste",
                    iconSystemName: "doc.on.clipboard",
                    label: "Paste",
                    isSelected: false,
                    command: .pasteSelection
                ),
                CompactQuickModeItem(
                    id: "extract.quick.lasso",
                    iconSystemName: "lasso",
                    label: "Lasso",
                    isSelected: state.selectionMode == .lasso,
                    command: .setSelectionMode(.lasso)
                ),
                CompactQuickModeItem(
                    id: "extract.quick.marquee",
                    iconSystemName: "rectangle.dashed",
                    label: "Box",
                    isSelected: state.selectionMode == .marquee,
                    command: .setSelectionMode(.marquee)
                )
            ]
        case .eraser:
            return [
                CompactQuickModeItem(
                    id: "eraser.quick.pixel",
                    iconSystemName: "circle.grid.cross",
                    label: "Pixels",
                    isSelected: state.eraserMode == .pixel,
                    command: .setEraserMode(.pixel)
                ),
                CompactQuickModeItem(
                    id: "eraser.quick.stroke",
                    iconSystemName: "scribble.variable",
                    label: "Stroke",
                    isSelected: state.eraserMode == .stroke,
                    command: .setEraserMode(.stroke)
                )
            ]
        case .cover:
            return [
                CompactQuickModeItem(
                    id: "cover.quick.marquee",
                    iconSystemName: "rectangle.dashed",
                    label: "Box",
                    isSelected: state.selectionMode == .marquee,
                    command: .setSelectionMode(.marquee)
                ),
                CompactQuickModeItem(
                    id: "cover.quick.lasso",
                    iconSystemName: "lasso",
                    label: "Lasso",
                    isSelected: state.selectionMode == .lasso,
                    command: .setSelectionMode(.lasso)
                )
            ]
        case .reserved, .pen, .marker, .geometry, .laser, .equation:
            return []
        }
    }

    private func selectQuickColor(_ color: PaletteColor, at index: Int) {
        if isQuickColorSelected(index) {
            colorPickerTarget = .stroke
            editingColorSlot = index
            editingColorTool = state.activeTool
            isColorPickerPresented = true
        } else {
            editingColorSlot = index
            editingColorTool = state.activeTool
            send(.setStrokeColor(color))
        }
    }

    private func selectDrawerColor(_ color: PaletteColor, at index: Int) {
        if isQuickColorSelected(index) {
            colorPickerTarget = .stroke
            editingColorSlot = index
            editingColorTool = state.activeTool
            isColorPickerPresented = true
        } else {
            editingColorSlot = index
            editingColorTool = state.activeTool
            send(.setStrokeColor(color))
        }
    }

    private func isQuickColorSelected(_ index: Int) -> Bool {
        editingColorSlot == index && editingColorTool == state.activeTool
    }

    private var quickPaletteColors: [PaletteColor] {
        state.activePaletteColors
    }

    private func railAccentColor(for toolID: ToolID) -> Color {
        switch toolID {
        case .pen: return state.penColor.swiftUIColor
        case .marker: return state.markerColor.swiftUIColor
        case .laser: return state.laserColor.swiftUIColor
        case .selection, .extract, .reserved, .eraser, .geometry, .equation, .cover:
            return ToolPaletteTheme.cyan
        }
    }

    // MARK: - Contextual drawer

    private func drawerPanel(_ configuration: ToolPaletteConfiguration) -> some View {
        contextDrawer(configuration)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(drawerFill)
                    .shadow(color: .black.opacity(0.28), radius: 14, x: 0, y: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
            .padding(.top, drawerTopOffset)
            .padding(.horizontal, 8)
    }

    private var drawerFill: LinearGradient {
        let white = Color.white.opacity(0.9)
        let blue = ToolPaletteTheme.shell
        return LinearGradient(
            colors: dockEdge == .left ? [white, blue] : [blue, white],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var drawerTopOffset: CGFloat {
        max(10, activeToolTopOffset - 10)
    }

    private var activeToolTopOffset: CGFloat {
        var y: CGFloat = 10
        if dragHandle != nil {
            y += Self.dragHandleHeight + Self.railSectionSpacing
        }

        for section in toolSections {
            let sectionTop = y
            if let index = section.firstIndex(of: state.activeTool) {
                return sectionTop + Self.railSectionPadding + CGFloat(index) * (Self.toolButtonHeight + Self.toolButtonSpacing)
            }

            y += Self.railSectionPadding * 2
            y += CGFloat(section.count) * Self.toolButtonHeight
            y += CGFloat(max(section.count - 1, 0)) * Self.toolButtonSpacing
            y += Self.railSectionSpacing
        }

        return y
    }

    private func contextDrawer(_ configuration: ToolPaletteConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(state.activeTool.displayName.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(ToolPaletteTheme.mutedLabel.opacity(0.65))

            if !configuration.topOrbit.isEmpty {
                orbitSection(configuration.topOrbit)
            }

            arcSection(configuration.leftArc)
            arcSection(configuration.rightArc)
        }
        .frame(width: 280, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
        }
    }

    @ViewBuilder
    private func orbitSection(_ items: [PaletteOrbitItem]) -> some View {
        // Colors flow in a wrapping row; action/shape buttons sit in their own row.
        let colorItems = items.filter { $0.color != nil }
        let actionItems = items.filter { $0.color == nil }

        VStack(alignment: .leading, spacing: 10) {
            if !colorItems.isEmpty {
                if state.activeTool == .geometry {
                    geometryColorControls
                } else {
                    CompactFlowRow(spacing: 8) {
                        ForEach(Array(colorItems.enumerated()), id: \.element.id) { index, item in
                            CompactOrbitChip(item: item, isSelected: isOrbitItemSelected(item)) {
                                if let color = item.color {
                                    selectDrawerColor(color, at: index)
                                } else {
                                    send(item.command)
                                }
                            }
                        }
                    }
                }
            }
            if !actionItems.isEmpty {
                CompactFlowRow(spacing: 8) {
                    ForEach(actionItems) { item in
                        CompactOrbitChip(item: item, isSelected: isOrbitItemSelected(item)) {
                            send(item.command)
                        }
                    }
                }
            }
        }
    }

    private var geometryColorControls: some View {
        HStack(spacing: 8) {
            CompactGeometryColorPicker(
                label: "Outline",
                color: state.strokeColor.swiftUIColor,
                selection: geometryStrokeColorBinding
            )
            CompactGeometryColorPicker(
                label: "Fill",
                color: state.fillColor.swiftUIColor,
                selection: geometryFillColorBinding
            )
        }
    }

    @ViewBuilder
    private func arcSection(_ arc: PaletteArcConfiguration) -> some View {
        switch arc {
        case .slider(let slider):
            CompactSlider(configuration: slider, onCommand: send)
        case .segmented(let segmented):
            CompactSegmentedControl(configuration: segmented, onCommand: send)
        case .disabled(let label):
            HStack {
                Image(systemName: "lock")
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(ToolPaletteTheme.mutedLabel.opacity(0.5))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(Color.black.opacity(0.18)))
        }
    }

    // MARK: - Command plumbing (mirrors RadialToolPaletteView.send)

    private func send(_ command: ToolPaletteCommand) {
        switch command {
        case .openColorPicker:
            colorPickerTarget = .stroke
            if editingColorTool != state.activeTool {
                editingColorTool = state.activeTool
                editingColorSlot = activeColorSlotIndex
            }
            isColorPickerPresented = true
        case .openFillColorPicker:
            colorPickerTarget = .fill
            editingColorSlot = nil
            editingColorTool = nil
            isColorPickerPresented = true
        case .openColorPaletteChooser:
            isPaletteChooserPresented = true
        case .openLatexEditor:
            latexDraft = state.latexSource
            isLatexEditorPresented = true
        case .openFontPicker:
            isFontPickerPresented = true
        default:
            break
        }
        ToolPaletteReducer.reduce(&state, command: command)
        onCommand(command)
        onResolvedCommand(command, state)
    }

    /// Selection highlight for orbit items — same rules as the radial dial.
    private func isOrbitItemSelected(_ item: PaletteOrbitItem) -> Bool {
        switch item.command {
        case .setGeometryType(let type):
            return state.activeTool == .geometry && state.geometryType == type
        case .setTextBold:
            return state.activeTool == .equation && state.textStyle == .bold
        case .setTextItalic:
            return state.activeTool == .equation && state.textIsItalic
        case .setTextUnderlined:
            return state.activeTool == .equation && state.textIsUnderlined
        case .openLatexEditor:
            return state.activeTool == .equation && !state.latexSource.isEmpty
        default:
            if item.id == "geometry.fillColor" {
                return item.color == state.fillColor
            }
            return item.color == state.activeStrokeColor
        }
    }

    private var customColorBinding: Binding<Color> {
        Binding(
            get: {
                switch colorPickerTarget {
                case .stroke:
                    if let editingColor = editingPaletteColor {
                        return editingColor.swiftUIColor
                    }
                    return state.activeStrokeColor.swiftUIColor
                case .fill: return state.fillColor.swiftUIColor
                }
            },
            set: { color in
                if let paletteColor = PaletteColor(name: customColorName, color: color) {
                    switch colorPickerTarget {
                    case .stroke:
                        if let editingColorTool, let editingColorSlot, editingColorTool.isCompactInkTool {
                            send(.setPaletteColor(editingColorTool, editingColorSlot, paletteColor))
                        } else {
                            send(.setStrokeColor(paletteColor))
                        }
                    case .fill: send(.setFillColor(paletteColor))
                    }
                }
            }
        )
    }

    private var geometryStrokeColorBinding: Binding<Color> {
        Binding(
            get: { state.strokeColor.swiftUIColor },
            set: { color in
                guard let paletteColor = PaletteColor(name: "Custom Outline", color: color) else { return }
                send(.setStrokeColor(paletteColor))
            }
        )
    }

    private var geometryFillColorBinding: Binding<Color> {
        Binding(
            get: { state.fillColor.swiftUIColor },
            set: { color in
                guard let paletteColor = PaletteColor(name: "Custom Fill", color: color) else { return }
                send(.setFillColor(paletteColor))
            }
        )
    }

    private var editingPaletteColor: PaletteColor? {
        guard let editingColorTool, let editingColorSlot else { return nil }
        let colors: [PaletteColor]
        switch editingColorTool {
        case .pen:
            colors = state.penPaletteColors
        case .marker:
            colors = state.markerPaletteColors
        case .laser:
            colors = state.laserPaletteColors
        case .selection, .extract, .reserved, .eraser, .geometry, .equation, .cover:
            return nil
        }
        guard colors.indices.contains(editingColorSlot) else { return nil }
        return colors[editingColorSlot]
    }

    private var activeColorSlotIndex: Int? {
        state.activePaletteColors.firstIndex(of: state.activeStrokeColor) ?? 0
    }

    private var customColorName: String {
        guard let editingColorSlot else { return "Custom" }
        return "Custom \(editingColorSlot + 1)"
    }
}

private extension ToolID {
    var isCompactInkTool: Bool {
        self == .pen || self == .marker || self == .laser
    }

    var hasCompactQuickStrip: Bool {
        isCompactInkTool || self == .selection || self == .extract || self == .eraser || self == .geometry || self == .cover
    }

    var hasCompactDrawer: Bool {
        self != .selection
    }
}

private enum CompactColorTarget {
    case stroke
    case fill

    var title: String {
        switch self {
        case .stroke: return "Outline Color"
        case .fill: return "Fill Color"
        }
    }
}

private struct CompactQuickModeItem: Identifiable {
    var id: String
    var iconSystemName: String
    var label: String
    var isSelected: Bool
    var command: ToolPaletteCommand
}

// MARK: - Tool button

private struct CompactToolButton: View {
    var toolID: ToolID
    var iconSystemName: String
    var isActive: Bool
    var accentColor: Color
    var outlineColor: Color
    var fillColor: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(buttonFill)
                    .shadow(color: isActive ? .black.opacity(0.30) : .white.opacity(0.55), radius: isActive ? 3 : 4, x: isActive ? 1 : -1, y: isActive ? 1 : -1)
                    .shadow(color: isActive ? .white.opacity(0.16) : .black.opacity(0.24), radius: isActive ? 1 : 5, x: isActive ? -1 : 2, y: isActive ? -1 : 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                isActive ? ToolPaletteTheme.cyan.opacity(0.98) : Color(red: 0.04, green: 0.11, blue: 0.18).opacity(0.32),
                                lineWidth: isActive ? 2.5 : 1.3
                            )
                    )

                icon
                    .frame(width: 26, height: 26)

                if isActive, toolID == .pen || toolID == .marker || toolID == .laser {
                    // Small live-color indicator so the active ink color is visible
                    // even while the drawer is collapsed.
                    Circle()
                        .fill(accentColor)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(6)
                }
            }
            .frame(width: 52, height: 46)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(toolID.displayName)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    @ViewBuilder
    private var icon: some View {
        if toolID == .geometry {
            CompactGeometryIcon(
                outlineColor: isActive ? outlineColor : Color(red: 0.05, green: 0.11, blue: 0.18),
                fillColor: isActive ? fillColor : Color(red: 0.05, green: 0.11, blue: 0.18).opacity(0.18),
                lineWidth: 1.4
            )
        } else {
            Image(systemName: iconSystemName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(iconColor)
        }
    }

    private var iconColor: Color {
        switch toolID {
        case .pen, .marker, .laser:
            return accentColor
        case .selection, .extract, .reserved, .eraser, .geometry, .equation, .cover:
            return isActive ? Color.white : Color(red: 0.02, green: 0.06, blue: 0.10)
        }
    }

    private var buttonFill: Color {
        isActive ? ToolPaletteTheme.segmentRaised.opacity(0.98) : Color.white.opacity(0.64)
    }
}

private struct CompactQuickColorButton: View {
    var color: PaletteColor
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(slotFill)
                    .shadow(color: color.swiftUIColor.opacity(isSelected ? 0.28 : 0), radius: 5)

                Circle()
                    .fill(color.swiftUIColor)
                    .frame(width: 26, height: 26)
                    .overlay(Circle().strokeBorder(circleBorder, lineWidth: isSelected ? 2.5 : 1.5))
            }
            .frame(width: 42, height: 40)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Color.white.opacity(0.72) : Color.white.opacity(0.32), lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color.name)
    }

    private var slotFill: Color {
        isSelected ? color.swiftUIColor.opacity(0.92) : Color.white.opacity(0.34)
    }

    private var circleBorder: Color {
        if isSelected {
            return color == .graphite ? Color.white.opacity(0.88) : Color.black.opacity(0.3)
        }
        return Color.black.opacity(color == .graphite ? 0.32 : 0.18)
    }
}

private struct CompactQuickModeButton: View {
    var iconSystemName: String
    var label: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(slotFill)
                    .shadow(color: ToolPaletteTheme.cyan.opacity(isSelected ? 0.24 : 0), radius: 5)

                Image(systemName: iconSystemName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.9))
            }
            .frame(width: 42, height: 40)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Color.white.opacity(0.72) : Color.white.opacity(0.32), lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var slotFill: Color {
        isSelected ? ToolPaletteTheme.cyan.opacity(0.92) : Color.white.opacity(0.62)
    }
}

private struct CompactGeometryIcon: View {
    var outlineColor: Color
    var fillColor: Color
    var lineWidth: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle()
                    .fill(fillColor)
                    .overlay(Circle().stroke(outlineColor, lineWidth: lineWidth))
                    .frame(width: size * 0.78, height: size * 0.78)
                    .offset(x: -size * 0.10, y: -size * 0.06)

                CompactTriangleShape()
                    .fill(fillColor)
                    .overlay(CompactTriangleShape().stroke(outlineColor, lineWidth: lineWidth))
                    .frame(width: size * 0.74, height: size * 0.66)
                    .offset(x: size * 0.10, y: size * 0.08)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

private struct CompactTriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Orbit chip (color swatch or icon/action button)


private struct CompactOrbitChip: View {
    var item: PaletteOrbitItem
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            if let color = item.color {
                CompactOrbitColorSwatch(color: color, isSelected: isSelected, label: item.label)
            } else {
                CompactOrbitActionChip(
                    iconSystemName: item.iconSystemName,
                    label: item.label,
                    isSelected: isSelected
                )
            }
        }
        .buttonStyle(.plain)
    }
}

private struct CompactOrbitColorSwatch: View {
    var color: PaletteColor
    var isSelected: Bool
    var label: String

    var body: some View {
        Circle()
            .fill(color.swiftUIColor)
            .frame(width: 30, height: 30)
            .overlay(Circle().strokeBorder(.white.opacity(isSelected ? 0.95 : 0.35), lineWidth: isSelected ? 3 : 1.5))
            .shadow(color: color.swiftUIColor.opacity(isSelected ? 0.55 : 0), radius: 5)
            .accessibilityLabel(label)
    }
}

private struct CompactGeometryColorPicker: View {
    var label: String
    var color: Color
    var selection: Binding<Color>

    var body: some View {
        ColorPicker(selection: selection, supportsOpacity: false) {
            HStack(spacing: 7) {
                Circle()
                    .fill(color)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(.white.opacity(0.62), lineWidth: 1.2))
                    .shadow(color: color.opacity(0.28), radius: 3)
                Text(label)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(ToolPaletteTheme.label)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(ToolPaletteTheme.segment))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))
        .accessibilityLabel(label)
    }
}

private struct CompactOrbitActionChip: View {
    var iconSystemName: String?
    var label: String
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            if let iconSystemName {
                Image(systemName: iconSystemName)
                    .font(.system(size: 14, weight: .semibold))
            }
            Text(label)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(isSelected ? Color(red: 0.05, green: 0.11, blue: 0.18) : ToolPaletteTheme.label)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(Capsule().fill(isSelected ? ToolPaletteTheme.cyan.opacity(0.92) : ToolPaletteTheme.segment))
        .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 1))
    }
}

// MARK: - Slider control

private struct CompactSlider: View {
    var configuration: PaletteSliderConfiguration
    var onCommand: (ToolPaletteCommand) -> Void

    @ViewBuilder
    var body: some View {
        if isLineArrowControl {
            lineArrowButtons
        } else {
            sliderContent
        }
    }

    private var isLineArrowControl: Bool {
        configuration.id.lowercased().contains("linearrows")
    }

    private var sliderContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: configuration.iconSystemName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ToolPaletteTheme.mutedLabel.opacity(0.8))
                Text(configuration.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ToolPaletteTheme.label)
                Spacer()
                Text(readout)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(ToolPaletteTheme.cyan)
                    .monospacedDigit()
            }

            Slider(value: valueBinding, in: configuration.range)
                .tint(ToolPaletteTheme.cyan)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ToolPaletteTheme.segment))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.06), lineWidth: 1))
    }

    // A start/end pair of toggle buttons instead of a slider so each line end's
    // arrow can be turned on/off independently.
    private var lineArrowButtons: some View {
        let idx = Int(configuration.value.rounded())
        let startOn = idx == 1 || idx == 3
        let endOn = idx == 2 || idx == 3
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: configuration.iconSystemName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ToolPaletteTheme.mutedLabel.opacity(0.8))
                Text(configuration.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ToolPaletteTheme.label)
                Spacer()
            }
            HStack(spacing: 8) {
                arrowToggleButton(title: "Start", systemImage: "arrow.left", isOn: startOn) {
                    onCommand(configuration.command(Double(Self.arrowIndex(start: !startOn, end: endOn))))
                }
                arrowToggleButton(title: "End", systemImage: "arrow.right", isOn: endOn) {
                    onCommand(configuration.command(Double(Self.arrowIndex(start: startOn, end: !endOn))))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ToolPaletteTheme.segment))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.06), lineWidth: 1))
    }

    private func arrowToggleButton(title: String, systemImage: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(isOn ? Color(red: 0.05, green: 0.11, blue: 0.18) : ToolPaletteTheme.label)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isOn ? ToolPaletteTheme.cyan.opacity(0.92) : ToolPaletteTheme.segment)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private static func arrowIndex(start: Bool, end: Bool) -> Int {
        switch (start, end) {
        case (true, true): return 3
        case (true, false): return 1
        case (false, true): return 2
        case (false, false): return 0
        }
    }

    private var valueBinding: Binding<Double> {
        Binding(
            get: { configuration.value },
            set: { onCommand(configuration.command($0)) }
        )
    }

    private var readout: String {
        let id = configuration.id.lowercased()
        if id.contains("opacity") {
            return "\(Int((configuration.value * 100).rounded()))%"
        }
        if id.contains("duration") {
            let rounded = (configuration.value * 2).rounded() / 2
            return rounded == rounded.rounded() ? "\(Int(rounded))s" : "\(String(format: "%.1f", rounded))s"
        }
        if id.contains("linearrows") {
            switch Int(configuration.value.rounded()) {
            case 1: return "←"
            case 2: return "→"
            case 3: return "↔"
            default: return "•"
            }
        }
        return "\(Int(configuration.value.rounded()))"
    }
}

// MARK: - Segmented control

private struct CompactSegmentedControl: View {
    var configuration: PaletteSegmentedConfiguration
    var onCommand: (ToolPaletteCommand) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(configuration.label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ToolPaletteTheme.label)

            HStack(spacing: 4) {
                ForEach(configuration.segments) { segment in
                    Button {
                        onCommand(segment.command)
                    } label: {
                        HStack(spacing: 5) {
                            if let iconSystemName = segment.iconSystemName {
                                Image(systemName: iconSystemName)
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            Text(segment.label)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(segment.isSelected ? Color(red: 0.05, green: 0.11, blue: 0.18) : ToolPaletteTheme.label)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(segment.isSelected ? ToolPaletteTheme.cyan.opacity(0.92) : Color.clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.black.opacity(0.22)))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ToolPaletteTheme.segment))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.06), lineWidth: 1))
    }
}

// MARK: - Simple wrapping row layout

/// Lays children left-to-right, wrapping to the next line when they overflow the
/// proposed width. Keeps color swatches / action chips compact without a fixed
/// column count.
private struct CompactFlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                maxRowWidth = max(maxRowWidth, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        maxRowWidth = max(maxRowWidth, rowWidth)
        return CGSize(width: min(maxRowWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxX = bounds.maxX
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Popover content

private struct CompactPaletteChooser: View {
    var selectedPreset: PalettePreset
    var onSelect: (PalettePreset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Color Palette").font(.headline)
            ForEach(PalettePreset.allCases) { preset in
                Button {
                    onSelect(preset)
                } label: {
                    HStack(spacing: 10) {
                        HStack(spacing: 4) {
                            ForEach(preset.colors, id: \.id) { color in
                                Circle()
                                    .fill(color.swiftUIColor)
                                    .frame(width: 18, height: 18)
                                    .overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1))
                            }
                        }
                        Text(preset.displayName).font(.system(size: 13, weight: .semibold))
                        Spacer()
                        if preset == selectedPreset {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(ToolPaletteTheme.cyan)
                        }
                    }
                    .foregroundStyle(ToolPaletteTheme.label)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(preset == selectedPreset ? ToolPaletteTheme.segmentRaised : ToolPaletteTheme.segment)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 260)
        .environment(\.colorScheme, .dark)
    }
}

private struct CompactLatexEditor: View {
    @Binding var latexSource: String
    var onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LaTeX").font(.headline)
            TextEditor(text: $latexSource)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(ToolPaletteTheme.label)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(width: 280, height: 120)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ToolPaletteTheme.segment))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
            Button("Apply", action: onApply)
                .buttonStyle(.borderedProminent)
        }
        .frame(width: 300)
        .environment(\.colorScheme, .dark)
    }
}

private struct CompactFontChooser: View {
    var selectedFontName: String
    var onSelect: (String) -> Void

    private let fontNames = ["System", "Serif", "Rounded", "Monospaced"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Font").font(.headline)
            ForEach(fontNames, id: \.self) { fontName in
                Button {
                    onSelect(fontName)
                } label: {
                    HStack {
                        Text("Aa").font(sampleFont(for: fontName))
                        Text(fontName).font(.system(size: 13, weight: .semibold))
                        Spacer()
                        if fontName == selectedFontName {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(ToolPaletteTheme.cyan)
                        }
                    }
                    .foregroundStyle(ToolPaletteTheme.label)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(fontName == selectedFontName ? ToolPaletteTheme.segmentRaised : ToolPaletteTheme.segment)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 230)
        .environment(\.colorScheme, .dark)
    }

    private func sampleFont(for fontName: String) -> Font {
        switch fontName {
        case "Serif": return .system(size: 22, weight: .semibold, design: .serif)
        case "Rounded": return .system(size: 22, weight: .semibold, design: .rounded)
        case "Monospaced": return .system(size: 22, weight: .semibold, design: .monospaced)
        default: return .system(size: 22, weight: .semibold)
        }
    }
}

// MARK: - Prototype host

/// Standalone host that floats the compact palette over a mock canvas and logs
/// the emitted `ToolPaletteCommand`s — the compact-palette analogue of
/// `ToolPalettePrototypeView`, for side-by-side comparison with the radial dial.
public struct CompactToolPalettePrototypeView: View {
    @State private var state = ToolPaletteState()
    @State private var paletteCenter: CGPoint?
    @State private var commandLog: [ToolPaletteCommand] = []

    public init() {}

    public var body: some View {
        ZStack(alignment: .topLeading) {
            CompactMockCanvasBackground()

            FloatingCompactToolPaletteView(
                state: $state,
                center: $paletteCenter,
                onCommand: { command in
                    commandLog.insert(command, at: 0)
                    if commandLog.count > 8 { commandLog.removeLast() }
                }
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("Command Log").font(.headline)
                if commandLog.isEmpty {
                    Text("Interact with the palette")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(commandLog.enumerated()), id: \.offset) { _, command in
                    Text(command.compactDebugLabel)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(12)
            .frame(width: 260, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.black.opacity(0.08), lineWidth: 1))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(20)
        }
    }
}

private struct CompactMockCanvasBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.94, green: 0.96, blue: 0.98)
            CompactGridPattern()
                .stroke(Color(red: 0.72, green: 0.78, blue: 0.86).opacity(0.35), lineWidth: 1)
            VStack(alignment: .leading, spacing: 10) {
                Text("Compact palette prototype")
                    .font(.title2.weight(.semibold))
                Text("Standalone mock canvas — dock docks to the left edge")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(28)
        }
        .ignoresSafeArea()
    }
}

private struct CompactGridPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 32
        var x = rect.minX
        while x <= rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += spacing
        }
        var y = rect.minY
        while y <= rect.maxY {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += spacing
        }
        return path
    }
}

private extension ToolPaletteCommand {
    var compactDebugLabel: String {
        switch self {
        case .selectTool(let tool): return "selectTool(\(tool.rawValue))"
        case .setStrokeColor(let color): return "setStrokeColor(\(color.name))"
        case .setFillColor(let color): return "setFillColor(\(color.name))"
        case .setStrokeWidth(let width): return "setStrokeWidth(\(String(format: "%.1f", width)))"
        case .setOpacity(let opacity): return "setOpacity(\(String(format: "%.2f", opacity)))"
        case .setLaserDuration(let duration): return "setLaserDuration(\(String(format: "%.1f", duration)))"
        case .openColorPicker: return "openColorPicker"
        case .openFillColorPicker: return "openFillColorPicker"
        case .openColorPaletteChooser: return "openColorPaletteChooser"
        case .setPalettePreset(let preset): return "setPalettePreset(\(preset.rawValue))"
        case .setPaletteColor(let tool, let index, let color): return "setPaletteColor(\(tool.rawValue), \(index), \(color.name))"
        case .setGeometryType(let type): return "setGeometryType(\(type.rawValue))"
        case .setPolygonSides(let sides): return "setPolygonSides(\(sides))"
        case .setGeometryLineArrowMode(let mode): return "setGeometryLineArrowMode(\(mode.rawValue))"
        case .setGeometryFillOpacity(let opacity): return "setGeometryFillOpacity(\(String(format: "%.2f", opacity)))"
        case .setSelectionTarget(let target): return "setSelectionTarget(\(target.rawValue))"
        case .setSelectionMode(let mode): return "setSelectionMode(\(mode.rawValue))"
        case .setSelectionBehavior(let behavior): return "setSelectionBehavior(\(behavior.rawValue))"
        case .setEraserMode(let mode): return "setEraserMode(\(mode.rawValue))"
        case .setLaserMode(let mode): return "setLaserMode(\(mode.rawValue))"
        case .setTextBold(let isBold): return "setTextBold(\(isBold))"
        case .setTextItalic(let isItalic): return "setTextItalic(\(isItalic))"
        case .setTextUnderlined(let isUnderlined): return "setTextUnderlined(\(isUnderlined))"
        case .setTextSize(let size): return "setTextSize(\(String(format: "%.1f", size)))"
        case .setTextFontName(let fontName): return "setTextFontName(\(fontName))"
        case .openLatexEditor: return "openLatexEditor"
        case .setLatexSource(let source): return "setLatexSource(\(source))"
        case .openFontPicker: return "openFontPicker"
        case .addItem(let kind): return "addItem(\(kind.rawValue))"
        case .undo: return "undo"
        case .redo: return "redo"
        case .copySelection: return "copySelection"
        case .pasteSelection: return "pasteSelection"
        case .duplicateSelection: return "duplicateSelection"
        case .deleteSelection: return "deleteSelection"
        case .extractSelectionAsImageSticker: return "extractSelectionAsImageSticker"
        case .sendSelectionToNextSlide: return "sendSelectionToNextSlide"
        }
    }
}

// MARK: - Previews

#Preview("Compact — Prototype Host") {
    CompactToolPalettePrototypeView()
}

private struct CompactPalettePreviewHost: View {
    @State private var state: ToolPaletteState
    @State private var paletteCenter: CGPoint?

    init(tool: ToolID) {
        _state = State(initialValue: ToolPaletteState(activeTool: tool))
    }

    var body: some View {
        ZStack {
            Color(red: 0.94, green: 0.96, blue: 0.98)
            FloatingCompactToolPaletteView(
                state: $state,
                center: $paletteCenter
            )
        }
        .ignoresSafeArea()
    }
}

#Preview("Compact — Pen") { CompactPalettePreviewHost(tool: .pen) }
#Preview("Compact — Marker") { CompactPalettePreviewHost(tool: .marker) }
#Preview("Compact — Eraser") { CompactPalettePreviewHost(tool: .eraser) }
#Preview("Compact — Laser") { CompactPalettePreviewHost(tool: .laser) }
#Preview("Compact — Geometry") { CompactPalettePreviewHost(tool: .geometry) }
#Preview("Compact — Selection") { CompactPalettePreviewHost(tool: .selection) }
#Preview("Compact — Text") { CompactPalettePreviewHost(tool: .equation) }
#Preview("Compact — Add") { CompactPalettePreviewHost(tool: .reserved) }
