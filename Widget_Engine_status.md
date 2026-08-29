# Widget Engine — Status

Native schema-driven widget engine for the MathBoard whiteboard. Prototype stage.

## Current direction

The Widget Engine is moving away from raw pasted HTML/JS as the primary authoring
path. The selected direction is a **MathBoard Widget JSON** schema rendered by
native SwiftUI components.

The teacher workflow should become:

1. Copy an app-provided AI instruction prompt.
2. Add a plain-language widget request, such as "Make a basketball-themed
   factoring practice widget for Algebra 1."
3. Paste the returned Widget JSON into MathBoard.
4. Preview, validate, and later add the widget to the whiteboard canvas.

The teacher should not need to know schema details. The boilerplate prompt should
teach AI what components, actions, styles, and limits are allowed.

HTML/WKWebView remains available as an advanced experimental preview path, but it
is not the preferred direction for teacher-generated classroom widgets because
of security, reliability, and future data-collection concerns.

## Architecture

- **Isolated module.** All code lives in `MathBoardCore/Sources/WidgetEngine/`.
- **Zero app dependencies.** The target has no dependency on `MathBoard.app` or
  other MathBoardCore modules. Canvas integration is intentionally deferred.
- **Native renderer.** Widget JSON decodes into Swift model types and renders
  with SwiftUI. No arbitrary code is executed in the schema path.
- **Preview-first development.** `WidgetEditorView`, `WidgetNativeRenderer`, and
  `WidgetScratchpad` are used to iterate before wiring widgets into the app.
- **Coordinator later.** A future canvas coordinator should place widget objects
  on the whiteboard, persist their JSON/state, and provide any app services such
  as analytics or student-device sync.

## Current files

| File | Responsibility |
| --- | --- |
| `WidgetSchema.swift` | Codable schema model, JSON codec, validation. Current schema includes layout, text, numeric controls, choices, meters, hints, symbols, graphics, native graphs, feedback, scoring, expressions, conditions, and actions. |
| `WidgetNativeRenderer.swift` | Native SwiftUI renderer for Widget JSON. Owns preview-local state, feedback state, selected `numberBox`, digit-pad input, expression evaluation, drawing, graphing, and action execution. |
| `WidgetSamples.swift` | AI instruction prompt, sample widget document, sample JSON, and advanced HTML sample. The prompt must stay aligned with `WidgetSchema.swift`. |
| `WidgetScratchpad.swift` | Temporary local testing file. Paste generated Widget JSON inside `widgetJSON` and preview this file directly. |
| `WidgetEditorView.swift` | Standalone authoring UI with Widget JSON and advanced HTML modes, copy prompt button, paste support, validation, and previews. |
| `WidgetContainerView.swift` | Floating/resizable prototype container and `WidgetWebView` wrapper for the advanced HTML path. |
| `WidgetContract.swift` | Minimal bridge placeholders for future MathBoard object integration. |

## Current schema behavior

- `stack` supports vertical/horizontal layout.
- `grid` supports multi-column layout.
- `text` supports `title`, `subtitle`, `body`, `caption`, and `math` roles.
- `mathTemplate` supports algebraic answer-entry layouts that mix fixed math
  text with embedded number boxes. This should be used for factored forms,
  equations, parentheses, variables, operators, and other inline math blanks
  where plain horizontal stacks do not align well.
- Top-level `presentation` metadata supports preferred widget width/height and
  scroll behavior. Previews honor this so taller generated widgets are not
  forced into one default frame.
- `numberInput` supports normal system text entry.
- `numberBox` supports touch selection, optional label, shape, max length, and
  clear-on-select behavior.
- `digitPad` enters digits into the currently selected `numberBox`.
- `valueStepper` and `valueSlider` support bounded numeric state changes for
  graph parameters and transformations.
