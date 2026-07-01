# Widget Engine — Status

Interactive HTML/JS widget engine for the MathBoard whiteboard. Prototype stage.

## Architecture

- **Isolated module.** All code lives in `MathBoardCore/Sources/WidgetEngine/`.
- **Zero app dependencies.** Registered as a standalone, self-contained SPM
  target in `MathBoardCore/Package.swift`. It has no dependency on `MathBoard.app`
  or any other MathBoardCore module, and nothing links it.
- **Exposed as a library product.** `WidgetEngine` is also declared as a
  `.library` product in `Package.swift` — *only* so Xcode generates a
  `WidgetEngine` scheme that builds the target for SwiftUI previews. The product
  is not linked by the app, so isolation is preserved.
- **Coordinator later.** Wiring widgets onto the real canvas / document state is
  deferred; `MathBoardObject` is the intended bridge point.

## Files

| File | Responsibility |
| --- | --- |
| `WidgetContract.swift` | `MathBoardObject` protocol (`id`, `frame`), `WidgetObject` value type (`name`, `codeString`), the boilerplate AI prompt, and the default sample widget (an interactive "factor the trinomial" activity used by previews / `WidgetObject.sample`). |
| `WidgetEditorView.swift` | Authoring UI: read-only boilerplate prompt, Copy Template button, editable code field, live `WKWebView` preview. |
| `WidgetContainerView.swift` | Floating widget object with draggable header + bottom-right resize handle; also hosts the cross-platform `WidgetWebView` (`WKWebView`) wrapper. |

## Behavior notes

- `WidgetWebView` wraps `WKWebView` for both iOS and macOS and reloads only when
  the HTML source actually changes (avoids reload thrash while typing).
- `WidgetContainerView` owns its own position/size state (`frame`), independent
  of the main canvas. Origin stays fixed during resize so the box grows toward
  the bottom-right handle.

## Previews

Select the **`WidgetEngine`** scheme in Xcode before previewing (the app scheme
does not build this target, which otherwise gives "Active scheme does not build
this file"). Available previews:

- `WidgetEditorView` → "Widget Editor"
- `WidgetContainerView` → "Widget Container" (floating on a whiteboard backdrop)

## Next steps

- Coordinator to place `WidgetObject`s on the canvas and persist them.
- Sandbox/security review of arbitrary pasted HTML/JS before any real use.
