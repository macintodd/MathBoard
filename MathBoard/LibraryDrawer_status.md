# Library Drawer — Status

Status: **Prototype (live insertions)** · Live canvas overlay · Last updated 2026-07-22

## Purpose

The Library drawer is a right-edge, slide-out **materials folder** for MathBoard:
a place to find and (later) insert reusable teaching materials during live
high-school math tutoring. It is separate from the compact tool palette — the
palette *does actions* (draw / select / extract / add), the Library *finds and
inserts* reusable objects.

## Current prototype scope

A SwiftUI drawer that matches the design mockups and now renders as a right-edge
overlay on the live `PresentingCanvasView`. Recent items persist per
`.mathboard` file for supported inserted objects. Global library folders and
starred Recent items now persist across files. PNG-backed items in persisted
libraries can be dragged from the drawer and dropped onto the canvas, and
widget-backed entries carry reusable widget JSON templates that insert as fresh
interactive canvas widgets, and LaTeX-backed entries carry editable source plus
their rendered PNG so they insert as resizable equation objects. It remains
previewable via the **Library** scheme and has been confirmed rendering on device
(iPad, landscape).

Supported in the prototype:

- **Skeuomorphic gold folder tab** on the right edge, vertical "LIBRARY" text,
  positioned near the **top** of the board (`folderTabTopInset`). Tapping it
  opens/closes the panel.
- Panel header ("Library" + ✕ close) and a **Recent | Libraries** segmented
  control (`LibraryMode`).
- **Recent mode** — a grid of objects inserted on *this* board, each a card with
  a type **badge** (INK / STICKER / HTML / GIF / TEXT / f(x)) top-left and a **star**
  top-right. A banner reads "Starred items will be added to **<library>**".
  Tapping a star files the item into the current destination library and persists
  a stored copy with its PNG thumbnail when available. Per the design decision,
  **ink appears only when it was Extracted into a sticker** — raw handwriting
  never shows here.
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
| `MathBoardCore/Sources/Library/LibraryModels.swift` | Design tokens (`LibraryTheme`, incl. gold folder-tab colors), enums (`LibraryMode`, `LibraryBadge`, `LibraryThumbnailStyle`), models (`LibraryObject`, `LibraryFolder`), drag payload (`LibraryCanvasDragPayload`), and mock content (`LibraryMock`: `recent`, `folders`, `objects(in:)`, `defaultDestination`). |
| `MathBoardCore/Sources/Library/LibraryRecentStore.swift` | Public per-lesson Recent sidecar API. Stores `library/recent.json` plus optional PNG thumbnails in `library/recent-assets/` inside each `.mathboard` package. |
| `MathBoardCore/Sources/Library/LibraryStore.swift` | Public global reusable Library store. Persists library folders in Application Support plus starred Recent items and copied thumbnails per library. |
| `MathBoardCore/Sources/Library/LibraryDrawerPrototypeView.swift` | `LibraryDrawerPrototypeView` + folder tab, mode picker, persisted Recent loading, Recent grid, persisted Libraries grid + opened-library detail, star handling, code-drawn or PNG thumbnails, preview host, `#Preview`s. |
| `MathBoard/LibraryDrawer_status.md` | This document. |

`MathBoardCore/Package.swift` exposes the `Library` target/product and links it
into `Presentation` so `PresentingCanvasView` can render
`LibraryDrawerPrototypeView(startOpen: false)` over the live canvas. `Slides` and
`Presentation` both depend on `Library` to record supported inserted objects into
per-lesson Recents.

Related: the compact tool palette's old "Widget" tool (`ToolID.reserved`) is now
the **"Add" (+) tool** — selecting it shows a mini strip of authored/inserted
content including **Text**, **f(x)** LaTeX, **Widget**, image import options,
Sticker, and Axis (`AddItemKind` + `.addItem`).

## Design decisions

