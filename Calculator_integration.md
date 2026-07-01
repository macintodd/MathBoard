# Calculator — Integration Handoff

> How to wire the finished, isolated `Calculator` module into MathBoard. Nothing here has been applied yet — the calculator module is feature-complete and tested (114/114) but **not connected to the app**. Follow these steps when you're ready. Each step is small and reversible.
>
> Design reference: `Calculator_status.md` section 2 (locked-in decisions). App reference: `Project_status.md`.

---

## What the module gives you

Three public entry points, all driven by one shared `@MainActor @Observable` singleton `CalculatorState.shared`:

| Type | Where it goes | Role |
|---|---|---|
| `CalculatorView(state:)` | iPad canvas overlay | Interactive draggable palette (compute + graph) |
| `CalculatorTVOverlay(state:referenceSize:)` | External-display overlay | Read-only mirror at the matching relative position |
| `CalculatorState.shared` | Both scenes | Bridges iPad ↔ TV automatically (same singleton, same process) |

`CalculatorState.shared.isVisible` is the on/off switch. It is **not** persisted — the calculator opens closed every session — so a toolbar button just toggles it.

**Key point:** `CalculatorState.shared` works across UIScenes exactly like `DisplayBroker.shared` does. The external scene reads the same instance the iPad mutates, so mode / position / expression / window all mirror for free. The only thing the TV overlay can't infer on its own is the **iPad container size** the palette position was measured in — that one value is published through `DisplayBroker`.

---

## Step 0 — Link the module (Package.swift)

`Calculator` currently has no library product and nothing depends on it. The two views that host the calculator (`PresentingCanvasView`, `ExternalCanvasView`) live in the **Presentation** module, so make Presentation depend on Calculator.

In `MathBoardCore/Package.swift`:

```swift
.target(name: "Presentation", dependencies: ["Canvas", "Calculator"]),
```

No new library product is needed — Presentation is already linked transitively through `Documents`, so the app target sees the calculator types with no Xcode framework-link step. (This is the same pattern used when Slides/Presentation/Canvas were added.)

> This is a `Package.swift` edit. It is **not** a `.pbxproj` edit, so it's safe to do with Xcode open — Xcode re-resolves the package automatically.

---

## Step 1 — Publish the reference size (DisplayBroker)

The TV overlay needs the iPad canvas container size to place the calculator proportionally. Add one property to `DisplayBroker` (Presentation module):

```swift
/// Size of the iPad canvas container the calculator palette position is
/// measured in. Published by PresentingCanvasView; read by the external
/// scene to place CalculatorTVOverlay at the matching relative spot.
public var calculatorReferenceSize: CGSize?
```

(`DisplayBroker` already imports `CoreGraphics`.)

---

## Step 2 — iPad side (PresentingCanvasView)

Three small additions to `PresentingCanvasView` (Presentation module).

**2a. Import + observe the calculator state.** At the top:

```swift
import Calculator
```

and as a stored property next to `broker`:

```swift
private let calculator = CalculatorState.shared
```

**2b. Overlay the palette + publish the container size.** Wrap (or extend) the existing `ZStack { CanvasView … ; ViewfinderOverlay … }` so the calculator sits on top, and read the container size with a `GeometryReader`. The simplest shape:

```swift
ZStack {
    CanvasView( … )                 // unchanged
    ViewfinderOverlay()             // unchanged
        .opacity(broker.mode == .present ? 1 : 0)

    if calculator.isVisible {
        CalculatorView(state: calculator)   // draggable, positions itself
    }
}
.background(
    GeometryReader { proxy in
        Color.clear
            .onAppear { broker.calculatorReferenceSize = proxy.size }
            .onChange(of: proxy.size) { _, newSize in
                broker.calculatorReferenceSize = newSize
            }
    }
)
```

`CalculatorView` uses its own `GeometryReader` internally to position itself, so it just needs to be in the ZStack — it fills the container and places the 360×540 card at `state.position` (centered on first open).

**2c. Toolbar button to toggle it.** Add to the existing `.toolbar { … }`:

```swift
ToolbarItem(placement: .secondaryAction) {
    Button {
        calculator.isVisible.toggle()
    } label: {
        Label("Calculator", systemImage: "function")
    }
    .tint(calculator.isVisible ? .blue : nil)
}
```

That's the whole iPad integration. The palette opens/closes, drags, switches modes, and persists its config across slides and launches on its own.

---

## Step 3 — TV side (ExternalCanvasView)

`ExternalCanvasView` already computes a `fitted` rect for the letterboxed canvas image inside the TV bounds. Overlay the calculator **inside that same fitted rect** so it tracks the mirrored canvas region. Add `import Calculator`, then overlay within the fitted-size frame:

```swift
ZStack {
    Image(decorative: frame, scale: 1.0) …      // unchanged
    if let liveStroke = broker.currentLiveStroke { … }   // unchanged

    // Calculator mirror — same relative spot as on the iPad.
    CalculatorTVOverlay(
        state: .shared,
        referenceSize: broker.calculatorReferenceSize ?? fitted
    )
}
.frame(width: fitted.width, height: fitted.height)
.clipped()
```

Because the overlay is inside the `fitted` rect and `referenceSize` is the iPad container size, the calculator lands at the same fraction of the canvas region on the TV. `CalculatorTVOverlay` only draws when `state.isVisible`, so when the calculator is closed it contributes nothing.

---

## Step 4 — App target

No change needed. Toggling happens inside `PresentingCanvasView`; the app target never references calculator types directly. (If you later want to open the calculator from somewhere in the app target, add `import Calculator` there — it's visible transitively through `Documents`.)

---

## Present-mode cropping (refinement, optional for first pass)

In **Mirror** mode the TV shows the full canvas and the calculator sits at its mirrored position — correct as-is.

In **Present** mode the TV shows only the centered 16:9 viewfinder crop. With the Step-3 wiring, the calculator is positioned relative to the full canvas region, so part of it can fall outside the crop (same as any canvas content outside the viewfinder). That's consistent with how everything else behaves in Present mode, so it's acceptable for v1.

If you later want the calculator to always stay fully visible on the TV regardless of mode, that's a deliberate enhancement (anchor it to the TV frame instead of the canvas region) — not part of this handoff.

---

## Verification checklist

After Steps 0–3, build for iPad + simulated external display and check:

1. **Toggle** — the toolbar `function` button shows/hides the palette.
2. **Drag** — dragging the title bar moves the palette; it stays on-screen at the edges (clamped).
3. **Persistence** — set graph mode + a function + window, close the lesson, reopen → calculator is closed but reopening it restores mode/function/window/position.
4. **Mode switch** — the Graph/Compute segmented control swaps bodies; compute evaluates on "="; graph plots, pans (drag), and zooms (pinch).
5. **Solid hit-test** — with the palette open, Apple Pencil draws on the canvas everywhere *except* under the palette card. **If ink bleeds through under the card**, the card's `.contentShape` isn't blocking the underlying `PKCanvasView`; the fix is to give the calculator card an explicit hit-testing-true opaque background layer (note it back to the calculator module — do not work around it in MathBoard).
6. **TV mirror** — open the calculator on iPad; it appears on the external display at the same relative spot, scaled, read-only. Typing/graphing on iPad updates the TV live.
7. **DEG/RAD** — toggling angle mode on iPad updates both compute results and the graph on both screens.

---

## Rollback

Every step is additive and reversible:
- Step 0: revert the one `Package.swift` line.
- Step 1: remove the `calculatorReferenceSize` property.
- Steps 2–3: remove the added overlay/import/toolbar lines.

The `Calculator` module's own files never need to change to disconnect it.

---

## Known v1 limits (from `Calculator_status.md` section 6)

- Snapshot-to-canvas button is present but **disabled** — wires up when the image-object layer exists.
- One `y = f(x)` at a time; multiple curves, parameter sliders, polar/parametric, trace, and regressions are growth items.
- TV compute display **re-evaluates live** (no key events to mirror), so it shows a running result as you type rather than only on "=". Acceptable for v1.
- Calculator size is fixed at 360×540 (resize handles are a growth item).
