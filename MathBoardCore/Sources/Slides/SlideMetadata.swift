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

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        viewport: SlideViewportState? = nil,
        background: SlideBackground? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.viewport = viewport
        self.background = background
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
}
