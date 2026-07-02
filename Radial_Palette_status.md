# MathBoard Radial Palette — Status

> Living design + progress doc for the custom palette system: `CompactToolPaletteView` is now the primary direction; `RadialToolPaletteView` is preserved as an experimental/legacy fallback.
> Read this document top-to-bottom before starting any tool palette work.
>
> **Hard rule:** future tool-palette design and polish should target Compact first. Do not spend new design effort on Radial unless the user explicitly asks.

**Last updated:** 2026-07-01 — Compact palette is primary tool palette direction

---

## Git / Backup Protocol

- GitHub remote: `https://github.com/macintodd/MathBoard.git`
- Stable branch: `main`
- After every tested working milestone, run a clean Xcode build, then create a Git checkpoint before starting risky new work.
- AI assistants in this Xcode/Codex environment can inspect Git state, edit project files, stage/check changes, and run builds, but they cannot reliably create commits or push because writes inside `.git` are blocked by the tool sandbox.
- The user should run this checkpoint sequence in Terminal:

```bash
cd /Users/macminim4/Documents/Develop/MathBoard
git status
git add -A
git commit -m "Short milestone description"
git push
```

- For risky experiments or alternate UI work, use a branch instead of changing `main` directly:

```bash
git checkout -b feature-name
git push -u origin feature-name
```

- Do not commit broken builds to `main`. Keep unfinished experiments on branches until they build and the user has tested the behavior.

---

## Current UI Test Note

- `CompactToolPaletteView` is now the primary tool palette direction for future development.
- Open the top-right **Tool Palette** menu and use **Palette Style** to switch between `Radial` and `Compact`.
- Keep `Radial` in the codebase as an experimental/legacy style and fallback. Do not delete it unless the user explicitly asks.
- New palette design and tool-polish work should target `Compact` first. Only touch `Radial` when fixing regressions, preserving fallback behavior, or when explicitly requested.
- Both styles share the same `ToolPaletteState` and command path so testing compares palette UI, not separate tool behavior.
- `Palette Size` only affects the radial palette.
- Compact palette owns its floating shell/drag handle inside the ToolPalette module, remembers its own position separately from the radial palette, and is edge-aware so the drawer opens toward the canvas.
- Compact drawer animation is rail-anchored: opening/closing the drawer should not displace the main tool rail.
- Compact rail uses segmented neumorphic tool groups; pen/marker/laser icons always show their selected tool color.
- Compact ink tools now use a two-step interaction: first tap selects Pen/Marker/Laser and shows that tool's quick five-color strip; second tap on the selected ink tool toggles the full drawer for width/opacity/details. Each ink tool remembers its own palette preset.
- Compact previews use the floating shell so the Move handle is visible during preview testing.
- Next palette work should proceed tool-by-tool in Compact: shell/drag/collapse behavior, Pen, Marker, Eraser, Selection, Text/Equation, Geometry, and then future Widget/Image/Sticker tools.

---

## 1. One-paragraph summary

The Compact palette is MathBoard's primary planned replacement for Apple's visible PencilKit tool palette on iPad. It should be a teacher-friendly, Apple-Pencil-centered tool surface with streamlined submenus/columns similar in spirit to Explain Everything, while keeping MathBoard's own tool model and visual language. The Radial palette remains in the app as an experimental/legacy fallback selectable from the Tool Palette menu. Future work should refine Compact tool-by-tool; Radial should be preserved, not expanded, unless explicitly requested.

---

## 2. Non-negotiable constraints

- **Do not replace PencilKit's drawing engine right now.** MathBoard already has working PencilKit storage, iPad/Mac file compatibility, PDF backgrounds, PDF export, external-display mirroring, live-stroke overlay, undo/redo, and `.mathboard` package persistence. A custom vector drawing engine is a future research project, not the next palette step.
- **Compact is primary.** Future palette work should start in `CompactToolPaletteView.swift` and shared definitions/reducer files, not in the radial view.
- **Build like the calculator.** Develop palette changes in isolated, reviewable pieces first, then wire them into the app with small integration edits.
- **Keep the palette data-driven.** Compact and Radial should render configuration supplied by active tool definitions. Avoid hardcoding every tool's UI behavior directly into palette views with large switch statements.
- **Prefer PencilKit control for v1.** The first integrated version should set `PKCanvasView.tool`, color, width, eraser mode, and related state rather than owning a new drawing engine.
- **Selection and object editing are future-dependent.** Full selection, region cutting, stickers, movable PDF objects, graph snapshots, image objects, and geometry editing depend on a future object layer. The palette can reserve UI for these tools, but should not fake deep object support before the object model exists.

---

## 3. Current Design Objective

The Compact palette should feel fast, streamlined, and classroom-friendly:

- The teacher can change tools, color, width, opacity, eraser mode, and laser mode without leaving the writing area.
- Common controls appear in the main rail and streamlined submenus/columns that can be moved out of the way.
- The palette should avoid covering instructional content as much as possible.
- It should fade to low opacity, roughly 10%, during selection-box drawing or other content-focused gestures where visibility matters.
- It should be visually stable and predictable: the rail selects tools; the adjacent drawer/columns configure the active tool.
- It should scale cleanly to more tools without requiring a rewrite of the palette renderer.
- Visual direction: compact dark navy dock, subtle raised/inset surfaces, cyan active accents, icon-first controls with compact labels, and streamlined submenus inspired by Explain Everything's tool palette.

---

## 4. Legacy Radial UI Concept

The radial palette is preserved as an experimental/legacy fallback. Its concept consists of:

- **Scalable circular dial** controlled by `dialSize`.
- **Center Hero Button** showing the active tool.
- **Main wheel** with eight permanent tool slots.
- **Top Orbit** for active-tool actions or context-specific nodes.
- **Bottom Left Arc** for a continuous slider, segmented control, or disabled state.
- **Bottom Right Arc** for a continuous slider, segmented control, or disabled state.
- **Optional outer ring / Color Bloom** for expanded color selection.

Reusable arc capabilities:

- Continuous slider.
- Segmented control.
- Disabled state.
- Tool-specific labels/icons.
- Stable geometry across size changes.

Initial standalone implementation choices:

- Use `MathBoardCore/Sources/ToolPalette/` as a new Swift package target.
- Do not add `ToolPalette` as a dependency of `Canvas`, `Presentation`, `Slides`, `Documents`, or the app target.
- Provide a standalone prototype host view with a mock canvas and command log.
- Start with the Pen tool as the only fully active tool.
- Render the remaining seven tool slots as selectable placeholders so geometry and command flow can be evaluated without pretending the future object tools exist.

---

## 5. Tool slots

The main wheel reserves eight permanent positions (clockwise from the top-left
slot, matching `ToolPaletteDefinitions.orderedToolIDs`):

1. **Selection**
2. **Laser Pointer**
3. **Pen**
4. **Marker**
5. **Eraser**
6. **Geometry**
7. **Reserved / Future Tool**
8. **fx / Equation Tool**

Slot 7 intentionally remains open for a future tool such as Text, Ruler,
Protractor, or another classroom-specific feature.

---

## 6. Top orbit behavior

Top orbit follows this rule:

**Top orbit performs contextual actions related to the active tool.**

Planned configurations:

- **Default drawing tools:** five preset colors; 12 o'clock indicates the active color or opens Color Bloom depending on tool context.
- **Geometry:** Line, Circle, Right Triangle, Polygon; 12 o'clock opens Color Bloom.
- **Selection before selection exists:** hidden or minimal.
- **Selection after selection exists:** Copy, Duplicate, Extract as Image Sticker, Send to Next Slide, Delete.
- **Laser:** possible quick actions such as clear trail or pointer style, if needed.
- **fx:** possible actions for insert, convert, or snapshot later.

---

## 7. Color Bloom

Color Bloom is an expandable outer ring for richer color control.

Planned behavior:

- Opens from the color node, especially in Geometry mode.
- Center transforms into a `Border | Fill` segmented selector for tools that support fill.
- Outer ring displays a 10-color palette.
- Selecting a color updates either border color or fill color depending on the active center segment.

For v1 standalone work, Color Bloom may be implemented as a visual/interaction prototype only. Real fill color is not useful until geometry/object tools exist.

For the first pen-tool pass, Color Bloom is deferred. The top orbit shows five fixed color presets and emits `setStrokeColor` commands.

---

## 8. Bottom arc behavior

Bottom arcs follow this rule:

**Bottom arcs configure how the active tool behaves.**

Planned tool-specific mappings:

- **Pen**
  - Left: thickness.
  - Right: opacity.
- **Marker**
  - Left: thickness.
  - Right: opacity.
- **Eraser**
  - Left: size.
  - Right: pixel/object or stroke/object mode.
- **Laser**
  - Left: size.
  - Right: dot/trail mode.
- **fx**
  - Left: text size.
  - Right: normal/bold.
- **Geometry normal mode**
  - Left: context-sensitive value, such as polygon sides or arrowheads.
  - Right: disabled unless needed.
- **Geometry with Color Bloom open**
  - Left: border thickness.
  - Right: opacity.
- **Selection pre-selection**
  - Left: object/region target.
  - Right: lasso/marquee mode.
- **Selection post-selection**
  - Left: rotation.
  - Right: disabled initially.

---

## 9. Selection philosophy

Selection should eventually use a two-state workflow.

Pre-selection:

- User chooses target: Object or Region.
- User chooses mode: Lasso or Marquee.
- Object mode selects entire strokes/objects.
- Region mode can eventually cut precisely through images/PDFs/ink once the object layer supports it.

