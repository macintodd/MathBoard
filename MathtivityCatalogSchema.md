# Mathtivity Catalog Schema

Last updated: 2026-08-29

## Ownership Model

The Catalog owns MathBoard-provided content:

- Widget Types: editable starter widget formats.
- Built-In Interactives: native MathBoard tools opened through reserved widget markers.
- Premade Mathtivities: ready-to-edit JSON activities organized by topic.

The teacher Library owns only reusable items a teacher explicitly saves. System categories such as `Widget Types`, `Built-In Interactives`, and `Premade Mathtivities` should not be modeled as teacher Library folders.

## Firebase Collection

Recommended collection: `mathtivityCatalog`

Each document ID should be stable and human-readable, for example:

- `template-multiple-choice-text-expression`
- `builtin-coordinate-grid-generator`
- `algebra1-linear-equations-five-question-practice`

## Document Fields

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `title` | string | yes | User-facing row title. |
| `catalogKind` | string | yes | `widgetTemplate`, `builtInInteractive`, or `premadeMathtivity`. Omitted legacy records are treated as `premadeMathtivity`. |
| `topic` | string | yes | Browse grouping/filter label, such as `Linear Equations` or `Built-In Interactives`. |
| `course` | string | no | Course or strand, such as `Algebra 1`. |
| `activityType` | string | no | `multipleChoice`, `fillInTheBlank`, `numericAnswer`, `expressionAnswer`, `matching`, `ordering`, or `multiStep`. Defaults to `multipleChoice` for older records. |
| `answerMode` | string | no | `text`, `expression`, `textAndExpression`, `graphic`, or `numeric`. |
| `mode` | string | no | `scored` or `demo`. Defaults to `scored`. |
| `topicLevel` | number | no | Optional sort/filter hint within a topic. |
| `questionCount` | number | no | Use for question-based widgets/mathtivities. Leave absent for utility interactives. |
| `difficulty` | string | no | Recommended values: `easy`, `medium`, `hard`, or `interactive`. |
| `description` | string | no | Short teacher-facing summary. |
| `tags` | array of strings | no | Search/filter hints. |
| `schemaVersion` | number | no | Current client expects `1`. |
| `requiredAppVersion` | string | no | Minimum app version if a catalog item requires a newer renderer. |
| `jsonStoragePath` | string | conditionally | Required for JSON-backed items. Built-ins may omit this when `builtInKind` is present. |
| `thumbnailStoragePath` | string | no | Firebase Storage path for a PNG thumbnail. |
| `builtInKind` | string | conditionally | Required for built-in interactives. Current values: `inequalitiesExplorer`, `countdownTimer`, `randomNumberGenerator`, `coordinateGridGenerator`. |
| `isPublished` | boolean | yes | Only published records are displayed. |
| `version` | number | no | Content version. Defaults to `1`. |
| `updatedAt` | timestamp | no | Firestore timestamp for sorting/admin review. |

## Storage Paths

JSON-backed catalog records should point to Firebase Storage files with `jsonStoragePath`, for example:

```json
{
  "jsonStoragePath": "jsonMathtivities/algebra1/linear-equations-five-question-practice.json",
  "thumbnailStoragePath": "jsonMathtivities/thumbnails/linear-equations-five-question-practice.png"
}
```

Built-in interactives do not need storage JSON. The app resolves them to a reserved marker payload:

```json
{
  "catalogKind": "builtInInteractive",
  "builtInKind": "coordinateGridGenerator"
}
```

## Example Premade Mathtivity

```json
{
  "title": "Linear Equations - 5 Question Practice",
  "catalogKind": "premadeMathtivity",
  "topic": "Linear Equations",
  "course": "Algebra 1",
  "activityType": "multipleChoice",
  "answerMode": "textAndExpression",
  "mode": "scored",
  "topicLevel": 1,
  "questionCount": 5,
  "difficulty": "easy",
  "description": "Five editable linear-equation questions with feedback.",
  "tags": ["equations", "one variable", "practice"],
  "schemaVersion": 1,
  "jsonStoragePath": "jsonMathtivities/algebra1/linear-equations-five-question-practice.json",
  "thumbnailStoragePath": "jsonMathtivities/thumbnails/linear-equations-five-question-practice.png",
  "isPublished": true,
  "version": 1
}
```

## Example Built-In Interactive

```json
{
  "title": "Coordinate Grid Generator",
  "catalogKind": "builtInInteractive",
  "topic": "Built-In Interactives",
  "activityType": "multipleChoice",
  "mode": "demo",
  "difficulty": "interactive",
  "description": "Configurable Cartesian coordinate grid generator for canvas work.",
  "tags": ["built-in", "interactive", "coordinate grid", "graphing"],
  "builtInKind": "coordinateGridGenerator",
  "isPublished": true,
  "version": 1
}
```
