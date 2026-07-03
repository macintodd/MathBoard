//
//  PencilKitCanvas.swift
//  MathBoardCore — Canvas module (iPad)
//
//  PencilKit drawing surface wrapped for SwiftUI. The container owns the
//  in-memory `PKDrawing`, hands a binding to a `UIViewRepresentable`
//  wrapper around `PKCanvasView`, loads from disk on first appear, and
//  writes back to disk on every stroke change (400ms debounced).
//
//  External-display publishing lives in the Coordinator. Committed strokes
//  publish through `PKDrawing.image(from:scale:)`; live in-progress strokes
//  publish as lightweight vector points from a non-canceling Apple Pencil
//  gesture recognizer. The live path deliberately avoids snapshotting
//  `PKCanvasView`, because PencilKit's live rendering can flicker when
//  captured mid-composite.
//
//  `updateUIView` also kicks a committed-frame publish on external drawing changes as a
//  belt-and-suspenders measure — in case PencilKit doesn't fire
//  `canvasViewDrawingDidChange` for a programmatic `canvas.drawing` set.
//

#if os(iOS)

import SwiftUI
import PencilKit
import PDFKit
import UIKit
@_spi(Textual) import SwiftUIMath

private enum PencilKitCanvasGeometry {
    static let drawingOriginOffset = CGPoint(x: 3000, y: 3000)
    static let paperBorderColor = UIColor.black.withAlphaComponent(0.22)
    static let paperShadowColor = UIColor.black.withAlphaComponent(0.18)

    static var storageToCanvasTransform: CGAffineTransform {
        CGAffineTransform(
            translationX: drawingOriginOffset.x,
            y: drawingOriginOffset.y
        )
    }

    static var canvasToStorageTransform: CGAffineTransform {
        CGAffineTransform(
            translationX: -drawingOriginOffset.x,
            y: -drawingOriginOffset.y
        )
    }
}

private extension CanvasStrokeColorRecord {
    var uiColor: UIColor {
        UIColor(
            red: Self.clamped(red),
            green: Self.clamped(green),
            blue: Self.clamped(blue),
            alpha: Self.clamped(alpha)
        )
    }

    private static func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }
}

private extension CanvasStrokeColor {
    var uiColor: UIColor {
        UIColor(
            red: Self.clamped(red),
            green: Self.clamped(green),
            blue: Self.clamped(blue),
            alpha: Self.clamped(alpha)
        )
    }

    private static func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }
}

private extension CanvasTextObject {
    var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    func uiFont(size: CGFloat) -> UIFont {
        let baseFont: UIFont
        if let fontName, let namedFont = UIFont(name: fontName, size: size) {
            baseFont = namedFont
        } else {
            baseFont = .systemFont(ofSize: size)
        }

        var traits: UIFontDescriptor.SymbolicTraits = []
        if isBold {
            traits.insert(.traitBold)
        }
        if isItalic {
            traits.insert(.traitItalic)
        }

        guard !traits.isEmpty,
              let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits) else {
            return baseFont
        }
        return UIFont(descriptor: descriptor, size: size)
    }

    func textAttributes(size: CGFloat) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: uiFont(size: size),
            .foregroundColor: uiColor
        ]
        if isUnderlined {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return attributes
    }
}

private extension CanvasToolCommand.EraserMode {
    var pencilKitType: PKEraserTool.EraserType {
        switch self {
        case .pixel:
            return .fixedWidthBitmap
        case .stroke:
            return .vector
        }
    }
}

private extension PKStroke {
    func replacingInkColor(_ color: UIColor) -> PKStroke {
        PKStroke(
            ink: PKInk(ink.inkType, color: color),
            path: path,
            transform: transform,
            mask: mask,
            randomSeed: randomSeed
        )
    }

    func translatedBy(x: CGFloat, y: CGFloat) -> PKStroke {
        PKStroke(
            ink: ink,
            path: path,
            transform: transform.translatedBy(x: x, y: y),
            mask: mask,
            randomSeed: randomSeed
        )
    }
}

struct PencilKitCanvasContainer: View {
    let drawingURL: URL
    let background: CanvasBackground?
    let presentationMode: CanvasPresentationMode
    let initialViewportState: CanvasViewportState?
    let viewportCommand: CanvasViewportCommand?
    let editCommand: CanvasEditCommand?
    let toolCommand: CanvasToolCommand?
    let objectCommand: CanvasObjectCommand?
    @Binding var selectionState: CanvasSelectionState
    let showsSystemToolPicker: Bool
    let onFrameUpdate: (@MainActor (CGImage, CGRect, CGRect) -> Void)?
    let onViewportSourceRectChange: (@MainActor (CGRect) -> Void)?
    let onLiveStrokeUpdate: (@MainActor (CanvasLiveStroke?) -> Void)?
    let onViewportStateChange: (@MainActor (CanvasViewportState) -> Void)?
    let onEditStateChange: (@MainActor (CanvasEditState) -> Void)?
    let onInteractionBegan: (@MainActor () -> Void)?
    let onTextEditingBegan: (@MainActor () -> Void)?
    let onTextEditingEnded: (@MainActor () -> Void)?
    let onTextPlacementRequested: (@MainActor (CGPoint) -> Void)?
    let onExtractedRegionSend: (@MainActor (CanvasExtractedRegion) -> Void)?

    @State private var drawing: PKDrawing = PKDrawing()
    @State private var textObjects: [CanvasTextObject] = []
    @State private var imageObjects: [CanvasImageObject] = []
    @State private var didLoad = false
    @State private var saveTask: Task<Void, Never>?
    @State private var textSaveTask: Task<Void, Never>?
    @State private var imageObjectSaveTask: Task<Void, Never>?
    @State private var hasPendingSave = false
    @State private var hasPendingTextSave = false
    @State private var hasPendingImageObjectSave = false
    @State private var undoStack: [PKDrawing] = []
    @State private var redoStack: [PKDrawing] = []
    @State private var isApplyingEditCommand = false
    @State private var appliedEditCommandID: CanvasEditCommand.ID?

    private static let saveDebounce: Duration = .milliseconds(400)
    private static let maximumUndoDepth = 50
    private static let absoluteBlack = UIColor(red: 0.0001, green: 0.0001, blue: 0.0001, alpha: 1)

    var body: some View {
        PencilKitCanvasRepresentable(
            drawingURL: drawingURL,
            drawing: $drawing,
            textObjects: $textObjects,
            imageObjects: $imageObjects,
            background: background,
            presentationMode: presentationMode,
            initialViewportState: initialViewportState,
            viewportCommand: viewportCommand,
            toolCommand: toolCommand,
            objectCommand: objectCommand,
            selectionState: $selectionState,
            showsSystemToolPicker: showsSystemToolPicker,
            onFrameUpdate: onFrameUpdate,
            onViewportSourceRectChange: onViewportSourceRectChange,
            onLiveStrokeUpdate: onLiveStrokeUpdate,
            onViewportStateChange: onViewportStateChange,
            onInteractionBegan: onInteractionBegan,
            onTextEditingBegan: onTextEditingBegan,
            onTextEditingEnded: onTextEditingEnded,
            onTextPlacementRequested: onTextPlacementRequested,
            onExtractedRegionSend: onExtractedRegionSend
        )
            .background(Color.white)
            .task(id: drawingURL) {
                didLoad = false
                textSaveTask?.cancel()
                textSaveTask = nil
                imageObjectSaveTask?.cancel()
                imageObjectSaveTask = nil
                hasPendingTextSave = false
                hasPendingImageObjectSave = false
                drawing = (try? Self.loadDrawing(at: drawingURL)) ?? PKDrawing()
                textObjects = CanvasTextObject.load(from: CanvasTextObject.sidecarURL(forDrawingURL: drawingURL))
                imageObjects = CanvasImageObject.load(from: CanvasImageObject.sidecarURL(forDrawingURL: drawingURL))
                undoStack = []
                redoStack = []
                isApplyingEditCommand = false
                appliedEditCommandID = nil
                await Task.yield()
                didLoad = true
                publishEditState()
            }
            .onChange(of: drawing) { oldDrawing, newDrawing in
                handleDrawingChange(from: oldDrawing, to: newDrawing)
            }
            .onChange(of: textObjects) { _, newTextObjects in
                handleTextObjectsChange(newTextObjects)
            }
            .onChange(of: imageObjects) { _, newImageObjects in
                handleImageObjectsChange(newImageObjects)
            }
            .onChange(of: editCommand) { _, command in
                applyEditCommandIfNeeded(command)
            }
            .onDisappear {
                flushPendingSave()
                flushPendingTextSave()
                flushPendingImageObjectSave()
            }
    }

    private func handleDrawingChange(from oldDrawing: PKDrawing, to newDrawing: PKDrawing) {
        guard didLoad else { return }
        if isApplyingEditCommand {
            isApplyingEditCommand = false
        } else if oldDrawing != newDrawing {
            undoStack.append(oldDrawing)
            if undoStack.count > Self.maximumUndoDepth {
                undoStack.removeFirst(undoStack.count - Self.maximumUndoDepth)
            }
            redoStack = []
        }
        publishEditState()
        scheduleSave(of: newDrawing)
    }

    private func handleTextObjectsChange(_ newTextObjects: [CanvasTextObject]) {
        guard didLoad else { return }
        scheduleTextSave(of: newTextObjects)
    }

    private func handleImageObjectsChange(_ newImageObjects: [CanvasImageObject]) {
        guard didLoad else { return }
        scheduleImageObjectSave(of: newImageObjects)
    }

    private func applyEditCommandIfNeeded(_ command: CanvasEditCommand?) {
        guard let command, appliedEditCommandID != command.id else { return }
        appliedEditCommandID = command.id

        switch command.action {
        case .undo:
            undoLastDrawingChange()
        case .redo:
            redoLastDrawingChange()
        }
    }

    private func undoLastDrawingChange() {
        guard let previousDrawing = undoStack.popLast() else {
            publishEditState()
            return
        }
        redoStack.append(drawing)
        isApplyingEditCommand = true
        drawing = previousDrawing
        publishEditState()
    }

    private func redoLastDrawingChange() {
        guard let nextDrawing = redoStack.popLast() else {
            publishEditState()
            return
        }
        undoStack.append(drawing)
        if undoStack.count > Self.maximumUndoDepth {
            undoStack.removeFirst(undoStack.count - Self.maximumUndoDepth)
        }
        isApplyingEditCommand = true
        drawing = nextDrawing
        publishEditState()
    }

    private func publishEditState() {
        onEditStateChange?(CanvasEditState(
            canUndo: !undoStack.isEmpty,
            canRedo: !redoStack.isEmpty
        ))
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

    private func flushPendingSave() {
        saveTask?.cancel()
        saveTask = nil
        guard hasPendingSave else { return }
        save(drawing, to: drawingURL)
        hasPendingSave = false
    }

    private func scheduleTextSave(of newTextObjects: [CanvasTextObject]) {
        hasPendingTextSave = true
        textSaveTask?.cancel()
        textSaveTask = Task { @MainActor in
            try? await Task.sleep(for: Self.saveDebounce)
            guard !Task.isCancelled else { return }
            saveTextObjects(newTextObjects, to: CanvasTextObject.sidecarURL(forDrawingURL: drawingURL))
            hasPendingTextSave = false
        }
    }

    private func flushPendingTextSave() {
        textSaveTask?.cancel()
        textSaveTask = nil
        guard hasPendingTextSave else { return }
        saveTextObjects(textObjects, to: CanvasTextObject.sidecarURL(forDrawingURL: drawingURL))
        hasPendingTextSave = false
    }

    private func scheduleImageObjectSave(of newImageObjects: [CanvasImageObject]) {
        hasPendingImageObjectSave = true
        imageObjectSaveTask?.cancel()
        imageObjectSaveTask = Task { @MainActor in
            try? await Task.sleep(for: Self.saveDebounce)
            guard !Task.isCancelled else { return }
            saveImageObjects(newImageObjects, to: CanvasImageObject.sidecarURL(forDrawingURL: drawingURL))
            hasPendingImageObjectSave = false
        }
    }

    private func flushPendingImageObjectSave() {
        imageObjectSaveTask?.cancel()
        imageObjectSaveTask = nil
        guard hasPendingImageObjectSave else { return }
        saveImageObjects(imageObjects, to: CanvasImageObject.sidecarURL(forDrawingURL: drawingURL))
        hasPendingImageObjectSave = false
    }

    private static func loadDrawing(at url: URL) throws -> PKDrawing {
        let data = try Data(contentsOf: url)
        let drawing = try PKDrawing(data: data)
        let colorRecords = CanvasStrokeColorRecord.load(
            from: CanvasStrokeColorRecord.sidecarURL(forDrawingURL: url)
        )
        let repairedDrawing = colorRecords.isEmpty
            ? normalizeMacNeutralInk(in: drawing)
            : applyStoredStrokeColors(colorRecords, to: drawing)
        return repairedDrawing
            .transformed(using: PencilKitCanvasGeometry.storageToCanvasTransform)
    }

    private static func applyStoredStrokeColors(
        _ records: [CanvasStrokeColorRecord],
        to drawing: PKDrawing
    ) -> PKDrawing {
        let recordsByKey = Dictionary(uniqueKeysWithValues: records.map { ($0.stableKey, $0) })
        var didRepair = false
        let strokes = drawing.strokes.map { stroke in
            let key = CanvasStrokeColorRecord.stableKey(
                for: stroke.path.creationDate.timeIntervalSinceReferenceDate
            )
            guard let record = recordsByKey[key] else { return stroke }
            didRepair = true
            return stroke.replacingInkColor(record.uiColor)
        }
        return didRepair ? PKDrawing(strokes: strokes) : drawing
    }

    private static func normalizeMacNeutralInk(in drawing: PKDrawing) -> PKDrawing {
        var didNormalize = false
        let strokes = drawing.strokes.map { stroke in
            guard shouldNormalizeToBlack(stroke.ink.color) else { return stroke }
            didNormalize = true
            return stroke.replacingInkColor(Self.absoluteBlack)
        }
        return didNormalize ? PKDrawing(strokes: strokes) : drawing
    }

    private static func shouldNormalizeToBlack(_ color: UIColor) -> Bool {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha), alpha > 0.1 else {
            return false
        }

        let components = [red, green, blue]
        if components.contains(where: { !$0.isFinite || $0 < -0.001 || $0 > 1.001 }) {
            return true
        }

        let maxComponent = max(red, green, blue)
        let minComponent = min(red, green, blue)
        let saturationRange = maxComponent - minComponent
        let isBlackLike = maxComponent < 0.12
        let isWhiteLike = minComponent > 0.88
        let isProblemNeutral = saturationRange < 0.04 && (isBlackLike || isWhiteLike)
        return isProblemNeutral
    }

    private func save(_ drawing: PKDrawing, to url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let storageDrawing = drawing
                .transformed(using: PencilKitCanvasGeometry.canvasToStorageTransform)
            try storageDrawing.dataRepresentation().write(to: url, options: .atomic)
        } catch {
            print("[Canvas] save error: \(error)")
        }
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
        } catch {
            print("[Canvas] image object save error: \(error)")
        }
    }
}

private final class PencilKitCanvasHostView: UIView {
    let backgroundView = PDFCanvasBackgroundView()
    let canvas = PKCanvasView()
    let imageObjectsView = CanvasImageObjectsView()
    let textObjectsView = CanvasTextObjectsView()
    let regionSelectionOverlayView = CanvasRegionSelectionOverlayView()
    let laserOverlayView = CanvasLaserOverlayView()
    let textPlacementOverlayView = CanvasTextPlacementOverlayView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        isOpaque = true
        overrideUserInterfaceStyle = .light
        clipsToBounds = true
        backgroundView.isUserInteractionEnabled = false
        imageObjectsView.isUserInteractionEnabled = false
        textObjectsView.isUserInteractionEnabled = false
        regionSelectionOverlayView.acceptsRegionSelectionInput = false
        laserOverlayView.acceptsLaserInput = false
        textPlacementOverlayView.acceptsTextPlacement = false
        addSubview(backgroundView)
        addSubview(canvas)
        addSubview(imageObjectsView)
        addSubview(textObjectsView)
        addSubview(regionSelectionOverlayView)
        addSubview(laserOverlayView)
        addSubview(textPlacementOverlayView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        canvas.frame = bounds
        imageObjectsView.frame = bounds
        textObjectsView.frame = bounds
        regionSelectionOverlayView.frame = bounds
        laserOverlayView.frame = bounds
        textPlacementOverlayView.frame = bounds
        updateBackgroundFrame(using: canvas)
        updateImageObjectFrame(using: canvas)
        updateTextObjectFrame(using: canvas)
    }

    func updateBackground(_ background: CanvasBackground?, using canvas: PKCanvasView) {
        backgroundView.configure(background)
        updateBackgroundFrame(using: canvas)
    }

    func updateTextObjects(
        _ textObjects: [CanvasTextObject],
        using canvas: PKCanvasView,
        hiddenTextObjectID: UUID? = nil,
        selectedTextObjectID: UUID? = nil
    ) {
        textObjectsView.configure(
            textObjects,
            hiddenTextObjectID: hiddenTextObjectID,
            selectedTextObjectID: selectedTextObjectID
        )
        updateTextObjectFrame(using: canvas)
    }

    func updateImageObjects(
        _ imageObjects: [CanvasImageObject],
        assetDirectoryURL: URL,
        using canvas: PKCanvasView,
        selectedImageObjectID: UUID? = nil
    ) {
        imageObjectsView.configure(
            imageObjects,
            assetDirectoryURL: assetDirectoryURL,
            selectedImageObjectID: selectedImageObjectID
        )
        updateImageObjectFrame(using: canvas)
    }

    func updateBackgroundFrame(using canvas: PKCanvasView) {
        guard let pageBounds = backgroundView.pageBounds else {
            backgroundView.isHidden = true
            return
        }

        let zoomScale = canvas.zoomScale
        let origin = PencilKitCanvasGeometry.drawingOriginOffset
        backgroundView.isHidden = false
        backgroundView.frame = CGRect(
            x: origin.x * zoomScale - canvas.contentOffset.x,
            y: origin.y * zoomScale - canvas.contentOffset.y,
            width: pageBounds.width * zoomScale,
            height: pageBounds.height * zoomScale
        )
    }

    func updateTextObjectFrame(using canvas: PKCanvasView) {
        textObjectsView.updateViewport(
            zoomScale: canvas.zoomScale,
            contentOffset: canvas.contentOffset,
            canvasOrigin: PencilKitCanvasGeometry.drawingOriginOffset
        )
    }

    func updateImageObjectFrame(using canvas: PKCanvasView) {
        imageObjectsView.updateViewport(
            zoomScale: canvas.zoomScale,
            contentOffset: canvas.contentOffset,
            canvasOrigin: PencilKitCanvasGeometry.drawingOriginOffset
        )
    }
}

private final class CanvasTextPlacementOverlayView: UIView {
    var acceptsTextPlacement = false {
        didSet {
            isUserInteractionEnabled = false
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        acceptsTextPlacement && super.point(inside: point, with: event)
    }
}

private final class CanvasRegionSelectionOverlayView: UIView {
    enum Mode {
        case lasso
        case marquee
    }

    var acceptsRegionSelectionInput = false {
        didSet {
            isUserInteractionEnabled = acceptsRegionSelectionInput
        }
    }

    private var mode: Mode = .marquee
    private var points: [CGPoint] = []
    private var marqueeStart: CGPoint?
    private var marqueeEnd: CGPoint?
    private var selectedRects: [CGRect] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        acceptsRegionSelectionInput && super.point(inside: point, with: event)
    }