Post-selection:

- Top orbit becomes action buttons: Copy, Duplicate, Extract as Image Sticker, Send to Next Slide, Delete.
- Selection receives bounding box handles.
- Left arc becomes a rotation slider.
- Native gestures perform move, resize, and rotate.
- The radial menu exposes higher-level operations, not every direct manipulation.

Important: full selection depends on the future object layer and should not be forced into the standalone palette v1.

---

## 10. Architecture decision

Use a hybrid of the two AI recommendations:

- Keep the Notion radial UX and interaction model.
- Use the second AI's data-driven tool architecture.
- Do **not** build a custom vector engine now.
- Do **not** split the existing MathBoard app into many packages now.
- Do **not** add a plugin system, event bus, macro recording, or scripting in v1.

The legacy radial palette should remain generic UI driven by tool definitions. Tool definitions declare their orbit, arcs, icon, labels, and command behavior.

Suggested standalone target later:

```text
MathBoardCore/Sources/ToolPalette/
```

or, if developed completely outside this repo first:

```text
ToolPalettePrototype/
```

No integration code should be added until the standalone component is approved.

---

## 11. Suggested model types

Names are provisional, but future AI should preserve the separation of concerns.

```swift
enum ToolID: String, Codable, Sendable {
    case selection
    case reserved
    case pen
    case marker
    case eraser
    case geometry
    case laser
    case equation
}

struct ToolPaletteState: Equatable, Sendable {
    var activeTool: ToolID
    var strokeColor: PaletteColor
    var fillColor: PaletteColor
    var strokeWidth: Double
    var opacity: Double
    var geometryType: GeometryType
    var polygonSides: Int
    var selectionTarget: SelectionTarget
    var selectionMode: SelectionMode
    var eraserMode: EraserMode
    var laserMode: LaserMode
    var textStyle: PaletteTextStyle
    var rotation: Double
    var isColorBloomOpen: Bool
}

protocol ToolDefinition {
    var id: ToolID { get }
    var iconSystemName: String { get }
    func configuration(for state: ToolPaletteState) -> ToolPaletteConfiguration
}

struct ToolPaletteConfiguration {
    var topOrbit: PaletteOrbitConfiguration
    var leftArc: PaletteArcConfiguration
    var rightArc: PaletteArcConfiguration
}
```

Use app-independent color/value types in the standalone module where practical. Do not bind directly to PencilKit types inside the palette renderer. PencilKit mapping should live in an integration adapter later.

---

## 12. Command output

The standalone palette should emit commands rather than directly mutating a drawing engine.

Suggested command shape:

```swift
enum ToolPaletteCommand: Equatable, Sendable {
    case selectTool(ToolID)
    case setStrokeColor(PaletteColor)
    case setFillColor(PaletteColor)
    case setStrokeWidth(Double)
    case setOpacity(Double)
    case setGeometryType(GeometryType)
    case setPolygonSides(Int)
    case setSelectionTarget(SelectionTarget)
    case setSelectionMode(SelectionMode)
    case setEraserMode(EraserMode)
    case setLaserMode(LaserMode)
    case undo
    case redo
    case copySelection
    case duplicateSelection
    case deleteSelection
    case extractSelectionAsImageSticker
    case sendSelectionToNextSlide
}
```

Future MathBoard integration can translate commands to:

- `PKCanvasView.tool`
- `PKInkingTool`
- `PKEraserTool`
- existing `CanvasEditCommand`
- future object-layer commands
- future selection commands
- future laser pointer state

---

## 13. Standalone v1 scope

Build first as a visual and interaction prototype.

Functional in standalone v1:

- Main eight-slot wheel.
- Center Hero Button.
- Active tool switching.
- Data-driven tool configuration.
- Top orbit renderer.
- Bottom left/right arc renderers.
- Pen width and opacity controls.
- Marker width and opacity controls.
- Eraser size and mode controls.
- Laser size and dot/trail mode controls.
- Basic color presets.
- Color Bloom visual behavior if time allows.
- Disabled placeholder states for Geometry, Selection, fx, and Reserved.
- Command emission to a mock debug panel.
- Mock canvas behind the palette so movement/fade behavior can be evaluated.

First implementation slice:

- `ToolPalette` package target.
- `ToolPalettePrototypeView` public host view.
- `RadialToolPaletteView` pen-first dial.
- `ToolPaletteState`, `ToolPaletteCommand`, data-driven configuration types, and pen/future-placeholder definitions.
- Deterministic layout helpers and tests for slot positions and arc value mapping.
- No PencilKit imports.

Not required in standalone v1:

- Real PencilKit integration.
- Real geometry drawing.
- Real selection.
- Real equation entry.
- Real object layer.
- Persistence.
- Plugin system.
- Event bus.
- Custom vector drawing engine.

---

## 14. Integration plan later

