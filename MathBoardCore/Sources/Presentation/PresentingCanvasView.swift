//
//  PresentingCanvasView.swift
//  MathBoardCore — Presentation module
//
//  Wraps the drawing canvas with the presentation chrome — toggleable
//  viewfinder overlay and the TV-connected status indicator. Pipes
//  rendered canvas frames from `CanvasView` into `DisplayBroker.shared`
//  so the external display can mirror in real time.
//
//  `publishFrame` is a static method (not a closure created in body) so
//  the reference passed to `CanvasView` has stable identity across body
//  re-evaluations. Without that, every parent re-render would look like
//  a parameter change to the underlying UIViewRepresentable, spuriously
//  triggering `updateUIView` and producing SwiftUI AttributeGraph cycles.
//

import SwiftUI
import Canvas
import Calculator
import ToolPalette

public typealias PresentationViewportState = CanvasViewportState
public typealias PresentationCanvasBackground = CanvasBackground
public typealias PresentationCanvasTextObject = CanvasTextObject

public struct PresentingCanvasView: View {
    private let drawingURL: URL
    private let background: PresentationCanvasBackground?
    private let initialViewportState: PresentationViewportState?
    private let onViewportStateChange: (@MainActor (PresentationViewportState) -> Void)?
    private let onInteractionBegan: (@MainActor () -> Void)?
    private let broker = DisplayBroker.shared
    private let calculator = CalculatorState.shared
    private let paletteSettings = ToolPaletteSettings.shared

    @State private var viewportCommand: CanvasViewportCommand?
    @State private var editCommand: CanvasEditCommand?
    @State private var toolCommand: CanvasToolCommand?
    @State private var objectCommand: CanvasObjectCommand?
    @State private var selectionState = CanvasSelectionState()
    @State private var editState = CanvasEditState()

    public init(
        drawingURL: URL,
        background: PresentationCanvasBackground? = nil,
        initialViewportState: PresentationViewportState? = nil,
        onViewportStateChange: (@MainActor (PresentationViewportState) -> Void)? = nil,
        onInteractionBegan: (@MainActor () -> Void)? = nil
    ) {
        self.drawingURL = drawingURL
        self.background = background
        self.initialViewportState = initialViewportState
        self.onViewportStateChange = onViewportStateChange
        self.onInteractionBegan = onInteractionBegan
    }

