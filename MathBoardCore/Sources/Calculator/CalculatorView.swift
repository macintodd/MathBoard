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

    /// Default palette dimensions. The live size lives in
    /// `CalculatorState.paletteSize` and is user-adjustable via the corner
    /// resize handle; this constant is the first-launch default.
    public static let paletteSize = CalculatorState.defaultPaletteSize

    @State private var dragStartCenter: CGPoint?
    /// Captured at the start of a resize: the size and top-left corner, so
    /// the corner under the handle stays anchored while dragging.
    @State private var resizeStart: (size: CGSize, topLeft: CGPoint)?

    public var body: some View {
        GeometryReader { proxy in
            let center = resolvedCenter(in: proxy.size)
            ZStack {
                if state.showFullKeypad {
                    let placeLeft = fullKeypadPlacesLeft(cardCenter: center, container: proxy.size)
                    CalculatorFullKeypadView(state: state)
                        .frame(width: CalculatorFullKeypadView.width, height: state.paletteSize.height)
                        .position(fullKeypadCenter(cardCenter: center, container: proxy.size, placeLeft: placeLeft))
                        .transition(.move(edge: placeLeft ? .leading : .trailing).combined(with: .opacity))
                }
                card
                    .frame(width: state.paletteSize.width, height: state.paletteSize.height)
                    .overlay(alignment: .bottomTrailing) {
                        resizeHandle(currentCenter: center, in: proxy.size)
                    }
                    .position(center)
                    .gesture(dragGesture(in: proxy.size, currentCenter: center))
            }
            .animation(.easeInOut(duration: 0.28), value: state.showFullKeypad)
        }
    }

    // MARK: - Full keypad slide-out placement

    /// Gap between the palette card and the slide-out keypad panel.
    private static let fullKeypadGap: CGFloat = 12

    /// The panel prefers the right of the card, but flips to the left when it
    /// would run past the container's right edge (and there's room on the left).
    private func fullKeypadPlacesLeft(cardCenter: CGPoint, container: CGSize) -> Bool {
        let panelW = CalculatorFullKeypadView.width
        let rightEdge = cardCenter.x + state.paletteSize.width / 2 + Self.fullKeypadGap + panelW
        guard rightEdge > container.width else { return false }
        let leftEdge = cardCenter.x - state.paletteSize.width / 2 - Self.fullKeypadGap - panelW
        return leftEdge >= 0
    }

    private func fullKeypadCenter(cardCenter: CGPoint, container: CGSize, placeLeft: Bool) -> CGPoint {
        let panelW = CalculatorFullKeypadView.width
        let offset = state.paletteSize.width / 2 + Self.fullKeypadGap + panelW / 2
        let x = placeLeft ? cardCenter.x - offset : cardCenter.x + offset
        return CGPoint(x: x, y: cardCenter.y)
    }

    // MARK: - Resize handle

    private func resizeHandle(currentCenter: CGPoint, in containerSize: CGSize) -> some View {
        ResizeGrip()
            .frame(width: 20, height: 20)
            // Tuck it into the very corner of the rounded card so it reads as
            // a fixed corner affordance rather than floating over the keys.
            .padding(.trailing, 4)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
            .gesture(resizeGesture(currentCenter: currentCenter, in: containerSize))
            .help("Drag to resize")
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
                    paletteSize: state.paletteSize,
                    in: containerSize
                )
            }
            .onEnded { _ in
                dragStartCenter = nil
            }
    }

    /// Resize by dragging the bottom-trailing handle. The top-left corner
    /// stays put (the center shifts to compensate), and both the size and
    /// the resulting position are clamped to the container.
    ///
    /// Uses `.global` translation: the handle moves as the card grows, so a
    /// `.local` delta would be measured against a frame that shifts under the
    /// finger each frame — a feedback loop that made the drag jitter.
    private func resizeGesture(currentCenter: CGPoint, in containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let start = resizeStart ?? (
                    size: state.paletteSize,
                    topLeft: CGPoint(
                        x: currentCenter.x - state.paletteSize.width / 2,
                        y: currentCenter.y - state.paletteSize.height / 2
                    )
                )
                if resizeStart == nil { resizeStart = start }

                let proposed = CGSize(
                    width: start.size.width + value.translation.width,
                    height: start.size.height + value.translation.height
                )
                let clamped = CalculatorPaletteLayout.clampSize(proposed, in: containerSize)
                state.paletteSize = clamped

                let newCenter = CGPoint(
                    x: start.topLeft.x + clamped.width / 2,
                    y: start.topLeft.y + clamped.height / 2
                )
                state.position = CalculatorPaletteLayout.clamp(
                    center: newCenter,
                    paletteSize: clamped,
                    in: containerSize
                )
            }
            .onEnded { _ in
                resizeStart = nil
            }
    }

    private func resolvedCenter(in containerSize: CGSize) -> CGPoint {
        let stored = state.position ?? CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)
        return CalculatorPaletteLayout.clamp(
            center: stored,
            paletteSize: state.paletteSize,
            in: containerSize
        )
    }
}

// MARK: - Resize grip

/// The bottom-right resize affordance: three short parallel diagonal lines
/// tucked into the corner (the classic drag-to-resize grip), drawn beside the
/// shrunken corner key rather than as an opaque chip over it.
private struct ResizeGrip: View {
    var body: some View {
        Canvas { context, size in
            // Anti-diagonal segments, shortest nearest the corner — kept
            // close to the corner so the grip stays tucked in, not floating.
            for fraction in [0.45, 0.68, 0.9] as [CGFloat] {
                var path = Path()
                path.move(to: CGPoint(x: size.width * fraction, y: size.height))
                path.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                context.stroke(
                    path,
                    with: .color(CalculatorTheme.label.opacity(0.55)),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
            }
        }
    }
}

// MARK: - Layout math (pure, testable)

public enum CalculatorPaletteLayout {

    /// Smallest usable palette — keeps the keypad legible.
    public static let minSize = CGSize(width: 300, height: 420)
    /// Largest palette we allow before it dominates the canvas.
    public static let maxSize = CGSize(width: 720, height: 1040)

    /// Clamp a proposed palette size to `minSize…maxSize`, further capped so
    /// it never exceeds the container on either axis (but never forced below
    /// `minSize`, so a tiny container still yields a usable, if clipped, card).
    public static func clampSize(_ size: CGSize, in containerSize: CGSize) -> CGSize {
        let maxW = max(minSize.width, min(maxSize.width, containerSize.width))
        let maxH = max(minSize.height, min(maxSize.height, containerSize.height))
        return CGSize(
            width: min(max(size.width, minSize.width), maxW),
            height: min(max(size.height, minSize.height), maxH)
        )
    }

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
