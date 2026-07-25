//
//  SlideNavigatorView.swift
//  MathBoardCore — Slides module
//
//  Production port of the SlideNav prototype (see
//  MathBoardCore/Sources/SlideNav/ — the design sandbox stays there for
//  look-and-feel iteration; port changes here after approval).
//
//  A bottom-trailing floating navigator with two pieces:
//   - Pill: physical-key prev / "8 of 13" counter / next. The counter is
//     raised while the filmstrip is closed and depresses with an amber inner
//     glow while it's open; the arrows are momentary keys that flash the
//     glow while held.
//   - Filmstrip panel: always laid out above the pill and hidden in place
//     (opacity/scale) so the pill never moves and never gets covered.
//     Thumbnails support tap = navigate, drag = scroll, long-press = select;
//     with a selection active, taps toggle membership. Header holds
//     Select All, move left/right (packing), delete, and add.
//
//  The view owns selection and scroll state; everything that touches the
//  lesson (navigation, add, move, delete) goes through host callbacks.
//  Deletion is a request — the host confirms before removing slides.
//

import SwiftUI

struct SlideNavigatorView: View {
    let slides: [SlideMetadata]
    let currentIndex: Int
    @Binding var isFilmstripOpen: Bool
    /// Thumbnail for a slide, or nil for the blank-card placeholder. Only
    /// called while the filmstrip is open, so closed-state renders do no work.
    let thumbnail: (SlideMetadata) -> Image?
    let onGoTo: (Int) -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onAdd: () -> Void
    /// Move the given slide indices one step (direction: -1 left, +1 right).
    let onMoveSlides: ([Int], Int) -> Void
    /// Request deletion of the given slide indices (host confirms first).
    let onDeleteSlides: ([Int]) -> Void

    /// Filmstrip multi-selection, tracked by ID so it survives reorders.
    @State private var selectedIDs: Set<UUID> = []
    /// Scroll target of the thumbnail strip (see `scrollPosition` below).
    @State private var scrolledSlideID: UUID?

    var body: some View {
        // The filmstrip panel is ALWAYS laid out (hidden via opacity/scale when
        // closed, never inserted/removed), so the navigator's frame is constant:
        // the pill cannot move and the panel cannot cover it. Hidden space is
        // transparent and non-hit-testable, so it never blocks the canvas.
        VStack(alignment: .trailing, spacing: 10) {
            filmstrip
            pill
        }
        .animation(.snappy(duration: 0.28, extraBounce: 0.06), value: isFilmstripOpen)
        .animation(.snappy(duration: 0.22), value: currentIndex)
        // NOTE: deliberately no `.animation(value: slides)` — animating tile
        // insertion makes scroll-to-the-new-slide requests resolve against
        // mid-animation content and get dropped.
        .animation(.snappy(duration: 0.18), value: selectedIDs)
        .onChange(of: isFilmstripOpen) { _, isOpen in
            // Selection is a filmstrip-session concept; closing clears it.
            if !isOpen { selectedIDs.removeAll() }
        }
        .onChange(of: slides) { _, newSlides in
            // Drop selection entries for slides deleted by the host.
            let ids = Set(newSlides.map(\.id))
            selectedIDs.formIntersection(ids)
        }
    }

    // MARK: - Derived state

    private var currentSlide: SlideMetadata? {
        slides.indices.contains(currentIndex) ? slides[currentIndex] : nil
    }

    private var canGoPrevious: Bool { currentIndex > 0 }
    private var canGoNext: Bool { currentIndex < slides.count - 1 }

    private var hasSelection: Bool { !selectedIDs.isEmpty }
    private var isAllSelected: Bool { !slides.isEmpty && selectedIDs.count == slides.count }

    /// The indices header actions (move/delete) operate on: the selection when
    /// one exists, otherwise the current slide.
    private var actionIndices: [Int] {
        if hasSelection {
            return slides.enumerated().filter { selectedIDs.contains($0.element.id) }.map(\.offset)
        }
        return slides.indices.contains(currentIndex) ? [currentIndex] : []
    }

    /// Enabled until the action slides are packed against the left edge.
    private var canMoveActionSlidesLeft: Bool {
        let indices = actionIndices
        return indices != Array(0..<indices.count)
    }

    /// Enabled until the action slides are packed against the right edge.
    private var canMoveActionSlidesRight: Bool {
        let indices = actionIndices
        return indices != Array((slides.count - indices.count)..<slides.count)
    }

    /// At least one slide must survive a delete.
    private var canDeleteActionSlides: Bool {
        let count = actionIndices.count
        return count > 0 && count < slides.count
    }