    public var body: some View {
        ZStack {
            CanvasView(
                drawingURL: drawingURL,
                background: background,
                presentationMode: broker.mode,
                initialViewportState: initialViewportState,
                viewportCommand: viewportCommand,
                editCommand: editCommand,
                toolCommand: toolCommand,
                objectCommand: objectCommand,
                selectionState: $selectionState,
                showsSystemToolPicker: !paletteSettings.isCustomPaletteEnabled,
                onFrameUpdate: broker.isExternalDisplayConnected ? Self.publishFrame : nil,
                onViewportSourceRectChange: broker.isExternalDisplayConnected ? Self.publishViewportSourceRect : nil,
                onLiveStrokeUpdate: Self.publishLiveStroke,
                onViewportStateChange: publishViewportState,
                onEditStateChange: publishEditState,
                onInteractionBegan: onInteractionBegan
            )
            ViewfinderOverlay()
                .opacity(broker.mode == .present ? 1 : 0)

            if calculator.isVisible {
                CalculatorView(state: calculator)
            }

            #if os(iOS)
            if paletteSettings.isCustomPaletteEnabled {
                activeToolPaletteOverlay
            }
            #endif
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        broker.calculatorReferenceSize = proxy.size
                        broker.toolPaletteReferenceSize = proxy.size
                    }
                    .onChange(of: proxy.size) { _, newSize in
                        broker.calculatorReferenceSize = newSize
                        broker.toolPaletteReferenceSize = newSize
                    }
            }
        )
        .ignoresSafeArea(edges: .bottom)
        .toolbar {
            if broker.isExternalDisplayConnected {
                ToolbarItem(placement: .secondaryAction) {
                    Label("TV Connected", systemImage: "tv.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.green)
                }
            }
            ToolbarItemGroup(placement: .secondaryAction) {
                Button {
                    editCommand = CanvasEditCommand(.undo)
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!editState.canUndo)

                Button {
                    editCommand = CanvasEditCommand(.redo)
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(!editState.canRedo)

                Button {
                    viewportCommand = CanvasViewportCommand(.zoomOut)
                } label: {
                    Label("Zoom Out", systemImage: "minus.magnifyingglass")
                }
                .disabled(!canZoomOut)

                Text(zoomLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44)

                Button {
                    viewportCommand = CanvasViewportCommand(.zoomIn)
                } label: {
                    Label("Zoom In", systemImage: "plus.magnifyingglass")
                }
                .disabled(!canZoomIn)

                Button {
                    viewportCommand = CanvasViewportCommand(.fitToViewfinder)
                } label: {
                    Label("Fit to Viewfinder", systemImage: "aspectratio")
                }

                Button {
                    viewportCommand = CanvasViewportCommand(.reset)
                } label: {
                    Label("Reset View", systemImage: "arrow.counterclockwise")
                }
            }

            ToolbarItem(placement: .secondaryAction) {
                Button {
                    togglePresentationMode()
                } label: {
                    Label(
                        broker.mode == .present ? "Mirror Mode" : "Present Mode",
                        systemImage: broker.mode == .present ? "rectangle.dashed" : "rectangle.inset.filled"
                    )
                }
                .tint(broker.mode == .present ? .orange : .blue)
            }

            ToolbarItem(placement: .secondaryAction) {
                Button {
                    calculator.isVisible.toggle()
                } label: {
                    Label("Calculator", systemImage: "function")
                }
                .tint(calculator.isVisible ? .blue : nil)
            }

            #if os(iOS)
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Button {
                        paletteSettings.isCustomPaletteEnabled.toggle()
                    } label: {
                        Label(
                            paletteSettings.isCustomPaletteEnabled ? "Hide Tool Palette" : "Show Tool Palette",
                            systemImage: paletteSettings.isCustomPaletteEnabled ? "eye.slash" : "eye"
                        )
                    }

                    Picker("Palette Style", selection: toolPaletteStyleBinding) {
                        ForEach(ToolPaletteStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }

                    Picker("Palette Size", selection: toolPaletteSizeBinding) {
                        ForEach(ToolPaletteSize.allCases) { size in
                            Text(size.displayName).tag(size)
                        }
                    }
                    .disabled(paletteSettings.paletteStyle != .radial)
                } label: {
                    Label("Tool Palette", systemImage: "paintpalette")
                }
                .tint(paletteSettings.isCustomPaletteEnabled ? .blue : nil)
            }
            #endif
        }
        .onAppear {
            applyCurrentToolPaletteStateIfNeeded(triggering: .selectTool(broker.toolPaletteState.activeTool))
        }
        .task(id: drawingURL) {
            await Task.yield()
            applyCurrentToolPaletteStateIfNeeded(triggering: .selectTool(broker.toolPaletteState.activeTool))
        }
        .onChange(of: paletteSettings.isCustomPaletteEnabled) { _, _ in
            applyCurrentToolPaletteStateIfNeeded(triggering: .selectTool(broker.toolPaletteState.activeTool))
        }
        .onChange(of: paletteSettings.paletteStyle) { _, _ in
            applyCurrentToolPaletteStateIfNeeded(triggering: .selectTool(broker.toolPaletteState.activeTool))
        }
    }

    #if os(iOS)
    @ViewBuilder
    private var activeToolPaletteOverlay: some View {
        switch paletteSettings.paletteStyle {
        case .radial:
            FloatingToolPaletteView(
                state: toolPaletteStateBinding,
                isExpanded: toolPaletteExpandedBinding,
                center: toolPaletteCenterBinding,
                dialSize: paletteSettings.paletteSize.dialSize,
                collapsedSize: paletteSettings.paletteSize.collapsedSize,
                onResolvedCommand: handleToolPaletteCommand
            )
        case .compact:
            FloatingCompactToolPaletteView(
                state: toolPaletteStateBinding,
                center: compactToolPaletteCenterBinding,
                onResolvedCommand: handleToolPaletteCommand
            )
        }
    }
    #endif

    private var zoomLabel: String {
        guard let viewportState = broker.viewportState else { return "100%" }
        return "\(Int((viewportState.zoomScale * 100).rounded()))%"
    }

    private var canZoomIn: Bool {
        guard let viewportState = broker.viewportState else { return true }
        return viewportState.zoomScale < viewportState.maximumZoomScale - 0.01
    }

    private var canZoomOut: Bool {
        guard let viewportState = broker.viewportState else { return true }
        return viewportState.zoomScale > viewportState.minimumZoomScale + 0.01
    }

    private var toolPaletteStateBinding: Binding<ToolPaletteState> {
        Binding(
            get: { broker.toolPaletteState },
            set: { broker.toolPaletteState = $0 }
        )
    }

    private var toolPaletteExpandedBinding: Binding<Bool> {
        Binding(
            get: { broker.isToolPaletteExpanded },
            set: { broker.isToolPaletteExpanded = $0 }
        )
    }

    private var toolPaletteCenterBinding: Binding<CGPoint?> {
        Binding(
            get: { broker.toolPaletteCenter },
            set: { broker.toolPaletteCenter = $0 }
        )
    }

    private var compactToolPaletteCenterBinding: Binding<CGPoint?> {
        Binding(
            get: { broker.compactToolPaletteCenter },
            set: { broker.compactToolPaletteCenter = $0 }
        )
    }

    private var toolPaletteSizeBinding: Binding<ToolPaletteSize> {
        Binding(
            get: { paletteSettings.paletteSize },
            set: { paletteSettings.paletteSize = $0 }
        )
    }

    private var toolPaletteStyleBinding: Binding<ToolPaletteStyle> {
        Binding(
            get: { paletteSettings.paletteStyle },
            set: { paletteSettings.paletteStyle = $0 }
        )
    }

    private func togglePresentationMode() {
        broker.mode = broker.mode == .present ? .mirror : .present
    }

    private func handleToolPaletteCommand(_ command: ToolPaletteCommand, state: ToolPaletteState) {
        applyToolPaletteState(state, triggering: command)
    }

    private func applyCurrentToolPaletteStateIfNeeded(triggering command: ToolPaletteCommand) {
        applyToolPaletteState(broker.toolPaletteState, triggering: command)
    }

    private func applyToolPaletteState(_ state: ToolPaletteState, triggering command: ToolPaletteCommand) {
        guard paletteSettings.isCustomPaletteEnabled,
              let canvasToolCommand = CanvasToolCommand(toolPaletteState: state, triggering: command) else {
            return
        }
        toolCommand = canvasToolCommand
    }

    @MainActor
    private static func publishFrame(_ frame: CGImage, sourceRect: CGRect, viewportSourceRect: CGRect) {
        DisplayBroker.shared.publishFrame(
            frame,
            sourceRect: sourceRect,
            viewportSourceRect: viewportSourceRect
        )
    }

    @MainActor
    private static func publishViewportSourceRect(_ sourceRect: CGRect) {
        DisplayBroker.shared.publishViewportSourceRect(sourceRect)
    }

    @MainActor
    private static func publishLiveStroke(_ stroke: CanvasLiveStroke?) {
        DisplayBroker.shared.publishLiveStroke(stroke)
    }

    @MainActor
    private func publishViewportState(_ state: PresentationViewportState) {
        broker.viewportState = state
        onViewportStateChange?(state)
    }

    @MainActor
    private func publishEditState(_ state: CanvasEditState) {
        editState = state
    }
}