    func begin(at point: CGPoint, mode: Mode) {
        self.mode = mode
        points = [point]
        marqueeStart = point
        marqueeEnd = point
        selectedRects = []
        setNeedsDisplay()
    }

    func updateSelectedRects(_ rects: [CGRect]) {
        selectedRects = rects
        setNeedsDisplay()
    }

    func update(to point: CGPoint) {
        switch mode {
        case .lasso:
            points.append(point)
        case .marquee:
            marqueeEnd = point
        }
        setNeedsDisplay()
    }

    func update(with newPoints: [CGPoint]) {
        guard !newPoints.isEmpty else { return }
        switch mode {
        case .lasso:
            points.append(contentsOf: newPoints)
        case .marquee:
            marqueeEnd = newPoints.last
        }
        setNeedsDisplay()
    }

    func clear() {
        points = []
        marqueeStart = nil
        marqueeEnd = nil
        selectedRects = []
        setNeedsDisplay()
    }

    func finishSelectionShape() {
        points = []
        marqueeStart = nil
        marqueeEnd = nil
        setNeedsDisplay()
    }

    func closeLasso() {
        guard mode == .lasso,
              let first = points.first,
              let last = points.last,
              hypot(last.x - first.x, last.y - first.y) > 1 else {
            return
        }
        points.append(first)
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        context.saveGState()
        UIColor.systemBlue.withAlphaComponent(0.14).setFill()
        UIColor.systemBlue.withAlphaComponent(0.95).setStroke()
        context.setLineWidth(2)
        context.setLineDash(phase: 0, lengths: [8, 5])

        switch mode {
        case .lasso:
            if points.count > 1 {
                let path = UIBezierPath()
                path.move(to: points[0])
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
                if points.count > 2, points.first == points.last {
                    path.close()
                    path.fill()
                }
                path.stroke()
            }
        case .marquee:
            if let marqueeStart, let marqueeEnd {
                let selectionRect = CGRect(
                    x: min(marqueeStart.x, marqueeEnd.x),
                    y: min(marqueeStart.y, marqueeEnd.y),
                    width: abs(marqueeEnd.x - marqueeStart.x),
                    height: abs(marqueeEnd.y - marqueeStart.y)
                )
                UIBezierPath(roundedRect: selectionRect, cornerRadius: 6).fill()
                UIBezierPath(roundedRect: selectionRect, cornerRadius: 6).stroke()
            }
        }

        context.setLineDash(phase: 0, lengths: [])
        UIColor.systemBlue.withAlphaComponent(0.12).setFill()
        UIColor.systemBlue.withAlphaComponent(0.95).setStroke()
        context.setLineWidth(3)
        for rect in selectedRects where !rect.isNull && !rect.isEmpty {
            let highlight = rect.insetBy(dx: -4, dy: -4)
            let path = UIBezierPath(roundedRect: highlight, cornerRadius: 7)
            path.fill()
            path.stroke()
        }

        context.restoreGState()
    }
}

private extension CanvasRegionSelectionOverlayView.Mode {
    init(_ mode: CanvasToolCommand.SelectionMode) {
        switch mode {
        case .lasso:
            self = .lasso
        case .marquee:
            self = .marquee
        }
    }
}

private final class CanvasLaserOverlayView: UIView {
    private static let pointerLifetime: TimeInterval = 0.14

    private var stroke: CanvasLiveStroke?
    private var displayLink: CADisplayLink?
    var acceptsLaserInput = false {
        didSet {
            isUserInteractionEnabled = acceptsLaserInput
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(stroke: CanvasLiveStroke?) {
        self.stroke = stroke
        if stroke?.isTransient == true {
            startDisplayLink()
        } else {
            stopDisplayLink()
        }
        setNeedsDisplay()
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        acceptsLaserInput && super.point(inside: point, with: event)
    }

    override func draw(_ rect: CGRect) {
        guard let stroke,
              let context = UIGraphicsGetCurrentContext(),
              !stroke.points.isEmpty else {
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        let visibleSamples = visibleLaserSamples(for: stroke, now: now)
        guard let lastVisibleSample = visibleSamples.last else {
            DispatchQueue.main.async { [weak self] in
                self?.update(stroke: nil)
            }
            return
        }

        let color = stroke.color.uiColor
        context.saveGState()

        switch stroke.kind {
        case .laserDot:
            let diameter = max(stroke.lineWidth, 3)
            let alpha = laserAlpha(for: lastVisibleSample, in: stroke, now: now, maximum: 1)
            let dotRect = CGRect(
                x: lastVisibleSample.location.x - diameter / 2,
                y: lastVisibleSample.location.y - diameter / 2,
                width: diameter,
                height: diameter
            )
            drawLaserDot(in: context, rect: dotRect, color: color, alpha: alpha)

        case .laserTrail:
            guard visibleSamples.count > 1 else {
                let diameter = max(stroke.lineWidth, 3)
                let alpha = laserAlpha(for: lastVisibleSample, in: stroke, now: now, maximum: 1)
                drawLaserDot(in: context, rect: CGRect(
                    x: lastVisibleSample.location.x - diameter / 2,
                    y: lastVisibleSample.location.y - diameter / 2,
                    width: diameter,
                    height: diameter
                ), color: color, alpha: alpha)
                context.restoreGState()
                return
            }

            for pair in zip(visibleSamples, visibleSamples.dropFirst()) {
                let alpha = laserAlpha(for: pair.1, in: stroke, now: now, maximum: 1)
                let path = UIBezierPath()
                path.move(to: pair.0.location)
                path.addLine(to: pair.1.location)
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                drawLaserPath(path, baseWidth: stroke.lineWidth, color: color, alpha: alpha)
            }

        case .ink:
            break
        }

        context.restoreGState()
    }

    private func drawLaserDot(in context: CGContext, rect: CGRect, color: UIColor, alpha: CGFloat) {
        let blurWidth = max(rect.width, 3)
        let whiteBloomRect = rect.insetBy(dx: rect.width * 0.18, dy: rect.height * 0.18)
        let colorCoreRect = rect.insetBy(dx: rect.width * 0.30, dy: rect.height * 0.30)
        let hotRect = rect.insetBy(dx: rect.width * 0.43, dy: rect.height * 0.43)

        context.saveGState()
        context.setShadow(offset: .zero, blur: blurWidth * 3, color: color.withAlphaComponent(alpha * 0.55).cgColor)
        color.withAlphaComponent(alpha * 0.24).setFill()
        context.fillEllipse(in: rect)
        context.restoreGState()

        context.saveGState()
        context.setShadow(offset: .zero, blur: blurWidth, color: color.withAlphaComponent(alpha * 0.85).cgColor)
        color.withAlphaComponent(alpha * 0.7).setFill()
        context.fillEllipse(in: rect)
        context.restoreGState()

        context.saveGState()
        context.setBlendMode(.screen)
        color.withAlphaComponent(alpha).setFill()
        context.fillEllipse(in: rect)
        UIColor.white.withAlphaComponent(alpha * 0.38).setFill()
        context.fillEllipse(in: whiteBloomRect)
        color.withAlphaComponent(alpha * 0.92).setFill()
        context.fillEllipse(in: colorCoreRect)
        UIColor.white.withAlphaComponent(alpha * 0.72).setFill()
        context.fillEllipse(in: hotRect)
        color.withAlphaComponent(alpha * 0.45).setFill()
        context.fillEllipse(in: hotRect.insetBy(dx: -rect.width * 0.04, dy: -rect.height * 0.04))
        context.restoreGState()
    }

    private func drawLaserPath(_ path: UIBezierPath, baseWidth: CGFloat, color: UIColor, alpha: CGFloat) {
        let beamWidth = max(baseWidth, 3)

        path.lineWidth = max(beamWidth * 1.65, 6)
        color.withAlphaComponent(alpha * 0.30).setStroke()
        path.stroke(with: .normal, alpha: 1)

        guard let context = UIGraphicsGetCurrentContext() else { return }

        context.saveGState()
        context.setShadow(offset: .zero, blur: beamWidth * 3, color: color.withAlphaComponent(alpha * 0.55).cgColor)
        path.lineWidth = max(beamWidth * 0.95, 4)
        color.withAlphaComponent(alpha * 0.25).setStroke()
        path.stroke()
        context.restoreGState()

        context.saveGState()
        context.setShadow(offset: .zero, blur: beamWidth, color: color.withAlphaComponent(alpha * 0.9).cgColor)
        path.lineWidth = max(beamWidth * 0.72, 3)
        color.withAlphaComponent(alpha * 0.75).setStroke()
        path.stroke()
        context.restoreGState()

        context.saveGState()
        context.setBlendMode(.screen)
        path.lineWidth = max(beamWidth * 0.46, 2)
        color.withAlphaComponent(alpha).setStroke()
        path.stroke()
        path.lineWidth = max(beamWidth * 0.28, 1.5)
        UIColor.white.withAlphaComponent(alpha * 0.38).setStroke()
        path.stroke()
        path.lineWidth = max(beamWidth * 0.22, 1.5)
        color.withAlphaComponent(alpha * 0.86).setStroke()
        path.stroke()
        path.lineWidth = max(beamWidth * 0.10, 1)
        UIColor.white.withAlphaComponent(alpha * 0.68).setStroke()
        path.stroke()
        context.restoreGState()
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(displayLinkDidTick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func displayLinkDidTick() {
        setNeedsDisplay()
    }

    private func visibleLaserSamples(for stroke: CanvasLiveStroke, now: TimeInterval) -> [CanvasLiveStrokePoint] {
        let lifetime = effectiveLifetime(for: stroke)
        let liveSamples = stroke.samples.filter { sample in
            now - sample.timestamp <= lifetime
        }

        switch stroke.kind {
        case .laserDot:
            return liveSamples.last.map { [$0] } ?? []
        case .laserTrail:
            return stroke.displayDuration <= 0
                ? liveSamples.last.map { [$0] } ?? []
                : liveSamples
        case .ink:
            return []
        }
    }

    private func laserAlpha(
        for sample: CanvasLiveStrokePoint,
        in stroke: CanvasLiveStroke,
        now: TimeInterval,
        maximum: CGFloat
    ) -> CGFloat {
        let lifetime = max(effectiveLifetime(for: stroke), 0.001)
        let progress = min(max((now - sample.timestamp) / lifetime, 0), 1)
        return maximum * CGFloat(1 - progress)
    }

    private func effectiveLifetime(for stroke: CanvasLiveStroke) -> TimeInterval {
        stroke.displayDuration <= 0 ? Self.pointerLifetime : stroke.displayDuration
    }
}

private final class PDFCanvasBackgroundView: UIView {
    private var background: CanvasBackground?
    private var page: PDFPage?
    private(set) var pageBounds: CGRect?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        isOpaque = true
        contentMode = .redraw
        layer.borderColor = PencilKitCanvasGeometry.paperBorderColor.cgColor
        layer.borderWidth = 1
        layer.shadowColor = PencilKitCanvasGeometry.paperShadowColor.cgColor
        layer.shadowOpacity = 1
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 3)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ background: CanvasBackground?) {
        guard self.background != background else { return }
        self.background = background

        guard let background,
              let document = PDFDocument(url: background.pdfURL),
              let page = document.page(at: background.pageIndex) else {
            self.page = nil
            pageBounds = nil
            setNeedsDisplay()
            return
        }

        self.page = page
        self.pageBounds = page.bounds(for: .mediaBox)
        layer.shadowPath = UIBezierPath(rect: bounds).cgPath
        setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(rect: bounds).cgPath
    }

    override func draw(_ rect: CGRect) {
        guard let page, let pageBounds, let context = UIGraphicsGetCurrentContext() else { return }
        PDFCanvasBackgroundRenderer.draw(
            page: page,
            pageBounds: pageBounds,
            in: bounds,
            context: context
        )
    }
}

private final class CanvasImageObjectsView: UIView {
    private var imageObjects: [CanvasImageObject] = []
    private var assetDirectoryURL: URL?
    private var selectedImageObjectID: UUID?
    private var zoomScale: CGFloat = 1
    private var contentOffset: CGPoint = .zero
    private var canvasOrigin: CGPoint = .zero
    private var imageCache: [String: UIImage] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        _ imageObjects: [CanvasImageObject],
        assetDirectoryURL: URL,
        selectedImageObjectID: UUID? = nil
    ) {
        guard self.imageObjects != imageObjects
                || self.assetDirectoryURL != assetDirectoryURL
                || self.selectedImageObjectID != selectedImageObjectID else {
            return
        }
        self.imageObjects = imageObjects
        self.assetDirectoryURL = assetDirectoryURL
        self.selectedImageObjectID = selectedImageObjectID
        imageCache = imageCache.filter { fileName, _ in
            imageObjects.contains { $0.imageFileName == fileName }
        }
        setNeedsDisplay()
    }

    func updateViewport(zoomScale: CGFloat, contentOffset: CGPoint, canvasOrigin: CGPoint) {
        self.zoomScale = zoomScale
        self.contentOffset = contentOffset
        self.canvasOrigin = canvasOrigin
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        UIColor.clear.setFill()
        UIRectFill(rect)

        for object in imageObjects {
            guard let image = image(for: object) else { continue }
            let frame = CGRect(
                x: (canvasOrigin.x + object.x) * zoomScale - contentOffset.x,
                y: (canvasOrigin.y + object.y) * zoomScale - contentOffset.y,
                width: object.width * zoomScale,
                height: object.height * zoomScale
            )
            image.draw(in: frame)
            if object.id == selectedImageObjectID {
                drawSelectionFrame(frame)
            }
        }
    }

    private func image(for object: CanvasImageObject) -> UIImage? {
        if let cached = imageCache[object.imageFileName] {
            return cached
        }
        guard let assetDirectoryURL else { return nil }
        let url = assetDirectoryURL.appendingPathComponent(object.imageFileName)
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        imageCache[object.imageFileName] = image
        return image
    }

    private func drawSelectionFrame(_ frame: CGRect) {
        let rect = frame.insetBy(dx: -6, dy: -6)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 6)
        UIColor.systemBlue.setStroke()
        path.lineWidth = 2
        path.setLineDash([6, 4], count: 2, phase: 0)
        path.stroke()
    }
}

private final class CanvasTextObjectsView: UIView {
    private var textObjects: [CanvasTextObject] = []
    private var hiddenTextObjectID: UUID?
    private var selectedTextObjectID: UUID?
    private var zoomScale: CGFloat = 1
    private var contentOffset: CGPoint = .zero
    private var canvasOrigin: CGPoint = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        _ textObjects: [CanvasTextObject],
        hiddenTextObjectID: UUID? = nil,
        selectedTextObjectID: UUID? = nil
    ) {
        guard self.textObjects != textObjects
                || self.hiddenTextObjectID != hiddenTextObjectID
                || self.selectedTextObjectID != selectedTextObjectID else {
            return
        }
        self.textObjects = textObjects
        self.hiddenTextObjectID = hiddenTextObjectID
        self.selectedTextObjectID = selectedTextObjectID
        setNeedsDisplay()
    }

    func updateViewport(zoomScale: CGFloat, contentOffset: CGPoint, canvasOrigin: CGPoint) {
        self.zoomScale = zoomScale
        self.contentOffset = contentOffset
        self.canvasOrigin = canvasOrigin
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        UIColor.clear.setFill()
        UIRectFill(rect)

        for object in textObjects where !object.text.isEmpty && object.id != hiddenTextObjectID {
            let frame = CGRect(
                x: (canvasOrigin.x + object.x) * zoomScale - contentOffset.x,
                y: (canvasOrigin.y + object.y) * zoomScale - contentOffset.y,
                width: object.width * zoomScale,
                height: object.height * zoomScale
            )
            CanvasMathTextRenderer.draw(object, in: frame, scale: zoomScale)
            if object.id == selectedTextObjectID {
                drawSelectionFrame(frame)
            }
        }
    }

    private func drawSelectionFrame(_ frame: CGRect) {
        let rect = frame.insetBy(dx: -6, dy: -6)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 6)
        UIColor.systemBlue.setStroke()
        path.lineWidth = 2
        path.setLineDash([6, 4], count: 2, phase: 0)
        path.stroke()

        UIColor.systemBlue.withAlphaComponent(0.75).setFill()
        for point in [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ] {
            UIBezierPath(ovalIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)).fill()
        }

        let resizeHandleRect = CGRect(x: rect.maxX - 7, y: rect.maxY - 7, width: 14, height: 14)
        UIColor.white.setFill()
        UIBezierPath(roundedRect: resizeHandleRect, cornerRadius: 4).fill()
        UIColor.systemBlue.setStroke()
        let handlePath = UIBezierPath(roundedRect: resizeHandleRect, cornerRadius: 4)
        handlePath.lineWidth = 2
        handlePath.stroke()
    }
}

private enum CanvasMathTextRenderer {
    private static let mathBlockSpacing: CGFloat = 8
    private static let fallbackPadding: CGFloat = 6
    private static let textInset: CGFloat = 8

    static func draw(_ object: CanvasTextObject, in frame: CGRect, scale: CGFloat) {
        let resolvedScale = max(scale, 0.001)
        let attributes = object.textAttributes(size: object.fontSize * resolvedScale)
        let segments = CanvasMathTextParser.segments(in: object.text)
        guard segments.contains(where: \.isMath) else {
            object.text.draw(in: frame, withAttributes: attributes)
            return
        }

        let contentFrame = frame.insetBy(
            dx: textInset * resolvedScale,
            dy: max(object.fontSize * resolvedScale * 0.25, fallbackPadding)
        )
        var cursorY = contentFrame.minY
        for segment in segments {
            guard cursorY < contentFrame.maxY else { break }

            switch segment {
            case .text(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let height = measuredTextHeight(trimmed, width: contentFrame.width, attributes: attributes)
                let drawRect = CGRect(
                    x: contentFrame.minX,
                    y: cursorY,
                    width: contentFrame.width,
                    height: min(height, contentFrame.maxY - cursorY)
                )
                trimmed.draw(in: drawRect, withAttributes: attributes)
                cursorY = drawRect.maxY + mathBlockSpacing
            case .math(let latex):
                let image = mathImage(for: latex, object: object, scale: resolvedScale)
                let imageSize = image?.size ?? fallbackSize(for: latex, width: contentFrame.width, attributes: attributes)
                let fittedSize = fittedMathSize(imageSize, maxWidth: contentFrame.width)
                let drawRect = CGRect(
                    x: contentFrame.minX,
                    y: cursorY,
                    width: fittedSize.width,
                    height: min(fittedSize.height, contentFrame.maxY - cursorY)
                )
                if let image {
                    image.draw(in: drawRect)
                } else {
                    fallbackText(for: latex).draw(in: drawRect, withAttributes: attributes)
                }
                cursorY = drawRect.maxY + mathBlockSpacing
            }
        }
    }

    private static func measuredTextHeight(
        _ text: String,
        width: CGFloat,
        attributes: [NSAttributedString.Key: Any]
    ) -> CGFloat {
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        ).integral
        return max(bounds.height, 1)
    }

