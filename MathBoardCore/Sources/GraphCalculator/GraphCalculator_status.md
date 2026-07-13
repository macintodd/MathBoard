# GraphCalculator Status

## Product Goal

Build a native, Desmos-style teaching graph calculator for MathBoard. The calculator should let a teacher demonstrate the same keystrokes and visual outcomes students see when using Desmos in class.

Primary goal:

- If a student presses the same sequence of calculator keys in MathBoard and in Desmos, the visible expression row, graph behavior, numeric result, and error feedback should be close enough for classroom instruction.

Non-goals for now:

- Do not replace the existing TI-style Calculator.
- Do not depend on Desmos/WKWebView unless the project later explicitly chooses that route.
- Do not optimize for advanced CAS behavior before Algebra 1 / Algebra 2 teaching workflows are solid.

Architecture rules for future agents:

- Keep all GraphCalculator-specific code isolated under `MathBoardCore/Sources/GraphCalculator`.
- The only current app integration is the `graphCalc` test mount in `PresentingCanvasView`.
- Prefer extending the existing native `Calculator` engine/AST over adding a third-party evaluator unless a dependency clearly solves Desmos-like visual behavior, not just numeric evaluation.
- Update this file after each meaningful implementation pass.

Acceptance standard:

- The calculator must build.
- The in-app `graphCalc` menu item must remain usable.
- Expression rows must preserve what the student typed, even when invalid.
- Invalid rows should not crash or disappear; they should show row-level feedback.

## 2026-07-06

Created an isolated `GraphCalculator` package target and product under `MathBoardCore/Sources/GraphCalculator`.

Continuation pass in progress:

- Working through the parity list systematically.
- Current focus is making expression rows behave more like Desmos before adding deeper graphing features.
- Status will be updated after each completed implementation step so another agent can continue without reverse-engineering the intent.
- Completed dynamic expression-row behavior:
  - expression list now scrolls vertically,
  - row count grows beyond three rows,
  - a blank next row is always available for entry,
  - left/right keypad arrows move row focus,
  - row delete removes the row while preserving at least one editable row.
- Completed first-pass math-style row display:
  - row display now renders parser text in a more classroom-friendly form for powers, roots, inequalities, multiplication, division, and pi,
  - formatting is visual-only; stored expressions remain plain text for the native parser.
- Completed first-pass relation plotting:
  - `y=...` rows are treated as explicit curve rows,
  - `y<...`, `y<=...`, `y>...`, and `y>=...` rows shade above/below the boundary,
  - strict inequalities use a dashed boundary,
  - reversed forms such as `x+1<y` are interpreted as y-relations,
  - `x=constant` draws a vertical line.
- Completed first-pass editable cursor behavior:
  - state now tracks a cursor offset for the selected expression row,
  - keypad insertion and delete occur at the cursor,
  - selected row renders a visible blue cursor,
  - left/right keypad arrows move the cursor inside the active expression.
- Completed first-pass table support:
  - toolbar has a table toggle,
  - table panel shows x/y values for the selected y-function or y-relation,
  - current table evaluates at x values `-2`, `-1`, `0`, `1`, and `2`,
  - vertical-line rows show a clear "Select a y-function" placeholder instead of failing.
- Completed first-pass slider support:
  - expressions are scanned for simple single-letter classroom variables such as `m`, `b`, `a`, and `c`,
  - compact sliders appear below the expression/table panel when those variables are present,
  - slider values feed graph rendering, table evaluation, and scalar display evaluation,
  - common implicit products like `mx+b` are normalized internally to `m*x+b` while preserving the typed row.
- Completed first-pass `funcs` keypad behavior:
  - `funcs` opens a touch panel in the expression area instead of adding row-navigation controls,
  - panel inserts common Desmos-style functions at the active row cursor: `sin(`, `cos(`, `tan(`, `log(`, `ln(`, `sqrt(`, `abs(`, and `pi`,
  - selecting a function closes the panel and preserves normal row-tap editing.
- Completed improved visual-token pass:
  - exponent display now handles multi-digit, signed, and parenthesized exponents such as `x^10`, `x^-1`, and `x^(2+1)`,
  - `theta` displays as `θ`,
  - keypad comma key was replaced with an `a/b` template key that inserts `()/()` for quick fraction-style entry.
- Completed broader x-relation plotting:
  - `x=...`, `x<...`, `x<=...`, `x>...`, and `x>=...` use a dedicated x-relation plot type,
  - x-inequalities shade left or right of the vertical boundary,
  - strict x-inequalities use dashed boundaries,
  - reversed forms such as `3<x` are interpreted correctly.
- Completed editable table x-values:
  - table x-values are stored in `GraphCalculatorState`,
  - teacher can add a new x-row with the table plus button,
  - each x-value has touch minus/plus controls for stepping by 1,
  - table rows can be removed while preserving at least one x-row,
  - y-values recalculate from the selected expression using slider values.
- Completed Desmos-style add menu and data-set table pass:
  - toolbar plus now opens an add menu instead of immediately adding a function row,
  - add menu can create a function row, data table, or folder placeholder,
  - data tables default to `x_1` and `x_2` and display as `x₁` and `x₂`,
  - data tables support up to four columns total: one input column and three output columns,
  - data-table numeric cells are editable,
  - graph renders ordered-pair points using column 1 as input and each remaining column as output.
- Completed richer `funcs` library pass:
  - function menu now has Basic, Trig, Stats, and Algebra 2 groups,
  - each group exposes eight touch items,
  - Stats table item creates a data table,
  - Algebra 2 templates include line, quadratic, cubic, vertex, exponential, root, log-base, and piece starter entries.
- Confirmed Desmos-style row selection rule:
  - row selection remains touch-driven,
  - no explicit up/down row controls were added,
  - keypad arrows remain cursor controls inside the active expression.
- Completed improved fraction-display pass:
  - `()/()` displays as `□⁄□`,
  - typed fractions such as `1/2` display with a fraction slash as `1⁄2`,
  - expression storage remains parser-friendly plain text.
- Completed direct numeric editing for compact value-table x-values:
  - compact value table x-cells are now editable text fields,
  - plus/minus stepping remains available.
- Completed data-table editing polish pass:
  - data-set table rows can be deleted,
  - data-table headers display subscripted trailing numbers such as `x₁₂`,
  - output columns already graph with distinct palette colors.
- Completed graph detach/controller split pass:
  - graph eject now separates the graph into its own draggable/resizable graph window,
  - the equations, expression panels, toolbar, and keypad become a separate draggable controller surface,
  - docking the graph returns to the single connected calculator layout,
  - graph size is preserved while detached instead of being reset on every eject.
