//
//  LiveTeacherInkCoordinator.swift
//  MathBoardCore - LiveClassroom module
//

import Canvas
import Foundation
import Observation

@MainActor
@Observable
public final class LiveTeacherInkCoordinator {
    public typealias SessionFactory = @MainActor (LiveClassroomSessionConfiguration) -> any LiveClassroomSessioning

    public private(set) var latestChunksByStrokeID: [UUID: TeacherInkStrokeChunk] = [:]
    public private(set) var latestInkDrawingSnapshotsBySlideID: [UUID: TeacherInkDrawingSnapshot] = [:]
    public private(set) var latestObjectSnapshotsBySlideID: [UUID: TeacherObjectSnapshot] = [:]
    public private(set) var latestSlideManifestSnapshot: TeacherSlideManifestSnapshot?
    public private(set) var receivedStrokeOrder: [UUID] = []
    public private(set) var lastErrorMessage: String?
    public var onPublishedTeacherInkChunk: ((TeacherInkStrokeChunk) -> Void)?
    public var onPublishedTeacherInkDrawingSnapshot: ((TeacherInkDrawingSnapshot) -> Void)?
    public var onPublishedTeacherObjectSnapshot: ((TeacherObjectSnapshot) -> Void)?
    public var onPublishedTeacherSlideManifestSnapshot: ((TeacherSlideManifestSnapshot) async throws -> Void)?
    public var onReceivedTeacherInkDrawingSnapshot: ((TeacherInkDrawingSnapshot) -> Void)?
    public var onReceivedTeacherObjectSnapshot: ((TeacherObjectSnapshot) -> Void)?
    public var onReceivedTeacherSlideManifestSnapshot: ((TeacherSlideManifestSnapshot) -> Void)?

    public static let defaultPublishInterval: Duration = .milliseconds(85)
    public static let maximumTransportPointCount = TeacherInkStrokeChunk.maximumPointCount

    private static let maximumReceivedStrokeCount = 800

    private var configuration: LiveClassroomSessionConfiguration?
    private var session: (any LiveClassroomSessioning)?
    private let publishInterval: Duration
    private let sessionFactory: SessionFactory
    private var activeStrokeID = UUID()
    private var activeSequence = 0
    private var lastPublishedStroke: CanvasLiveStroke?
    private var lastPublishedSlideID: UUID?
    private var pendingStroke: CanvasLiveStroke?
    private var pendingSlideID: UUID?
    private var pendingPublishTask: Task<Void, Never>?

    public init(
        publishInterval: Duration = LiveTeacherInkCoordinator.defaultPublishInterval,
        sessionFactory: @escaping SessionFactory = { AblyLiveClassroomSession(configuration: $0) }
    ) {
        self.publishInterval = publishInterval
        self.sessionFactory = sessionFactory
    }

    public func configure(_ newConfiguration: LiveClassroomSessionConfiguration?) {
        guard configuration != newConfiguration else { return }
        session?.stop()
        session = nil
        configuration = newConfiguration
        latestChunksByStrokeID = [:]
        latestInkDrawingSnapshotsBySlideID = [:]
        latestObjectSnapshotsBySlideID = [:]
        latestSlideManifestSnapshot = nil
        receivedStrokeOrder = []
        lastErrorMessage = nil
        activeStrokeID = UUID()
        activeSequence = 0
        lastPublishedStroke = nil
        lastPublishedSlideID = nil
        pendingStroke = nil
        pendingSlideID = nil
        pendingPublishTask?.cancel()
        pendingPublishTask = nil

        guard let newConfiguration else { return }
        let newSession = sessionFactory(newConfiguration)
        newSession.onTeacherInkChunk = { [weak self] chunk in
            self?.receive(chunk)
        }
        newSession.onTeacherInkDrawingSnapshot = { [weak self] snapshot in
            self?.receive(snapshot)
        }
        newSession.onTeacherObjectSnapshot = { [weak self] snapshot in
            self?.receive(snapshot)
        }
        newSession.onTeacherSlideManifestSnapshot = { [weak self] snapshot in
            self?.receive(snapshot)
        }
        session = newSession
        newSession.start()
    }

    public func stop() {
        configure(nil)
    }

