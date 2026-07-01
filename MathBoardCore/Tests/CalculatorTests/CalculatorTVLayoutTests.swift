//
//  CalculatorTVLayoutTests.swift
//  MathBoardCore — Calculator module tests
//
//  Pure-logic coverage for mapping the iPad palette position into the TV
//  overlay's bounds.
//

import XCTest
import CoreGraphics
@testable import Calculator

final class CalculatorTVLayoutTests: XCTestCase {

    private let palette = CGSize(width: 360, height: 540)
    private let reference = CGSize(width: 1000, height: 800)
    // TV is 2× the reference on each axis (same aspect ratio).
    private let tv = CGSize(width: 2000, height: 1600)

    func testNilPositionMapsToReferenceCenterThenScales() {
        let placement = CalculatorTVLayout.placement(
            position: nil,
            paletteSize: palette,
            referenceSize: reference,
            tvSize: tv
        )
        // Reference center (500,400) → fraction (0.5,0.5) → TV (1000,800).
        XCTAssertEqual(placement.center, CGPoint(x: 1000, y: 800))
        XCTAssertEqual(placement.scale, 2, accuracy: 1e-9)
    }

    func testCornerPositionPreservesFraction() {
        // Palette center near iPad top-left at (100, 80) → fraction (0.1, 0.1)
        // → TV (200, 160).
        let placement = CalculatorTVLayout.placement(
            position: CGPoint(x: 100, y: 80),
            paletteSize: palette,
            referenceSize: reference,
            tvSize: tv
        )
        XCTAssertEqual(placement.center.x, 200, accuracy: 1e-9)
        XCTAssertEqual(placement.center.y, 160, accuracy: 1e-9)
    }

    func testScaleIsWidthRatio() {
        let placement = CalculatorTVLayout.placement(
            position: CGPoint(x: 500, y: 400),
            paletteSize: palette,
            referenceSize: reference,
            tvSize: CGSize(width: 1500, height: 1200)
        )
        XCTAssertEqual(placement.scale, 1.5, accuracy: 1e-9)
    }

    func testZeroReferenceFallsBackToTVCenter() {
        let placement = CalculatorTVLayout.placement(
            position: CGPoint(x: 100, y: 100),
            paletteSize: palette,
            referenceSize: .zero,
            tvSize: tv
        )
        XCTAssertEqual(placement.center, CGPoint(x: 1000, y: 800))
        XCTAssertEqual(placement.scale, 1, accuracy: 1e-9)
    }

    func testSameSizeIsIdentityScale() {
        let placement = CalculatorTVLayout.placement(
            position: CGPoint(x: 300, y: 200),
            paletteSize: palette,
            referenceSize: reference,
            tvSize: reference
        )
        XCTAssertEqual(placement.scale, 1, accuracy: 1e-9)
        XCTAssertEqual(placement.center, CGPoint(x: 300, y: 200))
    }
}
