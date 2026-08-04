# MathBoard Firebase Rules

These files are deployable rule templates for the current classroom sync shape.

## Current App Shape

- Teachers publish assignment metadata to `classLessonCodes/{code}`.
- Teachers publish one per-student access document to `studentAssignmentAccess/{code}_{studentIdentifierHash}`.
- Students resolve a class lesson code by reading only their specific access document, computed from the code plus their teacher-supplied student ID hash.
- Students write live progress and submissions with `studentIdentifierHash` and `studentAccessDocumentID` fields, so Firestore rules can verify the write against the access document.
- Teachers own durable teacher ink writes under `classLessonCodes/{code}/teacherInk/{strokeID}`.

## Deployment Order

1. Build and test the app after the client changes that publish `studentAssignmentAccess` documents.
2. Republish any existing class lesson assignments that should work under the stricter rules. Older assignments without access documents only work while permissive console rules remain deployed.
3. Deploy `firebase/firestore.rules`.
4. Deploy `firebase/storage.rules`.

## Known Security Limits

These rules are stronger than `request.auth != null`, but this is not the final production model.

- Student access is still based on possession of the lesson code plus teacher-supplied student ID. That is acceptable for classroom testing, but not strong authentication.
- `teacherInk` reads are authenticated-only because the current document path does not include the student access hash. A production version should read teacher ink through a backend resolver, duplicate readable ink under the student access document, or use a path that includes the access key.
- Lesson package downloads are authenticated-only. Full production security should use a backend resolver with signed Storage URLs or move packages into an assignment-code path that Storage rules can verify against Firestore access documents.
