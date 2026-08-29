# Calculator Status

## 2026-08-28 (CALC menu — 2nd+TRACE graph analysis)

### CALC menu (2nd + TRACE)

Pressing `2nd` then `TRACE` opens the **CALCULATE** menu overlaid on the calculator screen. 7 items:

| # | Name | Implementation |
|---|---|---|
| 1 | value | Full — cursor-only, computes Y at cursor X |
| 2 | zero | Full — left bound → right bound → guess → Brent's method |
| 3 | minimum | Full — left bound → right bound → guess → Golden Section Search |
| 4 | maximum | Full — same as minimum, inverted |
| 5 | intersect | Placeholder (ERR message) |
| 6 | dy/dx | Full — cursor-only, central-difference derivative |
| 7 | ∫f(x)dx | Full — left bound → right bound → Simpson's rule (n=1000) |

Menu pre-highlights **3:minimum** on open. Digits 1–7 select directly; UP/DOWN arrow navigates rows; ENTER confirms selection; CLEAR exits.

### Interactive bound & guess workflow (minimum/maximum/zero)

After selecting an operation, the graph plot view shows an interactive cursor:

1. **Left Bound?** — cursor (crosshair snapped to curve) moves with LEFT/RIGHT arrows; ENTER locks the left bound (solid ▼ triangle marker appears at top of screen at that X)
2. **Right Bound?** — cursor must be placed to the right of the left bound; ENTER locks it (second triangle marker)
3. **Guess?** — cursor placed near the expected extremum/zero; ENTER seeds the optimizer

For `value` and `dy/dx` there is only a single cursor phase — ENTER computes immediately.
For `∫f(x)dx` there are only the two bound phases — no guess needed.

### Numerical algorithms

- **Minimum/Maximum**: Golden Section Search restricted to `[leftBound, rightBound]`, 200 iterations, tolerance 1e-12
- **Zero**: Brent's method with sign-change detection scan (200 sub-intervals) and 100 refinement iterations, tolerance 1e-12
- **dy/dx**: Central difference `(f(x+h) − f(x−h)) / 2h` with `h = 1e-7`
- **∫f(x)dx**: Composite Simpson's rule with n=1000 panels

### Result display

After computation, the result is shown in the bottom-left overlay (white rounded box):
- **Label**: "Minimum", "Maximum", "Zero", "∫f(x)dx", "value", "dy/dx"
- **X=**: result X coordinate (not shown for integral)
- **Y=**: result Y value (or integral area)

The crosshair cursor moves to the result point. ENTER or CLEAR exits back to the graph.

### State additions (CalculatorState.swift)

```
CalcToolPhase: none / leftBound / rightBound / guess / result
CalcToolOperation: value(0) / zero(1) / minimum(2) / maximum(3) / intersect(4) / dyDx(5) / integral(6)
calcToolPhase, calcToolOperation, calcToolMenuSelection
calcToolCursorX, calcToolLeftBound, calcToolRightBound
calcToolResultX, calcToolResultY, calcToolResultLabel
```

`CalculatorGraphScreenMode` extended with `.calcMenu`.

### Files changed

- `Calculator/CalculatorState.swift` — new enums + state vars + `beginCalcTool(operation:)` method
- `Calculator/CalculatorFullKeypadView.swift` — `calcAction` property, `.calc` command, `2nd+TRACE` wired
- `Calculator/CalculatorView.swift` — `showCalcMenu`, `handleCalcMenuNavigation`, `handleCalcToolNavigation`, `handleCalcToolEnter`, `exitCalcTool`, `computeCalcToolImmediate`, `computeCalcToolWithBounds`, `buildCalcFunction`, `calcGoldenSection`, `calcBrentsMethod`, `calcSimpsons`; `CalculatorCalcMenuScreen` struct; canvas `drawCalcToolOverlay`; `calcPromptOverlay` + `calcResultReadout` views



## 2026-08-27 (equation editor — = sign fix + touch targets + popover picker)

### = sign highlight fix

Only the `=` character is now highlighted (black bg / white text) when an equation is enabled — the `Y` and row number are never highlighted. Previously the entire `Y1=` label was lit, which was wrong. The two elements are now rendered as separate `Text` views: `Text("Y\(n)")` (always black) and `Text("=")` (lit when enabled, tappable).

### Touch targets

Each section of an equation row has its own tap gesture:
- **Swatch/line-style area** → selects the row (col=0) and opens the style popover
- **= sign** → toggles `equation.isEnabled` (on/off; lights or dims the `=` highlight)
- **Expression area** → selects the row (col=2) and positions cursor at end (or keeps current position if row was already selected)

### Style picker — SwiftUI popover with dropdowns

