# MathBoard Radial Tool Palette — Integration Handoff

> Copy-pasteable plan for connecting the standalone `ToolPalette` module to the
> MathBoard app, **slowly and reversibly**, mirroring how the Calculator was
> integrated (see `Calculator_integration.md` / the `Calculator_status.md`
> session log). Read `Radial_Palette_status.md` first for the design.
>
> **Status: PHASE 1 DONE** (2026-06-29). `ToolPalette` is linked into
> `Presentation` and a flagged, visual-only floating palette + toolbar toggle are
> wired into `PresentingCanvasView`. Full app builds clean. **Next: Phase 2**
> (command → PencilKit adapter). Phases 2–5 below are not yet applied.

---

## 0. Current state (what an incoming AI inherits)

- `ToolPalette` is a **standalone SwiftPM library target** in `MathBoardCore`
  (`Package.swift` line 41), a `.library` product (line 26), **not depended on
  by any app/canvas module**. It builds and previews in isolation.
- It is **dependency-free** (pure SwiftUI + Foundation; **no UIKit, no
  PencilKit**). Keep it that way — UIKit/PencilKit glue lives on the app side.
- What works in previews today: three-ring radial dial (Pen fully functional;
  Marker/Eraser/Laser/Geometry/Selection/Text/Widget are placeholder configs),
  floating **collapse/expand puck** that blooms outward, drag-to-move, and a
  command log host (`ToolPalettePrototypeView`).

### Public API the integration consumes

| Symbol | Role |
|---|---|
| `FloatingToolPaletteView(state:isExpanded:dialSize:collapsedSize:onCommand:)` | The thing you overlay on the canvas. Collapsed puck ⇄ expanded dial. |
| `RadialToolPaletteView(state:dialSize:onCommand:onHeroTap:)` | The dial alone (used by the floating wrapper; you normally won't embed this directly). |
| `ToolPaletteState` | `Equatable, Sendable` value type: `activeTool`, `strokeColor`, `strokeWidth`, `opacity`, `eraserMode`, `laserMode`, … |
| `ToolPaletteCommand` | `Equatable, Sendable` enum emitted via `onCommand` (e.g. `.selectTool`, `.setStrokeColor`, `.setStrokeWidth`, `.setOpacity`, `.setEraserMode`). |
| `isExpanded: Binding<Bool>` | Drives expand/collapse. The Apple Pencil **squeeze** trigger flips this. |

`ToolPaletteState` and `ToolPaletteCommand` live in
`MathBoardCore/Sources/ToolPalette/ToolPaletteModels.swift`.

---

## 1. Guardrails (do not violate)

- **Do not replace PencilKit.** v1 drives `PKCanvasView.tool` (PKInkingTool /
  PKEraserTool). No custom drawing engine.
- **Feature-flagged + reversible.** Every phase is behind a flag (default OFF)
  so the app behaves exactly as today until explicitly enabled. Each phase is a
  small, separately-revertable edit.
- **Keep `ToolPalette` dependency-free.** No PencilKit/UIKit imports inside the
  module. The command→PencilKit adapter lives in the **Canvas/Presentation**
  side.
- **Object-layer-dependent tools are deferred.** Selection, Geometry, Text,
  Widget need MathBoard's not-yet-built object layer (`Project_status.md` §6
  item 4). Integrate only **Pen, Marker, Eraser, Laser** now; leave the rest
  visible-but-inert.