    public func publishTeacherStroke(_ stroke: CanvasLiveStroke?, slideID: UUID) {
        guard let configuration,
              configuration.role == .teacher,
              let session else {
            return
        }

        if let stroke {
            if lastPublishedStroke == nil || lastPublishedSlideID != slideID {
                activeStrokeID = UUID()
                activeSequence = 0
            }
            pendingStroke = stroke
            pendingSlideID = slideID
            schedulePendingPublish()
            return
        }

        pendingPublishTask?.cancel()
        pendingPublishTask = nil

        let finalStroke = pendingStroke ?? lastPublishedStroke
        let finalSlideID = pendingSlideID ?? lastPublishedSlideID
        pendingStroke = nil
        pendingSlideID = nil

        if let finalStroke, let finalSlideID {
            publish(
                finalStroke,
                slideID: finalSlideID,
                isFinalChunk: true,
                session: session,
                configuration: configuration
            )
        }
        lastPublishedStroke = nil
        lastPublishedSlideID = nil
    }

    public func seedInitialInkDrawingSnapshots(_ snapshots: [TeacherInkDrawingSnapshot]) {
        for snapshot in snapshots {
            receive(snapshot)
        }
    }

    public func publishTeacherInkDrawingSnapshot(drawingData: Data, slideID: UUID, revision: Int) {
        guard let configuration,
              configuration.role == .teacher,
              let session else {
            return
        }

        let snapshot = TeacherInkDrawingSnapshot(
            lessonCode: configuration.lessonCode,
            slideID: slideID,
            revision: revision,
            drawingDataBase64: drawingData.base64EncodedString()
        )
        latestInkDrawingSnapshotsBySlideID[slideID] = snapshot
        session.publishTeacherInkDrawingSnapshot(snapshot)
        onPublishedTeacherInkDrawingSnapshot?(snapshot)
    }

    public func receivedStrokes(for slideID: UUID) -> [CanvasLiveStroke] {
        let snapshotSentAt = latestInkDrawingSnapshotsBySlideID[slideID]?.sentAt ?? .distantPast
        return receivedStrokeOrder.compactMap { strokeID in
            guard let chunk = latestChunksByStrokeID[strokeID],
                  chunk.slideID == slideID,
                  chunk.sentAt > snapshotSentAt else {
                return nil
            }
            return chunk.canvasLiveStroke
        }
    }

    public func receivedFinalInkChunks(for slideID: UUID) -> [TeacherInkStrokeChunk] {
        receivedStrokeOrder.compactMap { strokeID in
            guard let chunk = latestChunksByStrokeID[strokeID],
                  chunk.slideID == slideID,
                  chunk.isFinalChunk else {
                return nil
            }
            return chunk
        }
    }

    public func publishTeacherObjectSnapshot(_ snapshot: CanvasObjectSnapshot, slideID: UUID, revision: Int) {
        guard let configuration,
              configuration.role == .teacher,
              let session else {
            return
        }

        let teacherSnapshot = TeacherObjectSnapshot(
            lessonCode: configuration.lessonCode,
            slideID: slideID,
            revision: revision,
            snapshot: snapshot
        )
        latestObjectSnapshotsBySlideID[slideID] = teacherSnapshot
        session.publishTeacherObjectSnapshot(teacherSnapshot)
        onPublishedTeacherObjectSnapshot?(teacherSnapshot)
    }

    public func publishTeacherSlideManifestSnapshot(
        revision: Int,
        slides: [TeacherSlideMetadata],
        activeSlideID: UUID? = nil
    ) {
        guard let configuration,
              configuration.role == .teacher,
              let session else {
            return
        }

        let snapshot = TeacherSlideManifestSnapshot(
            lessonCode: configuration.lessonCode,
            revision: revision,
            slides: slides,
            activeSlideID: activeSlideID
        )
        let liveSnapshot = snapshot.withoutEmbeddedBackgroundAssets()
        latestSlideManifestSnapshot = liveSnapshot
        Task { @MainActor in
            do {
                if let onPublishedTeacherSlideManifestSnapshot {
                    try await onPublishedTeacherSlideManifestSnapshot(snapshot)
                }
                session.publishTeacherSlideManifestSnapshot(liveSnapshot)
            } catch {
                lastErrorMessage = error.localizedDescription
                print("[LiveClassroom] teacher slide manifest durable save failed before live nudge: \(error)")
            }
        }
    }

