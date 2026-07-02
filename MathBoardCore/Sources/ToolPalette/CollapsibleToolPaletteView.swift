//
//  CollapsibleToolPaletteView.swift
//  MathBoardCore - ToolPalette module
//
//  Floating, draggable palette with two states:
//   - Collapsed: a small puck showing only the active tool. Drag to move it
//     anywhere; tap to expand.
//   - Expanded: the full radial dial "blooms outward" from the puck's center.
//     Tap the center hero (or flip `isExpanded` externally — e.g. from an Apple
//     Pencil squeeze in the integration layer) to collapse again.
//
//  This view is intentionally dependency-free (pure SwiftUI). The squeeze
//  trigger is UIKit (`UIPencilInteraction`) and lives in the integration layer;
//  it drives this view only through the `isExpanded` binding.
//

import SwiftUI

public struct FloatingToolPaletteView: View {
    @Binding private var state: ToolPaletteState
    @Binding private var isExpanded: Bool
    private let dialSize: CGFloat
    private let collapsedSize: CGFloat
    private let onCommand: (ToolPaletteCommand) -> Void
    private let onResolvedCommand: (ToolPaletteCommand, ToolPaletteState) -> Void
    private let sharedCenter: Binding<CGPoint?>?

    /// Committed center of the floating palette in the host's coordinate space.
    /// `nil` until first laid out, at which point it defaults to the host center.
    @State private var localCenter: CGPoint?
    /// Center captured at the start of a move. Non-nil only while actually
    /// dragging — also used to distinguish a tap (never moved) from a drag.
    /// Mirrors `CalculatorView`'s proven-smooth drag exactly.
    @State private var dragStartCenter: CGPoint?

    public init(
        state: Binding<ToolPaletteState>,
        isExpanded: Binding<Bool>,
        center: Binding<CGPoint?>? = nil,
        dialSize: CGFloat = 360,
        collapsedSize: CGFloat = 92,
        onCommand: @escaping (ToolPaletteCommand) -> Void = { _ in },
        onResolvedCommand: @escaping (ToolPaletteCommand, ToolPaletteState) -> Void = { _, _ in }
    ) {
        self._state = state
        self._isExpanded = isExpanded
        self.sharedCenter = center
        self.dialSize = dialSize
        self.collapsedSize = collapsedSize
        self.onCommand = onCommand
        self.onResolvedCommand = onResolvedCommand
    }

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let resolvedCenter = paletteCenter ?? CGPoint(x: size.width / 2, y: size.height / 2)

            ZStack {
                ZStack {
                    if isExpanded {
                        RadialToolPaletteView(
                            state: $state,
                            dialSize: dialSize,
                            onCommand: onCommand,
                            onResolvedCommand: onResolvedCommand,
                            onHeroTap: collapse
                        )
                        .overlay {
                            if state.activeTool != .selection {
                                expandedWheelGrab(in: size, currentCenter: resolvedCenter)
                            }
                        }
                        // Center grab: a tap collapses; a press-and-drag moves. Sized
                        // to the hero so it never overlaps the outer ring controls.
                        .overlay(centerGrab(in: size, currentCenter: resolvedCenter, onTap: collapse))
                        .transition(bloom)
                    } else {
                        CollapsedToolPuck(state: state, size: collapsedSize)
                            .contentShape(Circle())
                            .gesture(dragOrTapGesture(in: size, currentCenter: resolvedCenter, onTap: expand))
                            .transition(bloom)
                    }
                }
                .position(resolvedCenter)
            }
            .frame(width: size.width, height: size.height)
        }
    }

    private var paletteCenter: CGPoint? {
        sharedCenter?.wrappedValue ?? localCenter
    }

    /// Transparent center hit-area used while expanded so the dial's middle can
    /// be tapped (collapse) or pressed-and-dragged (move) without touching the
    /// surrounding tool ring / sliders.
    private func centerGrab(in size: CGSize, currentCenter: CGPoint, onTap: @escaping () -> Void) -> some View {
        Circle()
            .fill(Color.clear)
            .contentShape(Circle())
            .frame(width: dialSize * 0.30, height: dialSize * 0.30)
            .gesture(dragOrTapGesture(in: size, currentCenter: currentCenter, onTap: onTap))
    }

    /// Transparent drag-only regions for the expanded dial's outer wheel. The
    /// shape deliberately skips the top orbit and bottom slider arcs so buttons
    /// and sliders keep their normal hit testing.
    private func expandedWheelGrab(in size: CGSize, currentCenter: CGPoint) -> some View {
        ExpandedPaletteDragShape()
            .fill(Color.clear)
            .contentShape(ExpandedPaletteDragShape())
            .frame(width: dialSize, height: dialSize)
            .gesture(dragOrTapGesture(in: size, currentCenter: currentCenter, onTap: {}))
    }

    /// Blooms the dial out from / back into the puck's center.
    private var bloom: AnyTransition {
        .scale(scale: 0.18, anchor: .center).combined(with: .opacity)
    }

    private func expand() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
            isExpanded = true
        }
    }

    private func collapse() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
            isExpanded = false
        }
    }

    private static let dragThreshold: CGFloat = 3

    /// Drag commits the new center **live in `.onChanged`** (exactly like
    /// `CalculatorView`, which slides smoothly over the same canvas) — no
    /// `@GestureState`, no `.highPriorityGesture`. A press that never crosses the
    /// threshold lifts as a tap (toggles via `onTap`).
    private func dragOrTapGesture(in size: CGSize, currentCenter: CGPoint, onTap: @escaping () -> Void) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                let distance = hypot(value.translation.width, value.translation.height)
                guard dragStartCenter != nil || distance >= Self.dragThreshold else { return }
                let base = dragStartCenter ?? currentCenter
                if dragStartCenter == nil { dragStartCenter = base }
                setCenterWithoutAnimation(clamp(
                    CGPoint(x: base.x + value.translation.width, y: base.y + value.translation.height),
                    in: size
                ))
            }
            .onEnded { _ in
                let moved = dragStartCenter != nil
                dragStartCenter = nil
                if !moved { onTap() }
            }
    }

    private func setCenterWithoutAnimation(_ newCenter: CGPoint) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if let sharedCenter {
                sharedCenter.wrappedValue = newCenter
            } else {
                localCenter = newCenter
            }
        }
    }

    private func clamp(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let margin = collapsedSize / 2
        let x = min(max(point.x, margin), max(margin, size.width - margin))
        let y = min(max(point.y, margin), max(margin, size.height - margin))
        return CGPoint(x: x, y: y)
    }
}

