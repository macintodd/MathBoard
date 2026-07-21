# Widget Engine — Status

Native schema-driven widget engine for the MathBoard whiteboard. Prototype stage.

## Current direction

The Widget Engine is moving away from raw pasted HTML/JS as the primary authoring
path. The selected direction is a **MathBoard Widget JSON** schema rendered by
native SwiftUI components.

The teacher workflow should become:

1. Copy an app-provided AI instruction prompt.
2. Add a plain-language widget request, such as "Make a basketball-themed
   factoring practice widget for Algebra 1."
3. Paste the returned Widget JSON into MathBoard.
4. Preview, validate, and later add the widget to the whiteboard canvas.

The teacher should not need to know schema details. The boilerplate prompt should
teach AI what components, actions, styles, and limits are allowed.

HTML/WKWebView remains available as an advanced experimental preview path, but it
is not the preferred direction for teacher-generated classroom widgets because
of security, reliability, and future data-collection concerns.

## Architecture

- **Isolated module.** All code lives in `MathBoardCore/Sources/WidgetEngine/`.
- **Zero app dependencies.** The target has no dependency on `MathBoard.app` or
  other MathBoardCore modules. Canvas integration is intentionally deferred.
- **Native renderer.** Widget JSON decodes into Swift model types and renders
  with SwiftUI. No arbitrary code is executed in the schema path.
- **Preview-first development.** `WidgetEditorView`, `WidgetNativeRenderer`, and
  `WidgetScratchpad` are used to iterate before wiring widgets into the app.
- **Coordinator later.** A future canvas coordinator should place widget objects
  on the whiteboard, persist their JSON/state, and provide any app services such
  as analytics or student-device sync.

## Current files

| File | Responsibility |
| --- | --- |
| `WidgetSchema.swift` | Codable schema model, JSON codec, validation. Current schema includes layout, text, numeric controls, choices, meters, hints, symbols, graphics, native graphs, feedback, scoring, expressions, conditions, and actions. |
| `WidgetNativeRenderer.swift` | Native SwiftUI renderer for Widget JSON. Owns preview-local state, feedback state, selected `numberBox`, digit-pad input, expression evaluation, drawing, graphing, and action execution. |
| `WidgetSamples.swift` | AI instruction prompt, sample widget document, sample JSON, and advanced HTML sample. The prompt must stay aligned with `WidgetSchema.swift`. |
| `WidgetScratchpad.swift` | Temporary local testing file. Paste generated Widget JSON inside `widgetJSON` and preview this file directly. |
| `WidgetEditorView.swift` | Standalone authoring UI with Widget JSON and advanced HTML modes, copy prompt button, paste support, validation, and previews. |
| `WidgetContainerView.swift` | Floating/resizable prototype container and `WidgetWebView` wrapper for the advanced HTML path. |
| `WidgetContract.swift` | Minimal bridge placeholders for future MathBoard object integration. |

## Current schema behavior

- `stack` supports vertical/horizontal layout.
- `grid` supports multi-column layout.
- `text` supports `title`, `subtitle`, `body`, `caption`, and `math` roles.
- `mathTemplate` supports algebraic answer-entry layouts that mix fixed math
  text with embedded number boxes. This should be used for factored forms,
  equations, parentheses, variables, operators, and other inline math blanks
  where plain horizontal stacks do not align well.
- Top-level `presentation` metadata supports preferred widget width/height and
  scroll behavior. Previews honor this so taller generated widgets are not
  forced into one default frame.
- `numberInput` supports normal system text entry.
- `numberBox` supports touch selection, optional label, shape, max length, and
  clear-on-select behavior.
- `digitPad` enters digits into the currently selected `numberBox`.
- `valueStepper` and `valueSlider` support bounded numeric state changes for
  graph parameters and transformations.
- `choiceGroup` supports selectable tiles/pills/buttons bound to state.
- `goalMeter` supports progress bars and radial meters.
- `hintProvider` reveals a bounded sequence of hints.
- `symbolCollection` renders controlled built-in symbols such as stars,
  basketballs, targets, coins, trophies, rockets, and checkmarks.
- `graphic` renders native graphic elements in normalized coordinates: line,
  arrow, point, label, parabola, absoluteValue, and built-in symbol.
- `nativeGraph` renders a coordinate plane with line, parabola, absoluteValue,
  and point elements. Graph parameters can be literal expressions or state-bound
  expressions.
