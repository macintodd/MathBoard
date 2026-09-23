//
//  MacCanvasPlaceholder.swift
//  MathBoardCore - Canvas module (Mac)
//
//  First-pass Mac prep canvas. It uses mouse drag input to create PencilKit
//  strokes directly, then saves the same PKDrawing data that iPad opens.
//

#if os(macOS)

import SwiftUI
import AppKit
import PDFKit
import PencilKit
import WidgetEngine

private enum MacCanvasTool: String, CaseIterable, Identifiable {
    case select
    case pen
    case eraser
    case text
    case extract

    var id: Self { self }

    var title: String {
        switch self {
        case .select:
            return "Select"
        case .pen:
            return "Pen"
        case .eraser:
            return "Eraser"
        case .text:
            return "Text"
        case .extract:
            return "Extract"
        }
    }

    var systemImage: String {
        switch self {
        case .select:
            return "cursorarrow"
        case .pen:
            return "pencil.tip"
        case .eraser:
            return "eraser"
        case .text:
            return "textformat"
        case .extract:
            return "crop"
        }
    }
}

private enum MacTextInteractionMode: Equatable {
    case move(offset: CGSize)
    case resize(origin: CGPoint)
}

private enum MacImageInteractionMode: Equatable {
    case move(offset: CGSize)
}

private struct MacExtractSelection: Equatable {
    var start: CGPoint
    var current: CGPoint

    var rect: CGRect {
        CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }
}

private enum MacPenPreset: String, CaseIterable, Identifiable {
    case black
    case blue
    case red
    case green
    case yellow

    var id: Self { self }

    var title: String {
        rawValue.capitalized
    }

    var nsColor: NSColor {
        switch self {
        case .black:
            return NSColor(srgbRed: 0.0001, green: 0.0001, blue: 0.0001, alpha: 1)
        case .blue:
            return NSColor(calibratedRed: 0.0, green: 0.32, blue: 0.92, alpha: 1)
        case .red:
            return NSColor(calibratedRed: 0.92, green: 0.08, blue: 0.12, alpha: 1)
        case .green:
            return NSColor(calibratedRed: 0.05, green: 0.62, blue: 0.24, alpha: 1)
        case .yellow:
            return NSColor(calibratedRed: 0.95, green: 0.72, blue: 0.0, alpha: 1)
        }
    }

    var color: Color {
        Color(nsColor: nsColor)
    }

    var textColorComponents: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        let color = nsColor.usingColorSpace(.deviceRGB) ?? nsColor
        return (color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent)
    }

    func apply(to textObject: inout CanvasTextObject) {
        let components = textColorComponents
        textObject.setColor(
            red: components.red,
            green: components.green,
            blue: components.blue,
            alpha: components.alpha
        )
    }

    static func closestPreset(to color: CanvasStrokeColor) -> MacPenPreset {
        allCases.min { lhs, rhs in
            lhs.distance(to: color) < rhs.distance(to: color)
        } ?? .black
    }

    private func distance(to color: CanvasStrokeColor) -> CGFloat {
        let components = textColorComponents
        let red = components.red - color.red
        let green = components.green - color.green
        let blue = components.blue - color.blue
        return red * red + green * green + blue * blue
    }
}

struct MacCanvasPlaceholder: View {
    let drawingURL: URL
    let widgetAssetBaseURL: URL?
    let background: CanvasBackground?
    let initialViewportState: CanvasViewportState?
    let viewportCommand: CanvasViewportCommand?
    let editCommand: CanvasEditCommand?
    let toolCommand: CanvasToolCommand?
    let objectCommand: CanvasObjectCommand?
    let onWidgetObjectsChange: (@MainActor ([WidgetObject], WidgetCanvasViewport, CGSize, String) -> Void)?
    let onCanvasObjectStateChange: (@MainActor () -> Void)?
    let onViewportStateChange: (@MainActor (CanvasViewportState) -> Void)?
    let onEditStateChange: (@MainActor (CanvasEditState) -> Void)?
    let onInteractionBegan: (@MainActor () -> Void)?
    let onWidgetEditRequested: (@MainActor (WidgetObject) -> Void)?
    let onWidgetMathInputRequested: (@MainActor (WidgetMathInputKeypadRequest) -> Void)?
    let onWidgetImageInsertionRequested: (@MainActor (WidgetCanvasImageInsertionRequest) -> Void)?
    let allowsWidgetAuthoring: Bool
    let showsTeacherDemoWebApplets: Bool

    @State private var drawing = PKDrawing()
    @State private var didLoad = false
    @State private var saveTask: Task<Void, Never>?
    @State private var hasPendingSave = false
    @State private var currentPoints: [CGPoint] = []
    @State private var strokeColorRecords: [CanvasStrokeColorRecord] = []
    @State private var textObjects: [CanvasTextObject] = []
    @State private var imageObjects: [CanvasImageObject] = []
    @State private var latexObjects: [CanvasLaTeXObject] = []
    @State private var widgetObjects: [WidgetObject] = []
    @State private var appliedEditCommandID: CanvasEditCommand.ID?
    @State private var appliedToolCommandID: CanvasToolCommand.ID?
    @State private var appliedObjectCommandID: CanvasObjectCommand.ID?
    @State private var selectedTextObjectID: UUID?
    @State private var selectedImageObjectID: UUID?
    @State private var textInteractionMode: MacTextInteractionMode?
    @State private var imageInteractionMode: MacImageInteractionMode?
    @State private var extractSelection: MacExtractSelection?
    @State private var completedExtractRect: CGRect?
    @State private var textObjectSaveTask: Task<Void, Never>?
    @State private var hasPendingTextObjectSave = false
    @State private var imageObjectSaveTask: Task<Void, Never>?
    @State private var hasPendingImageObjectSave = false
    @State private var latexObjectSaveTask: Task<Void, Never>?
    @State private var hasPendingLatexObjectSave = false
    @State private var widgetObjectSaveTask: Task<Void, Never>?
    @State private var hasPendingWidgetObjectSave = false
    @State private var pagePreview: MacPDFPagePreview?
    @State private var penWidth: CGFloat = 5
    @State private var selectedTool: MacCanvasTool = .pen
    @State private var selectedPenPreset: MacPenPreset = .black

    private static let contentSize = CanvasBoardMetrics.defaultUsableSize
    private static let canvasInset: CGFloat = 180
    private static let canvasOrigin = CGPoint(x: canvasInset, y: canvasInset)
    private static let minimumZoomScale: CGFloat = 0.1
    private static let maximumZoomScale: CGFloat = 4
    private static let saveDebounce: Duration = .milliseconds(400)
    private static let textObjectSaveDebounce: Duration = .milliseconds(250)
    private static let strokeEraserHitMargin: CGFloat = 14
    private static let textResizeHandleSize: CGFloat = 18
    private static let minimumTextObjectSize = CGSize(width: 48, height: 32)