The style picker is now a floating **popover** (SwiftUI `.popover()`, appears as a small popup bubble on iPad) rather than an inline panel. It contains:
- A **Color** dropdown (`Picker(.menu)`) with 10 named colors: BLUE, RED, GREEN, PURPLE, ORANGE, TEAL, BLACK, MAGENTA, BROWN, YELLOW — each showing a colored circle
- A **Line Style** dropdown (`Picker(.menu)`) with 6 options: Thin, Thick, Dotted, Dashed, Above, Below — each showing its display symbol

Arrow-key ENTER on col=0 still opens the popover via `state.isEquationStylePickerVisible`. Both `stylePickerPresented` (@State) and `state.isEquationStylePickerVisible` are kept in sync via `onChange`.

### Line style icon — diagonal "/" (up and to the right)

All line style icons in the equation rows now use a diagonal "/" path (bottom-left to top-right) matching the TI-84 visual, replacing the previous horizontal "—" stroke.

## 2026-08-27 (equation editor — full cursor + = toggle + style picker)

### Character-level cursor

The equation editor cursor now moves **character by character** through the expression. LEFT arrow moves the cursor one character left; when at the start of the expression, one more LEFT goes to the `=` sign, and another LEFT goes to the swatch/style area. RIGHT mirrors this in reverse.

- `equationEditorCharIndex: Int` tracks cursor position within the expression (0 = before first char, n = after last char)
- Cursor blinks as a dark block (14×22 pt) inserted between the "before" and "after" text at the cursor position — raised to center-align with text
- Typing any key while in the expression column inserts text at the cursor position (INSERT mode) and advances `charIndex`; DEL removes the character to the left; CLEAR clears the whole expression
- Any typing while cursor is on col 0 or 1 jumps cursor to end of expression and types there
- ENTER in expression column moves to the next equation row

### = sign enable/disable

- The `=` sign is displayed with **black background / white text** (lit) whenever the equation has content AND `isEnabled == true` — this is the "will be graphed" indicator, visible on ALL rows, not just the selected one
- When cursor is on col=1 (= sign) for the selected row, the = sign **blinks** (cursorVisible toggles) to show cursor position
- **ENTER while cursor is on the = sign** toggles `equation.isEnabled`. When disabled, the = sign goes dark (un-lit) and the equation is no longer plotted

### Color + line style picker

- **ENTER while cursor is on the swatch/style area (col=0)** opens/closes an inline picker panel
- The picker shows a **Color:** row (10 color swatches — blue, red, green, purple, orange, teal, black, magenta, brown, yellow) and a **Line:** row (6 TI-84 line styles: Thin, Thick, Dotted, Dashed, Above, Below)
- Tapping a swatch or style applies it immediately
- Arrow keys LEFT/RIGHT cycle through colors (UP row) or styles (DOWN row) in the picker; UP/DOWN switch between the two rows
- The line style icon in each equation row updates to reflect the chosen style

### GraphPalette expansion

`GraphPalette.colors` expanded from 6 to 10 entries (backward-compatible — first 6 unchanged). `colorNames` array added for picker labels. `EquationLineStyle` enum added with 6 cases and `displaySymbol`/`name` properties.

`GraphEquation.lineStyleIndex: Int` added (Codable with `decodeIfPresent` default=0 for backward compat).

## 2026-08-27 (equation editor cursor)

The Y= equation editor now has a TI-84-style column cursor navigatable with LEFT/RIGHT arrow keys. The cursor has three positions within the selected row:

| LEFT presses from default | Column | Visual |
|---|---|---|
| 0 | Expression (col 2, default) | Blinking dark block at end of expression text |
| 1 | Y= label (col 1) | `Y1=` text shown white-on-black (inverted) |
| 2 | Swatch + line style (col 0) | Color swatch and line icon inverted (white on black) |

**Navigation:**
- LEFT arrow: move cursor one column left (col 2 → 1 → 0, stops at 0)
- RIGHT arrow: move cursor one column right (col 0 → 1 → 2, stops at 2)
- UP/DOWN arrow: move to prev/next equation row (column position preserved)
- Tapping a row: selects it and resets cursor to col 2 (expression)
- Entering the editor (Y= key): resets cursor to col 2

**State:** `CalculatorState.equationEditorColumn: Int` (0=swatch+style, 1=Y=, 2=expression).

Functionality on ENTER while col=0 or col=1 is not yet wired (to be added next).

## 2026-08-27 (photo button)

The camera button in the calculator title bar (and the detached screen header) now captures a snapshot of the current calculator screen and inserts it as an image on the whiteboard canvas.

