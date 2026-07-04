# Library Drawer — Status

Status: **Prototype (UI-only)** · Not integrated · Last updated 2026-07-04

## Purpose

The Library drawer is a right-side, slide-out **materials drawer** for MathBoard:
a place to find and (later) insert reusable teaching materials during live
high-school math tutoring. It is deliberately separate from the compact tool
palette — the tool palette is for *doing actions* (draw / select / extract /
text), while the Library is for *finding and inserting* reusable stickers,
widgets, collections, and recents.

The future plan is for the Extract action "Sticker" (which currently behaves
like Clone) to save reusable items into this Library. That wiring is **not**
part of this prototype.

## Current prototype scope

A previewable SwiftUI drawer that visually fits MathBoard's design direction and
can later be wired into the canvas. It is fully self-contained and touches no
existing app behavior.

Supported in the prototype:

- Open / closed state with animated slide-out, driven by an internal `@State`.
- A closed **edge tab** on the right (grid icon + "Library") that toggles open.
- Four top-level tabs: **Stickers · Widgets · Collections · Recent**.
- **Stickers** sub-filters (segmented): **This Lesson · Saved · Built In**, each
  with distinct mock content.
- A **search field** that live-filters mock item titles (case-insensitive) in
  every section, with an empty-state per section.
- **Widgets** grid of mock tiles (Timer, Random Number, Coordinate Axis, Number
  Line, Table, Graph Grid, HTML Widget) using SF Symbols.
- **Collections** rows with mock metadata ("3 widgets · 5 stickers", "8 items").
- **Recent** mixed grid of recently-used stickers and widgets.
- Tap-to-select on any tile/row: shows a selected border and a footer
  "Selected: <name>". Selection is local state only.
- **Mocked drag-to-place** on sticker/widget tiles: dragging summons a ghost
  that follows the finger, a dashed "Drop to place on canvas" zone appears over
  the mock canvas region, and releasing there shows a transient
  "Placed on canvas: <name>" footer. Purely visual — nothing is placed on any
  real canvas. Tap and drag coexist via a simultaneous gesture.
- Code-generated sticker **thumbnails** (no image assets): slope triangle, mini
  graph curve, coordinate grid, number line, formula card (`y = mx + b`),
  highlight box, arrow callout, worked-example lines.

## Files created

| File | Role |
| --- | --- |
| `MathBoardCore/Sources/Library/LibraryModels.swift` | Design tokens (`LibraryTheme`), enums (`LibrarySection`, `StickerScope`, `LibraryItemKind`, `StickerThumbnailStyle`), `LibraryPrototypeItem`, `LibraryCollectionRow`, and all mock content (`LibraryMock`). |
| `MathBoardCore/Sources/Library/LibraryDrawerPrototypeView.swift` | `LibraryDrawerPrototypeView` + all subviews, code-drawn thumbnails, mock whiteboard preview host, and `#Preview`s. |
| `MathBoard/LibraryDrawer_status.md` | This document. |

Also edited:

- `MathBoardCore/Package.swift` — added a `Library` target and a preview-only
  `.library(name: "Library")` product, matching the existing pattern used for
  `WidgetEngine` and `TextEngine`. Nothing links this target, so the live app
  is unaffected.

## Design decisions

- **Lighter than the tool palette on purpose.** `ToolPaletteTheme` is dark
  slate/ink ("sci-fi"). The Library uses warm-white panels, soft blue-gray
  hairlines, a restrained classroom-blue accent (`RGB 0.29/0.53/0.86`), and
  slate/ink text — a friendly "materials drawer" feel, not a second palette.
- **Own module + preview product.** Placing files under `Sources/Library/`
  requires a matching SwiftPM target; exposing it as a preview-only product
  mirrors `WidgetEngine`/`TextEngine`, keeps it isolated, and makes it trivial
  to delete (remove the folder + two `Package.swift` blocks).
- **No image assets.** All sticker thumbnails are drawn with SwiftUI shapes/paths
  so the prototype ships zero resources.
- **Stable geometry.** Fixed panel width (348 pt), thumbnail height (78 pt), and
  tile sizing so layout never jumps when switching tabs/filters.
- **Modest radii** (panel 22 pt, cards 11 pt) and a single soft dual shadow, in
  line with the app's clean material look. No gradients or decorative blobs.
- **Cards not nested in cards.** Tiles sit directly on the panel; the segmented
  controls are the only recessed surfaces.
- **`Prototype` / `Mock` naming** throughout to signal this is not production
  state.

## Intentionally NOT wired yet

- No integration into the live Canvas, Slides, Presentation, ToolPalette, or
  Documents. The drawer is preview-only.
- No persistence for stickers/widgets/collections — all content is `LibraryMock`.
- No *real* drag-and-drop. The drag-to-place interaction is a preview-only mock
  (ghost + dashed drop zone + feedback); it never places anything on a real
  canvas and carries no drag payload / drop target plumbing.
- No Extract → Sticker saving. "This Lesson" stickers are mocked, not sourced
  from a real `.mathboard` file.
- No real widget configuration/placement. Widget tiles only communicate intent
  ("Tap to configure / place").
- `Project_status.md` was **not** changed (per instructions).

## Next implementation steps

1. Decide the host: overlay the drawer inside the Presentation/Canvas view
   hierarchy behind a feature flag (mirrors the ToolPalette integration).
2. Replace `LibraryMock` with real data sources:
   - "This Lesson" ← extracted regions from the current `.mathboard` file.
   - "Saved" ← a cross-lesson sticker store (define the persisted model + store).
   - "Built In" ← bundled prefab sticker packs.
3. Wire Extract → Sticker to persist a captured canvas region into "Saved".
4. Implement insertion — **both tap-to-place and drag-to-place** (decided):
   - Tap a sticker/widget → place it at a default canvas location (e.g. viewport
     center) via a Coordinator.
   - Drag a tile → carry a real drag payload and drop onto the canvas at the
     drop point, converting drawer/global geometry to canvas coordinates.
   The prototype already mocks both gestures; replace the mock feedback with the
   real Coordinator calls.
5. Real widget configuration flows (Timer, Random Number, axes, etc.), likely
   reusing the WidgetEngine module.
6. Persist "Recent" from actual insert events.
7. Add unit/UI tests once behavior (not just layout) exists.

## Known issues / open questions

- **Thumbnail fidelity:** current thumbnails are schematic placeholders; real
  stickers will need rendered snapshots of captured canvas regions.
- **Collections model:** metadata strings are mock; the real grouping model
  (tags? explicit folders? per-lesson vs. global?) is undecided.
- **Placement gesture:** decided — support **both** tap-to-place and
  drag-to-place. The prototype now mocks both; the real drop uses the leading
  "canvas" region as a stand-in target, so exact drop-coordinate mapping is
  still to be worked out against the real Canvas.
- **Left palette in the preview** is a 4-icon mock, intentionally *not* the real
  `CompactToolPaletteView`, only to judge scale.
- **Sizing** is tuned for iPad; phone/compact width behavior is unaddressed.
