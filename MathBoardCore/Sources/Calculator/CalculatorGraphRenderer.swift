//
//  CalculatorGraphRenderer.swift
//  MathBoardCore — Calculator module
//
//  Shared SwiftUI `Canvas` drawing for the graph plot: gridlines, axes,
//  tick labels, and the function curve. Used by both the interactive
//  `CalculatorGraphView` (iPad) and the read-only `CalculatorTVOverlay`
//  (external display) so the two render identically.
//
//  Drawing only — no gestures, no state. Callers own expression
//  compilation and pass in the compiled AST (or nil to draw just the
//  grid).
//

import SwiftUI

enum CalculatorGraphRenderer {

    /// Draw the grid plus every enabled equation in its palette color.
    /// Each equation is compiled here; ones that fail to parse or are empty
    /// are silently skipped (a half-typed equation simply doesn't plot).
    static func draw(
        in context: GraphicsContext,
        size: CGSize,
        window: GraphWindow,
        equations: [GraphEquation],
        angleMode: CalculatorAngleMode,
        engine: CalculatorEngine,
        lineWidth: CGFloat = 2
    ) {
        guard window.isValid, size.width > 0, size.height > 0 else { return }
        drawGrid(in: context, size: size, window: window)

        for equation in equations where equation.isEnabled {
            let trimmed = equation.expression.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let compiled = try? engine.compile(trimmed) else { continue }
            let rgb = GraphPalette.rgb(for: equation.colorIndex)
            drawCurve(
                in: context,
                size: size,
                window: window,
                compiled: compiled,
                angleMode: angleMode,
                engine: engine,
                color: Color(red: rgb.red, green: rgb.green, blue: rgb.blue),
                lineWidth: lineWidth
            )
        }
    }

    // MARK: - Grid + axes + labels

    private static func drawGrid(in context: GraphicsContext, size: CGSize, window: GraphWindow) {
        let xTargets = max(Int(size.width / 70), 2)
        let yTargets = max(Int(size.height / 70), 2)
        let xStep = CalculatorGraphGeometry.niceStep(range: window.width, targetCount: xTargets)
        let yStep = CalculatorGraphGeometry.niceStep(range: window.height, targetCount: yTargets)

        let xTicks = CalculatorGraphGeometry.ticks(min: window.xMin, max: window.xMax, step: xStep)
        let yTicks = CalculatorGraphGeometry.ticks(min: window.yMin, max: window.yMax, step: yStep)

        for x in xTicks {
            let p = CalculatorGraphGeometry.viewPoint(forGraph: CGPoint(x: x, y: 0), window: window, size: size)
            var line = Path()
            line.move(to: CGPoint(x: p.x, y: 0))
            line.addLine(to: CGPoint(x: p.x, y: size.height))
            context.stroke(line, with: .color(CalculatorTheme.gridline), lineWidth: 0.5)
        }
        for y in yTicks {
            let p = CalculatorGraphGeometry.viewPoint(forGraph: CGPoint(x: 0, y: y), window: window, size: size)
            var line = Path()
            line.move(to: CGPoint(x: 0, y: p.y))
            line.addLine(to: CGPoint(x: size.width, y: p.y))
            context.stroke(line, with: .color(CalculatorTheme.gridline), lineWidth: 0.5)
        }

        let origin = CalculatorGraphGeometry.viewPoint(forGraph: .zero, window: window, size: size)
        if origin.y >= 0, origin.y <= size.height {
            var axis = Path()
            axis.move(to: CGPoint(x: 0, y: origin.y))
            axis.addLine(to: CGPoint(x: size.width, y: origin.y))
            context.stroke(axis, with: .color(CalculatorTheme.axis), lineWidth: 1)
        }
        if origin.x >= 0, origin.x <= size.width {
            var axis = Path()
            axis.move(to: CGPoint(x: origin.x, y: 0))
            axis.addLine(to: CGPoint(x: origin.x, y: size.height))
            context.stroke(axis, with: .color(CalculatorTheme.axis), lineWidth: 1)
        }

        let labelY = min(max(origin.y, 10), size.height - 10)
        for x in xTicks where abs(x) > xStep * 1e-6 {
            let p = CalculatorGraphGeometry.viewPoint(forGraph: CGPoint(x: x, y: 0), window: window, size: size)
            context.draw(
                Text(tickLabel(x, step: xStep)).font(.system(size: 8)).foregroundStyle(CalculatorTheme.graphLabel),
                at: CGPoint(x: p.x + 2, y: labelY + 8),
                anchor: .leading
            )
        }
        let labelX = min(max(origin.x, 12), size.width - 12)
        for y in yTicks where abs(y) > yStep * 1e-6 {
            let p = CalculatorGraphGeometry.viewPoint(forGraph: CGPoint(x: 0, y: y), window: window, size: size)
            context.draw(
                Text(tickLabel(y, step: yStep)).font(.system(size: 8)).foregroundStyle(CalculatorTheme.graphLabel),
                at: CGPoint(x: labelX + 3, y: p.y - 6),
                anchor: .leading
            )
        }
    }

    // MARK: - Curve

    private static func drawCurve(
        in context: GraphicsContext,
        size: CGSize,
        window: GraphWindow,
        compiled: CalculatorExpression,
        angleMode: CalculatorAngleMode,
        engine: CalculatorEngine,
        color: Color,
        lineWidth: CGFloat
    ) {
        let columns = max(min(Int(size.width), 1200), 2)
        let samples = CalculatorGraphGeometry.sample(window: window, count: columns) { x in
            try? engine.evaluate(compiled: compiled, angleMode: angleMode, variables: ["x": x])
        }

        var path = Path()
        var penDown = false
        var previousY: Double?

        for sample in samples {
            guard let y = sample.y else {
                penDown = false
                previousY = nil
                continue
            }
            if let prev = previousY, isLikelyDiscontinuity(prev, y, window: window) {
                penDown = false
            }
            let viewPoint = CalculatorGraphGeometry.viewPoint(
                forGraph: CGPoint(x: sample.x, y: y),
                window: window,
                size: size
            )
            if penDown {
                path.addLine(to: viewPoint)
            } else {
                path.move(to: viewPoint)
                penDown = true
            }
            previousY = y
        }

        context.stroke(path, with: .color(color), lineWidth: lineWidth)
    }

    private static func isLikelyDiscontinuity(_ a: Double, _ b: Double, window: GraphWindow) -> Bool {
        let jump = abs(b - a)
        return jump > window.height * 3 && (a.sign != b.sign)
    }

    private static func tickLabel(_ value: Double, step: Double) -> String {
        if step >= 1, value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%g", value)
    }
}