private extension CanvasToolCommand {
    init?(toolPaletteState state: ToolPaletteState, triggering command: ToolPaletteCommand) {
        guard Self.shouldApply(command, activeTool: state.activeTool) else { return nil }

        switch command {
        case .duplicateSelection:
            self.init(.duplicateSelection)
            return
        case .deleteSelection:
            self.init(.deleteSelection)
            return
        default:
            break
        }

        switch state.activeTool {
        case .selection:
            self.init(.select(
                target: CanvasToolCommand.SelectionTarget(selectionTarget: state.selectionTarget),
                mode: CanvasToolCommand.SelectionMode(selectionMode: state.selectionMode)
            ))
        case .geometry, .reserved:
            self.init(.idle)
        case .pen:
            self.init(.pen(
                color: CanvasStrokeColor(color: state.penColor, opacity: state.penOpacity),
                width: CGFloat(state.penStrokeWidth)
            ))
        case .marker:
            self.init(.marker(
                color: CanvasStrokeColor(color: state.markerColor, opacity: state.markerOpacity),
                width: CGFloat(state.markerStrokeWidth)
            ))
        case .eraser:
            self.init(.eraser(
                mode: CanvasToolCommand.EraserMode(eraserMode: state.eraserMode),
                width: CGFloat(state.eraserWidth)
            ))
        case .laser:
            self.init(.laser(
                color: CanvasStrokeColor(color: state.laserColor, opacity: 1),
                diameter: CGFloat(state.laserDiameter),
                duration: state.laserDuration,
                mode: CanvasToolCommand.LaserMode(laserMode: state.laserMode)
            ))
        case .equation:
            self.init(.text(
                color: CanvasStrokeColor(color: state.strokeColor, opacity: state.opacity),
                fontSize: CGFloat(state.textSize),
                isBold: state.textStyle == .bold,
                isItalic: state.textIsItalic,
                isUnderlined: state.textIsUnderlined,
                fontName: state.textFontName
            ))
        }
    }

    private static func shouldApply(_ command: ToolPaletteCommand, activeTool: ToolID) -> Bool {
        switch command {
        case .selectTool(let tool):
            return ToolID.allCases.contains(tool)
        case .setStrokeColor, .setStrokeWidth, .setOpacity:
            return activeTool == .pen || activeTool == .marker || activeTool == .eraser || activeTool == .laser || activeTool == .equation
        case .setEraserMode:
            return activeTool == .eraser
        case .setLaserDuration, .setLaserMode:
            return activeTool == .laser
        case .setTextBold, .setTextItalic, .setTextUnderlined, .setTextSize, .setTextFontName:
            return activeTool == .equation
        case .setSelectionTarget, .setSelectionMode, .duplicateSelection, .deleteSelection:
            return activeTool == .selection
        default:
            return false
        }
    }
}