- `choiceGroup` supports selectable tiles/pills/buttons bound to state.
- `goalMeter` supports progress bars and radial meters.
- `hintProvider` reveals a bounded sequence of hints.
- `symbolCollection` renders controlled built-in symbols such as stars,
  basketballs, targets, coins, trophies, rockets, and checkmarks.
- `graphic` renders native graphic elements in normalized coordinates: line,
  arrow, point, label, parabola, absoluteValue, and built-in symbol.
- `nativeGraph` renders a coordinate plane with line, parabola, absoluteValue,
  and point elements. Graph parameters can be literal expressions or state-bound
  expressions.
- `button` runs allowlisted actions.
- `feedback` displays renderer-owned feedback messages.
- `score` displays a numeric state value.
- `divider` renders a visual separator.
- Expressions support literal values, state values, random integers, and binary
  math: add, subtract, multiply, divide, power, min, max.
- Conditions support equals, notEquals, greaterThan, lessThan,
  greaterThanOrEquals, and lessThanOrEquals.
- Actions include set, increment, showFeedback, clearFeedback, playAnimation,
  recordAttempt, if, and reset. `recordAttempt` is currently a preview no-op
  reserved for future app-level analytics.

Important enum distinction:

- Button styles: `primary`, `secondary`, `destructive`.
- Feedback styles: `neutral`, `success`, `warning`, `error`.
- AI has already confused these once, so the copy prompt and validator messages
  should keep this distinction explicit.

## Chosen guardrails

- Prefer native JSON widgets over arbitrary HTML/JS.
- Do not allow remote image URLs, network calls, raw JavaScript, SVG, CSS, or
  arbitrary code in the native schema path.
- Keep the schema expressive through reusable primitives, not many one-off
  classroom activities.
- Hide schema complexity from teachers; expose it to AI through the copy prompt.
- Add validation limits before real app integration: component count, nesting
  depth, text length, digit-pad count, graphic element count, and animation
  limits.

## Planned schema additions

These should be added gradually and validated carefully:

- Better graph labels, tick labels, and axis labels.
- More controlled built-in symbols/art where useful. Use app-defined symbols
  only, not external assets.
- More complete animation preset rendering. Current support is intentionally
  minimal and mostly feedback-oriented.
- Choice controls for multiple-choice or matching tasks.
- Matching/pairing components and drag-style manipulatives.
- Optional question/problem identifiers layered on top of existing metadata:
  `widgetId`, `learningObjective`, and `analytics.enabled`.

## Analytics / student data direction

Do not build full student data collection yet. It is a larger app architecture
feature involving identity, storage, sync, privacy, and teacher reporting.

However, the schema should remain compatible with future analytics:

- Use structured state rather than arbitrary code.
- Prefer stable state keys and eventual widget/question IDs.
- Later add a small app-controlled action such as `recordAttempt` or
  `recordAnswer`; it can be a no-op in previews until MathBoard app integration.
- Widgets should never talk directly to the network or other iPads. The app
  should own collection, storage, export, and sync.

## Integration path

Keep building and validating the Widget Engine inside `WidgetEngine` first. When
the schema and renderer feel stable:

1. Add a real widget canvas object type.
2. Wire the tool palette add button to create a widget object.
3. Render widgets as independent, resizable whiteboard objects above PencilKit.
4. Decide touch arbitration: PencilKit should not capture touches intended for
   an active widget.
5. Persist Widget JSON and widget state with the document/slide.
6. Mirror live widget rendering to the external display where appropriate.

Do not edit MathBoard app/canvas files for widget integration until explicitly
approved.

## Current risks

- AI can still produce invalid JSON or valid JSON with poor pedagogy/UX.
- The copy prompt must stay synchronized with the schema.
- Validation messages need to become teacher-friendly and specific.
- Sequential actions may surprise authors when later actions depend on newly
  assigned random state.
- Large widgets could hurt canvas performance; enforce size/complexity limits
  before app integration.
- The HTML/WKWebView path remains a security-sensitive advanced mode and should
  not be treated as the default teacher workflow.