- Completed graph/window drag fix pass:
  - the connected graphCalc calculator can now be dragged as one unit from its top bar,
  - detached graph and detached equations/keypad controller dragging now use their top bars so movement works in both x and y directions without fighting graph panning or row editing,
  - detached graph resize grip now takes priority over window dragging and resizes width and height together from the bottom-right corner.
- Completed app-mount drag-space fix:
  - `PresentingCanvasView` now mounts `GraphCalculatorView` as a full-canvas overlay instead of a `460 x 820` local frame,
  - this gives the connected calculator, detached graph, and detached controller the full canvas bounds for x/y dragging,
  - the visible calculator panel keeps its own internal size; only the overlay drag coordinate space changed.
- Completed drag-performance refinement:
  - connected calculator, detached graph, detached controller, and detached graph resize now use transient local view state during live drags,
  - `GraphCalculatorState` position/size values are committed only when the gesture ends,
  - live drag updates explicitly disable implicit animation to reduce jitter and finger lag.
- Completed second drag-performance refinement:
  - live panel movement now changes transient `.offset` transforms instead of changing `.position` layout values on every drag tick,
  - connected calculator, detached graph, and detached controller are composited so child views and shadows move as one rendered surface.
- Completed lightweight drag-proxy pass:
  - connected calculator, detached graph, and detached controller now dim the expensive live panel during drag,
  - a lightweight proxy view follows the finger during the live gesture,
  - the real panel commits to the proxy's final center when the drag ends.
- Completed external-display mirror pass:
  - `DisplayBroker` now owns shared graphCalc visibility and `GraphCalculatorState`,
  - `PresentingCanvasView` renders the iPad graphCalc from broker state,
  - `ExternalCanvasView` renders a non-interactive, scaled graphCalc overlay from the same broker state,
  - TV rendering uses the iPad canvas reference size so detached graph/controller positions match the teacher screen instead of being recomputed in TV-only coordinates.
- Completed Present-mode TV alignment fix:
  - external graphCalc overlay now uses the full iPad reference rect in Mirror mode,
  - in Present mode it uses the same centered 16:9 viewfinder rect that the red bounds show on the iPad,
  - the TV transform subtracts the viewfinder origin before scaling so graphCalc aligns with the visible present area like handwriting does.
- Completed TV edge-safe graphCalc adjustment:
  - external graphCalc scaling now uses a small safe reference inset so a calculator pushed flush to the iPad's right edge is not clipped by the TV frame,
  - this is TV-only and does not change iPad dragging/clamping behavior.
- Completed graph control relocation pass:
  - graph eject moved from the graph zoom stack to a red control in the lower-right corner of the graph,
  - the toolbar's former table button now hides/shows the keypad,
  - the toolbar's former hide-keypad button now reconnects a detached graph,
  - the old toolbar table toggle was removed because data tables are now added from the plus menu.
- Completed expression graph-style control pass:
  - expression graph color dots now live inside the row-number cell,
  - long-pressing a row color dot opens a style popover,
  - style popover includes a rainbow hue slider with labeled color stops,
  - style popover includes a stepped line-width slider from thin to classroom-bold,
  - graph rendering now uses each expression row's custom hue and line width when set.
- Completed expression style polish pass:
  - expression row numbers were removed because they are not needed for this teaching workflow,
  - larger color circles now fill the left row cell,
  - color-stop labels are touchable and snap the hue slider to Red, Green, Blue, or Indigo,
  - line-width labels are touchable and snap to Thin, Medium, or Bold,
  - maximum bold line width increased by 50% for stronger TV visibility.
- Completed keypad alignment and zoom-limit pass:
  - keypad columns now use shared fixed metrics so the left white key block and right keypad block align row-to-row,
  - wide keys now span exactly two normal key columns,
  - fraction key now uses a stacked fraction glyph instead of `a/b`,
  - `ABC` label uses a smaller font,
  - keys now use a skeuomorphic pressed keycap style,
  - GraphCalculator zoom is clamped to reasonable min/max spans without changing the shared TI calculator graph geometry.
- Completed alphabet/special keypad pass:
  - `ABC` now switches from the number keypad to an alphabet keypad,
  - alphabet keypad includes curly braces, factorial, underscore, comma, cursor movement, delete, and stacked fraction,
  - `123` returns to the number keypad,
  - number keypad fraction key was replaced with comma for ordered-pair entry.
- Completed defensive cursor-index crash guard:
  - expression insert/delete now clamp stale cursor offsets before indexing strings,
  - selected-row display splitting now uses a safe fallback index,
  - this targets the `String index is out of bounds` crash seen while testing keyboard/fraction entry.
- Completed function-notation keypad and resolver pass:
  - `f(x)` key keeps normal tap insertion of `f(`,
  - long-press menu on `f(x)` can insert `g(` or `h(`,
  - valid function definitions use one-letter names and one-letter input variables, such as `k(h)=h^2+a`,
  - function definitions graph over `x` regardless of their named input variable, so `g(k)=5k` plots like `g(x)=5x`,
  - defined functions can reference earlier/later defined functions, so `h(t)=g(t)+4` resolves through `g`,
  - function names are reserved and cannot be reused as input variables in other function definitions,
  - `y(...)` is rejected with a row-level error because `y` is reserved for graph relations,
  - slider scanning ignores defined function names, function-call names, and function-definition input variables,
  - adjacent implicit products such as `ah` and `mx` still create sliders for free non-input variables.
- Completed slider-default initialization pass:
  - newly detected slider variables now default to `0` before graph evaluation,
  - graph rendering, table evaluation, and resolved expression rows now use a zero-filled slider dictionary instead of raw missing slider values,
  - this fixes rows such as `h(m)=3m+b` disappearing after `+b` is typed and before the `b` slider is touched.
- Completed first-pass slider decision workflow:
  - new free variables in graphable rows now prompt with a yes/no choice before becoming sliders,
  - choosing yes creates an inline slider directly under the equation row that introduced the variable,
  - choosing no leaves the variable unresolved, prevents that row from graphing, and marks the row color cell with a red X,
  - scalar definition rows such as `k=5` now define variables for other rows and do not graph as horizontal curves,
  - previously unresolved rows such as `g(h)=5h+k` graph again once `k` is later defined or approved as a slider.
- Completed slider prompt scope and endpoint pass:
  - plain incomplete entries such as `p` or `p(v` no longer trigger the slider prompt,
  - slider prompts are limited to completed function definitions and `y` relation rows,
  - row error text now says `Define p` for non-slider-eligible rows and only mentions sliders for eligible rows,
  - sliders now default to a `-5` to `5` range,
  - each inline slider shows tappable minimum and maximum endpoint labels that can be edited,
  - changing a slider endpoint clamps the current slider value into the new range.
