# Animation and Interactive Applet Architecture Status

Status: **Planning** · Cross-cutting Presentation/Canvas/WidgetEngine architecture · Last updated 2026-08-29

## Goal

Add two related MathBoard capabilities without blending their responsibilities:

- **Object animations** for normal lesson objects during presentation.
- **Reusable native interactive math applets** that can be placed on a lesson like other canvas objects.

The systems may communicate later through presentation events, but they should remain separate internally.

## Current Architecture Findings

- MathBoard does not currently have one unified persisted canvas-object table. Text, image, geometry, cover/layer state, and widgets are stored through separate sidecar-backed models and arrays.
- `CanvasTextObject`, `CanvasImageObject`, and `CanvasGeometryObject` already have stable `UUID` identifiers and source-coordinate frames.
- `WidgetObject` already behaves like an on-canvas object with its own frame, persistence, drag/resize shell, external-display rendering, and Library/Catalog insertion path.
- `Presentation/DisplayBroker.swift` is the current bridge for external-display state shared between the iPad scene and secondary display scene.
- Widget score/data collection remains owned by `WidgetEngine` and the existing Ably/Firebase live-progress path. Classroom utilities and non-scoreable applets should not publish score records unless explicitly designed to do so.

## Design Decision

Animations should be owned by the Presentation/Canvas object layer and should reference existing objects by type plus `UUID` instead of being embedded separately into every object model at first.

Applets should be native `WidgetObject` built-ins or declarative WidgetEngine/Mathtivity records, not arbitrary JavaScript, HTML, or dynamically generated Swift code.

## Object Animation Model

First-pass animation metadata should live in a slide/drawing sidecar, likely near existing object sidecars. A small model should be enough:

```swift
CanvasAnimatedObjectRef
CanvasObjectAnimation
CanvasAnimationState
```

A reference should identify both object family and object ID, for example:

```swift
kind: text | image | geometry | widget
id: UUID
```

Initial supported presets should stay classroom-oriented:

- Appear
- Fade
- Slide
- Scale

Initial trigger support should stay small:

- On slide open
- On next animation
- With previous
- After previous

Duration, delay, and presentation order are enough for the first pass. Avoid a full timeline editor until the simple presentation flow works on iPad and secondary display.

## Interactive Applet Model

Interactive applets should use the existing WidgetEngine canvas shell where possible. A built-in applet can be inserted from the Catalog as a `WidgetObject` whose payload is a reserved marker, similar to current built-in interactives.

The applet renderer should be trusted native SwiftUI. JSON or another small declarative model may describe math content, parameters, defaults, and behavior, but MathBoard should own rendering, persistence, accessibility, synchronization, and interaction.

Candidate first applet:

- Function Transformation Explorer for `y = a(x - h)^2 + k` with sliders for `a`, `h`, and `k`.

## Presentation Event Model

Do not start with a broad scripting engine. Start with a tiny presentation playback state owned by Presentation:

```swift
PresentationPlaybackState
```

Initial state can track:

- Active slide ID
- Current animation step
- Whether presentation playback is active
- Object visibility/progress overrides for rendering

Possible future events:

- Slide appeared
- Teacher advanced animation
- Object tapped
- Animation completed
- Applet parameter changed
- Applet action started/completed

Only add events when a real workflow needs them.

## Phase 1 Scope

Recommended first implementation:

1. Add sidecar-backed `CanvasAnimationState` for the active drawing/slide.
2. Support text and image-backed objects first, including LaTeX images and graph snapshots.
3. Add a small selected-object animation inspector: preset, trigger, duration, delay, and order.
4. Add a teacher-facing Next Animation action during presentation.
5. Render the same animation playback state on the external display.
6. Add tests for model decoding defaults, ordering, and presentation-step advancement.

## Phase 2 Scope

Add the first native applet using the WidgetEngine built-in interactive path:

- Function Transformation Explorer
- Sliders for `a`, `h`, and `k`
- Native graph renderer
- Save/load through `WidgetObject`
- External display state sharing through the existing widget publication path

## Out of Scope Initially

- Full PowerPoint-style timeline editor
- Arbitrary scripting
- Arbitrary JavaScript/HTML applets
- Dynamically generated Swift code
- Student-device synchronization for applet state unless a specific applet requires it
- Score/data publication for non-scoreable teaching utilities

## Architectural Risks

- Adding animation fields directly to every object type may create duplicated migration work because canvas objects are currently stored in separate sidecars.
- External-display rendering must use the same playback state as the iPad, or animations will drift.
- Widget/app-related events must not accidentally publish live score records through Ably/Firebase unless the widget is explicitly scoreable.
- Applet state persistence must distinguish reusable template defaults from placed-object runtime state.

## Validation Checklist

- Existing lessons load when no animation sidecar exists.
- Text/image objects with no animation behave exactly as they do today.
- Animated objects render correctly on the iPad and secondary display.
- Presentation Next advances one deterministic step at a time.
- Library insertion and duplication preserve or intentionally reset animation metadata according to the selected workflow.
- Widget/app score records remain unchanged for non-scoreable applets.
- Full Xcode build passes after each implementation milestone.
