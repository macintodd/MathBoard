# Canvas / Widget Overlay — Architecture Improvement Status

> This document tracks an in-progress architectural refactor of the widget overlay and canvas rendering pipeline. It is written for **AI continuity** — a new session should read Section 0 first, then read only the sections relevant to the current task.

**Last updated:** 2026-11-13 — P1, P3-lite, P2, P4, and widget drag-bar spacer fix all committed to `architecture/widget-overlay-improvements`. See Section 3 for details.

---

## 0. Quick Onboarding (read this first)

**What this work is about:**
An architecture audit identified several structural problems in `PencilKitCanvas.swift` and `WidgetCanvasOverlayView.swift` that cause unnecessary CPU work during panning/zooming, potential lifecycle bugs, and rendering inconsistencies between the teacher iPad and the external display (TV/projector). This document tracks those problems and the fixes.

**Git state:**
- Safe baseline: branch `main`, commit `b8af877` — includes two web-applet bug fixes but no structural changes.
- Work branch: `architecture/widget-overlay-improvements` — all structural changes go here. To abandon and return to safety: `git checkout main`.

**What was already fixed (on `main`, before this branch):**
1. Remote web widget state reset when teacher returns to a slide → `RemoteWebAppletInteractiveView.swift` — `pendingStateJSON` stash before page reload; removed `isExternalDisplay` guard from `didFinish`.
2. Widget ~1/2 inch Y-offset on external display → `RemoteWebAppletWebView` and `WebAppletWebView` — added `scrollView.contentInsetAdjustmentBehavior = .never` and `scrollView.isScrollEnabled = false` to prevent iOS safe-area insets from shifting WKWebView content.

**Key files for this refactor:**
| File | Role |
|---|---|
| `MathBoardCore/Sources/Canvas/PencilKitCanvas.swift` | UIViewRepresentable host; owns `widgetOverlayController`, `layoutSubviews`, `publishWidgetObjects`, `updateWidgetObjectFrame` |
| `MathBoardCore/Sources/WidgetEngine/WidgetCanvasOverlayView.swift` | SwiftUI widget overlay; `sourceBinding(for:)`, `displayBinding(for:)`, `ForEach` over widget objects |
| `MathBoardCore/Sources/Presentation/PresentingCanvasView.swift` | Top-level presenting view; 30+ `@State` vars; `Self.publishWidgets` callback |
| `MathBoardCore/Sources/Presentation/DisplayBroker.swift` | Singleton bridge; `widgetReferenceSize`; `publishWidgets(_:viewport:referenceSize:canvasIdentity:)` |
| `MathBoardCore/Sources/Presentation/ExternalCanvasView.swift` | External display view; uses `broker.widgetReferenceSize` and `widgetVisibleReferenceRect` for scale/offset |

---

## 1. Problems Identified (Audit — 2026-11-13)

These were found during a read-only audit. No code was changed. Each entry includes severity, the specific location, and the symptom it causes.

---

### P1 — `UIHostingController` added without `addChild` (CRITICAL)

**File:** `Canvas/PencilKitCanvas.swift`  
**Where:** `widgetObjectsView.addSubview(controller.view)` — no `addChild(_:)` or `didMove(toParent:)` call  
**Severity:** HIGH — was the root architectural cause of the Y-offset bug. Without proper child view controller embedding, UIKit does not propagate safe areas, trait collections, or rotation events down to the hosted SwiftUI tree. This can cause subtle layout offsets, broken safe area insets in hosted views, and SwiftUI lifecycle events (`.onAppear`, `.task`, environment values) firing incorrectly.

**Root cause of the Y-offset:** When `UIHostingController` is added as a bare subview, iOS still injects a default safe area inset into the hosted view based on the parent window's safe area. This caused the WKWebView inside the hosted widget view to shift ~24pt (status bar height) on the iPad. On the external display (which has zero safe areas) the same code produced no shift, so the same widget appeared ~24pt higher on the TV than the iPad's laser pointer indicated.

**Fix required:** Wherever `widgetOverlayController` is set up:
```swift
parentVC.addChild(widgetOverlayController)
widgetObjectsView.addSubview(widgetOverlayController.view)
widgetOverlayController.view.frame = widgetObjectsView.bounds
widgetOverlayController.didMove(toParent: parentVC)
```
The `parentVC` is the `PencilKitCanvasHostView`'s nearest ancestor `UIViewController` — obtain it via `hostView?.parentViewController` or a stored reference.

---

### P2 — `publishWidgetObjects` fires unconditionally on every layout (HIGH)