    /// Filmstrip tap: in normal browsing a tap navigates; while a selection
    /// exists, taps toggle membership instead — long press starts a selection.
    private func handleTap(at index: Int) {
        if hasSelection {
            toggleSelection(at: index)
        } else {
            onGoTo(index)
        }
    }

    private func toggleSelection(at index: Int) {
        guard slides.indices.contains(index) else { return }
        let id = slides[index].id
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func toggleSelectAll() {
        if isAllSelected {
            selectedIDs.removeAll()
        } else {
            selectedIDs = Set(slides.map(\.id))
        }
    }

    // MARK: - Pill

    private var pill: some View {
        HStack(spacing: 8) {
            navArrowButton(systemName: "chevron.left", enabled: canGoPrevious, label: "Previous slide", action: onPrevious)
            counterButton
            navArrowButton(systemName: "chevron.right", enabled: canGoNext, label: "Next slide", action: onNext)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .slideNavigatorShell(Capsule())
    }

    /// The counter looks like a physical key: raised and shaded while the
    /// filmstrip is closed; pressing it depresses the same button (inverted
    /// shading, no drop shadow, nudged down) and lights an amber-glowing
    /// inner outline while the filmstrip is open.
    private var counterButton: some View {
        let isPressed = isFilmstripOpen
        return Button {
            isFilmstripOpen.toggle()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "rectangle.stack")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SlideNavigatorColors.accent)

                HStack(spacing: 3) {
                    Text("\(currentIndex + 1)")
                        .font(.subheadline.monospacedDigit().weight(.bold))
                        .foregroundStyle(SlideNavigatorColors.ink)
                    Text("of \(slides.count)")
                        .font(.subheadline.monospacedDigit().weight(.medium))
                        .foregroundStyle(Color.secondary)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(
                    LinearGradient(
                        colors: isPressed
                            ? [Color(red: 0.84, green: 0.81, blue: 0.75), Color(red: 0.94, green: 0.92, blue: 0.87)]
                            : [Color.white, Color(red: 0.90, green: 0.87, blue: 0.81)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            )
            .overlay(
                Capsule().strokeBorder(
                    LinearGradient(
                        colors: isPressed
                            ? [Color.black.opacity(0.28), Color.white.opacity(0.5)]
                            : [Color.white.opacity(0.9), Color.black.opacity(0.16)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            )
            .overlay {
                if isPressed {
                    ZStack {
                        Capsule()
                            .strokeBorder(SlideNavigatorColors.glow.opacity(0.65), lineWidth: 2.5)
                            .blur(radius: 2)
                        Capsule()
                            .strokeBorder(SlideNavigatorColors.glow, lineWidth: 1.2)
                    }
                    .clipShape(Capsule())
                    .padding(1)
                    .allowsHitTesting(false)
                }
            }
            .shadow(color: .black.opacity(isPressed ? 0 : 0.22), radius: 2.5, y: 2)
            .offset(y: isPressed ? 1 : 0)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPressed ? "Hide slide thumbnails" : "Show slide thumbnails")
    }

    private func navArrowButton(systemName: String, enabled: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(SlideNavigatorColors.ink)
        }
        .buttonStyle(SlideNavigatorRoundKeyStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }

    // MARK: - Filmstrip panel

    private var filmstrip: some View {
        VStack(spacing: 10) {
            filmstripHeader
            thumbnailStrip
        }
        .padding(12)
        .frame(width: filmstripPanelWidth)
        .slideNavigatorShell(RoundedRectangle(cornerRadius: 20, style: .continuous))
        // Hidden-in-place instead of removed: the bloom is opacity + scale
        // from the corner nearest the pill, and layout never changes.
        .opacity(isFilmstripOpen ? 1 : 0)
        .scaleEffect(isFilmstripOpen ? 1 : 0.86, anchor: .bottomTrailing)
        .allowsHitTesting(isFilmstripOpen)
        .accessibilityHidden(!isFilmstripOpen)
    }

    /// Panel width sized to the thumbnails (tile 116 + spacing 10, plus strip
    /// and panel padding), clamped so the header always fits and long lessons
    /// scroll instead of growing unbounded.
    private var filmstripPanelWidth: CGFloat {
        let tiles = CGFloat(slides.count) * 126 + 22
        return min(560, max(400, tiles))
    }

    private var filmstripHeader: some View {
        HStack(spacing: 8) {
            Text(hasSelection ? "\(selectedIDs.count) selected" : "Slides")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(hasSelection ? SlideNavigatorColors.accent : .secondary)
                .padding(.leading, 4)

            Spacer(minLength: 12)

            Button {
                toggleSelectAll()
            } label: {
                Text(isAllSelected ? "Deselect All" : "Select All")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SlideNavigatorColors.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.6)))
                    .overlay(Capsule().strokeBorder(Color.black.opacity(0.06), lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)

            headerActionButton(
                systemName: "arrow.left.to.line",
                enabled: canMoveActionSlidesLeft,
                label: hasSelection ? "Move selected slides left" : "Move slide left"
            ) {
                onMoveSlides(actionIndices, -1)
            }
            headerActionButton(
                systemName: "arrow.right.to.line",
                enabled: canMoveActionSlidesRight,
                label: hasSelection ? "Move selected slides right" : "Move slide right"
            ) {
                onMoveSlides(actionIndices, 1)
            }
            headerActionButton(
                systemName: "trash",
                enabled: canDeleteActionSlides,
                label: hasSelection ? "Delete selected slides" : "Delete slide",
                tint: .red
            ) {
                onDeleteSlides(actionIndices)
            }

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(SlideNavigatorColors.ink)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(SlideNavigatorColors.secondary))
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add slide")
        }
    }

    private func headerActionButton(
        systemName: String,
        enabled: Bool,
        label: String,
        tint: Color = SlideNavigatorColors.ink,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.6)))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }

    private var thumbnailStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(slides.enumerated()), id: \.element.id) { index, slide in
                        SlideNavigatorThumbnailTile(
                            // Skip thumbnail work entirely while hidden.
                            thumbnail: isFilmstripOpen ? thumbnail(slide) : nil,
                            index: index,
                            isCurrent: index == currentIndex,
                            isSelected: selectedIDs.contains(slide.id),
                            onTap: { handleTap(at: index) },
                            onToggleSelect: { toggleSelection(at: index) }
                        )
                        .id(slide.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }
            // Belt and suspenders: the `scrollPosition` binding handles initial
            // placement declaratively, and the ScrollViewReader proxy performs
            // explicit runtime scrolls. Driving both tolerates either API
            // dropping a request.
            .scrollPosition(id: $scrolledSlideID, anchor: .center)
            .onAppear { scrollToCurrent(proxy: proxy, animated: false) }
            .onChange(of: currentIndex) { _, _ in
                scrollToCurrent(proxy: proxy, animated: true)
            }
            .onChange(of: slides.count) { _, _ in
                // Content changed in this transaction; scroll requests made
                // while the strip is still laying out get dropped. Re-assert
                // the target well after everything settles.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    scrollToCurrent(proxy: proxy, animated: true)
                }
            }
            .onChange(of: isFilmstripOpen) { _, isOpen in
                if isOpen { scrollToCurrent(proxy: proxy, animated: false) }
            }
        }
    }

    private func scrollToCurrent(proxy: ScrollViewProxy, animated: Bool) {
        guard let id = currentSlide?.id else { return }
        if animated {
            withAnimation(.snappy(duration: 0.2)) {
                scrolledSlideID = id
                proxy.scrollTo(id, anchor: .center)
            }
        } else {
            scrolledSlideID = id
            proxy.scrollTo(id, anchor: .center)
        }
    }
}