    var body: some View {
        ZStack(alignment: .topLeading) {
            MacZoomableCanvasView(
                contentSize: documentSize,
                initialViewportState: initialViewportState,
                viewportCommand: viewportCommand,
                minimumZoomScale: Self.minimumZoomScale,
                maximumZoomScale: Self.maximumZoomScale,
                fitRect: documentFitRect,
                onViewportStateChange: handleViewportStateChange,
                onInteractionBegan: onInteractionBegan,
                onCanvasPointBegan: beginCanvasInteraction,
                onCanvasPointChanged: updateCanvasInteraction,
                onCanvasPointEnded: endCanvasInteraction
            ) {
                ZStack(alignment: .topLeading) {
                    Color(red: 0.82, green: 0.92, blue: 1.0)
                        .ignoresSafeArea()

                    ZStack(alignment: .topLeading) {
                        Color.white

                        if let pagePreview {
                            MacPDFPageSurface(preview: pagePreview)
                        }

                        if !nonBlackStrokes.isEmpty {
                            Image(nsImage: committedDrawingImage(for: nonBlackStrokes))
                                .renderingMode(.original)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: Self.contentSize.width, height: Self.contentSize.height)
                                .allowsHitTesting(false)
                        }

                        MacCommittedBlackInkView(strokes: blackStrokes)
                            .allowsHitTesting(false)

                        MacImageObjectLayer(
                            imageObjects: imageObjects,
                            assetDirectoryURL: imageObjectAssetDirectoryURL,
                            selectedImageObjectID: selectedImageObjectID
                        )
                        .allowsHitTesting(false)

                        MacTextObjectLayer(
                            textObjects: textObjects,
                            selectedTextObjectID: selectedTextObjectID,
                            resizeHandleSize: Self.textResizeHandleSize
                        )
                        .allowsHitTesting(false)

                        WidgetCanvasOverlayView(
                            widgets: $widgetObjects,
                            viewport: macWidgetViewport,
                            canvasIdentity: drawingURL.path,
                            widgetAssetBaseURL: widgetAssetBaseURL,
                            scoreSheet: WidgetActivityScoreSheet(widgets: widgetObjects),
                            onEditWidget: onWidgetEditRequested,
                            allowsWidgetAuthoring: allowsWidgetAuthoring,
                            onWidgetInteractionChanged: { isInteracting in
                                if isInteracting {
                                    onInteractionBegan?()
                                }
                            },
                            onWidgetDisplayFrameChanged: { _, _ in },
                            onMathInputRequested: onWidgetMathInputRequested,
                            onImageInsertionRequested: onWidgetImageInsertionRequested,
                            showsTeacherDemoWebApplets: showsTeacherDemoWebApplets
                        )
                        .frame(width: Self.contentSize.width, height: Self.contentSize.height, alignment: .topLeading)

                        MacLiveStrokeView(
                            points: currentPoints,
                            lineWidth: penWidth,
                            color: selectedPenPreset.color
                        )
                        .allowsHitTesting(false)

                        if let extractSelection {
                            MacExtractSelectionView(rect: extractSelection.rect, isCompleted: false)
                                .allowsHitTesting(false)
                        } else if let completedExtractRect {
                            MacExtractSelectionView(rect: completedExtractRect, isCompleted: true)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(width: Self.contentSize.width, height: Self.contentSize.height)
                    .background(.white)
                    .overlay {
                        Rectangle()
                            .stroke(Color(red: 0.45, green: 0.68, blue: 0.98), lineWidth: 3)
                    }
                    .shadow(color: .black.opacity(0.12), radius: 16, y: 4)
                    .offset(x: Self.canvasOrigin.x, y: Self.canvasOrigin.y)
                }
                .frame(width: documentSize.width, height: documentSize.height)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .task(id: drawingURL) {
            drawing = (try? Self.loadDrawing(at: drawingURL)) ?? PKDrawing()
            strokeColorRecords = Self.loadStrokeColorRecords(at: strokeColorRecordsURL)
            textObjects = Self.loadTextObjects(at: textObjectsURL)
            imageObjects = CanvasImageObject.load(from: imageObjectsURL)
            latexObjects = CanvasLaTeXObject.load(from: latexObjectsURL)
            widgetObjects = WidgetObject.load(from: widgetObjectsURL)
            selectedTextObjectID = nil
            didLoad = true
            publishEditState()
            publishWidgetObjects()
        }
        .task(id: background) {
            pagePreview = Self.loadPagePreview(from: background)
        }
        .task(id: editCommand?.id) {
            applyEditCommandIfNeeded(editCommand)
        }
        .task(id: toolCommand?.id) {
            applyToolCommandIfNeeded(toolCommand)
        }
        .task(id: objectCommand?.id) {
            applyObjectCommandIfNeeded(objectCommand)
        }
        .onChange(of: drawing) { _, newDrawing in
            guard didLoad else { return }
            scheduleSave(of: newDrawing)
            publishEditState()
        }
        .onChange(of: imageObjects) { _, newImageObjects in
            guard didLoad else { return }
            scheduleImageObjectSave(newImageObjects)
        }
        .onChange(of: latexObjects) { _, newLatexObjects in
            guard didLoad else { return }
            scheduleLatexObjectSave(newLatexObjects)
        }
        .onChange(of: widgetObjects) { _, newWidgetObjects in
            guard didLoad else { return }
            scheduleWidgetObjectSave(newWidgetObjects)
            publishWidgetObjects()
        }
        .onChange(of: editCommand) { _, newCommand in
            applyEditCommandIfNeeded(newCommand)
        }
        .onChange(of: toolCommand) { _, newCommand in
            applyToolCommandIfNeeded(newCommand)
        }
        .onChange(of: objectCommand) { _, newCommand in
            applyObjectCommandIfNeeded(newCommand)
        }
        .onDisappear {
            flushPendingSave()
            flushPendingTextObjectSave()
            flushPendingImageObjectSave()
            flushPendingLatexObjectSave()
            flushPendingWidgetObjectSave()
        }
    }

    private var contentRect: CGRect {
        CGRect(origin: .zero, size: Self.contentSize)
    }

    private var canvasContentBounds: CGRect {
        contentRect.union(fitRect ?? contentRect)
    }

    private var documentSize: CGSize {
        CGSize(
            width: max(Self.contentSize.width, canvasContentBounds.maxX) + Self.canvasInset * 2,
            height: max(Self.contentSize.height, canvasContentBounds.maxY) + Self.canvasInset * 2
        )
    }

    private var documentFitRect: CGRect {
        canvasContentBounds.offsetBy(dx: Self.canvasOrigin.x, dy: Self.canvasOrigin.y)
    }

    private var textObjectsURL: URL {
        CanvasTextObject.sidecarURL(forDrawingURL: drawingURL)
    }

    private var imageObjectsURL: URL {
        CanvasImageObject.sidecarURL(forDrawingURL: drawingURL)
    }

    private var imageObjectAssetDirectoryURL: URL {
        CanvasImageObject.assetDirectoryURL(forDrawingURL: drawingURL)
    }

    private var latexObjectsURL: URL {
        CanvasLaTeXObject.sidecarURL(forDrawingURL: drawingURL)
    }

    private var widgetObjectsURL: URL {
        WidgetObject.sidecarURL(forDrawingURL: drawingURL)
    }

    private var strokeColorRecordsURL: URL {
        CanvasStrokeColorRecord.sidecarURL(forDrawingURL: drawingURL)
    }

    private var macWidgetViewport: WidgetCanvasViewport {
        WidgetCanvasViewport(
            zoomScale: 1,
            contentOffset: .zero,
            canvasOrigin: .zero
        )
    }

    private var selectedTextObject: CanvasTextObject? {
        guard let selectedTextObjectID else { return nil }
        return textObjects.first { $0.id == selectedTextObjectID }
    }

    private var selectedTextBinding: Binding<String> {
        Binding(
            get: {
                selectedTextObject?.text ?? ""
            },
            set: { newValue in
                updateSelectedTextObject { object in
                    object.text = newValue
                }
            }
        )
    }

    private var selectedFontSizeBinding: Binding<Double> {
        Binding(
            get: {
                Double(selectedTextObject?.fontSize ?? 32)
            },
            set: { newValue in
                updateSelectedTextObject { object in
                    object.fontSize = CGFloat(newValue)
                    object.height = max(object.height, CGFloat(newValue) * 1.6)
                }
            }
        )
    }

    private var blackStrokes: [PKStroke] {
        drawing.strokes.filter(isBlackStroke)
    }

    private var nonBlackStrokes: [PKStroke] {
        drawing.strokes.filter { !isBlackStroke($0) }
    }

    private func committedDrawingImage(for strokes: [PKStroke]) -> NSImage {
        let image = PKDrawing(strokes: strokes).image(from: contentRect, scale: 1)
        image.isTemplate = false
        return image
    }

    private func isBlackStroke(_ stroke: PKStroke) -> Bool {
        let color = stroke.ink.color.usingColorSpace(.deviceRGB) ?? stroke.ink.color
        return color.redComponent < 0.08
            && color.greenComponent < 0.08
            && color.blueComponent < 0.08
            && color.alphaComponent > 0.1
    }

    private var fitRect: CGRect? {
        var bounds = CanvasContentBounds.combinedBounds(
            drawingBounds: drawing.bounds,
            backgroundSize: pagePreview?.size,
            textObjects: textObjects
        )
        for image in imageObjects where image.frame.width > 0 && image.frame.height > 0 {
            bounds = bounds.map { $0.union(image.renderedBounds) } ?? image.renderedBounds
        }
        for widget in widgetObjects where widget.frame.width > 0 && widget.frame.height > 0 {
            bounds = bounds.map { $0.union(widget.frame) } ?? widget.frame
        }
        return bounds
    }

    private func clampedPoint(_ point: CGPoint) -> CGPoint {
        let canvasPoint = CGPoint(
            x: point.x - Self.canvasOrigin.x,
            y: point.y - Self.canvasOrigin.y
        )
        return CGPoint(
            x: min(max(canvasPoint.x, 0), Self.contentSize.width),
            y: min(max(canvasPoint.y, 0), Self.contentSize.height)
        )
    }

    private func beginCanvasInteraction(_ point: CGPoint) {
        let clampedPoint = clampedPoint(point)
        switch selectedTool {
        case .select:
            beginSelectionInteraction(at: clampedPoint)
        case .pen:
            clearObjectSelection()
            currentPoints = [clampedPoint]
        case .eraser:
            clearObjectSelection()
            eraseStroke(at: clampedPoint)
        case .text:
            beginTextInteraction(at: clampedPoint, createsIfMissing: true)
        case .extract:
            clearObjectSelection()
            extractSelection = MacExtractSelection(start: clampedPoint, current: clampedPoint)
            completedExtractRect = nil
        }
    }

    private func updateCanvasInteraction(_ point: CGPoint) {
        let clampedPoint = clampedPoint(point)
        switch selectedTool {
        case .select:
            updateSelectionInteraction(at: clampedPoint)
        case .pen:
            if currentPoints.last != clampedPoint {
                currentPoints.append(clampedPoint)
            }
        case .eraser:
            eraseStroke(at: clampedPoint)
        case .text:
            updateTextInteraction(at: clampedPoint)
        case .extract:
            extractSelection?.current = clampedPoint
        }
    }

    private func endCanvasInteraction() {
        switch selectedTool {
        case .select:
            if imageInteractionMode != nil {
                scheduleImageObjectSave(imageObjects)
            }
            textInteractionMode = nil
            imageInteractionMode = nil
        case .pen:
            commitCurrentStroke()
        case .eraser:
            currentPoints = []
        case .text:
            textInteractionMode = nil
        case .extract:
            finishExtractSelection()
        }
    }

    private func beginTextInteraction(at point: CGPoint, createsIfMissing: Bool) {
        if let selectedIndex = selectedTextObjectIndex,
           resizeHandleRect(for: textObjects[selectedIndex]).contains(point) {
            textInteractionMode = .resize(origin: CGPoint(
                x: textObjects[selectedIndex].x,
                y: textObjects[selectedIndex].y
            ))
            return
        }

        if let index = textObjectIndex(at: point) {
            selectedTextObjectID = textObjects[index].id
            textInteractionMode = .move(offset: CGSize(
                width: point.x - textObjects[index].x,
                height: point.y - textObjects[index].y
            ))
            return
        }

        guard createsIfMissing else {
            clearObjectSelection()
            return
        }

        var newObject = CanvasTextObject(
            text: "Text",
            x: min(point.x, Self.contentSize.width - 240),
            y: min(point.y, Self.contentSize.height - 72),
            width: 240,
            height: 72,
            fontSize: 32
        )
        selectedPenPreset.apply(to: &newObject)
        textObjects.append(newObject)
        selectedTextObjectID = newObject.id
        textInteractionMode = .move(offset: CGSize(width: 12, height: 12))
        scheduleTextObjectSave()
    }

    private func beginSelectionInteraction(at point: CGPoint) {
        if let selectedIndex = selectedTextObjectIndex,
           resizeHandleRect(for: textObjects[selectedIndex]).contains(point) {
            selectedImageObjectID = nil
            textInteractionMode = .resize(origin: CGPoint(x: textObjects[selectedIndex].x, y: textObjects[selectedIndex].y))
            return
        }

        if let textIndex = textObjectIndex(at: point) {
            selectedTextObjectID = textObjects[textIndex].id
            selectedImageObjectID = nil
            textInteractionMode = .move(offset: CGSize(
                width: point.x - textObjects[textIndex].x,
                height: point.y - textObjects[textIndex].y
            ))
            return
        }

        if let imageIndex = imageObjectIndex(at: point) {
            selectedImageObjectID = imageObjects[imageIndex].id
            selectedTextObjectID = nil
            imageInteractionMode = .move(offset: CGSize(
                width: point.x - imageObjects[imageIndex].x,
                height: point.y - imageObjects[imageIndex].y
            ))
            return
        }

        clearObjectSelection()
    }

    private func updateSelectionInteraction(at point: CGPoint) {
        if textInteractionMode != nil {
            updateTextInteraction(at: point)
            return
        }
        updateImageInteraction(at: point)
    }

    private func updateImageInteraction(at point: CGPoint) {
        guard let selectedImageObjectID,
              let imageInteractionMode,
              let index = imageObjects.firstIndex(where: { $0.id == selectedImageObjectID }) else {
            return
        }

        switch imageInteractionMode {
        case .move(let offset):
            imageObjects[index].x = min(
                max(point.x - offset.width, 0),
                Self.contentSize.width - imageObjects[index].width
            )
            imageObjects[index].y = min(
                max(point.y - offset.height, 0),
                Self.contentSize.height - imageObjects[index].height
            )
        }
    }

    private func updateTextInteraction(at point: CGPoint) {
        guard let selectedTextObjectID,
              let textInteractionMode,
              let index = textObjects.firstIndex(where: { $0.id == selectedTextObjectID }) else {
            return
        }

        switch textInteractionMode {
        case .move(let offset):
            textObjects[index].x = min(
                max(point.x - offset.width, 0),
                Self.contentSize.width - textObjects[index].width
            )
            textObjects[index].y = min(
                max(point.y - offset.height, 0),
                Self.contentSize.height - textObjects[index].height
            )
        case .resize(let origin):
            textObjects[index].width = min(
                max(point.x - origin.x, Self.minimumTextObjectSize.width),
                Self.contentSize.width - origin.x
            )
            textObjects[index].height = min(
                max(point.y - origin.y, Self.minimumTextObjectSize.height),
                Self.contentSize.height - origin.y
            )
        }
        scheduleTextObjectSave()
    }

    private func clearObjectSelection() {
        selectedTextObjectID = nil
        selectedImageObjectID = nil
        textInteractionMode = nil
        imageInteractionMode = nil
    }

    private var selectedTextObjectIndex: Int? {
        guard let selectedTextObjectID else { return nil }
        return textObjects.firstIndex { $0.id == selectedTextObjectID }
    }

    private func textObjectIndex(at point: CGPoint) -> Int? {
        textObjects.indices.reversed().first { index in
            textObjects[index].frame.insetBy(dx: -8, dy: -8).contains(point)
        }
    }

    private func imageObjectIndex(at point: CGPoint) -> Int? {
        imageObjects.indices.reversed().first { index in
            imageObjects[index].renderedBounds.insetBy(dx: -8, dy: -8).contains(point)
        }
    }

    private func resizeHandleRect(for object: CanvasTextObject) -> CGRect {
        CGRect(
            x: object.x + object.width - Self.textResizeHandleSize,
            y: object.y + object.height - Self.textResizeHandleSize,
            width: Self.textResizeHandleSize * 1.4,
            height: Self.textResizeHandleSize * 1.4
        )
    }

    private func updateSelectedTextObject(_ update: (inout CanvasTextObject) -> Void) {
        guard let selectedTextObjectID,
              let index = textObjects.firstIndex(where: { $0.id == selectedTextObjectID }) else {
            return
        }

        update(&textObjects[index])
        scheduleTextObjectSave()
    }

    private func applySelectedColor(_ preset: MacPenPreset) {
        selectedPenPreset = preset
        guard selectedTool == .text else { return }
        updateSelectedTextObject { object in
            preset.apply(to: &object)
        }
    }

    private func deleteSelectedTextObject() {
        guard let selectedTextObjectID,
              let index = textObjects.firstIndex(where: { $0.id == selectedTextObjectID }) else {
            return
        }

        textObjects.remove(at: index)
        self.selectedTextObjectID = nil
        scheduleTextObjectSave()
    }

    private func applyEditCommandIfNeeded(_ command: CanvasEditCommand?) {
        guard let command, appliedEditCommandID != command.id else { return }
        appliedEditCommandID = command.id

        switch command.action {
        case .undo:
            undoLastStroke()
        case .redo:
            break
        }
    }

    private func applyToolCommandIfNeeded(_ command: CanvasToolCommand?) {
        guard let command, appliedToolCommandID != command.id else { return }
        appliedToolCommandID = command.id

        switch command.action {
        case .pen(let color, let width), .fountainPen(let color, let width), .marker(let color, let width):
            selectedTool = .pen
            selectedPenPreset = MacPenPreset.closestPreset(to: color)
            penWidth = width
        case .eraser:
            selectedTool = .eraser
        case .text:
            selectedTool = .text
        case .select(let target, _, _, _):
            selectedTool = target == .region ? .extract : .select
        case .extractSelectionAsImageSticker:
            extractCompletedSelectionAsImage()
        case .idle, .copySelection, .pasteSelection, .duplicateSelection, .deleteSelection,
             .sendSelectionToNextSlide, .setExtractAction, .laser, .geometry, .cover:
            break
        }
    }

    private func finishExtractSelection() {
        guard let selection = extractSelection else { return }
        extractSelection = nil
        let rect = selection.rect.integral
        guard rect.width >= 8, rect.height >= 8 else {
            completedExtractRect = nil
            return
        }
        completedExtractRect = rect
        extractCompletedSelectionAsImage()
    }

    private func extractCompletedSelectionAsImage() {
        guard let rect = completedExtractRect,
              rect.width >= 8,
              rect.height >= 8,
              let pngData = snapshotPNGData(in: rect) else { return }
        let offsetFrame = rect.offsetBy(dx: 24, dy: 24)
        guard saveImageObject(pngData: pngData, frame: offsetFrame, isLocked: false) != nil else { return }
        completedExtractRect = nil
    }

    private func snapshotPNGData(in rect: CGRect) -> Data? {
        let scale: CGFloat = 2
        let pixelSize = CGSize(width: rect.width * scale, height: rect.height * scale)
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixelSize.width.rounded(.up)),
            pixelsHigh: Int(pixelSize.height.rounded(.up)),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        representation.size = pixelSize
        guard let graphicsContext = NSGraphicsContext(bitmapImageRep: representation) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        let context = graphicsContext.cgContext
        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -rect.minX, y: -rect.minY)
        drawSnapshotContent(in: context)
        context.restoreGState()
        NSGraphicsContext.restoreGraphicsState()

        return representation.representation(using: .png, properties: [:])
    }

    private func drawSnapshotContent(in context: CGContext) {
        NSColor.white.setFill()
        context.fill(contentRect)

        if let pagePreview,
           let document = PDFDocument(url: pagePreview.pdfURL),
           let page = document.page(at: pagePreview.pageIndex) {
            context.saveGState()
            context.translateBy(x: 0, y: pagePreview.size.height)
            context.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: context)
            context.restoreGState()
        }

        for imageObject in imageObjects {
            guard let image = NSImage(contentsOf: imageObjectAssetDirectoryURL.appendingPathComponent(imageObject.imageFileName)),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            context.saveGState()
            context.translateBy(x: imageObject.center.x, y: imageObject.center.y)
            context.rotate(by: imageObject.rotation)
            context.translateBy(x: -imageObject.width / 2, y: -imageObject.height / 2)
            context.draw(cgImage, in: CGRect(origin: .zero, size: CGSize(width: imageObject.width, height: imageObject.height)))
            context.restoreGState()
        }

        if !drawing.strokes.isEmpty, let inkImage = committedDrawingImage(for: drawing.strokes).cgImage(forProposedRect: nil, context: nil, hints: nil) {
            context.draw(inkImage, in: contentRect)
        }

        for textObject in textObjects {
            drawTextObject(textObject, in: context)
        }
    }