**How it works:**
- `CalculatorView` accepts `onSnapshot: ((Data, CGSize) -> Void)?` callback (default `nil`)
- Pressing the camera button calls `takeSnapshot()`, which uses SwiftUI `ImageRenderer` to render the current screen content (`CalculatorScreenWindow`) at 480×360 pt (×2 scale = 960×720 px PNG)
- The PNG data + display size are returned via `onSnapshot`
- `PresentingCanvasView` wires the callback → `CanvasObjectCommand(.insertImageNearViewport(...))` to drop the image onto the canvas near the current viewport
- Camera button is visually dimmed and disabled when `onSnapshot` is `nil` (e.g. TV overlay, standalone previews)
- The detached screen header shows the camera button in all modes (graph and compute)

**Files changed:**
- `Calculator/CalculatorView.swift` — `onSnapshot` param, `takeSnapshot()`, button wiring
- `Presentation/PresentingCanvasView.swift` — wires the callback to canvas command (one call site)

## 2026-08-26 (font bump)

All calculator screen fonts increased ~3 pt for presentation legibility:

| Screen | Before | After |
|---|---|---|
| HOME — expression / answer / error | 16 / 16 / 14 | 20 / 20 / 18 |
| Tabbed-menu items | 17 | 21 |
| Tabbed-menu tab headers + message bar | 13 | 15 |
| Stat-editor column headers | 18 | 21 |
| Stat-editor cell values | 16 | 19 |
| Stat-editor entry label | 12 | 17 |
| Regression title / result rows | 18 / 16 | 21 / 19 |
| Regression expression | 13 | 16 |
| Equation editor status bar | 12 | 17 |
| Equation editor Plot header | 18 | 21 |
| Equation editor Y= label / expression | 24 / 21 | 27 / 24 |
| Zoom menu tabs | 16 | 19 |
| Zoom menu items | 18 | 21 |
| Y-VARS header / rows | 14 / 16 | 17 / 19 |
| 1-Var / 2-Var Stats header | 16 | 19 |
| 1-Var / 2-Var Stats result rows | 15 | 18 |
| WINDOW header / fields | 16 | 19 |
| TABLE header + cells | 14 | 17 |

Small decorative/overlay items intentionally left small: status-bar NORMAL strip (10 pt), row-number gutters (10 pt), DUMMY/ready badges, trace readout overlay.

## 2026-08-26 (TBLSET + >Frac deferred execution)

### TBLSET screen (2nd + WINDOW)

2nd+WINDOW now opens a dedicated TABLE SETUP screen (was incorrectly showing the TABLE view). Fields:

| Row | Label | Type | State property |
|---|---|---|---|
| 0 | TblStart= | numeric edit | `tableStartX` |
| 1 | ΔTbl= | numeric edit | `tableStep` |
| 2 | Indpnt: | Auto / Ask toggle | `tableIndpntMode` |
| 3 | Depend: | Auto / Ask toggle | `tableDependMode` |

Navigation: UP/DOWN moves between rows; LEFT/RIGHT toggles Auto/Ask on rows 2–3; ENTER on a numeric row commits the value and advances; ENTER on a toggle row cycles Auto↔Ask; CLEAR exits to home. Auto/Ask options are also directly tappable.

`TableControlMode` enum (`.auto`, `.ask`) added to `CalculatorState`. `tblSetEditorField` and `tblSetEditorText` track in-progress edits.

Note: TABLE view already respects `tableStartX` and `tableStep`. Ask-mode behavior inside the TABLE view (blank X rows / hidden Y cells) is a planned follow-on.

### >Frac / >Dec — deferred execution

Selecting `>Frac` from MATH menu no longer auto-evaluates. Instead it appends `>Frac` to the expression so the screen shows e.g. `0.25>Frac`. The user then presses ENTER to evaluate. Same for `>Dec`. If the expression is empty, `Ans>Frac` / `Ans>Dec` is inserted so the operator applies to the previous answer. `evaluateCompute()` strips the suffix before calling the engine, applies the fraction formatter if `>Frac`, and records the original expression (with suffix) in history.

## 2026-08-26 (TV key highlight)

The external-display mirror now shows the last pressed key highlighted in pink. The highlight persists until the next key press (no timer, no fade).

**How it works:**
- `CalculatorState.lastPressedKeyLabel: String?` — stores the label of the most recently pressed key. Set on the iPad (which handles input); read by the TV overlay.
- `CalculatorFullKeypadView(showsKeyHighlight: Bool)` — when `true`, `keyFill(for:)` returns `.pink` for the key whose label matches `lastPressedKeyLabel`. Direction-pad arrows use internal labels `"dir.up"` etc.
- `CalculatorView(showsKeyHighlight: Bool)` — threads the flag down to the keypad.
- `CalculatorTVOverlay` creates `CalculatorView(state:, showsKeyHighlight: true)`.
- iPad-side `CalculatorView` uses the default `showsKeyHighlight: false` — no pink on the teacher's screen.

