# MathBoard Future Features

> Parking lot for larger product ideas that should be preserved, but not built until the current lesson-building, document workflow, widget, object-layer, and presentation foundations are stable.

## Mathtivities / Built-In Native Interactives

MathBoard now has a first proof of concept for this idea: **Inequality Explorer** is integrated as a built-in native SwiftUI interactive placed from the Library, not as a multiple-choice JSON activity.

This feature class should remain distinct from user-authored or JSON-authored widgets:

| Area | Direction |
|---|---|
| Authoring model | Curated SwiftUI code shipped with MathBoard, not user-supplied code. |
| Persistence | Save a stable built-in kind plus frame and, later, optional widget-specific state. |
| Library placement | Store in a pinned Built-In Interactives library/category. |
| Runtime shell | Reuse the canvas widget/object placement shell where practical. |
| Future data | Add explicit submission hooks only after the roster/assignment backend exists. |

Current proof-of-concept limitations:

- Inequality Explorer currently exposes student practice mode through its public entry view.
- Teacher presentation mode exists in the source concept, but needs a public mode/configuration API before MathBoard can choose it.
- Score and streak state are local SwiftUI state and reset when the interactive reloads.
- No roster, assignment, Firebase, or teacher-console submission path is wired yet.

Possible future Mathtivities include algebra tiles, unit circle, slope triangle, trig graph explorer, transformation explorer, polynomial behavior explorer, and statistics simulation tools.

## Class Rosters, Assignments, and Teacher Console

### Product Goal

Add a teacher-managed class roster and assignment system so a teacher can:

- Import rosters one class at a time.
- Assign a MathBoard lesson to one or more classes.
- Share a class-specific lesson link/code with students.
- Have students identify themselves by a teacher-managed student ID.
- Collect widget scores/data into an online database.
- Watch participation and widget progress in a live teacher console.

This is a future online/classroom workflow feature. It should not block the current local `.mathboard` lesson-building work.

### Methodology Refinement

Treat this as three related systems, not one large feature:

| System | Responsibility |
|---|---|
| Local roster system | Teacher-owned class/student data. Should work fully offline first. |
| Assignment publishing system | Turns a local `.mathboard` lesson into one class-specific assignment per selected class. |
| Live session/submission system | Handles student join, presence, widget submissions, and teacher console updates. |

This separation matters because each system has different reliability, privacy, and technical requirements. The local roster system can be built and tested without accounts or networking. Assignment publishing requires backend storage and immutable lesson snapshots. Live sessions require real-time or near-real-time sync, student validation, and careful backend rules.

Use these concepts consistently:

| Concept | Purpose |
|---|---|
| `ClassRoster` | Teacher's saved list of students for one class. |
| `RosterStudent` | One student entry: first name, last name, and teacher/school-created student ID. |
| `StudentRosterID` | Student identifier stored as text. It may be numeric or alpha-numeric. |
| `LessonTemplate` | The original editable `.mathboard` lesson file. |
| `LessonSnapshot` | The frozen version of a lesson that was published for an assignment. |
| `LessonAssignment` | A published lesson snapshot connected to exactly one class. |
| `AssignmentCode` | Short code students can enter if they do not arrive through a direct assignment link. |
| `AssignmentLink` | Link that opens/downloads the assigned lesson and identifies the assignment. |
| `LiveSession` | One active classroom use of an assignment. |
| `WidgetSubmission` | Student data submitted by one widget. |

Important design rule: **do not make one code do everything.** The assignment link/code identifies the assignment. The student ID identifies the student. The live session identifies the current class event. Keeping those separate will make debugging, privacy rules, and reporting much cleaner.

### Roster Management

At the top of the MathBoard file/start view, add an entry point such as **Class Rosters** or **Import Class Rosters**.

Selecting it should open a dedicated roster-management view where the teacher can:

- Import a roster from CSV first.
- Consider PDF import later, but treat it as less reliable because PDFs do not guarantee clean table structure.
- Name each class during import.
- Store all roster data in a new app-managed area called `Class Rosters`.
- View rosters in a spreadsheet-like interface.
- Use tabs or a segmented class picker across the top for each class.
- Edit student first name, last name, and student ID.
- Add individual students manually.
- Delete individual students.
- Transfer or copy students between existing classes.

Required student fields:

| Field | Notes |
|---|---|
| First name | Teacher-visible display name. |
| Last name | Teacher-visible display name. |
| Student ID | Teacher-created or school-provided identifier. Must support numeric and alpha-numeric values. Treat as text, not an integer. |

Important: student IDs are identifiers, not passwords. The eventual online design should avoid treating them as secure authentication by themselves.

### Lesson Assignment Flow

When a teacher creates or opens a lesson, the lesson menu should eventually include an assignment/share action.

Possible flow:

1. Teacher chooses **Share** or **Assign** from the lesson/file menu.
2. App shows a class list with checkboxes/radio-style selection.
3. Teacher selects one or more classes.
4. Teacher taps **Assign**.
5. App uploads or publishes the lesson package to an online backend.
6. Backend creates a unique assignment entry per selected class.
7. App returns a shareable link and a class/lesson code for each selected class.
8. The roster-management view shows each assigned lesson next to the appropriate class roster, including a copyable link and code for resharing.

