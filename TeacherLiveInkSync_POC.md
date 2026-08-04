# Teacher Live Ink Sync — Ably Pub/Sub Proof of Concept

Status: Durable teacher ink plus prototype teacher-object and teacher-slide live/durable sync implemented · Created 2026-07-31 · Updated 2026-08-04 · Firebase listener for live PDF slide delivery

## Goal

Prove that one teacher iPad can write with Apple Pencil and have the teacher ink appear live on one or more student iPads during an assigned MathBoard lesson.

This proof of concept is intentionally narrow. It should answer whether Ably Pub/Sub gives MathBoard good enough latency, ordering, reliability, and cost shape for classroom live teaching.

## Product Shape

Firebase remains the durable system of record:

- lesson packages
- class lesson codes
- student profile/identifier flow
- per-class hashed student-ID allowlists and per-student assignment-access documents for assigned lesson access
- submissions
- live progress summaries
- durable final teacher ink chunks by class lesson code
- durable teacher object snapshots by class lesson code and slide ID
- durable teacher slide manifests by class lesson code
- teacher account/auth state

Ably Pub/Sub handles temporary live classroom events:

- teacher pencil stroke chunks
- teacher object snapshots for the active class-session slide
- teacher slide changes
- later: teacher laser/pointer
- later: presence or student current-slide status

Teacher live ink renders on student iPads as a read-only overlay while the lesson is open. Final teacher strokes are then merged into the student's local working copy and also persisted to Firebase by class lesson code so late joiners and later-day reopens can recover teacher notes. It still must not mutate submitted answers.

## Non-Goals For The First POC

- Do not replace Firebase.
- Do not use Ably Spaces as the core ink transport.
- Do not build production token auth in the first pass unless the SDK forces it.
- Do not build fine-grained object patches for widgets, photos, object layers, or calculator snapshots yet; the classroom prototype uses slide-level object snapshots.
- Do not sync student writing back to the teacher.
- Do not solve multi-teacher collaboration.
- Do not make teacher ink editable on the student device.

## Recommended Architecture

Use Ably Pub/Sub for stroke messages.

Initial channel:

```text
classroom:{classLessonCode}:ink
```

Likely later channels:

```text
classroom:{classLessonCode}:ink
classroom:{classLessonCode}:objects
classroom:{classLessonCode}:slides
classroom:{classLessonCode}:pointer
```

Optional later Ably Spaces use:

- presence
- connected student list
- cursor/laser location
- current slide/member location

## First-Pass Message Model

Start with simple Codable payloads before optimizing to binary.

```swift
struct TeacherInkStrokeChunk: Codable {
    var lessonCode: String
    var slideID: UUID
    var strokeID: UUID
    var sequence: Int
    var isFinalChunk: Bool
    var colorHex: String
    var width: Double
    var points: [TeacherInkPoint]
    var sentAt: Date
}

struct TeacherInkPoint: Codable {
    var x: Double
    var y: Double
    var force: Double?
    var timestampOffset: Double
}
```

Coordinate system should be MathBoard source-space coordinates, not screen pixels. That keeps teacher/student iPads independent of viewport zoom, pan, and device size.

## Batching Strategy

Initial target:

- collect Pencil points while the teacher writes
- publish stroke chunks about every 100 ms
- publish a final chunk when the stroke ends
- include monotonically increasing `sequence` per stroke

Do not publish every raw point as a separate Ably message.

After the POC works, evaluate:

- point simplification
- binary payloads
- server-side batching rules
- delta compression only for checkpoint/full-state messages, not tiny chunks

## Late Join And Recovery

Current POC:

- teacher final chunks are persisted to Firestore under `classLessonCodes/{classLessonCode}/teacherInk/{strokeID}` after verifying the signed-in teacher owns the class-code document
- teacher object snapshots are persisted under `classLessonCodes/{classLessonCode}/teacherObjects/{slideID}`
- the teacher slide manifest is persisted under `classLessonCodes/{classLessonCode}/teacherSlides/current`
- student assigned lessons fetch the durable slide manifest, object snapshots, and final ink chunks before `SlidesView` opens
- `SlidesView` merges durable teacher slides and teacher ink into the student-local working copy before PencilKit loads
- student still subscribes to Ably and requests recent channel history for short live-session catch-up

Production direction:

- keep Firebase as the durable recovery source for class-session teacher notes
- add compact checkpoints if raw stroke replay becomes too large for long classes
- replay only chunks newer than the latest checkpoint
- broaden durable/live sync later from whole-slide object snapshots to fine-grained object patches for teacher-added widgets, photos, object layers, and calculator snapshots

