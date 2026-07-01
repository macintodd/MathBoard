# MathBoard Calculator — Status

> Living design + progress doc for the in-app calculator/graphing tool. Mirrors the structure of `Project_status.md`. Updated at the end of every session.
>
> **Reading instruction (Claude):** Read this document top-to-bottom at the start of any working session that follows a break of **one hour or more**, before writing any calculator code. The locked-in design decisions in section 2 and the deferral list in section 6 are the source of truth — do not reopen them without explicit user direction.

**Last updated:** 2026-07-01 — Git backup protocol documented. Calculator remains at v1 shipped / v2 TI-84 keypad / v3 graphing status from 2026-06-28.

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

## 1. One-paragraph summary

A scientific + graphing calculator embedded in MathBoard as a draggable floating tool palette. Opens on a tap from a toolbar button, persists across slide changes within a lesson, and follows the same Mirror/Present TV-output rules as the rest of the canvas (Mirror shows it wherever it sits on the iPad screen; Present shows it only where it intersects the 16:9 viewfinder). Two modes — **Graph** (primary, Desmos-style) and **Compute** (scientific) — toggled by a single button on the calculator. State (mode, angle units, last function entered, last window, last position) persists in `UserDefaults` across lesson and app sessions; the calculator itself is closed at every fresh lesson open. Built as an **isolated `Calculator` library target** inside `MathBoardCore` — does not depend on any other MathBoard module and is not depended on by any other module. Integrates into the rest of the app via overlay + broker glue the user adds when ready.

---

## 2. Locked-in design decisions

From the design conversation, locked in:

| Decision | Value |
|---|---|
| Primary mode at first ever open | Graph |
| Mode persistence | Yes — remember last-used mode across sessions |
| Trig units at first ever open | Degrees |
| Trig units persistence | Yes — remember last-used across sessions |
| Equation entry | **Both** — button keypad + editable text field |
| Implicit multiplication | **Accepted** — `2x`, `2sin(x)`, `2π`, `(x+1)(x-1)` all parse as multiplication |
| Calculator size | 360 × 540 points (fixed for v1, resizable later) |
| Initial position on first ever open | Center of iPad viewport |
| Position persistence | Yes — last drag position remembered across sessions |
| Visibility at lesson open | Closed |
| Pencil hit-test | Solid — calculator absorbs all touches on its area; ink works elsewhere |
| TV mirroring | Calculator is rendered both on iPad and on TV via a shared broker; appears in same relative viewport position; Present mode crops as it does for everything else |
| Snapshot-to-canvas | UI button present but **disabled / placeholder**. Wires up to the image-object layer (not yet built) at a later date |
| State storage | `UserDefaults` for UI preferences and last-used state |
| Per-lesson / per-slide state | None — calculator state is global to the app, not stored in `.mathboard` packages |
| Pencil-only or finger | Both work on the canvas; both work on calculator buttons |
| File touching policy | Calculator built in **entirely new files** in `MathBoardCore/Sources/Calculator/`. The only existing file touched is `Package.swift` to register the new target. No other MathBoard file changes until the user is ready to integrate |

---

## 3. Architecture (modular, future-proofed)

### File layout

```
MathBoardCore/Sources/Calculator/
  CalculatorAngleMode.swift     ← degrees / radians enum
  CalculatorError.swift         ← typed errors (parse + eval)
  CalculatorToken.swift         ← lexer token enum
  CalculatorTokenizer.swift     ← String → [CalculatorToken]
  CalculatorExpression.swift    ← AST (indirect enum)
  CalculatorParser.swift        ← [Token] → Expression
  CalculatorEvaluator.swift     ← Expression × variables → Double
  CalculatorEngine.swift        ← public façade composing tokenizer + parser + evaluator
  CalculatorState.swift         ← @Observable mode/angle/expression/window/position with UserDefaults persistence
  CalculatorView.swift          ← main SwiftUI panel (palette body)
  CalculatorKeyGrid.swift       ← button grid + key model
  CalculatorDisplay.swift       ← entry text field + result display
  CalculatorGraphView.swift     ← graph rendering (axes, gridlines, curve)
  CalculatorGraphWindow.swift   ← xmin/xmax/ymin/ymax + pan/zoom math
  CalculatorTVOverlay.swift     ← TV-side view (same calculator, no input)
```

### Dependency rules

- `Calculator` target depends on **nothing** from other MathBoard modules.
- No other module depends on `Calculator`.
- Calculator is unaware of `DisplayBroker`, `SlideStore`, `PKCanvasView`, etc.
- Integration glue (toolbar button to open, overlay onto `PresentingCanvasView`, overlay onto `ExternalCanvasView`) is **not** in this module — it's the integration step the user wires up later.

### Math engine pipeline

```
String → Tokenizer → [Token] → Parser → Expression (AST) → Evaluator → Double
                                              ↑
                                              └── compile once, evaluate many times for graphing
```

- Pure Swift, `Sendable`, no UI/imports beyond Foundation.
- Implicit multiplication handled in the parser (after a value/closing-paren/identifier, if the next token can start a Power, multiply).
- Functions: `sin/cos/tan/csc/sec/cot`, inverse, hyperbolic, `log` (1 or 2 args), `ln`, `log2`, `exp`, `sqrt`, `cbrt`, `abs`, `floor`, `ceil`, `round`, `min`, `max`, `mod`.
- Constants: `pi` (or `π`), `e`.
- Postfix factorial: `n!`.
- Errors: typed `CalculatorError` with human-readable `errorDescription`.

---

## 4. What is built

*(Updated as code lands.)*

