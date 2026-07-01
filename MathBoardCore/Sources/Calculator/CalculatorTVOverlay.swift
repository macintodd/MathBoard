//
//  CalculatorTVOverlay.swift
//  MathBoardCore — Calculator module
//
//  Read-only calculator rendering for the external display. Observes the
//  same `CalculatorState` the iPad palette mutates and draws an identical
//  card — graph plot or compute display — at the matching RELATIVE
//  position, scaled to the TV's container. No input handling.
//
//  Positioning contract (kept simple so the module stays unaware of
//  `DisplayBroker`): the integration glue passes `referenceSize` — the
//  size of the iPad container the palette's `state.position` was measured
//  in. `CalculatorTVLayout` converts that to a fractional position and a
//  uniform scale for this overlay's own bounds. The glue is responsible
//  for placing this overlay inside the correct TV region (e.g. inside the
//  letterboxed canvas rect) and for Present-mode cropping.
//
//  Compute-mode note: the iPad shows a result only after "=", but the TV
//  has no key events to mirror, so it RE-EVALUATES `computeExpression`
//  live from the shared state. Acceptable for v1 (students see it compute);
//  noted as a minor iPad/TV divergence in Calculator_status.md.
//

import SwiftUI

public struct CalculatorTVOverlay: View {
    private var state: CalculatorState
    private let referenceSize: CGSize

    public init(state: CalculatorState = .shared, referenceSize: CGSize) {
        self.state = state
        self.referenceSize = referenceSize
    }

    public var body: some View {
        GeometryReader { proxy in
            if state.isVisible {
                let placement = CalculatorTVLayout.placement(
                    position: state.position,
                    paletteSize: CalculatorView.paletteSize,
                    referenceSize: referenceSize,
                    tvSize: proxy.size
                )
                card
                    .frame(width: CalculatorView.paletteSize.width, height: CalculatorView.paletteSize.height)
                    .scaleEffect(placement.scale)
                    .position(placement.center)
                    .allowsHitTesting(false)
            }
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            // Render the real calculator bodies so the external display
            // shows the full interface — keypad / graph controls — letting
            // the teacher demonstrate which buttons to push. The overlay
            // applies `.allowsHitTesting(false)`, so these stay read-only.
            switch state.mode {
            case .graph:
                CalculatorGraphView(state: state)
            case .compute:
                CalculatorComputeView(state: state)
            }
        }
        .background(CalculatorTheme.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.10), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
        .environment(\.colorScheme, .dark)
        .tint(CalculatorTheme.accent)
    }

    private var titleBar: some View {
        HStack {
            Text(state.mode.displayName)
                .font(.headline)
            Spacer()
            Text(state.angleMode.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(CalculatorTheme.surface)
    }
}

// MARK: - Positioning math (pure, testable)

public enum CalculatorTVLayout {

    public struct Placement: Equatable, Sendable {
        public let center: CGPoint
        public let scale: CGFloat
    }

    /// Map the iPad palette's position into the TV overlay's bounds.
    ///
    /// - The fractional center (palette center as a fraction of the iPad
    ///   container) is reproduced in the TV bounds, so the calculator sits
    ///   in the same relative spot.
    /// - Scale is the TV-to-reference width ratio, so the palette occupies
    ///   the same fraction of the screen on both displays (the canvas
    ///   mirror preserves aspect ratio, so width and height ratios match).
    /// - A nil position (palette never moved) maps to the container center.
    public static func placement(
        position: CGPoint?,
        paletteSize: CGSize,
        referenceSize: CGSize,
        tvSize: CGSize
    ) -> Placement {
        guard referenceSize.width > 0, referenceSize.height > 0 else {
            return Placement(center: CGPoint(x: tvSize.width / 2, y: tvSize.height / 2), scale: 1)
        }

        let referenceCenter = position
            ?? CGPoint(x: referenceSize.width / 2, y: referenceSize.height / 2)

        let fractionX = referenceCenter.x / referenceSize.width
        let fractionY = referenceCenter.y / referenceSize.height
        let center = CGPoint(x: fractionX * tvSize.width, y: fractionY * tvSize.height)

        let scale = tvSize.width / referenceSize.width
        return Placement(center: center, scale: scale)
    }
}

#if DEBUG
#Preview("TV overlay") {
    ZStack {
        Color.black
        CalculatorTVOverlay(
            state: {
                let state = CalculatorState(store: UserDefaults(suiteName: "preview.tv")!)
                state.isVisible = true
                state.mode = .graph
                state.graphEquations = [GraphEquation(expression: "sin(x)", colorIndex: 0)]
                state.angleMode = .radians
                return state
            }(),
            referenceSize: CGSize(width: 1024, height: 768)
        )
    }
    .frame(width: 960, height: 540)
}
#endif
