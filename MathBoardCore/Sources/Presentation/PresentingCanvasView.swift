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
import GraphCalculator
import TextEngine
import ToolPalette

public typealias PresentationViewportState = CanvasViewportState
public typealias PresentationCanvasBackground = CanvasBackground
public typealias PresentationCanvasTextObject = CanvasTextObject
public typealias PresentationCanvasImageObject = CanvasImageObject
public typealias PresentationExtractedRegion = CanvasExtractedRegion

public struct PresentingCanvasView: View {
    private let drawingURL: URL
    private let background: PresentationCanvasBackground?
    private let initialViewportState: PresentationViewportState?
    private let onViewportStateChange: (@MainActor (PresentationViewportState) -> Void)?
    private let onInteractionBegan: (@MainActor () -> Void)?
    private let onExtractedRegionSend: (@MainActor (PresentationExtractedRegion) -> Void)?
    private let broker = DisplayBroker.shared
    private let calculator = CalculatorState.shared
    private let paletteSettings = ToolPaletteSettings.shared

    @State private var viewportCommand: CanvasViewportCommand?
    @State private var editCommand: CanvasEditCommand?
    @State private var toolCommand: CanvasToolCommand?
    @State private var objectCommand: CanvasObjectCommand?
    @State private var selectionState = CanvasSelectionState()
    @State private var editState = CanvasEditState()
    @State private var pendingTextPlacement: PendingTextPlacement?
    @State private var pendingTextEdit: PendingTextEdit?

    public init(
        drawingURL: URL,
        background: PresentationCanvasBackground? = nil,
        initialViewportState: PresentationViewportState? = nil,
        onViewportStateChange: (@MainActor (PresentationViewportState) -> Void)? = nil,
        onInteractionBegan: (@MainActor () -> Void)? = nil,
        onExtractedRegionSend: (@MainActor (PresentationExtractedRegion) -> Void)? = nil
    ) {
        self.drawingURL = drawingURL
        self.background = background
        self.initialViewportState = initialViewportState
        self.onViewportStateChange = onViewportStateChange
        self.onInteractionBegan = onInteractionBegan
        self.onExtractedRegionSend = onExtractedRegionSend
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
                onInteractionBegan: onInteractionBegan,
                onTextEditingBegan: activateTextToolForExistingEditor,
                onTextEditingEnded: activateSelectTool,
                onTextPlacementRequested: requestTextPlacement,
                onExtractedRegionSend: onExtractedRegionSend
            )
            ViewfinderOverlay()
                .opacity(broker.mode == .present ? 1 : 0)

            if calculator.isVisible {
                CalculatorView(state: calculator)
            }

