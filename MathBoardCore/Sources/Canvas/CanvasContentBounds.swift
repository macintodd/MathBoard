//
//  CanvasContentBounds.swift
//  MathBoardCore - Canvas module
//

import CoreGraphics
import Foundation

public enum CanvasBoardMetrics {
    public static let defaultUsableSize = CGSize(width: 2550, height: 3300)
}

public enum CanvasContentBounds {
    public static func combinedBounds(
        drawingBounds: CGRect?,
        backgroundSize: CGSize?,
        textObjects: [CanvasTextObject],
        geometryObjects: [CanvasGeometryObject] = [],
        canvasOrigin: CGPoint = .zero
    ) -> CGRect? {
        var combined: CGRect?

        if let drawingBounds, isUsable(drawingBounds) {
            combined = drawingBounds
        }

        if let backgroundSize, backgroundSize.width > 0, backgroundSize.height > 0 {
            combined = union(
                combined,
                CGRect(origin: canvasOrigin, size: backgroundSize)
            )
        }

        for object in textObjects where !object.text.isEmpty {
            let frame = object.frame.offsetBy(dx: canvasOrigin.x, dy: canvasOrigin.y)
            guard isUsable(frame) else { continue }
            combined = union(combined, frame)
        }

        for object in geometryObjects {
            let frame = object.renderedBounds.offsetBy(dx: canvasOrigin.x, dy: canvasOrigin.y)
            guard isUsable(frame) else { continue }
            combined = union(combined, frame)
        }

        return combined
    }

    private static func union(_ existing: CGRect?, _ next: CGRect) -> CGRect {
        guard let existing, isUsable(existing) else { return next }
        return existing.union(next)
    }

    private static func isUsable(_ rect: CGRect) -> Bool {
        rect.width > 0
            && rect.height > 0
            && !rect.isEmpty
            && !rect.isNull
            && !rect.isInfinite
    }
}
