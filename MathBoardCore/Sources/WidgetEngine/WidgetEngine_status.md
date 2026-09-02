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
- **Catalog utilities:** Built-In Interactives now include Countdown Timer, Random Number Generator, Coordinate Grid Generator, Function Transformation Explorer, and MatchGrid alongside Inequality Explorer.
- **Function Transformation Explorer:** First native applet slice graphs `y = a(x - h)^2 + k` with sliders for `a`, `h`, and `k`, a live equation readout, and reset control. It inserts through the normal WidgetObject shell from the Catalog.
- **MatchGrid:** First teacher-led classroom game built-in. Ships as a 6 x 6 matching grid with 18 pairs mixing linear-equation/solution cards and geometry formula/name cards — all pairs verified to have unique answers. Cards are wider rectangles with larger/heavier classroom-readable text. Teacher taps numbered cards to flip them; non-matches stay visible until Continue, matches stay solved and show a point flash/glow. All Play launches manually from the game controls AND auto-triggers with ~1-in-3 probability after each match is confirmed (deferred via `Task { @MainActor in }` to the next run loop cycle so the Continue button's tap fully completes before the view hierarchy changes). The centered All Play overlay uses a larger high-contrast revealed answer for secondary-display readability. MatchGrid game controls sit below the board so the shared widget shell remains the only top grab bar. The Q&A Sheet has three in-app tabs — Student Sheet, Answer Key, and All Play — and exports a three-page PDF: student tracking sheet, answer key, and All Play Q&A. All notation is cleaned (fractions as 1/2, π, ²). **Critical gesture fix (2026-08-31):** The Q&A Sheet is presented as a SwiftUI overlay, NOT a `.sheet`. Using `.sheet` inside a `UIHostingController` installs UIKit pan gesture recognizers for interactive dismiss at the UIKit presentation layer; these recognizers compete with the widget's drag/resize gestures and cause intermittent freezes (everything unresponsive until the UIKit recognizer times out). The overlay approach keeps all interaction handling in SwiftUI's gesture system. **Resize freeze fix (2026-09-01):** After resize the `PKCanvasView.isScrollEnabled` was set back to `true` synchronously on the same run-loop cycle that ended the gesture. This left PKCanvasView's pan gesture recogniser in an ambiguous state where subsequent widget drag/resize attempts appeared frozen until the recogniser timed out. Fixed in `PencilKitCanvas.swift`: `PencilKitCanvasHostView` now tracks `widgetIsInteracting` and the `onWidgetInteractionChanged` callback defers `isScrollEnabled = true` via `Task { @MainActor in }`, aborting the re-enable if a new interaction starts before the task fires. Student point tracking belongs in the Live Progress drawer; MatchGrid does not publish Ably/Firebase score records.
- **Runtime safety:** Placed widget IDs, runtime state, and Ably/Firebase sync paths still use the existing widget-object path. Only scoreable built-ins publish live score records; classroom utilities and non-scoreable applets return no score record.
- **Shared utility state:** Timer, random-number, and coordinate-grid built-ins keep state in widget-ID registries so the teacher iPad and external display observe the same values. Countdown ticks are therefore visible on the secondary display once per second.
- **Coordinate grid status:** The grid generator can configure viewing region, Minor Grid spacing, Major Grid spacing, label spacing, full gridlines versus ticks, axis numbering, axis labels, positive/negative axis arrows, line darkness, and Square mode for equal x/y unit sizing as a native on-canvas utility. Its Photo button renders the configured grid to PNG via `ImageRenderer` and asks the host canvas to insert it as a selectable image object.