    private func drawTextObject(_ object: CanvasTextObject, in context: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        let font = NSFont.systemFont(ofSize: object.fontSize, weight: object.isBold ? .bold : .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(
                srgbRed: object.red,
                green: object.green,
                blue: object.blue,
                alpha: object.alpha
            ),
            .paragraphStyle: paragraph
        ]
        (object.text as NSString).draw(with: object.frame, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func applyObjectCommandIfNeeded(_ command: CanvasObjectCommand?) {
        guard let command, appliedObjectCommandID != command.id else { return }
        appliedObjectCommandID = command.id
        guard allowsWidgetAuthoring || command.action == .reloadObjectState else { return }

        switch command.action {
        case .insertText(let insertion):
            insertTextObject(insertion)
        case .insertImage(let insertion):
            insertImageObject(insertion)
        case .insertImageAtCanvasPoint(let insertion):
            insertDroppedImageObject(insertion)
        case .insertImageNearViewport(let insertion):
            insertViewportImageObject(insertion)
        case .insertImagesNearViewport(let insertions):
            for (index, insertion) in insertions.enumerated() {
                insertViewportImageObject(insertion, cascadeIndex: index)
            }
        case .insertLaTeX(let insertion):
            insertLaTeXObject(insertion)
        case .updateLaTeX(let update):
            updateLaTeXObject(update)
        case .insertWidget(let insertion):
            insertWidgetObject(insertion)
        case .updateWidget(let update):
            updateWidgetObject(update)
        case .updateText(let update):
            updateTextObject(update)
        case .delete(.text(let id)):
            deleteTextObject(id)
        case .delete(.image(let id)):
            deleteImageObject(id)
        case .clearSelection:
            selectedTextObjectID = nil
        case .reloadObjectState:
            textObjects = CanvasTextObject.load(from: textObjectsURL)
            imageObjects = CanvasImageObject.load(from: imageObjectsURL)
            latexObjects = CanvasLaTeXObject.load(from: latexObjectsURL)
            widgetObjects = WidgetObject.load(from: widgetObjectsURL)
            publishWidgetObjects()
        default:
            break
        }
    }

    private func insertTextObject(_ insertion: CanvasTextInsertion) {
        let text = insertion.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        onInteractionBegan?()
        let size = insertion.displaySize ?? CGSize(width: 360, height: max(insertion.fontSize * 1.8, 72))
        let origin = sourceOrigin(
            canvasPoint: insertion.canvasPoint,
            fallbackSourcePoint: insertion.sourcePoint,
            size: size
        )
        let object = CanvasTextObject(
            text: text,
            x: origin.x,
            y: origin.y,
            width: size.width,
            height: size.height,
            fontSize: insertion.fontSize,
            red: insertion.color.red,
            green: insertion.color.green,
            blue: insertion.color.blue,
            alpha: insertion.color.alpha,
            backgroundRed: insertion.backgroundColor?.red,
            backgroundGreen: insertion.backgroundColor?.green,
            backgroundBlue: insertion.backgroundColor?.blue,
            backgroundAlpha: insertion.backgroundColor?.alpha,
            isBold: insertion.isBold,
            isItalic: insertion.isItalic,
            isUnderlined: insertion.isUnderlined,
            fontName: insertion.fontName,
            librarySourceText: insertion.librarySourceText,
            hasRecordedLibraryDerivative: insertion.hasRecordedLibraryDerivative
        )
        textObjects.append(object)
        selectedTextObjectID = object.id
        scheduleTextObjectSave()
    }

    private func updateTextObject(_ update: CanvasTextUpdate) {
        let text = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              let index = textObjects.firstIndex(where: { $0.id == update.id }) else { return }
        onInteractionBegan?()
        textObjects[index].text = text
        textObjects[index].fontSize = update.fontSize
        if let color = update.color {
            textObjects[index].setColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        }
        if update.updatesBackgroundColor {
            if let backgroundColor = update.backgroundColor {
                textObjects[index].setBackgroundColor(
                    red: backgroundColor.red,
                    green: backgroundColor.green,
                    blue: backgroundColor.blue,
                    alpha: backgroundColor.alpha
                )
            } else {
                textObjects[index].clearBackgroundColor()
            }
        }
        textObjects[index].isBold = update.isBold
        textObjects[index].isItalic = update.isItalic
        textObjects[index].isUnderlined = update.isUnderlined
        textObjects[index].fontName = update.fontName
        if let hasRecordedLibraryDerivative = update.hasRecordedLibraryDerivative {
            textObjects[index].hasRecordedLibraryDerivative = hasRecordedLibraryDerivative
        }
        selectedTextObjectID = update.id
        scheduleTextObjectSave()
    }

    private func deleteTextObject(_ id: UUID) {
        textObjects.removeAll { $0.id == id }
        if selectedTextObjectID == id {
            selectedTextObjectID = nil
        }
        scheduleTextObjectSave()
    }

    private func insertImageObject(_ insertion: CanvasImageInsertion) {
        saveImageObject(
            pngData: insertion.pngData,
            imageFileExtension: insertion.imageFileExtension,
            frame: insertion.frame,
            isLocked: insertion.isLocked
        )
    }

    private func insertDroppedImageObject(_ insertion: CanvasDroppedImageInsertion) {
        let frame = centeredFrame(size: insertion.displaySize, center: insertion.canvasPoint, margin: 24)
        saveImageObject(
            pngData: insertion.pngData,
            imageFileExtension: insertion.imageFileExtension,
            frame: frame,
            isLocked: insertion.isLocked
        )
    }

    private func insertViewportImageObject(_ insertion: CanvasViewportImageInsertion, cascadeIndex: Int = 0) {
        var frame = sourceFrame(forViewportImageInsertion: insertion)
        let offset = CGFloat(cascadeIndex) * 24
        frame.origin.x += offset
        frame.origin.y += offset
        saveImageObject(
            pngData: insertion.pngData,
            imageFileExtension: insertion.imageFileExtension,
            frame: frame,
            isLocked: insertion.isLocked
        )
    }

    @discardableResult
    private func saveImageObject(
        pngData: Data,
        imageFileExtension: String = "png",
        frame: CGRect,
        isLocked: Bool
    ) -> CanvasImageObject? {
        let fileName = "\(UUID().uuidString).\(Self.imageFileExtension(for: pngData, preferredExtension: imageFileExtension))"
        let assetURL = imageObjectAssetDirectoryURL.appendingPathComponent(fileName)
        do {
            try FileManager.default.createDirectory(at: imageObjectAssetDirectoryURL, withIntermediateDirectories: true)
            try pngData.write(to: assetURL, options: .atomic)
        } catch {
            print("[Canvas] Mac image object save error: \(error)")
            return nil
        }

        onInteractionBegan?()
        let imageObject = CanvasImageObject(
            imageFileName: fileName,
            x: frame.minX,
            y: frame.minY,
            width: frame.width,
            height: frame.height,
            isLocked: isLocked ? true : nil
        )
        imageObjects.append(imageObject)
        return imageObject
    }

    private func insertLaTeXObject(_ insertion: CanvasLaTeXInsertion) {
        let frame: CGRect
        if let canvasPoint = insertion.canvasPoint {
            frame = centeredFrame(size: insertion.displaySize, center: canvasPoint, margin: insertion.margin)
        } else {
            frame = sourceFrame(forViewportImageInsertion: CanvasViewportImageInsertion(
                pngData: insertion.pngData,
                displaySize: insertion.displaySize,
                referenceRect: insertion.referenceRect,
                containerSize: insertion.containerSize,
                margin: insertion.margin
            ))
        }

        guard let imageObject = saveImageObject(
            pngData: insertion.pngData,
            imageFileExtension: "png",
            frame: frame,
            isLocked: false
        ) else { return }
        latexObjects.append(CanvasLaTeXObject(
            imageObjectID: imageObject.id,
            latexSource: insertion.latexSource,
            librarySourceLaTeX: insertion.librarySourceLaTeX,
            hasRecordedLibraryDerivative: insertion.hasRecordedLibraryDerivative
        ))
    }

    private func updateLaTeXObject(_ update: CanvasLaTeXUpdate) {
        guard let imageIndex = imageObjects.firstIndex(where: { $0.id == update.imageObjectID }),
              let latexIndex = latexObjects.firstIndex(where: { $0.imageObjectID == update.imageObjectID }) else { return }
        let oldFileName = imageObjects[imageIndex].imageFileName
        let newFileName = "\(UUID().uuidString).png"
        let assetURL = imageObjectAssetDirectoryURL.appendingPathComponent(newFileName)
        do {
            try FileManager.default.createDirectory(at: imageObjectAssetDirectoryURL, withIntermediateDirectories: true)
            try update.pngData.write(to: assetURL, options: .atomic)
        } catch {
            print("[Canvas] Mac LaTeX image update save error: \(error)")
            return
        }

        onInteractionBegan?()
        latexObjects[latexIndex].latexSource = update.latexSource
        if let hasRecordedLibraryDerivative = update.hasRecordedLibraryDerivative {
            latexObjects[latexIndex].hasRecordedLibraryDerivative = hasRecordedLibraryDerivative
        }
        imageObjects[imageIndex].imageFileName = newFileName
        let aspectRatio = max(update.displaySize.width, 1) / max(update.displaySize.height, 1)
        let center = imageObjects[imageIndex].center
        let height = max(imageObjects[imageIndex].height, 1)
        let width = max(height * aspectRatio, 1)
        imageObjects[imageIndex].x = center.x - width / 2
        imageObjects[imageIndex].y = center.y - height / 2
        imageObjects[imageIndex].width = width
        imageObjects[imageIndex].height = height
        if !imageObjects.contains(where: { $0.id != update.imageObjectID && $0.imageFileName == oldFileName }) {
            try? FileManager.default.removeItem(at: imageObjectAssetDirectoryURL.appendingPathComponent(oldFileName))
        }
    }

    private func deleteImageObject(_ id: UUID) {
        guard let index = imageObjects.firstIndex(where: { $0.id == id }) else { return }
        let fileName = imageObjects[index].imageFileName
        imageObjects.remove(at: index)
        latexObjects.removeAll { $0.imageObjectID == id }
        if !imageObjects.contains(where: { $0.imageFileName == fileName }) {
            try? FileManager.default.removeItem(at: imageObjectAssetDirectoryURL.appendingPathComponent(fileName))
        }
    }

    private func insertWidgetObject(_ insertion: CanvasWidgetInsertion) {
        onInteractionBegan?()
        var widgetObject = insertion.widgetObject
        widgetObject.frame = sourceFrame(forWidgetInsertion: insertion)
        widgetObjects.append(widgetObject)
    }

    private func updateWidgetObject(_ update: CanvasWidgetUpdate) {
        guard let index = widgetObjects.firstIndex(where: { $0.id == update.id }) else { return }
        onInteractionBegan?()
        widgetObjects[index].name = update.name
        widgetObjects[index].codeString = update.codeString
        widgetObjects[index].activityRuntimeState = update.resetsRuntimeState ? nil : widgetObjects[index].activityRuntimeState
        if let hasRecordedLibraryDerivative = update.hasRecordedLibraryDerivative {
            widgetObjects[index].hasRecordedLibraryDerivative = hasRecordedLibraryDerivative
        }
    }

    private func sourceOrigin(canvasPoint: CGPoint?, fallbackSourcePoint: CGPoint, size: CGSize) -> CGPoint {
        if let canvasPoint {
            return CGPoint(x: canvasPoint.x - size.width / 2, y: canvasPoint.y - size.height / 2)
        }
        return fallbackSourcePoint
    }

    private func centeredFrame(size: CGSize, center: CGPoint, margin: CGFloat) -> CGRect {
        let proposedOrigin = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        return clampedFrame(origin: proposedOrigin, size: size, margin: margin)
    }

    private func sourceFrame(forViewportImageInsertion insertion: CanvasViewportImageInsertion) -> CGRect {
        let containerSize = insertion.containerSize ?? Self.contentSize
        let margin = max(insertion.margin, 0)
        let size = CGSize(
            width: min(max(insertion.displaySize.width, 1), max(containerSize.width - margin * 2, 1)),
            height: min(max(insertion.displaySize.height, 1), max(containerSize.height - margin * 2, 1))
        )
        let proposedOrigin: CGPoint
        if let referenceRect = insertion.referenceRect {
            let canvasReferenceRect = referenceRect.offsetBy(dx: -Self.canvasOrigin.x, dy: -Self.canvasOrigin.y)
            proposedOrigin = CGPoint(
                x: canvasReferenceRect.midX - size.width / 2,
                y: canvasReferenceRect.midY - size.height / 2
            )
        } else {
            proposedOrigin = CGPoint(x: (Self.contentSize.width - size.width) / 2, y: (Self.contentSize.height - size.height) / 2)
        }
        return clampedFrame(origin: proposedOrigin, size: size, margin: margin)
    }

    private func clampedFrame(origin: CGPoint, size: CGSize, margin: CGFloat) -> CGRect {
        CGRect(
            x: min(max(origin.x, margin), max(margin, Self.contentSize.width - size.width - margin)),
            y: min(max(origin.y, margin), max(margin, Self.contentSize.height - size.height - margin)),
            width: size.width,
            height: size.height
        )
    }

    private static func normalizedImageFileExtension(_ fileExtension: String) -> String {
        let normalized = fileExtension
            .trimmingCharacters(in: CharacterSet(charactersIn: ".").union(.whitespacesAndNewlines))
            .lowercased()
        return normalized.isEmpty ? "png" : normalized
    }

    private static func imageFileExtension(for data: Data, preferredExtension: String) -> String {
        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "jpg"
        }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return "png"
        }
        return normalizedImageFileExtension(preferredExtension)
    }

