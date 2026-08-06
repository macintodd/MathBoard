# Slides

## Purpose
Slide management module for per-lesson whiteboard pages, ordering, thumbnails, and PDF import/export workflows.

## Responsibilities
- Define slide metadata and navigation contracts.
- Manage slide persistence and ordering operations.
- Generate and cache slide thumbnails.
- Support PDF import preview and export selection flows.

## Key Files
- `SlideStore.swift`
- `SlideNavigator.swift` / `SlideNavigatorView.swift`
- `SlideThumbnailRenderer.swift` / `SlideFilmstripView.swift`
- `PDFImportPreviewView.swift` / `PDFExportSelectionView.swift` / `SlidePDFExporter.swift`

## Dependencies
- Internal module dependencies: `Library`, `LiveClassroom`, `Presentation`, `WidgetEngine`.
- External package dependencies: none.

## Integration Status
- Upstream dependency for `Documents`; central module for lesson-page workflows.
