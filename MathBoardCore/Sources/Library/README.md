# Library

## Purpose
Library drawer and catalog module for inserting reusable MathBoard content and tracking recent inserts.

## Responsibilities
- Define library/catalog/recent models.
- Fetch and map mathtivity catalog data.
- Maintain recent-item storage behavior.
- Render library drawer and catalog sheet UI surfaces.

## Key Files
- `LibraryModels.swift` / `MathtivityCatalogModels.swift`
- `LibraryStore.swift` / `LibraryRecentStore.swift`
- `FirebaseMathtivityCatalogService.swift`
- `LibraryDrawerPrototypeView.swift` / `MathtivityCatalogSheet.swift`

## Dependencies
- Internal module dependencies: `WidgetEngine`.
- External package dependencies: `FirebaseAuth`, `FirebaseCore`, `FirebaseFirestore`, `FirebaseStorage`.

## Integration Status
- Consumed by `Slides` and `Presentation`.
- Exposed as its own package product for previews.
