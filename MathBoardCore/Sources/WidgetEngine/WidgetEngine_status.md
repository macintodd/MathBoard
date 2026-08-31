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

## Recent changes (2026-08-29) — Catalog organization

- **Catalog content kinds:** Library catalog metadata now distinguishes Widget Types, Built-In Interactives, and Premade Mathtivities.
- **Local catalog registry:** Bundled widget templates, bundled JSON mathtivities, and built-in interactive marker payloads are exposed through one catalog source.
- **Catalog utilities:** Built-In Interactives now include Countdown Timer, Random Number Generator, Coordinate Grid Generator, and Function Transformation Explorer alongside Inequality Explorer.
- **Function Transformation Explorer:** First native applet slice graphs `y = a(x - h)^2 + k` with sliders for `a`, `h`, and `k`, a live equation readout, and reset control. It inserts through the normal WidgetObject shell from the Catalog.
- **Runtime safety:** Placed widget IDs, runtime state, and Ably/Firebase sync paths still use the existing widget-object path. Only scoreable built-ins publish live score records; classroom utilities and non-scoreable applets return no score record.
- **Shared utility state:** Timer, random-number, and coordinate-grid built-ins keep state in widget-ID registries so the teacher iPad and external display observe the same values. Countdown ticks are therefore visible on the secondary display once per second.
- **Coordinate grid status:** The grid generator can configure viewing region, Minor Grid spacing, Major Grid spacing, label spacing, full gridlines versus ticks, axis numbering, axis labels, arrows, and line darkness as a native on-canvas utility. Its Photo button renders the configured grid to PNG via `ImageRenderer` and asks the host canvas to insert it as a selectable image object.
