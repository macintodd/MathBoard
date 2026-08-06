# Documents

## Purpose
App-facing lesson/document workflow module: start screen, folder navigation, classroom flows, auth, and `.mathboard` packaging.

## Responsibilities
- Define lesson/document and classroom sync models.
- Manage local document store and package archive/export behavior.
- Provide start screen, folder/lesson views, and teacher/student account flows.
- Bootstrap Firebase and classroom sync services.

## Key Files
- `DocumentModels.swift` / `DocumentStore.swift`
- `MathBoardPackageArchive.swift` / `PresentationExports.swift`
- `StartScreenView.swift` / `FolderDetailView.swift` / `LessonDetailView.swift`
- `FirebaseClassroomSyncService.swift` / `FirebaseAppBootstrap.swift`

## Dependencies
- Internal module dependencies: `LiveClassroom`, `Slides`, `WidgetEngine`.
- External package dependencies: `FirebaseAuth`, `FirebaseCore`, `FirebaseFirestore`, `FirebaseStorage`.

## Integration Status
- Primary app-facing package product for MathBoard.
