# Presentation

## Purpose
Presentation orchestration layer that mounts canvas experiences across iPad/external-display contexts.

## Responsibilities
- Broker display routing and presentation context.
- Host and compose canvas-centered presentation surfaces.
- Provide viewfinder and external-canvas presentation overlays.
- Bridge presentation-level tool palette and embedded module mounts.

## Key Files
- `PresentingCanvasView.swift`
- `ExternalCanvasView.swift`
- `DisplayBroker.swift`
- `ViewfinderOverlay.swift` / `ToolPaletteSettings.swift`

## Dependencies
- Internal module dependencies: `Canvas`, `Calculator`, `GraphCalculator`, `Library`, `LiveClassroom`, `TextEngine`, `ToolPalette`, `WidgetEngine`.
- External package dependencies: none (direct).

## Integration Status
- Core integration target between feature modules and rendered teaching surfaces.