    private func sourceFrame(forWidgetInsertion insertion: CanvasWidgetInsertion) -> CGRect {
        let size = insertion.displaySize
        let proposedOrigin: CGPoint
        if let canvasPoint = insertion.canvasPoint {
            proposedOrigin = CGPoint(
                x: canvasPoint.x - size.width / 2,
                y: canvasPoint.y - size.height / 2
            )
        } else if let referenceRect = insertion.referenceRect, let containerSize = insertion.containerSize {
            let canvasReferenceRect = referenceRect.offsetBy(dx: -Self.canvasOrigin.x, dy: -Self.canvasOrigin.y)
            let canvasContainerSize = CGSize(
                width: min(containerSize.width, Self.contentSize.width),
                height: min(containerSize.height, Self.contentSize.height)
            )
            proposedOrigin = CGPoint(
                x: (canvasContainerSize.width - size.width) / 2 + canvasReferenceRect.minX,
                y: (canvasContainerSize.height - size.height) / 2 + canvasReferenceRect.minY
            )
        } else {
            proposedOrigin = CGPoint(
                x: (Self.contentSize.width - size.width) / 2,
                y: (Self.contentSize.height - size.height) / 2
            )
        }

        return CGRect(
            x: min(max(proposedOrigin.x, insertion.margin), max(insertion.margin, Self.contentSize.width - size.width - insertion.margin)),
            y: min(max(proposedOrigin.y, insertion.margin), max(insertion.margin, Self.contentSize.height - size.height - insertion.margin)),
            width: size.width,
            height: size.height
        )
    }

