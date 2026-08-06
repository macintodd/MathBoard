# Calculator

## Purpose
Self-contained TI-style teaching calculator prototype with expression parsing, evaluation, statistics, and graph helpers.

## Responsibilities
- Parse/tokenize calculator input and evaluate expressions.
- Maintain calculator state, keypad actions, and error handling.
- Render calculator UI variants (main, full keypad, graph, number line, TV overlay).
- Provide equation solving, statistics, and regression helpers.

## Key Files
- `CalculatorEngine.swift` / `CalculatorEvaluator.swift` / `CalculatorParser.swift`
- `CalculatorState.swift` / `CalculatorKey.swift`
- `CalculatorView.swift` / `CalculatorFullKeypadView.swift`
- `CalculatorStatistics.swift` / `CalculatorEquationSolver.swift`

## Dependencies
- Internal module dependencies: none.
- External package dependencies: none.

## Integration Status
- Exposed as its own package product and scheme for isolated iteration and previews.
- Reused by `Presentation` and `GraphCalculator`.
- Ongoing implementation notes: `Calculator_status.md`.
