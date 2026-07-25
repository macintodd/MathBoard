//
//  SlideNavMockArt.swift
//  MathBoardCore — SlideNav prototype module
//
//  Deterministic "handwritten math" doodles used as stand-in slide content:
//  each variant draws light axes plus one colored figure, size-relative so the
//  same view works as a filmstrip thumbnail and as the harness's full canvas.
//

import SwiftUI

struct SlideNavMockArt: View {
    static let variantCount = 6

    let variant: Int

    var body: some View {
        Canvas { context, size in
            drawAxes(in: &context, size: size)
            switch variant % Self.variantCount {
            case 0: drawParabola(in: &context, size: size, color: .blue)
            case 1: drawSine(in: &context, size: size, color: Color(red: 0.2, green: 0.55, blue: 0.3))
            case 2: drawLines(in: &context, size: size, color: SlideNavColors.accent)
            case 3: drawCircleFigure(in: &context, size: size, color: .purple)
            case 4: drawTriangle(in: &context, size: size, color: .orange)
            default: drawScatter(in: &context, size: size, color: .teal)
            }
        }
    }

    private func stroke(_ path: Path, in context: inout GraphicsContext, size: CGSize, color: Color) {
        let width = max(1.5, min(size.width, size.height) * 0.028)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    private func drawAxes(in context: inout GraphicsContext, size: CGSize) {
        var axes = Path()
        axes.move(to: CGPoint(x: size.width * 0.12, y: size.height * 0.1))
        axes.addLine(to: CGPoint(x: size.width * 0.12, y: size.height * 0.88))
        axes.addLine(to: CGPoint(x: size.width * 0.92, y: size.height * 0.88))
        let width = max(1, min(size.width, size.height) * 0.018)
        context.stroke(axes, with: .color(.gray.opacity(0.45)), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    private func drawParabola(in context: inout GraphicsContext, size: CGSize, color: Color) {
        var path = Path()
        path.move(to: CGPoint(x: size.width * 0.2, y: size.height * 0.18))
        path.addQuadCurve(
            to: CGPoint(x: size.width * 0.85, y: size.height * 0.18),
            control: CGPoint(x: size.width * 0.52, y: size.height * 1.35)
        )
        stroke(path, in: &context, size: size, color: color)
    }

    private func drawSine(in context: inout GraphicsContext, size: CGSize, color: Color) {
        var path = Path()
        let midY = size.height * 0.5
        let amplitude = size.height * 0.24
        path.move(to: CGPoint(x: size.width * 0.14, y: midY))
        let steps = 40
        for step in 1...steps {
            let t = Double(step) / Double(steps)
            let x = size.width * (0.14 + 0.74 * t)
            let y = midY - amplitude * sin(t * 2 * .pi)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        stroke(path, in: &context, size: size, color: color)
    }

    private func drawLines(in context: inout GraphicsContext, size: CGSize, color: Color) {
        var path = Path()
        path.move(to: CGPoint(x: size.width * 0.18, y: size.height * 0.78))
        path.addLine(to: CGPoint(x: size.width * 0.85, y: size.height * 0.2))
        path.move(to: CGPoint(x: size.width * 0.18, y: size.height * 0.3))
        path.addLine(to: CGPoint(x: size.width * 0.85, y: size.height * 0.7))
        stroke(path, in: &context, size: size, color: color)

        let intersection = CGPoint(x: size.width * 0.515, y: size.height * 0.49)
        let dotRadius = min(size.width, size.height) * 0.045
        context.fill(Path(ellipseIn: CGRect(x: intersection.x - dotRadius, y: intersection.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)), with: .color(color))
    }

    private func drawCircleFigure(in context: inout GraphicsContext, size: CGSize, color: Color) {
        let radius = min(size.width, size.height) * 0.3
        let center = CGPoint(x: size.width * 0.52, y: size.height * 0.48)
        var path = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        path.move(to: center)
        path.addLine(to: CGPoint(x: center.x + radius * 0.71, y: center.y - radius * 0.71))
        stroke(path, in: &context, size: size, color: color)
    }

    private func drawTriangle(in context: inout GraphicsContext, size: CGSize, color: Color) {
        var path = Path()
        let apex = CGPoint(x: size.width * 0.55, y: size.height * 0.18)
        let left = CGPoint(x: size.width * 0.22, y: size.height * 0.78)
        let right = CGPoint(x: size.width * 0.86, y: size.height * 0.78)
        path.move(to: apex)
        path.addLine(to: left)
        path.addLine(to: right)
        path.closeSubpath()
        path.move(to: apex)
        path.addLine(to: CGPoint(x: apex.x, y: size.height * 0.78))
        stroke(path, in: &context, size: size, color: color)
    }

    private func drawScatter(in context: inout GraphicsContext, size: CGSize, color: Color) {
        let points: [(Double, Double)] = [(0.22, 0.7), (0.34, 0.62), (0.45, 0.5), (0.55, 0.45), (0.66, 0.32), (0.78, 0.24)]
        let radius = min(size.width, size.height) * 0.035
        for (px, py) in points {
            let rect = CGRect(
                x: size.width * px - radius,
                y: size.height * py - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(Path(ellipseIn: rect), with: .color(color))
        }
        var trend = Path()
        trend.move(to: CGPoint(x: size.width * 0.18, y: size.height * 0.76))
        trend.addLine(to: CGPoint(x: size.width * 0.84, y: size.height * 0.2))
        let width = max(1, min(size.width, size.height) * 0.015)
        context.stroke(trend, with: .color(color.opacity(0.5)), style: StrokeStyle(lineWidth: width, dash: [width * 3]))
    }
}

#Preview("All variants") {
    LazyVGrid(columns: Array(repeating: GridItem(.fixed(160)), count: 3), spacing: 16) {
        ForEach(0..<SlideNavMockArt.variantCount, id: \.self) { variant in
            SlideNavMockArt(variant: variant)
                .padding(8)
                .frame(width: 160, height: 120)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
    .padding(30)
    .background(SlideNavColors.canvasCream)
}
