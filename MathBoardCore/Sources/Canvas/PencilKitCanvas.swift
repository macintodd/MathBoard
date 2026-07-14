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
    let onExtractActionCompleted: (@MainActor () -> Void)?

    @State private var drawing: PKDrawing = PKDrawing()
    @State private var textObjects: [CanvasTextObject] = []
    @State private var imageObjects: [CanvasImageObject] = []
    @State private var geometryObjects: [CanvasGeometryObject] = []
    @State private var coverObjects: [CanvasCoverObject] = []
    @State private var objectLayerState = CanvasObjectLayerState()
    @State private var didLoad = false
    @State private var saveTask: Task<Void, Never>?
    @State private var textSaveTask: Task<Void, Never>?
    @State private var imageObjectSaveTask: Task<Void, Never>?
    @State private var geometryObjectSaveTask: Task<Void, Never>?
    @State private var coverObjectSaveTask: Task<Void, Never>?
    @State private var objectLayerSaveTask: Task<Void, Never>?
    @State private var hasPendingSave = false
    @State private var hasPendingTextSave = false
    @State private var hasPendingImageObjectSave = false
    @State private var hasPendingGeometryObjectSave = false
    @State private var hasPendingCoverObjectSave = false
    @State private var hasPendingObjectLayerSave = false
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
            geometryObjects: $geometryObjects,
            coverObjects: $coverObjects,
            objectLayerState: $objectLayerState,
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
            onExtractedRegionSend: onExtractedRegionSend,
            onExtractActionCompleted: onExtractActionCompleted
        )
            .background(Color.white)
            .task(id: drawingURL) {
                didLoad = false
                textSaveTask?.cancel()
                textSaveTask = nil
                imageObjectSaveTask?.cancel()
                imageObjectSaveTask = nil
                geometryObjectSaveTask?.cancel()
                geometryObjectSaveTask = nil
                coverObjectSaveTask?.cancel()
                coverObjectSaveTask = nil
                objectLayerSaveTask?.cancel()
                objectLayerSaveTask = nil
                hasPendingTextSave = false
                hasPendingImageObjectSave = false
                hasPendingGeometryObjectSave = false
                hasPendingCoverObjectSave = false
                hasPendingObjectLayerSave = false
                drawing = (try? Self.loadDrawing(at: drawingURL)) ?? PKDrawing()
                textObjects = CanvasTextObject.load(from: CanvasTextObject.sidecarURL(forDrawingURL: drawingURL))
                imageObjects = CanvasImageObject.load(from: CanvasImageObject.sidecarURL(forDrawingURL: drawingURL))
                geometryObjects = CanvasGeometryObject.load(from: CanvasGeometryObject.sidecarURL(forDrawingURL: drawingURL))
                coverObjects = CanvasCoverObject.load(from: CanvasCoverObject.sidecarURL(forDrawingURL: drawingURL))
                objectLayerState = CanvasObjectLayerState.load(from: CanvasObjectLayerState.sidecarURL(forDrawingURL: drawingURL))
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
            .onChange(of: geometryObjects) { _, newGeometryObjects in
                handleGeometryObjectsChange(newGeometryObjects)
            }
            .onChange(of: coverObjects) { _, newCoverObjects in
                handleCoverObjectsChange(newCoverObjects)
            }
            .onChange(of: objectLayerState) { _, newObjectLayerState in
                handleObjectLayerStateChange(newObjectLayerState)
            }
            .onChange(of: editCommand) { _, command in
                applyEditCommandIfNeeded(command)
            }
            .onDisappear {
                flushPendingSave()
                flushPendingTextSave()
                flushPendingImageObjectSave()
                flushPendingGeometryObjectSave()
                flushPendingCoverObjectSave()
                flushPendingObjectLayerSave()
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

    private func handleGeometryObjectsChange(_ newGeometryObjects: [CanvasGeometryObject]) {
        guard didLoad else { return }
        scheduleGeometryObjectSave(of: newGeometryObjects)
    }

    private func handleCoverObjectsChange(_ newCoverObjects: [CanvasCoverObject]) {
        guard didLoad else { return }
        scheduleCoverObjectSave(of: newCoverObjects)
    }

    private func handleObjectLayerStateChange(_ newObjectLayerState: CanvasObjectLayerState) {
        guard didLoad else { return }
        scheduleObjectLayerSave(of: newObjectLayerState)
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

    private func scheduleGeometryObjectSave(of newGeometryObjects: [CanvasGeometryObject]) {
        hasPendingGeometryObjectSave = true
        geometryObjectSaveTask?.cancel()
        geometryObjectSaveTask = Task { @MainActor in
            try? await Task.sleep(for: Self.saveDebounce)
            guard !Task.isCancelled else { return }
            saveGeometryObjects(newGeometryObjects, to: CanvasGeometryObject.sidecarURL(forDrawingURL: drawingURL))
            hasPendingGeometryObjectSave = false
        }
    }

    private func flushPendingGeometryObjectSave() {
        geometryObjectSaveTask?.cancel()
        geometryObjectSaveTask = nil
        guard hasPendingGeometryObjectSave else { return }
        saveGeometryObjects(geometryObjects, to: CanvasGeometryObject.sidecarURL(forDrawingURL: drawingURL))
        hasPendingGeometryObjectSave = false
    }

    private func scheduleCoverObjectSave(of newCoverObjects: [CanvasCoverObject]) {
        hasPendingCoverObjectSave = true
        coverObjectSaveTask?.cancel()
        coverObjectSaveTask = Task { @MainActor in
            try? await Task.sleep(for: Self.saveDebounce)
            guard !Task.isCancelled else { return }
            saveCoverObjects(newCoverObjects, to: CanvasCoverObject.sidecarURL(forDrawingURL: drawingURL))
            hasPendingCoverObjectSave = false
        }
    }

    private func flushPendingCoverObjectSave() {
        coverObjectSaveTask?.cancel()
        coverObjectSaveTask = nil
        guard hasPendingCoverObjectSave else { return }
        saveCoverObjects(coverObjects, to: CanvasCoverObject.sidecarURL(forDrawingURL: drawingURL))
        hasPendingCoverObjectSave = false
    }

    private func scheduleObjectLayerSave(of newObjectLayerState: CanvasObjectLayerState) {
        hasPendingObjectLayerSave = true
        objectLayerSaveTask?.cancel()
        objectLayerSaveTask = Task { @MainActor in
            try? await Task.sleep(for: Self.saveDebounce)
            guard !Task.isCancelled else { return }
            saveObjectLayerState(newObjectLayerState, to: CanvasObjectLayerState.sidecarURL(forDrawingURL: drawingURL))
            hasPendingObjectLayerSave = false
        }
    }

    private func flushPendingObjectLayerSave() {
        objectLayerSaveTask?.cancel()
        objectLayerSaveTask = nil
        guard hasPendingObjectLayerSave else { return }
        saveObjectLayerState(objectLayerState, to: CanvasObjectLayerState.sidecarURL(forDrawingURL: drawingURL))
        hasPendingObjectLayerSave = false
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

    private func saveGeometryObjects(_ geometryObjects: [CanvasGeometryObject], to url: URL) {
        do {
            try CanvasGeometryObject.save(geometryObjects, to: url)
        } catch {
            print("[Canvas] geometry object save error: \(error)")
        }
    }

    private func saveCoverObjects(_ coverObjects: [CanvasCoverObject], to url: URL) {
        do {
            try CanvasCoverObject.save(coverObjects, to: url)
        } catch {
            print("[Canvas] cover object save error: \(error)")
        }
    }

    private func saveObjectLayerState(_ state: CanvasObjectLayerState, to url: URL) {
        do {
            try CanvasObjectLayerState.save(state, to: url)
        } catch {
            print("[Canvas] object layer save error: \(error)")
        }
    }
}

private final class PencilKitCanvasHostView: UIView {
    let backgroundView = PDFCanvasBackgroundView()
    let canvas = PKCanvasView()
    let imageObjectsView = CanvasImageObjectsView()
    let geometryObjectsView = CanvasGeometryObjectsView()
    let textObjectsView = CanvasTextObjectsView()
    let coverObjectsView = CanvasCoverObjectsView()
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
        geometryObjectsView.isUserInteractionEnabled = false
        textObjectsView.isUserInteractionEnabled = false
        coverObjectsView.isUserInteractionEnabled = false
        regionSelectionOverlayView.acceptsRegionSelectionInput = false
        laserOverlayView.acceptsLaserInput = false
        textPlacementOverlayView.acceptsTextPlacement = false
        // Paint order (bottom → top): PDF paper, then the content object layers
        // (images, geometry, text), then handwriting ink on top of the content,
        // then the transient interaction overlays with the laser pointer topmost.
        addSubview(backgroundView)
        addSubview(imageObjectsView)
        addSubview(geometryObjectsView)
        addSubview(textObjectsView)
        addSubview(canvas)
        // Tape covers paint above the ink/content so they can hide anything,
        // but below the transient overlays so the laser stays topmost.
        addSubview(coverObjectsView)
        addSubview(regionSelectionOverlayView)
        addSubview(textPlacementOverlayView)
        addSubview(laserOverlayView)
        updateObjectLayerState(CanvasObjectLayerState())
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        canvas.frame = bounds
        imageObjectsView.frame = bounds
        geometryObjectsView.frame = bounds
        textObjectsView.frame = bounds
        coverObjectsView.frame = bounds
        regionSelectionOverlayView.frame = bounds
        laserOverlayView.frame = bounds
        textPlacementOverlayView.frame = bounds
        updateBackgroundFrame(using: canvas)
        updateImageObjectFrame(using: canvas)
        updateGeometryObjectFrame(using: canvas)
        updateTextObjectFrame(using: canvas)
        updateCoverObjectFrame(using: canvas)
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

    func updateGeometryObjects(
        _ geometryObjects: [CanvasGeometryObject],
        using canvas: PKCanvasView,
        selectedGeometryObjectID: UUID? = nil,
        resizingGeometryObjectID: UUID? = nil
    ) {
        geometryObjectsView.configure(
            geometryObjects,
            selectedGeometryObjectID: selectedGeometryObjectID,
            resizingGeometryObjectID: resizingGeometryObjectID
        )
        updateGeometryObjectFrame(using: canvas)
    }

    func updateObjectLayerState(_ state: CanvasObjectLayerState) {
        backgroundView.layer.zPosition = 0
        geometryObjectsView.layer.zPosition = 20
        textObjectsView.layer.zPosition = 40
        canvas.layer.zPosition = 60
        coverObjectsView.layer.zPosition = 70
        regionSelectionOverlayView.layer.zPosition = 80
        textPlacementOverlayView.layer.zPosition = 90
        laserOverlayView.layer.zPosition = 100

        switch state.imageLayerPosition {
        case .belowGeometry:
            imageObjectsView.layer.zPosition = 10
        case .betweenGeometryAndText:
            imageObjectsView.layer.zPosition = 30
        case .aboveText:
            imageObjectsView.layer.zPosition = 50
        }
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

    func updateGeometryObjectFrame(using canvas: PKCanvasView) {
        geometryObjectsView.updateViewport(
            zoomScale: canvas.zoomScale,
            contentOffset: canvas.contentOffset,
            canvasOrigin: PencilKitCanvasGeometry.drawingOriginOffset
        )
    }

    func updateCoverObjects(_ coverObjects: [CanvasCoverObject], using canvas: PKCanvasView) {
        coverObjectsView.configure(coverObjects)
        updateCoverObjectFrame(using: canvas)
    }

    func updateCoverObjectFrame(using canvas: PKCanvasView) {
        coverObjectsView.updateViewport(
            zoomScale: canvas.zoomScale,
            contentOffset: canvas.contentOffset,
            canvasOrigin: PencilKitCanvasGeometry.drawingOriginOffset
        )
    }
}

private final class CanvasCoverObjectsView: UIView {
    private var coverObjects: [CanvasCoverObject] = []
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

    func configure(_ coverObjects: [CanvasCoverObject]) {
        guard self.coverObjects != coverObjects else { return }
        self.coverObjects = coverObjects
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

        for object in coverObjects where !object.isRevealed {
            guard object.points.count >= 2 else { continue }
            let path = UIBezierPath()
            path.move(to: screenPoint(object.points[0]))
            for point in object.points.dropFirst() {
                path.addLine(to: screenPoint(point))
            }
            path.close()
            UIColor(
                red: object.red,
                green: object.green,
                blue: object.blue,
                alpha: object.alpha
            ).setFill()
            path.fill()
        }
    }

    private func screenPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (canvasOrigin.x + point.x) * zoomScale - contentOffset.x,
            y: (canvasOrigin.y + point.y) * zoomScale - contentOffset.y
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
        UIColor.systemBlue.withAlphaComponent(0.95).setStroke()
        context.setLineWidth(2)
        context.setLineDash(phase: 0, lengths: [8, 5])
        let drawableSelectedRects = selectedRects.filter { !$0.isNull && !$0.isEmpty }
        for rect in drawableSelectedRects {
            let highlight = rect.insetBy(dx: -4, dy: -4)
            let path = UIBezierPath(roundedRect: highlight, cornerRadius: 7)
            path.stroke()
        }
        if drawableSelectedRects.count > 1 {
            let groupRect = drawableSelectedRects
                .dropFirst()
                .reduce(drawableSelectedRects[0]) { $0.union($1) }
                .insetBy(dx: -10, dy: -10)
            UIColor.systemBlue.withAlphaComponent(0.98).setStroke()
            context.setLineWidth(4)
            context.setLineDash(phase: 0, lengths: [])
            UIBezierPath(roundedRect: groupRect, cornerRadius: 10).stroke()

            let topCenter = CGPoint(x: groupRect.midX, y: groupRect.minY)
            let knob = CGPoint(x: groupRect.midX, y: groupRect.minY - 34)
            let stem = UIBezierPath()
            stem.move(to: topCenter)
            stem.addLine(to: knob)
            stem.lineWidth = 2
            UIColor.systemBlue.setStroke()
            stem.stroke()

            let knobRect = CGRect(x: knob.x - 9, y: knob.y - 9, width: 18, height: 18)
            UIColor.white.setFill()
            UIBezierPath(ovalIn: knobRect).fill()
            let knobPath = UIBezierPath(ovalIn: knobRect)
            knobPath.lineWidth = 2
            UIColor.systemBlue.setStroke()
            knobPath.stroke()

            let handleSize: CGFloat = 18
            let handleRect = CGRect(
                x: groupRect.maxX - handleSize / 2,
                y: groupRect.maxY - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            UIColor.white.setFill()
            let handlePath = UIBezierPath(roundedRect: handleRect, cornerRadius: 5)
            handlePath.fill()
            handlePath.lineWidth = 2
            UIColor.systemBlue.setStroke()
            handlePath.stroke()
        }

        context.restoreGState()
    }
}

private extension CanvasRegionSelectionOverlayView.Mode {
    init(_ mode: CanvasToolCommand.SelectionMode) {
        switch mode {
        case .tap:
            self = .marquee
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
    private static let rotationStemLength: CGFloat = 30

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
            let frame = screenRect(for: object.frame)
            if let context = UIGraphicsGetCurrentContext(), object.rotation != 0 {
                context.saveGState()
                let center = screenPoint(object.center)
                context.translateBy(x: center.x, y: center.y)
                context.rotate(by: object.rotation)
                let rotatedFrame = CGRect(
                    x: -frame.width / 2,
                    y: -frame.height / 2,
                    width: frame.width,
                    height: frame.height
                )
                image.draw(in: rotatedFrame)
                context.restoreGState()
            } else {
                image.draw(in: frame)
            }
            if object.id == selectedImageObjectID {
                drawSelectionFrame(for: object)
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

    private func screenRect(for sourceRect: CGRect) -> CGRect {
        CGRect(
            x: (canvasOrigin.x + sourceRect.minX) * zoomScale - contentOffset.x,
            y: (canvasOrigin.y + sourceRect.minY) * zoomScale - contentOffset.y,
            width: sourceRect.width * zoomScale,
            height: sourceRect.height * zoomScale
        )
    }

    private func screenPoint(_ sourcePoint: CGPoint) -> CGPoint {
        CGPoint(
            x: (canvasOrigin.x + sourcePoint.x) * zoomScale - contentOffset.x,
            y: (canvasOrigin.y + sourcePoint.y) * zoomScale - contentOffset.y
        )
    }

    private func rotatedSourcePoint(_ point: CGPoint, object: CanvasImageObject) -> CGPoint {
        let center = object.center
        let dx = point.x - center.x
        let dy = point.y - center.y
        let cosR = cos(object.rotation)
        let sinR = sin(object.rotation)
        return CGPoint(x: center.x + dx * cosR - dy * sinR, y: center.y + dx * sinR + dy * cosR)
    }

    private func drawSelectionFrame(for object: CanvasImageObject) {
        let topLeft = screenPoint(rotatedSourcePoint(CGPoint(x: object.frame.minX, y: object.frame.minY), object: object))
        let topRight = screenPoint(rotatedSourcePoint(CGPoint(x: object.frame.maxX, y: object.frame.minY), object: object))
        let bottomRight = screenPoint(rotatedSourcePoint(CGPoint(x: object.frame.maxX, y: object.frame.maxY), object: object))
        let bottomLeft = screenPoint(rotatedSourcePoint(CGPoint(x: object.frame.minX, y: object.frame.maxY), object: object))

        let path = UIBezierPath()
        path.move(to: topLeft)
        path.addLine(to: topRight)
        path.addLine(to: bottomRight)
        path.addLine(to: bottomLeft)
        path.close()
        UIColor.systemBlue.setStroke()
        path.lineWidth = 2
        path.setLineDash([6, 4], count: 2, phase: 0)
        path.stroke()

        if object.isLocked == true {
            drawLockBadge(at: topRight)
            return
        }

        let topCenter = screenPoint(rotatedSourcePoint(CGPoint(x: object.frame.midX, y: object.frame.minY), object: object))
        let up = CGVector(dx: sin(object.rotation), dy: -cos(object.rotation))
        let knob = CGPoint(
            x: topCenter.x + up.dx * Self.rotationStemLength,
            y: topCenter.y + up.dy * Self.rotationStemLength
        )
        let stem = UIBezierPath()
        stem.move(to: topCenter)
        stem.addLine(to: knob)
        stem.lineWidth = 2
        UIColor.systemBlue.setStroke()
        stem.stroke()
        drawRotationKnob(at: knob)

        let handleSize: CGFloat = 18
        let handleRect = CGRect(
            x: bottomRight.x - handleSize / 2,
            y: bottomRight.y - handleSize / 2,
            width: handleSize,
            height: handleSize
        )
        let handlePath = UIBezierPath(roundedRect: handleRect, cornerRadius: 5)
        UIColor.white.setFill()
        handlePath.fill()
        UIColor.systemBlue.setStroke()
        handlePath.lineWidth = 2
        handlePath.stroke()
    }

    private func drawLockBadge(at point: CGPoint) {
        let badgeRect = CGRect(x: point.x - 11, y: point.y - 11, width: 22, height: 22)
        let badgePath = UIBezierPath(ovalIn: badgeRect)
        UIColor.white.setFill()
        badgePath.fill()
        UIColor.systemBlue.setStroke()
        badgePath.lineWidth = 2
        badgePath.stroke()

        if let lockImage = UIImage(systemName: "lock.fill") {
            lockImage
                .withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
                .draw(in: badgeRect.insetBy(dx: 5, dy: 5))
        }
    }

    private func drawRotationKnob(at point: CGPoint) {
        let r = CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18)
        UIColor.white.setFill()
        UIBezierPath(ovalIn: r).fill()
        UIColor.systemBlue.setStroke()
        let ring = UIBezierPath(ovalIn: r)
        ring.lineWidth = 2
        ring.stroke()
    }
}

private final class CanvasGeometryObjectsView: UIView {
    private var geometryObjects: [CanvasGeometryObject] = []
    private var selectedGeometryObjectID: UUID?
    private var resizingGeometryObjectID: UUID?
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
        _ geometryObjects: [CanvasGeometryObject],
        selectedGeometryObjectID: UUID? = nil,
        resizingGeometryObjectID: UUID? = nil
    ) {
        guard self.geometryObjects != geometryObjects
                || self.selectedGeometryObjectID != selectedGeometryObjectID
                || self.resizingGeometryObjectID != resizingGeometryObjectID else {
            return
        }
        self.geometryObjects = geometryObjects
        self.selectedGeometryObjectID = selectedGeometryObjectID
        self.resizingGeometryObjectID = resizingGeometryObjectID
        setNeedsDisplay()
    }

    func updateViewport(zoomScale: CGFloat, contentOffset: CGPoint, canvasOrigin: CGPoint) {
        self.zoomScale = zoomScale
        self.contentOffset = contentOffset
        self.canvasOrigin = canvasOrigin
        setNeedsDisplay()
    }

    // Rotation stem length (screen points) from the top edge to the rotate knob.
    static let rotationStemLength: CGFloat = 30

    override func draw(_ rect: CGRect) {
        UIColor.clear.setFill()
        UIRectFill(rect)
        guard let context = UIGraphicsGetCurrentContext() else { return }

        for object in geometryObjects {
            let normalized = object.normalizedFrame
            let boundingRect = screenRect(for: normalized)
            let start = screenPoint(x: object.x, y: object.y)
            let end = screenPoint(x: object.x + object.width, y: object.y + object.height)
            let pivot = screenPoint(x: object.pivot.x, y: object.pivot.y)
            CanvasGeometryRenderer.draw(
                object,
                boundingRect: boundingRect,
                start: start,
                end: end,
                lineWidthScale: zoomScale,
                pivot: pivot,
                in: context
            )
            if object.id == selectedGeometryObjectID {
                drawSelection(for: object)
            }
        }
    }

    private func screenRect(for sourceRect: CGRect) -> CGRect {
        CGRect(
            x: (canvasOrigin.x + sourceRect.minX) * zoomScale - contentOffset.x,
            y: (canvasOrigin.y + sourceRect.minY) * zoomScale - contentOffset.y,
            width: sourceRect.width * zoomScale,
            height: sourceRect.height * zoomScale
        )
    }

    private func screenPoint(x: CGFloat, y: CGFloat) -> CGPoint {
        CGPoint(
            x: (canvasOrigin.x + x) * zoomScale - contentOffset.x,
            y: (canvasOrigin.y + y) * zoomScale - contentOffset.y
        )
    }

    private func rotatedScreenPoint(_ point: CGPoint, pivotSource: CGPoint, rotation: CGFloat) -> CGPoint {
        let dx = point.x - pivotSource.x
        let dy = point.y - pivotSource.y
        let cosR = cos(rotation)
        let sinR = sin(rotation)
        return screenPoint(x: pivotSource.x + dx * cosR - dy * sinR,
                           y: pivotSource.y + dx * sinR + dy * cosR)
    }

    private func drawSelection(for object: CanvasGeometryObject) {
        let normalized = object.renderedBounds
        let pivotSource = object.pivot
        let rotation = object.rotation
        func rs(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            rotatedScreenPoint(CGPoint(x: x, y: y), pivotSource: pivotSource, rotation: rotation)
        }

        let topLeft = rs(normalized.minX, normalized.minY)
        let topRight = rs(normalized.maxX, normalized.minY)
        let bottomRight = rs(normalized.maxX, normalized.maxY)
        let bottomLeft = rs(normalized.minX, normalized.maxY)

        let box = UIBezierPath()
        box.move(to: topLeft)
        box.addLine(to: topRight)
        box.addLine(to: bottomRight)
        box.addLine(to: bottomLeft)
        box.close()
        UIColor.systemBlue.setStroke()
        box.lineWidth = 2
        box.setLineDash([6, 4], count: 2, phase: 0)
        box.stroke()

        // While actively resizing a circle/rectangle/right triangle, show a
        // dotted diagonal corner-to-corner of the box when it is equal-sided
        // (perfect circle / square / isosceles right triangle). It is a transient
        // resize guide only — nothing is drawn once the resize ends.
        if object.id == resizingGeometryObjectID,
           object.shape == .circle || object.shape == .rectangle || object.shape == .rightTriangle,
           CanvasGeometryRenderer.isEqualSided(width: object.width, height: object.height) {
            let diagonal = UIBezierPath()
            diagonal.move(to: topLeft)
            diagonal.addLine(to: bottomRight)
            diagonal.lineWidth = 4
            diagonal.lineCapStyle = .round
            diagonal.setLineDash([4, 5], count: 2, phase: 0)
            UIColor.systemBlue.setStroke()
            diagonal.stroke()
        }

        // Rotation stem + knob, extending outward from the top edge center.
        let topCenter = rs(normalized.midX, normalized.minY)
        let up = CGVector(dx: sin(rotation), dy: -cos(rotation))
        let knob = CGPoint(
            x: topCenter.x + up.dx * Self.rotationStemLength,
            y: topCenter.y + up.dy * Self.rotationStemLength
        )
        let stem = UIBezierPath()
        stem.move(to: topCenter)
        stem.addLine(to: knob)
        stem.lineWidth = 2
        UIColor.systemBlue.setStroke()
        stem.stroke()
        drawRotationKnob(at: knob)

        // Resize handle follows the signed resize corner, so dragging through
        // the origin can flip directional shapes such as right triangles.
        let resizeCorner = rotatedScreenPoint(
            CGPoint(x: object.x + object.width, y: object.y + object.height),
            pivotSource: pivotSource,
            rotation: rotation
        )
        drawResizeHandle(at: resizeCorner)

        // Green rotation pivot dot (invariant under the object's own rotation).
        drawPivotDot(at: screenPoint(x: pivotSource.x, y: pivotSource.y))

        if object.shape == .triangle {
            drawApexHandle(at: rotatedScreenPoint(object.triangleApexSourcePoint, pivotSource: pivotSource, rotation: rotation))
        }
    }

    private func drawResizeHandle(at point: CGPoint) {
        let r = CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14)
        UIColor.white.setFill()
        UIBezierPath(roundedRect: r, cornerRadius: 4).fill()
        UIColor.systemBlue.setStroke()
        let path = UIBezierPath(roundedRect: r, cornerRadius: 4)
        path.lineWidth = 2
        path.stroke()
    }

    private func drawRotationKnob(at point: CGPoint) {
        let r = CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18)
        UIColor.white.setFill()
        UIBezierPath(ovalIn: r).fill()
        UIColor.systemBlue.setStroke()
        let ring = UIBezierPath(ovalIn: r)
        ring.lineWidth = 2
        ring.stroke()
    }

    private func drawPivotDot(at point: CGPoint) {
        let r = CGRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16)
        UIColor.systemGreen.setFill()
        UIBezierPath(ovalIn: r).fill()
        UIColor.white.setStroke()
        let ring = UIBezierPath(ovalIn: r)
        ring.lineWidth = 2
        ring.stroke()
    }

    private func drawApexHandle(at point: CGPoint) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: point.x, y: point.y - 8))
        path.addLine(to: CGPoint(x: point.x + 8, y: point.y))
        path.addLine(to: CGPoint(x: point.x, y: point.y + 8))
        path.addLine(to: CGPoint(x: point.x - 8, y: point.y))
        path.close()
        UIColor.systemOrange.setFill()
        path.fill()
        UIColor.white.setStroke()
        path.lineWidth = 2
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
    private static let rotationStemLength: CGFloat = 30

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
            if let context = UIGraphicsGetCurrentContext(), object.rotation != 0 {
                context.saveGState()
                let center = screenPoint(object.center)
                context.translateBy(x: center.x, y: center.y)
                context.rotate(by: object.rotation)
                CanvasMathTextRenderer.draw(
                    object,
                    in: CGRect(x: -frame.width / 2, y: -frame.height / 2, width: frame.width, height: frame.height),
                    scale: zoomScale
                )
                context.restoreGState()
            } else {
                CanvasMathTextRenderer.draw(object, in: frame, scale: zoomScale)
            }
            if object.id == selectedTextObjectID {
                drawSelectionFrame(for: object)
            }
        }
    }

    private func screenPoint(_ sourcePoint: CGPoint) -> CGPoint {
        CGPoint(
            x: (canvasOrigin.x + sourcePoint.x) * zoomScale - contentOffset.x,
            y: (canvasOrigin.y + sourcePoint.y) * zoomScale - contentOffset.y
        )
    }

    private func rotatedSourcePoint(_ point: CGPoint, object: CanvasTextObject) -> CGPoint {
        let center = object.center
        let dx = point.x - center.x
        let dy = point.y - center.y
        let cosR = cos(object.rotation)
        let sinR = sin(object.rotation)
        return CGPoint(x: center.x + dx * cosR - dy * sinR, y: center.y + dx * sinR + dy * cosR)
    }

    private func drawSelectionFrame(for object: CanvasTextObject) {
        let inset: CGFloat = -6 / max(zoomScale, 0.001)
        let frame = object.frame.insetBy(dx: inset, dy: inset)
        let topLeft = screenPoint(rotatedSourcePoint(CGPoint(x: frame.minX, y: frame.minY), object: object))
        let topRight = screenPoint(rotatedSourcePoint(CGPoint(x: frame.maxX, y: frame.minY), object: object))
        let bottomRight = screenPoint(rotatedSourcePoint(CGPoint(x: frame.maxX, y: frame.maxY), object: object))
        let bottomLeft = screenPoint(rotatedSourcePoint(CGPoint(x: frame.minX, y: frame.maxY), object: object))

        let path = UIBezierPath()
        path.move(to: topLeft)
        path.addLine(to: topRight)
        path.addLine(to: bottomRight)
        path.addLine(to: bottomLeft)
        path.close()
        UIColor.systemBlue.setStroke()
        path.lineWidth = 2
        path.setLineDash([6, 4], count: 2, phase: 0)
        path.stroke()

        UIColor.systemBlue.withAlphaComponent(0.75).setFill()
        for point in [topLeft, topRight, bottomLeft] {
            UIBezierPath(ovalIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)).fill()
        }

        let topCenter = screenPoint(rotatedSourcePoint(CGPoint(x: frame.midX, y: frame.minY), object: object))
        let up = CGVector(dx: sin(object.rotation), dy: -cos(object.rotation))
        let knob = CGPoint(
            x: topCenter.x + up.dx * Self.rotationStemLength,
            y: topCenter.y + up.dy * Self.rotationStemLength
        )
        let stem = UIBezierPath()
        stem.move(to: topCenter)
        stem.addLine(to: knob)
        stem.lineWidth = 2
        UIColor.systemBlue.setStroke()
        stem.stroke()
        drawRotationKnob(at: knob)

        let resizeHandleRect = CGRect(x: bottomRight.x - 7, y: bottomRight.y - 7, width: 14, height: 14)
        UIColor.white.setFill()
        UIBezierPath(roundedRect: resizeHandleRect, cornerRadius: 4).fill()
        UIColor.systemBlue.setStroke()
        let handlePath = UIBezierPath(roundedRect: resizeHandleRect, cornerRadius: 4)
        handlePath.lineWidth = 2
        handlePath.stroke()
    }

    private func drawRotationKnob(at point: CGPoint) {
        let rect = CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18)
        UIColor.white.setFill()
        UIBezierPath(ovalIn: rect).fill()
        UIColor.systemBlue.setStroke()
        let ring = UIBezierPath(ovalIn: rect)
        ring.lineWidth = 2
        ring.stroke()
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
    @Binding var geometryObjects: [CanvasGeometryObject]
    @Binding var coverObjects: [CanvasCoverObject]
    @Binding var objectLayerState: CanvasObjectLayerState
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
    let onExtractActionCompleted: (@MainActor () -> Void)?

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
        context.coordinator.installGeometryCreationRecognizer(on: hostView)
        context.coordinator.installCoverCreationRecognizer(on: hostView)
        hostView.updateBackground(background, using: canvas)
        hostView.updateImageObjects(
            imageObjects,
            assetDirectoryURL: CanvasImageObject.assetDirectoryURL(forDrawingURL: drawingURL),
            using: canvas
        )
        hostView.updateGeometryObjects(geometryObjects, using: canvas)
        hostView.updateCoverObjects(coverObjects, using: canvas)
        hostView.updateTextObjects(textObjects, using: canvas)
        hostView.updateObjectLayerState(objectLayerState)

        // Tool picker has to be installed after the view is in a window;
        // schedule it on the next runloop pass so the view hierarchy has
        // a chance to attach first.
        DispatchQueue.main.async {
            context.coordinator.configureViewport(for: canvas)
            context.coordinator.installToolPicker(on: canvas, isVisible: showsSystemToolPicker)
            context.coordinator.applyObjectCommandIfNeeded(objectCommand, to: canvas)
            context.coordinator.applyToolCommandIfNeeded(toolCommand, to: canvas)
            hostView.updateBackground(self.background, using: canvas)
            hostView.updateImageObjects(
                self.imageObjects,
                assetDirectoryURL: CanvasImageObject.assetDirectoryURL(forDrawingURL: self.drawingURL),
                using: canvas,
                selectedImageObjectID: context.coordinator.selectedImageObjectForDisplayID
            )
            hostView.updateGeometryObjects(
                self.geometryObjects,
                using: canvas,
                selectedGeometryObjectID: context.coordinator.selectedGeometryObjectForDisplayID
            )
            hostView.updateCoverObjects(self.coverObjects, using: canvas)
            hostView.updateTextObjects(
                self.textObjects,
                using: canvas,
                hiddenTextObjectID: context.coordinator.activeEditingTextObjectID,
                selectedTextObjectID: context.coordinator.selectedTextObjectForDisplayID
            )
            hostView.updateObjectLayerState(self.objectLayerState)
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
        hostView.updateGeometryObjects(
            geometryObjects,
            using: canvas,
            selectedGeometryObjectID: context.coordinator.selectedGeometryObjectForDisplayID
        )
        hostView.updateCoverObjects(coverObjects, using: canvas)
        hostView.updateTextObjects(
            textObjects,
            using: canvas,
            hiddenTextObjectID: context.coordinator.activeEditingTextObjectID,
            selectedTextObjectID: context.coordinator.selectedTextObjectForDisplayID
        )
        hostView.updateObjectLayerState(objectLayerState)
        context.coordinator.updateActiveTextEditorFrame(on: canvas)
        context.coordinator.applyViewportCommandIfNeeded(viewportCommand, to: canvas)
        context.coordinator.updateToolPickerVisibility(isVisible: showsSystemToolPicker, for: canvas)
        context.coordinator.applyObjectCommandIfNeeded(objectCommand, to: canvas)
        context.coordinator.applyToolCommandIfNeeded(toolCommand, to: canvas)

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
        private static let minimumRegionSelectionDragDistance: CGFloat = 8

        private var toolPicker: PKToolPicker?
        private var liveStrokeRecognizer: PencilLiveStrokeGestureRecognizer?
        private var laserStrokeRecognizer: PencilLiveStrokeGestureRecognizer?
        private var textPlacementRecognizer: UITapGestureRecognizer?
        private var textSelectionTapRecognizer: UITapGestureRecognizer?
        private var textSelectionDoubleTapRecognizer: UITapGestureRecognizer?
        private var textSelectionPanRecognizer: CanvasObjectDragGestureRecognizer?
        private var selectionLongPressRecognizer: UILongPressGestureRecognizer?
        private var textEditorDismissRecognizer: UITapGestureRecognizer?
        private var regionSelectionRecognizer: PencilLiveStrokeGestureRecognizer?
        private var geometryCreationRecognizer: PencilLiveStrokeGestureRecognizer?
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
        private var activeSelectionBehavior: CanvasToolCommand.SelectionBehavior = .single
        private var activeExtractAction: CanvasToolCommand.ExtractAction = .copy
        private var activeRegionSelection: RegionSelection?
        private var activeRegionSourcePoints: [CGPoint] = []
        private var activeRegionOverlayPoints: [CGPoint] = []
        private var activeRegionConsumedSampleCount = 0
        private var isActiveRegionSelectionDrag = false
        private var activeRegionSelectedTextObjectIDs: Set<UUID> = []
        private var activeRegionSelectedImageObjectIDs: Set<UUID> = []
        private var activeRegionSelectedGeometryObjectIDs: Set<UUID> = []
        private var activeRegionSelectedStrokeIndexes: Set<Int> = []
        private var activeGroupTransform: GroupTransformKind?
        private var activeGroupStartSourcePoint: CGPoint = .zero
        private var activeGroupStartBounds: CGRect = .null
        private var activeGroupStartCenter: CGPoint = .zero
        private var activeGroupStartAngle: CGFloat = 0
        private var activeGroupStartTextObjects: [CanvasTextObject] = []
        private var activeGroupStartImageObjects: [CanvasImageObject] = []
        private var activeGroupStartGeometryObjects: [CanvasGeometryObject] = []
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
        private var resizingTextStartAnchorSourcePoint: CGPoint = .zero
        private var resizingTextStartRotation: CGFloat = 0
        private var rotatingTextObjectID: UUID?
        private var rotatingTextStartRotation: CGFloat = 0
        private var rotatingTextStartAngle: CGFloat = 0
        private var resizingImageObjectID: UUID?
        private var resizingImageObjectStartSize: CGSize = .zero
        private var resizingImageStartAnchorSourcePoint: CGPoint = .zero
        private var resizingImageStartRotation: CGFloat = 0
        private var rotatingImageObjectID: UUID?
        private var rotatingImageStartRotation: CGFloat = 0
        private var rotatingImageStartAngle: CGFloat = 0
        private var selectedGeometryObjectID: UUID?
        private var lastSelectedGeometryObjectID: UUID?
        private var movingGeometryObjectID: UUID?
        private var movingGeometryObjectStartOrigin: CGPoint = .zero
        private var movingGeometryObjectStartPivot: CGPoint?
        private var movingGeometryStartSourcePoint: CGPoint = .zero
        private var resizingGeometryObjectID: UUID?
        private var resizingGeometryObjectStartOrigin: CGPoint = .zero
        private var resizingGeometryObjectStartSize: CGSize = .zero
        private var resizingGeometryStartAnchorSourcePoint: CGPoint = .zero
        private var resizingGeometryStartPivot: CGPoint = .zero
        private var resizingGeometryStartRotation: CGFloat = 0
        private var resizingGeometryStartLocalPoint: CGPoint = .zero
        private var rotatingGeometryObjectID: UUID?
        private var rotatingGeometryStartRotation: CGFloat = 0
        private var rotatingGeometryStartAngle: CGFloat = 0
        private var pivotDraggingGeometryObjectID: UUID?
        private var apexDraggingGeometryObjectID: UUID?
        private var pendingGeometryHandleHit: (id: UUID, kind: GeometryHandleKind)?
        private var creatingGeometryObjectID: UUID?
        private var creatingGeometryStartSourcePoint: CGPoint = .zero
        private var creatingGeometryConsumedSampleCount = 0
        private var activeGeometryConfig: GeometryToolConfig?
        private var coverCreationRecognizer: PencilLiveStrokeGestureRecognizer?
        private var activeCoverConfig: CoverToolConfig?
        private var creatingCoverObjectID: UUID?
        private var creatingCoverSourcePoints: [CGPoint] = []
        private var creatingCoverConsumedSampleCount = 0
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

        struct GeometryToolConfig {
            var shape: CanvasGeometryShape
            var strokeColor: CanvasStrokeColor
            var strokeWidth: CGFloat
            var fillColor: CanvasStrokeColor
            var fillOpacity: CGFloat
            var polygonSides: Int
            var arrow: CanvasGeometryArrow
        }

        struct CoverToolConfig {
            var color: CanvasStrokeColor
            var mode: CanvasToolCommand.SelectionMode
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

            // Geometry creation is only active for the geometry tool; the
            // `.geometry` case re-enables it. Clearing here keeps every other
            // tool from leaving a live create gesture armed.
            geometryCreationRecognizer?.isEnabled = false
            if case .geometry = command.action {} else {
                activeGeometryConfig = nil
                finishCreatingGeometryObject(commit: false)
            }

            // Cover (tape) creation is only active for the cover tool.
            coverCreationRecognizer?.isEnabled = false
            if case .cover = command.action {} else {
                activeCoverConfig = nil
                creatingCoverSourcePoints = []
                creatingCoverConsumedSampleCount = 0
            }

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
            case .select(let target, let mode, let behavior, let extractAction):
                finishTextEditing()
                activeLiveStrokeColor = nil
                activeLiveStrokeWidth = nil
                activeLiveStrokeTool = nil
                activeTextColor = nil
                let didSelectionConfigurationChange = activeSelectionTarget != target
                    || activeRegionSelectionMode != mode
                    || activeSelectionBehavior != behavior
                activeSelectionTarget = target
                isTextSelectionEnabled = target == .object
                isRegionSelectionEnabled = target == .region || mode != .tap
                activeRegionSelectionMode = mode
                activeSelectionBehavior = behavior
                if let extractAction {
                    activeExtractAction = extractAction
                }
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
                    if self.activeSelectionTarget == .region {
                        self.copySelectedRegionToPasteboard(using: canvas)
                    } else {
                        self.copySelectedSemanticObjectToPasteboard(using: canvas)
                    }
                }
            case .pasteSelection:
                Task { @MainActor [weak self, weak canvas] in
                    guard let self, let canvas else { return }
                    if self.activeSelectionTarget == .region {
                        self.pasteExtractedImageFromPasteboard(using: canvas)
                    } else {
                        self.pasteClipboardObjectFromPasteboard(using: canvas)
                    }
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
            case .setExtractAction(let action):
                Task { @MainActor [weak self, weak canvas] in
                    guard let self, let canvas else { return }
                    self.activeExtractAction = action
                    _ = self.performActiveExtractActionIfPossible(using: canvas)
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
            case .geometry(let shape, let strokeColor, let strokeWidth, let fillColor, let fillOpacity, let polygonSides, let arrow):
                finishTextEditing()
                activeLiveStrokeColor = nil
                activeLiveStrokeWidth = nil
                activeLiveStrokeTool = nil
                activeTextColor = nil
                let isEditingSelectedGeometry = selectedGeometryObjectIDFromSharedState != nil || selectedGeometryObjectID != nil
                isTextSelectionEnabled = isEditingSelectedGeometry
                isRegionSelectionEnabled = false
                if !isEditingSelectedGeometry {
                    setSelectedTextObjectID(nil)
                }
                activeLaserDuration = 0
                if isEditingSelectedGeometry {
                    activeGeometryConfig = nil
                } else {
                    setSelectedGeometryObjectID(nil)
                    activeGeometryConfig = GeometryToolConfig(
                        shape: shape,
                        strokeColor: strokeColor,
                        strokeWidth: strokeWidth,
                        fillColor: fillColor,
                        fillOpacity: fillOpacity,
                        polygonSides: polygonSides,
                        arrow: arrow
                    )
                }
                liveStrokeRecognizer?.isEnabled = false
                liveStrokeRecognizer?.cancelsTouchesInView = false
                canvas.drawingGestureRecognizer.isEnabled = false
                canvas.panGestureRecognizer.minimumNumberOfTouches = 2
                activeSelectionTarget = .object
                geometryCreationRecognizer?.isEnabled = !isEditingSelectedGeometry
                hostView?.laserOverlayView.acceptsLaserInput = false
                hostView?.textPlacementOverlayView.acceptsTextPlacement = false
                hostView?.regionSelectionOverlayView.acceptsRegionSelectionInput = false
                clearRegionSelection()
                updateHostTextObjects(using: canvas)
                clearLaserOverlay()
            case .cover(let color, let mode):
                finishTextEditing()
                activeLiveStrokeColor = nil
                activeLiveStrokeWidth = nil
                activeLiveStrokeTool = nil
                activeTextColor = nil
                isTextSelectionEnabled = false
                isRegionSelectionEnabled = false
                setSelectedTextObjectID(nil)
                setSelectedGeometryObjectID(nil)
                activeLaserDuration = 0
                activeCoverConfig = CoverToolConfig(color: color, mode: mode)
                creatingCoverSourcePoints = []
                creatingCoverConsumedSampleCount = 0
                liveStrokeRecognizer?.isEnabled = false
                liveStrokeRecognizer?.cancelsTouchesInView = false
                canvas.drawingGestureRecognizer.isEnabled = false
                canvas.panGestureRecognizer.minimumNumberOfTouches = 2
                coverCreationRecognizer?.isEnabled = true
                hostView?.laserOverlayView.acceptsLaserInput = false
                hostView?.textPlacementOverlayView.acceptsTextPlacement = false
                hostView?.regionSelectionOverlayView.acceptsRegionSelectionInput = false
                clearRegionSelection()
                updateHostTextObjects(using: canvas)
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
            case .insertImage(let insertion):
                Task { @MainActor [weak self, weak canvas] in
                    guard let self, let canvas else { return }
                    _ = self.saveImageObject(
                        pngData: insertion.pngData,
                        frame: insertion.frame,
                        selectAfterInsert: insertion.selectAfterInsert,
                        isLocked: insertion.isLocked,
                        using: canvas
                    )
                }
            case .insertImageNearViewport(let insertion):
                Task { @MainActor [weak self, weak canvas] in
                    guard let self, let canvas else { return }
                    let frame = self.sourceFrame(forViewportImageInsertion: insertion, on: canvas)
                    _ = self.saveImageObject(
                        pngData: insertion.pngData,
                        frame: frame,
                        selectAfterInsert: insertion.selectAfterInsert,
                        isLocked: insertion.isLocked,
                        using: canvas
                    )
                }
            case .updateText(let update):
                Task { @MainActor [weak self, weak canvas] in
                    guard let self, let canvas else { return }
                    self.updateTextObject(update, using: canvas)
                }
            case .updateGeometry(let update):
                Task { @MainActor [weak self, weak canvas] in
                    guard let self, let canvas else { return }
                    self.updateGeometryObject(update, using: canvas)
                }
            case .clearSelection:
                Task { @MainActor [weak self, weak canvas] in
                    guard let self, let canvas else { return }
                    self.clearObjectSelection(using: canvas)
                }
            case .copy(let object):
                Task { @MainActor [weak self, weak canvas] in
                    guard let self, let canvas else { return }
                    self.copySemanticObject(object, using: canvas)
                }
            case .pasteClipboard:
                Task { @MainActor [weak self, weak canvas] in
                    guard let self, let canvas else { return }
                    self.pasteClipboardObjectFromPasteboard(using: canvas)
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
            case .reorderImage(let id, let action):
                Task { @MainActor [weak self, weak canvas] in
                    guard let self, let canvas else { return }
                    self.reorderImageObject(id, action: action, using: canvas)
                }
            case .setImageLocked(let id, let isLocked):
                Task { @MainActor [weak self, weak canvas] in
                    guard let self, let canvas else { return }
                    self.setImageObjectLocked(id, isLocked: isLocked, using: canvas)
                }
            case .duplicate(.geometry(let id)):
                Task { @MainActor [weak self, weak canvas] in
                    guard let self, let canvas else { return }
                    self.duplicateGeometryObject(id, using: canvas)
                }
            case .delete(.geometry(let id)):
                Task { @MainActor [weak self, weak canvas] in
                    guard let self, let canvas else { return }
                    self.deleteGeometryObject(id, using: canvas)
                }
            case .groupSelection:
                Task { @MainActor [weak self, weak canvas] in
                    guard let self, let canvas else { return }
                    self.groupSelectedObjects(using: canvas)
                }
            case .ungroupSelection:
                Task { @MainActor [weak self, weak canvas] in
                    guard let self, let canvas else { return }
                    self.ungroupSelectedObjects(using: canvas)
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

            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleSelectionLongPress(_:)))
            longPress.minimumPressDuration = 0.45
            longPress.cancelsTouchesInView = false
            longPress.delaysTouchesBegan = false
            longPress.delaysTouchesEnded = false
            longPress.delegate = self
            canvas.addGestureRecognizer(longPress)

            textSelectionTapRecognizer = tap
            textSelectionDoubleTapRecognizer = doubleTap
            textSelectionPanRecognizer = pan
            selectionLongPressRecognizer = longPress
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

        func installGeometryCreationRecognizer(on hostView: PencilKitCanvasHostView) {
            guard geometryCreationRecognizer == nil else { return }

            let recognizer = PencilLiveStrokeGestureRecognizer(
                allowedTouchTypes: [.direct, .pencil]
            ) { [weak self, weak hostView] samples, phase in
                guard let self, let hostView else { return }
                self.handleGeometryCreationSamples(samples, phase: phase, hostView: hostView)
            }
            recognizer.cancelsTouchesInView = false
            recognizer.isEnabled = false
            recognizer.delegate = self
            hostView.addGestureRecognizer(recognizer)
            geometryCreationRecognizer = recognizer
        }

        func installCoverCreationRecognizer(on hostView: PencilKitCanvasHostView) {
            guard coverCreationRecognizer == nil else { return }

            let recognizer = PencilLiveStrokeGestureRecognizer(
                allowedTouchTypes: [.direct, .pencil]
            ) { [weak self, weak hostView] samples, phase in
                guard let self, let hostView else { return }
                self.handleCoverCreationSamples(samples, phase: phase, hostView: hostView)
            }
            recognizer.cancelsTouchesInView = false
            recognizer.isEnabled = false
            recognizer.delegate = self
            hostView.addGestureRecognizer(recognizer)
            coverCreationRecognizer = recognizer
        }

        private func handleCoverCreationSamples(
            _ samples: [CanvasLiveStrokePoint],
            phase: PencilLiveStrokeGestureRecognizer.Phase,
            hostView: PencilKitCanvasHostView
        ) {
            guard let config = activeCoverConfig, let canvas else {
                creatingCoverConsumedSampleCount = 0
                return
            }

            func sourcePointFromSample(_ sample: CanvasLiveStrokePoint) -> CGPoint {
                let canvasPoint = hostView.convert(sample.location, to: canvas)
                return sourcePoint(forCanvasPoint: canvasPoint, on: canvas)
            }

            switch phase {
            case .began:
                parent.onInteractionBegan?()
                creatingCoverObjectID = nil
                creatingCoverSourcePoints = samples.map(sourcePointFromSample)
                creatingCoverConsumedSampleCount = samples.count
            case .moved:
                let newPoints = samples.dropFirst(creatingCoverConsumedSampleCount).map(sourcePointFromSample)
                creatingCoverConsumedSampleCount = samples.count
                creatingCoverSourcePoints.append(contentsOf: newPoints)
                updateCoverPreview(config: config, using: canvas)
            case .ended, .cancelled:
                let newPoints = samples.dropFirst(creatingCoverConsumedSampleCount).map(sourcePointFromSample)
                creatingCoverSourcePoints.append(contentsOf: newPoints)
                creatingCoverConsumedSampleCount = 0
                finishCover(cancelled: phase == .cancelled, using: canvas)
            }
        }

        private func coverBoundingBox(of points: [CGPoint]) -> CGRect {
            guard let first = points.first else { return .null }
            var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
            for point in points.dropFirst() {
                minX = min(minX, point.x)
                minY = min(minY, point.y)
                maxX = max(maxX, point.x)
                maxY = max(maxY, point.y)
            }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }

        private func coverPreviewPoints(config: CoverToolConfig) -> [CGPoint] {
            switch config.mode {
            case .tap:
                let bounds = coverBoundingBox(of: creatingCoverSourcePoints)
                return [
                    CGPoint(x: bounds.minX, y: bounds.minY),
                    CGPoint(x: bounds.maxX, y: bounds.minY),
                    CGPoint(x: bounds.maxX, y: bounds.maxY),
                    CGPoint(x: bounds.minX, y: bounds.maxY)
                ]
            case .marquee:
                let bounds = coverBoundingBox(of: creatingCoverSourcePoints)
                return [
                    CGPoint(x: bounds.minX, y: bounds.minY),
                    CGPoint(x: bounds.maxX, y: bounds.minY),
                    CGPoint(x: bounds.maxX, y: bounds.maxY),
                    CGPoint(x: bounds.minX, y: bounds.maxY)
                ]
            case .lasso:
                return creatingCoverSourcePoints
            }
        }

        private func updateCoverPreview(config: CoverToolConfig, using canvas: PKCanvasView) {
            guard creatingCoverSourcePoints.count >= 2 else { return }
            let points = coverPreviewPoints(config: config)
            var coverObjects = parent.coverObjects
            if let id = creatingCoverObjectID,
               let index = coverObjects.firstIndex(where: { $0.id == id }) {
                coverObjects[index].points = points
            } else {
                let cover = CanvasCoverObject(
                    points: points,
                    red: config.color.red,
                    green: config.color.green,
                    blue: config.color.blue,
                    alpha: 1
                )
                creatingCoverObjectID = cover.id
                coverObjects.append(cover)
            }
            parent.coverObjects = coverObjects
            updateHostCoverObjects(using: canvas)
        }

        private func finishCover(cancelled: Bool, using canvas: PKCanvasView) {
            let bounds = coverBoundingBox(of: creatingCoverSourcePoints)
            let wasDrag = max(bounds.width, bounds.height) >= 12

            if cancelled || !wasDrag {
                // A tap (or cancel): drop any provisional cover, and on a tap
                // toggle the reveal state of the topmost cover under the point.
                if let id = creatingCoverObjectID {
                    parent.coverObjects.removeAll { $0.id == id }
                }
                if !cancelled, let point = creatingCoverSourcePoints.first {
                    toggleCoverReveal(at: point)
                }
            }
            // A real drag leaves the provisional cover in place as the final cover.
            creatingCoverObjectID = nil
            creatingCoverSourcePoints = []
            updateHostCoverObjects(using: canvas)
            publishImageFromModel()
        }

        private func toggleCoverReveal(at sourcePoint: CGPoint) {
            guard let index = parent.coverObjects.lastIndex(where: { $0.contains(sourcePoint) }) else { return }
            var coverObjects = parent.coverObjects
            coverObjects[index].isRevealed.toggle()
            parent.coverObjects = coverObjects
        }

        private func updateHostCoverObjects(using canvas: PKCanvasView) {
            hostView?.updateCoverObjects(parent.coverObjects, using: canvas)
        }

        private func handleGeometryCreationSamples(
            _ samples: [CanvasLiveStrokePoint],
            phase: PencilLiveStrokeGestureRecognizer.Phase,
            hostView: PencilKitCanvasHostView
        ) {
            guard let config = activeGeometryConfig, let canvas else {
                creatingGeometryConsumedSampleCount = 0
                return
            }

            func sourcePointFromSample(_ sample: CanvasLiveStrokePoint) -> CGPoint {
                let canvasPoint = hostView.convert(sample.location, to: canvas)
                return sourcePoint(forCanvasPoint: canvasPoint, on: canvas)
            }

            switch phase {
            case .began:
                guard let first = samples.first else { return }
                creatingGeometryConsumedSampleCount = samples.count
                parent.onInteractionBegan?()
                setSelectedTextObjectID(nil)
                let start = sourcePointFromSample(first)
                creatingGeometryStartSourcePoint = start
                let object = CanvasGeometryObject(
                    shape: config.shape,
                    x: start.x,
                    y: start.y,
                    width: 0,
                    height: 0,
                    strokeRed: config.strokeColor.red,
                    strokeGreen: config.strokeColor.green,
                    strokeBlue: config.strokeColor.blue,
                    strokeAlpha: config.strokeColor.alpha,
                    strokeWidth: config.strokeWidth,
                    fillRed: config.fillColor.red,
                    fillGreen: config.fillColor.green,
                    fillBlue: config.fillColor.blue,
                    fillOpacity: config.fillOpacity,
                    polygonSides: config.polygonSides,
                    arrow: config.arrow
                )
                creatingGeometryObjectID = object.id
                var geometryObjects = parent.geometryObjects
                geometryObjects.append(object)
                parent.geometryObjects = geometryObjects
                setSelectedGeometryObjectID(object.id)
                updateHostGeometryObjects(using: canvas)
            case .moved, .ended, .cancelled:
                guard let last = samples.last else { return }
                creatingGeometryConsumedSampleCount = samples.count
                let current = sourcePointFromSample(last)
                updateCreatingGeometryObject(to: current, using: canvas)
                if phase == .ended || phase == .cancelled {
                    finishCreatingGeometryObject(commit: true)
                    publishImageFromModel()
                }
            }
        }

        private func updateCreatingGeometryObject(to current: CGPoint, using canvas: PKCanvasView) {
            guard let id = creatingGeometryObjectID,
                  let index = parent.geometryObjects.firstIndex(where: { $0.id == id }) else {
                return
            }
            var geometryObjects = parent.geometryObjects
            geometryObjects[index].x = creatingGeometryStartSourcePoint.x
            geometryObjects[index].y = creatingGeometryStartSourcePoint.y
            geometryObjects[index].width = current.x - creatingGeometryStartSourcePoint.x
            geometryObjects[index].height = current.y - creatingGeometryStartSourcePoint.y
            parent.geometryObjects = geometryObjects
            updateHostGeometryObjects(using: canvas)
        }

        /// Ends any in-progress geometry create gesture. When `commit` is false
        /// or the shape is too small to be intentional, the provisional object
        /// is removed.
        private func finishCreatingGeometryObject(commit: Bool) {
            creatingGeometryConsumedSampleCount = 0
            guard let id = creatingGeometryObjectID else { return }
            creatingGeometryObjectID = nil
            guard let index = parent.geometryObjects.firstIndex(where: { $0.id == id }) else { return }
            let object = parent.geometryObjects[index]
            let isLine = object.shape == .line
            let extent = isLine
                ? hypot(object.width, object.height)
                : max(abs(object.width), abs(object.height))
            if !commit || extent < 8 {
                var geometryObjects = parent.geometryObjects
                geometryObjects.remove(at: index)
                parent.geometryObjects = geometryObjects
                if selectedGeometryObjectID == id {
                    setSelectedGeometryObjectID(nil)
                }
                if let canvas {
                    updateHostGeometryObjects(using: canvas)
                }
            } else {
                activeGeometryConfig = nil
                activeSelectionTarget = .object
                isTextSelectionEnabled = true
                isRegionSelectionEnabled = false
                geometryCreationRecognizer?.isEnabled = false
                setSelectedGeometryObjectID(id)
                if let canvas {
                    updateHostGeometryObjects(using: canvas)
                }
            }
        }

        @objc private func handleTextSelectionTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  isTextSelectionEnabled,
                  let canvas else {
                return
            }

            let location = recognizer.location(in: canvas)
            if activeTextEditor != nil {
                handleActiveTextEditorTap(atCanvasPoint: location, on: canvas)
                return
            }
            if activeSelectionTarget == .object {
                handleObjectSelectionTap(at: location, on: canvas)
                return
            }

            clearRegionSelection()
            if let handle = textHandleHit(at: location, on: canvas) {
                setSelectedTextObjectID(handle.id)
                updateHostTextObjects(using: canvas)
                return
            }
            if let handle = geometryHandleHit(at: location, on: canvas) {
                setSelectedGeometryObjectID(handle.id)
                updateHostGeometryObjects(using: canvas)
                return
            }
            if let id = hitSelectedTextObjectID(at: location, on: canvas) {
                setSelectedTextObjectID(id)
                updateHostTextObjects(using: canvas)
                return
            }
            if let id = hitSelectedGeometryObjectID(at: location, on: canvas) {
                setSelectedGeometryObjectID(id)
                updateHostGeometryObjects(using: canvas)
                return
            }
            if let object = topObjectHit(at: location, on: canvas, includeLockedImages: true) {
                switch object {
                case .text(let id):
                    setSelectedTextObjectID(id)
                case .image(let id):
                    setSelectedImageObjectID(id)
                case .geometry(let id):
                    setSelectedGeometryObjectID(id)
                }
            } else {
                setSelectedTextObjectID(nil)
            }
            updateHostTextObjects(using: canvas)
            updateHostGeometryObjects(using: canvas)
            updateHostImageObjects(using: canvas)
        }

        private func handleObjectSelectionTap(at canvasPoint: CGPoint, on canvas: PKCanvasView) {
            switch activeSelectionBehavior {
            case .single:
                handleObjectSingleSelectionTap(at: canvasPoint, on: canvas)
            case .multi:
                handleObjectMultiSelectionTap(at: canvasPoint, on: canvas)
            }
        }

        private func handleObjectSingleSelectionTap(at canvasPoint: CGPoint, on canvas: PKCanvasView) {
            if activeObjectRegionSelectionCount > 1,
               groupTransformHit(at: canvasPoint, on: canvas) != nil {
                return
            }
            guard let object = topObjectHit(at: canvasPoint, on: canvas, includeLockedImages: false) else {
                clearSingleObjectSelection()
                clearLastSingleObjectSelection()
                clearRegionSelection()
                updateHostTextObjects(using: canvas)
                updateHostGeometryObjects(using: canvas)
                updateHostImageObjects(using: canvas)
                return
            }
            if let group = savedObjectGroup(containing: object) {
                selectSavedObjectGroup(group, on: canvas)
                return
            }

            clearRegionSelection()
            clearLastSingleObjectSelection()

            switch object {
            case .text(let id):
                setSelectedTextObjectID(id)
            case .image(let id):
                setSelectedImageObjectID(id)
            case .geometry(let id):
                setSelectedGeometryObjectID(id)
            }

            updateHostTextObjects(using: canvas)
            updateHostGeometryObjects(using: canvas)
            updateHostImageObjects(using: canvas)
        }

        private func handleObjectMultiSelectionTap(at canvasPoint: CGPoint, on canvas: PKCanvasView) {
            if activeObjectRegionSelectionCount > 1,
               groupTransformHit(at: canvasPoint, on: canvas) != nil {
                return
            }
            guard let object = topObjectHit(at: canvasPoint, on: canvas, includeLockedImages: false) else {
                clearSingleObjectSelection()
                clearLastSingleObjectSelection()
                clearRegionSelection()
                updateHostTextObjects(using: canvas)
                updateHostGeometryObjects(using: canvas)
                updateHostImageObjects(using: canvas)
                return
            }
            if let group = savedObjectGroup(containing: object) {
                selectSavedObjectGroup(group, on: canvas)
                return
            }

            clearSingleObjectSelection()
            clearLastSingleObjectSelection()
            activeRegionSelection = nil
            activeRegionSourcePoints = []
            activeRegionOverlayPoints = []
            activeRegionSelectedStrokeIndexes = []

            switch object {
            case .text(let id):
                toggle(id, in: &activeRegionSelectedTextObjectIDs)
            case .image(let id):
                toggle(id, in: &activeRegionSelectedImageObjectIDs)
            case .geometry(let id):
                toggle(id, in: &activeRegionSelectedGeometryObjectIDs)
            }

            switch activeObjectRegionSelectionCount {
            case 0:
                clearRegionSelection()
                updateSharedSelectionState()
            case 1:
                hostView?.regionSelectionOverlayView.updateSelectedRects([])
                promoteSingleObjectRegionSelection(on: canvas)
            default:
                updateRegionSelectionHighlight(on: canvas)
                updateSharedSelectionState()
            }

            updateHostTextObjects(using: canvas)
            updateHostGeometryObjects(using: canvas)
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
                  let canvas else {
                return
            }

            let location = recognizer.location(in: canvas)
            if let handle = geometryHandleHit(at: location, on: canvas),
               handle.kind == .pivot,
               let index = parent.geometryObjects.firstIndex(where: { $0.id == handle.id }) {
                parent.onInteractionBegan?()
                clearRegionSelection()
                setSelectedGeometryObjectID(handle.id)
                var geometryObjects = parent.geometryObjects
                geometryObjects[index].pivotX = nil
                geometryObjects[index].pivotY = nil
                parent.geometryObjects = geometryObjects
                updateSharedSelectionState()
                updateHostGeometryObjects(using: canvas)
                publishImageFromModel()
                return
            }

            guard let id = hitTextObjectID(at: location, on: canvas),
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
                if let groupTransform = groupTransformHit(at: startLocation, on: canvas) {
                    beginGroupTransform(groupTransform, at: startLocation, on: canvas)
                    return
                }
                let geometryHandleAtStart = geometryHandleHit(at: startLocation, on: canvas) ?? pendingGeometryHandleHit
                pendingGeometryHandleHit = nil
                if let handle = textHandleHit(at: startLocation, on: canvas),
                   let object = parent.textObjects.first(where: { $0.id == handle.id }) {
                    parent.onInteractionBegan?()
                    clearRegionSelection()
                    setSelectedTextObjectID(handle.id)
                    clearObjectDragState()
                    let startSource = sourcePoint(forCanvasPoint: startLocation, on: canvas)
                    switch handle.kind {
                    case .resize:
                        resizingTextObjectID = handle.id
                        resizingTextObjectStartSize = CGSize(width: object.width, height: object.height)
                        resizingTextStartRotation = object.rotation
                        resizingTextStartAnchorSourcePoint = rotateSourcePoint(
                            CGPoint(x: object.frame.minX, y: object.frame.minY),
                            about: object.center,
                            by: object.rotation
                        )
                    case .rotate:
                        rotatingTextObjectID = handle.id
                        rotatingTextStartRotation = object.rotation
                        let center = object.center
                        rotatingTextStartAngle = atan2(startSource.y - center.y, startSource.x - center.x)
                    }
                    updateHostTextObjects(using: canvas)
                    return
                }

                if let handle = geometryHandleAtStart,
                   let object = parent.geometryObjects.first(where: { $0.id == handle.id }) {
                    parent.onInteractionBegan?()
                    clearRegionSelection()
                    setSelectedGeometryObjectID(handle.id)
                    clearObjectDragState()
                    let startSource = sourcePoint(forCanvasPoint: startLocation, on: canvas)
                    switch handle.kind {
                    case .resize:
                        resizingGeometryObjectID = handle.id
                        var resizeObject = object
                        if resizeObject.pivotX != nil || resizeObject.pivotY != nil,
                           let index = parent.geometryObjects.firstIndex(where: { $0.id == handle.id }) {
                            var geometryObjects = parent.geometryObjects
                            geometryObjects[index].pivotX = nil
                            geometryObjects[index].pivotY = nil
                            parent.geometryObjects = geometryObjects
                            resizeObject = geometryObjects[index]
                        }
                        resizingGeometryObjectStartOrigin = CGPoint(x: resizeObject.x, y: resizeObject.y)
                        resizingGeometryObjectStartSize = CGSize(width: resizeObject.width, height: resizeObject.height)
                        resizingGeometryStartPivot = resizeObject.pivot
                        resizingGeometryStartRotation = resizeObject.rotation
                        resizingGeometryStartAnchorSourcePoint = rotateSourcePoint(
                            resizingGeometryObjectStartOrigin,
                            about: resizingGeometryStartPivot,
                            by: resizingGeometryStartRotation
                        )
                        resizingGeometryStartLocalPoint = geometryLocalPoint(
                            startSource,
                            pivot: resizingGeometryStartPivot,
                            rotation: resizingGeometryStartRotation
                        )
                    case .rotate:
                        rotatingGeometryObjectID = handle.id
                        rotatingGeometryStartRotation = object.rotation
                        let pivot = object.pivot
                        rotatingGeometryStartAngle = atan2(startSource.y - pivot.y, startSource.x - pivot.x)
                    case .pivot:
                        pivotDraggingGeometryObjectID = handle.id
                    case .apex:
                        apexDraggingGeometryObjectID = handle.id
                    }
                    updateHostGeometryObjects(using: canvas)
                    return
                }

                if let handle = imageHandleHit(at: startLocation, on: canvas),
                   let object = parent.imageObjects.first(where: { $0.id == handle.id }) {
                    parent.onInteractionBegan?()
                    clearRegionSelection()
                    setSelectedImageObjectID(handle.id)
                    clearObjectDragState()
                    let startSource = sourcePoint(forCanvasPoint: startLocation, on: canvas)
                    switch handle.kind {
                    case .resize:
                        resizingImageObjectID = handle.id
                        resizingImageObjectStartSize = CGSize(width: object.width, height: object.height)
                        resizingImageStartRotation = object.rotation
                        resizingImageStartAnchorSourcePoint = rotateSourcePoint(
                            CGPoint(x: object.frame.minX, y: object.frame.minY),
                            about: object.center,
                            by: object.rotation
                        )
                    case .rotate:
                        rotatingImageObjectID = handle.id
                        rotatingImageStartRotation = object.rotation
                        let center = object.center
                        rotatingImageStartAngle = atan2(startSource.y - center.y, startSource.x - center.x)
                    }
                    updateHostImageObjects(using: canvas)
                    return
                }

                if activeSelectionBehavior == .single,
                   let object = topObjectHit(at: startLocation, on: canvas, includeLockedImages: false) {
                    beginSingleSelectionObjectDrag(object, at: startLocation, on: canvas)
                    return
                }

                let textObjectHitID = hitSelectedTextObjectID(at: startLocation, on: canvas)
                guard let id = textObjectHitID,
                      let object = parent.textObjects.first(where: { $0.id == id }) else {
                    let geometryObjectHitID = hitSelectedGeometryObjectID(at: startLocation, on: canvas)
                    if let id = geometryObjectHitID,
                       let object = parent.geometryObjects.first(where: { $0.id == id }) {
                        parent.onInteractionBegan?()
                        clearRegionSelection()
                        setSelectedGeometryObjectID(id)
                        clearObjectDragState()
                        movingGeometryObjectID = id
                        movingGeometryObjectStartOrigin = CGPoint(x: object.x, y: object.y)
                        movingGeometryObjectStartPivot = (object.pivotX != nil || object.pivotY != nil) ? object.pivot : nil
                        movingGeometryStartSourcePoint = sourcePoint(forCanvasPoint: startLocation, on: canvas)
                        updateHostGeometryObjects(using: canvas)
                        return
                    }

                    let imageObjectHitID = hitSelectedImageObjectID(at: startLocation, on: canvas)
                    if let id = imageObjectHitID,
                       let object = parent.imageObjects.first(where: { $0.id == id }) {
                        parent.onInteractionBegan?()
                        clearRegionSelection()
                        setSelectedImageObjectID(id)
                        clearObjectDragState()
                        movingImageObjectID = id
                        movingImageObjectStartOrigin = CGPoint(x: object.x, y: object.y)
                        movingImageStartSourcePoint = sourcePoint(forCanvasPoint: startLocation, on: canvas)
                        updateHostImageObjects(using: canvas)
                        return
                    }
                    clearObjectDragState()
                    return
                }
                parent.onInteractionBegan?()
                clearRegionSelection()
                setSelectedTextObjectID(id)
                clearObjectDragState()
                movingTextObjectID = id
                movingTextObjectStartOrigin = CGPoint(x: object.x, y: object.y)
                movingTextStartSourcePoint = sourcePoint(forCanvasPoint: startLocation, on: canvas)
                updateHostTextObjects(using: canvas)
            case .changed:
                if let activeGroupTransform {
                    updateGroupTransform(activeGroupTransform, at: recognizer.location(in: canvas), on: canvas)
                    return
                }
                if let resizingTextObjectID,
                   let index = parent.textObjects.firstIndex(where: { $0.id == resizingTextObjectID }) {
                    let currentSource = sourcePoint(forCanvasPoint: recognizer.location(in: canvas), on: canvas)
                    var anchoredSize = anchoredResizeSize(
                        from: resizingTextStartAnchorSourcePoint,
                        to: currentSource,
                        rotation: resizingTextStartRotation
                    )
                    let startWidth = max(resizingTextObjectStartSize.width, 1)
                    let startHeight = max(resizingTextObjectStartSize.height, 1)
                    anchoredSize.width = max(anchoredSize.width, max(parent.textObjects[index].fontSize * 4, 80))
                    anchoredSize.height = max(anchoredSize.height, max(parent.textObjects[index].fontSize * 1.4, 36))
                    if anchoredSize.width.isNaN || anchoredSize.height.isNaN {
                        anchoredSize = CGSize(width: startWidth, height: startHeight)
                    }
                    let origin = anchoredResizeOrigin(
                        anchorSource: resizingTextStartAnchorSourcePoint,
                        size: anchoredSize,
                        rotation: resizingTextStartRotation
                    )
                    commitTextObjectUpdate(at: index, using: canvas) { object in
                        object.x = origin.x
                        object.y = origin.y
                        object.width = anchoredSize.width
                        object.height = anchoredSize.height
                    }
                    updateHostTextObjects(using: canvas)
                    publishImageFromModel()
                    return
                }

                if let rotatingTextObjectID,
                   let index = parent.textObjects.firstIndex(where: { $0.id == rotatingTextObjectID }) {
                    let center = parent.textObjects[index].center
                    let currentSource = sourcePoint(forCanvasPoint: recognizer.location(in: canvas), on: canvas)
                    let currentAngle = atan2(currentSource.y - center.y, currentSource.x - center.x)
                    commitTextObjectUpdate(at: index, using: canvas) { object in
                        object.rotation = rotatingTextStartRotation + (currentAngle - rotatingTextStartAngle)
                    }
                    updateHostTextObjects(using: canvas)
                    publishImageFromModel()
                    return
                }

                if let rotatingImageObjectID,
                   let index = parent.imageObjects.firstIndex(where: { $0.id == rotatingImageObjectID }) {
                    let center = parent.imageObjects[index].center
                    let currentSource = sourcePoint(forCanvasPoint: recognizer.location(in: canvas), on: canvas)
                    let currentAngle = atan2(currentSource.y - center.y, currentSource.x - center.x)
                    var imageObjects = parent.imageObjects
                    imageObjects[index].rotation = rotatingImageStartRotation + (currentAngle - rotatingImageStartAngle)
                    parent.imageObjects = imageObjects
                    if selectedImageObjectID == rotatingImageObjectID {
                        updateSharedSelectionState()
                    }
                    updateHostImageObjects(using: canvas)
                    publishImageFromModel()
                    return
                }

                if let resizingImageObjectID,
                   let index = parent.imageObjects.firstIndex(where: { $0.id == resizingImageObjectID }) {
                    let currentSource = sourcePoint(forCanvasPoint: recognizer.location(in: canvas), on: canvas)
                    var anchoredSize = anchoredResizeSize(
                        from: resizingImageStartAnchorSourcePoint,
                        to: currentSource,
                        rotation: resizingImageStartRotation
                    )
                    let startWidth = max(resizingImageObjectStartSize.width, 1)
                    let startHeight = max(resizingImageObjectStartSize.height, 1)
                    let widthScale = anchoredSize.width / startWidth
                    let heightScale = anchoredSize.height / startHeight
                    let projectedScale = (
                        widthScale * startWidth * startWidth
                            + heightScale * startHeight * startHeight
                    ) / (startWidth * startWidth + startHeight * startHeight)
                    let minimumScale = max(24 / startWidth, 24 / startHeight)
                    let scale = max(projectedScale, minimumScale)
                    anchoredSize = CGSize(
                        width: startWidth * scale,
                        height: startHeight * scale
                    )
                    let origin = anchoredResizeOrigin(
                        anchorSource: resizingImageStartAnchorSourcePoint,
                        size: anchoredSize,
                        rotation: resizingImageStartRotation
                    )
                    var imageObjects = parent.imageObjects
                    imageObjects[index].x = origin.x
                    imageObjects[index].y = origin.y
                    imageObjects[index].width = anchoredSize.width
                    imageObjects[index].height = anchoredSize.height
                    parent.imageObjects = imageObjects
                    if selectedImageObjectID == resizingImageObjectID {
                        updateSharedSelectionState()
                    }
                    updateHostImageObjects(using: canvas)
                    publishImageFromModel()
                    return
                }

                if let rotatingGeometryObjectID,
                   let index = parent.geometryObjects.firstIndex(where: { $0.id == rotatingGeometryObjectID }) {
                    let pivot = parent.geometryObjects[index].pivot
                    let currentSource = sourcePoint(forCanvasPoint: recognizer.location(in: canvas), on: canvas)
                    let currentAngle = atan2(currentSource.y - pivot.y, currentSource.x - pivot.x)
                    var geometryObjects = parent.geometryObjects
                    geometryObjects[index].rotation = rotatingGeometryStartRotation + (currentAngle - rotatingGeometryStartAngle)
                    parent.geometryObjects = geometryObjects
                    if selectedGeometryObjectID == rotatingGeometryObjectID {
                        updateSharedSelectionState()
                    }
                    updateHostGeometryObjects(using: canvas)
                    publishImageFromModel()
                    return
                }

                if let pivotDraggingGeometryObjectID,
                   let index = parent.geometryObjects.firstIndex(where: { $0.id == pivotDraggingGeometryObjectID }) {
                    let source = sourcePoint(forCanvasPoint: recognizer.location(in: canvas), on: canvas)
                    var geometryObjects = parent.geometryObjects
                    let object = geometryObjects[index]
                    let oldPivot = object.pivot
                    let newOrigin = originPreservingRenderedPosition(
                        origin: CGPoint(x: object.x, y: object.y),
                        oldPivot: oldPivot,
                        newPivot: source,
                        rotation: object.rotation
                    )
                    geometryObjects[index].x = newOrigin.x
                    geometryObjects[index].y = newOrigin.y
                    geometryObjects[index].pivotX = source.x
                    geometryObjects[index].pivotY = source.y
                    parent.geometryObjects = geometryObjects
                    if selectedGeometryObjectID == pivotDraggingGeometryObjectID {
                        updateSharedSelectionState()
                    }
                    updateHostGeometryObjects(using: canvas)
                    publishImageFromModel()
                    return
                }

                if let apexDraggingGeometryObjectID,
                   let index = parent.geometryObjects.firstIndex(where: { $0.id == apexDraggingGeometryObjectID }) {
                    let source = sourcePoint(forCanvasPoint: recognizer.location(in: canvas), on: canvas)
                    let object = parent.geometryObjects[index]
                    let local = geometryLocalPoint(source, object: object)
                    let frame = object.normalizedFrame
                    guard frame.width > 0.001 else { return }
                    let renderedOffset = (local.x - frame.minX) / frame.width
                    var geometryObjects = parent.geometryObjects
                    geometryObjects[index].apexOffset = object.isFlippedHorizontal ? 1 - renderedOffset : renderedOffset
                    parent.geometryObjects = geometryObjects
                    if selectedGeometryObjectID == apexDraggingGeometryObjectID {
                        updateSharedSelectionState()
                    }
                    updateHostGeometryObjects(using: canvas)
                    publishImageFromModel()
                    return
                }

                if let resizingGeometryObjectID,
                   let index = parent.geometryObjects.firstIndex(where: { $0.id == resizingGeometryObjectID }) {
                    let currentSource = sourcePoint(forCanvasPoint: recognizer.location(in: canvas), on: canvas)
                    var geometryObjects = parent.geometryObjects
                    if geometryObjects[index].shape == .line {
                        let currentLocal = geometryLocalPoint(
                            currentSource,
                            pivot: resizingGeometryStartPivot,
                            rotation: resizingGeometryStartRotation
                        )
                        let delta = CGPoint(
                            x: currentLocal.x - resizingGeometryStartLocalPoint.x,
                            y: currentLocal.y - resizingGeometryStartLocalPoint.y
                        )
                        // Keep the start endpoint fixed and move the end point so
                        // the line's direction is preserved.
                        geometryObjects[index].width = resizingGeometryObjectStartSize.width + delta.x
                        geometryObjects[index].height = resizingGeometryObjectStartSize.height + delta.y
                    } else {
                        var anchoredSize = anchoredResizeSize(
                            from: resizingGeometryStartAnchorSourcePoint,
                            to: currentSource,
                            rotation: resizingGeometryStartRotation
                        )
                        anchoredSize.width = signedGeometryDimension(anchoredSize.width)
                        anchoredSize.height = signedGeometryDimension(anchoredSize.height)
                        // Snap circles/rectangles/right triangles to an equal-sided
                        // shape (perfect circle, square, or isosceles right triangle)
                        // when the width and height get close, so the user can lift on
                        // an exact equal-sided shape. Projects both onto their average
                        // magnitude (the 45° diagonal) while preserving each sign.
                        if geometryObjects[index].shape == .circle
                            || geometryObjects[index].shape == .rectangle
                            || geometryObjects[index].shape == .rightTriangle {
                            let widthMagnitude = abs(anchoredSize.width)
                            let heightMagnitude = abs(anchoredSize.height)
                            let maxMagnitude = max(widthMagnitude, heightMagnitude)
                            let snapTolerance = max(maxMagnitude * 0.06, 14)
                            if maxMagnitude > 0.5, abs(widthMagnitude - heightMagnitude) <= snapTolerance {
                                let snapped = (widthMagnitude + heightMagnitude) / 2
                                anchoredSize.width = anchoredSize.width < 0 ? -snapped : snapped
                                anchoredSize.height = anchoredSize.height < 0 ? -snapped : snapped
                            }
                        }
                        let origin = anchoredResizeOrigin(
                            anchorSource: resizingGeometryStartAnchorSourcePoint,
                            size: anchoredSize,
                            rotation: resizingGeometryStartRotation
                        )
                        geometryObjects[index].x = origin.x
                        geometryObjects[index].y = origin.y
                        geometryObjects[index].width = anchoredSize.width
                        geometryObjects[index].height = anchoredSize.height
                    }
                    parent.geometryObjects = geometryObjects
                    if selectedGeometryObjectID == resizingGeometryObjectID {
                        updateSharedSelectionState()
                    }
                    updateHostGeometryObjects(using: canvas)
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
                    if selectedImageObjectID == movingImageObjectID {
                        updateSharedSelectionState()
                    }
                    updateHostImageObjects(using: canvas)
                    publishImageFromModel()
                }
                if let movingGeometryObjectID,
                   let index = parent.geometryObjects.firstIndex(where: { $0.id == movingGeometryObjectID }) {
                    let currentSourcePoint = sourcePoint(forCanvasPoint: recognizer.location(in: canvas), on: canvas)
                    let delta = CGPoint(
                        x: currentSourcePoint.x - movingGeometryStartSourcePoint.x,
                        y: currentSourcePoint.y - movingGeometryStartSourcePoint.y
                    )
                    var geometryObjects = parent.geometryObjects
                    geometryObjects[index].x = movingGeometryObjectStartOrigin.x + delta.x
                    geometryObjects[index].y = movingGeometryObjectStartOrigin.y + delta.y
                    if let movingGeometryObjectStartPivot {
                        geometryObjects[index].pivotX = movingGeometryObjectStartPivot.x + delta.x
                        geometryObjects[index].pivotY = movingGeometryObjectStartPivot.y + delta.y
                    }
                    parent.geometryObjects = geometryObjects
                    if selectedGeometryObjectID == movingGeometryObjectID {
                        updateSharedSelectionState()
                    }
                    updateHostGeometryObjects(using: canvas)
                    publishImageFromModel()
                }
            case .ended, .cancelled, .failed:
                clearObjectDragState()
                // Refresh geometry overlay so the transient resize guide (the
                // equal-sided diagonal) clears now that no resize is in progress.
                updateHostGeometryObjects(using: canvas)
                publishImageFromModel()
            default:
                break
            }
        }

        private func beginSingleSelectionObjectDrag(
            _ object: CanvasSelectionState.Object,
            at startLocation: CGPoint,
            on canvas: PKCanvasView
        ) {
            if let group = savedObjectGroup(containing: object) {
                selectSavedObjectGroup(group, on: canvas)
                beginGroupTransform(.move, at: startLocation, on: canvas)
                return
            }

            parent.onInteractionBegan?()
            clearRegionSelection()
            clearLastSingleObjectSelection()
            clearObjectDragState()

            switch object {
            case .text(let id):
                guard let object = parent.textObjects.first(where: { $0.id == id }) else { return }
                setSelectedTextObjectID(id)
                movingTextObjectID = id
                movingTextObjectStartOrigin = CGPoint(x: object.x, y: object.y)
                movingTextStartSourcePoint = sourcePoint(forCanvasPoint: startLocation, on: canvas)
                updateHostTextObjects(using: canvas)
            case .image(let id):
                guard let object = parent.imageObjects.first(where: { $0.id == id }),
                      object.isLocked != true else { return }
                setSelectedImageObjectID(id)
                movingImageObjectID = id
                movingImageObjectStartOrigin = CGPoint(x: object.x, y: object.y)
                movingImageStartSourcePoint = sourcePoint(forCanvasPoint: startLocation, on: canvas)
                updateHostImageObjects(using: canvas)
            case .geometry(let id):
                guard let object = parent.geometryObjects.first(where: { $0.id == id }),
                      object.isLocked != true else { return }
                setSelectedGeometryObjectID(id)
                movingGeometryObjectID = id
                movingGeometryObjectStartOrigin = CGPoint(x: object.x, y: object.y)
                movingGeometryObjectStartPivot = (object.pivotX != nil || object.pivotY != nil) ? object.pivot : nil
                movingGeometryStartSourcePoint = sourcePoint(forCanvasPoint: startLocation, on: canvas)
                updateHostGeometryObjects(using: canvas)
            }
        }

        private func beginGroupTransform(_ kind: GroupTransformKind, at canvasPoint: CGPoint, on canvas: PKCanvasView) {
            guard let groupScreenRect = selectedObjectGroupScreenRect(on: canvas) else { return }
            parent.onInteractionBegan?()
            clearObjectDragState()
            activeGroupTransform = kind
            activeGroupStartSourcePoint = sourcePoint(forCanvasPoint: canvasPoint, on: canvas)
            let topLeft = sourcePoint(forCanvasPoint: CGPoint(
                x: (groupScreenRect.minX + canvas.contentOffset.x),
                y: (groupScreenRect.minY + canvas.contentOffset.y)
            ), on: canvas)
            let bottomRight = sourcePoint(forCanvasPoint: CGPoint(
                x: (groupScreenRect.maxX + canvas.contentOffset.x),
                y: (groupScreenRect.maxY + canvas.contentOffset.y)
            ), on: canvas)
            activeGroupStartBounds = CGRect(
                x: min(topLeft.x, bottomRight.x),
                y: min(topLeft.y, bottomRight.y),
                width: abs(bottomRight.x - topLeft.x),
                height: abs(bottomRight.y - topLeft.y)
            )
            activeGroupStartCenter = CGPoint(x: activeGroupStartBounds.midX, y: activeGroupStartBounds.midY)
            activeGroupStartAngle = atan2(
                activeGroupStartSourcePoint.y - activeGroupStartCenter.y,
                activeGroupStartSourcePoint.x - activeGroupStartCenter.x
            )
            activeGroupStartTextObjects = parent.textObjects.filter { activeRegionSelectedTextObjectIDs.contains($0.id) }
            activeGroupStartImageObjects = parent.imageObjects.filter { activeRegionSelectedImageObjectIDs.contains($0.id) }
            activeGroupStartGeometryObjects = parent.geometryObjects.filter { activeRegionSelectedGeometryObjectIDs.contains($0.id) }
        }

        private func updateGroupTransform(_ kind: GroupTransformKind, at canvasPoint: CGPoint, on canvas: PKCanvasView) {
            let currentSource = sourcePoint(forCanvasPoint: canvasPoint, on: canvas)
            switch kind {
            case .move:
                let delta = CGPoint(
                    x: currentSource.x - activeGroupStartSourcePoint.x,
                    y: currentSource.y - activeGroupStartSourcePoint.y
                )
                applyGroupMove(delta: delta)
            case .resize:
                let startWidth = max(activeGroupStartBounds.width, 1)
                let startHeight = max(activeGroupStartBounds.height, 1)
                let startVector = CGVector(
                    dx: activeGroupStartSourcePoint.x - activeGroupStartBounds.minX,
                    dy: activeGroupStartSourcePoint.y - activeGroupStartBounds.minY
                )
                let currentVector = CGVector(
                    dx: currentSource.x - activeGroupStartBounds.minX,
                    dy: currentSource.y - activeGroupStartBounds.minY
                )
                let startDistance = max(hypot(startVector.dx / startWidth, startVector.dy / startHeight), 0.001)
                let currentDistance = hypot(currentVector.dx / startWidth, currentVector.dy / startHeight)
                let scale = max(currentDistance / startDistance, 0.05)
                applyGroupScale(scale)
            case .rotate:
                let currentAngle = atan2(currentSource.y - activeGroupStartCenter.y, currentSource.x - activeGroupStartCenter.x)
                applyGroupRotation(currentAngle - activeGroupStartAngle)
            }
            updateRegionSelectionHighlight(on: canvas)
            updateHostTextObjects(using: canvas)
            updateHostImageObjects(using: canvas)
            updateHostGeometryObjects(using: canvas)
            publishImageFromModel()
        }

        private func applyGroupMove(delta: CGPoint) {
            var textObjects = parent.textObjects
            for start in activeGroupStartTextObjects {
                guard let index = textObjects.firstIndex(where: { $0.id == start.id }) else { continue }
                textObjects[index].x = start.x + delta.x
                textObjects[index].y = start.y + delta.y
            }
            parent.textObjects = textObjects

            var imageObjects = parent.imageObjects
            for start in activeGroupStartImageObjects {
                guard let index = imageObjects.firstIndex(where: { $0.id == start.id }) else { continue }
                imageObjects[index].x = start.x + delta.x
                imageObjects[index].y = start.y + delta.y
            }
            parent.imageObjects = imageObjects

            var geometryObjects = parent.geometryObjects
            for start in activeGroupStartGeometryObjects {
                guard let index = geometryObjects.firstIndex(where: { $0.id == start.id }) else { continue }
                geometryObjects[index].x = start.x + delta.x
                geometryObjects[index].y = start.y + delta.y
                if start.pivotX != nil || start.pivotY != nil {
                    let pivot = start.pivot
                    geometryObjects[index].pivotX = pivot.x + delta.x
                    geometryObjects[index].pivotY = pivot.y + delta.y
                }
            }
            parent.geometryObjects = geometryObjects
        }

        private func applyGroupScale(_ scale: CGFloat) {
            func scaledPoint(_ point: CGPoint) -> CGPoint {
                CGPoint(
                    x: activeGroupStartBounds.minX + (point.x - activeGroupStartBounds.minX) * scale,
                    y: activeGroupStartBounds.minY + (point.y - activeGroupStartBounds.minY) * scale
                )
            }

            var textObjects = parent.textObjects
            for start in activeGroupStartTextObjects {
                guard let index = textObjects.firstIndex(where: { $0.id == start.id }) else { continue }
                let origin = scaledPoint(CGPoint(x: start.x, y: start.y))
                textObjects[index].x = origin.x
                textObjects[index].y = origin.y
                textObjects[index].width = max(start.width * scale, 24)
                textObjects[index].height = max(start.height * scale, 18)
                textObjects[index].fontSize = max(start.fontSize * scale, 8)
            }
            parent.textObjects = textObjects

            var imageObjects = parent.imageObjects
            for start in activeGroupStartImageObjects {
                guard let index = imageObjects.firstIndex(where: { $0.id == start.id }) else { continue }
                let origin = scaledPoint(CGPoint(x: start.x, y: start.y))
                imageObjects[index].x = origin.x
                imageObjects[index].y = origin.y
                imageObjects[index].width = max(start.width * scale, 24)
                imageObjects[index].height = max(start.height * scale, 24)
            }
            parent.imageObjects = imageObjects

            var geometryObjects = parent.geometryObjects
            for start in activeGroupStartGeometryObjects {
                guard let index = geometryObjects.firstIndex(where: { $0.id == start.id }) else { continue }
                let origin = scaledPoint(CGPoint(x: start.x, y: start.y))
                geometryObjects[index].x = origin.x
                geometryObjects[index].y = origin.y
                geometryObjects[index].width = start.width * scale
                geometryObjects[index].height = start.height * scale
                geometryObjects[index].strokeWidth = max(start.strokeWidth * scale, 1)
                if start.pivotX != nil || start.pivotY != nil {
                    let pivot = scaledPoint(start.pivot)
                    geometryObjects[index].pivotX = pivot.x
                    geometryObjects[index].pivotY = pivot.y
                }
            }
            parent.geometryObjects = geometryObjects
        }

        private func applyGroupRotation(_ rotationDelta: CGFloat) {
            var textObjects = parent.textObjects
            for start in activeGroupStartTextObjects {
                guard let index = textObjects.firstIndex(where: { $0.id == start.id }) else { continue }
                let rotatedCenter = rotateSourcePoint(start.center, about: activeGroupStartCenter, by: rotationDelta)
                textObjects[index].x = rotatedCenter.x - start.width / 2
                textObjects[index].y = rotatedCenter.y - start.height / 2
                textObjects[index].rotation = start.rotation + rotationDelta
            }
            parent.textObjects = textObjects

            var imageObjects = parent.imageObjects
            for start in activeGroupStartImageObjects {
                guard let index = imageObjects.firstIndex(where: { $0.id == start.id }) else { continue }
                let rotatedCenter = rotateSourcePoint(start.center, about: activeGroupStartCenter, by: rotationDelta)
                imageObjects[index].x = rotatedCenter.x - start.width / 2
                imageObjects[index].y = rotatedCenter.y - start.height / 2
                imageObjects[index].rotation = start.rotation + rotationDelta
            }
            parent.imageObjects = imageObjects

            var geometryObjects = parent.geometryObjects
            for start in activeGroupStartGeometryObjects {
                guard let index = geometryObjects.firstIndex(where: { $0.id == start.id }) else { continue }
                let newRotation = start.rotation + rotationDelta
                let pivot = rotateSourcePoint(start.pivot, about: activeGroupStartCenter, by: rotationDelta)
                let renderedOrigin = rotateSourcePoint(
                    rotateSourcePoint(CGPoint(x: start.x, y: start.y), about: start.pivot, by: start.rotation),
                    about: activeGroupStartCenter,
                    by: rotationDelta
                )
                let localOrigin = rotateSourcePoint(renderedOrigin, about: pivot, by: -newRotation)
                geometryObjects[index].x = localOrigin.x
                geometryObjects[index].y = localOrigin.y
                geometryObjects[index].rotation = newRotation
                geometryObjects[index].pivotX = pivot.x
                geometryObjects[index].pivotY = pivot.y
            }
            parent.geometryObjects = geometryObjects
        }

        private func clearObjectDragState() {
            activeGroupTransform = nil
            activeGroupStartTextObjects = []
            activeGroupStartImageObjects = []
            activeGroupStartGeometryObjects = []
            movingTextObjectID = nil
            movingImageObjectID = nil
            movingGeometryObjectID = nil
            movingGeometryObjectStartPivot = nil
            resizingTextObjectID = nil
            resizingImageObjectID = nil
            resizingGeometryObjectID = nil
            rotatingTextObjectID = nil
            rotatingImageObjectID = nil
            rotatingGeometryObjectID = nil
            pivotDraggingGeometryObjectID = nil
            apexDraggingGeometryObjectID = nil
            pendingGeometryHandleHit = nil
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
                activeRegionSelection = nil
                activeRegionSourcePoints = []
                activeRegionOverlayPoints = []
                activeRegionConsumedSampleCount = 0
                isActiveRegionSelectionDrag = false
                _ = appendRegionSelectionSamples(
                    samples,
                    hostView: hostView,
                    overlayView: overlayView,
                    canvas: canvas
                )
            case .moved:
                let newOverlayPoints = appendRegionSelectionSamples(
                    samples,
                    hostView: hostView,
                    overlayView: overlayView,
                    canvas: canvas
                )
                beginActiveRegionSelectionDragIfNeeded(overlayView: overlayView, canvas: canvas)
                guard isActiveRegionSelectionDrag else { return }
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
                beginActiveRegionSelectionDragIfNeeded(overlayView: overlayView, canvas: canvas)
                guard isActiveRegionSelectionDrag else {
                    activeRegionSelection = nil
                    activeRegionSourcePoints = []
                    activeRegionOverlayPoints = []
                    activeRegionConsumedSampleCount = 0
                    overlayView.clear()
                    return
                }
                overlayView.update(with: newOverlayPoints)
                closeActiveRegionSourceLassoIfNeeded()
                overlayView.closeLasso()
                updateActiveRegionSelection()
                updateRegionSelectionTargetState(using: canvas)
                if activeSelectionTarget == .object {
                    overlayView.finishSelectionShape()
                } else {
                    _ = performActiveExtractActionIfPossible(using: canvas)
                }
                activeRegionConsumedSampleCount = 0
                isActiveRegionSelectionDrag = false
                publishImageFromModel()
            }
        }

        private func beginActiveRegionSelectionDragIfNeeded(
            overlayView: CanvasRegionSelectionOverlayView,
            canvas: PKCanvasView
        ) {
            guard !isActiveRegionSelectionDrag,
                  let firstPoint = activeRegionOverlayPoints.first,
                  let lastPoint = activeRegionOverlayPoints.last,
                  hypot(lastPoint.x - firstPoint.x, lastPoint.y - firstPoint.y) >= Self.minimumRegionSelectionDragDistance else {
                return
            }

            parent.onInteractionBegan?()
            clearSingleObjectSelection()
            activeRegionSelectedTextObjectIDs = []
            activeRegionSelectedImageObjectIDs = []
            activeRegionSelectedGeometryObjectIDs = []
            activeRegionSelectedStrokeIndexes = []
            isActiveRegionSelectionDrag = true
            overlayView.begin(
                at: firstPoint,
                mode: CanvasRegionSelectionOverlayView.Mode(activeRegionSelectionMode)
            )
            updateActiveRegionSelection()
            updateRegionSelectionTargetState(using: canvas)
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
            isActiveRegionSelectionDrag = false
            clearObjectRegionTargets()
            hostView?.regionSelectionOverlayView.clear()
        }

        private var hasActiveObjectRegionSelection: Bool {
            !activeRegionSelectedTextObjectIDs.isEmpty
                || !activeRegionSelectedImageObjectIDs.isEmpty
                || !activeRegionSelectedGeometryObjectIDs.isEmpty
        }

        private var activeObjectRegionSelectionCount: Int {
            activeRegionSelectedTextObjectIDs.count
                + activeRegionSelectedImageObjectIDs.count
                + activeRegionSelectedGeometryObjectIDs.count
        }


        private func promoteSingleObjectRegionSelection(on canvas: PKCanvasView) {
            if let id = activeRegionSelectedTextObjectIDs.first {
                setSelectedTextObjectID(id)
            } else if let id = activeRegionSelectedImageObjectIDs.first {
                setSelectedImageObjectID(id)
            } else if let id = activeRegionSelectedGeometryObjectIDs.first {
                setSelectedGeometryObjectID(id)
            } else {
                updateSharedSelectionState()
            }
            updateHostTextObjects(using: canvas)
            updateHostImageObjects(using: canvas)
            updateHostGeometryObjects(using: canvas)
        }

        private func toggle(_ id: UUID, in selectedIDs: inout Set<UUID>) {
            if selectedIDs.contains(id) {
                selectedIDs.remove(id)
            } else {
                selectedIDs.insert(id)
            }
        }

        private func isObjectSelectedInActiveGroup(_ object: CanvasSelectionState.Object) -> Bool {
            switch object {
            case .text(let id):
                return activeRegionSelectedTextObjectIDs.contains(id)
            case .image(let id):
                return activeRegionSelectedImageObjectIDs.contains(id)
            case .geometry(let id):
                return activeRegionSelectedGeometryObjectIDs.contains(id)
            }
        }

        private func activeObjectGroup() -> CanvasObjectGroup? {
            guard activeObjectRegionSelectionCount > 1 else { return nil }
            return CanvasObjectGroup(
                textObjectIDs: activeRegionSelectedTextObjectIDs,
                imageObjectIDs: activeRegionSelectedImageObjectIDs,
                geometryObjectIDs: activeRegionSelectedGeometryObjectIDs
            )
        }

        private func matchingSavedObjectGroupID() -> UUID? {
            guard let activeGroup = activeObjectGroup() else { return nil }
            return parent.objectLayerState.objectGroups.first { savedGroup in
                savedGroup.isExplicit
                    && savedGroup.textObjectIDs == activeGroup.textObjectIDs
                    && savedGroup.imageObjectIDs == activeGroup.imageObjectIDs
                    && savedGroup.geometryObjectIDs == activeGroup.geometryObjectIDs
            }?.id
        }

        private func savedObjectGroup(containing object: CanvasSelectionState.Object) -> CanvasObjectGroup? {
            parent.objectLayerState.objectGroups.first { group in
                group.isExplicit && group.objectCount > 1 && group.contains(object)
            }
        }

        private func selectSavedObjectGroup(_ group: CanvasObjectGroup, on canvas: PKCanvasView) {
            clearSingleObjectSelection()
            clearLastSingleObjectSelection()
            activeRegionSelection = nil
            activeRegionSourcePoints = []
            activeRegionOverlayPoints = []
            activeRegionSelectedStrokeIndexes = []
            activeRegionSelectedTextObjectIDs = group.textObjectIDs.filter { id in
                parent.textObjects.contains { $0.id == id }
            }
            activeRegionSelectedImageObjectIDs = group.imageObjectIDs.filter { id in
                parent.imageObjects.contains { $0.id == id }
            }
            activeRegionSelectedGeometryObjectIDs = group.geometryObjectIDs.filter { id in
                parent.geometryObjects.contains { $0.id == id }
            }
            guard activeObjectRegionSelectionCount > 1 else {
                clearRegionSelection()
                updateSharedSelectionState()
                return
            }
            updateRegionSelectionHighlight(on: canvas)
            updateHostTextObjects(using: canvas)
            updateHostImageObjects(using: canvas)
            updateHostGeometryObjects(using: canvas)
        }

        private func clearObjectRegionTargets() {
            activeRegionSelectedTextObjectIDs = []
            activeRegionSelectedImageObjectIDs = []
            activeRegionSelectedGeometryObjectIDs = []
            activeRegionSelectedStrokeIndexes = []
            hostView?.regionSelectionOverlayView.updateSelectedRects([])
        }

        private func updateActiveRegionSelection() {
            switch activeRegionSelectionMode {
            case .tap:
                activeRegionSelection = nil
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
                activeRegionSelectedGeometryObjectIDs = []
                activeRegionSelectedStrokeIndexes = []
                hostView?.regionSelectionOverlayView.updateSelectedRects([])
                return
            }

            activeRegionSelectedTextObjectIDs = Set(parent.textObjects.compactMap { object in
                !object.text.isEmpty && activeRegionSelection.intersects(object.frame) ? object.id : nil
            })
            activeRegionSelectedImageObjectIDs = Set(parent.imageObjects.compactMap { object in
                object.isLocked == true ? nil : (activeRegionSelection.intersects(object.renderedBounds) ? object.id : nil)
            })
            activeRegionSelectedGeometryObjectIDs = Set(parent.geometryObjects.compactMap { object in
                object.isLocked == true ? nil : (activeRegionSelection.intersects(object.renderedBounds) ? object.id : nil)
            })
            activeRegionSelectedStrokeIndexes = []
            updateRegionSelectionHighlight(on: canvas)
            updateSharedSelectionState()
        }

        private func updateRegionSelectionHighlight(on canvas: PKCanvasView) {
            hostView?.regionSelectionOverlayView.updateSelectedRects(selectedObjectRegionScreenRects(on: canvas))
            updateSharedSelectionState()
        }

        private func hitTextResizeHandleID(at canvasPoint: CGPoint, on canvas: PKCanvasView) -> UUID? {
            guard let hit = textHandleHit(at: canvasPoint, on: canvas), hit.kind == .resize else {
                return nil
            }
            return hit.id
        }

        private func textHandleHit(at canvasPoint: CGPoint, on canvas: PKCanvasView) -> (id: UUID, kind: TextHandleKind)? {
            guard let selectedID = selectedTextObjectIDFromSharedState ?? selectedTextObjectID ?? lastSelectedTextObjectID,
                  let object = parent.textObjects.first(where: { $0.id == selectedID }),
                  !object.text.isEmpty else {
                return nil
            }
            let touchCandidates = [
                canvasPoint,
                CGPoint(
                    x: canvasPoint.x - canvas.contentOffset.x,
                    y: canvasPoint.y - canvas.contentOffset.y
                ),
                hostPoint(forCanvasPoint: canvasPoint, on: canvas)
            ]
            let zoom = max(canvas.zoomScale, 0.001)
            let sourceTouchCandidates = touchCandidates.map { point in
                CGPoint(
                    x: (point.x + canvas.contentOffset.x) / zoom - PencilKitCanvasGeometry.drawingOriginOffset.x,
                    y: (point.y + canvas.contentOffset.y) / zoom - PencilKitCanvasGeometry.drawingOriginOffset.y
                )
            } + [
                sourcePoint(forCanvasPoint: canvasPoint, on: canvas)
            ]
            let radius: CGFloat = 44
            let sourceRadius = radius / zoom
            let frame = object.frame.insetBy(dx: -6 / zoom, dy: -6 / zoom)
            let topCenterSource = textRotatedSourcePoint(CGPoint(x: frame.midX, y: frame.minY), object: object)
            let resizeSource = textRotatedSourcePoint(CGPoint(x: frame.maxX, y: frame.maxY), object: object)
            let up = CGPoint(x: sin(object.rotation), y: -cos(object.rotation))
            let knobSource = CGPoint(
                x: topCenterSource.x + up.x * (30 / zoom),
                y: topCenterSource.y + up.y * (30 / zoom)
            )
            let topCenterScreen = screenPoint(for: topCenterSource, on: canvas)
            let knobScreen = CGPoint(
                x: topCenterScreen.x + up.x * 30,
                y: topCenterScreen.y + up.y * 30
            )
            let resizeScreen = screenPoint(for: resizeSource, on: canvas)

            func distance(to point: CGPoint) -> CGFloat {
                touchCandidates.map { hypot($0.x - point.x, $0.y - point.y) }.min() ?? .greatestFiniteMagnitude
            }

            func sourceDistance(to point: CGPoint) -> CGFloat {
                sourceTouchCandidates.map { hypot($0.x - point.x, $0.y - point.y) }.min() ?? .greatestFiniteMagnitude
            }

            func normalizedDistance(screen: CGPoint, source: CGPoint) -> CGFloat {
                min(distance(to: screen), sourceDistance(to: source) * zoom)
            }

            let rotateDistance = normalizedDistance(screen: knobScreen, source: knobSource)
            let resizeDistance = normalizedDistance(screen: resizeScreen, source: resizeSource)
            if min(rotateDistance, resizeDistance) > radius {
                return nil
            }
            return rotateDistance <= resizeDistance ? (object.id, .rotate) : (object.id, .resize)
        }

        private func hitSelectedTextObjectID(at canvasPoint: CGPoint, on canvas: PKCanvasView) -> UUID? {
            guard let selectedTextObjectID = selectedTextObjectID ?? selectedTextObjectIDFromSharedState,
                  let object = parent.textObjects.first(where: { $0.id == selectedTextObjectID }),
                  !object.text.isEmpty else {
                return nil
            }

            let sourcePoint = sourcePoint(forCanvasPoint: canvasPoint, on: canvas)
            let hitMargin = selectedObjectDragHitMargin(on: canvas)
            let localPoint = textLocalPoint(sourcePoint, object: object)
            return object.frame.insetBy(dx: -hitMargin, dy: -hitMargin).contains(localPoint) ? object.id : nil
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
                let localPoint = textLocalPoint(sourcePoint, object: object)
                return !object.text.isEmpty && object.frame.insetBy(dx: -hitMargin, dy: -hitMargin).contains(localPoint)
            }?.id
        }

        private func hitSelectedImageObjectID(at canvasPoint: CGPoint, on canvas: PKCanvasView) -> UUID? {
            guard let selectedImageObjectID = selectedImageObjectID ?? selectedImageObjectIDFromSharedState,
                  let object = parent.imageObjects.first(where: { $0.id == selectedImageObjectID }),
                  object.isLocked != true else {
                return nil
            }

            let sourcePoint = sourcePoint(forCanvasPoint: canvasPoint, on: canvas)
            let hitMargin = selectedObjectDragHitMargin(on: canvas)
            let localPoint = imageLocalPoint(sourcePoint, object: object)
            return object.frame.insetBy(dx: -hitMargin, dy: -hitMargin).contains(localPoint) ? object.id : nil
        }

        private var selectedImageObjectIDFromSharedState: UUID? {
            guard case .image(let id) = parent.selectionState.selectedObject else {
                return nil
            }
            return id
        }

        private func selectedObjectDragHitMargin(on canvas: PKCanvasView) -> CGFloat {
            max(72 / max(canvas.zoomScale, 0.001), 24)
        }

        private func signedGeometryDimension(_ value: CGFloat, minimumMagnitude: CGFloat = 6) -> CGFloat {
            if value < 0 {
                return min(value, -minimumMagnitude)
            }
            return max(value, minimumMagnitude)
        }

        private func hitImageResizeHandleID(at canvasPoint: CGPoint, on canvas: PKCanvasView) -> UUID? {
            guard let hit = imageHandleHit(at: canvasPoint, on: canvas), hit.kind == .resize else {
                return nil
            }
            return hit.id
        }

        private func imageHandleHit(at canvasPoint: CGPoint, on canvas: PKCanvasView) -> (id: UUID, kind: ImageHandleKind)? {
            guard let selectedID = selectedImageObjectIDFromSharedState ?? selectedImageObjectID ?? lastSelectedImageObjectID,
                  let object = parent.imageObjects.first(where: { $0.id == selectedID }),
                  object.isLocked != true else {
                return nil
            }

            let touchCandidates = [
                canvasPoint,
                CGPoint(x: canvasPoint.x - canvas.contentOffset.x, y: canvasPoint.y - canvas.contentOffset.y),
                hostPoint(forCanvasPoint: canvasPoint, on: canvas)
            ]
            let zoom = max(canvas.zoomScale, 0.001)
            let sourceTouchCandidates = touchCandidates.map { point in
                CGPoint(
                    x: (point.x + canvas.contentOffset.x) / zoom - PencilKitCanvasGeometry.drawingOriginOffset.x,
                    y: (point.y + canvas.contentOffset.y) / zoom - PencilKitCanvasGeometry.drawingOriginOffset.y
                )
            } + [
                sourcePoint(forCanvasPoint: canvasPoint, on: canvas)
            ]
            let radius: CGFloat = 44
            let sourceRadius = radius / zoom

            func distance(to point: CGPoint) -> CGFloat {
                touchCandidates
                    .map { hypot($0.x - point.x, $0.y - point.y) }
                    .min() ?? .greatestFiniteMagnitude
            }

            func sourceDistance(to point: CGPoint) -> CGFloat {
                sourceTouchCandidates
                    .map { hypot($0.x - point.x, $0.y - point.y) }
                    .min() ?? .greatestFiniteMagnitude
            }

            func hits(screen screenPoint: CGPoint, source sourcePoint: CGPoint) -> Bool {
                distance(to: screenPoint) <= radius || sourceDistance(to: sourcePoint) <= sourceRadius
            }

            let topCenterSource = imageRotatedSourcePoint(
                CGPoint(x: object.frame.midX, y: object.frame.minY),
                object: object
            )
            let topCenter = screenPoint(for: topCenterSource, on: canvas)
            let up = CGPoint(x: sin(object.rotation), y: -cos(object.rotation))
            let sourceStem = Self.geometryRotationStemLength / zoom
            let knobSource = CGPoint(
                x: topCenterSource.x + up.x * sourceStem,
                y: topCenterSource.y + up.y * sourceStem
            )
            let knob = CGPoint(
                x: topCenter.x + up.x * Self.geometryRotationStemLength,
                y: topCenter.y + up.y * Self.geometryRotationStemLength
            )
            let resizeSource = imageRotatedSourcePoint(
                CGPoint(x: object.frame.maxX, y: object.frame.maxY),
                object: object
            )
            let resize = screenPoint(for: resizeSource, on: canvas)

            let rotateDistance = min(distance(to: knob), sourceDistance(to: knobSource) * zoom)
            let resizeDistance = min(distance(to: resize), sourceDistance(to: resizeSource) * zoom)
            if rotateDistance <= resizeDistance, hits(screen: knob, source: knobSource) {
                return (object.id, .rotate)
            }
            if hits(screen: resize, source: resizeSource) {
                return (object.id, .resize)
            }
            return nil
        }

        private func hitImageObjectID(at canvasPoint: CGPoint, on canvas: PKCanvasView) -> UUID? {
            let sourcePoint = sourcePoint(forCanvasPoint: canvasPoint, on: canvas)
            let hitMargin = max(16 / max(canvas.zoomScale, 0.001), 4)
            return parent.imageObjects.reversed().first { object in
                guard object.isLocked != true else { return false }
                let localPoint = imageLocalPoint(sourcePoint, object: object)
                return object.frame.insetBy(dx: -hitMargin, dy: -hitMargin).contains(localPoint)
            }?.id
        }

        private func hitAnyImageObjectID(at canvasPoint: CGPoint, on canvas: PKCanvasView) -> UUID? {
            let sourcePoint = sourcePoint(forCanvasPoint: canvasPoint, on: canvas)
            let hitMargin = max(16 / max(canvas.zoomScale, 0.001), 4)
            return parent.imageObjects.reversed().first { object in
                let localPoint = imageLocalPoint(sourcePoint, object: object)
                return object.frame.insetBy(dx: -hitMargin, dy: -hitMargin).contains(localPoint)
            }?.id
        }

        private func topObjectHit(
            at canvasPoint: CGPoint,
            on canvas: PKCanvasView,
            includeLockedImages: Bool
        ) -> CanvasSelectionState.Object? {
            let imageID = includeLockedImages
                ? hitAnyImageObjectID(at: canvasPoint, on: canvas)
                : hitImageObjectID(at: canvasPoint, on: canvas)
            let geometryID = hitGeometryObjectID(at: canvasPoint, on: canvas)
            let textID = hitTextObjectID(at: canvasPoint, on: canvas)

            switch parent.objectLayerState.imageLayerPosition {
            case .aboveText:
                if let imageID { return .image(imageID) }
                if let textID { return .text(textID) }
                if let geometryID { return .geometry(geometryID) }
            case .betweenGeometryAndText:
                if let textID { return .text(textID) }
                if let imageID { return .image(imageID) }
                if let geometryID { return .geometry(geometryID) }
            case .belowGeometry:
                if let textID { return .text(textID) }
                if let geometryID { return .geometry(geometryID) }
                if let imageID { return .image(imageID) }
            }

            return nil
        }

        private var selectedGeometryObjectIDFromSharedState: UUID? {
            guard case .geometry(let id) = parent.selectionState.selectedObject else { return nil }
            return id
        }

        private func geometryHitFrame(_ object: CanvasGeometryObject) -> CGRect {
            if object.shape == .line {
                let lineBounds = CGRect(
                    x: min(object.x, object.x + object.width),
                    y: min(object.y, object.y + object.height),
                    width: abs(object.width),
                    height: abs(object.height)
                )
                return lineBounds.insetBy(dx: -max(object.strokeWidth, 6), dy: -max(object.strokeWidth, 6))
            }
            let normalized = object.renderedBounds
            if normalized.width < 1 || normalized.height < 1 {
                return normalized.insetBy(dx: -6, dy: -6)
            }
            return normalized
        }

        // MARK: Geometry handle hit-testing (pure source space, like text resize)

        private static let geometryHandleHitRadius: CGFloat = 44
        private static let geometryRotationStemLength: CGFloat = 30

        private func rotateSourcePoint(_ point: CGPoint, about pivot: CGPoint, by rotation: CGFloat) -> CGPoint {
            let dx = point.x - pivot.x
            let dy = point.y - pivot.y
            let cosR = cos(rotation)
            let sinR = sin(rotation)
            return CGPoint(x: pivot.x + dx * cosR - dy * sinR, y: pivot.y + dx * sinR + dy * cosR)
        }

        private func rotateSourceVector(_ vector: CGVector, by rotation: CGFloat) -> CGVector {
            let cosR = cos(rotation)
            let sinR = sin(rotation)
            return CGVector(
                dx: vector.dx * cosR - vector.dy * sinR,
                dy: vector.dx * sinR + vector.dy * cosR
            )
        }

        private func anchoredResizeSize(from anchorSource: CGPoint, to handleSource: CGPoint, rotation: CGFloat) -> CGSize {
            let sourceDelta = CGVector(
                dx: handleSource.x - anchorSource.x,
                dy: handleSource.y - anchorSource.y
            )
            let localDelta = rotateSourceVector(sourceDelta, by: -rotation)
            return CGSize(width: localDelta.dx, height: localDelta.dy)
        }

        private func anchoredResizeOrigin(anchorSource: CGPoint, size: CGSize, rotation: CGFloat) -> CGPoint {
            let localSize = CGVector(dx: size.width, dy: size.height)
            let rotatedSize = rotateSourceVector(localSize, by: rotation)
            return CGPoint(
                x: anchorSource.x - localSize.dx / 2 + rotatedSize.dx / 2,
                y: anchorSource.y - localSize.dy / 2 + rotatedSize.dy / 2
            )
        }

        private func originPreservingRenderedPosition(
            origin: CGPoint,
            oldPivot: CGPoint,
            newPivot: CGPoint,
            rotation: CGFloat
        ) -> CGPoint {
            let renderedOrigin = rotateSourcePoint(origin, about: oldPivot, by: rotation)
            return rotateSourcePoint(renderedOrigin, about: newPivot, by: -rotation)
        }

        /// Un-rotates a source point into the object's local (unrotated) space so
        /// a rotated object can be hit-tested against its axis-aligned frame.
        private func geometryLocalPoint(_ source: CGPoint, object: CanvasGeometryObject) -> CGPoint {
            rotateSourcePoint(source, about: object.pivot, by: -object.rotation)
        }

        private func geometryLocalPoint(_ source: CGPoint, pivot: CGPoint, rotation: CGFloat) -> CGPoint {
            rotateSourcePoint(source, about: pivot, by: -rotation)
        }

        private func imageRotatedSourcePoint(_ point: CGPoint, object: CanvasImageObject) -> CGPoint {
            rotateSourcePoint(point, about: object.center, by: object.rotation)
        }

        private func imageLocalPoint(_ source: CGPoint, object: CanvasImageObject) -> CGPoint {
            rotateSourcePoint(source, about: object.center, by: -object.rotation)
        }

        private func textRotatedSourcePoint(_ point: CGPoint, object: CanvasTextObject) -> CGPoint {
            rotateSourcePoint(point, about: object.center, by: object.rotation)
        }

        private func textLocalPoint(_ source: CGPoint, object: CanvasTextObject) -> CGPoint {
            rotateSourcePoint(source, about: object.center, by: -object.rotation)
        }

        private func groupTransformHit(at canvasPoint: CGPoint, on canvas: PKCanvasView) -> GroupTransformKind? {
            guard activeObjectRegionSelectionCount > 1,
                  let groupRect = selectedObjectGroupScreenRect(on: canvas) else { return nil }
            let pointCandidates = [
                canvasPoint,
                CGPoint(
                    x: canvasPoint.x - canvas.contentOffset.x,
                    y: canvasPoint.y - canvas.contentOffset.y
                ),
                hostPoint(forCanvasPoint: canvasPoint, on: canvas)
            ]
            let handleRadius: CGFloat = 28
            let resizePoint = CGPoint(x: groupRect.maxX, y: groupRect.maxY)
            if pointCandidates.contains(where: { hypot($0.x - resizePoint.x, $0.y - resizePoint.y) <= handleRadius }) {
                return .resize
            }
            let rotatePoint = CGPoint(x: groupRect.midX, y: groupRect.minY - 34)
            if pointCandidates.contains(where: { hypot($0.x - rotatePoint.x, $0.y - rotatePoint.y) <= handleRadius }) {
                return .rotate
            }
            if pointCandidates.contains(where: { groupRect.insetBy(dx: -12, dy: -12).contains($0) }) {
                return .move
            }
            return nil
        }

        private func selectedObjectGroupScreenRect(on canvas: PKCanvasView) -> CGRect? {
            let rects = selectedObjectRegionScreenRects(on: canvas)
            guard rects.count > 1 else { return nil }
            return rects.dropFirst().reduce(rects[0]) { $0.union($1) }.insetBy(dx: -10, dy: -10)
        }

        enum GeometryHandleKind {
            case rotate
            case pivot
            case apex
            case resize
        }

        enum ImageHandleKind {
            case rotate
            case resize
        }

        enum TextHandleKind {
            case rotate
            case resize
        }

        enum GroupTransformKind {
            case move
            case resize
            case rotate
        }

        private func hostPoint(forCanvasPoint canvasPoint: CGPoint, on canvas: PKCanvasView) -> CGPoint {
            if let hostView {
                return canvas.convert(canvasPoint, to: hostView)
            }
            return CGPoint(
                x: canvasPoint.x - canvas.contentOffset.x,
                y: canvasPoint.y - canvas.contentOffset.y
            )
        }

        private func screenPoint(for sourcePoint: CGPoint, on canvas: PKCanvasView) -> CGPoint {
            let zoom = max(canvas.zoomScale, 0.001)
            return CGPoint(
                x: (PencilKitCanvasGeometry.drawingOriginOffset.x + sourcePoint.x) * zoom - canvas.contentOffset.x,
                y: (PencilKitCanvasGeometry.drawingOriginOffset.y + sourcePoint.y) * zoom - canvas.contentOffset.y
            )
        }

        private func rotatedGeometryScreenPoint(
            _ point: CGPoint,
            object: CanvasGeometryObject,
            on canvas: PKCanvasView
        ) -> CGPoint {
            screenPoint(for: rotateSourcePoint(point, about: object.pivot, by: object.rotation), on: canvas)
        }

        /// Hit test for the selected geometry object's handles in the same
        /// screen-space coordinates used by `CanvasGeometryObjectsView.draw`.
        private func geometryHandleHit(at canvasPoint: CGPoint, on canvas: PKCanvasView) -> (id: UUID, kind: GeometryHandleKind)? {
            guard let selectedID = selectedGeometryObjectIDFromSharedState ?? selectedGeometryObjectID ?? lastSelectedGeometryObjectID,
                  let object = parent.geometryObjects.first(where: { $0.id == selectedID }),
                  object.isLocked != true else {
                return nil
            }
            let touchCandidates = [
                canvasPoint,
                CGPoint(
                    x: canvasPoint.x - canvas.contentOffset.x,
                    y: canvasPoint.y - canvas.contentOffset.y
                ),
                hostPoint(forCanvasPoint: canvasPoint, on: canvas)
            ]
            let zoom = max(canvas.zoomScale, 0.001)
            let sourceTouchCandidates = touchCandidates.map { point in
                CGPoint(
                    x: (point.x + canvas.contentOffset.x) / zoom - PencilKitCanvasGeometry.drawingOriginOffset.x,
                    y: (point.y + canvas.contentOffset.y) / zoom - PencilKitCanvasGeometry.drawingOriginOffset.y
                )
            } + [
                sourcePoint(forCanvasPoint: canvasPoint, on: canvas)
            ]
            let radius = Self.geometryHandleHitRadius
            let sourceRadius = radius / zoom
            let renderedBounds = object.renderedBounds

            func distance(to point: CGPoint) -> CGFloat {
                touchCandidates
                    .map { hypot($0.x - point.x, $0.y - point.y) }
                    .min() ?? .greatestFiniteMagnitude
            }

            func sourceDistance(to point: CGPoint) -> CGFloat {
                sourceTouchCandidates
                    .map { hypot($0.x - point.x, $0.y - point.y) }
                    .min() ?? .greatestFiniteMagnitude
            }

            func hits(screen screenPoint: CGPoint, source sourcePoint: CGPoint) -> Bool {
                distance(to: screenPoint) <= radius || sourceDistance(to: sourcePoint) <= sourceRadius
            }

            let topCenterSource = rotateSourcePoint(
                CGPoint(x: renderedBounds.midX, y: renderedBounds.minY),
                about: object.pivot,
                by: object.rotation
            )
            let topCenter = screenPoint(for: topCenterSource, on: canvas)
            let up = CGPoint(x: sin(object.rotation), y: -cos(object.rotation))
            let sourceStem = Self.geometryRotationStemLength / zoom
            let knobSource = CGPoint(
                x: topCenterSource.x + up.x * sourceStem,
                y: topCenterSource.y + up.y * sourceStem
            )
            let knob = CGPoint(
                x: topCenter.x + up.x * Self.geometryRotationStemLength,
                y: topCenter.y + up.y * Self.geometryRotationStemLength
            )

            let pivotScreen = screenPoint(for: object.pivot, on: canvas)

            let apexSource: CGPoint?
            let apexScreen: CGPoint?
            if object.shape == .triangle {
                let source = rotateSourcePoint(
                    object.triangleApexSourcePoint,
                    about: object.pivot,
                    by: object.rotation
                )
                apexSource = source
                apexScreen = screenPoint(for: source, on: canvas)
            } else {
                apexSource = nil
                apexScreen = nil
            }

            let resizeCornerSource = rotateSourcePoint(
                CGPoint(x: object.x + object.width, y: object.y + object.height),
                about: object.pivot,
                by: object.rotation
            )
            let resizeCornerScreen = screenPoint(for: resizeCornerSource, on: canvas)

            // Nearest-handle-wins. The rotation knob and the apex handle sit only
            // ~30pt apart, so a fixed priority + radius can't separate them; instead
            // pick whichever handle center the touch is closest to (within radius).
            // Distances are normalized to screen units so screen and source
            // candidates compare fairly.
            func normalizedDistance(screen screenPoint: CGPoint, source sourcePoint: CGPoint) -> CGFloat {
                min(distance(to: screenPoint), sourceDistance(to: sourcePoint) * zoom)
            }

            var best: (kind: GeometryHandleKind, distance: CGFloat)?
            func consider(_ kind: GeometryHandleKind, _ candidateDistance: CGFloat) {
                guard candidateDistance <= radius else { return }
                if best == nil || candidateDistance < best!.distance {
                    best = (kind, candidateDistance)
                }
            }

            consider(.rotate, normalizedDistance(screen: knob, source: knobSource))
            consider(.pivot, normalizedDistance(screen: pivotScreen, source: object.pivot))
            if let apexScreen, let apexSource {
                consider(.apex, normalizedDistance(screen: apexScreen, source: apexSource))
            }
            consider(.resize, normalizedDistance(screen: resizeCornerScreen, source: resizeCornerSource))

            if let best {
                return (object.id, best.kind)
            }
            return nil
        }

        private func hitSelectedGeometryObjectID(at canvasPoint: CGPoint, on canvas: PKCanvasView) -> UUID? {
            guard let selectedID = selectedGeometryObjectID ?? selectedGeometryObjectIDFromSharedState ?? lastSelectedGeometryObjectID,
                  let object = parent.geometryObjects.first(where: { $0.id == selectedID }),
                  object.isLocked != true else {
                return nil
            }
            let source = sourcePoint(forCanvasPoint: canvasPoint, on: canvas)
            let local = geometryLocalPoint(source, object: object)
            let hitMargin = selectedObjectDragHitMargin(on: canvas)
            return geometryHitFrame(object).insetBy(dx: -hitMargin, dy: -hitMargin).contains(local) ? object.id : nil
        }

        private func hitGeometryObjectID(at canvasPoint: CGPoint, on canvas: PKCanvasView) -> UUID? {
            let source = sourcePoint(forCanvasPoint: canvasPoint, on: canvas)
            let hitMargin = max(16 / max(canvas.zoomScale, 0.001), 8)
            return parent.geometryObjects.reversed().first { object in
                guard object.isLocked != true else { return false }
                let local = geometryLocalPoint(source, object: object)
                return geometryHitFrame(object).insetBy(dx: -hitMargin, dy: -hitMargin).contains(local)
            }?.id
        }

        private func setSelectedTextObjectID(_ id: UUID?) {
            guard selectedTextObjectID != id
                    || selectedImageObjectID != nil
                    || selectedGeometryObjectID != nil
                    || parent.selectionState.selectedObject != id.map(CanvasSelectionState.Object.text) else {
                return
            }
            selectedTextObjectID = id
            selectedImageObjectID = nil
            selectedGeometryObjectID = nil
            if let id {
                lastSelectedTextObjectID = id
            }
            updateSharedSelectionState()
        }

        private func clearSingleObjectSelection() {
            selectedTextObjectID = nil
            selectedImageObjectID = nil
            selectedGeometryObjectID = nil
            parent.selectionState = CanvasSelectionState()
        }

        private func clearLastSingleObjectSelection() {
            lastSelectedTextObjectID = nil
            lastSelectedImageObjectID = nil
            lastSelectedGeometryObjectID = nil
        }

        private func setSelectedImageObjectID(_ id: UUID?) {
            guard selectedImageObjectID != id
                    || selectedTextObjectID != nil
                    || selectedGeometryObjectID != nil
                    || parent.selectionState.selectedObject != id.map(CanvasSelectionState.Object.image) else {
                return
            }
            selectedImageObjectID = id
            selectedTextObjectID = nil
            selectedGeometryObjectID = nil
            if let id {
                lastSelectedImageObjectID = id
            }
            updateSharedSelectionState()
        }

        private func setSelectedGeometryObjectID(_ id: UUID?) {
            guard selectedGeometryObjectID != id
                    || selectedTextObjectID != nil
                    || selectedImageObjectID != nil
                    || parent.selectionState.selectedObject != id.map(CanvasSelectionState.Object.geometry) else {
                return
            }
            selectedGeometryObjectID = id
            selectedTextObjectID = nil
            selectedImageObjectID = nil
            if let id {
                lastSelectedGeometryObjectID = id
            }
            updateSharedSelectionState()
        }

        private func updateSharedSelectionState() {
            if selectedTextObjectID == nil,
               selectedImageObjectID == nil,
               selectedGeometryObjectID == nil,
               let groupSelection = activeObjectGroupSelectionState() {
                parent.selectionState = groupSelection
            } else if let selectedTextObjectID,
               let object = parent.textObjects.first(where: { $0.id == selectedTextObjectID }) {
                parent.selectionState = CanvasSelectionState(
                    selectedObject: .text(object.id),
                    selectedTextObject: object,
                    viewportFrame: canvas.flatMap { screenBoundingRect(for: textSelectionScreenPoints(for: object, on: $0)) }
                )
            } else if let selectedImageObjectID,
                      let object = parent.imageObjects.first(where: { $0.id == selectedImageObjectID }) {
                let index = parent.imageObjects.firstIndex(where: { $0.id == selectedImageObjectID })
                let isLocked = object.isLocked == true
                parent.selectionState = CanvasSelectionState(
                    selectedObject: .image(object.id),
                    selectedImageObject: object,
                    selectedImageCanMoveBackward: !isLocked && canMoveSelectedImageBackward(index: index),
                    selectedImageCanMoveForward: !isLocked && canMoveSelectedImageForward(index: index),
                    viewportFrame: canvas.map { overlayRect(forSourceRect: object.renderedBounds, on: $0) }
                )
            } else if let selectedGeometryObjectID,
                      let object = parent.geometryObjects.first(where: { $0.id == selectedGeometryObjectID }) {
                parent.selectionState = CanvasSelectionState(
                    selectedObject: .geometry(object.id),
                    selectedGeometryObject: object,
                    viewportFrame: canvas.map { overlayRect(forSourceRect: object.renderedBounds, on: $0) }
                )
            } else {
                parent.selectionState = CanvasSelectionState()
            }
        }

        private func activeObjectGroupSelectionState() -> CanvasSelectionState? {
            guard let canvas else { return nil }
            let screenRects = selectedObjectRegionScreenRects(on: canvas)
            guard screenRects.count > 1 else { return nil }
            let groupScreenRect = screenRects
                .dropFirst()
                .reduce(screenRects[0]) { $0.union($1) }
            return CanvasSelectionState(
                viewportFrame: groupScreenRect,
                selectedGroupObjectCount: screenRects.count,
                selectedObjectGroupID: matchingSavedObjectGroupID()
            )
        }

        private func selectedObjectRegionScreenRects(on canvas: PKCanvasView) -> [CGRect] {
            let textRects = parent.textObjects.compactMap { object -> CGRect? in
                guard activeRegionSelectedTextObjectIDs.contains(object.id), !object.text.isEmpty else { return nil }
                return screenBoundingRect(for: textSelectionScreenPoints(for: object, on: canvas))?.insetBy(dx: -6, dy: -6)
            }
            let imageRects = parent.imageObjects.compactMap { object -> CGRect? in
                guard activeRegionSelectedImageObjectIDs.contains(object.id) else { return nil }
                return screenBoundingRect(for: imageSelectionScreenPoints(for: object, on: canvas))
            }
            let geometryRects = parent.geometryObjects.compactMap { object -> CGRect? in
                guard activeRegionSelectedGeometryObjectIDs.contains(object.id) else { return nil }
                return screenBoundingRect(for: geometrySelectionScreenPoints(for: object, on: canvas))
            }
            return textRects + imageRects + geometryRects
        }

        private func textSelectionScreenPoints(for object: CanvasTextObject, on canvas: PKCanvasView) -> [CGPoint] {
            [
                textRotatedSourcePoint(CGPoint(x: object.frame.minX, y: object.frame.minY), object: object),
                textRotatedSourcePoint(CGPoint(x: object.frame.maxX, y: object.frame.minY), object: object),
                textRotatedSourcePoint(CGPoint(x: object.frame.maxX, y: object.frame.maxY), object: object),
                textRotatedSourcePoint(CGPoint(x: object.frame.minX, y: object.frame.maxY), object: object)
            ].map { screenPoint(for: $0, on: canvas) }
        }

        private func imageSelectionScreenPoints(for object: CanvasImageObject, on canvas: PKCanvasView) -> [CGPoint] {
            [
                imageRotatedSourcePoint(CGPoint(x: object.frame.minX, y: object.frame.minY), object: object),
                imageRotatedSourcePoint(CGPoint(x: object.frame.maxX, y: object.frame.minY), object: object),
                imageRotatedSourcePoint(CGPoint(x: object.frame.maxX, y: object.frame.maxY), object: object),
                imageRotatedSourcePoint(CGPoint(x: object.frame.minX, y: object.frame.maxY), object: object)
            ].map { screenPoint(for: $0, on: canvas) }
        }

        private func geometrySelectionScreenPoints(for object: CanvasGeometryObject, on canvas: PKCanvasView) -> [CGPoint] {
            if object.shape == .line {
                let start = CGPoint(x: object.x, y: object.y)
                let end = CGPoint(x: object.x + object.width, y: object.y + object.height)
                return [
                    rotatedGeometryScreenPoint(start, object: object, on: canvas),
                    rotatedGeometryScreenPoint(end, object: object, on: canvas)
                ]
            }

            let bounds = object.renderedBounds
            return [
                CGPoint(x: bounds.minX, y: bounds.minY),
                CGPoint(x: bounds.maxX, y: bounds.minY),
                CGPoint(x: bounds.maxX, y: bounds.maxY),
                CGPoint(x: bounds.minX, y: bounds.maxY)
            ].map { rotatedGeometryScreenPoint($0, object: object, on: canvas) }
        }

        private func screenBoundingRect(for points: [CGPoint]) -> CGRect? {
            guard let first = points.first else { return nil }
            var minX = first.x
            var maxX = first.x
            var minY = first.y
            var maxY = first.y
            for point in points.dropFirst() {
                minX = min(minX, point.x)
                maxX = max(maxX, point.x)
                minY = min(minY, point.y)
                maxY = max(maxY, point.y)
            }
            return CGRect(x: minX, y: minY, width: max(maxX - minX, 1), height: max(maxY - minY, 1))
                .insetBy(dx: -6, dy: -6)
        }

        private func canMoveSelectedImageBackward(index: Int?) -> Bool {
            guard let index else { return false }
            return index > 0 || parent.objectLayerState.imageLayerPosition != .belowGeometry
        }

        private func canMoveSelectedImageForward(index: Int?) -> Bool {
            guard let index else { return false }
            return index < parent.imageObjects.index(before: parent.imageObjects.endIndex)
                || parent.objectLayerState.imageLayerPosition != .aboveText
        }

        private func clearObjectSelection(using canvas: PKCanvasView) {
            finishTextEditing()
            selectedTextObjectID = nil
            selectedImageObjectID = nil
            selectedGeometryObjectID = nil
            lastSelectedTextObjectID = nil
            lastSelectedImageObjectID = nil
            lastSelectedGeometryObjectID = nil
            clearObjectDragState()
            clearRegionSelection()
            updateSharedSelectionState()
            updateHostTextObjects(using: canvas)
            updateHostImageObjects(using: canvas)
            updateHostGeometryObjects(using: canvas)
            publishImageFromModel()
        }

        private func groupSelectedObjects(using canvas: PKCanvasView) {
            guard let activeGroup = activeObjectGroup() else { return }
            if matchingSavedObjectGroupID() != nil { return }
            parent.onInteractionBegan?()
            var layerState = parent.objectLayerState
            layerState.objectGroups.removeAll { group in
                !group.textObjectIDs.isDisjoint(with: activeGroup.textObjectIDs)
                    || !group.imageObjectIDs.isDisjoint(with: activeGroup.imageObjectIDs)
                    || !group.geometryObjectIDs.isDisjoint(with: activeGroup.geometryObjectIDs)
            }
            layerState.objectGroups.append(CanvasObjectGroup(
                id: activeGroup.id,
                textObjectIDs: activeGroup.textObjectIDs,
                imageObjectIDs: activeGroup.imageObjectIDs,
                geometryObjectIDs: activeGroup.geometryObjectIDs,
                isExplicit: true
            ))
            parent.objectLayerState = layerState
            updateRegionSelectionHighlight(on: canvas)
        }

        private func ungroupSelectedObjects(using canvas: PKCanvasView) {
            guard activeObjectRegionSelectionCount > 1 else { return }
            let savedGroupID = matchingSavedObjectGroupID()
            guard let savedGroupID else { return }
            parent.onInteractionBegan?()
            var layerState = parent.objectLayerState
            layerState.objectGroups.removeAll { $0.id == savedGroupID }
            parent.objectLayerState = layerState
            updateRegionSelectionHighlight(on: canvas)
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
            if let targetID = selectedGeometryObjectID {
                duplicateGeometryObject(targetID, using: canvas)
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
                fontName: object.fontName,
                rotation: object.rotation
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
            if let targetID = selectedGeometryObjectID {
                deleteGeometryObject(targetID, using: canvas)
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
                height: object.height,
                rotation: object.rotation,
                isLocked: object.isLocked
            )
            parent.imageObjects.append(duplicate)
            setSelectedImageObjectID(duplicate.id)
            updateHostImageObjects(using: canvas)
            publishImageFromModel()
        }

        private func deleteImageObject(_ id: UUID, using canvas: PKCanvasView) {
            guard let object = parent.imageObjects.first(where: { $0.id == id }),
                  object.isLocked != true else { return }
            parent.onInteractionBegan?()
            parent.imageObjects.removeAll { $0.id == id }
            setSelectedImageObjectID(nil)
            lastSelectedImageObjectID = nil
            movingImageObjectID = nil
            resizingImageObjectID = nil
            rotatingImageObjectID = nil
            updateHostImageObjects(using: canvas)
            publishImageFromModel()
        }

        private func reorderImageObject(
            _ id: UUID,
            action: CanvasObjectCommand.ImageLayerAction,
            using canvas: PKCanvasView
        ) {
            guard let currentIndex = parent.imageObjects.firstIndex(where: { $0.id == id }),
                  parent.imageObjects[currentIndex].isLocked != true else { return }
            let lastIndex = parent.imageObjects.index(before: parent.imageObjects.endIndex)
            var targetIndex = currentIndex
            var layerState = parent.objectLayerState
            switch action {
            case .bringForward:
                if currentIndex < lastIndex {
                    targetIndex = currentIndex + 1
                } else {
                    layerState.imageLayerPosition = layerState.imageLayerPosition.raised
                }
            case .sendBackward:
                if currentIndex > 0 {
                    targetIndex = currentIndex - 1
                } else {
                    layerState.imageLayerPosition = layerState.imageLayerPosition.lowered
                }
            case .bringToFront:
                layerState.imageLayerPosition = .aboveText
                targetIndex = lastIndex
            case .sendToBack:
                layerState.imageLayerPosition = .belowGeometry
                targetIndex = 0
            }
            guard targetIndex != currentIndex || layerState != parent.objectLayerState else { return }

            parent.onInteractionBegan?()
            if targetIndex != currentIndex {
                var imageObjects = parent.imageObjects
                let object = imageObjects.remove(at: currentIndex)
                imageObjects.insert(object, at: targetIndex)
                parent.imageObjects = imageObjects
            }
            parent.objectLayerState = layerState
            setSelectedImageObjectID(id)
            updateSharedSelectionState()
            updateHostImageObjects(using: canvas)
            hostView?.updateObjectLayerState(layerState)
            publishImageFromModel()
        }

        private func setImageObjectLocked(_ id: UUID, isLocked: Bool, using canvas: PKCanvasView) {
            guard let index = parent.imageObjects.firstIndex(where: { $0.id == id }) else { return }
            parent.onInteractionBegan?()
            var imageObjects = parent.imageObjects
            imageObjects[index].isLocked = isLocked ? true : nil
            parent.imageObjects = imageObjects
            setSelectedImageObjectID(id)
            clearObjectDragState()
            updateSharedSelectionState()
            updateHostImageObjects(using: canvas)
            publishImageFromModel()
        }

        private func duplicateGeometryObject(_ id: UUID, using canvas: PKCanvasView) {
            guard let object = parent.geometryObjects.first(where: { $0.id == id }) else { return }
            parent.onInteractionBegan?()
            let offset = max(24 / max(canvas.zoomScale, 0.001), 12)
            let duplicate = CanvasGeometryObject(
                shape: object.shape,
                x: object.x + offset,
                y: object.y + offset,
                width: object.width,
                height: object.height,
                strokeRed: object.strokeRed,
                strokeGreen: object.strokeGreen,
                strokeBlue: object.strokeBlue,
                strokeAlpha: object.strokeAlpha,
                strokeWidth: object.strokeWidth,
                fillRed: object.fillRed,
                fillGreen: object.fillGreen,
                fillBlue: object.fillBlue,
                fillOpacity: object.fillOpacity,
                polygonSides: object.polygonSides,
                arrow: object.arrow,
                apexOffset: object.apexOffset,
                rotation: object.rotation,
                pivotX: object.pivotX.map { $0 + offset },
                pivotY: object.pivotY.map { $0 + offset },
                isLocked: object.isLocked
            )
            var geometryObjects = parent.geometryObjects
            geometryObjects.append(duplicate)
            parent.geometryObjects = geometryObjects
            setSelectedGeometryObjectID(duplicate.id)
            updateHostGeometryObjects(using: canvas)
            publishImageFromModel()
        }

        private func updateGeometryObject(_ update: CanvasGeometryUpdate, using canvas: PKCanvasView) {
            guard let index = parent.geometryObjects.firstIndex(where: { $0.id == update.id }) else { return }
            var geometryObjects = parent.geometryObjects
            geometryObjects[index].shape = update.shape
            geometryObjects[index].strokeRed = update.strokeColor.red
            geometryObjects[index].strokeGreen = update.strokeColor.green
            geometryObjects[index].strokeBlue = update.strokeColor.blue
            geometryObjects[index].strokeAlpha = update.strokeColor.alpha
            geometryObjects[index].strokeWidth = update.strokeWidth
            geometryObjects[index].fillRed = update.fillColor.red
            geometryObjects[index].fillGreen = update.fillColor.green
            geometryObjects[index].fillBlue = update.fillColor.blue
            geometryObjects[index].fillOpacity = update.fillOpacity
            geometryObjects[index].polygonSides = update.polygonSides
            geometryObjects[index].arrow = update.arrow
            parent.geometryObjects = geometryObjects
            if selectedGeometryObjectID == update.id {
                updateSharedSelectionState()
            }
            updateHostGeometryObjects(using: canvas)
            publishImageFromModel()
        }

        private func deleteGeometryObject(_ id: UUID, using canvas: PKCanvasView) {
            guard parent.geometryObjects.contains(where: { $0.id == id }) else { return }
            parent.onInteractionBegan?()
            parent.geometryObjects.removeAll { $0.id == id }
            setSelectedGeometryObjectID(nil)
            lastSelectedGeometryObjectID = nil
            clearObjectDragState()
            updateHostGeometryObjects(using: canvas)
            publishImageFromModel()
        }

        private func copySelectedRegionToPasteboard(using canvas: PKCanvasView) {
            guard let snapshot = makeRegionSnapshot() else { return }
            let payload = CanvasExtractedImageClipboardPayload(
                pngData: snapshot.pngData,
                sourceBounds: snapshot.sourceBounds
            )
            if let data = try? JSONEncoder().encode(payload) {
                UIPasteboard.general.items = [[
                    Self.extractedImagePasteboardType: data,
                    "public.png": snapshot.pngData
                ]]
            }
        }

        private static let semanticObjectPasteboardType = "com.mathboard.canvas.semantic-object"
        private static let extractedImagePasteboardType = "com.mathboard.canvas.extracted-image"

        private struct CanvasExtractedImageClipboardPayload: Codable {
            var pngData: Data
            var sourceBounds: CGRect
        }

        private func copySelectedSemanticObjectToPasteboard(using canvas: PKCanvasView) {
            finishTextEditing()
            if let targetID = selectedGeometryObjectID ?? lastSelectedGeometryObjectID {
                copySemanticObject(.geometry(targetID), using: canvas)
                return
            }
            if let targetID = selectedImageObjectID ?? lastSelectedImageObjectID {
                copySemanticObject(.image(targetID), using: canvas)
                return
            }
            if let targetID = selectedTextObjectID ?? lastSelectedTextObjectID {
                copySemanticObject(.text(targetID), using: canvas)
                return
            }
        }

        private func copySemanticObject(_ object: CanvasSelectionState.Object, using canvas: PKCanvasView) {
            switch object {
            case .text(let id):
                guard let textObject = parent.textObjects.first(where: { $0.id == id }) else { return }
                writeSemanticObjectToPasteboard(.text(textObject))
            case .geometry(let id):
                guard let geometryObject = parent.geometryObjects.first(where: { $0.id == id }) else { return }
                writeSemanticObjectToPasteboard(.geometry(geometryObject))
            case .image(let id):
                guard let imageObject = parent.imageObjects.first(where: { $0.id == id }) else { return }
                let imageURL = CanvasImageObject.assetDirectoryURL(forDrawingURL: parent.drawingURL)
                    .appendingPathComponent(imageObject.imageFileName)
                guard let data = try? Data(contentsOf: imageURL) else { return }
                writeSemanticObjectToPasteboard(.image(imageObject, data), imageData: data)
            }
        }

        private func writeSemanticObjectToPasteboard(_ payload: CanvasSemanticClipboardPayload, imageData: Data? = nil) {
            guard let data = try? JSONEncoder().encode(payload) else { return }
            if let imageData {
                UIPasteboard.general.items = [[
                    Self.semanticObjectPasteboardType: data,
                    "public.png": imageData
                ]]
            } else {
                UIPasteboard.general.setData(data, forPasteboardType: Self.semanticObjectPasteboardType)
            }
        }

        private func semanticObjectPayloadFromPasteboard() -> CanvasSemanticClipboardPayload? {
            guard let data = UIPasteboard.general.data(forPasteboardType: Self.semanticObjectPasteboardType) else {
                return nil
            }
            return try? JSONDecoder().decode(CanvasSemanticClipboardPayload.self, from: data)
        }

        private func extractedImagePayloadFromPasteboard() -> CanvasExtractedImageClipboardPayload? {
            if let data = UIPasteboard.general.data(forPasteboardType: Self.extractedImagePasteboardType),
               let payload = try? JSONDecoder().decode(CanvasExtractedImageClipboardPayload.self, from: data) {
                return payload
            }
            guard let image = UIPasteboard.general.image,
                  let pngData = image.pngData() else {
                return nil
            }
            return CanvasExtractedImageClipboardPayload(
                pngData: pngData,
                sourceBounds: CGRect(origin: .zero, size: image.size)
            )
        }

        private func canPasteClipboardObject() -> Bool {
            semanticObjectPayloadFromPasteboard() != nil || extractedImagePayloadFromPasteboard() != nil
        }

        private func pasteClipboardObjectFromPasteboard(using canvas: PKCanvasView, at sourcePoint: CGPoint? = nil) {
            if semanticObjectPayloadFromPasteboard() != nil {
                pasteSemanticObjectFromPasteboard(using: canvas, at: sourcePoint)
            } else {
                pasteExtractedImageFromPasteboard(using: canvas, at: sourcePoint)
            }
        }

        private func pasteSemanticObjectFromPasteboard(using canvas: PKCanvasView, at sourcePoint: CGPoint? = nil) {
            guard let payload = semanticObjectPayloadFromPasteboard() else { return }
            parent.onInteractionBegan?()
            let offset = max(24 / max(canvas.zoomScale, 0.001), 12)

            switch payload {
            case .text(let object):
                let pastedOrigin = sourcePoint ?? CGPoint(x: object.x + offset, y: object.y + offset)
                let pasted = CanvasTextObject(
                    text: object.text,
                    x: pastedOrigin.x,
                    y: pastedOrigin.y,
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
                    fontName: object.fontName,
                    rotation: object.rotation
                )
                var textObjects = parent.textObjects
                textObjects.append(pasted)
                parent.textObjects = textObjects
                setSelectedTextObjectID(pasted.id)
                updateHostTextObjects(using: canvas)
            case .image(let object, let data):
                let pastedOrigin = sourcePoint ?? CGPoint(x: object.x + offset, y: object.y + offset)
                let fileName = "\(UUID().uuidString).png"
                let assetDirectoryURL = CanvasImageObject.assetDirectoryURL(forDrawingURL: parent.drawingURL)
                let assetURL = assetDirectoryURL.appendingPathComponent(fileName)
                do {
                    try FileManager.default.createDirectory(
                        at: assetDirectoryURL,
                        withIntermediateDirectories: true
                    )
                    try data.write(to: assetURL, options: .atomic)
                } catch {
                    print("[Canvas] semantic image paste save error: \(error)")
                    return
                }
                let pasted = CanvasImageObject(
                    imageFileName: fileName,
                    x: pastedOrigin.x,
                    y: pastedOrigin.y,
                    width: object.width,
                    height: object.height,
                    rotation: object.rotation,
                    isLocked: object.isLocked
                )
                var imageObjects = parent.imageObjects
                imageObjects.append(pasted)
                parent.imageObjects = imageObjects
                setSelectedImageObjectID(pasted.id)
                updateHostImageObjects(using: canvas)
            case .geometry(let object):
                let pastedOrigin = sourcePoint ?? CGPoint(x: object.x + offset, y: object.y + offset)
                let deltaX = pastedOrigin.x - object.x
                let deltaY = pastedOrigin.y - object.y
                let pasted = CanvasGeometryObject(
                    shape: object.shape,
                    x: pastedOrigin.x,
                    y: pastedOrigin.y,
                    width: object.width,
                    height: object.height,
                    strokeRed: object.strokeRed,
                    strokeGreen: object.strokeGreen,
                    strokeBlue: object.strokeBlue,
                    strokeAlpha: object.strokeAlpha,
                    strokeWidth: object.strokeWidth,
                    fillRed: object.fillRed,
                    fillGreen: object.fillGreen,
                    fillBlue: object.fillBlue,
                    fillOpacity: object.fillOpacity,
                    polygonSides: object.polygonSides,
                    arrow: object.arrow,
                    apexOffset: object.apexOffset,
                    rotation: object.rotation,
                    pivotX: object.pivotX.map { $0 + deltaX },
                    pivotY: object.pivotY.map { $0 + deltaY },
                    isLocked: object.isLocked
                )
                var geometryObjects = parent.geometryObjects
                geometryObjects.append(pasted)
                parent.geometryObjects = geometryObjects
                setSelectedGeometryObjectID(pasted.id)
                updateHostGeometryObjects(using: canvas)
            }
            publishImageFromModel()
        }

        private func pasteExtractedImageFromPasteboard(using canvas: PKCanvasView, at sourcePoint: CGPoint? = nil) {
            guard let payload = extractedImagePayloadFromPasteboard() else { return }
            let offset = max(24 / max(canvas.zoomScale, 0.001), 12)
            let origin = sourcePoint ?? CGPoint(
                x: payload.sourceBounds.minX + offset,
                y: payload.sourceBounds.minY + offset
            )
            let frame = CGRect(
                x: origin.x,
                y: origin.y,
                width: max(payload.sourceBounds.width, 1),
                height: max(payload.sourceBounds.height, 1)
            )
            guard saveImageObject(
                pngData: payload.pngData,
                frame: frame,
                selectAfterInsert: true,
                using: canvas
            ) else {
                return
            }
            clearRegionSelection()
            publishImageFromModel()
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

        private func performActiveExtractActionIfPossible(using canvas: PKCanvasView) -> Bool {
            guard activeSelectionTarget == .region,
                  activeRegionSelection != nil else { return false }

            let didComplete: Bool
            switch activeExtractAction {
            case .copy:
                guard makeRegionSnapshot() != nil else { return false }
                copySelectedRegionToPasteboard(using: canvas)
                didComplete = true
            case .clone:
                didComplete = duplicateSelectedRegionAsImageObject(using: canvas)
            case .send:
                guard makeRegionSnapshot() != nil else { return false }
                sendSelectedRegionToNextSlide(using: canvas)
                didComplete = true
            case .sticker:
                didComplete = duplicateSelectedRegionAsImageObject(using: canvas)
            case .delete:
                didComplete = fillSelectedRegionWithBackground(using: canvas)
            }

            if didComplete {
                parent.onExtractActionCompleted?()
            }
            return didComplete
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

        private func saveImageObject(
            pngData: Data,
            frame: CGRect,
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
                print("[Canvas] image paste save error: \(error)")
                return false
            }

            parent.onInteractionBegan?()
            let imageObject = CanvasImageObject(
                imageFileName: fileName,
                x: frame.minX,
                y: frame.minY,
                width: frame.width,
                height: frame.height,
                isLocked: isLocked ? true : nil
            )
            parent.imageObjects.append(imageObject)
            if selectAfterInsert {
                setSelectedImageObjectID(imageObject.id)
            }
            updateHostImageObjects(using: canvas)
            return true
        }

        private func sourceFrame(
            forViewportImageInsertion insertion: CanvasViewportImageInsertion,
            on canvas: PKCanvasView
        ) -> CGRect {
            let containerSize = insertion.containerSize ?? canvas.bounds.size
            let margin = max(insertion.margin, 0)
            let displaySize = CGSize(
                width: min(max(insertion.displaySize.width, 1), max(containerSize.width - margin * 2, 1)),
                height: min(max(insertion.displaySize.height, 1), max(containerSize.height - margin * 2, 1))
            )
            let overlayFrame = viewportImageOverlayFrame(
                displaySize: displaySize,
                referenceRect: insertion.referenceRect,
                containerSize: containerSize,
                margin: margin
            )
            let zoomScale = max(canvas.zoomScale, 0.001)
            let sourceOrigin = CGPoint(
                x: (canvas.contentOffset.x + overlayFrame.minX) / zoomScale - PencilKitCanvasGeometry.drawingOriginOffset.x,
                y: (canvas.contentOffset.y + overlayFrame.minY) / zoomScale - PencilKitCanvasGeometry.drawingOriginOffset.y
            )

            return CGRect(
                x: sourceOrigin.x,
                y: sourceOrigin.y,
                width: overlayFrame.width / zoomScale,
                height: overlayFrame.height / zoomScale
            )
        }

        private func viewportImageOverlayFrame(
            displaySize: CGSize,
            referenceRect: CGRect?,
            containerSize: CGSize,
            margin: CGFloat
        ) -> CGRect {
            guard let referenceRect else {
                return CGRect(
                    x: (containerSize.width - displaySize.width) / 2,
                    y: (containerSize.height - displaySize.height) / 2,
                    width: displaySize.width,
                    height: displaySize.height
                )
            }

            let leftSpace = referenceRect.minX
            let rightSpace = containerSize.width - referenceRect.maxX
            let x: CGFloat
            if rightSpace >= leftSpace {
                x = referenceRect.maxX + margin
            } else {
                x = referenceRect.minX - margin - displaySize.width
            }
            let y = referenceRect.midY - displaySize.height / 2
            let maxX = max(containerSize.width - margin - displaySize.width, margin)
            let maxY = max(containerSize.height - margin - displaySize.height, margin)

            return CGRect(
                x: min(max(x, margin), maxX),
                y: min(max(y, margin), maxY),
                width: displaySize.width,
                height: displaySize.height
            )
        }

        private func duplicateSelectedRegion(using canvas: PKCanvasView) -> Bool {
            let matchingTextObjects = parent.textObjects.filter { object in
                activeRegionSelectedTextObjectIDs.contains(object.id)
            }
            let matchingImageObjects = parent.imageObjects.filter { object in
                activeRegionSelectedImageObjectIDs.contains(object.id)
            }
            let matchingGeometryObjects = parent.geometryObjects.filter { object in
                activeRegionSelectedGeometryObjectIDs.contains(object.id)
            }
            let matchingStrokeIndexes = activeRegionSelectedStrokeIndexes.sorted()
            guard !matchingTextObjects.isEmpty || !matchingImageObjects.isEmpty
                || !matchingGeometryObjects.isEmpty || !matchingStrokeIndexes.isEmpty else { return false }

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
                        fontName: object.fontName,
                        rotation: object.rotation
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
                        height: object.height,
                        rotation: object.rotation,
                        isLocked: object.isLocked
                    )
                }
                parent.imageObjects.append(contentsOf: duplicates)
            }
            if !matchingGeometryObjects.isEmpty {
                let duplicates = matchingGeometryObjects.map { object -> CanvasGeometryObject in
                    CanvasGeometryObject(
                        shape: object.shape,
                        x: object.x + offset,
                        y: object.y + offset,
                        width: object.width,
                        height: object.height,
                        strokeRed: object.strokeRed,
                        strokeGreen: object.strokeGreen,
                        strokeBlue: object.strokeBlue,
                        strokeAlpha: object.strokeAlpha,
                        strokeWidth: object.strokeWidth,
                        fillRed: object.fillRed,
                        fillGreen: object.fillGreen,
                        fillBlue: object.fillBlue,
                        fillOpacity: object.fillOpacity,
                        polygonSides: object.polygonSides,
                        arrow: object.arrow,
                        apexOffset: object.apexOffset,
                        rotation: object.rotation,
                        pivotX: object.pivotX.map { $0 + offset },
                        pivotY: object.pivotY.map { $0 + offset },
                        isLocked: object.isLocked
                    )
                }
                parent.geometryObjects.append(contentsOf: duplicates)
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
            updateHostGeometryObjects(using: canvas)
            if activeRegionSelection != nil {
                updateActiveRegionTargets(using: canvas)
            } else {
                clearRegionSelection()
                updateSharedSelectionState()
            }
            publishImageFromModel()
            return true
        }

        private func deleteSelectedRegion(using canvas: PKCanvasView) -> Bool {
            let matchingTextIDs = activeRegionSelectedTextObjectIDs
            let matchingImageIDs = activeRegionSelectedImageObjectIDs
            let matchingGeometryIDs = activeRegionSelectedGeometryObjectIDs
            let matchingStrokeIndexes = activeRegionSelectedStrokeIndexes
            guard !matchingTextIDs.isEmpty || !matchingImageIDs.isEmpty
                || !matchingGeometryIDs.isEmpty || !matchingStrokeIndexes.isEmpty else { return false }

            parent.onInteractionBegan?()
            if !matchingTextIDs.isEmpty {
                parent.textObjects.removeAll { matchingTextIDs.contains($0.id) }
            }
            if !matchingImageIDs.isEmpty {
                parent.imageObjects.removeAll { matchingImageIDs.contains($0.id) }
            }
            if !matchingGeometryIDs.isEmpty {
                parent.geometryObjects.removeAll { matchingGeometryIDs.contains($0.id) }
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
            clearObjectDragState()
            clearRegionSelection()
            updateHostTextObjects(using: canvas)
            updateHostImageObjects(using: canvas)
            updateHostGeometryObjects(using: canvas)
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
                // Keep extracted copies transparent so white ink pastes without a gray paper halo.
                drawContentObjectLayers(
                    in: context,
                    sourceRect: canvasSourceRect,
                    destinationRect: destinationRect
                )
                parent.drawing.image(from: canvasSourceRect, scale: format.scale).draw(in: destinationRect)
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

        @objc private func handleSelectionLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began,
                  let canvas,
                  activeSelectionTarget == .object,
                  isTextSelectionEnabled,
                  canPasteClipboardObject() else {
                return
            }

            let canvasPoint = recognizer.location(in: canvas)
            guard isEmptySelectionCanvasPoint(canvasPoint, on: canvas) else { return }

            clearRegionSelection()
            let sourcePoint = sourcePoint(forCanvasPoint: canvasPoint, on: canvas)
            presentSelectionPasteMenu(from: canvasPoint, on: canvas) { [weak self, weak canvas] in
                guard let self, let canvas else { return }
                self.pasteClipboardObjectFromPasteboard(using: canvas, at: sourcePoint)
            }
        }

        private func isEmptySelectionCanvasPoint(_ point: CGPoint, on canvas: PKCanvasView) -> Bool {
            textHandleHit(at: point, on: canvas) == nil
                && hitTextObjectID(at: point, on: canvas) == nil
                && geometryHandleHit(at: point, on: canvas) == nil
                && hitGeometryObjectID(at: point, on: canvas) == nil
                && imageHandleHit(at: point, on: canvas) == nil
                && hitAnyImageObjectID(at: point, on: canvas) == nil
        }

        private func presentSelectionPasteMenu(
            from canvasPoint: CGPoint,
            on canvas: PKCanvasView,
            pasteAction: @escaping () -> Void
        ) {
            guard let presenter = canvas.window?.rootViewController?.topPresentedViewController else {
                pasteAction()
                return
            }

            let menu = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
            menu.addAction(UIAlertAction(title: "Paste", style: .default) { _ in
                pasteAction()
            })
            menu.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            if let popover = menu.popoverPresentationController {
                popover.sourceView = canvas
                popover.sourceRect = CGRect(
                    x: canvasPoint.x,
                    y: canvasPoint.y,
                    width: 1,
                    height: 1
                )
                popover.permittedArrowDirections = []
            }
            presenter.present(menu, animated: true)
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

        var selectedGeometryObjectForDisplayID: UUID? {
            guard activeTextEditor == nil,
                  case .geometry(let id) = parent.selectionState.selectedObject else {
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

        private func updateHostGeometryObjects(using canvas: PKCanvasView) {
            hostView?.updateGeometryObjects(
                parent.geometryObjects,
                using: canvas,
                selectedGeometryObjectID: selectedGeometryObjectForDisplayID,
                resizingGeometryObjectID: resizingGeometryObjectID
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
            if gestureRecognizer === geometryCreationRecognizer {
                return activeGeometryConfig != nil
            }
            if gestureRecognizer === coverCreationRecognizer {
                return activeCoverConfig != nil
            }
            if gestureRecognizer === regionSelectionRecognizer {
                if activeSelectionTarget == .object,
                   let canvas,
                   let hostView {
                    let location = hostView.convert(gestureRecognizer.location(in: hostView), to: canvas)
                    if groupTransformHit(at: location, on: canvas) != nil
                        || textHandleHit(at: location, on: canvas) != nil
                        || hitTextObjectID(at: location, on: canvas) != nil
                        || geometryHandleHit(at: location, on: canvas) != nil
                        || hitGeometryObjectID(at: location, on: canvas) != nil
                        || imageHandleHit(at: location, on: canvas) != nil
                        || hitAnyImageObjectID(at: location, on: canvas) != nil {
                        return false
                    }
                }
                return isRegionSelectionEnabled
            }
            if gestureRecognizer === textSelectionTapRecognizer
                || gestureRecognizer === textSelectionDoubleTapRecognizer {
                return isTextSelectionEnabled
            }
            if gestureRecognizer === selectionLongPressRecognizer {
                guard isTextSelectionEnabled,
                      activeSelectionTarget == .object,
                      canPasteClipboardObject(),
                      let canvas else {
                    return false
                }
                return isEmptySelectionCanvasPoint(gestureRecognizer.location(in: canvas), on: canvas)
            }
            if gestureRecognizer === textSelectionPanRecognizer {
                guard isTextSelectionEnabled,
                      let canvas else {
                    pendingGeometryHandleHit = nil
                    return false
                }
                let startLocation = gestureRecognizer.location(in: canvas)
                let geometryHandle = geometryHandleHit(at: startLocation, on: canvas)
                pendingGeometryHandleHit = geometryHandle
                return groupTransformHit(at: startLocation, on: canvas) != nil
                    || textHandleHit(at: startLocation, on: canvas) != nil
                    || geometryHandle != nil
                    || imageHandleHit(at: startLocation, on: canvas) != nil
                    || hitSelectedTextObjectID(at: startLocation, on: canvas) != nil
                    || hitSelectedGeometryObjectID(at: startLocation, on: canvas) != nil
                    || hitSelectedImageObjectID(at: startLocation, on: canvas) != nil
                    || (activeSelectionBehavior == .single
                        && topObjectHit(at: startLocation, on: canvas, includeLockedImages: false) != nil)
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            if gestureRecognizer === selectionLongPressRecognizer || otherGestureRecognizer === selectionLongPressRecognizer {
                return true
            }
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
            if (gestureRecognizer === regionSelectionRecognizer && otherGestureRecognizer === textSelectionTapRecognizer)
                || (otherGestureRecognizer === regionSelectionRecognizer && gestureRecognizer === textSelectionTapRecognizer) {
                return true
            }
            if gestureRecognizer === regionSelectionRecognizer
                || otherGestureRecognizer === regionSelectionRecognizer
                || gestureRecognizer === geometryCreationRecognizer
                || otherGestureRecognizer === geometryCreationRecognizer
                || gestureRecognizer === coverCreationRecognizer
                || otherGestureRecognizer === coverCreationRecognizer {
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
            hostView?.updateGeometryObjectFrame(using: canvas)
            hostView?.updateCoverObjectFrame(using: canvas)
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
            hostView?.updateGeometryObjectFrame(using: canvas)
            hostView?.updateCoverObjectFrame(using: canvas)
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
            hostView?.updateGeometryObjectFrame(using: canvas)
            hostView?.updateCoverObjectFrame(using: canvas)
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
                // Content object layers first, then handwriting ink on top, to
                // match the on-canvas paint order.
                drawContentObjectLayers(
                    in: context.cgContext,
                    sourceRect: sourceRect,
                    destinationRect: destinationRect
                )
                parent.drawing.image(from: sourceRect, scale: drawingImageScale).draw(in: destinationRect)
                // Tape covers paint last (above everything) so they hide content
                // on the mirrored display too.
                drawCoverObjects(
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

        private func drawContentObjectLayers(
            in context: CGContext,
            sourceRect: CGRect,
            destinationRect: CGRect
        ) {
            switch parent.objectLayerState.imageLayerPosition {
            case .belowGeometry:
                drawImageObjects(in: context, sourceRect: sourceRect, destinationRect: destinationRect)
                drawGeometryObjects(in: context, sourceRect: sourceRect, destinationRect: destinationRect)
                drawTextObjects(in: context, sourceRect: sourceRect, destinationRect: destinationRect)
            case .betweenGeometryAndText:
                drawGeometryObjects(in: context, sourceRect: sourceRect, destinationRect: destinationRect)
                drawImageObjects(in: context, sourceRect: sourceRect, destinationRect: destinationRect)
                drawTextObjects(in: context, sourceRect: sourceRect, destinationRect: destinationRect)
            case .aboveText:
                drawGeometryObjects(in: context, sourceRect: sourceRect, destinationRect: destinationRect)
                drawTextObjects(in: context, sourceRect: sourceRect, destinationRect: destinationRect)
                drawImageObjects(in: context, sourceRect: sourceRect, destinationRect: destinationRect)
            }
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
                if object.rotation == 0 {
                    CanvasMathTextRenderer.draw(object, in: textFrame, scale: scaleY)
                } else {
                    context.saveGState()
                    context.translateBy(x: textFrame.midX, y: textFrame.midY)
                    context.rotate(by: object.rotation)
                    CanvasMathTextRenderer.draw(
                        object,
                        in: CGRect(
                            x: -textFrame.width / 2,
                            y: -textFrame.height / 2,
                            width: textFrame.width,
                            height: textFrame.height
                        ),
                        scale: scaleY
                    )
                    context.restoreGState()
                }
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
                if object.rotation == 0 {
                    image.draw(in: imageFrame)
                } else {
                    context.saveGState()
                    context.translateBy(x: imageFrame.midX, y: imageFrame.midY)
                    context.rotate(by: object.rotation)
                    image.draw(
                        in: CGRect(
                            x: -imageFrame.width / 2,
                            y: -imageFrame.height / 2,
                            width: imageFrame.width,
                            height: imageFrame.height
                        )
                    )
                    context.restoreGState()
                }
            }

            context.restoreGState()
        }

        private func drawGeometryObjects(
            in context: CGContext,
            sourceRect: CGRect,
            destinationRect: CGRect
        ) {
            guard !parent.geometryObjects.isEmpty else { return }

            let scaleX = destinationRect.width / max(sourceRect.width, 0.001)
            let scaleY = destinationRect.height / max(sourceRect.height, 0.001)
            let origin = PencilKitCanvasGeometry.drawingOriginOffset
            context.saveGState()
            context.clip(to: destinationRect)

            func map(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(
                    x: destinationRect.minX + (origin.x + x - sourceRect.minX) * scaleX,
                    y: destinationRect.minY + (origin.y + y - sourceRect.minY) * scaleY
                )
            }

            for object in parent.geometryObjects {
                let normalized = object.normalizedFrame
                let topLeft = map(normalized.minX, normalized.minY)
                let boundingRect = CGRect(
                    x: topLeft.x,
                    y: topLeft.y,
                    width: normalized.width * scaleX,
                    height: normalized.height * scaleY
                )
                let start = map(object.x, object.y)
                let end = map(object.x + object.width, object.y + object.height)
                let pivot = map(object.pivot.x, object.pivot.y)
                CanvasGeometryRenderer.draw(
                    object,
                    boundingRect: boundingRect,
                    start: start,
                    end: end,
                    lineWidthScale: scaleY,
                    pivot: pivot,
                    in: context
                )
            }

            context.restoreGState()
        }

        private func drawCoverObjects(
            in context: CGContext,
            sourceRect: CGRect,
            destinationRect: CGRect
        ) {
            guard !parent.coverObjects.isEmpty else { return }

            let scaleX = destinationRect.width / max(sourceRect.width, 0.001)
            let scaleY = destinationRect.height / max(sourceRect.height, 0.001)
            let origin = PencilKitCanvasGeometry.drawingOriginOffset
            context.saveGState()
            context.clip(to: destinationRect)

            func map(_ point: CGPoint) -> CGPoint {
                CGPoint(
                    x: destinationRect.minX + (origin.x + point.x - sourceRect.minX) * scaleX,
                    y: destinationRect.minY + (origin.y + point.y - sourceRect.minY) * scaleY
                )
            }

            for object in parent.coverObjects where !object.isRevealed {
                guard object.points.count >= 2 else { continue }
                let path = CGMutablePath()
                path.move(to: map(object.points[0]))
                for point in object.points.dropFirst() {
                    path.addLine(to: map(point))
                }
                path.closeSubpath()
                context.addPath(path)
                context.setFillColor(CGColor(
                    colorSpace: CGColorSpaceCreateDeviceRGB(),
                    components: [object.red, object.green, object.blue, object.alpha]
                ) ?? CGColor(gray: 0.16, alpha: 1))
                context.fillPath()
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

private extension UIViewController {
    var topPresentedViewController: UIViewController {
        presentedViewController?.topPresentedViewController ?? self
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
