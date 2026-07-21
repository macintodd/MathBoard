# Widget Activity Architecture Status

## Purpose

Document the pivot from low-level component-authored widgets to activity-authored widgets rendered by polished native SwiftUI experiences.

## Why We Are Pivoting

The current schema-driven WidgetEngine can create functional interactive widgets, but the resulting widgets are often visually generic. Expanding the low-level schema with more styling and layout controls increases complexity and still leaves the AI responsible for visual design.

The new strategy separates educational content from presentation:

- Teachers define the instructional goal.
- AI creates the activity content.
- MathBoard chooses and renders the native experience.
- Students interact with a polished, consistent widget.

## Current WidgetEngine State

- `WidgetSchema.swift` defines the existing component JSON contract.
- `WidgetNativeRenderer.swift` renders component widgets in SwiftUI.
- `WidgetEditorView.swift` previews pasted widget JSON.
- `WidgetSamples.swift` contains AI prompts and sample JSON.
- `WidgetScratchpad.swift` is used for local widget JSON experiments.

The existing component renderer remains valuable as an advanced format and fallback.

## Architecture Decision

Add a higher-level activity JSON contract above the component schema.

Activity JSON describes what students do educationally. It should not describe detailed layout, colors, typography, or view hierarchy.

MathBoard maps activity JSON to compatible native experiences. A single activity can be rendered by more than one experience.

## Key Terms

- Activity: The educational interaction type, such as `multipleChoice`.
- Experience: The native SwiftUI presentation used to render an activity, such as `arcadeChoiceChallenge`.
- Theme: A curated visual palette and styling layer, such as `neonMath` or `chalkboard`.
- Activity JSON: The AI-generated content contract.
- Component JSON: The existing low-level fallback contract.

## Initial Activity JSON Shape

```json
{
  "schemaVersion": 1,
  "widgetId": "order-ops-first-step",
  "activity": "multipleChoice",
  "title": "Order of Operations",
  "description": "Students identify the first operation before simplifying.",
  "learningObjective": "Identify multiplication or division before addition or subtraction.",
  "difficulty": "easy",
  "presentation": {
    "preferredTheme": "neonMath",
    "preferredExperience": "arcadeChoiceChallenge"
  },
  "rules": {
    "scoreMode": "correctOutOfAttempted",
    "advanceMode": "manual",
    "allowRetry": true,
    "calculatorAllowed": false
  },
  "questions": []
}
```

## First Supported Activity: multipleChoice

The first milestone supports multiple-choice activities with:

- prompt
- optional expression
- 2-6 answer choices
- exactly one correct choice
- hints
- correct feedback
- incorrect feedback
- scoring and progress rules

## Native Experience Rendering

The initial renderer should route `multipleChoice` to a native SwiftUI activity view. The view owns layout, spacing, typography, colors, answer-card design, feedback presentation, progress display, and animations.

Native activity experiences should be responsive. The same activity view should support compact iPad/editor layouts and wide 16:9 second-display layouts without changing the activity JSON. Projected widgets should avoid required scrolling when possible.

The current multiple-choice view is still an active design pass. Recent refinements remove visible question numbering, place the prompt above the expression, keep action buttons compact, and use an icon-only hint button in the action row. The plain progress bar has been replaced with a native SwiftUI scoring section: a skeuomorphic gauge cluster for progress and score representations, plus a table-style summary for streak, score, longest streak, bonus, and points.

Suggested first experience:

- `arcadeChoiceChallenge`

Future compatible experiences:

- `paperQuiz`
- `sportsArena`
- `mysteryReveal`
- `bossBattle`

## Theme Strategy

The AI may suggest a theme, but MathBoard and the teacher retain final control.

Initial themes:

- `cleanClassroom`
- `neonMath`
- `paperArcade`
- `chalkboard`
- `sportsCourt`

## Tool Policy

Activity rules include `calculatorAllowed`. This is a host-app policy flag, not a renderer-only display setting.

- `calculatorAllowed: false` means MathBoard should hide or disable calculator access while students work on the widget.
- `calculatorAllowed: true` means calculator access supports the learning goal.
- Missing value should be treated conservatively by the host. The default policy can be decided when widgets are integrated into the broader app.

## Runtime State Policy

