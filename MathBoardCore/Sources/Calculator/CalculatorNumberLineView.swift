//
//  CalculatorNumberLineView.swift
//  MathBoardCore — Calculator module
//
//  Renders a 1D number line for the "1 Variable" topic. Draws an axis with
//  ticks across the domain, then one or more solution "layers" — each in
//  its own color, vertically offset so multiple inequalities are visible
//  on the same line. Filled dots = equality solutions; shaded segments
//  with open/closed end circles = inequality intervals.
//

import SwiftUI

struct NumberLineLayer: Equatable {
    let solution: SolutionSet
    let color: Color
}

struct CalculatorNumberLineView: View {
    let domain: ClosedRange<Double>
    let layers: [NumberLineLayer]

    init(domain: ClosedRange<Double>, layers: [NumberLineLayer]) {
        self.domain = domain
        self.layers = layers
    }

    /// Convenience for a single solution.
    init(domain: ClosedRange<Double>, solution: SolutionSet, color: Color) {
        self.init(domain: domain, layers: [NumberLineLayer(solution: solution, color: color)])
    }

    var body: some View {
        Canvas { context, size in
            guard size.width > 4, size.height > 4 else { return }
            let lower = domain.lowerBound
            let upper = domain.upperBound
            guard upper > lower else { return }

            let axisY = size.height / 2
            let leftPad: CGFloat = 12
            let usableWidth = size.width - leftPad * 2

            func viewX(_ value: Double) -> CGFloat {
                leftPad + CGFloat((value - lower) / (upper - lower)) * usableWidth
            }

            // Axis
            var axis = Path()
            axis.move(to: CGPoint(x: leftPad, y: axisY))
            axis.addLine(to: CGPoint(x: size.width - leftPad, y: axisY))
            context.stroke(axis, with: .color(CalculatorTheme.axis), lineWidth: 1.5)

            // Ticks + labels
            let step = CalculatorGraphGeometry.niceStep(range: upper - lower, targetCount: max(Int(size.width / 60), 2))
            for tick in CalculatorGraphGeometry.ticks(min: lower, max: upper, step: step) {
                let x = viewX(tick)
                var t = Path()
                t.move(to: CGPoint(x: x, y: axisY - 4))
                t.addLine(to: CGPoint(x: x, y: axisY + 4))
                context.stroke(t, with: .color(CalculatorTheme.axis), lineWidth: 1)
                context.draw(
                    Text(tickLabel(tick, step: step)).font(.system(size: 9)).foregroundStyle(CalculatorTheme.graphLabel),
                    at: CGPoint(x: x, y: axisY + 15)
                )
            }

            // Each layer at its own vertical offset.
            let count = layers.count
            for (index, layer) in layers.enumerated() {
                let offset = (CGFloat(index) - CGFloat(count - 1) / 2) * 12
                draw(layer: layer, in: context, y: axisY + offset, lower: lower, upper: upper, viewX: viewX)
            }
        }
    }

    private func draw(
        layer: NumberLineLayer,
        in context: GraphicsContext,
        y: CGFloat,
        lower: Double,
        upper: Double,
        viewX: (Double) -> CGFloat
    ) {
        switch layer.solution {
        case .discrete(let xs):
            for value in xs where value >= lower && value <= upper {
                let x = viewX(value)
                context.fill(Path(ellipseIn: CGRect(x: x - 5, y: y - 5, width: 10, height: 10)), with: .color(layer.color))
            }
        case .intervals(let intervals):
            for interval in intervals {
                if abs(interval.upper - interval.lower) < 1e-9 {
                    let x = viewX(interval.lower)
                    context.fill(Path(ellipseIn: CGRect(x: x - 5, y: y - 5, width: 10, height: 10)), with: .color(layer.color))
                    continue
                }
                let x0 = viewX(max(interval.lower, lower))
                let x1 = viewX(min(interval.upper, upper))
                var seg = Path()
                seg.move(to: CGPoint(x: x0, y: y))
                seg.addLine(to: CGPoint(x: x1, y: y))
                context.stroke(seg, with: .color(layer.color), lineWidth: 4)
                endpoint(context, x: x0, y: y, filled: interval.lowerInclusive, atEdge: interval.lower <= lower + 1e-9, color: layer.color)
                endpoint(context, x: x1, y: y, filled: interval.upperInclusive, atEdge: interval.upper >= upper - 1e-9, color: layer.color)
            }
        case .all:
            var seg = Path()
            seg.move(to: CGPoint(x: viewX(lower), y: y))
            seg.addLine(to: CGPoint(x: viewX(upper), y: y))
            context.stroke(seg, with: .color(layer.color), lineWidth: 4)
        case .none, .error:
            break
        }
    }

    private func endpoint(_ context: GraphicsContext, x: CGFloat, y: CGFloat, filled: Bool, atEdge: Bool, color: Color) {
        guard !atEdge else { return }
        let circle = Path(ellipseIn: CGRect(x: x - 5, y: y - 5, width: 10, height: 10))
        if filled {
            context.fill(circle, with: .color(color))
        } else {
            context.fill(circle, with: .color(.white))
            context.stroke(circle, with: .color(color), lineWidth: 2)
        }
    }

    private func tickLabel(_ value: Double, step: Double) -> String {
        if step >= 1, value.rounded() == value { return String(Int(value)) }
        return String(format: "%g", value)
    }
}
