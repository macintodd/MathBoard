//
//  SlideNavPreviewHarness.swift
//  MathBoardCore — SlideNav prototype module
//
//  A fake whiteboard scene for designing the navigator in Xcode previews:
//  cream canvas showing the current mock slide's content, plus stand-ins for
//  the lesson chrome (back button + title, top-leading) and the ••• tool menu
//  (top-trailing), so placement can be judged against the real chrome. Select
//  the "SlideNav" scheme in Xcode to build these previews. Fully interactive:
//  navigate, open the filmstrip, add/delete/move slides.
//

import SwiftUI

struct SlideNavPreviewHarness: View {
    @State private var state: SlideNavState
    let placement: SlideNavPlacement

    init(placement: SlideNavPlacement = .bottomTrailing, startOpen: Bool = false, slideCount: Int = 9) {
        let state = SlideNavState(slideCount: slideCount)
        state.isFilmstripOpen = startOpen
        _state = State(initialValue: state)
        self.placement = placement
    }

    var body: some View {
        ZStack {
            mockCanvas
            mockLessonChrome
            navigatorOverlay
        }
    }

    /// The current slide's doodle fills the screen, so slide navigation is
    /// visible in the harness just like on the real whiteboard. Blank slides
    /// (freshly added) show an empty canvas.
    private var mockCanvas: some View {
        ZStack {
            SlideNavColors.canvasCream
            if let variant = state.currentSlide?.artVariant {
                SlideNavMockArt(variant: variant)
                    .padding(80)
                    .opacity(0.9)
            }
        }
        .ignoresSafeArea()
    }

    private var mockLessonChrome: some View {
        VStack {
            HStack(alignment: .center) {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(.regularMaterial))

                    Text("Algebra 2 — 5.3 Quadratics")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.regularMaterial))
                }

                Spacer()

                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(.regularMaterial))
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()
        }
    }

    private var navigatorOverlay: some View {
        VStack {
            if placement == .topLeading {
                HStack {
                    SlideNavView(state: state, placement: placement)
                        .padding(.leading, 16)
                        .padding(.top, 56) // below the mock lesson chrome
                    Spacer()
                }
                Spacer()
            } else {
                Spacer()
                HStack {
                    Spacer()
                    SlideNavView(state: state, placement: placement)
                        .padding(.trailing, 16)
                        .padding(.bottom, 14)
                }
            }
        }
    }
}

#Preview("Lower Right — collapsed", traits: .fixedLayout(width: 1194, height: 834)) {
    SlideNavPreviewHarness(placement: .bottomTrailing)
}

#Preview("Lower Right — filmstrip open", traits: .fixedLayout(width: 1194, height: 834)) {
    SlideNavPreviewHarness(placement: .bottomTrailing, startOpen: true)
}

#Preview("Top Leading — by lesson title", traits: .fixedLayout(width: 1194, height: 834)) {
    SlideNavPreviewHarness(placement: .topLeading, startOpen: true)
}

#Preview("Many slides", traits: .fixedLayout(width: 1194, height: 834)) {
    SlideNavPreviewHarness(placement: .bottomTrailing, startOpen: true, slideCount: 24)
}

#Preview("Navigator only") {
    SlideNavView(state: SlideNavState())
        .padding(40)
        .background(SlideNavColors.canvasCream)
}