`WidgetActivityRuntimeState.swift` defines Codable runtime and score-sheet models for activity widgets. `WidgetObject` now has an optional `activityRuntimeState` field, widget sidecar load/save helpers, and score records keyed by the placed widget instance ID. `WidgetActivityRenderer` can render against a `Binding<WidgetActivityRuntimeState>` while still providing local fallback state for editor previews. `WidgetContainerView` can now render activity JSON natively and write frame/runtime changes through a bound `WidgetObject`. The iPad canvas owns a bound `[WidgetObject]`, loads/saves it through per-slide `.widgets.json`, passes a file-level score sheet into rendered activity widgets, and accepts `CanvasObjectCommand.insertWidget` / `CanvasObjectCommand.updateWidget` for authored widget JSON. The `+ > Widget` palette command opens `WidgetEditorView`; its preview insert button places the widget on the current canvas, and the score-gear popover can reopen the editor for that placed widget.

Recommended app behavior:

- Activity JSON remains content and rules only.
- Runtime progress should live in a separate session state model keyed by lesson, slide, and widget instance.
- Navigating away from a page should preserve in-progress work during the current lesson/session.
- Widgets should expose an explicit reset action.
- Score sheets should be generated from runtime states, not edited as separate student-facing objects.
- `WidgetActivityScoreSheet(widgets:)` can aggregate rows from widget objects once the canvas provides the file's widget list.
- Persistent scores and high scores should be optional, stored outside the activity JSON, and keyed by widget instance or stable widget id depending on whether the goal is per-placement or cross-lesson tracking.

## Files To Create Or Change

- Create `WidgetActivitySchema.swift`.
- Later create `WidgetActivityRenderer.swift`.
- Later create native activity views and theme support.
- Later update `WidgetEditorView.swift` to decode activity JSON first and component JSON second.
- Later update `WidgetSamples.swift` with a new activity-authoring prompt.
- Later update `WidgetScratchpad.swift` to test activity JSON.

## Implementation Checklist

- [x] Create activity architecture status document.
- [x] Link from WidgetEngine status document.
- [x] Add first-stage activity schema models.
- [x] Add activity JSON validation helpers.
- [x] Add activity renderer.
- [x] Add first native multiple-choice experience.
- [x] Add curated theme model.
- [x] Update WidgetEditor preview flow.
- [x] Add activity JSON prompt.
- [x] Add activity JSON scratchpad sample.
- [x] Add teacher theme and experience override controls in the editor preview.
- [x] Honor multiple-choice rules for shuffling, retry, max attempts, scoring mode, and auto-advance.
- [x] Prevent repeated correct submissions from increasing score.
- [x] Add calculator policy flag to activity rules.
- [x] Refine multiple-choice question layout and compact action row.
- [x] Replace basic progress bar with a custom score/progress gauge cluster.
- [x] Add table-style score summary next to the gauge on wider layouts.
- [x] Add Codable activity runtime and score-sheet models.
- [x] Add hidden gear popover with reset, widget score row, average, points, and points possible.
- [x] Add optional runtime-state storage to `WidgetObject`.
- [x] Make `WidgetActivityRenderer` binding-capable for document-backed runtime state.
- [x] Add score-sheet aggregation helper for widget object arrays.
- [x] Add widget sidecar load/save helpers for per-slide `.widgets.json` storage.
- [x] Key score-sheet rows by placed widget instance ID instead of activity JSON ID.
- [x] Make `WidgetContainerView` render native activity JSON with a bound runtime state.
- [x] Wire the iPad canvas layer to own and persist a bound `[WidgetObject]`.
- [x] Show score-sheet rows across every widget loaded on the current slide.
- [x] Add the canvas command insertion path that creates `WidgetObject` instances from authored activity JSON.
- [x] Add the teacher-facing UI/editor workflow that sends `CanvasObjectCommand.insertWidget`.
- [x] Add score-gear edit workflow that reopens `WidgetEditorView` and sends `CanvasObjectCommand.updateWidget`.
- [ ] Decide whether the score sheet should aggregate current-slide widgets only or every widget across all slides in the `.mathboard` file.
- [ ] Add equivalent widget rendering/persistence to the Mac canvas placeholder if Mac authoring needs live widgets.

## Validation Rules

Initial multiple-choice validation should require:

- schema version is positive.
- title is not empty.
- learning objective is not empty.
- at least one question exists.
- each question has a prompt or expression.
- each question has 2-6 choices.
- each question has exactly one correct choice.
- each choice has a non-empty label.

## Open Questions

- Should experience selection eventually swap between distinct native views, or should some experiences be style variants of the same activity view?
- Should retry behavior be controlled globally, per question, or both?
- How much activity-level metadata should be stored for future analytics before analytics is implemented?
- Should missing `calculatorAllowed` default to false for student assignments, but true for teacher preview?
- Which session persistence modes should be supported first: current view only, current lesson, across app launches, or student profile?
