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
    var gridlineOpacity: CGFloat = 0.24
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

/// A set of teacher-added ordered pairs (from a point row's table) to plot in a row's style.
struct GraphAttachedPoints {
    /// Points in graph coordinates.
    var points: [CGPoint]
    var color: Color
    var lineWidth: CGFloat
}

/// A point from a visible function-table row, plotted on the trace overlay.
struct GraphTracePoint {
    var point: CGPoint
    var rowIndex: Int
}

/// The live trace overlay for a function table: the selected point, the visible table points
/// along the curve, and the selected point's ordered-pair label. All points are in graph coordinates.
struct GraphTraceOverlay {
    var anchor: CGPoint
    var points: [GraphTracePoint]
    var color: Color
    var lineWidth: CGFloat
    var label: String
    var specialKind: GraphCalculatorPointReadout.Kind?
    var secondary: GraphTraceSeries? = nil
}

struct GraphTraceSeries {
    var anchor: CGPoint
    var points: [GraphTracePoint]
    var color: Color
    var lineWidth: CGFloat
    var label: String
    var specialKind: GraphCalculatorPointReadout.Kind?
}

enum GraphHighlightPalette {
    /// Warm gold — curve–curve intersection points.
    static let intersection = Color(red: 0.98, green: 0.70, blue: 0.11)
    /// Cyan/teal — x-intercepts.
    static let xIntercept = Color(red: 0.10, green: 0.72, blue: 0.78)
    /// Violet — y-intercepts.
    static let yIntercept = Color(red: 0.60, green: 0.30, blue: 0.92)
    /// Coral — plotted ordered-pair rows and attached point-table points.
    static let plottedPoint = Color(red: 0.96, green: 0.36, blue: 0.24)

    static func color(for kind: GraphCalculatorPointReadout.Kind) -> Color {
        switch kind {
        case .intersection: return intersection
        case .xIntercept: return xIntercept
        case .yIntercept: return yIntercept
        case .plottedPoint: return plottedPoint
        }
    }

    /// Label text color chosen for contrast against the (filled) bubble color.
    static func labelColor(for kind: GraphCalculatorPointReadout.Kind) -> Color {
        switch kind {
        case .intersection: return .black.opacity(0.82) // dark on bright gold
        case .xIntercept, .yIntercept, .plottedPoint: return .white
        }
    }
}

enum GraphCalculatorRenderer {
    static func draw(
        in context: GraphicsContext,
        size: CGSize,
        window: GraphWindow,
        expressions: [GraphEquation],
        engine: CalculatorEngine,
        variableValues: [String: Double] = [:],
        accent: Color,
        axisStyle: GraphAxisStyle = .default,
        highlightedPoint: GraphCalculatorPointReadout? = nil,
        attachedPoints: [GraphAttachedPoints] = [],
        trace: GraphTraceOverlay? = nil
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

        for set in attachedPoints {
            for graphPoint in set.points {
                drawPoint(in: context, size: size, window: window, x: Double(graphPoint.x), y: Double(graphPoint.y), color: set.color, lineWidth: set.lineWidth)
            }
        }

        if let trace {
            drawTrace(in: context, size: size, window: window, trace: trace)
        }

        if let highlightedPoint {
            drawHighlightedPoint(in: context, size: size, window: window, point: highlightedPoint)
        }
    }

