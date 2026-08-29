# Mathtivity System — AI Reference

This document is a dense orientation guide for AI assistants working on MathBoard's
Mathtivity (widget) system. Read this before touching any of the files listed below.

---

## Terminology

| Term | Meaning |
|---|---|
| **Mathtivity / Widget** | Synonymous. A JSON-authored `ActivityWidgetDocument` rendered by native SwiftUI. |
| **Widget object** | A `WidgetObject` placed on the whiteboard canvas. Holds the JSON document + runtime state. |
| **JSON Mathtivity** | A `.json` file in `JSONMathtivities/` parsed into `ActivityWidgetDocument`. |
| **Activity runtime state** | `WidgetActivityRuntimeState` — in-memory + persisted attempt/answer history. |
| **Live Progress** | Firebase documents the student writes during a lesson; the teacher reads these in real time. |
| **Submission** | Student explicitly pressing Submit → score locked in Firebase `submissions/` subcollection. |

---

## Key File Map

### WidgetEngine module (`MathBoardCore/Sources/WidgetEngine/`)

| File | Role |
|---|---|
| `WidgetActivitySchema.swift` | Codable schema: `ActivityWidgetDocument`, `WidgetActivityQuestion`, `WidgetActivityRules`, `WidgetActivityScoreRecord`, etc. Add new schema fields here. |
| `WidgetActivityRenderer.swift` | ~4900-line SwiftUI renderer. Two top-level views: `MultipleChoiceActivityView` and `FillInTheBlankActivityView`. Inner private structs: `ActivityScoreGaugePanel`, `ScoreSummaryTable`, `WidgetScoreSheetPopover`. |
| `WidgetActivityRuntimeState.swift` | `WidgetActivityRuntimeState`, `WidgetMultipleChoiceRuntimeState`, `WidgetFillInTheBlankRuntimeState`. Persist attempt counts, answered IDs, score records. |
| `WidgetContainerView.swift` | Floating/resizable container. Builds `effectiveGearConfiguration(for:)` which reads `@Environment(\.widgetSubmit)` to wire submit callbacks without going through canvas overlay. |
| `WidgetContract.swift` | Public bridge types: `WidgetObject`, `WidgetGearConfiguration`, `WidgetSubmitEnvironment`, `WidgetSubmitEnvironmentKey`, `EnvironmentValues.widgetSubmit`. |
| `JSONMathtivityCatalog.swift` | Loads `.json` files from `JSONMathtivities/` bundle folder. |
| `JSONMathtivities/*.json` | Individual Mathtivity JSON files (MC and FITB format). |

### Documents module (`MathBoardCore/Sources/Documents/`)

| File | Role |
|---|---|
| `StudentModeView.swift` | **Main student lesson container.** `StudentAssignedLessonView` owns all live-progress publishing, submit/reset/resubmit state, Firebase restoration. `StudentModeView` is the outer view for the legacy/non-package path — keep them separate. |
| `ClassroomSyncModels.swift` | `StudentWidgetLiveProgress`, `StudentSubmissionPacket`, `AssignmentSyncPacket`, `LiveProgressIndicatorState`. |
| `FirebaseClassroomSyncService.swift` | All Firebase read/write for student progress. `publishLiveProgress`, `submitWidgetScore`, `fetchStudentWidgetProgress`, `publishLessonPresence`, `deleteLessonPresence`. **Do not change the lesson download/storage architecture in this file.** Live-progress publishing functions are safe to modify. |
| `LessonDetailView.swift` | Teacher-side Live Progress drawer. `LiveProgressStudentRow` reads `progress?.hasEverBeenSubmitted` to show green "Submitted" text even after student resets. |
| `ClassroomAssignmentModels.swift` | `ClassroomAssignment`, `AssignedWidgetSummary`, `WidgetActivityScoreRecord`. |

### Slides / Canvas (`MathBoardCore/Sources/Slides/` and `Canvas/`)

| File | Role |
|---|---|
| `SlidesView.swift` | Top-level lesson renderer. Passes `.environment(\.widgetSubmit, ...)` down from `StudentAssignedLessonView`. Does NOT need to know about submit details — environment propagates automatically. |
| `WidgetCanvasOverlayView.swift` | Places `WidgetContainerView` instances on the canvas. Does NOT pass `gearConfiguration` — submit environment bypasses this via SwiftUI environment injection. |