- Living design doc (this file) and locked-in decisions.
- **`Calculator` library target** registered in `MathBoardCore/Package.swift`. No dependencies, no library product — sits in the package so it compiles in isolation. Removing it later is a one-line revert.
- **Math engine** — pure Swift, `Sendable`, no UI imports. Eight files in `MathBoardCore/Sources/Calculator/`:
  - `CalculatorAngleMode.swift` — `degrees` / `radians` enum with `DEG` / `RAD` display labels.
  - `CalculatorError.swift` — typed errors covering tokenizer / parser / evaluator failures, each with a human-readable `errorDescription` suitable for inline display.
  - `CalculatorToken.swift` — lexer token enum + `debugDescription`.
  - `CalculatorExpression.swift` — AST (`number`, `identifier`, `unary`, `binary`, `factorial`, `function`) plus `CalculatorBinaryOp` / `CalculatorUnaryOp`.
  - `CalculatorTokenizer.swift` — decimal numbers (incl. scientific notation), letter-and-digit identifiers, ASCII + Unicode operator synonyms (`× · ⋅ ÷ −`), `[` / `]` as parentheses, `π` → identifier `pi`.
  - `CalculatorParser.swift` — recursive-descent parser. Precedence (low → high): `+ -` < `* /` and **implicit multiplication** < `^` (right-associative) < unary +/- < postfix `!` < primary. Function calls are identifier-followed-by-`(`. Implicit multiplication is detected when a primary-starter (`number`, `identifier`, `(`) immediately follows a value — handles `2x`, `2sin(x)`, `2π`, `(x+1)(x-1)`.
  - `CalculatorEvaluator.swift` — recursive AST walker. Constants: `pi`, `e`. Trig: `sin/cos/tan/csc/sec/cot` + inverse + hyperbolic + inverse hyperbolic, all degree/radian-aware. Logs: `log` (base-10 with 1 arg, arbitrary base with 2 args), `ln`, `log2`. Powers/roots: `sqrt` (`√`), `cbrt`, `^`, `exp`. Misc: `abs`, `floor`, `ceil` (`ceiling`), `round`, `sign`, `min`, `max`, `mod`. Factorial via postfix `!` with negative / non-integer / overflow guards. Domain errors raised for `csc/sec/cot` at zeros, inverse trig outside `[-1, 1]`, `acosh` below 1, `atanh` at ±1, `ln/log/sqrt` of non-positive values.
  - `CalculatorEngine.swift` — public façade with `compile(_:)` + `evaluate(compiled:)` (for graph loops) and `evaluate(_:)` (compile + evaluate in one call, for compute mode).
- Build verifies clean — engine compiles standalone in the package without touching any other module.
- **`CalculatorTests` test target** at `MathBoardCore/Tests/CalculatorTests/`. **66 XCTest cases total, all passing.**
  - `CalculatorEngineTests.swift` — 53 cases in 9 suites (arithmetic, power & unary minus, implicit multiplication, trig modes, logs & exponentials, misc functions, factorial, constants & variables, error paths). Bugs caught and fixed during the first test run: `√` (sqrt symbol) was missing from the tokenizer despite the spec; added it. Round-test expectations corrected — Swift's default `.rounded()` is round-half-away-from-zero (matches calculator convention `round(2.5) = 3`), not banker's rounding.
  - `CalculatorStateTests.swift` — 13 cases covering first-launch defaults, mode/angle/position/expression/window round-trips across separate instances, the `GraphWindow` default (±10) and `isValid` checks, `position == nil` clear path, the same-value no-op write guard, and the per-session "visibility never persists" rule. Each test uses an isolated `UserDefaults` suite torn down in `tearDown`.
- **TV overlay** — `CalculatorTVOverlay.swift` (read-only external-display view) + `CalculatorGraphRenderer.swift` (shared plot drawing) + `CalculatorTVLayoutTests.swift` (5 tests).
  - `CalculatorGraphRenderer` — extracted the gridline/axis/label/curve `Canvas` drawing out of `CalculatorGraphView` so the iPad graph view and the TV overlay render identically. `CalculatorGraphView` now calls it (its ~90 lines of duplicated draw code were removed).
  - `CalculatorTVOverlay(state:referenceSize:)` — **public**, read-only. Observes the same `CalculatorState` the iPad palette mutates; draws an identical card (graph plot via the shared renderer, or a re-evaluated compute display) at the matching relative position, scaled to the TV bounds, `allowsHitTesting(false)`. Only renders when `state.isVisible`.
  - `CalculatorTVLayout.placement(position:paletteSize:referenceSize:tvSize:)` — pure mapping: reproduces the palette's fractional center in the TV bounds and scales by the TV-to-reference width ratio (canvas mirror preserves aspect, so width and height ratios match); nil position or zero reference falls back to the TV center. Tested for nil-center, fraction-preserving corner, width-ratio scale, zero-reference fallback, and identity.
  - **Intentional iPad/TV divergence:** the iPad compute view shows a result only after "=", but the TV has no key events to mirror, so the overlay **re-evaluates `computeExpression` live** from shared state. Acceptable for v1 (students see it compute); recorded here and in the source.
- **Graph-mode UI** — `CalculatorGraphGeometry.swift` (pure math) + `CalculatorGraphView.swift` (SwiftUI plot, now delegating drawing to `CalculatorGraphRenderer`) + `CalculatorGraphGeometryTests.swift` (18 tests). Wired into `CalculatorView`'s graph branch (placeholder removed).
  - `CalculatorGraphGeometry` — SwiftUI-free: `viewPoint(forGraph:)` / `graphPoint(forView:)` transforms (y flips between math-up and view-down), `pan(window:byViewTranslation:size:)` (drag-right reveals lower x, drag-down reveals higher y, span preserved), `zoom(window:magnification:aroundViewPoint:size:)` (focal graph point stays fixed; spans clamped to `[minimumSpan 1e-6, maximumSpan 1e9]`), `niceStep(range:targetCount:)` (1/2/5 × 10ⁿ gridline steps), `ticks(min:max:step:)` (first-multiple-onward, guards against absurd counts), and `sample(window:count:eval:)` returning `[Sample]` where `y == nil` marks undefined/non-finite (pen-lift) columns.
  - `CalculatorGraphView` — `@Bindable CalculatorState`. "y =" monospaced editor (DEG/RAD chip toggles angle mode), a `Canvas`-drawn plot (minor gridlines, bolder x/y axes when in view, small tick labels, blue curve), drag-to-pan + `MagnifyGesture` zoom-around-focal, and a zoom-out/zoom-in/Reset control row. Compiles the expression once via `engine.compile` on appear and on expression change (`@State compiled`/`errorText`); samples per-frame across the window so pan/zoom stay live. Breaks the curve at undefined samples and at likely asymptotes (jump > 3× window height with a sign change). Invalid expressions show a red banner instead of a curve.
