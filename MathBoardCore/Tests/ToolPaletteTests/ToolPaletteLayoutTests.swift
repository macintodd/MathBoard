//
//  ToolPaletteLayoutTests.swift
//  MathBoardCore - ToolPalette tests
//

import Testing
@testable import ToolPalette

@Suite("Tool palette layout")
struct ToolPaletteLayoutTests {
    @Test func toolSlotAnglesAreEvenlySpaced() {
        let layout = RadialPaletteLayout(dialSize: 360)

        #expect(layout.toolSlotAngle(index: 0).isApproximatelyEqual(to: -157.5))
        #expect(layout.toolSlotAngle(index: 1).isApproximatelyEqual(to: -112.5))
        #expect(layout.toolSlotAngle(index: 2).isApproximatelyEqual(to: -67.5))
        #expect(layout.toolSlotAngle(index: 7).isApproximatelyEqual(to: 157.5))
    }

    @Test func toolSlotCenterUsesDialCenter() {
        let layout = RadialPaletteLayout(dialSize: 360)
        let center = layout.toolSlotCenter(index: 2)

        #expect(center.x > 180)
        #expect(center.y < 180)
    }

    @Test func orbitSingleItemCentersAtTop() {
        let layout = RadialPaletteLayout(dialSize: 360)
        let point = layout.orbitCenter(index: 0, count: 1)

        #expect(Double(point.x).isApproximatelyEqual(to: 180))
        #expect(point.y < 180)
    }

    @Test func leftArcAngleToValueMapping() {
        // Value increases from the outer end (160°, min) to the bottom-center
        // end (110°, max).
        let range = 1.0...24.0

        #expect(ToolPaletteArcMath.value(for: 160, side: .left, range: range).isApproximatelyEqual(to: 1))
        #expect(ToolPaletteArcMath.value(for: 135, side: .left, range: range).isApproximatelyEqual(to: 12.5))
        #expect(ToolPaletteArcMath.value(for: 110, side: .left, range: range).isApproximatelyEqual(to: 24))
    }

    @Test func rightArcValueToAngleMapping() {
        // Minimum maps to the outer end (70°), maximum to the bottom-center end (20°).
        let range = 0.1...1.0

        #expect(ToolPaletteArcMath.angle(for: 0.1, side: .right, range: range).isApproximatelyEqual(to: 70))
        #expect(ToolPaletteArcMath.angle(for: 1.0, side: .right, range: range).isApproximatelyEqual(to: 20))
    }

    @Test func slidersStayInBottomQuadrants() {
        // Both sliders must remain within the lower half (screen 0°–180°,
        // y-down) so their geometry is identical across every tool ring.
        let left = ToolPaletteArcMath.angleRange(for: .left)
        let right = ToolPaletteArcMath.angleRange(for: .right)

        #expect(left.lowerBound >= 90 && left.upperBound <= 180)
        #expect(right.lowerBound >= 0 && right.upperBound <= 90)
    }
}

private extension Double {
    func isApproximatelyEqual(to expected: Double, tolerance: Double = 0.001) -> Bool {
        abs(self - expected) <= tolerance
    }
}
