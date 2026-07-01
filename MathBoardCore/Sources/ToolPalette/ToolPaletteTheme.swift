//
//  ToolPaletteTheme.swift
//  MathBoardCore - ToolPalette module
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum ToolPaletteTheme {
    static let shell = Color(red: 0.06, green: 0.14, blue: 0.24)
    static let segment = Color(red: 0.08, green: 0.18, blue: 0.30)
    static let segmentRaised = Color(red: 0.10, green: 0.22, blue: 0.35)
    static let optionBand = Color(red: 0.11, green: 0.24, blue: 0.38)
    static let hero = Color(red: 0.07, green: 0.15, blue: 0.26)
    static let cyan = Color(red: 0.18, green: 0.72, blue: 1.0)
    static let label = Color.white
    static let mutedLabel = Color.white
    static let divider = Color.black.opacity(0.42)
    static let glow = Color(red: 0.13, green: 0.70, blue: 1.0)
}

extension PaletteColor {
    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue)
    }

    init?(name: String, color: Color) {
        #if canImport(UIKit)
        let platformColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard platformColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }
        self.init(name: name, red: Double(red), green: Double(green), blue: Double(blue))
        #elseif canImport(AppKit)
        let platformColor = NSColor(color)
        guard let converted = platformColor.usingColorSpace(.sRGB) else {
            return nil
        }
        self.init(name: name, red: Double(converted.redComponent), green: Double(converted.greenComponent), blue: Double(converted.blueComponent))
        #else
        return nil
        #endif
    }
}

struct AnnularSector: Shape {
    var startDegrees: Double
    var endDegrees: Double
    var innerRadiusRatio: CGFloat
    var outerRadiusRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) * outerRadiusRatio
        let innerRadius = min(rect.width, rect.height) * innerRadiusRatio
        var path = Path()

        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: .degrees(startDegrees),
            endAngle: .degrees(endDegrees),
            clockwise: false
        )
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: .degrees(endDegrees),
            endAngle: .degrees(startDegrees),
            clockwise: true
        )
        path.closeSubpath()
        return path
    }
}

struct ArcStrokeShape: Shape {
    var startDegrees: Double
    var endDegrees: Double
    var radiusRatio: CGFloat = 0.34

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) * radiusRatio
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startDegrees),
            endAngle: .degrees(endDegrees),
            clockwise: false
        )
        return path
    }
}