    static func fittingSize(for object: CanvasTextObject, maxWidth: CGFloat) -> CGSize? {
        let segments = CanvasMathTextParser.segments(in: object.text)
        guard segments.contains(where: \.isMath) else { return nil }

        let fontSize = min(max(object.fontSize, 8), 96)
        let attributes = object.textAttributes(size: fontSize)
        let contentWidth = max(maxWidth - textInset * 2, 1)
        let verticalInset = max(fontSize * 0.25, fallbackPadding)
        var width: CGFloat = 0
        var height: CGFloat = verticalInset * 2

        for segment in segments {
            switch segment {
            case .text(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let textHeight = measuredTextHeight(trimmed, width: contentWidth, attributes: attributes)
                let textWidth = measuredTextWidth(trimmed, attributes: attributes)
                width = max(width, min(textWidth, contentWidth))
                height += textHeight + mathBlockSpacing
            case .math(let latex):
                let mathSize = mathImageSize(for: latex, fontSize: fontSize)
                let fittedSize = fittedMathSize(mathSize, maxWidth: contentWidth)
                width = max(width, fittedSize.width)
                height += fittedSize.height + mathBlockSpacing
            }
        }

        return CGSize(
            width: min(max(width + textInset * 2, max(fontSize * 5, 160)), maxWidth),
            height: max(height - mathBlockSpacing, max(fontSize * 1.9, 56))
        )
    }

    private static func measuredTextWidth(
        _ text: String,
        attributes: [NSAttributedString.Key: Any]
    ) -> CGFloat {
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        ).integral
        return max(bounds.width, 1)
    }

    private static func mathImage(for latex: String, object: CanvasTextObject, scale: CGFloat) -> UIImage? {
        let fontSize = max(object.fontSize * scale, 8)
        let size = mathImageSize(for: latex, fontSize: fontSize)
        guard size.width > 0, size.height > 0 else {
            return nil
        }

        return MainActor.assumeIsolated {
            let mathFont = Math.Font(name: .latinModern, size: fontSize)
            let content = Math(latex)
                .mathTypesettingStyle(.display)
                .mathFont(mathFont)
                .foregroundStyle(Color(uiColor: object.uiColor))
                .fixedSize()
                .padding(.horizontal, max(fontSize * 1.4, fallbackPadding * 3))
                .padding(.vertical, max(fontSize * 0.9, fallbackPadding * 3))
            let renderer = ImageRenderer(content: content)
            renderer.proposedSize = ProposedViewSize(size)
            renderer.scale = UIScreen.main.scale
            return renderer.uiImage
        }
    }

    private static func mathImageSize(for latex: String, fontSize: CGFloat) -> CGSize {
        let mathFont = Math.Font(name: .latinModern, size: fontSize)
        let bounds = Math.typographicBounds(
            for: latex,
            fitting: ProposedViewSize(width: 100_000, height: 100_000),
            font: mathFont,
            style: .display
        )
        let horizontalPadding = max(fallbackPadding * 6, fontSize * 2.8)
        let verticalPadding = max(fallbackPadding * 6, fontSize * 1.8)
        return CGSize(
            width: ceil(bounds.size.width + horizontalPadding),
            height: ceil(bounds.size.height + verticalPadding)
        )
    }

    private static func fittedMathSize(_ size: CGSize, maxWidth: CGFloat) -> CGSize {
        guard size.width > maxWidth, size.width > 0 else { return size }
        let scale = maxWidth / size.width
        return CGSize(width: maxWidth, height: size.height * scale)
    }

    private static func fallbackText(for latex: String) -> String {
        "$$\(latex)$$"
    }

    private static func fallbackSize(
        for latex: String,
        width: CGFloat,
        attributes: [NSAttributedString.Key: Any]
    ) -> CGSize {
        let text = fallbackText(for: latex)
        return CGSize(
            width: width,
            height: measuredTextHeight(text, width: width, attributes: attributes)
        )
    }
}

private enum CanvasMathTextSegment: Equatable {
    case text(String)
    case math(String)

    var isMath: Bool {
        if case .math = self { return true }
        return false
    }
}