When the standalone palette is approved, integrate in a small controlled pass:

1. Add the palette target to `MathBoardCore/Package.swift`.
2. Make `Canvas` or `Presentation` depend on the palette only if necessary.
3. Hide Apple's visible `PKToolPicker` on iPad when custom palette mode is enabled.
4. Add an adapter that maps `ToolPaletteCommand` to PencilKit:
   - Pen/marker → `PKInkingTool`.
   - Eraser → `PKEraserTool`.
   - Color/width/opacity → active tool reconstruction.
   - Undo/redo → existing `CanvasEditCommand`.
5. Keep integration edits small and reversible.
6. Build and test iPad drawing, external display, save/load, undo/redo, and PDF export after integration.

The first integrated version should control existing PencilKit behavior only. Selection, object editing, geometry, and equation placement come later.

---

## 15. Relationship to future object layer

The second AI was correct that MathBoard eventually needs a unified object model:

- `StrokeObject`
- `ShapeObject`
- `TextObject`
- `ImageObject`
- `PDFObject`
- `EquationObject`
- `StickerObject`

That object layer should eventually support:

- Selection.
- Move/resize/rotate.
- Copy/duplicate/delete.
- Extract as image sticker.
- Graph snapshot-to-canvas.
- Movable PDF page objects.
- Shape tools.
- Equation objects.

However, the radial palette does not need this object layer for standalone v1. It only needs to reserve the commands and UI states so integration can grow naturally later.

---

## 16. Development order

Recommended sequence:

1. **Standalone pen-tool prototype.**
   Build the radial dial, hero button, top color orbit, bottom width/opacity arcs, and mock canvas using the supplied mockup's dark segmented visual language.
2. **Data-driven tool definitions.**
   Implement Pen, Marker, Eraser, Laser, Selection placeholder, Geometry placeholder, fx placeholder, Reserved placeholder as `ToolDefinition`s.
3. **Command emission.**
   Palette emits `ToolPaletteCommand` values to a mock command log.
4. **Interaction polish.**
   Tune touch targets, animation, fade behavior, disabled states, and responsiveness.
5. **Standalone preview/testing.**
   Add previews or a small host view for multiple dial sizes and tool states.
6. **Integration planning.**
   Only after user approval, write a small integration handoff similar to `Calculator_integration.md`.
7. **MathBoard integration.**
   Wire commands to PencilKit in the existing canvas.

---

## 17. Open questions

### Resolved (2026-06-29) — placement & visibility

**Collapse / expand floating model (locked in).**

- The palette is **floating and draggable**, not anchored to the Pencil contact
  point.
- Its **resting state is collapsed**: only the active tool shows, as a small
  center "hero" puck that the teacher can drag anywhere on the canvas. This is
  also the while-drawing state — it stays present but compact instead of
  covering content, which answers the earlier "remain visible vs. fade"
  question.
- The full radial dial **expands** when the user **taps the puck** or performs
  an **Apple Pencil squeeze**. Collapsing again (tap-away / select-a-tool /
  re-squeeze) is a detail to settle during build.
- **Build implications:** the collapse/expand floating model is now built in the
  module — see `CollapsibleToolPaletteView.swift` (`FloatingToolPaletteView`).
  It renders the collapsed puck (active tool only, drag-to-move, tap-to-expand),
  blooms out to the full dial, and collapses when the center hero is tapped. It
  exposes a plain `isExpanded` binding so the integration can drive expand/
  collapse. The Pencil-squeeze trigger is `UIPencilInteraction` (UIKit) and
  therefore still lives in the **integration layer** (Canvas/Presentation side),
  not in the dependency-free `ToolPalette` module — it just flips `isExpanded`.

### Still open

- What are the exact v1 color presets?
- Should marker be a true highlighter-style translucent ink or just a wider translucent pen?
- Should eraser v1 be PencilKit bitmap/vector eraser, stroke/object eraser, or both?
- Should undo/redo live in the radial palette, the existing toolbar, or both?
- How should this interact with Apple Pencil squeeze/barrel-roll if available on iPadOS 26?

---

## 18. Current status

**Standalone prototype built; Phase 2 app integration started.** A standalone radial palette prototype now exists
in the isolated `ToolPalette` target. It **renders and functions** on its own —
you can open `RadialToolPaletteView`/`ToolPalettePrototypeView` in Xcode previews
(or the prototype host window) and interact with it: switch tools, pick colors,
and drag the width/opacity sliders, with every action emitted to the mock
command log. It builds independently of the app.

It is **partially integrated into MathBoard** behind a default-OFF flag:
`Presentation` depends on `ToolPalette`, `ToolPaletteSettings.shared` controls
the toolbar flag, and `PresentingCanvasView` hosts `FloatingToolPaletteView`.
Pen, Marker, and Eraser commands now map through a Canvas-side adapter into
PencilKit (`PKInkingTool` / `PKEraserTool`). Laser, Geometry, Text, Widget, and
Selection remain UI-only until their canvas/object-layer models exist.