// MARK: - Thumbnail tile

private struct SlideNavigatorThumbnailTile: View {
    let thumbnail: Image?
    let index: Int
    let isCurrent: Bool
    let isSelected: Bool
    /// Quick tap: navigate (or toggle selection while selection mode is active).
    let onTap: () -> Void
    /// Long press (finger held still ~0.35s): toggle selection.
    let onToggleSelect: () -> Void

    @State private var isPressing = false

    // Current slide (what's on the whiteboard) = terracotta ring.
    // Selected-for-action = mustard ring + checkmark badge. A slide can be both.
    private var ringColor: Color {
        if isCurrent { return SlideNavigatorColors.accent }
        if isSelected { return SlideNavigatorColors.secondary }
        return Color.black.opacity(0.12)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let thumbnail {
                    thumbnail
                        .resizable()
                        .scaledToFit()
                } else {
                    // Ink-only or blank slide — plain card with a hint glyph.
                    Image(systemName: "square.and.pencil")
                        .font(.title3)
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            }
            .padding(4)
            .frame(width: 116, height: 87) // 4:3 like the whiteboard
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(ringColor, lineWidth: isCurrent || isSelected ? 2.5 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(SlideNavigatorColors.accent)
                        .background(Circle().fill(.white))
                        .padding(4)
                }
            }

