//
//  CanvasViewportControls.swift
//  MathBoardCore - Canvas module
//

import CoreGraphics
import Foundation

public struct CanvasViewportState: Sendable, Equatable {
    public let zoomScale: CGFloat
    public let contentOffset: CGPoint
    public let minimumZoomScale: CGFloat
    public let maximumZoomScale: CGFloat

    public init(
        zoomScale: CGFloat,
        contentOffset: CGPoint = .zero,
        minimumZoomScale: CGFloat,
        maximumZoomScale: CGFloat
    ) {
        self.zoomScale = zoomScale
        self.contentOffset = contentOffset
        self.minimumZoomScale = minimumZoomScale
        self.maximumZoomScale = maximumZoomScale
    }
}

public struct CanvasViewportCommand: Sendable, Equatable, Identifiable {
    public enum Action: Sendable, Equatable {
        case zoomIn
        case zoomOut
        case reset
        /// Pan and zoom so the current drawing's bounding box fits centered
        /// inside the 16:9 viewfinder region with a small margin. No-op if
        /// the drawing has no strokes yet.
        case fitToViewfinder
    }

    public let id: UUID
    public let action: Action

    public init(_ action: Action) {
        self.id = UUID()
        self.action = action
    }
}
