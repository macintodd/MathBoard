//
//  SlidesView.swift
//  MathBoardCore — Slides module
//
//  Multi-slide wrapper around `PresentingCanvasView`. Owns the active
//  slide index and hosts the floating navigator overlay. Each slide
//  gets its own fresh viewport state on activation (via `.id(slide.id)`)
//  so switching slides doesn't carry over zoom/pan — matches the
//  Keynote / PowerPoint expectation.
//

import SwiftUI
import Library
import Presentation
import PDFKit
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public enum MathBoardClassroomMode: String, CaseIterable, Identifiable {
    case teacher
    case student

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .teacher: return "Teacher"
        case .student: return "Student"
        }
    }

    public var systemImage: String {
        switch self {
        case .teacher: return "person.crop.rectangle"
        case .student: return "graduationcap"
        }
    }

    public var allowsWidgetAuthoring: Bool {
        self == .teacher
    }
}

public struct SlidesView: View {
    private let lessonURL: URL

    @State private var store: SlideStore
    @Binding private var classroomMode: MathBoardClassroomMode
    @State private var activeIndex: Int = 0
    @State private var pendingDeleteIndices: [Int]?
    @State private var thumbnailCache = SlideThumbnailCache()
    @State private var slideErrorMessage: String?
    @State private var isShowingPDFImporter = false
    @State private var isShowingPDFExporter = false
    @State private var isShowingFilmstrip = false
    @State private var isTextEditingOnCanvas = false
    @State private var pendingPDFImport: PendingPDFImport?
    @State private var viewportSaveTask: Task<Void, Never>?
    @State private var pendingViewportSave: PendingViewportSave?

    private static let viewportSaveDebounce: Duration = .milliseconds(300)