Open design question: a radio button allows only one class, while checkboxes allow assigning to several classes at once. The current product idea needs multiple classes, so the future UI should likely use checkboxes.

### Assignment Snapshots

For v1, published assignments should use immutable lesson snapshots.

Reasoning:

- If a teacher edits the original lesson tomorrow, yesterday's assignment data should still point to the exact lesson version students used.
- Widget IDs and slide structure need to remain stable for submitted data.
- Reports are easier to trust when the assignment content cannot silently change after students submit work.

Later, MathBoard can add an explicit **Republish Assignment** or **Update Assignment** action, but that should be a deliberate teacher choice with clear consequences.

### Student Join Flow

During class:

1. Teacher posts or shares the assignment link.
2. Student opens the link on their iPad.
3. Link identifies the assignment and downloads/opens the assigned `.mathboard` lesson in the student version of MathBoard.
4. Student enters their student ID.
5. App checks the backend for a matching roster entry tied to that assignment's class.
6. If the ID matches, the student joins the assignment and can complete widgets.
7. If the ID does not match, the app shows a clear error: wrong assignment, wrong ID, or roster mismatch.

Student ID can be stored locally on the student device after first entry, but the student should be able to change it if needed.

If students receive the `.mathboard` file through another path instead of the direct assignment link, they may also need to enter an `AssignmentCode`. In the cleanest path, the link identifies the assignment and the student only enters their ID.

### Teacher Console

Inside an active MathBoard lesson, add a teacher console tab/panel.

The teacher enters or selects the lesson code/class assignment. The console then shows:

- Class roster.
- Student online/present status.
- Green dot or similar presence indicator next to students currently in the file.
- Widget completion state per student.
- Widget scores or submitted data as they arrive.
- Class-level summary views later.

The console should be available while teaching, without taking over the whiteboard.

### Widget Data Submission

Every data-collecting widget should eventually have a **Submit** action.

When submitted, the widget posts data to the backend using:

| Key | Purpose |
|---|---|
| Class code or class assignment ID | Identifies the roster/class context. |
| Lesson code or assignment ID | Identifies the specific assigned lesson instance. |
| Student ID | Maps submission to the roster entry. |
| Widget ID | Identifies which widget produced the data. |
| Submission payload | Score, selected answer, attempts, work state, or widget-specific data. |
| Timestamp | Supports progress and audit history. |

Widgets should remain usable locally even before this online submission layer exists.

### Backend Concept

Firebase is the current candidate backend.

The backend would need to store:

| Entity | Purpose |
|---|---|
| Teacher account | Owns rosters, lessons, assignments, and result data. |
| Class roster | Class name plus student list. |
| Student roster entry | First name, last name, student ID, class membership. |
| Published lesson file | The assigned `.mathboard` lesson package or a reference to hosted storage. |
| Assignment | Connects a lesson to a class with unique codes/link metadata. |
| Student session | Tracks whether a student is currently in the lesson. |
| Widget submissions | Stores per-student, per-widget results/data. |

Possible Firebase-style hierarchy:

```text
teachers/{teacherId}
  classes/{classId}
    students/{studentId}
  lessonSnapshots/{lessonSnapshotId}
  assignments/{assignmentId}
    classId
    lessonSnapshotId
    assignmentCode
    shareLink
    createdAt
  sessions/{sessionId}
    assignmentId
    activeStudentIds
  submissions/{submissionId}
    assignmentId
    sessionId
    classId
    studentRosterId
    widgetId
    payload
    submittedAt
```

Open backend questions:

- Teacher account/auth model.
- Student privacy and FERPA considerations.
- Whether student ID alone is acceptable for joining, or whether an additional short join code is needed.
- Whether published lesson files are immutable snapshots or can update after assignment.
- How to handle offline students or interrupted network connections.
- Whether students need the full MathBoard app or a lighter student app/viewer.

### Suggested Implementation Phases

| Phase | Scope |
|---|---|
| 1 | Local roster-management model and UI only. CSV import, class tabs, add/edit/delete/transfer students. No backend. |
| 2 | Local lesson-to-class assignment metadata. Assign lessons to classes locally and show assigned lessons next to rosters. |
| 3 | Backend spike with Firebase. Publish a lesson snapshot and create class-specific assignment records. |
| 4 | Student join prototype. Link identifies assignment, student enters student ID, backend validates roster match. Assignment code is fallback for non-link entry. |
| 5 | Widget submit pipeline. Multiple-choice widgets submit score/answer data. |
| 6 | Teacher console. Presence, roster list, live submissions, and simple progress summary. |

### Naming Notes

Possible user-facing names:

- Class Rosters
- Classes
- Assignments
- Teacher Console
- Live Class Console

Avoid naming the backend-facing model too casually. Use clear internal names such as `ClassRoster`, `RosterStudent`, `StudentRosterID`, `LessonTemplate`, `LessonSnapshot`, `LessonAssignment`, `AssignmentCode`, `AssignmentLink`, `LiveSession`, and `WidgetSubmission`.