- Completed y-relation slider-scope refinement:
  - y-inequality rows such as `y<mx+b`, `y<=a*x+c`, and reversed forms like `mx+b<y` now participate in slider prompting,
  - x-only relations such as `x<k` do not trigger slider prompts,
  - incomplete function typing such as `p(v` remains prompt-free.
- Completed ordered-pair/table/zoom pass:
  - expression rows now graph numeric ordered pairs such as `(3,5)`, `(3, 5)`, and `(-2.5, 4)`,
  - ordered pairs render as graph points using the row color and line-width style,
  - new data tables now default to columns `x_1` and `y_1`,
  - new data tables now start with blank rows so students enter their own data before points appear,
  - add-table output now visually lives in the expression-list cell system with a row-style color cell instead of as a loose card,
  - table column values continue graphing as ordered-pair points,
  - pinch zoom now uses the graph window from the start of the gesture and damps magnification so small finger spreads do not zoom too far too quickly.

Current behavior:

- Desmos-inspired teaching calculator layout with:
  - dark MathBoard-style top bar,
  - graph canvas,
  - expression rows,
  - built-in keypad.
- Graph supports panning, pinch zoom, plus/minus zoom buttons, and reset-window gear.
- Graph zoom has GraphCalculator-local min/max limits to prevent runaway zoom-in or zoom-out.
- Graph eject is a red lower-right graph control positioned above the toolbar controls.
- Expression row color dots fill the left row cells and can be long-pressed to adjust graph color and line width.
- Expressions plot through the existing `Calculator` expression engine.
- Function notation is supported for teaching entry: definitions such as `f(x)=x^2` and calls such as `f(3)` are recognized.
- Function definitions graph over `x` even when the input variable is named something else.
- Free variables in function definitions, such as `b` in `h(m)=3m+b`, create sliders initialized to `0` and graph immediately.
- New free variables now ask before becoming sliders; denied variables keep their rows ungraphable until a scalar definition such as `k=5` exists.
- Slider prompts are intentionally limited to complete `y=`/`y<...` style rows and complete function-definition rows such as `g(h)=5h+k`.
- Plain partial typing such as `p` or `p(v` only leaves the row invalid with an X marker; it does not interrupt with a prompt.
- Inline slider endpoints default to `-5` and `5` and can be edited by tapping the endpoint labels.
- Numeric ordered-pair rows such as `(3,5)` graph directly as points.
- Add-table creates an expression-list table cell with blank `x_1` and `y_1` columns, and entered column values graph as points.
- Pinch zoom is intentionally slowed and uses a stable gesture-start window to avoid compounding zoom jumps.
- The keypad has an `f(x)` key in place of the speaker-style key from the reference. It inserts `f(`, and long-press offers `g(` and `h(`.
- Keypad uses a narrower fixed grid with skeuomorphic press feedback and aligned wide keys.
- `ABC` opens an alphabet/special-key keypad, and `123` returns to numeric entry.
- Cursor-based expression edits clamp stale offsets before string indexing.
- `funcs` is intentionally a placeholder button for now.
- Eject button detaches the graph into a separate draggable/resizable graph window.
- While detached, the equation rows and keypad are shown as a separate draggable controller panel.
- Connected and detached calculator surfaces drag from their top bars.
- In-app `graphCalc` uses the full canvas as its drag/resize coordinate space.
- Live dragging avoids per-frame observable model writes; persisted positions update when the gesture ends.
- Live panel dragging uses transform offsets during the gesture, then commits the final center.
- Dragging now uses a lightweight proxy so the heavy graph/expression UI does not repaint continuously while moving.
- `graphCalc` is visible on the external display when it is visible on the iPad.
- External `graphCalc` is read-only and scaled from the iPad canvas coordinate space.
- In Present mode, external `graphCalc` is crop-aware and aligns to the iPad viewfinder bounds instead of the full iPad screen bounds.
- External `graphCalc` has a small edge-safe scale adjustment so far-right placement remains fully visible on the TV.
- `GraphCalculatorView.preview()` and `#Preview` entries render the calculator directly in Xcode.
- Added `GraphCalculatorExpressionResolver`:
  - collects simple function definitions like `f(x)=x^2-4`,
  - expands calls like `f(x+1)` into graphable expressions,
  - resolves scalar rows like `f(3)` into display values,
  - returns row-level parse/evaluation errors without deleting student input.
- Expression rows now show:
  - curve color dots,
  - scalar values when an expression has no `x`,
  - red row-level error text for invalid expressions.
- Expression list is scrollable and dynamically grows as rows are added or selected.
- Expression row text displays first-pass math tokens such as `x²`, `√(`, `≤`, `≥`, `×`, `÷`, and `π`.
- Simple Desmos-style relation rows now render for `y=`, y-inequalities, reversed y-inequalities, and `x=constant`.
- Selected expression row supports cursor-positioned insertion and delete instead of append-only input.
- Selected y-function rows can be shown as a compact value table from the toolbar.
- Rows such as `y=mx+b` now prompt variable sliders and graph with the slider values.
- Row selection remains touch-driven like Desmos; keypad arrows are cursor controls, not row controls.
- The `funcs` key now opens a basic touch function menu.
- Expression rows now show richer superscript display for nested and signed powers.
- Simple x-relations and x-inequalities now render with vertical boundaries and Desmos-style shading.
- Table x-values are now teacher-adjustable by touch and persist in calculator state while the view is open.
- Toolbar plus opens a Desmos-style add menu for function, table, or folder.
- Toolbar keypad collapse is in the former table-button slot; the far-right toolbar button reconnects a detached graph.
- Added data-set tables for plotted ordered pairs; first column is input, later columns are outputs.
- The `funcs` menu now exposes grouped classroom-oriented function/template libraries.
- Compact value-table x-values can be edited directly or stepped.
- Data-set table rows can be deleted, and column headers display trailing numbers as subscripts.
- Fraction-like text now uses a fraction slash display while preserving parser input.
- Expression curves can use per-row custom hue and stroke width for better classroom visibility.
- Style popover labels snap directly to common color and line-width stops.

App test mount:

- `graphCalc` is available from the top-right MathBoard toolbar menu for in-app visual testing.
- This is a test mount only; it does not replace the existing TI-style Calculator button.
- The test mount now mirrors to the external display through shared `DisplayBroker` state.

Not integrated yet:

