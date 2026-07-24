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
import Library
import PDFKit
import TextEngine
import ToolPalette
import UniformTypeIdentifiers
import WidgetEngine

#if os(iOS)
import PhotosUI
import UIKit
#elseif os(macOS)
import AppKit
#endif

public typealias PresentationViewportState = CanvasViewportState
public typealias PresentationCanvasBackground = CanvasBackground
public typealias PresentationCanvasTextObject = CanvasTextObject
public typealias PresentationCanvasImageObject = CanvasImageObject
public typealias PresentationCanvasGeometryObject = CanvasGeometryObject
public typealias PresentationCanvasBoardMetrics = CanvasBoardMetrics
public typealias PresentationGeometryRenderer = CanvasGeometryRenderer
public typealias PresentationExtractedRegion = CanvasExtractedRegion

public struct PresentingCanvasView: View {
    private let drawingURL: URL
    private let background: PresentationCanvasBackground?
    private let initialViewportState: PresentationViewportState?
    private let onViewportStateChange: (@MainActor (PresentationViewportState) -> Void)?
    private let onInteractionBegan: (@MainActor () -> Void)?
    private let onTextEditingBegan: (@MainActor () -> Void)?
    private let onTextEditingEnded: (@MainActor () -> Void)?
    private let onExtractedRegionSend: (@MainActor (PresentationExtractedRegion) -> Void)?
    private let onImportPDF: (@MainActor () -> Void)?
    private let onImportPDFObjects: (@MainActor (URL, [Int]) -> Void)?
    private let onExportPDF: (@MainActor () -> Void)?
    private let allowsWidgetAuthoring: Bool
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
    @State private var pendingLaTeXPlacement: PendingLaTeXPlacement?
    @State private var pendingLaTeXEdit: PendingLaTeXEdit?
    @State private var actionHUDOffset: CGSize = .zero
    @State private var actionHUDStoredOffset: CGSize = .zero
    @State private var isClearingGeometrySelectionForCreation = false
    @State private var isImageFileImporterPresented = false
    @State private var isPhotoImporterPresented = false
    @State private var isCameraImporterPresented = false
    @State private var isWidgetEditorPresented = false
    @State private var pendingWidgetEdit: PendingWidgetEdit?
    @State private var pendingPDFObjectImport: PendingPDFObjectImport?
    @State private var imageFileImportError: ImageFileImportError?
    @State private var libraryRecentRefreshID = UUID()

    public init(
        drawingURL: URL,
        background: PresentationCanvasBackground? = nil,
        initialViewportState: PresentationViewportState? = nil,
        onViewportStateChange: (@MainActor (PresentationViewportState) -> Void)? = nil,
        onInteractionBegan: (@MainActor () -> Void)? = nil,
        onTextEditingBegan: (@MainActor () -> Void)? = nil,
        onTextEditingEnded: (@MainActor () -> Void)? = nil,
        onExtractedRegionSend: (@MainActor (PresentationExtractedRegion) -> Void)? = nil,
        onImportPDF: (@MainActor () -> Void)? = nil,
        onImportPDFObjects: (@MainActor (URL, [Int]) -> Void)? = nil,
        onExportPDF: (@MainActor () -> Void)? = nil,
        allowsWidgetAuthoring: Bool = true
    ) {
        self.drawingURL = drawingURL
        self.background = background
        self.initialViewportState = initialViewportState
        self.onViewportStateChange = onViewportStateChange
        self.onInteractionBegan = onInteractionBegan
        self.onTextEditingBegan = onTextEditingBegan
        self.onTextEditingEnded = onTextEditingEnded
        self.onExtractedRegionSend = onExtractedRegionSend
        self.onImportPDF = onImportPDF
        self.onImportPDFObjects = onImportPDFObjects
        self.onExportPDF = onExportPDF
        self.allowsWidgetAuthoring = allowsWidgetAuthoring
    }

    // The full-screen drawing surface and its full-bleed overlays. This
    // ignores all safe areas so the whiteboard reaches every edge of the
    // display; the floating chrome (back/title, tool menu) is layered over
    // it separately and respects the safe area.
    private var canvasStack: some View {
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
                onViewportSourceRectChange: Self.publishViewportSourceRect,
                onLiveStrokeUpdate: Self.publishLiveStroke,
                onWidgetObjectsChange: Self.publishWidgets,
                onViewportStateChange: publishViewportState,
                onEditStateChange: publishEditState,
                onInteractionBegan: handleCanvasInteractionBegan,
                onTextEditingBegan: handleTextEditingBegan,
                onTextEditingEnded: handleTextEditingEnded,
                onTextPlacementRequested: requestTextPlacement,
                onLibraryTextDerivativeCreated: recordLibraryTextDerivative,
                onExtractedRegionSend: handleExtractedRegionSend,
                onExtractedRegionPlaced: recordExtractedRegionPlacement,
                onExtractActionCompleted: activateSelectToolAfterExtractAction,
                onWidgetEditRequested: allowsWidgetAuthoring ? requestWidgetEdit : nil,
                allowsWidgetAuthoring: allowsWidgetAuthoring
            )
            ViewfinderOverlay()
                .opacity(broker.mode == .present ? 1 : 0)

            if calculator.isVisible {
                CalculatorView(state: calculator)
            }

            floatingLaTeXEditor