**File:** `Canvas/PencilKitCanvas.swift`, function `publishWidgetObjects(using:)`  
**Called from:** `PencilKitCanvasHostView.layoutSubviews` — which runs on every frame during pan/zoom  
**Severity:** HIGH — full widget-data scan + downstream `DisplayBroker` update on every layout pass, even when nothing changed. With many widgets on a slide this stacks up during fluid pan/zoom.

**Fix required:** Add a dirty flag or identity check before the publish call:
```swift
// Only republish if the widget array or viewport actually changed
guard widgetObjects != lastPublishedWidgetObjects || viewport != lastPublishedViewport else { return }
lastPublishedWidgetObjects = widgetObjects
lastPublishedViewport = viewport
publishWidgetObjects(using: hostView)
```
The `WidgetObject` type must be `Equatable` for this — check if it already is; if not, compare a hash of IDs + positions.

---

### P3 — `rootView` replacement instead of binding (HIGH)

**File:** `Canvas/PencilKitCanvas.swift`, function `updateWidgetObjectFrame`  
**Pattern:** `widgetOverlayController.rootView = WidgetCanvasOverlayView(...)` — replaces the entire SwiftUI root view  
**Severity:** HIGH — SwiftUI cannot diff across a `rootView` replacement. Every pan/zoom that moves the overlay frame triggers a full tree teardown and rebuild of the widget overlay, discarding all SwiftUI state within it (animations, text field focus, etc.).

**Fix required:** Hold the widget data in an `@Observable` model object and pass it once at setup. Update the model's properties instead of replacing `rootView`:
```swift
// At setup:
let model = WidgetOverlayModel()
widgetOverlayController = UIHostingController(rootView: WidgetCanvasOverlayView(model: model))
// On each frame update:
model.widgetObjects = newObjects
model.frame = newFrame
```
`WidgetCanvasOverlayView` reads from the model via `@Bindable` — SwiftUI diffs only the changed properties.

---

### P4 — `sourceBinding(for:)` double-scans the widget array (MEDIUM)

**File:** `WidgetEngine/WidgetCanvasOverlayView.swift`, function `sourceBinding(for:)`  
**Pattern:** getter calls `first(where:)` (O(n)); setter calls `firstIndex(where:)` then subscript-assigns (O(n) again). Called once per widget per ForEach render.  
**Severity:** MEDIUM — O(n²) behavior with many widgets; also unsafe: if the array mutates between getter and setter calls (possible under concurrent SwiftUI updates), the setter may write to the wrong index.

**Fix required:** Scan once and use an index-based approach:
```swift
func sourceBinding(for id: UUID) -> Binding<WidgetObject>? {
    guard let idx = widgetObjects.firstIndex(where: { $0.id == id }) else { return nil }
    return Binding(
        get: { self.widgetObjects[idx] },
        set: { self.widgetObjects[idx] = $0 }
    )
}
```
Or, since `widgetObjects` is likely a `[UUID: WidgetObject]` dictionary candidate, switch the backing store to a dictionary for O(1) keyed access.

---

### P5 — `displayBinding()` creates new closures on every ForEach iteration (MEDIUM)

**File:** `WidgetEngine/WidgetCanvasOverlayView.swift`, function `displayBinding(for:)` (or inline in `body`)  
**Pattern:** Computed `Binding` returned from a function called in `ForEach` — a new `Binding` struct (with two new closure allocations) is created on every render pass for every widget.  
**Severity:** MEDIUM — unnecessary allocation pressure. Not a correctness issue but accumulates during heavy pan/zoom.

**Fix required:** Memoize bindings or rewrite the ForEach to use index-based enumeration:
```swift
ForEach(widgetObjects.indices, id: \.self) { i in
    WidgetView(object: $widgetObjects[i])
}
```

---

### P6 — `publishImageFromModel` called excessively (MEDIUM)

**File:** `Canvas/PencilKitCanvas.swift`  
**Pattern:** Called ~60+ times across different state paths (tool change, zoom, layout, widget update, slide change). Each call rasterizes the full canvas to a `UIImage` for external display mirroring.  
**Severity:** MEDIUM — full rasterization is expensive. Should only run when the PKDrawing or viewport actually changes, not on every tool change or widget update.

**Fix required:** Add a drawing-content hash or revision counter. Only call `publishImageFromModel` when the drawing data or viewport changes:
```swift
let drawingHash = canvas.drawing.dataRepresentation().hashValue
guard drawingHash != lastPublishedDrawingHash || viewport != lastPublishedViewport else { return }
lastPublishedDrawingHash = drawingHash
publishImageFromModel()
```

