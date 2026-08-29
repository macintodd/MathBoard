# Mathtivity Schema Redesign

## Decision

MathBoard Mathtivities should be authored as JSON documents that configure trusted native renderers. We should not add new one-off SwiftUI-coded Mathtivities as first-class library items. The previous Inequality Explorer built-in is a legacy path and should be replaced by JSON-authored activities using reusable schema parts.

This gives us one durable format for authoring, catalog delivery, classroom assignment, student rendering, scoring, and future web participation.

## Core Model

A Mathtivity remains an `ActivityWidgetDocument`:

- `activity`: the outer question flow, currently `multipleChoice` or `fillInTheBlank`.
- `questions`: prompts, expressions, choices/blanks, feedback, and optional interactive parts.
- `interactiveParts`: reusable native modules configured by JSON and rendered by MathBoard.

The JSON describes intent and settings. Swift owns rendering, hit-testing, persistence, scoring, accessibility, and classroom sync.

## Interactive Parts

### Number Line

Use for inequality, compound inequality, interval, absolute-value inequality, ordering, and graph-from-symbol tasks.

Initial schema shape:

```json
{
  "type": "numberLine",
  "id": "solution-line",
  "domain": { "min": -10, "max": 10, "step": 1 },
  "features": {
    "pointsTappable": true,
    "pointsDraggable": true,
    "raysEnabled": true,
    "segmentsEnabled": true,
    "openClosedEndpoints": true,
    "pointHasRay": true,
    "maxPoints": 2,
    "labelsVisible": true,
    "snapToTicks": true
  },
  "initialResponse": {
    "rays": [
      { "endpoint": 1, "direction": "right", "isClosed": false }
    ]
  },
  "answer": {
    "segments": [
      { "start": -2, "end": 5, "startClosed": false, "endClosed": true }
    ]
  }
}
```

Number-line graph state supports:

- `selectedPoints`: legacy closed points, kept for compatibility.
- `points`: explicit open/closed points.
- `rays`: half-infinite solution sets, such as `x > 1` or `x <= 5`.
- `segments`: bounded intervals, such as `-2 < x <= 5`.
- `initialResponse`: an authored graph rendered before student interaction. This lets schema authors use the number line as a prompt, as an answer choice, or as the starting state for an editable response.
- `answer`: the scorable expected graph state.

Multiple number lines in one question are represented as multiple `numberLine` interactive parts with distinct IDs. That covers side-by-side AND/OR graphing tasks, three-choice graph comparisons, and compound-inequality practice without a separate SwiftUI widget.

Editable number lines are object-based, not mode-based. A student taps a point to place or select it. If `pointHasRay` and `raysEnabled` are true, the selected point exposes left/right ray handles; dragging a handle turns the selected point into a ray endpoint. If `segmentsEnabled` is true and the student taps a second endpoint on the same side as the selected ray, the ray is replaced by a bounded segment. `maxPoints` limits how many anchors the student can create, so simple inequalities can stay one-endpoint tasks while compound inequalities can allow two endpoints. When `openClosedEndpoints` is true, tapping an already-selected point, ray endpoint, or segment endpoint toggles it between open and closed — no separate button is shown.

### Coordinate Plane

Use for graphing lines, systems, transformations, quadratic features, coordinate geometry, and quadrant-limited graph tasks. Prefer one configurable coordinate-plane renderer over separate full-plane and quadrant-one implementations.

Initial schema shape:

```json
{
  "type": "coordinatePlane",
  "id": "graph",
  "domain": {
    "xMin": -10,
    "xMax": 10,
    "yMin": -10,
    "yMax": 10,
    "xStep": 1,
    "yStep": 1
  },
  "features": {
    "pointsTappable": true,
    "pointsDraggable": true,
    "linesEnabled": true,
    "segmentsEnabled": true,
    "raysEnabled": false,
    "parabolasEnabled": false,
    "labelsVisible": true,
    "snapToGrid": true
  }
}
```

A quadrant-one graph is just a coordinate plane with nonnegative bounds, for example `xMin: 0`, `xMax: 10`, `yMin: 0`, `yMax: 10`.

## Scoring Direction

