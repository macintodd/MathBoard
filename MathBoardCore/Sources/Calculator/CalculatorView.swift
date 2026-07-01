//
//  CalculatorView.swift
//  MathBoardCore — Calculator module
//
//  The floating calculator palette: a fixed-size card with a draggable
//  title bar (mode toggle, disabled snapshot button, close button) over
//  a body that switches between compute and graph modes. This is the
//  public entry point the integration glue overlays onto the canvas.
//
//  Hit-testing is solid per the locked-in design: the whole card absorbs
//  touches via `.contentShape(Rectangle())`, so Apple Pencil ink only
//  lands on canvas areas outside the palette's footprint.
//
//  Position lives in `CalculatorState.position` (iPad viewport-space
//  point, palette CENTER). `nil` means "never moved" → the view centers
//  itself in its container on first appearance. Dragging the title bar
//  writes the clamped center back into state, which the TV overlay reads
//  to mirror the palette in the same relative spot.
//

import SwiftUI

public struct CalculatorView: View {
    @Bindable private var state: CalculatorState

    public init(state: CalculatorState = .shared) {
        self.state = state
    }

    public static let paletteSize = CGSize(width: 360, height: 540)

    @State private var dragStartCenter: CGPoint?

    public var body: some View {
        GeometryReader { proxy in
            let center = resolvedCenter(in: proxy.size)
            card
                .frame(width: Self.paletteSize.width, height: Self.paletteSize.height)
                .position(center)
                .gesture(dragGesture(in: proxy.size, currentCenter: center))
        }
    }

    // MARK: - Card

    private var card: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            body(for: state.mode)
        }
        .background(CalculatorTheme.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .environment(\.colorScheme, .dark) // force dark chrome + white text
        .tint(CalculatorTheme.accent)
    }

    // MARK: - Title bar

    private var titleBar: some View {
        HStack(spacing: 10) {
            Picker("Mode", selection: $state.mode) {
                ForEach(CalculatorMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 160)

            Spacer(minLength: 4)

            Button {
                // Snapshot-to-canvas wires up when the image-object layer
                // exists. Disabled placeholder for now.
            } label: {
                Image(systemName: "camera.viewfinder")
            }
            .disabled(true)
            .help("Drop graph onto the whiteboard (coming with image objects)")

            Button {
                state.isVisible = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .help("Close calculator")
        }
        .buttonStyle(.plain)
        .foregroundStyle(CalculatorTheme.label)
        .font(.title3)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(CalculatorTheme.surface)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18))
        // Only the title bar initiates a move-drag; the body keeps its own
        // gestures (keypad taps, future graph pan/zoom).
        .contentShape(Rectangle())
    }

    // MARK: - Body switch

    @ViewBuilder
    private func body(for mode: CalculatorMode) -> some View {
        switch mode {
        case .compute:
            CalculatorComputeView(state: state)
        case .graph:
            CalculatorGraphView(state: state)
        }
    }

    // MARK: - Drag

    private func dragGesture(in containerSize: CGSize, currentCenter: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                let base = dragStartCenter ?? currentCenter
                if dragStartCenter == nil { dragStartCenter = base }
                let proposed = CGPoint(
                    x: base.x + value.translation.width,
                    y: base.y + value.translation.height
                )
                state.position = CalculatorPaletteLayout.clamp(
                    center: proposed,
                    paletteSize: Self.paletteSize,
                    in: containerSize
                )
            }
            .onEnded { _ in
                dragStartCenter = nil
            }
    }

    private func resolvedCenter(in containerSize: CGSize) -> CGPoint {
        let stored = state.position ?? CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)
        return CalculatorPaletteLayout.clamp(
            center: stored,
            paletteSize: Self.paletteSize,
            in: containerSize
        )
    }
}

// MARK: - Layout math (pure, testable)

public enum CalculatorPaletteLayout {

    /// Clamp the palette's center so the card stays fully within the
    /// container. If the container is smaller than the palette on an
    /// axis, the center is pinned to the container's midpoint on that
    /// axis (best-effort centering rather than pushing it off-screen).
    public static func clamp(center: CGPoint, paletteSize: CGSize, in containerSize: CGSize) -> CGPoint {
        CGPoint(
            x: clampAxis(center.x, palette: paletteSize.width, container: containerSize.width),
            y: clampAxis(center.y, palette: paletteSize.height, container: containerSize.height)
        )
    }

    private static func clampAxis(_ value: CGFloat, palette: CGFloat, container: CGFloat) -> CGFloat {
        let half = palette / 2
        // Container can't fit the palette → center on the axis.
        guard container >= palette else { return container / 2 }
        return min(max(value, half), container - half)
    }
}

#if DEBUG
#Preview("Calculator palette") {
    ZStack {
        Color(white: 0.95)
        CalculatorView(
            state: CalculatorState(store: UserDefaults(suiteName: "preview.palette")!)
        )
    }
    .frame(width: 800, height: 700)
}
#endif