- **Two modes, one folder.** Replaced the earlier 4-section-tab design
  (Stickers/Widgets/Collections/Recent) with the mockups' single gold folder tab
  + Recent | Libraries segmented control.
- **Recent is per-board; Libraries are global.** Recent saves with the
  `.mathboard` file (each file its own; duplicating or importing a lesson package
  explicitly preserves its Recent sidecar); Libraries are persisted globally in
  Application Support and reusable across every file.
- **Ink = extracted only.** Honors "no raw handwriting" while still showing the
  INK badge from the mockup for Extract-made stickers.
- **Star files into the last-opened library**, surfaced in the Recent banner.
- **Recent sidecar.** Supported insertions append to `library/recent.json` in the
  `.mathboard` package, capped at 80 newest items. Repeated photos/images are
  valid separate Recent items and should not replace each other. PNG thumbnails
  are saved for snapshot/image-like items. Current recording includes text,
  widgets, LaTeX equations, imported images, PDF page objects, graph-calculator snapshots, and
  extracted-region images created by Extract copy+paste, duplicate, send, and
  make-sticker flows. Plain geometry objects are intentionally not added to
  Recents.
- **Preview-safe thumbnails.** Mock content still uses code-drawn thumbnails;
  persisted Recents use saved PNG thumbnails when available and fall back to the
  schematic thumbnail styles.
- **Canvas insertion.** PNG-backed objects in Recent and inside persisted
  Libraries can be dragged onto the canvas for precise placement or tapped to
  insert near the visible viewport center. Widget-backed entries store the
  validated widget JSON and insert as fresh interactive `WidgetObject`s with new
  runtime state. Reusing an item from the Library does not create another Recent
  entry; Recents are recorded only when objects are authored/imported/extracted.
  If a widget placed from the Library is later edited and its JSON changes, the
  edited widget is treated as a new derivative and added to Recents once. Text
  entries carry reusable text payloads, can be inserted from the Library, and use
  the same one-time derivative Recent behavior when their content changes after
  Library placement. LaTeX entries carry both the rendered PNG and source
  metadata; they insert as image-backed equation objects, resize with image
  handles, and reopen in the LaTeX editor from the HUD.
- **Stored item cleanup.** Opened persistent Libraries expose an item menu on
  each stored item with **Rename Item** and **Remove from Library**.
- **Folder management.** Persistent Libraries expose a folder menu from grid/list
  cards and the opened-library header with **Rename Library** and destructive
  **Delete Library** with confirmation.
- **Stable geometry** (panel 366 pt, thumbnail 118 pt, 2-column grids) so layout
  never jumps.

## Intentionally NOT wired yet

- Mock-only schematic library cards without persisted PNG payloads are still browse-only.
- External-display output still comes from `CanvasView`'s render pipeline, so the
  Library drawer is not part of the TV frame.

## Next implementation steps

1. Generate richer widget thumbnails/previews for widget-backed library cards;
   the current first pass uses the schematic widget thumbnail.
2. Add richer text thumbnails/previews for text-backed library cards; the current
   first pass uses the schematic text fallback thumbnail.
3. Expand Recent capture to any newly supported object categories (GIF-specific
   handling, future stickers, and future object types) while keeping plain
   geometry objects out unless the user explicitly changes that rule.
4. Add Add-tool handoff later if Library content should also be reachable from
   the palette; this is intentionally deferred while widget placement is next.
5. Tests once behavior is broader than UI/prototype state.

## Known issues / notes

- The drawer can still be previewed under the **Library** scheme, and it is now
  also linked into the app through the `Presentation` target.
- Full-disk conditions break preview rendering and app builds ("No space left on
  device"); clearing `~/Library/Developer/Xcode/DerivedData` resolves it.
- If the app ever reports **"Missing package product 'SwiftUIMath'"**, run
  **File → Packages → Resolve Package Versions** (re-fetches the remote
  `swiftui-math` dependency after a DerivedData clear).
- Placement gesture (tap vs. drag) and exact drop-coordinate mapping still TBD.
