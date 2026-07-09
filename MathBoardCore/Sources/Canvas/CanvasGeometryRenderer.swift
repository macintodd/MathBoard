//
//  CanvasGeometryRenderer.swift
//  MathBoardCore - Canvas module
//
//  Shared CoreGraphics drawing for geometry objects. Used by the on-canvas
//  overlay view, the external-display committed frame, and PDF export so the
//  three render paths stay identical. Callers supply already-mapped target
//  coordinates (y-down) so this file never needs to know about zoom/pan.
//

import CoreGraphics
import Foundation

public enum CanvasGeometryRenderer {

    /// Draws `object` into `context`.
    /// - Parameters:
    ///   - boundingRect: normalized destination rect (y-down) for shape objects.
    ///   - start / end: destination-space endpoints for `.line` objects.
    ///   - lineWidthScale: multiplier applied to `object.strokeWidth`.
    ///   - pivot: destination-space rotation pivot (maps `object.pivot`).
    public static func draw(
        _ object: CanvasGeometryObject,
        boundingRect: CGRect,
        start: CGPoint,
        end: CGPoint,
        lineWidthScale: CGFloat,
        pivot: CGPoint,
        in context: CGContext
    ) {
        let strokeWidth = max(object.strokeWidth * lineWidthScale, 0.5)
        let strokeColor = rgb(object.strokeRed, object.strokeGreen, object.strokeBlue, object.strokeAlpha)
        let fillColor = rgb(object.fillRed, object.fillGreen, object.fillBlue, object.fillOpacity)

        context.saveGState()
        if object.rotation != 0 {
            context.translateBy(x: pivot.x, y: pivot.y)
            context.rotate(by: object.rotation)
            context.translateBy(x: -pivot.x, y: -pivot.y)
        }
        context.setLineWidth(strokeWidth)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.setStrokeColor(strokeColor)
        context.setFillColor(fillColor)

        switch object.shape {
        case .line:
            let arrowLength = Self.arrowHeadLength(for: strokeWidth)
            let shaft = lineShaftEndpoints(
                start: start,
                end: end,
                arrow: object.arrow,
                arrowLength: arrowLength
            )
            context.beginPath()
            context.move(to: shaft.start)
            context.addLine(to: shaft.end)
            context.strokePath()
            drawArrowHeads(object, start: start, end: end, strokeWidth: strokeWidth, color: strokeColor, in: context)
        case .rectangle:
            fillAndStroke(CGPath(rect: boundingRect, transform: nil), fillOpacity: object.fillOpacity, in: context)
        case .circle:
            fillAndStroke(CGPath(ellipseIn: boundingRect, transform: nil), fillOpacity: object.fillOpacity, in: context)
        case .triangle:
            let path = CGMutablePath()
            let apexX = boundingRect.minX + object.renderedTriangleApexOffset * boundingRect.width
            let apexY = object.isFlippedVertical ? boundingRect.maxY : boundingRect.minY
            let baseY = object.isFlippedVertical ? boundingRect.minY : boundingRect.maxY
            path.move(to: CGPoint(x: apexX, y: apexY))
            path.addLine(to: CGPoint(x: boundingRect.maxX, y: baseY))
            path.addLine(to: CGPoint(x: boundingRect.minX, y: baseY))
            path.closeSubpath()
            fillAndStroke(path, fillOpacity: object.fillOpacity, in: context)
        case .rightTriangle:
            let path = CGMutablePath()
            let rightAngleX = object.isFlippedHorizontal ? boundingRect.maxX : boundingRect.minX
            let oppositeX = object.isFlippedHorizontal ? boundingRect.minX : boundingRect.maxX
            let rightAngleY = object.isFlippedVertical ? boundingRect.minY : boundingRect.maxY
            let oppositeY = object.isFlippedVertical ? boundingRect.maxY : boundingRect.minY
            path.move(to: CGPoint(x: rightAngleX, y: oppositeY))
            path.addLine(to: CGPoint(x: rightAngleX, y: rightAngleY))
            path.addLine(to: CGPoint(x: oppositeX, y: rightAngleY))
            path.closeSubpath()
            fillAndStroke(path, fillOpacity: object.fillOpacity, in: context)
        case .polygon:
            fillAndStroke(regularPolygonPath(in: boundingRect, sides: max(object.polygonSides, 3)), fillOpacity: object.fillOpacity, in: context)
        }

        context.restoreGState()
    }