- **NEVER edit `project.pbxproj` directly** (Xcode crashes if it's open). All
  linking here is via `Package.swift` (safe) — no pbxproj edit is needed because
  the app already links `Documents`, which transitively pulls `Presentation`.
- **Mac is unaffected.** This is an iPad/Pencil feature. Gate everything in
  `#if os(iOS)`; `MacCanvasPlaceholder` keeps its own toolbar.

---

## 2. Phased plan (slow + reversible)

Do these one at a time, building/testing between each. Phases 1–2 prove the
plumbing without changing how drawing works; only Phase 4 hides Apple's picker.

### Phase 1 — Link + render (visual only, no drawing change) ✅ DONE 2026-06-29
**Goal:** the floating palette appears over the canvas, drags, expands/collapses;
commands only log. Apple's `PKToolPicker` stays visible. Nothing about drawing
changes.

**What was applied:**
- `Package.swift` line 30 — `Presentation` now depends on `"ToolPalette"`.
- New `MathBoardCore/Sources/Presentation/ToolPaletteSettings.swift` —
  `@MainActor @Observable` flag `ToolPaletteSettings.shared.isCustomPaletteEnabled`
  (default `false`, persisted in `UserDefaults`).
- `PresentingCanvasView.swift` — `import ToolPalette`; `@State paletteState`,
  `@State isPaletteExpanded`; an `#if os(iOS)` flagged `FloatingToolPaletteView`
  overlay in the ZStack; and an `#if os(iOS)` "Tool Palette" toolbar toggle.
  `onCommand` is `{ _ in }` for now (Phase 2 wires it).
- Full app `BuildProject` succeeded; Xcode diagnostics clean.

**To try it:** run on iPad, open a lesson, tap the **paintpalette** toolbar
button to show the floating puck; drag it, tap to bloom open, pick tools/colors
(self-contained state). Ink still draws via Apple's picker; nothing is wired to
PencilKit yet. Hardware-verify the Pencil hit-test (ink should not draw under the
puck/dial).

**Original step list (for reference):**

1. `Package.swift` line 30 — add `ToolPalette` to `Presentation`'s deps:
   ```swift
   .target(name: "Presentation", dependencies: ["Canvas", "Calculator", "ToolPalette"]),
   ```
   (No pbxproj edit; transitively linked through `Documents`.)
2. New file `MathBoardCore/Sources/Presentation/ToolPaletteFeatureFlag.swift` —
   a tiny `@MainActor @Observable` (or `UserDefaults`-backed) flag, default
   `false`. Suggest `ToolPaletteSettings.shared.isCustomPaletteEnabled`.
3. `PresentingCanvasView.swift`:
   - `import ToolPalette`
   - Add `@State private var paletteState = ToolPaletteState()` and
     `@State private var isPaletteExpanded = false`.
   - In the `ZStack` (next to the `if calculator.isVisible` overlay, ~line 71),
     inside `#if os(iOS)`:
     ```swift
     if ToolPaletteSettings.shared.isCustomPaletteEnabled {
         FloatingToolPaletteView(
             state: $paletteState,
             isExpanded: $isPaletteExpanded,
             onCommand: { command in /* Phase 2 wires this */ }
         )
     }
     ```
   - Add a toolbar toggle (mirror the Calculator button at lines 152–159) to flip
     `ToolPaletteSettings.shared.isCustomPaletteEnabled` so you can turn it on/off
     on-device.

**Test:** palette floats, drags, blooms; ink still draws via Apple's picker; no
regressions with/without TV connected.

### Phase 2 — Command → PencilKit adapter (drawing now driven by the palette)
**Goal:** selecting Pen/Marker/Eraser and changing color/width/opacity actually
changes `PKCanvasView.tool`. Apple's picker still visible (both can coexist).

1. New file `MathBoardCore/Sources/Canvas/ToolPaletteCommandAdapter.swift`
   (Canvas module, iOS-only) — pure mapping from the palette's *intent* to a
   PencilKit tool. To avoid a Canvas→ToolPalette dependency, **do not import
   ToolPalette here**; instead define a small Canvas-side input struct
   (e.g. `CanvasToolRequest { kind, color, width, opacity, eraserMode }`) and
   translate `ToolPaletteCommand`→`CanvasToolRequest` in `PresentingCanvasView`.
2. Feed the request into the canvas the same way `editCommand` flows
   (`CanvasView.init` takes `editCommand: CanvasEditCommand?`,
   `CanvasView.swift` line 37): add a `toolRequest: CanvasToolRequest?`
   parameter threaded `CanvasView → PencilKitCanvasRepresentable →
   updateUIView`, applied to `canvas.tool`.
3. Mapping table:

   | Palette | PencilKit |
   |---|---|
   | Pen + color + width + opacity | `PKInkingTool(.pen, color: color.withOpacity, width: width)` |
   | Marker | `PKInkingTool(.marker, color:…, width:…)` (translucent) |
   | Eraser (`.pixel`) | `PKEraserTool(.bitmap)` |
   | Eraser (`.stroke`) | `PKEraserTool(.vector)` |
   | Laser | **not** a PKTool — overlay-only pointer; defer or render via the live-stroke overlay path |

   Existing `canvas.tool` read/write sites for reference:
   `PencilKitCanvas.swift` lines 838, 869, 885.

**Test:** pick Pen, change color/width/opacity → strokes reflect it. Eraser
erases. Marker is translucent. Undo/redo still work.

### Phase 3 — Pencil squeeze → expand
**Goal:** an Apple Pencil squeeze toggles `isPaletteExpanded`.

- New file `MathBoardCore/Sources/Presentation/PencilSqueezeView.swift` — a
  `UIViewRepresentable` wrapping a `UIView` with a `UIPencilInteraction`; its
  delegate `pencilInteraction(_:didReceiveSqueeze:)` calls a closure. Overlay it
  (size-zero, non-blocking) and have the closure flip `isPaletteExpanded`.
- This is the only reason any UIKit is needed; it stays out of the `ToolPalette`
  module (module just exposes the `isExpanded` binding).

**Test:** squeeze opens the dial; tap-center/tap-away collapses.

### Phase 4 — Hide Apple's `PKToolPicker` (only when the flag is ON)
**Goal:** the custom palette becomes the *only* visible tool UI.

- In `PencilKitCanvas.installToolPicker(on:)` (line 614) gate visibility on the
  flag: when the custom palette is enabled, `picker.setVisible(false, …)` (or
  skip install). Keep `canvas.becomeFirstResponder()`.
- Make sure the canvas still has an initial tool when the picker is hidden (set
  a default `PKInkingTool` so drawing works before the first palette command).

**Test:** with flag ON, Apple's picker is gone and the radial palette fully
controls ink. With flag OFF, behavior is exactly as today.

### Phase 5 — External display + persistence polish
- Decide if the palette should appear on the TV (`ExternalCanvasView`). Likely
  **no** (it's a teacher control, not content) — confirm with user.
- Persist `paletteState` (active tool/color/width) across sessions if desired,
  following `CalculatorState`'s `UserDefaults` pattern.

---

## 3. Verification checklist (run on physical iPad + Pencil)

- [ ] Flag OFF → app identical to today (Apple picker, drawing, undo/redo, TV).
- [ ] Flag ON, Phase 1 → palette floats/drags/blooms; ink unaffected.
- [ ] Phase 2 → Pen color/width/opacity, Marker translucency, Eraser modes all
      drive real strokes; undo/redo intact.
- [ ] Phase 3 → Pencil squeeze expands; tap collapses.
- [ ] Phase 4 → Apple picker hidden with flag ON; default tool draws before first
      command.
- [ ] Pencil hit-test: ink does **not** draw under the palette puck/dial; draws
      everywhere else (same concern the Calculator hit when integrated).
- [ ] TV mirror/present unaffected; pinch/pan performance unchanged.

---

## 4. Rollback

- Each phase is a separate, small diff. To fully back out: remove the
  `FloatingToolPaletteView` overlay + toolbar toggle from `PresentingCanvasView`,
  remove `"ToolPalette"` from the `Presentation` deps in `Package.swift`, delete
  the new adapter/flag/squeeze files, and restore `installToolPicker`. The
  `ToolPalette` module itself stays untouched and standalone.

---

## 5. Open questions to confirm with the user before/while integrating

- **Laser** has no PKTool — ship later via the live-stroke overlay, or omit from
  v1? (Recommend omit from the first integrated pass.)
- **Color presets:** exact v1 set (the module currently ships Graphite/Sky/Mint/
  Amber/Coral + palette presets).
- **Marker:** true translucent highlighter vs. wide translucent pen.
- **Where the flag lives / how it's toggled** in real use (debug setting vs. a
  real Settings toggle vs. always-on once stable).

---

## 6. Current pickup point

**Phase 1 is applied and building.** Pending: **hardware-verify Phase 1** on a
physical iPad (palette shows/drags/blooms; ink hit-test correct under the
puck/dial; no regressions with/without TV).

**Phase 1 follow-up — drag performance (in progress).** On device the puck drag
was jittery (finger) and trailed (Pencil) over the live `PKCanvasView`.
- *Attempt 1 (did NOT fix):* `.highPriorityGesture` + moved the bloom spring off
  the drag path.
- *Attempt 2 (did NOT fix):* single combined gesture with `@GestureState` +
  `minimumDistance: 0`.
- *Attempt 3 (awaiting hardware retest):* replaced the gesture with an **exact
  copy of `CalculatorView`'s drag** (which slides smoothly over the same canvas):
  commit `center` **live in `.onChanged`** using a captured `dragStartCenter`
  `@State`, `DragGesture(minimumDistance: 1, coordinateSpace: .local)`, plain
  `.gesture` (no `@GestureState`, no `.highPriorityGesture`); tap = "never moved
  past threshold." See `CalculatorView.swift` `dragGesture` for the reference.

**If attempt 2 still lags on hardware, escalate:** host the drag in a UIKit
`UIPanGestureRecognizer`
(integration layer, `#if os(iOS)`), which slots into PencilKit's recognizer
system — e.g. `require(toFail:)` against / take precedence over the canvas pan, or
`cancelsTouchesInView`. The `ToolPalette` module would then expose a position
binding the host drives, keeping the module UIKit-free.

**Next action: Phase 2** — the `ToolPaletteCommand` → PencilKit adapter. Replace
the `onCommand: { _ in }` in `PresentingCanvasView` with a translation to a
Canvas-side `CanvasToolRequest`, thread it into `CanvasView` like `editCommand`,
and apply it to `canvas.tool` (`PencilKitCanvas` lines 838/869/885). Start with
Pen color/width/opacity. See the §2 Phase 2 mapping table.