---

### P7 — 30+ flat `@State` variables in `PresentingCanvasView` (LOW-MEDIUM)

**File:** `Presentation/PresentingCanvasView.swift`, lines 94–136  
**Pattern:** 30+ individual `@State` vars at the top level of a large view. Any change to any of these variables invalidates the entire `body` — SwiftUI cannot scope the re-render to just the view that uses the changed state.  
**Severity:** LOW-MEDIUM — contributes to broad UI re-renders when unrelated state changes. Refactoring risk is high (many call sites). Best approach: extract child views that hold their own state, reducing `PresentingCanvasView`'s responsibility.

**Fix required (long-term):** Group related state into child views or `@Observable` models. Example: HUD state (position, visibility, selected object) can move into a `HUDState` observable; overlay state can move into `CanvasOverlayState`. Each child re-renders only when its own model changes.

---

### P8 — Mixed `CADisplayLink` and `asyncAfter` frame timing (LOW)

**File:** `Canvas/PencilKitCanvas.swift`  
**Pattern:** Some animation paths use `CADisplayLink` (hardware-synced); others use `asyncAfter(deadline: .now() + 1/30)` (imprecise, not vsync-aware).  
**Severity:** LOW — causes occasional frame tearing when the two paths interleave. Unify on `CADisplayLink` or on SwiftUI's `TimelineView` for all animation.

---

### P9 — 29–33 MainActor isolation warnings in WebApplet files (LOW)

**Files:** `RemoteWebAppletInteractiveView.swift`, `WebAppletInteractiveView.swift`  
**Pattern:** Closures passed across actor boundaries without explicit `@MainActor` annotation.  
**Severity:** LOW — warnings only, no runtime impact under current Swift 6 strict-concurrency. But they will become errors if strict concurrency is ever enforced on this module.

**Fix required:** Add `@MainActor` annotations to the closure parameters or use `MainActor.assumeIsolated` at the call sites.

---

## 2. Fix Priority Order

| Priority | Problem | Status | Risk | Effort |
|---|---|---|---|---|
| ~~1~~ | ~~P1 — `addChild` for UIHostingController~~ | **Done** `47ad7d5` | Medium | Low |
| ~~2~~ | ~~P3-lite — stable `widgetDisplayFrameCallback`~~ | **Done** `47ad7d5` | Low | Low |
| ~~3~~ | ~~P2 — dirty-flag on `publishWidgetObjects`~~ | **Done** `07fd289` | Low | Low |
| ~~4~~ | ~~P4 — `sourceBinding` double-scan~~ | **Done** `07fd289` | Low | Low |
| 5 | P5 — `displayBinding` closure allocation | Deferred (needs P3 first) | Low | Low |
| 6 — defer | P3 — full `rootView` → Observable model refactor | Pending | High | Medium |
| 7 — defer | P6 — `publishImageFromModel` throttle | Pending | Medium | Medium |
| 8 — defer | P7 — `PresentingCanvasView` state explosion | Pending | High | High |
| 9 — defer | P8 — frame timing unification | Pending | Low | Medium |
| 10 — cleanup | P9 — MainActor warnings | Pending | None | Low |

---

## 3. Changes Applied on This Branch

### 3.1 — P3-lite: Stable `widgetDisplayFrameCallback` (commit `47ad7d5`, 2026-11-13)

**File:** `Canvas/PencilKitCanvas.swift`  
**What changed:**
- Added `private lazy var widgetDisplayFrameCallback: (WidgetObject.ID, CGRect?) -> Void` to `PencilKitCanvasHostView`. Initialized once; captures `[weak self]`.
- Replaced the two inline `{ [weak self] id, frame in self?.updateActiveWidgetDisplayFrame(...) }` closures in `updateWidgetObjects` (line ~1527) and `updateWidgetObjectFrame` (line ~1576) with `widgetDisplayFrameCallback`.

**Why this matters:**  
`updateWidgetObjectFrame` runs on every scroll/zoom frame via `scrollViewDidScroll`/`scrollViewDidZoom`. Each call was allocating a new closure on the heap. Since `((WidgetObject.ID, CGRect?) -> Void)?` is not `Equatable`, SwiftUI treated each new closure as "changed" and re-rendered all `WidgetContainerView` instances at 60fps even when widget positions hadn't moved. This eliminated ~60 unnecessary heap allocations/second and the spurious re-renders they triggered.

**Build status:** Clean (6 pre-existing warnings, no new errors).

