//
//  GraphCalculatorRenderer.swift
//  MathBoardCore - GraphCalculator module
//
//  Canvas drawing for the isolated Desmos-style graph calculator.
//

import SwiftUI
import Calculator

/// Appearance options for the graph axes/grid, configured from the gear settings panel.
struct GraphAxisStyle {
    var axisStrokeWidth: CGFloat = 1.4
    var gridlineThickness: CGFloat = 0.8
    var showGrid: Bool = true
    var xAxisLabel: String = ""
    var yAxisLabel: String = ""
    /// When true, curves are drawn with a "fountain pen on paper" look: off-white paper with a
    /// faint grain and a subtly variable-width ink stroke. Line color and width remain customizable.
    var handDrawn: Bool = true

    static let `default` = GraphAxisStyle()
}

enum GraphPaperPalette {
    /// Warm off-white "bond paper".
    static let paper = Color(red: 0.984, green: 0.980, blue: 0.957)
}

enum GraphCalculatorRenderer {
    static func draw(
        in context: GraphicsContext,
        size: CGSize,
        window: GraphWindow,
        expressions: [GraphEquation],
        dataTables: [GraphCalculatorDataTable] = [],
        engine: CalculatorEngine,
        variableValues: [String: Double] = [:],
        accent: Color,
        axisStyle: GraphAxisStyle = .default
    ) {
        guard window.isValid, size.width > 0, size.height > 0 else { return }

        if axisStyle.handDrawn {
            drawPaper(in: context, size: size)
        }
        drawGrid(in: context, size: size, window: window, axisStyle: axisStyle)
        let resolvedRows = GraphCalculatorExpressionResolver.resolveRows(expressions: expressions, engine: engine, variableValues: variableValues)

        for row in resolvedRows where expressions.indices.contains(row.index) && expressions[row.index].isEnabled {
            guard let plot = row.plot else { continue }
            let expression = expressions[row.index]
            let color = color(for: expression, fallback: accent)
            let lineWidth = CGFloat(expression.lineWidth ?? GraphCalculatorStyleDefaults.lineWidth)
            drawPlot(in: context, size: size, window: window, plot: plot, engine: engine, variableValues: variableValues, color: color, lineWidth: lineWidth, handDrawn: axisStyle.handDrawn)
        }

        drawDataTables(in: context, size: size, window: window, dataTables: dataTables, fallback: accent)
    }

    /// Fills an off-white "bond paper" background with a faint, cheap grain (one filled path).
    private static func drawPaper(in context: GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(GraphPaperPalette.paper))

