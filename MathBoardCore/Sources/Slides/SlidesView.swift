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
import Canvas
import Library
import LiveClassroom
import Presentation
import PDFKit
import UniformTypeIdentifiers
import WidgetEngine
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

private struct StudentLiveTeacherInkSaveRequest {
    var drawingURL: URL
    var strokes: [CanvasLiveStroke]
    var strokeIDs: [UUID]
}

private struct StudentCoverMaskOverlay: View {
    var coverObjects: [CanvasCoverObject]
    var viewportSourceRect: CGRect?
    var fallbackSourceSize: CGSize
    var fittedSize: CGSize

    var body: some View {
        SwiftUI.Canvas { context, _ in
            for cover in coverObjects where cover.points.count >= 2 {
                var path = Path()
                let points = cover.points.map(scaledPoint)
                guard let first = points.first else { continue }
                path.move(to: first)
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
                path.closeSubpath()

                context.fill(
                    path,
                    with: .color(Color(
                        red: Double(cover.red),
                        green: Double(cover.green),
                        blue: Double(cover.blue),
                        opacity: Double(cover.alpha)
                    ))
                )
            }
        }
        .frame(width: fittedSize.width, height: fittedSize.height)
        .allowsHitTesting(false)
    }

    private func scaledPoint(_ point: CGPoint) -> CGPoint {
        if let viewportSourceRect,
           viewportSourceRect.width > 0,
           viewportSourceRect.height > 0 {
            return CGPoint(
                x: (point.x - viewportSourceRect.minX) * fittedSize.width / viewportSourceRect.width,
                y: (point.y - viewportSourceRect.minY) * fittedSize.height / viewportSourceRect.height
            )
        }

        guard fallbackSourceSize.width > 0, fallbackSourceSize.height > 0 else { return point }
        return CGPoint(
            x: point.x * fittedSize.width / fallbackSourceSize.width,
            y: point.y * fittedSize.height / fallbackSourceSize.height
        )
    }
}

public struct SlidesView: View {
    private let lessonURL: URL
    private let classroomSessionCode: String?
    private let liveClassroomConfiguration: LiveClassroomSessionConfiguration?
    private let initialTeacherInkDrawingSnapshots: [TeacherInkDrawingSnapshot]
    private let initialTeacherSlideManifestSnapshot: TeacherSlideManifestSnapshot?
    private let initialTeacherObjectSnapshots: [TeacherObjectSnapshot]
    private let onActiveWidgetIDsChanged: ((Set<UUID>) -> Void)?
    private let onActiveWidgetsChanged: (([WidgetObject]) -> Void)?
    private let onTeacherInkChunkPublished: ((TeacherInkStrokeChunk) -> Void)?
    private let onTeacherInkDrawingSnapshotPublished: ((TeacherInkDrawingSnapshot) -> Void)?
    private let onTeacherObjectSnapshotPublished: ((TeacherObjectSnapshot) -> Void)?
    private let onTeacherSlideManifestSnapshotPublished: ((TeacherSlideManifestSnapshot) async throws -> Void)?
    private let onLiveTeacherSlideManifestRefreshRequested: ((TeacherSlideManifestSnapshot) async -> TeacherSlideManifestSnapshot?)?
    private let onLibraryDrawerOpenChange: (@MainActor (Bool) -> Void)?
    private let onLessonContentChanged: (@MainActor () -> Void)?
    private let isEditingLocked: Bool

    @State private var store: SlideStore
    @Binding private var classroomMode: MathBoardClassroomMode
    @Binding private var isFollowMeEnabled: Bool
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
    @State private var liveTeacherInkCoordinator = LiveTeacherInkCoordinator()
    @State private var currentViewportSourceRect: CGRect?
    @State private var objectStateReloadCommand: CanvasObjectCommand?
    @State private var canvasRefreshToken = UUID()
    @State private var inkDrawingSnapshotSaveTask: Task<Void, Never>?
    @State private var objectSnapshotSaveTasksBySlideID: [UUID: Task<Void, Never>] = [:]
    @State private var lessonContentPropagationTask: Task<Void, Never>?
    @State private var inkDrawingSnapshotRevisionsBySlideID: [UUID: Int] = [:]
    @State private var objectSnapshotRevisionsBySlideID: [UUID: Int] = [:]
    @State private var slideManifestRevision = 0
    @State private var appliedTeacherSlideManifestUpdateID: String?
    @State private var appliedTeacherObjectSnapshotsUpdateID: String?
    @State private var isStudentFollowMeActive = false

    private static let viewportSaveDebounce: Duration = .milliseconds(300)
    private static let inkDrawingSnapshotDebounce: Duration = .milliseconds(700)
    private static let objectSnapshotDebounce: Duration = .milliseconds(700)

