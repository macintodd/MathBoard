//
//  ToolPaletteLayout.swift
//  MathBoardCore - ToolPalette module
//

import CoreGraphics
import Foundation

public struct RadialPaletteLayout: Equatable, Sendable {
    public var dialSize: CGFloat
    public var center: CGPoint
    public var outerRadius: CGFloat
    public var wheelInnerRadius: CGFloat
    public var heroRadius: CGFloat
    public var orbitRadius: CGFloat

    /// Radius (in points) at which the active-tool option controls — colors and
    /// the width/opacity sliders — are placed. This is the outermost of the
    /// three concentric rings.
    public var optionRingRadius: CGFloat

    public init(dialSize: CGFloat) {
        self.dialSize = dialSize
        self.center = CGPoint(x: dialSize / 2, y: dialSize / 2)
        self.outerRadius = dialSize / 2
        // Ring 2 (tool selection) occupies the middle band.
        self.wheelInnerRadius = dialSize * 0.18
        // Ring 1 (inner hero / active tool).
        self.heroRadius = dialSize * 0.155
        // Ring 3 (active-tool options) — colors and sliders live here.
        self.orbitRadius = dialSize * 0.425
        self.optionRingRadius = dialSize * 0.425
    }

    public func toolSlotCenter(index: Int, count: Int = 8) -> CGPoint {
        point(angleDegrees: toolSlotAngle(index: index, count: count), radius: dialSize * 0.262)
    }

    public func toolSlotAngle(index: Int, count: Int = 8) -> Double {
        -157.5 + (Double(index) * 360.0 / Double(count))
    }

    public func orbitCenter(index: Int, count: Int) -> CGPoint {
        let start = -140.0
        let end = -40.0
        let angle: Double
        if count <= 1 {
            angle = -90
        } else {
            angle = start + ((end - start) * Double(index) / Double(count - 1))
        }
        return point(angleDegrees: angle, radius: orbitRadius)
    }

    public func point(angleDegrees: Double, radius: CGFloat) -> CGPoint {
        let radians = angleDegrees * .pi / 180
        return CGPoint(
            x: center.x + cos(radians) * radius,
            y: center.y + sin(radians) * radius
        )
    }
}

public enum PaletteArcSide: Equatable, Sendable {
    case left
    case right
}

public enum ToolPaletteArcMath {
    /// Angles (screen degrees) representing the minimum and maximum value. Value
    /// increases from `min` to `max`; these may be descending. Both sliders put
    /// the minimum at the outer end of the track (`angleRange.upperBound`) and
    /// the maximum at the bottom-center end (`angleRange.lowerBound`), so the
    /// "more" marker (thick line / dark circle) sits nearest 6 o'clock.
    public static func valueEndpoints(for side: PaletteArcSide) -> (min: Double, max: Double) {
        let range = angleRange(for: side)
        return (min: range.upperBound, max: range.lowerBound)
    }

    public static func normalizedValue(for angleDegrees: Double, side: PaletteArcSide) -> Double {
        let endpoints = valueEndpoints(for: side)
        let lo = min(endpoints.min, endpoints.max)
        let hi = max(endpoints.min, endpoints.max)
        let clamped = min(max(angleDegrees, lo), hi)
        return (clamped - endpoints.min) / (endpoints.max - endpoints.min)
    }

    public static func value(for angleDegrees: Double, side: PaletteArcSide, range: ClosedRange<Double>) -> Double {
        let normalized = normalizedValue(for: angleDegrees, side: side)
        return range.lowerBound + ((range.upperBound - range.lowerBound) * normalized)
    }

    public static func angle(for value: Double, side: PaletteArcSide, range: ClosedRange<Double>) -> Double {
        let normalized = (min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / (range.upperBound - range.lowerBound)
        let endpoints = valueEndpoints(for: side)
        return endpoints.min + ((endpoints.max - endpoints.min) * normalized)
    }

    // Sliders are confined to the bottom two quadrants so their geometry is
    // identical across every tool's outer ring. Angles are in screen space
    // (clockwise, y-down). Expressed in standard math coordinates these are the
    // left slider at 200°–250° (quadrant 3) and the right slider at 290°–340°
    // (quadrant 4); screen = 360 − math.
    public static func angleRange(for side: PaletteArcSide) -> ClosedRange<Double> {
        switch side {
        case .left:
            return 110...160
        case .right:
            return 20...70
        }
    }
}
