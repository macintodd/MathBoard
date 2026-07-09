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
import Presentation
import UniformTypeIdentifiers

public struct SlidesView: View {
    private let lessonURL: URL

    @State private var store: SlideStore
    @State private var activeIndex: Int = 0
    @State private var isShowingDeleteConfirmation = false
    @State private var slideErrorMessage: String?
    @State private var isShowingPDFImporter = false
    @State private var isShowingPDFExporter = false
    @State private var isShowingFilmstrip = false
    @State private var shouldHideFilmstripOnCanvasInteraction = false
    @State private var pendingPDFImport: PendingPDFImport?
    @State private var viewportSaveTask: Task<Void, Never>?
    @State private var pendingViewportSave: PendingViewportSave?

    private static let viewportSaveDebounce: Duration = .milliseconds(300)

    public init(lessonURL: URL) {
        self.lessonURL = lessonURL
        _store = State(initialValue: SlideStore(lessonURL: lessonURL))
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            if let slide = activeSlide {
                PresentingCanvasView(
                    drawingURL: store.drawingURL(for: slide),
                    background: canvasBackground(for: slide.background),
                    initialViewportState: presentationViewportState(for: slide),
                    onViewportStateChange: { state in
                        scheduleViewportSave(state, for: slide.id)
                    },
                    onInteractionBegan: handleCanvasInteractionBegan,
                    onExtractedRegionSend: sendExtractedRegionToNextEmptySlide,
                    onImportPDF: { isShowingPDFImporter = true },
                    onExportPDF: {
                        flushPendingViewportSave()
                        isShowingPDFExporter = true
                    }
                )
                    .id(slide.id)
            }

            VStack(spacing: 10) {
                if isShowingFilmstrip {
                    SlideFilmstripView(
                        slides: store.slides,
                        currentIndex: activeIndex,
                        backgroundURL: store.backgroundURL(for:),
                        onSelect: goToSlide
                    )
                    .padding(.horizontal, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                SlideNavigator(
                    currentIndex: activeIndex,
                    totalCount: store.slides.count,
                    isFilmstripExpanded: isShowingFilmstrip,
                    onToggleFilmstrip: toggleFilmstrip,
                    onPrevious: goToPrevious,
                    onNext: goToNext,
                    onMoveLeft: moveCurrentSlideLeft,
                    onMoveRight: moveCurrentSlideRight,
                    onDelete: requestDeleteCurrentSlide,
                    onAdd: addSlide
                )
            }
            .padding(.bottom, 12)
        }
        .confirmationDialog(
            "Delete Slide \(activeIndex + 1)?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Slide", role: .destructive, action: deleteCurrentSlide)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the slide and its drawing from this lesson.")
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
        shouldHideFilmstripOnCanvasInteraction = true
        guard index != activeIndex else { return }
        flushPendingViewportSave()
        activeIndex = index
    }

    private func toggleFilmstrip() {
        withAnimation(.snappy(duration: 0.22)) {
            isShowingFilmstrip.toggle()
        }
        if !isShowingFilmstrip {
            shouldHideFilmstripOnCanvasInteraction = false
        }
    }

    private func handleCanvasInteractionBegan() {
        guard shouldHideFilmstripOnCanvasInteraction, isShowingFilmstrip else { return }
        shouldHideFilmstripOnCanvasInteraction = false
        withAnimation(.snappy(duration: 0.22)) {
            isShowingFilmstrip = false
        }
    }

    private func addSlide() {
        flushPendingViewportSave()
        store.addSlide()
        activeIndex = store.slides.count - 1
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

    private func requestDeleteCurrentSlide() {
        guard store.slides.count > 1 else {
            slideErrorMessage = SlideStoreError.cannotDeleteLastSlide.localizedDescription
            return
        }
        isShowingDeleteConfirmation = true
    }

    private func deleteCurrentSlide() {
        do {
            flushPendingViewportSave()
            activeIndex = try store.deleteSlide(at: activeIndex)
        } catch {
            slideErrorMessage = error.localizedDescription
        }
    }

    private func moveCurrentSlideLeft() {
        moveCurrentSlide(to: activeIndex - 1)
    }

    private func moveCurrentSlideRight() {
        moveCurrentSlide(to: activeIndex + 1)
    }

    private func moveCurrentSlide(to destinationIndex: Int) {
        do {
            flushPendingViewportSave()
            activeIndex = try store.moveSlide(at: activeIndex, to: destinationIndex)
        } catch {
            slideErrorMessage = error.localizedDescription
        }
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
}

private extension SlideViewportState {
    func isApproximatelyEqual(to other: SlideViewportState) -> Bool {
        platform == other.platform
            && abs(zoomScale - other.zoomScale) < 0.0001
            && abs(contentOffsetX - other.contentOffsetX) < 0.5
            && abs(contentOffsetY - other.contentOffsetY) < 0.5
    }
}
