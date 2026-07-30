# Mathtivity Laptop Starter Prompt

Copy and paste the prompt below into the AI assistant in Xcode on the laptop.

This prompt is for creating a small standalone SwiftUI app that contains one reusable **Mathtivity**. The goal is to build and test the interactive on a lower-RAM laptop without opening the full MathBoard project, then later copy the reusable Swift file into MathBoard and wire it into the built-in interactive registry.

---

## Prompt For Laptop Xcode AI

I want to create a standalone **Mathtivity**: a rich coded SwiftUI math interactive that I can develop independently from my main MathBoard app.

Do **not** open, modify, import, or depend on the MathBoard app. This must be a small standalone SwiftUI Xcode app so it runs well on a lower-RAM laptop. The final reusable interactive should be easy to copy into MathBoard later.

Before coding, ask me for a short description of the Mathtivity I want to create. Ask for:

1. The math topic and grade/course.
2. What students should do.
3. Whether it needs student practice mode, teacher presentation mode, or both.
4. What should be scored or tracked, if anything.
5. Any specific examples, problem types, or visual models I want included.
6. Whether to use the standard MathBoard "Skill Builder" color theme and aesthetic described under **Aesthetic & Theme**, or a different look.

Default to a student-practice activity. Explicitly ask whether I also want a **teacher presentation mode** before building one, and do not add it unless I confirm.

After I answer, create the standalone app and reusable Swift file using the rules below.

## Scope: One Skill Per Mathtivity

Each Mathtivity works on exactly **one** skill. Do **not** add top-level tabs to switch between two or more skills or unrelated sections. If a topic needs several distinct skills, build them as separate Mathtivities. A single skill may still walk through a short sequence of problems and end with a summary, but present it as one continuous practice — never as tabbed sub-activities.

## Naming Rules

Choose names from my activity description.

Use this pattern:

```text
<ActivityName>/
  <ActivityName>App.swift
  ContentView.swift
  <ActivityName>InteractiveView.swift
```

Examples:

| User idea | App name | Reusable file | Reusable view |
|---|---|---|---|
| Compound inequalities | `CompoundInequalities` | `CompoundInequalitiesInteractiveView.swift` | `CompoundInequalitiesInteractiveView` |
| Unit circle explorer | `UnitCircleExplorer` | `UnitCircleExplorerInteractiveView.swift` | `UnitCircleExplorerInteractiveView` |
| Algebra tiles | `AlgebraTiles` | `AlgebraTilesInteractiveView.swift` | `AlgebraTilesInteractiveView` |

Use PascalCase for type/file names and avoid spaces in Swift type names.

## Required File Structure

Create a new SwiftUI app with this minimal structure:

```text
<ActivityName>/
  <ActivityName>App.swift
  ContentView.swift
  <ActivityName>InteractiveView.swift
```

Keep almost all activity code in:

```text
<ActivityName>InteractiveView.swift
```

The app shell should only host the reusable view. Keep `<ActivityName>App.swift` and `ContentView.swift` thin.

If a few helper types are needed, keep them in the reusable Swift file. Do not create a large multi-file architecture unless I explicitly ask for it.

## Reusable View Requirements

The reusable file must compile if copied by itself into MathBoard later.

At minimum, create this public SwiftUI entry view:

```swift
public struct <ActivityName>InteractiveView: View {
    public init() {}

    public var body: some View {
        // interactive UI
    }
}
```

Also create an internal shared state object so MathBoard can later render the same Mathtivity on the iPad and external display without creating two independent copies:

```swift
@MainActor
@Observable
final class <ActivityName>State {
    // current problem, draft answers, score, streak, feedback, completion, etc.
}
```

The public view should own a default state for the standalone app, and it should also have an internal initializer that accepts shared state:

```swift
public struct <ActivityName>InteractiveView: View {
    private let state: <ActivityName>State

    public init() {
        self.state = <ActivityName>State()
    }

    init(state: <ActivityName>State) {
        self.state = state
    }

    public var body: some View {
        <ActivityName>StudentView(state: state)
    }
}
```

Use `@Bindable` in internal child views when editing state:

```swift
private struct <ActivityName>StudentView: View {
    @Bindable private var state: <ActivityName>State

    init(state: <ActivityName>State) {
        self.state = state
    }

    var body: some View {
        // UI
    }
}
```

This structure matters because MathBoard may render one copy on the iPad and another copy on the external display. Shared state keeps both copies in sync.

## Optional Snapshot State

If the Mathtivity has meaningful progress or settings, also create a Codable snapshot model for future persistence:

```swift
public struct <ActivityName>StateSnapshot: Codable, Equatable, Sendable {
    // stable values only: problem index, score, streak, selected answers, etc.
}
```

Do not overbuild persistence. The snapshot model can exist without being saved yet.

## MathBoard Compatibility Rules

Write the reusable file so that later I can copy only:

```text
<ActivityName>InteractiveView.swift
```

into MathBoard.

That means:

- Use only `SwiftUI` and `Foundation` unless I explicitly approve another Apple framework.
- Do not rely on app assets.
- Do not rely on `ContentView`.
- Do not rely on `<ActivityName>App`.
- Do not use project-specific environment objects.
- Do not use singletons unless they are purely local to the reusable file.
- Do not use network calls.
- Do not write files.
- Do not use MathBoard, PencilKit, PDFKit, Firebase, or external packages.
- Keep the reusable view public.
- Keep helper implementation types internal or private unless MathBoard will need to construct them.
- Avoid force unwrapping.
- Keep UI state inside the shared state object when that state should mirror to an external display.
- Local one-off animation flags may use `@State`, but student answers, score, streaks, problem progress, graph positions, feedback, and completion state should live in `<ActivityName>State`.

## LaTeX / Math Rendering Rule

Some Mathtivities may need formatted equations. Store all math as LaTeX source strings, but do not add a new LaTeX rendering dependency to this standalone app unless I explicitly ask.

Create one small wrapper view for math display:

```swift
private struct MathtivityMathText: View {
    let latex: String
    var fontSize: CGFloat = 22

    var body: some View {
        Text(latex)
            .font(.system(size: fontSize, weight: .semibold, design: .rounded))
            .monospaced()
    }
}
```

Use `MathtivityMathText(latex:)` everywhere math notation is displayed.

Do not scatter raw `Text(latex)` calls throughout the app. This wrapper lets MathBoard later replace the placeholder with its existing LaTeX renderer, such as `SwiftUIMath`, in one place.

## Expected MathBoard Integration Shape

Later, MathBoard will likely integrate this by:

1. Copying `<ActivityName>InteractiveView.swift` into:

```text
MathBoardCore/Sources/WidgetEngine/BuiltInInteractives/
```

2. Adding a case to MathBoard's built-in interactive enum:

```swift
case <activityName>
```

3. Creating or reusing a state registry keyed by placed `WidgetObject.ID`:

```swift
<ActivityName>InteractiveView(
    state: <ActivityName>StateRegistry.state(for: widget.id)
)
```

Do not implement this MathBoard wiring in the laptop app. Just structure the reusable file so this wiring will be straightforward.

## ContentView

`ContentView` should be only a lightweight host:

```swift
struct ContentView: View {
    var body: some View {
        <ActivityName>InteractiveView()
            .frame(minWidth: 520, minHeight: 360)
            .padding()
    }
}
```

Adjust sizing if needed for iPad/macOS previews.

## Design Requirements

This should feel like a compact teaching tool, not a landing page.

Use:

- A clean SwiftUI layout.
- Compact controls.
- The math visual model as the main focus.
- Clear labels and feedback.
- Standard SwiftUI controls: buttons, segmented pickers, toggles, sliders, steppers, tabs, and menus where appropriate.
- SF Symbols where useful.
- Stable sizes for toolbars, buttons, cards, and visual work areas so the layout does not jump.

Avoid:

- Marketing text.
- Large hero sections.
- Decorative filler.
- Network calls.
- File system writes.
- App-specific dependencies.
- Overly large architecture.

## Aesthetic & Theme

Ask whether I want this standard MathBoard "Skill Builder" theme (see intake question 6). If I say yes, match it; if I want a different look, follow my direction instead. Either way, keep all colors and reusable styles in one private `Theme` enum near the top of the reusable file so the palette is easy to retune or swap.

