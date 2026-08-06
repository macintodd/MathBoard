# TextEngine

## Purpose
Standalone rich-text and LaTeX editor module for math text authoring and preview.

## Responsibilities
- Provide editor state/result models for text authoring.
- Render text/LaTeX editing surfaces and modal editor flows.
- Render native LaTeX previews from editor content.

## Key Files
- `TextEditorViewModel.swift` / `TextEditorResult.swift`
- `TextEditorModalView.swift` / `TextEditorView.swift`
- `LaTeXEditorView.swift` / `LaTeXPreviewView.swift`

## Dependencies
- Internal module dependencies: none.
- External package dependencies: `SwiftUIMath`.

## Integration Status
- Exposed as independent product/scheme; mounted by `Presentation` as an adapter client.