    private func schedulePendingPublish() {
        guard pendingPublishTask == nil else { return }
        pendingPublishTask = Task { [weak self] in
            do {
                try await Task.sleep(for: self?.publishInterval ?? Self.defaultPublishInterval)
            } catch {
                return
            }
            self?.publishPendingStroke()
        }
    }

    private func publishPendingStroke() {
        pendingPublishTask = nil
        guard let pendingStroke,
              let pendingSlideID,
              let session,
              let configuration,
              configuration.role == .teacher else {
            return
        }

        self.pendingStroke = nil
        self.pendingSlideID = nil
        publish(
            pendingStroke,
            slideID: pendingSlideID,
            isFinalChunk: false,
            session: session,
            configuration: configuration
        )
        lastPublishedStroke = pendingStroke
        lastPublishedSlideID = pendingSlideID
    }

    private func publish(
        _ stroke: CanvasLiveStroke,
        slideID: UUID,
        isFinalChunk: Bool,
        session: any LiveClassroomSessioning,
        configuration: LiveClassroomSessionConfiguration
    ) {
        guard let chunk = TeacherInkStrokeChunk(
            stroke: stroke,
            lessonCode: configuration.lessonCode,
            slideID: slideID,
            strokeID: activeStrokeID,
            sequence: activeSequence,
            isFinalChunk: isFinalChunk
        ) else {
            return
        }
        activeSequence += 1
        session.publishTeacherInkChunk(chunk)
        if chunk.isFinalChunk {
            onPublishedTeacherInkChunk?(chunk)
        }
    }

    private func receive(_ chunk: TeacherInkStrokeChunk) {
        if latestChunksByStrokeID[chunk.strokeID] == nil {
            receivedStrokeOrder.append(chunk.strokeID)
            pruneReceivedStrokesIfNeeded()
        }
        latestChunksByStrokeID[chunk.strokeID] = chunk
    }

    private func receive(_ snapshot: TeacherInkDrawingSnapshot) {
        if let current = latestInkDrawingSnapshotsBySlideID[snapshot.slideID], current.revision > snapshot.revision {
            return
        }
        latestInkDrawingSnapshotsBySlideID[snapshot.slideID] = snapshot
        onReceivedTeacherInkDrawingSnapshot?(snapshot)
    }

    private func receive(_ snapshot: TeacherObjectSnapshot) {
        if let current = latestObjectSnapshotsBySlideID[snapshot.slideID], current.revision > snapshot.revision {
            return
        }
        latestObjectSnapshotsBySlideID[snapshot.slideID] = snapshot
        onReceivedTeacherObjectSnapshot?(snapshot)
    }

    private func receive(_ snapshot: TeacherSlideManifestSnapshot) {
        if let current = latestSlideManifestSnapshot, current.revision > snapshot.revision {
            return
        }
        latestSlideManifestSnapshot = snapshot
        onReceivedTeacherSlideManifestSnapshot?(snapshot)
    }

    private func pruneReceivedStrokesIfNeeded() {
        let overflowCount = receivedStrokeOrder.count - Self.maximumReceivedStrokeCount
        guard overflowCount > 0 else { return }

        let removedStrokeIDs = receivedStrokeOrder.prefix(overflowCount)
        for strokeID in removedStrokeIDs {
            latestChunksByStrokeID[strokeID] = nil
        }
        receivedStrokeOrder.removeFirst(overflowCount)
    }
}
private extension TeacherSlideManifestSnapshot {
    func withoutEmbeddedBackgroundAssets() -> TeacherSlideManifestSnapshot {
        TeacherSlideManifestSnapshot(
            id: id,
            lessonCode: lessonCode,
            revision: revision,
            slides: slides.map { slide in
                var strippedSlide = slide
                strippedSlide.background?.assetBase64Data = nil
                return strippedSlide
            },
            activeSlideID: activeSlideID,
            sentAt: sentAt
        )
    }
}

