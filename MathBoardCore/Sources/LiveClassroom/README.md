# LiveClassroom

## Purpose
Realtime classroom collaboration layer (teacher ink sync and session messaging).

## Responsibilities
- Define live classroom session/data models.
- Manage Ably-backed live classroom session lifecycle.
- Coordinate live teacher ink streaming and overlays.

## Key Files
- `AblyLiveClassroomSession.swift`
- `LiveClassroomModels.swift`
- `LiveTeacherInkCoordinator.swift`
- `LiveTeacherInkOverlay.swift`

## Dependencies
- Internal module dependencies: `Canvas`.
- External package dependencies: `Ably`.

## Integration Status
- Optional realtime dependency for `Documents`, `Slides`, and `Presentation`.