- Save, undo, redo, function library, and advanced expression templates are visual placeholders.
- Detached graph/controller layout is local to the prototype state and is not persisted across calculator launches.

## 2026-07-07

- Completed square-container styling pass:
  - the docked calculator panel, the detached graph container, and the detached control container now use plain rectangular backgrounds/borders instead of rounded corners,
  - small controls (keypad keys, Save button, function/add-menu buttons, slider endpoint chips) intentionally keep their existing rounding.
- Completed inline slider-creation redesign (replaces the full-screen slider Alert):
  - removed the modal "Make _ a slider?" Alert and its Yes/No/Cancel prompting lifecycle,
  - when a graphable row introduces a slider-eligible variable, an inline `create slider: [name]` prompt now appears directly beneath that equation,
  - the `[name]` is a tappable blue button; pressing it turns the variable into a slider immediately,
  - approved sliders now render in their own standalone "slider cell" that mirrors the equation-cell layout but has no color circle in the left gutter,
  - each slider cell shows `name = value`, the slider track, and tappable min/max endpoint chips,
  - a slider cell is owned by (rendered under) the lowest-index expression that references its variable,
  - removing a slider cell via its X fully clears the variable's slider state (value/min/max/decision) so the `create slider:` prompt returns,
  - added `GraphCalculatorState.removeSlider(named:)` for full slider teardown.

- Completed slider-prompt vs scalar-definition reconciliation:
  - `sliderPromptNames(forExpression:)` now intersects with `sliderCandidateNames`, which already excludes variables defined as scalars elsewhere,
  - so if a variable such as `k` is later defined in another row (e.g. `k=4`), the `create slider: k` prompt disappears and the equation graphs (the red X was already cleared by the resolver via `scalarVariableValues`),
  - deleting the definition (e.g. back to `k=`) makes `k` a candidate again, so the red X returns over the color cell and the `create slider: k` prompt reappears,
  - the pick-the-slider path is unchanged: approving the variable clears the red X and shows the slider cell.

- Completed keypad space-filling / larger-key pass:
  - the keypad now uses a `GeometryReader` to fill its entire fixed frame, eliminating the dark bands that previously showed above and below the keys,
  - key column width and row height are computed from the available keypad area (`keypadMetrics(for:)`), so keys grow to fill the space and the wide gray gap between the left function keys and the right number/operator keys collapses to a small group gap,
  - key glyph sizes scale with the larger keys via `keyFontSize(for:metrics:)`,
  - the overall calculator size is unchanged; only the internal key area was resized (the keypad frame is still 260pt tall / collapsible),
  - the ABC (alphabet) keypad uses the same larger metrics and is now staggered like a QWERTY keyboard (the `asdf` and `zxcv` rows are indented half/one key), filling the width instead of leaving a trailing gap,
  - removed the old fixed `keyColumnWidth`/`keyRowHeight`/`keySpacing`/`keyGroupSpacing` constants in favor of the computed `KeypadMetrics`.

- Completed slider-cell interaction pass:
  - the slider cell's left gutter now holds a play/pause button (no color swatch) that animates the slider value back and forth between its min and max on its own,
  - playback runs on a single `@MainActor` task loop (~30fps) shared by all playing sliders, reverses direction at each endpoint, auto-stops a slider that is removed or defined away, and is cancelled on view disappear,
  - the min/max endpoint values are now larger, tappable bubble buttons instead of tiny labels,
  - tapping an endpoint no longer opens a full-screen Alert with a text field and the system keyboard; instead the tapped value turns into an inline highlighted bubble (filled blue, white text, value pre-selected) edited directly with the calculator keypad,
  - keypad digits/`.`/`−` route into the bound editor while it is open (first press replaces the pre-selected value), `⌫` deletes within the bubble, and `↵` commits; tapping the bubble again or selecting another row also commits,
  - non-numeric keypad keys are ignored while editing a bound; removing the slider or switching rows cancels/commits the edit so the keypad returns to normal expression entry.
