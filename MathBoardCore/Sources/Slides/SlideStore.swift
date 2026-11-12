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
    public private(set) var lastActiveSlideID: UUID?

    private let lessonURL: URL
    private let classroomSessionCode: String?
    private let fileManager: FileManager

    private static let manifestFileName = "slides.json"
    private static let strokesDirName = "strokes"
    private static let classSessionsDirName = "class-sessions"
    private static let classSessionEditsFileName = "edited-slides.json"
    private static let assetsDirName = "assets"
    private static let legacyDrawingFileName = "main.drawing"
    private static let canvasSidecarExtensions = [
        "strokecolors.json",
        "textobjects.json",
        "imageobjects.json",
        "latexobjects.json",
        "geometryobjects.json",
        "coverobjects.json",
        "widgets.json",
        "objectlayers.json"
    ]
    private static let canvasSidecarDirectoryExtensions = ["imageobjects"]

    public init(lessonURL: URL, classroomSessionCode: String? = nil) {
        let normalizedCode = Self.normalizedClassroomSessionCode(classroomSessionCode)
        self.lessonURL = lessonURL
        self.classroomSessionCode = normalizedCode
        self.fileManager = .default
        let loaded = Self.loadOrMigrate(lessonURL: lessonURL, classroomSessionCode: normalizedCode, fileManager: .default)
        self.slides = loaded.slides
        self.lastActiveSlideID = loaded.lastActiveSlideID
    }

    /// File URL where the given slide's `PKDrawing` data lives. Returned
    /// even if the file doesn't exist yet — the canvas loader handles a
    /// missing file by starting with an empty drawing.
    public func drawingURL(for slide: SlideMetadata) -> URL {
        let masterDrawingURL = Self.drawingURL(in: lessonURL, slideID: slide.id)
        guard let classroomSessionCode else {
            return masterDrawingURL
        }
        let sessionDrawingURL = Self.sessionDrawingURL(
            in: lessonURL,
            sessionCode: classroomSessionCode,
            slideID: slide.id
        )
        Self.seedClassSessionIfNeeded(from: masterDrawingURL, to: sessionDrawingURL, fileManager: fileManager)
        return sessionDrawingURL
    }

    public func drawingURL(for slide: SlideMetadata, classroomSessionCode: String?) -> URL {
        let masterDrawingURL = Self.drawingURL(in: lessonURL, slideID: slide.id)
        guard let classroomSessionCode = Self.normalizedClassroomSessionCode(classroomSessionCode) else {
            return drawingURL(for: slide)
        }
        let sessionDrawingURL = Self.sessionDrawingURL(
            in: lessonURL,
            sessionCode: classroomSessionCode,
            slideID: slide.id
        )
        Self.seedClassSessionIfNeeded(from: masterDrawingURL, to: sessionDrawingURL, fileManager: fileManager)
        return sessionDrawingURL
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

    /// Insert empty slides after the supplied index, preserving the current slide
    /// when callers need to populate it themselves.
    @discardableResult
    public func insertSlides(count: Int, afterSlideAt index: Int) throws -> [SlideMetadata] {
        try validateSlideIndex(index)
        guard count > 0 else { return [] }

        let newSlides = (0..<count).map { _ in SlideMetadata() }
        slides.insert(contentsOf: newSlides, at: index + 1)
        saveManifest()
        return newSlides
    }

    /// Insert a single anchored supplementary slide after the slide at `index`.
    /// The new slide is tagged with `kind` and an anchor pointing to the nearest
    /// preceding master slide (or `nil` if there is none), so `mergeMasterSlides`
    /// can restore its position relative to master slides on reload.
    @discardableResult
    public func insertAnchoredSlide(kind: SlideAnchor.Kind, afterSlideAt index: Int) throws -> SlideMetadata {
        try validateSlideIndex(index)

        let masterSlideID: UUID?
        let existingCount: Int

        if slides[index].anchor == nil {
            // Inserting right after a master slide: fresh group, no existing same-kind slides.
            masterSlideID = slides[index].id
            existingCount = 0
        } else {
            // Inserting after an existing anchored slide: inherit its master anchor.
            masterSlideID = slides[index].anchor!.masterSlideID
            // Count same-kind anchored slides in this group (from after the preceding master to index).
            let masterIdx = slides[...index].indices.last(where: { slides[$0].anchor == nil }) ?? -1
            let groupStart = masterIdx + 1  // safe: masterIdx < index since slides[index] is anchored
            existingCount = slides[groupStart...index].filter { $0.anchor?.kind == kind }.count
        }

        let anchor = SlideAnchor(kind: kind, masterSlideID: masterSlideID, sequenceNumber: existingCount + 1)
        let newSlide = SlideMetadata(anchor: anchor)
        slides.insert(newSlide, at: index + 1)
        print("[Slides] insertAnchoredSlide: kind=\(kind.rawValue) masterSlideID=\(masterSlideID?.uuidString ?? "nil") seq=\(anchor.sequenceNumber) newSlideID=\(newSlide.id) totalSlides=\(slides.count)")
        saveManifest()
        return newSlide
    }

    /// Compute the display label for `slide` given the current ordered `slides` array.
    /// Master slides get plain numbers ("1", "2", …). Anchored slides get the preceding
    /// master number plus a kind suffix and optional sequence number ("3T", "3T2", "3S").
    public static func slideLabel(for slide: SlideMetadata, in slides: [SlideMetadata]) -> String {
        guard let slideIndex = slides.firstIndex(where: { $0.id == slide.id }) else {
            return "?"
        }

        if slide.anchor == nil {
            let position = slides[...slideIndex].filter { $0.anchor == nil }.count
            return "\(position)"
        }

        let kind = slide.anchor!.kind
        let precedingMasterCount = slides[..<slideIndex].filter { $0.anchor == nil }.count

        // Walk back to find the start of this contiguous anchor group
        var groupStart = slideIndex
        while groupStart > 0 && slides[groupStart - 1].anchor != nil {
            groupStart -= 1
        }

        let seqNum = slides[groupStart...slideIndex].filter { $0.anchor?.kind == kind }.count
        let suffix = kind.rawValue
        return seqNum <= 1 ? "\(precedingMasterCount)\(suffix)" : "\(precedingMasterCount)\(suffix)\(seqNum)"
    }

    /// Duplicate the slide at `index`, placing the copy immediately after it.
    /// All canvas sidecar files are deep-copied under the new slide's UUID.
    @discardableResult
    public func duplicateSlide(at index: Int) throws -> SlideMetadata {
        try validateSlideIndex(index)
        let source = slides[index]
        let copy = SlideMetadata(background: source.background)

        let sourceDrawingURL = Self.drawingURL(in: lessonURL, slideID: source.id)
        let copyDrawingURL = Self.drawingURL(in: lessonURL, slideID: copy.id)
        try? Self.copyCanvasState(from: sourceDrawingURL, to: copyDrawingURL, fileManager: fileManager)

        slides.insert(copy, at: index + 1)
        saveManifest()
        return copy
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

    public static func propagateMasterContent(
        lessonURL: URL,
        toClassSessionCodes classSessionCodes: [String]
    ) {
        let normalizedCodes = Set(classSessionCodes.compactMap(Self.normalizedClassroomSessionCode))
        guard !normalizedCodes.isEmpty else { return }

        let masterSlides = loadOrMigrateMasterSlides(lessonURL: lessonURL, fileManager: .default)
        for sessionCode in normalizedCodes {
            let sessionStore = SlideStore(lessonURL: lessonURL, classroomSessionCode: sessionCode)
            let editedSlideIDs = loadClassSessionEditedSlideIDs(
                lessonURL: lessonURL,
                sessionCode: sessionCode,
                fileManager: .default
            )
            let deletedSlideIDs = loadClassSessionDeletedSlideIDs(
                lessonURL: lessonURL,
                sessionCode: sessionCode,
                fileManager: .default
            )
            let isSlideOrderEdited = loadClassSessionEditManifest(
                lessonURL: lessonURL,
                sessionCode: sessionCode,
                fileManager: .default
            ).isSlideOrderEdited
            _ = sessionStore.mergeMasterSlides(
                masterSlides,
                preservingEditedSlideIDs: editedSlideIDs,
                deletedSlideIDs: deletedSlideIDs,
                preservingSlideOrder: isSlideOrderEdited
            )

            for slide in masterSlides {
                guard !editedSlideIDs.contains(slide.id),
                      !deletedSlideIDs.contains(slide.id) else { continue }
                let masterDrawingURL = drawingURL(in: lessonURL, slideID: slide.id)
                let sessionDrawingURL = sessionDrawingURL(
                    in: lessonURL,
                    sessionCode: sessionCode,
                    slideID: slide.id
                )
                replaceCanvasState(
                    from: masterDrawingURL,
                    to: sessionDrawingURL,
                    fileManager: .default
                )
            }
        }
    }

    public static func markClassSessionSlideEdited(
        lessonURL: URL,
        classroomSessionCode: String?,
        slideID: UUID
    ) {
        guard let sessionCode = normalizedClassroomSessionCode(classroomSessionCode) else { return }
        var editedSlideIDs = loadClassSessionEditedSlideIDs(
            lessonURL: lessonURL,
            sessionCode: sessionCode,
            fileManager: .default
        )
        guard editedSlideIDs.insert(slideID).inserted else { return }
        saveClassSessionEditedSlideIDs(
            editedSlideIDs,
            lessonURL: lessonURL,
            sessionCode: sessionCode,
            fileManager: .default
        )
    }

    public static func markClassSessionSlideDeleted(
        lessonURL: URL,
        classroomSessionCode: String?,
        slideID: UUID
    ) {
        guard let sessionCode = normalizedClassroomSessionCode(classroomSessionCode) else { return }
        var manifest = loadClassSessionEditManifest(
            lessonURL: lessonURL,
            sessionCode: sessionCode,
            fileManager: .default
        )
        manifest.editedSlideIDs.removeAll { $0 == slideID }
        guard !manifest.deletedSlideIDs.contains(slideID) else { return }
        manifest.deletedSlideIDs.append(slideID)
        saveClassSessionEditManifest(
            manifest,
            lessonURL: lessonURL,
            sessionCode: sessionCode,
            fileManager: .default
        )
    }

    public static func markClassSessionSlideOrderEdited(
        lessonURL: URL,
        classroomSessionCode: String?
    ) {
        guard let sessionCode = normalizedClassroomSessionCode(classroomSessionCode) else { return }
        var manifest = loadClassSessionEditManifest(
            lessonURL: lessonURL,
            sessionCode: sessionCode,
            fileManager: .default
        )
        guard !manifest.isSlideOrderEdited else { return }
        manifest.isSlideOrderEdited = true
        saveClassSessionEditManifest(
            manifest,
            lessonURL: lessonURL,
            sessionCode: sessionCode,
            fileManager: .default
        )
    }

    public static func loadClassSessionDeletedSlideIDs(
        lessonURL: URL,
        classroomSessionCode: String?
    ) -> [UUID] {
        guard let sessionCode = normalizedClassroomSessionCode(classroomSessionCode) else { return [] }
        return loadClassSessionEditManifest(
            lessonURL: lessonURL,
            sessionCode: sessionCode,
            fileManager: .default
        ).deletedSlideIDs
    }

    @discardableResult
    public func mergeTeacherSlides(
        _ teacherSlides: [SlideMetadata],
        deferredTeacherSlideIDs: Set<UUID> = [],
        teacherDeletedSlideIDs: Set<UUID> = []
    ) -> Bool {
        guard !teacherSlides.isEmpty || !deferredTeacherSlideIDs.isEmpty || !teacherDeletedSlideIDs.isEmpty else { return false }

        let originalSlides = slides
        let teacherSlideIDs = Set(teacherSlides.map(\.id))
        let remainingLocalSlides = slides.filter { localSlide in
            !teacherSlideIDs.contains(localSlide.id)
                && !deferredTeacherSlideIDs.contains(localSlide.id)
                && !teacherDeletedSlideIDs.contains(localSlide.id)
        }
        let mergedTeacherSlides = teacherSlides.map { teacherSlide in
            if let localSlide = originalSlides.first(where: { $0.id == teacherSlide.id }) {
                var mergedSlide = teacherSlide
                mergedSlide.viewport = localSlide.viewport ?? teacherSlide.viewport
                return mergedSlide
            }
            return teacherSlide
        }

        slides = mergedTeacherSlides + remainingLocalSlides
        guard slides != originalSlides else { return false }
        saveManifest()
        return true
    }

    @discardableResult
    private func mergeMasterSlides(
        _ masterSlides: [SlideMetadata],
        preservingEditedSlideIDs editedSlideIDs: Set<UUID>,
        deletedSlideIDs: Set<UUID>,
        preservingSlideOrder: Bool
    ) -> Bool {
        guard !masterSlides.isEmpty else { return false }

        let originalSlides = slides
        let visibleMasterSlides = masterSlides.filter { !deletedSlideIDs.contains($0.id) }
        let masterSlideIDs = Set(visibleMasterSlides.map(\.id))
        let masterSlidesByID = Dictionary(uniqueKeysWithValues: visibleMasterSlides.map { ($0.id, $0) })

        // Supplementary (anchored) slides: always preserved unless explicitly deleted
        let supplementarySlides = originalSlides.filter {
            $0.anchor != nil && !deletedSlideIDs.contains($0.id)
        }
        print("[Slides] mergeMasterSlides: original=\(originalSlides.count) master=\(masterSlides.count) supplementary=\(supplementarySlides.count) editedIDs=\(editedSlideIDs.count)")

        if preservingSlideOrder {
            // Teacher manually reordered slides: preserve existing order, but update master
            // slide content and keep anchored slides in their current positions.
            var emittedSlideIDs = Set<UUID>()
            var orderedSlides: [SlideMetadata] = originalSlides.compactMap { localSlide in
                if localSlide.anchor != nil {
                    return deletedSlideIDs.contains(localSlide.id) ? nil : localSlide
                }
                guard let masterSlide = masterSlidesByID[localSlide.id] else {
                    return editedSlideIDs.contains(localSlide.id) && !deletedSlideIDs.contains(localSlide.id)
                        ? localSlide
                        : nil
                }
                emittedSlideIDs.insert(localSlide.id)
                if editedSlideIDs.contains(localSlide.id) { return localSlide }
                var mergedSlide = masterSlide
                mergedSlide.viewport = localSlide.viewport ?? masterSlide.viewport
                return mergedSlide
            }
            orderedSlides.append(contentsOf: visibleMasterSlides.filter { !emittedSlideIDs.contains($0.id) })
            slides = orderedSlides
        } else {
            // Default: interleave supplementary slides after their anchor master slide.
            // Build merged master slides first (unchanged from before).
            let mergedMasterSlides: [SlideMetadata] = visibleMasterSlides.map { masterSlide in
                if editedSlideIDs.contains(masterSlide.id),
                   let localSlide = originalSlides.first(where: { $0.id == masterSlide.id }) {
                    return localSlide
                }
                if let localSlide = originalSlides.first(where: { $0.id == masterSlide.id }) {
                    var mergedSlide = masterSlide
                    mergedSlide.viewport = localSlide.viewport ?? masterSlide.viewport
                    return mergedSlide
                }
                return masterSlide
            }

            // Build an insertion map: masterSlideID? → [slides to insert after that master].
            // Handles both anchor-tagged slides and older/unanchored local-only slides by
            // inferring position from where the slide appeared in the original session order.
            var insertionMap: [UUID?: [SlideMetadata]] = [:]

            // Pass 1: anchored supplementary slides — use their stored anchor.
            for slide in supplementarySlides {
                let anchorID = slide.anchor!.masterSlideID
                if let anchorID, masterSlidesByID[anchorID] == nil {
                    // Master was deleted — fall back to the last surviving master before this slide.
                    let fallbackID = originalSlides
                        .prefix(while: { $0.id != slide.id })
                        .last(where: { $0.anchor == nil && masterSlidesByID[$0.id] != nil })?
                        .id
                    insertionMap[fallbackID, default: []].append(slide)
                } else {
                    insertionMap[anchorID, default: []].append(slide)
                }
            }

            // Pass 2: local-only slides without an anchor tag (legacy slides or decode fallback).
            // Infer position from the slide's location in the original session manifest.
            let unanchoredLocalSlides = originalSlides.filter { slide in
                slide.anchor == nil
                    && !masterSlideIDs.contains(slide.id)
                    && !deletedSlideIDs.contains(slide.id)
                    && editedSlideIDs.contains(slide.id)
            }
            for slide in unanchoredLocalSlides {
                let precedingMasterID = originalSlides
                    .prefix(while: { $0.id != slide.id })
                    .last(where: { $0.anchor == nil && masterSlidesByID[$0.id] != nil })?
                    .id
                insertionMap[precedingMasterID, default: []].append(slide)
            }

            // Sort each bucket by the slide's original position in the session manifest.
            // This preserves the teacher's arrangement across round-trips regardless of
            // whether slides carry anchor tags or are legacy unanchored local slides.
            let originalPositions: [UUID: Int] = Dictionary(
                uniqueKeysWithValues: originalSlides.enumerated().map { ($1.id, $0) }
            )
            for key in insertionMap.keys {
                insertionMap[key]?.sort {
                    (originalPositions[$0.id] ?? Int.max) < (originalPositions[$1.id] ?? Int.max)
                }
            }

            // Interleave: pre-master slides, then for each master slide its followers.
            var result: [SlideMetadata] = insertionMap[nil] ?? []
            for masterSlide in mergedMasterSlides {
                result.append(masterSlide)
                if let followers = insertionMap[masterSlide.id] {
                    result.append(contentsOf: followers)
                }
            }

            slides = result
        }

        guard slides != originalSlides else {
            print("[Slides] mergeMasterSlides: no change, skipping save. result=\(slides.count) anchored=\(slides.filter { $0.anchor != nil }.count)")
            return false
        }
        print("[Slides] mergeMasterSlides: saving result=\(slides.count) anchored=\(slides.filter { $0.anchor != nil }.count)")
        saveManifest()
        return true
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
        let url = Self.manifestURL(in: lessonURL, classroomSessionCode: classroomSessionCode)
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try Self.jsonEncoder.encode(SlideManifest(slides: slides, lastActiveSlideID: lastActiveSlideID))
            try data.write(to: url, options: .atomic)
        } catch {
            print("[Slides] save error: \(error)")
        }
    }

    public func saveLastActiveSlide(_ slideID: UUID) {
        guard slides.contains(where: { $0.id == slideID }) else { return }
        guard lastActiveSlideID != slideID else { return }
        lastActiveSlideID = slideID
        saveManifest()
    }

    private static func loadOrMigrate(
        lessonURL: URL,
        classroomSessionCode: String?,
        fileManager: FileManager
    ) -> (slides: [SlideMetadata], lastActiveSlideID: UUID?) {
        let masterSlides = loadOrMigrateMasterSlides(lessonURL: lessonURL, fileManager: fileManager)
        guard let classroomSessionCode else {
            // Master context — re-read the master manifest to pick up lastActiveSlideID.
            let masterManifestURL = manifestURL(in: lessonURL, classroomSessionCode: nil)
            let lastActiveSlideID: UUID?
            if let data = try? Data(contentsOf: masterManifestURL),
               let manifest = try? jsonDecoder.decode(SlideManifest.self, from: data) {
                lastActiveSlideID = manifest.lastActiveSlideID
            } else {
                lastActiveSlideID = nil
            }
            return (slides: masterSlides, lastActiveSlideID: lastActiveSlideID)
        }

        let sessionManifestURL = manifestURL(in: lessonURL, classroomSessionCode: classroomSessionCode)
        if let data = try? Data(contentsOf: sessionManifestURL) {
            do {
                let manifest = try jsonDecoder.decode(SlideManifest.self, from: data)
                if !manifest.slides.isEmpty {
                    let supplementaryCount = manifest.slides.filter { $0.anchor != nil }.count
                    print("[Slides] loadOrMigrate code=\(classroomSessionCode) slides=\(manifest.slides.count) supplementary=\(supplementaryCount)")
                    return (slides: manifest.slides, lastActiveSlideID: manifest.lastActiveSlideID)
                }
            } catch {
                print("[Slides] ⚠️ session manifest decode FAILED code=\(classroomSessionCode) error=\(error)")
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("[Slides] ⚠️ bad JSON snippet: \(String(jsonString.prefix(500)))")
                }
            }
        } else {
            print("[Slides] loadOrMigrate code=\(classroomSessionCode) — no manifest file, seeding from master")
        }

        do {
            try fileManager.createDirectory(
                at: sessionManifestURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try jsonEncoder.encode(SlideManifest(slides: masterSlides))
            try data.write(to: sessionManifestURL, options: .atomic)
        } catch {
            print("[Slides] class session manifest seed error: \(error)")
        }
        return (slides: masterSlides, lastActiveSlideID: nil)
    }

    private static func loadOrMigrateMasterSlides(lessonURL: URL, fileManager: FileManager) -> [SlideMetadata] {
        let manifestURL = manifestURL(in: lessonURL, classroomSessionCode: nil)

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

    private static func manifestURL(in lessonURL: URL, classroomSessionCode: String?) -> URL {
        if let classroomSessionCode {
            return lessonURL
                .appendingPathComponent(classSessionsDirName, isDirectory: true)
                .appendingPathComponent(classroomSessionCode, isDirectory: true)
                .appendingPathComponent(manifestFileName)
        }
        return lessonURL.appendingPathComponent(manifestFileName)
    }

    private static func drawingURL(in lessonURL: URL, slideID: UUID) -> URL {
        lessonURL
            .appendingPathComponent(strokesDirName, isDirectory: true)
            .appendingPathComponent("slide-\(slideID.uuidString).drawing")
    }

    private static func sessionDrawingURL(in lessonURL: URL, sessionCode: String, slideID: UUID) -> URL {
        lessonURL
            .appendingPathComponent(classSessionsDirName, isDirectory: true)
            .appendingPathComponent(sessionCode, isDirectory: true)
            .appendingPathComponent(strokesDirName, isDirectory: true)
            .appendingPathComponent("slide-\(slideID.uuidString).drawing")
    }

    private static func classSessionEditsURL(in lessonURL: URL, sessionCode: String) -> URL {
        lessonURL
            .appendingPathComponent(classSessionsDirName, isDirectory: true)
            .appendingPathComponent(sessionCode, isDirectory: true)
            .appendingPathComponent(classSessionEditsFileName)
    }

    private static func normalizedClassroomSessionCode(_ code: String?) -> String? {
        let normalized = (code ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
        return normalized.isEmpty ? nil : normalized
    }

    private static func seedClassSessionIfNeeded(
        from masterDrawingURL: URL,
        to sessionDrawingURL: URL,
        fileManager: FileManager
    ) {
        do {
            try fileManager.createDirectory(
                at: sessionDrawingURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try copyCanvasState(from: masterDrawingURL, to: sessionDrawingURL, fileManager: fileManager)
        } catch {
            // The canvas can still open and save into the session URL if seeding fails.
        }
    }

    private static func copyCanvasState(
        from masterDrawingURL: URL,
        to sessionDrawingURL: URL,
        fileManager: FileManager
    ) throws {
        try copyItemIfPresent(from: masterDrawingURL, to: sessionDrawingURL, fileManager: fileManager)

        let masterBaseURL = masterDrawingURL.deletingPathExtension()
        let sessionBaseURL = sessionDrawingURL.deletingPathExtension()
        for sidecarExtension in canvasSidecarExtensions {
            try copyItemIfPresent(
                from: masterBaseURL.appendingPathExtension(sidecarExtension),
                to: sessionBaseURL.appendingPathExtension(sidecarExtension),
                fileManager: fileManager
            )
        }
        for directoryExtension in canvasSidecarDirectoryExtensions {
            try copyItemIfPresent(
                from: masterBaseURL.appendingPathExtension(directoryExtension),
                to: sessionBaseURL.appendingPathExtension(directoryExtension),
                fileManager: fileManager
            )
        }
    }

    private static func replaceCanvasState(
        from masterDrawingURL: URL,
        to sessionDrawingURL: URL,
        fileManager: FileManager
    ) {
        do {
            try replaceItemIfPresent(from: masterDrawingURL, to: sessionDrawingURL, fileManager: fileManager)

            let masterBaseURL = masterDrawingURL.deletingPathExtension()
            let sessionBaseURL = sessionDrawingURL.deletingPathExtension()
            for sidecarExtension in canvasSidecarExtensions {
                try replaceItemIfPresent(
                    from: masterBaseURL.appendingPathExtension(sidecarExtension),
                    to: sessionBaseURL.appendingPathExtension(sidecarExtension),
                    fileManager: fileManager
                )
            }
            for directoryExtension in canvasSidecarDirectoryExtensions {
                try replaceItemIfPresent(
                    from: masterBaseURL.appendingPathExtension(directoryExtension),
                    to: sessionBaseURL.appendingPathExtension(directoryExtension),
                    fileManager: fileManager
                )
            }
        } catch {
            print("[Slides] class session master propagation error: \(error)")
        }
    }

    private static func copyItemIfPresent(from sourceURL: URL, to destinationURL: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: sourceURL.path),
              !fileManager.fileExists(atPath: destinationURL.path) else {
            return
        }
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private static func replaceItemIfPresent(from sourceURL: URL, to destinationURL: URL, fileManager: FileManager) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        guard fileManager.fileExists(atPath: sourceURL.path) else { return }
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private static func loadClassSessionEditedSlideIDs(
        lessonURL: URL,
        sessionCode: String,
        fileManager: FileManager
    ) -> Set<UUID> {
        Set(loadClassSessionEditManifest(
            lessonURL: lessonURL,
            sessionCode: sessionCode,
            fileManager: fileManager
        ).editedSlideIDs)
    }

    private static func loadClassSessionDeletedSlideIDs(
        lessonURL: URL,
        sessionCode: String,
        fileManager: FileManager
    ) -> Set<UUID> {
        Set(loadClassSessionEditManifest(
            lessonURL: lessonURL,
            sessionCode: sessionCode,
            fileManager: fileManager
        ).deletedSlideIDs)
    }

    private static func saveClassSessionEditedSlideIDs(
        _ editedSlideIDs: Set<UUID>,
        lessonURL: URL,
        sessionCode: String,
        fileManager: FileManager
    ) {
        var manifest = loadClassSessionEditManifest(
            lessonURL: lessonURL,
            sessionCode: sessionCode,
            fileManager: fileManager
        )
        manifest.editedSlideIDs = editedSlideIDs.sorted { $0.uuidString < $1.uuidString }
        saveClassSessionEditManifest(manifest, lessonURL: lessonURL, sessionCode: sessionCode, fileManager: fileManager)
    }

    private static func loadClassSessionEditManifest(
        lessonURL: URL,
        sessionCode: String,
        fileManager: FileManager
    ) -> ClassSessionEditManifest {
        let url = classSessionEditsURL(in: lessonURL, sessionCode: sessionCode)
        guard let data = try? Data(contentsOf: url),
              let manifest = try? jsonDecoder.decode(ClassSessionEditManifest.self, from: data) else {
            return ClassSessionEditManifest()
        }
        return manifest
    }

    private static func saveClassSessionEditManifest(
        _ manifest: ClassSessionEditManifest,
        lessonURL: URL,
        sessionCode: String,
        fileManager: FileManager
    ) {
        let url = classSessionEditsURL(in: lessonURL, sessionCode: sessionCode)
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var normalizedManifest = manifest
            normalizedManifest.editedSlideIDs.sort { $0.uuidString < $1.uuidString }
            normalizedManifest.deletedSlideIDs.sort { $0.uuidString < $1.uuidString }
            let data = try jsonEncoder.encode(normalizedManifest)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[Slides] class session edit manifest save error: \(error)")
        }
    }

    private struct SlideManifest: Codable {
        let slides: [SlideMetadata]
        var lastActiveSlideID: UUID? = nil
    }

    private struct ClassSessionEditManifest: Codable {
        var editedSlideIDs: [UUID]
        var deletedSlideIDs: [UUID]
        var isSlideOrderEdited: Bool

        init(
            editedSlideIDs: [UUID] = [],
            deletedSlideIDs: [UUID] = [],
            isSlideOrderEdited: Bool = false
        ) {
            self.editedSlideIDs = editedSlideIDs
            self.deletedSlideIDs = deletedSlideIDs
            self.isSlideOrderEdited = isSlideOrderEdited
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            editedSlideIDs = try container.decodeIfPresent([UUID].self, forKey: .editedSlideIDs) ?? []
            deletedSlideIDs = try container.decodeIfPresent([UUID].self, forKey: .deletedSlideIDs) ?? []
            isSlideOrderEdited = try container.decodeIfPresent(Bool.self, forKey: .isSlideOrderEdited) ?? false
        }
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