## Previews

Select the **`WidgetEngine`** scheme in Xcode before previewing. Useful previews:

- `WidgetScratchpad` → "Widget Scratchpad"
- `WidgetEditorView` → "Widget Editor"
- `WidgetNativeRenderer` → "Native Widget"
- `WidgetContainerView` → "Widget Container"

## Recent changes (2026-08-05)

- **Gear popover redesign:** `WidgetScoreSheetPopover` now shows Reset Widget / Edit Widget action buttons, a save-to-library star (with folder dropdown via `Menu`), a Questions count, a Requires Student Work toggle, and an editable tag chip list with a text field. Tags and `requiresStudentWork` live on `WidgetObject` (placed canvas instance) and propagate to `LibraryStoredItem` when saved to library.
- **Score table UI:** `ScoreSummaryTable` now shows "1st Attempt X/Y", "After Corrections X/Y", and an Ego Score row (score + 0.1 × longestStreak) that appears with a scale+opacity transition after `hasSubmittedScore`. Stars flash briefly on Submit. SCORE nav row displays `score/totalCount` (not `score/attempts`). Removed Longest Streak / Bonus / Points rows.
- **New public types in `WidgetContract.swift`:** `WidgetLibraryFolderDescriptor` and `WidgetGearConfiguration` — thread from `WidgetActivityRenderer` through MC/FITB → `ActivityScoreGaugePanel` → `ScoreSummaryTable` → `WidgetScoreSheetPopover`.
- **`WidgetObject`** and **`LibraryStoredItem`** both gained `tags: [String]` and `requiresStudentWork: Bool` with backward-compat decoders (`decodeIfPresent` with `?? []` / `?? false` defaults).
- **`LibraryStore.addRecentItem`** updated to forward `tags` and `requiresStudentWork` into the stored item.
- **`WidgetContainerView`** now builds and passes an `effectiveGearConfiguration` from widget state; host can supply library info via the new `gearConfiguration` parameter.

## Recent changes (2026-08-05, session 2)

- **Live Progress denominator fix:** `WidgetMultipleChoiceRuntimeState.scoreRecord(for:)` and `WidgetFillInTheBlankRuntimeState.scoreRecord(for:)` now set `pointsPossible: document.questions.count` instead of `pointsPossible: attempts`. `FirebaseClassroomSyncService.publishLiveProgress` now reads `submission.widgetScoreRecord.pointsPossible` as `attemptedCount`, so the teacher's Live Progress drawer shows `score/totalQuestions` instead of `score/totalCheckPresses`. This prevents the counter from exceeding the question count after the retry pass.
- **Submitted score immutability:** `StudentAssignedLessonView.publishLiveProgress(forActiveWidgetIDs:activeWidgets:)` now skips publishing for any widget in `localSubmittedWidgetIDs`. The final score was already published at submission time; the 2-second loop no longer overwrites it with stale data.

## Recent changes (2026-08-05, session 3)

- **Widget state isolation fix (v2):** `CanvasObjectSnapshot.write(to:)` gained a `preserving: Set<String> = []` parameter — listed sidecar files are skipped for both deletion and overwrite. `SlidesView.publishTeacherObjectSnapshot(for:)` strips `widgets.json` before publishing so teacher runtime state never enters Ably/Firebase. `applyTeacherObjectSnapshot(_:)` calls `write(to:preserving: ["widgets.json"])`, which prevents the student's widget state from being deleted or overwritten by any incoming snapshot — including old Firebase snapshots that still embed `widgets.json`. `mergeInitialTeacherObjectSnapshots` (called at `SlidesView.init` to apply durable Firebase snapshots) also uses `preserving: ["widgets.json"]`, so reopening the app after the teacher moves a widget no longer deletes the student's progress on disk.
- **Live Progress score doubling fix:** `WidgetInteractivePartsRuntimeState.combinedScoreRecord` now replaces the base MC/FITB score entirely when scorable number-line parts exist, instead of adding on top of it. The "Done/Revise" choices in number-line JSON mathtivities are scaffolding — the `isCorrect: true` on "Done" was silently awarding an extra point per question alongside the number-line score. A 2-question widget now shows 0/2 in Live Progress instead of 0/4, and each correct question increments by 1 instead of 2.