    @MainActor
    private func handleViewportStateChange(_ state: CanvasViewportState) {
        onViewportStateChange?(state)
    }

    private func commitCurrentStroke() {
        defer { currentPoints = [] }
        guard selectedTool == .pen else { return }
        guard let stroke = makeStroke(from: currentPoints) else { return }
        strokeColorRecords.append(colorRecord(for: stroke))
        drawing = PKDrawing(strokes: drawing.strokes + [stroke])
    }

    private func makeStroke(from points: [CGPoint]) -> PKStroke? {
        guard let first = points.first else { return nil }
        var strokePoints = points
        while strokePoints.count < 4 {
            strokePoints.append(first)
        }

        let controlPoints = strokePoints.enumerated().map { index, location in
            PKStrokePoint(
                location: location,
                timeOffset: TimeInterval(index) / 60,
                size: CGSize(width: penWidth, height: penWidth),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }

        let path = PKStrokePath(controlPoints: controlPoints, creationDate: Date())
        let ink = PKInk(.pen, color: selectedPenPreset.nsColor)
        return PKStroke(ink: ink, path: path, transform: .identity, mask: nil)
    }

    private func colorRecord(for stroke: PKStroke) -> CanvasStrokeColorRecord {
        let components = selectedPenPreset.textColorComponents
        return CanvasStrokeColorRecord(
            creationTime: stroke.path.creationDate.timeIntervalSinceReferenceDate,
            red: components.red,
            green: components.green,
            blue: components.blue,
            alpha: components.alpha
        )
    }

    private func pruneStrokeColorRecords(for strokes: [PKStroke]) {
        let validKeys = Set(strokes.map { stroke in
            CanvasStrokeColorRecord.stableKey(
                for: stroke.path.creationDate.timeIntervalSinceReferenceDate
            )
        })
        strokeColorRecords = strokeColorRecords.filter { validKeys.contains($0.stableKey) }
    }

    private func eraseStroke(at point: CGPoint) {
        let remainingStrokes = drawing.strokes.filter { stroke in
            !stroke.renderBounds.insetBy(
                dx: -Self.strokeEraserHitMargin,
                dy: -Self.strokeEraserHitMargin
            )
            .contains(point)
        }

        guard remainingStrokes.count != drawing.strokes.count else { return }
        currentPoints = []
        pruneStrokeColorRecords(for: remainingStrokes)
        drawing = PKDrawing(strokes: remainingStrokes)
    }

    private func undoLastStroke() {
        guard !drawing.strokes.isEmpty else { return }
        let remainingStrokes = Array(drawing.strokes.dropLast())
        pruneStrokeColorRecords(for: remainingStrokes)
        drawing = PKDrawing(strokes: remainingStrokes)
    }

    private func clearDrawing() {
        guard !drawing.strokes.isEmpty else { return }
        strokeColorRecords = []
        drawing = PKDrawing()
    }

    private func publishEditState() {
        onEditStateChange?(CanvasEditState(canUndo: !drawing.strokes.isEmpty, canRedo: false))
    }

    private func scheduleSave(of newDrawing: PKDrawing) {
        hasPendingSave = true
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: Self.saveDebounce)
            guard !Task.isCancelled else { return }
            save(newDrawing, to: drawingURL)
            hasPendingSave = false
        }
    }

    private func scheduleTextObjectSave() {
        hasPendingTextObjectSave = true
        textObjectSaveTask?.cancel()
        textObjectSaveTask = Task { @MainActor in
            try? await Task.sleep(for: Self.textObjectSaveDebounce)
            guard !Task.isCancelled else { return }
            saveTextObjects(textObjects, to: textObjectsURL)
            hasPendingTextObjectSave = false
        }
    }

    private func scheduleImageObjectSave(_ newImageObjects: [CanvasImageObject]) {
        hasPendingImageObjectSave = true
        imageObjectSaveTask?.cancel()
        imageObjectSaveTask = Task { @MainActor in
            try? await Task.sleep(for: Self.textObjectSaveDebounce)
            guard !Task.isCancelled else { return }
            saveImageObjects(newImageObjects, to: imageObjectsURL)
            hasPendingImageObjectSave = false
        }
    }

    private func scheduleLatexObjectSave(_ newLatexObjects: [CanvasLaTeXObject]) {
        hasPendingLatexObjectSave = true
        latexObjectSaveTask?.cancel()
        latexObjectSaveTask = Task { @MainActor in
            try? await Task.sleep(for: Self.textObjectSaveDebounce)
            guard !Task.isCancelled else { return }
            saveLatexObjects(newLatexObjects, to: latexObjectsURL)
            hasPendingLatexObjectSave = false
        }
    }

    private func scheduleWidgetObjectSave(_ newWidgetObjects: [WidgetObject]) {
        hasPendingWidgetObjectSave = true
        widgetObjectSaveTask?.cancel()
        widgetObjectSaveTask = Task { @MainActor in
            try? await Task.sleep(for: Self.textObjectSaveDebounce)
            guard !Task.isCancelled else { return }
            saveWidgetObjects(newWidgetObjects, to: widgetObjectsURL)
            hasPendingWidgetObjectSave = false
        }
    }

    private func flushPendingSave() {
        saveTask?.cancel()
        saveTask = nil
        guard hasPendingSave else { return }
        save(drawing, to: drawingURL)
        hasPendingSave = false
    }

    private func flushPendingTextObjectSave() {
        textObjectSaveTask?.cancel()
        textObjectSaveTask = nil
        guard hasPendingTextObjectSave else { return }
        saveTextObjects(textObjects, to: textObjectsURL)
        hasPendingTextObjectSave = false
    }

    private func flushPendingImageObjectSave() {
        imageObjectSaveTask?.cancel()
        imageObjectSaveTask = nil
        guard hasPendingImageObjectSave else { return }
        saveImageObjects(imageObjects, to: imageObjectsURL)
        hasPendingImageObjectSave = false
    }

    private func flushPendingLatexObjectSave() {
        latexObjectSaveTask?.cancel()
        latexObjectSaveTask = nil
        guard hasPendingLatexObjectSave else { return }
        saveLatexObjects(latexObjects, to: latexObjectsURL)
        hasPendingLatexObjectSave = false
    }

    private func flushPendingWidgetObjectSave() {
        widgetObjectSaveTask?.cancel()
        widgetObjectSaveTask = nil
        guard hasPendingWidgetObjectSave else { return }
        saveWidgetObjects(widgetObjects, to: widgetObjectsURL)
        hasPendingWidgetObjectSave = false
    }

    private static func loadDrawing(at url: URL) throws -> PKDrawing {
        let data = try Data(contentsOf: url)
        return try PKDrawing(data: data)
    }

    private static func loadTextObjects(at url: URL) -> [CanvasTextObject] {
        CanvasTextObject.load(from: url)
    }

    private static func loadStrokeColorRecords(at url: URL) -> [CanvasStrokeColorRecord] {
        CanvasStrokeColorRecord.load(from: url)
    }

    private func save(_ drawing: PKDrawing, to url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let records = prunedStrokeColorRecords(for: drawing.strokes)
            try drawing.dataRepresentation().write(to: url, options: .atomic)
            try CanvasStrokeColorRecord.save(records, to: strokeColorRecordsURL)
            strokeColorRecords = records
        } catch {
            print("[Canvas] Mac save error: \(error)")
        }
    }

    private func prunedStrokeColorRecords(for strokes: [PKStroke]) -> [CanvasStrokeColorRecord] {
        let validKeys = Set(strokes.map { stroke in
            CanvasStrokeColorRecord.stableKey(
                for: stroke.path.creationDate.timeIntervalSinceReferenceDate
            )
        })
        return strokeColorRecords.filter { validKeys.contains($0.stableKey) }
    }

    private func saveTextObjects(_ textObjects: [CanvasTextObject], to url: URL) {
        do {
            try CanvasTextObject.save(textObjects, to: url)
        } catch {
            print("[Canvas] text object save error: \(error)")
        }
    }

    private func saveImageObjects(_ imageObjects: [CanvasImageObject], to url: URL) {
        do {
            try CanvasImageObject.save(imageObjects, to: url)
            onCanvasObjectStateChange?()
        } catch {
            print("[Canvas] image object save error: \(error)")
        }
    }

    private func saveLatexObjects(_ latexObjects: [CanvasLaTeXObject], to url: URL) {
        do {
            try CanvasLaTeXObject.save(latexObjects, to: url)
            onCanvasObjectStateChange?()
        } catch {
            print("[Canvas] LaTeX object save error: \(error)")
        }
    }

    private func saveWidgetObjects(_ widgetObjects: [WidgetObject], to url: URL) {
        do {
            try WidgetObject.save(widgetObjects, to: url)
            onCanvasObjectStateChange?()
        } catch {
            print("[Canvas] widget object save error: \(error)")
        }
    }

    private func publishWidgetObjects() {
        onWidgetObjectsChange?(
            widgetObjects,
            macWidgetViewport,
            Self.contentSize,
            drawingURL.path
        )
    }

    private static func loadPagePreview(from background: CanvasBackground?) -> MacPDFPagePreview? {
        guard let background,
              let document = PDFDocument(url: background.pdfURL),
              let page = document.page(at: background.pageIndex) else {
            return nil
        }

        let pageBounds = page.bounds(for: .mediaBox)
        return MacPDFPagePreview(
            pdfURL: background.pdfURL,
            pageIndex: background.pageIndex,
            size: pageBounds.size
        )
    }
}

