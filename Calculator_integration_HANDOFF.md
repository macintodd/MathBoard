# Calculator Integration — AI Handoff

**Read this, then `Calculator_integration.md` (full steps), then `Calculator_status.md` (module detail). Do NOT review the rest of the codebase to "understand it" — read only the files you are about to edit.**

## Situation
The `Calculator` SwiftUI module is **built, isolated, and tested (114/114 passing)**. It is **NOT yet connected** to the MathBoard app. The remaining task is integration only — no new calculator features.

## The module (all in `MathBoardCore/Sources/Calculator/`)
- `CalculatorView(state:)` — interactive draggable palette (compute + graph). Put on iPad canvas.
- `CalculatorTVOverlay(state:referenceSize:)` — read-only mirror. Put on external display.
- `CalculatorState.shared` — `@MainActor @Observable` singleton. On/off = `.isVisible` (not persisted; opens closed). Bridges iPad↔TV scenes automatically (same process), exactly like `DisplayBroker.shared`.

## Integration = 4 edits (all in `Calculator_integration.md`, copy-pasteable)
1. **`MathBoardCore/Package.swift`**: make `Presentation` target depend on `"Calculator"`. (Safe with Xcode open — NOT a pbxproj edit.)
2. **`DisplayBroker.swift`**: add `public var calculatorReferenceSize: CGSize?`.
3. **`PresentingCanvasView.swift`**: `import Calculator`; overlay `CalculatorView` in the ZStack when `isVisible`; publish container size to broker via background `GeometryReader`; add a `function` toolbar button toggling `CalculatorState.shared.isVisible`.
4. **`ExternalCanvasView.swift`**: `import Calculator`; overlay `CalculatorTVOverlay(state:.shared, referenceSize: broker.calculatorReferenceSize ?? fitted)` inside the existing `fitted`-rect ZStack.

## CRITICAL process rules
- **Re-read the 3 target files IN FULL before editing them** (`PresentingCanvasView`, `ExternalCanvasView`, `DisplayBroker`). They were modified by the user/linter after the handoff doc was written — do not trust the doc's snippets verbatim; match the CURRENT code structure.
- **Verify build** via the `xcode-tools` `BuildProject` MCP tool after edits.
- Calculator module unit tests run via:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path /Users/macminim4/Documents/Develop/MathBoard/MathBoardCore --filter CalculatorTests --build-path /tmp/MathBoardCore-calc-build`
- **pbxproj must NEVER be edited while Xcode is open** (crashes Xcode). Package.swift is fine.
- After it builds, update `Calculator_status.md` (header + session log) and `Project_status.md`.

## Two things only the USER's hardware can confirm (flag these to the user, don't assume)
1. **Pencil hit-test**: with palette open, Apple Pencil must draw on canvas everywhere EXCEPT under the palette card. If ink bleeds through, fix belongs in the Calculator module (give the card an opaque hit-testing background), not in MathBoard.
2. **TV live update**: `CalculatorTVOverlay` must re-render on the external display when the iPad mutates `CalculatorState.shared`. Cross-scene SwiftUI observation has been fragile in this project historically — test on real iPad+TV.

## Done means
Build clean on iPad + Mac; user confirms on hardware: toggle works, drag+clamp works, persistence works, mode switch works, pencil hit-test correct, TV mirrors live. Then mark v1 integrated in both status docs.

## Deferred (do NOT build now — see `Calculator_status.md` §6)
Snapshot-to-canvas (needs image-object layer), multiple curves, sliders, polar/parametric, resize.

---

## VERIFIED CURRENT-STATE NOTES (files read 2026-06-26 — exact, use these)

**All 4 target files were read fresh. Findings below override the doc snippets where they differ.**

### `Package.swift` (current)
Line 35 is exactly: `.target(name: "Calculator"),`
Change line 29 to: `.target(name: "Presentation", dependencies: ["Canvas", "Calculator"]),`
(Leave the `Calculator` target + its testTarget as-is. Don't add a new product.)

### `DisplayBroker.swift` (current)
`@MainActor @Observable public final class DisplayBroker`, `import CoreGraphics` already present. Add after line 53 (`isExternalDisplayConnected`):
```swift
/// iPad canvas container size the calculator palette position is measured in.
public var calculatorReferenceSize: CGSize?
```

### `PresentingCanvasView.swift` (current — IT HAS EVOLVED)
- Now also wires undo/redo: `@State editCommand`, `@State editState`, and the `CanvasView(...)` call includes `editCommand:` and `onEditStateChange: publishEditState`. **Keep all of that.** Just add the calculator alongside.
- `import Canvas` is there; ADD `import Calculator`.
- Add stored prop near line 30: `private let calculator = CalculatorState.shared`
- Body is `ZStack { CanvasView(...) ; ViewfinderOverlay()... }` (lines 51–67). Add inside the ZStack after ViewfinderOverlay:
  ```swift
  if calculator.isVisible {
      CalculatorView(state: calculator)
  }
  ```
- Publish container size: add `.background(GeometryReader { p in Color.clear.onAppear { broker.calculatorReferenceSize = p.size }.onChange(of: p.size) { _, s in broker.calculatorReferenceSize = s } })` to the ZStack (after `.ignoresSafeArea(edges: .bottom)` on line 68).
- Toolbar: there is one `if broker.isExternalDisplayConnected` ToolbarItem, one big `ToolbarItemGroup(.secondaryAction)` (undo/redo/zoom/fit/reset, lines 77–122), and one `ToolbarItem(.secondaryAction)` for present/mirror (124–134). Add a new `ToolbarItem(placement: .secondaryAction)` with the `function`-icon button toggling `calculator.isVisible`.

### `ExternalCanvasView.swift` (current — confirmed unchanged)
Body: `GeometryReader { proxy in ZStack { Color.black; if let frame = broker.currentFrame { let fitted = Self.fittedSize(...); ZStack { Image(decorative: frame...); if let liveStroke... { LiveStrokeOverlay(...) } }.frame(width: fitted.width, height: fitted.height).clipped() } else { ExternalDisplayPlaceholder() } } }`.
- ADD `import Calculator`.
- Inside the inner `ZStack` (the one with `.frame(width: fitted.width, height: fitted.height)`), after the LiveStrokeOverlay, add:
  ```swift
  CalculatorTVOverlay(state: .shared, referenceSize: broker.calculatorReferenceSize ?? fitted)
  ```

### Order of operations next session
1. Apply Package.swift line 29 edit. 2. DisplayBroker prop. 3. PresentingCanvasView edits. 4. ExternalCanvasView edit. 5. `BuildProject` (MCP) → fix any compile errors. 6. Run CalculatorTests (cmd above) to confirm module still green. 7. Tell user to test on hardware (pencil hit-test + TV live update). 8. Update both status docs.
