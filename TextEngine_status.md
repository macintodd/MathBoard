# Text Engine — Status

Standalone, previewable rich-text + LaTeX editor for the MathBoard whiteboard.
Prototype / decoupled stage. **Not integrated** with the canvas, ToolPalette,
`CanvasTextObject`, or the current Text tool — integration is a later pass.

## Purpose

Provide a polished, word-processor-style modal text editor that:

- edits plain text with lightweight inline markup (bold / italic / underline),
- detects and live-previews LaTeX regions wrapped in `$$ … $$`,
- returns a self-owned `TextEditorResult` value that a future Coordinator can
  translate into the app's canvas text object — without TextEngine ever
  importing `CanvasTextObject`.

## Architectural boundaries

- **Isolated module.** All code lives in `MathBoardCore/Sources/TextEngine/`.
- **Zero app dependencies.** Registered as a standalone, self-contained SPM
  target in `MathBoardCore/Package.swift`. It has no dependency on `MathBoard.app`
  or any other MathBoardCore module, and nothing links it.
- **Exposed as a library product.** `TextEngine` is also declared as a `.library`
  product in `Package.swift` — *only* so Xcode generates a `TextEngine` scheme
  that builds the target for SwiftUI previews. The product is not linked by the
  app, so isolation is preserved. (Same pattern as `WidgetEngine`.)
- **Own result model.** `TextEditorResult` is TextEngine's own type. It carries
  everything a Coordinator needs (source text, font size, font name, formatting
  flags, markup convention, detected LaTeX regions) but never references the
  app's `CanvasTextObject`.

## Files created

| File | Responsibility |
| --- | --- |
| `TextEditorResult.swift` | TextEngine-owned models: `TextEditorResult` (the Save payload), `DetectedLaTeXRegion` (a `$$…$$` region with character offsets), `TextMarkupConvention` (documents how inline formatting is encoded), and `DetectedLaTeXRegion.detect(in:)` — the shared regex-based region detector. |
| `TextEditorViewModel.swift` | `@Observable` state (`text`, `isBold`, `isItalic`, `isUnderline`, `fontSize`, `fontName`), placeholder font list, computed `detectedLaTeXRegions` and `result`, and editing helpers (`toggleBold`/`toggleItalic`/`toggleUnderline`/`insertMathMode`) that wrap the selection or insert placeholder markup. |
| `TextEditorModalView.swift` | Large modal editor: top Cancel/Save bar, `TextEditor` with live `TextSelection`, live LaTeX preview pane, and a bottom formatting toolbar (Bold, Italic, Underline, font menu, size slider, Math). Returns `TextEditorResult` through an `onSave` closure. |
| `LaTeXPreviewView.swift` | Auxiliary view that detects `$$…$$` regions in a `source` string and renders each in a small "math card". The actual typesetting is done by a private `EquationRenderer` seam backed by **SwiftUIMath** (native, offline). Cards lay out in a horizontal scroll row so each stays fully visible. |

## Package.swift changes

Added a `TextEngine` target and a matching `TextEngine` library product,
mirroring the `WidgetEngine` setup, plus **one package dependency** used only by
`TextEngine`:

```swift
.library(name: "TextEngine", targets: ["TextEngine"])   // product (previews only)
...
dependencies: [
    .package(url: "https://github.com/gonzalezreal/swiftui-math", from: "0.1.0")
],
...
.target(name: "TextEngine", dependencies: [
    .product(name: "SwiftUIMath", package: "swiftui-math")
])
```

Nothing else in the package depends on `TextEngine`, and the app target does not
link it, so the module stays fully isolated. Note: adding the package makes SPM
resolve `swiftui-math` for the whole package graph (its only extra dependency is
the test-only `swift-snapshot-testing`), but only `TextEngine` links it.

## Markup convention

Formatting is stored as in-text markup (not an attributed string) so the source
stays portable. Convention `markdownWithHTMLUnderlineAndDollarMath`:

- **Bold** → Markdown `**bold**`
- **Italic** → Markdown `*italic*`
- **Underline** → HTML-style `<u>underline</u>` (underline is not standard Markdown)
- **Math** → `$$ … $$` LaTeX regions

## Selected-range editing

SwiftUI's `TextEditor(text:selection:)` with a `TextSelection?` binding *is*
available on this deployment target (iOS 26 / macOS 26), so editing is
selection-aware:

