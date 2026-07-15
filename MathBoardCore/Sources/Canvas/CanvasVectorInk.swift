//
//  CanvasVectorInk.swift
//  MathBoardCore - Canvas module
//
//  Lightweight renderer helpers for MathBoard's presentation-side vector ink.
//  PencilKit still owns the committed drawing for now; this code shapes the
//  temporary live stroke shown on external displays while PencilKit is drawing.
//

import CoreGraphics
import SwiftUI

public enum CanvasVectorInk {
    private static let minimumPointSpacing: CGFloat = 2.0
    private static let smoothing: CGFloat = 0.18
    private static let presentationWidthScale: CGFloat = 0.82
    private static let minimumWidthScale: CGFloat = 0.18
    private static let maximumWidthScale: CGFloat = 0.78

    public static func smoothedPath(points: [CGPoint]) -> Path {
        Path { path in
            let points = filtered(points)
            guard let firstPoint = points.first else { return }

            if points.count == 1 {
                path.move(to: firstPoint)
                path.addLine(to: firstPoint)
                return
            }

            if points.count == 2 {
                path.move(to: firstPoint)
                path.addLine(to: points[1])
                return
            }

            path.move(to: firstPoint)

            for index in 1..<(points.count - 1) {
                let current = points[index]
                let next = points[index + 1]
                let midpoint = CGPoint(
                    x: (current.x + next.x) / 2,
                    y: (current.y + next.y) / 2
                )
                path.addQuadCurve(to: midpoint, control: current)
            }

            if let penultimate = points.dropLast().last,
               let last = points.last {
                path.addQuadCurve(to: last, control: penultimate)
            }
        }
    }

    public static func smoothedSegments(
        samples: [CanvasLiveStrokePoint],
        baseLineWidth: CGFloat
    ) -> [(path: Path, lineWidth: CGFloat)] {
        let samples = filtered(samples)
        guard samples.count > 1 else { return [] }

        return (0..<(samples.count - 1)).map { index in
            let previous = samples[max(index - 1, 0)]
            let current = samples[index]
            let next = samples[index + 1]
            let following = samples[min(index + 2, samples.count - 1)]

            let path = Path { path in
                path.move(to: current.location)
                path.addCurve(
                    to: next.location,
                    control1: controlPoint(
                        from: current.location,
                        toward: next.location,
                        awayFrom: previous.location
                    ),
                    control2: controlPoint(
                        from: next.location,
                        toward: current.location,
                        awayFrom: following.location
                    )
                )
            }

            return (
                path: path,
                lineWidth: baseLineWidth * widthScale(
                    at: index,
                    in: samples,
                    current: current,
                    next: next
                )
            )
        }
    }

    public static func crispLineWidth(baseLineWidth: CGFloat) -> CGFloat {
        baseLineWidth * presentationWidthScale
    }

    private static func filtered(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 2 else { return points }

        var filteredPoints: [CGPoint] = []
        filteredPoints.reserveCapacity(points.count)

        for point in points {
            guard let previous = filteredPoints.last else {
                filteredPoints.append(point)
                continue
            }

            if distance(from: previous, to: point) >= Self.minimumPointSpacing {
                filteredPoints.append(point)
            }
        }

        if filteredPoints.last != points.last, let lastPoint = points.last {
            filteredPoints.append(lastPoint)
        }

        return filteredPoints
    }

    private static func filtered(_ samples: [CanvasLiveStrokePoint]) -> [CanvasLiveStrokePoint] {
        guard samples.count > 2 else { return samples }

        var filteredSamples: [CanvasLiveStrokePoint] = []
        filteredSamples.reserveCapacity(samples.count)

        for sample in samples {
            guard let previous = filteredSamples.last else {
                filteredSamples.append(sample)
                continue
            }

            if distance(from: previous.location, to: sample.location) >= Self.minimumPointSpacing {
                filteredSamples.append(sample)
            }
        }

        if filteredSamples.last != samples.last, let lastSample = samples.last {
            filteredSamples.append(lastSample)
        }

        return filteredSamples
    }

    private static func controlPoint(from point: CGPoint, toward target: CGPoint, awayFrom opposite: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x + (target.x - opposite.x) * Self.smoothing,
            y: point.y + (target.y - opposite.y) * Self.smoothing
        )
    }

    private static func widthScale(
        at index: Int,
        in samples: [CanvasLiveStrokePoint],
        current: CanvasLiveStrokePoint,
        next: CanvasLiveStrokePoint
    ) -> CGFloat {
        let progress = CGFloat(index) / CGFloat(max(samples.count - 2, 1))
        let taper = taperScale(progress: progress)
        let pressure = min(max((current.pressure + next.pressure) / 2, 0), 1)
        let pressureScale = 0.82 + pressure * 0.34

        let elapsed = max(next.timestamp - current.timestamp, 0.001)
        let speed = distance(from: current.location, to: next.location) / CGFloat(elapsed)
        let speedProgress = min(max((speed - 80) / 1100, 0), 1)
        let velocityScale = 1.08 - speedProgress * 0.22

        let widthScale = taper * pressureScale * velocityScale * Self.presentationWidthScale
        return min(max(widthScale, Self.minimumWidthScale), Self.maximumWidthScale)
    }

    private static func taperScale(progress: CGFloat) -> CGFloat {
        let lead = min(max(progress / 0.14, 0), 1)
        let tail = min(max((1 - progress) / 0.18, 0), 1)
        let eased = min(easeOut(lead), easeOut(tail))
        return 0.34 + eased * 0.66
    }

    private static func easeOut(_ value: CGFloat) -> CGFloat {
        1 - pow(1 - min(max(value, 0), 1), 2)
    }

    private static func distance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}
