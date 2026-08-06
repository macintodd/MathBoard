# WidgetEngine

## Purpose
Self-contained interactive widget framework for MathBoard, with JSON-authored widgets and native activity rendering.

## Responsibilities
- Define widget contracts, schema validation, and JSON repair helpers.
- Render native widget/activity experiences and container surfaces.
- Manage widget runtime state, theming, and score aggregation models.
- Provide editor/scratchpad/sample workflows for widget authoring.

## Key Files
- `WidgetSchema.swift` / `WidgetContract.swift`
- `WidgetActivitySchema.swift` / `WidgetActivityRenderer.swift` / `WidgetActivityRuntimeState.swift`
- `WidgetNativeRenderer.swift` / `WidgetContainerView.swift`
- `WidgetEditorView.swift` / `WidgetSamples.swift` / `WidgetScratchpad.swift`

## Dependencies
- Internal module dependencies: none.
- External package dependencies: `SwiftUIMath`.

## Integration Status
- Isolated package product and preview scheme.
- Used by `Canvas`, `Presentation`, `Slides`, `Documents`, and `Library`.
- Architecture/status notes: `WidgetEngine_status.md`, `WidgetActivityArchitecture_status.md`.
