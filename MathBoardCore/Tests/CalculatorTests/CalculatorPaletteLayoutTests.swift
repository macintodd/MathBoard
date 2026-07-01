//
//  CalculatorPaletteLayoutTests.swift
//  MathBoardCore — Calculator module tests
//
//  Pure-logic coverage for the palette drag-clamping math.
//

import XCTest
import CoreGraphics
@testable import Calculator

final class CalculatorPaletteLayoutTests: XCTestCase {

    private let palette = CGSize(width: 360, height: 540)
    private let container = CGSize(width: 1000, height: 800)

    func testCenterWellInsideIsUnchanged() {
        let center = CGPoint(x: 500, y: 400)
        let clamped = CalculatorPaletteLayout.clamp(center: center, paletteSize: palette, in: container)
        XCTAssertEqual(clamped, center)
    }

    func testClampsLeftEdge() {
        // Center at x=0 would push the left half off-screen; min center.x
        // is half the palette width = 180.
        let clamped = CalculatorPaletteLayout.clamp(
            center: CGPoint(x: 0, y: 400),
            paletteSize: palette,
            in: container
        )
        XCTAssertEqual(clamped.x, 180)
        XCTAssertEqual(clamped.y, 400)
    }

    func testClampsRightEdge() {
        // Max center.x = container.width - half = 1000 - 180 = 820.
        let clamped = CalculatorPaletteLayout.clamp(
            center: CGPoint(x: 5000, y: 400),
            paletteSize: palette,
            in: container
        )
        XCTAssertEqual(clamped.x, 820)
    }

    func testClampsTopEdge() {
        // Min center.y = half palette height = 270.
        let clamped = CalculatorPaletteLayout.clamp(
            center: CGPoint(x: 500, y: -100),
            paletteSize: palette,
            in: container
        )
        XCTAssertEqual(clamped.y, 270)
    }

    func testClampsBottomEdge() {
        // Max center.y = 800 - 270 = 530.
        let clamped = CalculatorPaletteLayout.clamp(
            center: CGPoint(x: 500, y: 5000),
            paletteSize: palette,
            in: container
        )
        XCTAssertEqual(clamped.y, 530)
    }

    func testContainerSmallerThanPaletteCentersOnAxis() {
        // Container narrower than the palette on x → center on x.
        let narrow = CGSize(width: 200, height: 800)
        let clamped = CalculatorPaletteLayout.clamp(
            center: CGPoint(x: 999, y: 400),
            paletteSize: palette,
            in: narrow
        )
        XCTAssertEqual(clamped.x, 100, "Expected x centered at container midpoint")
        XCTAssertEqual(clamped.y, 400)
    }

    func testExactCornerStaysFullyVisible() {
        // Dragging to the bottom-right corner clamps to keep the card on screen.
        let clamped = CalculatorPaletteLayout.clamp(
            center: CGPoint(x: 1000, y: 800),
            paletteSize: palette,
            in: container
        )
        XCTAssertEqual(clamped, CGPoint(x: 820, y: 530))
    }
}
