//
//  SlideMetadata.swift
//  MathBoardCore — Slides module
//
//  Per-slide metadata stored in `slides.json` inside each `.mathboard`
//  package. The slide's drawing data lives in a sibling file named
//  `strokes/slide-<uuid>.drawing`.
//

import Foundation

public struct SlideMetadata: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public var viewport: SlideViewportState?
    public var background: SlideBackground?
    /// Non-nil for supplementary slides added during a class session (not from the master lesson).
    /// `nil` means this is a master-derived slide.
    public var anchor: SlideAnchor?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        viewport: SlideViewportState? = nil,
        background: SlideBackground? = nil,
        anchor: SlideAnchor? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.viewport = viewport
        self.background = background
        self.anchor = anchor
    }
}

/// Placement metadata for a slide added during a class session (not a master slide).
/// Stores who added it and which master slide it lives after, so merge can restore position
/// even when master slides are added or removed.
public struct SlideAnchor: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case teacher = "T"
        case student = "S"
    }

    public var kind: Kind
    /// ID of the master slide this is anchored after. `nil` = before all master slides.
    public var masterSlideID: UUID?
    /// 1-based rank among same-kind anchored slides after the same master, used for stable ordering.
    public var sequenceNumber: Int

    public init(kind: Kind, masterSlideID: UUID?, sequenceNumber: Int) {
        self.kind = kind
        self.masterSlideID = masterSlideID
        self.sequenceNumber = sequenceNumber
    }
}

public struct SlideBackground: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case pdfPage
    }

    public var kind: Kind
    public var assetFileName: String
    public var pageIndex: Int

    public init(kind: Kind, assetFileName: String, pageIndex: Int) {
        self.kind = kind
        self.assetFileName = assetFileName
        self.pageIndex = pageIndex
    }
}

public struct SlideViewportState: Codable, Hashable, Sendable {
    public var zoomScale: Double
    public var contentOffsetX: Double
    public var contentOffsetY: Double
    public var platform: String?

    public init(
        zoomScale: Double,
        contentOffsetX: Double,
        contentOffsetY: Double,
        platform: String? = nil
    ) {
        self.zoomScale = zoomScale
        self.contentOffsetX = contentOffsetX
        self.contentOffsetY = contentOffsetY
        self.platform = platform
    }

    public func isUsableSavedCanvasViewport(drawingOriginOffset: Double = 3000) -> Bool {
        guard zoomScale.isFinite, zoomScale > 0,
              contentOffsetX.isFinite, contentOffsetY.isFinite,
              contentOffsetX >= 0, contentOffsetY >= 0 else {
            return false
        }

        let scaledBoardOrigin = max(drawingOriginOffset * zoomScale, 1)
        let topLeftVoidThreshold = max(scaledBoardOrigin * 0.2, 24)
        if contentOffsetX <= topLeftVoidThreshold && contentOffsetY <= topLeftVoidThreshold {
            return false
        }

        return true
    }
}