private struct MacPDFPagePreview: Equatable {
    let pdfURL: URL
    let pageIndex: Int
    let size: CGSize

    var frame: CGRect {
        CGRect(origin: .zero, size: size)
    }
}

private struct MacZoomableCanvasView<Content: View>: NSViewRepresentable {
    let contentSize: CGSize
    let initialViewportState: CanvasViewportState?
    let viewportCommand: CanvasViewportCommand?
    let minimumZoomScale: CGFloat
    let maximumZoomScale: CGFloat
    let fitRect: CGRect?
    let onViewportStateChange: (@MainActor (CanvasViewportState) -> Void)?
    let onInteractionBegan: (@MainActor () -> Void)?
    let onCanvasPointBegan: (@MainActor (CGPoint) -> Void)?
    let onCanvasPointChanged: (@MainActor (CGPoint) -> Void)?
    let onCanvasPointEnded: (@MainActor () -> Void)?
    @ViewBuilder let content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.contentView = MacCenteringClipView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(calibratedRed: 0.82, green: 0.92, blue: 1.0, alpha: 1)
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = minimumZoomScale
        scrollView.maxMagnification = maximumZoomScale
        scrollView.magnification = initialViewportState?.zoomScale ?? 1
        scrollView.usesPredominantAxisScrolling = false
        scrollView.automaticallyAdjustsContentInsets = false

