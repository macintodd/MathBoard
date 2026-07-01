//
//  CalculatorTheme.swift
//  MathBoardCore — Calculator module
//
//  Dark, textured color scheme for the calculator (charcoal panels, warm
//  bronze/amber accents, white labels) — tuned for legibility on a TV.
//  All numbers and lettering are white.
//

import SwiftUI

enum CalculatorTheme {

    // MARK: - Panels / surfaces

    /// Card background — charcoal with a subtle top-to-bottom gradient for
    /// a textured, tactile feel.
    static var panel: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.17, green: 0.17, blue: 0.18), Color(red: 0.10, green: 0.10, blue: 0.11)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Inset surface (display area, equation cells).
    static let surface = Color(red: 0.13, green: 0.13, blue: 0.145)

    /// Graph / number-line background.
    static let graphBackground = Color(red: 0.09, green: 0.09, blue: 0.10)

    // MARK: - Text (all white per design)

    static let label = Color.white
    static let secondaryLabel = Color.white.opacity(0.65)

    // MARK: - Accents

    /// Warm amber/bronze accent for primary actions (`=`, etc.).
    static let accent = Color(red: 0.87, green: 0.49, blue: 0.20)
    static let hairline = Color.white.opacity(0.12)

    // MARK: - Graph elements

    static let gridline = Color.white.opacity(0.13)
    static let axis = Color.white.opacity(0.5)
    static let graphLabel = Color.white.opacity(0.7)

    // MARK: - Key fills by category (dark; differentiated by warmth/tone)

    static func keyFill(for style: CalculatorKeyStyle) -> Color {
        switch style {
        case .digit:    return Color(red: 0.22, green: 0.22, blue: 0.24)
        case .operator: return Color(red: 0.28, green: 0.29, blue: 0.33)
        case .function: return Color(red: 0.20, green: 0.25, blue: 0.27)
        case .modifier: return Color(red: 0.27, green: 0.22, blue: 0.30)
        case .action:   return accent
        }
    }
}

/// Neumorphic dark key button: a softly extruded, domed key with white
/// label, a top sheen + bottom shade, and dual shadows (light top-left,
/// dark bottom-right). On press it depresses — shadows collapse, the dome
/// inverts to a subtle inset, and it scales down.
struct CalculatorKeyButtonStyle: ButtonStyle {
    var fill: Color
    var minHeight: CGFloat = 34

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        return configuration.label
            .foregroundStyle(CalculatorTheme.label)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .padding(.horizontal, 2)
            .background(
                shape
                    .fill(fill)
                    // Domed sheen: light at the top, shade at the bottom.
                    // Inverts when pressed so the key reads as pushed-in.
                    .overlay(
                        shape.fill(
                            LinearGradient(
                                colors: pressed
                                    ? [.black.opacity(0.22), .clear, .white.opacity(0.05)]
                                    : [.white.opacity(0.18), .clear, .black.opacity(0.14)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    )
                    .overlay(shape.strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
                    // Neumorphic dual shadows — extruded when idle, flat when pressed.
                    .shadow(color: .black.opacity(pressed ? 0.0 : 0.6), radius: pressed ? 1 : 4, x: pressed ? 0 : 3, y: pressed ? 0 : 4)
                    .shadow(color: .white.opacity(pressed ? 0.0 : 0.07), radius: 3, x: -3, y: -3)
            )
            .scaleEffect(pressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.09), value: pressed)
    }
}