---

## Submit / Reset / Resubmit State Machine

### State in `StudentAssignedLessonView`

```
localSubmittedWidgetIDs: Set<UUID>   // currently locked-in submitted score
everSubmittedWidgetIDs:  Set<UUID>   // ever submitted this session (never cleared after adding)
```

### Button logic (in `ScoreSummaryTable.submitButton`)

```
onSubmitWidget == nil           → button hidden (teacher preview / non-assigned mode)
isSubmitted && !isReset         → "Reset"     (orange, always enabled)
isReset (was submitted, now reset) → "Resubmit" (green, disabled until answeredCount >= totalCount)
!isSubmitted && !isReset        → "Submit"    (green, disabled until answeredCount >= totalCount)
```

Where:
- `isWidgetSubmitted` = `localSubmittedWidgetIDs.contains(widgetID)`
- `isWidgetReset` = `everSubmittedWidgetIDs.contains(widgetID) && !localSubmittedWidgetIDs.contains(widgetID)`

### Callback flow

**onSubmitWidget(widgetID):**
1. Look up score record from `scoreRecordsByWidgetID[widgetID]`
2. Call `submitWidgetScore(record)` → Firebase `submissions/` + `publishLiveProgress(..., hasEverBeenSubmitted: true)`
3. `localSubmittedWidgetIDs.insert(widgetID)`, `everSubmittedWidgetIDs.insert(widgetID)`

**onResetAfterSubmit(widgetID):**
1. `localSubmittedWidgetIDs.remove(widgetID)` — unlocks submit loop, changes button to "Resubmit"
2. `everSubmittedWidgetIDs.insert(widgetID)` — keeps teacher text green
3. `scoreRecordsByWidgetID.removeValue(forKey: widgetID)` — clears cached .complete score
4. `saveCachedScoreRecords()` — persists the cleared state
5. Widget visual state is reset by the renderer's `resetWidget()` (called alongside in `ScoreSummaryTable`)

**Resubmit** → same as onSubmitWidget (the button just calls `onSubmitWidget` again).

### Teacher dot / text after Reset

```
Dot color:  Yellow  (.active — student is reworking)
Text:       "Submitted" in green  (because hasEverBeenSubmitted == true in Firebase doc)
```

This is driven by `LessonDetailView.LiveProgressStudentRow`:
```swift
if progress?.hasEverBeenSubmitted == true { return "Submitted" }  // statusText
if progress?.hasEverBeenSubmitted == true { return .green }       // statusTextColor
```

---

## Firebase Document Structure

### Live Progress (written every ~2 seconds by student loop)

Path: `lessonCodes/{code}/liveProgress/{studentID}_{widgetID}`

Key fields:
```
assignmentID, classroomID, studentID, widgetID
correctCount, attemptedCount, status ("inProgress" | "complete")
isActiveOnStudentScreen: Bool
hasEverBeenSubmitted: Bool     ← added session 8; persists through Reset
updatedAt: Timestamp
```

The loop publishes for all widgets NOT in `localSubmittedWidgetIDs` (or those in `everSubmittedWidgetIDs` that have been reset). Submitted-and-not-reset widgets are skipped; their final score is already in Firebase.

### Submissions (written once on Submit / overwritten on Resubmit)

Path: `lessonCodes/{code}/submissions/{studentID}_{widgetID}`

Written by `FirebaseClassroomSyncService.submitWidgetScore`. Contains the full `StudentSubmissionPacket` with `widgetScoreRecord.status = .complete`.

### Lesson Presence (heartbeat, student in lesson)

Path: `lessonCodes/{code}/liveProgress/{studentID}_{lessonPresenceWidgetID}`

`lessonPresenceWidgetID` = all-zeros UUID. Written by `publishLessonPresence()` every 2 seconds.  `isActiveOnStudentScreen` = true when student is on any widget slide.  Deleted on lesson exit via `deleteLessonPresence()`.  Used to distinguish green (submitted + in lesson) vs gray (submitted + left).