        let hostingView = MacCanvasDocumentView(
            rootView: content(),
            onCanvasPointBegan: onCanvasPointBegan,
            onCanvasPointChanged: onCanvasPointChanged,
            onCanvasPointEnded: onCanvasPointEnded,
            onInteractionBegan: onInteractionBegan
        )
        hostingView.frame = CGRect(origin: .zero, size: contentSize)
        scrollView.documentView = hostingView

        scrollView.contentView.postsBoundsChangedNotifications = true
        context.coordinator.hostingView = hostingView
        context.coordinator.scrollView = scrollView
        context.coordinator.observe(scrollView)

        DispatchQueue.main.async {
            context.coordinator.applyInitialViewportIfNeeded()
            context.coordinator.publishViewportState()
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.hostingView?.onCanvasPointBegan = onCanvasPointBegan
        context.coordinator.hostingView?.onCanvasPointChanged = onCanvasPointChanged
        context.coordinator.hostingView?.onCanvasPointEnded = onCanvasPointEnded
        context.coordinator.hostingView?.onInteractionBegan = onInteractionBegan

        scrollView.minMagnification = minimumZoomScale
        scrollView.maxMagnification = maximumZoomScale

        let rootView = content()
        let frame = CGRect(origin: .zero, size: contentSize)
        let hostingView = context.coordinator.hostingView
        DispatchQueue.main.async {
            hostingView?.rootView = rootView
            hostingView?.frame = frame
        }

        if let viewportCommand {
            context.coordinator.apply(viewportCommand)
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: MacZoomableCanvasView
        weak var scrollView: NSScrollView?
        weak var hostingView: MacCanvasDocumentView<Content>?
        private var boundsObserver: NSObjectProtocol?
        private var magnifyObserver: NSObjectProtocol?
        private var didApplyInitialViewport = false
        private var lastCommandID: UUID?

        init(_ parent: MacZoomableCanvasView) {
            self.parent = parent
        }

        func stopObserving() {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
                self.boundsObserver = nil
            }
            if let magnifyObserver {
                NotificationCenter.default.removeObserver(magnifyObserver)
                self.magnifyObserver = nil
            }
        }

        func observe(_ scrollView: NSScrollView) {
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.parent.onInteractionBegan?()
                    self?.publishViewportState()
                }
            }

            magnifyObserver = NotificationCenter.default.addObserver(
                forName: NSScrollView.didEndLiveMagnifyNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.parent.onInteractionBegan?()
                    self?.publishViewportState()
                }
            }
        }

        func applyInitialViewportIfNeeded() {
            guard !didApplyInitialViewport, let scrollView else { return }
            didApplyInitialViewport = true

            if let fitRect = parent.fitRect, !fitRect.isEmpty {
                scrollView.magnify(toFit: fitRect.insetBy(dx: -80, dy: -80))
                scrollView.contentView.needsDisplay = true
                scrollView.reflectScrolledClipView(scrollView.contentView)
                return
            }

            guard let initialViewportState = parent.initialViewportState else { return }

            let zoomScale = clampedZoom(initialViewportState.zoomScale)
            scrollView.magnification = zoomScale
            scrollView.contentView.scroll(to: initialViewportState.contentOffset)
            scrollView.contentView.needsDisplay = true
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        func apply(_ command: CanvasViewportCommand) {
            guard command.id != lastCommandID, let scrollView else { return }
            lastCommandID = command.id

            Task { @MainActor [weak self] in
                await Task.yield()
                self?.parent.onInteractionBegan?()
            }

            switch command.action {
            case .zoomIn:
                zoom(scrollView, by: 1.25)
            case .zoomOut:
                zoom(scrollView, by: 0.8)
            case .reset:
                scrollView.magnification = 1
                scrollView.contentView.scroll(to: .zero)
                scrollView.contentView.needsDisplay = true
                scrollView.reflectScrolledClipView(scrollView.contentView)
            case .fitToViewfinder:
                guard let fitRect = parent.fitRect, !fitRect.isEmpty else { return }
                scrollView.magnify(toFit: fitRect.insetBy(dx: -80, dy: -80))
                scrollView.contentView.needsDisplay = true
            }

            publishViewportStateAfterViewUpdate()
        }

        func publishViewportState() {
            guard let scrollView else { return }
            parent.onViewportStateChange?(viewportState(from: scrollView))
        }

        private func publishViewportStateAfterViewUpdate() {
            guard let scrollView else { return }
            let state = viewportState(from: scrollView)
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.parent.onViewportStateChange?(state)
            }
        }

        private func viewportState(from scrollView: NSScrollView) -> CanvasViewportState {
            CanvasViewportState(
                zoomScale: scrollView.magnification,
                contentOffset: scrollView.documentVisibleRect.origin,
                minimumZoomScale: parent.minimumZoomScale,
                maximumZoomScale: parent.maximumZoomScale
            )
        }

        private func zoom(_ scrollView: NSScrollView, by multiplier: CGFloat) {
            let targetZoom = clampedZoom(scrollView.magnification * multiplier)
            let visibleRect = scrollView.documentVisibleRect
            let center = CGPoint(x: visibleRect.midX, y: visibleRect.midY)
            scrollView.setMagnification(targetZoom, centeredAt: center)
            scrollView.contentView.needsDisplay = true
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func clampedZoom(_ zoomScale: CGFloat) -> CGFloat {
            min(max(zoomScale, parent.minimumZoomScale), parent.maximumZoomScale)
        }
    }
}

private final class MacCenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var bounds = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return bounds }

        let documentFrame = documentView.frame
        if bounds.width > documentFrame.width {
            bounds.origin.x = documentFrame.midX - bounds.width / 2
        }
        if bounds.height > documentFrame.height {
            bounds.origin.y = documentFrame.midY - bounds.height / 2
        }
        return bounds
    }
}

@MainActor
private final class MacCanvasDocumentView<Content: View>: NSHostingView<Content> {
    var onCanvasPointBegan: (@MainActor (CGPoint) -> Void)?
    var onCanvasPointChanged: (@MainActor (CGPoint) -> Void)?
    var onCanvasPointEnded: (@MainActor () -> Void)?
    var onInteractionBegan: (@MainActor () -> Void)?

    override var acceptsFirstResponder: Bool { true }