/// Compact resting face: the active tool's icon + name on the same domed circle
/// as the dial's center hero, so expanding reads as the puck growing into the dial.
struct CollapsedToolPuck: View {
    var state: ToolPaletteState
    var size: CGFloat

    var body: some View {
        VStack(spacing: size * 0.05) {
            if state.activeTool == .geometry {
                GeometrySymbolView(
                    outlineColor: state.strokeColor.swiftUIColor,
                    fillColor: state.fillColor.swiftUIColor.opacity(state.geometryFillOpacity),
                    lineWidth: size * 0.035
                )
                .frame(width: size * 0.34, height: size * 0.34)
            } else {
                Image(systemName: state.activeTool.iconSystemName)
                    .font(.system(size: size * 0.30, weight: .medium))
                    .foregroundStyle(iconColor)
            }
            Text(state.activeTool.displayName)
                .font(.system(size: size * 0.13, weight: .semibold))
                .foregroundStyle(ToolPaletteTheme.label)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(width: size, height: size)
        .background(puckBackground)
        .overlay(Circle().strokeBorder(.black.opacity(0.45), lineWidth: 2))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tool palette, \(state.activeTool.displayName). Double tap to expand.")
    }

    private var iconColor: Color {
        switch state.activeTool {
        case .pen, .marker, .laser:
            return state.activeStrokeColor.swiftUIColor
        case .selection, .extract, .reserved, .eraser, .geometry, .equation:
            return ToolPaletteTheme.label
        }
    }

    private var puckBackground: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color(red: 0.16, green: 0.31, blue: 0.48),
                        Color(red: 0.11, green: 0.23, blue: 0.38)
                    ],
                    center: .topLeading,
                    startRadius: size * 0.05,
                    endRadius: size * 0.62
                )
            )
            .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1).padding(2))
            .shadow(color: .black.opacity(0.5), radius: 8, y: 3)
    }
}

private struct ExpandedPaletteDragShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * 0.69

        // Screen-space degrees: 90 is down, 270 is up. Keep these drag sectors
        // away from the slider arcs, including their enlarged endpoint hit zones,
        // so a touch near a slider knob cannot start moving the whole palette.
        addAnnularSector(to: &path, center: center, innerRadius: innerRadius, outerRadius: outerRadius, startDegrees: 180, endDegrees: 210)
        addAnnularSector(to: &path, center: center, innerRadius: innerRadius, outerRadius: outerRadius, startDegrees: 330, endDegrees: 360)

        return path
    }

    private func addAnnularSector(
        to path: inout Path,
        center: CGPoint,
        innerRadius: CGFloat,
        outerRadius: CGFloat,
        startDegrees: Double,
        endDegrees: Double
    ) {
        path.move(to: point(center: center, radius: outerRadius, degrees: startDegrees))
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: .degrees(startDegrees),
            endAngle: .degrees(endDegrees),
            clockwise: false
        )
        path.addLine(to: point(center: center, radius: innerRadius, degrees: endDegrees))
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: .degrees(endDegrees),
            endAngle: .degrees(startDegrees),
            clockwise: true
        )
        path.closeSubpath()
    }

    private func point(center: CGPoint, radius: CGFloat, degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(
            x: center.x + cos(radians) * radius,
            y: center.y + sin(radians) * radius
        )
    }
}

// MARK: - Preview

private struct FloatingPalettePreviewHost: View {
    @State private var state = ToolPaletteState()
    @State private var isExpanded = false

    var body: some View {
        ZStack {
            Color(red: 0.94, green: 0.96, blue: 0.98)
            FloatingToolPaletteView(state: $state, isExpanded: $isExpanded)
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            Text(isExpanded ? "Expanded — tap center to collapse" : "Collapsed — drag to move, tap to expand")
                .font(.caption)
                .padding(8)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, 12)
        }
    }
}

#Preview("Floating collapse / expand") {
    FloatingPalettePreviewHost()
}