- `button` runs allowlisted actions.
- `feedback` displays renderer-owned feedback messages.
- `score` displays a numeric state value.
- `divider` renders a visual separator.
- Expressions support literal values, state values, random integers, and binary
  math: add, subtract, multiply, divide, power, min, max.
- Conditions support equals, notEquals, greaterThan, lessThan,
  greaterThanOrEquals, and lessThanOrEquals.
- Actions include set, increment, showFeedback, clearFeedback, playAnimation,
  recordAttempt, if, and reset. `recordAttempt` is currently a preview no-op
  reserved for future app-level analytics.

Important enum distinction:

- Button styles: `primary`, `secondary`, `destructive`.
- Feedback styles: `neutral`, `success`, `warning`, `error`.
- AI has already confused these once, so the copy prompt and validator messages
  should keep this distinction explicit.

## Chosen guardrails

- Prefer native JSON widgets over arbitrary HTML/JS.
- Do not allow remote image URLs, network calls, raw JavaScript, SVG, CSS, or
  arbitrary code in the native schema path.
- Keep the schema expressive through reusable primitives, not many one-off
  classroom activities.
- Hide schema complexity from teachers; expose it to AI through the copy prompt.
- Add validation limits before real app integration: component count, nesting
  depth, text length, digit-pad count, graphic element count, and animation
  limits.

## Planned schema additions

These should be added gradually and validated carefully:

- Better graph labels, tick labels, and axis labels.
- More controlled built-in symbols/art where useful. Use app-defined symbols
  only, not external assets.
- More complete animation preset rendering. Current support is intentionally
  minimal and mostly feedback-oriented.
- Choice controls for multiple-choice or matching tasks.
- Matching/pairing components and drag-style manipulatives.
- Optional question/problem identifiers layered on top of existing metadata:
  `widgetId`, `learningObjective`, and `analytics.enabled`.

## Analytics / student data direction

Do not build full student data collection yet. It is a larger app architecture
feature involving identity, storage, sync, privacy, and teacher reporting.

However, the schema should remain compatible with future analytics:

- Use structured state rather than arbitrary code.
- Prefer stable state keys and eventual widget/question IDs.
- Later add a small app-controlled action such as `recordAttempt` or
  `recordAnswer`; it can be a no-op in previews until MathBoard app integration.
- Widgets should never talk directly to the network or other iPads. The app
  should own collection, storage, export, and sync.

## Integration path

Keep building and validating the Widget Engine inside `WidgetEngine` first. When
the schema and renderer feel stable:

1. Add a real widget canvas object type.
2. Wire the tool palette add button to create a widget object.
3. Render widgets as independent, resizable whiteboard objects above PencilKit.
4. Decide touch arbitration: PencilKit should not capture touches intended for
   an active widget.
5. Persist Widget JSON and widget state with the document/slide.
6. Mirror live widget rendering to the external display where appropriate.

Do not edit MathBoard app/canvas files for widget integration until explicitly
approved.

## Current risks

- AI can still produce invalid JSON or valid JSON with poor pedagogy/UX.
- The copy prompt must stay synchronized with the schema.
- Validation messages need to become teacher-friendly and specific.
- Sequential actions may surprise authors when later actions depend on newly
  assigned random state.
- Large widgets could hurt canvas performance; enforce size/complexity limits
  before app integration.
- The HTML/WKWebView path remains a security-sensitive advanced mode and should
  not be treated as the default teacher workflow.

## Previews

Select the **`WidgetEngine`** scheme in Xcode before previewing. Useful previews:

- `WidgetScratchpad` → "Widget Scratchpad"
- `WidgetEditorView` → "Widget Editor"
- `WidgetNativeRenderer` → "Native Widget"
- `WidgetContainerView` → "Widget Container"

## Next steps

- Improve validation errors for enum mismatches and invalid component fields.
- Add container decoration and simple native graphic primitives.
- Update the AI prompt after every schema addition.
- Add sample JSON that uses `numberBox` and `digitPad`.
- Prefer `mathTemplate` in generated factoring/equation widgets instead of
  manually composing separate text and number boxes in horizontal stacks.
- Include `presentation.preferredHeight` and `scroll: "enabled"` in generated
  widgets that contain digit pads, hints, graphs, meters, or several controls.
- Keep testing generated widgets in `WidgetScratchpad` before canvas integration.