Interactive parts write part responses into `WidgetActivityRuntimeState`, then produce the same `WidgetActivityScoreRecord` used by current JSON activities and live classroom reporting.

Scoring rules should stay declarative where possible:

- selected points
- dragged points
- open/closed endpoints
- rays/segments
- graph objects
- equivalent accepted solution sets

The native scorer should normalize mathematically equivalent answers before scoring. For example, a compound inequality graph and interval notation should be compared as solution sets, not as raw gestures.

## Migration Plan

1. Stop creating new built-in SwiftUI Mathtivity library items.
2. Add JSON schema support for `interactiveParts`.
3. Render number-line and coordinate-plane parts as trusted native modules inside existing JSON activity flows.
4. Add part runtime state and student response persistence.
5. Add scoring adapters from part state to `WidgetActivityScoreRecord`.
6. Rebuild Inequality Explorer as JSON activities that use `numberLine` parts.
7. Remove the legacy built-in renderer only after existing documents no longer need it.

## Graph Utility Direction

A future authoring helper can parse compact algebraic notation such as `linearGraphUtility{x>1}`, `linearGraphUtility{x<=5}`, or `linearGraphUtility{-2<x<=5}` and compile it into the same `initialResponse` / `answer` graph state. This keeps the app schema explicit and durable while letting lesson authors write graph answers in a faster, math-native shorthand.

The utility should emit JSON primitives rather than become a second runtime renderer. Examples:

- `x > 1` compiles to one right ray with endpoint `1` and `isClosed: false`.
- `x <= 5` compiles to one left ray with endpoint `5` and `isClosed: true`.
- `-2 < x <= 5` compiles to one segment from `-2` to `5`, open on the left and closed on the right.
- `x = 3` or `3 = x` compiles to one closed point.

Current parser scope is intentionally narrow: one-variable `x` comparisons with numeric constants, using `<`, `<=`, `>`, `>=`, `=`, or the Unicode `≤` / `≥` forms. Utility strings are accepted anywhere the number-line schema expects `initialResponse` or `answer`.

## Current Implementation Slice

The first slice supports schema decoding and validation for `numberLine` and `coordinatePlane` interactive parts. The second slice adds tappable `numberLine` runtime responses, optional declarative number-line answers, and score-record integration. The current number-line slice adds authored `initialResponse` graphs, explicit open/closed points, rays, bounded segments, `linearGraphUtility{...}` shorthand compilation, and point-first editing with ray handles. Open/closed toggling is now tap-driven: a second tap on an already-selected endpoint toggles it between open and closed; the separate button has been removed. Endpoint dots are 20pt diameter: closed endpoints are a solid filled circle; open endpoints are a stroke-only ring with no white fill. The selection overlay circle has been removed — selection is indicated by the ray handles appearing, not by a separate ring. Touch target is value-based and unchanged. Coordinate-plane parts still render read-only; coordinate response capture/scoring remains a future slice.

Per-question scoring and a deliberate retry flow are live for number-line questions. When the student taps Check, the renderer scores the actual graph against the `answer` field using the same `matches()` normalization as the live classroom score record.

**First pass:** Correct → question locks, streak increments, celebration fires. Incorrect → question locks, contextual feedback from the JSON `incorrectFeedback` field is shown (e.g. "Strict inequalities use open points"), Next enables, question is queued in Retry Missed.

**Retry Missed:** The student returns to each missed question and sees their original graph. Hints are hidden. Controls show Retry + Skip. Pressing Retry resets the graph to `initialResponse` (or blank) and switches to Check + Next. Pressing Skip records a skip (`skippedRetryQuestionIDs`) with no additional score penalty. After the retry round, first-pass and correction scores are captured separately in `numberCorrectFirstTry` and `numberCorrectAfterRetry`.

Bundled number-line examples now cover graph-to-algebra matching, student graphing of simple inequalities, compound-inequality segments, static graph-choice comparison, and absolute-value inequalities converted to interval graphs.

The current schema does not yet have a dedicated pre-question splash modal. Larger synthesis checks should use the description, prompt, and hints for now; a future slice can add an optional `introCard` / `workRequiredPrompt` field if those checks become common.
