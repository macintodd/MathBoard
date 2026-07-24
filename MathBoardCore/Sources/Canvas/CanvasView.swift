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
import WidgetEngine

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
    private let onWidgetObjectsChange: (@MainActor ([WidgetObject], WidgetCanvasViewport, CGSize, String) -> Void)?
    private let onViewportStateChange: (@MainActor (CanvasViewportState) -> Void)?
    private let onEditStateChange: (@MainActor (CanvasEditState) -> Void)?
    private let onInteractionBegan: (@MainActor () -> Void)?
    private let onTextEditingBegan: (@MainActor () -> Void)?
    private let onTextEditingEnded: (@MainActor () -> Void)?
    private let onTextPlacementRequested: (@MainActor (CGPoint) -> Void)?
    private let onLibraryTextDerivativeCreated: (@MainActor (CanvasTextObject) -> Bool)?
    private let onExtractedRegionSend: (@MainActor (CanvasExtractedRegion) -> Void)?
    private let onExtractedRegionPlaced: (@MainActor (CanvasExtractedRegion) -> Void)?
    private let onExtractActionCompleted: (@MainActor () -> Void)?
    private let onWidgetEditRequested: (@MainActor (WidgetObject) -> Void)?
    private let allowsWidgetAuthoring: Bool

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
        onWidgetObjectsChange: (@MainActor ([WidgetObject], WidgetCanvasViewport, CGSize, String) -> Void)? = nil,
        onViewportStateChange: (@MainActor (CanvasViewportState) -> Void)? = nil,
        onEditStateChange: (@MainActor (CanvasEditState) -> Void)? = nil,
        onInteractionBegan: (@MainActor () -> Void)? = nil,
        onTextEditingBegan: (@MainActor () -> Void)? = nil,
        onTextEditingEnded: (@MainActor () -> Void)? = nil,
        onTextPlacementRequested: (@MainActor (CGPoint) -> Void)? = nil,
        onLibraryTextDerivativeCreated: (@MainActor (CanvasTextObject) -> Bool)? = nil,
        onExtractedRegionSend: (@MainActor (CanvasExtractedRegion) -> Void)? = nil,
        onExtractedRegionPlaced: (@MainActor (CanvasExtractedRegion) -> Void)? = nil,
        onExtractActionCompleted: (@MainActor () -> Void)? = nil,
        onWidgetEditRequested: (@MainActor (WidgetObject) -> Void)? = nil,
        allowsWidgetAuthoring: Bool = true
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
        self.onWidgetObjectsChange = onWidgetObjectsChange
        self.onViewportStateChange = onViewportStateChange
        self.onEditStateChange = onEditStateChange
        self.onInteractionBegan = onInteractionBegan
        self.onTextEditingBegan = onTextEditingBegan
        self.onTextEditingEnded = onTextEditingEnded
        self.onTextPlacementRequested = onTextPlacementRequested
        self.onLibraryTextDerivativeCreated = onLibraryTextDerivativeCreated
        self.onExtractedRegionSend = onExtractedRegionSend
        self.onExtractedRegionPlaced = onExtractedRegionPlaced
        self.onExtractActionCompleted = onExtractActionCompleted
        self.onWidgetEditRequested = onWidgetEditRequested
        self.allowsWidgetAuthoring = allowsWidgetAuthoring
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
            onWidgetObjectsChange: onWidgetObjectsChange,
            onViewportStateChange: onViewportStateChange,
            onEditStateChange: onEditStateChange,
            onInteractionBegan: onInteractionBegan,
            onTextEditingBegan: onTextEditingBegan,
            onTextEditingEnded: onTextEditingEnded,
            onTextPlacementRequested: onTextPlacementRequested,
            onLibraryTextDerivativeCreated: onLibraryTextDerivativeCreated,
            onExtractedRegionSend: onExtractedRegionSend,
            onExtractedRegionPlaced: onExtractedRegionPlaced,
            onExtractActionCompleted: onExtractActionCompleted,
            onWidgetEditRequested: onWidgetEditRequested,
            allowsWidgetAuthoring: allowsWidgetAuthoring
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
