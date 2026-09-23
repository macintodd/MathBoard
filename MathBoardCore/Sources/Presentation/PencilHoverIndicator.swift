//
//  PencilHoverIndicator.swift
//  MathBoardCore — Presentation module
//
//  Renders the teacher's Apple Pencil position as a small dot with a
//  directional shadow on secondary displays (external TV / student views).
//  The shadow length and angle reflect the pencil's altitude and azimuth,
//  mimicking the real-world shadow a pencil would cast under angled light.
//
//  Two visual states:
//    - Hovering: open circle with a soft elongated shadow (pencil above screen)
//    - Writing:  filled dot (pencil touching screen, ink is flowing)
//

import Canvas
import CoreGraphics
import SwiftUI

/// Overlay that maps a `CanvasPencilHover` in drawing-coordinate space to
/// screen pixels and draws the indicator dot and shadow.
public struct PencilHoverIndicatorOverlay: View {
    let hoverState: CanvasPencilHover
    let viewportSourceRect: CGRect?
    let fallbackSourceSize: CGSize
    let fittedSize: CGSize

    public init(
        hoverState: CanvasPencilHover,
        viewportSourceRect: CGRect?,
        fallbackSourceSize: CGSize,
        fittedSize: CGSize
    ) {
        self.hoverState = hoverState
        self.viewportSourceRect = viewportSourceRect
        self.fallbackSourceSize = fallbackSourceSize
        self.fittedSize = fittedSize
    }

    public var body: some View {
        SwiftUI.Canvas { context, size in
            guard let screenPoint = screenPoint(for: hoverState.canvasPoint, in: size) else { return }
            drawIndicator(at: screenPoint, in: &context)
        }
        .frame(width: fittedSize.width, height: fittedSize.height)
        .allowsHitTesting(false)
    }

    // MARK: - Rendering

    private func drawIndicator(at point: CGPoint, in context: inout GraphicsContext) {
        let dotRadius: CGFloat = 7
        let shadowLength = shadowLength(for: hoverState.altitudeAngle)
        let shadowAngle = hoverState.azimuthAngle

        if shadowLength > 2 {
            drawShadow(from: point, length: shadowLength, angle: shadowAngle, in: &context)
        }

        if hoverState.isWriting {
            drawFilledDot(at: point, radius: dotRadius, in: &context)
        } else {
            drawOpenDot(at: point, radius: dotRadius, in: &context)
        }
    }

    /// Shadow length in points. Flat pencil (altitude ≈ 0) → long shadow;
    /// upright pencil (altitude ≈ π/2) → no shadow.
    private func shadowLength(for altitudeAngle: CGFloat) -> CGFloat {
        let normalized = 1 - min(max(altitudeAngle / (.pi / 2), 0), 1)
        return normalized * normalized * 56
    }

    private func drawShadow(from tip: CGPoint, length: CGFloat, angle: CGFloat, in context: inout GraphicsContext) {
        // Soft teardrop shadow: a blurred ellipse whose center is shifted 60% along the
        // azimuth direction so it tapers sharply at the tip and widens toward the far end,
        // matching the look of a real pencil shadow cast on paper.
        let shadowWidth = max(length * 0.40, 8)
        let opacity = 0.30 + 0.22 * (length / 56)

        let centerFraction: CGFloat = 0.60
        let cx = tip.x + cos(angle) * length * centerFraction
        let cy = tip.y + sin(angle) * length * centerFraction

        let transform = CGAffineTransform(translationX: cx, y: cy).rotated(by: angle)
        let ellipseRect = CGRect(
            x: -length * centerFraction,
            y: -shadowWidth / 2,
            width: length,
            height: shadowWidth
        )
        let shadowPath = Path(ellipseIn: ellipseRect).applying(transform)

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 14))
            layer.fill(shadowPath, with: .color(.black.opacity(Double(opacity * 0.80))))
        }
        context.fill(shadowPath, with: .color(.black.opacity(Double(opacity * 0.12))))
    }

    private func drawOpenDot(at point: CGPoint, radius: CGFloat, in context: inout GraphicsContext) {
        let rect = CGRect(
            x: point.x - radius, y: point.y - radius,
            width: radius * 2, height: radius * 2
        )
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 3))
            layer.fill(Path(ellipseIn: rect), with: .color(.black.opacity(0.18)))
        }
        context.fill(Path(ellipseIn: rect.insetBy(dx: 2, dy: 2)), with: .color(.white.opacity(0.92)))
        context.stroke(
            Path(ellipseIn: rect),
            with: .color(.black.opacity(0.55)),
            style: StrokeStyle(lineWidth: 2.5)
        )
    }

    private func drawFilledDot(at point: CGPoint, radius: CGFloat, in context: inout GraphicsContext) {
        let rect = CGRect(
            x: point.x - radius, y: point.y - radius,
            width: radius * 2, height: radius * 2
        )
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 4))
            layer.fill(Path(ellipseIn: rect.insetBy(dx: -2, dy: -2)), with: .color(.black.opacity(0.22)))
        }
        context.fill(Path(ellipseIn: rect), with: .color(.black.opacity(0.85)))
        context.fill(
            Path(ellipseIn: rect.insetBy(dx: radius * 0.35, dy: radius * 0.35)),
            with: .color(.white.opacity(0.42))
        )
    }

    // MARK: - Coordinate mapping

    private func screenPoint(for canvasPoint: CGPoint, in size: CGSize) -> CGPoint? {
        if let viewportSourceRect,
           viewportSourceRect.width > 0,
           viewportSourceRect.height > 0 {
            let scaleX = size.width / viewportSourceRect.width
            let scaleY = size.height / viewportSourceRect.height
            let sx = (canvasPoint.x - viewportSourceRect.minX) * scaleX
            let sy = (canvasPoint.y - viewportSourceRect.minY) * scaleY
            guard sx >= -20 && sx <= size.width + 20 &&
                  sy >= -20 && sy <= size.height + 20 else { return nil }
            return CGPoint(x: sx, y: sy)
        }

        guard fallbackSourceSize.width > 0, fallbackSourceSize.height > 0 else { return nil }
        let scaleX = size.width / fallbackSourceSize.width
        let scaleY = size.height / fallbackSourceSize.height
        return CGPoint(x: canvasPoint.x * scaleX, y: canvasPoint.y * scaleY)
    }
}