private extension CanvasStrokeColor {
    init(color: PaletteColor, opacity: Double) {
        self.init(
            red: CGFloat(color.red),
            green: CGFloat(color.green),
            blue: CGFloat(color.blue),
            alpha: CGFloat(opacity)
        )
    }
}

#if os(iOS)
private struct FloatingCompactToolPaletteView: View {
    @Binding var state: ToolPaletteState
    @Binding var center: CGPoint?

    var onResolvedCommand: (ToolPaletteCommand, ToolPaletteState) -> Void

    @State private var measuredSize: CGSize = .zero
    @State private var dragStartCenter: CGPoint?

    var body: some View {
        GeometryReader { proxy in
            let containerSize = proxy.size
            let paletteSize = measuredSize == .zero ? Self.fallbackSize : measuredSize
            let resolvedCenter = center ?? Self.defaultCenter(in: containerSize, paletteSize: paletteSize)

            VStack(alignment: .leading, spacing: 0) {
                dragHandle
                    .gesture(dragGesture(in: containerSize, currentCenter: resolvedCenter, paletteSize: paletteSize))
                CompactToolPaletteView(
                    state: $state,
                    onResolvedCommand: onResolvedCommand
                )
            }
            .background(
                GeometryReader { paletteProxy in
                    Color.clear
                        .onAppear {
                            measuredSize = paletteProxy.size
                        }
                        .onChange(of: paletteProxy.size) { _, newSize in
                            measuredSize = newSize
                            if let center {
                                self.center = Self.clamp(center, in: containerSize, paletteSize: newSize)
                            }
                        }
                }
            )
            .position(resolvedCenter)
        }
    }

    private var dragHandle: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .bold))
            Text("Move")
                .font(.system(size: 11, weight: .heavy))
                .textCase(.uppercase)
                .tracking(1)
        }
        .foregroundStyle(Color.white.opacity(0.78))
        .frame(width: Self.railWidth, height: 30)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 18,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 18,
                style: .continuous
            )
            .fill(Color(red: 0.08, green: 0.18, blue: 0.30))
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .accessibilityLabel("Move compact tool palette")
    }

    private func dragGesture(in containerSize: CGSize, currentCenter: CGPoint, paletteSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                let base = dragStartCenter ?? currentCenter
                if dragStartCenter == nil {
                    dragStartCenter = base
                }
                center = Self.clamp(
                    CGPoint(x: base.x + value.translation.width, y: base.y + value.translation.height),
                    in: containerSize,
                    paletteSize: paletteSize
                )
            }
            .onEnded { _ in
                dragStartCenter = nil
            }
    }

    private static let fallbackSize = CGSize(width: 360, height: 420)
    private static let railWidth: CGFloat = 68
    private static let margin: CGFloat = 16

    private static func defaultCenter(in containerSize: CGSize, paletteSize: CGSize) -> CGPoint {
        clamp(
            CGPoint(
                x: containerSize.width - paletteSize.width / 2 - margin,
                y: paletteSize.height / 2 + margin
            ),
            in: containerSize,
            paletteSize: paletteSize
        )
    }

    private static func clamp(_ point: CGPoint, in containerSize: CGSize, paletteSize: CGSize) -> CGPoint {
        let halfWidth = max(paletteSize.width / 2, 1)
        let halfHeight = max(paletteSize.height / 2, 1)
        let minX = halfWidth + margin
        let maxX = max(minX, containerSize.width - halfWidth - margin)
        let minY = halfHeight + margin
        let maxY = max(minY, containerSize.height - halfHeight - margin)
        return CGPoint(
            x: min(max(point.x, minX), maxX),
            y: min(max(point.y, minY), maxY)
        )
    }
}
#endif

private extension CanvasToolCommand.EraserMode {
    init(eraserMode: EraserMode) {
        switch eraserMode {
        case .pixel:
            self = .pixel
        case .stroke:
            self = .stroke
        }
    }
}

private extension CanvasToolCommand.LaserMode {
    init(laserMode: LaserMode) {
        switch laserMode {
        case .dot:
            self = .dot
        case .trail:
            self = .trail
        }
    }
}

private extension CanvasToolCommand.SelectionTarget {
    init(selectionTarget: SelectionTarget) {
        switch selectionTarget {
        case .object:
            self = .object
        case .region:
            self = .region
        }
    }
}

private extension CanvasToolCommand.SelectionMode {
    init(selectionMode: SelectionMode) {
        switch selectionMode {
        case .lasso:
            self = .lasso
        case .marquee:
            self = .marquee
        }
    }
}
