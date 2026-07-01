//
//  ViewfinderOverlay.swift
//  MathBoardCore — Presentation module
//
//  Fixed 16:9 viewfinder rectangle centered in the available space, with
//  dimmed regions outside it. The clear region is what the TV / external
//  display will eventually show; the dimmed regions are teacher-only.
//
//  v1 is intentionally non-interactive — no drag handles. The teacher
//  composes their layout by panning / zooming the canvas (handled by
//  PKCanvasView's built-in scroll behavior) so the desired content lands
//  inside the viewfinder. The viewfinder itself only resizes when the
//  enclosing app window resizes.
//

import SwiftUI

struct ViewfinderOverlay: View {

    private static let viewfinderTint = Color(red: 0.91, green: 0.45, blue: 0.32)
    private static let dimOpacity: Double = 0.35
    private static let targetAspect: CGFloat = 16.0 / 9.0
    private static let borderWidth: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            let canvasSize = proxy.size
            let viewfinderSize = Self.viewfinderSize(in: canvasSize)
            let viewfinderOrigin = CGPoint(
                x: (canvasSize.width - viewfinderSize.width) / 2,
                y: (canvasSize.height - viewfinderSize.height) / 2
            )
            let viewfinderRect = CGRect(origin: viewfinderOrigin, size: viewfinderSize)
            let centerPoint = CGPoint(x: viewfinderRect.midX, y: viewfinderRect.midY)

            ZStack {
                // Dim everything except the viewfinder rectangle via even-odd
                // fill — single draw call, no corner double-dimming.
                SwiftUI.Canvas { context, size in
                    var path = Path(CGRect(origin: .zero, size: size))
                    path.addRect(viewfinderRect)
                    context.fill(
                        path,
                        with: .color(.black.opacity(Self.dimOpacity)),
                        style: FillStyle(eoFill: true)
                    )
                }

                Rectangle()
                    .strokeBorder(Self.viewfinderTint, lineWidth: Self.borderWidth)
                    .frame(width: viewfinderSize.width, height: viewfinderSize.height)
                    .position(centerPoint)
            }
            .allowsHitTesting(false)
        }
    }

    /// Largest 16:9 rectangle that fits inside `canvasSize`.
    private static func viewfinderSize(in canvasSize: CGSize) -> CGSize {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return .zero }
        let aspect = canvasSize.width / canvasSize.height
        if aspect > targetAspect {
            let height = canvasSize.height
            return CGSize(width: height * targetAspect, height: height)
        } else {
            let width = canvasSize.width
            return CGSize(width: width, height: width / targetAspect)
        }
    }
}