## 2026-08-26 (blinking block cursor)

`CalculatorComputeScreen` now shows a TI-84-style blinking block cursor at the insertion point:
- A dark gray `Rectangle` (12 × 19 pt, `Color(white: 0.28)`) appended directly after the expression text
- When the expression is empty the cursor sits alone at the left margin
- Blinks at 530 ms intervals via a Swift Concurrency `.task` loop — task is automatically cancelled when the view disappears
- The static `■` placeholder has been removed

## 2026-08-26 (MATH/NUM menu fixes)

### ENTER key in menus (bug fix)

`handleKey` was routing `.evaluate` (ENTER) directly to `evaluateCompute()` even when the math menu, stat menu, or other overlay screen was active. Added an early-return guard: when `activeScreen == .calc && calculatorScreenMode != .home`, ENTER is now dispatched through `handleCalculatorScreenKey` — fixing selection by ENTER for every calculator menu (MATH, NUM, STAT, Y-VARS, stat editor).

Number shortcuts (press "1" through "9" to pick an item) were already wired correctly through `.insert` → `handleMathMenuShortcut`; no change needed there.

### NUM tab — item 0: remainder(

Added `remainder(dividend, divisor)` as shortcut "0" in the NUM tab. Also added `"remainder"` as an alias for `"mod"` in `CalculatorEvaluator` so the expression evaluates correctly. Semantics: truncating remainder (same as TI-84 `remainder`).

## 2026-08-26 (earlier)

### HOME screen — authentic TI-84 layout

- **Expression rows** — left-aligned (matching TI-84 home screen where typed input grows left-to-right).
- **Answer rows** — a `Canvas`-drawn dotted rule fills the full row width; the answer value is right-aligned and sits on top with a white background that masks the dots behind it, matching the TI-84 visual exactly.
- **Cursor** — `■` character at bottom-left when the expression is empty.
- **Status bar** — gray header row showing NORMAL · FLOAT · DEGREE/RADIAN (like TI-84's top status strip); STO→ badge appears here when waiting for a variable letter.
- **Errors** — printed on the answer row in red (dotted rule + red text), keeping the expression on screen for editing.

### Y-function evaluation (Y1(x), Y2(x), …)

- `CalculatorEvaluator.evaluate()` accepts `yFunctions: [String: @Sendable (Double) throws -> Double]` (default `[:]`; all existing call sites unaffected).
- `CalculatorEngine.evaluate()` threads the same parameter through.
- `CalculatorView.evaluateCompute()` builds Y-function closures at call time (Y1–Y9), each compiling and evaluating the corresponding graph equation at the given x.
- Typing `Y1(4)` on the home screen evaluates equation Y1 at x=4.

### Y-VARS menu (ALPHA + TRACE = F4)

- ALPHA then TRACE (alpha label "F4") opens a Y-VARS screen listing Y1–Y9 with expressions.
- ENTER or digit shortcut inserts `Y1(` etc. into the expression; CLEAR/DEL cancels.

### STO→ history entry

- `storeVariable()` appends `Ans→A` + value to compute history so the confirmation appears in the left/right-aligned flow.

### QUIT (2nd + MODE)

- `quitToHome()` resets to Calc home screen from any mode/screen.

## 2026-08-25

TI-84 calculator module — Algebra 2 / Precalculus feature pass.

### Engine

- `rand`, `nPr`, `nCr`, `randInt`, `iPart`, `fPart`, `int` all wired.

### State

- `GraphWindow` with `xScl`/`yScl` (backwards-compatible Codable).
- `CalculatorHistoryEntry`, scrollable compute history (capped at 20).
- `storedVariables` A–Z (persisted). TABLE settings persisted. TRACE state. WINDOW editor state.

### Screens

- **HOME** — TI-84 left/right layout with dotted rule separating expression and answer.
- **WINDOW editor** — 6 fields, arrow-key navigation.
- **TABLE** — x vs Y1/Y2/Y3, UP/DOWN scrolls.
- **TRACE** — crosshair + X/Y readout, arrows step/cycle.
- **1-Var Stats** / **2-Var Stats** result screens.
- **Regression result** screen.

### Known intentional placeholders

- ZOOM presets other than `6:ZStandard` return to graph without applying.
- STAT tests, complex numbers, and FRAC/CMPLX menu tabs are visual placeholders.
- TABLE TBLSET step editing not yet wired; step defaults to 1.
- Y-functions inside graphed equations (Y2 = Y1(x)+1) not wired — compute-mode only.
