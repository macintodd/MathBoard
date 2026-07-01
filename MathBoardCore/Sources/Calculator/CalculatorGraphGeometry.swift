//
//  CalculatorGraphGeometry.swift
//  MathBoardCore — Calculator module
//
//  Pure graphing math: coordinate transforms between graph-space and
//  view-space, pan/zoom of the graph window, "nice" gridline tick steps,
//  and function sampling. SwiftUI-free so it can be unit-tested without a
//  view host. The plot view in `CalculatorGraphView` consumes these.
//
//  Coordinate conventions:
//    • Graph space: math (x, y), y grows UP.
//    • View space: pixels in the plot rect, origin top-left, y grows DOWN.
//

import Foundation
import CoreGraphics

public enum CalculatorGraphGeometry {

    /// Smallest allowed window span on either axis, to avoid divide-by-zero
    /// and runaway zoom-in.
    public static let minimumSpan: Double = 1e-6
    /// Largest allowed window span, to avoid runaway zoom-out.
    public static let maximumSpan: Double = 1e9

    // MARK: - Transforms

    /// Map a graph-space point to a view-space point inside `size`.
    public static func viewPoint(
        forGraph point: CGPoint,
        window: GraphWindow,
        size: CGSize
    ) -> CGPoint {
        let vx = (Double(point.x) - window.xMin) / window.width * Double(size.width)
        let vy = Double(size.height) - (Double(point.y) - window.yMin) / window.height * Double(size.height)
        return CGPoint(x: vx, y: vy)
    }

    /// Map a view-space point back to graph-space.
    public static func graphPoint(
        forView point: CGPoint,
        window: GraphWindow,
        size: CGSize
    ) -> CGPoint {
        let x = window.xMin + (Double(point.x) / Double(size.width)) * window.width
        let y = window.yMin + (Double(size.height - point.y) / Double(size.height)) * window.height
        return CGPoint(x: x, y: y)
    }

    // MARK: - Pan

    /// Pan the window by a view-space drag translation. Dragging right
    /// reveals lower-x content (window shifts left); dragging down reveals
    /// higher-y content (window shifts up).
    public static func pan(
        window: GraphWindow,
        byViewTranslation translation: CGSize,
        size: CGSize
    ) -> GraphWindow {
        guard size.width > 0, size.height > 0 else { return window }
        let dx = Double(translation.width) / Double(size.width) * window.width
        let dy = Double(translation.height) / Double(size.height) * window.height
        return GraphWindow(
            xMin: window.xMin - dx,
            xMax: window.xMax - dx,
            yMin: window.yMin + dy,
            yMax: window.yMax + dy
        )
    }

    // MARK: - Zoom

    /// Zoom the window around a focal view-point. `magnification > 1`
    /// zooms in (window shrinks); `< 1` zooms out. The focal graph point
    /// stays fixed on screen. Spans are clamped to [minimumSpan,
    /// maximumSpan].
    public static func zoom(
        window: GraphWindow,
        magnification: Double,
        aroundViewPoint viewPoint: CGPoint,
        size: CGSize
    ) -> GraphWindow {
        guard magnification > 0, size.width > 0, size.height > 0 else { return window }

        let focal = graphPoint(forView: viewPoint, window: window, size: size)
        let scale = 1 / magnification

        var newXMin = Double(focal.x) - (Double(focal.x) - window.xMin) * scale
        var newXMax = Double(focal.x) + (window.xMax - Double(focal.x)) * scale
        var newYMin = Double(focal.y) - (Double(focal.y) - window.yMin) * scale
        var newYMax = Double(focal.y) + (window.yMax - Double(focal.y)) * scale

        (newXMin, newXMax) = clampSpan(min: newXMin, max: newXMax, focal: Double(focal.x))
        (newYMin, newYMax) = clampSpan(min: newYMin, max: newYMax, focal: Double(focal.y))

        return GraphWindow(xMin: newXMin, xMax: newXMax, yMin: newYMin, yMax: newYMax)
    }

    private static func clampSpan(min lo: Double, max hi: Double, focal: Double) -> (Double, Double) {
        let span = hi - lo
        if span < minimumSpan {
            return (focal - minimumSpan / 2, focal + minimumSpan / 2)
        }
        if span > maximumSpan {
            return (focal - maximumSpan / 2, focal + maximumSpan / 2)
        }
        return (lo, hi)
    }

    // MARK: - Tick steps

    /// A "nice" step (1, 2, or 5 × 10ⁿ) for the given range and a target
    /// number of intervals. Used for gridline spacing.
    public static func niceStep(range: Double, targetCount: Int) -> Double {
        guard range > 0, targetCount > 0 else { return 1 }
        let raw = range / Double(targetCount)
        let magnitude = pow(10, floor(log10(raw)))
        let normalized = raw / magnitude
        let nice: Double
        if normalized < 1.5 { nice = 1 }
        else if normalized < 3 { nice = 2 }
        else if normalized < 7 { nice = 5 }
        else { nice = 10 }
        return nice * magnitude
    }

    /// Tick values in [min, max] at multiples of `step`, starting at the
    /// first multiple ≥ min. Guards against pathological step counts.
    public static func ticks(min lo: Double, max hi: Double, step: Double) -> [Double] {
        guard step > 0, hi > lo else { return [] }
        // Refuse to emit an absurd number of ticks.
        guard (hi - lo) / step < 1000 else { return [] }

        var values: [Double] = []
        let first = (lo / step).rounded(.up) * step
        var value = first
        // Small epsilon so the last tick at exactly `hi` isn't dropped to
        // floating-point error.
        let epsilon = step * 1e-6
        while value <= hi + epsilon {
            values.append(value)
            value += step
        }
        return values
    }

    // MARK: - Sampling

    /// One sampled column: the x value and the function's y there, or nil
    /// if the function is undefined / non-finite at that x.
    public struct Sample: Equatable, Sendable {
        public let x: Double
        public let y: Double?
        public init(x: Double, y: Double?) {
            self.x = x
            self.y = y
        }
    }

    /// Sample `eval` across the window's x-range at `count` evenly-spaced
    /// columns. A returned y of nil marks a break (undefined / non-finite)
    /// so the plot can lift the pen there.
    public static func sample(
        window: GraphWindow,
        count: Int,
        eval: (Double) -> Double?
    ) -> [Sample] {
        guard count >= 2, window.width > 0 else { return [] }
        var samples: [Sample] = []
        samples.reserveCapacity(count)
        let step = window.width / Double(count - 1)
        for index in 0..<count {
            let x = window.xMin + Double(index) * step
            let raw = eval(x)
            if let raw, raw.isFinite {
                samples.append(Sample(x: x, y: raw))
            } else {
                samples.append(Sample(x: x, y: nil))
            }
        }
        return samples
    }
}
