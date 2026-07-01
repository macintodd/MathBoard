//
//  CalculatorGraphGeometryTests.swift
//  MathBoardCore — Calculator module tests
//
//  Pure-logic coverage for graph coordinate transforms, pan, zoom, tick
//  steps, and function sampling.
//

import XCTest
import CoreGraphics
@testable import Calculator

final class GraphTransformTests: XCTestCase {

    private let window = GraphWindow(xMin: -10, xMax: 10, yMin: -10, yMax: 10)
    private let size = CGSize(width: 200, height: 200)

    func testOriginMapsToCenter() {
        let p = CalculatorGraphGeometry.viewPoint(forGraph: .zero, window: window, size: size)
        XCTAssertEqual(p.x, 100, accuracy: 1e-9)
        XCTAssertEqual(p.y, 100, accuracy: 1e-9)
    }

    func testTopRightCornerMapping() {
        // Graph (10, 10) → view (200, 0): right edge, top (y flipped).
        let p = CalculatorGraphGeometry.viewPoint(forGraph: CGPoint(x: 10, y: 10), window: window, size: size)
        XCTAssertEqual(p.x, 200, accuracy: 1e-9)
        XCTAssertEqual(p.y, 0, accuracy: 1e-9)
    }

    func testRoundTripTransform() {
        let graph = CGPoint(x: 3.5, y: -7.25)
        let view = CalculatorGraphGeometry.viewPoint(forGraph: graph, window: window, size: size)
        let back = CalculatorGraphGeometry.graphPoint(forView: view, window: window, size: size)
        XCTAssertEqual(Double(back.x), Double(graph.x), accuracy: 1e-9)
        XCTAssertEqual(Double(back.y), Double(graph.y), accuracy: 1e-9)
    }
}

final class GraphPanTests: XCTestCase {

    private let window = GraphWindow(xMin: -10, xMax: 10, yMin: -10, yMax: 10)
    private let size = CGSize(width: 200, height: 200)

    func testDragRightShiftsWindowLeft() {
        // 200px wide over 20 units → 0.1 units/px. Drag right 20px → −2 units.
        let panned = CalculatorGraphGeometry.pan(
            window: window,
            byViewTranslation: CGSize(width: 20, height: 0),
            size: size
        )
        XCTAssertEqual(panned.xMin, -12, accuracy: 1e-9)
        XCTAssertEqual(panned.xMax, 8, accuracy: 1e-9)
        XCTAssertEqual(panned.yMin, -10, accuracy: 1e-9)
    }

    func testDragDownShiftsWindowUp() {
        let panned = CalculatorGraphGeometry.pan(
            window: window,
            byViewTranslation: CGSize(width: 0, height: 20),
            size: size
        )
        XCTAssertEqual(panned.yMin, -8, accuracy: 1e-9)
        XCTAssertEqual(panned.yMax, 12, accuracy: 1e-9)
    }

    func testPanPreservesSpan() {
        let panned = CalculatorGraphGeometry.pan(
            window: window,
            byViewTranslation: CGSize(width: 37, height: -19),
            size: size
        )
        XCTAssertEqual(panned.width, window.width, accuracy: 1e-9)
        XCTAssertEqual(panned.height, window.height, accuracy: 1e-9)
    }
}

final class GraphZoomTests: XCTestCase {

    private let window = GraphWindow(xMin: -10, xMax: 10, yMin: -10, yMax: 10)
    private let size = CGSize(width: 200, height: 200)

    func testZoomInAroundCenterShrinksSpan() {
        // Magnify 2× around the center → span halves, still centered.
        let zoomed = CalculatorGraphGeometry.zoom(
            window: window,
            magnification: 2,
            aroundViewPoint: CGPoint(x: 100, y: 100),
            size: size
        )
        XCTAssertEqual(zoomed.width, 10, accuracy: 1e-9)
        XCTAssertEqual(zoomed.height, 10, accuracy: 1e-9)
        XCTAssertEqual(zoomed.xMin, -5, accuracy: 1e-9)
        XCTAssertEqual(zoomed.xMax, 5, accuracy: 1e-9)
    }

