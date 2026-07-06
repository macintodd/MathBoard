# Library Drawer — Status

Status: **Prototype (UI-only)** · Not integrated · Last updated 2026-07-05

## Purpose

The Library drawer is a right-edge, slide-out **materials folder** for MathBoard:
a place to find and (later) insert reusable teaching materials during live
high-school math tutoring. It is separate from the compact tool palette — the
palette *does actions* (draw / select / extract / add), the Library *finds and
inserts* reusable objects.

## Current prototype scope

A previewable SwiftUI drawer that matches the design mockups. Fully
self-contained (isolated `Library` SwiftPM target); touches no app behavior and
has no persistence. Previewed via the **Library** scheme; confirmed rendering on
device (iPad, landscape).

Supported in the prototype:

- **Skeuomorphic gold folder tab** on the right edge, vertical "LIBRARY" text,
  positioned near the **top** of the board (`folderTabTopInset`). Tapping it
  opens/closes the panel.
- Panel header ("Library" + ✕ close) and a **Recent | Libraries** segmented
  control (`LibraryMode`).
- **Recent mode** — a grid of objects inserted on *this* board, each a card with
  a type **badge** (INK / STICKER / HTML / GIF / TEXT) top-left and a **star**
  top-right. A banner reads "Starred items will be added to **<library>**".
  Tapping a star files the item into the current destination library (mocked;
  shows transient footer feedback). Per the design decision, **ink appears only
  when it was Extracted into a sticker** — raw handwriting never shows here.
- **Libraries mode** — a grid of reusable **library cards** (icon chip, name,
  "N items") plus a dashed **"New library"** card. Tapping a library **opens**
  it into a detail view: a sub-header with a **back arrow** (← returns to the
  library grid), the library name, and item count, over a grid of the library's
  object cards. You can also switch back to Recent at any time via the segmented
  control.
- **Star destination = last library opened.** Opening a library (Libraries mode)
  sets it as the Recent banner's destination; defaults to Quadratics until one
  is opened.
- Code-generated **thumbnails** (no image assets): parabola, sine, circle+radius,
  bar chart, right triangle, up-arrow, gold-star sticker (on a checkerboard
  cut-out), timer widget, GIF card, ink square, generic graph.
- Three landscape `#Preview`s (Recent open, closed folder tab, panel only) over a
  dotted mock board.

## Files

| File | Role |
| --- | --- |
| `MathBoardCore/Sources/Library/LibraryModels.swift` | Design tokens (`LibraryTheme`, incl. gold folder-tab colors), enums (`LibraryMode`, `LibraryBadge`, `LibraryThumbnailStyle`), models (`LibraryObject`, `LibraryFolder`), and mock content (`LibraryMock`: `recent`, `folders`, `objects(in:)`, `defaultDestination`). |
| `MathBoardCore/Sources/Library/LibraryDrawerPrototypeView.swift` | `LibraryDrawerPrototypeView` + folder tab, mode picker, Recent grid, Libraries grid + opened-library detail, star handling, code-drawn thumbnails, preview host, `#Preview`s. |
| `MathBoard/LibraryDrawer_status.md` | This document. |

`MathBoardCore/Package.swift` still exposes the preview-only `Library` target /
product (nothing links it), so the live app is unaffected.

Related (separate work): the compact tool palette's old "Widget" tool
(`ToolID.reserved`) is now the **"Add" (+) tool** — selecting it shows a mini
strip of **File · Widget · Sticker · Axis** (`AddItemKind` + `.addItem`). That
is the intended entry point for placing Library/sticker/widget content later.

## Design decisions

- **Two modes, one folder.** Replaced the earlier 4-section-tab design
  (Stickers/Widgets/Collections/Recent) with the mockups' single gold folder tab
  + Recent | Libraries segmented control.
- **Recent is per-board; Libraries are global.** Recent conceptually saves with
  the `.mathboard` file (each file its own; duplicating a file copies its Recent
  library); Libraries are reusable across every file. All mocked with comments.
- **Ink = extracted only.** Honors "no raw handwriting" while still showing the
  INK badge from the mockup for Extract-made stickers.
- **Star files into the last-opened library**, surfaced in the Recent banner.
- **No image assets.** Every thumbnail is drawn with SwiftUI shapes/`Canvas`.
- **Stable geometry** (panel 366 pt, thumbnail 118 pt, 2-column grids) so layout
  never jumps.

## Intentionally NOT wired yet

- No integration into the live Canvas, Slides, Presentation, ToolPalette, or
  Documents. Preview-only.
- No persistence. `LibraryMock` is the only content; Recent per-board saving,
  file-duplication copying, library creation, and cross-file library sharing are
  all mocked (starring/new-library only show transient footer text).
- No real Extract → Recent capture, and no canvas insertion / drag-and-drop.
- `Project_status.md` unchanged by this work.

## Next implementation steps

1. Real Recent source: capture every inserted object (text, GIF, widget,
   sticker, extracted-ink sticker) for the current board, newest first; persist
   it with the `.mathboard` file and copy it on duplication.
2. Real library store: create/rename libraries; star → add object to the
   last-opened library; share libraries across files.
3. Wire insertion (tap/drag → place on canvas via a Coordinator), likely from
   the new **Add (+)** tool's strip.
4. Replace schematic thumbnails with rendered snapshots of the real objects.
5. Tests once behavior (not just layout) exists.

## Known issues / notes

- **Scheme gotcha:** the isolated `Library` target only builds/previews under the
  **Library** scheme; the app/MathBoard scheme does not include it. Switch
  schemes to preview.
- Full-disk conditions break preview rendering and app builds ("No space left on
  device"); clearing `~/Library/Developer/Xcode/DerivedData` resolves it.
- If the app ever reports **"Missing package product 'SwiftUIMath'"**, run
  **File → Packages → Resolve Package Versions** (re-fetches the remote
  `swiftui-math` dependency after a DerivedData clear).
- Placement gesture (tap vs. drag) and exact drop-coordinate mapping still TBD.