## Auth Strategy

POC-only options:

- use a temporary Ably API key locally while testing
- keep it out of committed source if possible
- if committed configuration is unavoidable, use a clearly named development-only placeholder and document setup steps

Production direction:

- use Firebase Auth identity
- call a Firebase Cloud Function or backend endpoint
- endpoint issues short-lived Ably tokens
- teacher token allows publish + subscribe for the lesson channel
- student token allows subscribe + history only
- scope capabilities to exact lesson-code channels, not broad wildcards

Example capability shape:

```json
{
  "classroom:ABC123:ink": ["publish", "subscribe", "history"]
}
```

Student:

```json
{
  "classroom:ABC123:ink": ["subscribe", "history"]
}
```

## Integration Points To Inspect First

Teacher side:

- `MathBoardCore/Sources/Documents/LessonDetailView.swift`
- `MathBoardCore/Sources/Slides/SlidesView.swift`
- `MathBoardCore/Sources/Presentation/PresentingCanvasView.swift`
- `MathBoardCore/Sources/Canvas/PencilKitCanvas.swift`

Student side:

- `MathBoardCore/Sources/Documents/StudentModeView.swift`
- assigned lesson working-copy flow
- current active-slide/widget live-progress builder

Sync/Firebase context:

- `MathBoardCore/Sources/Documents/ClassroomSyncModels.swift`
- `MathBoardCore/Sources/Documents/FirebaseClassroomSyncService.swift`
- `MathBoardCore/Sources/Documents/MathBoardStudentAuthStore.swift`

## Implementation Slices

Completed in the first buildable POC:

1. Added a small `LiveClassroom` boundary in `MathBoardCore/Sources/LiveClassroom/`.
2. Added the official Ably Cocoa Swift package and an Ably-backed session wrapper behind a local feature flag.
3. Added a teacher publishing path from the existing live ink callback.
4. Added a student subscription path for live teacher ink chunks.
5. Render received teacher ink as a read-only overlay above the student lesson.
6. Added slide ID filtering so ink only appears on the matching slide.
7. Added coordinator-side throttling so live-stroke callbacks publish at most about every 85 ms while writing, with an immediate final chunk on pencil-up.
8. Added a per-chunk point cap so long strokes do not repeatedly send unbounded JSON payloads.
9. Added Ably channel-history replay on student session start for recent teacher ink catch-up.
10. Added a teacher menu status indicator for off / missing assignment code / missing key / ready.
11. Added focused tests for channel naming, point capping, slide filtering, and final-chunk publishing.
12. Merged final received teacher ink into the student-local drawing on lesson close.
13. Persisted teacher final chunks to Firestore at `classLessonCodes/{code}/teacherInk/{strokeID}`.
14. Fetch durable final chunks when a student opens or reopens an assigned lesson and preload them into the working copy before PencilKit loads.
15. Added prototype teacher-object snapshot sync over `classroom:{code}:objects`.
16. Persisted latest object snapshot per slide to Firestore at `classLessonCodes/{code}/teacherObjects/{slideID}`.
17. Fetch durable teacher-object snapshots before student `SlidesView` opens, then live-apply new snapshots while connected.
18. Added live teacher slide manifest sync over `classroom:{code}:slides` so teacher-added slides appear on open student files.
19. Persisted the current teacher slide manifest to Firestore at `classLessonCodes/{code}/teacherSlides/current`.
20. Fetch durable teacher slide manifests before student `SlidesView` opens so late joiners and later-day reopens have the current teacher slide list.
21. Stripped embedded PDF/background asset bytes out of Ably live slide-manifest messages.
22. Teacher slide-manifest publishing now saves the full asset-bearing manifest to Firebase first, then sends the lightweight Ably slide nudge only after that durable save returns.
23. Student slide manifest merge now defers only the teacher slides whose PDF/background assets are not local yet, removes stale blank placeholders for deferred imported PDF slides, keeps existing local slides visible while they wait for hydration, includes PDF background identity in the canvas view identity, and applies teacher active-slide changes for ready slides.
24. Open student lessons now attach a Firestore listener to the durable teacher slide manifest, hydrate Storage-backed PDF/background assets through the same path used on reopen, and pass newer durable revisions into the already-open `SlidesView`.
25. Added `MathBoardTests` coverage for teacher-slide merges that add/change PDF backgrounds and remove deferred placeholders.

Still pending:

1. Retest live PDF import on physical teacher/student iPads. The intended behavior is that students do not create blank PDF slides from the live nudge; they should add the teacher PDF slides only after the durable Firebase manifest supplies the background asset and it is written locally.
2. Watch student logs during that retest for `[Slides] received live teacher slide manifest`, `[Slides] partially merging teacher slide manifest`, and `[Slides] wrote teacher background asset` to confirm the deferred-then-hydrated path.
3. Expand to multiple student iPads and inspect Ably message counts/reports.
4. Replace local API-key testing with production token authentication.
5. Add checkpoint compaction if raw durable stroke replay becomes too large.
6. Keep large teacher-added assets in Firebase Storage, not Ably payloads; evaluate fine-grained object patches once snapshot restore is reliable and class use shows where bandwidth matters.

## Feature Flag

Use a default-off flag, likely named:

```text
Live Teacher Ink
```

The feature should be easy to disable without affecting existing Firebase assignments or student submissions.

## Local POC Setup

Use the in-app fields, not committed source files, for the temporary Ably API key.

Teacher iPad:

1. Sign in / use the teacher version.
2. Assign the lesson so it has a class lesson code.
3. Open the lesson.
4. Tap the lesson-title capsule.
5. Turn on **Sync teacher ink**.
6. Open **Set Ably API Key** and paste the temporary Ably API key.
7. Confirm the menu status says **Ready to sync**.

Student iPad:

1. Open Student mode.
2. Open the Student Profile sheet.
3. Enter first name and teacher-supplied ID.
4. Turn on **Receive live teacher ink**.
5. Paste the same temporary Ably API key.
6. Join the assigned lesson by class lesson code. The local student ID must match an official or alternate ID in the class roster assigned to that code.

Expected quick test:

1. Teacher writes on slide 1.
2. Student sees teacher ink as a read-only overlay.
3. Student changes to another slide; slide-1 teacher ink should not appear there.
4. Student returns to slide 1; recent teacher ink should be replayed from the in-memory overlay state, and a newly opened student session should request recent Ably channel history.
5. Student closes and reopens the assigned lesson from the catalog; final teacher strokes should be present from the local working copy.
6. A late student opens the same class lesson code after teacher notes already exist; durable final teacher strokes should load from Firestore before the canvas appears.

## Success Criteria

The POC is successful if:

- teacher handwriting appears on the student iPad within roughly 100-250 ms in normal Wi-Fi conditions
- strokes preserve shape well enough for classroom math
- slide filtering works
- reconnect can recover recent live ink during a short session
- late join and later-day reopen can recover final teacher ink from Firebase
- student work remains separate from teacher overlay ink
- disabling the feature restores current behavior
- Ably dashboard reports/message counts look economically plausible for 1 teacher and 30-50 students

## Risks

- Apple Pencil can generate too many points unless batched and simplified.
- Ably message fan-out cost scales with subscribers: 1 teacher message to 30 students is 31 message events.
- Late joiners should not have to replay a full 45-minute stream in production.
- Shipping an Ably API key inside the app would be unsafe.
- Teacher and student slide coordinate spaces must match exactly.
- The student overlay must not interfere with widget interaction or student writing.

## Resolved POC Decisions

- Ably package: `https://github.com/ably/ably-cocoa`, product `Ably`, linked through the `LiveClassroom` target.
- First payload format: JSON `Codable` strings for speed of development and easy debugging.
- Student rendering layer: `SlidesView` hosts a read-only `LiveTeacherInkOverlay` above the student lesson.
- Slide behavior: each stroke chunk carries `slideID`; students render only chunks matching the currently visible slide.
- Local credential setup: feature-flagged `UserDefaults` settings store a temporary Ably API key on each test device. This is not the production security model. Do not commit real API keys to source or paste them into AI chat; production should use Firebase-backed short-lived Ably token requests.

## Current Validation

- Xcode `BuildProject(buildForTesting: true)` succeeds after durable teacher-ink recovery and per-class student ID gating.
- Xcode live diagnostics are clean for the durable Firestore service, live coordinator, lesson/student wiring, and test files.
- `SlidesView.swift` still has only two pre-existing unused-`try?` warnings.
- Focused LiveClassroom tests previously passed for channel naming, point capping, slide filtering, and immediate final-chunk publishing; the latest focused durable-callback test command exceeded the 120-second tool timeout before reporting results.

## Remaining Open Questions

- Is the current 85 ms publish interval the right classroom balance between latency and Ably message count?
- At what stroke count should durable raw chunks be compacted into checkpoints?
- What should the teacher-facing control be for starting/stopping a live ink session during class?
- How should teacher-added widgets, photos, object layers, and calculator snapshots sync during a live class?