---

### 3.3 — P2: `publishWidgetObjects` dirty flag (commit `07fd289`, 2026-11-13)

**File:** `Canvas/PencilKitCanvas.swift` — `Coordinator` class  
**What changed:**
- Added `private var lastPublishedWidgetViewport: WidgetCanvasViewport?` and `private var lastPublishedWidgetCount: Int = -1` to `Coordinator`.
- In `publishWidgetObjects`, guard: skip `onWidgetObjectsChange` when `viewport == lastPublishedWidgetViewport && widgetCount == lastPublishedWidgetCount`.

**Why:** `publishWidgetObjects` is called from `updateUIView` on every SwiftUI render of the representable — including tool switches, overlay state changes, and other non-widget events. Each call was updating `DisplayBroker.shared`, which notified `ExternalCanvasView` observers and triggered a re-render on the external display even when nothing visual changed. Scroll/zoom frames always pass through because viewport changes every frame.

---

### 3.4 — P4: Index-based `sourceBinding` (commit `07fd289`, 2026-11-13)

**File:** `WidgetEngine/WidgetCanvasOverlayView.swift`  
**What changed:** `sourceBinding(for:)` now calls `firstIndex(where:)` once at binding-creation time and captures the index. Getter and setter use O(1) subscript access with an identity guard (`indices.contains(index) && widgets[index].id == id`). Falls back to O(n) scan only if the array was mutated and the index went stale (rare).

**Why:** The original getter called `first(where:)` and the setter called `firstIndex(where:)` — two O(n) scans per widget per render. In a `ForEach` over n widgets, this was O(n²) per SwiftUI update of the overlay.

---

### 3.5 — Drag-bar spacer on external display (commit `0cf7eeb`, 2026-11-13)

**File:** `WidgetEngine/WidgetContainerView.swift`  
**What changed:** When `isExternalDisplay == true`, instead of hiding the header entirely, renders a `Color.clear` spacer of `headerHeight` (34pt). This keeps widget content at the same vertical offset as on the iPad, so the teacher's laser pointer and handwriting align correctly with widget UI elements on the TV.

---

### 3.2 — P1: `addChild` for widget overlay `UIHostingController` (commit `47ad7d5`, 2026-11-13)

**File:** `Canvas/PencilKitCanvas.swift`  
**What changed:**
- Added `override func didMoveToWindow()` to `PencilKitCanvasHostView`. When the view enters a window and `widgetOverlayController` has no parent, walks the responder chain via `nearestViewController()` to find the nearest `UIViewController`, then calls `parentVC.addChild(controller)` + `controller.didMove(toParent: parentVC)`.
- Added private `nearestViewController()` helper using `sequence(first:next:)` over the responder chain.

**Why deferred to `didMoveToWindow` (not setup):**  
`updateWidgetObjects` is first called from `makeUIView`, when the view is not yet in the window. The responder chain doesn't have a parent view controller at that point, so `addChild` must be called once the view is attached. `didMoveToWindow` is the standard UIKit hook for this.

**Build status:** Clean.

---

## 4. Decisions & Rationale

| Decision | Rationale |
|---|---|
| Fix P1 (`addChild`) first | Lowest risk, highest correctness payoff. Proper view controller embedding is a UIKit requirement, not an optimization. |
| Fix P3 (`rootView` replacement) with an `@Observable` model | Avoids full SwiftUI tree teardown; preserves widget state (animations, focus) across pan/zoom. Alternative (pass new view to `setRootView`) was rejected because it has the same teardown problem. |
| Do NOT refactor `PresentingCanvasView` state (P7) in this branch | Too many call sites; risk of regressions in unrelated features. Keep it as a known debt item. |
| Keep CADisplayLink vs asyncAfter mixing (P8) for now | No user-visible symptom. Unifying requires touching animation code throughout the canvas; defer. |

---

## 5. How to Continue (for the next AI session)

1. Read **Section 0** of this doc and **Section 0** of `Project_status.md`.
2. Read `Canvas/PencilKitCanvas.swift` around the `widgetOverlayController` setup and `updateWidgetObjectFrame` function.
3. Apply fixes in priority order from Section 2 above.
4. After each fix: run `BuildProject` to verify the build, then commit to `architecture/widget-overlay-improvements`.
5. When all planned fixes are done and tested: merge branch to `main`, update this doc's "Last updated" line and Section 3, and update `Project_status.md` Section 0 and Section 5.

**Branch:** `architecture/widget-overlay-improvements`  
**Safe rollback:** `git checkout main`