            Text("\(index + 1)")
                .font(.caption2.monospacedDigit().weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(isCurrent ? SlideNavigatorColors.accent : Color.black.opacity(0.4))
                )
                .padding(5)
        }
        .scaleEffect(isCurrent ? 1.0 : 0.94)
        // Squeeze while the finger holds still, signaling the pending selection.
        .scaleEffect(isPressing ? 0.9 : 1.0)
        .shadow(color: .black.opacity(isCurrent ? 0.18 : 0.08), radius: isCurrent ? 5 : 3, y: 2)
        .animation(.snappy(duration: 0.15), value: isPressing)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        // Tap and long press compose without blocking the ScrollView's drag:
        // moving the finger cancels the long press (default 10pt tolerance)
        // and the strip scrolls instead.
        .onTapGesture(perform: onTap)
        .onLongPressGesture(minimumDuration: 0.35) {
            onToggleSelect()
        } onPressingChanged: { pressing in
            isPressing = pressing
        }
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityLabel("Slide \(index + 1)")
        .accessibilityValue([isCurrent ? "Current slide" : nil, isSelected ? "Selected" : nil].compactMap(\.self).joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: isSelected ? "Deselect" : "Select", onToggleSelect)
    }
}

// MARK: - Round key button style

/// A circular physical key matching the counter button's language: raised and
/// shaded at rest; while the finger is down it depresses (inverted shading,
/// shadow gone, nudged down) and flashes an amber-glowing inner outline, then
/// springs back on release.
private struct SlideNavigatorRoundKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .frame(width: 34, height: 34)
            .background(
                Circle().fill(
                    LinearGradient(
                        colors: pressed
                            ? [Color(red: 0.84, green: 0.81, blue: 0.75), Color(red: 0.94, green: 0.92, blue: 0.87)]
                            : [Color.white, Color(red: 0.90, green: 0.87, blue: 0.81)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            )
            .overlay(
                Circle().strokeBorder(
                    LinearGradient(
                        colors: pressed
                            ? [Color.black.opacity(0.28), Color.white.opacity(0.5)]
                            : [Color.white.opacity(0.9), Color.black.opacity(0.16)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            )
            .overlay {
                if pressed {
                    ZStack {
                        Circle()
                            .strokeBorder(SlideNavigatorColors.glow.opacity(0.65), lineWidth: 2.5)
                            .blur(radius: 2)
                        Circle()
                            .strokeBorder(SlideNavigatorColors.glow, lineWidth: 1.2)
                    }
                    .clipShape(Circle())
                    .padding(1)
                    .allowsHitTesting(false)
                }
            }
            .shadow(color: .black.opacity(pressed ? 0 : 0.22), radius: 2.5, y: 2)
            .offset(y: pressed ? 1 : 0)
            .contentShape(Circle())
            .animation(.snappy(duration: 0.12), value: pressed)
    }
}

// MARK: - Shell style + colors

/// Warm color tokens matching the app's design language (AppColors is
/// internal to the Documents module, so the Slides module keeps local copies).
private enum SlideNavigatorColors {
    static let shellCream = Color(red: 0.97, green: 0.95, blue: 0.90)
    static let accent = Color(red: 0.91, green: 0.45, blue: 0.32)      // terracotta
    static let secondary = Color(red: 0.96, green: 0.78, blue: 0.45)   // mustard
    static let ink = Color(red: 0.24, green: 0.22, blue: 0.20)
    static let glow = Color(red: 1.0, green: 0.58, blue: 0.22)         // amber
}

private struct SlideNavigatorShell<S: InsettableShape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content
            .background(shape.fill(.regularMaterial))
            .background(shape.fill(SlideNavigatorColors.shellCream.opacity(0.72)))
            .overlay(shape.strokeBorder(Color.white.opacity(0.7), lineWidth: 1))
            .overlay(shape.strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
            .shadow(color: .white.opacity(0.6), radius: 3, x: -1, y: -1)
    }
}

private extension View {
    func slideNavigatorShell<S: InsettableShape>(_ shape: S) -> some View {
        modifier(SlideNavigatorShell(shape: shape))
    }
}

// MARK: - Preview

#Preview("Navigator (mock slides)") {
    @Previewable @State var isOpen = true
    let slides = (0..<9).map { _ in SlideMetadata() }
    return ZStack(alignment: .bottomTrailing) {
        Color(red: 0.98, green: 0.97, blue: 0.94)
        SlideNavigatorView(
            slides: slides,
            currentIndex: 2,
            isFilmstripOpen: $isOpen,
            thumbnail: { _ in nil },
            onGoTo: { _ in },
            onPrevious: {},
            onNext: {},
            onAdd: {},
            onMoveSlides: { _, _ in },
            onDeleteSlides: { _ in }
        )
        .padding(24)
    }
    .frame(width: 700, height: 340)
}