---

## Live Progress Loop

In `StudentAssignedLessonView`:

```
runLiveProgressLoop() — Task, repeats every 2 seconds
  └── publishLessonPresence()
  └── publishLiveProgress(forActiveWidgetIDs:activeWidgets:)
        └── mergeScoreRecords(from:)        // updates scoreRecordsByWidgetID
        └── StudentAssignedLessonLiveProgressBuilder.updates()
        └── for each update where !localSubmittedWidgetIDs.contains(widgetID):
              FirebaseClassroomSyncService.publishLiveProgress(..., hasEverBeenSubmitted:)
```

**Key guardrails:**
- Loop is blocked until `hasLoadedDurableTeacherState == true` (prevents overwriting submitted scores on cold start)
- `localSubmittedWidgetIDs` blocks re-publishing of submitted widgets
- `StudentAssignedLessonLiveProgressBuilder` always forces `status: .inProgress` — only `submitWidgetScore()` writes `.complete`

---

## Score Restoration on Reopen

`loadDurableTeacherState()` → `restoreSubmittedScoresFromFirebase()`:
1. Fetches student's `liveProgress` docs from Firebase
2. Any doc with `status == .complete` → adds to `localSubmittedWidgetIDs` + `everSubmittedWidgetIDs` + `scoreRecordsByWidgetID`
3. Also checked: local disk cache at `Library/Application Support/MathBoard/StudentProgress/`

---

## Environment Injection Pattern (Why It Exists)

`WidgetCanvasOverlayView` creates `WidgetContainerView` instances but does NOT pass `gearConfiguration`. Adding it to the call chain would require threading through `SlidesView` → `WidgetCanvasOverlayView` → `WidgetContainerView`, which touches many files.

Instead: `StudentAssignedLessonView` sets `.environment(\.widgetSubmit, WidgetSubmitEnvironment(...))` on `SlidesView`. SwiftUI propagates this automatically through the entire hierarchy. `WidgetContainerView.effectiveGearConfiguration` reads `@Environment(\.widgetSubmit)` and injects submit callbacks into `WidgetGearConfiguration` before passing it to `WidgetActivityRenderer`.

**To add new per-widget callbacks from the lesson layer:** add to `WidgetSubmitEnvironment` and `WidgetGearConfiguration`, then read in `effectiveGearConfiguration`.

---

## WidgetActivityRules (JSON Schema)

```json
"rules": {
  "scoreMode": "correctOutOfTotal",        // correctOutOfAttempted | correctOutOfTotal | streak
  "advanceMode": "automaticOnCorrect",     // manual | automaticOnCorrect | automaticAfterAnswer
  "allowRetry": true,
  "maxRetries": 1,                         // retries per question after first wrong (maxRetries+1 = total attempts)
  "maxAttemptsPerQuestion": 2,             // legacy; maxRetries takes precedence if both present
  "shuffleQuestions": false,
  "shuffleChoices": true,
  "calculatorAllowed": false
}
```

`maxRetries` is the teacher-friendly name. `maxRetries: 1` = one retry allowed = 2 total checks per question.

---

## Ably Relationship

Ably is used for **real-time teacher ink sync** only (strokes from teacher iPad → student iPads during live lessons). It is NOT used for student progress / submissions / scores — those go through Firebase.

Relevant files: `AblyLiveClassroomSession.swift`, `SlidesView` (Ably session management). Do not mix Ably and Firebase progress paths.

---

## What NOT to Touch Without Reading First

- **`FirebaseClassroomSyncService` lesson download/storage code** — the `downloadLesson`, `resolveAssignment`, `fetchAndStoreLesson` functions. The structure of how lessons are downloaded and cached is intentional and fragile. Only modify `publishLiveProgress` / `submitWidgetScore` / presence functions.
- **`CanvasObjectSnapshot.write(to:preserving:)`** — the `preserving:` parameter exists specifically to prevent teacher snapshots from overwriting student widget state. Don't remove it.
- **`StudentAssignedLessonLiveProgressBuilder`** — the builder always forces `.inProgress` status; this is intentional. Only `submitWidgetScore()` should ever write `.complete` to Firebase.