- **Non-empty selection** → the selected span is wrapped in markers.
- **Caret (empty selection)** → a wrapped placeholder is inserted at the caret.
- **No selection info** → a wrapped placeholder is appended at the end.

The modal view translates `TextSelection.indices` (`.selection(Range<String.Index>)`
/ `.multiSelection(RangeSet<String.Index>)`) into a `Range<String.Index>` and hands
it to the view model's helpers. After each edit the selection binding is reset,
since the previous indices are no longer valid against the mutated text.

## LaTeX preview strategy

**Now — native offline renderer (SwiftUIMath).** `LaTeXPreviewView` scans for
`$$…$$` regions and typesets each one with **SwiftUIMath** — a native, vector,
fully offline SwiftUI LaTeX renderer (no CDN MathJax, no `WKWebView`, no network).
Native rendering is also the most preview-reliable option.

**Isolated behind one seam.** All SwiftUIMath usage lives in a single private
view, `EquationRenderer`, inside `LaTeXPreviewView.swift`:

```swift
private struct EquationRenderer: View {
    let latex: String
    var body: some View {
        Math(latex)
            .mathTypesettingStyle(.display)
            .mathFont(Math.Font(name: .latinModern, size: 22))
    }
}
```

Nothing else in TextEngine references SwiftUIMath. To swap renderers later (e.g.
if SwiftUIMath doesn't cover enough LaTeX for classroom use), change only
`EquationRenderer`'s body — `LaTeXPreviewView`'s public surface (`init(source:)`)
and the detection logic stay the same.

**Raw-text fallback.** SwiftUIMath's `Math` view silently draws *nothing* for
LaTeX it can't parse (its parser returns nil). `EquationRenderer` guards against
blank cards by measuring first via `Math.typographicBounds(...)` (exposed through
`@_spi(Textual) import SwiftUIMath`): a zero width means it won't typeset, so the
card shows the **raw LaTeX source** plus a small ⚠︎ marker instead. The SPI hook
is the only public way to detect renderability; it is pre-1.0 API, and all use is
contained in `EquationRenderer`.

## How to open the Xcode previews

1. In Xcode, select the **`TextEngine`** scheme (generated from the new library
   product). The app scheme does **not** build this target — trying to preview
   under it gives *"…not found in any targets / must belong to at least one
   target in the current scheme"* (confirmed during validation).
2. Open any of these files and use the canvas / preview:
   - `TextEditorModalView.swift` → **"Empty editor"**, **"Seeded with math"**
   - `LaTeXPreviewView.swift` → **"With equation"**, **"Multiple equations"**, **"No math"**

## Known limitations

- The plain `TextEditor` shows **raw markup** (e.g. `**bold**`, `<u>…</u>`,
  `$$…$$`). It is not a true rich-text/WYSIWYG surface yet; the font-size, bold,
  and italic toggles restyle the whole editor, and underline is not visually
  applied inline (only the `<u>` markers are inserted).
- The `isBold`/`isItalic`/`isUnderline` toggles represent block-level intent that
  flows into `TextEditorResult`; they always insert markers when tapped and do
  not "un-wrap" an existing span.
- Font choices (`System` / `Serif` / `Monospaced` / `Rounded`) are placeholders
  mapped to `Font.Design`; there is no real font-family picker yet.
- LaTeX is now typeset by **SwiftUIMath v0.1.0** — a pre-1.0 library, so its API
  may shift and it may not support every LaTeX construct needed for classroom
  use. It renders math-mode LaTeX only; invalid/unsupported input shows the
  library's own error/fallback. Mitigation: all usage is isolated in
  `EquationRenderer` so it can be replaced.
- `$$…$$` detection is non-nested and non-escaping (a literal `\$\$` is not
  special-cased); empty `$$$$` regions are ignored.

## Future integration (later pass)

- Add a **Coordinator/adaptor** (outside TextEngine) that converts a
  `TextEditorResult` into the app's `CanvasTextObject` — mapping `sourceText`,
  `fontSize`, `fontName`, and the formatting flags, and deciding how detected
  LaTeX regions are placed/rendered on the canvas.
- Present `TextEditorModalView` from the whiteboard Text tool, wiring `onSave`
  to that Coordinator and `onCancel` to dismissal.
- Swap the offline LaTeX card for a local renderer (bundled MathJax in
  `WKWebView` or native), keeping detection unchanged.

## Session log

- **2026-07-02** — Initial module created.
  - Added `TextEngine` target + library product to `MathBoardCore/Package.swift`.
  - Created `TextEditorResult.swift`, `TextEditorViewModel.swift`,
    `TextEditorModalView.swift`, `LaTeXPreviewView.swift`.
  - **Validation:** App project builds successfully (`BuildProject`, ~27s, no
    errors). All four TextEngine files report **no** compiler diagnostics via
    per-file code-issue checks (fixed one issue: moved the detection `Regex`
    literal from a non-`Sendable` static property into the function body).
    Preview *rendering* under the app scheme fails by design (target not in that
    scheme) — previews must be opened under the `TextEngine` scheme in Xcode.
  - No existing app / canvas / ToolPalette code was modified.
- **2026-07-02** — Modal layout tweaks (from preview feedback).
  - Moved the formatting toolbar to the **top** of the editor (directly under the
    Cancel/Save bar, above the `TextEditor`) instead of the bottom.
  - Collapsed the toolbar to a single row: `B I U | font | Math` on the left, a
    **short (150 pt) size slider** + `pt` readout pushed to the right.
  - **Decision:** the LaTeX preview keeps the **offline placeholder** card (shows
    the equation source) for now — a preview reviewer read the raw-source card as
    "not rendering." True typesetting (bundled MathJax / native renderer) is
    deferred to the integration pass; detection + card chrome are unchanged.
  - `TextEditorModalView.swift` reports no compiler diagnostics after the change.
- **2026-07-02** — Compact preview cards + landscape + windowed-presentation demo.
  - `LaTeXPreviewView` now lays each equation out as a **small, fixed-width
    (220 pt) card** in a **horizontal scroll row** (with an `EQ n` tag), so every
    card stays fully visible as more equations are added — the previous vertical
    stack clipped lower cards inside the modal's bounded preview pane.
  - Modal `previewPane` no longer wraps the preview in a vertical `ScrollView`
    (cards scroll horizontally now) and sizes to its content.
  - Added `traits: .landscapeLeft` to the modal previews.
  - Added a **"As a floating window"** preview demonstrating the intended
    integration look: the editor as a rounded, shadowed, centered window over a
    dimmed stand-in canvas. Confirms the modal can be hosted as a windowed sheet
    with the app faded behind it — the scrim/framing is the host's job; the modal
    just fills whatever frame it's given. Both files: no diagnostics.
- **2026-07-02** — Real LaTeX rendering via SwiftUIMath.
  - Added `https://github.com/gonzalezreal/swiftui-math` (`SwiftUIMath` product)
    as a dependency of the `TextEngine` target in `Package.swift`. Chosen over
    SwiftMath because it is SwiftUI-native (a `Math` view, no
    `UIViewRepresentable` wrapper), native/vector, and fully offline.
  - Replaced the placeholder card content with typeset math, isolated behind a
    new private `EquationRenderer` seam in `LaTeXPreviewView.swift` (per review
    guidance: keep the renderer swappable behind `LaTeXPreviewView`).
  - **Validation:** `BuildProject` succeeded after SPM resolved the new package
    (first attempt returned the transient "model objects have changed — build
    again" notice; the immediate rebuild passed). `LaTeXPreviewView.swift`
    reports no compiler diagnostics, confirming the SwiftUIMath API usage
    (`Math`, `.mathTypesettingStyle(.display)`, `.mathFont(.init(name:size:))`).
    Visual typesetting is best confirmed by opening the previews under the
    `TextEngine` scheme.
- **2026-07-02** — Raw-LaTeX fallback + font-size presets.
  - `EquationRenderer` now measures with `Math.typographicBounds` (`@_spi(Textual)`)
    and, when SwiftUIMath can't parse an equation, shows the **raw source + a ⚠︎
    marker** instead of a blank card. New preview: "Invalid LaTeX falls back to raw".
  - Added **font-size preset buttons** (10, 11, 12, 25, 50) to the top toolbar,
    next to the Math button (`TextEditorViewModel.presetFontSizes`). Tapping one
    sets `fontSize`; the slider follows (both bound to the same value), and the
    active preset highlights.
  - **Validation:** `BuildProject` succeeded; `LaTeXPreviewView.swift`,
    `TextEditorModalView.swift`, and `TextEditorViewModel.swift` all report no
    compiler diagnostics.