private enum CanvasMathTextParser {
    static func segments(in text: String) -> [CanvasMathTextSegment] {
        var segments: [CanvasMathTextSegment] = []
        var searchStart = text.startIndex

        while let openingRange = text.range(of: "$$", range: searchStart..<text.endIndex) {
            if openingRange.lowerBound > searchStart {
                segments.append(.text(String(text[searchStart..<openingRange.lowerBound])))
            }

            let bodyStart = openingRange.upperBound
            guard let closingRange = text.range(of: "$$", range: bodyStart..<text.endIndex) else {
                segments.append(.text(String(text[openingRange.lowerBound..<text.endIndex])))
                return segments
            }

            let latex = String(text[bodyStart..<closingRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if latex.isEmpty {
                segments.append(.text(String(text[openingRange.lowerBound..<closingRange.upperBound])))
            } else {
                segments.append(.math(latex))
            }
            searchStart = closingRange.upperBound
        }

        if searchStart < text.endIndex {
            segments.append(.text(String(text[searchStart..<text.endIndex])))
        }
        return segments
    }
}

private enum PDFCanvasBackgroundRenderer {
    static func draw(page: PDFPage, pageBounds: CGRect, in rect: CGRect, context: CGContext) {
        context.saveGState()
        UIColor.white.setFill()
        context.fill(rect)
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(
            x: rect.width / max(pageBounds.width, 0.001),
            y: -rect.height / max(pageBounds.height, 0.001)
        )
        context.translateBy(x: -pageBounds.minX, y: -pageBounds.minY)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()
    }
}

private struct PencilKitCanvasRepresentable: UIViewRepresentable {
    let drawingURL: URL
    @Binding var drawing: PKDrawing
    @Binding var textObjects: [CanvasTextObject]
    @Binding var imageObjects: [CanvasImageObject]
    let background: CanvasBackground?
    let presentationMode: CanvasPresentationMode
    let initialViewportState: CanvasViewportState?
    let viewportCommand: CanvasViewportCommand?
    let toolCommand: CanvasToolCommand?
    let objectCommand: CanvasObjectCommand?
    @Binding var selectionState: CanvasSelectionState
    let showsSystemToolPicker: Bool
    let onFrameUpdate: (@MainActor (CGImage, CGRect, CGRect) -> Void)?
    let onViewportSourceRectChange: (@MainActor (CGRect) -> Void)?
    let onLiveStrokeUpdate: (@MainActor (CanvasLiveStroke?) -> Void)?
    let onViewportStateChange: (@MainActor (CanvasViewportState) -> Void)?
    let onInteractionBegan: (@MainActor () -> Void)?
    let onTextEditingBegan: (@MainActor () -> Void)?
    let onTextEditingEnded: (@MainActor () -> Void)?
    let onTextPlacementRequested: (@MainActor (CGPoint) -> Void)?
    let onExtractedRegionSend: (@MainActor (CanvasExtractedRegion) -> Void)?

    func makeUIView(context: Context) -> PencilKitCanvasHostView {
        let hostView = PencilKitCanvasHostView()
        let canvas = hostView.canvas
        canvas.drawing = drawing
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = .anyInput
        canvas.overrideUserInterfaceStyle = .light
        canvas.backgroundColor = .clear
        canvas.isOpaque = false

        context.coordinator.hostView = hostView
        context.coordinator.configureViewport(for: canvas)
        context.coordinator.canvas = canvas
        context.coordinator.installLiveStrokeRecognizer(on: canvas)
        context.coordinator.installLaserStrokeRecognizer(on: hostView.laserOverlayView, canvas: canvas)
        context.coordinator.installTextPlacementRecognizer(on: hostView.textPlacementOverlayView, canvas: canvas)
        context.coordinator.installTextSelectionRecognizers(on: canvas)
        context.coordinator.installTextEditorDismissRecognizer(on: hostView)
        context.coordinator.installRegionSelectionRecognizer(on: hostView)
        hostView.updateBackground(background, using: canvas)
        hostView.updateImageObjects(
            imageObjects,
            assetDirectoryURL: CanvasImageObject.assetDirectoryURL(forDrawingURL: drawingURL),
            using: canvas
        )
        hostView.updateTextObjects(textObjects, using: canvas)

        // Tool picker has to be installed after the view is in a window;
        // schedule it on the next runloop pass so the view hierarchy has
        // a chance to attach first.
        DispatchQueue.main.async {
            context.coordinator.configureViewport(for: canvas)
            context.coordinator.installToolPicker(on: canvas, isVisible: showsSystemToolPicker)
            context.coordinator.applyToolCommandIfNeeded(toolCommand, to: canvas)
            context.coordinator.applyObjectCommandIfNeeded(objectCommand, to: canvas)
            hostView.updateBackground(self.background, using: canvas)
            hostView.updateImageObjects(
                self.imageObjects,
                assetDirectoryURL: CanvasImageObject.assetDirectoryURL(forDrawingURL: self.drawingURL),
                using: canvas,
                selectedImageObjectID: context.coordinator.selectedImageObjectForDisplayID
            )
            hostView.updateTextObjects(
                self.textObjects,
                using: canvas,
                hiddenTextObjectID: context.coordinator.activeEditingTextObjectID,
                selectedTextObjectID: context.coordinator.selectedTextObjectForDisplayID
            )
            context.coordinator.publishImageFromModel()
        }
        return hostView
    }

    func updateUIView(_ hostView: PencilKitCanvasHostView, context: Context) {
        let canvas = hostView.canvas
        hostView.overrideUserInterfaceStyle = .light
        canvas.overrideUserInterfaceStyle = .light
        context.coordinator.parent = self
        context.coordinator.hostView = hostView
        context.coordinator.canvas = canvas
        context.coordinator.configureViewport(for: canvas)
        hostView.updateBackground(background, using: canvas)
        hostView.updateImageObjects(
            imageObjects,
            assetDirectoryURL: CanvasImageObject.assetDirectoryURL(forDrawingURL: drawingURL),
            using: canvas,
            selectedImageObjectID: context.coordinator.selectedImageObjectForDisplayID
        )
        hostView.updateTextObjects(
            textObjects,
            using: canvas,
            hiddenTextObjectID: context.coordinator.activeEditingTextObjectID,
            selectedTextObjectID: context.coordinator.selectedTextObjectForDisplayID
        )
        context.coordinator.updateActiveTextEditorFrame(on: canvas)
        context.coordinator.applyViewportCommandIfNeeded(viewportCommand, to: canvas)
        context.coordinator.updateToolPickerVisibility(isVisible: showsSystemToolPicker, for: canvas)
        context.coordinator.applyToolCommandIfNeeded(toolCommand, to: canvas)
        context.coordinator.applyObjectCommandIfNeeded(objectCommand, to: canvas)

        if context.coordinator.presentationModeDidChange(to: presentationMode) {
            context.coordinator.clearLiveStrokeAfterViewUpdate()
            DispatchQueue.main.async {
                context.coordinator.publishImageFromModel()
            }
        }

        if context.coordinator.textObjectsDidChange(to: textObjects) {
            DispatchQueue.main.async {
                context.coordinator.publishImageFromModel()
            }
        }

        if canvas.drawing != drawing {
            canvas.drawing = drawing
            // Belt and suspenders: if PencilKit doesn't fire
            // canvasViewDrawingDidChange for this programmatic assignment,
            // we still want the TV to update.
            DispatchQueue.main.async {
                context.coordinator.publishImageFromModel()
            }
        }
    }

    static func dismantleUIView(_ uiView: PencilKitCanvasHostView, coordinator: Coordinator) {
        coordinator.cancelPendingViewportFramePublish()
        coordinator.clearLiveStroke()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate, UIGestureRecognizerDelegate, UITextViewDelegate {
        var parent: PencilKitCanvasRepresentable
        weak var hostView: PencilKitCanvasHostView?
        weak var canvas: PKCanvasView?
        private var publishedPresentationMode: CanvasPresentationMode
        private var publishedTextObjects: [CanvasTextObject]

        private static let targetAspect: CGFloat = 16.0 / 9.0
        private static let publishScale: CGFloat = 2
        private static let minimumZoomScale: CGFloat = 0.1
        private static let maximumZoomScale: CGFloat = 4.0
        private static let contentScaleMultiplier: CGFloat = 4.0
        private static let minimumContentSize = CGSize(width: 4000, height: 3000)
        private static let viewportFramePublishDebounce: Duration = .milliseconds(120)
        private static let committedFrameOverscan: CGFloat = 2.0
        private static let minimumLiveStrokePublishInterval: TimeInterval = 1.0 / 30.0
        private static let maximumLiveStrokePreviewPoints = 240
        private static let minimumLiveStrokeWidthPreviewScale: CGFloat = 0.45
        private static let maximumLiveStrokeWidthPreviewScale: CGFloat = 0.85
        private static let laserPointerLifetime: TimeInterval = 0.14

        private var toolPicker: PKToolPicker?
        private var liveStrokeRecognizer: PencilLiveStrokeGestureRecognizer?
        private var laserStrokeRecognizer: PencilLiveStrokeGestureRecognizer?
        private var textPlacementRecognizer: UITapGestureRecognizer?
        private var textSelectionTapRecognizer: UITapGestureRecognizer?
        private var textSelectionDoubleTapRecognizer: UITapGestureRecognizer?
        private var textSelectionPanRecognizer: CanvasObjectDragGestureRecognizer?
        private var textEditorDismissRecognizer: UITapGestureRecognizer?
        private var regionSelectionRecognizer: PencilLiveStrokeGestureRecognizer?
        private var appliedViewportCommandID: CanvasViewportCommand.ID?
        private var appliedToolCommandID: CanvasToolCommand.ID?
        private var appliedObjectCommandID: CanvasObjectCommand.ID?
        private var didRestoreInitialViewport = false
        private var fittedBackground: CanvasBackground?
        private var configuredBoundsSize: CGSize = .zero
        private var didSetInitialContentOffset = false
        private var viewportFramePublishTask: Task<Void, Never>?
        private var lastLiveStrokePublishTime: TimeInterval = 0
        private var activeLiveStrokeColor: CanvasStrokeColor?
        private var activeLiveStrokeWidth: CGFloat?
        private var activeLiveStrokeTool: ActiveLiveStrokeTool?
        private var activeTextColor: CanvasStrokeColor?
        private var activeTextFontSize: CGFloat = 28
        private var activeTextIsBold = false
        private var activeTextIsItalic = false
        private var activeTextIsUnderlined = false
        private var activeTextFontName: String?
        private var isTextSelectionEnabled = false
        private var isRegionSelectionEnabled = false
        private var activeSelectionTarget: CanvasToolCommand.SelectionTarget = .object
        private var activeRegionSelectionMode: CanvasToolCommand.SelectionMode = .marquee
        private var activeRegionSelection: RegionSelection?
        private var activeRegionSourcePoints: [CGPoint] = []
        private var activeRegionOverlayPoints: [CGPoint] = []
        private var activeRegionConsumedSampleCount = 0
        private var activeRegionSelectedTextObjectIDs: Set<UUID> = []
        private var activeRegionSelectedImageObjectIDs: Set<UUID> = []
        private var activeRegionSelectedStrokeIndexes: Set<Int> = []
        private var selectedTextObjectID: UUID?
        private var lastSelectedTextObjectID: UUID?
        private var selectedImageObjectID: UUID?
        private var lastSelectedImageObjectID: UUID?
        private var movingTextObjectID: UUID?
        private var movingImageObjectID: UUID?
        private var movingTextObjectStartOrigin: CGPoint = .zero
        private var movingImageObjectStartOrigin: CGPoint = .zero
        private var movingTextStartSourcePoint: CGPoint = .zero
        private var movingImageStartSourcePoint: CGPoint = .zero
        private var resizingTextObjectID: UUID?
        private var resizingTextObjectStartSize: CGSize = .zero
        private var resizingTextStartSourcePoint: CGPoint = .zero
        private var activeLaserDuration: TimeInterval = 0
        private var activeLaserMode: CanvasToolCommand.LaserMode = .trail
        private var laserClearTask: Task<Void, Never>?
        private weak var activeTextEditor: UITextView?
        private var activeTextObjectID: UUID?
        private var isApplyingTextEditorUpdate = false

        private enum ActiveLiveStrokeTool {
            case pen
            case marker
            case laser
        }

        private enum RegionSelection {
            case lasso([CGPoint])
            case marquee(CGRect)

            var bounds: CGRect {
                switch self {
                case .lasso(let points):
                    guard let first = points.first else { return .null }
                    return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { rect, point in
                        rect.union(CGRect(origin: point, size: .zero))
                    }
                case .marquee(let rect):
                    return rect
                }
            }

            func intersects(_ rect: CGRect) -> Bool {
                guard !rect.isNull, !rect.isEmpty, bounds.intersects(rect) else { return false }
                switch self {
                case .marquee(let selectionRect):
                    return selectionRect.intersects(rect)
                case .lasso(let points):
                    guard points.count > 2 else { return false }
                    let testPoints = [
                        CGPoint(x: rect.midX, y: rect.midY),
                        CGPoint(x: rect.minX, y: rect.minY),
                        CGPoint(x: rect.maxX, y: rect.minY),
                        CGPoint(x: rect.minX, y: rect.maxY),
                        CGPoint(x: rect.maxX, y: rect.maxY)
                    ]
                    return testPoints.contains { contains($0) }
                }
            }

            private func contains(_ point: CGPoint) -> Bool {
                guard case .lasso(let points) = self, points.count > 2 else { return false }
                var isInside = false
                var previous = points[points.count - 1]
                for current in points {
                    let crossesY = (current.y > point.y) != (previous.y > point.y)
                    if crossesY {
                        let denominator = previous.y - current.y
                        guard abs(denominator) > 0.0001 else {
                            previous = current
                            continue
                        }
                        let xIntersection = (previous.x - current.x) * (point.y - current.y) / denominator + current.x
                        if point.x < xIntersection {
                            isInside.toggle()
                        }
                    }
                    previous = current
                }
                return isInside
            }
        }

        init(parent: PencilKitCanvasRepresentable) {
            self.parent = parent
            self.publishedPresentationMode = parent.presentationMode
            self.publishedTextObjects = parent.textObjects
        }

        func installToolPicker(on canvas: PKCanvasView, isVisible: Bool) {
            guard isVisible else {
                toolPicker?.removeObserver(canvas)
                toolPicker = nil
                return
            }

            let picker = toolPicker ?? PKToolPicker()
            picker.addObserver(canvas)
            picker.setVisible(true, forFirstResponder: canvas)
            canvas.becomeFirstResponder()
            self.toolPicker = picker
        }

        func updateToolPickerVisibility(isVisible: Bool, for canvas: PKCanvasView) {
            if isVisible {
                installToolPicker(on: canvas, isVisible: true)
                canvas.becomeFirstResponder()
            } else {
                toolPicker?.setVisible(false, forFirstResponder: canvas)
                toolPicker?.removeObserver(canvas)
                toolPicker = nil
            }
        }

        func applyToolCommandIfNeeded(_ command: CanvasToolCommand?, to canvas: PKCanvasView) {
            guard let command, appliedToolCommandID != command.id else { return }
            appliedToolCommandID = command.id

            switch command.action {
            case .idle:
                finishTextEditing()
                activeLiveStrokeColor = nil
                activeLiveStrokeWidth = nil
                activeLiveStrokeTool = nil
                activeTextColor = nil
                isTextSelectionEnabled = false
                isRegionSelectionEnabled = false
                setSelectedTextObjectID(nil)
                activeLaserDuration = 0
                liveStrokeRecognizer?.isEnabled = false
                liveStrokeRecognizer?.cancelsTouchesInView = false
                canvas.drawingGestureRecognizer.isEnabled = false
                canvas.panGestureRecognizer.minimumNumberOfTouches = 2
                hostView?.laserOverlayView.acceptsLaserInput = false
                hostView?.textPlacementOverlayView.acceptsTextPlacement = false
                hostView?.regionSelectionOverlayView.acceptsRegionSelectionInput = false
                clearRegionSelection()
                updateHostTextObjects(using: canvas)
                clearLaserOverlay()
            case .select(let target, let mode):
                finishTextEditing()
                activeLiveStrokeColor = nil
                activeLiveStrokeWidth = nil
                activeLiveStrokeTool = nil
                activeTextColor = nil
                let didSelectionConfigurationChange = activeSelectionTarget != target
                    || activeRegionSelectionMode != mode
                activeSelectionTarget = target
                isTextSelectionEnabled = target == .object
                isRegionSelectionEnabled = true
                activeRegionSelectionMode = mode
                if target == .region {
                    setSelectedTextObjectID(nil)
                } else if didSelectionConfigurationChange {
                    clearRegionSelection()
                }
                activeLaserDuration = 0
                liveStrokeRecognizer?.isEnabled = false
                liveStrokeRecognizer?.cancelsTouchesInView = false
                canvas.drawingGestureRecognizer.isEnabled = false
                canvas.panGestureRecognizer.minimumNumberOfTouches = 2
                hostView?.laserOverlayView.acceptsLaserInput = false
                hostView?.textPlacementOverlayView.acceptsTextPlacement = false
                hostView?.regionSelectionOverlayView.acceptsRegionSelectionInput = false
                updateHostTextObjects(using: canvas)
                clearLaserOverlay()
            case .copySelection:
                Task { @MainActor [weak self, weak canvas] in
                    guard let self, let canvas else { return }
                    self.copySelectedRegionToPasteboard(using: canvas)
                }
            case .duplicateSelection:
                Task { @MainActor [weak self, weak canvas] in
                    guard let self, let canvas else { return }
                    self.duplicateSelectedTextObject(using: canvas)
                }
            case .deleteSelection:
                Task { @MainActor [weak self, weak canvas] in
                    guard let self, let canvas else { return }
                    self.deleteSelectedTextObject(using: canvas)
                }
            case .extractSelectionAsImageSticker:
                Task { @MainActor [weak self, weak canvas] in
                    guard let self, let canvas else { return }
                    self.extractSelectedRegionAsImageSticker(using: canvas)
                }
            case .sendSelectionToNextSlide:
                Task { @MainActor [weak self, weak canvas] in
                    guard let self, let canvas else { return }
                    self.sendSelectedRegionToNextSlide(using: canvas)
                }
            case .pen(let color, let width):
                finishTextEditing()
                let clampedWidth = clampedWidth(width, for: .pen)
                activeLiveStrokeColor = color
                activeLiveStrokeWidth = clampedWidth
                activeLiveStrokeTool = .pen
                activeTextColor = nil
                isTextSelectionEnabled = false
                isRegionSelectionEnabled = false
                setSelectedTextObjectID(nil)
                activeLaserDuration = 0
                liveStrokeRecognizer?.isEnabled = true
                liveStrokeRecognizer?.cancelsTouchesInView = false
                canvas.drawingGestureRecognizer.isEnabled = true
                canvas.panGestureRecognizer.minimumNumberOfTouches = 1
                hostView?.laserOverlayView.acceptsLaserInput = false
                hostView?.textPlacementOverlayView.acceptsTextPlacement = false
                hostView?.regionSelectionOverlayView.acceptsRegionSelectionInput = false
                clearRegionSelection()
                updateHostTextObjects(using: canvas)
                clearLaserOverlay()
                canvas.tool = PKInkingTool(
                    .pen,
                    color: color.uiColor,
                    width: clampedWidth
                )
            case .marker(let color, let width):
                finishTextEditing()
                let clampedWidth = clampedWidth(width, for: .marker)
                activeLiveStrokeColor = color
                activeLiveStrokeWidth = clampedWidth
                activeLiveStrokeTool = .marker
                activeTextColor = nil
                isTextSelectionEnabled = false
                isRegionSelectionEnabled = false
                setSelectedTextObjectID(nil)
                activeLaserDuration = 0
                liveStrokeRecognizer?.isEnabled = true
                liveStrokeRecognizer?.cancelsTouchesInView = false
                canvas.drawingGestureRecognizer.isEnabled = true
                canvas.panGestureRecognizer.minimumNumberOfTouches = 1
                hostView?.laserOverlayView.acceptsLaserInput = false
                hostView?.textPlacementOverlayView.acceptsTextPlacement = false
                hostView?.regionSelectionOverlayView.acceptsRegionSelectionInput = false
                clearRegionSelection()
                updateHostTextObjects(using: canvas)
                clearLaserOverlay()
                canvas.tool = PKInkingTool(
                    .marker,
                    color: color.uiColor,
                    width: clampedWidth
                )
            case .eraser(let mode, let width):
                finishTextEditing()
                activeLiveStrokeColor = nil
                activeLiveStrokeWidth = nil
                activeLiveStrokeTool = nil
                activeTextColor = nil
                isTextSelectionEnabled = false
                isRegionSelectionEnabled = false
                setSelectedTextObjectID(nil)
                activeLaserDuration = 0
                liveStrokeRecognizer?.isEnabled = false
                liveStrokeRecognizer?.cancelsTouchesInView = false
                canvas.drawingGestureRecognizer.isEnabled = true
                canvas.panGestureRecognizer.minimumNumberOfTouches = 1
                hostView?.laserOverlayView.acceptsLaserInput = false
                hostView?.textPlacementOverlayView.acceptsTextPlacement = false
                hostView?.regionSelectionOverlayView.acceptsRegionSelectionInput = false
                clearRegionSelection()
                updateHostTextObjects(using: canvas)
                clearLaserOverlay()
                let eraserType = mode.pencilKitType
                canvas.tool = PKEraserTool(eraserType, width: clampedWidth(width, for: eraserType))
            case .laser(let color, let diameter, let duration, let mode):
                finishTextEditing()
                activeLiveStrokeColor = color
                activeLiveStrokeWidth = min(max(diameter, 3), 56)
                activeLiveStrokeTool = .laser
                activeTextColor = nil
                isTextSelectionEnabled = false
                isRegionSelectionEnabled = false
                setSelectedTextObjectID(nil)
                activeLaserDuration = min(max(duration, 0), 10)
                activeLaserMode = mode
                liveStrokeRecognizer?.isEnabled = false
                liveStrokeRecognizer?.cancelsTouchesInView = false
                canvas.drawingGestureRecognizer.isEnabled = false
                canvas.panGestureRecognizer.minimumNumberOfTouches = 2
                hostView?.laserOverlayView.acceptsLaserInput = true
                hostView?.textPlacementOverlayView.acceptsTextPlacement = false
                hostView?.regionSelectionOverlayView.acceptsRegionSelectionInput = false
                clearRegionSelection()
                updateHostTextObjects(using: canvas)
                clearLaserOverlay()
            case .text(let color, let fontSize, let isBold, let isItalic, let isUnderlined, let fontName):
                activeLiveStrokeColor = nil
                activeLiveStrokeWidth = nil
                activeLiveStrokeTool = nil
                activeTextColor = color
                activeTextFontSize = min(max(fontSize, 8), 96)
                activeTextIsBold = isBold
                activeTextIsItalic = isItalic
                activeTextIsUnderlined = isUnderlined
                activeTextFontName = fontName?.isEmpty == true ? nil : fontName
                isTextSelectionEnabled = false
                isRegionSelectionEnabled = false
                setSelectedTextObjectID(nil)
                activeLaserDuration = 0
                liveStrokeRecognizer?.isEnabled = false
                liveStrokeRecognizer?.cancelsTouchesInView = false
                canvas.drawingGestureRecognizer.isEnabled = false
                canvas.panGestureRecognizer.minimumNumberOfTouches = 2
                hostView?.laserOverlayView.acceptsLaserInput = false
                hostView?.textPlacementOverlayView.acceptsTextPlacement = true
                hostView?.regionSelectionOverlayView.acceptsRegionSelectionInput = false
                clearRegionSelection()
                updateHostTextObjects(using: canvas)
                applyActiveTextStyleToSelectedObject(using: canvas)
                clearLaserOverlay()
            }
        }

        func applyObjectCommandIfNeeded(_ command: CanvasObjectCommand?, to canvas: PKCanvasView) {
            guard let command, appliedObjectCommandID != command.id else { return }
            appliedObjectCommandID = command.id

            switch command.action {
            case .insertText(let insertion):
                Task { @MainActor [weak self, weak canvas] in
                    guard let self, let canvas else { return }
                    self.insertTextObject(insertion, using: canvas)
                }
            case .updateText(let update):
                Task { @MainActor [weak self, weak canvas] in
                    guard let self, let canvas else { return }
                    self.updateTextObject(update, using: canvas)
                }
            case .duplicate(.text(let id)):
                Task { @MainActor [weak self, weak canvas] in
                    guard let self, let canvas else { return }
                    self.duplicateTextObject(id, using: canvas)
                }
            case .duplicate(.image(let id)):
                Task { @MainActor [weak self, weak canvas] in
                    guard let self, let canvas else { return }
                    self.duplicateImageObject(id, using: canvas)
                }
            case .delete(.text(let id)):
                Task { @MainActor [weak self, weak canvas] in
                    guard let self, let canvas else { return }
                    self.deleteTextObject(id, using: canvas)
                }
            case .delete(.image(let id)):
                Task { @MainActor [weak self, weak canvas] in
                    guard let self, let canvas else { return }
                    self.deleteImageObject(id, using: canvas)
                }
            }
        }

        private func clampedWidth(_ width: CGFloat, for inkType: PKInkingTool.InkType) -> CGFloat {
            let range = inkType.validWidthRange
            return min(max(width, range.lowerBound), range.upperBound)
        }

        private func clampedWidth(_ width: CGFloat, for eraserType: PKEraserTool.EraserType) -> CGFloat {
            let range = eraserType.validWidthRange
            return min(max(width, range.lowerBound), range.upperBound)
        }

        func configureViewport(for canvas: PKCanvasView) {
            canvas.minimumZoomScale = Self.minimumZoomScale
            canvas.maximumZoomScale = Self.maximumZoomScale
            canvas.bounces = false
            canvas.bouncesZoom = false
            canvas.alwaysBounceHorizontal = false
            canvas.alwaysBounceVertical = false
            canvas.scrollsToTop = false

            let boundsSize = canvas.bounds.size
            guard boundsSize.width > 0, boundsSize.height > 0 else {
                publishViewportStateAfterViewUpdate(from: canvas)
                return
            }

            if configuredBoundsSize != boundsSize {
                configuredBoundsSize = boundsSize
                configureContentArea(for: canvas, boundsSize: boundsSize)
            }

            if parent.initialViewportState == nil {
                fitInitialBackgroundIfNeeded(on: canvas)
            }
            restoreInitialViewportIfNeeded(on: canvas)
            publishViewportStateAfterViewUpdate(from: canvas)
        }

        private func configureContentArea(for canvas: PKCanvasView, boundsSize: CGSize) {
            let drawingOriginOffset = PencilKitCanvasGeometry.drawingOriginOffset
            let drawableSize = CGSize(
                width: max(boundsSize.width * Self.contentScaleMultiplier, Self.minimumContentSize.width),
                height: max(boundsSize.height * Self.contentScaleMultiplier, Self.minimumContentSize.height)
            )
            let contentSize = CGSize(
                width: drawingOriginOffset.x + drawableSize.width,
                height: drawingOriginOffset.y + drawableSize.height
            )
            if canvas.contentSize != contentSize {
                canvas.contentSize = contentSize
            }

            if canvas.contentInset != .zero {
                canvas.contentInset = .zero
            }
            if canvas.scrollIndicatorInsets != .zero {
                canvas.scrollIndicatorInsets = .zero
            }

            if !didSetInitialContentOffset {
                didSetInitialContentOffset = true
                canvas.contentOffset = drawingOriginOffset
            }
        }

        private func restoreInitialViewportIfNeeded(on canvas: PKCanvasView) {
            guard !didRestoreInitialViewport else { return }
            didRestoreInitialViewport = true
            guard let initialViewportState = parent.initialViewportState else { return }

            let clampedZoom = min(
                max(initialViewportState.zoomScale, canvas.minimumZoomScale),
                canvas.maximumZoomScale
            )
            canvas.setZoomScale(clampedZoom, animated: false)
            canvas.setContentOffset(initialViewportState.contentOffset, animated: false)
        }

        private func fitInitialBackgroundIfNeeded(on canvas: PKCanvasView) {
            guard let background = parent.background,
                  fittedBackground != background else { return }
            fittedBackground = background
            fitCombinedContentToViewfinder(on: canvas, animated: false, marginFactor: 0.92)
        }

        func applyViewportCommandIfNeeded(_ command: CanvasViewportCommand?, to canvas: PKCanvasView) {
            guard let command, appliedViewportCommandID != command.id else { return }
            appliedViewportCommandID = command.id

            switch command.action {
            case .zoomIn:
                setZoomScale(canvas.zoomScale * 1.25, on: canvas, animated: true)
            case .zoomOut:
                setZoomScale(canvas.zoomScale / 1.25, on: canvas, animated: true)
            case .reset:
                setZoomScale(1, on: canvas, animated: true)
                canvas.setContentOffset(PencilKitCanvasGeometry.drawingOriginOffset, animated: true)
            case .fitToViewfinder:
                fitContentToViewfinder(on: canvas)
            }

            DispatchQueue.main.async { [weak self, weak canvas] in
                guard let self, let canvas else { return }
                self.publishViewportState(from: canvas)
                self.publishImageFromModel()
            }
        }

        private func setZoomScale(_ zoomScale: CGFloat, on canvas: PKCanvasView, animated: Bool) {
            let clampedZoom = min(max(zoomScale, canvas.minimumZoomScale), canvas.maximumZoomScale)
            let currentZoom = max(canvas.zoomScale, 0.001)
            let viewportSize = canvas.bounds.size
            guard viewportSize.width > 0, viewportSize.height > 0 else {
                canvas.setZoomScale(clampedZoom, animated: animated)
                return
            }

            let visibleCenter = CGPoint(
                x: (canvas.contentOffset.x + viewportSize.width / 2) / currentZoom,
                y: (canvas.contentOffset.y + viewportSize.height / 2) / currentZoom
            )
            let targetSize = CGSize(
                width: viewportSize.width / clampedZoom,
                height: viewportSize.height / clampedZoom
            )
            let targetRect = CGRect(
                x: visibleCenter.x - targetSize.width / 2,
                y: visibleCenter.y - targetSize.height / 2,
                width: targetSize.width,
                height: targetSize.height
            )

            canvas.zoom(to: targetRect, animated: animated)
        }

        private func fitContentToViewfinder(on canvas: PKCanvasView) {
            fitCombinedContentToViewfinder(on: canvas, animated: true, marginFactor: 0.9)
        }

        private func fitCombinedContentToViewfinder(
            on canvas: PKCanvasView,
            animated: Bool,
            marginFactor: CGFloat
        ) {
            guard let contentBounds = combinedTeachingContentBounds(),
                  contentBounds.width > 0,
                  contentBounds.height > 0 else { return }

            let viewportSize = canvas.bounds.size
            guard viewportSize.width > 0, viewportSize.height > 0 else { return }

            let viewfinder = viewfinderRect(in: viewportSize)
            let targetWidth = viewfinder.width * marginFactor
            let targetHeight = viewfinder.height * marginFactor

            let zoomByWidth = targetWidth / contentBounds.width
            let zoomByHeight = targetHeight / contentBounds.height
            let targetZoom = min(
                max(min(zoomByWidth, zoomByHeight), canvas.minimumZoomScale),
                canvas.maximumZoomScale
            )

            let newContentOffset = CGPoint(
                x: contentBounds.midX * targetZoom - viewfinder.midX,
                y: contentBounds.midY * targetZoom - viewfinder.midY
            )

            canvas.setZoomScale(targetZoom, animated: animated)
            canvas.setContentOffset(newContentOffset, animated: animated)
            hostView?.updateBackgroundFrame(using: canvas)
            hostView?.updateTextObjectFrame(using: canvas)
        }

        private func combinedTeachingContentBounds() -> CGRect? {
            CanvasContentBounds.combinedBounds(
                drawingBounds: parent.drawing.bounds,
                backgroundSize: parent.background.flatMap { pdfPageBounds(for: $0)?.size },
                textObjects: parent.textObjects,
                canvasOrigin: PencilKitCanvasGeometry.drawingOriginOffset
            )
        }

        private func publishViewportState(from canvas: PKCanvasView) {
            parent.onViewportStateChange?(viewportState(from: canvas))
        }

        private func stabilizeBackgroundViewportIfNeeded(on canvas: PKCanvasView) {
            guard parent.background != nil else { return }

            let viewportSize = canvas.bounds.size
            guard viewportSize.width > 0, viewportSize.height > 0 else { return }

            let viewfinder = viewfinderRect(in: viewportSize)
            let overhangSlack = CGSize(
                width: max(viewfinder.width * 0.25, 160),
                height: max(viewfinder.height * 0.25, 160)
            )
            let minimumOffset = CGPoint(
                x: PencilKitCanvasGeometry.drawingOriginOffset.x * canvas.zoomScale - viewfinder.maxX + overhangSlack.width,
                y: PencilKitCanvasGeometry.drawingOriginOffset.y * canvas.zoomScale - viewfinder.maxY + overhangSlack.height
            )
            let stabilizedOffset = CGPoint(
                x: max(canvas.contentOffset.x, minimumOffset.x),
                y: max(canvas.contentOffset.y, minimumOffset.y)
            )

            guard stabilizedOffset != canvas.contentOffset else { return }
            canvas.setContentOffset(stabilizedOffset, animated: false)
        }

        private func publishViewportStateAfterViewUpdate(from canvas: PKCanvasView) {
            let state = viewportState(from: canvas)
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.parent.onViewportStateChange?(state)
            }
        }

        private func viewportState(from canvas: PKCanvasView) -> CanvasViewportState {
            CanvasViewportState(
                zoomScale: canvas.zoomScale,
                contentOffset: canvas.contentOffset,
                minimumZoomScale: canvas.minimumZoomScale,
                maximumZoomScale: canvas.maximumZoomScale
            )
        }

        func installLiveStrokeRecognizer(on canvas: PKCanvasView) {
            guard liveStrokeRecognizer == nil else { return }

            let recognizer = PencilLiveStrokeGestureRecognizer { [weak self] samples, phase in
                self?.publishLiveStroke(samples: samples, phase: phase)
            }
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            canvas.addGestureRecognizer(recognizer)
            liveStrokeRecognizer = recognizer
        }

        func installLaserStrokeRecognizer(on overlayView: CanvasLaserOverlayView, canvas: PKCanvasView) {
            guard laserStrokeRecognizer == nil else { return }

            let recognizer = PencilLiveStrokeGestureRecognizer { [weak self, weak overlayView, weak canvas] samples, phase in
                guard let self, let overlayView, let canvas else { return }
                let convertedSamples = self.canvasSamples(from: samples, overlayView: overlayView, canvas: canvas)
                self.publishLiveStroke(samples: convertedSamples, phase: phase)
            }
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            overlayView.addGestureRecognizer(recognizer)
            laserStrokeRecognizer = recognizer
        }

        func installTextPlacementRecognizer(on overlayView: CanvasTextPlacementOverlayView, canvas: PKCanvasView) {
            guard textPlacementRecognizer == nil else { return }

            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTextPlacementTap(_:)))
            recognizer.numberOfTouchesRequired = 1
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            canvas.addGestureRecognizer(recognizer)
            textPlacementRecognizer = recognizer
        }

        func installTextSelectionRecognizers(on canvas: PKCanvasView) {
            guard textSelectionTapRecognizer == nil else { return }

            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleTextSelectionDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = 2
            doubleTap.numberOfTouchesRequired = 1
            doubleTap.cancelsTouchesInView = false
            doubleTap.delaysTouchesBegan = false
            doubleTap.delaysTouchesEnded = false
            doubleTap.delegate = self
            canvas.addGestureRecognizer(doubleTap)

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTextSelectionTap(_:)))
            tap.numberOfTouchesRequired = 1
            tap.cancelsTouchesInView = false
            tap.delaysTouchesBegan = false
            tap.delaysTouchesEnded = false
            tap.delegate = self
            tap.require(toFail: doubleTap)
            canvas.addGestureRecognizer(tap)