            if broker.isGraphCalculatorVisible {
                GraphCalculatorView(state: broker.graphCalculator)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            selectedTextActionHUD

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
                        broker.isGraphCalculatorVisible.toggle()
                    } label: {
                        Label(
                            broker.isGraphCalculatorVisible ? "Hide graphCalc" : "Show graphCalc",
                            systemImage: "chart.xyaxis.line"
                        )
                    }

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
        .fullScreenCover(item: $pendingTextPlacement) { placement in
            TextEditorModalView { result in
                insertText(result, at: placement.sourcePoint)
                pendingTextPlacement = nil
                activateSelectTool()
            } onCancel: {
                pendingTextPlacement = nil
                activateSelectTool()
            }
        }
        .fullScreenCover(item: $pendingTextEdit) { edit in
            TextEditorModalView(
                viewModel: TextEditorViewModel(
                    text: edit.object.text,
                    isBold: edit.object.isBold,
                    isItalic: edit.object.isItalic,
                    isUnderline: edit.object.isUnderlined,
                    fontSize: edit.object.fontSize,
                    fontName: edit.object.fontName ?? "System"
                )
            ) { result in
                updateText(result, object: edit.object)
                pendingTextEdit = nil
                activateSelectTool()
            } onCancel: {
                pendingTextEdit = nil
                activateSelectTool()
            }
        }
    }

    private var selectedTextActionHUD: some View {
        GeometryReader { proxy in
            if let object = selectionState.selectedTextObject,
               let viewportFrame = selectionState.viewportFrame,
               pendingTextEdit == nil,
               pendingTextPlacement == nil {
                FloatingActionHUD(
                    onEdit: { pendingTextEdit = PendingTextEdit(object: object) },
                    onClone: { objectCommand = CanvasObjectCommand(.duplicate(.text(object.id))) },
                    onDelete: { objectCommand = CanvasObjectCommand(.delete(.text(object.id))) }
                )
                .position(hudPosition(for: viewportFrame, in: proxy.size))
            }
        }
        .ignoresSafeArea()
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

    private func activateTextToolForExistingEditor() {
        var state = broker.toolPaletteState
        ToolPaletteReducer.reduce(&state, command: .selectTool(.equation))
        broker.toolPaletteState = state
        applyToolPaletteState(state, triggering: .selectTool(.equation))
    }

    private func requestTextPlacement(at sourcePoint: CGPoint) {
        pendingTextPlacement = PendingTextPlacement(sourcePoint: sourcePoint)
    }

    private func insertText(_ result: TextEditorResult, at sourcePoint: CGPoint) {
        let state = broker.toolPaletteState
        objectCommand = CanvasObjectCommand(.insertText(CanvasTextInsertion(
            text: result.sourceText,
            sourcePoint: sourcePoint,
            fontSize: result.fontSize,
            color: CanvasStrokeColor(color: state.strokeColor, opacity: state.opacity),
            isBold: result.isBold,
            isItalic: result.isItalic,
            isUnderlined: result.isUnderline,
            fontName: result.fontName
        )))
    }

    private func updateText(_ result: TextEditorResult, object: CanvasTextObject) {
        objectCommand = CanvasObjectCommand(.updateText(CanvasTextUpdate(
            id: object.id,
            text: result.sourceText,
            fontSize: result.fontSize,
            isBold: result.isBold,
            isItalic: result.isItalic,
            isUnderlined: result.isUnderline,
            fontName: result.fontName
        )))
    }

    private func activateSelectTool() {
        var state = broker.toolPaletteState
        ToolPaletteReducer.reduce(&state, command: .selectTool(.selection))
        broker.toolPaletteState = state
        applyToolPaletteState(state, triggering: .selectTool(.selection))
    }

    private func hudPosition(for frame: CGRect, in size: CGSize) -> CGPoint {
        let hudWidth: CGFloat = 148
        let hudHeight: CGFloat = 44
        let margin: CGFloat = 14
        let requestedDownwardOffset: CGFloat = 90
        let aboveY = frame.minY - hudHeight / 2 - 4
        let belowY = frame.maxY + hudHeight / 2 + 12
        let proposedY = (aboveY >= margin + hudHeight / 2 ? aboveY : belowY) + requestedDownwardOffset
        return CGPoint(
            x: min(max(frame.midX, margin + hudWidth / 2), size.width - margin - hudWidth / 2),
            y: min(max(proposedY, margin + hudHeight / 2), size.height - margin - hudHeight / 2)
        )
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

private struct PendingTextPlacement: Identifiable {
    let id = UUID()
    var sourcePoint: CGPoint
}

private struct PendingTextEdit: Identifiable {
    var object: CanvasTextObject

    var id: UUID {
        object.id
    }
}

private struct FloatingActionHUD: View {
    let onEdit: () -> Void
    let onClone: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            hudButton("Edit", systemImage: "pencil", action: onEdit)
            hudButton("Clone", systemImage: "plus.square.on.square", action: onClone)
            hudButton("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 10, x: 0, y: 4)
    }

    private func hudButton(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? .red : .primary)
        .background(Color.white.opacity(0.86), in: Circle())
        .overlay(
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .help(title)
    }
}

private extension CanvasToolCommand {
    init?(toolPaletteState state: ToolPaletteState, triggering command: ToolPaletteCommand) {
        guard Self.shouldApply(command, activeTool: state.activeTool) else { return nil }

        switch command {
        case .copySelection:
            self.init(.copySelection)
            return
        case .duplicateSelection:
            self.init(.duplicateSelection)
            return
        case .deleteSelection:
            self.init(.deleteSelection)
            return
        case .extractSelectionAsImageSticker:
            self.init(.extractSelectionAsImageSticker)
            return
        case .sendSelectionToNextSlide:
            self.init(.sendSelectionToNextSlide)
            return
        default:
            break
        }

        switch state.activeTool {
        case .selection:
            self.init(.select(
                target: .object,
                mode: CanvasToolCommand.SelectionMode(selectionMode: state.selectionMode)
            ))
        case .extract:
            self.init(.select(
                target: .region,
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
        case .setStrokeColor, .setPaletteColor, .setStrokeWidth, .setOpacity:
            return activeTool == .pen || activeTool == .marker || activeTool == .eraser || activeTool == .laser || activeTool == .equation
        case .setEraserMode:
            return activeTool == .eraser
        case .setLaserDuration, .setLaserMode:
            return activeTool == .laser
        case .setTextBold, .setTextItalic, .setTextUnderlined, .setTextSize, .setTextFontName:
            return activeTool == .equation
        case .setSelectionTarget:
            return activeTool == .selection || activeTool == .extract
        case .setSelectionMode:
            return activeTool == .extract
        case .copySelection, .duplicateSelection, .deleteSelection,
             .extractSelectionAsImageSticker, .sendSelectionToNextSlide:
            return activeTool == .selection || activeTool == .extract
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