        // Subtle paper "tooth": many tiny speckles collected into a single path so it is one fill
        // call per frame (cheap even during pan/zoom).
        var grain = Path()
        let step: CGFloat = 6
        var row = 0
        var y: CGFloat = 0
        while y < size.height {
            var col = 0
            var x: CGFloat = 0
            while x < size.width {
                let hash = sin(CGFloat(col) * 12.9898 + CGFloat(row) * 78.233) * 43758.5453
                let frac = hash - hash.rounded(.down)
                if frac > 0.82 {
                    let jx = (sin(CGFloat(col) * 3.17 + CGFloat(row)) * 0.5) * step
                    let jy = (cos(CGFloat(row) * 2.71 + CGFloat(col)) * 0.5) * step
                    let dotSize: CGFloat = frac > 0.94 ? 1.1 : 0.7
                    grain.addRect(CGRect(x: x + jx, y: y + jy, width: dotSize, height: dotSize))
                }
                x += step
                col += 1
            }
            y += step
            row += 1
        }
        context.fill(grain, with: .color(.black.opacity(0.05)))
    }

    private static func drawGrid(in context: GraphicsContext, size: CGSize, window: GraphWindow, axisStyle: GraphAxisStyle) {
        let majorX = CalculatorGraphGeometry.niceStep(range: window.width, targetCount: max(Int(size.width / 120), 2))
        let majorY = CalculatorGraphGeometry.niceStep(range: window.height, targetCount: max(Int(size.height / 120), 2))
        // Minor gridlines must evenly subdivide the major step (5 minor cells per major square),
        // otherwise independently-computed "nice" steps make the grid look unevenly spaced.
        let minorX = majorX / 5
        let minorY = majorY / 5

        if axisStyle.showGrid {
            let minorWidth = max(0.25, axisStyle.gridlineThickness * 0.6)
            let majorWidth = max(0.25, axisStyle.gridlineThickness)
            drawTicks(context: context, size: size, window: window, step: minorX, axis: .x, color: .black.opacity(0.10), lineWidth: minorWidth)
            drawTicks(context: context, size: size, window: window, step: minorY, axis: .y, color: .black.opacity(0.10), lineWidth: minorWidth)
            drawTicks(context: context, size: size, window: window, step: majorX, axis: .x, color: .black.opacity(0.24), lineWidth: majorWidth)
            drawTicks(context: context, size: size, window: window, step: majorY, axis: .y, color: .black.opacity(0.24), lineWidth: majorWidth)
        }

        let axisWidth = max(0.5, axisStyle.axisStrokeWidth)
        let origin = CalculatorGraphGeometry.viewPoint(forGraph: .zero, window: window, size: size)
        if origin.y >= 0, origin.y <= size.height {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: origin.y))
            path.addLine(to: CGPoint(x: size.width, y: origin.y))
            context.stroke(path, with: .color(.black.opacity(0.88)), lineWidth: axisWidth)
        }
        if origin.x >= 0, origin.x <= size.width {
            var path = Path()
            path.move(to: CGPoint(x: origin.x, y: 0))
            path.addLine(to: CGPoint(x: origin.x, y: size.height))
            context.stroke(path, with: .color(.black.opacity(0.88)), lineWidth: axisWidth)
        }

        drawLabels(in: context, size: size, window: window, xStep: majorX, yStep: majorY)
        drawAxisTitles(in: context, size: size, window: window, axisStyle: axisStyle)
    }

    private static func drawAxisTitles(in context: GraphicsContext, size: CGSize, window: GraphWindow, axisStyle: GraphAxisStyle) {
        let origin = CalculatorGraphGeometry.viewPoint(forGraph: .zero, window: window, size: size)

        let xTitle = axisStyle.xAxisLabel.trimmingCharacters(in: .whitespaces)
        if !xTitle.isEmpty {
            let labelY = min(max(origin.y, 20), size.height - 12)
            context.draw(
                Text(xTitle).font(.system(size: 14, weight: .semibold)).foregroundStyle(.black.opacity(0.82)),
                at: CGPoint(x: size.width - 8, y: labelY - 12),
                anchor: .trailing
            )
        }

        let yTitle = axisStyle.yAxisLabel.trimmingCharacters(in: .whitespaces)
        if !yTitle.isEmpty {
            let labelX = min(max(origin.x, 12), size.width - 12)
            context.draw(
                Text(yTitle).font(.system(size: 14, weight: .semibold)).foregroundStyle(.black.opacity(0.82)),
                at: CGPoint(x: labelX + 10, y: 10),
                anchor: .leading
            )
        }
    }

    private enum Axis {
        case x
        case y
    }

    private static func drawTicks(
        context: GraphicsContext,
        size: CGSize,
        window: GraphWindow,
        step: Double,
        axis: Axis,
        color: Color,
        lineWidth: CGFloat
    ) {
        let values = axis == .x
            ? CalculatorGraphGeometry.ticks(min: window.xMin, max: window.xMax, step: step)
            : CalculatorGraphGeometry.ticks(min: window.yMin, max: window.yMax, step: step)

        for value in values {
            let point = axis == .x
                ? CalculatorGraphGeometry.viewPoint(forGraph: CGPoint(x: value, y: 0), window: window, size: size)
                : CalculatorGraphGeometry.viewPoint(forGraph: CGPoint(x: 0, y: value), window: window, size: size)
            var path = Path()
            if axis == .x {
                path.move(to: CGPoint(x: point.x, y: 0))
                path.addLine(to: CGPoint(x: point.x, y: size.height))
            } else {
                path.move(to: CGPoint(x: 0, y: point.y))
                path.addLine(to: CGPoint(x: size.width, y: point.y))
            }
            context.stroke(path, with: .color(color), lineWidth: lineWidth)
        }
    }

    private static func drawLabels(in context: GraphicsContext, size: CGSize, window: GraphWindow, xStep: Double, yStep: Double) {
        let origin = CalculatorGraphGeometry.viewPoint(forGraph: .zero, window: window, size: size)
        let labelY = min(max(origin.y, 14), size.height - 14)
        let labelX = min(max(origin.x, 18), size.width - 22)

        for x in CalculatorGraphGeometry.ticks(min: window.xMin, max: window.xMax, step: xStep) where abs(x) > xStep * 1e-6 {
            let point = CalculatorGraphGeometry.viewPoint(forGraph: CGPoint(x: x, y: 0), window: window, size: size)
            context.draw(
                Text(label(for: x, step: xStep)).font(.system(size: 12)).foregroundStyle(.black.opacity(0.76)),
                at: CGPoint(x: point.x + 4, y: labelY + 12),
                anchor: .leading
            )
        }

        for y in CalculatorGraphGeometry.ticks(min: window.yMin, max: window.yMax, step: yStep) where abs(y) > yStep * 1e-6 {
            let point = CalculatorGraphGeometry.viewPoint(forGraph: CGPoint(x: 0, y: y), window: window, size: size)
            context.draw(
                Text(label(for: y, step: yStep)).font(.system(size: 12)).foregroundStyle(.black.opacity(0.76)),
                at: CGPoint(x: labelX - 6, y: point.y - 5),
                anchor: .trailing
            )
        }
    }

    private static func drawCurve(
        in context: GraphicsContext,
        size: CGSize,
        window: GraphWindow,
        compiled: CalculatorExpression,
        engine: CalculatorEngine,
        variableValues: [String: Double] = [:],
        color: Color,
        lineWidth: CGFloat,
        dashed: Bool = false,
        handDrawn: Bool = false
    ) {
        let samples = CalculatorGraphGeometry.sample(window: window, count: max(Int(size.width), 2)) { x in
            try? engine.evaluate(compiled: compiled, angleMode: .radians, variables: graphVariables(x: x, values: variableValues))
        }

        // Split the sampled curve into continuous runs (breaking at undefined values and asymptotes).
        var runs: [[CGPoint]] = []
        var current: [CGPoint] = []
        var previousY: Double?

        for sample in samples {
            guard let y = sample.y else {
                if !current.isEmpty { runs.append(current); current = [] }
                previousY = nil
                continue
            }
            if let previousY, abs(y - previousY) > window.height * 3 && previousY.sign != y.sign {
                if !current.isEmpty { runs.append(current); current = [] }
            }
            current.append(CalculatorGraphGeometry.viewPoint(forGraph: CGPoint(x: sample.x, y: y), window: window, size: size))
            previousY = y
        }
        if !current.isEmpty { runs.append(current) }

        if handDrawn && !dashed {
            for run in runs {
                strokeInkRun(in: context, points: run, baseWidth: lineWidth, color: color)
            }
            return
        }

        var path = Path()
        for run in runs {
            guard let first = run.first else { continue }
            path.move(to: first)
            for point in run.dropFirst() { path.addLine(to: point) }
        }
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round, dash: dashed ? [7, 5] : []))
    }

    /// Strokes a continuous polyline with a subtly fluctuating width to mimic a fountain-pen nib.
    /// The line is stroked in short arc-length chunks (not per pixel) so it stays performant.
    private static func strokeInkRun(in context: GraphicsContext, points: [CGPoint], baseWidth: CGFloat, color: Color) {
        guard points.count > 1 else {
            if let p = points.first {
                let r = baseWidth / 2
                context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: baseWidth, height: baseWidth)), with: .color(color))
            }
            return
        }

        let chunkLength: CGFloat = 9
        var arc: CGFloat = 0
        var i = 0
        while i < points.count - 1 {
            var sub = Path()
            sub.move(to: points[i])
            var segLength: CGFloat = 0
            var j = i
            while j < points.count - 1 && segLength < chunkLength {
                let a = points[j]
                let b = points[j + 1]
                sub.addLine(to: b)
                segLength += hypot(b.x - a.x, b.y - a.y)
                j += 1
            }
            let width = inkWidth(base: baseWidth, arc: arc)
            context.stroke(sub, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            arc += segLength
            i = max(j, i + 1)
        }
    }

    /// Smooth, deterministic width fluctuation (~ ±20%) along the stroke's arc length.
    private static func inkWidth(base: CGFloat, arc: CGFloat) -> CGFloat {
        let wobble = sin(arc * 0.035) * 0.6 + sin(arc * 0.011 + 1.3) * 0.4
        return max(0.6, base * (1 + 0.2 * wobble))
    }

    private static func drawPlot(
        in context: GraphicsContext,
        size: CGSize,
        window: GraphWindow,
        plot: GraphCalculatorPlot,
        engine: CalculatorEngine,
        variableValues: [String: Double],
        color: Color,
        lineWidth: CGFloat,
        handDrawn: Bool
    ) {
        switch plot {
        case .curve(let source):
            guard let compiled = try? engine.compile(source) else { return }
            drawCurve(in: context, size: size, window: window, compiled: compiled, engine: engine, variableValues: variableValues, color: color, lineWidth: lineWidth, handDrawn: handDrawn)
        case .yRelation(let source, let relation):
            guard let compiled = try? engine.compile(source) else { return }
            drawYRelation(in: context, size: size, window: window, compiled: compiled, engine: engine, variableValues: variableValues, relation: relation, color: color, lineWidth: lineWidth, handDrawn: handDrawn)
        case .xRelation(let source, let relation):
            guard let compiled = try? engine.compile(source),
                  let x = try? engine.evaluate(compiled: compiled, variables: variableValues),
                  x.isFinite else {
                return
            }
            drawXRelation(in: context, size: size, window: window, x: x, relation: relation, color: color, lineWidth: lineWidth)
        case .point(let x, let y):
            drawPoint(in: context, size: size, window: window, x: x, y: y, color: color, lineWidth: lineWidth)
        }
    }

    private static func drawPoint(
        in context: GraphicsContext,
        size: CGSize,
        window: GraphWindow,
        x: Double,
        y: Double,
        color: Color,
        lineWidth: CGFloat
    ) {
        let point = CalculatorGraphGeometry.viewPoint(forGraph: CGPoint(x: x, y: y), window: window, size: size)
        guard point.x.isFinite, point.y.isFinite else { return }
        let radius = max(4.5, min(8, lineWidth * 1.5))
        let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: rect), with: .color(color))
        context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.9)), lineWidth: 1.2)
    }

    private static func drawYRelation(
        in context: GraphicsContext,
        size: CGSize,
        window: GraphWindow,
        compiled: CalculatorExpression,
        engine: CalculatorEngine,
        variableValues: [String: Double],
        relation: GraphCalculatorYRelation,
        color: Color,
        lineWidth: CGFloat,
        handDrawn: Bool
    ) {
        if let shadesBelow = relation.shadesBelow {
            drawYRelationShading(
                in: context,
                size: size,
                window: window,
                compiled: compiled,
                engine: engine,
                variableValues: variableValues,
                shadesBelow: shadesBelow,
                color: color
            )
        }
        drawCurve(
            in: context,
            size: size,
            window: window,
            compiled: compiled,
            engine: engine,
            variableValues: variableValues,
            color: color,
            lineWidth: lineWidth,
            dashed: relation.isStrict,
            handDrawn: handDrawn
        )
    }

    private static func drawYRelationShading(
        in context: GraphicsContext,
        size: CGSize,
        window: GraphWindow,
        compiled: CalculatorExpression,
        engine: CalculatorEngine,
        variableValues: [String: Double],
        shadesBelow: Bool,
        color: Color
    ) {
        let samples = CalculatorGraphGeometry.sample(window: window, count: max(Int(size.width), 2)) { x in
            try? engine.evaluate(compiled: compiled, angleMode: .radians, variables: graphVariables(x: x, values: variableValues))
        }

        for pair in zip(samples, samples.dropFirst()) {
            guard let y1 = pair.0.y, let y2 = pair.1.y else { continue }
            let p1 = CalculatorGraphGeometry.viewPoint(forGraph: CGPoint(x: pair.0.x, y: y1), window: window, size: size)
            let p2 = CalculatorGraphGeometry.viewPoint(forGraph: CGPoint(x: pair.1.x, y: y2), window: window, size: size)
            guard p1.y.isFinite, p2.y.isFinite else { continue }

            let edgeY: CGFloat = shadesBelow ? size.height : 0
            var path = Path()
            path.move(to: p1)
            path.addLine(to: p2)
            path.addLine(to: CGPoint(x: p2.x, y: edgeY))
            path.addLine(to: CGPoint(x: p1.x, y: edgeY))
            path.closeSubpath()
            context.fill(path, with: .color(color.opacity(0.12)))
        }
    }

    private static func drawVerticalLine(
        in context: GraphicsContext,
        size: CGSize,
        window: GraphWindow,
        x: Double,
        color: Color,
        lineWidth: CGFloat,
        dashed: Bool = false
    ) {
        let point = CalculatorGraphGeometry.viewPoint(forGraph: CGPoint(x: x, y: 0), window: window, size: size)
        guard point.x.isFinite, point.x >= -1, point.x <= size.width + 1 else { return }

        var path = Path()
        path.move(to: CGPoint(x: point.x, y: 0))
        path.addLine(to: CGPoint(x: point.x, y: size.height))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: dashed ? [7, 5] : []))
    }

    private static func drawXRelation(
        in context: GraphicsContext,
        size: CGSize,
        window: GraphWindow,
        x: Double,
        relation: GraphCalculatorXRelation,
        color: Color,
        lineWidth: CGFloat
    ) {
        let point = CalculatorGraphGeometry.viewPoint(forGraph: CGPoint(x: x, y: 0), window: window, size: size)
        if let shadesLeft = relation.shadesLeft, point.x.isFinite {
            let leftX: CGFloat = shadesLeft ? 0 : point.x
            let rightX: CGFloat = shadesLeft ? point.x : size.width
            let rect = CGRect(
                x: min(leftX, rightX),
                y: 0,
                width: abs(rightX - leftX),
                height: size.height
            )
            if rect.width > 0 {
                context.fill(Path(rect), with: .color(color.opacity(0.12)))
            }
        }
        drawVerticalLine(in: context, size: size, window: window, x: x, color: color, lineWidth: lineWidth, dashed: relation.isStrict)
    }

    private static func graphVariables(x: Double, values: [String: Double]) -> [String: Double] {
        var variables = values
        variables["x"] = x
        return variables
    }

    private static func drawDataTables(
        in context: GraphicsContext,
        size: CGSize,
        window: GraphWindow,
        dataTables: [GraphCalculatorDataTable],
        fallback: Color
    ) {
        for (tableIndex, table) in dataTables.enumerated() {
            guard table.columnNames.count >= 2 else { continue }
            for columnIndex in 1..<table.columnNames.count {
                let color = color(for: tableIndex + columnIndex - 1, fallback: fallback)
                for row in table.rows {
                    guard row.indices.contains(0),
                          row.indices.contains(columnIndex),
                          let x = row[0],
                          let y = row[columnIndex],
                          x.isFinite,
                          y.isFinite else {
                        continue
                    }
                    let point = CalculatorGraphGeometry.viewPoint(forGraph: CGPoint(x: x, y: y), window: window, size: size)
                    guard point.x.isFinite, point.y.isFinite else { continue }
                    let rect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
                    context.fill(Path(ellipseIn: rect), with: .color(color))
                    context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.85)), lineWidth: 1)
                }
            }
        }
    }

    private static func color(for index: Int, fallback: Color) -> Color {
        guard !GraphPalette.colors.isEmpty else { return fallback }
        let rgb = GraphPalette.rgb(for: index)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    private static func color(for expression: GraphEquation, fallback: Color) -> Color {
        if let hue = expression.lineHue {
            return Color(hue: hue, saturation: 0.82, brightness: 0.90)
        }
        return color(for: expression.colorIndex, fallback: fallback)
    }

    private static func label(for value: Double, step: Double) -> String {
        if step >= 1, value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%g", value)
    }
}