            let pan = CanvasObjectDragGestureRecognizer(
                allowedTouchTypes: [.direct, .pencil],
                target: self,
                action: #selector(handleTextSelectionPan(_:))
            )
            pan.cancelsTouchesInView = true
            pan.delaysTouchesBegan = false
            pan.delaysTouchesEnded = false
            pan.delegate = self
            canvas.addGestureRecognizer(pan)
            canvas.panGestureRecognizer.require(toFail: pan)

            textSelectionTapRecognizer = tap
            textSelectionDoubleTapRecognizer = doubleTap
            textSelectionPanRecognizer = pan
        }

        func installTextEditorDismissRecognizer(on hostView: PencilKitCanvasHostView) {
            guard textEditorDismissRecognizer == nil else { return }

            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTextEditorDismissTap(_:)))
            recognizer.numberOfTouchesRequired = 1
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            hostView.addGestureRecognizer(recognizer)
            textPlacementRecognizer?.require(toFail: recognizer)
            textEditorDismissRecognizer = recognizer
        }

        func installRegionSelectionRecognizer(on hostView: PencilKitCanvasHostView) {
            guard regionSelectionRecognizer == nil else { return }

            let recognizer = PencilLiveStrokeGestureRecognizer(
                allowedTouchTypes: [.direct, .pencil]
            ) { [weak self, weak hostView] samples, phase in
                guard let self, let hostView else { return }
                self.handleRegionSelectionSamples(samples, phase: phase, hostView: hostView)
            }
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            hostView.addGestureRecognizer(recognizer)
            regionSelectionRecognizer = recognizer
        }

        @objc private func handleTextSelectionTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  isTextSelectionEnabled,
                  let canvas else {
                return
            }

            clearRegionSelection()
            let location = recognizer.location(in: canvas)
            if activeTextEditor != nil {
                handleActiveTextEditorTap(atCanvasPoint: location, on: canvas)
                return
            }
            if let id = hitTextResizeHandleID(at: location, on: canvas) {
                setSelectedTextObjectID(id)
                updateHostTextObjects(using: canvas)
                return
            }
            if let id = hitSelectedTextObjectID(at: location, on: canvas) {
                setSelectedTextObjectID(id)
                updateHostTextObjects(using: canvas)
                return
            }
            if let id = hitTextObjectID(at: location, on: canvas) {
                setSelectedTextObjectID(id)
            } else {
                setSelectedImageObjectID(hitImageObjectID(at: location, on: canvas))
            }
            updateHostTextObjects(using: canvas)
            updateHostImageObjects(using: canvas)
        }

        @objc private func handleTextEditorDismissTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  activeTextEditor != nil,
                  let hostView else {
                return
            }

            handleActiveTextEditorTap(atHostPoint: recognizer.location(in: hostView))
        }

        @objc private func handleTextSelectionDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  isTextSelectionEnabled,
                  activeTextEditor == nil,
                  let canvas,
                  let id = hitTextObjectID(at: recognizer.location(in: canvas), on: canvas),
                  let object = parent.textObjects.first(where: { $0.id == id }) else {
                return
            }

            clearRegionSelection()
            setSelectedTextObjectID(id)
            activeTextColor = CanvasStrokeColor(red: object.red, green: object.green, blue: object.blue, alpha: object.alpha)
            activeTextFontSize = object.fontSize
            activeTextIsBold = object.isBold
            activeTextIsItalic = object.isItalic
            activeTextIsUnderlined = object.isUnderlined
            activeTextFontName = object.fontName
            beginEditingTextObject(id, on: canvas, selectAll: false)
            updateHostTextObjects(using: canvas)
        }

        @objc private func handleTextSelectionPan(_ recognizer: CanvasObjectDragGestureRecognizer) {
            guard isTextSelectionEnabled,
                  activeTextEditor == nil,
                  let canvas else {
                return
            }

            switch recognizer.state {
            case .began:
                let startLocation = recognizer.location(in: canvas)
                if let id = hitTextResizeHandleID(at: startLocation, on: canvas),
                   let object = parent.textObjects.first(where: { $0.id == id }) {
                    parent.onInteractionBegan?()
                    clearRegionSelection()
                    setSelectedTextObjectID(id)
                    movingTextObjectID = nil
                    movingImageObjectID = nil
                    resizingTextObjectID = id
                    resizingTextObjectStartSize = CGSize(width: object.width, height: object.height)
                    resizingTextStartSourcePoint = sourcePoint(forCanvasPoint: startLocation, on: canvas)
                    updateHostTextObjects(using: canvas)
                    return
                }

                let textObjectHitID = hitSelectedTextObjectID(at: startLocation, on: canvas)
                    ?? hitTextObjectID(at: startLocation, on: canvas)
                guard let id = textObjectHitID,
                      let object = parent.textObjects.first(where: { $0.id == id }) else {
                    let imageObjectHitID = hitSelectedImageObjectID(at: startLocation, on: canvas)
                        ?? hitImageObjectID(at: startLocation, on: canvas)
                    if let id = imageObjectHitID,
                       let object = parent.imageObjects.first(where: { $0.id == id }) {
                        parent.onInteractionBegan?()
                        clearRegionSelection()
                        setSelectedImageObjectID(id)
                        movingTextObjectID = nil
                        resizingTextObjectID = nil
                        movingImageObjectID = id
                        movingImageObjectStartOrigin = CGPoint(x: object.x, y: object.y)
                        movingImageStartSourcePoint = sourcePoint(forCanvasPoint: startLocation, on: canvas)
                        updateHostImageObjects(using: canvas)
                        return
                    }
                    movingTextObjectID = nil
                    movingImageObjectID = nil
                    resizingTextObjectID = nil
                    return
                }
                parent.onInteractionBegan?()
                clearRegionSelection()
                setSelectedTextObjectID(id)
                movingTextObjectID = id
                movingImageObjectID = nil
                resizingTextObjectID = nil
                movingTextObjectStartOrigin = CGPoint(x: object.x, y: object.y)
                movingTextStartSourcePoint = sourcePoint(forCanvasPoint: startLocation, on: canvas)
                updateHostTextObjects(using: canvas)
            case .changed:
                if let resizingTextObjectID,
                   let index = parent.textObjects.firstIndex(where: { $0.id == resizingTextObjectID }) {
                    let currentSourcePoint = sourcePoint(forCanvasPoint: recognizer.location(in: canvas), on: canvas)
                    let delta = CGPoint(
                        x: currentSourcePoint.x - resizingTextStartSourcePoint.x,
                        y: currentSourcePoint.y - resizingTextStartSourcePoint.y
                    )
                    commitTextObjectUpdate(at: index, using: canvas) { object in
                        object.width = max(resizingTextObjectStartSize.width + delta.x, max(object.fontSize * 4, 80))
                        object.height = max(resizingTextObjectStartSize.height + delta.y, max(object.fontSize * 1.4, 36))
                    }
                    updateHostTextObjects(using: canvas)
                    publishImageFromModel()
                    return
                }

                if let movingTextObjectID,
                   let index = parent.textObjects.firstIndex(where: { $0.id == movingTextObjectID }) {
                    let currentSourcePoint = sourcePoint(forCanvasPoint: recognizer.location(in: canvas), on: canvas)
                    let delta = CGPoint(
                        x: currentSourcePoint.x - movingTextStartSourcePoint.x,
                        y: currentSourcePoint.y - movingTextStartSourcePoint.y
                    )
                    commitTextObjectUpdate(at: index, using: canvas) { object in
                        object.x = movingTextObjectStartOrigin.x + delta.x
                        object.y = movingTextObjectStartOrigin.y + delta.y
                    }
                    updateHostTextObjects(using: canvas)
                    publishImageFromModel()
                }
                if let movingImageObjectID,
                   let index = parent.imageObjects.firstIndex(where: { $0.id == movingImageObjectID }) {
                    let currentSourcePoint = sourcePoint(forCanvasPoint: recognizer.location(in: canvas), on: canvas)
                    let delta = CGPoint(
                        x: currentSourcePoint.x - movingImageStartSourcePoint.x,
                        y: currentSourcePoint.y - movingImageStartSourcePoint.y
                    )
                    var imageObjects = parent.imageObjects
                    imageObjects[index].x = movingImageObjectStartOrigin.x + delta.x
                    imageObjects[index].y = movingImageObjectStartOrigin.y + delta.y
                    parent.imageObjects = imageObjects
                    updateHostImageObjects(using: canvas)
                    publishImageFromModel()
                }
            case .ended, .cancelled, .failed:
                movingTextObjectID = nil
                movingImageObjectID = nil
                resizingTextObjectID = nil
                publishImageFromModel()
            default:
                break
            }
        }

        private func handleRegionSelectionSamples(
            _ samples: [CanvasLiveStrokePoint],
            phase: PencilLiveStrokeGestureRecognizer.Phase,
            hostView: PencilKitCanvasHostView
        ) {
            guard isRegionSelectionEnabled,
                  activeTextEditor == nil,
                  let canvas else {
                activeRegionConsumedSampleCount = 0
                return
            }

            let overlayView = hostView.regionSelectionOverlayView

            switch phase {
            case .began:
                parent.onInteractionBegan?()
                setSelectedTextObjectID(nil)
                activeRegionSelection = nil
                activeRegionSourcePoints = []
                activeRegionOverlayPoints = []
                activeRegionConsumedSampleCount = 0
                activeRegionSelectedTextObjectIDs = []
                activeRegionSelectedImageObjectIDs = []
                activeRegionSelectedStrokeIndexes = []
                let newOverlayPoints = appendRegionSelectionSamples(
                    samples,
                    hostView: hostView,
                    overlayView: overlayView,
                    canvas: canvas
                )
                guard let firstPoint = activeRegionOverlayPoints.first else { return }
                overlayView.begin(
                    at: firstPoint,
                    mode: CanvasRegionSelectionOverlayView.Mode(activeRegionSelectionMode)
                )
                overlayView.update(with: Array(newOverlayPoints.dropFirst()))
            case .moved:
                let newOverlayPoints = appendRegionSelectionSamples(
                    samples,
                    hostView: hostView,
                    overlayView: overlayView,
                    canvas: canvas
                )
                overlayView.update(with: newOverlayPoints)
                updateActiveRegionSelection()
                updateRegionSelectionTargetState(using: canvas)
            case .ended, .cancelled:
                let newOverlayPoints = appendRegionSelectionSamples(
                    samples,
                    hostView: hostView,
                    overlayView: overlayView,
                    canvas: canvas
                )
                overlayView.update(with: newOverlayPoints)
                closeActiveRegionSourceLassoIfNeeded()
                overlayView.closeLasso()
                updateActiveRegionSelection()
                updateRegionSelectionTargetState(using: canvas)
                if activeSelectionTarget == .object {
                    overlayView.finishSelectionShape()
                }
                activeRegionConsumedSampleCount = 0
                publishImageFromModel()
            }
        }

        private func appendRegionSelectionSamples(
            _ samples: [CanvasLiveStrokePoint],
            hostView: PencilKitCanvasHostView,
            overlayView: CanvasRegionSelectionOverlayView,
            canvas: PKCanvasView
        ) -> [CGPoint] {
            guard activeRegionConsumedSampleCount < samples.count else { return [] }

            let newSamples = samples.dropFirst(activeRegionConsumedSampleCount)
            activeRegionConsumedSampleCount = samples.count

            var newOverlayPoints: [CGPoint] = []
            for sample in newSamples {
                let overlayPoint = hostView.convert(sample.location, to: overlayView)
                if let last = activeRegionOverlayPoints.last,
                   hypot(last.x - overlayPoint.x, last.y - overlayPoint.y) < 1 {
                    continue
                }

                let canvasPoint = hostView.convert(sample.location, to: canvas)
                let sourcePoint = sourcePoint(forCanvasPoint: canvasPoint, on: canvas)
                activeRegionOverlayPoints.append(overlayPoint)
                activeRegionSourcePoints.append(sourcePoint)
                newOverlayPoints.append(overlayPoint)
            }

            return newOverlayPoints
        }

        private func updateRegionSelectionTargetState(using canvas: PKCanvasView) {
            if activeSelectionTarget == .object {
                updateActiveRegionTargets(using: canvas)
            } else {
                clearObjectRegionTargets()
            }
        }

        private func clearRegionSelection() {
            activeRegionSelection = nil
            activeRegionSourcePoints = []
            clearObjectRegionTargets()
            hostView?.regionSelectionOverlayView.clear()
        }

        private func clearObjectRegionTargets() {
            activeRegionSelectedTextObjectIDs = []
            activeRegionSelectedImageObjectIDs = []
            activeRegionSelectedStrokeIndexes = []
            hostView?.regionSelectionOverlayView.updateSelectedRects([])
        }

        private func updateActiveRegionSelection() {
            switch activeRegionSelectionMode {
            case .lasso:
                guard activeRegionSourcePoints.count > 2 else {
                    activeRegionSelection = nil
                    return
                }
                activeRegionSelection = .lasso(activeRegionSourcePoints)
            case .marquee:
                guard let first = activeRegionSourcePoints.first,
                      let last = activeRegionSourcePoints.last else {
                    activeRegionSelection = nil
                    return
                }
                activeRegionSelection = .marquee(CGRect(
                    x: min(first.x, last.x),
                    y: min(first.y, last.y),
                    width: abs(last.x - first.x),
                    height: abs(last.y - first.y)
                ))
            }
        }

        private func closeActiveRegionSourceLassoIfNeeded() {
            guard activeRegionSelectionMode == .lasso,
                  let first = activeRegionSourcePoints.first,
                  let last = activeRegionSourcePoints.last,
                  hypot(last.x - first.x, last.y - first.y) > 1 else {
                return
            }
            activeRegionSourcePoints.append(first)
        }

        private func updateActiveRegionTargets(using canvas: PKCanvasView) {
            guard let activeRegionSelection else {
                activeRegionSelectedTextObjectIDs = []
                activeRegionSelectedImageObjectIDs = []
                activeRegionSelectedStrokeIndexes = []
                hostView?.regionSelectionOverlayView.updateSelectedRects([])
                return
            }

            activeRegionSelectedTextObjectIDs = Set(parent.textObjects.compactMap { object in
                !object.text.isEmpty && activeRegionSelection.intersects(object.frame) ? object.id : nil
            })
            activeRegionSelectedImageObjectIDs = Set(parent.imageObjects.compactMap { object in
                object.isLocked == true ? nil : (activeRegionSelection.intersects(object.frame) ? object.id : nil)
            })
            activeRegionSelectedStrokeIndexes = []
            updateRegionSelectionHighlight(on: canvas)
        }

        private func updateRegionSelectionHighlight(on canvas: PKCanvasView) {
            let textRects = parent.textObjects.compactMap { object -> CGRect? in
                guard activeRegionSelectedTextObjectIDs.contains(object.id) else { return nil }
                return overlayRect(forSourceRect: object.frame, on: canvas)
            }
            let imageRects = parent.imageObjects.compactMap { object -> CGRect? in
                guard activeRegionSelectedImageObjectIDs.contains(object.id) else { return nil }
                return overlayRect(forSourceRect: object.frame, on: canvas)
            }
            hostView?.regionSelectionOverlayView.updateSelectedRects(textRects + imageRects)
        }

        private func hitTextResizeHandleID(at canvasPoint: CGPoint, on canvas: PKCanvasView) -> UUID? {
            let sourcePoint = sourcePoint(forCanvasPoint: canvasPoint, on: canvas)
            let selectedID = selectedTextObjectID ?? selectedTextObjectIDFromSharedState

            if let selectedID,
               let object = parent.textObjects.first(where: { $0.id == selectedID }),
               textResizeHandleRect(for: object, on: canvas).contains(sourcePoint) {
                return object.id
            }

            return parent.textObjects.reversed().first { object in
                !object.text.isEmpty && textResizeHandleRect(for: object, on: canvas).contains(sourcePoint)
            }?.id
        }

        private func hitSelectedTextObjectID(at canvasPoint: CGPoint, on canvas: PKCanvasView) -> UUID? {
            guard let selectedTextObjectID = selectedTextObjectID ?? selectedTextObjectIDFromSharedState,
                  let object = parent.textObjects.first(where: { $0.id == selectedTextObjectID }),
                  !object.text.isEmpty else {
                return nil
            }

            let sourcePoint = sourcePoint(forCanvasPoint: canvasPoint, on: canvas)
            let hitMargin = selectedObjectDragHitMargin(on: canvas)
            return object.frame.insetBy(dx: -hitMargin, dy: -hitMargin).contains(sourcePoint) ? object.id : nil
        }

        private var selectedTextObjectIDFromSharedState: UUID? {
            guard case .text(let id) = parent.selectionState.selectedObject else {
                return nil
            }
            return id
        }

        private func hitTextObjectID(at canvasPoint: CGPoint, on canvas: PKCanvasView) -> UUID? {
            let sourcePoint = sourcePoint(forCanvasPoint: canvasPoint, on: canvas)
            let hitMargin = max(16 / max(canvas.zoomScale, 0.001), 4)
            return parent.textObjects.reversed().first { object in
                !object.text.isEmpty && object.frame.insetBy(dx: -hitMargin, dy: -hitMargin).contains(sourcePoint)
            }?.id
        }

        private func hitSelectedImageObjectID(at canvasPoint: CGPoint, on canvas: PKCanvasView) -> UUID? {
            guard let selectedImageObjectID,
                  let object = parent.imageObjects.first(where: { $0.id == selectedImageObjectID }),
                  object.isLocked != true else {
                return nil
            }

            let sourcePoint = sourcePoint(forCanvasPoint: canvasPoint, on: canvas)
            let hitMargin = selectedObjectDragHitMargin(on: canvas)
            return object.frame.insetBy(dx: -hitMargin, dy: -hitMargin).contains(sourcePoint) ? object.id : nil
        }

        private func selectedObjectDragHitMargin(on canvas: PKCanvasView) -> CGFloat {
            max(72 / max(canvas.zoomScale, 0.001), 24)
        }

        private func textResizeHandleRect(for object: CanvasTextObject, on canvas: PKCanvasView) -> CGRect {
            let handleSize = max(44 / max(canvas.zoomScale, 0.001), 18)
            return CGRect(
                x: object.frame.maxX - handleSize,
                y: object.frame.maxY - handleSize,
                width: handleSize * 1.75,
                height: handleSize * 1.75
            )
        }

        private func hitImageObjectID(at canvasPoint: CGPoint, on canvas: PKCanvasView) -> UUID? {
            let sourcePoint = sourcePoint(forCanvasPoint: canvasPoint, on: canvas)
            let hitMargin = max(16 / max(canvas.zoomScale, 0.001), 4)
            return parent.imageObjects.reversed().first { object in
                object.isLocked != true
                    && object.frame.insetBy(dx: -hitMargin, dy: -hitMargin).contains(sourcePoint)
            }?.id
        }

        private func setSelectedTextObjectID(_ id: UUID?) {
            guard selectedTextObjectID != id
                    || selectedImageObjectID != nil
                    || parent.selectionState.selectedObject != id.map(CanvasSelectionState.Object.text) else {
                return
            }
            selectedTextObjectID = id
            selectedImageObjectID = nil
            if let id {
                lastSelectedTextObjectID = id
            }
            updateSharedSelectionState()
        }

        private func setSelectedImageObjectID(_ id: UUID?) {
            guard selectedImageObjectID != id
                    || selectedTextObjectID != nil
                    || parent.selectionState.selectedObject != id.map(CanvasSelectionState.Object.image) else {
                return
            }
            selectedImageObjectID = id
            selectedTextObjectID = nil
            if let id {
                lastSelectedImageObjectID = id
            }
            updateSharedSelectionState()
        }

        private func updateSharedSelectionState() {
            if let selectedTextObjectID,
               let object = parent.textObjects.first(where: { $0.id == selectedTextObjectID }) {
                parent.selectionState = CanvasSelectionState(
                    selectedObject: .text(object.id),
                    selectedTextObject: object,
                    viewportFrame: canvas.map { viewportFrame(for: object, on: $0) }
                )
            } else if let selectedImageObjectID,
                      let object = parent.imageObjects.first(where: { $0.id == selectedImageObjectID }) {
                parent.selectionState = CanvasSelectionState(
                    selectedObject: .image(object.id),
                    viewportFrame: canvas.map { overlayRect(forSourceRect: object.frame, on: $0) }
                )
            } else {
                parent.selectionState = CanvasSelectionState()
            }
        }

        private func duplicateSelectedTextObject(using canvas: PKCanvasView) {
            finishTextEditing()
            if activeSelectionTarget == .region {
                _ = duplicateSelectedRegionAsImageObject(using: canvas)
                return
            }
            if duplicateSelectedRegion(using: canvas) {
                return
            }
            if let targetID = selectedImageObjectID ?? lastSelectedImageObjectID {
                duplicateImageObject(targetID, using: canvas)
                return
            }
            guard let targetID = selectedTextObjectID ?? lastSelectedTextObjectID,
                  let object = parent.textObjects.first(where: { $0.id == targetID }) else {
                return
            }
            duplicateTextObject(targetID, object: object, using: canvas)
        }

        private func duplicateTextObject(_ id: UUID, using canvas: PKCanvasView) {
            guard let object = parent.textObjects.first(where: { $0.id == id }) else { return }
            duplicateTextObject(id, object: object, using: canvas)
        }

        private func duplicateTextObject(_ id: UUID, object: CanvasTextObject, using canvas: PKCanvasView) {
            parent.onInteractionBegan?()
            let offset = max(24 / max(canvas.zoomScale, 0.001), 12)
            let duplicate = CanvasTextObject(
                text: object.text,
                x: object.x + offset,
                y: object.y + offset,
                width: object.width,
                height: object.height,
                fontSize: object.fontSize,
                red: object.red,
                green: object.green,
                blue: object.blue,
                alpha: object.alpha,
                isBold: object.isBold,
                isItalic: object.isItalic,
                isUnderlined: object.isUnderlined,
                fontName: object.fontName
            )
            var textObjects = parent.textObjects
            textObjects.append(duplicate)
            parent.textObjects = textObjects
            setSelectedTextObjectID(duplicate.id)
            updateHostTextObjects(using: canvas)
            publishImageFromModel()
        }

        private func deleteSelectedTextObject(using canvas: PKCanvasView) {
            finishTextEditing()
            if activeSelectionTarget == .region {
                _ = fillSelectedRegionWithBackground(using: canvas)
                return
            }
            if deleteSelectedRegion(using: canvas) {
                return
            }
            if let targetID = selectedImageObjectID ?? lastSelectedImageObjectID {
                deleteImageObject(targetID, using: canvas)
                return
            }
            guard let targetID = selectedTextObjectID ?? lastSelectedTextObjectID,
                  let index = parent.textObjects.firstIndex(where: { $0.id == targetID }) else {
                return
            }
            deleteTextObject(at: index, using: canvas)
        }

        private func deleteTextObject(_ id: UUID, using canvas: PKCanvasView) {
            guard let index = parent.textObjects.firstIndex(where: { $0.id == id }) else { return }
            deleteTextObject(at: index, using: canvas)
        }

        private func deleteTextObject(at index: Int, using canvas: PKCanvasView) {
            parent.onInteractionBegan?()
            var textObjects = parent.textObjects
            textObjects.remove(at: index)
            parent.textObjects = textObjects
            setSelectedTextObjectID(nil)
            lastSelectedTextObjectID = nil
            movingTextObjectID = nil
            resizingTextObjectID = nil
            updateHostTextObjects(using: canvas)
            publishImageFromModel()
        }

        private func duplicateImageObject(_ id: UUID, using canvas: PKCanvasView) {
            guard let object = parent.imageObjects.first(where: { $0.id == id }) else { return }
            parent.onInteractionBegan?()
            let offset = max(24 / max(canvas.zoomScale, 0.001), 12)
            let duplicate = CanvasImageObject(
                imageFileName: object.imageFileName,
                x: object.x + offset,
                y: object.y + offset,
                width: object.width,
                height: object.height
            )
            parent.imageObjects.append(duplicate)
            setSelectedImageObjectID(duplicate.id)
            updateHostImageObjects(using: canvas)
            publishImageFromModel()
        }

        private func deleteImageObject(_ id: UUID, using canvas: PKCanvasView) {
            guard parent.imageObjects.contains(where: { $0.id == id }) else { return }
            parent.onInteractionBegan?()
            parent.imageObjects.removeAll { $0.id == id }
            setSelectedImageObjectID(nil)
            lastSelectedImageObjectID = nil
            movingImageObjectID = nil
            updateHostImageObjects(using: canvas)
            publishImageFromModel()
        }

        private func copySelectedRegionToPasteboard(using canvas: PKCanvasView) {
            guard let snapshot = makeRegionSnapshot() else { return }
            UIPasteboard.general.image = snapshot.image
        }

        private func extractSelectedRegionAsImageSticker(using canvas: PKCanvasView) {
            _ = duplicateSelectedRegionAsImageObject(using: canvas)
        }

        private func sendSelectedRegionToNextSlide(using canvas: PKCanvasView) {
            guard let snapshot = makeRegionSnapshot() else { return }
            parent.onExtractedRegionSend?(CanvasExtractedRegion(
                pngData: snapshot.pngData,
                sourceBounds: snapshot.sourceBounds
            ))
            clearRegionSelection()
            publishImageFromModel()
        }

        private func fillSelectedRegionWithBackground(using canvas: PKCanvasView) -> Bool {
            guard let activeRegionSelection else { return false }
            let sourceBounds = normalizedRegionBounds(activeRegionSelection.bounds)
            guard sourceBounds.width >= 2, sourceBounds.height >= 2 else { return false }

            let destinationSize = CGSize(
                width: max(sourceBounds.width, 1),
                height: max(sourceBounds.height, 1)
            )
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            format.opaque = false
            let image = UIGraphicsImageRenderer(size: destinationSize, format: format).image { rendererContext in
                let context = rendererContext.cgContext
                context.clear(CGRect(origin: .zero, size: destinationSize))
                context.saveGState()
                applyRegionClip(activeRegionSelection, sourceBounds: sourceBounds, in: context)
                context.setFillColor(UIColor.white.cgColor)
                context.fill(CGRect(origin: .zero, size: destinationSize))
                context.restoreGState()
            }
            guard let pngData = image.pngData() else { return false }
            guard saveRegionImageObject(
                pngData: pngData,
                sourceBounds: sourceBounds,
                offset: .zero,
                selectAfterInsert: false,
                isLocked: true,
                using: canvas
            ) else {
                return false
            }
            clearRegionSelection()
            publishImageFromModel()
            return true
        }

        private func makeRegionSnapshot() -> (image: UIImage, pngData: Data, sourceBounds: CGRect)? {
            guard let activeRegionSelection else { return nil }
            let sourceBounds = normalizedRegionBounds(activeRegionSelection.bounds)
            guard sourceBounds.width >= 2, sourceBounds.height >= 2 else { return nil }
            let image = renderRegionSnapshot(selection: activeRegionSelection, sourceBounds: sourceBounds)
            guard let pngData = image.pngData() else { return nil }
            return (image, pngData, sourceBounds)
        }

        private func normalizedRegionBounds(_ bounds: CGRect) -> CGRect {
            bounds.integral.insetBy(dx: -2, dy: -2)
        }

        private func saveRegionImageObject(
            pngData: Data,
            sourceBounds: CGRect,
            offset: CGPoint,
            selectAfterInsert: Bool,
            isLocked: Bool = false,
            using canvas: PKCanvasView
        ) -> Bool {
            let fileName = "\(UUID().uuidString).png"
            let assetDirectoryURL = CanvasImageObject.assetDirectoryURL(forDrawingURL: parent.drawingURL)
            let assetURL = assetDirectoryURL.appendingPathComponent(fileName)
            do {
                try FileManager.default.createDirectory(
                    at: assetDirectoryURL,
                    withIntermediateDirectories: true
                )
                try pngData.write(to: assetURL, options: .atomic)
            } catch {
                print("[Canvas] region snapshot save error: \(error)")
                return false
            }

            parent.onInteractionBegan?()
            let imageObject = CanvasImageObject(
                imageFileName: fileName,
                x: sourceBounds.minX + offset.x,
                y: sourceBounds.minY + offset.y,
                width: sourceBounds.width,
                height: sourceBounds.height,
                isLocked: isLocked ? true : nil
            )
            parent.imageObjects.append(imageObject)
            if selectAfterInsert {
                setSelectedImageObjectID(imageObject.id)
            }
            updateHostImageObjects(using: canvas)
            return true
        }

        private func duplicateSelectedRegion(using canvas: PKCanvasView) -> Bool {
            guard activeRegionSelection != nil else { return false }
            let matchingTextObjects = parent.textObjects.filter { object in
                activeRegionSelectedTextObjectIDs.contains(object.id)
            }
            let matchingImageObjects = parent.imageObjects.filter { object in
                activeRegionSelectedImageObjectIDs.contains(object.id)
            }
            let matchingStrokeIndexes = activeRegionSelectedStrokeIndexes.sorted()
            guard !matchingTextObjects.isEmpty || !matchingImageObjects.isEmpty || !matchingStrokeIndexes.isEmpty else { return false }

            parent.onInteractionBegan?()
            let offset = max(24 / max(canvas.zoomScale, 0.001), 12)
            if !matchingTextObjects.isEmpty {
                let duplicates = matchingTextObjects.map { object in
                    CanvasTextObject(
                        text: object.text,
                        x: object.x + offset,
                        y: object.y + offset,
                        width: object.width,
                        height: object.height,
                        fontSize: object.fontSize,
                        red: object.red,
                        green: object.green,
                        blue: object.blue,
                        alpha: object.alpha,
                        isBold: object.isBold,
                        isItalic: object.isItalic,
                        isUnderlined: object.isUnderlined,
                        fontName: object.fontName
                    )
                }
                parent.textObjects.append(contentsOf: duplicates)
            }
            if !matchingImageObjects.isEmpty {
                let duplicates = matchingImageObjects.map { object in
                    CanvasImageObject(
                        imageFileName: object.imageFileName,
                        x: object.x + offset,
                        y: object.y + offset,
                        width: object.width,
                        height: object.height
                    )
                }
                parent.imageObjects.append(contentsOf: duplicates)
            }

            if !matchingStrokeIndexes.isEmpty {
                let strokes = parent.drawing.strokes
                let duplicateStrokes = matchingStrokeIndexes.map { index in
                    strokes[index].translatedBy(x: offset, y: offset)
                }
                parent.drawing = PKDrawing(strokes: strokes + duplicateStrokes)
                canvas.drawing = parent.drawing
            }

            setSelectedTextObjectID(nil)
            updateHostTextObjects(using: canvas)
            updateHostImageObjects(using: canvas)
            updateActiveRegionTargets(using: canvas)
            publishImageFromModel()
            return true
        }

        private func deleteSelectedRegion(using canvas: PKCanvasView) -> Bool {
            guard activeRegionSelection != nil else { return false }
            let matchingTextIDs = activeRegionSelectedTextObjectIDs
            let matchingImageIDs = activeRegionSelectedImageObjectIDs
            let matchingStrokeIndexes = activeRegionSelectedStrokeIndexes
            guard !matchingTextIDs.isEmpty || !matchingImageIDs.isEmpty || !matchingStrokeIndexes.isEmpty else { return false }

            parent.onInteractionBegan?()
            if !matchingTextIDs.isEmpty {
                parent.textObjects.removeAll { matchingTextIDs.contains($0.id) }
            }
            if !matchingImageIDs.isEmpty {
                parent.imageObjects.removeAll { matchingImageIDs.contains($0.id) }
            }
            if !matchingStrokeIndexes.isEmpty {
                let remainingStrokes = parent.drawing.strokes.enumerated().compactMap { index, stroke in
                    matchingStrokeIndexes.contains(index) ? nil : stroke
                }
                parent.drawing = PKDrawing(strokes: remainingStrokes)
                canvas.drawing = parent.drawing
            }

            setSelectedTextObjectID(nil)
            lastSelectedTextObjectID = nil
            movingTextObjectID = nil
            resizingTextObjectID = nil
            clearRegionSelection()
            updateHostTextObjects(using: canvas)
            updateHostImageObjects(using: canvas)
            publishImageFromModel()
            return true
        }

        private func duplicateSelectedRegionAsImageObject(using canvas: PKCanvasView) -> Bool {
            guard let snapshot = makeRegionSnapshot() else { return false }
            let offset = max(24 / max(canvas.zoomScale, 0.001), 12)
            guard saveRegionImageObject(
                pngData: snapshot.pngData,
                sourceBounds: snapshot.sourceBounds,
                offset: CGPoint(x: offset, y: offset),
                selectAfterInsert: true,
                using: canvas
            ) else {
                return false
            }
            clearRegionSelection()
            publishImageFromModel()
            return true
        }

        private func renderRegionSnapshot(
            selection: RegionSelection,
            sourceBounds: CGRect
        ) -> UIImage {
            let destinationSize = CGSize(
                width: max(sourceBounds.width, 1),
                height: max(sourceBounds.height, 1)
            )
            let destinationRect = CGRect(origin: .zero, size: destinationSize)
            let canvasSourceRect = sourceBounds.offsetBy(
                dx: PencilKitCanvasGeometry.drawingOriginOffset.x,
                dy: PencilKitCanvasGeometry.drawingOriginOffset.y
            )
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            format.opaque = false

            return UIGraphicsImageRenderer(size: destinationSize, format: format).image { rendererContext in
                let context = rendererContext.cgContext
                context.clear(destinationRect)
                context.saveGState()
                applyRegionClip(selection, sourceBounds: sourceBounds, in: context)
                drawBackground(
                    in: context,
                    sourceRect: canvasSourceRect,
                    destinationRect: destinationRect
                )
                parent.drawing.image(from: canvasSourceRect, scale: format.scale).draw(in: destinationRect)
                drawImageObjects(
                    in: context,
                    sourceRect: canvasSourceRect,
                    destinationRect: destinationRect
                )
                drawTextObjects(
                    in: context,
                    sourceRect: canvasSourceRect,
                    destinationRect: destinationRect
                )
                context.restoreGState()
            }
        }

        private func applyRegionClip(
            _ selection: RegionSelection,
            sourceBounds: CGRect,
            in context: CGContext
        ) {
            switch selection {
            case .marquee:
                context.clip(to: CGRect(origin: .zero, size: sourceBounds.size))
            case .lasso(let points):
                guard points.count > 2 else {
                    context.clip(to: CGRect(origin: .zero, size: sourceBounds.size))
                    return
                }
                let path = UIBezierPath()
                path.move(to: CGPoint(
                    x: points[0].x - sourceBounds.minX,
                    y: points[0].y - sourceBounds.minY
                ))
                for point in points.dropFirst() {
                    path.addLine(to: CGPoint(
                        x: point.x - sourceBounds.minX,
                        y: point.y - sourceBounds.minY
                    ))
                }
                path.close()
                path.addClip()
            }
        }

        private func selectedStrokeIndexes(in selection: RegionSelection) -> [Int] {
            parent.drawing.strokes.enumerated().compactMap { index, stroke in
                selection.intersects(sourceBounds(for: stroke)) ? index : nil
            }
        }

        private func sourceBounds(for stroke: PKStroke) -> CGRect {
            stroke.renderBounds
                .applying(PencilKitCanvasGeometry.canvasToStorageTransform)
                .insetBy(dx: -8, dy: -8)
        }

        private func overlayRect(forSourceRect sourceRect: CGRect, on canvas: PKCanvasView) -> CGRect {
            let zoomScale = max(canvas.zoomScale, 0.001)
            let origin = PencilKitCanvasGeometry.drawingOriginOffset
            return CGRect(
                x: (sourceRect.minX + origin.x) * zoomScale - canvas.contentOffset.x,
                y: (sourceRect.minY + origin.y) * zoomScale - canvas.contentOffset.y,
                width: sourceRect.width * zoomScale,
                height: sourceRect.height * zoomScale
            )
        }

        private func sourcePoint(forCanvasPoint canvasPoint: CGPoint, on canvas: PKCanvasView) -> CGPoint {
            let zoomScale = max(canvas.zoomScale, 0.001)
            return CGPoint(
                x: canvasPoint.x / zoomScale - PencilKitCanvasGeometry.drawingOriginOffset.x,
                y: canvasPoint.y / zoomScale - PencilKitCanvasGeometry.drawingOriginOffset.y
            )
        }

        @objc private func handleTextPlacementTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let canvas,
                  hostView?.textPlacementOverlayView.acceptsTextPlacement == true,
                  let activeTextColor else {
                return
            }

            let canvasPoint = recognizer.location(in: canvas)
            if activeTextEditor != nil {
                handleActiveTextEditorTap(atCanvasPoint: canvasPoint, on: canvas)
                return
            }

            let sourcePoint = sourcePoint(forCanvasPoint: canvasPoint, on: canvas)
            parent.onInteractionBegan?()
            parent.onTextPlacementRequested?(sourcePoint)
        }

        private func insertTextObject(_ insertion: CanvasTextInsertion, using canvas: PKCanvasView) {
            let text = insertion.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }

            parent.onInteractionBegan?()
            let size = measuredTextObjectSize(for: insertion)
            let textObject = CanvasTextObject(
                text: text,
                x: insertion.sourcePoint.x,
                y: insertion.sourcePoint.y,
                width: size.width,
                height: size.height,
                fontSize: insertion.fontSize,
                red: insertion.color.red,
                green: insertion.color.green,
                blue: insertion.color.blue,
                alpha: insertion.color.alpha,
                isBold: insertion.isBold,
                isItalic: insertion.isItalic,
                isUnderlined: insertion.isUnderlined,
                fontName: insertion.fontName
            )

            var textObjects = parent.textObjects
            textObjects.append(textObject)
            parent.textObjects = textObjects
            setSelectedTextObjectID(textObject.id)
            updateHostTextObjects(using: canvas)
            publishImageFromModel()
        }

        private func updateTextObject(_ update: CanvasTextUpdate, using canvas: PKCanvasView) {
            let text = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty,
                  let index = parent.textObjects.firstIndex(where: { $0.id == update.id }) else {
                return
            }

            parent.onInteractionBegan?()
            commitTextObjectUpdate(at: index, using: canvas) { object in
                object.text = text
                object.fontSize = update.fontSize
                object.isBold = update.isBold
                object.isItalic = update.isItalic
                object.isUnderlined = update.isUnderlined
                object.fontName = update.fontName

                if update.expandsToFitContent {
                    let fittedSize = measuredTextObjectSize(for: object)
                    object.width = max(object.width, fittedSize.width)
                    object.height = max(object.height, fittedSize.height)
                }
            }
            setSelectedTextObjectID(update.id)
            updateHostTextObjects(using: canvas)
            publishImageFromModel()
        }

        private func measuredTextObjectSize(for insertion: CanvasTextInsertion) -> CGSize {
            let fontSize = min(max(insertion.fontSize, 8), 96)
            let sizingObject = CanvasTextObject(
                text: insertion.text,
                x: 0,
                y: 0,
                width: 1,
                height: 1,
                fontSize: fontSize,
                red: insertion.color.red,
                green: insertion.color.green,
                blue: insertion.color.blue,
                alpha: insertion.color.alpha,
                isBold: insertion.isBold,
                isItalic: insertion.isItalic,
                isUnderlined: insertion.isUnderlined,
                fontName: insertion.fontName
            )
            let attributes = sizingObject.textAttributes(size: fontSize)
            let maximumWidth: CGFloat = 900
            if let mathSize = CanvasMathTextRenderer.fittingSize(for: sizingObject, maxWidth: maximumWidth) {
                return mathSize
            }
            let boundingSize = CGSize(width: maximumWidth, height: .greatestFiniteMagnitude)
            let bounds = (insertion.text as NSString).boundingRect(
                with: boundingSize,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            ).integral
            return CGSize(
                width: min(max(bounds.width + 28, max(fontSize * 5, 160)), maximumWidth),
                height: max(bounds.height + 20, max(fontSize * 1.6, 44))
            )
        }

        private func measuredTextObjectSize(for object: CanvasTextObject) -> CGSize {
            let fontSize = min(max(object.fontSize, 8), 96)
            let attributes = object.textAttributes(size: fontSize)
            let maximumWidth: CGFloat = 900
            if let mathSize = CanvasMathTextRenderer.fittingSize(for: object, maxWidth: maximumWidth) {
                return mathSize
            }
            let boundingSize = CGSize(width: maximumWidth, height: .greatestFiniteMagnitude)
            let bounds = (object.text as NSString).boundingRect(
                with: boundingSize,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            ).integral
            return CGSize(
                width: min(max(bounds.width + 28, max(fontSize * 5, 160)), maximumWidth),
                height: max(bounds.height + 20, max(fontSize * 1.6, 44))
            )
        }

        private func applyActiveTextStyleToSelectedObject(using canvas: PKCanvasView) {
            guard let index = activeTextObjectIndex else {
                return
            }

            let updatedObject = commitTextObjectUpdate(at: index, using: canvas) { object in
                object.fontSize = activeTextFontSize
                if let activeTextColor {
                    object.red = activeTextColor.red
                    object.green = activeTextColor.green
                    object.blue = activeTextColor.blue
                    object.alpha = activeTextColor.alpha
                }
                object.isBold = activeTextIsBold
                object.isItalic = activeTextIsItalic
                object.isUnderlined = activeTextIsUnderlined
                object.fontName = activeTextFontName
            }
            if let updatedObject {
                updateActiveTextEditorContent(from: updatedObject, on: canvas)
            }
            updateHostTextObjects(using: canvas)
            publishImageFromModel()
        }

        var activeEditingTextObjectID: UUID? {
            activeTextEditor == nil ? nil : activeTextObjectID
        }

        var selectedTextObjectForDisplayID: UUID? {
            guard activeTextEditor == nil,
                  case .text(let id) = parent.selectionState.selectedObject else {
                return nil
            }
            return id
        }

        var selectedImageObjectForDisplayID: UUID? {
            guard activeTextEditor == nil,
                  case .image(let id) = parent.selectionState.selectedObject else {
                return nil
            }
            return id
        }

        private var activeTextObjectIndex: Int? {
            if let activeTextObjectID,
               let index = parent.textObjects.firstIndex(where: { $0.id == activeTextObjectID }) {
                return index
            }
            guard activeTextEditor != nil else { return nil }
            guard let index = parent.textObjects.indices.last else { return nil }
            activeTextObjectID = parent.textObjects[index].id
            return index
        }

        private func beginEditingTextObject(_ id: UUID, on canvas: PKCanvasView, selectAll: Bool) {
            guard let hostView,
                  let object = parent.textObjects.first(where: { $0.id == id }) else {
                return
            }

            let textView = activeTextEditor ?? UITextView()
            activeTextObjectID = id
            if activeTextEditor == nil {
                textView.delegate = self
                textView.backgroundColor = UIColor.white.withAlphaComponent(0.20)
                textView.layer.borderColor = UIColor.systemBlue.cgColor
                textView.layer.borderWidth = 2
                textView.layer.cornerRadius = 5
                textView.textContainerInset = UIEdgeInsets(top: 2, left: 3, bottom: 2, right: 3)
                textView.textContainer.lineFragmentPadding = 0
                textView.isScrollEnabled = false
                textView.keyboardDismissMode = .interactive
                textView.autocorrectionType = .yes
                textView.spellCheckingType = .yes
                textView.smartDashesType = .no
                textView.smartQuotesType = .no
                hostView.addSubview(textView)
                activeTextEditor = textView
            }

            updateActiveTextEditorContent(from: object, on: canvas)
            updateActiveTextEditorFrame(on: canvas)
            textView.becomeFirstResponder()
            parent.onTextEditingBegan?()
            if selectAll {
                textView.selectedRange = NSRange(location: 0, length: (textView.text as NSString).length)
            }
        }

        private func updateActiveTextEditorContent(from object: CanvasTextObject, on canvas: PKCanvasView) {
            guard let textView = activeTextEditor else { return }

            let selectedRange = textView.selectedRange
            let zoomScale = max(canvas.zoomScale, 0.001)
            let attributes = object.textAttributes(size: object.fontSize * zoomScale)
            let displayText = object.text.isEmpty ? "Text" : object.text
            isApplyingTextEditorUpdate = true
            textView.attributedText = NSAttributedString(string: displayText, attributes: attributes)
            textView.typingAttributes = attributes
            textView.font = attributes[.font] as? UIFont
            textView.textColor = attributes[.foregroundColor] as? UIColor
            let fullRange = NSRange(location: 0, length: (textView.text as NSString).length)
            if fullRange.length > 0 {
                textView.layoutManager.invalidateDisplay(forCharacterRange: fullRange)
                textView.layoutManager.ensureLayout(for: textView.textContainer)
            }
            textView.setNeedsDisplay()
            isApplyingTextEditorUpdate = false
            let textLength = (textView.text as NSString).length
            if selectedRange.location <= textLength {
                textView.selectedRange = NSRange(
                    location: selectedRange.location,
                    length: min(selectedRange.length, textLength - selectedRange.location)
                )
            }
        }

        func updateActiveTextEditorFrame(on canvas: PKCanvasView) {
            guard let activeTextObjectID,
                  let textView = activeTextEditor,
                  let object = parent.textObjects.first(where: { $0.id == activeTextObjectID }) else {
                return
            }

            textView.frame = viewportFrame(for: object, on: canvas).insetBy(dx: -4, dy: -4)
        }

        private func viewportFrame(for object: CanvasTextObject, on canvas: PKCanvasView) -> CGRect {
            let zoomScale = max(canvas.zoomScale, 0.001)
            return CGRect(
                x: (PencilKitCanvasGeometry.drawingOriginOffset.x + object.x) * zoomScale - canvas.contentOffset.x,
                y: (PencilKitCanvasGeometry.drawingOriginOffset.y + object.y) * zoomScale - canvas.contentOffset.y,
                width: object.width * zoomScale,
                height: object.height * zoomScale
            )
        }

        private func finishTextEditing() {
            activeTextEditor?.resignFirstResponder()
            activeTextEditor?.removeFromSuperview()
            activeTextEditor = nil
            activeTextObjectID = nil
            if let canvas {
                updateHostTextObjects(using: canvas)
            }
        }

        private func handleActiveTextEditorTap(atCanvasPoint canvasPoint: CGPoint, on canvas: PKCanvasView) {
            guard let hostView else {
                finishTextEditing()
                publishImageFromModel()
                return
            }

            handleActiveTextEditorTap(atHostPoint: hostView.convert(canvasPoint, from: canvas))
        }

        private func handleActiveTextEditorTap(atHostPoint hostPoint: CGPoint) {
            guard let textView = activeTextEditor else {
                finishTextEditing()
                publishImageFromModel()
                return
            }

            guard !textView.frame.insetBy(dx: -12, dy: -12).contains(hostPoint) else {
                return
            }

            finishTextEditing()
            publishImageFromModel()
            parent.onTextEditingEnded?()
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingTextEditorUpdate else { return }
            guard let activeTextObjectID,
                  let canvas,
                  let index = parent.textObjects.firstIndex(where: { $0.id == activeTextObjectID }) else {
                return
            }

            commitTextObjectUpdate(at: index, using: canvas) { object in
                object.text = textView.text
            }
            updateHostTextObjects(using: canvas)
            publishImageFromModel()
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            guard let activeTextObjectID,
                  let index = parent.textObjects.firstIndex(where: { $0.id == activeTextObjectID }),
                  parent.textObjects[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            if let canvas {
                commitTextObjectUpdate(at: index, using: canvas) { object in
                    object.text = "Text"
                }
                updateHostTextObjects(using: canvas)
                publishImageFromModel()
            }
        }

        @discardableResult
        private func commitTextObjectUpdate(
            at index: Int,
            using canvas: PKCanvasView,
            _ update: (inout CanvasTextObject) -> Void
        ) -> CanvasTextObject? {
            var textObjects = parent.textObjects
            guard textObjects.indices.contains(index) else { return nil }
            update(&textObjects[index])
            let updatedObject = textObjects[index]
            parent.textObjects = textObjects
            if selectedTextObjectID == updatedObject.id {
                updateSharedSelectionState()
            }
            return updatedObject
        }

        private func updateHostTextObjects(using canvas: PKCanvasView) {
            hostView?.updateTextObjects(
                parent.textObjects,
                using: canvas,
                hiddenTextObjectID: activeEditingTextObjectID,
                selectedTextObjectID: selectedTextObjectForDisplayID
            )
        }

        private func updateHostImageObjects(using canvas: PKCanvasView) {
            hostView?.updateImageObjects(
                parent.imageObjects,
                assetDirectoryURL: CanvasImageObject.assetDirectoryURL(forDrawingURL: parent.drawingURL),
                using: canvas,
                selectedImageObjectID: selectedImageObjectForDisplayID
            )
        }

        private func canvasSamples(
            from samples: [CanvasLiveStrokePoint],
            overlayView: UIView,
            canvas: PKCanvasView
        ) -> [CanvasLiveStrokePoint] {
            samples.map { sample in
                CanvasLiveStrokePoint(
                    location: overlayView.convert(sample.location, to: canvas),
                    pressure: sample.pressure,
                    timestamp: sample.timestamp
                )
            }
        }

        private func overlaySamples(
            from samples: [CanvasLiveStrokePoint],
            canvas: PKCanvasView
        ) -> [CanvasLiveStrokePoint] {
            guard let overlayView = hostView?.laserOverlayView else { return samples }
            return samples.map { sample in
                CanvasLiveStrokePoint(
                    location: canvas.convert(sample.location, to: overlayView),
                    pressure: sample.pressure,
                    timestamp: sample.timestamp
                )
            }
        }

        private func publishLiveStroke(
            samples: [CanvasLiveStrokePoint],
            phase: PencilLiveStrokeGestureRecognizer.Phase
        ) {
            guard let canvas, let onLiveStrokeUpdate = parent.onLiveStrokeUpdate else { return }

            let isLaser = activeLiveStrokeTool == .laser
            if phase == .ended || phase == .cancelled || samples.isEmpty {
                lastLiveStrokePublishTime = 0
                if isLaser, phase == .ended, !samples.isEmpty {
                    publishLaserStroke(samples: samples, on: canvas, onLiveStrokeUpdate: onLiveStrokeUpdate)
                    scheduleLaserClear(after: activeLaserDuration)
                } else {
                    clearLiveStroke()
                }
                return
            }

            guard isLaser || canvas.tool is PKInkingTool else {
                onLiveStrokeUpdate(nil)
                return
            }

            let viewportSize = canvas.bounds.size
            guard viewportSize.width > 0, viewportSize.height > 0 else { return }
            guard shouldPublishLiveStroke(for: phase) else { return }

            let zoomScale = max(canvas.zoomScale, 0.001)
            let outputRect = outputRect(in: viewportSize)
            let visibleContentRect = CGRect(
                x: canvas.contentOffset.x + outputRect.minX,
                y: canvas.contentOffset.y + outputRect.minY,
                width: outputRect.width,
                height: outputRect.height
            )
            let visibleSourceRect = sourceRect(for: outputRect, on: canvas)
            let mappedSamples = previewSamples(from: samples).compactMap { sample -> CanvasLiveStrokePoint? in
                guard visibleContentRect.contains(sample.location) else { return nil }
                return CanvasLiveStrokePoint(
                    location: CGPoint(
                        x: sample.location.x / zoomScale,
                        y: sample.location.y / zoomScale
                    ),
                    pressure: sample.pressure,
                    timestamp: sample.timestamp
                )
            }
            guard !mappedSamples.isEmpty else { return }

            if isLaser {
                let localStroke = CanvasLiveStroke(
                    samples: laserSamples(from: overlaySamples(from: previewSamples(from: samples), canvas: canvas)),
                    lineWidth: liveLineWidth(on: canvas),
                    color: currentStrokeColor(on: canvas),
                    kind: laserStrokeKind,
                    displayDuration: activeLaserDuration
                )
                laserClearTask?.cancel()
                hostView?.laserOverlayView.update(stroke: localStroke)
            }

            parent.onViewportSourceRectChange?(visibleSourceRect)
            onLiveStrokeUpdate(
                CanvasLiveStroke(
                    samples: isLaser ? laserSamples(from: mappedSamples) : mappedSamples,
                    lineWidth: liveLineWidth(on: canvas),
                    color: currentStrokeColor(on: canvas),
                    kind: isLaser ? laserStrokeKind : .ink,
                    displayDuration: isLaser ? activeLaserDuration : 0
                )
            )
        }

        private func publishLaserStroke(
            samples: [CanvasLiveStrokePoint],
            on canvas: PKCanvasView,
            onLiveStrokeUpdate: @MainActor (CanvasLiveStroke?) -> Void
        ) {
            let viewportSize = canvas.bounds.size
            guard viewportSize.width > 0, viewportSize.height > 0 else { return }

            let zoomScale = max(canvas.zoomScale, 0.001)
            let outputRect = outputRect(in: viewportSize)
            let visibleContentRect = CGRect(
                x: canvas.contentOffset.x + outputRect.minX,
                y: canvas.contentOffset.y + outputRect.minY,
                width: outputRect.width,
                height: outputRect.height
            )
            let visibleSourceRect = sourceRect(for: outputRect, on: canvas)
            let preview = previewSamples(from: samples)
            let mappedSamples = preview.compactMap { sample -> CanvasLiveStrokePoint? in
                guard visibleContentRect.contains(sample.location) else { return nil }
                return CanvasLiveStrokePoint(
                    location: CGPoint(
                        x: sample.location.x / zoomScale,
                        y: sample.location.y / zoomScale
                    ),
                    pressure: sample.pressure,
                    timestamp: sample.timestamp
                )
            }
            guard !mappedSamples.isEmpty else { return }

            let lineWidth = liveLineWidth(on: canvas)
            let color = currentStrokeColor(on: canvas)
            let kind = laserStrokeKind
            let duration = activeLaserDuration
            let localStroke = CanvasLiveStroke(
                samples: laserSamples(from: overlaySamples(from: preview, canvas: canvas)),
                lineWidth: lineWidth,
                color: color,
                kind: kind,
                displayDuration: duration
            )
            let displayStroke = CanvasLiveStroke(
                samples: laserSamples(from: mappedSamples),
                lineWidth: lineWidth,
                color: color,
                kind: kind,
                displayDuration: duration
            )

            parent.onViewportSourceRectChange?(visibleSourceRect)
            hostView?.laserOverlayView.update(stroke: localStroke)
            onLiveStrokeUpdate(displayStroke)
        }

        private var laserStrokeKind: CanvasLiveStroke.Kind {
            guard activeLaserDuration > 0 else { return .laserDot }
            switch activeLaserMode {
            case .dot:
                return .laserDot
            case .trail:
                return .laserTrail
            }
        }

        private func laserSamples(from samples: [CanvasLiveStrokePoint]) -> [CanvasLiveStrokePoint] {
            guard activeLaserDuration > 0 else {
                return samples.last.map { [$0] } ?? []
            }

            switch activeLaserMode {
            case .dot:
                return samples.last.map { [$0] } ?? []
            case .trail:
                return samples
            }
        }

        private func scheduleLaserClear(after duration: TimeInterval) {
            laserClearTask?.cancel()
            let lifetime = duration <= 0 ? Self.laserPointerLifetime : duration

            laserClearTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(Int(lifetime * 1000)))
                guard !Task.isCancelled else { return }
                self?.clearLiveStroke()
            }
        }

        private func shouldPublishLiveStroke(for phase: PencilLiveStrokeGestureRecognizer.Phase) -> Bool {
            let now = CACurrentMediaTime()
            guard phase != .began else {
                lastLiveStrokePublishTime = now
                return true
            }
            guard now - lastLiveStrokePublishTime >= Self.minimumLiveStrokePublishInterval else {
                return false
            }
            lastLiveStrokePublishTime = now
            return true
        }

        private func previewSamples(from samples: [CanvasLiveStrokePoint]) -> [CanvasLiveStrokePoint] {
            guard samples.count > Self.maximumLiveStrokePreviewPoints else { return samples }
            let pointStride = max(samples.count / Self.maximumLiveStrokePreviewPoints, 1)
            var preview = stride(from: 0, to: samples.count, by: pointStride).map { samples[$0] }
            if preview.last != samples.last, let lastSample = samples.last {
                preview.append(lastSample)
            }
            return preview
        }

        private func liveLineWidth(on canvas: PKCanvasView) -> CGFloat {
            if let activeLiveStrokeWidth {
                switch activeLiveStrokeTool {
                case .pen:
                    return activeLiveStrokeWidth * liveStrokeWidthPreviewScale(forWidth: activeLiveStrokeWidth, inkType: .pen)
                case .marker:
                    return activeLiveStrokeWidth
                case .laser:
                    return activeLiveStrokeWidth
                case nil:
                    break
                }
            }

            if let inkingTool = canvas.tool as? PKInkingTool {
                // PencilKit's committed Apple Pencil strokes render narrower
                // than the raw PKInkingTool width, but the mismatch is not
                // linear: thin strokes need more live width, thick strokes need
                // less. This only calibrates the temporary TV overlay.
                return inkingTool.width * liveStrokeWidthPreviewScale(for: inkingTool)
            }
            return 4
        }

        private func liveStrokeWidthPreviewScale(for tool: PKInkingTool) -> CGFloat {
            liveStrokeWidthPreviewScale(forWidth: tool.width, inkType: tool.ink.inkType)
        }

        private func liveStrokeWidthPreviewScale(forWidth width: CGFloat, inkType: PKInkingTool.InkType) -> CGFloat {
            let range = inkType.validWidthRange
            let span = max(range.upperBound - range.lowerBound, 0.001)
            let normalizedWidth = min(max((width - range.lowerBound) / span, 0), 1)
            let curvedProgress = sqrt(normalizedWidth)
            return Self.maximumLiveStrokeWidthPreviewScale
                - ((Self.maximumLiveStrokeWidthPreviewScale - Self.minimumLiveStrokeWidthPreviewScale) * curvedProgress)
        }

        private func currentStrokeColor(on canvas: PKCanvasView) -> CanvasStrokeColor {
            if let activeLiveStrokeColor {
                return activeLiveStrokeColor
            }

            let uiColor: UIColor
            if let inkingTool = canvas.tool as? PKInkingTool {
                uiColor = inkingTool.color
            } else {
                uiColor = .black
            }

            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 1
            uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            return CanvasStrokeColor(red: red, green: green, blue: blue, alpha: alpha)
        }

        fileprivate func clearLiveStroke() {
            laserClearTask?.cancel()
            laserClearTask = nil
            clearLaserOverlay()
            parent.onLiveStrokeUpdate?(nil)
        }

        private func clearLaserOverlay() {
            hostView?.laserOverlayView.update(stroke: nil)
        }

        fileprivate func clearLiveStrokeAfterViewUpdate() {
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.clearLiveStroke()
            }
        }

        fileprivate func presentationModeDidChange(to mode: CanvasPresentationMode) -> Bool {
            guard publishedPresentationMode != mode else { return false }
            publishedPresentationMode = mode
            return true
        }

        fileprivate func textObjectsDidChange(to textObjects: [CanvasTextObject]) -> Bool {
            guard publishedTextObjects != textObjects else { return false }
            publishedTextObjects = textObjects
            return true
        }

        // MARK: - UIGestureRecognizerDelegate

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer === textEditorDismissRecognizer {
                return activeTextEditor != nil
            }
            if gestureRecognizer === textPlacementRecognizer {
                return hostView?.textPlacementOverlayView.acceptsTextPlacement == true
                    && activeTextEditor == nil
            }
            if gestureRecognizer === regionSelectionRecognizer {
                if activeSelectionTarget == .object,
                   let canvas,
                   let hostView {
                    let location = hostView.convert(gestureRecognizer.location(in: hostView), to: canvas)
                    if hitTextResizeHandleID(at: location, on: canvas) != nil
                        || hitTextObjectID(at: location, on: canvas) != nil
                        || hitImageObjectID(at: location, on: canvas) != nil {
                        return false
                    }
                }
                return isRegionSelectionEnabled
            }
            if gestureRecognizer === textSelectionTapRecognizer
                || gestureRecognizer === textSelectionDoubleTapRecognizer {
                return isTextSelectionEnabled
            }
            if gestureRecognizer === textSelectionPanRecognizer {
                guard isTextSelectionEnabled,
                      let canvas else {
                    return false
                }
                let startLocation = gestureRecognizer.location(in: canvas)
                return hitTextResizeHandleID(at: startLocation, on: canvas) != nil
                    || hitSelectedTextObjectID(at: startLocation, on: canvas) != nil
                    || hitTextObjectID(at: startLocation, on: canvas) != nil
                    || hitSelectedImageObjectID(at: startLocation, on: canvas) != nil
                    || hitImageObjectID(at: startLocation, on: canvas) != nil
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            if gestureRecognizer === textSelectionPanRecognizer || otherGestureRecognizer === textSelectionPanRecognizer {
                return !isCanvasViewportGesture(gestureRecognizer) && !isCanvasViewportGesture(otherGestureRecognizer)
            }
            if isCanvasViewportGesture(gestureRecognizer) || isCanvasViewportGesture(otherGestureRecognizer) {
                return true
            }
            if gestureRecognizer === textEditorDismissRecognizer
                || otherGestureRecognizer === textEditorDismissRecognizer {
                return true
            }
            if gestureRecognizer === regionSelectionRecognizer
                || otherGestureRecognizer === regionSelectionRecognizer {
                return false
            }
            return true
        }

        private func isCanvasViewportGesture(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let canvas else { return false }
            return gestureRecognizer === canvas.panGestureRecognizer
                || gestureRecognizer === canvas.pinchGestureRecognizer
        }

        // MARK: - UIScrollViewDelegate

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let canvas = scrollView as? PKCanvasView else { return }
            stabilizeBackgroundViewportIfNeeded(on: canvas)
            hostView?.updateBackgroundFrame(using: canvas)
            hostView?.updateImageObjectFrame(using: canvas)
            hostView?.updateTextObjectFrame(using: canvas)
            updateActiveTextEditorFrame(on: canvas)
            updateRegionSelectionHighlight(on: canvas)
            updateSharedSelectionState()
            publishViewportState(from: canvas)
            publishViewportSourceRect(from: canvas)
            scheduleViewportFramePublish()
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            parent.onInteractionBegan?()
        }

        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            parent.onInteractionBegan?()
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let canvas = scrollView as? PKCanvasView else { return }
            hostView?.updateBackgroundFrame(using: canvas)
            hostView?.updateImageObjectFrame(using: canvas)
            hostView?.updateTextObjectFrame(using: canvas)
            updateActiveTextEditorFrame(on: canvas)
            updateRegionSelectionHighlight(on: canvas)
            updateSharedSelectionState()
            publishViewportState(from: canvas)
            publishViewportSourceRect(from: canvas)
            scheduleViewportFramePublish()
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            guard let canvas = scrollView as? PKCanvasView else { return }
            hostView?.updateBackgroundFrame(using: canvas)
            hostView?.updateImageObjectFrame(using: canvas)
            hostView?.updateTextObjectFrame(using: canvas)
            updateActiveTextEditorFrame(on: canvas)
            updateSharedSelectionState()
            publishViewportState(from: canvas)
            publishViewportSourceRect(from: canvas)
            publishViewportFrameNow()
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            guard !decelerate, let canvas = scrollView as? PKCanvasView else { return }
            publishViewportState(from: canvas)
            publishViewportSourceRect(from: canvas)
            publishViewportFrameNow()
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            guard let canvas = scrollView as? PKCanvasView else { return }
            publishViewportState(from: canvas)
            publishViewportSourceRect(from: canvas)
            publishViewportFrameNow()
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            guard let canvas = scrollView as? PKCanvasView else { return }
            publishViewportState(from: canvas)
            publishViewportSourceRect(from: canvas)
            publishViewportFrameNow()
        }

        // MARK: - PKCanvasViewDelegate

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
            if !(canvasView.tool is PKInkingTool) {
                publishImageFromModel()
            }
        }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            canvas = canvasView
            parent.onInteractionBegan?()
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            // The final committed-state publish comes from
            // canvasViewDrawingDidChange firing next.
        }

        // MARK: - Publish from model (non-stroke renders)

        private func publishViewportSourceRect(from canvas: PKCanvasView) {
            guard let onViewportSourceRectChange = parent.onViewportSourceRectChange else { return }
            let viewportSize = canvas.bounds.size
            guard viewportSize.width > 0, viewportSize.height > 0 else { return }
            let outputRect = outputRect(in: viewportSize)
            onViewportSourceRectChange(sourceRect(for: outputRect, on: canvas))
        }

        func cancelPendingViewportFramePublish() {
            viewportFramePublishTask?.cancel()
            viewportFramePublishTask = nil
        }

        private func scheduleViewportFramePublish() {
            guard parent.onFrameUpdate != nil else { return }
            viewportFramePublishTask?.cancel()
            viewportFramePublishTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.viewportFramePublishDebounce)
                guard !Task.isCancelled else { return }
                self?.publishImageFromModel()
            }
        }

        private func publishViewportFrameNow() {
            cancelPendingViewportFramePublish()
            publishImageFromModel()
        }

        func publishImageFromModel() {
            guard let canvas, let onFrameUpdate = parent.onFrameUpdate else { return }
            // PKCanvasView is a UIScrollView. `bounds.origin` may be
            // non-zero if the canvas has been scrolled. We need to keep
            // source and destination rects separate — sourcing from the
            // centered 16:9 viewfinder inside the visible region but rendering
            // into a zero-origin destination — so the captured image is never
            // shifted or clipped inside the renderer.
            let viewportSize = canvas.bounds.size
            guard viewportSize.width > 0, viewportSize.height > 0 else { return }

            let outputRect = outputRect(in: viewportSize)
            let visibleSourceRect = sourceRect(for: outputRect, on: canvas)
            let sourceRect = overscannedSourceRect(around: visibleSourceRect)
            let destinationSize = CGSize(
                width: outputRect.width * Self.committedFrameOverscan,
                height: outputRect.height * Self.committedFrameOverscan
            )
            let destinationRect = CGRect(origin: .zero, size: destinationSize)

            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            format.opaque = true

            // Composite an overscanned committed frame. The external display
            // crops/transforms inside this larger cached image during live
            // pan/zoom, which avoids black edges without rasterizing every
            // scroll event.
            let drawingImageScale = committedDrawingImageScale(
                sourceRect: sourceRect,
                destinationRect: destinationRect,
                rendererScale: format.scale
            )
            let renderer = UIGraphicsImageRenderer(size: destinationSize, format: format)
            let image = renderer.image { context in
                UIColor.white.setFill()
                UIRectFill(destinationRect)
                drawBackground(
                    in: context.cgContext,
                    sourceRect: sourceRect,
                    destinationRect: destinationRect
                )
                parent.drawing.image(from: sourceRect, scale: drawingImageScale).draw(in: destinationRect)
                drawImageObjects(
                    in: context.cgContext,
                    sourceRect: sourceRect,
                    destinationRect: destinationRect
                )
                drawTextObjects(
                    in: context.cgContext,
                    sourceRect: sourceRect,
                    destinationRect: destinationRect
                )
            }
            if let cg = image.cgImage {
                onFrameUpdate(cg, sourceRect, visibleSourceRect)
            }
        }

        private func committedDrawingImageScale(
            sourceRect: CGRect,
            destinationRect: CGRect,
            rendererScale: CGFloat
        ) -> CGFloat {
            let scaleX = destinationRect.width / max(sourceRect.width, 0.001)
            let scaleY = destinationRect.height / max(sourceRect.height, 0.001)
            let zoomedScale = rendererScale * max(scaleX, scaleY)
            return min(max(rendererScale, zoomedScale), 8)
        }

        private func drawBackground(
            in context: CGContext,
            sourceRect: CGRect,
            destinationRect: CGRect
        ) {
            guard let background = parent.background,
                  let document = PDFDocument(url: background.pdfURL),
                  let page = document.page(at: background.pageIndex) else { return }

            let pageBounds = page.bounds(for: .mediaBox)
            let backgroundRect = CGRect(
                origin: PencilKitCanvasGeometry.drawingOriginOffset,
                size: pageBounds.size
            )
            let scaleX = destinationRect.width / max(sourceRect.width, 0.001)
            let scaleY = destinationRect.height / max(sourceRect.height, 0.001)

            context.saveGState()
            context.clip(to: destinationRect)
            context.translateBy(x: destinationRect.minX, y: destinationRect.minY)
            context.scaleBy(x: scaleX, y: scaleY)
            context.translateBy(x: -sourceRect.minX, y: -sourceRect.minY)
            drawPaperSurface(in: context, rect: backgroundRect)
            PDFCanvasBackgroundRenderer.draw(
                page: page,
                pageBounds: pageBounds,
                in: backgroundRect,
                context: context
            )
            drawPaperBorder(in: context, rect: backgroundRect)
            context.restoreGState()
        }

        private func drawPaperSurface(in context: CGContext, rect: CGRect) {
            context.saveGState()
            context.setShadow(
                offset: CGSize(width: 0, height: 7),
                blur: 14,
                color: PencilKitCanvasGeometry.paperShadowColor.cgColor
            )
            UIColor.white.setFill()
            context.fill(rect)
            context.restoreGState()
        }

        private func drawPaperBorder(in context: CGContext, rect: CGRect) {
            context.saveGState()
            context.setStrokeColor(PencilKitCanvasGeometry.paperBorderColor.cgColor)
            context.setLineWidth(1)
            context.stroke(rect)
            context.restoreGState()
        }

        private func drawTextObjects(
            in context: CGContext,
            sourceRect: CGRect,
            destinationRect: CGRect
        ) {
            guard !parent.textObjects.isEmpty else { return }

            let scaleX = destinationRect.width / max(sourceRect.width, 0.001)
            let scaleY = destinationRect.height / max(sourceRect.height, 0.001)
            context.saveGState()
            context.clip(to: destinationRect)

            for object in parent.textObjects where !object.text.isEmpty {
                let textFrame = CGRect(
                    x: destinationRect.minX + (PencilKitCanvasGeometry.drawingOriginOffset.x + object.x - sourceRect.minX) * scaleX,
                    y: destinationRect.minY + (PencilKitCanvasGeometry.drawingOriginOffset.y + object.y - sourceRect.minY) * scaleY,
                    width: object.width * scaleX,
                    height: object.height * scaleY
                )
                CanvasMathTextRenderer.draw(object, in: textFrame, scale: scaleY)
            }

            context.restoreGState()
        }

        private func drawImageObjects(
            in context: CGContext,
            sourceRect: CGRect,
            destinationRect: CGRect
        ) {
            guard !parent.imageObjects.isEmpty else { return }

            let scaleX = destinationRect.width / max(sourceRect.width, 0.001)
            let scaleY = destinationRect.height / max(sourceRect.height, 0.001)
            let assetDirectoryURL = CanvasImageObject.assetDirectoryURL(forDrawingURL: parent.drawingURL)
            context.saveGState()
            context.clip(to: destinationRect)

            for object in parent.imageObjects {
                let imageURL = assetDirectoryURL.appendingPathComponent(object.imageFileName)
                guard let image = UIImage(contentsOfFile: imageURL.path) else { continue }
                let imageFrame = CGRect(
                    x: destinationRect.minX + (PencilKitCanvasGeometry.drawingOriginOffset.x + object.x - sourceRect.minX) * scaleX,
                    y: destinationRect.minY + (PencilKitCanvasGeometry.drawingOriginOffset.y + object.y - sourceRect.minY) * scaleY,
                    width: object.width * scaleX,
                    height: object.height * scaleY
                )
                image.draw(in: imageFrame)
            }

            context.restoreGState()
        }

        private func pdfPageBounds(for background: CanvasBackground) -> CGRect? {
            guard let document = PDFDocument(url: background.pdfURL),
                  let page = document.page(at: background.pageIndex) else { return nil }
            return page.bounds(for: .mediaBox)
        }

        // MARK: - Output Geometry

        private func outputRect(in size: CGSize) -> CGRect {
            switch parent.presentationMode {
            case .mirror:
                return CGRect(origin: .zero, size: size)
            case .present:
                return viewfinderRect(in: size)
            }
        }

        private func sourceRect(for outputRect: CGRect, on canvas: PKCanvasView) -> CGRect {
            let zoomScale = max(canvas.zoomScale, 0.001)
            return CGRect(
                x: (canvas.contentOffset.x + outputRect.origin.x) / zoomScale,
                y: (canvas.contentOffset.y + outputRect.origin.y) / zoomScale,
                width: outputRect.width / zoomScale,
                height: outputRect.height / zoomScale
            )
        }

        private func overscannedSourceRect(around sourceRect: CGRect) -> CGRect {
            guard sourceRect.width > 0, sourceRect.height > 0 else { return sourceRect }
            let width = sourceRect.width * Self.committedFrameOverscan
            let height = sourceRect.height * Self.committedFrameOverscan
            return CGRect(
                x: sourceRect.midX - width / 2,
                y: sourceRect.midY - height / 2,
                width: width,
                height: height
            )
        }

        private func viewfinderRect(in size: CGSize) -> CGRect {
            guard size.width > 0, size.height > 0 else { return .zero }

            let containerAspect = size.width / size.height
            let rectSize: CGSize
            if containerAspect > Self.targetAspect {
                rectSize = CGSize(width: size.height * Self.targetAspect, height: size.height)
            } else {
                rectSize = CGSize(width: size.width, height: size.width / Self.targetAspect)
            }

            return CGRect(
                x: (size.width - rectSize.width) / 2,
                y: (size.height - rectSize.height) / 2,
                width: rectSize.width,
                height: rectSize.height
            )
        }
    }
}

