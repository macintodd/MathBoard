# Teacher Live Ink Sync — Ably Pub/Sub Proof of Concept

Status: First buildable POC implemented · Created 2026-07-31 · Updated 2026-07-31

## Goal

Prove that one teacher iPad can write with Apple Pencil and have the teacher ink appear live on one or more student iPads during an assigned MathBoard lesson.

This proof of concept is intentionally narrow. It should answer whether Ably Pub/Sub gives MathBoard good enough latency, ordering, reliability, and cost shape for classroom live teaching.

## Product Shape

Firebase remains the durable system of record:

- lesson packages
- class lesson codes
- student profile/identifier flow
- submissions
- live progress summaries
- teacher account/auth state

Ably Pub/Sub handles temporary live classroom events:

- teacher pencil stroke chunks
- teacher slide changes
- later: teacher laser/pointer
- later: presence or student current-slide status

Teacher live ink should render on student iPads as a read-only overlay. It should not mutate the student's working copy or submitted answers unless a future feature explicitly imports teacher notes into a lesson.

## Non-Goals For The First POC

- Do not replace Firebase.
- Do not use Ably Spaces as the core ink transport.
- Do not build production token auth in the first pass unless the SDK forces it.
- Do not persist teacher ink into the final lesson package yet.
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
classroom:{classLessonCode}:slide
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

First POC:

- use Ably channel history only
- student subscribes and requests recent history for the active channel
- acceptable if this only works during short test sessions

Production direction:

- publish compact checkpoints every 30-60 seconds
- late joiner loads latest checkpoint
- then replay only chunks newer than that checkpoint
- final teacher overlay state can be saved to Firebase Storage after class if needed

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

Still pending:

1. Test on two iPads with one teacher and one student after throttling/history scaffold.
2. Expand to multiple student iPads and inspect Ably message counts/reports.
3. Replace local API-key testing with production token authentication.
4. Decide whether history replay should eventually use raw chunks, periodic checkpoints, or both.

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
6. Join the assigned lesson by class lesson code.

Expected quick test:

1. Teacher writes on slide 1.
2. Student sees teacher ink as a read-only overlay.
3. Student changes to another slide; slide-1 teacher ink should not appear there.
4. Student returns to slide 1; recent teacher ink should be replayed from the in-memory overlay state, and a newly opened student session should request recent Ably channel history.

## Success Criteria

The POC is successful if:

- teacher handwriting appears on the student iPad within roughly 100-250 ms in normal Wi-Fi conditions
- strokes preserve shape well enough for classroom math
- slide filtering works
- reconnect or late join can recover recent ink in a short session
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

- Xcode `BuildProject(buildForTesting: true)` succeeds after the Ably POC tightening pass.
- Focused LiveClassroom tests pass 4/4: channel naming, point capping, slide filtering, and immediate final-chunk publishing.
- Xcode live diagnostics are clean for the modified LiveClassroom, lesson menu, and MathBoard test files.

## Remaining Open Questions

- Is the current 85 ms publish interval the right classroom balance between latency and Ably message count?
- Should history replay load raw chunks, periodic checkpoints, or both?
- What should the teacher-facing control be for starting/stopping a live ink session during class?
- Should remote teacher ink eventually be importable into the student file, or remain view-only forever?