Still to work out:

- Real behavior for the non-Pen tools (Marker, Eraser, Laser, Geometry,
  Selection, Text/equation, Widget) beyond the initial PencilKit adapter:
  Marker and Eraser now control PencilKit, while Laser/Geometry/Selection/Text/
  Widget still need their own canvas/object-layer implementations.
- Color Bloom / expanded color picking, and fill vs. border for shape tools.
- Hardware verification for the initial PencilKit adapter: Pen color/width/
  opacity, Marker color/width/opacity, Eraser pixel/stroke mode and size, undo/
  redo, save/load, and external-display live ink.
- Final visual polish after hardware testing: drag hit regions, collapsed/expanded
  placement, slider touch targets, and any TV-display scaling issues.

**Integration:** the phased, reversible connect plan lives in
`ToolPalette_integration.md` (mirrors `Calculator_integration.md`). **Phase 1 is
applied** — `ToolPalette` is linked into `Presentation`, a default-OFF persisted
flag (`ToolPaletteSettings.shared`) gates `FloatingToolPaletteView`
overlay + a "Tool Palette" toolbar toggle in `PresentingCanvasView`; full app
builds clean. The floating center/expanded state is stored in `DisplayBroker` so
the external display can mirror it in full-canvas sharing. Commands are **not**
globally wired yet: Pen/Marker/Eraser are now translated to Canvas tool commands
and applied to PencilKit; Laser/Geometry/Selection/Text/Widget remain UI-only.
Next: hardware-verify this adapter, then decide whether to tune Pen/Marker/
Eraser or proceed to Laser.

Current decision:

- Calculator work is on hold.
- iPad pinch/pan performance work has been improved and should be kept stable.
- Radial palette should be the next major standalone component if the user chooses to proceed.
- The first step is to build a standalone pen-tool prototype without touching MathBoard integration code.

Current implementation:

- `MathBoardCore/Sources/ToolPalette/ToolPaletteModels.swift` — app-independent state, color, command, orbit, and arc configuration types.
- `MathBoardCore/Sources/ToolPalette/ToolPaletteDefinitions.swift` — data-driven tool definitions and reducer. Pen is active; other tools are placeholders.
- `MathBoardCore/Sources/ToolPalette/ToolPaletteLayout.swift` — deterministic radial layout and arc slider math.
- `MathBoardCore/Sources/ToolPalette/ToolPaletteTheme.swift` — dark navy/cyan visual tokens inspired by the supplied selection mockup.
- `MathBoardCore/Sources/ToolPalette/RadialToolPaletteView.swift` — standalone radial dial view with eight tool slots, center hero button, top color orbit, width arc, and opacity arc.
- `MathBoardCore/Sources/ToolPalette/CollapsibleToolPaletteView.swift` — floating collapsed puck + expanded radial dial wrapper, smooth drag, center drag/collapse target, and non-control outer-wheel drag regions.
- `MathBoardCore/Sources/ToolPalette/ToolPalettePrototypeView.swift` — mock canvas host with command log for standalone review.
- `MathBoardCore/Sources/Canvas/CanvasEditControls.swift` / `CanvasView.swift` / `PencilKitCanvas.swift` — canvas-native `CanvasToolCommand`, threaded through to the iOS PencilKit canvas. Pen and Marker map to `PKInkingTool`; Eraser maps to `PKEraserTool`.
- `MathBoardCore/Sources/Presentation/DisplayBroker.swift` / `PresentingCanvasView.swift` / `ExternalCanvasView.swift` — Phase 1 visual integration, Phase 2 Pen/Marker/Eraser adapter, and external-display sharing behavior. In full iPad sharing mode, the external display shows the calculator and radial palette; in Present Mode, the external display hides the radial palette but still shows the calculator.
- `MathBoardCore/Tests/ToolPaletteTests/` — focused Swift Testing coverage for layout and reducer logic.

Layout refinements since the first pass:

- **Three concentric rings.** Ring 1 (inner) is the active-tool hero; ring 2 (middle) is the eight-slot tool selector; ring 3 (outer) holds the active tool's options (colors across the top, sliders in the bottom quadrants). Ring 3 is fully driven by `ToolDefinition.configuration(for:)`, so it swaps with the selected tool.
- **Bottom-quadrant sliders.** The width slider is confined to screen 110°–160° (standard-math quadrant 3) and the opacity slider to 20°–70° (quadrant 4). Geometry is identical across every tool ring. Each slider's drag hit-area is an `AnnularSector` wedge, so the two sliders never capture taps meant for the rest of the dial.
- **Value direction.** Both sliders place the minimum at the outer end of the track and the maximum at the bottom-center end (nearest 6 o'clock), via `ToolPaletteArcMath.valueEndpoints(for:)`.
- **Data-driven slider end markers.** `PaletteSliderEndMarker` lets a slider declare a glyph for each end. The pen width slider shows a thin line (min) → thick line (max); the opacity slider shows a light circle (min) → dark circle (max). The previous center icon was removed; the numeric readout remains.
- **`#Preview` blocks** were added to `RadialToolPaletteView.swift` (per-tool + size sweep) and `ToolPalettePrototypeView.swift` (host). Preview only renders under a scheme that builds the `ToolPalette` target, since the module is intentionally not linked into the app.
- **Floating drag polish.** `FloatingToolPaletteView` uses global-coordinate drag
  translation and disables implicit animation for live center updates. The
  expanded dial can be dragged from the center and from quiet outer-wheel regions
  that avoid buttons, top orbit controls, and bottom sliders.
- **External display behavior.** Toolbar wording now offers `Present Mode` from
  full iPad sharing and `Mirror Mode` from Present Mode. Calculator remains
  visible on the external display in both modes. The radial palette appears on
  the external display only in full iPad sharing; it is hidden from Present Mode.
- **Live external-display stroke tuning.** The temporary vector overlay now
  publishes at a capped cadence, downsamples very dense in-progress strokes, and
  uses a non-linear TV-only width multiplier because committed Apple Pencil
  strokes do not scale visually like raw `PKInkingTool.width`: thin strokes use
  up to `0.85`, and the curve eases down to `0.45` for thick strokes. Pen/
  Marker/Eraser widths are clamped to PencilKit's valid width ranges before
  assigning `PKInkingTool` / `PKEraserTool`, so the live TV preview should better
  match the committed PencilKit stroke on pen-up.

Validation:

- Xcode app build: clean. Existing MathBoard app/canvas functionality remains unlinked from `ToolPalette`.
- SwiftPM standalone target build: `swift build --disable-sandbox --target ToolPalette` completes successfully.
- SwiftPM tests: `swift test --disable-sandbox --package-path MathBoardCore --filter ToolPaletteTests` passes 18 tests.
- Xcode app build: clean after the floating drag and external-display updates.

---

## 19. Session log

| Date | Summary |
|---|---|
| 2026-06-30 — Pen/Marker/Laser color state separated | **Fixed the shared color-swatch coupling between Pen, Marker, and Laser.** `ToolPaletteState` now stores separate `penColor`, `markerColor`, and `laserColor` values plus an `activeStrokeColor` helper. `ToolPaletteReducer.setStrokeColor` now updates only the currently active color-bearing tool instead of globally changing every tool that uses color swatches. The radial palette hero, custom color picker, selected swatch ring, collapsed puck, and PencilKit Pen/Marker adapter now read the per-tool colors. Added a regression test proving Pen, Marker, and Laser colors remain independent. Validation: Xcode build clean. Package-level filtered test was attempted with `swift test --disable-sandbox`, but the command hung during compile in this environment and was stopped. Hardware retest pending for swatch selection across Pen/Marker/Laser. |
| 2026-06-30 — pure-white palette icon/text pass | **Changed radial palette icon and lettering colors to pure white after hardware visual review.** `ToolPaletteTheme.label` and `ToolPaletteTheme.mutedLabel` now both use `Color.white`, so selected and unselected tool icons/labels no longer carry the previous blue-white / blue-gray tint. The cyan active highlight remains unchanged. Validation: Xcode build clean; user confirmed the visual change worked. |
| 2026-06-30 — Small/Medium palette size presets | **Added a persisted radial palette size setting without duplicating the palette view.** `ToolPaletteSettings` now stores `ToolPaletteSize` with `Small` as the current 360-point dial and `Medium` as a 432-point dial. `PresentingCanvasView` passes the selected `dialSize` and matching collapsed-puck size into `FloatingToolPaletteView`, and the external display mirrors that size proportionally inside the fitted shared-canvas frame. The existing Tool Palette toolbar control is now a menu with Show/Hide and a `Palette Size` picker. Validation: Xcode build clean. Hardware retest pending for Medium target feel and canvas obstruction. |
| 2026-06-29 — initial radial palette plan | **Created the radial palette status/design doc.** Captured the Notion radial UX, second-AI architecture review, and MathBoard-specific implementation decision: build the palette independently first, keep it data-driven, emit commands, control PencilKit later through an adapter, and do not replace the drawing engine or touch MathBoard integration code during standalone palette work. |
| 2026-06-29 — pen-tool implementation start | **Updated the plan from the supplied mockup.** The image establishes the dark navy segmented circular dial, cyan active accents, center hero button, top contextual orbit, and bottom arc-control language. Implementation begins with the Pen tool, not Selection: top orbit = color presets, bottom left = width, bottom right = opacity, remaining tool slots = placeholders. Work stays isolated in a new `ToolPalette` package target with no dependency from the existing app/canvas modules. |
| 2026-06-29 — standalone target added | **Added the isolated `ToolPalette` module.** Package manifest now exposes a standalone `ToolPalette` library product without adding it to the app dependency chain. Added pen-first model/config/reducer/layout/theme/view/prototype files plus focused package tests. App build remains clean, and `swift build --disable-sandbox --target ToolPalette` succeeds. `swift test` is blocked locally by command-line toolchain test-framework availability, not by palette source compilation. |
| 2026-06-29 — Phase 1 drag-perf fix (attempt 1) | **Addressed on-device drag jitter (finger) / trailing (Pencil) over the live canvas.** Switched the puck + center-grab drag to `.highPriorityGesture` so it beats the `PKCanvasView` scroll/draw recognizers, and moved the bloom spring off the drag path (`withAnimation` at expand/collapse instead of a container `.animation(value:)`). App builds clean. **Needs hardware retest.** If still laggy, fallback is a UIKit `UIPanGestureRecognizer` in the integration layer (see `ToolPalette_integration.md` Phase 1 follow-up). |
| 2026-06-29 — integration Phase 1 (flagged overlay) | **Connected the palette to the app behind a feature flag (full app builds clean).** `Package.swift`: `Presentation` now depends on `ToolPalette` (no pbxproj edit; transitively linked via `Documents`). New `ToolPaletteSettings.swift` (`@MainActor @Observable`, `isCustomPaletteEnabled` default OFF, persisted in `UserDefaults`). `PresentingCanvasView`: `import ToolPalette`, `paletteState`/`isPaletteExpanded` state, an `#if os(iOS)` flagged `FloatingToolPaletteView` overlay (empty areas don't capture touches; `onCommand: { _ in }` — Phase 2 wires it), and an `#if os(iOS)` "Tool Palette" toolbar toggle. Visual only — drawing path unchanged, Apple's `PKToolPicker` still visible. `BuildProject` clean (3.8s). **Needs hardware verify** (show/drag/bloom; ink hit-test under the puck/dial; no TV regressions). Next: Phase 2 command→PencilKit adapter. |
| 2026-06-29 — floating drag + external display polish | **Fixed on-device floating drag and clarified external-display behavior.** `FloatingToolPaletteView` now uses global-coordinate drag translation, disables implicit animation during live center updates, lowers the drag threshold, and exposes non-control outer-wheel drag regions so the expanded dial can move from empty wheel areas without stealing button/slider touches. Palette state, expansion, and center are shared through `DisplayBroker` so the external display can render the same visual palette position in full iPad sharing. Toolbar wording now offers `Present Mode` from full iPad sharing and `Mirror Mode` from Present Mode. External display shows the calculator in both modes, but hides the radial palette in Present Mode. Validation: Xcode build clean; `ToolPaletteTests` pass 18 tests via SwiftPM. |
| 2026-06-29 — Phase 2 Pen/Marker/Eraser adapter | **Started real PencilKit control from the radial palette.** Added Canvas-native `CanvasToolCommand` so `ToolPalette` stays PencilKit-free. `PresentingCanvasView` translates `ToolPaletteCommand` + current `ToolPaletteState` into Canvas commands only for Pen, Marker, and Eraser. `CanvasView` threads those commands into `PencilKitCanvas`, where Pen maps to `PKInkingTool(.pen, color, width)`, Marker maps to `PKInkingTool(.marker, color, width)`, and Eraser maps to `PKEraserTool(.bitmap/.vector, width)` for pixel/stroke modes. The system `PKToolPicker` is hidden while the custom palette flag is enabled and shown again when disabled. Laser, Geometry, Selection, Text, and Widget remain UI-only. Validation: live diagnostics clean, Xcode build clean, `ToolPaletteTests` pass 18 tests. Needs hardware verification on iPad for actual drawing behavior. |
| 2026-06-29 — live stroke performance + TV width match | **Reduced active-drawing lag and width pop on the external display.** User reported active iPad drawing lag while connected to the secondary display and a TV-only width mismatch: the temporary live vector stroke appeared too wide, then snapped to the narrower committed PencilKit stroke on pen-up. `PencilKitCanvas.Coordinator` now throttles live-stroke publishes to 30 fps, caps preview point density to 240 points, and removes the previous pressure multiplier from the TV live overlay. Pen/Marker/Eraser widths are clamped to PencilKit `validWidthRange` before assigning `PKInkingTool` / `PKEraserTool`. Validation: diagnostics clean, Xcode build clean, `ToolPaletteTests` pass 18 tests. Needs hardware retest for lag and width matching. |
| 2026-06-29 — TV live-stroke width calibration | **Scaled down the temporary external-display live stroke only.** User retest clarified that the committed PencilKit redraw on the secondary display matches the iPad exactly; only the in-progress live overlay was too thick, especially at larger radial-palette widths. Added `liveStrokeWidthPreviewScale = 0.45` in `PencilKitCanvas.Coordinator.liveLineWidth(on:)`. This does not change the actual `PKInkingTool` width, saved drawing, undo/redo, or committed external frame; it only calibrates the temporary TV overlay before PencilKit commits. Validation: diagnostics clean, Xcode build clean, `ToolPaletteTests` pass 18 tests. Needs hardware retest; tune the multiplier if still visibly off. |
| 2026-06-29 — non-linear TV live-stroke width curve | **Replaced the flat TV live-stroke multiplier with a width-based curve.** User retest showed the `0.45` multiplier improved medium/thick strokes but made the thinnest live stroke too thin before the committed redraw. `PencilKitCanvas.Coordinator.liveLineWidth(on:)` now computes a multiplier from the current `PKInkingTool` valid width range: thin strokes approach `0.85`, thick strokes ease down to `0.45` using a square-root curve. This still affects only the temporary external-display live overlay, not the iPad stroke, saved drawing, or committed TV frame. Validation: diagnostics clean, Xcode build clean, `ToolPaletteTests` pass 18 tests. Needs hardware retest across low/medium/high widths. |
| 2026-06-29 — integration handoff doc | **Wrote `ToolPalette_integration.md`** — the phased, reversible plan to connect the palette to the app, grounded in the real touch-points: link `ToolPalette` into the `Presentation` target (`Package.swift` line 30; no pbxproj edit needed), feature flag (default OFF), flagged `FloatingToolPaletteView` overlay + toolbar toggle in `PresentingCanvasView` (mirrors the Calculator overlay at lines 71–74 / toolbar 152–159), a Canvas-side `ToolPaletteCommand`→`PKInkingTool`/`PKEraserTool` adapter (driven like `editCommand`), Pencil **squeeze** via `UIPencilInteraction` flipping `isExpanded`, and hiding Apple's `PKToolPicker` (`PencilKitCanvas.installToolPicker`, line 614) only when the flag is on. Integrate **Pen/Marker/Eraser/Laser** first; Selection/Geometry/Text/Widget wait for the object layer. Doc-only — **no app code touched.** Next action = Phase 1. |
| 2026-06-29 — puck drag polish + prototype host | **Smoothed the drag and made the center grabbable while expanded.** Switched `FloatingToolPaletteView` drag from per-frame `@State` writes to `@GestureState` (committing `center` only on release) to fix jitter. The dial center is now a transparent grab area (sized to the hero) that **taps to collapse** and **press-and-drags to move** — so the palette can be repositioned while the menu is open, while a click-and-release still just closes it. Wired `ToolPalettePrototypeView` (the command-log host) to use `FloatingToolPaletteView` so collapse/expand + bloom are exercised alongside the command log. Diagnostics clean. |
| 2026-06-29 — collapse/expand floating puck | **Locked the placement/visibility design and built the collapse/expand model.** Decision: the palette is floating + draggable; its resting state is a small **puck** showing only the active tool (drag to move, also the while-drawing state); it **blooms outward** into the full dial on tap or Apple Pencil squeeze. Added `CollapsibleToolPaletteView.swift` with public `FloatingToolPaletteView` (collapsed puck ⇄ full dial, spring "bloom" scale+opacity transition, drag-to-move only while collapsed so it never fights the dial's slider/button gestures) and a `CollapsedToolPuck` that reuses the hero's domed look. `RadialToolPaletteView` gained an `onHeroTap` hook (tapping the dial center collapses) — kept `onCommand` first so existing trailing-closure call sites still bind correctly — and `GeometrySymbolView` was made module-internal for reuse. The squeeze trigger stays in the future integration layer via the exposed `isExpanded` binding. New `#Preview("Floating collapse / expand")`. Xcode diagnostics clean; `ToolPalette` target compiles (only the `#Preview` macro is unavailable to the CLI toolchain, as before). |
| 2026-06-29 — three-ring layout + slider polish | **Restructured the dial into three concentric rings** (hero / tool selector / tool-options) and added SwiftUI previews. **Confined the two bottom sliders to quadrants 3 and 4** (width 110°–160°, opacity 20°–70° in screen space) so their geometry is consistent across every tool, and **scoped each slider's drag gesture to its own arc wedge** instead of the full dial. **Reversed the slider value direction** so "more" sits nearest 6 o'clock (`ToolPaletteArcMath.valueEndpoints`). **Added data-driven slider end markers** (`PaletteSliderEndMarker`): pen width shows thin→thick lines, opacity shows light→dark circles; removed the redundant center icon. **Swapped the Laser and Future/Reserved tool slots.** Layout tests updated to the new angle/value mapping; `ToolPalette` target compiles cleanly (only the `#Preview` macro is unavailable to the CLI toolchain, as before). |