    public init(
        lessonURL: URL,
        classroomMode: Binding<MathBoardClassroomMode> = .constant(.teacher),
        isFollowMeEnabled: Binding<Bool> = .constant(false),
        classroomSessionCode: String? = nil,
        liveClassroomConfiguration: LiveClassroomSessionConfiguration? = nil,
        initialTeacherInkChunks: [TeacherInkStrokeChunk] = [],
        initialTeacherInkDrawingSnapshots: [TeacherInkDrawingSnapshot] = [],
        initialTeacherSlideManifestSnapshot: TeacherSlideManifestSnapshot? = nil,
        initialTeacherObjectSnapshots: [TeacherObjectSnapshot] = [],
        onActiveWidgetIDsChanged: ((Set<UUID>) -> Void)? = nil,
        onActiveWidgetsChanged: (([WidgetObject]) -> Void)? = nil,
        onTeacherInkChunkPublished: ((TeacherInkStrokeChunk) -> Void)? = nil,
        onTeacherInkDrawingSnapshotPublished: ((TeacherInkDrawingSnapshot) -> Void)? = nil,
        onTeacherObjectSnapshotPublished: ((TeacherObjectSnapshot) -> Void)? = nil,
        onTeacherSlideManifestSnapshotPublished: ((TeacherSlideManifestSnapshot) async throws -> Void)? = nil,
        onLiveTeacherSlideManifestRefreshRequested: ((TeacherSlideManifestSnapshot) async -> TeacherSlideManifestSnapshot?)? = nil,
        onLibraryDrawerOpenChange: (@MainActor (Bool) -> Void)? = nil,
        onLessonContentChanged: (@MainActor () -> Void)? = nil,
        isEditingLocked: Bool = false
    ) {
        self.lessonURL = lessonURL
        self.classroomSessionCode = classroomSessionCode
        self.liveClassroomConfiguration = liveClassroomConfiguration
        self.initialTeacherInkDrawingSnapshots = initialTeacherInkDrawingSnapshots
        self.initialTeacherSlideManifestSnapshot = initialTeacherSlideManifestSnapshot
        self.initialTeacherObjectSnapshots = initialTeacherObjectSnapshots
        self.onActiveWidgetIDsChanged = onActiveWidgetIDsChanged
        self.onActiveWidgetsChanged = onActiveWidgetsChanged
        self.onTeacherInkChunkPublished = onTeacherInkChunkPublished
        self.onTeacherInkDrawingSnapshotPublished = onTeacherInkDrawingSnapshotPublished
        self.onTeacherObjectSnapshotPublished = onTeacherObjectSnapshotPublished
        self.onTeacherSlideManifestSnapshotPublished = onTeacherSlideManifestSnapshotPublished
        self.onLiveTeacherSlideManifestRefreshRequested = onLiveTeacherSlideManifestRefreshRequested
        self.onLibraryDrawerOpenChange = onLibraryDrawerOpenChange
        self.onLessonContentChanged = onLessonContentChanged
        self.isEditingLocked = isEditingLocked
        let initialStore = SlideStore(
            lessonURL: lessonURL,
            classroomSessionCode: classroomMode.wrappedValue == .teacher ? classroomSessionCode : nil
        )
        var appliedInitialTeacherSlideManifestUpdateID: String?
        var appliedInitialTeacherObjectSnapshotsUpdateID: String?
        if classroomMode.wrappedValue == .student {
            if let initialTeacherSlideManifestSnapshot {
                Self.mergeInitialTeacherSlideManifestSnapshot(initialTeacherSlideManifestSnapshot, into: initialStore)
                appliedInitialTeacherSlideManifestUpdateID = Self.teacherSlideManifestUpdateID(
                    for: initialTeacherSlideManifestSnapshot
                )
            }
            Self.mergeInitialTeacherObjectSnapshots(initialTeacherObjectSnapshots, into: initialStore)
            appliedInitialTeacherObjectSnapshotsUpdateID = Self.teacherObjectSnapshotsUpdateID(
                for: initialTeacherObjectSnapshots
            )
            // Teacher ink is rendered as a separate live overlay. Do not write it
            // into the student's own PencilKit drawing file, or student notes are
            // replaced the next time the lesson is opened.
        }
        let initialActiveIndex: Int
        if classroomMode.wrappedValue == .student,
           initialTeacherSlideManifestSnapshot?.isFollowMeEnabled == true,
           let teacherActiveSlideID = initialTeacherSlideManifestSnapshot?.activeSlideID,
           let teacherActiveIndex = initialStore.slides.firstIndex(where: { $0.id == teacherActiveSlideID }) {
            initialActiveIndex = teacherActiveIndex
        } else {
            initialActiveIndex = initialStore.lastActiveSlideID.flatMap { slideID in
                initialStore.slides.firstIndex { $0.id == slideID }
            } ?? 0
        }
        _store = State(initialValue: initialStore)
        _classroomMode = classroomMode
        _isFollowMeEnabled = isFollowMeEnabled
        _activeIndex = State(initialValue: initialActiveIndex)
        _isStudentFollowMeActive = State(initialValue: initialTeacherSlideManifestSnapshot?.isFollowMeEnabled ?? false)
        _appliedTeacherSlideManifestUpdateID = State(initialValue: appliedInitialTeacherSlideManifestUpdateID)
        _appliedTeacherObjectSnapshotsUpdateID = State(initialValue: appliedInitialTeacherObjectSnapshotsUpdateID)
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            activeCanvasLayer

            liveTeacherInkOverlay

            studentCoverMaskOverlay

            slideNavigatorLayer
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
            if let activeSlide {
                store.saveLastActiveSlide(activeSlide.id)
            }
            onActiveWidgetIDsChanged?([])
            onActiveWidgetsChanged?([])
            scheduleReceivedTeacherInkPersistenceForStudentCopy()
            inkDrawingSnapshotSaveTask?.cancel()
            inkDrawingSnapshotSaveTask = nil
            objectSnapshotSaveTasksBySlideID.values.forEach { $0.cancel() }
            objectSnapshotSaveTasksBySlideID = [:]
            // Flush any pending master propagation before the lesson closes.
            // The child canvas view disappears before SlidesView, so PencilKit
            // will have already flushed its pending drawing save by this point.
            let hadPendingPropagation = lessonContentPropagationTask != nil
            lessonContentPropagationTask?.cancel()
            lessonContentPropagationTask = nil
            if hadPendingPropagation {
                onLessonContentChanged?()
            }
            liveTeacherInkCoordinator.onPublishedTeacherInkChunk = nil
            liveTeacherInkCoordinator.onPublishedTeacherInkDrawingSnapshot = nil
            liveTeacherInkCoordinator.onPublishedTeacherObjectSnapshot = nil
            liveTeacherInkCoordinator.onPublishedTeacherSlideManifestSnapshot = nil
            liveTeacherInkCoordinator.onReceivedTeacherInkDrawingSnapshot = nil
            liveTeacherInkCoordinator.onReceivedTeacherObjectSnapshot = nil
            liveTeacherInkCoordinator.onReceivedTeacherSlideManifestSnapshot = nil
            liveTeacherInkCoordinator.stop()
            flushPendingViewportSave()
        }
        .onAppear {
            publishActiveWidgetIDs()
            liveTeacherInkCoordinator.onPublishedTeacherInkChunk = onTeacherInkChunkPublished
            liveTeacherInkCoordinator.onPublishedTeacherInkDrawingSnapshot = onTeacherInkDrawingSnapshotPublished
            liveTeacherInkCoordinator.onPublishedTeacherObjectSnapshot = onTeacherObjectSnapshotPublished
            liveTeacherInkCoordinator.onPublishedTeacherSlideManifestSnapshot = onTeacherSlideManifestSnapshotPublished
            liveTeacherInkCoordinator.onReceivedTeacherInkDrawingSnapshot = applyTeacherInkDrawingSnapshot
            liveTeacherInkCoordinator.onReceivedTeacherObjectSnapshot = applyTeacherObjectSnapshot
            liveTeacherInkCoordinator.onReceivedTeacherSlideManifestSnapshot = applyTeacherSlideManifestSnapshot
            liveTeacherInkCoordinator.configure(liveClassroomConfiguration)
            liveTeacherInkCoordinator.seedInitialInkDrawingSnapshots(initialTeacherInkDrawingSnapshots)
            publishTeacherSlideManifestSnapshot()
        }
        .onChange(of: liveClassroomConfiguration) { _, newConfiguration in
            liveTeacherInkCoordinator.onPublishedTeacherInkChunk = onTeacherInkChunkPublished
            liveTeacherInkCoordinator.onPublishedTeacherInkDrawingSnapshot = onTeacherInkDrawingSnapshotPublished
            liveTeacherInkCoordinator.onPublishedTeacherObjectSnapshot = onTeacherObjectSnapshotPublished
            liveTeacherInkCoordinator.onPublishedTeacherSlideManifestSnapshot = onTeacherSlideManifestSnapshotPublished
            liveTeacherInkCoordinator.onReceivedTeacherObjectSnapshot = applyTeacherObjectSnapshot
            liveTeacherInkCoordinator.onReceivedTeacherSlideManifestSnapshot = applyTeacherSlideManifestSnapshot
            liveTeacherInkCoordinator.configure(newConfiguration)
            liveTeacherInkCoordinator.seedInitialInkDrawingSnapshots(initialTeacherInkDrawingSnapshots)
            publishTeacherSlideManifestSnapshot()
        }
        .onChange(of: classroomSessionCode) { oldSessionCode, newSessionCode in
            // Switching from master (nil) to a class session — immediately flush
            // any buffered master propagation so the class canvas loads from
            // already-propagated disk state rather than a snapshot that's still
            // waiting for the 900 ms debounce to expire.
            // Widget and object saves are synchronous, so they're already on disk.
            // The pending 900 ms task is left running as a safety net for any ink
            // strokes that may still be within their own 400 ms debounce window.
            if oldSessionCode == nil, newSessionCode != nil {
                onLessonContentChanged?()
            }
            reloadClassroomSessionStore(for: newSessionCode)
            publishActiveWidgetIDs()
            publishTeacherSlideManifestSnapshot()
        }
        .task(id: teacherSlideManifestUpdateID) {
            applyInitialTeacherSlideManifestSnapshotIfNeeded()
        }
        .task(id: teacherObjectSnapshotsUpdateID) {
            applyInitialTeacherObjectSnapshotsIfNeeded()
        }
        .onChange(of: activeSlide?.id) { _, _ in
            publishActiveWidgetIDs()
            publishTeacherSlideManifestSnapshot()
        }
        .onChange(of: isFollowMeEnabled) { _, _ in
            publishTeacherSlideManifestSnapshot()
        }
        .onChange(of: isStudentFollowMeActive) { _, isActive in
            if isActive { isShowingFilmstrip = false }
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

    @ViewBuilder
    private var activeCanvasLayer: some View {
        if let slide = activeSlide {
            presentingCanvas(for: slide)
        }
    }

    private func presentingCanvas(for slide: SlideMetadata) -> some View {
        let viewportChange: (@MainActor (PresentationViewportState) -> Void)? = isEditingLocked ? nil : { @MainActor state in
            scheduleViewportSave(state, for: slide.id)
        }
        let extractedRegionSend: (@MainActor (PresentationExtractedRegion) -> Void)? = isEditingLocked ? nil : { @MainActor region in
            sendExtractedRegionToNextEmptySlide(region)
        }
        let pdfImport: (@MainActor () -> Void)? = isEditingLocked ? nil : { @MainActor in
            isShowingPDFImporter = true
        }
        let pdfObjectImport: (@MainActor (URL, [Int]) -> Void)? = isEditingLocked ? nil : { @MainActor pdfURL, pageIndices in
            importPDFPagesAsCanvasObjects(pdfURL: pdfURL, pageIndices: pageIndices)
        }
        let drawingDataChange: (@MainActor (Data) -> Void)? = isEditingLocked ? nil : { @MainActor drawingData in
            scheduleTeacherInkDrawingSnapshotPublish(drawingData, for: slide)
            notifyLessonContentChanged(slideID: slide.id)
        }
        let objectStateChange: (@MainActor () -> Void)? = isEditingLocked ? nil : { @MainActor in
            scheduleTeacherObjectSnapshotPublish(for: slide)
            notifyLessonContentChanged(slideID: slide.id)
        }

        return PresentingCanvasView(
            drawingURL: canvasDrawingURL(for: slide),
            background: canvasBackground(for: slide.background),
            initialViewportState: presentationViewportState(for: slide),
            onViewportStateChange: viewportChange,
            onInteractionBegan: handleCanvasInteractionBegan,
            onTextEditingBegan: handleCanvasTextEditingBegan,
            onTextEditingEnded: handleCanvasTextEditingEnded,
            onExtractedRegionSend: extractedRegionSend,
            onImportPDF: pdfImport,
            onImportPDFObjects: pdfObjectImport,
            onExportPDF: {
                flushPendingViewportSave()
                isShowingPDFExporter = true
            },
            onViewportSourceRectChange: { sourceRect in
                currentViewportSourceRect = sourceRect
            },
            onLiveStrokeUpdate: { stroke in
                liveTeacherInkCoordinator.publishTeacherStroke(stroke, slideID: slide.id)
            },
            onDrawingDataChange: drawingDataChange,
            onCanvasObjectStateChange: objectStateChange,
            onLibraryDrawerOpenChange: { isOpen in
                onLibraryDrawerOpenChange?(isOpen)
            },
            objectStateReloadCommand: objectStateReloadCommand,
            allowsWidgetAuthoring: !isEditingLocked && classroomMode.allowsWidgetAuthoring,
            isEditingLocked: isEditingLocked
        )
        .id(canvasViewIdentity(for: slide))
    }

    @ViewBuilder
    private var slideNavigatorLayer: some View {
        if !isTextEditingOnCanvas && !isStudentFollowMeActive {
            SlideNavigatorView(
                slides: store.slides,
                currentIndex: activeIndex,
                isFilmstripOpen: $isShowingFilmstrip,
                thumbnail: thumbnail(for:),
                onGoTo: goToSlide,
                onPrevious: goToPrevious,
                onNext: goToNext,
                onAdd: addSlide,
                onMoveSlides: moveSlides(at:by:),
                onDeleteSlides: requestDeleteSlides(at:),
                allowsEditing: !isEditingLocked
            )
            .padding(.trailing, 16)
            .padding(.bottom, 14)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var activeSlide: SlideMetadata? {
        guard activeIndex >= 0, activeIndex < store.slides.count else { return nil }
        return store.slides[activeIndex]
    }

    private var teacherSlideManifestUpdateID: String {
        guard let initialTeacherSlideManifestSnapshot else { return "none" }
        return Self.teacherSlideManifestUpdateID(for: initialTeacherSlideManifestSnapshot)
    }

    private var teacherObjectSnapshotsUpdateID: String {
        Self.teacherObjectSnapshotsUpdateID(for: initialTeacherObjectSnapshots)
    }

    private static func teacherSlideManifestUpdateID(for snapshot: TeacherSlideManifestSnapshot) -> String {
        var parts = [
            snapshot.id.uuidString,
            snapshot.lessonCode,
            "\(snapshot.revision)",
            snapshot.activeSlideID?.uuidString ?? "no-active",
            "\(snapshot.slides.count)"
        ]
        for slide in snapshot.slides {
            parts.append(slide.id.uuidString)
            parts.append(slide.background?.kind ?? "no-background")
            parts.append(slide.background?.assetFileName ?? "")
            parts.append("\(slide.background?.pageIndex ?? -1)")
            parts.append(slide.background?.assetStoragePath ?? "")
            parts.append("\(slide.background?.assetBase64Data?.count ?? 0)")
        }
        return parts.joined(separator: "|")
    }

    private static func teacherObjectSnapshotsUpdateID(
        for snapshots: [TeacherObjectSnapshot],
        availableSlideIDs: Set<UUID>? = nil
    ) -> String {
        let applicableSnapshots = snapshots
            .filter { snapshot in
                availableSlideIDs?.contains(snapshot.slideID) ?? true
            }
            .sorted(by: teacherObjectSnapshotSort)
        var parts = ["\(applicableSnapshots.count)"]
        for snapshot in applicableSnapshots {
            parts.append(snapshot.slideID.uuidString)
            parts.append("\(snapshot.revision)")
            parts.append("\(snapshot.snapshot.sidecarFiles.count)")
            parts.append("\(snapshot.snapshot.imageAssetFiles.count)")
            parts.append("\(snapshot.snapshot.sidecarFiles.reduce(0) { $0 + $1.base64Data.count })")
            parts.append("\(snapshot.snapshot.imageAssetFiles.reduce(0) { $0 + $1.base64Data.count })")
        }
        return parts.joined(separator: "|")
    }

    private static func teacherObjectSnapshotSort(_ first: TeacherObjectSnapshot, _ second: TeacherObjectSnapshot) -> Bool {
        if first.slideID == second.slideID {
            return first.revision < second.revision
        }
        return first.sentAt < second.sentAt
    }

    private func applyInitialTeacherSlideManifestSnapshotIfNeeded() {
        guard classroomMode == .student,
              let initialTeacherSlideManifestSnapshot else { return }
        let updateID = Self.teacherSlideManifestUpdateID(for: initialTeacherSlideManifestSnapshot)
        guard appliedTeacherSlideManifestUpdateID != updateID else { return }
        appliedTeacherSlideManifestUpdateID = updateID
        mergeTeacherSlideManifestSnapshot(initialTeacherSlideManifestSnapshot)
    }

    private func applyInitialTeacherObjectSnapshotsIfNeeded() {
        guard classroomMode == .student else { return }
        let availableSlideIDs = Set(store.slides.map(\.id))
        let applicableSnapshots = initialTeacherObjectSnapshots
            .filter { availableSlideIDs.contains($0.slideID) }
            .sorted(by: Self.teacherObjectSnapshotSort)
        let updateID = Self.teacherObjectSnapshotsUpdateID(
            for: applicableSnapshots,
            availableSlideIDs: availableSlideIDs
        )
        guard appliedTeacherObjectSnapshotsUpdateID != updateID else { return }
        appliedTeacherObjectSnapshotsUpdateID = updateID
        for snapshot in applicableSnapshots {
            applyTeacherObjectSnapshot(snapshot)
        }
    }

    private func canvasDrawingURL(for slide: SlideMetadata) -> URL {
        store.drawingURL(
            for: slide,
            classroomSessionCode: classroomMode == .teacher ? classroomSessionCode : nil
        )
    }

    private func canvasViewIdentity(for slide: SlideMetadata) -> String {
        let backgroundIdentity = slide.background.map { background in
            "\(background.kind.rawValue)|\(background.assetFileName)|\(background.pageIndex)"
        } ?? "no-background"
        return "\(slide.id.uuidString)|\(canvasDrawingURL(for: slide).path)|\(backgroundIdentity)|\(canvasRefreshToken.uuidString)"
    }

    private func reloadClassroomSessionStore(for sessionCode: String?) {
        guard classroomMode == .teacher else { return }
        flushPendingViewportSave()
        if let activeSlide {
            store.saveLastActiveSlide(activeSlide.id)
        }
        store = SlideStore(lessonURL: lessonURL, classroomSessionCode: sessionCode)
        if let lastID = store.lastActiveSlideID,
           let savedIndex = store.slides.firstIndex(where: { $0.id == lastID }) {
            activeIndex = savedIndex
        } else {
            activeIndex = 0
        }
        thumbnailCache.thumbnails = [:]
        objectStateReloadCommand = CanvasObjectCommand(.reloadObjectState)
        inkDrawingSnapshotRevisionsBySlideID = [:]
        objectSnapshotRevisionsBySlideID = [:]
    }

    @ViewBuilder
    private var liveTeacherInkOverlay: some View {
        if liveClassroomConfiguration?.role == .student,
           let activeSlide {
            let snapshot = liveTeacherInkCoordinator.latestInkDrawingSnapshotsBySlideID[activeSlide.id]
            let strokes = liveTeacherInkCoordinator.receivedStrokes(for: activeSlide.id)
            if snapshot != nil || !strokes.isEmpty {
                GeometryReader { proxy in
                    ZStack {
                        #if os(iOS)
                        if let snapshot {
                            LiveTeacherInkDrawingSnapshotOverlay(
                                snapshot: snapshot,
                                viewportSourceRect: currentViewportSourceRect,
                                fallbackSourceSize: CanvasBoardMetrics.defaultUsableSize,
                                fittedSize: proxy.size
                            )
                        }
                        #endif

                        if !strokes.isEmpty {
                            LiveTeacherInkOverlay(
                                strokes: strokes,
                                viewportSourceRect: currentViewportSourceRect,
                                fallbackSourceSize: CanvasBoardMetrics.defaultUsableSize,
                                fittedSize: proxy.size
                            )
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .zIndex(0.5)
            }
        }
    }

    @ViewBuilder
    private var studentCoverMaskOverlay: some View {
        if liveClassroomConfiguration?.role == .student,
           let activeSlide {
            let covers = CanvasCoverObject.load(
                from: CanvasCoverObject.sidecarURL(forDrawingURL: canvasDrawingURL(for: activeSlide))
            ).filter { !$0.isRevealed }
            if !covers.isEmpty {
                GeometryReader { proxy in
                    StudentCoverMaskOverlay(
                        coverObjects: covers,
                        viewportSourceRect: currentViewportSourceRect,
                        fallbackSourceSize: CanvasBoardMetrics.defaultUsableSize,
                        fittedSize: proxy.size
                    )
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .zIndex(0.6)
            }
        }
    }

    private func publishActiveWidgetIDs() {
        guard let activeSlide else {
            onActiveWidgetIDsChanged?([])
            onActiveWidgetsChanged?([])
            return
        }
        let widgetSidecarURL = WidgetObject.sidecarURL(forDrawingURL: canvasDrawingURL(for: activeSlide))
        let activeWidgets = WidgetObject.load(from: widgetSidecarURL)
        onActiveWidgetIDsChanged?(Set(activeWidgets.map(\.id)))
        onActiveWidgetsChanged?(activeWidgets)
    }

    private static func mergeInitialTeacherSlideManifestSnapshot(
        _ snapshot: TeacherSlideManifestSnapshot,
        into store: SlideStore
    ) {
        let wroteBackgroundAssets = writeTeacherSlideBackgroundAssets(snapshot.slides, into: store)
        guard !hasUnhydratedBackgroundAssets(in: snapshot) else {
            print("[Slides] skipped initial teacher slide manifest revision=\(snapshot.revision) because background assets are not hydrated")
            return
        }
        guard !hasMissingLocalBackgroundAssets(for: snapshot, in: store) else {
            print("[Slides] skipped initial teacher slide manifest revision=\(snapshot.revision) because local background files are missing")
            return
        }
        let teacherSlides = snapshot.slides.map(SlideMetadata.init(teacherSlide:))
        let changed = store.mergeTeacherSlides(teacherSlides)
        if changed || wroteBackgroundAssets {
            print("[Slides] merged initial teacher slide manifest revision=\(snapshot.revision) slides=\(snapshot.slides.count)")
        }
    }

    @discardableResult
    private static func writeTeacherSlideBackgroundAssets(_ slides: [TeacherSlideMetadata], into store: SlideStore) -> Bool {
        let fileManager = FileManager.default
        var didWriteAsset = false
        for teacherSlide in slides {
            guard let teacherBackground = teacherSlide.background,
                  let slideBackground = SlideBackground(teacherBackground: teacherBackground),
                  let assetBase64Data = teacherBackground.assetBase64Data,
                  let assetData = Data(base64Encoded: assetBase64Data) else {
                continue
            }

            let assetURL = store.backgroundURL(for: slideBackground)
            do {
                try fileManager.createDirectory(at: assetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try assetData.write(to: assetURL, options: .atomic)
                print("[Slides] wrote teacher background asset slide=\(teacherSlide.id) file=\(slideBackground.assetFileName) bytes=\(assetData.count)")
                didWriteAsset = true
            } catch {
                print("[Slides] teacher slide background asset merge error: \(error)")
            }
        }
        return didWriteAsset
    }

    private static func writeTeacherInkDrawingSnapshots(_ snapshots: [TeacherInkDrawingSnapshot], into store: SlideStore) {
        let latestSnapshots = Dictionary(grouping: snapshots, by: \.slideID).compactMapValues { slideSnapshots in
            slideSnapshots.max { first, second in
                if first.revision == second.revision {
                    return first.sentAt < second.sentAt
                }
                return first.revision < second.revision
            }
        }
        guard !latestSnapshots.isEmpty else { return }

        for slide in store.slides {
            guard let snapshot = latestSnapshots[slide.id],
                  let drawingData = Data(base64Encoded: snapshot.drawingDataBase64) else {
                continue
            }
            let drawingURL = store.drawingURL(for: slide)
            do {
                try FileManager.default.createDirectory(at: drawingURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try drawingData.write(to: drawingURL, options: .atomic)
            } catch {
                print("[Slides] teacher ink snapshot write error: \(error)")
            }
        }
    }

    private static func mergeInitialTeacherObjectSnapshots(_ snapshots: [TeacherObjectSnapshot], into store: SlideStore) {
        let latestSnapshots = Dictionary(grouping: snapshots, by: \.slideID).compactMapValues { slideSnapshots in
            slideSnapshots.max { first, second in
                if first.revision == second.revision {
                    return first.sentAt < second.sentAt
                }
                return first.revision < second.revision
            }
        }
        guard !latestSnapshots.isEmpty else { return }

        for slide in store.slides {
            guard let snapshot = latestSnapshots[slide.id] else { continue }
            do {
                let drawingURL = store.drawingURL(for: slide)
                let preserving: Set<String> = snapshot.snapshot.sidecarFiles.contains { $0.name == "widgets.json" }
                    ? []
                    : ["widgets.json"]
                try studentMergedObjectSnapshot(
                    snapshot.snapshot,
                    drawingURL: drawingURL
                ).write(to: drawingURL, preserving: preserving)
            } catch {
                print("[Slides] initial teacher object merge error: \(error)")
            }
        }
    }

    private static func studentMergedObjectSnapshot(
        _ snapshot: CanvasObjectSnapshot,
        drawingURL: URL
    ) -> CanvasObjectSnapshot {
        guard let widgetsFile = snapshot.sidecarFiles.first(where: { $0.name == "widgets.json" }),
              let widgetsData = widgetsFile.data,
              let teacherWidgets = try? JSONDecoder().decode([WidgetObject].self, from: widgetsData) else {
            return snapshot
        }

        let localWidgets = WidgetObject.load(from: WidgetObject.sidecarURL(forDrawingURL: drawingURL))
        let localWidgetsByID = Dictionary(uniqueKeysWithValues: localWidgets.map { ($0.id, $0) })
        let mergedWidgets = teacherWidgets.map { teacherWidget -> WidgetObject in
            guard let localWidget = localWidgetsByID[teacherWidget.id] else { return teacherWidget }
            var mergedWidget = teacherWidget
            mergedWidget.activityRuntimeState = localWidget.activityRuntimeState
            mergedWidget.builtInRuntimeState = localWidget.builtInRuntimeState
            return mergedWidget
        }
        guard let mergedData = try? JSONEncoder().encode(mergedWidgets) else { return snapshot }

        var mergedSnapshot = snapshot
        mergedSnapshot.sidecarFiles.removeAll { $0.name == "widgets.json" }
        mergedSnapshot.sidecarFiles.append(CanvasObjectSnapshotFile(name: "widgets.json", data: mergedData))
        return mergedSnapshot
    }

    private static func mergeInitialTeacherInkChunks(_ chunks: [TeacherInkStrokeChunk], into store: SlideStore) {
        #if os(iOS)
        let chunksBySlideID = Dictionary(grouping: chunks.filter(\.isFinalChunk), by: \.slideID)
        guard !chunksBySlideID.isEmpty else { return }

        for slide in store.slides {
            guard let slideChunks = chunksBySlideID[slide.id], !slideChunks.isEmpty else { continue }
            do {
                _ = try CanvasLiveInkPersistence.mergeLiveInkStrokes(
                    slideChunks.map(\.canvasLiveStroke),
                    strokeIDs: slideChunks.map(\.strokeID),
                    into: store.drawingURL(for: slide)
                )
            } catch {
                print("[Slides] initial teacher ink merge error: \(error)")
            }
        }
        #endif
    }

    private func scheduleTeacherInkDrawingSnapshotPublish(_ drawingData: Data, for slide: SlideMetadata) {
        guard liveClassroomConfiguration?.role == .teacher else { return }
        inkDrawingSnapshotSaveTask?.cancel()
        inkDrawingSnapshotSaveTask = Task { @MainActor in
            try? await Task.sleep(for: Self.inkDrawingSnapshotDebounce)
            guard !Task.isCancelled else { return }
            publishTeacherInkDrawingSnapshot(drawingData, for: slide)
        }
    }

    private func publishTeacherInkDrawingSnapshot(_ drawingData: Data, for slide: SlideMetadata) {
        let revision = nextLiveRevision(after: inkDrawingSnapshotRevisionsBySlideID[slide.id] ?? 0)
        inkDrawingSnapshotRevisionsBySlideID[slide.id] = revision
        liveTeacherInkCoordinator.publishTeacherInkDrawingSnapshot(
            drawingData: drawingData,
            slideID: slide.id,
            revision: revision
        )
    }

    private func scheduleTeacherObjectSnapshotPublish(for slide: SlideMetadata) {
        guard liveClassroomConfiguration?.role == .teacher else { return }
        objectSnapshotSaveTasksBySlideID[slide.id]?.cancel()
        objectSnapshotSaveTasksBySlideID[slide.id] = Task { @MainActor in
            try? await Task.sleep(for: Self.objectSnapshotDebounce)
            guard !Task.isCancelled else { return }
            objectSnapshotSaveTasksBySlideID[slide.id] = nil
            publishTeacherObjectSnapshot(for: slide)
        }
    }

    private func publishTeacherObjectSnapshot(for slide: SlideMetadata) {
        let revision = nextLiveRevision(after: objectSnapshotRevisionsBySlideID[slide.id] ?? 0)
        objectSnapshotRevisionsBySlideID[slide.id] = revision
        let snapshot = CanvasObjectSnapshot.capture(
            slideID: slide.id,
            drawingURL: canvasDrawingURL(for: slide),
            revision: revision
        )
        liveTeacherInkCoordinator.publishTeacherObjectSnapshot(snapshot, slideID: slide.id, revision: revision)
    }

    private func publishTeacherSlideManifestSnapshot() {
        guard liveClassroomConfiguration?.role == .teacher else { return }
        slideManifestRevision = nextLiveRevision(after: slideManifestRevision)
        liveTeacherInkCoordinator.publishTeacherSlideManifestSnapshot(
            revision: slideManifestRevision,
            slides: store.slides.map(teacherSlideMetadata(for:)),
            activeSlideID: activeSlide?.id,
            isFollowMeEnabled: isFollowMeEnabled
        )
    }

    private func teacherSlideMetadata(for slide: SlideMetadata) -> TeacherSlideMetadata {
        let background = slide.background.map { slideBackground in
            TeacherSlideBackground(
                background: slideBackground,
                assetData: try? Data(contentsOf: store.backgroundURL(for: slideBackground))
            )
        }
        return TeacherSlideMetadata(
            id: slide.id,
            createdAt: slide.createdAt,
            viewport: slide.viewport.map(TeacherSlideViewport.init(viewport:)),
            background: background
        )
    }

    private func nextLiveRevision(after currentRevision: Int) -> Int {
        let timestampRevision = Int((Date().timeIntervalSince1970 * 1000).rounded())
        return max(currentRevision + 1, timestampRevision)
    }

    private func applyTeacherSlideManifestSnapshot(_ snapshot: TeacherSlideManifestSnapshot) {
        guard liveClassroomConfiguration?.role == .student else { return }
        print("[Slides] received live teacher slide manifest revision=\(snapshot.revision) slides=\(snapshot.slides.count) unhydrated=\(hasUnhydratedBackgroundAssets(in: snapshot)) missingLocal=\(hasMissingLocalBackgroundAssets(for: snapshot))")
        let needsDurableRefresh = scheduleDurableTeacherSlideManifestRefreshIfNeeded(for: snapshot)
        mergeTeacherSlideManifestSnapshot(snapshot, allowsPartialBackgroundMerge: needsDurableRefresh)
    }

    private func mergeTeacherSlideManifestSnapshot(
        _ snapshot: TeacherSlideManifestSnapshot,
        allowsPartialBackgroundMerge: Bool = false
    ) {
        let wroteBackgroundAssets = Self.writeTeacherSlideBackgroundAssets(snapshot.slides, into: store)
        let readySlides = allowsPartialBackgroundMerge
            ? Self.teacherSlidesWithAvailableBackgrounds(snapshot.slides, in: store)
            : snapshot.slides
        let readySlideIDs = Set(readySlides.map(\.id))
        let deferredSlideIDs = Set(snapshot.slides.map(\.id)).subtracting(readySlideIDs)
        let deferredPlaceholderSlideIDs = Self.deferredTeacherSlidePlaceholderIDs(
            in: store,
            deferredTeacherSlides: snapshot.slides.filter { deferredSlideIDs.contains($0.id) }
        )

        if !deferredSlideIDs.isEmpty {
            print("[Slides] partially merging teacher slide manifest revision=\(snapshot.revision) deferredBackgroundSlides=\(deferredSlideIDs.count)")
        }
        if readySlides.isEmpty && deferredPlaceholderSlideIDs.isEmpty {
            print("[Slides] teacher slide manifest revision=\(snapshot.revision) had no ready slides to merge")
            return
        }

        let previousActiveSlideID = activeSlide?.id
        let changed = store.mergeTeacherSlides(
            readySlides.map(SlideMetadata.init(teacherSlide:)),
            deferredTeacherSlideIDs: deferredPlaceholderSlideIDs
        )

        isStudentFollowMeActive = snapshot.isFollowMeEnabled
        if snapshot.isFollowMeEnabled,
           let teacherActiveSlideID = snapshot.activeSlideID,
           readySlideIDs.contains(teacherActiveSlideID),
           let newActiveIndex = store.slides.firstIndex(where: { $0.id == teacherActiveSlideID }) {
            activeIndex = newActiveIndex
        } else if let previousActiveSlideID,
                  let newActiveIndex = store.slides.firstIndex(where: { $0.id == previousActiveSlideID }) {
            activeIndex = newActiveIndex
        } else {
            activeIndex = min(activeIndex, max(store.slides.count - 1, 0))
        }

        let activeSlideChanged = previousActiveSlideID != activeSlide?.id
        guard changed || wroteBackgroundAssets || activeSlideChanged else {
            print("[Slides] teacher slide manifest revision=\(snapshot.revision) received with no metadata/background/active-slide change")
            return
        }

        thumbnailCache.thumbnails = [:]
        canvasRefreshToken = UUID()
        for objectSnapshot in liveTeacherInkCoordinator.latestObjectSnapshotsBySlideID.values {
            applyTeacherObjectSnapshot(objectSnapshot)
        }
        applyInitialTeacherObjectSnapshotsIfNeeded()
        publishActiveWidgetIDs()
    }

    private static func hasUnhydratedBackgroundAssets(in snapshot: TeacherSlideManifestSnapshot) -> Bool {
        snapshot.slides.contains { teacherSlide in
            guard let teacherBackground = teacherSlide.background else { return false }
            return teacherBackground.assetBase64Data == nil
        }
    }

    private func hasUnhydratedBackgroundAssets(in snapshot: TeacherSlideManifestSnapshot) -> Bool {
        Self.hasUnhydratedBackgroundAssets(in: snapshot)
    }

    private static func hasMissingLocalBackgroundAssets(for snapshot: TeacherSlideManifestSnapshot, in store: SlideStore) -> Bool {
        snapshot.slides.contains { teacherSlide in
            guard let teacherBackground = teacherSlide.background,
                  let slideBackground = SlideBackground(teacherBackground: teacherBackground) else {
                return false
            }
            return !FileManager.default.fileExists(atPath: store.backgroundURL(for: slideBackground).path)
        }
    }

    private func hasMissingLocalBackgroundAssets(for snapshot: TeacherSlideManifestSnapshot) -> Bool {
        Self.hasMissingLocalBackgroundAssets(for: snapshot, in: store)
    }

    private static func teacherSlidesWithAvailableBackgrounds(
        _ teacherSlides: [TeacherSlideMetadata],
        in store: SlideStore
    ) -> [TeacherSlideMetadata] {
        teacherSlides.filter { teacherSlide in
            guard let teacherBackground = teacherSlide.background,
                  let slideBackground = SlideBackground(teacherBackground: teacherBackground) else {
                return true
            }
            if teacherBackground.assetBase64Data != nil {
                return true
            }
            return FileManager.default.fileExists(atPath: store.backgroundURL(for: slideBackground).path)
        }
    }

    private static func deferredTeacherSlidePlaceholderIDs(
        in store: SlideStore,
        deferredTeacherSlides: [TeacherSlideMetadata]
    ) -> Set<UUID> {
        let deferredBackgroundsByID = Dictionary(
            uniqueKeysWithValues: deferredTeacherSlides.compactMap { teacherSlide -> (UUID, SlideBackground)? in
                guard let teacherBackground = teacherSlide.background,
                      let slideBackground = SlideBackground(teacherBackground: teacherBackground) else {
                    return nil
                }
                return (teacherSlide.id, slideBackground)
            }
        )

        return Set(store.slides.compactMap { localSlide in
            guard let deferredBackground = deferredBackgroundsByID[localSlide.id],
                  localSlide.background == deferredBackground else {
                return nil
            }
            return localSlide.id
        })
    }

    @discardableResult
    private func scheduleDurableTeacherSlideManifestRefreshIfNeeded(for snapshot: TeacherSlideManifestSnapshot) -> Bool {
        guard hasMissingLocalBackgroundAssets(for: snapshot),
              let onLiveTeacherSlideManifestRefreshRequested else {
            return false
        }

        Task { @MainActor in
            print("[Slides] waiting for durable teacher slide manifest revision=\(snapshot.revision)")
            for delay in [500, 1_500, 3_000, 6_000, 10_000, 15_000] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard let durableSnapshot = await onLiveTeacherSlideManifestRefreshRequested(snapshot),
                      durableSnapshot.revision >= snapshot.revision else {
                    print("[Slides] durable teacher slide manifest unavailable revision=\(snapshot.revision) delay=\(delay)ms")
                    continue
                }
                mergeTeacherSlideManifestSnapshot(durableSnapshot)
                if !hasUnhydratedBackgroundAssets(in: durableSnapshot),
                   !hasMissingLocalBackgroundAssets(for: durableSnapshot) {
                    break
                }
            }
        }
        return true
    }

    private func applyTeacherInkDrawingSnapshot(_ snapshot: TeacherInkDrawingSnapshot) {
        guard liveClassroomConfiguration?.role == .student else { return }
        _ = snapshot
        // The coordinator already keeps the latest teacher snapshot for the
        // overlay. Persisting it into the local slide drawing would overwrite
        // student-owned annotations on reopen.
    }

    private func applyTeacherObjectSnapshot(_ snapshot: TeacherObjectSnapshot) {
        guard liveClassroomConfiguration?.role == .student,
              let slide = store.slides.first(where: { $0.id == snapshot.slideID }) else {
            return
        }

        do {
            let drawingURL = canvasDrawingURL(for: slide)
            let preserving: Set<String> = snapshot.snapshot.sidecarFiles.contains { $0.name == "widgets.json" }
                ? []
                : ["widgets.json"]
            try Self.studentMergedObjectSnapshot(snapshot.snapshot, drawingURL: drawingURL)
                .write(to: drawingURL, preserving: preserving)
            print("[Slides] applied teacher object snapshot slide=\(slide.id) revision=\(snapshot.revision) sidecars=\(snapshot.snapshot.sidecarFiles.count) imageAssets=\(snapshot.snapshot.imageAssetFiles.count)")
            if activeSlide?.id == slide.id {
                objectStateReloadCommand = CanvasObjectCommand(.reloadObjectState)
                publishActiveWidgetIDs()
            }
        } catch {
            print("[Slides] live teacher object apply error: \(error)")
        }
    }

    private func scheduleReceivedTeacherInkPersistenceForStudentCopy() {
        guard liveClassroomConfiguration?.role == .student else { return }
        // Teacher ink persistence is handled by the class-level durable
        // snapshot in Firebase. The student's local drawing file must remain
        // reserved for that student's own PencilKit annotations.
    }

    private func goToPrevious() {
        guard !isStudentFollowMeActive else { return }
        guard activeIndex > 0 else { return }
        flushPendingViewportSave()
        activeIndex -= 1
    }

    private func goToNext() {
        guard !isStudentFollowMeActive else { return }
        guard activeIndex < store.slides.count - 1 else { return }
        flushPendingViewportSave()
        activeIndex += 1
    }

    private func goToSlide(_ index: Int) {
        guard !isStudentFollowMeActive else { return }
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

    private func notifyLessonContentChanged(slideID: UUID? = nil) {
        guard classroomMode == .teacher, !isEditingLocked else { return }

        if let slideID, classroomSessionCode != nil {
            SlideStore.markClassSessionSlideEdited(
                lessonURL: lessonURL,
                classroomSessionCode: classroomSessionCode,
                slideID: slideID
            )
            return
        }

        guard classroomSessionCode == nil else { return }
        lessonContentPropagationTask?.cancel()
        lessonContentPropagationTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            onLessonContentChanged?()
        }
    }

    private func markClassSessionSlidesEdited(_ slideIDs: [UUID]) {
        guard classroomMode == .teacher, classroomSessionCode != nil else { return }
        for slideID in slideIDs {
            SlideStore.markClassSessionSlideEdited(
                lessonURL: lessonURL,
                classroomSessionCode: classroomSessionCode,
                slideID: slideID
            )
        }
    }

    private func markClassSessionSlidesDeleted(_ slideIDs: [UUID]) {
        guard classroomMode == .teacher, classroomSessionCode != nil else { return }
        for slideID in slideIDs {
            SlideStore.markClassSessionSlideDeleted(
                lessonURL: lessonURL,
                classroomSessionCode: classroomSessionCode,
                slideID: slideID
            )
        }
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
        guard !isEditingLocked else { return }
        flushPendingViewportSave()
        do {
            let insertedSlides = try store.insertSlides(count: 1, afterSlideAt: activeIndex)
            activeIndex += 1
            publishTeacherSlideManifestSnapshot()
            notifyLessonContentChanged(slideID: insertedSlides.first?.id)
        } catch {
            slideErrorMessage = error.localizedDescription
        }
    }

    private func sendExtractedRegionToNextEmptySlide(_ region: PresentationExtractedRegion) {
        guard !isEditingLocked else { return }
        flushPendingViewportSave()
        do {
            let targetSlide: SlideMetadata
            if let emptyIndex = store.slides.indices.first(where: { index in
                index > activeIndex && isEmptyForExtractSend(store.slides[index])
            }) {
                targetSlide = store.slides[emptyIndex]
            } else {
                targetSlide = store.addSlide()
                publishTeacherSlideManifestSnapshot()
                notifyLessonContentChanged(slideID: targetSlide.id)
            }
            try placeExtractedRegion(region, on: targetSlide)
        } catch {
            slideErrorMessage = error.localizedDescription
        }
    }

    private func isEmptyForExtractSend(_ slide: SlideMetadata) -> Bool {
        guard slide.background == nil else { return false }
        let drawingURL = canvasDrawingURL(for: slide)
        if FileManager.default.fileExists(atPath: drawingURL.path) {
            return false
        }
        let textObjects = PresentationCanvasTextObject.load(from: PresentationCanvasTextObject.sidecarURL(forDrawingURL: drawingURL))
        let imageObjects = PresentationCanvasImageObject.load(from: PresentationCanvasImageObject.sidecarURL(forDrawingURL: drawingURL))
        let geometryObjects = PresentationCanvasGeometryObject.load(from: PresentationCanvasGeometryObject.sidecarURL(forDrawingURL: drawingURL))
        return textObjects.isEmpty && imageObjects.isEmpty && geometryObjects.isEmpty
    }

    private func placeExtractedRegion(_ region: PresentationExtractedRegion, on slide: SlideMetadata) throws {
        let drawingURL = canvasDrawingURL(for: slide)
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
        _ = try? LibraryRecentStore.record(
            title: Self.libraryRecentTitle("Extracted sticker"),
            kind: .extractedInk,
            thumbnailPNGData: region.pngData,
            forDrawingURL: drawingURL
        )
        scheduleTeacherObjectSnapshotPublish(for: slide)
        notifyLessonContentChanged(slideID: slide.id)
    }

    private static func libraryRecentTitle(_ baseTitle: String, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return "\(baseTitle) \(formatter.string(from: date))"
    }

    private func importPDFPagesAsCanvasObjects(pdfURL: URL, pageIndices: [Int]) {
        guard !isEditingLocked else { return }
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
            publishTeacherSlideManifestSnapshot()
            notifyLessonContentChanged()
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
        let drawingURL = canvasDrawingURL(for: slide)
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
        _ = try? LibraryRecentStore.record(
            title: Self.libraryRecentTitle("PDF page object"),
            kind: .image,
            thumbnailPNGData: page.pngData,
            forDrawingURL: drawingURL
        )
        scheduleTeacherObjectSnapshotPublish(for: slide)
        notifyLessonContentChanged(slideID: slide.id)
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
        guard !isEditingLocked else { return }
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
        guard !isEditingLocked else { return }
        do {
            flushPendingViewportSave()
            let result = try store.importPDF(
                from: pendingImport.url,
                pageIndices: pageIndices,
                afterSlideAt: activeIndex,
                reuseCurrentSlideIfBlank: true
            )
            activeIndex = result.startIndex
            thumbnailCache.thumbnails = [:]
            canvasRefreshToken = UUID()
            publishTeacherSlideManifestSnapshot()
            let importedSlideIDs = (result.startIndex..<(result.startIndex + result.slides.count)).compactMap { index in
                store.slides.indices.contains(index) ? store.slides[index].id : nil
            }
            for slideID in importedSlideIDs {
                notifyLessonContentChanged(slideID: slideID)
            }
            notifyLessonContentChanged()
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
            drawingURL: canvasDrawingURL(for:),
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
        guard !isEditingLocked else { return }
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
        guard !isEditingLocked else { return }
        guard let indices = pendingDeleteIndices else { return }
        pendingDeleteIndices = nil
        flushPendingViewportSave()

        let doomed = Set(indices)
        let deletedSlideIDs = indices.compactMap { index in
            store.slides.indices.contains(index) ? store.slides[index].id : nil
        }
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
            markClassSessionSlidesDeleted(deletedSlideIDs)
            publishTeacherSlideManifestSnapshot()
            notifyLessonContentChanged()
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
        guard !isEditingLocked else { return }
        guard !indices.isEmpty else { return }
        flushPendingViewportSave()
        let currentID = activeSlide?.id
        let movedSlideIDs = indices.compactMap { index in
            store.slides.indices.contains(index) ? store.slides[index].id : nil
        }

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
        markClassSessionSlidesEdited(movedSlideIDs)
        publishTeacherSlideManifestSnapshot()
        notifyLessonContentChanged()
    }

    /// Static slide preview for the navigator filmstrip, cached by persisted
    /// slide-file fingerprints so scrolling doesn't re-render every tile.
    private func thumbnail(for slide: SlideMetadata) -> SlideNavigatorThumbnail {
        let drawingURL = canvasDrawingURL(for: slide)
        let key = SlideThumbnailRenderer.cacheKey(
            for: slide,
            drawingURL: drawingURL,
            backgroundURL: store.backgroundURL(for:)
        )
        if let cached = thumbnailCache.thumbnails[key] {
            return cached
        }

        let content = SlideThumbnailRenderer.content(
            for: slide,
            drawingURL: drawingURL,
            backgroundURL: store.backgroundURL(for:)
        )
        let thumbnail = SlideNavigatorThumbnail(
            image: content.image,
            widgetKind: content.widgetKind
        )
        thumbnailCache.thumbnails[key] = thumbnail
        return thumbnail
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
        guard viewport.isUsableSavedCanvasViewport() else { return false }

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
    var thumbnails: [String: SlideNavigatorThumbnail] = [:]
}

private extension SlideViewportState {
    func isApproximatelyEqual(to other: SlideViewportState) -> Bool {
        platform == other.platform
            && abs(zoomScale - other.zoomScale) < 0.0001
            && abs(contentOffsetX - other.contentOffsetX) < 0.5
            && abs(contentOffsetY - other.contentOffsetY) < 0.5
    }
}

private extension TeacherSlideMetadata {
    init(slide: SlideMetadata) {
        self.init(
            id: slide.id,
            createdAt: slide.createdAt,
            viewport: slide.viewport.map(TeacherSlideViewport.init(viewport:)),
            background: slide.background.map(TeacherSlideBackground.init(background:))
        )
    }
}

private extension TeacherSlideViewport {
    init(viewport: SlideViewportState) {
        self.init(
            zoomScale: viewport.zoomScale,
            contentOffsetX: viewport.contentOffsetX,
            contentOffsetY: viewport.contentOffsetY,
            platform: viewport.platform
        )
    }
}

private extension TeacherSlideBackground {
    init(background: SlideBackground) {
        self.init(background: background, assetData: nil)
    }

    init(background: SlideBackground, assetData: Data?) {
        self.init(
            kind: background.kind.rawValue,
            assetFileName: background.assetFileName,
            pageIndex: background.pageIndex,
            assetBase64Data: assetData?.base64EncodedString()
        )
    }
}

private extension SlideMetadata {
    init(teacherSlide: TeacherSlideMetadata) {
        self.init(
            id: teacherSlide.id,
            createdAt: teacherSlide.createdAt,
            viewport: teacherSlide.viewport.map(SlideViewportState.init(teacherViewport:)),
            background: teacherSlide.background.flatMap(SlideBackground.init(teacherBackground:))
        )
    }
}

private extension SlideViewportState {
    init(teacherViewport: TeacherSlideViewport) {
        self.init(
            zoomScale: teacherViewport.zoomScale,
            contentOffsetX: teacherViewport.contentOffsetX,
            contentOffsetY: teacherViewport.contentOffsetY,
            platform: teacherViewport.platform
        )
    }
}

private extension SlideBackground {
    init?(teacherBackground: TeacherSlideBackground) {
        guard let kind = Kind(rawValue: teacherBackground.kind) else { return nil }
        self.init(
            kind: kind,
            assetFileName: teacherBackground.assetFileName,
            pageIndex: teacherBackground.pageIndex
        )
    }
}
