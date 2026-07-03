//
//  CanvasView.swift
//  MathBoardCore — Canvas module
//
//  Public entry point. Takes a URL pointing at a `.drawing` file (the
//  raw `PKDrawing` data) and renders the appropriate drawing surface for
//  the platform.
//  - iPad: PencilKit canvas with the system tool picker, auto-loads /
//    saves from / to the given URL.
//  - Mac: simple mouse-based prep drawing that saves compatible `PKDrawing`
//    data.
//

import SwiftUI
import CoreGraphics

public struct CanvasView: View {
    private let drawingURL: URL
    private let background: CanvasBackground?
    private let presentationMode: CanvasPresentationMode
    private let initialViewportState: CanvasViewportState?
    private let viewportCommand: CanvasViewportCommand?
    private let editCommand: CanvasEditCommand?
    private let toolCommand: CanvasToolCommand?
    private let objectCommand: CanvasObjectCommand?
    @Binding private var selectionState: CanvasSelectionState
    private let showsSystemToolPicker: Bool
    private let onFrameUpdate: (@MainActor (CGImage, CGRect, CGRect) -> Void)?
    private let onViewportSourceRectChange: (@MainActor (CGRect) -> Void)?
    private let onLiveStrokeUpdate: (@MainActor (CanvasLiveStroke?) -> Void)?
    private let onViewportStateChange: (@MainActor (CanvasViewportState) -> Void)?
    private let onEditStateChange: (@MainActor (CanvasEditState) -> Void)?
    private let onInteractionBegan: (@MainActor () -> Void)?
    private let onTextEditingBegan: (@MainActor () -> Void)?
    private let onTextEditingEnded: (@MainActor () -> Void)?
    private let onTextPlacementRequested: (@MainActor (CGPoint) -> Void)?

    public init(
        drawingURL: URL,
        background: CanvasBackground? = nil,
        presentationMode: CanvasPresentationMode = .present,
        initialViewportState: CanvasViewportState? = nil,
        viewportCommand: CanvasViewportCommand? = nil,
        editCommand: CanvasEditCommand? = nil,
        toolCommand: CanvasToolCommand? = nil,
        objectCommand: CanvasObjectCommand? = nil,
        selectionState: Binding<CanvasSelectionState> = .constant(CanvasSelectionState()),
        showsSystemToolPicker: Bool = true,
        onFrameUpdate: (@MainActor (CGImage, CGRect, CGRect) -> Void)? = nil,
        onViewportSourceRectChange: (@MainActor (CGRect) -> Void)? = nil,
        onLiveStrokeUpdate: (@MainActor (CanvasLiveStroke?) -> Void)? = nil,
        onViewportStateChange: (@MainActor (CanvasViewportState) -> Void)? = nil,
        onEditStateChange: (@MainActor (CanvasEditState) -> Void)? = nil,
        onInteractionBegan: (@MainActor () -> Void)? = nil,
        onTextEditingBegan: (@MainActor () -> Void)? = nil,
        onTextEditingEnded: (@MainActor () -> Void)? = nil,
        onTextPlacementRequested: (@MainActor (CGPoint) -> Void)? = nil
    ) {
        self.drawingURL = drawingURL
        self.background = background
        self.presentationMode = presentationMode
        self.initialViewportState = initialViewportState
        self.viewportCommand = viewportCommand
        self.editCommand = editCommand
        self.toolCommand = toolCommand
        self.objectCommand = objectCommand
        self._selectionState = selectionState
        self.showsSystemToolPicker = showsSystemToolPicker
        self.onFrameUpdate = onFrameUpdate
        self.onViewportSourceRectChange = onViewportSourceRectChange
        self.onLiveStrokeUpdate = onLiveStrokeUpdate
        self.onViewportStateChange = onViewportStateChange
        self.onEditStateChange = onEditStateChange
        self.onInteractionBegan = onInteractionBegan
        self.onTextEditingBegan = onTextEditingBegan
        self.onTextEditingEnded = onTextEditingEnded
        self.onTextPlacementRequested = onTextPlacementRequested
    }

    public var body: some View {
        #if os(iOS)
        PencilKitCanvasContainer(
            drawingURL: drawingURL,
            background: background,
            presentationMode: presentationMode,
            initialViewportState: initialViewportState,
            viewportCommand: viewportCommand,
            editCommand: editCommand,
            toolCommand: toolCommand,
            objectCommand: objectCommand,
            selectionState: $selectionState,
            showsSystemToolPicker: showsSystemToolPicker,
            onFrameUpdate: onFrameUpdate,
            onViewportSourceRectChange: onViewportSourceRectChange,
            onLiveStrokeUpdate: onLiveStrokeUpdate,
            onViewportStateChange: onViewportStateChange,
            onEditStateChange: onEditStateChange,
            onInteractionBegan: onInteractionBegan,
            onTextEditingBegan: onTextEditingBegan,
            onTextEditingEnded: onTextEditingEnded,
            onTextPlacementRequested: onTextPlacementRequested
        )
        #else
        MacCanvasPlaceholder(
            drawingURL: drawingURL,
            background: background,
            initialViewportState: initialViewportState,
            viewportCommand: viewportCommand,
            onViewportStateChange: onViewportStateChange,
            onInteractionBegan: onInteractionBegan
        )
        #endif
    }
}