## Recent changes (2026-08-06)

- **Post-reset Live Progress fix:** `StudentAssignedLessonView.mergeScoreRecords` now detects when a student resets a widget after submitting it. When the on-disk `activityRuntimeState` is nil but the widget is still in `localSubmittedWidgetIDs`, the submission lock and stale cached score are both cleared. The 2-second loop can then re-publish the fresh 0/N state to the teacher's Live Progress drawer. Previously, resetting after submission permanently blocked the loop and left the teacher seeing the old score.
- **Student sign-out on lesson exit:** `FirebaseClassroomSyncService` gained `deleteLessonPresence` (and a `deleteDocument` private helper). `StudentAssignedLessonView.onDisappear` now calls `removeLessonPresence()`, which deletes the student's presence record from Firebase when they leave the lesson. This prevents stale presence records from persisting in the teacher's Live Progress view after a student exits.
- **Dot timing fix:** `publishLessonPresence()` now guards on `hasLoadedDurableTeacherState` — it's a no-op until the lesson content is actually visible. An `.onChange(of: hasLoadedDurableTeacherState)` fires presence immediately when the lesson first loads, so the dot turns blue at the right moment without the 2-second loop delay. Previously the dot turned blue as soon as the navigation push completed (while the student was still on the loading screen).
- **Faster offline detection:** `StudentWidgetLiveProgress.defaultActiveStaleInterval` reduced from 20 seconds to 10 seconds. The live progress loop publishes every 2 seconds (5× headroom), and the teacher polls every 5 seconds — so a student who exits now appears offline within ~15 seconds instead of ~25 seconds.
- **Score cache moved to app support:** `StudentAssignedLessonScoreRecordCache` now stores the score cache at `Library/Application Support/MathBoard/StudentProgress/` instead of inside the lesson bundle. The cache no longer gets wiped by lesson re-downloads or iCloud sync operations that replace the bundle.
- **Cross-device / post-redownload score restoration:** `FirebaseClassroomSyncService.fetchStudentWidgetProgress` fetches the student's previously-submitted widget records directly from Firebase at session start. `restoreSubmittedScoresFromFirebase()` runs inside `loadDurableTeacherState` (before `hasLoadedDurableTeacherState = true`) and merges any `.complete` Firebase records into `localSubmittedWidgetIDs` and `scoreRecordsByWidgetID`. `publishLiveProgress(forActiveWidgetIDs:activeWidgets:)` is also guarded on `hasLoadedDurableTeacherState`, preventing the first loop iteration from publishing a stale 0/N record before the restoration completes. Together these ensure a student who submits on iPad A and opens on iPad B will have their submission recognized rather than overwritten.

## Recent changes (2026-08-06, session 7)

- **Yellow dot on widget slide (any picker selection):** The teacher's dot for a student only turned yellow if the teacher had the exact widget selected in the Live Progress picker that the student was currently on. If the teacher had a different widget selected, the dot fell back to the presence doc — which always had `isActiveOnStudentScreen: false` (blue). Fixed by making `publishLessonPresence()` pass `isActiveOnStudentScreen: !activeWidgetIDs.isEmpty` to `FirebaseClassroomSyncService.publishLessonPresence`. Now the presence doc is `true` whenever the student is on any widget slide. The fallback always shows yellow if the student is on a widget slide, regardless of which widget the teacher has selected.
- **Immediate presence update on slide change:** `handleActiveWidgetIDsChanged` now calls `publishLessonPresence()` immediately after updating `activeWidgetIDs`, so the presence doc is refreshed the moment the student navigates to a new slide — without waiting for the next 2-second loop tick. This eliminates the brief window where the dot could show blue before the loop updated the presence.

