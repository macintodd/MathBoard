# Calculator Status

## 2026-08-29 (MathPrint superscript, auto-close parens, root slot navigation)

### `^` renders as superscript in MathPrint mode

In MathPrint mode, `x^3` renders as `x` with a raised `³` superscript. Expressions like `sin(x)^2`, `2^(n+1)`, `e^x` all render correctly with the exponent raised above the baseline.

**Parser:** `parseMathPrint` now handles `^` — it calls `mpExtractExponent` which:
- Takes a parenthesized group (e.g. `^(n+1)` → exponent is `(n+1)`)
- Or a simple atom with optional leading minus (e.g. `^3`, `^-1`, `^x`)
- Stops at operators, commas, closing parens — so `x^2+3` renders `x²+3` with `+3` at normal height

**Token:** `.superscript(exponent: [MPToken])` added to `MPToken`.

**Rendering:** `MPLineView` renders `.superscript` as a smaller (0.6em) `MPLineView` with `padding(.bottom, 0.5em)`. In the parent `HStack(.bottom)`, this raises the exponent above the text baseline.

**Cursor in superscript slot:** `x^` (incomplete) places the cursor inside the raised slot. `x^3` (with cursor active) shows `3■` in the superscript position.

### Auto-close unclosed parentheses before evaluation

`cbrt(9` now evaluates correctly as `cbrt(9)` without requiring the user to type the closing paren. The radical bar visually closes the construct, so the closing paren is implied.

**Implementation:** `autoCloseParens(_ expr: String)` counts unmatched open parens and appends the necessary closing parens before the expression is passed to the evaluator. Applied to `exprToEval` in `evaluateCompute()`. Works for all functions: `cbrt(`, `root(`, `sqrt(`, `sin(`, etc.

### Right arrow advances from root index slot to radicand

After typing `root(3` (cursor in the index superscript slot), pressing the right arrow key inserts a comma and advances the cursor to the radicand slot under the radical bar. Same behavior for `logBASE(` (right arrow advances from base subscript to argument slot).

**Implementation:** `handleHomeHistoryNavigation` now handles `.right` — when the live input (not scrolling history) contains `root(` or `logbase(` with no top-level comma after the opening paren, a `,` is appended.

### Files changed

- `Calculator/CalculatorView.swift` — `.superscript` case in `MPToken`; `^` handling in `parseMathPrint`; `mpExtractExponent` helper; `.superscript` rendering in `MPLineView.tokenView`; `autoCloseParens` method; `evaluateCompute` calls `autoCloseParens`; `handleHomeHistoryNavigation` handles `.right` for slot navigation

---

## 2026-08-29 (imaginary i key, NONREAL ANSWERS error screen)

### 2nd + . inserts imaginary unit `i`

`2nd` then `.` (decimal point) now inserts the imaginary unit `i` regardless of the calculator's complex mode. Works in both REAL and a+bi/re^(θi) modes.

**Implementation:** `CalculatorFullKeypadView.swift` — the `.` key already had `second: "i"` label; `secondAction: .insert("i")` was added so the 2nd+. action fires `.insert("i")` instead of being a no-op.

### ERR: NONREAL ANSWERS error screen

When the calculator is in **REAL mode** (`calcComplexMode == .real`) and an expression produces a complex/imaginary result (e.g. `sqrt(-1)`, `ln(-5)`), the home screen switches to a TI-84-style error screen instead of displaying a result.

**Detection — two paths:**
1. Expression contains `i` → routed to `CalculatorComplexEvaluator` → result is nonreal → triggers error
2. Expression has no `i` → real evaluator throws domain error → complex evaluator retry produces nonreal → triggers error

**Error screen UI (`CalculatorNonrealErrorScreen`):**
- Inverted black header: `ERROR: NONREAL ANSWERS`
- `1:Quit` — clears expression and result, returns to home with fresh cursor
- `2:Goto` — finds the first offending function in the expression (`sqrt(`, `log(`, `ln(`, `asin(`, `acos(`), truncates the expression to just after that function's opening paren, returns to home with cursor inside the construct (visible in MathPrint as an open radical with cursor inside)
- Explanation text: "In REAL MODE, all calculations must result in a real number."

Pressing `CLEAR` on the error screen behaves like `1:Quit`.  Pressing `1` or `2` via the keypad also works.

