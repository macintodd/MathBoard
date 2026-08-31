# Animation and Interactive Applet Architecture Status

Status: **Text-effects pivot implemented** · Cross-cutting Presentation/Canvas/WidgetEngine architecture · Last updated 2026-08-30

## Goal

Add two related MathBoard capabilities without blending their responsibilities:

- **Text effects** for lesson text objects during authoring/presentation.
- **Reusable native interactive math applets** that can be placed on a lesson like other canvas objects.

The systems may communicate later through presentation events, but they should remain separate internally.

## Current Architecture Findings

- MathBoard does not currently have one unified persisted canvas-object table. Text, image, geometry, cover/layer state, and widgets are stored through separate sidecar-backed models and arrays.
- `CanvasTextObject`, `CanvasImageObject`, and `CanvasGeometryObject` have stable `UUID` identifiers and source-coordinate frames.
- `WidgetObject` already behaves like an on-canvas object with its own frame, persistence, drag/resize shell, external-display rendering, and Library/Catalog insertion path.
- `Presentation/DisplayBroker.swift` is the current bridge for external-display state shared between the iPad scene and secondary display scene.
- Widget score/data collection remains owned by `WidgetEngine` and the existing Ably/Firebase live-progress path. Classroom utilities and non-scoreable applets should not publish score records unless explicitly designed to do so.

## Implemented Vertical Slice

- Added sidecar-backed `CanvasAnimationState` stored beside each drawing as `<slide>.animations.json`.
- Animation targets use explicit typed identity: `CanvasAnimatedObjectRef(kind:id:)`, where kind is text, image, geometry, or widget.
- First rendered animation support originally covered text objects, image objects, LaTeX-as-image objects, graph/image snapshots, and geometry objects.
- The authoring UI has now pivoted to text effects only. Widgets/applets, images, and geometry keep loading any existing sidecar animation data but no longer expose animation assignment controls in the selected-object HUD.
- Teacher-facing text effect presets are Typewriter, Scrolling, Glow Pulse, and Highlight Sweep. Pop In and Fancy Title remain decode/render-compatible for existing sidecars but are hidden from the picker for now.
- Text effects support canvas-level show/hide, play, pause, and repeat-mode controls (`1x`, `2x`, `Loop`) from the selected text HUD.
- Presentation owns `CanvasAnimationPlaybackState` with current step, active presentation flag, and step timestamp.
- Present mode starts playback at step 0 for slide-open effects. The toolbar has Next Animation and Reset Animations actions.
- Selected text HUD exposes Text Effects plus eye/play/pause/repeat controls. Selected image and geometry HUDs remain focused on their normal edit/reorder/lock/delete actions.
- Rendering is sidecar tolerant: missing animation sidecars load as empty; stale object refs are ignored and pruned on load/reload/deletion cleanup.
- The iPad canvas object layers and the committed external-display renderer both apply the same animation state. A short-lived publish loop refreshes secondary-display frames while an animation is active.
- Added model tests for sidecar URL naming, explicit typed identity, stale-target cleanup, hidden future steps, visible completed steps, and render tick windows.

## Interactive Applet Slice

- Added a native **Function Transformation Explorer** built-in interactive through the existing WidgetEngine built-in path.
- It graphs `y = a(x - h)^2 + k` with sliders for `a`, `h`, and `k`, a live equation readout, and a reset action.
- It is exposed through `BuiltInInteractiveKind.allCases`, so it appears in the Catalog under Built-In Interactives and inserts as a normal `WidgetObject` with the existing canvas shell.
- It is explicitly non-scoreable, so it does not publish Ably/Firebase score records.

## Design Decision

Text effects are owned by the Presentation/Canvas object layer and reference existing text objects by type plus `UUID` instead of being embedded into `CanvasTextObject`.

The typed animation sidecar remains in place for compatibility and future presentation sequencing, but new authoring work should start with teacher-useful text effects rather than broad animations for every object family.

Applets are native `WidgetObject` built-ins or declarative WidgetEngine/Mathtivity records, not arbitrary JavaScript, HTML, or dynamically generated Swift code.

## Object Animation Model

The first-pass metadata lives in a drawing sidecar:

```swift
CanvasAnimatedObjectRef
CanvasObjectAnimation
CanvasAnimationState
```

A reference identifies both object family and object ID:

```swift
enum CanvasAnimatedObjectKind: String, Codable, Sendable {
    case text
    case image
    case geometry
    case widget
}

struct CanvasAnimatedObjectRef: Codable, Hashable, Sendable {
    var kind: CanvasAnimatedObjectKind
    var id: UUID
}
```

Do not store animation ownership as a bare `UUID` and search every object sidecar for it. The explicit kind makes loading, validation, deletion cleanup, diagnostics, and future migrations much cleaner.

Animation records must be tolerant of missing objects. If a referenced text, image, geometry, or widget object has been deleted, the animation entry should be ignored during rendering and either left harmlessly in the sidecar or cleaned up during a save/maintenance pass. Missing animation targets must never break slide loading.

## Presentation Event Model

Do not start with a broad scripting engine. The first slice uses `CanvasAnimationPlaybackState` only:

- Current animation step
- Whether presentation playback is active
- Step start timestamp for progress calculation

Possible future events:

- Slide appeared
- Teacher advanced animation
- Object tapped
- Animation completed
- Applet parameter changed
- Applet action started/completed

Only add events when a real workflow needs them.

## Out of Scope For This Slice

- Full PowerPoint-style timeline editor
- Duration/delay/order editing UI beyond default preset assignment
- Widget-object animation assignment from the widget shell
- Arbitrary scripting
- Arbitrary JavaScript/HTML applets
- Dynamically generated Swift code
- Student-device synchronization for applet state unless a specific applet requires it
- Score/data publication for non-scoreable teaching utilities

## Architectural Risks

- Adding animation fields directly to every object type would create duplicated migration work because canvas objects are stored in separate sidecars.
- External-display rendering must use the same playback state as the iPad, or animations drift.
- Widget/app-related events must not accidentally publish live score records through Ably/Firebase unless the widget is explicitly scoreable.
- Applet state persistence must distinguish reusable template defaults from placed-object runtime state.
- Animation references must remain explicit about object kind; bare object IDs should not be used as animation targets.
- Orphaned animation records are expected during edits and must be harmless.

## Needs Work Before First Test Release

- Text effects function, but several presets need visual polish before the first tester build. The current implementation proves the architecture and controls; it is not yet the final classroom-quality motion design.
- Current useful set after hands-on review: Typewriter, Scrolling, Glow Pulse, and Highlight Sweep. Scrolling and Glow Pulse work best with a colored text background.
- Secondary-display behavior has been checked and works well enough for the current slice. Some animation jitter remains acceptable for the first tester path because the effect is attention-oriented rather than precision-timed.
- Consider whether the broad image/geometry animation sidecar should stay as hidden compatibility-only infrastructure or be removed before test release.

## Validation Checklist

- Existing lessons load when no animation sidecar exists.
- Text/image/geometry objects with no animation behave exactly as they do today.
- Existing lessons load if an animation sidecar references a deleted/missing object.
- Animated objects render correctly on the iPad and secondary display.
- Presentation Next advances one deterministic step at a time.
- Library insertion and duplication preserve or intentionally reset animation metadata according to the selected workflow.
- Widget/app score records remain unchanged for non-scoreable applets.
- Full Xcode build passes after each implementation milestone.
