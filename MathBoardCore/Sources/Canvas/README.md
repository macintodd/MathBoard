# Canvas

## Purpose
Core drawing surface for MathBoard, including stroke/object rendering and canvas interaction primitives.

## Responsibilities
- Host PencilKit canvas behavior and macOS placeholder behavior.
- Render and manage canvas objects (ink, text, images, LaTeX, geometry, covers).
- Handle viewport controls, edit controls, object layering, and snapshots.
- Persist live ink and related canvas-side state.

## Key Files
- `CanvasView.swift` / `PencilKitCanvas.swift`
- `CanvasVectorInk.swift` / `CanvasLiveStroke.swift`
- `CanvasGeometryObject.swift` / `CanvasGeometryRenderer.swift`
- `CanvasTextObject.swift` / `CanvasImageObject.swift` / `CanvasLaTeXObject.swift`

## Dependencies
- Internal module dependencies: `WidgetEngine`.
- External package dependencies: `SwiftUIMath`.

## Integration Status
- Foundational module consumed by `LiveClassroom` and `Presentation`.
