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
public typealias PresentationCanvasLaTeXObject = CanvasLaTeXObject
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
    private let onViewportSourceRectChange: (@MainActor (CGRect) -> Void)?
    private let onLiveStrokeUpdate: (@MainActor (CanvasLiveStroke?) -> Void)?
    private let onDrawingDataChange: (@MainActor (Data) -> Void)?
    private let onCanvasObjectStateChange: (@MainActor () -> Void)?
    private let onLibraryDrawerOpenChange: (@MainActor (Bool) -> Void)?
    private let objectStateReloadCommand: CanvasObjectCommand?
    private let allowsWidgetAuthoring: Bool
    private static let importedPhotoMaxPixelSide: CGFloat = 1800
    private static let importedPhotoJPEGCompressionQuality: CGFloat = 0.82
    private let broker = DisplayBroker.shared
    private let calculator = CalculatorState.shared
    private let paletteSettings = ToolPaletteSettings.shared

    @State private var viewportCommand: CanvasViewportCommand?
    @State private var editCommand: CanvasEditCommand?
    @State private var toolCommand: CanvasToolCommand?
    @State private var objectCommand: CanvasObjectCommand?
    @State private var animationPlaybackState = CanvasAnimationPlaybackState()
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
    @State private var pendingCatalogWidgetPreview: PendingCatalogWidgetPreview?
    @State private var pendingWidgetEdit: PendingWidgetEdit?
    @State private var activeWidgetMathInputRequest: WidgetMathInputKeypadRequest?
    @State private var widgetMathKeypadPosition: CGPoint?
    @State private var widgetMathKeypadDragStart: WidgetMathKeypadDragStart?
    @State private var widgetMathKeypadSizeOverride: CGSize?
    @State private var widgetMathKeypadResizeStart: CGSize?
    @State private var pendingPDFObjectImport: PendingPDFObjectImport?
    @State private var imageFileImportError: ImageFileImportError?
    @State private var isExternalDisplayUnavailableAlertPresented = false
    @State private var libraryRecentRefreshID = UUID()
    /// The tool that was active before the most recent tool change, so an
    /// Apple Pencil barrel double tap can toggle back to it.
    @State private var pencilPreviousTool: ToolID?

    @Environment(\.preferredPencilDoubleTapAction) private var preferredPencilDoubleTapAction

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
        onViewportSourceRectChange: (@MainActor (CGRect) -> Void)? = nil,
        onLiveStrokeUpdate: (@MainActor (CanvasLiveStroke?) -> Void)? = nil,
        onDrawingDataChange: (@MainActor (Data) -> Void)? = nil,
        onCanvasObjectStateChange: (@MainActor () -> Void)? = nil,
        onLibraryDrawerOpenChange: (@MainActor (Bool) -> Void)? = nil,
        objectStateReloadCommand: CanvasObjectCommand? = nil,
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
        self.onViewportSourceRectChange = onViewportSourceRectChange
        self.onLiveStrokeUpdate = onLiveStrokeUpdate
        self.onDrawingDataChange = onDrawingDataChange
        self.onCanvasObjectStateChange = onCanvasObjectStateChange
        self.onLibraryDrawerOpenChange = onLibraryDrawerOpenChange
        self.objectStateReloadCommand = objectStateReloadCommand
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
                animationPlaybackState: animationPlaybackState,
                selectionState: $selectionState,
                showsSystemToolPicker: !paletteSettings.isCustomPaletteEnabled,
                onFrameUpdate: broker.isExternalDisplayConnected ? Self.publishFrame : nil,
                onViewportSourceRectChange: publishViewportSourceRect,
                onLiveStrokeUpdate: publishLiveStroke,
                onDrawingDataChange: publishDrawingData,
                onWidgetObjectsChange: Self.publishWidgets,
                onCanvasObjectStateChange: onCanvasObjectStateChange,
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
                onWidgetMathInputRequested: handleWidgetMathInputRequest,
                onWidgetImageInsertionRequested: handleWidgetImageInsertionRequest,
                allowsWidgetAuthoring: allowsWidgetAuthoring
            )
            ViewfinderOverlay()
                .opacity(broker.mode == .present ? 1 : 0)

            if calculator.isVisible {
                CalculatorView(state: calculator, onSnapshot: { data, size in
                    objectCommand = CanvasObjectCommand(.insertImageNearViewport(
                        CanvasViewportImageInsertion(pngData: data, displaySize: size)
                    ))
                })
            }

            floatingLaTeXEditor

            widgetMathInputKeypadOverlay

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

    @ViewBuilder
    private var widgetMathInputKeypadOverlay: some View {
        if let request = activeWidgetMathInputRequest {
            GeometryReader { proxy in
                let panelSize = widgetMathKeypadSize(in: proxy.size)
                let center = resolvedWidgetMathKeypadPosition(panelSize: panelSize, in: proxy.size)
                let panelShape = RoundedRectangle(cornerRadius: 16, style: .continuous)

                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: request.kind == .numeric ? "number" : "keyboard")
                            .font(.headline.weight(.bold))
                        Text(request.title)
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Button {
                            activeWidgetMathInputRequest = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundStyle(.black.opacity(0.78))
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .background(Color.white)
                    .contentShape(Rectangle())
                    .gesture(widgetMathKeypadDragGesture(panelSize: panelSize, in: proxy.size))

                    MathInputKeyboardView(
                        profile: request.kind == .numeric ? .numericAnswer : .alphanumericAnswer,
                        onInsert: { text in insertWidgetMathInputText(text, into: request) },
                        onDelete: { request.applyAction(.deleteBackward) },
                        onClear: { request.applyAction(.clear) },
                        onReturn: { request.applyAction(.returnKey) },
                        onMoveLeft: { request.applyAction(.moveCursorLeft) },
                        onMoveRight: { request.applyAction(.moveCursorRight) }
                    )
                    .frame(height: max(120, panelSize.height - 42))
                }
                .frame(width: panelSize.width, height: panelSize.height)
                .background(Color.white, in: panelShape)
                .clipShape(panelShape)
                .overlay(
                    panelShape
                        .strokeBorder(Color.black.opacity(0.16), lineWidth: 1)
                )
                .overlay(alignment: .bottomTrailing) {
                    widgetMathKeypadResizeHandle(panelSize: panelSize, containerSize: proxy.size)
                }
                .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 8)
                .position(center)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            .ignoresSafeArea()
            .zIndex(30)
        }
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            canvasStack
            LibraryDrawerPrototypeView(
                startOpen: false,
                recentLessonURL: LibraryRecentStore.lessonURL(forDrawingURL: drawingURL),
                recentRefreshID: libraryRecentRefreshID,
                onInsertItem: { payload in
                    placeLibraryItemAtViewportCenter(payload)
                },
                onPreviewCatalogMathtivity: presentCatalogWidgetPreview,
                onOpenStateChange: { isOpen in
                    onLibraryDrawerOpenChange?(isOpen)
                }
            )
            floatingToolBar
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .onAppear {
            applyObjectStateReloadCommandIfNeeded()
            applyCurrentToolPaletteStateIfNeeded(triggering: .selectTool(broker.toolPaletteState.activeTool))
            broker.graphSnapshotHandler = insertGraphSnapshot
        }
        .onDisappear {
            broker.graphSnapshotHandler = nil
        }
        .onChange(of: objectStateReloadCommand) { _, _ in
            applyObjectStateReloadCommandIfNeeded()
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
        .onChange(of: broker.toolPaletteState.activeTool) { oldValue, newValue in
            if oldValue != newValue {
                pencilPreviousTool = oldValue
            }
        }
        .onPencilDoubleTap { _ in
            handlePencilDoubleTap()
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
            let state = broker.toolPaletteState
            TextEditorModalView(
                viewModel: TextEditorViewModel(
                    fontSize: editorFontSize(forCanvasFontSize: CGFloat(state.textSize)),
                    fontName: state.textFontName,
                    textColor: TextEditorColor(CanvasStrokeColor(color: state.strokeColor, opacity: state.opacity))
                )
            ) { result in
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
                    fontName: edit.object.fontName ?? "System",
                    textColor: TextEditorColor(
                        red: edit.object.red,
                        green: edit.object.green,
                        blue: edit.object.blue,
                        alpha: edit.object.alpha
                    ),
                    backgroundColor: edit.object.backgroundColorComponents.map {
                        TextEditorColor(red: $0.red, green: $0.green, blue: $0.blue, alpha: $0.alpha)
                    }
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
        .platformEditorCover(item: $pendingCatalogWidgetPreview) { preview in
            WidgetEditorView(
                initialJSONSource: preview.downloadedItem.jsonSource,
                insertButtonTitle: "Insert Widget"
            ) { insertion in
                insertWidget(insertion)
                pendingCatalogWidgetPreview = nil
                activateSelectTool()
            } onCancel: {
                pendingCatalogWidgetPreview = nil
                activateSelectTool()
            }
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
        .alert("External Display Not Available", isPresented: $isExternalDisplayUnavailableAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            externalDisplayUnavailableAlertMessage
        }
    }

    private var externalDisplayUnavailableAlertMessage: some View {
        Text("MathBoard is not receiving a custom external-display route from iPadOS. The monitor will continue to mirror this iPad until iPadOS provides either the external scene path or the legacy external screen path.")
    }

    // Icon-only toolbar at top-center — promoted actions as icon buttons,
    // with remaining items in the ... overflow menu.
    private var floatingToolBar: some View {
        HStack(spacing: 0) {
            toolbarIconButton("arrow.uturn.backward", label: "Undo", disabled: !editState.canUndo) {
                editCommand = CanvasEditCommand(.undo)
            }
            toolbarIconButton("arrow.uturn.forward", label: "Redo", disabled: !editState.canRedo) {
                editCommand = CanvasEditCommand(.redo)
            }
            toolbarSeparator
            toolbarIconButton("plus.magnifyingglass", label: "Zoom In", disabled: !canZoomIn) {
                viewportCommand = CanvasViewportCommand(.zoomIn)
            }
            toolbarIconButton("minus.magnifyingglass", label: "Zoom Out", disabled: !canZoomOut) {
                viewportCommand = CanvasViewportCommand(.zoomOut)
            }
            toolbarIconButton("arrow.counterclockwise", label: "Reset Zoom") {
                viewportCommand = CanvasViewportCommand(.reset)
            }
            toolbarSeparator
            toolbarIconButton(
                broker.mode == .present ? "rectangle.dashed" : "rectangle.inset.filled",
                label: broker.mode == .present ? "Mirror Mode" : "Present Mode"
            ) {
                togglePresentationMode()
            }
            toolbarIconButton("forward.frame.fill", label: "Next Animation") {
                advanceAnimationPlayback()
            }
            toolbarIconButton("arrow.counterclockwise.circle", label: "Reset Animations") {
                resetAnimationPlayback()
            }
            #if os(iOS)
            toolbarIconButton(
                "chart.xyaxis.line",
                label: isGraphCalculatorVisibleToUser ? "Hide Graph Calc" : "Show Graph Calc"
            ) {
                if isGraphCalculatorVisibleToUser {
                    broker.isGraphCalculatorVisible = false
                } else {
                    broker.graphCalculator.restoreCompositeHomeBase()
                    broker.isGraphCalculatorVisible = true
                }
            }
            #endif
            toolbarSeparator
            floatingOverflowMenu
        }
        .padding(.horizontal, 6)
        .frame(height: 50)
        .background(
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.18, green: 0.26, blue: 0.40),
                            Color(red: 0.10, green: 0.16, blue: 0.27)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1.2)
        )
        .shadow(color: .white.opacity(0.10), radius: 1, x: 0, y: -1)
        .shadow(color: .black.opacity(0.40), radius: 12, x: 0, y: 5)
    }

    private var toolbarSeparator: some View {
        Rectangle()
            .fill(Color.white.opacity(0.18))
            .frame(width: 1, height: 24)
            .padding(.horizontal, 4)
    }

    private func toolbarIconButton(
        _ systemImage: String,
        label: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
                .frame(width: 46, height: 44)
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.28 : 1.0)
        .disabled(disabled)
        .accessibilityLabel(label)
    }

    private var floatingOverflowMenu: some View {
        Menu {
            Section("Zoom \(zoomLabel)") {
                Button {
                    viewportCommand = CanvasViewportCommand(.fitToViewfinder)
                } label: {
                    Label("Fit to Viewfinder", systemImage: "aspectratio")
                }
            }

            Section {
                Label(externalDisplayStatusTitle, systemImage: externalDisplayStatusIcon)
                    .foregroundStyle(.secondary)

                Button {
                    calculator.isVisible.toggle()
                } label: {
                    Label(
                        calculator.isVisible ? "Hide Calculator" : "Calculator",
                        systemImage: "function"
                    )
                }
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
            HStack(spacing: 5) {
                if broker.isExternalDisplayConnected {
                    Image(systemName: "tv.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 14, weight: .semibold))
                }
                Image(systemName: "ellipsis")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
            }
            .frame(width: 50, height: 44)
        }
        .menuOrder(.fixed)
        .accessibilityLabel("More")
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
                    onTextEffect: textEffectAction(for: object.id),
                    onTextEffectToggleVisibility: {
                        objectCommand = CanvasObjectCommand(.toggleTextEffectHidden(object.id))
                    },
                    onTextEffectPlay: {
                        objectCommand = CanvasObjectCommand(.playTextEffect(object.id))
                    },
                    onTextEffectPause: {
                        objectCommand = CanvasObjectCommand(.pauseTextEffect(object.id))
                    },
                    onTextEffectRepeat: { repeatMode in
                        objectCommand = CanvasObjectCommand(.setTextEffectRepeatMode(object.id, repeatMode))
                    },
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
                let isLocked = object.isLocked == true
                FloatingActionHUD(
                    onEdit: { loadGeometryObjectIntoPalette(object) },
                    onCopy: { objectCommand = CanvasObjectCommand(.copy(.geometry(object.id))) },
                    onClone: { objectCommand = CanvasObjectCommand(.duplicate(.geometry(object.id))) },
                    onLockToggle: { objectCommand = CanvasObjectCommand(.setGeometryLocked(object.id, !isLocked)) },
                    lockToggleTitle: isLocked ? "Locked" : "Unlocked",
                    lockToggleSystemImage: isLocked ? "lock.fill" : "lock.open",
                    lockToggleTint: isLocked ? .red : .green,
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
                    onBringForward: { objectCommand = CanvasObjectCommand(.reorderImage(object.id, .bringForward)) },
                    onSendBackward: { objectCommand = CanvasObjectCommand(.reorderImage(object.id, .sendBackward)) },
                    onBringToFront: { objectCommand = CanvasObjectCommand(.reorderImage(object.id, .bringToFront)) },
                    onSendToBack: { objectCommand = CanvasObjectCommand(.reorderImage(object.id, .sendToBack)) },
                    canBringForward: !isLocked && selectionState.selectedImageCanMoveForward,
                    canSendBackward: !isLocked && selectionState.selectedImageCanMoveBackward,
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

    private var externalDisplayStatusTitle: String {
        switch broker.externalDisplayConnectionRoute {
        case .none:
            return "External: none"
        case .scene:
            return "External: scene"
        case .legacyScreen:
            return "External: legacy"
        }
    }

    private var externalDisplayStatusIcon: String {
        broker.externalDisplayConnectionRoute == .none ? "display.slash" : "display"
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
        let nextMode: CanvasPresentationMode = broker.mode == .present ? .mirror : .present
        broker.mode = nextMode
        animationPlaybackState = nextMode == .present
            ? CanvasAnimationPlaybackState(currentStep: 0, isPresenting: true)
            : animationPlaybackState.reset()
        if nextMode == .present, broker.externalDisplayConnectionRoute == .none {
            isExternalDisplayUnavailableAlertPresented = true
        }
    }

    private func advanceAnimationPlayback() {
        animationPlaybackState = animationPlaybackState.advancing()
    }

    private func resetAnimationPlayback() {
        animationPlaybackState = broker.mode == .present
            ? CanvasAnimationPlaybackState(currentStep: 0, isPresenting: true)
            : animationPlaybackState.reset()
    }

    private func textEffectAction(for textObjectID: UUID) -> (CanvasAnimationPreset?) -> Void {
        { preset in
            if let preset {
                objectCommand = CanvasObjectCommand(.setTextEffect(textObjectID, preset))
            } else {
                objectCommand = CanvasObjectCommand(.removeAnimation(CanvasAnimatedObjectRef(kind: .text, id: textObjectID)))
            }
            resetAnimationPlayback()
        }
    }

    /// Handles an Apple Pencil barrel double tap, honoring the person's
    /// systemwide preference from Settings > Apple Pencil > Actions > Double
    /// Tap. Only the tool-switching preferences apply here; other preferences
    /// (color palette, shortcuts, ignore) do nothing. When the system PencilKit
    /// tool picker is showing instead of the custom palette, PencilKit handles
    /// the double tap itself, so this handler stays out of the way.
    private func handlePencilDoubleTap() {
        guard paletteSettings.isCustomPaletteEnabled else { return }

        let currentTool = broker.toolPaletteState.activeTool
        let targetTool: ToolID?
        if preferredPencilDoubleTapAction == .switchEraser {
            targetTool = currentTool == .eraser ? pencilPreviousTool : .eraser
        } else if preferredPencilDoubleTapAction == .switchPrevious {
            targetTool = pencilPreviousTool
        } else {
            targetTool = nil
        }
        guard let targetTool, targetTool != currentTool else { return }

        var state = broker.toolPaletteState
        ToolPaletteReducer.reduce(&state, command: .selectTool(targetTool))
        broker.toolPaletteState = state
        applyToolPaletteState(state, triggering: .selectTool(targetTool))
    }

    private func handleToolPaletteCommand(_ command: ToolPaletteCommand, state: ToolPaletteState) {
        if command == .addItem(.file) {
            broker.toolPaletteState = collapsedAddItemState(from: state)
            presentImageFileImporter()
            return
        }

        if command == .addItem(.photo) {
            broker.toolPaletteState = collapsedAddItemState(from: state)
            presentPhotoImporter()
            return
        }

        if command == .addItem(.camera) {
            broker.toolPaletteState = collapsedAddItemState(from: state)
            presentCameraImporter()
            return
        }

        if command == .addItem(.text) {
            broker.toolPaletteState = collapsedAddItemState(from: state)
            requestTextPlacementAtViewportCenter()
            activateSelectTool()
            return
        }

        if command == .addItem(.latex) {
            broker.toolPaletteState = collapsedAddItemState(from: state)
            requestLaTeXPlacementAtViewportCenter()
            activateSelectTool()
            return
        }

        if command == .addItem(.widget) {
            guard allowsWidgetAuthoring else { return }
            broker.toolPaletteState = collapsedAddItemState(from: state)
            presentWidgetEditor()
            return
        }

        if case .addItem = command {
            broker.toolPaletteState = collapsedAddItemState(from: state)
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

    private func collapsedAddItemState(from state: ToolPaletteState) -> ToolPaletteState {
        var collapsedState = state
        collapsedState.isCompactDrawerOpen = false
        collapsedState.isCompactQuickStripOpen = false
        return collapsedState
    }

    private func handleCanvasInteractionBegan() {
        collapseCompactDrawerForCanvasInteraction()
        onInteractionBegan?()
    }

    private func collapseCompactDrawerForCanvasInteraction() {
        guard paletteSettings.isCustomPaletteEnabled,
              paletteSettings.paletteStyle == .compact,
              (broker.toolPaletteState.isCompactDrawerOpen || broker.toolPaletteState.isCompactQuickStripOpen) else {
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

    private func presentCatalogWidgetPreview(_ downloadedItem: DownloadedMathtivityCatalogItem) {
        if downloadedItem.item.catalogKind == .builtInInteractive {
            let builtInKind = downloadedItem.item.builtInKind
            let displaySize = catalogBuiltInDisplaySize(for: builtInKind)
            placeLibraryItemAtViewportCenter(
                LibraryCanvasDragPayload(
                    title: downloadedItem.item.title,
                    kind: .widget,
                    displaySize: displaySize,
                    widgetCodeString: downloadedItem.jsonSource
                ),
                pinsWidgetToCanvas: builtInKind == .matchGrid
            )
            recordLibraryRecent(
                title: downloadedItem.item.title,
                kind: .widget,
                widgetCodeString: downloadedItem.jsonSource
            )
            return
        }

        Task { @MainActor in
            await Task.yield()
            pendingCatalogWidgetPreview = PendingCatalogWidgetPreview(downloadedItem: downloadedItem)
        }
    }

    private func catalogBuiltInDisplaySize(for kind: BuiltInInteractiveKind?) -> CGSize {
        let defaultSize = kind?.defaultSize ?? CGSize(width: 820, height: 420)
        guard kind == .matchGrid else { return defaultSize }
        let referenceSize = broker.toolPaletteReferenceSize
            ?? broker.calculatorReferenceSize
            ?? CGSize(width: 1194, height: 744)
        let margin: CGFloat = 24
        let availableWidth = max(referenceSize.width - margin * 2, 1)
        let availableHeight = max(referenceSize.height - margin * 2, 1)
        let scale = min(1, availableWidth / defaultSize.width, availableHeight / defaultSize.height)
        return CGSize(width: defaultSize.width * scale, height: defaultSize.height * scale)
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
        state.isCompactQuickStripOpen = false
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
        state.isCompactQuickStripOpen = false
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
                state.isCompactQuickStripOpen = false
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
        if case .geometry = oldValue,
           !Self.isGeometrySelection(newValue) {
            if isClearingGeometrySelectionForCreation {
                isClearingGeometrySelectionForCreation = false
                return
            }

            // Return the palette to the selection controls after deselecting.
            var state = broker.toolPaletteState
            if state.activeTool == .geometry {
                state.activeTool = .selection
                state.isCompactQuickStripOpen = false
                broker.toolPaletteState = state
            }
        }
    }

    private static func isGeometrySelection(_ object: CanvasSelectionState.Object?) -> Bool {
        if case .geometry = object {
            return true
        }
        return false
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
    private func placeLibraryItem(
        _ payload: LibraryCanvasDragPayload,
        at canvasPoint: CGPoint,
        pinsWidgetToCanvas: Bool = false
    ) {
        if payload.kind == .widget,
           let widgetCodeString = payload.widgetCodeString {
            objectCommand = CanvasObjectCommand(.insertWidget(CanvasWidgetInsertion(
                name: payload.title,
                codeString: widgetCodeString,
                displaySize: payload.displaySize,
                canvasPoint: canvasPoint,
                librarySourceCodeString: widgetCodeString,
                isPinnedToCanvas: pinsWidgetToCanvas
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
                backgroundColor: textPayload.backgroundAlpha.map { alpha in
                    CanvasStrokeColor(
                        red: textPayload.backgroundRed ?? 1,
                        green: textPayload.backgroundGreen ?? 1,
                        blue: textPayload.backgroundBlue ?? 1,
                        alpha: alpha
                    )
                },
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
    private func placeLibraryItemAtViewportCenter(
        _ payload: LibraryCanvasDragPayload,
        pinsWidgetToCanvas: Bool = false
    ) {
        let referenceSize = broker.toolPaletteReferenceSize
            ?? broker.calculatorReferenceSize
            ?? CGSize(width: 1194, height: 744)
        placeLibraryItem(
            payload,
            at: CGPoint(x: referenceSize.width / 2, y: referenceSize.height / 2),
            pinsWidgetToCanvas: pinsWidgetToCanvas
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
            kind: .sticker,
            thumbnailPNGData: region.pngData
        )
    }

    private func handleExtractedRegionSend(_ region: PresentationExtractedRegion) {
        onExtractedRegionSend?(region)
        libraryRecentRefreshID = UUID()
    }

    private func applyObjectStateReloadCommandIfNeeded() {
        guard let objectStateReloadCommand,
              objectCommand?.id != objectStateReloadCommand.id else {
            return
        }
        objectCommand = objectStateReloadCommand
    }

    private func insertText(_ result: TextEditorResult, placement: PendingTextPlacement) {
        let canvasFontSize = canvasFontSize(forEditorFontSize: result.fontSize)
        objectCommand = CanvasObjectCommand(.insertText(CanvasTextInsertion(
            text: result.sourceText,
            sourcePoint: placement.sourcePoint,
            canvasPoint: placement.canvasPoint,
            fontSize: canvasFontSize,
            color: CanvasStrokeColor(result.textColor),
            backgroundColor: result.backgroundColor.map(CanvasStrokeColor.init),
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
                fontSize: canvasFontSize,
                fallbackSize: object.frame.size
            )
        )

        objectCommand = CanvasObjectCommand(.updateText(CanvasTextUpdate(
            id: object.id,
            text: result.sourceText,
            fontSize: canvasFontSize,
            color: CanvasStrokeColor(result.textColor),
            backgroundColor: result.backgroundColor.map(CanvasStrokeColor.init),
            updatesBackgroundColor: true,
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

    private func handleWidgetMathInputRequest(_ request: WidgetMathInputKeypadRequest) {
        activeWidgetMathInputRequest = request
    }

    private func handleWidgetImageInsertionRequest(_ request: WidgetCanvasImageInsertionRequest) {
        guard allowsWidgetAuthoring else { return }
        objectCommand = CanvasObjectCommand(.insertImageNearViewport(
            CanvasViewportImageInsertion(
                pngData: request.pngData,
                displaySize: request.displaySize,
                selectAfterInsert: true
            )
        ))
        recordLibraryRecent(
            title: Self.libraryRecentTitle(request.title),
            kind: .graphSnapshot,
            thumbnailPNGData: request.pngData
        )
        activateSelectTool()
    }

    private func insertWidgetMathInputText(_ text: String, into request: WidgetMathInputKeypadRequest) {
        guard let filteredText = filteredWidgetInputText(text, for: request.kind), !filteredText.isEmpty else { return }
        request.applyAction(.insert(filteredText))
    }

    private func filteredWidgetInputText(
        _ text: String,
        for kind: WidgetMathInputKeypadKind
    ) -> String? {
        switch kind {
        case .alphanumeric:
            return text
        case .numeric:
            let allowedCharacters = CharacterSet(charactersIn: "0123456789.-/ ")
            let filteredScalars = text.unicodeScalars.filter { allowedCharacters.contains($0) }
            return String(String.UnicodeScalarView(filteredScalars))
        }
    }

    private func widgetMathKeypadSize(in containerSize: CGSize) -> CGSize {
        let defaultSize = CGSize(
            width: min(max(containerSize.width - 32, 520), 760),
            height: 252
        )
        let proposed = widgetMathKeypadSizeOverride ?? defaultSize
        return clampWidgetMathKeypadSize(proposed, in: containerSize)
    }

    private func resolvedWidgetMathKeypadPosition(panelSize: CGSize, in containerSize: CGSize) -> CGPoint {
        let defaultCenter = CGPoint(
            x: containerSize.width / 2,
            y: max(panelSize.height / 2 + 16, containerSize.height - panelSize.height / 2 - 34)
        )
        return clampWidgetMathKeypadPosition(widgetMathKeypadPosition ?? defaultCenter, panelSize: panelSize, in: containerSize)
    }

    private func widgetMathKeypadDragGesture(panelSize: CGSize, in containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let start = widgetMathKeypadDragStart ?? WidgetMathKeypadDragStart(
                    center: resolvedWidgetMathKeypadPosition(panelSize: panelSize, in: containerSize),
                    location: value.startLocation
                )
                if widgetMathKeypadDragStart == nil {
                    widgetMathKeypadDragStart = start
                }
                let translation = CGSize(
                    width: value.location.x - start.location.x,
                    height: value.location.y - start.location.y
                )
                widgetMathKeypadPosition = clampWidgetMathKeypadPosition(
                    CGPoint(x: start.center.x + translation.width, y: start.center.y + translation.height),
                    panelSize: panelSize,
                    in: containerSize
                )
            }
            .onEnded { _ in
                widgetMathKeypadDragStart = nil
            }
    }

    private func widgetMathKeypadResizeHandle(panelSize: CGSize, containerSize: CGSize) -> some View {
        ZStack {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.caption.weight(.black))
                .foregroundStyle(.black.opacity(0.54))
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.92), in: Circle())
                .overlay(Circle().strokeBorder(.black.opacity(0.16), lineWidth: 1))
        }
        .padding(8)
        .contentShape(Rectangle())
        .gesture(widgetMathKeypadResizeGesture(panelSize: panelSize, in: containerSize))
    }

    private func widgetMathKeypadResizeGesture(panelSize: CGSize, in containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                let start = widgetMathKeypadResizeStart ?? panelSize
                if widgetMathKeypadResizeStart == nil {
                    widgetMathKeypadResizeStart = start
                }

                let nextSize = CGSize(
                    width: start.width + value.translation.width,
                    height: start.height + value.translation.height
                )
                let clampedSize = clampWidgetMathKeypadSize(nextSize, in: containerSize)
                widgetMathKeypadSizeOverride = clampedSize

                if let position = widgetMathKeypadPosition {
                    widgetMathKeypadPosition = clampWidgetMathKeypadPosition(position, panelSize: clampedSize, in: containerSize)
                }
            }
            .onEnded { _ in
                widgetMathKeypadResizeStart = nil
            }
    }

    private func clampWidgetMathKeypadSize(_ size: CGSize, in containerSize: CGSize) -> CGSize {
        CGSize(
            width: min(max(size.width, 420), max(420, containerSize.width - 24)),
            height: min(max(size.height, 172), max(172, containerSize.height - 24))
        )
    }

    private func clampWidgetMathKeypadPosition(_ position: CGPoint, panelSize: CGSize, in containerSize: CGSize) -> CGPoint {
        let halfWidth = panelSize.width / 2
        let halfHeight = panelSize.height / 2
        let x = min(max(position.x, halfWidth + 12), max(halfWidth + 12, containerSize.width - halfWidth - 12))
        let y = min(max(position.y, halfHeight + 12), max(halfHeight + 12, containerSize.height - halfHeight - 12))
        return CGPoint(x: x, y: y)
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
        state.isCompactQuickStripOpen = false
        broker.toolPaletteState = state
        applyToolPaletteState(state, triggering: .selectTool(.selection))
    }

    private func hudPosition(for frame: CGRect, in size: CGSize) -> CGPoint {
        let hudWidth: CGFloat = 300
        let hudHeight: CGFloat = 50
        let margin: CGFloat = 14
        let gap: CGFloat = 46
        let aboveY = frame.minY - hudHeight / 2 - gap
        let belowY = frame.maxY + hudHeight / 2 + gap
        let minimumY = margin + hudHeight / 2
        let maximumY = size.height - margin - hudHeight / 2
        let proposedY: CGFloat
        if aboveY >= minimumY {
            proposedY = aboveY
        } else if belowY <= maximumY {
            proposedY = belowY
        } else {
            proposedY = frame.midY < size.height / 2 ? belowY : aboveY
        }
        return CGPoint(
            x: min(max(frame.midX, margin + hudWidth / 2), size.width - margin - hudWidth / 2),
            y: min(max(proposedY, minimumY), maximumY)
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
    private func publishViewportSourceRect(_ sourceRect: CGRect) {
        Self.publishViewportSourceRect(sourceRect)
        onViewportSourceRectChange?(sourceRect)
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
                    imageFileExtension: importedImage.imageFileExtension,
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
              let preparedImage = preparedCanvasImage(from: image) else {
            throw ImageFileImportError(message: "MathBoard could not read this image file.")
        }
        return preparedImage
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

    #if os(iOS)
    private static func preparedCanvasImage(from image: UIImage) -> ImportedCanvasImage? {
        let sourcePixelSize = CGSize(
            width: CGFloat(image.cgImage?.width ?? Int(image.size.width * image.scale)),
            height: CGFloat(image.cgImage?.height ?? Int(image.size.height * image.scale))
        )
        let maxPixelSide = max(sourcePixelSize.width, sourcePixelSize.height, 1)
        let scale = min(1, importedPhotoMaxPixelSide / maxPixelSide)
        let outputPixelSize = CGSize(
            width: max((sourcePixelSize.width * scale).rounded(), 1),
            height: max((sourcePixelSize.height * scale).rounded(), 1)
        )
        let preservesAlpha = imageHasAlpha(image.cgImage)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = !preservesAlpha
        let preparedImage = UIGraphicsImageRenderer(size: outputPixelSize, format: format).image { context in
            if !preservesAlpha {
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: outputPixelSize))
            }
            image.draw(in: CGRect(origin: .zero, size: outputPixelSize))
        }

        if preservesAlpha {
            guard let pngData = preparedImage.pngData() else { return nil }
            return ImportedCanvasImage(pngData: pngData, imageFileExtension: "png", imageSize: outputPixelSize)
        }

        guard let jpegData = preparedImage.jpegData(compressionQuality: importedPhotoJPEGCompressionQuality) else {
            return nil
        }
        return ImportedCanvasImage(pngData: jpegData, imageFileExtension: "jpg", imageSize: outputPixelSize)
    }

    private static func imageHasAlpha(_ image: CGImage?) -> Bool {
        guard let image else { return false }
        switch image.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast:
            return true
        default:
            return false
        }
    }
    #endif

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
    private func publishLiveStroke(_ stroke: CanvasLiveStroke?) {
        Self.publishLiveStroke(stroke)
        onLiveStrokeUpdate?(stroke)
    }

    @MainActor
    private func publishDrawingData(_ data: Data) {
        onDrawingDataChange?(data)
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

private struct WidgetMathKeypadDragStart {
    var center: CGPoint
    var location: CGPoint
}

private struct PendingCatalogWidgetPreview: Identifiable {
    let id = UUID()
    var downloadedItem: DownloadedMathtivityCatalogItem
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
        fontSize: CGFloat? = nil,
        fallbackSize: CGSize = CGSize(width: 220, height: 80)
    ) {
        self.init(
            text: result.sourceText,
            fontSize: fontSize ?? result.fontSize,
            red: result.textColor.red,
            green: result.textColor.green,
            blue: result.textColor.blue,
            alpha: result.textColor.alpha,
            backgroundRed: result.backgroundColor?.red,
            backgroundGreen: result.backgroundColor?.green,
            backgroundBlue: result.backgroundColor?.blue,
            backgroundAlpha: result.backgroundColor?.alpha,
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
            backgroundRed: object.backgroundRed,
            backgroundGreen: object.backgroundGreen,
            backgroundBlue: object.backgroundBlue,
            backgroundAlpha: object.backgroundAlpha,
            isBold: object.isBold,
            isItalic: object.isItalic,
            isUnderlined: object.isUnderlined,
            fontName: object.fontName,
            width: object.width,
            height: object.height
        )
    }
}

private extension TextEditorColor {
    init(_ color: CanvasStrokeColor) {
        self.init(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }
}

private extension CanvasStrokeColor {
    init(_ color: TextEditorColor) {
        self.init(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }
}

private struct PendingPDFObjectImport: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ImportedCanvasImage {
    let pngData: Data
    let imageFileExtension: String
    let displaySize: CGSize

    init(pngData: Data, imageFileExtension: String = "png", imageSize: CGSize) {
        self.pngData = pngData
        self.imageFileExtension = imageFileExtension

        let maxDisplaySide: CGFloat = 480
        let width = max(imageSize.width, 1)
        let height = max(imageSize.height, 1)
        let scale = min(1, maxDisplaySide / max(width, height))
        self.displaySize = CGSize(width: width * scale, height: height * scale)
    }

    init(pngData: Data, imageFileExtension: String = "png", displaySize: CGSize) {
        self.pngData = pngData
        self.imageFileExtension = imageFileExtension
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
                  let imageData = image.jpegData(compressionQuality: 0.9) else {
                onCapture(.failure(ImageFileImportError(message: "MathBoard could not read the captured photo.")))
                return
            }

            onCapture(.success(imageData))
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
    var onPaste: (() -> Void)? = nil
    var onClone: (() -> Void)?
    var onBringForward: (() -> Void)?
    var onSendBackward: (() -> Void)?
    var onBringToFront: (() -> Void)?
    var onSendToBack: (() -> Void)?
    var canBringForward = true
    var canSendBackward = true
    var onLockToggle: (() -> Void)?
    var lockToggleTitle = "Lock"
    var lockToggleSystemImage = "lock"
    var lockToggleTint = Color.primary
    var onGroupToggle: (() -> Void)?
    var groupToggleTitle = "Group"
    var groupToggleSystemImage = "rectangle.3.group"
    var onTextEffect: ((CanvasAnimationPreset?) -> Void)?
    var onTextEffectToggleVisibility: (() -> Void)?
    var onTextEffectPlay: (() -> Void)?
    var onTextEffectPause: (() -> Void)?
    var onTextEffectRepeat: ((CanvasAnimationRepeatMode) -> Void)?
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
            if let onPaste {
                hudButton("Paste", systemImage: "doc.on.clipboard", action: onPaste)
            }
            if let onClone {
                hudButton("Clone", systemImage: "plus.square.on.square", action: onClone)
            }
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
                hudButton(
                    lockToggleTitle,
                    systemImage: lockToggleSystemImage,
                    foregroundColor: lockToggleTint,
                    action: onLockToggle
                )
            }
            if let onGroupToggle {
                hudButton(groupToggleTitle, systemImage: groupToggleSystemImage, action: onGroupToggle)
            }
            if let onTextEffectToggleVisibility {
                hudButton("Show or Hide Text Effect", systemImage: "eye", action: onTextEffectToggleVisibility)
            }
            if let onTextEffectPlay {
                hudButton("Play Text Effect", systemImage: "play.fill", action: onTextEffectPlay)
            }
            if let onTextEffectPause {
                hudButton("Pause Text Effect", systemImage: "pause.fill", action: onTextEffectPause)
            }
            if let onTextEffectRepeat {
                Menu {
                    ForEach(CanvasAnimationRepeatMode.allCases, id: \.self) { repeatMode in
                        Button(repeatMode.displayName) {
                            onTextEffectRepeat(repeatMode)
                        }
                    }
                } label: {
                    Label("Repeat Text Effect", systemImage: "repeat")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.primary)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.96), Color(red: 0.84, green: 0.90, blue: 0.96)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.72), lineWidth: 1)
                )
                .shadow(color: .white.opacity(0.32), radius: 2, x: -1, y: -1)
                .shadow(color: .black.opacity(0.12), radius: 3, x: 1, y: 2)
                .help("Repeat Text Effect")
            }
            if let onTextEffect {
                Menu {
                    ForEach(CanvasAnimationPreset.textEffectPresets, id: \.self) { preset in
                        Button(preset.displayName) {
                            onTextEffect(preset)
                        }
                    }
                    Divider()
                    Button("None", role: .destructive) {
                        onTextEffect(nil)
                    }
                } label: {
                    Label("Text Effects", systemImage: "textformat")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.primary)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.96), Color(red: 0.84, green: 0.90, blue: 0.96)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.72), lineWidth: 1)
                )
                .shadow(color: .white.opacity(0.32), radius: 2, x: -1, y: -1)
                .shadow(color: .black.opacity(0.12), radius: 3, x: 1, y: 2)
                .help("Text Effects")
            }
            hudButton("Delete", systemImage: "trash", role: .destructive, isEnabled: canDelete, action: onDelete)
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.93, green: 0.97, blue: 1.0).opacity(0.98),
                            Color(red: 0.72, green: 0.82, blue: 0.92).opacity(0.94)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.72), lineWidth: 1)
        )
        .shadow(color: .white.opacity(0.34), radius: 4, x: -2, y: -2)
        .shadow(color: Color.black.opacity(0.24), radius: 12, x: 0, y: 6)
    }

    private func hudButton(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        isEnabled: Bool = true,
        foregroundColor: Color? = nil,
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
        .foregroundStyle(foregroundColor ?? (role == .destructive ? .red : .primary))
        .background(
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.96), Color(red: 0.84, green: 0.90, blue: 0.96)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.72), lineWidth: 1)
        )
        .shadow(color: .white.opacity(0.32), radius: 2, x: -1, y: -1)
        .shadow(color: .black.opacity(0.12), radius: 3, x: 1, y: 2)
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
