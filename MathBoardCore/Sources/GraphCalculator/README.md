# GraphCalculator

## Purpose
Isolated Desmos-style graphing calculator prototype built for classroom graph instruction.

## Responsibilities
- Manage expression rows, row-level validation, and graph calculator UI state.
- Resolve/evaluate expressions for plotting and table workflows.
- Render graph relations, function curves, and graph interactions.
- Provide in-module keyboard/input workflows for graphing scenarios.

## Key Files
- `GraphCalculatorState.swift`
- `GraphCalculatorExpressionResolver.swift` / `GraphCalculatorExpressionActions.swift`
- `GraphCalculatorRenderer.swift`
- `GraphCalculatorView.swift` / `MathInputKeyboardView.swift`

## Dependencies
- Internal module dependencies: `Calculator`.
- External package dependencies: `SwiftUIMath`.

## Integration Status
- Isolated package product and preview scheme.
- Linked by `Presentation` for app mount points.
- Ongoing implementation notes: `GraphCalculator_status.md`.
