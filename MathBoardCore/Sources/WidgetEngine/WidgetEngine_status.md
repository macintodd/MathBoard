# WidgetEngine Status

## Current State

The WidgetEngine currently has a component-based JSON schema in `WidgetSchema.swift` and a native SwiftUI renderer in `WidgetNativeRenderer.swift`. This path can render functional widgets with stacks, grids, text, formulas, inputs, choice groups, keypads, hints, feedback, scores, question sets, graphics, and actions.

## Issue Found

The component schema works technically, but it puts too much visual design responsibility on the AI. Valid widgets often look like generic form-based practice activities because the AI is assembling the full interface from low-level pieces.

## Architecture Pivot

The next direction is an activity-based widget architecture. AI should generate educational content and logic, while MathBoard should render that content through curated native SwiftUI experiences.

Detailed handoff and implementation notes live in `WidgetActivityArchitecture_status.md`.

## Recent changes (2026-08-06, session 8) — Submit/Reset/Resubmit system

- **App-owned Submit button:** Submit/Reset/Resubmit button now lives in `ScoreSummaryTable` next to the gear ⚙️, not in the widget's Final Score page.
- **Submit states:** "Submit" (not yet submitted, dimmed until all questions answered) → "Reset" (after submit) → "Resubmit" (after reset). State driven by `localSubmittedWidgetIDs` and `everSubmittedWidgetIDs` in `StudentAssignedLessonView`.
- **Final Score page simplified:** Both MC and FITB `finalScorePanel` now only show "Review Mathtivity" and "Retry Missed". Reset and Submit removed from the widget interior.
- **Environment injection:** `WidgetSubmitEnvironment` (new struct in `WidgetContract.swift`) injected via SwiftUI `.environment(\.widgetSubmit, ...)` from `StudentAssignedLessonView` through to `WidgetContainerView.effectiveGearConfiguration`. Avoids threading through `WidgetCanvasOverlayView`.
- **`WidgetGearConfiguration` new fields:** `isWidgetSubmitted`, `isWidgetReset`, `onSubmitWidget`, `onResetAfterSubmit`.
- **`hasEverBeenSubmitted`:** New field on `StudentWidgetLiveProgress`, published to Firebase. Teacher always sees green "Submitted" text after a student submits, even after they reset and are reworking.
- **`maxRetries` rule:** New field on `WidgetActivityRules`. `maxRetries: 1` = 2 total attempts per question. Takes precedence over `maxAttemptsPerQuestion`. Applied in both MC and FITB `isCurrentQuestionLocked`.