## Recent changes (2026-08-06, session 6)

- **Stale widget doc + fresh presence → blue (not red):** `indicatorState(now:staleInterval:lessonPresence:)` now checks presence freshness when the widget doc is stale. Previously, a stale widget score doc always returned `.offline` (red) even if the student had a fresh presence record (meaning they just re-entered the lesson and the loop hadn't published a fresh widget doc yet). Now: stale widget doc + fresh presence → `.inactive` (blue); stale widget doc + no presence → `.offline` (red). This eliminates the bug where a student reopening a saved lesson showed a red dot until the teacher manually changed the widget in Live Progress.

## Recent changes (2026-08-06, session 5)

- **Live Progress real-time stale detection:** `LiveProgressDrawerView` now has a `@State private var now = Date()` that ticks every 2 seconds via a `.task` loop. This value is passed into every `LiveProgressStudentRow` and used as the `now` argument to `indicatorState(now:lessonPresence:)`. Previously, SwiftUI only re-evaluated the stale check when `liveProgressRows` changed (e.g., on a widget picker change). Dots for students who left the lesson now turn red/gray automatically within ~12 seconds of exit, without any teacher interaction required.

## Recent changes (2026-08-06, session 4)

- **Premature green dot fix:** `StudentAssignedLessonLiveProgressBuilder.scoreRecord(for:)` was returning whatever `status` the cached score record held — which becomes `.complete` as soon as a widget's questions are all answered. The loop was publishing `.complete` to Firebase before the student pressed Submit, turning the teacher's dot green early. The builder now always forces `status: .inProgress` for any widget not in `submittedWidgetIDs`. Only `submitWidgetScore()` adds to that set, so the dot only goes green when the student actually submits.
- **Dot stays blue/green after exit fix:** `onDisappear` was calling `publishLiveProgress(forActiveWidgetIDs: [], activeWidgets: [])` which wrote a fresh `updatedAt = now` to Firebase, resetting the 10-second stale timer and keeping the dot blue for another 10 seconds every time the student left. That call has been removed. Widget score docs now go stale naturally from the last loop publish (≤2 seconds before exit), so the teacher sees the dot turn red within ~12 seconds of the student leaving — without any extra Firebase write on exit.

## Recent changes (2026-08-06, session 3)

- **Submitted-offline dot:** Added `LiveProgressIndicatorState.submittedOffline` case. `indicatorState()` now accepts an optional `lessonPresence` parameter — when a widget is complete but the student's presence record is absent or stale (they have left the lesson), the dot shows **gray** instead of green. When the student is actively in the lesson with a fresh presence record, the dot stays **green**. `LiveProgressStudentRow` now takes a `lessonPresence` parameter and both call sites in `progressList` pass it.
- **Green "Submitted" text:** The status label in `LiveProgressStudentRow` shows "Submitted" in **green** for both `.submitted` (in-lesson) and `.submittedOffline` (left-lesson) states. This gives the teacher a persistent visual confirmation that the widget was completed even after the dot turns gray.

## Recent changes (2026-08-06, session 2)

- **Yellow dot during download fix:** The outer `StudentModeView` has a legacy live progress system (manual Stepper scoring) that was inadvertently firing for JSON-mathtivity lessons. `findOnlineLesson()` → `syncSelectedWidget()` → sets `selectedWidgetID` → `.onChange` → `scheduleLiveProgressUpdate()` was writing `isActiveOnStudentScreen: true` (yellow) to Firebase before the lesson was even open. Similarly, `publishCurrentWidgetAsInactive()` on `onDisappear` was writing `score=0, attempts=1, pointsPossible=1` (its draft default) to the same Firebase documents the inner view manages, causing the teacher to see 0/1. Both functions now guard on `resolvedAssignmentPacket?.lesson.packageStoragePath == nil` — for any lesson with a downloadable package, the outer view is completely silent. The inner `StudentAssignedLessonView` owns all live progress publishing for those lessons.
- **Score 0/1 on reopen fix (root cause):** The 0/1 score on student close/reopen was caused by the outer view's `publishCurrentWidgetAsInactive()` overwriting the inner view's submitted record with default draft values on each lesson exit. The inner view's `restoreSubmittedScoresFromFirebase()` and `localSubmittedWidgetIDs` cache were both correct, but the outer view's overwrite happened in between. With the outer view now silenced for lesson-package assignments, the inner view's submitted scores persist in Firebase across exits/reopens.

## Recent changes (2026-08-06, session 8) — Submit/Reset/Resubmit system

- **App-owned Submit button:** The Submit/Reset/Resubmit button now lives in `ScoreSummaryTable` (the score panel's bottom row, next to the gear ⚙️), not inside the widget's Final Score page. This makes it app-controlled and always visible during active widget use.
- **Submit/Reset/Resubmit states:** Button label and behavior are driven by two sets in `StudentAssignedLessonView`: `localSubmittedWidgetIDs` (currently locked-in) and `everSubmittedWidgetIDs` (ever submitted this session). "Submit" = not yet submitted; "Reset" = currently submitted (dimmed when not all answered → lit when all answered → becomes Reset after submit); "Resubmit" = was submitted then reset.
- **Submit is dimmed until all questions answered:** `ScoreSummaryTable.submitButton` disables itself when `answeredCount < totalCount`. `answeredCount: Int` is a new field on `ScoreSummaryTable`, threaded from `ActivityScoreGaugePanel.answeredCount`.
- **Final Score page simplified:** Both MC and FITB `finalScorePanel` now only contain "Review Mathtivity" and "Retry Missed" buttons. Reset and Submit/Resubmit have been removed from the Final Score panel since they now live in the score table.
- **Environment injection for submit callbacks:** `WidgetSubmitEnvironment` (defined in `WidgetContract.swift`) is injected via SwiftUI environment from `StudentAssignedLessonView` → `SlidesView` → `WidgetContainerView` → `effectiveGearConfiguration`. This avoids threading callbacks through `WidgetCanvasOverlayView`.
- **`WidgetGearConfiguration` new fields:** `isWidgetSubmitted: Bool`, `isWidgetReset: Bool`, `onSubmitWidget: (() -> Void)?`, `onResetAfterSubmit: (() -> Void)?`.
- **`hasEverBeenSubmitted` on live progress:** `StudentWidgetLiveProgress` gained `hasEverBeenSubmitted: Bool` (default `false`). Published to Firebase with each `publishLiveProgress` call. After reset, `everSubmittedWidgetIDs` keeps this true so teacher always sees green "Submitted" text even when the dot is yellow (student is working on a retry).
- **Teacher display after Reset:** `LessonDetailView.LiveProgressStudentRow.statusText` and `statusTextColor` check `progress?.hasEverBeenSubmitted` — if true, text is always "Submitted" in green regardless of dot color.
- **`maxRetries` rule:** `WidgetActivityRules` gained `maxRetries: Int?`. Takes precedence over `maxAttemptsPerQuestion`. `maxRetries: 1` = 2 total attempts per question. Applied in both MC and FITB `isCurrentQuestionLocked`.

## Next steps

- Improve validation errors for enum mismatches and invalid component fields.
- Add container decoration and simple native graphic primitives.
- Update the AI prompt after every schema addition.
- Add sample JSON that uses `numberBox` and `digitPad`.
- Prefer `mathTemplate` in generated factoring/equation widgets instead of
  manually composing separate text and number boxes in horizontal stacks.
- Include `presentation.preferredHeight` and `scroll: "enabled"` in generated
  widgets that contain digit pads, hints, graphs, meters, or several controls.
- Keep testing generated widgets in `WidgetScratchpad` before canvas integration.