    /// Draws a tapped-out notable point (x-intercept, y-intercept, or intersection) as a glowing
    /// dot with its ordered-pair label. Each kind uses its own color from `GraphHighlightPalette`.
    private static func drawHighlightedPoint(
        in context: GraphicsContext,
        size: CGSize,
        window: GraphWindow,
        point: GraphCalculatorPointReadout
    ) {
        let center = CalculatorGraphGeometry.viewPoint(forGraph: CGPoint(x: point.x, y: point.y), window: window, size: size)
        guard center.x.isFinite, center.y.isFinite else { return }

        let color = GraphHighlightPalette.color(for: point.kind)

        // Layered blurred halos give a genuine glow around the point.
        var glow = context
        glow.addFilter(.blur(radius: 9))
        for haloRadius in [18, 12] as [CGFloat] {
            let rect = CGRect(x: center.x - haloRadius, y: center.y - haloRadius, width: haloRadius * 2, height: haloRadius * 2)
            glow.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.55)))
        }
        let coreGlow = CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)
        glow.fill(Path(ellipseIn: coreGlow), with: .color(.white.opacity(0.9)))

        let radius: CGFloat = 7
        let dotRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: dotRect), with: .color(color))
        context.stroke(Path(ellipseIn: dotRect), with: .color(.white), lineWidth: 2)
        // A bright inner pip to make the dot read as "lit".
        let pip = CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4)
        context.fill(Path(ellipseIn: pip), with: .color(.white))

        let text = "(\(coordinateLabel(point.x)), \(coordinateLabel(point.y)))"
        drawLabelBubble(
            in: context,
            near: center,
            markerRadius: radius,
            size: size,
            text: text,
            fill: color,
            textColor: GraphHighlightPalette.labelColor(for: point.kind)
        )
    }

    /// Draws a rounded label bubble anchored above (or, near the top edge, below) a marker.
    private static func drawLabelBubble(
        in context: GraphicsContext,
        near center: CGPoint,
        markerRadius: CGFloat,
        size: CGSize,
        text: String,
        fill: Color,
        textColor: Color
    ) {
        let resolved = context.resolve(
            Text(text)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(textColor)
        )
        let textSize = resolved.measure(in: CGSize(width: 240, height: 60))
        let padding = CGSize(width: 10, height: 5)
        let bubbleWidth = textSize.width + padding.width * 2
        let bubbleHeight = textSize.height + padding.height * 2

        var bubbleY = center.y - markerRadius - 8 - bubbleHeight / 2
        if bubbleY - bubbleHeight / 2 < 4 {
            bubbleY = center.y + markerRadius + 8 + bubbleHeight / 2
        }
        let bubbleX = min(max(center.x, bubbleWidth / 2 + 4), size.width - bubbleWidth / 2 - 4)

        let bubbleRect = CGRect(
            x: bubbleX - bubbleWidth / 2,
            y: bubbleY - bubbleHeight / 2,
            width: bubbleWidth,
            height: bubbleHeight
        )
        context.fill(
            Path(roundedRect: bubbleRect, cornerRadius: 7, style: .continuous),
            with: .color(fill)
        )
        context.draw(resolved, at: CGPoint(x: bubbleX, y: bubbleY), anchor: .center)
    }

    /// Draws the trace overlay: a faint vertical guide at the anchor x, a dot at each table point,
    /// and a ringed, labeled marker at the anchor (the finger / table-start point).
    private static func drawTrace(
        in context: GraphicsContext,
        size: CGSize,
        window: GraphWindow,
        trace: GraphTraceOverlay
    ) {
        let anchorView = CalculatorGraphGeometry.viewPoint(forGraph: trace.anchor, window: window, size: size)
        guard anchorView.x.isFinite, anchorView.y.isFinite else { return }

        // Faint vertical guide line at the traced x.
        if anchorView.x >= 0, anchorView.x <= size.width {
            var guide = Path()
            guide.move(to: CGPoint(x: anchorView.x, y: 0))
            guide.addLine(to: CGPoint(x: anchorView.x, y: size.height))
            context.stroke(guide, with: .color(trace.color.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }

        // A dot at each table point along the curve.
        for tracePoint in trace.points {
            let view = CalculatorGraphGeometry.viewPoint(forGraph: tracePoint.point, window: window, size: size)
            guard view.x.isFinite, view.y.isFinite else { continue }
            let r: CGFloat = 4
            let rect = CGRect(x: view.x - r, y: view.y - r, width: r * 2, height: r * 2)
            context.fill(Path(ellipseIn: rect), with: .color(trace.color))
            context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.9)), lineWidth: 1)
        }

        if let secondary = trace.secondary {
            drawTraceSeries(in: context, size: size, window: window, series: secondary)
        }

        if let specialKind = trace.specialKind {
            drawHighlightedPoint(
                in: context,
                size: size,
                window: window,
                point: GraphCalculatorPointReadout(
                    x: Double(trace.anchor.x),
                    y: Double(trace.anchor.y),
                    kind: specialKind
                )
            )
            return
        }

        // The selected trace point: larger ringed marker plus label.
        let radius: CGFloat = 7
        let dotRect = CGRect(x: anchorView.x - radius, y: anchorView.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: dotRect), with: .color(trace.color))
        context.stroke(Path(ellipseIn: dotRect), with: .color(.white), lineWidth: 2)
        drawLabelBubble(
            in: context,
            near: anchorView,
            markerRadius: radius,
            size: size,
            text: trace.label,
            fill: trace.color,
            textColor: .white
        )
    }

    private static func drawTraceSeries(
        in context: GraphicsContext,
        size: CGSize,
        window: GraphWindow,
        series: GraphTraceSeries
    ) {
        for tracePoint in series.points {
            let view = CalculatorGraphGeometry.viewPoint(forGraph: tracePoint.point, window: window, size: size)
            guard view.x.isFinite, view.y.isFinite else { continue }
            let r: CGFloat = 4
            let rect = CGRect(x: view.x - r, y: view.y - r, width: r * 2, height: r * 2)
            context.fill(Path(ellipseIn: rect), with: .color(series.color))
            context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.9)), lineWidth: 1)
        }

        if let specialKind = series.specialKind {
            drawHighlightedPoint(
                in: context,
                size: size,
                window: window,
                point: GraphCalculatorPointReadout(
                    x: Double(series.anchor.x),
                    y: Double(series.anchor.y),
                    kind: specialKind
                )
            )
            return
        }

        let anchorView = CalculatorGraphGeometry.viewPoint(forGraph: series.anchor, window: window, size: size)
        guard anchorView.x.isFinite, anchorView.y.isFinite else { return }
        let radius: CGFloat = 7
        let dotRect = CGRect(x: anchorView.x - radius, y: anchorView.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: dotRect), with: .color(series.color))
        context.stroke(Path(ellipseIn: dotRect), with: .color(.white), lineWidth: 2)
        drawLabelBubble(
            in: context,
            near: anchorView,
            markerRadius: radius,
            size: size,
            text: series.label,
            fill: series.color,
            textColor: .white
        )
    }

    /// Compact coordinate formatting: trims trailing zeros and rounds off floating-point noise.
    private static func coordinateLabel(_ value: Double) -> String {
        let rounded = (value * 1e6).rounded() / 1e6
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%g", rounded)
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
            let majorOpacity = min(max(axisStyle.gridlineOpacity, 0.02), 0.85)
            let minorOpacity = min(max(majorOpacity * 0.42, 0.02), 0.60)
            drawTicks(context: context, size: size, window: window, step: minorX, axis: .x, color: .black.opacity(minorOpacity), lineWidth: minorWidth)
            drawTicks(context: context, size: size, window: window, step: minorY, axis: .y, color: .black.opacity(minorOpacity), lineWidth: minorWidth)
            drawTicks(context: context, size: size, window: window, step: majorX, axis: .x, color: .black.opacity(majorOpacity), lineWidth: majorWidth)
            drawTicks(context: context, size: size, window: window, step: majorY, axis: .y, color: .black.opacity(majorOpacity), lineWidth: majorWidth)
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
        case .implicitRelation(let source):
            guard let compiled = try? engine.compile(source) else { return }
            drawImplicitRelation(in: context, size: size, window: window, compiled: compiled, engine: engine, variableValues: variableValues, color: color, lineWidth: lineWidth, handDrawn: handDrawn)
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

    private static func drawImplicitRelation(
        in context: GraphicsContext,
        size: CGSize,
        window: GraphWindow,
        compiled: CalculatorExpression,
        engine: CalculatorEngine,
        variableValues: [String: Double],
        color: Color,
        lineWidth: CGFloat,
        handDrawn: Bool
    ) {
        let columns = max(36, min(140, Int(size.width / 5)))
        let rows = max(36, min(140, Int(size.height / 5)))
        let dx = window.width / Double(columns)
        let dy = window.height / Double(rows)
        guard dx.isFinite, dy.isFinite, dx > 0, dy > 0 else { return }

        var values = Array(repeating: Array<Double?>(repeating: nil, count: rows + 1), count: columns + 1)
        for ix in 0...columns {
            let x = window.xMin + Double(ix) * dx
            for iy in 0...rows {
                let y = window.yMin + Double(iy) * dy
                values[ix][iy] = evaluateImplicit(compiled: compiled, engine: engine, x: x, y: y, values: variableValues)
            }
        }

        var path = Path()
        var inkRuns: [[CGPoint]] = []

        for ix in 0..<columns {
            for iy in 0..<rows {
                guard let bottomLeft = values[ix][iy],
                      let bottomRight = values[ix + 1][iy],
                      let topRight = values[ix + 1][iy + 1],
                      let topLeft = values[ix][iy + 1] else {
                    continue
                }

                let x0 = window.xMin + Double(ix) * dx
                let x1 = x0 + dx
                let y0 = window.yMin + Double(iy) * dy
                let y1 = y0 + dy
                let corners = [
                    (value: bottomLeft, point: CGPoint(x: x0, y: y0)),
                    (value: bottomRight, point: CGPoint(x: x1, y: y0)),
                    (value: topRight, point: CGPoint(x: x1, y: y1)),
                    (value: topLeft, point: CGPoint(x: x0, y: y1))
                ]
                let edgePairs = [(0, 1), (1, 2), (2, 3), (3, 0)]
                let crossings = edgePairs.compactMap { a, b -> CGPoint? in
                    zeroCrossing(from: corners[a], to: corners[b])
                }

                guard crossings.count >= 2 else { continue }
                let screenPoints = crossings.map {
                    CalculatorGraphGeometry.viewPoint(forGraph: $0, window: window, size: size)
                }.filter { $0.x.isFinite && $0.y.isFinite }
                guard screenPoints.count >= 2 else { continue }

                for pairIndex in stride(from: 0, to: screenPoints.count - 1, by: 2) {
                    let start = screenPoints[pairIndex]
                    let end = screenPoints[pairIndex + 1]
                    if handDrawn {
                        inkRuns.append([start, end])
                    } else {
                        path.move(to: start)
                        path.addLine(to: end)
                    }
                }
            }
        }

        if handDrawn {
            for run in inkRuns {
                strokeInkRun(in: context, points: run, baseWidth: lineWidth, color: color)
            }
        } else {
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }

    private static func evaluateImplicit(
        compiled: CalculatorExpression,
        engine: CalculatorEngine,
        x: Double,
        y: Double,
        values: [String: Double]
    ) -> Double? {
        var variables = values
        variables["x"] = x
        variables["y"] = y
        guard let value = try? engine.evaluate(compiled: compiled, angleMode: .radians, variables: variables),
              value.isFinite else {
            return nil
        }
        return value
    }

    private static func zeroCrossing(
        from a: (value: Double, point: CGPoint),
        to b: (value: Double, point: CGPoint)
    ) -> CGPoint? {
        if abs(a.value) < 1e-9 { return a.point }
        if abs(b.value) < 1e-9 { return b.point }
        guard a.value.sign != b.value.sign else { return nil }
        let t = abs(a.value) / (abs(a.value) + abs(b.value))
        return CGPoint(
            x: a.point.x + (b.point.x - a.point.x) * t,
            y: a.point.y + (b.point.y - a.point.y) * t
        )
    }

    private static func graphVariables(x: Double, values: [String: Double]) -> [String: Double] {
        var variables = values
        variables["x"] = x
        return variables
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