            if isGraphCalculatorVisibleToUser {
                GraphCalculatorView(
                    state: broker.graphCalculator,
                    onGraphSnapshot: insertGraphSnapshot
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            selectedTextActionHUD

            #if os(iOS)
            if paletteSettings.isCustomPaletteEnabled {
                activeToolPaletteOverlay
            }
            #endif
        }
        .onDrop(
            of: [UTType(exportedAs: LibraryCanvasDragPayload.typeIdentifier)],
            isTargeted: nil
        ) { providers, location in
            handleLibraryItemDrop(providers, at: location)
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
        .ignoresSafeArea()
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            canvasStack
            LibraryDrawerPrototypeView(
                startOpen: false,
                recentLessonURL: LibraryRecentStore.lessonURL(forDrawingURL: drawingURL),
                recentRefreshID: libraryRecentRefreshID,
                onInsertItem: placeLibraryItemAtViewportCenter
            )
            floatingToolMenu
                .padding(.top, 8)
                .padding(.trailing, 12)
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
        .onChange(of: selectionState.selectedObject) { oldValue, newValue in
            handleSelectionChange(from: oldValue, to: newValue)
            if oldValue != newValue {
                actionHUDOffset = .zero
                actionHUDStoredOffset = .zero
            }
        }
        .onChange(of: isLaTeXEditorPresented) { _, isPresented in
            if isPresented {
                onTextEditingBegan?()
            } else {
                onTextEditingEnded?()
            }
        }
        .platformEditorCover(item: $pendingTextPlacement) { placement in
            TextEditorModalView { result in
                insertText(result, placement: placement)
                pendingTextPlacement = nil
                activateSelectTool()
            } onCancel: {
                pendingTextPlacement = nil
                activateSelectTool()
            }
        }
        .platformEditorCover(item: $pendingTextEdit) { edit in
            TextEditorModalView(
                viewModel: TextEditorViewModel(
                    text: edit.object.text,
                    isBold: edit.object.isBold,
                    isItalic: edit.object.isItalic,
                    isUnderline: edit.object.isUnderlined,
                    fontSize: editorFontSize(forCanvasFontSize: edit.object.fontSize),
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
        .platformEditorCover(isPresented: $isWidgetEditorPresented) {
            WidgetEditorView(onInsertWidget: { insertion in
                insertWidget(insertion)
                isWidgetEditorPresented = false
                activateSelectTool()
            }, onCancel: {
                isWidgetEditorPresented = false
                activateSelectTool()
            })
        }
        .platformEditorCover(item: $pendingWidgetEdit) { edit in
            WidgetEditorView(
                initialJSONSource: edit.widget.codeString,
                insertButtonTitle: "Update Widget"
            ) { insertion in
                updateWidget(insertion, id: edit.widget.id)
                pendingWidgetEdit = nil
                activateSelectTool()
            } onCancel: {
                pendingWidgetEdit = nil
                activateSelectTool()
            }
        }
        #if os(iOS)
        .sheet(isPresented: $isImageFileImporterPresented) {
            ImageDocumentPicker { result in
                isImageFileImporterPresented = false
                handleImageFileImport(result)
            } onCancel: {
                isImageFileImporterPresented = false
            }
        }
        .sheet(isPresented: $isPhotoImporterPresented) {
            ImagePhotoPicker { result in
                isPhotoImporterPresented = false
                handlePhotoImport(result)
            } onCancel: {
                isPhotoImporterPresented = false
            }
        }
        .sheet(isPresented: $isCameraImporterPresented) {
            ImageCameraPicker { result in
                isCameraImporterPresented = false
                handleCameraImport(result)
            } onCancel: {
                isCameraImporterPresented = false
            }
        }
        #elseif os(macOS)
        .fileImporter(
            isPresented: $isImageFileImporterPresented,
            allowedContentTypes: [.image, .pdf],
            allowsMultipleSelection: false
        ) { result in
            handleImageFileImport(result)
        }
        #endif
        .sheet(item: $pendingPDFObjectImport) { pendingImport in
            PDFObjectImportPreviewView(
                pdfURL: pendingImport.url,
                onCancel: clearPendingPDFObjectImport,
                onImport: { pageIndices in
                    importSelectedPDFPagesAsObjects(pageIndices, from: pendingImport)
                }
            )
        }
        .alert(item: $imageFileImportError) { error in
            Alert(
                title: Text("Image Import Failed"),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // Floating overflow menu that replaces the former navigation-bar toolbar.
    // Layered over the full-screen canvas (top-trailing) so the whiteboard can
    // use the entire display while every tool stays reachable.
    private var floatingToolMenu: some View {
        Menu {
            Section {
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
            }

            Section("Zoom \(zoomLabel)") {
                Button {
                    viewportCommand = CanvasViewportCommand(.zoomIn)
                } label: {
                    Label("Zoom In", systemImage: "plus.magnifyingglass")
                }
                .disabled(!canZoomIn)

                Button {
                    viewportCommand = CanvasViewportCommand(.zoomOut)
                } label: {
                    Label("Zoom Out", systemImage: "minus.magnifyingglass")
                }
                .disabled(!canZoomOut)

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

            Section {
                Button {
                    togglePresentationMode()
                } label: {
                    Label(
                        broker.mode == .present ? "Mirror Mode" : "Present Mode",
                        systemImage: broker.mode == .present ? "rectangle.dashed" : "rectangle.inset.filled"
                    )
                }

                Button {
                    calculator.isVisible.toggle()
                } label: {
                    Label(
                        calculator.isVisible ? "Hide Calculator" : "Calculator",
                        systemImage: "function"
                    )
                }

                #if os(iOS)
                Button {
                    if isGraphCalculatorVisibleToUser {
                        broker.isGraphCalculatorVisible = false
                    } else {
                        broker.graphCalculator.restoreCompositeHomeBase()
                        broker.isGraphCalculatorVisible = true
                    }
                } label: {
                    Label(
                        isGraphCalculatorVisibleToUser ? "Hide graphCalc" : "Show graphCalc",
                        systemImage: "chart.xyaxis.line"
                    )
                }
                #endif
            }

            #if os(iOS)
            Section("Tool Palette") {
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
            }
            #endif

            if onImportPDF != nil || onExportPDF != nil {
                Section {
                    if let onImportPDF {
                        Button {
                            onImportPDF()
                        } label: {
                            Label("Import PDF", systemImage: "doc.badge.plus")
                        }
                    }
                    if let onExportPDF {
                        Button {
                            onExportPDF()
                        } label: {
                            Label("Export PDF", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if broker.isExternalDisplayConnected {
                    Image(systemName: "tv.fill")
                        .foregroundStyle(.green)
                }
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Tools")
    }

    private var selectedTextActionHUD: some View {
        GeometryReader { proxy in
            if selectionState.selectedGroupObjectCount > 1,
               let viewportFrame = selectionState.viewportFrame,
               pendingTextEdit == nil,
               pendingTextPlacement == nil,
               pendingLaTeXPlacement == nil,
               pendingLaTeXEdit == nil {
                FloatingActionHUD(
                    onPaste: { objectCommand = CanvasObjectCommand(.pasteClipboard) },
                    onClone: { toolCommand = CanvasToolCommand(.duplicateSelection) },
                    onGroupToggle: {
                        objectCommand = CanvasObjectCommand(selectionState.selectedObjectGroupID == nil ? .groupSelection : .ungroupSelection)
                    },
                    groupToggleTitle: selectionState.selectedObjectGroupID == nil ? "Group" : "Ungroup",
                    groupToggleSystemImage: selectionState.selectedObjectGroupID == nil ? "rectangle.3.group" : "rectangle.3.group.bubble.left",
                    onDelete: { toolCommand = CanvasToolCommand(.deleteSelection) }
                )
                .position(hudPosition(for: viewportFrame, in: proxy.size))
                .offset(actionHUDOffset)
                .gesture(actionHUDDragGesture)
            } else if let object = selectionState.selectedTextObject,
               let viewportFrame = selectionState.viewportFrame,
               pendingTextEdit == nil,
               pendingTextPlacement == nil,
               pendingLaTeXPlacement == nil,
               pendingLaTeXEdit == nil {
                FloatingActionHUD(
                    onEdit: { pendingTextEdit = PendingTextEdit(object: object) },
                    onCopy: { objectCommand = CanvasObjectCommand(.copy(.text(object.id))) },
                    onPaste: { objectCommand = CanvasObjectCommand(.pasteClipboard) },
                    onClone: { objectCommand = CanvasObjectCommand(.duplicate(.text(object.id))) },
                    onDelete: { objectCommand = CanvasObjectCommand(.delete(.text(object.id))) }
                )
                .position(hudPosition(for: viewportFrame, in: proxy.size))
                .offset(actionHUDOffset)
                .gesture(actionHUDDragGesture)
            } else if let object = selectionState.selectedGeometryObject,
                      let viewportFrame = selectionState.viewportFrame,
                      pendingTextEdit == nil,
                      pendingTextPlacement == nil,
                      pendingLaTeXPlacement == nil,
                      pendingLaTeXEdit == nil {
                FloatingActionHUD(
                    onCopy: { objectCommand = CanvasObjectCommand(.copy(.geometry(object.id))) },
                    onPaste: { objectCommand = CanvasObjectCommand(.pasteClipboard) },
                    onClone: { objectCommand = CanvasObjectCommand(.duplicate(.geometry(object.id))) },
                    onDelete: { objectCommand = CanvasObjectCommand(.delete(.geometry(object.id))) }
                )
                .position(hudPosition(for: viewportFrame, in: proxy.size))
                .offset(actionHUDOffset)
                .gesture(actionHUDDragGesture)
            } else if let object = selectionState.selectedImageObject,
                      let viewportFrame = selectionState.viewportFrame,
                      pendingTextEdit == nil,
                      pendingTextPlacement == nil,
                      pendingLaTeXPlacement == nil,
                      pendingLaTeXEdit == nil {
                let isLocked = object.isLocked == true
                FloatingActionHUD(
                    onEdit: selectionState.selectedLaTeXObject.map { latexObject in
                        { pendingLaTeXEdit = PendingLaTeXEdit(imageObject: object, latexObject: latexObject) }
                    },
                    onCopy: { objectCommand = CanvasObjectCommand(.copy(.image(object.id))) },
                    onPaste: { objectCommand = CanvasObjectCommand(.pasteClipboard) },
                    onClone: { objectCommand = CanvasObjectCommand(.duplicate(.image(object.id))) },
                    onBringForward: { objectCommand = CanvasObjectCommand(.reorderImage(object.id, .bringForward)) },
                    onSendBackward: { objectCommand = CanvasObjectCommand(.reorderImage(object.id, .sendBackward)) },
                    onBringToFront: { objectCommand = CanvasObjectCommand(.reorderImage(object.id, .bringToFront)) },
                    onSendToBack: { objectCommand = CanvasObjectCommand(.reorderImage(object.id, .sendToBack)) },
                    canBringForward: !isLocked && selectionState.selectedImageCanMoveForward,
                    canSendBackward: !isLocked && selectionState.selectedImageCanMoveBackward,
                    onLockToggle: { objectCommand = CanvasObjectCommand(.setImageLocked(object.id, !isLocked)) },
                    lockToggleTitle: isLocked ? "Unlock" : "Lock",
                    lockToggleSystemImage: isLocked ? "lock.open" : "lock",
                    canDelete: !isLocked,
                    onDelete: { objectCommand = CanvasObjectCommand(.delete(.image(object.id))) }
                )
                .position(hudPosition(for: viewportFrame, in: proxy.size))
                .offset(actionHUDOffset)
                .gesture(actionHUDDragGesture)
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var floatingLaTeXEditor: some View {
        if let placement = pendingLaTeXPlacement {
            LaTeXEditorView { result in
                insertLaTeX(result, placement: placement)
                pendingLaTeXPlacement = nil
                activateSelectTool()
            } onCancel: {
                pendingLaTeXPlacement = nil
                activateSelectTool()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(24)
        } else if let edit = pendingLaTeXEdit {
            LaTeXEditorView(initialSource: edit.latexObject.latexSource, submitTitle: "Update") { result in
                updateLaTeX(result, imageObject: edit.imageObject, latexObject: edit.latexObject)
                pendingLaTeXEdit = nil
                activateSelectTool()
            } onCancel: {
                pendingLaTeXEdit = nil
                activateSelectTool()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(24)
        }
    }

    private var actionHUDDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                actionHUDOffset = CGSize(
                    width: actionHUDStoredOffset.width + value.translation.width,
                    height: actionHUDStoredOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                actionHUDStoredOffset = actionHUDOffset
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

    private var isGraphCalculatorVisibleToUser: Bool {
        broker.isGraphCalculatorVisible && broker.graphCalculator.hasVisibleSection
    }

    private var isLaTeXEditorPresented: Bool {
        pendingLaTeXPlacement != nil || pendingLaTeXEdit != nil
    }

    private var canZoomIn: Bool {
        guard let viewportState = broker.viewportState else { return true }
        return viewportState.zoomScale < viewportState.maximumZoomScale - 0.01
    }

    private var canZoomOut: Bool {
        guard let viewportState = broker.viewportState else { return true }
        return viewportState.zoomScale > viewportState.minimumZoomScale + 0.01
    }

    private var currentCanvasZoomScale: CGFloat {
        max(broker.viewportState?.zoomScale ?? 1, 0.001)
    }

    // Canvas text is rendered through UIKit onto a zoomed canvas layer, while many
    // worksheet/PDF backgrounds arrive as page-sized raster content. This factor
    // maps the editor's document-style point sizes to the canvas backing size that
    // visually matches those worksheets.
    private var canvasTextPointScale: CGFloat {
        4
    }

    private func canvasFontSize(forEditorFontSize fontSize: CGFloat) -> CGFloat {
        fontSize * canvasTextPointScale / currentCanvasZoomScale
    }

    private func editorFontSize(forCanvasFontSize fontSize: CGFloat) -> CGFloat {
        fontSize * currentCanvasZoomScale / canvasTextPointScale
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
        if command == .addItem(.file) {
            broker.toolPaletteState = state
            presentImageFileImporter()
            return
        }

        if command == .addItem(.photo) {
            broker.toolPaletteState = state
            presentPhotoImporter()
            return
        }

        if command == .addItem(.camera) {
            broker.toolPaletteState = state
            presentCameraImporter()
            return
        }

        if command == .addItem(.text) {
            broker.toolPaletteState = state
            requestTextPlacementAtViewportCenter()
            activateSelectTool()
            return
        }

        if command == .addItem(.latex) {
            broker.toolPaletteState = state
            requestLaTeXPlacementAtViewportCenter()
            activateSelectTool()
            return
        }

        if command == .addItem(.widget) {
            guard allowsWidgetAuthoring else { return }
            broker.toolPaletteState = state
            presentWidgetEditor()
            return
        }

        if case .geometry? = selectionState.selectedObject,
           command == .selectTool(.geometry) {
            isClearingGeometrySelectionForCreation = true
            broker.toolPaletteState = state
            objectCommand = CanvasObjectCommand(.clearSelection)
            Task { @MainActor in
                await Task.yield()
                guard broker.toolPaletteState.activeTool == .geometry,
                      selectionState.selectedObject == nil else { return }
                applyToolPaletteState(broker.toolPaletteState, triggering: .setGeometryType(broker.toolPaletteState.geometryType))
            }
            return
        }

        // When a geometry object is selected, the geometry controls edit that
        // object instead of only the create config. The canvas stays in Select
        // mode so the object can still be moved / resized / rotated.
        if case .geometry(let id)? = selectionState.selectedObject,
           Self.isGeometryEditCommand(command) {
            broker.toolPaletteState = state
            objectCommand = CanvasObjectCommand(.updateGeometry(geometryUpdate(for: id, from: state)))
            return
        }
        applyToolPaletteState(state, triggering: command)
    }

    private func handleCanvasInteractionBegan() {
        collapseCompactDrawerForCanvasInteraction()
        onInteractionBegan?()
    }

    private func collapseCompactDrawerForCanvasInteraction() {
        guard paletteSettings.isCustomPaletteEnabled,
              paletteSettings.paletteStyle == .compact,
              broker.toolPaletteState.isCompactDrawerOpen else {
            return
        }

        var state = broker.toolPaletteState
        ToolPaletteReducer.reduce(&state, command: .collapseCompactDrawerForCanvasInteraction)
        broker.toolPaletteState = state
    }

    private func presentImageFileImporter() {
        Task { @MainActor in
            await Task.yield()
            isImageFileImporterPresented = true
        }
    }

    private func presentPhotoImporter() {
        #if os(iOS)
        Task { @MainActor in
            await Task.yield()
            isPhotoImporterPresented = true
        }
        #else
        imageFileImportError = ImageFileImportError(message: "Photos import is available on iPad.")
        #endif
    }

    private func presentCameraImporter() {
        #if os(iOS)
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            imageFileImportError = ImageFileImportError(message: "Camera is not available on this device.")
            return
        }

        Task { @MainActor in
            await Task.yield()
            isCameraImporterPresented = true
        }
        #else
        imageFileImportError = ImageFileImportError(message: "Camera import is available on iPad.")
        #endif
    }

    private func presentWidgetEditor() {
        Task { @MainActor in
            await Task.yield()
            isWidgetEditorPresented = true
        }
    }

    private static func isGeometryEditCommand(_ command: ToolPaletteCommand) -> Bool {
        switch command {
        case .setStrokeColor, .setPaletteColor, .setStrokeWidth, .setOpacity, .setFillColor,
             .setGeometryType, .setPolygonSides, .setGeometryLineArrowMode, .setGeometryFillOpacity:
            return true
        default:
            return false
        }
    }

    private func geometryUpdate(for id: UUID, from state: ToolPaletteState) -> CanvasGeometryUpdate {
        CanvasGeometryUpdate(
            id: id,
            shape: CanvasGeometryShape(geometryType: state.geometryType),
            strokeColor: CanvasStrokeColor(color: state.strokeColor, opacity: state.opacity),
            strokeWidth: CGFloat(state.strokeWidth),
            fillColor: CanvasStrokeColor(color: state.fillColor, opacity: 1),
            fillOpacity: CGFloat(state.geometryFillOpacity),
            polygonSides: state.polygonSides,
            arrow: CanvasGeometryArrow(mode: state.geometryLineArrowMode)
        )
    }

    /// Loads a selected geometry object's properties into the palette and opens
    /// the geometry controls drawer so the user can edit it in place.
    private func loadGeometryObjectIntoPalette(_ object: CanvasGeometryObject) {
        var state = broker.toolPaletteState
        state.activeTool = .geometry
        state.isCompactDrawerOpen = true
        state.geometryType = GeometryType(canvasShape: object.shape)
        state.strokeColor = PaletteColor(name: "custom", red: Double(object.strokeRed), green: Double(object.strokeGreen), blue: Double(object.strokeBlue))
        state.strokeWidth = Double(object.strokeWidth)
        state.fillColor = PaletteColor(name: "customFill", red: Double(object.fillRed), green: Double(object.fillGreen), blue: Double(object.fillBlue))
        state.geometryFillOpacity = Double(object.fillOpacity)
        state.polygonSides = object.polygonSides
        state.geometryLineArrowMode = GeometryLineArrowMode(canvasArrow: object.arrow)
        broker.toolPaletteState = state
    }

    /// Loads a selected text object's style into the text controls before the
    /// canvas applies the text-tool command. This prevents the palette's default
    /// text size from overwriting an existing object's font size on edit begin.
    private func loadTextObjectIntoPalette(_ object: CanvasTextObject) {
        var state = broker.toolPaletteState
        state.activeTool = .equation
        state.isCompactDrawerOpen = true
        state.strokeColor = PaletteColor(
            name: "customText",
            red: Double(object.red),
            green: Double(object.green),
            blue: Double(object.blue)
        )
        state.opacity = Double(object.alpha)
        state.textStyle = object.isBold ? .bold : .normal
        state.textIsItalic = object.isItalic
        state.textIsUnderlined = object.isUnderlined
        state.textSize = Double(object.fontSize)
        state.textFontName = object.fontName ?? "System"
        broker.toolPaletteState = state
    }

    private func handleSelectionChange(from oldValue: CanvasSelectionState.Object?, to newValue: CanvasSelectionState.Object?) {
        if selectionState.selectedGroupObjectCount > 1 {
            var state = broker.toolPaletteState
            var shouldApplySelectionTool = false
            if state.activeTool != .selection {
                state.activeTool = .selection
                state.isCompactDrawerOpen = false
                shouldApplySelectionTool = true
            }
            if state.selectionMode != .tap {
                state.selectionMode = .tap
                shouldApplySelectionTool = true
            }
            if shouldApplySelectionTool {
                broker.toolPaletteState = state
                applyToolPaletteState(state, triggering: .selectTool(.selection))
            }
            return
        }
        if case .geometry = newValue, let object = selectionState.selectedGeometryObject {
            if broker.toolPaletteState.activeTool == .selection,
               broker.toolPaletteState.selectionMode == .tap {
                return
            }
            loadGeometryObjectIntoPalette(object)
        } else if case .geometry = oldValue {
            if isClearingGeometrySelectionForCreation {
                isClearingGeometrySelectionForCreation = false
                return
            }

            // Return the palette to the selection controls after deselecting.
            var state = broker.toolPaletteState
            if state.activeTool == .geometry {
                state.activeTool = .selection
                broker.toolPaletteState = state
            }
        }
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
        if let object = selectionState.selectedTextObject {
            state.strokeColor = PaletteColor(
                name: "customText",
                red: Double(object.red),
                green: Double(object.green),
                blue: Double(object.blue)
            )
            state.opacity = Double(object.alpha)
            state.textStyle = object.isBold ? .bold : .normal
            state.textIsItalic = object.isItalic
            state.textIsUnderlined = object.isUnderlined
            state.textSize = Double(object.fontSize)
            state.textFontName = object.fontName ?? "System"
        }
        ToolPaletteReducer.reduce(&state, command: .selectTool(.equation))
        broker.toolPaletteState = state
        applyToolPaletteState(state, triggering: .selectTool(.equation))
    }

    private func handleTextEditingBegan() {
        onTextEditingBegan?()
        activateTextToolForExistingEditor()
    }

    private func handleTextEditingEnded() {
        onTextEditingEnded?()
        activateSelectTool()
    }

    private func requestTextPlacement(at sourcePoint: CGPoint) {
        pendingTextPlacement = PendingTextPlacement(sourcePoint: sourcePoint)
    }

    private func requestTextPlacementAtViewportCenter() {
        let referenceSize = broker.toolPaletteReferenceSize
            ?? broker.calculatorReferenceSize
            ?? CGSize(width: 1194, height: 744)
        pendingTextPlacement = PendingTextPlacement(
            sourcePoint: broker.currentViewportSourceRect.map {
                CGPoint(x: $0.midX, y: $0.midY)
            } ?? CGPoint(x: 320, y: 240),
            canvasPoint: CGPoint(x: referenceSize.width / 2, y: referenceSize.height / 2)
        )
    }

    private func requestLaTeXPlacementAtViewportCenter() {
        let referenceSize = broker.toolPaletteReferenceSize
            ?? broker.calculatorReferenceSize
            ?? CGSize(width: 1194, height: 744)
        pendingLaTeXPlacement = PendingLaTeXPlacement(
            canvasPoint: CGPoint(x: referenceSize.width / 2, y: referenceSize.height / 2)
        )
    }

    private func handleLibraryItemDrop(_ providers: [NSItemProvider], at canvasPoint: CGPoint) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(LibraryCanvasDragPayload.typeIdentifier)
        }) else {
            return false
        }

        provider.loadDataRepresentation(forTypeIdentifier: LibraryCanvasDragPayload.typeIdentifier) { data, _ in
            guard let data,
                  let payload = try? JSONDecoder().decode(LibraryCanvasDragPayload.self, from: data) else {
                return
            }

            Task { @MainActor in
                placeLibraryItem(payload, at: canvasPoint)
            }
        }
        return true
    }

    @MainActor
    private func placeLibraryItem(_ payload: LibraryCanvasDragPayload, at canvasPoint: CGPoint) {
        if payload.kind == .widget,
           let widgetCodeString = payload.widgetCodeString {
            objectCommand = CanvasObjectCommand(.insertWidget(CanvasWidgetInsertion(
                name: payload.title,
                codeString: widgetCodeString,
                displaySize: payload.displaySize,
                canvasPoint: canvasPoint,
                librarySourceCodeString: widgetCodeString
            )))
            activateSelectTool()
            return
        }

        if payload.kind == .text,
           let textPayload = payload.textPayload {
            objectCommand = CanvasObjectCommand(.insertText(CanvasTextInsertion(
                text: textPayload.text,
                sourcePoint: .zero,
                canvasPoint: canvasPoint,
                fontSize: textPayload.fontSize,
                color: CanvasStrokeColor(
                    red: textPayload.red,
                    green: textPayload.green,
                    blue: textPayload.blue,
                    alpha: textPayload.alpha
                ),
                isBold: textPayload.isBold,
                isItalic: textPayload.isItalic,
                isUnderlined: textPayload.isUnderlined,
                fontName: textPayload.fontName,
                displaySize: CGSize(width: textPayload.width, height: textPayload.height),
                librarySourceText: textPayload.text
            )))
            activateSelectTool()
            return
        }

        if payload.kind == .latex,
           let latexPayload = payload.latexPayload,
           let pngData = payload.pngData {
            objectCommand = CanvasObjectCommand(.insertLaTeX(CanvasLaTeXInsertion(
                latexSource: latexPayload.latexSource,
                pngData: pngData,
                displaySize: payload.displaySize,
                canvasPoint: canvasPoint,
                librarySourceLaTeX: latexPayload.latexSource
            )))
            activateSelectTool()
            return
        }

        guard let pngData = payload.pngData else { return }

        objectCommand = CanvasObjectCommand(
            .insertImageAtCanvasPoint(
                CanvasDroppedImageInsertion(
                    pngData: pngData,
                    displaySize: payload.displaySize,
                    canvasPoint: canvasPoint,
                    selectAfterInsert: true
                )
            )
        )
        activateSelectTool()
    }

    @MainActor
    private func placeLibraryItemAtViewportCenter(_ payload: LibraryCanvasDragPayload) {
        let referenceSize = broker.toolPaletteReferenceSize
            ?? broker.calculatorReferenceSize
            ?? CGSize(width: 1194, height: 744)
        placeLibraryItem(
            payload,
            at: CGPoint(x: referenceSize.width / 2, y: referenceSize.height / 2)
        )
    }

    @discardableResult
    private func recordLibraryRecent(
        title: String,
        kind: LibraryRecentKind,
        thumbnailPNGData: Data? = nil,
        widgetCodeString: String? = nil,
        textPayload: LibraryTextPayload? = nil,
        latexPayload: LibraryLaTeXPayload? = nil
    ) -> Bool {
        do {
            try LibraryRecentStore.record(
                title: title,
                kind: kind,
                thumbnailPNGData: thumbnailPNGData,
                widgetCodeString: widgetCodeString,
                textPayload: textPayload,
                latexPayload: latexPayload,
                forDrawingURL: drawingURL
            )
            libraryRecentRefreshID = UUID()
            return true
        } catch {
            // Recent is supportive metadata; insertion should not fail if it cannot be recorded.
            return false
        }
    }

    private func recordExtractedRegionPlacement(_ region: PresentationExtractedRegion) {
        recordLibraryRecent(
            title: Self.libraryRecentTitle("Extracted sticker"),
            kind: .extractedInk,
            thumbnailPNGData: region.pngData
        )
    }

    private func handleExtractedRegionSend(_ region: PresentationExtractedRegion) {
        onExtractedRegionSend?(region)
        libraryRecentRefreshID = UUID()
    }

    private func insertText(_ result: TextEditorResult, placement: PendingTextPlacement) {
        let state = broker.toolPaletteState
        let canvasFontSize = canvasFontSize(forEditorFontSize: result.fontSize)
        objectCommand = CanvasObjectCommand(.insertText(CanvasTextInsertion(
            text: result.sourceText,
            sourcePoint: placement.sourcePoint,
            canvasPoint: placement.canvasPoint,
            fontSize: canvasFontSize,
            color: CanvasStrokeColor(color: state.strokeColor, opacity: state.opacity),
            isBold: result.isBold,
            isItalic: result.isItalic,
            isUnderlined: result.isUnderline,
            fontName: result.fontName
        )))
        let trimmedText = result.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        recordLibraryRecent(
            title: trimmedText.isEmpty ? "Text object" : String(trimmedText.prefix(36)),
            kind: .text,
            textPayload: LibraryTextPayload(
                result,
                color: CanvasStrokeColor(color: state.strokeColor, opacity: state.opacity),
                fontSize: canvasFontSize
            )
        )
    }

    private func updateText(_ result: TextEditorResult, object: CanvasTextObject) {
        let canvasFontSize = canvasFontSize(forEditorFontSize: result.fontSize)
        let shouldRecordLibraryDerivative = object.shouldRecordLibraryDerivative(
            forUpdatedText: result.sourceText
        )
        let didRecordLibraryDerivative = shouldRecordLibraryDerivative && recordLibraryRecent(
            title: Self.libraryRecentTitle(forText: result.sourceText),
            kind: .text,
            textPayload: LibraryTextPayload(
                result,
                color: CanvasStrokeColor(
                    red: object.red,
                    green: object.green,
                    blue: object.blue,
                    alpha: object.alpha
                ),
                fontSize: canvasFontSize,
                fallbackSize: object.frame.size
            )
        )

        objectCommand = CanvasObjectCommand(.updateText(CanvasTextUpdate(
            id: object.id,
            text: result.sourceText,
            fontSize: canvasFontSize,
            isBold: result.isBold,
            isItalic: result.isItalic,
            isUnderlined: result.isUnderline,
            fontName: result.fontName,
            hasRecordedLibraryDerivative: didRecordLibraryDerivative ? true : nil
        )))
    }

    private func insertLaTeX(_ result: LaTeXEditorResult, placement: PendingLaTeXPlacement) {
        objectCommand = CanvasObjectCommand(.insertLaTeX(CanvasLaTeXInsertion(
            latexSource: result.latexSource,
            pngData: result.pngData,
            displaySize: result.displaySize,
            canvasPoint: placement.canvasPoint
        )))
        recordLibraryRecent(
            title: Self.libraryRecentTitle(forLaTeX: result.latexSource),
            kind: .latex,
            thumbnailPNGData: result.pngData,
            latexPayload: LibraryLaTeXPayload(
                latexSource: result.latexSource,
                width: result.displaySize.width,
                height: result.displaySize.height
            )
        )
    }

    private func updateLaTeX(_ result: LaTeXEditorResult, imageObject: CanvasImageObject, latexObject: CanvasLaTeXObject) {
        let shouldRecordLibraryDerivative = latexObject.shouldRecordLibraryDerivative(
            forUpdatedSource: result.latexSource
        )
        let shouldRecordCanvasDerivative = latexObject.shouldRecordCanvasDerivative(
            forUpdatedSource: result.latexSource
        )
        let shouldRecordRecent = shouldRecordLibraryDerivative || shouldRecordCanvasDerivative
        let didRecordRecent = shouldRecordRecent && recordLibraryRecent(
            title: Self.libraryRecentTitle(forLaTeX: result.latexSource),
            kind: .latex,
            thumbnailPNGData: result.pngData,
            latexPayload: LibraryLaTeXPayload(
                latexSource: result.latexSource,
                width: imageObject.width,
                height: imageObject.height
            )
        )

        objectCommand = CanvasObjectCommand(.updateLaTeX(CanvasLaTeXUpdate(
            imageObjectID: imageObject.id,
            latexSource: result.latexSource,
            pngData: result.pngData,
            displaySize: result.displaySize,
            hasRecordedLibraryDerivative: shouldRecordLibraryDerivative && didRecordRecent ? true : nil
        )))
    }

    @MainActor
    private func recordLibraryTextDerivative(_ object: CanvasTextObject) -> Bool {
        recordLibraryRecent(
            title: Self.libraryRecentTitle(forText: object.text),
            kind: .text,
            textPayload: LibraryTextPayload(object)
        )
    }

    private func insertWidget(_ insertion: WidgetEditorInsertion) {
        objectCommand = CanvasObjectCommand(.insertWidget(CanvasWidgetInsertion(
            name: insertion.name,
            codeString: insertion.codeString
        )))
        recordLibraryRecent(
            title: insertion.name,
            kind: .widget,
            widgetCodeString: insertion.codeString
        )
    }

    private func updateWidget(_ insertion: WidgetEditorInsertion, id: UUID) {
        let shouldRecordLibraryDerivative = pendingWidgetEdit?.widget.shouldRecordLibraryDerivative(
            forUpdatedCodeString: insertion.codeString
        ) ?? false
        let didRecordLibraryDerivative = shouldRecordLibraryDerivative && recordLibraryRecent(
            title: insertion.name,
            kind: .widget,
            widgetCodeString: insertion.codeString
        )

        objectCommand = CanvasObjectCommand(.updateWidget(CanvasWidgetUpdate(
            id: id,
            name: insertion.name,
            codeString: insertion.codeString,
            hasRecordedLibraryDerivative: didRecordLibraryDerivative ? true : nil
        )))
    }

    private func requestWidgetEdit(_ widget: WidgetObject) {
        guard allowsWidgetAuthoring else { return }
        pendingWidgetEdit = PendingWidgetEdit(widget: widget)
    }

    private func activateSelectTool() {
        var state = broker.toolPaletteState
        ToolPaletteReducer.reduce(&state, command: .selectTool(.selection))
        broker.toolPaletteState = state
        applyToolPaletteState(state, triggering: .selectTool(.selection))
    }

    private func activateSelectToolAfterExtractAction() {
        var state = broker.toolPaletteState
        guard state.activeTool == .extract else { return }
        ToolPaletteReducer.reduce(&state, command: .selectTool(.selection))
        state.isCompactDrawerOpen = false
        broker.toolPaletteState = state
        applyToolPaletteState(state, triggering: .selectTool(.selection))
    }

    private func hudPosition(for frame: CGRect, in size: CGSize) -> CGPoint {
        let hudWidth: CGFloat = 220
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
    private func insertGraphSnapshot(_ snapshot: GraphCalculatorSnapshot) {
        let aspect = snapshot.size.width / max(snapshot.size.height, 1)
        let baseDisplayWidth: CGFloat = 160
        let displayWidth = baseDisplayWidth * 3
        objectCommand = CanvasObjectCommand(
            .insertImageNearViewport(
                CanvasViewportImageInsertion(
                    pngData: snapshot.pngData,
                    displaySize: CGSize(width: displayWidth, height: displayWidth / aspect),
                    referenceRect: snapshot.placementRect,
                    containerSize: snapshot.containerSize,
                    margin: 20,
                    selectAfterInsert: true
                )
            )
        )
        recordLibraryRecent(
            title: Self.libraryRecentTitle("Graph snapshot"),
            kind: .graphSnapshot,
            thumbnailPNGData: snapshot.pngData
        )
    }

    @MainActor
    private func handleImageFileImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            if try Self.isPDFFile(url) {
                pendingPDFObjectImport = try makePendingPDFObjectImport(from: url)
                return
            }

            let importedImage = try Self.importedCanvasImage(from: url)
            insertImportedCanvasImage(importedImage)
            activateSelectTool()
        } catch {
            imageFileImportError = ImageFileImportError(message: error.localizedDescription)
        }
    }

    @MainActor
    private func handlePhotoImport(_ result: Result<Data, Error>) {
        do {
            let importedImage = try Self.importedCanvasImage(fromImageData: try result.get())
            insertImportedCanvasImage(importedImage)
            activateSelectTool()
        } catch {
            imageFileImportError = ImageFileImportError(message: error.localizedDescription)
        }
    }

    @MainActor
    private func handleCameraImport(_ result: Result<Data, Error>) {
        do {
            let importedImage = try Self.importedCanvasImage(fromImageData: try result.get())
            insertImportedCanvasImage(importedImage)
            activateSelectTool()
        } catch {
            imageFileImportError = ImageFileImportError(message: error.localizedDescription)
        }
    }

    @MainActor
    private func insertImportedCanvasImage(_ importedImage: ImportedCanvasImage) {
        objectCommand = CanvasObjectCommand(
            .insertImageNearViewport(
                CanvasViewportImageInsertion(
                    pngData: importedImage.pngData,
                    displaySize: importedImage.displaySize,
                    margin: 24,
                    selectAfterInsert: true
                )
            )
        )
        recordLibraryRecent(
            title: Self.libraryRecentTitle("Imported image"),
            kind: .image,
            thumbnailPNGData: importedImage.pngData
        )
    }

    @MainActor
    private func importSelectedPDFPagesAsObjects(_ pageIndices: [Int], from pendingImport: PendingPDFObjectImport) {
        if let onImportPDFObjects {
            onImportPDFObjects(pendingImport.url, pageIndices)
            pendingPDFObjectImport = nil
            activateSelectTool()
            return
        }

        do {
            let importedPages = try Self.importedCanvasImages(fromPDFAt: pendingImport.url, pageIndices: pageIndices)
            guard !importedPages.isEmpty else {
                throw ImageFileImportError(message: "Select at least one PDF page to import.")
            }

            objectCommand = CanvasObjectCommand(
                .insertImagesNearViewport(
                    importedPages.map { page in
                        CanvasViewportImageInsertion(
                            pngData: page.pngData,
                            displaySize: page.displaySize,
                            margin: 24,
                            selectAfterInsert: true
                        )
                    }
                )
            )
            for (index, page) in importedPages.enumerated() {
                recordLibraryRecent(
                    title: Self.libraryRecentTitle("PDF page \(index + 1)"),
                    kind: .image,
                    thumbnailPNGData: page.pngData
                )
            }
            clearPendingPDFObjectImport()
            activateSelectTool()
        } catch {
            imageFileImportError = ImageFileImportError(message: error.localizedDescription)
        }
    }

    private func clearPendingPDFObjectImport() {
        if let pendingPDFObjectImport {
            try? FileManager.default.removeItem(at: pendingPDFObjectImport.url)
        }
        pendingPDFObjectImport = nil
    }

    private static func libraryRecentTitle(_ baseTitle: String, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return "\(baseTitle) \(formatter.string(from: date))"
    }

    private static func libraryRecentTitle(forText text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty ? "Text object" : String(trimmedText.prefix(36))
    }

    private static func libraryRecentTitle(forLaTeX latexSource: String) -> String {
        let trimmedSource = latexSource.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedSource.isEmpty ? "LaTeX equation" : "f(x) \(String(trimmedSource.prefix(32)))"
    }

    private static func isPDFFile(_ url: URL) throws -> Bool {
        if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return contentType.conforms(to: .pdf)
        }
        return UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true
    }

    private func makePendingPDFObjectImport(from sourceURL: URL) throws -> PendingPDFObjectImport {
        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MathBoard-PDF-Object-\(UUID().uuidString).pdf")
        try FileManager.default.copyItem(at: sourceURL, to: temporaryURL)
        return PendingPDFObjectImport(url: temporaryURL)
    }

    private static func importedCanvasImage(from url: URL) throws -> ImportedCanvasImage {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        return try importedCanvasImage(fromImageData: data)
    }

    private static func importedCanvasImage(fromImageData data: Data) throws -> ImportedCanvasImage {
        #if os(iOS)
        guard let image = UIImage(data: data),
              let pngData = image.pngData() else {
            throw ImageFileImportError(message: "MathBoard could not read this image file.")
        }
        return ImportedCanvasImage(pngData: pngData, imageSize: image.size)
        #elseif os(macOS)
        guard let image = NSImage(data: data),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ImageFileImportError(message: "MathBoard could not read this image file.")
        }
        return ImportedCanvasImage(pngData: pngData, imageSize: image.size)
        #endif
    }

    private static func importedCanvasImages(fromPDFAt url: URL, pageIndices: [Int]) throws -> [ImportedCanvasImage] {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            throw ImageFileImportError(message: "MathBoard could not read this PDF.")
        }

        let validPageIndices = pageIndices.filter { $0 >= 0 && $0 < document.pageCount }
        guard !validPageIndices.isEmpty else {
            throw ImageFileImportError(message: "Select at least one PDF page to import.")
        }

        return try validPageIndices.map { pageIndex in
            guard let page = document.page(at: pageIndex) else {
                throw ImageFileImportError(message: "MathBoard could not read page \(pageIndex + 1).")
            }
            return try importedCanvasImage(fromPDFPage: page)
        }
    }

    private static func importedCanvasImage(fromPDFPage page: PDFPage) throws -> ImportedCanvasImage {
        let pageBounds = page.bounds(for: .mediaBox)
        let width = max(pageBounds.width, 1)
        let height = max(pageBounds.height, 1)
        let maxDisplaySide: CGFloat = 560
        let displayScale = min(1, maxDisplaySide / max(width, height))
        let displaySize = CGSize(width: width * displayScale, height: height * displayScale)
        let renderScale: CGFloat = 2
        let renderSize = CGSize(width: width * renderScale, height: height * renderScale)

        #if os(iOS)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: renderSize, format: format).image { rendererContext in
            UIColor.white.setFill()
            rendererContext.fill(CGRect(origin: .zero, size: renderSize))
            let context = rendererContext.cgContext
            context.saveGState()
            context.scaleBy(x: renderScale, y: renderScale)
            context.translateBy(x: -pageBounds.minX, y: pageBounds.height + pageBounds.minY)
            context.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: context)
            context.restoreGState()
        }
        guard let pngData = image.pngData() else {
            throw ImageFileImportError(message: "MathBoard could not render this PDF page.")
        }
        return ImportedCanvasImage(pngData: pngData, displaySize: displaySize)
        #elseif os(macOS)
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(renderSize.width.rounded(.up)),
            pixelsHigh: Int(renderSize.height.rounded(.up)),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw ImageFileImportError(message: "MathBoard could not render this PDF page.")
        }
        representation.size = renderSize
        NSGraphicsContext.saveGraphicsState()
        guard let graphicsContext = NSGraphicsContext(bitmapImageRep: representation) else {
            NSGraphicsContext.restoreGraphicsState()
            throw ImageFileImportError(message: "MathBoard could not render this PDF page.")
        }
        NSGraphicsContext.current = graphicsContext
        NSColor.white.setFill()
        NSRect(origin: .zero, size: renderSize).fill()
        let context = graphicsContext.cgContext
        context.saveGState()
        context.scaleBy(x: renderScale, y: renderScale)
        context.translateBy(x: -pageBounds.minX, y: pageBounds.height + pageBounds.minY)
        context.scaleBy(x: 1, y: -1)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()
        NSGraphicsContext.restoreGraphicsState()
        guard let pngData = representation.representation(using: .png, properties: [:]) else {
            throw ImageFileImportError(message: "MathBoard could not render this PDF page.")
        }
        return ImportedCanvasImage(pngData: pngData, displaySize: displaySize)
        #endif
    }

    @MainActor
    private static func publishLiveStroke(_ stroke: CanvasLiveStroke?) {
        DisplayBroker.shared.publishLiveStroke(stroke)
    }

    @MainActor
    private static func publishWidgets(
        _ widgets: [WidgetObject],
        viewport: WidgetCanvasViewport,
        referenceSize: CGSize,
        canvasIdentity: String
    ) {
        DisplayBroker.shared.publishWidgets(
            widgets,
            viewport: viewport,
            referenceSize: referenceSize,
            canvasIdentity: canvasIdentity
        )
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
    var canvasPoint: CGPoint?
}

private struct PendingLaTeXPlacement: Identifiable {
    let id = UUID()
    var canvasPoint: CGPoint
}

private struct PendingLaTeXEdit: Identifiable {
    var imageObject: CanvasImageObject
    var latexObject: CanvasLaTeXObject

    var id: UUID {
        imageObject.id
    }
}

private struct PendingWidgetEdit: Identifiable {
    var widget: WidgetObject

    var id: UUID {
        widget.id
    }
}

private extension WidgetObject {
    func shouldRecordLibraryDerivative(forUpdatedCodeString updatedCodeString: String) -> Bool {
        guard let librarySourceCodeString,
              !hasRecordedLibraryDerivative else {
            return false
        }

        return Self.normalizedLibraryCode(librarySourceCodeString) != Self.normalizedLibraryCode(updatedCodeString)
    }

    static func normalizedLibraryCode(_ codeString: String) -> String {
        codeString.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension CanvasLaTeXObject {
    func shouldRecordLibraryDerivative(forUpdatedSource updatedSource: String) -> Bool {
        guard let librarySourceLaTeX,
              !hasRecordedLibraryDerivative else {
            return false
        }

        return Self.normalizedLibrarySource(librarySourceLaTeX) != Self.normalizedLibrarySource(updatedSource)
    }

    func shouldRecordCanvasDerivative(forUpdatedSource updatedSource: String) -> Bool {
        guard librarySourceLaTeX == nil else { return false }
        return Self.normalizedLibrarySource(latexSource) != Self.normalizedLibrarySource(updatedSource)
    }

    static func normalizedLibrarySource(_ source: String) -> String {
        source.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension CanvasTextObject {
    func shouldRecordLibraryDerivative(forUpdatedText updatedText: String) -> Bool {
        guard let librarySourceText,
              !hasRecordedLibraryDerivative else {
            return false
        }

        return Self.normalizedLibraryText(librarySourceText) != Self.normalizedLibraryText(updatedText)
    }

    static func normalizedLibraryText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension LibraryTextPayload {
    init(
        _ result: TextEditorResult,
        color: CanvasStrokeColor,
        fontSize: CGFloat? = nil,
        fallbackSize: CGSize = CGSize(width: 220, height: 80)
    ) {
        self.init(
            text: result.sourceText,
            fontSize: fontSize ?? result.fontSize,
            red: color.red,
            green: color.green,
            blue: color.blue,
            alpha: color.alpha,
            isBold: result.isBold,
            isItalic: result.isItalic,
            isUnderlined: result.isUnderline,
            fontName: result.fontName,
            width: fallbackSize.width,
            height: fallbackSize.height
        )
    }

    init(_ object: CanvasTextObject) {
        self.init(
            text: object.text,
            fontSize: object.fontSize,
            red: object.red,
            green: object.green,
            blue: object.blue,
            alpha: object.alpha,
            isBold: object.isBold,
            isItalic: object.isItalic,
            isUnderlined: object.isUnderlined,
            fontName: object.fontName,
            width: object.width,
            height: object.height
        )
    }
}

private struct PendingPDFObjectImport: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ImportedCanvasImage {
    let pngData: Data
    let displaySize: CGSize

    init(pngData: Data, imageSize: CGSize) {
        self.pngData = pngData

        let maxDisplaySide: CGFloat = 480
        let width = max(imageSize.width, 1)
        let height = max(imageSize.height, 1)
        let scale = min(1, maxDisplaySide / max(width, height))
        self.displaySize = CGSize(width: width * scale, height: height * scale)
    }

    init(pngData: Data, displaySize: CGSize) {
        self.pngData = pngData
        self.displaySize = displaySize
    }
}

private struct ImageFileImportError: LocalizedError, Identifiable {
    let id = UUID()
    let message: String

    var errorDescription: String? {
        message
    }
}

private struct PDFObjectImportPreviewView: View {
    let pdfURL: URL
    let onCancel: () -> Void
    let onImport: ([Int]) -> Void

    @State private var selectedPages: Set<Int>

    private let document: PDFDocument?
    private let pageCount: Int
    private let columns = [
        GridItem(.adaptive(minimum: 132, maximum: 180), spacing: 16)
    ]

    init(
        pdfURL: URL,
        onCancel: @escaping () -> Void,
        onImport: @escaping ([Int]) -> Void
    ) {
        self.pdfURL = pdfURL
        self.onCancel = onCancel
        self.onImport = onImport

        let document = PDFDocument(url: pdfURL)
        self.document = document
        self.pageCount = document?.pageCount ?? 0
        _selectedPages = State(initialValue: Set(0..<(document?.pageCount ?? 0)))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(0..<pageCount, id: \.self) { pageIndex in
                        PDFObjectPageSelectionTile(
                            document: document,
                            pageIndex: pageIndex,
                            isSelected: selectedPages.contains(pageIndex)
                        ) {
                            togglePage(pageIndex)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Import PDF Pages")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }

                ToolbarItemGroup(placement: .secondaryAction) {
                    Button("Select All") {
                        selectedPages = Set(0..<pageCount)
                    }
                    .disabled(selectedPages.count == pageCount)

                    Button("Select None") {
                        selectedPages.removeAll()
                    }
                    .disabled(selectedPages.isEmpty)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        onImport(selectedPages.sorted())
                    }
                    .disabled(selectedPages.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Text("\(selectedPages.count) of \(pageCount) pages selected")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Canvas objects")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.regularMaterial)
            }
        }
    }

    private func togglePage(_ pageIndex: Int) {
        if selectedPages.contains(pageIndex) {
            selectedPages.remove(pageIndex)
        } else {
            selectedPages.insert(pageIndex)
        }
    }
}

private struct PDFObjectPageSelectionTile: View {
    let document: PDFDocument?
    let pageIndex: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    PDFObjectThumbnailView(document: document, pageIndex: pageIndex)
                        .aspectRatio(0.72, contentMode: .fit)
                        .background(Color.white)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(
                                    isSelected ? Color.accentColor : Color.secondary.opacity(0.28),
                                    lineWidth: isSelected ? 3 : 1
                                )
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .shadow(color: .black.opacity(0.12), radius: 5, y: 2)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .background(.white, in: Circle())
                        .padding(6)
                }

                Text("Page \(pageIndex + 1)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Page \(pageIndex + 1)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct PDFObjectThumbnailView: View {
    let document: PDFDocument?
    let pageIndex: Int

    var body: some View {
        Group {
            if let image = thumbnailImage {
                #if os(iOS)
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                #else
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                #endif
            } else {
                Image(systemName: "doc")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var thumbnailImage: PlatformPDFThumbnailImage? {
        guard let page = document?.page(at: pageIndex) else { return nil }
        return page.thumbnail(of: CGSize(width: 220, height: 300), for: .mediaBox)
    }
}

#if os(iOS)
private typealias PlatformPDFThumbnailImage = UIImage
#elseif os(macOS)
private typealias PlatformPDFThumbnailImage = NSImage
#endif

#if os(iOS)
private struct ImageDocumentPicker: UIViewControllerRepresentable {
    var onPick: (Result<[URL], Error>) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image, .pdf], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: (Result<[URL], Error>) -> Void
        private let onCancel: () -> Void

        init(
            onPick: @escaping (Result<[URL], Error>) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(.success(urls))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}

private struct ImagePhotoPicker: UIViewControllerRepresentable {
    var onPick: (Result<Data, Error>) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onPick: (Result<Data, Error>) -> Void
        private let onCancel: () -> Void

        init(
            onPick: @escaping (Result<Data, Error>) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let itemProvider = results.first?.itemProvider else {
                onCancel()
                return
            }

            guard itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
                onPick(.failure(ImageFileImportError(message: "MathBoard could not read this photo.")))
                return
            }

            itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                DispatchQueue.main.async {
                    if let error {
                        self.onPick(.failure(error))
                        return
                    }

                    guard let data else {
                        self.onPick(.failure(ImageFileImportError(message: "MathBoard could not read this photo.")))
                        return
                    }

                    self.onPick(.success(data))
                }
            }
        }
    }
}

private struct ImageCameraPicker: UIViewControllerRepresentable {
    var onCapture: (Result<Data, Error>) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (Result<Data, Error>) -> Void
        private let onCancel: () -> Void

        init(
            onCapture: @escaping (Result<Data, Error>) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage,
                  let pngData = image.pngData() else {
                onCapture(.failure(ImageFileImportError(message: "MathBoard could not read the captured photo.")))
                return
            }

            onCapture(.success(pngData))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}
#endif

private struct PendingTextEdit: Identifiable {
    var object: CanvasTextObject

    var id: UUID {
        object.id
    }
}

private struct FloatingActionHUD: View {
    var onEdit: (() -> Void)?
    var onCopy: (() -> Void)?
    let onPaste: () -> Void
    let onClone: () -> Void
    var onBringForward: (() -> Void)?
    var onSendBackward: (() -> Void)?
    var onBringToFront: (() -> Void)?
    var onSendToBack: (() -> Void)?
    var canBringForward = true
    var canSendBackward = true
    var onLockToggle: (() -> Void)?
    var lockToggleTitle = "Lock"
    var lockToggleSystemImage = "lock"
    var onGroupToggle: (() -> Void)?
    var groupToggleTitle = "Group"
    var groupToggleSystemImage = "rectangle.3.group"
    var canDelete = true
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let onEdit {
                hudButton("Edit", systemImage: "pencil", action: onEdit)
            }
            if let onCopy {
                hudButton("Copy", systemImage: "doc.on.doc", action: onCopy)
            }
            hudButton("Paste", systemImage: "doc.on.clipboard", action: onPaste)
            hudButton("Clone", systemImage: "plus.square.on.square", action: onClone)
            if let onSendToBack {
                hudButton("Send to Back", systemImage: "square.3.layers.3d.down.backward", isEnabled: canSendBackward, action: onSendToBack)
            }
            if let onSendBackward {
                hudButton("Send Backward", systemImage: "square.2.layers.3d.bottom.filled", isEnabled: canSendBackward, action: onSendBackward)
            }
            if let onBringForward {
                hudButton("Bring Forward", systemImage: "square.2.layers.3d.top.filled", isEnabled: canBringForward, action: onBringForward)
            }
            if let onBringToFront {
                hudButton("Bring to Front", systemImage: "square.3.layers.3d.up.forward", isEnabled: canBringForward, action: onBringToFront)
            }
            if let onLockToggle {
                hudButton(lockToggleTitle, systemImage: lockToggleSystemImage, action: onLockToggle)
            }
            if let onGroupToggle {
                hudButton(groupToggleTitle, systemImage: groupToggleSystemImage, action: onGroupToggle)
            }
            hudButton("Delete", systemImage: "trash", role: .destructive, isEnabled: canDelete, action: onDelete)
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
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 34, height: 34)
        }
        .disabled(!isEnabled)
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
        case .pasteSelection:
            self.init(.pasteSelection)
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
        case .setExtractAction(let action):
            self.init(.setExtractAction(CanvasToolCommand.ExtractAction(extractAction: action)))
            return
        default:
            break
        }

        switch state.activeTool {
        case .selection:
            self.init(.select(
                target: .object,
                mode: CanvasToolCommand.SelectionMode(selectionSelectionMode: state.selectionMode),
                behavior: CanvasToolCommand.SelectionBehavior(selectionBehavior: state.selectionBehavior),
                extractAction: nil
            ))
        case .extract:
            self.init(.select(
                target: .region,
                mode: CanvasToolCommand.SelectionMode(regionSelectionMode: state.selectionMode),
                behavior: .single,
                extractAction: CanvasToolCommand.ExtractAction(extractAction: state.extractAction)
            ))
        case .geometry:
            self.init(.geometry(
                shape: CanvasGeometryShape(geometryType: state.geometryType),
                strokeColor: CanvasStrokeColor(color: state.strokeColor, opacity: state.opacity),
                strokeWidth: CGFloat(state.strokeWidth),
                fillColor: CanvasStrokeColor(color: state.fillColor, opacity: 1),
                fillOpacity: CGFloat(state.geometryFillOpacity),
                polygonSides: state.polygonSides,
                arrow: CanvasGeometryArrow(mode: state.geometryLineArrowMode)
            ))
        case .reserved:
            self.init(.idle)
        case .cover:
            self.init(.cover(
                color: CanvasStrokeColor(color: state.strokeColor, opacity: 1),
                mode: CanvasToolCommand.SelectionMode(regionSelectionMode: state.selectionMode)
            ))
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
            self.init(.idle)
        }
    }

    private static func shouldApply(_ command: ToolPaletteCommand, activeTool: ToolID) -> Bool {
        switch command {
        case .selectTool(let tool):
            return ToolID.allCases.contains(tool)
        case .setStrokeColor, .setPaletteColor, .setStrokeWidth, .setOpacity:
            return activeTool == .pen || activeTool == .marker || activeTool == .eraser || activeTool == .laser || activeTool == .geometry || activeTool == .cover
        case .setFillColor, .setGeometryType, .setPolygonSides, .setGeometryLineArrowMode, .setGeometryFillOpacity:
            return activeTool == .geometry
        case .setEraserMode:
            return activeTool == .eraser
        case .setLaserDuration, .setLaserMode:
            return activeTool == .laser
        case .setTextBold, .setTextItalic, .setTextUnderlined, .setTextSize, .setTextFontName:
            return false
        case .setSelectionTarget:
            return activeTool == .selection || activeTool == .extract
        case .setSelectionMode:
            return activeTool == .selection || activeTool == .extract || activeTool == .cover
        case .setSelectionBehavior:
            return activeTool == .selection
        case .setExtractAction:
            return activeTool == .extract
        case .copySelection, .pasteSelection, .duplicateSelection, .deleteSelection,
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

private extension CanvasGeometryShape {
    init(geometryType: GeometryType) {
        switch geometryType {
        case .line: self = .line
        case .circle: self = .circle
        case .rightTriangle: self = .rightTriangle
        case .triangle: self = .triangle
        case .rectangle: self = .rectangle
        case .polygon: self = .polygon
        }
    }
}

private extension View {
    @ViewBuilder
    func platformEditorCover<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented) {
            content()
        }
        #else
        sheet(isPresented: isPresented) {
            content()
        }
        #endif
    }

    @ViewBuilder
    func platformEditorCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(iOS)
        fullScreenCover(item: item) { item in
            content(item)
        }
        #else
        sheet(item: item) { item in
            content(item)
        }
        #endif
    }
}

private extension CanvasGeometryArrow {
    init(mode: GeometryLineArrowMode) {
        switch mode {
        case .none: self = .none
        case .start: self = .start
        case .end: self = .end
        case .both: self = .both
        }
    }
}

private extension GeometryType {
    init(canvasShape: CanvasGeometryShape) {
        switch canvasShape {
        case .line: self = .line
        case .circle: self = .circle
        case .rightTriangle: self = .rightTriangle
        case .triangle: self = .triangle
        case .rectangle: self = .rectangle
        case .polygon: self = .polygon
        }
    }
}

private extension GeometryLineArrowMode {
    init(canvasArrow: CanvasGeometryArrow) {
        switch canvasArrow {
        case .none: self = .none
        case .start: self = .start
        case .end: self = .end
        case .both: self = .both
        }
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

private extension CanvasToolCommand.SelectionBehavior {
    init(selectionBehavior: SelectionBehavior) {
        switch selectionBehavior {
        case .single:
            self = .single
        case .multi:
            self = .multi
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
    init(selectionSelectionMode: SelectionMode) {
        self = .marquee
    }

    init(regionSelectionMode: SelectionMode) {
        switch regionSelectionMode {
        case .tap:
            self = .marquee
        case .lasso:
            self = .lasso
        case .marquee:
            self = .marquee
        }
    }
}

private extension CanvasToolCommand.ExtractAction {
    init(extractAction: ExtractAction) {
        switch extractAction {
        case .copy:
            self = .copy
        case .clone:
            self = .clone
        case .send:
            self = .send
        case .sticker:
            self = .sticker
        case .delete:
            self = .delete
        }
    }
}
