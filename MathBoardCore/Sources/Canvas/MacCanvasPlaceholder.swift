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

private enum MacCanvasTool: String, CaseIterable, Identifiable {
    case pen
    case eraser
    case text

    var id: Self { self }

    var title: String {
        switch self {
        case .pen:
            return "Pen"
        case .eraser:
            return "Eraser"
        case .text:
            return "Text"
        }
    }

    var systemImage: String {
        switch self {
        case .pen:
            return "pencil.tip"
        case .eraser:
            return "eraser"
        case .text:
            return "textformat"
        }
    }
}

private enum MacTextInteractionMode: Equatable {
    case move(offset: CGSize)
    case resize(origin: CGPoint)
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
}

struct MacCanvasPlaceholder: View {
    let drawingURL: URL
    let background: CanvasBackground?
    let initialViewportState: CanvasViewportState?
    let viewportCommand: CanvasViewportCommand?
    let onViewportStateChange: (@MainActor (CanvasViewportState) -> Void)?
    let onInteractionBegan: (@MainActor () -> Void)?

    @State private var drawing = PKDrawing()
    @State private var didLoad = false
    @State private var saveTask: Task<Void, Never>?
    @State private var hasPendingSave = false
    @State private var currentPoints: [CGPoint] = []
    @State private var strokeColorRecords: [CanvasStrokeColorRecord] = []
    @State private var textObjects: [CanvasTextObject] = []
    @State private var selectedTextObjectID: UUID?
    @State private var textInteractionMode: MacTextInteractionMode?
    @State private var textObjectSaveTask: Task<Void, Never>?
    @State private var hasPendingTextObjectSave = false
    @State private var pagePreview: MacPDFPagePreview?
    @State private var penWidth: CGFloat = 5
    @State private var selectedTool: MacCanvasTool = .pen
    @State private var selectedPenPreset: MacPenPreset = .black

    private static let contentSize = CGSize(width: 2400, height: 1800)
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
                contentSize: Self.contentSize,
                initialViewportState: initialViewportState,
                viewportCommand: viewportCommand,
                minimumZoomScale: Self.minimumZoomScale,
                maximumZoomScale: Self.maximumZoomScale,
                fitRect: fitRect,
                onViewportStateChange: handleViewportStateChange,
                onInteractionBegan: onInteractionBegan,
                onCanvasPointBegan: beginCanvasInteraction,
                onCanvasPointChanged: updateCanvasInteraction,
                onCanvasPointEnded: endCanvasInteraction
            ) {
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

                    MacTextObjectLayer(
                        textObjects: textObjects,
                        selectedTextObjectID: selectedTextObjectID,
                        resizeHandleSize: Self.textResizeHandleSize
                    )
                    .allowsHitTesting(false)

                    MacLiveStrokeView(
                        points: currentPoints,
                        lineWidth: penWidth,
                        color: selectedPenPreset.color
                    )
                        .allowsHitTesting(false)
                }
                .frame(width: Self.contentSize.width, height: Self.contentSize.height)
            }
            .background(Color(nsColor: .windowBackgroundColor))

            MacPrepToolbar(
                canUndo: !drawing.strokes.isEmpty,
                canClear: !drawing.strokes.isEmpty,
                selectedTool: $selectedTool,
                selectedPenPreset: $selectedPenPreset,
                penWidth: $penWidth,
                selectedText: selectedTextBinding,
                selectedFontSize: selectedFontSizeBinding,
                applySelectedColor: applySelectedColor,
                deleteSelectedText: deleteSelectedTextObject,
                undo: undoLastStroke,
                clear: clearDrawing
            )
            .padding(12)
        }
        .task(id: drawingURL) {
            drawing = (try? Self.loadDrawing(at: drawingURL)) ?? PKDrawing()
            strokeColorRecords = Self.loadStrokeColorRecords(at: strokeColorRecordsURL)
            textObjects = Self.loadTextObjects(at: textObjectsURL)
            selectedTextObjectID = nil
            didLoad = true
        }
        .task(id: background) {
            pagePreview = Self.loadPagePreview(from: background)
        }
        .onChange(of: drawing) { _, newDrawing in
            guard didLoad else { return }
            scheduleSave(of: newDrawing)
        }
        .onDisappear {
            flushPendingSave()
            flushPendingTextObjectSave()
        }
    }

    private var contentRect: CGRect {
        CGRect(origin: .zero, size: Self.contentSize)
    }

    private var textObjectsURL: URL {
        CanvasTextObject.sidecarURL(forDrawingURL: drawingURL)
    }

    private var strokeColorRecordsURL: URL {
        CanvasStrokeColorRecord.sidecarURL(forDrawingURL: drawingURL)
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
        CanvasContentBounds.combinedBounds(
            drawingBounds: drawing.bounds,
            backgroundSize: pagePreview?.size,
            textObjects: textObjects
        )
    }

    private func clampedPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), Self.contentSize.width),
            y: min(max(point.y, 0), Self.contentSize.height)
        )
    }

    private func beginCanvasInteraction(_ point: CGPoint) {
        let clampedPoint = clampedPoint(point)
        switch selectedTool {
        case .pen:
            selectedTextObjectID = nil
            currentPoints = [clampedPoint]
        case .eraser:
            selectedTextObjectID = nil
            eraseStroke(at: clampedPoint)
        case .text:
            beginTextInteraction(at: clampedPoint)
        }
    }

    private func updateCanvasInteraction(_ point: CGPoint) {
        let clampedPoint = clampedPoint(point)
        switch selectedTool {
        case .pen:
            if currentPoints.last != clampedPoint {
                currentPoints.append(clampedPoint)
            }
        case .eraser:
            eraseStroke(at: clampedPoint)
        case .text:
            updateTextInteraction(at: clampedPoint)
        }
    }

    private func endCanvasInteraction() {
        switch selectedTool {
        case .pen:
            commitCurrentStroke()
        case .eraser:
            currentPoints = []
        case .text:
            textInteractionMode = nil
        }
    }

    private func beginTextInteraction(at point: CGPoint) {
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

    private var selectedTextObjectIndex: Int? {
        guard let selectedTextObjectID else { return nil }
        return textObjects.firstIndex { $0.id == selectedTextObjectID }
    }

    private func textObjectIndex(at point: CGPoint) -> Int? {
        textObjects.indices.reversed().first { index in
            textObjects[index].frame.insetBy(dx: -8, dy: -8).contains(point)
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
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .windowBackgroundColor
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
                self?.parent.onInteractionBegan?()
                self?.publishViewportState()
            }

            magnifyObserver = NotificationCenter.default.addObserver(
                forName: NSScrollView.didEndLiveMagnifyNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                self?.parent.onInteractionBegan?()
                self?.publishViewportState()
            }
        }

        func applyInitialViewportIfNeeded() {
            guard !didApplyInitialViewport, let scrollView else { return }
            didApplyInitialViewport = true

            guard let initialViewportState = parent.initialViewportState else {
                return
            }

            let zoomScale = clampedZoom(initialViewportState.zoomScale)
            scrollView.magnification = zoomScale
            scrollView.contentView.scroll(to: initialViewportState.contentOffset)
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
                scrollView.reflectScrolledClipView(scrollView.contentView)
            case .fitToViewfinder:
                guard let fitRect = parent.fitRect, !fitRect.isEmpty else { return }
                scrollView.magnify(toFit: fitRect.insetBy(dx: -80, dy: -80))
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
        }

        private func clampedZoom(_ zoomScale: CGFloat) -> CGFloat {
            min(max(zoomScale, parent.minimumZoomScale), parent.maximumZoomScale)
        }
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