private final class PencilLiveStrokeGestureRecognizer: UIGestureRecognizer {
    enum Phase {
        case began
        case moved
        case ended
        case cancelled
    }

    private let permittedTouchTypes: Set<UITouch.TouchType>
    private let onUpdate: ([CanvasLiveStrokePoint], Phase) -> Void
    private var activeTouch: UITouch?
    private var samples: [CanvasLiveStrokePoint] = []

    init(
        allowedTouchTypes: Set<UITouch.TouchType> = [.pencil],
        onUpdate: @escaping ([CanvasLiveStrokePoint], Phase) -> Void
    ) {
        self.permittedTouchTypes = allowedTouchTypes
        self.onUpdate = onUpdate
        super.init(target: nil, action: nil)
        self.allowedTouchTypes = allowedTouchTypes.map { NSNumber(value: $0.rawValue) }
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if activeTouch != nil {
            cancelActiveStroke()
            return
        }

        guard touches.count == 1,
              let touch = touches.first(where: { permittedTouchTypes.contains($0.type) }),
              let view else {
            state = .failed
            return
        }

        activeTouch = touch
        samples = [sample(for: touch, in: view)]
        state = .began
        onUpdate(samples, .began)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let activeTouch, touches.contains(activeTouch), let view else { return }

        if let allTouches = event.allTouches, allTouches.count > 1 {
            cancelActiveStroke()
            return
        }

        let coalescedTouches = event.coalescedTouches(for: activeTouch) ?? [activeTouch]
        samples.append(contentsOf: coalescedTouches.map { sample(for: $0, in: view) })
        state = .changed
        onUpdate(samples, .moved)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let activeTouch, touches.contains(activeTouch) else { return }
        onUpdate(samples, .ended)
        resetStroke()
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let activeTouch, touches.contains(activeTouch) else { return }
        onUpdate(samples, .cancelled)
        resetStroke()
        state = .cancelled
    }