The default "Skill Builder" look:

- **Accent:** a royal blue (~`RGB 0.22, 0.47, 0.96`) with a `topLeading → bottomTrailing` gradient (`blueGradient`) used for the primary button, a small logo badge, selected controls, and the main prompt/problem card.
- **Canvas:** a solid light cool near-white background (~`RGB 0.955, 0.965, 0.99`).
- **Cards:** white, continuous-corner rounded rectangles (radius ~16) with a soft shadow and a 1pt hairline stroke, exposed as a `.cardStyle()` modifier.
- **Prompt / problem card:** a filled **blue-gradient** card with white text — a small uppercased label, the large formula/prompt, and any "Given" values shown as translucent white pills.
- **Answer tiles:** white rounded tiles (radius ~14) in a 2-column grid, each with a leading checkbox (`square` → `checkmark.square.fill`) and dark text. Selected = blue check + light-blue tint + blue border. After checking, tint green for correct picks (green check), red for wrong picks (red ✗), and outline correct answers the student missed.
- **Buttons:** primary = solid blue-gradient capsule with white bold text (`PrimaryActionStyle`); secondary = white capsule with a blue outline and blue text (`SecondaryActionStyle`).
- **Typography:** SF Rounded throughout (`.system(..., design: .rounded)`), semibold/bold for emphasis, `.monospacedDigit()` for scores.

Signature details:

- A thin **multicolor "rainbow" accent line** (~3pt) directly under the header/title area.
- A header with a small blue rounded **logo badge** (SF Symbol), the activity title, a lighter "Skill Builder" subtitle, and a **Submit** button top-right that opens a results summary sheet.
- If scored, a floating **white score card on the right** with a vertical light-up **point meter** (segments light from the bottom; base range in blue/green, the extra-credit range at the top in gold), a row of **streak stars**, and a small icon (a flame that upgrades to a flashing gold **crown** on a perfect score). Numbers use the accent color and animate as score/streak change.

Appearance mode:

- The palette is a fixed light aesthetic. Lock the activity to light mode with `.environment(\.colorScheme, .light)` on the public entry view (and on any sheet it presents) so it stays readable regardless of the host's light/dark setting. Do not build a separate dark palette unless I ask.

Keep the math visual model the focal point, controls compact, and all sizes stable so the layout never jumps.

## Interaction Requirements

After I describe the Mathtivity, design the interaction flow before coding.

For student practice modes, include:

- Clear task prompt.
- Direct manipulation where useful.
- A check/submit action.
- Feedback for correct and incorrect attempts.
- A way to retry missed work.
- A way to mark a missed problem complete if the student does not want to retry.
- A section or final summary if the activity has multiple sections.
- State that does not reset completed work unless the student chooses a redo/reset action.

For teacher presentation modes, include:

- A clean display for examples.
- Controls that help demonstrate the concept.
- Minimal scoring or no scoring unless I ask for it.

## Scoring / Reporting Contract

If the Mathtivity is only a teacher demonstration tool, scoring can be omitted.

If the Mathtivity has student practice, it must expose a consistent score report so MathBoard can later collect results from every widget and Mathtivity in one teacher view.

Create this public score-report model in the reusable Swift file:

```swift
public struct MathtivityScoreReport: Codable, Equatable, Sendable {
    public var activityID: String
    public var activityTitle: String

    public var totalProblems: Int
    public var correctFirstTry: Int
    public var correctedAfterRetry: Int
    public var markedComplete: Int
    public var incorrectOrIncomplete: Int

    public var longestStreak: Int

    public var earnedPoints: Double
    public var possiblePoints: Double
    public var bonusPoints: Double

    public var masteryPercent: Double
    public var displayPercent: Double
}
```

The shared state object should expose a computed report:

```swift
var scoreReport: MathtivityScoreReport {
    // compute from current student progress
}
```

Use these meanings consistently:

- `correctFirstTry`: problems answered correctly before any retry.
- `correctedAfterRetry`: problems missed at first but later corrected.
- `markedComplete`: problems the student skipped or chose not to retry.
- `incorrectOrIncomplete`: problems not completed or still incorrect.
- `longestStreak`: longest run of first-try correct answers.
- `earnedPoints`: score from mastery/correctness.
- `possiblePoints`: maximum mastery points for the activity.
- `bonusPoints`: optional small motivational bonus, such as streak/star bonuses.
- `masteryPercent`: teacher-facing score based on correctness/completion only.
- `displayPercent`: student-facing score that may include bonus points.

MathBoard will average `masteryPercent` across widgets/Mathtivities at the end of a lesson. This means a 5-point activity and a 12-point activity are weighted equally in the lesson average.

Keep streak/star bonuses small. If bonuses are included, they should affect `displayPercent`, not distort `masteryPercent`.

## Review / Missed-Problem Flow

If the Mathtivity has scored practice, implement review behavior carefully:

1. Correct problems remain completed and should not appear undone during review.
2. Missed problems can be reviewed one at a time.
3. When viewing a missed problem, show **Try Again** and **Mark Complete**.
4. If the student taps **Try Again**, reset only that problem's draft answer.
5. While the student is retrying, the primary action should be **Check**.
6. After the retry is checked, show feedback.
7. After feedback, allow **Try Again** or **Mark Complete**.
8. Marking complete should move to the next missed problem.
9. When all missed problems are corrected or marked complete, show **Next Practice** or the final summary.
10. Do not reset an entire section unless the student explicitly chooses a redo/reset action.

## External Display Readiness

Assume MathBoard may render the Mathtivity twice: once on the iPad and once on a second display.

To make this work later:

- Put meaningful interactive state in `<ActivityName>State`.
- Do not put answer/progress state only in private child-view `@State`.
- Use child-view `@State` only for temporary animation or focus details that do not need to mirror.
- Make sure the UI redraws completely from `<ActivityName>State`.

## Preview Requirements

Add previews for:

1. Normal standalone view.
2. Compact widget-sized frame.
3. Wider teaching-frame layout.
4. Any important mode-specific view if the activity has multiple modes.

Use SwiftUI `#Preview` if available.

## Validation

After implementation:

1. Build the app.
2. Fix compile errors.
3. Verify the main interactive controls work.
4. Verify feedback and scoring work if included.
5. Verify reset/redo only resets what it is supposed to reset.
6. Verify the view still compiles from only `<ActivityName>InteractiveView.swift`, `SwiftUI`, and `Foundation`.

## Important

Before coding, briefly summarize:

- The files you will create.
- The reusable view name.
- The shared state type name.
- The student/teacher modes you plan to include.
- The major interactions.
- Any assumptions you are making from my description.

Then implement the standalone app.

Keep the first version pragmatic and working. Do not build MathBoard wiring, online data submission, Firebase, roster integration, or lesson-file persistence in the laptop app.

End this setup step by asking me:

**What Mathtivity do you want to create first? Describe the topic, student task, teacher presentation needs, scoring/progress needs, and any examples you want included.**

---

## Notes For Me

This laptop project is only for developing one reusable Mathtivity quickly.

When it feels good, copy:

```text
<ActivityName>InteractiveView.swift
```

into:

```text
MathBoardCore/Sources/WidgetEngine/BuiltInInteractives/
```

Then wire it into MathBoard's built-in interactive enum and Library item list.

Lessons learned from the Inequality Explorer integration:

- The reusable view copied into MathBoard cleanly because it had one main Swift file and did not depend on the standalone app shell.
- It needed a shared state object after integration so the iPad and external display could stay in sync.
- Review/retry logic should be designed up front; fixing it afterward is harder.
- Deleting widgets from MathBoard works best when the MathBoard overlay uses stable widget IDs, so the Mathtivity itself should not manage deletion.
- The Mathtivity should not write files or assume anything about MathBoard's lesson package format.

Possible future names:

- Mathtivity
- Mathtivities
- MathBoard Activities
- Math Interactives

Do not bake the marketing name too deeply into code yet. For reusable code, prefer neutral names like:

- `<ActivityName>InteractiveView`
- `<ActivityName>State`
- `<ActivityName>StateSnapshot`
- `BuiltInInteractiveKind`