- **Draggable palette frame** — `CalculatorView.swift` (public entry point) + `CalculatorPaletteLayout` (pure clamp math) + `CalculatorPaletteLayoutTests.swift` (7 tests). Graph branch now hosts `CalculatorGraphView`.
  - `CalculatorView(state:)` renders a fixed **360 × 540** card: title bar (segmented Graph/Compute `Picker` bound to `state.mode`, a **disabled** snapshot button with "coming with image objects" help text, and a close button that sets `state.isVisible = false`) over a body that switches between `CalculatorComputeView` and a graph-mode placeholder (until the graph view lands). Positioned via `.position()` at the palette **center**; `GeometryReader` supplies the container size. A title-bar-only `DragGesture` writes the clamped center into `state.position` (so the keypad below still receives taps). The whole card uses `.contentShape(RoundedRectangle)` for solid hit-testing per the locked-in design. Default placement when `state.position == nil` is the container center.
  - `CalculatorPaletteLayout.clamp(center:paletteSize:in:)` keeps the card fully on-screen; if the container is smaller than the palette on an axis it pins to that axis's midpoint. Tests cover inside-unchanged, all four edges, the corner, and the container-smaller-than-palette case.
- **Compute-mode UI** — three files (the SwiftUI view compiles under Xcode's toolchain; the pure-logic pieces are unit-tested):
  - `CalculatorKey.swift` — pure, SwiftUI-free model. `CalculatorKeyAction` (`insert`/`evaluate`/`clear`/`deleteBackward`/`toggleAngleMode`), `CalculatorKeyStyle` (digit/operator/function/action/modifier presentation hint), `CalculatorKey` (id/label/action/style + convenience constructors). `CalculatorKeypadLayout.compute` is the default scientific keypad (function strip: sin/cos/tan/ln/log, then xⁿ/√/π/e/!, parens/C/⌫/÷, digit+operator grid, DEG/RAD toggle, and `=`). `CalculatorExpressionReducer.reduce(expression:action:)` applies a key to the expression text (append / drop-last / clear; evaluate + toggle leave text unchanged). `CalculatorResultFormatter.string(for:)` formats a `Double` — integers without trailing `.0`, fractional values trimmed, scientific notation for very large/small magnitudes, `∞`/`−∞`/`NaN` labels, all using the unicode minus `−`.
  - `CalculatorComputeView.swift` — SwiftUI compute body. `@Bindable` on `CalculatorState`. Editable expression `TextField` (1–3 lines, monospaced, no autocaps/autocorrect, ascii keyboard on iOS) + a result line that turns red on error, above a keypad built from `CalculatorKeypadLayout.compute`. Tapping a key routes through the reducer or runs an action; `=` (or field submit) evaluates via `CalculatorEngine` with the current angle mode; the DEG/RAD key flips `state.angleMode` and re-evaluates. Owns only ephemeral result/error `@State`; the durable expression + angle mode live in `CalculatorState`.
  - `CalculatorKeyTests.swift` — 18 cases: reducer (insert/append/backspace/clear/empty-safe/evaluate-and-toggle-no-op), formatter (integers, zero, fractions, non-finite, scientific thresholds, unicode minus), keypad layout (non-empty rows, digits 0–9 present, core actions present, unique ids, function keys insert call syntax).
- **`CalculatorState.swift`** — `@MainActor @Observable` state container. Persisted via `UserDefaults` (keys namespaced `calculator.*`, each written in its property's `didSet`): `mode` (default `.graph`), `angleMode` (default `.degrees`), `position: CGPoint?` (nil = never moved, view falls back to center), `computeExpression`, `graphExpression`, and a `GraphWindow` (Codable, default ±10 each axis, with `isValid` + `width`/`height`). `isVisible` is deliberately **not** persisted — resets to closed every session. `init(store:)` takes an injectable `UserDefaults` for test isolation; `CalculatorState.shared` is the app-level instance. Also defines `CalculatorMode` (`.graph`/`.compute` with `displayName` + `toggled`) and `GraphWindow`.

---

## 5. What is next

1. ~~**Engine** — tokenizer, parser, evaluator, public engine façade. Pure Swift, no UI.~~ **Done — 2026-06-25.**
2. ~~**Engine tests** — XCTest pure-logic coverage.~~ **Done — 2026-06-26. 53 tests passing.**
3. ~~**State + persistence** — `CalculatorState` `@Observable`, UserDefaults round-trip.~~ **Done — 2026-06-26. 13 tests passing.**
4. ~~**Compute-mode UI** — display, button grid, expression entry, evaluation.~~ **Done — 2026-06-26. 18 new tests; 84 total passing.** (History strip deferred — not built in v1; revisit if useful.)
5. ~~**Draggable palette frame** — title bar, mode toggle, disabled snapshot button, close button, drag-to-move.~~ **Done — 2026-06-26. 7 new tests; 91 total passing.**
6. ~~**Graph mode UI** — `y = f(x)` editor, plot (axes/gridlines/labels), zoom + pan, window controls.~~ **Done — 2026-06-26. 18 new tests; 109 total passing.** (Single function for v1; multiple curves + sliders are growth items.)
7. ~~**TV overlay view** — read-only, same `CalculatorState`, matching relative position.~~ **Done — 2026-06-26. 5 new tests; 114 total passing.**
8. ~~**Integration handoff doc** — exact glue for `PresentingCanvasView` / `ExternalCanvasView` + toolbar button.~~ **Done — 2026-06-26. See `Calculator_integration.md`.**

**v1 module is complete and SHIPPED (integrated + hardware-verified 2026-06-27).**

### v2 — TI-84-style mature keypad (BUILT 2026-06-27; see §9 for spec)
Goal: the compute keypad resembles a **TI-84 Plus CE** so the teacher can demonstrate the exact keys students press. Status:
1. ✅ **Engine `ans`** — `CalculatorState.lastAnswer` (ephemeral); `evaluate` injects `ans` variable and stores the result. Engine already supported variables.
2. ✅ **`2nd` modifier** — `CalculatorKey` gained `secondLabel`/`secondAction`/`hasSecond`; new `.toggleSecond` action. Compute view tracks `isSecondActive`, renders secondary labels (indigo tint), arms the 2nd key (accent tint), and auto-resets after one shifted press (TI behavior).
3. ✅ **TI-84-style keypad** — `2nd`, `DEG/RAD`, `ans`, `C`, `⌫`; `sin/cos/tan` (+2nd `sin⁻¹/cos⁻¹/tan⁻¹`), `(`, `)`; `x²`, `xⁿ`, `√`, `log` (+2nd `10ˣ`), `ln` (+2nd `eˣ`); `π`, `e`, `EE`, `,`, `!`; digit/operator grid; `(−)` negation; `=`.
4. ✅ **Tests** — +9 (2nd-secondaries, ans injection, constants/power keys present, hasSecond). 123/123 passing.
5. ⏳ **TV mirror** — inherits the new keypad automatically (TV renders the real compute view). `isSecondActive` is local `@State` in the compute view, so the **2nd-armed highlight may NOT mirror to the TV** (the TV's compute view has its own `@State`). Verify on hardware; if the teacher needs the armed-state to show on TV, lift `isSecondActive` into `CalculatorState`.
6. ⏳ **Keypad fit** — went from 7 to 8 rows; key minHeight reduced 40→34 and display lineLimit 3→2 to fit 360×540. **Verify on hardware**; if cramped, grow the palette height or shrink keys further.

### v2 — deferred to a later pass (still wanted, bigger)
- **`STO→` / `RCL` + variables A–Z** — store/recall named values.
- **Complex numbers / `i`** — beyond precalc core.

### v3 — Desmos-style graphing
Reference: Desmos compact-mode screenshot (graph on top, numbered equation list with color swatches + delete X + `+` add, math keypad at bottom). Status:
1. ✅ **Pinch-zoom bug FIX (2026-06-27)** — root cause was `CalculatorGraphView.zoomGesture` multiplying `MagnifyGesture.value.startLocation` (already in points) by the view size → enormous focal point flung the window off-screen → graph vanished. Now passes `startLocation` directly.
2. ✅ **Multiple equations (2026-06-27)** — `CalculatorState.graphExpression: String` replaced by `graphEquations: [GraphEquation]` (id/expression/colorIndex/isEnabled), persisted, with migration from the legacy single-expression key. Added `GraphEquation` + `GraphPalette` (6 colors). Equation-list UI: numbered colored rows, editable fields, delete X, `+` Add.
3. ✅ **Family-specific entry keypad (2026-06-28)** — `GraphFunctionFamily` (General/Linear/Quadratic/Polynomial/Trig/Exp·Log), persisted as `graphKeypadFamily`. `GraphKeypadLayout.keys(for:)` returns family-specific function rows over a shared numeric/operator/`x` base. Linear shows no powers; Quadratic adds `x²`/`√`; Polynomial adds `x³`/`^`/`∛`; Trig adds `sin/cos/tan/π`; Exp·Log adds `eˣ/ln/10ˣ/log`; General has trig+log+√+x². `CalculatorGraphView` rebuilt: **Topic dropdown**, tap-to-select equation rows (keypad-only entry, no system keyboard), togglable keypad, **DEG/RAD only shown for Trig** (`family.showsAngleToggle`), a **photo button** (present; calls optional `onSnapshot`, disabled until wired), and the existing pan/zoom. Compute/Graph toggle remains in the palette title bar. No `=`; `−` doubles as unary negation. Inequalities (`< ≤ > ≥`) NOT added — need parser support; belong to the 1-Variable mode (below).
4. ✅ **Renderer multi-curve (2026-06-27)** — `CalculatorGraphRenderer.draw` now takes `equations: [GraphEquation]`, compiles each enabled non-empty one, strokes in its palette color. Used by both the interactive graph view and the TV overlay.
5. ✅ **Tests (2026-06-27)** — `GraphEquation` round-trip, add/remove (never-empty), legacy migration, palette index wrap. 129/129 passing.

### v3 — 1 Variable REDESIGN (IMPLEMENTED 2026-06-28 — verify on hardware)
Built per the spec below. `oneVariableBody` in `CalculatorGraphView`: one number-line window (pan/zoom) showing each active inequality as a colored layer; cell 1 (field + right-end `connectiveMenu` showing `–`/`and`/`or`); cell 2 appears when a connective is chosen (field + `solutionMenu` `–`/`=`); the combined solution number line appears when cell 2's `=` is chosen. State: `oneVarConnective` + `oneVarShowSolution` (persisted). Keypad row1 `x = < >`, row2 `and or ≤ ≥`, then number pad. **Verify each interaction on device.**

Original spec (max **two** inequalities):
- **One number-line graph window** at top, **zoomable + panable** (adjusts the x-range).
- Below it, **equation cell 1**: a text field with a **pull-down menu at its right end** showing **"−"** by default. Menu options: `−`, `and`, `or`.
  - Entering an equation (e.g. `x ≥ 3`) graphs its x-values on the number line.
  - Choosing **and**/**or** reveals **equation cell 2** below, which has its OWN right-end pull-down showing **"−"** (options `−`, `=`).
  - Choosing **=** on cell 2's menu makes a **3rd graph** (number line) appear showing the combined solution (intersection for *and*, union for *or*).
- **Keypad arrangement:** inequalities in a **2×2 block** (`< >` / `≤ ≥`); put **and**/**or** directly under **x** and **=**. So: row1 `x = < >`, row2 `and or ≤ ≥`, then the number pad.
- State: `oneVarConnective` (none/and/or, on cell 1) + `oneVarShowSolution` (cell 2's `=`), both persisted.

### v3 — OTHER NEXT PICKUP POINTS
1. ✅ **"1 Variable" topic — number line + solver (DONE 2026-06-28).** Engine gained `|…|` abs-bar parsing (tokenizer `.bar` + parser with a `barDepth` counter so `2|x|` and `|x-3|` both parse). `CalculatorEquationSolver` (pure, tested): splits on `= < ≤ > ≥` (unicode + ascii; no operator ⇒ `expr = 0`), builds `g(x)=lhs−rhs`, finds roots by sign-change bisection + near-zero sampling (equality → discrete; inequality → midpoint-tested merged intervals; `.all`/`.none`). `CalculatorSolutionFormatter` renders "x = 1, 5" / "x ≤ −2  or  x ≥ 2". `CalculatorNumberLineView` draws axis/ticks + filled dots (equality) / shaded segments with open·closed endpoints (inequality). `.oneVariable` family + bespoke keypad (`x ( ) | < ≤ > ≥`, digits, ops, wide `=`). `CalculatorGraphView` branches to the number line + solution text when the topic is 1 Variable. **The `|x−3| = 2 → x = 1, 5` screenshot example works.** *(Cursor arrows / mid-string editing NOT done — append/backspace only; see item 3.)*
2. **Photo button wiring.** The graph view has a `camera` button calling optional `onSnapshot` (disabled until wired). Needs MathBoard's **image-object layer** (not built). When it exists: render the plot/number-line via `ImageRenderer` to an image and hand it to the canvas as a movable object.
3. **Cursor / mid-string editing.** Keypad entry appends/backspaces at the end only. The screenshot has ◀ ▶ cursor keys — optional polish: track a caret position per equation for insert/delete anywhere.
4. **1-Variable polish (later):** tangent/double roots (e.g. `(x−2)^2=0`) can be missed by pure sign-change scanning — add local-minimum detection; systems of 1-var relations (intersection of multiple rows) currently solve only the selected row.

**v3 deferred (Desmos has, we don't need yet):** inequality shading on 2D graph, sliders, tables, regressions, polar/parametric, points/labels.

---

## 6. Deferred / open

- **Snapshot-to-canvas button.** Stub now; full implementation depends on the image-object layer (which is in MathBoard's own roadmap).
- **Multiple simultaneous functions in graph mode.** v1 supports one `y = f(x)` at a time.
- **Parameter sliders** (`y = ax² + bx + c` with sliders for a, b, c). Growth item.
- **Polar / parametric graphing.** Growth item.
- **Statistical regressions.** Growth item.
- **Trace mode / function intersection / zero finding.** Growth item.
- **Calculator resizing (keypad + screen).** Fixed 360×540 for now. **Requested future feature** (inspired by Calculate84): let the teacher resize the palette and independently resize the display/keypad split, so the calculator can be made large for the class or compact to leave canvas room. Needs: a resize handle, min/max clamps, the size persisted in `CalculatorState`, and the TV overlay scaling to match. Until this lands, the keypad is capped at what fits 360×540 (currently 8 rows).
- **TI menu / variable keys.** `MATH`, `APPS`, `VARS`, `STAT`, `MODE` (menus), `ALPHA` + letter variables, and `STO→`/`RCL` (variable store) are on the TI-84 but need menu and/or variable-store systems. Deferred — not added as dead keys.
- **Complex numbers / `i`.** Beyond precalc core. Deferred.

---

## 7. Open questions

*(Empty for now — all locked-in design questions are answered in section 2.)*

---

## 9. v2 keypad spec (TI-84 Plus CE reference)

Reference: user supplied a TI-84 Plus CE photo. Students use TI-84s, so demonstrating on a familiar layout matters. We mirror the *useful* TI behaviors, not every niche key.

**`2nd` modifier:** a toggle key. While active, keys with a secondary function insert/do their secondary instead of primary, and `2nd` auto-deactivates after that one key (matches TI). Secondary pairs:
- `sin` → `sin⁻¹` (`asin(`), `cos` → `cos⁻¹` (`acos(`), `tan` → `tan⁻¹` (`atan(`)
- `log` → `10ˣ` (`10^(`), `ln` → `eˣ` (`e^(`)
- `x²` → `x⁻¹`? (inserts `^-1`) — optional
- `,` → `EE` (`e` scientific notation) — or give EE its own key

**Dedicated keys (no 2nd needed):** `π`, `e`, `√` (`sqrt(`), `^`, `x²` (`^2`), `(`, `)`, `(−)` negation (`-`), `ans`, `EE`.

**`ans`:** engine evaluates with variable `ans` = last numeric result. `CalculatorState.lastAnswer: Double?` (ephemeral). Inserting `ans` references it; evaluating with no prior answer treats `ans` as undefined (error) — acceptable.

**Mapping to existing engine (already supports all of this):** inverse trig `asin/acos/atan`, `10^(`, `e^(` (or `exp(`), `sqrt`, `^`, `pi`, `e`, scientific `2e3`. No new engine math needed except `ans` variable injection.

**NOT in v2:** `STO→`/`RCL`/variables A–Z, complex `i`, matrices, stat/lists, `solve`, programs — these are TI features beyond a precalc demonstration calculator (deferred; see §6 and the v2-deferred list in §5).

---

## 8. Session log

| Date | Summary |
|---|---|
| 2026-06-25 — calculator design lock-in | **Created `Calculator_status.md`.** Captured the full design conversation: graph-first with mode toggle, draggable as a floating palette, TV mirroring via the same Mirror/Present rules as the rest of the canvas, state persisted via UserDefaults, implicit multiplication in the parser, snapshot-to-canvas deferred until image-object layer exists. Locked architecture: new `Calculator` library target inside `MathBoardCore`, no cross-module dependencies, integration glue deferred. Began engine implementation. |
| 2026-06-25 — read-after-1hr directive | **Added a Reading instruction block at the top of the doc.** Claude reads `Calculator_status.md` top-to-bottom at the start of any session that follows a break of one hour or more, before writing any calculator code. Section 2 (locked-in decisions) and section 6 (deferrals) are the source of truth and not reopened without explicit user direction. |
| 2026-06-25 — engine v1 | **Math engine shipped.** Added `Calculator` target to `Package.swift` (no dependencies, no library product — sits in the package and compiles standalone). Wrote eight engine files: `CalculatorAngleMode`, `CalculatorError`, `CalculatorToken`, `CalculatorExpression`, `CalculatorTokenizer`, `CalculatorParser`, `CalculatorEvaluator`, `CalculatorEngine`. Recursive-descent parser handles standard precedence plus implicit multiplication (`2x`, `2sin(x)`, `2π`, `(x+1)(x-1)`). Evaluator covers trig + inverse + hyperbolic (degree/radian aware), `log` 1- or 2-argument, `ln`, `log2`, `exp`, `sqrt` / `√` / `cbrt`, `abs`, `floor`, `ceil`, `round`, `sign`, `min`, `max`, `mod`, postfix factorial with negative / non-integer / overflow guards, and domain errors for trig zeros + inverse-trig bounds + non-positive log/sqrt input. Constants: `pi` (also `π`), `e`. Two-stage API: `compile(_:)` + `evaluate(compiled:)` for graphing loops, plus a one-shot `evaluate(_:)` for the compute-mode press-equals path. Build verifies clean. No other MathBoard module touched. |
| 2026-06-26 — parser precedence fix | **Made `^` bind tighter than unary minus** so `-2^2 = -(2^2) = -4`, matching standard math convention (and scientific calculators). Restructured the parser's call chain so `parseUnary` calls `parsePower` rather than `parsePostfix`. Verified by tests: `-2^2 == -4`, `(-2)^2 == 4`. |
| 2026-06-28 — neumorphic keys | **Made the keys neumorphic / tactile (build clean, 169/169 tests).** `CalculatorKeyButtonStyle` now renders a softly-extruded domed key: a top→bottom sheen gradient (light top, shade bottom) over the fill, a hairline edge, and dual neumorphic shadows (dark bottom-right + faint white top-left). On press the gradient inverts (reads as pushed-in), the shadows collapse, and it scales to 0.96. Applies to both compute and graph keypads automatically (shared style). |
| 2026-06-28 — dark theme | **Restyled the calculator dark for TV legibility (build clean, 169/169 tests).** New `CalculatorTheme` (charcoal panel gradient, `surface`, `graphBackground`, amber/bronze `accent`, white labels) + `CalculatorKeyButtonStyle` (dark rounded keys, white text, hairline edge, press feedback). `CalculatorView` and `CalculatorTVOverlay` cards use the panel gradient and force `.environment(\.colorScheme, .dark)` so all text is white and system controls (TextField/Picker/Menu) render dark automatically; `.tint(accent)`. Compute + graph keypads use the dark key style (digits/operators/functions/modifiers differentiated by subtle dark tones; action keys amber; 2nd-armed = amber, 2nd-shifted = dark indigo). Graph plot, number line, and equation cells now use `graphBackground`/`surface`; `CalculatorGraphRenderer` and `CalculatorNumberLineView` Canvas gridlines/axes/labels switched to white-on-dark (`gridline`/`axis`/`graphLabel`). Removed the old pastel `.tint` key coloring. Inspired by the user's dark textured metronome screenshot. |
| 2026-06-28 — 1 Variable menu-driven flow | **Rebuilt 1-Variable to the menu-driven spec (+2 tests, 169/169 passing, builds clean).** One number-line graph window (pan/zoom via gestures on the window) shows each active inequality as a colored layer (`CalculatorNumberLineView` now takes `[NumberLineLayer]`). Cell 1 = field + right-end dropdown (`–`/`and`/`or`); choosing `and`/`or` reveals cell 2 (ensures a 2nd equation exists) with its own dropdown (`–`/`=`); choosing `=` shows the combined-solution number line (intersection/union per the connective). Max two inequalities. State: `oneVarConnective` (none/and/or) + `oneVarShowSolution`, persisted; `OneVarConnective.combineMode` maps to the region algebra. Keypad rearranged: row1 `x = < >`, row2 `and or ≤ ≥` (inequalities 2×2; and/or under x/=), then number pad. **Needs hardware verification of each interaction step.** |
| 2026-06-28 — 1 Variable redesign (per-equation lines + And/Or) | **Reworked 1-Variable mode toward the user's spec (+8 tests, 167/167 passing, builds clean).** Keypad reduced to exactly `x`, relations (`< ≤ > ≥ =`), `and`/`or`, and a number pad (`0–9 . (−)`, `⌫`, `C`) — removed abs-bar, parens, and arithmetic operators. The number-line area now renders **one number line per equation** (stacked, scrollable, each labeled + colored + with its own solution text). When ≥2 equations exist, an **And/Or segmented toggle** (`CalculatorState.graphCombineMode`, persisted) appears plus a **combined 3rd number line** showing the intersection (And) or union (Or). Added `SolutionRegion` set-algebra (`from`/`contains`/`combine`/`asSolutionSet`) via boundary+midpoint testing, and compound `" and "`/`" or "` parsing in the solver (and binds tighter than or). Number-line renderer draws degenerate `[p,p]` intervals as dots. **Open item:** the equation rows are still tap-to-select with keypad entry (the "+" circle adds rows); per-equation editing targets the selected row. |
| 2026-06-28 — 1 Variable mode + Topic dropdown fix | **Shipped number-line equation solving + fixed the Topic dropdown (+22 tests, 159/159 passing, builds clean).** Engine: added `\|…\|` absolute-value bars (tokenizer `.bar`, parser uses a `barDepth` counter so `2\|x\|` and `\|x-3\|` both parse correctly; `.unmatchedAbsBar` error). New `CalculatorEquationSolver` (pure): splits on `= < ≤ > ≥` (unicode + ascii; no-operator ⇒ `=0`), builds `g(x)=lhs−rhs`, sign-change bisection root finding; equality→discrete roots, inequality→merged midpoint-tested intervals with correct endpoint inclusivity, plus `.all`/`.none`/`.error`. `CalculatorSolutionFormatter` ("x = 1, 5" / "x ≤ −2 or x ≥ 2"). `CalculatorNumberLineView` (axis, ticks, filled dots for equalities, shaded open·closed segments for inequalities). Added `.oneVariable` to `GraphFunctionFamily` with a bespoke keypad (x, (, ), \|, <, ≤, >, ≥, digits, ops, wide =). `CalculatorGraphView` branches to number-line + solution text for 1 Variable. **Topic dropdown fix:** moved to its own full-width row using a `Menu` of `Button` rows (checkmark on current) + `.lineLimit(1)` + full-width label, so family names (e.g. "Exponential / Log", "Trigonometric") no longer truncate/ellipsize. Verified: `\|x-3\| = 2 → x = 1, 5`. Append/backspace entry only (cursor keys deferred). |
| 2026-06-28 — graph family/Topic keypad | **Added the Topic dropdown + family-specific entry keypad (+8 tests, 137/137 passing, builds clean).** New `GraphFunctionFamily` (General/Linear/Quadratic/Polynomial/Trig/Exp·Log), persisted as `CalculatorState.graphKeypadFamily`. `GraphKeypadLayout.keys(for:)` swaps the function-key rows per family over a shared numeric base (Linear has no powers; Quadratic `x²`/`√`; Polynomial `x³`/`^`/`∛`; Trig `sin/cos/tan/π`; Exp·Log `eˣ/ln/10ˣ/log`). `CalculatorGraphView` rebuilt to the screenshot model: tap-to-select equation rows (keypad-only entry, no system keyboard), Topic menu, family keypad (togglable), DEG/RAD shown only for Trig, and a `camera` photo button (calls optional `onSnapshot`, disabled until the MathBoard image-object layer exists). Compute/Graph toggle stays in the palette title bar. **Logged next steps from the user's screenshot:** the `1 Variable` number-line + equation solver (needs parser `= < ≤ > ≥`, a solver, and a 1D number-line renderer) and photo-button wiring — full specs in §5. |
| 2026-06-27 — v2 fuller keypad + resize noted | **Expanded the keypad after seeing the Calculate84 layout (124/124 passing, builds clean).** Added the genuinely-functional TI keys still missing: `x` (the X,T,θ,n graphing variable), `x⁻¹` (reciprocal, `^-1`), and `∛` (cube root, `cbrt(`). Repacked to a full 8×5 grid (no half-empty row): row1 `2nd`/`DEG·RAD`/`x`/`C`/`⌫`; row2 `x⁻¹`/`sin`/`cos`/`tan`/`xⁿ`; row3 `x²`/`√`/`∛`/`(`/`)`; row4 `log`/`ln`/`π`/`e`/`EE`; rows5–8 digit grid with `÷ × − +`, `,` `!` `ans` `(−)` `=`. Pure-menu TI keys (MATH/APPS/VARS/STAT/MODE/ALPHA/STO) intentionally NOT added as dead keys — they need menu/variable systems (deferred). **Recorded keypad+screen RESIZE as a requested future feature** (Calculate84 has it) in §6. Still capped at 8 rows so it fits 360×540 until resize lands. |
| 2026-06-27 — v2 TI-84-style keypad | **Built a mature TI-84-Plus-CE-style compute keypad (+9 tests, 123/123 passing, builds clean).** User wants the calculator to mirror a TI-84 so they can demonstrate which keys students press. Added: engine `ans` (last-answer injection via `CalculatorState.lastAnswer`); a `2nd` modifier system (`CalculatorKey.secondLabel/secondAction/hasSecond`, `.toggleSecond` action, `isSecondActive` in the compute view with TI-style auto-reset and visual arming); a rebuilt keypad with `2nd`, `DEG/RAD`, `ans`, `C`, `⌫`, `sin/cos/tan` (+2nd inverse), `(`, `)`, `x²`, `xⁿ`, `√`, `log` (+2nd `10ˣ`), `ln` (+2nd `eˣ`), `π`, `e`, `EE`, `,`, `!`, digit/operator grid, `(−)`, `=`. Reduced key minHeight 40→34 and display lineLimit 3→2 for the now-8-row keypad. Two hardware-verify items remain: (a) keypad fit in 360×540, (b) whether the `2nd`-armed highlight needs to mirror to the TV (currently local `@State`; lift to `CalculatorState` if needed). Still deferred: STO/RCL + variables A–Z, complex `i`. |
| 2026-06-27 — v1 SHIPPED (hardware verified) | **User confirmed on physical iPad + TV:** (1) buttons visible on the external display, (2) live mirror works (expression + result + graph), (3) calculator is correctly read-only on the TV. Combined with the earlier pencil-hit-test pass, all integration acceptance criteria are met. **Calculator v1 is complete and shipped.** Growth items remain in §6 (snapshot-to-canvas, multiple curves, sliders, polar/parametric, resize). |
| 2026-06-27 — TV shows full interface + pencil verified | **Hardware test results + fix.** User confirmed (1) Apple Pencil hit-test PASSES — ink draws on canvas everywhere except under the palette. (2) TV showed the calculator card but no buttons — by design the TV bodies were stripped-down (no keypad). User wants the full button interface on the TV to demo which buttons to push. **Fix:** `CalculatorTVOverlay` now renders the REAL `CalculatorComputeView` / `CalculatorGraphView` (full keypad + graph controls), kept read-only by the overlay's existing `.allowsHitTesting(false)`; deleted the stripped `CalculatorTVGraphBody` / `CalculatorTVComputeBody`. To mirror the compute answer too, moved the compute result into shared state: added ephemeral `CalculatorState.computeResult` / `computeIsError` (not persisted) and switched `CalculatorComputeView` from local `@State` result to the shared properties — so the iPad's "=" result appears on the TV. Cross-scene observation confirmed working (the card already appeared on connect). Build clean; 114/114 tests still pass. **Needs USER re-test on hardware:** TV now shows the keypad/graph controls and mirrors expression + result live. |
| 2026-06-27 — INTEGRATED into MathBoard | **Wired the calculator into the app — full project builds clean, 114/114 module tests still pass.** Applied the 4 edits from `Calculator_integration_HANDOFF.md`: (1) `Package.swift` — `Presentation` now depends on `Calculator`; (2) `DisplayBroker` — added `calculatorReferenceSize: CGSize?`; (3) `PresentingCanvasView` — `import Calculator`, `private let calculator = CalculatorState.shared`, `CalculatorView(state:)` overlaid in the ZStack when `calculator.isVisible`, container size published to the broker via a background `GeometryReader`, and a `function`-icon toolbar button toggling `calculator.isVisible`; (4) `ExternalCanvasView` — `import Calculator` + `CalculatorTVOverlay(state: .shared, referenceSize: broker.calculatorReferenceSize ?? fitted)` overlaid inside the fitted-rect ZStack. `BuildProject` succeeded (9.5s). **Still needs USER hardware test:** (a) Apple Pencil must draw on canvas everywhere except under the palette card — if ink bleeds through, fix belongs in the Calculator module (opaque hit-testing background), not MathBoard; (b) `CalculatorTVOverlay` must update live on the external display when the iPad mutates `CalculatorState.shared`. |
| 2026-06-26 — integration handoff / v1 complete | **Wrote `Calculator_integration.md` — the calculator module is feature-complete for v1.** Documentation-only step (no code). The handoff doc gives copy-pasteable steps: link the module (make `Presentation` depend on `Calculator` in `Package.swift` — no pbxproj edit), publish `calculatorReferenceSize` on `DisplayBroker`, overlay `CalculatorView` + a `function` toolbar toggle in `PresentingCanvasView`, overlay `CalculatorTVOverlay` inside the fitted rect in `ExternalCanvasView`, plus a verification checklist (toggle, drag/clamp, persistence, mode switch, solid pencil hit-test, TV mirror, DEG/RAD) and rollback notes. `CalculatorState.shared` bridges the iPad and external UIScenes automatically (same singleton, same process) exactly like `DisplayBroker.shared`. All eight planned module steps are done; the remaining work is the user's integration on their own timeline. |
| 2026-06-26 — TV overlay | **Shipped the read-only external-display overlay + 5 layout tests (114 total passing).** Extracted `CalculatorGraphRenderer.swift` (shared gridline/axis/label/curve `Canvas` drawing) and refactored `CalculatorGraphView` to use it (removed ~90 duplicated lines). Added `CalculatorTVOverlay.swift` — public read-only view observing the shared `CalculatorState`, rendering the graph plot or a re-evaluated compute display at the matching relative position, scaled to the TV bounds, hit-testing disabled, only visible when `state.isVisible`. `CalculatorTVLayout.placement(...)` (pure: fractional-center + width-ratio scale, nil/zero fallbacks) covered by `CalculatorTVLayoutTests.swift`. Intentional divergence recorded: the TV re-evaluates `computeExpression` live since it has no key events to mirror. Refactor + new code verified clean on the first test run. **The calculator module is now feature-complete for v1** — only the integration handoff doc remains. No other MathBoard module touched. |
| 2026-06-26 — graph mode UI | **Shipped graphing + 18 geometry tests (109 total passing).** Added `CalculatorGraphGeometry.swift` (pure: graph↔view transforms, pan, focal-point zoom with span clamping, nice-number tick steps, tick generation, function sampling with nil-for-undefined) and `CalculatorGraphView.swift` (y= editor, `Canvas` plot with axes/gridlines/labels/curve, drag-pan + `MagnifyGesture` zoom, zoom/reset buttons, asymptote-break + invalid-expression banner). Replaced `CalculatorView`'s graph placeholder with the real view. `CalculatorGraphGeometryTests.swift` covers transforms (round-trip), pan direction + span preservation, zoom shrink/grow/focal-fixed/min-span clamp, tick steps + range + huge-count guard, and sampling (count, linear values, NaN→nil, nil→nil). Two test-only compile errors fixed (the `XCTAssertEqual(_:_:accuracy:)` overload needs a non-optional `Double`, so optional `.y`/`.first?.x` were `XCTUnwrap`'d) — production code was correct as written. v1 graphs one `y = f(x)`; multiple curves + sliders + polar/parametric remain growth items. No other MathBoard module touched. |
| 2026-06-26 — draggable palette | **Shipped the floating palette frame + 7 clamp tests (91 total passing).** Added `CalculatorView.swift` — the public `CalculatorView(state:)` entry point: fixed 360×540 card, title bar with a segmented Graph/Compute mode `Picker`, a disabled snapshot button (placeholder until the image-object layer), and a close button; body switches between `CalculatorComputeView` and a graph placeholder. Title-bar `DragGesture` writes the clamped center into `state.position`; solid hit-testing via `.contentShape`. Extracted `CalculatorPaletteLayout.clamp(...)` as pure math (keeps the card on-screen, centers on an axis if the container is too small) with `CalculatorPaletteLayoutTests.swift` covering edges/corner/undersized-container. SwiftUI view compiles under Xcode's toolchain. No other MathBoard module touched. |
| 2026-06-26 — compute-mode UI | **Shipped compute-mode keypad + display, 18 new tests (84 total passing).** Added `CalculatorKey.swift` (SwiftUI-free: key model, default scientific keypad layout, expression reducer, result formatter), `CalculatorComputeView.swift` (editable expression field + result line + keypad, evaluates via `CalculatorEngine` with the live angle mode, DEG/RAD key flips mode and re-evaluates), and `CalculatorKeyTests.swift` (reducer, formatter, keypad-layout coverage). **One real bug caught by the tests:** the formatter's integer path emitted an ASCII `-` while the fractional/scientific paths used the unicode minus `−` — made all paths consistent on `−`. The SwiftUI view compiles cleanly under Xcode's toolchain (CLI `swift test` with `DEVELOPER_DIR` pointed at Xcode resolves the `#Preview` macro plugin). History strip intentionally not built in v1. No other MathBoard module touched. |
| 2026-06-26 — state + persistence | **Shipped `CalculatorState` + 13 tests (all passing).** `@MainActor @Observable` container persisting `mode`, `angleMode`, `position`, `computeExpression`, `graphExpression`, and a Codable `GraphWindow` to `UserDefaults` (keys namespaced `calculator.*`, written per-property in `didSet`). `isVisible` is per-session and never persists — the calculator opens closed every session per the locked-in design. Added `CalculatorMode` (`.graph`/`.compute`, `toggled` helper) and `GraphWindow` (default ±10, `isValid`, `width`/`height`). `init(store:)` accepts an injectable `UserDefaults` so tests run in isolated suites. Tests cover defaults, every round-trip, position-clear, same-value no-op writes, invalid-window detection, and the visibility-not-persisted rule. Engine + state combined: **66/66 tests passing.** No other MathBoard module touched. |
| 2026-06-26 — engine tests | **Wrote and ran 53 XCTest cases** in `Tests/CalculatorTests/CalculatorEngineTests.swift`. Nine suites cover arithmetic precedence, power + unary minus convention, implicit multiplication (`2x`, `2sin(x)`, `2π`, `(x+1)(x-1)`, `2x^2`), trig in both degree and radian modes including reciprocal + inverse + hyperbolic, log (1-arg base 10 vs 2-arg arbitrary base), `ln`, `log2`, `exp`, `sqrt` + `√` + `cbrt`, abs/floor/ceil/round/sign, min/max/mod, factorial edge cases (`0! = 1`, negative/non-integer rejected, overflow at 171!), constants (`pi`/`π`/`e`), variable injection for graphing, `compile` + `evaluate(compiled:)` loop replaying many `x` values, and error paths (division by zero, sqrt of negative, ln of zero, asin out of range, unknown function, wrong arity, unbalanced parens, unexpected character, empty expression). **Two real bugs caught and fixed:** (1) `√` symbol was missing from the tokenizer despite the design doc claiming it worked — added `.identifier("sqrt")` mapping; (2) my round-test expectation assumed banker's rounding, but Swift's default `.rounded()` rounds half away from zero (which is what calculators should do — `round(2.5) = 3`, `round(-2.5) = -3`) — updated test to match. **All 53 tests pass.** Tests run via `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CalculatorTests --build-path /tmp/MathBoardCore-calc-build` (separate build path to avoid Xcode-while-open touching the SPM `.build` directory mid-compile). XCTest rather than Swift Testing chosen so the suite runs from both `swift test` CLI and Xcode without extra toolchain dependency. |