    /// True when the two axes are within ~2% — i.e. a circle is a perfect circle
    /// (not an ellipse) or a rectangle is a square. Keyed off the object's own
    /// source dimensions so it is independent of the render scale.
    public static func isEqualSided(width: CGFloat, height: CGFloat) -> Bool {
        let w = abs(width)
        let h = abs(height)
        let maxSide = max(w, h)
        guard maxSide > 0.5 else { return false }
        return abs(w - h) <= maxSide * 0.02
    }

    private static func fillAndStroke(_ path: CGPath, fillOpacity: CGFloat, in context: CGContext) {
        if fillOpacity > 0.001 {
            context.addPath(path)
            context.fillPath()
        }
        context.addPath(path)
        context.strokePath()
    }

    private static func regularPolygonPath(in rect: CGRect, sides: Int) -> CGPath {
        let path = CGMutablePath()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radiusX = rect.width / 2
        let radiusY = rect.height / 2
        // Start at the top (‑90°) so shapes read upright.
        let startAngle = -CGFloat.pi / 2
        for index in 0..<sides {
            let angle = startAngle + CGFloat(index) * (2 * .pi / CGFloat(sides))
            let point = CGPoint(x: center.x + radiusX * cos(angle), y: center.y + radiusY * sin(angle))
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }

    private static func drawArrowHeads(
        _ object: CanvasGeometryObject,
        start: CGPoint,
        end: CGPoint,
        strokeWidth: CGFloat,
        color: CGColor,
        in context: CGContext
    ) {
        guard object.arrow != .none else { return }
        let length = arrowHeadLength(for: strokeWidth)
        if object.arrow == .end || object.arrow == .both {
            drawArrowHead(tip: end, from: start, length: length, color: color, in: context)
        }
        if object.arrow == .start || object.arrow == .both {
            drawArrowHead(tip: start, from: end, length: length, color: color, in: context)
        }
    }

    private static func drawArrowHead(
        tip: CGPoint,
        from other: CGPoint,
        length: CGFloat,
        color: CGColor,
        in context: CGContext
    ) {
        let angle = atan2(tip.y - other.y, tip.x - other.x)
        let spread = CGFloat.pi / 7
        let left = CGPoint(x: tip.x - length * cos(angle - spread), y: tip.y - length * sin(angle - spread))
        let right = CGPoint(x: tip.x - length * cos(angle + spread), y: tip.y - length * sin(angle + spread))
        let path = CGMutablePath()
        path.move(to: tip)
        path.addLine(to: left)
        path.addLine(to: right)
        path.closeSubpath()
        context.setFillColor(color)
        context.addPath(path)
        context.fillPath()
    }

    private static func arrowHeadLength(for strokeWidth: CGFloat) -> CGFloat {
        max(strokeWidth * 3.2, 10)
    }

    private static func lineShaftEndpoints(
        start: CGPoint,
        end: CGPoint,
        arrow: CanvasGeometryArrow,
        arrowLength: CGFloat
    ) -> (start: CGPoint, end: CGPoint) {
        guard arrow != .none else {
            return (start, end)
        }

        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = hypot(dx, dy)
        guard distance > 0.001 else {
            return (start, end)
        }

        let unit = CGVector(dx: dx / distance, dy: dy / distance)
        let requestedInset = arrowLength * 0.82
        let arrowedEndCount: CGFloat = arrow == .both ? 2 : 1
        let inset = min(requestedInset, distance / max(arrowedEndCount + 1, 1))

        var shaftStart = start
        var shaftEnd = end
        if arrow == .start || arrow == .both {
            shaftStart = CGPoint(
                x: start.x + unit.dx * inset,
                y: start.y + unit.dy * inset
            )
        }
        if arrow == .end || arrow == .both {
            shaftEnd = CGPoint(
                x: end.x - unit.dx * inset,
                y: end.y - unit.dy * inset
            )
        }
        return (shaftStart, shaftEnd)
    }

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat) -> CGColor {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let components = [red, green, blue, alpha]
        return CGColor(colorSpace: colorSpace, components: components)
            ?? CGColor(gray: 0, alpha: alpha)
    }
}
