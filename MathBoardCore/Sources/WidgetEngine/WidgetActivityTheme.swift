//
//  WidgetActivityTheme.swift
//  WidgetEngine
//
//  Curated visual themes for activity-based widgets.
//

import SwiftUI

struct WidgetActivityVisualTheme {
    let background: LinearGradient
    let panel: Color
    let card: Color
    let choice: Color
    let selectedChoice: Color
    let expressionBackground: Color
    let hintBackground: Color
    let badge: Color
    let accent: Color
    let border: Color
    let progressTrack: Color
    let progressFill: LinearGradient
    let primaryText: Color
    let secondaryText: Color
    let expressionText: Color
    let correct: Color
    let incorrect: Color
    let warning: Color
    let correctText: Color
    let badgeSelectedText: Color

    init(_ theme: WidgetActivityTheme) {
        switch theme {
        case .cleanClassroom:
            self.init(
                top: Color(red: 0.95, green: 0.98, blue: 1.00),
                bottom: Color(red: 0.98, green: 0.99, blue: 0.96),
                panel: .white.opacity(0.86),
                card: .white.opacity(0.92),
                choice: .white.opacity(0.96),
                selectedChoice: Color(red: 0.88, green: 0.94, blue: 1.00),
                expressionBackground: Color(red: 0.94, green: 0.97, blue: 1.00),
                hintBackground: Color(red: 1.00, green: 0.96, blue: 0.84),
                badge: Color.black.opacity(0.06),
                accent: Color(red: 0.02, green: 0.45, blue: 0.88),
                border: Color.black.opacity(0.10),
                primaryText: Color(red: 0.08, green: 0.10, blue: 0.13),
                secondaryText: Color(red: 0.34, green: 0.38, blue: 0.44)
            )
        case .neonMath:
            self.init(
                top: Color(red: 0.03, green: 0.05, blue: 0.12),
                bottom: Color(red: 0.04, green: 0.12, blue: 0.20),
                panel: Color.white.opacity(0.11),
                card: Color.white.opacity(0.13),
                choice: Color.white.opacity(0.14),
                selectedChoice: Color(red: 0.05, green: 0.44, blue: 0.78).opacity(0.50),
                expressionBackground: Color.black.opacity(0.28),
                hintBackground: Color(red: 0.99, green: 0.82, blue: 0.27).opacity(0.18),
                badge: Color.white.opacity(0.13),
                accent: Color(red: 0.14, green: 0.82, blue: 1.00),
                border: Color.white.opacity(0.18),
                primaryText: .white,
                secondaryText: Color.white.opacity(0.72)
            )
        case .paperArcade:
            self.init(
                top: Color(red: 1.00, green: 0.96, blue: 0.86),
                bottom: Color(red: 0.90, green: 0.96, blue: 1.00),
                panel: .white.opacity(0.78),
                card: .white.opacity(0.88),
                choice: .white.opacity(0.94),
                selectedChoice: Color(red: 1.00, green: 0.88, blue: 0.55),
                expressionBackground: Color(red: 1.00, green: 0.91, blue: 0.66),
                hintBackground: Color(red: 0.89, green: 0.97, blue: 0.78),
                badge: Color(red: 0.08, green: 0.10, blue: 0.13).opacity(0.08),
                accent: Color(red: 0.91, green: 0.30, blue: 0.15),
                border: Color(red: 0.08, green: 0.10, blue: 0.13).opacity(0.13),
                primaryText: Color(red: 0.12, green: 0.10, blue: 0.08),
                secondaryText: Color(red: 0.46, green: 0.38, blue: 0.30)
            )
        case .chalkboard:
            self.init(
                top: Color(red: 0.05, green: 0.19, blue: 0.15),
                bottom: Color(red: 0.03, green: 0.11, blue: 0.10),
                panel: Color.white.opacity(0.10),
                card: Color.white.opacity(0.12),
                choice: Color.white.opacity(0.13),
                selectedChoice: Color(red: 0.80, green: 0.94, blue: 0.74).opacity(0.24),
                expressionBackground: Color.black.opacity(0.20),
                hintBackground: Color(red: 0.93, green: 0.84, blue: 0.56).opacity(0.20),
                badge: Color.white.opacity(0.12),
                accent: Color(red: 0.80, green: 0.94, blue: 0.74),
                border: Color.white.opacity(0.18),
                primaryText: Color(red: 0.95, green: 0.98, blue: 0.91),
                secondaryText: Color(red: 0.77, green: 0.84, blue: 0.76)
            )
        case .sportsCourt:
            self.init(
                top: Color(red: 0.04, green: 0.34, blue: 0.20),
                bottom: Color(red: 0.08, green: 0.15, blue: 0.37),
                panel: Color.white.opacity(0.13),
                card: Color.white.opacity(0.15),
                choice: Color.white.opacity(0.16),
                selectedChoice: Color(red: 1.00, green: 0.59, blue: 0.20).opacity(0.35),
                expressionBackground: Color.white.opacity(0.13),
                hintBackground: Color(red: 1.00, green: 0.88, blue: 0.38).opacity(0.20),
                badge: Color.white.opacity(0.13),
                accent: Color(red: 1.00, green: 0.59, blue: 0.20),
                border: Color.white.opacity(0.20),
                primaryText: .white,
                secondaryText: Color.white.opacity(0.74)
            )
        }
    }

    private init(
        top: Color,
        bottom: Color,
        panel: Color,
        card: Color,
        choice: Color,
        selectedChoice: Color,
        expressionBackground: Color,
        hintBackground: Color,
        badge: Color,
        accent: Color,
        border: Color,
        primaryText: Color,
        secondaryText: Color
    ) {
        self.background = LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
        self.panel = panel
        self.card = card
        self.choice = choice
        self.selectedChoice = selectedChoice
        self.expressionBackground = expressionBackground
        self.hintBackground = hintBackground
        self.badge = badge
        self.accent = accent
        self.border = border
        self.progressTrack = primaryText.opacity(0.12)
        self.progressFill = LinearGradient(colors: [accent, accent.opacity(0.55)], startPoint: .leading, endPoint: .trailing)
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.expressionText = primaryText
        self.correct = Color(red: 0.20, green: 0.78, blue: 0.38)
        self.incorrect = Color(red: 0.95, green: 0.24, blue: 0.24)
        self.warning = Color(red: 0.95, green: 0.63, blue: 0.18)
        self.correctText = primaryText
        self.badgeSelectedText = .white
    }
}