- Completed multi-variable slider recognition fix:
  - a single letter such as `f`, `g`, or `h` is no longer blanket-reserved in `GraphCalculatorVariableScanner.isSliderCandidate`,
  - those letters are still excluded when actually used as functions (via `functionNames` / `inputVariables` / `calledFunctionNames`), but a bare `h` used as a value is now slider-eligible,
  - so a function with two (or more) free variables, e.g. `f(x)=4x^2+k+h`, now offers `create slider: h  k` with an independent button per variable,
  - approving each variable produces its own standalone slider cell with its own play/pause button (the multi-cell / prompt plumbing already supported any number of variables; only the scanner's reservation was blocking the second offer).
- Completed resizable entry-panel-when-keypad-hidden pass (docked calculator):
  - when the keypad is hidden, the equation entry area expands into the space freed by the keypad so it fills to a clean bottom edge instead of ending in empty white space,
  - a grab handle (thin bordered strip with a capsule indicator) is drawn at the bottom edge of the entry area while the keypad is hidden; dragging it resizes the entry area within the freed space (clamped between the base height and base + full keypad height),
  - the expansion defaults to fully filled so the edge looks clean immediately; the chosen size is remembered while the calculator stays open,
  - showing the keypad again removes the handle and returns the entry area to its normal height, with the keypad covering the freed space as before,
  - scope is the docked calculator; the detached control panel already sizes itself to its content so it has no trailing white space to fix.
- Extended the resizable entry panel to the detached (disconnected-graph) control panel:
  - when the graph is detached and the keypad is hidden, the detached control panel now grows so its entry area expands into the freed keypad space (previously it just shrank and capped the entry at its base height),
  - the same bottom grab handle appears and shares the drag-adjustable amount with the docked calculator,
  - showing the keypad again returns the detached panel and its entry to their normal sizes.
- Completed graph-settings pass (gear panel + home button):
  - the toolbar gained a dedicated home button (house icon) that resets the graph zoom/window (previously the gear did this),
  - the gear button now toggles a "Graph Settings" panel in the entry area (mutually exclusive with the add/function/table panels),
  - the settings panel (scrollable) exposes: an axis-stroke-width slider, a gridline-thickness slider, a show-grid toggle, and x-axis / y-axis label text fields,
  - added matching state to `GraphCalculatorState` (`axisStrokeWidth`, `gridlineThickness`, `isGridVisible`, `xAxisLabel`, `yAxisLabel`, `isGraphSettingsVisible`),
  - added `GraphAxisStyle` to the renderer; `GraphCalculatorRenderer.draw` now takes an `axisStyle` and applies axis stroke width, gridline thickness, grid on/off, and draws the x/y axis titles near the axis ends,
  - the settings are wired live from state into the graph canvas, so changes update the graph immediately (and mirror to the external display since it renders the same view).
- Completed "pen & paper" (fountain-pen) graph aesthetic pass:
  - added a hand-drawn style (default on) rendered inside the existing SwiftUI `Canvas` — no separate engine/refactor,
  - `drawPaper` fills a warm off-white "bond paper" background and adds a faint grain built as a single filled speckle path (one fill call per frame, so it stays cheap during pan/zoom/animation),
  - function curves are stroked with a subtly variable width (`strokeInkRun` + `inkWidth`, ~±20% around the chosen line width) in short ~9px arc-length chunks to mimic a fountain-pen nib without per-pixel cost,
  - default stroke/row-dot color in this mode is rich dark gray ink (#2D2D2D), not pure black; per-row color and line-width controls still fully override it,
  - dashed strict-inequality boundaries keep constant width; shading/points/data tables unchanged,
  - added `GraphAxisStyle.handDrawn`, `GraphPaperPalette` (paper + ink), `GraphCalculatorState.isHandDrawnStyle`, a "Pen & paper style" toggle in the gear settings panel, and a paper-colored canvas background when enabled,
  - turning the toggle off restores the previous clean flat-white background and palette-colored constant-width vector lines.
- Completed grid-spacing fix and color restoration:
  - minor gridlines are now derived as `major / 5` (5 minor cells per major square) instead of an independently-computed "nice" step, so the grid is evenly spaced at all zoom levels (previously minor/major steps could mismatch, e.g. minor 2 under major 5, making the grid look irregular),
  - reverted the pen & paper default stroke color from mono ink back to the distinct palette colors so multiple graphs are distinguishable again (the pen texture / variable width / paper still apply); per-row color and width overrides unchanged,
  - row color dots again reflect the palette color, and `GraphPaperPalette.ink` was removed as unused.

Verification notes (2026-07-07):

- Full project build passed after the square-container styling pass.
- Xcode live diagnostics passed for `GraphCalculatorView` and `GraphCalculatorState` after the inline slider redesign.
- Full project build passed after the inline slider redesign.
- Preview render of `f(x)=4x^2+k` showed the inline `create slider: k` prompt beneath the equation.
- Preview render with `k` pre-approved showed a standalone `k = 1` slider cell (no color circle) beneath the equation, and the curve graphed correctly with `k` defined.
- Preview render of `f(x)=4x^2+k` with `k=4` in a second row showed no red X and no `create slider` prompt, and the parabola graphed.
- Preview render of the same with `k=` (value deleted) showed the red X and `create slider: k` prompt restored, and the parabola removed.
- Full project build passed after the slider-prompt/scalar-definition reconciliation.
- Preview render of the number keypad showed larger keys filling the full keypad area with no dark bands and only a small center group gap.
- Preview render of the ABC keypad showed larger, staggered QWERTY-style keys filling the area.
- Full project build passed after the keypad space-filling / larger-key pass.
- Preview render of a slider cell showed the play button in the gutter (no color swatch) and larger `−5` / `5` bound bubbles.
- Preview render with a bound in the editing state showed the tapped value as a filled-blue highlighted bubble alongside the calculator keypad.
- Full project build passed after the slider-cell interaction pass.
- Preview render of `f(x)=4x^2+k+h` showed `create slider: h  k` with both variables offered as separate buttons.
- Preview render with both `h` and `k` approved showed two separate slider cells, each with its own play button, and the parabola graphed.
- Full project build passed after the multi-variable slider recognition fix.
- Preview render with the keypad hidden showed the entry area expanded to fill the freed space with a grab handle at its clean bottom edge.
- Full project build passed after the resizable entry-panel-when-keypad-hidden pass.
- Preview render of the detached control panel with the keypad hidden showed the entry area expanded into the freed space with the grab handle at its bottom edge.
- Full project build passed after extending the resizable entry panel to the detached control panel.
- Preview render with the gear panel open showed the settings controls and the graph reflecting a bold axis (3.5), thick gridlines (2.0), and `time`/`height` axis labels.
- Preview render with the grid toggled off showed the gridlines removed while axes and labels remained, and confirmed the show-grid toggle and both label text fields.
- Full project build passed after the graph-settings pass.
- Preview render of `abs(x)` and a parabola in pen & paper mode showed off-white paper with faint grain, subtle grid, and dark variable-width ink strokes; row dots match the ink color.
- Full project build passed after the pen & paper aesthetic pass.
- Preview render confirmed evenly-spaced gridlines (5 minor per major) and three graphs in distinct palette colors (blue/red/green) with matching row dots on the paper background.
- Full project build passed after the grid-spacing fix and color restoration.

## 2026-07-12

- Completed first-pass tap-to-read x-intercepts:
  - the graph canvas now recognizes a tap (via `SpatialTapGesture`, added as a simultaneous gesture alongside pan/zoom so it does not interfere),
  - tapping on or near where a graphed curve crosses the x-axis shows that intercept's ordered pair, e.g. `(2, 0)`,
  - tapping elsewhere on the graph clears the readout,
  - intercepts are found by densely sampling each `y = f(x)` row (`.curve` and `y=` `.yRelation` rows) across the visible window, detecting sign changes, and refining each with bisection,
  - sign changes across asymptotes are rejected by requiring the refined value to be near zero (within 2% of the window height),
  - the nearest intercept within a 34pt screen tolerance is chosen when several are in range,
  - the readout is drawn by `GraphCalculatorRenderer` as a ringed dot in the owning row's color plus a colored ordered-pair label bubble that flips above/below the dot and clamps to the canvas width,
  - added `GraphCalculatorPointReadout` and `GraphCalculatorState.selectedPoint`; the marker mirrors to the external display because the TV renders the same shared state,
  - `GraphCalculatorRenderer.draw` gained an optional `highlightedPoint` parameter (defaulted, so no other call sites changed).
- Extended tap-to-read to y-intercepts:
  - tapping on or near where a curve crosses the y-axis now shows its ordered pair, e.g. `(0, -4)`,
  - the y-intercept is the single point `(0, f(0))` for each `y = f(x)` row, skipped when the curve is undefined at `x = 0`,
  - x-intercepts and the y-intercept are gathered as candidates per row and the nearest to the tap (within the 34pt tolerance) wins, so overlapping intercepts resolve to whichever the teacher tapped closest to,
  - refactored evaluation into a shared `evaluate(compiled:at:variableValues:)` helper used by both intercept paths.

Verification notes (2026-07-12):

- Xcode live diagnostics passed for `GraphCalculatorView`, `GraphCalculatorRenderer`, and `GraphCalculatorState` after the tap-to-read intercept pass.
- Full project build passed after the tap-to-read intercept pass.
- Xcode live diagnostics passed and full project build passed after adding the y-intercept readout.
- Fixed x-intercept marker accuracy:
  - the root finder previously accepted the first sample whose magnitude fell under a zoom-scaled tolerance, which biased the marker to the left (approaching) side of the true crossing, visibly off the line when zoomed in,
  - it now always bisects the bracketed sign change to the true root and only uses a tight magnitude check (`window.height * 1e-4`) to reject asymptote/discontinuity crossings,
  - the marker now sits centered on the line at the crossing.
- Full project build passed after the x-intercept accuracy fix.
- Added curve–curve intersection readouts:
  - tapping on or near where two graphed curves cross now shows that intersection's ordered pair, e.g. `(1.5, 2.25)`,
  - each `y = f(x)` row is compiled once per tap and reused for intercepts and intersections,
  - for each pair of curves the difference `f(x) − g(x)` is compiled and run through the same bisection root finder; the intersection y comes from evaluating the first curve at each root,
  - intersection markers use the neutral accent color (they belong to both curves), while intercepts keep their owning row's color,
  - x-intercepts, the y-intercept, and intersections are all gathered as candidates and the nearest to the tap (within the 34pt tolerance) wins.
- Full project build passed after the intersection readout pass.
- Made intersection points a celebratory "glowing dot":
  - `GraphCalculatorPointReadout` gained a `kind` (`.intercept` / `.intersection`); the tap handler tags intersections,
  - intersections now render in a warm gold (`GraphHighlightPalette.intersection`), distinct from every curve palette color, instead of the accent,
  - the marker is drawn with layered blurred halos (via a `.blur` filter on a copied `GraphicsContext`) plus a bright white core pip so it reads as lit,
  - the ordered-pair bubble for an intersection uses dark text on the gold fill for contrast; intercepts keep white text on their curve color,
  - intercepts are visually unchanged.
- Full project build passed after the glowing intersection marker pass.
- Gave each notable-point type its own glowing-dot color:
  - `GraphCalculatorPointReadout.Kind` split into `.xIntercept`, `.yIntercept`, and `.intersection`; the tap handler tags each candidate,
  - all three now render as glowing dots (blurred halos + white core pip), no longer just intersections,
  - colors are fixed per kind in `GraphHighlightPalette`: x-intercept = cyan/teal, y-intercept = violet, intersection = gold (they no longer borrow the curve's palette color),
  - label bubble text is dark on the bright gold intersection bubble and white on the cyan/violet intercept bubbles,
  - no animation, per request.
- Full project build passed after the per-kind glow-color pass.
- Added plotted-point tap readouts:
  - tapping on or near a typed ordered-pair row such as `(3,5)` now shows that point's ordered-pair label,
  - tapping on or near teacher-added points from a point row's floating table shows the same readout,
  - plotted points use their own coral glowing-dot color so they are distinct from x-intercepts, y-intercepts, and curve intersections,
  - plotted points participate in the same nearest-tap candidate selection as intercepts/intersections, so overlapping points resolve by touch proximity.
- Xcode live diagnostics passed for `GraphCalculatorView`, `GraphCalculatorRenderer`, and `GraphCalculatorState` after adding plotted-point tap readouts.
- Full project build passed after adding plotted-point tap readouts.

## 2026-07-12 (table feature rework)

Replaced the crowded inline-table behavior with per-row table icons that open a floating, draggable/resizable table window (one at a time), matching the graph-eject windowing style.

Decisions (confirmed with teacher): one table window open at a time; the old inline tables removed entirely; function-table x column auto-generated read-only from start/delta; external-display mirroring deferred.

- State (`GraphCalculatorState`):
  - added `GraphOrderedPair` (editable x/y, optional while typing), `GraphFunctionTableSettings` (start default 0, delta default 1), and `GraphActiveTable` (`.function` / `.points`, tied to the owning `GraphEquation.id`),
  - added `activeTable`, `tableWindowPosition`, `tableWindowSize`, `functionTableSettings[UUID]`, and `pointRows[UUID]` (extra points beyond the typed one),
  - helpers: `toggleTable`/`closeTable`, function-table start/delta setters (delta ≠ 0 guard), and add/update/delete for extra points,
  - table data is keyed by `GraphEquation.id` so nothing outside the GraphCalculator folder was touched (the model lives in the Calculator module).
- Equation rows:
  - each eligible row shows a table icon just left of the ✕ — a single-valued function of x (`.curve` / `y=` `.yRelation(.equal)`) gets a function table; an ordered `.point` gets a points table; inequalities/`x=` rows get none,
  - tapping the icon opens/closes that row's table window (opening one replaces any other),
  - a point row with attached extra points shows a trailing `…` ellipsis.
- Floating table window (reuses the drag-proxy/clamp/resize-grip infra):
  - menu bar with title, a settings gear (function tables only) or a `+` add button (points tables), and a close button; the bar is the drag handle,
  - function body: read-only `x | f(x)` generated as `start + n·delta`, evaluated through the engine with current slider/scalar values, lazy + scrollable,
  - points body: the typed pair as a shaded read-only first row, then editable `x | y` rows with delete and an "Add point" button,
  - gear popover edits table start and step (also seeds the future graph trace step).
- Graphing: teacher-added points plot via a new `attachedPoints` parameter on `GraphCalculatorRenderer.draw`, styled in the owning row's color/width.
- Removals: the + menu "Table" option, the funcs Stats "table" item, the inline `dataTableCard`/headers/value cells, the dormant compact `tablePanel`, and all `dataTables`/`tableXValues` state and `GraphCalculatorDataTable` (plus the renderer's `drawDataTables`).
- Added DEBUG previews for the function-table and points-table windows.

Deferred follow-ups: external-display mirroring of table windows.

## 2026-07-12 (graph trace)

Added finger-driven trace for function tables, wired to the table's start/delta so the traced points and the table rows stay in sync.

- A `scope` trace toggle sits in the function-table window menu bar (next to the gear). Turning it on puts the graph into trace mode; `GraphCalculatorState.isTraceActive` holds the mode and is reset whenever the table is closed or switched.
- While tracing, a finger tap or drag on the graph sets the table **start** value to the touched x (`setFunctionTableStart`), so the table regenerates live and the traced anchor sits under the finger. The table **delta** controls the spacing of the traced points. Panning is suppressed during trace; pinch-zoom still works; intercept taps are disabled (and the tapped-intercept readout is cleared).
- Rendering: `GraphCalculatorRenderer.draw` gained a `trace: GraphTraceOverlay?` parameter. The overlay draws a faint dashed vertical guide at the start x, a small dot at each table row along the curve (row color), and a larger ringed, labeled anchor marker at `(start, f(start))`. The ordered-pair label bubble was factored into a shared `drawLabelBubble` helper used by both the trace anchor and the tapped-point readout.
- The trace overlay is computed in the view from the same start/delta the function table shows, capped at 400 points and clipped to the visible x-range.
- Added a DEBUG "Trace" preview.
- Refined trace point-picking:
  - tapping near an already-shown trace point snaps the table start to that point, with closest visible point winning between points,
  - tapping near the first or last visible trace point chooses that endpoint instead of jumping past it,
  - tapping the curve away from visible trace points snaps the new table start to the precision implied by the table step (`step = 3` makes `x = 1.3` become start `1`; `step = 0.1` keeps `1.3`),
  - off-curve touches no longer move the table start,
  - x- and y-intercepts remain special readouts during trace mode and do not change the table start.
- Completed visible-row trace selection refinement:
  - trace dots now represent the function-table rows visible on the calculator screen instead of every in-window step along the graph,
  - the selected trace point can be any visible table point, not only the table-start point,
  - tapping a visible trace point shows its coordinate label without forcing that point to become row 1,
  - if the selected point is outside table slots 5-7, the table start recenters so the selected point lands back in slots 5-7,
  - tapping a non-shown point on the curve still follows the explicit start-reset rule from the prior pass,
  - off-curve drags in trace mode now fall through to normal graph panning, restoring pan while keeping trace movement on curve/point drags.
- Completed trace table highlight and row-size pass:
  - while trace is active, the function table highlights the row for the selected trace point,
  - the trace overlay now plots the same 10 function-table rows visible in the table body,
  - function-table value cells, point-table read-only cells, point edit fields, delete controls, and add-point rows use larger 44pt row heights,
  - table numbers use larger text with tighter horizontal padding and scaling so values still fit in the wider touch targets.
- Completed trace special-point highlight pass:
  - intersection readouts continue to use the same glowing-point renderer as x- and y-intercepts, with a warm gold intersection color,
  - trace-selected points are classified as x-intercepts, y-intercepts, or curve intersections when applicable,
  - trace-selected special points now render with the matching glowing marker instead of the plain trace marker,
  - the highlighted function-table row uses the matching notable-point color (teal x-intercept, violet y-intercept, gold intersection),
  - trace taps now route through trace selection so special points can still highlight the table row while tracing.
- Completed first-pass graph snapshot/photo feature:
  - the graph toolbar now has a camera button when `GraphCalculatorView` is mounted with a snapshot callback,
  - pressing it renders the graph-only view at high resolution using the same `GraphCalculatorRenderer` inputs as the live graph,
  - `GraphCalculatorSnapshot` carries PNG data and image size back to the presentation layer,
  - `CanvasObjectCommand` gained an `insertImage` action backed by the existing `CanvasImageObject` PNG persistence path,
  - `PresentingCanvasView` inserts the snapshot near the current visible canvas center and selects it so it can be moved/resized like other canvas images,
  - this reuses the existing image-object layer/persistence/selection system instead of adding a parallel image model.
- External-display reminder: verify trace snapping, shown-point selection, and special intercept readouts on the TV/external mirror after the next visual pass.

Verification notes (2026-07-12):

- Xcode live diagnostics passed for `GraphCalculatorState`, `GraphCalculatorRenderer`, and `GraphCalculatorView` after the trace pass.
- Full project build passed after the trace pass.
- Preview render of `y=x²-5` with trace on and start −3 / delta 1 showed dots at each table x along the parabola, a ringed `(−3, 4)` anchor with a dashed guide, and the table rows (−3→4, −2→−1, 0→−5, 3→4…) matching the on-curve dots exactly.
- Xcode live diagnostics passed for `GraphCalculatorState`, `GraphCalculatorRenderer`, and `GraphCalculatorView` after the trace point-picking refinement.
- Full project build passed after the trace point-picking refinement.
- Xcode live diagnostics passed for `GraphCalculatorState`, `GraphCalculatorRenderer`, and `GraphCalculatorView` after the visible-row trace selection and pan restoration pass.
- Full project build passed after the visible-row trace selection and pan restoration pass.
- Xcode live diagnostics passed for `GraphCalculatorState`, `GraphCalculatorRenderer`, and `GraphCalculatorView` after the trace table highlight and row-size pass.
- Full project build passed after the trace table highlight and row-size pass.
- Xcode live diagnostics passed for `GraphCalculatorView` and `GraphCalculatorRenderer` after the trace special-point highlight pass.
- Full project build passed after the trace special-point highlight pass.
- Xcode live diagnostics passed for `GraphCalculatorView`, `PresentingCanvasView`, `CanvasEditControls`, and `PencilKitCanvas` after the graph snapshot/photo feature pass.
- Full project build passed after the graph snapshot/photo feature pass.

Verification notes (2026-07-12):

- Xcode live diagnostics passed for `GraphCalculatorState`, `GraphCalculatorRenderer`, and `GraphCalculatorView` through every phase.
- Full project build passed after the table-window rework.
- Preview render confirmed the per-row table icon on function rows, the function-table window generating correct `x | f(x)` values for `y=x²-5` (0→−5, 1→−4, 2→−1, 3→4…), and the points-table window showing the typed pair plus editable added points with an "Add point" control.

## Engine / Behavior Direction

The goal for this tool is Desmos-style teaching behavior, not just raw expression evaluation. The important compatibility surface is:

- Keystroke result: the same button sequence should produce the same visible expression structure a student expects from Desmos.
- Visual graph response: valid lines, parabolas, function notation, points, tables, sliders, and errors should appear in a Desmos-like way.
- Classroom reliability: common Algebra 1 / Algebra 2 expressions should be deterministic, fast, and readable on the second display.

Current decision:

- Keep the native engine path for now rather than adding `peredaniel/MathExpression`.
- Reason: `MathExpression` is useful for arithmetic string-to-Double evaluation, but `GraphCalculator` needs a richer model: function definitions like `f(x)=...`, graphable relations, tables, sliders, visual tokens, and eventually Desmos-like errors.
- The existing `Calculator` module already has an AST, implicit multiplication, variables, graph geometry, evaluator hooks, and regression helpers. Extending that gives us more control over classroom-specific behavior and avoids a third-party dependency boundary that does not solve the visual-entry problem.

Near-term parity targets:

1. Desmos-style expression rows: active row, delete row, add row, focus behavior, and immediate graph update. Basic version exists; needs more polish and more than three visible rows.
2. Function notation: `f(x)=...`, `g(x)=...`, and calls like `f(3)` / `f(x+1)`. Basic single-letter, one-variable support exists.
3. Desmos-like visual errors: invalid expressions stay visible but do not plot, with clear row-level feedback. Basic support exists.
4. Algebra 2 graph support: linear, quadratic, cubic, quartic, absolute value, square root, exponential, logarithmic, trig, inequalities.
5. Tables and sliders after expression rows feel right.

Next recommended tasks:

1. Persist or restore the detached graph/controller layout if teachers expect the layout to survive closing/reopening the graphCalc tool.
2. Improve data-table active header editing so the visible formatted header and the edit field feel less layered.
3. Add regression helpers for data tables: linear, quadratic, cubic, and quartic fits from selected columns.
4. Add data-table column color swatches and visibility toggles.
5. Add more Algebra 2 templates and make placeholder cursor placement smarter after template insertion.
6. Add direct point labels/trace readouts for plotted data points.
7. Add save/undo/redo behavior for GraphCalculator-local edits.

Verification notes:

- Resolver check passed for `y<=x^2`, `x=3`, `x+1<y`, `f(x)=x^2-4`, and `f(3)`.
- Cursor state check passed for insert, move-left, move-right, and delete-at-cursor behavior.
- Xcode live diagnostics passed for table state and view changes.
- Slider variable check passed for `y=mx+b` with `m=2`, `b=-1`, and `x=3`, producing `5`.
- Xcode live diagnostics passed for first-pass `funcs` menu state and view changes.
- Display formatter check produced `x⁽²⁺¹⁾+θ¹⁰+π+x⁻¹` for `x^(2+1)+theta^10+pi+x^-1`.
- Full project build passed after the improved visual-token pass.
- X-relation resolver check passed for `x<3`, `x>=a`, and `3<x`.
- Full project build passed after x-relation plotting.
- Editable table state check passed for step, add, and delete behavior.
- Full project build passed after editable table x-values.
- Add-menu data-table check passed for default `x_1,x_2`, adding a third column, and editing a numeric cell.
- Full project build passed after Desmos-style add menu and data-set table plotting.
- Function menu grouping check passed: Basic, Trig, Stats, and Alg 2 each expose eight items.
- Full project build passed after richer `funcs` groups.
- Display formatter check passed for `□⁄□+1⁄2+x¹⁰` and `x₁₂`.
- Data-table row deletion and compact-table x editing state check passed.
- Full project build passed after row-selection confirmation, fraction display, compact-table numeric editing, and data-table row deletion.
- Xcode live diagnostics passed for detached GraphCalculator state/view changes.
- Full project build passed after graph detach/controller split.
- Xcode live diagnostics passed after docked drag, detached top-bar drag, and resize-priority fixes.
- Full project build passed after graph/window drag fix pass.
- Xcode live diagnostics passed for the `PresentingCanvasView` graphCalc mount change.
- Full project build passed after switching graphCalc to a full-canvas overlay mount.
- Xcode live diagnostics passed after transient local drag/resize state refinement.
- Full project build passed after drag-performance refinement.
- Xcode live diagnostics passed after transform-offset drag refinement.
- Full project build passed after transform-offset drag refinement.
- Xcode live diagnostics passed after lightweight drag-proxy implementation.
- Full project build passed after lightweight drag-proxy implementation.
- Xcode live diagnostics passed for `DisplayBroker`, `PresentingCanvasView`, and `ExternalCanvasView` external-display graphCalc integration.
- Full project build passed after external-display graphCalc integration.
- Xcode live diagnostics passed after Present-mode crop-aware graphCalc TV transform.
- Full project build passed after Present-mode crop-aware graphCalc TV transform.
- Xcode live diagnostics passed after TV edge-safe graphCalc scale adjustment.
- Full project build passed after TV edge-safe graphCalc scale adjustment.
- Xcode live diagnostics passed after graph control relocation.
- Full project build passed after graph control relocation.
- Xcode live diagnostics passed after expression graph-style controls.
- Full project build passed after expression graph-style controls.
- Xcode live diagnostics passed after expression style polish.
- Full project build passed after expression style polish.
- Xcode live diagnostics passed after keypad alignment and zoom-limit pass.
- Full project build passed after keypad alignment and zoom-limit pass.
- Xcode live diagnostics passed after alphabet/special keypad pass.
- Full project build passed after alphabet/special keypad pass.
- Xcode live diagnostics passed after defensive cursor-index crash guard.
- Full project build passed after defensive cursor-index crash guard.
- Function-notation check passed for `k(h)=h^2+a`, `k(3)`, and rejection of `y(x)=x^2`.
- Slider scanner check passed for `k(h)=ah+b`, `k(3)`, `y(x)=x^2`, and `p(q)=mq+b`, producing `a`, `b`, and `m`.
- Xcode live diagnostics passed after function-notation keypad and resolver pass.
- Full project build passed after function-notation keypad and resolver pass.
- Function-definition graphing check passed for `g(k)=5k`, `g(2)`, `h(t)=g(t)+4`, `h(2)`, and rejection of `p(g)=g+1`.
- Xcode live diagnostics passed after function definition graph substitution update.
- Full project build passed after function definition graph substitution update.
- Completed graph snapshot placement refinement:
  - graph snapshot insertions now pass the calculator's on-screen bounds to the canvas,
  - `PencilKitCanvas` places the static image in screen space beside the calculator on whichever side has more room, clamps it inside the visible iPad bounds, then converts it to canvas source coordinates at the current zoom,
  - graph photos default to a roughly 2-inch on-screen width at normal zoom while preserving graph aspect ratio.
- Xcode live diagnostics passed for graph snapshot placement changes.
- Full project build passed after graph snapshot placement changes.
- Completed calculator ellipsis display controls:
  - the top-bar `...` button now opens a compact graph display popover,
  - added an `Axis boldness` slider bound to the existing axis stroke width,
  - added a separate `Grid darkness` slider backed by new gridline opacity state so teachers can darken grid lines without changing grid thickness.
- Xcode live diagnostics passed for the graph display popover changes.
- Full project build passed after the graph display popover changes.
- Completed graph style default adjustment:
  - default equation graph line width increased from `3.0` to `4.5`,
  - maximum per-equation line width increased from `7.5` to `9.0`,
  - grid darkness slider maximum increased to `0.75`, with renderer clamping raised to support the darker range.
- Xcode live diagnostics passed for the graph style default adjustment.
- Full project build passed after the graph style default adjustment.