**State additions (`CalculatorState.swift`):**
- `CalculatorHomeScreenMode.nonrealError` case added to enum
- `nonrealErrorExpression: String` — stores the expression that caused the error (used by Goto)

**Architecture note:** `CalculatorNonrealErrorScreen` is self-contained — it takes `@Bindable var state: CalculatorState` directly and implements `quit()` and `goto()` internally. This avoids a scope mismatch (the `screenContent` property lives inside `CalculatorScreenWindow`, not `CalculatorView`).

### Files changed

- `Calculator/CalculatorFullKeypadView.swift` — added `secondAction: .insert("i")` to the `.` key
- `Calculator/CalculatorState.swift` — added `.nonrealError` to `CalculatorHomeScreenMode`; added `nonrealErrorExpression: String`
- `Calculator/CalculatorView.swift` — `triggerNonrealError()`, `handleNonrealQuit()`, `handleNonrealGoto()` on `CalculatorView`; `.nonrealError` handling in `handleCalculatorScreenKey` and `handleCalculatorNavigation`; `CalculatorNonrealErrorScreen` struct (self-contained with state); `screenContent` routes `.nonrealError` to the screen

---

## 2026-08-29 (MathPrint 2D rendering, argument order fix)

### MathPrint mode — 2D expression rendering on the home screen

When `MODE → MATHPRINT` is active (`state.calcDisplayFormat == .mathPrint`), the home screen renders expressions as proper 2D mathematical notation instead of flat text.

**Supported 2D constructs:**

| Expression text | MathPrint display |
|---|---|
| `cbrt(expr)` | `³√expr` with radical bar over expr |
| `root(n, expr)` | `ⁿ√expr` — superscript n, radical bar |
| `logBASE(base, x)` | `log` with subscript base, then `(x)` |
| Fraction result `"a/b"` | Stacked numerator-over-denominator |

**Cursor in slots (live input):**
- `logBASE(` typed → cursor appears in the subscript (base) slot; arg slot shows a dotted placeholder
- `logBASE(10,` → cursor moves into the argument slot
- `cbrt(` / `root(n,` → cursor is inside the radical (under the bar)
- Incomplete `root(` → cursor is in the index superscript position first, then moves under the bar after `,`

**Implementation:** `parseMathPrint(_ expr: String, addCursor: Bool)` returns `[MPToken]` (an `indirect enum` tree). `MPLineView` renders tokens using `HStack`; special views (`MPRadicalView`, `MPLogBaseView`, `MPFractionView`, `MPSlotPlaceholder`) handle 2D layout. The radical bar is drawn via SwiftUI `Canvas` overlay. All added as private file-scope types in `CalculatorView.swift`.

**History rendering:** Non-highlighted history expression rows use `MPLineView`; highlighted (inverted) rows fall back to plain `Text` for clean inversion. Result rows with fraction format `"n/d"` render as stacked fractions via `MPFractionView`.

**Classic mode unchanged:** When `MODE → CLASSIC`, flat text rendering is used exactly as before.

### Argument order fix (logBASE and root)

Fixed to match TI-84 convention — the slot the cursor enters first is the first argument:

| Function | Old order | New order |
|---|---|---|
| `logBASE(a, b)` | a=value, b=base | **a=base, b=value** |
| `root(a, b)` | a=value, b=index | **a=index, b=value** |

Examples (after fix): `logBASE(10, 100)` → `log₁₀(100) = 2`; `root(3, 27)` → `³√27 = 3`.

Both the real evaluator and the complex evaluator (`CalculatorComplexEvaluator`) were updated.

### Files changed

- `Calculator/CalculatorEvaluator.swift` — `logbase` and `root` argument order swapped in both real and complex evaluators
- `Calculator/CalculatorView.swift` — Added `MPToken`, `parseMathPrint`, `mpExtract`, `mpSplitComma`, `MPLineView`, `MPRadicalView`, `MPLogBaseView`, `MPFractionView`, `MPSlotPlaceholder`; `CalculatorComputeScreen` updated to use MathPrint views for history and live input

---

## 2026-08-28 (MATH menu, complex numbers, CLEAR, π display)

### MATH menu — full TI-84 CE MATH tab

All 13 items are now shown in the correct TI-84 order. Functional items:

| Shortcut | Display | Action |
|---|---|---|
| 1 | ▶Frac | append `>Frac`, ENTER converts to fraction |
| 2 | ▶Dec | append `>Dec`, ENTER converts to decimal |
| 3 | ³ | append `^3` (cubic) |
| 4 | ³√( | insert `cbrt(` |
| 5 | ˣ√( | insert `root(n, value)` — index first (TI-84 convention) |
| A | logBASE( | insert `logBASE(base, value)` — base first (TI-84 convention) |

Items 6–9, 0, B, C shown as disabled (DUMMY), matching TI-84 appearance.

### Complex numbers (CMPLX menu)

All 5 CMPLX items are now functional: `conj(`, `real(`, `imag(`, `angle(`, `abs(`.

When an expression contains the standalone token `i` (imaginary unit), evaluation routes to `CalculatorComplexEvaluator` which supports:
- Full complex arithmetic: `+`, `−`, `×`, `/`, `^` (integer powers via repeated multiplication, general via exp/log)
- `i^2 = −1`, `(2+3i)*(1−2i)`, etc.
- `abs(z)` → magnitude, `conj(z)` → conjugate, `real(z)`, `imag(z)`, `angle(z)` → argument in current angle mode
- Complex `sqrt(z)` (principal value), complex `ln(z)`
- Results formatted as `a+bi`, `a`, `bi`, `i`, `−i` etc. with insignificant parts suppressed (< 1e-10)

Implementation: `CalcComplex` struct + `CalculatorComplexEvaluator` appended to `CalculatorEvaluator.swift`.

### CLEAR behavior (two-press clear)

- **First press on non-empty expression**: clears the expression text only (same as before)
- **Second press on empty expression**: clears the visible history (sets `computeScreenCleared = true`)
- History entries are still retained in memory — UP arrow still recalls all previous entries
- Any key press or new evaluation un-clears the screen

### π symbol in expression display

Expressions containing `pi` display as `π` in the live input line and in the history. The evaluator still accepts both `pi` and `π` as the constant.

`logBASE(base, value)` is stored and displayed literally; `Ans` is used in place of `ans` for display. (Argument order is base-first to match TI-84 convention.)

### logBASE

`logBASE(` inserts the text `logBASE(` into the expression. The evaluator recognises `logbase` as an alias for `log(base, value)` — **base is the first argument**. Usage: `logBASE(2,8)` → `3`.

---

## 2026-08-28 (HOME screen history recall + implicit Ans)

### History recall (UP/DOWN on the home screen)

Pressing UP on the home screen scrolls backward through past inputs and outputs. Each line is highlighted with an inverted (black bg / white text) block as it is selected. DOWN scrolls back toward the live input.

- **Line order** (UP from live input): last result → last expression → second-to-last result → second-to-last expression → …
- The scroll view automatically centers the selected line in view.
- **ENTER while a line is selected**: pastes that line's text as the new current expression and returns to live input.
- **CLEAR while a line is selected**: cancels the selection without affecting the expression.
- **Any other key while selected**: cancels the selection, then applies the key normally.
- Evaluating an expression (ENTER from live input) resets selection to nil (live input).
- The blinking block cursor is hidden while scrolling through history.

State: `computeHistoryLine: Int?` — nil = live input; even value = result line, odd = expression line, counted from the bottom of history.

### Implicit Ans prefix

Typing a binary operator (`+`, `−`, `*`, `/`, `^`) into an empty expression prepends `ans` automatically. The display shows e.g. `ans+2`, matching TI-84 CE behavior for result chaining. Pressing ENTER evaluates it using the previous answer.

---

## 2026-08-28 (MODE screen — full TI-84 CE MODE menu)

### MODE screen (MODE key)

The `mode` key (previously toggled angle mode directly) now opens a **full TI-84 CE MODE screen** matching all 15 rows of the physical calculator.

| Row | Label | Options | State property |
|---|---|---|---|
| 0 | — | MATHPRINT / CLASSIC | `calcDisplayFormat` |
| 1 | — | NORMAL / SCI / ENG | `calcNumberNotation` (persisted) |
| 2 | — | FLOAT / 0–9 | `calcNumberPrecision` -1=Float (persisted) |
| 3 | — | RADIAN / DEGREE | `angleMode` (existing, persisted) |
| 4 | — | FUNCTION / PARAMETRIC / POLAR / SEQ | `calcGraphType` |
| 5 | — | THICK / DOT-THICK / THIN / DOT-THIN | `calcDrawMode` |
| 6 | — | SEQUENTIAL / SIMUL | `calcEvalOrder` |
| 7 | — | REAL / a+bi / re^(θi) | `calcComplexMode` |
| 8 | — | FULL / HORIZONTAL / GRAPH-TABLE | `calcScreenLayout` |
| 9 | FRACTION TYPE: | n/d / Un/d | `calcFractionType` |
| 10 | ANSWERS: | AUTO / DEC | `calcAnswerMode` |
| 11 | STAT DIAGNOSTICS: | OFF / ON | `calcStatDiagnostics` (Bool) |
| 12 | STAT WIZARDS: | ON / OFF | `calcStatWizards` (Bool) |
| 13 | SET CLOCK | — | display only |
| 14 | LANGUAGE: ENGLISH | — | display only |

**Interaction:** Selected option shown with **inverted** (black bg / white text) highlighting. Current row has subtle tint background. Options are directly tappable. UP/DOWN arrow navigates rows; LEFT/RIGHT cycles the selected option; ENTER confirms and advances to next row; CLEAR exits to home screen.

**Number notation (rows 1–2)** is live: the HOME screen status bar shows the current `NORMAL`/`SCI`/`ENG` and `FLOAT`/`0`–`9` values, and all compute results respect them via `CalculatorResultFormatter.string(for:notation:precision:)`.

### New enums (CalculatorState.swift)

```swift
CalcDisplayFormat:  mathprint / classic
CalcNumberNotation: normal / sci / eng  (persisted UserDefaults)
CalcGraphType:      function / parametric / polar / seq
CalcDrawMode:       thick / dotThick / thin / dotThin
CalcEvalOrder:      sequential / simul
CalcComplexMode:    real / abi / polar
CalcScreenLayout:   full / horizontal / graphTable
CalcFractionType:   nd / und
CalcAnswerMode:     auto / dec
```

`calcNumberNotation` and `calcNumberPrecision` are the only two that persist (they affect compute output directly). The rest are stored in-memory (visual/graph features not yet driven by them).

### Files changed

- `Calculator/CalculatorState.swift` — 9 new enums, `modeMenuRow`, 9 mode state vars, 2 persisted vars + UserDefaults keys
- `Calculator/CalculatorView.swift` — `showModeMenu`, `handleModeMenuNavigation`, `handleModeMenuKey`, `stepModeOption`, `CalculatorModeMenuScreen` struct; routing in `handleNavigation`, `handleCalculatorScreenKey`, `screenContent`; `mode` key repurposed from direct angle toggle to opening MODE screen

---

## 2026-08-28 (CALC menu — 2nd+TRACE graph analysis)

### CALC menu (2nd + TRACE)

Pressing `2nd` then `TRACE` opens the **CALCULATE** menu overlaid on the calculator screen. 7 items:

| # | Name | Implementation |
|---|---|---|
| 1 | value | Full — cursor-only, computes Y at cursor X |
| 2 | zero | Full — left bound → right bound → guess → Brent's method |
| 3 | minimum | Full — left bound → right bound → guess → Golden Section Search |
| 4 | maximum | Full — same as minimum, inverted |
| 5 | intersect | Full — 1st Curve? → 2nd Curve? → Guess? → Brent's method on f1−f2 |
| 6 | dy/dx | Full — cursor-only, central-difference derivative |
| 7 | ∫f(x)dx | Full — left bound → right bound → Simpson's rule (n=1000) |

Menu pre-highlights **3:minimum** on open. Digits 1–7 select directly; UP/DOWN arrow navigates rows; ENTER confirms selection; CLEAR exits.

#### 5: intersect workflow

Intersect uses the same three phases as min/max/zero but with a different meaning:

1. **1st Curve?** — cursor moves with LEFT/RIGHT (snapped to curve 1). UP/DOWN cycles through enabled equations to pick the first curve. The current curve name (Y1, Y2…) is shown in the prompt overlay. ENTER locks curve 1 selection.
2. **2nd Curve?** — same for the second curve. Auto-advances to the next equation on entry. ENTER locks curve 2.
3. **Guess?** — cursor moves near the expected intersection. ENTER triggers computation.

**Algorithm:** Brent's method applied to `g(x) = f1(x) − f2(x)` over the full visible x-range `[xMin, xMax]`. Includes the 200-subinterval sign-change scan, so it finds any intersection in the visible window regardless of where the guess lands. Result label: "Intersection".

State additions: `calcToolCurveIndex1`, `calcToolCurveIndex2` (indices into the enabled-equation array).

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
