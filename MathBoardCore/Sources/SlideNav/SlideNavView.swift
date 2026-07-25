//
//  SlideNavView.swift
//  MathBoardCore — SlideNav prototype module
//
//  Redesigned slide navigator. Two pieces:
//   - Collapsed pill: back / "3 of 12" counter / forward. Deliberately minimal —
//     the current in-app navigator crams move/delete/add into the pill; here
//     those live in the filmstrip header, where the slides are visible.
//   - Filmstrip panel: blooms out of the pill toward the canvas. Header row
//     holds the management actions (move left/right, delete, add); below it a
//     horizontal strip of landscape 4:3 thumbnails (the whiteboard is 4:3).
//
//  Styling follows the app's warm FigJam-ish language: cream shell over
//  material, terracotta accent, mustard for the add CTA, soft dual shadows
//  echoing the compact tool palette's neumorphic look.
//

import SwiftUI

struct SlideNavView: View {
    let state: SlideNavState
    var placement: SlideNavPlacement = .bottomTrailing

    /// Scroll target of the thumbnail strip (see `scrollPosition` below).
    @State private var scrolledSlideID: UUID?

    var body: some View {
        // The filmstrip panel is ALWAYS laid out (hidden via opacity/scale when
        // closed, never inserted/removed), so the navigator's frame is constant:
        // the pill cannot move and the panel cannot cover it — the panel owns
        // the space above (or below, for top placement) the pill permanently.
        // Hidden space is transparent and non-hit-testable, so it never blocks
        // canvas interaction.
        VStack(alignment: placement.filmstripOpensDownward ? .leading : .trailing, spacing: 10) {
            if placement.filmstripOpensDownward {
                pill
                filmstrip
            } else {
                filmstrip
                pill
            }
        }
        .animation(.snappy(duration: 0.28, extraBounce: 0.06), value: state.isFilmstripOpen)
        .animation(.snappy(duration: 0.22), value: state.currentIndex)
        // NOTE: deliberately no `.animation(value: state.slides)` — animating
        // tile insertion means scroll-to-the-new-slide requests resolve against
        // mid-animation content and get dropped.
        .animation(.snappy(duration: 0.18), value: state.selectedIDs)
    }

    // MARK: - Collapsed pill