    func testZoomOutAroundCenterGrowsSpan() {
        let zoomed = CalculatorGraphGeometry.zoom(
            window: window,
            magnification: 0.5,
            aroundViewPoint: CGPoint(x: 100, y: 100),
            size: size
        )
        XCTAssertEqual(zoomed.width, 40, accuracy: 1e-9)
    }

    func testZoomKeepsFocalPointFixed() {
        // Focal at view (50,50) = graph (-5, 5). After zoom, that view
        // point must still map to the same graph point.
        let focalView = CGPoint(x: 50, y: 50)
        let focalGraphBefore = CalculatorGraphGeometry.graphPoint(forView: focalView, window: window, size: size)
        let zoomed = CalculatorGraphGeometry.zoom(
            window: window,
            magnification: 3,
            aroundViewPoint: focalView,
            size: size
        )
        let focalGraphAfter = CalculatorGraphGeometry.graphPoint(forView: focalView, window: zoomed, size: size)
        XCTAssertEqual(Double(focalGraphAfter.x), Double(focalGraphBefore.x), accuracy: 1e-9)
        XCTAssertEqual(Double(focalGraphAfter.y), Double(focalGraphBefore.y), accuracy: 1e-9)
    }

    func testZoomInClampsAtMinimumSpan() {
        let zoomed = CalculatorGraphGeometry.zoom(
            window: window,
            magnification: 1e12,
            aroundViewPoint: CGPoint(x: 100, y: 100),
            size: size
        )
        XCTAssertGreaterThanOrEqual(zoomed.width, CalculatorGraphGeometry.minimumSpan)
    }
}

final class GraphTickTests: XCTestCase {

    func testNiceStepValues() {
        // 20 over ~4 intervals → raw 5 → nice 5.
        XCTAssertEqual(CalculatorGraphGeometry.niceStep(range: 20, targetCount: 4), 5, accuracy: 1e-9)
        // 1 over ~5 → raw 0.2 → nice 0.2.
        XCTAssertEqual(CalculatorGraphGeometry.niceStep(range: 1, targetCount: 5), 0.2, accuracy: 1e-9)
        // 100 over ~5 → raw 20 → nice 20.
        XCTAssertEqual(CalculatorGraphGeometry.niceStep(range: 100, targetCount: 5), 20, accuracy: 1e-9)
    }

    func testTicksWithinRange() {
        let ticks = CalculatorGraphGeometry.ticks(min: -10, max: 10, step: 5)
        XCTAssertEqual(ticks, [-10, -5, 0, 5, 10])
    }

    func testTicksStartAtFirstMultiple() {
        let ticks = CalculatorGraphGeometry.ticks(min: -7, max: 7, step: 5)
        XCTAssertEqual(ticks, [-5, 0, 5])
    }

    func testTicksGuardAgainstHugeCount() {
        let ticks = CalculatorGraphGeometry.ticks(min: 0, max: 1_000_000, step: 0.001)
        XCTAssertTrue(ticks.isEmpty, "Expected guard to refuse an absurd tick count")
    }
}

final class GraphSamplingTests: XCTestCase {

    private let window = GraphWindow(xMin: 0, xMax: 10, yMin: -5, yMax: 5)

    func testSampleCountMatches() throws {
        let samples = CalculatorGraphGeometry.sample(window: window, count: 11) { $0 }
        XCTAssertEqual(samples.count, 11)
        XCTAssertEqual(try XCTUnwrap(samples.first).x, 0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(samples.last).x, 10, accuracy: 1e-9)
    }

    func testLinearFunctionSampledCorrectly() throws {
        let samples = CalculatorGraphGeometry.sample(window: window, count: 11) { 2 * $0 }
        let y = try XCTUnwrap(samples[5].y) // x=5 → y=10
        XCTAssertEqual(y, 10, accuracy: 1e-9)
    }

    func testNonFiniteBecomesNil() {
        let samples = CalculatorGraphGeometry.sample(window: window, count: 3) { x in
            x == 5 ? Double.nan : x
        }
        XCTAssertEqual(samples[1].x, 5, accuracy: 1e-9)
        XCTAssertNil(samples[1].y, "NaN must sample to nil")
    }

    func testNilEvalBecomesNil() {
        let samples = CalculatorGraphGeometry.sample(window: window, count: 3) { _ in nil }
        XCTAssertTrue(samples.allSatisfy { $0.y == nil })
    }
}
