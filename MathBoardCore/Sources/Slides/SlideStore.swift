//
//  SlideStore.swift
//  MathBoardCore — Slides module
//
//  Owns the slide list for a single `.mathboard` lesson package. Loads
//  / writes `<lesson>.mathboard/slides.json` and constructs the path to
//  each slide's drawing file (`<lesson>.mathboard/strokes/slide-<uuid>.drawing`).
//
//  Migration: if a lesson predates slides (only `strokes/main.drawing`
//  exists), the loader synthesizes a single SlideMetadata, renames
//  `main.drawing` to `slide-<uuid>.drawing`, and writes a slides.json.
//  After migration, the lesson behaves like any other multi-slide
//  lesson.
//

import Foundation
import Observation
import PDFKit

@MainActor
@Observable
public final class SlideStore {

    public private(set) var slides: [SlideMetadata]

    private let lessonURL: URL
    private let fileManager: FileManager

    private static let manifestFileName = "slides.json"
    private static let strokesDirName = "strokes"
    private static let assetsDirName = "assets"
    private static let legacyDrawingFileName = "main.drawing"

    public init(lessonURL: URL) {
        self.lessonURL = lessonURL
        self.fileManager = .default
        self.slides = Self.loadOrMigrate(lessonURL: lessonURL, fileManager: .default)
    }

    /// File URL where the given slide's `PKDrawing` data lives. Returned
    /// even if the file doesn't exist yet — the canvas loader handles a
    /// missing file by starting with an empty drawing.
    public func drawingURL(for slide: SlideMetadata) -> URL {
        Self.drawingURL(in: lessonURL, slideID: slide.id)
    }

    public func backgroundURL(for background: SlideBackground) -> URL {
        lessonURL
            .appendingPathComponent(Self.assetsDirName, isDirectory: true)
            .appendingPathComponent(background.assetFileName)
    }

    /// Append a new empty slide at the end of the list.
    @discardableResult
    public func addSlide() -> SlideMetadata {
        let newSlide = SlideMetadata()
        slides.append(newSlide)
        saveManifest()
        return newSlide
    }

    /// Delete a slide and its drawing file, returning the index that should
    /// become active after removal.
    @discardableResult
    public func deleteSlide(at index: Int) throws -> Int {
        try validateSlideIndex(index)
        guard slides.count > 1 else {
            throw SlideStoreError.cannotDeleteLastSlide
        }

        let deletedSlide = slides.remove(at: index)
        let url = drawingURL(for: deletedSlide)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }

        saveManifest()
        return min(index, slides.count - 1)
    }

    /// Move a slide within the manifest order, returning the moved slide's
    /// new index.
    @discardableResult
    public func moveSlide(at index: Int, to destinationIndex: Int) throws -> Int {
        try validateSlideIndex(index)
        try validateSlideIndex(destinationIndex)
        guard index != destinationIndex else { return index }

        let movedSlide = slides.remove(at: index)
        slides.insert(movedSlide, at: destinationIndex)
        saveManifest()
        return destinationIndex
    }

    public func updateViewport(_ viewport: SlideViewportState, forSlideAt index: Int) throws {
        try validateSlideIndex(index)
        guard slides[index].viewport != viewport else { return }

        slides[index].viewport = viewport
        saveManifest()
    }

    public func updateViewport(_ viewport: SlideViewportState, forSlideID slideID: UUID) throws {
        guard let index = slides.firstIndex(where: { $0.id == slideID }) else {
            throw SlideStoreError.invalidSlideIndex
        }
        try updateViewport(viewport, forSlideAt: index)
    }

    @discardableResult
    public func importPDF(from sourceURL: URL) throws -> [SlideMetadata] {
        try importPDF(
            from: sourceURL,
            pageIndices: nil,
            afterSlideAt: slides.count - 1,
            reuseCurrentSlideIfBlank: false
        ).slides
    }

    @discardableResult
    public func importPDF(
        from sourceURL: URL,
        pageIndices selectedPageIndices: [Int]? = nil,
        afterSlideAt activeIndex: Int,
        reuseCurrentSlideIfBlank: Bool
    ) throws -> PDFImportResult {
        try validateSlideIndex(activeIndex)

        let assetsDir = lessonURL.appendingPathComponent(Self.assetsDirName, isDirectory: true)
        try fileManager.createDirectory(at: assetsDir, withIntermediateDirectories: true)

        let assetFileName = "pdf-\(UUID().uuidString).pdf"
        let destinationURL = assetsDir.appendingPathComponent(assetFileName)
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        guard let document = PDFDocument(url: destinationURL), document.pageCount > 0 else {
            try? fileManager.removeItem(at: destinationURL)
            throw SlideStoreError.invalidPDF
        }

        let pageIndices = (selectedPageIndices ?? Array(0..<document.pageCount))
            .filter { $0 >= 0 && $0 < document.pageCount }
        guard !pageIndices.isEmpty else {
            try? fileManager.removeItem(at: destinationURL)
            throw SlideStoreError.noPDFPagesSelected
        }

        let importedSlides = pageIndices.map { pageIndex in
            SlideMetadata(
                background: SlideBackground(
                    kind: .pdfPage,
                    assetFileName: assetFileName,
                    pageIndex: pageIndex
                )
            )
        }

        let startIndex: Int
        if reuseCurrentSlideIfBlank && isBlankSlide(at: activeIndex) {
            var replacementSlide = slides[activeIndex]
            replacementSlide.background = importedSlides[0].background
            replacementSlide.viewport = nil
            slides[activeIndex] = replacementSlide

            if importedSlides.count > 1 {
                slides.insert(contentsOf: importedSlides.dropFirst(), at: activeIndex + 1)
            }
            startIndex = activeIndex
        } else {
            startIndex = activeIndex + 1
            slides.insert(contentsOf: importedSlides, at: startIndex)
        }

        saveManifest()
        return PDFImportResult(startIndex: startIndex, slides: importedSlides)
    }

    public func isBlankSlide(at index: Int) -> Bool {
        guard slides.indices.contains(index) else { return false }
        let slide = slides[index]
        return slide.background == nil
            && slide.viewport == nil
            && !fileManager.fileExists(atPath: drawingURL(for: slide).path)
    }

    private func validateSlideIndex(_ index: Int) throws {
        guard slides.indices.contains(index) else {
            throw SlideStoreError.invalidSlideIndex
        }
    }

    // MARK: - Manifest persistence

    private func saveManifest() {
        let url = lessonURL.appendingPathComponent(Self.manifestFileName)
        do {
            let data = try Self.jsonEncoder.encode(SlideManifest(slides: slides))
            try data.write(to: url, options: .atomic)
        } catch {
            print("[Slides] save error: \(error)")
        }
    }

    private static func loadOrMigrate(lessonURL: URL, fileManager: FileManager) -> [SlideMetadata] {
        let manifestURL = lessonURL.appendingPathComponent(manifestFileName)

        if let data = try? Data(contentsOf: manifestURL),
           let manifest = try? jsonDecoder.decode(SlideManifest.self, from: data) {
            return manifest.slides
        }

        // No manifest — migrate from the v1 single-page layout. Synthesize
        // one slide and, if a legacy main.drawing exists, rename it into
        // the new per-slide filename.
        let migratedSlide = SlideMetadata()
        let strokesDir = lessonURL
            .appendingPathComponent(strokesDirName, isDirectory: true)
        let legacyURL = strokesDir.appendingPathComponent(legacyDrawingFileName)
        let newDrawingURL = drawingURL(in: lessonURL, slideID: migratedSlide.id)

        if fileManager.fileExists(atPath: legacyURL.path) {
            try? fileManager.createDirectory(
                at: strokesDir,
                withIntermediateDirectories: true
            )
            try? fileManager.moveItem(at: legacyURL, to: newDrawingURL)
        }

        let migrated = [migratedSlide]
        if let data = try? jsonEncoder.encode(SlideManifest(slides: migrated)) {
            try? data.write(to: manifestURL, options: .atomic)
        }
        return migrated
    }

    private static func drawingURL(in lessonURL: URL, slideID: UUID) -> URL {
        lessonURL
            .appendingPathComponent(strokesDirName, isDirectory: true)
            .appendingPathComponent("slide-\(slideID.uuidString).drawing")
    }

    private struct SlideManifest: Codable {
        let slides: [SlideMetadata]
    }

    private static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

public enum SlideStoreError: LocalizedError {
    case cannotDeleteLastSlide
    case invalidSlideIndex
    case invalidPDF
    case noPDFPagesSelected

    public var errorDescription: String? {
        switch self {
        case .cannotDeleteLastSlide:
            "A lesson must keep at least one slide."
        case .invalidSlideIndex:
            "That slide no longer exists."
        case .invalidPDF:
            "The selected PDF couldn't be imported."
        case .noPDFPagesSelected:
            "Select at least one PDF page to import."
        }
    }
}

public struct PDFImportResult: Sendable {
    public let startIndex: Int
    public let slides: [SlideMetadata]
}