    init(
        rootView: Content,
        onCanvasPointBegan: (@MainActor (CGPoint) -> Void)?,
        onCanvasPointChanged: (@MainActor (CGPoint) -> Void)?,
        onCanvasPointEnded: (@MainActor () -> Void)?,
        onInteractionBegan: (@MainActor () -> Void)?
    ) {
        self.onCanvasPointBegan = onCanvasPointBegan
        self.onCanvasPointChanged = onCanvasPointChanged
        self.onCanvasPointEnded = onCanvasPointEnded
        self.onInteractionBegan = onInteractionBegan
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init(rootView: Content) {
        fatalError("Use init(rootView:onDrawingPointChanged:onDrawingEnded:onInteractionBegan:)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        onInteractionBegan?()
        onCanvasPointBegan?(canvasPoint(from: event))
    }

    override func mouseDragged(with event: NSEvent) {
        onCanvasPointChanged?(canvasPoint(from: event))
    }

    override func mouseUp(with event: NSEvent) {
        onCanvasPointChanged?(canvasPoint(from: event))
        onCanvasPointEnded?()
    }

    private func canvasPoint(from event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }
}

private struct MacPDFPageSurface: View {
    let preview: MacPDFPagePreview

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(.white)
                .frame(width: preview.size.width, height: preview.size.height)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                .overlay {
                    Rectangle()
                        .stroke(.black.opacity(0.22), lineWidth: 1)
                }

            MacPDFPageVectorView(preview: preview)
                .frame(width: preview.size.width, height: preview.size.height)
                .allowsHitTesting(false)
        }
    }
}

private struct MacPDFPageVectorView: NSViewRepresentable {
    let preview: MacPDFPagePreview

    func makeNSView(context: Context) -> MacPDFPageDrawingView {
        MacPDFPageDrawingView(preview: preview)
    }

    func updateNSView(_ nsView: MacPDFPageDrawingView, context: Context) {
        nsView.preview = preview
    }
}

private final class MacPDFPageDrawingView: NSView {
    var preview: MacPDFPagePreview {
        didSet {
            if oldValue != preview {
                loadPage()
            }
        }
    }

    private var page: PDFPage?
    private var pageBounds: CGRect?

    init(preview: MacPDFPagePreview) {
        self.preview = preview
        super.init(frame: CGRect(origin: .zero, size: preview.size))
        wantsLayer = true
        layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        loadPage()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.saveGState()
        NSColor.white.setFill()
        context.fill(bounds)
        context.restoreGState()

        guard let page, let pageBounds else { return }

        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: -pageBounds.minX, y: -pageBounds.minY)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()
    }

    private func loadPage() {
        guard let document = PDFDocument(url: preview.pdfURL),
              let page = document.page(at: preview.pageIndex) else {
            self.page = nil
            pageBounds = nil
            needsDisplay = true
            return
        }

        self.page = page
        pageBounds = page.bounds(for: .mediaBox)
        needsDisplay = true
    }
}

private struct MacLiveStrokeView: View {
    let points: [CGPoint]
    let lineWidth: CGFloat
    let color: Color

    var body: some View {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
        .stroke(
            color,
            style: StrokeStyle(
                lineWidth: lineWidth,
                lineCap: .round,
                lineJoin: .round
            )
        )
    }
}

private struct MacExtractSelectionView: View {
    let rect: CGRect
    let isCompleted: Bool

    var body: some View {
        Rectangle()
            .fill(Color.blue.opacity(isCompleted ? 0.08 : 0.12))
            .frame(width: rect.width, height: rect.height)
            .overlay {
                Rectangle()
                    .stroke(
                        Color.blue.opacity(isCompleted ? 0.85 : 0.95),
                        style: StrokeStyle(lineWidth: 2, dash: [8, 5])
                    )
            }
            .position(x: rect.midX, y: rect.midY)
    }
}

private struct MacImageObjectLayer: View {
    let imageObjects: [CanvasImageObject]
    let assetDirectoryURL: URL
    let selectedImageObjectID: UUID?

    var body: some View {
        ForEach(imageObjects) { object in
            if let image = NSImage(contentsOf: assetDirectoryURL.appendingPathComponent(object.imageFileName)) {
                let isSelected = selectedImageObjectID == object.id
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: object.width, height: object.height)
                    .overlay {
                        Rectangle()
                            .stroke(
                                isSelected ? Color.blue : Color.clear,
                                style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                            )
                    }
                    .rotationEffect(.radians(Double(object.rotation)))
                    .position(x: object.center.x, y: object.center.y)
            }
        }
    }
}

private struct MacTextObjectLayer: View {
    let textObjects: [CanvasTextObject]
    let selectedTextObjectID: UUID?
    let resizeHandleSize: CGFloat

    var body: some View {
        ForEach(textObjects) { object in
            let isSelected = selectedTextObjectID == object.id
            Text(object.text.isEmpty ? "Text" : object.text)
                .font(.system(size: object.fontSize))
                .fontWeight(object.isBold ? .bold : .regular)
                .conditionallyItalic(object.isItalic)
                .underline(object.isUnderlined)
                .foregroundStyle(textColor(for: object))
                .lineLimit(nil)
                .frame(width: object.width, height: object.height, alignment: .topLeading)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(backgroundColor(for: object) ?? Color.clear)
                )
                .overlay(alignment: .bottomTrailing) {
                    if isSelected {
                        ResizeHandle(size: resizeHandleSize)
                            .offset(x: resizeHandleSize / 2, y: resizeHandleSize / 2)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(
                            isSelected ? Color.blue : Color.clear,
                            style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                        )
                )
                .position(
                    x: object.x + object.width / 2,
                    y: object.y + object.height / 2
                )
        }
    }

    private func textColor(for object: CanvasTextObject) -> Color {
        Color(
            red: Double(object.red),
            green: Double(object.green),
            blue: Double(object.blue),
            opacity: Double(object.alpha)
        )
    }

    private func backgroundColor(for object: CanvasTextObject) -> Color? {
        guard let background = object.backgroundColorComponents else { return nil }
        return Color(
            red: Double(background.red),
            green: Double(background.green),
            blue: Double(background.blue),
            opacity: Double(background.alpha)
        )
    }

    private struct ResizeHandle: View {
        let size: CGFloat

        var body: some View {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white)
                .frame(width: size, height: size)
                .overlay {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.blue, lineWidth: 2)
                }
                .overlay {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: max(size * 0.45, 8), weight: .semibold))
                        .foregroundStyle(Color.blue)
                }
        }
    }
}

private extension View {
    @ViewBuilder
    func conditionallyItalic(_ isItalic: Bool) -> some View {
        if isItalic {
            self.italic()
        } else {
            self
        }
    }
}

private struct MacCommittedBlackInkView: View {
    let strokes: [PKStroke]

    var body: some View {
        Canvas { context, _ in
            for stroke in strokes {
                let points = Array(stroke.path)
                guard let first = points.first else { continue }

                var path = Path()
                path.move(to: first.location.applying(stroke.transform))
                for point in points.dropFirst() {
                    path.addLine(to: point.location.applying(stroke.transform))
                }

                let lineWidth = max(first.size.width, first.size.height, 1)
                context.stroke(
                    path,
                    with: .color(.black),
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
        }
    }
}

private struct MacPrepToolbar: View {
    let canUndo: Bool
    let canClear: Bool
    @Binding var selectedTool: MacCanvasTool
    @Binding var selectedPenPreset: MacPenPreset
    @Binding var penWidth: CGFloat
    @Binding var selectedText: String
    @Binding var selectedFontSize: Double
    let applySelectedColor: (MacPenPreset) -> Void
    let deleteSelectedText: () -> Void
    let undo: () -> Void
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Picker("Tool", selection: $selectedTool) {
                ForEach(MacCanvasTool.allCases) { tool in
                    Label(tool.title, systemImage: tool.systemImage)
                        .tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 170)
            .help("Drawing tool")

            Divider()
                .frame(height: 22)

            Button(action: undo) {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!canUndo)
            .help("Undo last stroke")

            Button(role: .destructive, action: clear) {
                Image(systemName: "trash")
            }
            .disabled(!canClear)
            .help("Clear slide ink")

            Divider()
                .frame(height: 22)

            HStack(spacing: 6) {
                ForEach(MacPenPreset.allCases) { preset in
                    Button {
                        applySelectedColor(preset)
                    } label: {
                        Circle()
                            .fill(preset.color)
                            .frame(width: 18, height: 18)
                            .overlay {
                                Circle()
                                    .stroke(.primary.opacity(selectedPenPreset == preset ? 0.85 : 0.25), lineWidth: selectedPenPreset == preset ? 2 : 1)
                            }
                            .padding(3)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedTool == .eraser)
                    .help(selectedTool == .text ? "Set selected text to \(preset.title.lowercased())" : preset.title)
                }
            }

            Divider()
                .frame(height: 22)

            Image(systemName: "pencil.tip")
                .foregroundStyle(.secondary)

            Slider(value: $penWidth, in: 2...18, step: 1)
                .frame(width: 120)
                .help("Pen width")
                .disabled(selectedTool != .pen)

            if selectedTool == .text {
                Divider()
                    .frame(height: 22)

                TextField("Text", text: $selectedText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .help("Selected text")

                Slider(value: $selectedFontSize, in: 12...96, step: 1)
                    .frame(width: 120)
                    .help("Text size")

                Button(role: .destructive, action: deleteSelectedText) {
                    Image(systemName: "trash")
                }
                .disabled(selectedText.isEmpty)
                .help("Delete selected text")
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

#endif
