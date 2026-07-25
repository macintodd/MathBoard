# SlideNav — Slide Navigator Redesign Prototype

> Isolated design sandbox for replacing the current slide navigator
> (`Slides/SlideNavigator.swift` + `Slides/SlideFilmstripView.swift`).
> Nothing in MathBoard links this target; it links nothing. Select the
> **SlideNav** scheme in Xcode to build and open previews in
> `SlideNavPreviewHarness.swift`.

**Last updated:** 2026-07-24 — first design pass.

## Why

The shipping navigator is a single bottom-center pill with 7 actions crammed
into one row (prev/next, counter, move left/right, delete, add) in plain gray
material — functional but not up to the app's warm aesthetic, and its fixed
center position sits in the drawing area. Candidate new homes: lower-right, or
top-leading next to the lesson-title chrome (harness previews both).

## Design decisions (first pass)

- **Collapsed pill is minimal:** back arrow / "3 of 12" counter / forward
  arrow. Tapping the counter blooms the filmstrip.
- **The counter is a physical key:** closed = raised and shaded (top-lit
  gradient, bevel rim, drop shadow). Open = the same button depresses —
  shading inverts (dark top edge), the drop shadow disappears, it nudges down
  1pt, and an amber-glowing inner outline lights up around the readout. (An
  earlier dark "LED screen" treatment was rejected in favor of this.)
- **The pill's prev/next arrows are momentary keys** with the same physical
  treatment (`SlideNavRoundKeyStyle`, a ButtonStyle driven by
  `configuration.isPressed`): raised at rest; while held they depress and
  flash the amber inner glow, springing back on release.
- **Management actions moved into the filmstrip header** (move left/right,
  delete, add) — you act on slides while looking at them, and the always-on
  pill stays small during teaching.
- **Filmstrip blooms toward the canvas** from the pill's corner
  (`SlideNavPlacement` controls direction + alignment) instead of being a
  fixed bottom-center strip.
- **The pill never moves and is never covered:** the filmstrip panel is
  always laid out above the pill (below, for top placement) and hidden in
  place via opacity + scale + `allowsHitTesting(false)` rather than being
  inserted/removed — so the navigator's frame is constant, the pill can't
  reflow, and the panel occupies its own space instead of overlapping the
  pill. (An `.overlay` + alignment-guide version rendered on top of the pill;
  hidden-in-place is deterministic.) Hidden space is transparent and
  non-hit-testable. Panel width is sized to the slide count, capped at 560pt.
- **Thumbnails are landscape 4:3** (like the whiteboard); the shipping strip
  uses portrait tiles. Current slide gets a terracotta ring, slight scale-up,
  and an accent number badge.
- **Styling:** cream shell over `.regularMaterial`, terracotta accent, mustard
  add-CTA, soft dual shadows — echoes the compact tool palette's neumorphic
  language. Color tokens are local copies (`SlideNavColors`) because
  `AppColors` is internal to Documents.

- **Multi-selection in the filmstrip (Photos-style gestures):** tap =
  navigate to that slide; drag = scroll the strip; long press (~0.35s, finger
  still — tile squeezes while pending) = toggle selection. While a selection
  exists, plain taps toggle membership too, so sets build quickly;
  deselecting the last slide returns taps to navigation. Selection is
  decoupled from navigation (selecting doesn't change the current slide).
  A Select All / Deselect All capsule sits in the header, which shows
  "N selected" while a selection exists. Selection is tracked by slide ID
  (survives reorders) and clears when the strip closes. Visual language:
  terracotta ring = current slide, mustard ring + terracotta checkmark badge
  = selected (a slide can be both). Selection changes play haptic feedback on
  hardware.
- **Selection-aware actions:** move left/right and delete act on the whole
  selection, falling back to the current slide when nothing is selected.
  Non-contiguous moves shift every selected slide one step per click and pack
  against the edges (standard move-selected-items algorithm); delete keeps at
  least one survivor and lands on the nearest remaining slide.

## Files

- `SlideNavModels.swift` — `SlideNavSlide` mock slide, `SlideNavState`
  (interactive mock of SlideStore: navigate/add/delete/move), placement enum,
  color tokens.
- `SlideNavView.swift` — the navigator: pill, filmstrip panel, thumbnail
  tiles, shared shell style.
- `SlideNavMockArt.swift` — deterministic math doodles (parabola, sine, lines,
  circle, triangle, scatter) used as thumbnail + harness canvas stand-ins.
- `SlideNavPreviewHarness.swift` — fake whiteboard with mock lesson chrome and
  `#Preview` variants: lower-right collapsed/open, top-leading, 24 slides,
  navigator-only.

## Wiring status: PORTED (2026-07-24)

Production port lives at `Slides/SlideNavigatorView.swift`, hosted by
`SlidesView`. Contract: the navigator owns selection + scroll state and takes
`slides`/`currentIndex`/`isFilmstripOpen` (Binding) plus callbacks; the host
owns store mutations (insert-after-current add, packing multi-move, multi-
delete with confirmation dialog) and provides cached PDF-page thumbnails
(ink-only slides get a placeholder card). This sandbox remains the place to
iterate on look/feel — design here with previews, then port changes over.
The old `SlideNavigator`/`SlideFilmstripView` stay as unreferenced fallbacks
until hardware verification.

## Open questions / next steps

- Lower-right vs. top-leading placement (previews cover both; decide on iPad).
- Drag-to-reorder thumbnails in the filmstrip (buttons only for now).
- Delete confirmation lives in SlidesView today; decide where it goes.
- Whether the filmstrip should auto-close after picking a slide.
