# Review of Scoring Widgets Handoff

## User-reported testing issues

1. Inequality Explorer Assessment is too busy. It should be split into smaller widgets or replaced with separate widgets for the three concepts it covers.
2. Inequality Explorer did not preserve the student's in-widget score/progress after leaving and reopening a lesson. The teacher live view could show the score while the student was active, but later reopen flows could fall back to 0 points.
3. Compound Inequality Explorer Assessment had no obvious way to set graph endpoints open vs. closed.
4. Analizing Graphs 1 Demonstration appeared on the teacher lesson but did not render for students after the lesson was shared.
5. Review scoring widgets for consistent live-view/data collection wiring.

## Changes made in this pass

- `InequalityExplorerState` now persists its meaningful runtime state into `WidgetObject.builtInRuntimeState` using the same pattern as `ACTDailyPracticeState`.
- The persisted inequality state includes current activity, per-activity progress, review/retry problem sets, completed review sections, final-summary state, and the `StudentSession` score/attempt history.
- `CompoundInequalitiesInteractiveView` saves the inequality runtime snapshot on appear, on state changes, and on disappear.
- `WidgetContainerView` now constructs Inequality Explorer with a runtime persistence callback and initializes JSON activity runtime state with multiple choice, fill-in-the-blank, and interactive-parts defaults.
- `WidgetObject.liveActivityScoreRecord` now seeds Inequality Explorer and ACT Daily Practice live scoring from each widget's saved built-in runtime state, so reopening an assigned lesson can repopulate score records before the live view publishes.
- Student slides now pass `showsTeacherDemoWebApplets: true`, so shared web applet widgets such as Analizing Graphs 1 render for students while the student catalog remains hidden.
- Number-line graph widgets now show an explicit Open/Closed endpoint button in the control bar when an endpoint is selected. The older hidden tap-again gesture still works.
- Test fake `FakeLiveClassroomSession` was updated for the current `LiveClassroomSessioning` pencil-hover requirements so the build can validate.

## Scoring wiring observations

- JSON mathtivities use `WidgetActivityRuntimeState` and are persisted through `WidgetContainerView.activityRuntimeStateBinding` into the widget sidecar. Their live score path reads `widget.liveActivityScoreRecord`, which falls back to `activityScoreRecord`.
- Inequality Explorer was the outlier: it used `InequalityExplorerStateRegistry.state(for: widget.id)` only, so registry resets or unopened views produced fresh 0-point records. This pass moves it to saved built-in runtime state.
- ACT Daily Practice already used `builtInRuntimeState`, but live score lookup now uses the widget-seeded state path for consistency.
- Match Grid remains registry-backed and currently has `scoreableTaskCount == 0`, so it is not included in assignment score summaries/live scoring as a scored widget.
- Web applet demos, including Analizing Graphs 1, are conceptual interactives with no score record; the issue there was rendering visibility, not scoring.

## Remaining follow-up

- The Inequality Explorer should still be redesigned into smaller activities. Its code already exposes the three concepts as `StudentActivity.symbolToGraph`, `.graphToSymbol`, and `.storyToSymbol`; those are the natural split points for separate widgets.
- A deeper scoring-widget audit should add focused tests around built-in runtime rehydration for Inequality Explorer and ACT Daily Practice. The build is green, but there is not yet a targeted persistence test for the new inequality snapshot.
- Existing live diagnostics in `InequalitiesInteractiveView.swift` still report four warnings unrelated to this pass: three actor-isolation warnings in `SymbolToGraphDraft.initial(...)` helper calls and one unused `withAnimation` result around line 723.

## Validation

- Xcode live diagnostics are clean for `WidgetContainerView.swift`, `WidgetContract.swift`, `WidgetActivityRenderer.swift`, and `MathBoardTests.swift`.
- `InequalitiesInteractiveView.swift` has the pre-existing warnings listed above, with no new errors.
- `BuildProject(buildForTesting: true)` succeeds after updating the live classroom test fake.