    override func reset() {
        resetStroke()
    }

    private func sample(for touch: UITouch, in view: UIView) -> CanvasLiveStrokePoint {
        CanvasLiveStrokePoint(
            location: touch.location(in: view),
            pressure: normalizedPressure(for: touch),
            timestamp: touch.timestamp
        )
    }

    private func normalizedPressure(for touch: UITouch) -> CGFloat {
        guard touch.maximumPossibleForce > 0 else { return 0.5 }
        return touch.force / touch.maximumPossibleForce
    }

    private func resetStroke() {
        activeTouch = nil
        samples.removeAll(keepingCapacity: true)
    }

    private func cancelActiveStroke() {
        if activeTouch != nil {
            onUpdate(samples, .cancelled)
        }
        resetStroke()
        state = .cancelled
    }
}

private final class CanvasObjectDragGestureRecognizer: UIGestureRecognizer {
    private let permittedTouchTypes: Set<UITouch.TouchType>
    private var activeTouch: UITouch?

    init(
        allowedTouchTypes: Set<UITouch.TouchType>,
        target: Any?,
        action: Selector?
    ) {
        self.permittedTouchTypes = allowedTouchTypes
        super.init(target: target, action: action)
        self.allowedTouchTypes = allowedTouchTypes.map { NSNumber(value: $0.rawValue) }
        cancelsTouchesInView = true
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard activeTouch == nil,
              touches.count == 1,
              let touch = touches.first(where: { permittedTouchTypes.contains($0.type) }) else {
            state = .failed
            return
        }

        activeTouch = touch
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let activeTouch, touches.contains(activeTouch) else { return }
        if let allTouches = event.allTouches, allTouches.count > 1 {
            state = .cancelled
            return
        }
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let activeTouch, touches.contains(activeTouch) else { return }
        resetDrag()
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let activeTouch, touches.contains(activeTouch) else { return }
        resetDrag()
        state = .cancelled
    }

    override func reset() {
        resetDrag()
    }

    private func resetDrag() {
        activeTouch = nil
    }
}

#endif