    private var pill: some View {
        HStack(spacing: 8) {
            navArrowButton(systemName: "chevron.left", enabled: state.canGoPrevious, label: "Previous slide") {
                state.goToPrevious()
            }

            counterButton

            navArrowButton(systemName: "chevron.right", enabled: state.canGoNext, label: "Next slide") {
                state.goToNext()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .slideNavShell(Capsule())
    }

    /// The counter looks like a physical key: raised and shaded while the
    /// filmstrip is closed; pressing it depresses the same button (inverted
    /// shading, no drop shadow, nudged down) and lights an amber-glowing
    /// inner outline while the filmstrip is open.
    private var counterButton: some View {
        let isPressed = state.isFilmstripOpen
        return Button {
            state.isFilmstripOpen.toggle()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "rectangle.stack")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SlideNavColors.accent)

                HStack(spacing: 3) {
                    Text("\(state.currentIndex + 1)")
                        .font(.subheadline.monospacedDigit().weight(.bold))
                        .foregroundStyle(SlideNavColors.ink)
                    Text("of \(state.totalCount)")
                        .font(.subheadline.monospacedDigit().weight(.medium))
                        .foregroundStyle(Color.secondary)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(
                // Raised: lit from above. Pressed: shading inverts — darker at
                // the top, as if the key sank below the surface.
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
                // Bevel. Raised: bright top rim, shaded bottom. Pressed: the
                // surrounding surface shades the top inner edge instead.
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
                // Amber-glowing inner outline while depressed.
                if isPressed {
                    ZStack {
                        Capsule()
                            .strokeBorder(SlideNavColors.glow.opacity(0.65), lineWidth: 2.5)
                            .blur(radius: 2)
                        Capsule()
                            .strokeBorder(SlideNavColors.glow, lineWidth: 1.2)
                    }
                    .clipShape(Capsule())
                    .padding(1)
                    .allowsHitTesting(false)
                }
            }
            // Raised keys cast a shadow; depressed ones don't, and sit lower.
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
                .foregroundStyle(SlideNavColors.ink)
        }
        .buttonStyle(SlideNavRoundKeyStyle())
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
        .slideNavShell(RoundedRectangle(cornerRadius: 20, style: .continuous))
        // Hidden-in-place instead of removed: the bloom is opacity + scale from
        // the corner nearest the pill, and layout never changes.
        .opacity(state.isFilmstripOpen ? 1 : 0)
        .scaleEffect(state.isFilmstripOpen ? 1 : 0.86, anchor: placement.bloomAnchor)
        .allowsHitTesting(state.isFilmstripOpen)
        .accessibilityHidden(!state.isFilmstripOpen)
    }

    /// Panel width sized to the thumbnails (tile 116 + spacing 10, plus strip
    /// and panel padding), clamped so the header always fits and long lessons
    /// scroll instead of growing unbounded.
    private var filmstripPanelWidth: CGFloat {
        let tiles = CGFloat(state.totalCount) * 126 + 22
        return min(560, max(400, tiles))
    }

    private var filmstripHeader: some View {
        HStack(spacing: 8) {
            Text(state.hasSelection ? "\(state.selectionCount) selected" : "Slides")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(state.hasSelection ? SlideNavColors.accent : .secondary)
                .padding(.leading, 4)

            Spacer(minLength: 12)

            Button {
                state.toggleSelectAll()
            } label: {
                Text(state.isAllSelected ? "Deselect All" : "Select All")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SlideNavColors.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.6)))
                    .overlay(Capsule().strokeBorder(Color.black.opacity(0.06), lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)

            headerActionButton(
                systemName: "arrow.left.to.line",
                enabled: state.canMoveActionSlidesLeft,
                label: state.hasSelection ? "Move selected slides left" : "Move slide left"
            ) {
                state.moveActionSlides(by: -1)
            }
            headerActionButton(
                systemName: "arrow.right.to.line",
                enabled: state.canMoveActionSlidesRight,
                label: state.hasSelection ? "Move selected slides right" : "Move slide right"
            ) {
                state.moveActionSlides(by: 1)
            }
            headerActionButton(
                systemName: "trash",
                enabled: state.canDeleteActionSlides,
                label: state.hasSelection ? "Delete selected slides" : "Delete slide",
                tint: .red
            ) {
                state.deleteActionSlides()
            }

            Button {
                state.addSlide()
            } label: {
                Image(systemName: "plus")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(SlideNavColors.ink)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(SlideNavColors.secondary))
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
        tint: Color = SlideNavColors.ink,
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
                    ForEach(Array(state.slides.enumerated()), id: \.element.id) { index, slide in
                        SlideNavThumbnailTile(
                            slide: slide,
                            index: index,
                            isCurrent: index == state.currentIndex,
                            isSelected: state.isSelected(slide),
                            onTap: { state.handleTap(at: index) },
                            onToggleSelect: { state.toggleSelection(at: index) }
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
            .onChange(of: state.currentIndex) { _, _ in
                scrollToCurrent(proxy: proxy, animated: true)
            }
            .onChange(of: state.totalCount) { _, _ in
                // Content changed in this transaction; scroll requests made
                // while the strip is still laying out / animating get dropped.
                // Re-assert the target well after everything settles.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    scrollToCurrent(proxy: proxy, animated: true)
                }
            }
            .onChange(of: state.isFilmstripOpen) { _, isOpen in
                if isOpen { scrollToCurrent(proxy: proxy, animated: false) }
            }
        }
    }

    private func scrollToCurrent(proxy: ScrollViewProxy, animated: Bool) {
        guard let id = state.currentSlide?.id else { return }
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

private struct SlideNavThumbnailTile: View {
    let slide: SlideNavSlide
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
        if isCurrent { return SlideNavColors.accent }
        if isSelected { return SlideNavColors.secondary }
        return Color.black.opacity(0.12)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let variant = slide.artVariant {
                    SlideNavMockArt(variant: variant)
                } else {
                    Color.clear // blank slide — plain white card
                }
            }
                .padding(6)
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
                            .foregroundStyle(SlideNavColors.accent)
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
                    Capsule().fill(isCurrent ? SlideNavColors.accent : Color.black.opacity(0.4))
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
private struct SlideNavRoundKeyStyle: ButtonStyle {
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
                            .strokeBorder(SlideNavColors.glow.opacity(0.65), lineWidth: 2.5)
                            .blur(radius: 2)
                        Circle()
                            .strokeBorder(SlideNavColors.glow, lineWidth: 1.2)
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

// MARK: - Shared shell style

private struct SlideNavShell<S: InsettableShape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content
            .background(shape.fill(.regularMaterial))
            .background(shape.fill(SlideNavColors.shellCream.opacity(0.72)))
            .overlay(shape.strokeBorder(Color.white.opacity(0.7), lineWidth: 1))
            .overlay(shape.strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
            .shadow(color: .white.opacity(0.6), radius: 3, x: -1, y: -1)
    }
}

extension View {
    func slideNavShell<S: InsettableShape>(_ shape: S) -> some View {
        modifier(SlideNavShell(shape: shape))
    }
}

// MARK: - Previews
// Component-only previews. For the navigator in a full mock whiteboard with
// lesson chrome and placement variants, open SlideNavPreviewHarness.swift.

#Preview("Collapsed pill") {
    SlideNavView(state: SlideNavState())
        .padding(40)
        .background(SlideNavColors.canvasCream)
}

// The filmstrip is an overlay above the pill, so the preview needs a canvas
// tall enough to show it; anchor the navigator bottom-trailing like the app.
#Preview("Filmstrip open") {
    let state = SlideNavState()
    state.isFilmstripOpen = true
    return ZStack(alignment: .bottomTrailing) {
        SlideNavColors.canvasCream
        SlideNavView(state: state)
            .padding(24)
    }
    .frame(width: 700, height: 340)
}

// Verifies the strip scrolls to a far-right current slide (e.g. right after
// adding a slide at the end of the deck).
#Preview("Current slide is last") {
    let state = SlideNavState(slideCount: 12)
    state.isFilmstripOpen = true
    state.currentIndex = 11 // on the last slide…
    state.addSlide()        // …press +: now 13 slides, current = blank slide 13
    return ZStack(alignment: .bottomTrailing) {
        SlideNavColors.canvasCream
        SlideNavView(state: state)
            .padding(24)
    }
    .frame(width: 700, height: 340)
}

// Self-driving repro of the "+ on the last slide" flow: the slide is added
// AFTER the view is on screen, exactly like an interactive + press.
#Preview("Auto-add repro") {
    let state = SlideNavState(slideCount: 12)
    state.isFilmstripOpen = true
    state.currentIndex = 11
    return ZStack(alignment: .bottomTrailing) {
        SlideNavColors.canvasCream
        SlideNavView(state: state)
            .padding(24)
    }
    .frame(width: 700, height: 340)
    .task {
        try? await Task.sleep(for: .milliseconds(600))
        state.addSlide()
    }
}

#Preview("Multi-selection") {
    let state = SlideNavState()
    state.isFilmstripOpen = true
    state.selectedIDs = [state.slides[1].id, state.slides[3].id]
    return ZStack(alignment: .bottomTrailing) {
        SlideNavColors.canvasCream
        SlideNavView(state: state)
            .padding(24)
    }
    .frame(width: 700, height: 340)
}
