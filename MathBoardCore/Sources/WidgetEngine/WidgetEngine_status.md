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

## Recent changes (2026-09-09) — HTML widget: fix Live Progress scoring + UX improvements

### Root cause fix: Live Progress score stuck at 0 + "Answer at least one item" on Submit
- **Bug:** `ScoredHTMLMultipleChoiceActivityView` sent `flow:{}` (empty object) in every `publish()` call. Swift's synthesized `Codable` for `WidgetActivityAttemptFlowState` requires ALL non-optional fields (`isShowingFinalScore`, `isRetryingMissed`, `retryQuestionIDs`, etc.) to be present in JSON — missing any caused `JSONDecoder` to throw. The `try?` in the Coordinator's `userContentController` silently returned `nil`, so `runtimeState` on the Swift side was never updated. This made Swift always see 0 answered questions, causing Live Progress to show 0/3 and the `onSubmitWidget` guard to fire "Answer at least one item".
- **Fix:** Added `defaultFlow()` JS function returning a complete flow object with all required fields. `defaultState()` uses `defaultFlow()`. `normalizeState()` merges via `Object.assign(defaultFlow(), s.flow || {})` so every `publish()` call sends a fully-formed flow that Swift can decode correctly.

### Navigation improvements
- **Removed:** Old `Next` button that auto-advanced to `isShowingFinalScore` final-score screen. Removed `nextQuestion()` entirely.
- **Added:** `←` / `→` icon buttons for free prev/next navigation — always available, no answer required (allows skipping).
- **Added:** `navigateToIndex(idx)`, `navigatePrev()`, `navigateNext()` functions. Navigating to an already-answered question restores its submitted choice highlight but leaves it locked (can't re-answer unless Retry Missed).
- **Added:** Bottom navigation strip (`#qStrip`) — one tile per question showing question number plus ✓/✗/blank indicator. Tapping a tile jumps to that question. Current question gets accent border.

### Retry Missed
- **Before:** Button always visible, just disabled when no misses. Could appear before all questions answered.
- **After:** Fully hidden via `.hidden` class until ALL questions answered AND at least one missed. When triggered, the missed question is fully reset (removed from `answeredQuestionIDs`, deleted from `submittedChoiceIDsByQuestionID`) and navigation jumps to it clean.

### Submit button
- Hidden when `canSubmitToTeacher` is false; visible and enabled only when all questions are answered. Sets `flow.hasSubmittedScore = true` and calls `publish()` before firing the native submit handler.

### `checkAnswer()` guard
- Added early return if current question is already in `answeredQuestionIDs` to prevent double-scoring on re-entry.

### HTML widget LaTeX rendering fix
- Added `\div` to `replaceCommandSymbols` in `ScoredHTMLMultipleChoiceActivityView.htmlSource`: `.replace(/\\div/g,"&divide;")`. Previously `\div` rendered as raw text in feedback/hints.
- Fixed Q3 `correctFeedback` in `html-latex-multiple-choice.json`: `"Correct. $\\frac{8}{4} = 2$."` (added spaces around `=` so the fraction and equals sign don't bleed together in the HTML renderer).

## Recent changes (2026-09-11) — Teacher-only widget flag

- **`WidgetObject.isTeacherOnly: Bool`** (default `false`) added to `WidgetContract.swift`. Stored/loaded via `decodeIfPresent` so all existing JSON widgets default to `false` (backwards-compatible).
- **Class code widget** created in `LessonDetailView.insertClassCodeWidgetIfNeeded` now passes `isTeacherOnly: true`. The colored class-code rectangle no longer appears on student iPads.
- **`SlidesView.studentMergedObjectSnapshot`** filters `teacherWidgets` with `.filter { !$0.isTeacherOnly }` before merging into the student-local sidecar. Both the initial durable-snapshot path and the live `applyTeacherObjectSnapshot` path call this function, so the filter covers all student-side merge points.

## Recent changes (2026-09-12) — Trivial Pursuit gameplay fixes

- **Removed 0.75 s teacher reveal delay**: `sendChoicesToStudentsBeforeHostReveal()` now shows choices on teacher and student screens simultaneously; `studentRevealHeadStartSeconds` constant removed; `choicesRevealedAt` is set to `Date()` (not the future) so both screens start the same 10-second countdown.
- **`.selected` choice tile state** added to `TrivialPursuitChoiceTile.State`: tapping an answer on the student screen highlights it in blue with a hollow checkmark. The tile transitions to `.correct` (green) or `.incorrect` (red) only after `runtimeState.winnerDisplayName` is set — students no longer see the right/wrong answer immediately on tap.
- **Teacher no longer auto-advances**: `resolveRoundIfNeeded()` now only auto-reveals the correct answer (sets `revealedChoiceIndex` to the correct index) when the timer reaches 0 or all students have answered. It does NOT call `awardRound()`. The teacher must tap a player button or "No one got it" to advance to the result screen, giving live-progress records time to arrive before the winner is determined.
- **`isSendingChoices` state removed** (was unused after the reveal-delay was eliminated).
- **"Answer submitted" label no longer reveals correct/incorrect**: the label now reads "Answer submitted — waiting for results" in a neutral secondary color regardless of whether the answer was right or wrong, so students see no green signal before the winner is announced.
- **`answeredAt` timestamp added to live-progress metadata**: `WidgetTrivialPursuitRuntimeState.scoreMetadata` now publishes `trivialPursuitAnsweredAt` as a Unix epoch string so the actual tap time is stored in Firebase.
- **Winner determined by fastest tap, not by server arrival order**: `suggestedWinner` now compares `metadata["trivialPursuitAnsweredAt"]` (the student's device-local tap time) instead of `updatedAt` (the Firebase server write timestamp). Falls back to `updatedAt` only if the metadata key is absent.

## Recent changes (2026-09-12) — Trivial Pursuit Party widget

- **New activity kind `trivialPursuit`** added to `WidgetActivityKind` (internal) and `WidgetObjectActivityKind` (public, `displayCode: "TP"`, `displayName: "Trivial Pursuit Party"`).
- **`ActivityWidgetDocument`** gained optional `categories: [TrivialPursuitCategory]?` and a custom `init(from decoder:)` using `decodeIfPresent` for `questions` (defaulting to `[]`), so TrivialPursuit JSON (which uses `categories` instead of `questions`) parses correctly.
- **`TrivialPursuitCategory`** and **`TrivialPursuitQuestion`** structs added to `WidgetActivitySchema.swift`; `TrivialPursuitQuestion.choices` reuses `WidgetActivityChoice`.
- **`TrivialPursuitModels.swift`** (new file): `TrivialPursuitGamePhase` enum, `TrivialPursuitGamePlayer` struct, and `TrivialPursuitGameEngine` `@Observable` class. Engine handles setup (2–8 players), random question pick from unused pool per category, wedge awards, win detection, and turn rotation (winner picks next or else rotate).
- **`TrivialPursuitActivityView.swift`** (new file): full host-controlled game UI. Setup screen → two-panel layout (scoreboard left / game content right) → category pick grid → question reveal with Show Choices / Reveal Answer / Who got it? flow → result screen → celebration win screen.
- **`trivial-pursuit-party.json`** (new bundled resource): 6 categories × 6 questions each = 36 questions targeting adults 57–70. Categories: Groovy Decades 🕺, Blockbuster Silver Screen 🎬, Global Landmarks ✈️, Household Classics & Commercials 📺, Legends of Rock/Pop/Soul 🎸, Kitchen & Comfort Food 🍳.
- **Catalog entry** `JSONMathtivityCatalog.trivialPursuitParty` added to `bundledEntries`; `MathtivityCatalogModels` resolves it to `.classPlay` pedagogical workflow.
- **Scoring:** Returns `.notStarted` with all-zeros (unscored party game); satisfies `JSONMathtivityTestContract` checks.
- **⚠️ Pending user action:** Add `TrivialPursuitModels.swift`, `TrivialPursuitActivityView.swift`, and `trivial-pursuit-party.json` to the Xcode project target via Xcode UI (File → Add Files to "MathBoardCore"). Never hand-edit `.pbxproj`.

## Recent changes (2026-09-12) — Student personal clip library

- **`StudentPersonalLibraryStore`** (new file, `Documents` module): singleton that persists extract clips to `{appDocuments}/StudentPersonalLibrary/assets/`. Each clip is a `StudentClip` (id, date, fileName). Clips survive lesson deletion and device backup/restore; independent of any lesson package.
- **`StudentPersonalLibraryView`** (new file, iOS only): `LazyVGrid` sheet showing all clips with context-menu delete. Backed by `StudentPersonalLibraryStore`. Shown from a scissors toolbar button (`.primaryAction`) in the student lesson navigation bar.
- **`SlidesView.onStudentExtractedClip`**: new `(@MainActor (Data) -> Void)?` parameter. When `classroomMode == .student` and this handler is provided, the extract action sends the PNG data to this callback instead of sending it to the next lesson slide. `StudentAssignedLessonView` supplies the callback to call `StudentPersonalLibraryStore.shared.saveClip`.
- **No cross-module dependency violation**: `SlidesView` (Slides module) passes raw `Data` via callback; the `Documents`-module `StudentAssignedLessonView` handles the actual store write, keeping the dependency direction intact (Documents → Slides, not the reverse).

### Live Progress navigation reset bug fix (StudentModeView.swift)
- **Bug:** When a student navigated away from a widget slide, the teacher's Live Progress score reset to 0/N even if the student had scored 3/3. It auto-recovered only after the student navigated back.
- **Root cause:** `StudentAssignedLessonView.activeWidgets` is set once from disk when the student first arrives on the slide (via `SlidesView.publishActiveWidgetIDs()`). At that moment the widget has `activityRuntimeState = nil`. Widget state updates from the HTML widget's WKWebView are saved to disk with a 400 ms debounce, and the 2-second live progress loop reads from disk. If the student navigated away before the loop ran after the debounce save, `scoreRecordsByWidgetID` still contained the initial 0-attempt record. The guard in `mergeScoreRecords` that protects the cache only fires when `cachedRecord.attempts > 0`, so the stale 0-attempt initial record failed to protect the score.
- **Fix:** Added `@State private var lastKnownNonEmptyActiveWidgetIDs: Set<UUID> = []` to `StudentAssignedLessonView`. Updated in `handleActiveWidgetIDsChanged` whenever `widgetIDs` is non-empty. When navigating away (`widgetIDs.isEmpty`), `handleActiveWidgetIDsChanged` now does a fresh disk read using `lastKnownNonEmptyActiveWidgetIDs` instead of passing the stale `activeWidgets`. `runLiveProgressLoop` also uses `lastKnownNonEmptyActiveWidgetIDs` for `refreshedWidgets` when `activeWidgetIDs` is empty, so every 2-second tick continues doing a fresh disk read of the last slide's widgets. Result: score auto-corrects within ≤2 seconds after the debounce save (≤2.4 s total after last answer), instead of staying wrong until the student navigates back.