    public init(
        lessonURL: URL,
        classroomMode: Binding<MathBoardClassroomMode> = .constant(.teacher)
    ) {
        self.lessonURL = lessonURL
        _store = State(initialValue: SlideStore(lessonURL: lessonURL))
        _classroomMode = classroomMode
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let slide = activeSlide {
                PresentingCanvasView(
                    drawingURL: store.drawingURL(for: slide),
                    background: canvasBackground(for: slide.background),
                    initialViewportState: presentationViewportState(for: slide),
                    onViewportStateChange: { state in
                        scheduleViewportSave(state, for: slide.id)
                    },
                    onInteractionBegan: handleCanvasInteractionBegan,
                    onTextEditingBegan: handleCanvasTextEditingBegan,
                    onTextEditingEnded: handleCanvasTextEditingEnded,
                    onExtractedRegionSend: sendExtractedRegionToNextEmptySlide,
                    onImportPDF: { isShowingPDFImporter = true },
                    onImportPDFObjects: importPDFPagesAsCanvasObjects,
                    onExportPDF: {
                        flushPendingViewportSave()
                        isShowingPDFExporter = true
                    },
                    allowsWidgetAuthoring: classroomMode.allowsWidgetAuthoring
                )
                    .id(slide.id)
            }

            if !isTextEditingOnCanvas {
                SlideNavigatorView(
                    slides: store.slides,
                    currentIndex: activeIndex,
                    isFilmstripOpen: $isShowingFilmstrip,
                    thumbnail: thumbnailImage(for:),
                    onGoTo: goToSlide,
                    onPrevious: goToPrevious,
                    onNext: goToNext,
                    onAdd: addSlide,
                    onMoveSlides: moveSlides(at:by:),
                    onDeleteSlides: requestDeleteSlides(at:)
                )
                .padding(.trailing, 16)
                .padding(.bottom, 14)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // Grabbing a tool (or any tool-palette interaction) closes the
        // filmstrip: every palette command writes broker.toolPaletteState.
        // Library drawer taps and drag-drops touch neither the palette state
        // nor the canvas, so the strip stays open for the "stamp the same
        // sticker across slides" workflow.
        .onChange(of: DisplayBroker.shared.toolPaletteState) { _, _ in
            closeFilmstripForOutsideInteraction()
        }
        .confirmationDialog(
            deleteConfirmationTitle,
            isPresented: Binding(
                get: { pendingDeleteIndices != nil },
                set: { isPresented in
                    if !isPresented { pendingDeleteIndices = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(
                (pendingDeleteIndices?.count ?? 0) > 1 ? "Delete Slides" : "Delete Slide",
                role: .destructive,
                action: deletePendingSlides
            )
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(
                (pendingDeleteIndices?.count ?? 0) > 1
                    ? "This removes the slides and their drawings from this lesson."
                    : "This removes the slide and its drawing from this lesson."
            )
        }
        .alert(
            "Couldn't Update Slides",
            isPresented: Binding(
                get: { slideErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        slideErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            if let slideErrorMessage {
                Text(slideErrorMessage)
            }
        }
        .onDisappear {
            flushPendingViewportSave()
        }
        .fileImporter(
            isPresented: $isShowingPDFImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false,
            onCompletion: handlePDFImport
        )
        .sheet(item: $pendingPDFImport) { pendingImport in
            PDFImportPreviewView(
                pdfURL: pendingImport.url,
                onCancel: {
                    clearPendingPDFImport()
                },
                onImport: { pageIndices in
                    importSelectedPDFPages(pageIndices, from: pendingImport)
                }
            )
        }
        .sheet(isPresented: $isShowingPDFExporter) {
            PDFExportSelectionView(
                slides: store.slides,
                initialIndex: activeIndex,
                onCancel: {
                    isShowingPDFExporter = false
                },
                onExport: exportPDF
            )
        }
    }

    private var activeSlide: SlideMetadata? {
        guard activeIndex >= 0, activeIndex < store.slides.count else { return nil }
        return store.slides[activeIndex]
    }

    private func goToPrevious() {
        guard activeIndex > 0 else { return }
        flushPendingViewportSave()
        activeIndex -= 1
    }

    private func goToNext() {
        guard activeIndex < store.slides.count - 1 else { return }
        flushPendingViewportSave()
        activeIndex += 1
    }

    private func goToSlide(_ index: Int) {
        guard store.slides.indices.contains(index) else { return }
        guard index != activeIndex else { return }
        flushPendingViewportSave()
        activeIndex = index
    }

    /// Any interaction outside the navigator and the Library drawer closes
    /// the filmstrip — touching the canvas or grabbing a tool means attention
    /// has moved back to the whiteboard. Library taps and drag-drops reach
    /// neither the canvas-interaction callback nor the tool palette state, so
    /// the strip stays open while stamping library items across slides.
    private func closeFilmstripForOutsideInteraction() {
        guard isShowingFilmstrip else { return }
        withAnimation(.snappy(duration: 0.22)) {
            isShowingFilmstrip = false
        }
    }

    private func handleCanvasInteractionBegan() {
        closeFilmstripForOutsideInteraction()
    }

    private func handleCanvasTextEditingBegan() {
        withAnimation(.snappy(duration: 0.18)) {
            isShowingFilmstrip = false
            isTextEditingOnCanvas = true
        }
    }

    private func handleCanvasTextEditingEnded() {
        withAnimation(.snappy(duration: 0.18)) {
            isTextEditingOnCanvas = false
        }
    }

    /// Inserts a blank slide directly after the current one and makes it the
    /// active slide (matches the SlideNav prototype behavior).
    private func addSlide() {
        flushPendingViewportSave()
        do {
            try store.insertSlides(count: 1, afterSlideAt: activeIndex)
            activeIndex += 1
        } catch {
            slideErrorMessage = error.localizedDescription
        }
    }

    private func sendExtractedRegionToNextEmptySlide(_ region: PresentationExtractedRegion) {
        flushPendingViewportSave()
        do {
            let targetSlide: SlideMetadata
            if let emptyIndex = store.slides.indices.first(where: { index in
                index > activeIndex && isEmptyForExtractSend(store.slides[index])
            }) {
                targetSlide = store.slides[emptyIndex]
            } else {
                targetSlide = store.addSlide()
            }
            try placeExtractedRegion(region, on: targetSlide)
        } catch {
            slideErrorMessage = error.localizedDescription
        }
    }

    private func isEmptyForExtractSend(_ slide: SlideMetadata) -> Bool {
        guard slide.background == nil else { return false }
        let drawingURL = store.drawingURL(for: slide)
        if FileManager.default.fileExists(atPath: drawingURL.path) {
            return false
        }
        let textObjects = PresentationCanvasTextObject.load(from: PresentationCanvasTextObject.sidecarURL(forDrawingURL: drawingURL))
        let imageObjects = PresentationCanvasImageObject.load(from: PresentationCanvasImageObject.sidecarURL(forDrawingURL: drawingURL))
        let geometryObjects = PresentationCanvasGeometryObject.load(from: PresentationCanvasGeometryObject.sidecarURL(forDrawingURL: drawingURL))
        return textObjects.isEmpty && imageObjects.isEmpty && geometryObjects.isEmpty
    }

    private func placeExtractedRegion(_ region: PresentationExtractedRegion, on slide: SlideMetadata) throws {
        let drawingURL = store.drawingURL(for: slide)
        let assetDirectoryURL = PresentationCanvasImageObject.assetDirectoryURL(forDrawingURL: drawingURL)
        try FileManager.default.createDirectory(at: assetDirectoryURL, withIntermediateDirectories: true)

        let fileName = "\(UUID().uuidString).png"
        let assetURL = assetDirectoryURL.appendingPathComponent(fileName)
        try region.pngData.write(to: assetURL, options: .atomic)

        var imageObjects = PresentationCanvasImageObject.load(from: PresentationCanvasImageObject.sidecarURL(forDrawingURL: drawingURL))
        imageObjects.append(PresentationCanvasImageObject(
            imageFileName: fileName,
            x: region.sourceBounds.minX,
            y: region.sourceBounds.minY,
            width: region.sourceBounds.width,
            height: region.sourceBounds.height
        ))
        try PresentationCanvasImageObject.save(
            imageObjects,
            to: PresentationCanvasImageObject.sidecarURL(forDrawingURL: drawingURL)
        )
        try? LibraryRecentStore.record(
            title: Self.libraryRecentTitle("Extracted sticker"),
            kind: .extractedInk,
            thumbnailPNGData: region.pngData,
            forDrawingURL: drawingURL
        )
    }

    private static func libraryRecentTitle(_ baseTitle: String, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return "\(baseTitle) \(formatter.string(from: date))"
    }

    private func importPDFPagesAsCanvasObjects(pdfURL: URL, pageIndices: [Int]) {
        do {
            flushPendingViewportSave()
            let importedPages = try Self.renderPDFPagesAsCanvasImages(from: pdfURL, pageIndices: pageIndices)
            guard !importedPages.isEmpty else {
                throw SlideStoreError.noPDFPagesSelected
            }

            let targetSlides = try slidesForPDFObjectImport(count: importedPages.count)
            for (page, slide) in zip(importedPages, targetSlides) {
                try placePDFPageImage(page, on: slide)
            }
            if let firstTargetIndex = store.slides.firstIndex(where: { $0.id == targetSlides[0].id }) {
                activeIndex = firstTargetIndex
            }
            try? FileManager.default.removeItem(at: pdfURL)
        } catch {
            slideErrorMessage = error.localizedDescription
            try? FileManager.default.removeItem(at: pdfURL)
        }
    }

    private func slidesForPDFObjectImport(count: Int) throws -> [SlideMetadata] {
        guard count > 0 else { return [] }

        if let activeSlide, isEmptyForExtractSend(activeSlide) {
            let additionalSlides = try store.insertSlides(count: count - 1, afterSlideAt: activeIndex)
            return [activeSlide] + additionalSlides
        }

        return try store.insertSlides(count: count, afterSlideAt: activeIndex)
    }

    private func placePDFPageImage(_ page: ImportedPDFPageImage, on slide: SlideMetadata) throws {
        let drawingURL = store.drawingURL(for: slide)
        let assetDirectoryURL = PresentationCanvasImageObject.assetDirectoryURL(forDrawingURL: drawingURL)
        try FileManager.default.createDirectory(at: assetDirectoryURL, withIntermediateDirectories: true)

        let fileName = "\(UUID().uuidString).png"
        try page.pngData.write(to: assetDirectoryURL.appendingPathComponent(fileName), options: .atomic)

        let frame = Self.centeredPDFPageFrame(for: page.displaySize)
        let imageObject = PresentationCanvasImageObject(
            imageFileName: fileName,
            x: frame.minX,
            y: frame.minY,
            width: frame.width,
            height: frame.height,
            isLocked: true
        )
        try PresentationCanvasImageObject.save(
            [imageObject],
            to: PresentationCanvasImageObject.sidecarURL(forDrawingURL: drawingURL)
        )
        try? LibraryRecentStore.record(
            title: Self.libraryRecentTitle("PDF page object"),
            kind: .image,
            thumbnailPNGData: page.pngData,
            forDrawingURL: drawingURL
        )
    }

    private static func centeredPDFPageFrame(for displaySize: CGSize) -> CGRect {
        let boardSize = PresentationCanvasBoardMetrics.defaultUsableSize
        let margin: CGFloat = 180
        let availableSize = CGSize(
            width: max(boardSize.width - margin * 2, 1),
            height: max(boardSize.height - margin * 2, 1)
        )
        let scale = min(
            availableSize.width / max(displaySize.width, 1),
            availableSize.height / max(displaySize.height, 1)
        )
        let enlargedScale = min(
            scale * 1.3,
            min(
                (boardSize.width - 48) / max(displaySize.width, 1),
                (boardSize.height - 48) / max(displaySize.height, 1)
            )
        )
        let fittedSize = CGSize(
            width: displaySize.width * enlargedScale,
            height: displaySize.height * enlargedScale
        )
        let centeredOrigin = CGPoint(
            x: (boardSize.width - fittedSize.width) / 2,
            y: (boardSize.height - fittedSize.height) / 2
        )
        let bottomWhitespace = max(boardSize.height - (centeredOrigin.y + fittedSize.height), 0)
        let shiftedOrigin = CGPoint(
            x: min(centeredOrigin.x + fittedSize.width / 2, max(boardSize.width - fittedSize.width - 24, 0)),
            y: min(centeredOrigin.y + bottomWhitespace / 2, max(boardSize.height - fittedSize.height - 24, 0))
        )
        return CGRect(
            x: max(shiftedOrigin.x, 24),
            y: max(shiftedOrigin.y, 24),
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    private func handlePDFImport(_ result: Result<[URL], any Error>) {
        do {
            let urls = try result.get()
            guard let sourceURL = urls.first else { return }

            let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            flushPendingViewportSave()
            pendingPDFImport = try makePendingPDFImport(from: sourceURL)
        } catch {
            slideErrorMessage = error.localizedDescription
        }
    }

    private func makePendingPDFImport(from sourceURL: URL) throws -> PendingPDFImport {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MathBoard-PDF-\(UUID().uuidString).pdf")
        try FileManager.default.copyItem(at: sourceURL, to: temporaryURL)
        return PendingPDFImport(url: temporaryURL)
    }

    private func importSelectedPDFPages(_ pageIndices: [Int], from pendingImport: PendingPDFImport) {
        do {
            flushPendingViewportSave()
            let result = try store.importPDF(
                from: pendingImport.url,
                pageIndices: pageIndices,
                afterSlideAt: activeIndex,
                reuseCurrentSlideIfBlank: true
            )
            activeIndex = result.startIndex
            clearPendingPDFImport()
        } catch {
            slideErrorMessage = error.localizedDescription
        }
    }

    private func clearPendingPDFImport() {
        if let pendingPDFImport {
            try? FileManager.default.removeItem(at: pendingPDFImport.url)
        }
        pendingPDFImport = nil
    }

    private func exportPDF(selectedIndices: [Int]) async throws -> URL {
        let selectedSlides = selectedIndices.compactMap { index in
            store.slides.indices.contains(index) ? store.slides[index] : nil
        }
        guard !selectedSlides.isEmpty else {
            throw SlidePDFExportError.couldNotCreatePDF
        }

        return try await SlidePDFExporter.export(
            slides: selectedSlides,
            drawingURL: store.drawingURL(for:),
            backgroundURL: store.backgroundURL(for:),
            lessonName: lessonURL.deletingPathExtension().lastPathComponent
        )
    }

    private var deleteConfirmationTitle: String {
        guard let indices = pendingDeleteIndices else { return "" }
        if indices.count == 1, let index = indices.first {
            return "Delete Slide \(index + 1)?"
        }
        return "Delete \(indices.count) Slides?"
    }

    private func requestDeleteSlides(at indices: [Int]) {
        guard !indices.isEmpty, indices.count < store.slides.count else {
            slideErrorMessage = SlideStoreError.cannotDeleteLastSlide.localizedDescription
            return
        }
        pendingDeleteIndices = indices
    }

    /// Deletes the confirmed slides (highest index first so earlier removals
    /// don't shift later ones), then lands on the nearest survivor at or after
    /// the old current position.
    private func deletePendingSlides() {
        guard let indices = pendingDeleteIndices else { return }
        pendingDeleteIndices = nil
        flushPendingViewportSave()

        let doomed = Set(indices)
        let survivorAfter = store.slides.enumerated().first {
            $0.offset >= activeIndex && !doomed.contains($0.offset)
        }?.element.id
        let survivorBefore = store.slides.enumerated().reversed().first {
            $0.offset < activeIndex && !doomed.contains($0.offset)
        }?.element.id

        do {
            for index in indices.sorted(by: >) {
                try store.deleteSlide(at: index)
            }
        } catch {
            slideErrorMessage = error.localizedDescription
        }

        if let survivor = survivorAfter ?? survivorBefore,
           let index = store.slides.firstIndex(where: { $0.id == survivor }) {
            activeIndex = index
        } else {
            activeIndex = min(max(activeIndex, 0), store.slides.count - 1)
        }
    }

    /// Moves the given slides one step (direction: -1 left, +1 right).
    /// Non-contiguous selections all shift together; slides already packed
    /// against the edge stay put and become a boundary the rest pack up
    /// against on further clicks.
    private func moveSlides(at indices: [Int], by direction: Int) {
        guard !indices.isEmpty else { return }
        flushPendingViewportSave()
        let currentID = activeSlide?.id

        do {
            if direction < 0 {
                var boundary = 0
                for index in indices.sorted() {
                    if index > boundary {
                        try store.moveSlide(at: index, to: index - 1)
                    } else {
                        boundary = index + 1
                    }
                }
            } else if direction > 0 {
                var boundary = store.slides.count - 1
                for index in indices.sorted().reversed() {
                    if index < boundary {
                        try store.moveSlide(at: index, to: index + 1)
                    } else {
                        boundary = index - 1
                    }
                }
            }
        } catch {
            slideErrorMessage = error.localizedDescription
        }

        if let currentID, let newIndex = store.slides.firstIndex(where: { $0.id == currentID }) {
            activeIndex = newIndex
        }
    }

    /// PDF-page thumbnail for the navigator filmstrip, cached per asset+page
    /// so scrolling the strip doesn't re-open PDF documents. Ink-only slides
    /// return nil and get the navigator's placeholder card.
    private func thumbnailImage(for slide: SlideMetadata) -> Image? {
        guard let background = slide.background, background.kind == .pdfPage else { return nil }
        let key = "\(background.assetFileName)#\(background.pageIndex)"
        if let cached = thumbnailCache.images[key] {
            return cached
        }
        guard let document = PDFDocument(url: store.backgroundURL(for: background)),
              let page = document.page(at: background.pageIndex) else { return nil }
        let platformImage = page.thumbnail(of: CGSize(width: 232, height: 174), for: .mediaBox)
        #if os(iOS)
        let image = Image(uiImage: platformImage)
        #else
        let image = Image(nsImage: platformImage)
        #endif
        thumbnailCache.images[key] = image
        return image
    }

    private func scheduleViewportSave(_ state: PresentationViewportState, for slideID: UUID) {
        let viewport = SlideViewportState(
            zoomScale: Double(state.zoomScale),
            contentOffsetX: Double(state.contentOffset.x),
            contentOffsetY: Double(state.contentOffset.y),
            platform: Self.viewportPlatformIdentifier
        )
        if pendingViewportSave?.slideID == slideID,
           let pendingViewport = pendingViewportSave?.viewport,
           pendingViewport.isApproximatelyEqual(to: viewport) {
            return
        }
        if activeSlide?.id == slideID,
           let savedViewport = activeSlide?.viewport,
           savedViewport.isApproximatelyEqual(to: viewport) {
            return
        }
        pendingViewportSave = PendingViewportSave(slideID: slideID, viewport: viewport)
        viewportSaveTask?.cancel()
        viewportSaveTask = Task { @MainActor in
            try? await Task.sleep(for: Self.viewportSaveDebounce)
            guard !Task.isCancelled else { return }
            flushPendingViewportSave()
        }
    }

    private func flushPendingViewportSave() {
        viewportSaveTask?.cancel()
        viewportSaveTask = nil
        guard let pendingViewportSave else { return }

        do {
            try store.updateViewport(
                pendingViewportSave.viewport,
                forSlideID: pendingViewportSave.slideID
            )
            self.pendingViewportSave = nil
        } catch {
            slideErrorMessage = error.localizedDescription
        }
    }

    private func presentationViewportState(for slide: SlideMetadata) -> PresentationViewportState? {
        guard let viewport = slide.viewport else { return nil }
        guard shouldRestoreViewport(viewport, for: slide) else { return nil }
        return PresentationViewportState(
            zoomScale: CGFloat(viewport.zoomScale),
            contentOffset: CGPoint(
                x: CGFloat(viewport.contentOffsetX),
                y: CGFloat(viewport.contentOffsetY)
            ),
            minimumZoomScale: 0.1,
            maximumZoomScale: 4
        )
    }

    private func shouldRestoreViewport(_ viewport: SlideViewportState, for slide: SlideMetadata) -> Bool {
        if let platform = viewport.platform {
            return platform == Self.viewportPlatformIdentifier
        }

        // Legacy PDF-backed slides may contain Mac-saved viewport coordinates
        // without a platform tag. Do not restore those on iPad; let the canvas
        // apply first-open combined-content fitting instead.
        #if os(iOS)
        if slide.background != nil {
            return false
        }
        #endif
        return true
    }

    private static func renderPDFPagesAsCanvasImages(from pdfURL: URL, pageIndices: [Int]) throws -> [ImportedPDFPageImage] {
        guard let document = PDFDocument(url: pdfURL), document.pageCount > 0 else {
            throw SlideStoreError.invalidPDF
        }

        let validPageIndices = pageIndices.filter { $0 >= 0 && $0 < document.pageCount }
        guard !validPageIndices.isEmpty else {
            throw SlideStoreError.noPDFPagesSelected
        }

        return try validPageIndices.map { pageIndex in
            guard let page = document.page(at: pageIndex) else {
                throw SlideStoreError.invalidPDF
            }
            return try renderPDFPageAsCanvasImage(page)
        }
    }

    private static func renderPDFPageAsCanvasImage(_ page: PDFPage) throws -> ImportedPDFPageImage {
        let pageBounds = page.bounds(for: .mediaBox)
        let width = max(pageBounds.width, 1)
        let height = max(pageBounds.height, 1)
        let displaySize = CGSize(width: width, height: height)
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
            throw SlideStoreError.invalidPDF
        }
        return ImportedPDFPageImage(pngData: pngData, displaySize: displaySize)
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
            throw SlideStoreError.invalidPDF
        }
        representation.size = renderSize
        NSGraphicsContext.saveGraphicsState()
        guard let graphicsContext = NSGraphicsContext(bitmapImageRep: representation) else {
            NSGraphicsContext.restoreGraphicsState()
            throw SlideStoreError.invalidPDF
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
            throw SlideStoreError.invalidPDF
        }
        return ImportedPDFPageImage(pngData: pngData, displaySize: displaySize)
        #endif
    }

    private static var viewportPlatformIdentifier: String {
        #if os(macOS)
        "macOS"
        #elseif os(iOS)
        "iPadOS"
        #else
        "unknown"
        #endif
    }

    private func canvasBackground(for background: SlideBackground?) -> PresentationCanvasBackground? {
        guard let background else { return nil }

        switch background.kind {
        case .pdfPage:
            return PresentationCanvasBackground(
                pdfURL: store.backgroundURL(for: background),
                pageIndex: background.pageIndex
            )
        }
    }

    private struct PendingViewportSave {
        let slideID: UUID
        let viewport: SlideViewportState
    }

    private struct PendingPDFImport: Identifiable {
        let id = UUID()
        let url: URL
    }

    private struct ImportedPDFPageImage {
        let pngData: Data
        let displaySize: CGSize
    }
}

/// Reference-type thumbnail cache: mutating its contents during a body render
/// is fine because it never triggers a SwiftUI state change — it only avoids
/// re-opening PDF documents for tiles that were already rendered once.
@MainActor
private final class SlideThumbnailCache {
    var images: [String: Image] = [:]
}

private extension SlideViewportState {
    func isApproximatelyEqual(to other: SlideViewportState) -> Bool {
        platform == other.platform
            && abs(zoomScale - other.zoomScale) < 0.0001
            && abs(contentOffsetX - other.contentOffsetX) < 0.5
            && abs(contentOffsetY - other.contentOffsetY) < 0.5
    }
}
