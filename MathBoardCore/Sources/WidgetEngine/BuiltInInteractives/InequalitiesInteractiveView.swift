//
//  CompoundInequalitiesInteractiveView.swift
//  CompoundInequalities
//
//  "Inequality Explorer" — an interactive iPad teaching widget for learning
//  inequality notation and number line representation.
//
//  This file is designed to be copied into MathBoard as-is: it depends only
//  on SwiftUI/Foundation and has no app-specific state. The public entry
//  point is `CompoundInequalitiesInteractiveView`.
//

import SwiftUI
import Foundation

// MARK: - Theme

/// Color palette and shared metrics for the Inequality Explorer.
enum ExplorerTheme {
    /// #F5F3EE warm off-white canvas.
    static let canvas = Color(red: 245 / 255, green: 243 / 255, blue: 238 / 255)
    /// #FFFFFF card surfaces.
    static let card = Color.white
    /// #7F77DD purple accent.
    static let purple = Color(red: 127 / 255, green: 119 / 255, blue: 221 / 255)
    /// #1D9E75 correct state (also the Student Mode teal).
    static let green = Color(red: 29 / 255, green: 158 / 255, blue: 117 / 255)
    /// #D85A30 incorrect state.
    static let orange = Color(red: 216 / 255, green: 90 / 255, blue: 48 / 255)
    /// #EF9F27 missed-correct / warning amber.
    static let amber = Color(red: 239 / 255, green: 159 / 255, blue: 39 / 255)
    /// Primary text on the light canvas/cards (fixed, since backgrounds are fixed light).
    static let textPrimary = Color(red: 0.13, green: 0.13, blue: 0.16)
    /// Secondary/muted text.
    static let textSecondary = Color(red: 0.45, green: 0.45, blue: 0.5)

    static let cardCornerRadius: CGFloat = 12
    static let buttonCornerRadius: CGFloat = 10
    static let pillCornerRadius: CGFloat = 20
}

// MARK: - Inequality Symbol

enum InequalitySymbol: String, Codable, CaseIterable, Identifiable, Sendable {
    case lessThan = "<"
    case atMost = "≤"
    case greaterThan = ">"
    case atLeast = "≥"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .lessThan: return "Less than"
        case .atMost: return "At most"
        case .greaterThan: return "Greater than"
        case .atLeast: return "At least"
        }
    }

    /// Strict inequalities exclude the boundary (open dot).
    var isStrict: Bool { self == .lessThan || self == .greaterThan }

    /// Whether the solution region extends to the right of the boundary.
    var pointsRight: Bool { self == .greaterThan || self == .atLeast }

    /// Whether the boundary dot is drawn filled (closed).
    var dotIsClosed: Bool { !isStrict }

    /// One-sentence description for the reference panel.
    var conceptDescription: String {
        switch self {
        case .lessThan: return "Shades left on the number line. Open dot — boundary not included."
        case .atMost: return "Shades left on the number line. Closed dot — boundary is included."
        case .greaterThan: return "Shades right on the number line. Open dot — boundary not included."
        case .atLeast: return "Shades right on the number line. Closed dot — boundary is included."
        }
    }
}

// MARK: - Story Problem

struct StoryProblem: Identifiable, Sendable {
    let id: Int
    let emoji: String
    /// Story text is split so the key inequality phrase can be shown bold.
    let storyPrefix: String
    let keyPhrase: String
    let storySuffix: String
    let variableName: String
    let variableDefinition: String
    let boundary: Double
    let symbol: InequalitySymbol
    /// Value range shown on this problem's number line.
    let axisRange: ClosedRange<Double>
    /// Spacing between tick marks on this problem's number line.
    let tickStep: Double
    let isTrickyFlip: Bool
    let flipExplanation: String?

    /// The correct inequality, e.g. "M > 125".
    var inequalityText: String {
        "\(variableName) \(symbol.rawValue) \(Self.formatted(boundary))"
    }

    var storyText: String {
        storyPrefix + keyPhrase + storySuffix
    }

    /// Story text with the key phrase bolded, at the given display size.
    func attributedStory(fontSize: CGFloat, weight: Font.Weight = .regular) -> AttributedString {
        var prefix = AttributedString(storyPrefix)
        prefix.font = .system(size: fontSize, weight: weight)
        var key = AttributedString(keyPhrase)
        key.font = .system(size: fontSize, weight: .bold)
        var suffix = AttributedString(storySuffix)
        suffix.font = .system(size: fontSize, weight: weight)
        prefix.append(key)
        prefix.append(suffix)
        return prefix
    }

    static func formatted(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return value.formatted(.number.precision(.fractionLength(1)))
    }

    static let all: [StoryProblem] = [
        StoryProblem(
            id: 1, emoji: "👟",
            storyPrefix: "Johnny needs to save ",
            keyPhrase: "more than $125",
            storySuffix: " to buy new sneakers.",
            variableName: "M", variableDefinition: "M = money saved ($)",
            boundary: 125, symbol: .greaterThan,
            axisRange: 0...250, tickStep: 25,
            isTrickyFlip: false, flipExplanation: nil
        ),
        StoryProblem(
            id: 2, emoji: "🌡️",
            storyPrefix: "This week's temperature will be ",
            keyPhrase: "less than 72°",
            storySuffix: ", the weekly average.",
            variableName: "T", variableDefinition: "T = this week's Temperature (°F)",
            boundary: 72, symbol: .lessThan,
            axisRange: 60...84, tickStep: 2,
            isTrickyFlip: false, flipExplanation: nil
        ),
        StoryProblem(
            id: 3, emoji: "🎢",
            storyPrefix: "You must be ",
            keyPhrase: "at least 48 inches",
            storySuffix: " tall to ride.",
            variableName: "H", variableDefinition: "H = height (inches)",
            boundary: 48, symbol: .atLeast,
            axisRange: 40...56, tickStep: 2,
            isTrickyFlip: false, flipExplanation: nil
        ),
        StoryProblem(
            id: 4, emoji: "📱",
            storyPrefix: "The phone battery must stay ",
            keyPhrase: "above 20%",
            storySuffix: " to avoid shutdown.",
            variableName: "B", variableDefinition: "B = battery level (%)",
            boundary: 20, symbol: .greaterThan,
            axisRange: 0...40, tickStep: 5,
            isTrickyFlip: false, flipExplanation: nil
        ),
        StoryProblem(
            id: 5, emoji: "🌡️",
            storyPrefix: "",
            keyPhrase: "75 degrees is greater than",
            storySuffix: " this week's temperature.",
            variableName: "T", variableDefinition: "T = this week's Temperature (°F)",
            boundary: 75, symbol: .lessThan,
            axisRange: 55...95, tickStep: 5,
            isTrickyFlip: true,
            flipExplanation: "The sentence says 75 > T. Rewrite it with T on the left: T < 75. When you move the variable to the left side, the symbol flips direction."
        ),
        StoryProblem(
            id: 6, emoji: "🏆",
            storyPrefix: "A student needs ",
            keyPhrase: "at most 3 absences",
            storySuffix: " to earn the attendance award.",
            variableName: "A", variableDefinition: "A = number of absences",
            boundary: 3, symbol: .atMost,
            axisRange: 0...6, tickStep: 1,
            isTrickyFlip: false, flipExplanation: nil
        ),
        StoryProblem(
            id: 7, emoji: "💧",
            storyPrefix: "A water tank holds ",
            keyPhrase: "no more than 500 gallons",
            storySuffix: ".",
            variableName: "G", variableDefinition: "G = gallons of water",
            boundary: 500, symbol: .atMost,
            axisRange: 0...1000, tickStep: 100,
            isTrickyFlip: false, flipExplanation: nil
        ),
        StoryProblem(
            id: 8, emoji: "🚗",
            storyPrefix: "A car must travel ",
            keyPhrase: "at least 60 mph",
            storySuffix: " to keep up with highway traffic.",
            variableName: "S", variableDefinition: "S = speed (mph)",
            boundary: 60, symbol: .atLeast,
            axisRange: 40...80, tickStep: 5,
            isTrickyFlip: false, flipExplanation: nil
        ),
        StoryProblem(
            id: 9, emoji: "🍕",
            storyPrefix: "A pizza party needs ",
            keyPhrase: "more than 4 pizzas",
            storySuffix: " to feed everyone.",
            variableName: "P", variableDefinition: "P = number of pizzas",
            boundary: 4, symbol: .greaterThan,
            axisRange: 0...8, tickStep: 1,
            isTrickyFlip: false, flipExplanation: nil
        ),
        StoryProblem(
            id: 10, emoji: "🎒",
            storyPrefix: "Your backpack can hold ",
            keyPhrase: "at most 25 pounds",
            storySuffix: ".",
            variableName: "W", variableDefinition: "W = weight (pounds)",
            boundary: 25, symbol: .atMost,
            axisRange: 0...50, tickStep: 5,
            isTrickyFlip: false, flipExplanation: nil
        ),
    ]
}

// MARK: - Root View

public struct CompoundInequalitiesInteractiveView: View {
    private let state: InequalityExplorerState

    public init() {
        self.state = InequalityExplorerState()
    }

    init(state: InequalityExplorerState) {
        self.state = state
    }

    public var body: some View {
        ZStack {
            ExplorerTheme.canvas.ignoresSafeArea()
            StudentModeView(state: state)
        }
    }
}

// MARK: - Student Mode

enum StudentActivity: String, CaseIterable, Identifiable {
    case symbolToGraph
    case graphToSymbol
    case storyToSymbol

    var id: String { rawValue }

    var title: String {
        switch self {
        case .symbolToGraph: return "Symbol → Graph"
        case .graphToSymbol: return "Graph → Symbol"
        case .storyToSymbol: return "Story → Symbol"
        }
    }

    var scoringKeyPrefixes: [String] {
        switch self {
        case .symbolToGraph:
            return ["graph/"]
        case .graphToSymbol:
            return ["read/", "read-forms/"]
        case .storyToSymbol:
            return ["story/", "story-cata/"]
        }
    }
}

enum ProblemReviewStatus: Equatable {
    case none
    case correct
    case missed
    case retry
}

struct SymbolToGraphDraft: Equatable {
    var pointValue: Double
    var dotChoice: Bool?
    var hasAdjustedGraph: Bool
    var feedback: WorkspaceFeedback?
    var attemptCount: Int
    var solved: Bool

    static func initial(for problem: StoryProblem, reviewStatus: ProblemReviewStatus) -> SymbolToGraphDraft {
        SymbolToGraphDraft(
            pointValue: SymbolToGraphWorkspace.initialPointValue(for: problem, reviewStatus: reviewStatus),
            dotChoice: SymbolToGraphWorkspace.initialDotChoice(for: problem, reviewStatus: reviewStatus),
            hasAdjustedGraph: reviewStatus != .none,
            feedback: SymbolToGraphWorkspace.initialFeedback(for: problem, reviewStatus: reviewStatus),
            attemptCount: 0,
            solved: reviewStatus == .correct
        )
    }
}

@MainActor
@Observable
final class InequalityExplorerState {
    var activity: StudentActivity = .symbolToGraph
    /// Each activity tab runs its own sequence through the questions.
    var progressByActivity: [StudentActivity: Int] = [:]
    var reviewProblemIDsByActivity: [StudentActivity: Set<Int>] = [:]
    var retryProblemIDsByActivity: [StudentActivity: Set<Int>] = [:]
    var completedReviewActivities: Set<StudentActivity> = []
    var symbolToGraphDrafts: [Int: SymbolToGraphDraft] = [:]
    var sectionSummary: SectionSummary?
    var showingFinalSummary = false
    var session = StudentSession()
}

@MainActor
enum InequalityExplorerStateRegistry {
    private static var statesByWidgetID: [WidgetObject.ID: InequalityExplorerState] = [:]

    static func state(for widgetID: WidgetObject.ID) -> InequalityExplorerState {
        if let state = statesByWidgetID[widgetID] {
            return state
        }
        let state = InequalityExplorerState()
        statesByWidgetID[widgetID] = state
        return state
    }

    static func removeState(for widgetID: WidgetObject.ID) {
        statesByWidgetID.removeValue(forKey: widgetID)
    }
}

private struct StudentModeView: View {
    @Bindable private var state: InequalityExplorerState

    init(state: InequalityExplorerState) {
        self.state = state
    }

    private var activeProblemIndex: Int {
        state.progressByActivity[state.activity] ?? 0
    }

    private var selectedProblem: StoryProblem {
        StoryProblem.all[activeProblemIndex]
    }

    /// Solved problems, most recently completed first (they stack up under
    /// the active card in the carousel).
    private var completedProblems: [StoryProblem] {
        Array(StoryProblem.all[..<activeProblemIndex].reversed())
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                HStack(alignment: .top, spacing: 12) {
                    StoryListPanel(
                        activeProblem: selectedProblem,
                        completedProblems: completedProblems,
                        reviewProblemIDs: activeReviewProblemIDs,
                        onSelectProblem: selectProblem
                    )
                    .frame(width: 220)

                    workspace
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    ReferencePanel()
                        .frame(width: 190)
                }
                .padding([.horizontal, .bottom], 12)
            }

            if let sectionSummary = state.sectionSummary {
                SectionCompletionDialog(
                    summary: sectionSummary,
                    onDismiss: { dismissSectionSummary(sectionSummary) },
                    onNextSection: { moveToNextSection(after: sectionSummary.activity) }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            if state.showingFinalSummary {
                FinalSummaryDialog(
                    summaries: StudentActivity.allCases.map(makeSectionSummary),
                    onRedoSection: redoSection,
                    onRedoAll: redoAllSections,
                    onDismiss: { state.showingFinalSummary = false }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            ActivityModeSelector(selection: $state.activity)
                .frame(width: 520)

            Spacer()

            statPill(icon: "star.fill", tint: ExplorerTheme.purple, text: "\(state.session.score) pts")
            statPill(icon: "flame.fill", tint: ExplorerTheme.amber, text: "\(state.session.streak)")

            Button {
                state.showingFinalSummary = true
            } label: {
                Text("Mark Complete")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ExplorerTheme.purple)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(Capsule().fill(ExplorerTheme.card))
                    .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
            }
            .buttonStyle(.plain)
        }
    }

    private func statPill(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(ExplorerTheme.textPrimary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Capsule().fill(ExplorerTheme.card))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }

    @ViewBuilder
    private var workspace: some View {
        switch state.activity {
        case .symbolToGraph:
            SymbolToGraphWorkspace(
                problem: selectedProblem,
                session: $state.session,
                draft: symbolToGraphDraftBinding(for: selectedProblem, reviewStatus: reviewStatus(for: selectedProblem)),
                reviewStatus: reviewStatus(for: selectedProblem),
                hasRemainingMissedProblems: hasRemainingReviewProblems(after: selectedProblem, in: .symbolToGraph),
                isReviewComplete: state.completedReviewActivities.contains(.symbolToGraph),
                onRetryProblem: { retryProblem(selectedProblem, in: .symbolToGraph) },
                onReviewProblemComplete: { completeReviewProblem(selectedProblem, in: .symbolToGraph) },
                onNextSection: { moveToNextSection(after: .symbolToGraph) },
                onNextProblem: advanceToNextProblem
            )
            .id("graph-\(selectedProblem.id)-\(reviewStatus(for: selectedProblem))-\(state.completedReviewActivities.contains(.symbolToGraph))")
        case .graphToSymbol:
            GraphToSymbolWorkspace(
                problem: selectedProblem,
                session: $state.session,
                reviewStatus: reviewStatus(for: selectedProblem),
                hasRemainingMissedProblems: hasRemainingReviewProblems(after: selectedProblem, in: .graphToSymbol),
                isReviewComplete: state.completedReviewActivities.contains(.graphToSymbol),
                onRetryProblem: { retryProblem(selectedProblem, in: .graphToSymbol) },
                onReviewProblemComplete: { completeReviewProblem(selectedProblem, in: .graphToSymbol) },
                onNextSection: { moveToNextSection(after: .graphToSymbol) },
                onNextProblem: advanceToNextProblem
            )
            .id("read-\(selectedProblem.id)-\(reviewStatus(for: selectedProblem))-\(state.completedReviewActivities.contains(.graphToSymbol))")
        case .storyToSymbol:
            StoryToSymbolWorkspace(
                problem: selectedProblem,
                session: $state.session,
                reviewStatus: reviewStatus(for: selectedProblem),
                hasRemainingMissedProblems: hasRemainingReviewProblems(after: selectedProblem, in: .storyToSymbol),
                isReviewComplete: state.completedReviewActivities.contains(.storyToSymbol),
                onRetryProblem: { retryProblem(selectedProblem, in: .storyToSymbol) },
                onReviewProblemComplete: { completeReviewProblem(selectedProblem, in: .storyToSymbol) },
                onNextSection: { state.showingFinalSummary = true },
                onNextProblem: advanceToNextProblem
            )
            // Recreate workspace state whenever the problem changes.
            .id("story-\(selectedProblem.id)-\(reviewStatus(for: selectedProblem))-\(state.completedReviewActivities.contains(.storyToSymbol))")
        }
    }

    private var activeReviewProblemIDs: Set<Int> {
        state.reviewProblemIDsByActivity[state.activity, default: []]
            .union(state.retryProblemIDsByActivity[state.activity, default: []])
    }

    private func advanceToNextProblem() {
        guard activeProblemIndex + 1 < StoryProblem.all.count else {
            withAnimation(.easeOut(duration: 0.2)) {
                state.sectionSummary = makeSectionSummary(for: state.activity)
            }
            return
        }
        withAnimation(.easeInOut(duration: 0.35)) {
            state.progressByActivity[state.activity] = activeProblemIndex + 1
        }
    }

    private func makeSectionSummary(for activity: StudentActivity) -> SectionSummary {
        let problemIDs = StoryProblem.all.map(\.id)
        let missedIDs = problemIDs.filter { problemID in
            activity.scoringKeyPrefixes.contains { prefix in
                state.session.erroredKeys.contains("\(prefix)\(problemID)")
            }
        }
        let correctIDs = problemIDs.filter { problemID in
            let hasSolvedRecord = activity.scoringKeyPrefixes.contains { prefix in
                state.session.solvedKeys.contains("\(prefix)\(problemID)")
            }
            return hasSolvedRecord && !missedIDs.contains(problemID)
        }
        let total = StoryProblem.all.count
        return SectionSummary(
            activity: activity,
            correctCount: correctIDs.count,
            totalCount: total,
            missedProblemIDs: missedIDs
        )
    }

    private func dismissSectionSummary(_ summary: SectionSummary) {
        withAnimation(.easeOut(duration: 0.2)) {
            state.reviewProblemIDsByActivity[summary.activity] = Set(summary.missedProblemIDs)
            state.retryProblemIDsByActivity[summary.activity] = []
            state.sectionSummary = nil
        }
    }

    private func moveToNextSection(after activity: StudentActivity) {
        let allActivities = StudentActivity.allCases
        guard let index = allActivities.firstIndex(of: activity) else { return }
        let nextActivity = allActivities.index(after: index) < allActivities.endIndex
            ? allActivities[allActivities.index(after: index)]
            : allActivities[0]
        withAnimation(.easeInOut(duration: 0.25)) {
            state.sectionSummary = nil
            state.completedReviewActivities.remove(activity)
            state.activity = nextActivity
            state.progressByActivity[nextActivity] = state.progressByActivity[nextActivity] ?? 0
        }
    }

    private func selectProblem(_ problem: StoryProblem) {
        guard let index = StoryProblem.all.firstIndex(where: { $0.id == problem.id }) else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            state.progressByActivity[state.activity] = index
        }
    }

    private func reviewStatus(for problem: StoryProblem) -> ProblemReviewStatus {
        if state.retryProblemIDsByActivity[state.activity, default: []].contains(problem.id) {
            return .retry
        }
        let reviewIDs = state.reviewProblemIDsByActivity[state.activity, default: []]
        guard !reviewIDs.isEmpty else { return .none }
        return reviewIDs.contains(problem.id) ? .missed : .correct
    }

    private func retryProblem(_ problem: StoryProblem, in activity: StudentActivity) {
        withAnimation(.easeInOut(duration: 0.25)) {
            state.completedReviewActivities.remove(activity)
            state.reviewProblemIDsByActivity[activity, default: []].remove(problem.id)
            state.retryProblemIDsByActivity[activity, default: []].insert(problem.id)
            if activity == .symbolToGraph {
                state.symbolToGraphDrafts[problem.id] = SymbolToGraphDraft.initial(for: problem, reviewStatus: .retry)
            }
            state.session.reset(problemID: problem.id, keyPrefixes: activity.scoringKeyPrefixes)
        }
    }

    private func completeReviewProblem(_ problem: StoryProblem, in activity: StudentActivity) {
        state.session.markReviewComplete(problemID: problem.id, keyPrefixes: activity.scoringKeyPrefixes)

        state.retryProblemIDsByActivity[activity, default: []].remove(problem.id)
        state.reviewProblemIDsByActivity[activity, default: []].remove(problem.id)
        state.completedReviewActivities.remove(activity)

        let remainingMissedIDs = activeReviewProblemIDs(for: activity).sorted()
        guard let nextID = remainingMissedIDs.first(where: { $0 > problem.id }) ?? remainingMissedIDs.first,
              let nextIndex = StoryProblem.all.firstIndex(where: { $0.id == nextID }) else {
            withAnimation(.easeInOut(duration: 0.25)) {
                state.completedReviewActivities.insert(activity)
            }
            return
        }

        withAnimation(.easeInOut(duration: 0.25)) {
            state.progressByActivity[activity] = nextIndex
        }
    }

    private func redoSection(_ activity: StudentActivity) {
        withAnimation(.easeInOut(duration: 0.25)) {
            state.session.reset(keysWithPrefixes: activity.scoringKeyPrefixes)
            state.progressByActivity[activity] = 0
            state.reviewProblemIDsByActivity[activity] = []
            state.retryProblemIDsByActivity[activity] = []
            state.completedReviewActivities.remove(activity)
            if activity == .symbolToGraph {
                state.symbolToGraphDrafts = [:]
            }
            state.sectionSummary = nil
            state.showingFinalSummary = false
            state.activity = activity
        }
    }

    private func redoAllSections() {
        withAnimation(.easeInOut(duration: 0.25)) {
            let allPrefixes = StudentActivity.allCases.flatMap(\.scoringKeyPrefixes)
            state.session.reset(keysWithPrefixes: allPrefixes)
            state.progressByActivity = [:]
            state.reviewProblemIDsByActivity = [:]
            state.retryProblemIDsByActivity = [:]
            state.completedReviewActivities = []
            state.symbolToGraphDrafts = [:]
            state.sectionSummary = nil
            state.showingFinalSummary = false
            state.activity = .symbolToGraph
        }
    }

    private func symbolToGraphDraftBinding(
        for problem: StoryProblem,
        reviewStatus: ProblemReviewStatus
    ) -> Binding<SymbolToGraphDraft> {
        Binding {
            state.symbolToGraphDrafts[problem.id] ?? SymbolToGraphDraft.initial(for: problem, reviewStatus: reviewStatus)
        } set: { newValue in
            state.symbolToGraphDrafts[problem.id] = newValue
        }
    }

    private func activeReviewProblemIDs(for activity: StudentActivity) -> Set<Int> {
        state.reviewProblemIDsByActivity[activity, default: []]
            .union(state.retryProblemIDsByActivity[activity, default: []])
    }

    private func hasRemainingReviewProblems(after problem: StoryProblem, in activity: StudentActivity) -> Bool {
        activeReviewProblemIDs(for: activity)
            .subtracting([problem.id])
            .isEmpty == false
    }
}

private struct ActivityModeSelector: View {
    @Binding var selection: StudentActivity

    var body: some View {
        HStack(spacing: 3) {
            ForEach(StudentActivity.allCases) { activity in
                Button {
                    selection = activity
                } label: {
                    Text(activity.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selection == activity ? .white : ExplorerTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(selection == activity ? ExplorerTheme.purple : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: ExplorerTheme.buttonCornerRadius)
                .fill(Color.black.opacity(0.07))
        )
    }
}

// MARK: - Student Session (score, streak, attempt records)

struct StudentSession {
    struct MissedProblem {
        let inequality: String
        let note: String
    }

    var score = 0
    var streak = 0
    var longestStreak = 0
    private(set) var solvedKeys: Set<String> = []
    private(set) var erroredKeys: Set<String> = []
    private var pointsByKey: [String: Int] = [:]
    /// First error per task, kept for the summary screen.
    private(set) var missed: [String: MissedProblem] = [:]

    /// Every task attempted (solved or errored) counts toward the max possible score.
    var attemptedCount: Int { solvedKeys.union(erroredKeys).count }

    mutating func recordCorrect(key: String, points: Int, firstAttempt: Bool) {
        guard !solvedKeys.contains(key) else { return }
        solvedKeys.insert(key)
        pointsByKey[key] = points
        score += points
        if firstAttempt {
            streak += 1
            longestStreak = max(longestStreak, streak)
        }
    }

    mutating func recordError(key: String, inequality: String, note: String) {
        streak = 0
        erroredKeys.insert(key)
        if missed[key] == nil {
            missed[key] = MissedProblem(inequality: inequality, note: note)
        }
    }

    mutating func reset(keysWithPrefixes prefixes: [String]) {
        let keysToReset = solvedKeys
            .union(erroredKeys)
            .filter { key in
                prefixes.contains { key.hasPrefix($0) }
            }
        for key in keysToReset {
            if let points = pointsByKey[key] {
                score = max(0, score - points)
            }
            pointsByKey.removeValue(forKey: key)
            solvedKeys.remove(key)
            erroredKeys.remove(key)
            missed.removeValue(forKey: key)
        }
        streak = 0
    }

    mutating func reset(problemID: Int, keyPrefixes prefixes: [String]) {
        let keysToReset = solvedKeys
            .union(erroredKeys)
            .filter { key in
                prefixes.contains { prefix in key == "\(prefix)\(problemID)" }
            }
        for key in keysToReset {
            if let points = pointsByKey[key] {
                score = max(0, score - points)
            }
            pointsByKey.removeValue(forKey: key)
            solvedKeys.remove(key)
            erroredKeys.remove(key)
            missed.removeValue(forKey: key)
        }
        streak = 0
    }

    mutating func markReviewComplete(problemID: Int, keyPrefixes prefixes: [String]) {
        let keysToComplete = erroredKeys.filter { key in
            prefixes.contains { prefix in key == "\(prefix)\(problemID)" }
        }
        for key in keysToComplete {
            erroredKeys.remove(key)
            missed.removeValue(forKey: key)
        }
    }
}

// MARK: - Section Completion

struct SectionSummary: Equatable, Identifiable {
    let activity: StudentActivity
    let correctCount: Int
    let totalCount: Int
    let missedProblemIDs: [Int]

    var id: String { activity.id }
    var passed: Bool { correctCount >= 7 }
}

private struct SectionCompletionDialog: View {
    let summary: SectionSummary
    let onDismiss: () -> Void
    let onNextSection: () -> Void

    private var title: String {
        summary.passed ? "\(summary.activity.title) Complete" : "Keep Practicing"
    }

    private var message: String {
        if summary.missedProblemIDs.isEmpty {
            return "Strong work. You completed this section without missing any problems."
        }

        let missedList = summary.missedProblemIDs.map(String.init).joined(separator: ", ")
        return "You missed problems \(missedList). Review the highlighted cards on the left, retry only those problems, or move on to the next section."
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: summary.passed ? "checkmark.seal.fill" : "arrow.clockwise.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(summary.passed ? ExplorerTheme.green : ExplorerTheme.amber)

                VStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(ExplorerTheme.textPrimary)

                    Text("\(summary.correctCount) out of \(summary.totalCount) correct")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(summary.passed ? ExplorerTheme.green : ExplorerTheme.orange)
                }

                Text(message)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(ExplorerTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Button(action: onDismiss) {
                        Text(summary.missedProblemIDs.isEmpty ? "Dismiss" : "Review Missed")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(ExplorerTheme.purple)
                            .padding(.horizontal, 22)
                            .frame(height: 42)
                            .background(Capsule().fill(ExplorerTheme.purple.opacity(0.12)))
                    }
                    .buttonStyle(.plain)

                    Button(action: onNextSection) {
                        Text("Next Section")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 22)
                            .frame(height: 42)
                            .background(Capsule().fill(ExplorerTheme.green))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(26)
            .frame(width: 420)
            .background(
                RoundedRectangle(cornerRadius: ExplorerTheme.cardCornerRadius)
                    .fill(ExplorerTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ExplorerTheme.cardCornerRadius)
                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        }
    }
}

private struct FinalSummaryDialog: View {
    let summaries: [SectionSummary]
    let onRedoSection: (StudentActivity) -> Void
    let onRedoAll: () -> Void
    let onDismiss: () -> Void

    private var totalCorrect: Int {
        summaries.reduce(0) { $0 + $1.correctCount }
    }

    private var totalPossible: Int {
        summaries.reduce(0) { $0 + $1.totalCount }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Final Summary")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(ExplorerTheme.textPrimary)
                        Text("Review section scores or redo any section from the beginning.")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(ExplorerTheme.textSecondary)
                    }
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(ExplorerTheme.textSecondary)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.black.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }

                VStack(spacing: 10) {
                    ForEach(summaries) { summary in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(summary.activity.title)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(ExplorerTheme.textPrimary)
                                Text("\(summary.correctCount) out of \(summary.totalCount) correct")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(summary.passed ? ExplorerTheme.green : ExplorerTheme.orange)
                            }

                            Spacer()

                            Button {
                                onRedoSection(summary.activity)
                            } label: {
                                Text("Redo")
                                    .font(.system(size: 13.5, weight: .bold))
                                    .foregroundStyle(ExplorerTheme.purple)
                                    .padding(.horizontal, 16)
                                    .frame(height: 34)
                                    .background(Capsule().fill(ExplorerTheme.purple.opacity(0.12)))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: ExplorerTheme.buttonCornerRadius)
                                .fill(Color.black.opacity(0.04))
                        )
                    }
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Total")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(ExplorerTheme.textPrimary)
                        Text("\(totalCorrect) out of \(totalPossible) correct")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(totalCorrect >= 21 ? ExplorerTheme.green : ExplorerTheme.orange)
                    }
                    Spacer()
                    Button(action: onRedoAll) {
                        Text("Redo All")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .frame(height: 40)
                            .background(Capsule().fill(ExplorerTheme.purple))
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: ExplorerTheme.buttonCornerRadius)
                        .fill(ExplorerTheme.green.opacity(0.12))
                )
            }
            .padding(24)
            .frame(width: 520)
            .background(
                RoundedRectangle(cornerRadius: ExplorerTheme.cardCornerRadius)
                    .fill(ExplorerTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ExplorerTheme.cardCornerRadius)
                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        }
    }
}

// MARK: - Interactive Number Line

/// The shared draggable number line: arrow-capped axis, per-problem ticks,
/// a tappable boundary dot the student fills (closed) or leaves open, a
/// draggable arrow endpoint, and live shading between boundary and arrow.
private struct InteractiveNumberLine: View {
    let axisRange: ClosedRange<Double>
    let tickStep: Double
    let boundary: Double
    @Binding var dotClosed: Bool
    @Binding var pointValue: Double
    var isEnabled = true
    /// One-time tutorial arrow pointing at the boundary dot.
    var showDotCoachMark = false
    var hintText: String? = "← less than · greater than →  ·  tap the circle to fill or unfill it"

    @State private var isDragging = false
    /// Whether the current drag started close enough to the arrow to move it.
    @State private var dragAccepted: Bool?

    private let edgePadding: CGFloat = 40
    private let dotDiameter: CGFloat = 18

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            Canvas { context, canvasSize in
                draw(context: &context, size: canvasSize, axisY: canvasSize.height * 0.4)
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                guard isEnabled else { return }
                let boundaryX = xPosition(for: boundary, width: size.width)
                if abs(location.x - boundaryX) < 26 {
                    dotClosed.toggle()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { gesture in
                        guard isEnabled else { return }
                        if dragAccepted == nil {
                            let pointX = xPosition(for: pointValue, width: size.width)
                            dragAccepted = abs(gesture.startLocation.x - pointX) < 30
                        }
                        guard dragAccepted == true else { return }
                        isDragging = true
                        pointValue = value(atX: gesture.location.x, width: size.width)
                    }
                    .onEnded { _ in
                        dragAccepted = nil
                        isDragging = false
                    }
            )
        }
    }

    private func xPosition(for value: Double, width: CGFloat) -> CGFloat {
        let fraction = (value - axisRange.lowerBound) / (axisRange.upperBound - axisRange.lowerBound)
        return edgePadding + CGFloat(fraction) * (width - 2 * edgePadding)
    }

    private func value(atX x: CGFloat, width: CGFloat) -> Double {
        let fraction = (x - edgePadding) / (width - 2 * edgePadding)
        let raw = axisRange.lowerBound + Double(fraction) * (axisRange.upperBound - axisRange.lowerBound)
        return min(max(raw, axisRange.lowerBound), axisRange.upperBound)
    }

    private func draw(context: inout GraphicsContext, size: CGSize, axisY: CGFloat) {
        let axisColor = Color.black.opacity(0.35)
        let axisLeft: CGFloat = 10
        let axisRight = size.width - 10

        // Axis with arrow caps on both ends.
        var axis = Path()
        axis.move(to: CGPoint(x: axisLeft, y: axisY))
        axis.addLine(to: CGPoint(x: axisRight, y: axisY))
        context.stroke(axis, with: .color(axisColor), lineWidth: 2)
        context.fill(arrowhead(tip: CGPoint(x: axisLeft, y: axisY), pointingRight: false), with: .color(axisColor))
        context.fill(arrowhead(tip: CGPoint(x: axisRight, y: axisY), pointingRight: true), with: .color(axisColor))

        // Shading between the boundary and the student's point.
        let boundaryX = xPosition(for: boundary, width: size.width)
        let pointX = xPosition(for: pointValue, width: size.width)
        if abs(pointX - boundaryX) > 1 {
            let shadeRect = CGRect(
                x: min(boundaryX, pointX), y: axisY - 5,
                width: abs(pointX - boundaryX), height: 10
            )
            context.fill(
                Path(roundedRect: shadeRect, cornerRadius: 5),
                with: .color(ExplorerTheme.purple.opacity(0.35))
            )
        }

        // Tick marks and labels.
        for tick in stride(from: axisRange.lowerBound, through: axisRange.upperBound + tickStep / 2, by: tickStep) {
            let tickValue = min(tick, axisRange.upperBound)
            let x = xPosition(for: tickValue, width: size.width)
            let isBoundary = abs(tickValue - boundary) < tickStep / 100

            var tickPath = Path()
            tickPath.move(to: CGPoint(x: x, y: axisY - 6))
            tickPath.addLine(to: CGPoint(x: x, y: axisY + 6))
            context.stroke(tickPath, with: .color(axisColor), lineWidth: isBoundary ? 2 : 1)

            let label = Text(StoryProblem.formatted(tickValue))
                .font(.system(size: isBoundary ? 14 : 11, weight: isBoundary ? .bold : .regular))
                .foregroundStyle(isBoundary ? ExplorerTheme.purple : ExplorerTheme.textSecondary)
            context.draw(label, at: CGPoint(x: x, y: axisY + 19))
        }

        // Draggable endpoint: an arrowhead so the graph reads as a ray, not
        // an interval. Before the first drag (arrow still at the boundary),
        // show chevrons either side of the dot as a drag affordance.
        let delta = pointX - boundaryX
        if abs(delta) <= 2 {
            for direction in [-1.0, 1.0] {
                let tip = CGPoint(x: boundaryX + direction * 22, y: axisY)
                context.fill(
                    arrowhead(tip: tip, pointingRight: direction > 0, length: 9, halfWidth: 6),
                    with: .color(ExplorerTheme.purple.opacity(0.45))
                )
            }
        } else {
            let pointingRight = delta > 0
            let scale: CGFloat = isDragging ? 1.15 : 1
            let tip = CGPoint(x: pointX + (pointingRight ? 3 : -3), y: axisY)
            // White halo so the arrow stands out over the shading.
            context.fill(
                arrowhead(tip: CGPoint(x: tip.x + (pointingRight ? 2.5 : -2.5), y: axisY),
                          pointingRight: pointingRight,
                          length: 21 * scale, halfWidth: 13 * scale),
                with: .color(.white)
            )
            context.fill(
                arrowhead(tip: tip, pointingRight: pointingRight,
                          length: 17 * scale, halfWidth: 10 * scale),
                with: .color(ExplorerTheme.purple)
            )
        }

        // Boundary dot (open or closed), drawn over the shading.
        let dotRect = CGRect(
            x: boundaryX - dotDiameter / 2, y: axisY - dotDiameter / 2,
            width: dotDiameter, height: dotDiameter
        )
        if dotClosed {
            context.fill(Path(ellipseIn: dotRect), with: .color(ExplorerTheme.purple))
        } else {
            context.fill(Path(ellipseIn: dotRect), with: .color(.white))
            context.stroke(
                Path(ellipseIn: dotRect.insetBy(dx: 1.25, dy: 1.25)),
                with: .color(ExplorerTheme.purple), lineWidth: 2.5
            )
        }

        if showDotCoachMark {
            drawDotCoachMark(in: &context, boundaryX: boundaryX, axisY: axisY)
        }

        // Direction hint below the center of the line.
        if let hintText {
            let hint = Text(hintText)
                .font(.system(size: 11))
                .foregroundStyle(ExplorerTheme.textSecondary.opacity(0.8))
            context.draw(hint, at: CGPoint(x: size.width / 2, y: axisY + 40))
        }
    }

    private func arrowhead(tip: CGPoint, pointingRight: Bool, length: CGFloat = 11, halfWidth: CGFloat = 6) -> Path {
        let back = pointingRight ? tip.x - length : tip.x + length
        var path = Path()
        path.move(to: tip)
        path.addLine(to: CGPoint(x: back, y: tip.y - halfWidth))
        path.addLine(to: CGPoint(x: back, y: tip.y + halfWidth))
        path.closeSubpath()
        return path
    }

    /// A curved red arrow swooping down onto the boundary dot, with a short
    /// instruction label at its tail.
    private func drawDotCoachMark(in context: inout GraphicsContext, boundaryX: CGFloat, axisY: CGFloat) {
        let red = Color.red
        let start = CGPoint(x: boundaryX + 96, y: max(axisY - 28, 18))
        let control = CGPoint(x: boundaryX + 34, y: max(axisY - 46, 2))
        let end = CGPoint(x: boundaryX + 8, y: axisY - 14)

        var curve = Path()
        curve.move(to: start)
        curve.addQuadCurve(to: end, control: control)
        context.stroke(curve, with: .color(red), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

        // Arrowhead aligned with the curve's direction at its end.
        let dx = end.x - control.x
        let dy = end.y - control.y
        let length = max((dx * dx + dy * dy).squareRoot(), 0.001)
        let ux = dx / length, uy = dy / length
        var head = Path()
        head.move(to: end)
        head.addLine(to: CGPoint(x: end.x - ux * 10 - uy * 5, y: end.y - uy * 10 + ux * 5))
        head.addLine(to: CGPoint(x: end.x - ux * 10 + uy * 5, y: end.y - uy * 10 - ux * 5))
        head.closeSubpath()
        context.fill(head, with: .color(red))

        let label = Text("Touch the point\nto toggle inclusion")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(red)
        context.draw(label, at: CGPoint(x: start.x + 6, y: start.y), anchor: .leading)
    }
}

// MARK: - Inequality Builder

/// The inequality with a blank slot: "H [ ? ] 48", with the four symbol
/// choices underneath. Tapping a symbol fills the slot; tapping the filled
/// slot clears it. Used by Story → Symbol and Graph → Symbol.
private struct InequalityBuilder: View {
    let variableName: String
    let boundaryText: String
    @Binding var selectedSymbol: InequalitySymbol?
    var isLocked = false

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                valueBox(text: variableName, textColor: ExplorerTheme.purple,
                         background: ExplorerTheme.purple.opacity(0.12))

                symbolSlot

                valueBox(text: boundaryText, textColor: ExplorerTheme.textPrimary,
                         background: Color.black.opacity(0.05))
            }

            HStack(spacing: 10) {
                ForEach(InequalitySymbol.allCases) { symbol in
                    symbolButton(symbol)
                }
            }
        }
    }

    /// The blank the student fills by tapping a symbol below.
    private var symbolSlot: some View {
        Group {
            if let symbol = selectedSymbol {
                Text(symbol.rawValue)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: ExplorerTheme.buttonCornerRadius)
                            .fill(ExplorerTheme.purple)
                    )
            } else {
                Text("?")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(ExplorerTheme.textSecondary.opacity(0.7))
                    .frame(width: 52, height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: ExplorerTheme.buttonCornerRadius)
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                            .foregroundStyle(Color.black.opacity(0.25))
                    )
            }
        }
        .onTapGesture {
            if !isLocked {
                selectedSymbol = nil
            }
        }
    }

    private func valueBox(text: String, textColor: Color, background: Color) -> some View {
        Text(text)
            .font(.system(size: 24, weight: .bold))
            .foregroundStyle(textColor)
            .monospacedDigit()
            .padding(.horizontal, 16)
            .frame(minWidth: 56, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: ExplorerTheme.buttonCornerRadius)
                    .fill(background)
            )
    }

    private func symbolButton(_ symbol: InequalitySymbol) -> some View {
        let isSelected = selectedSymbol == symbol
        return Button {
            selectedSymbol = symbol
        } label: {
            Text(symbol.rawValue)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(isSelected ? .white : ExplorerTheme.textSecondary)
                .frame(width: 52, height: 52)
                .background(
                    RoundedRectangle(cornerRadius: ExplorerTheme.buttonCornerRadius)
                        .fill(isSelected ? ExplorerTheme.purple : Color.black.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ExplorerTheme.buttonCornerRadius)
                        .strokeBorder(isSelected ? ExplorerTheme.purple : Color.black.opacity(0.15), lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
    }
}

// MARK: - Feedback Card

struct WorkspaceFeedback: Equatable {
    enum Kind {
        case success
        case adjust
        case incorrect
    }

    let kind: Kind
    let message: String

    var color: Color {
        switch kind {
        case .success: return ExplorerTheme.green
        case .adjust: return Color(red: 0.42, green: 0.47, blue: 0.86)
        case .incorrect: return ExplorerTheme.orange
        }
    }

    var icon: String {
        switch kind {
        case .success: return "checkmark.circle.fill"
        case .adjust: return "arrow.left.arrow.right.circle.fill"
        case .incorrect: return "xmark.circle.fill"
        }
    }
}

private struct FeedbackCard: View {
    let feedback: WorkspaceFeedback

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: feedback.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
            Text(feedback.message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: ExplorerTheme.cardCornerRadius)
                .fill(feedback.color)
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Mode 3: Story → Symbol

private struct StoryToSymbolWorkspace: View {
    let problem: StoryProblem
    @Binding var session: StudentSession
    let reviewStatus: ProblemReviewStatus
    let hasRemainingMissedProblems: Bool
    let isReviewComplete: Bool
    let onRetryProblem: () -> Void
    let onReviewProblemComplete: () -> Void
    let onNextSection: () -> Void
    let onNextProblem: () -> Void

    @State private var pointValue: Double
    @State private var selectedSymbol: InequalitySymbol?
    /// The student's open/closed choice for the boundary dot. Starts open.
    @State private var studentDotClosed = false
    @State private var feedback: WorkspaceFeedback?
    @State private var attemptCount = 0
    @State private var solved = false
    @State private var hasAdjustedGraph = false
    @State private var hasToggledDot = false
    @State private var choicesAttempted = false
    /// True while the student is mid-retry on the choices (after Try Again,
    /// before re-checking) — Next Problem dims until they check again.
    @State private var awaitingRecheck = false

    init(
        problem: StoryProblem,
        session: Binding<StudentSession>,
        reviewStatus: ProblemReviewStatus = .none,
        hasRemainingMissedProblems: Bool = false,
        isReviewComplete: Bool = false,
        onRetryProblem: @escaping () -> Void = {},
        onReviewProblemComplete: @escaping () -> Void = {},
        onNextSection: @escaping () -> Void = {},
        onNextProblem: @escaping () -> Void
    ) {
        self.problem = problem
        self._session = session
        self.reviewStatus = reviewStatus
        self.hasRemainingMissedProblems = hasRemainingMissedProblems
        self.isReviewComplete = isReviewComplete
        self.onRetryProblem = onRetryProblem
        self.onReviewProblemComplete = onReviewProblemComplete
        self.onNextSection = onNextSection
        self.onNextProblem = onNextProblem
        self._pointValue = State(initialValue: Self.initialPointValue(for: problem, reviewStatus: reviewStatus))
        self._selectedSymbol = State(initialValue: Self.initialSymbol(for: problem, reviewStatus: reviewStatus))
        self._studentDotClosed = State(initialValue: Self.initialDotClosed(for: problem, reviewStatus: reviewStatus))
        self._hasAdjustedGraph = State(initialValue: reviewStatus != .none)
        self._hasToggledDot = State(initialValue: reviewStatus != .none)
        self._solved = State(initialValue: reviewStatus == .correct)
        self._feedback = State(initialValue: Self.initialFeedback(for: problem, reviewStatus: reviewStatus))
    }

    private var formattedBoundary: String { StoryProblem.formatted(problem.boundary) }

    /// Checking requires a filled-in symbol and at least one graph adjustment —
    /// neither has to be correct.
    private var canCheck: Bool {
        selectedSymbol != nil && hasAdjustedGraph && !solved && reviewStatus != .missed && !isReviewComplete
    }

    private func handleChoicesResult(fullCredit: Bool, firstAttempt: Bool, errorNote: String?) {
        let key = "story-cata/\(problem.id)"
        if fullCredit {
            session.recordCorrect(key: key, points: 10, firstAttempt: firstAttempt)
        } else {
            session.recordError(
                key: key, inequality: problem.inequalityText,
                note: errorNote ?? "Chose incorrect values for \(problem.inequalityText)"
            )
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                storyHeader

                InteractiveNumberLine(
                    axisRange: problem.axisRange,
                    tickStep: problem.tickStep,
                    boundary: problem.boundary,
                    dotClosed: $studentDotClosed,
                    pointValue: $pointValue,
                    isEnabled: !solved && reviewStatus != .missed,
                    showDotCoachMark: problem.id == StoryProblem.all[0].id && !hasToggledDot && !solved
                )
                .frame(height: 120)
                .onChange(of: pointValue) { _, _ in
                    hasAdjustedGraph = true
                }
                .onChange(of: studentDotClosed) { _, _ in
                    hasToggledDot = true
                }

                InequalityBuilder(
                    variableName: problem.variableName,
                    boundaryText: formattedBoundary,
                    selectedSymbol: $selectedSymbol,
                    isLocked: solved || reviewStatus == .missed
                )

                checkControls

                if let feedback {
                    FeedbackCard(feedback: feedback)
                }

                if reviewStatus == .missed {
                    retryProblemButton
                }

                if solved && reviewStatus != .missed {
                    CheckAllThatApplySection(
                        problem: problem,
                        onResult: handleChoicesResult,
                        onAnyCheck: {
                            withAnimation(.easeOut(duration: 0.2)) {
                                choicesAttempted = true
                                awaitingRecheck = false
                            }
                        },
                        onRetry: {
                            withAnimation(.easeOut(duration: 0.2)) {
                                awaitingRecheck = true
                            }
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if reviewStatus == .retry && choicesAttempted {
                    reviewNavigationButtons
                }

                if isReviewComplete {
                    reviewCompleteCard
                }

                if choicesAttempted && reviewStatus == .none && !isReviewComplete {
                    Button(action: onNextProblem) {
                        Label("Next Problem", systemImage: "arrow.right")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .frame(height: 44)
                            .background(Capsule().fill(ExplorerTheme.green))
                    }
                    .buttonStyle(.plain)
                    .disabled(awaitingRecheck)
                    .opacity(awaitingRecheck ? 0.4 : 1)
                }
            }
            .padding(18)
        }
        .background(
            RoundedRectangle(cornerRadius: ExplorerTheme.cardCornerRadius)
                .fill(ExplorerTheme.card)
        )
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }

    private var storyHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(problem.emoji)
                .font(.system(size: 30))
            VStack(alignment: .leading, spacing: 3) {
                Text(problem.attributedStory(fontSize: 16))
                    .foregroundStyle(ExplorerTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(problem.variableDefinition)
                    .font(.system(size: 13))
                    .foregroundStyle(ExplorerTheme.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var checkControls: some View {
        if reviewStatus == .retry {
            Button(action: retryPrimaryAction) {
                Text(selectedSymbol == nil ? "Mark Problem Complete" : "Check")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 34)
                    .frame(height: 44)
                    .background(Capsule().fill(selectedSymbol == nil ? ExplorerTheme.green : ExplorerTheme.purple))
            }
            .buttonStyle(.plain)
            .disabled(solved)
            .opacity(solved ? 0.45 : 1)
        } else {
            VStack(spacing: 6) {
                Button(action: check) {
                    Text("Check")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 40)
                        .frame(height: 44)
                        .background(Capsule().fill(ExplorerTheme.purple))
                }
                .buttonStyle(.plain)
                .disabled(!canCheck)
                .opacity(canCheck ? 1 : 0.4)

                if !solved && !canCheck {
                    Text("Drag the point on the number line and fill in the blank, then check.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(ExplorerTheme.textSecondary)
                }
            }
        }
    }

    private var reviewNavigationButtons: some View {
        HStack(spacing: 12) {
            Button(action: resetForRetry) {
                Text("Try Again")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(ExplorerTheme.purple)
                    .padding(.horizontal, 20)
                    .frame(height: 42)
                    .background(Capsule().fill(ExplorerTheme.purple.opacity(0.12)))
            }
            .buttonStyle(.plain)

            if hasRemainingMissedProblems {
                Button(action: onReviewProblemComplete) {
                    Text("Next Missed")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .frame(height: 42)
                        .background(Capsule().fill(ExplorerTheme.green))
                }
                .buttonStyle(.plain)
            }

            Button(action: hasRemainingMissedProblems ? onReviewProblemComplete : onNextSection) {
                Text(hasRemainingMissedProblems ? "Mark Complete" : "Next Practice")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(height: 42)
                    .background(Capsule().fill(ExplorerTheme.green.opacity(0.85)))
            }
            .buttonStyle(.plain)
        }
    }

    private var reviewCompleteCard: some View {
        VStack(spacing: 10) {
            FeedbackCard(feedback: WorkspaceFeedback(kind: .success, message: "All missed problems in this practice are complete. Move to the next practice when you are ready."))
            Button(action: onNextSection) {
                Label("Next Practice", systemImage: "arrow.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .frame(height: 44)
                    .background(Capsule().fill(ExplorerTheme.green))
            }
            .buttonStyle(.plain)
        }
    }

    private func retryPrimaryAction() {
        guard selectedSymbol != nil else {
            onReviewProblemComplete()
            return
        }
        check()
    }

    private var retryProblemButton: some View {
        Button {
            resetForRetry()
        } label: {
            Text("Try Again")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .frame(height: 44)
                .background(Capsule().fill(ExplorerTheme.purple))
        }
        .buttonStyle(.plain)
    }

    private func resetForRetry() {
        pointValue = problem.boundary
        selectedSymbol = nil
        studentDotClosed = false
        feedback = nil
        attemptCount = 0
        solved = false
        hasAdjustedGraph = false
        hasToggledDot = false
        choicesAttempted = false
        awaitingRecheck = false
        onRetryProblem()
    }

    private static func initialPointValue(for problem: StoryProblem, reviewStatus: ProblemReviewStatus) -> Double {
        switch reviewStatus {
        case .correct:
            return problem.symbol.pointsRight ? problem.axisRange.upperBound : problem.axisRange.lowerBound
        case .missed:
            return problem.symbol.pointsRight ? problem.axisRange.lowerBound : problem.axisRange.upperBound
        case .none, .retry:
            return problem.boundary
        }
    }

    private static func initialSymbol(for problem: StoryProblem, reviewStatus: ProblemReviewStatus) -> InequalitySymbol? {
        switch reviewStatus {
        case .correct:
            return problem.symbol
        case .missed:
            return problem.symbol.pointsRight ? .lessThan : .greaterThan
        case .none, .retry:
            return nil
        }
    }

    private static func initialDotClosed(for problem: StoryProblem, reviewStatus: ProblemReviewStatus) -> Bool {
        switch reviewStatus {
        case .correct:
            return problem.symbol.dotIsClosed
        case .missed:
            return !problem.symbol.dotIsClosed
        case .none, .retry:
            return false
        }
    }

    private static func initialFeedback(for problem: StoryProblem, reviewStatus: ProblemReviewStatus) -> WorkspaceFeedback? {
        switch reviewStatus {
        case .correct:
            return WorkspaceFeedback(kind: .success, message: "Correct answer shown: \(problem.inequalityText).")
        case .missed:
            return WorkspaceFeedback(kind: .incorrect, message: "This was one of your missed problems. Your previous work is shown in orange/red style. Tap Try Again to redo only this problem.")
        case .none, .retry:
            return nil
        }
    }

    private func check() {
        guard let symbol = selectedSymbol, !solved else { return }
        attemptCount += 1

        let key = "story/\(problem.id)"
        let symbolCorrect = symbol == problem.symbol
        let delta = pointValue - problem.boundary
        let clearlyMoved = abs(delta) > problem.tickStep * 0.2
        let onCorrectSide = clearlyMoved && ((delta > 0) == problem.symbol.pointsRight)
        let dotCorrect = studentDotClosed == problem.symbol.dotIsClosed
        let direction = problem.symbol.pointsRight ? "right" : "left"
        let dotText = problem.symbol.dotIsClosed
            ? "closed dot, because \(formattedBoundary) itself is included"
            : "open dot, because \(formattedBoundary) itself is not included"

        withAnimation(.easeOut(duration: 0.2)) {
            if symbolCorrect && onCorrectSide && dotCorrect {
                solved = true
                session.recordCorrect(key: key, points: 10, firstAttempt: attemptCount == 1)
                feedback = WorkspaceFeedback(
                    kind: .success,
                    message: "Correct! \(problem.inequalityText) — the solution shades \(direction) from \(formattedBoundary) with a \(dotText)."
                )
            } else if symbolCorrect {
                var fixes: [String] = []
                if !onCorrectSide {
                    fixes.append("drag the arrow to the \(direction) of \(formattedBoundary) — \(symbol.name.lowercased()) means the solution lives on the \(direction) side")
                }
                if !dotCorrect {
                    fixes.append(problem.symbol.dotIsClosed
                        ? "tap the dot to fill it in — \(symbol.rawValue) includes \(formattedBoundary) itself"
                        : "tap the dot to unfill it — \(symbol.rawValue) does not include \(formattedBoundary) itself")
                }
                session.recordError(
                    key: key, inequality: problem.inequalityText,
                    note: "Symbol right, but graph wrong on \(problem.inequalityText) (\(onCorrectSide ? "dot type" : dotCorrect ? "direction" : "direction and dot"))"
                )
                feedback = WorkspaceFeedback(
                    kind: .adjust,
                    message: "Your symbol is right! Now \(fixes.joined(separator: ", and ")). Adjust the graph and check again."
                )
            } else {
                session.recordError(
                    key: key, inequality: problem.inequalityText,
                    note: "Chose wrong symbol — selected \(symbol.rawValue) instead of \(problem.symbol.rawValue)"
                )
                let message: String
                if problem.isTrickyFlip, let flip = problem.flipExplanation {
                    message = "Not quite. \(flip)"
                } else {
                    let sizeWord = problem.symbol.pointsRight ? "bigger" : "smaller"
                    message = "Not quite. The story says \(problem.variableName) must be \(problem.keyPhrase). Numbers \(sizeWord) than \(formattedBoundary) live to the \(direction) on the number line — so \(problem.variableName) needs \(problem.symbol.rawValue) (\(problem.symbol.name.lowercased())). Try again."
                }
                feedback = WorkspaceFeedback(kind: .incorrect, message: message)
            }
        }
    }
}

// MARK: - Mode 1: Symbol → Graph

private struct SymbolToGraphWorkspace: View {
    let problem: StoryProblem
    @Binding var session: StudentSession
    @Binding var draft: SymbolToGraphDraft
    let reviewStatus: ProblemReviewStatus
    let hasRemainingMissedProblems: Bool
    let isReviewComplete: Bool
    let onRetryProblem: () -> Void
    let onReviewProblemComplete: () -> Void
    let onNextSection: () -> Void
    let onNextProblem: () -> Void

    init(
        problem: StoryProblem,
        session: Binding<StudentSession>,
        draft: Binding<SymbolToGraphDraft>,
        reviewStatus: ProblemReviewStatus = .none,
        hasRemainingMissedProblems: Bool = false,
        isReviewComplete: Bool = false,
        onRetryProblem: @escaping () -> Void = {},
        onReviewProblemComplete: @escaping () -> Void = {},
        onNextSection: @escaping () -> Void = {},
        onNextProblem: @escaping () -> Void
    ) {
        self.problem = problem
        self._session = session
        self._draft = draft
        self.reviewStatus = reviewStatus
        self.hasRemainingMissedProblems = hasRemainingMissedProblems
        self.isReviewComplete = isReviewComplete
        self.onRetryProblem = onRetryProblem
        self.onReviewProblemComplete = onReviewProblemComplete
        self.onNextSection = onNextSection
        self.onNextProblem = onNextProblem
    }

    private var formattedBoundary: String { StoryProblem.formatted(problem.boundary) }

    /// The number line shows an open dot until the student chooses.
    private var dotBinding: Binding<Bool> {
        Binding(
            get: { draft.dotChoice ?? false },
            set: { draft.dotChoice = $0 }
        )
    }

    private var canCheck: Bool {
        draft.hasAdjustedGraph && draft.dotChoice != nil && !draft.solved && reviewStatus != .missed && !isReviewComplete
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Text("Draw this on the number line.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(ExplorerTheme.textSecondary)
                    Text(problem.inequalityText)
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                        .foregroundStyle(ExplorerTheme.purple)
                }

                InteractiveNumberLine(
                    axisRange: problem.axisRange,
                    tickStep: problem.tickStep,
                    boundary: problem.boundary,
                    dotClosed: dotBinding,
                    pointValue: $draft.pointValue,
                    isEnabled: !draft.solved && reviewStatus != .missed
                )
                .frame(height: 120)
                .onChange(of: draft.pointValue) { _, _ in
                    draft.hasAdjustedGraph = true
                }

                HStack(spacing: 12) {
                    dotButton(closed: false, label: "Open dot — boundary not included")
                    dotButton(closed: true, label: "Closed dot — boundary is included")
                }

                VStack(spacing: 6) {
                    Button(action: check) {
                        Text("Check")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 40)
                            .frame(height: 44)
                            .background(Capsule().fill(ExplorerTheme.purple))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canCheck)
                    .opacity(canCheck ? 1 : 0.4)

                    if !draft.solved && !canCheck {
                        Text("Drag the arrow to one side and choose a dot type, then check.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(ExplorerTheme.textSecondary)
                    }
                }

                if let feedback = draft.feedback {
                    FeedbackCard(feedback: feedback)
                }

                if reviewStatus == .missed {
                    initialReviewButtons
                }

                if reviewStatus == .retry && (draft.solved || draft.attemptCount > 0) {
                    reviewNavigationButtons
                }

                if isReviewComplete {
                    reviewCompleteCard
                }

                if draft.solved && reviewStatus == .none && !isReviewComplete {
                    Button(action: onNextProblem) {
                        Label("Next Problem", systemImage: "arrow.right")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .frame(height: 44)
                            .background(Capsule().fill(ExplorerTheme.green))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
        }
        .background(
            RoundedRectangle(cornerRadius: ExplorerTheme.cardCornerRadius)
                .fill(ExplorerTheme.card)
        )
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }

    private func dotButton(closed: Bool, label: String) -> some View {
        let isSelected = draft.dotChoice == closed
        return Button {
            draft.dotChoice = closed
        } label: {
            HStack(spacing: 8) {
                if closed {
                    Circle()
                        .fill(ExplorerTheme.purple)
                        .frame(width: 14, height: 14)
                } else {
                    Circle()
                        .strokeBorder(ExplorerTheme.purple, lineWidth: 2.5)
                        .frame(width: 14, height: 14)
                }
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ExplorerTheme.textPrimary)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: ExplorerTheme.buttonCornerRadius)
                    .fill(isSelected ? ExplorerTheme.purple.opacity(0.12) : Color.black.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ExplorerTheme.buttonCornerRadius)
                    .strokeBorder(
                        isSelected ? ExplorerTheme.purple : Color.black.opacity(0.12),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(draft.solved || reviewStatus == .missed)
    }

    private var initialReviewButtons: some View {
        HStack(spacing: 12) {
            Button(action: resetForRetry) {
                Text("Try Again")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .frame(height: 44)
                    .background(Capsule().fill(ExplorerTheme.purple))
            }
            .buttonStyle(.plain)

            Button(action: onReviewProblemComplete) {
                Text("Mark Complete")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(ExplorerTheme.green)
                    .padding(.horizontal, 24)
                    .frame(height: 44)
                    .background(Capsule().fill(ExplorerTheme.green.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
    }

    private var reviewNavigationButtons: some View {
        HStack(spacing: 12) {
            Button(action: resetForRetry) {
                Text("Try Again")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(ExplorerTheme.purple)
                    .padding(.horizontal, 20)
                    .frame(height: 42)
                    .background(Capsule().fill(ExplorerTheme.purple.opacity(0.12)))
            }
            .buttonStyle(.plain)

            Button(action: onReviewProblemComplete) {
                Text("Mark Complete")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(height: 42)
                    .background(Capsule().fill(ExplorerTheme.green))
            }
            .buttonStyle(.plain)
        }
    }

    private var reviewCompleteCard: some View {
        VStack(spacing: 10) {
            FeedbackCard(feedback: WorkspaceFeedback(kind: .success, message: "All missed problems in this practice are complete. Move to the next practice when you are ready."))
            Button(action: onNextSection) {
                Label("Next Practice", systemImage: "arrow.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .frame(height: 44)
                    .background(Capsule().fill(ExplorerTheme.green))
            }
            .buttonStyle(.plain)
        }
    }

    private func resetForRetry() {
        draft = SymbolToGraphDraft(
            pointValue: problem.boundary,
            dotChoice: nil,
            hasAdjustedGraph: false,
            feedback: nil,
            attemptCount: 0,
            solved: false
        )
        onRetryProblem()
    }

    static func initialPointValue(for problem: StoryProblem, reviewStatus: ProblemReviewStatus) -> Double {
        switch reviewStatus {
        case .correct:
            return problem.symbol.pointsRight ? problem.axisRange.upperBound : problem.axisRange.lowerBound
        case .missed:
            return problem.symbol.pointsRight ? problem.axisRange.lowerBound : problem.axisRange.upperBound
        case .none, .retry:
            return problem.boundary
        }
    }

    static func initialDotChoice(for problem: StoryProblem, reviewStatus: ProblemReviewStatus) -> Bool? {
        switch reviewStatus {
        case .correct:
            return problem.symbol.dotIsClosed
        case .missed:
            return !problem.symbol.dotIsClosed
        case .none, .retry:
            return nil
        }
    }

    static func initialFeedback(for problem: StoryProblem, reviewStatus: ProblemReviewStatus) -> WorkspaceFeedback? {
        switch reviewStatus {
        case .correct:
            return WorkspaceFeedback(kind: .success, message: "Correct answer shown: \(problem.inequalityText).")
        case .missed:
            return WorkspaceFeedback(kind: .incorrect, message: "This was one of your missed problems. The incorrect graph is shown. Tap Try Again to redo only this problem.")
        case .none, .retry:
            return nil
        }
    }

    private func check() {
        guard let chosenDot = draft.dotChoice, !draft.solved else { return }
        draft.attemptCount += 1

        let key = "graph/\(problem.id)"
        let delta = draft.pointValue - problem.boundary
        let clearlyMoved = abs(delta) > problem.tickStep * 0.2
        let directionCorrect = clearlyMoved && ((delta > 0) == problem.symbol.pointsRight)
        let dotCorrect = chosenDot == problem.symbol.dotIsClosed
        let direction = problem.symbol.pointsRight ? "right" : "left"
        let sizeWord = problem.symbol.pointsRight ? "bigger" : "smaller"
        let dotExplanation = problem.symbol.dotIsClosed
            ? "\(problem.symbol.rawValue) includes \(formattedBoundary) itself, so the dot is closed (filled)"
            : "\(problem.symbol.rawValue) is strict — \(formattedBoundary) itself is not a solution, so the dot is open (unfilled)"

        withAnimation(.easeOut(duration: 0.2)) {
            if directionCorrect && dotCorrect {
                draft.solved = true
                session.recordCorrect(key: key, points: 10, firstAttempt: draft.attemptCount == 1)
                draft.feedback = WorkspaceFeedback(
                    kind: .success,
                    message: "That's it! \(problem.inequalityText) shades \(direction) from \(formattedBoundary), and \(dotExplanation)."
                )
            } else if directionCorrect {
                session.recordError(
                    key: key, inequality: problem.inequalityText,
                    note: "Graphed \(problem.inequalityText) with the wrong dot type"
                )
                draft.feedback = WorkspaceFeedback(
                    kind: .adjust,
                    message: "The direction is right! But look at the dot: \(dotExplanation). Fix the dot and check again."
                )
            } else if dotCorrect {
                session.recordError(
                    key: key, inequality: problem.inequalityText,
                    note: "Graphed \(problem.inequalityText) in the wrong direction"
                )
                draft.feedback = WorkspaceFeedback(
                    kind: .incorrect,
                    message: "The dot is right, but the shading goes the wrong way. \(problem.symbol.name) means values \(sizeWord) than \(formattedBoundary), and those live to the \(direction). Try again."
                )
            } else {
                session.recordError(
                    key: key, inequality: problem.inequalityText,
                    note: "Graphed \(problem.inequalityText) with wrong direction and dot"
                )
                draft.feedback = WorkspaceFeedback(
                    kind: .incorrect,
                    message: "Start with the direction: \(problem.symbol.name.lowercased()) means values \(sizeWord) than \(formattedBoundary), which live to the \(direction). Then check the dot — \(dotExplanation). Try again."
                )
            }
        }
    }
}

// MARK: - Mode 2: Graph → Symbol

private struct GraphToSymbolWorkspace: View {
    let problem: StoryProblem
    @Binding var session: StudentSession
    let reviewStatus: ProblemReviewStatus
    let hasRemainingMissedProblems: Bool
    let isReviewComplete: Bool
    let onRetryProblem: () -> Void
    let onReviewProblemComplete: () -> Void
    let onNextSection: () -> Void
    let onNextProblem: () -> Void

    @State private var selectedSymbol: InequalitySymbol?
    @State private var feedback: WorkspaceFeedback?
    @State private var attemptCount = 0
    @State private var solved = false
    @State private var equivalentFormsAttempted = false
    @State private var retryAnswerChecked = false
    /// True while the student is mid-retry on equivalent forms.
    @State private var awaitingRecheck = false

    init(
        problem: StoryProblem,
        session: Binding<StudentSession>,
        reviewStatus: ProblemReviewStatus = .none,
        hasRemainingMissedProblems: Bool = false,
        isReviewComplete: Bool = false,
        onRetryProblem: @escaping () -> Void = {},
        onReviewProblemComplete: @escaping () -> Void = {},
        onNextSection: @escaping () -> Void = {},
        onNextProblem: @escaping () -> Void
    ) {
        self.problem = problem
        self._session = session
        self.reviewStatus = reviewStatus
        self.hasRemainingMissedProblems = hasRemainingMissedProblems
        self.isReviewComplete = isReviewComplete
        self.onRetryProblem = onRetryProblem
        self.onReviewProblemComplete = onReviewProblemComplete
        self.onNextSection = onNextSection
        self.onNextProblem = onNextProblem
        self._selectedSymbol = State(initialValue: Self.initialSymbol(for: problem, reviewStatus: reviewStatus))
        self._feedback = State(initialValue: Self.initialFeedback(for: problem, reviewStatus: reviewStatus))
        self._solved = State(initialValue: reviewStatus == .correct)
        self._equivalentFormsAttempted = State(initialValue: reviewStatus == .correct)
    }

    private var formattedBoundary: String { StoryProblem.formatted(problem.boundary) }
    private var graphPointValue: Double {
        problem.symbol.pointsRight ? problem.axisRange.upperBound : problem.axisRange.lowerBound
    }

    private var canCheck: Bool {
        selectedSymbol != nil && !solved && reviewStatus != .missed && !retryAnswerChecked && !isReviewComplete
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Text("Read the graph and write the inequality.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(ExplorerTheme.textSecondary)
                    Text(problem.variableDefinition)
                        .font(.system(size: 13))
                        .foregroundStyle(ExplorerTheme.textSecondary)
                }

                InteractiveNumberLine(
                    axisRange: problem.axisRange,
                    tickStep: problem.tickStep,
                    boundary: problem.boundary,
                    dotClosed: .constant(problem.symbol.dotIsClosed),
                    pointValue: .constant(graphPointValue),
                    isEnabled: false,
                    hintText: nil
                )
                .frame(height: 120)

                InequalityBuilder(
                    variableName: problem.variableName,
                    boundaryText: formattedBoundary,
                    selectedSymbol: $selectedSymbol,
                    isLocked: solved || reviewStatus == .missed
                )

                checkControls

                if let feedback {
                    FeedbackCard(feedback: feedback)
                }

                if reviewStatus == .missed {
                    retryProblemButton
                }

                if solved && reviewStatus != .missed && !retryAnswerChecked {
                    EquivalentFormsSection(
                        problem: problem,
                        onResult: handleEquivalentFormsResult,
                        onAnyCheck: {
                            withAnimation(.easeOut(duration: 0.2)) {
                                equivalentFormsAttempted = true
                                awaitingRecheck = false
                            }
                        },
                        onRetry: {
                            withAnimation(.easeOut(duration: 0.2)) {
                                awaitingRecheck = true
                            }
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if reviewStatus == .retry && (equivalentFormsAttempted || retryAnswerChecked) {
                    reviewNavigationButtons
                }

                if isReviewComplete {
                    reviewCompleteCard
                }

                if equivalentFormsAttempted && reviewStatus == .none && !isReviewComplete {
                    Button(action: onNextProblem) {
                        Label("Next Problem", systemImage: "arrow.right")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .frame(height: 44)
                            .background(Capsule().fill(ExplorerTheme.green))
                    }
                    .buttonStyle(.plain)
                    .disabled(awaitingRecheck)
                    .opacity(awaitingRecheck ? 0.4 : 1)
                }
            }
            .padding(18)
        }
        .background(
            RoundedRectangle(cornerRadius: ExplorerTheme.cardCornerRadius)
                .fill(ExplorerTheme.card)
        )
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }

    @ViewBuilder
    private var checkControls: some View {
        if reviewStatus == .retry {
            Button(action: retryPrimaryAction) {
                Text(selectedSymbol == nil ? "Mark Problem Complete" : "Check Solutions")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 34)
                    .frame(height: 44)
                    .background(Capsule().fill(selectedSymbol == nil ? ExplorerTheme.green : ExplorerTheme.purple))
            }
            .buttonStyle(.plain)
            .disabled(retryAnswerChecked || solved)
            .opacity((retryAnswerChecked || solved) ? 0.45 : 1)
        } else {
            VStack(spacing: 6) {
                Button(action: check) {
                    Text("Check")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 40)
                        .frame(height: 44)
                        .background(Capsule().fill(ExplorerTheme.purple))
                }
                .buttonStyle(.plain)
                .disabled(!canCheck)
                .opacity(canCheck ? 1 : 0.4)

                if !solved && !canCheck {
                    Text("Choose the symbol that matches the graph, then check.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(ExplorerTheme.textSecondary)
                }
            }
        }
    }

    private var reviewNavigationButtons: some View {
        HStack(spacing: 12) {
            Button(action: resetForRetry) {
                Text("Try Again")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(ExplorerTheme.purple)
                    .padding(.horizontal, 20)
                    .frame(height: 42)
                    .background(Capsule().fill(ExplorerTheme.purple.opacity(0.12)))
            }
            .buttonStyle(.plain)

            if hasRemainingMissedProblems {
                Button(action: onReviewProblemComplete) {
                    Text("Next Missed")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .frame(height: 42)
                        .background(Capsule().fill(ExplorerTheme.green))
                }
                .buttonStyle(.plain)
            }

            Button(action: hasRemainingMissedProblems ? onReviewProblemComplete : onNextSection) {
                Text(hasRemainingMissedProblems ? "Mark Complete" : "Next Practice")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(height: 42)
                    .background(Capsule().fill(ExplorerTheme.green.opacity(0.85)))
            }
            .buttonStyle(.plain)
        }
    }

    private var reviewCompleteCard: some View {
        VStack(spacing: 10) {
            FeedbackCard(feedback: WorkspaceFeedback(kind: .success, message: "All missed problems in this practice are complete. Move to the next practice when you are ready."))
            Button(action: onNextSection) {
                Label("Next Practice", systemImage: "arrow.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .frame(height: 44)
                    .background(Capsule().fill(ExplorerTheme.green))
            }
            .buttonStyle(.plain)
        }
    }

    private func retryPrimaryAction() {
        guard let selectedSymbol else {
            onReviewProblemComplete()
            return
        }
        checkRetrySymbol(selectedSymbol)
    }

    private func checkRetrySymbol(_ symbol: InequalitySymbol) {
        attemptCount += 1
        let correct = symbol == problem.symbol
        let direction = problem.symbol.pointsRight ? "right" : "left"
        let dotText = problem.symbol.dotIsClosed ? "closed dot" : "open dot"

        withAnimation(.easeOut(duration: 0.2)) {
            if correct {
                solved = true
                session.recordCorrect(key: "read/\(problem.id)", points: 10, firstAttempt: attemptCount == 1)
                feedback = WorkspaceFeedback(
                    kind: .success,
                    message: "Correct. Now check which solution statements match \(problem.inequalityText)."
                )
            } else {
                retryAnswerChecked = true
                self.selectedSymbol = problem.symbol
                session.recordError(
                    key: "read/\(problem.id)",
                    inequality: problem.inequalityText,
                    note: "Retry read graph as \(problem.variableName) \(symbol.rawValue) \(formattedBoundary)"
                )
                feedback = WorkspaceFeedback(
                    kind: .incorrect,
                    message: "Not quite. The graph has a \(dotText) at \(formattedBoundary) and shades \(direction), so the answer is \(problem.inequalityText)."
                )
            }
        }
    }

    private func check() {
        guard let symbol = selectedSymbol, !solved else { return }
        attemptCount += 1

        let key = "read/\(problem.id)"
        let correct = symbol == problem.symbol
        let direction = problem.symbol.pointsRight ? "right" : "left"
        let dotText = problem.symbol.dotIsClosed ? "closed dot" : "open dot"

        withAnimation(.easeOut(duration: 0.2)) {
            if correct {
                solved = true
                session.recordCorrect(key: key, points: 10, firstAttempt: attemptCount == 1)
                feedback = WorkspaceFeedback(
                    kind: .success,
                    message: "Correct! A \(dotText) at \(formattedBoundary) shaded \(direction) represents \(problem.inequalityText)."
                )
            } else {
                session.recordError(
                    key: key,
                    inequality: problem.inequalityText,
                    note: "Read graph as \(problem.variableName) \(symbol.rawValue) \(formattedBoundary)"
                )
                feedback = WorkspaceFeedback(
                    kind: .incorrect,
                    message: "Not quite. The graph has a \(dotText) and shades \(direction), so it matches \(problem.symbol.rawValue). Try again."
                )
            }
        }
    }

    private var retryProblemButton: some View {
        Button {
            resetForRetry()
        } label: {
            Text("Try Again")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .frame(height: 44)
                .background(Capsule().fill(ExplorerTheme.purple))
        }
        .buttonStyle(.plain)
    }

    private func resetForRetry() {
        selectedSymbol = nil
        feedback = nil
        attemptCount = 0
        solved = false
        equivalentFormsAttempted = false
        retryAnswerChecked = false
        awaitingRecheck = false
        onRetryProblem()
    }

    private static func initialSymbol(for problem: StoryProblem, reviewStatus: ProblemReviewStatus) -> InequalitySymbol? {
        switch reviewStatus {
        case .correct:
            return problem.symbol
        case .missed:
            return problem.symbol.pointsRight ? .lessThan : .greaterThan
        case .none, .retry:
            return nil
        }
    }

    private static func initialFeedback(for problem: StoryProblem, reviewStatus: ProblemReviewStatus) -> WorkspaceFeedback? {
        switch reviewStatus {
        case .correct:
            return WorkspaceFeedback(kind: .success, message: "Correct answer shown: \(problem.inequalityText).")
        case .missed:
            return WorkspaceFeedback(kind: .incorrect, message: "This was one of your missed problems. The incorrect symbol is shown. Tap Try Again to redo only this problem.")
        case .none, .retry:
            return nil
        }
    }

    private func handleEquivalentFormsResult(fullCredit: Bool, firstAttempt: Bool, errorNote: String?) {
        let key = "read-forms/\(problem.id)"
        if fullCredit {
            session.recordCorrect(key: key, points: 10, firstAttempt: firstAttempt)
        } else {
            session.recordError(
                key: key,
                inequality: problem.inequalityText,
                note: errorNote ?? "Chose incorrect equivalent forms for \(problem.inequalityText)"
            )
        }
    }
}

// MARK: - Equivalent Forms

private struct EquivalentFormChoice: Identifiable {
    let id = UUID()
    let display: String
    let isCorrect: Bool
}

private struct EquivalentFormsSection: View {
    let problem: StoryProblem
    let onResult: (_ fullCredit: Bool, _ firstAttempt: Bool, _ errorNote: String?) -> Void
    let onAnyCheck: () -> Void
    let onRetry: () -> Void

    @State private var choices: [EquivalentFormChoice]
    @State private var selectedIDs: Set<UUID> = []
    @State private var checked = false
    @State private var attempts = 0
    @State private var solvedFully = false
    @State private var feedback: WorkspaceFeedback?
    @State private var pulseMissed = false

    init(
        problem: StoryProblem,
        onResult: @escaping (_ fullCredit: Bool, _ firstAttempt: Bool, _ errorNote: String?) -> Void,
        onAnyCheck: @escaping () -> Void,
        onRetry: @escaping () -> Void
    ) {
        self.problem = problem
        self.onResult = onResult
        self.onAnyCheck = onAnyCheck
        self.onRetry = onRetry
        self._choices = State(initialValue: Self.generateChoices(for: problem))
    }

    var body: some View {
        VStack(spacing: 14) {
            Divider()

            Text("Select all equivalent forms.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ExplorerTheme.textPrimary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 10)], spacing: 10) {
                ForEach(choices) { choice in
                    choiceButton(choice)
                }
            }

            if let feedback {
                FeedbackCard(feedback: feedback)
            }

            if !solvedFully {
                if checked {
                    Button(action: resetForRetry) {
                        Text("Try Again")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 28)
                            .frame(height: 44)
                            .background(Capsule().fill(ExplorerTheme.purple))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: checkChoices) {
                        Text("Check Solutions")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 28)
                            .frame(height: 44)
                            .background(Capsule().fill(ExplorerTheme.purple))
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedIDs.isEmpty)
                    .opacity(selectedIDs.isEmpty ? 0.4 : 1)
                }
            }
        }
    }

    private func choiceButton(_ choice: EquivalentFormChoice) -> some View {
        let visual = visualState(for: choice)
        return Button {
            guard !checked, !solvedFully else { return }
            if selectedIDs.contains(choice.id) {
                selectedIDs.remove(choice.id)
            } else {
                selectedIDs.insert(choice.id)
            }
        } label: {
            Text(choice.display)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(visual.text)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: ExplorerTheme.buttonCornerRadius)
                        .fill(visual.fill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ExplorerTheme.buttonCornerRadius)
                        .strokeBorder(visual.border, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(visual.isMissed && pulseMissed ? 1.06 : 1)
    }

    private struct ChoiceVisual {
        let fill: Color
        let border: Color
        let text: Color
        var isMissed = false
    }

    private func visualState(for choice: EquivalentFormChoice) -> ChoiceVisual {
        let isSelected = selectedIDs.contains(choice.id)
        guard checked else {
            return isSelected
                ? ChoiceVisual(fill: ExplorerTheme.purple, border: ExplorerTheme.purple, text: .white)
                : ChoiceVisual(fill: Color.black.opacity(0.05), border: Color.black.opacity(0.12),
                               text: ExplorerTheme.textPrimary)
        }

        switch (isSelected, choice.isCorrect) {
        case (true, true):
            return ChoiceVisual(fill: ExplorerTheme.green, border: ExplorerTheme.green, text: .white)
        case (true, false):
            return ChoiceVisual(fill: ExplorerTheme.orange, border: ExplorerTheme.orange, text: .white)
        case (false, true):
            return ChoiceVisual(fill: ExplorerTheme.amber, border: ExplorerTheme.amber, text: .white, isMissed: true)
        case (false, false):
            return ChoiceVisual(fill: Color.black.opacity(0.05), border: Color.black.opacity(0.12),
                                text: ExplorerTheme.textPrimary)
        }
    }

    private func checkChoices() {
        attempts += 1

        let correctIDs = Set(choices.filter(\.isCorrect).map(\.id))
        let wrongSelected = selectedIDs.subtracting(correctIDs)
        let missed = correctIDs.subtracting(selectedIDs)
        let fullCredit = wrongSelected.isEmpty && missed.isEmpty

        withAnimation(.easeOut(duration: 0.2)) {
            checked = true
            if fullCredit {
                solvedFully = true
                feedback = WorkspaceFeedback(
                    kind: .success,
                    message: "Excellent! Those are all equivalent to \(problem.inequalityText). +10 points!"
                )
                onResult(true, attempts == 1, nil)
            } else {
                feedback = WorkspaceFeedback(
                    kind: .incorrect,
                    message: "Some choices do not describe the same solution set, and the amber choices are equivalent forms you missed. Try again!"
                )
                onResult(false, false, "Missed or extra equivalent forms for \(problem.inequalityText)")
            }
        }

        if !missed.isEmpty {
            pulseMissedButtons()
        }
        onAnyCheck()
    }

    private func pulseMissedButtons() {
        Task { @MainActor in
            withAnimation(.easeInOut(duration: 0.2)) { pulseMissed = true }
            try? await Task.sleep(nanoseconds: 200_000_000)
            withAnimation(.easeInOut(duration: 0.2)) { pulseMissed = false }
        }
    }

    private func resetForRetry() {
        withAnimation(.easeOut(duration: 0.2)) {
            selectedIDs = []
            checked = false
            feedback = nil
        }
        onRetry()
    }

    static func generateChoices(for problem: StoryProblem) -> [EquivalentFormChoice] {
        let variable = problem.variableName
        let boundary = StoryProblem.formatted(problem.boundary)
        let symbol = problem.symbol.rawValue
        let swapped = swappedSymbol(for: problem.symbol).rawValue
        let stricterOrLooser = strictnessToggledSymbol(for: problem.symbol).rawValue
        let opposite = oppositeDirectionSymbol(for: problem.symbol).rawValue
        let relation = relationPhrase(for: problem.symbol)
        let wrongRelation = relationPhrase(for: oppositeDirectionSymbol(for: problem.symbol))

        return [
            EquivalentFormChoice(display: "\(variable) \(symbol) \(boundary)", isCorrect: true),
            EquivalentFormChoice(display: "\(boundary) \(swapped) \(variable)", isCorrect: true),
            EquivalentFormChoice(display: "{\(variable) | \(variable) \(symbol) \(boundary)}", isCorrect: true),
            EquivalentFormChoice(display: "\(variable) is \(relation) \(boundary)", isCorrect: true),
            EquivalentFormChoice(display: "\(variable) \(stricterOrLooser) \(boundary)", isCorrect: false),
            EquivalentFormChoice(display: "\(variable) \(opposite) \(boundary)", isCorrect: false),
            EquivalentFormChoice(display: "\(boundary) \(symbol) \(variable)", isCorrect: false),
            EquivalentFormChoice(display: "{\(variable) | \(variable) \(opposite) \(boundary)}", isCorrect: false),
            EquivalentFormChoice(display: "\(variable) is \(wrongRelation) \(boundary)", isCorrect: false),
        ].shuffled()
    }

    private static func swappedSymbol(for symbol: InequalitySymbol) -> InequalitySymbol {
        switch symbol {
        case .lessThan: return .greaterThan
        case .atMost: return .atLeast
        case .greaterThan: return .lessThan
        case .atLeast: return .atMost
        }
    }

    private static func strictnessToggledSymbol(for symbol: InequalitySymbol) -> InequalitySymbol {
        switch symbol {
        case .lessThan: return .atMost
        case .atMost: return .lessThan
        case .greaterThan: return .atLeast
        case .atLeast: return .greaterThan
        }
    }

    private static func oppositeDirectionSymbol(for symbol: InequalitySymbol) -> InequalitySymbol {
        switch symbol {
        case .lessThan: return .greaterThan
        case .atMost: return .atLeast
        case .greaterThan: return .lessThan
        case .atLeast: return .atMost
        }
    }

    private static func relationPhrase(for symbol: InequalitySymbol) -> String {
        switch symbol {
        case .lessThan: return "less than"
        case .atMost: return "at most"
        case .greaterThan: return "greater than"
        case .atLeast: return "at least"
        }
    }
}

// MARK: - Check All That Apply

private struct AnswerChoice: Identifiable {
    let id = UUID()
    let display: String
    let value: Double
}

private struct CheckAllThatApplySection: View {
    let problem: StoryProblem
    /// Reports each check attempt to the parent for scoring.
    let onResult: (_ fullCredit: Bool, _ firstAttempt: Bool, _ errorNote: String?) -> Void
    /// Fires on every check so the parent can offer Next Problem.
    let onAnyCheck: () -> Void
    /// Fires when the student starts a retry, so the parent can dim
    /// Next Problem until the next check.
    let onRetry: () -> Void

    @State private var choices: [AnswerChoice]
    @State private var selectedIDs: Set<UUID> = []
    @State private var checked = false
    @State private var attempts = 0
    @State private var solvedFully = false
    @State private var feedback: WorkspaceFeedback?
    @State private var pulseMissed = false

    init(
        problem: StoryProblem,
        onResult: @escaping (_ fullCredit: Bool, _ firstAttempt: Bool, _ errorNote: String?) -> Void,
        onAnyCheck: @escaping () -> Void,
        onRetry: @escaping () -> Void
    ) {
        self.problem = problem
        self.onResult = onResult
        self.onAnyCheck = onAnyCheck
        self.onRetry = onRetry
        // Randomized order each time the problem loads.
        self._choices = State(initialValue: Self.generateChoices(for: problem))
    }

    private var formattedBoundary: String { StoryProblem.formatted(problem.boundary) }

    var body: some View {
        VStack(spacing: 14) {
            Divider()

            Text(problem.inequalityText)
                .font(.system(size: 26, weight: .bold, design: .monospaced))
                .foregroundStyle(ExplorerTheme.purple)

            Text("Which values satisfy this inequality? Select all that apply.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ExplorerTheme.textPrimary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 170), spacing: 10)], spacing: 10) {
                ForEach(choices) { choice in
                    choiceButton(choice)
                }
            }

            if let feedback {
                FeedbackCard(feedback: feedback)
            }

            if !solvedFully {
                if checked {
                    Button(action: resetForRetry) {
                        Text("Try Again")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 28)
                            .frame(height: 44)
                            .background(Capsule().fill(ExplorerTheme.purple))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: checkChoices) {
                        Text("Check Choices")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 28)
                            .frame(height: 44)
                            .background(Capsule().fill(ExplorerTheme.purple))
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedIDs.isEmpty)
                    .opacity(selectedIDs.isEmpty ? 0.4 : 1)
                }
            }
        }
    }

    // MARK: Choice buttons

    private func choiceButton(_ choice: AnswerChoice) -> some View {
        let visual = visualState(for: choice)
        return Button {
            guard !checked, !solvedFully else { return }
            if selectedIDs.contains(choice.id) {
                selectedIDs.remove(choice.id)
            } else {
                selectedIDs.insert(choice.id)
            }
        } label: {
            Text(choice.display)
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(visual.text)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: ExplorerTheme.buttonCornerRadius)
                        .fill(visual.fill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ExplorerTheme.buttonCornerRadius)
                        .strokeBorder(visual.border, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(visual.isMissed && pulseMissed ? 1.06 : 1)
    }

    private struct ChoiceVisual {
        let fill: Color
        let border: Color
        let text: Color
        var isMissed = false
    }

    private func visualState(for choice: AnswerChoice) -> ChoiceVisual {
        let isSelected = selectedIDs.contains(choice.id)
        guard checked else {
            return isSelected
                ? ChoiceVisual(fill: ExplorerTheme.purple, border: ExplorerTheme.purple, text: .white)
                : ChoiceVisual(fill: Color.black.opacity(0.05), border: Color.black.opacity(0.12),
                               text: ExplorerTheme.textPrimary)
        }
        let isCorrect = satisfies(choice.value)
        switch (isSelected, isCorrect) {
        case (true, true):
            return ChoiceVisual(fill: ExplorerTheme.green, border: ExplorerTheme.green, text: .white)
        case (true, false):
            return ChoiceVisual(fill: ExplorerTheme.orange, border: ExplorerTheme.orange, text: .white)
        case (false, true):
            return ChoiceVisual(fill: ExplorerTheme.amber, border: ExplorerTheme.amber, text: .white, isMissed: true)
        case (false, false):
            return ChoiceVisual(fill: Color.black.opacity(0.05), border: Color.black.opacity(0.12),
                                text: ExplorerTheme.textPrimary)
        }
    }

    // MARK: Checking

    private func satisfies(_ value: Double) -> Bool {
        switch problem.symbol {
        case .lessThan: return value < problem.boundary
        case .atMost: return value <= problem.boundary
        case .greaterThan: return value > problem.boundary
        case .atLeast: return value >= problem.boundary
        }
    }

    private func checkChoices() {
        attempts += 1

        let correctIDs = Set(choices.filter { satisfies($0.value) }.map(\.id))
        let wrongSelected = selectedIDs.subtracting(correctIDs)
        let missed = correctIDs.subtracting(selectedIDs)
        let fullCredit = wrongSelected.isEmpty && missed.isEmpty
        let boundarySelectedOnStrict = problem.symbol.isStrict
            && choices.contains { selectedIDs.contains($0.id) && $0.value == problem.boundary }

        withAnimation(.easeOut(duration: 0.2)) {
            checked = true
            if fullCredit {
                solvedFully = true
                feedback = WorkspaceFeedback(
                    kind: .success,
                    message: "Excellent! You found every value that satisfies \(problem.inequalityText). +10 points!"
                )
                onResult(true, attempts == 1, nil)
            } else if boundarySelectedOnStrict {
                var message = "\(formattedBoundary) does not satisfy \(problem.inequalityText) because \(problem.symbol.rawValue) means strictly \(problem.symbol.pointsRight ? "greater" : "less") than — \(formattedBoundary) itself is not included. An open dot on the number line means the boundary is excluded."
                if wrongSelected.count > 1 || !missed.isEmpty {
                    message += " Check the other highlighted values too."
                }
                feedback = WorkspaceFeedback(kind: .incorrect, message: message)
                onResult(false, false, "Selected boundary value \(formattedBoundary) on strict inequality \(problem.inequalityText)")
            } else {
                let wrongDisplays = choices
                    .filter { wrongSelected.contains($0.id) }
                    .map(\.display)
                var parts: [String] = []
                if !wrongDisplays.isEmpty {
                    let joined = wrongDisplays.joined(separator: ", ")
                    parts.append("\(joined) \(wrongDisplays.count == 1 ? "doesn't" : "don't") satisfy \(problem.inequalityText) — check which side of \(formattedBoundary) on the number line \(wrongDisplays.count == 1 ? "it lands" : "they land").")
                }
                if !missed.isEmpty {
                    parts.append("The amber values do satisfy \(problem.inequalityText) but weren't selected.")
                }
                feedback = WorkspaceFeedback(kind: .incorrect, message: parts.joined(separator: " ") + " Try again!")
                onResult(false, false, "Missed or extra values when selecting solutions of \(problem.inequalityText)")
            }
        }

        if !missed.isEmpty {
            pulseMissedButtons()
        }
        onAnyCheck()
    }

    /// One-shot 1.0 → 1.06 → 1.0 pulse on missed-correct buttons.
    private func pulseMissedButtons() {
        Task { @MainActor in
            withAnimation(.easeInOut(duration: 0.2)) { pulseMissed = true }
            try? await Task.sleep(nanoseconds: 200_000_000)
            withAnimation(.easeInOut(duration: 0.2)) { pulseMissed = false }
        }
    }

    private func resetForRetry() {
        withAnimation(.easeOut(duration: 0.2)) {
            selectedIDs = []
            checked = false
            feedback = nil
        }
        onRetry()
    }

    // MARK: Choice generation

    /// Builds 8–10 choices per problem: the boundary itself (strict-vs-non-strict
    /// trap), clearly-correct and clearly-wrong values, near-boundary values,
    /// a decimal, a fraction, and a negative where the context allows.
    static func generateChoices(for problem: StoryProblem) -> [AnswerChoice] {
        let boundary = problem.boundary
        let step = problem.tickStep
        var list: [AnswerChoice] = []

        func add(_ value: Double, _ display: String? = nil) {
            list.append(AnswerChoice(display: display ?? StoryProblem.formatted(value), value: value))
        }

        add(boundary)                       // The trap: boundary itself.
        add(boundary + 2 * step)            // Clearly above.
        add(boundary + 3 * step)
        add(boundary - 2 * step)            // Clearly below.
        add(boundary - 3 * step)
        add(boundary + 1)                   // Just above.
        add(boundary - 0.01, String(format: "%.2f", boundary - 0.01))   // Just below, as a decimal.
        add(boundary - 0.5, "\(Int(2 * boundary - 1))/2")               // Just below, as a fraction.
        if problem.variableName == "T" {
            add(-5)                         // Negative fits temperature contexts.
        }
        return list.shuffled()
    }
}

// MARK: - Story List Panel

/// Vertical progress carousel: only the active question is visible at the
/// top; completed questions stack below it, grayed out. Upcoming questions
/// stay hidden.
private struct StoryListPanel: View {
    let activeProblem: StoryProblem
    let completedProblems: [StoryProblem]
    let reviewProblemIDs: Set<Int>
    let onSelectProblem: (StoryProblem) -> Void

    private var displayedProblems: [StoryProblem] {
        if reviewProblemIDs.isEmpty {
            return [activeProblem] + completedProblems
        }
        return StoryProblem.all
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(displayedProblems) { problem in
                    Button {
                        onSelectProblem(problem)
                    } label: {
                        StoryCard(
                            problem: problem,
                            isCompleted: problem.id != activeProblem.id,
                            isReviewTarget: reviewProblemIDs.contains(problem.id)
                        )
                    }
                    .buttonStyle(.plain)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(3)
        }
        .scrollIndicators(.hidden)
    }
}

private struct StoryCard: View {
    let problem: StoryProblem
    let isCompleted: Bool
    let isReviewTarget: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isReviewTarget {
                Label("Review", systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(ExplorerTheme.orange)
            }
            HStack(alignment: .top, spacing: 6) {
                Text(problem.emoji)
                    .font(.system(size: 18))
                Text(problem.attributedStory(fontSize: 12.5))
                    .foregroundStyle(ExplorerTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(problem.variableDefinition)
                .font(.system(size: 11))
                .foregroundStyle(ExplorerTheme.textSecondary)
            if problem.isTrickyFlip && !isCompleted {
                Text("⚠ Careful — who goes on the left?")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(ExplorerTheme.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: ExplorerTheme.cardCornerRadius)
                .fill(isReviewTarget ? ExplorerTheme.amber.opacity(0.16) : ExplorerTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ExplorerTheme.cardCornerRadius)
                .strokeBorder(
                    isReviewTarget ? ExplorerTheme.amber : isCompleted ? Color.black.opacity(0.08) : ExplorerTheme.purple,
                    lineWidth: isReviewTarget || !isCompleted ? 2 : 1
                )
        )
        .overlay {
            if isCompleted && !isReviewTarget {
                RoundedRectangle(cornerRadius: ExplorerTheme.cardCornerRadius)
                    .fill(Color.gray.opacity(0.4))
            }
        }
    }
}

// MARK: - Reference Panel

private struct ReferencePanel: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(InequalitySymbol.allCases) { symbol in
                    ConceptCard(symbol: symbol)
                }
                trickyFlipCard
            }
            .padding(3)
        }
        .scrollIndicators(.hidden)
    }

    private var trickyFlipCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("💡 Tricky flip")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(red: 0.65, green: 0.45, blue: 0.05))
            Text("\u{201C}75 is greater than T\u{201D} rewrites as T < 75. Variable always goes on the left — flip the symbol when you swap sides.")
                .font(.system(size: 11))
                .foregroundStyle(ExplorerTheme.textPrimary.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: ExplorerTheme.cardCornerRadius)
                .fill(ExplorerTheme.amber.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: ExplorerTheme.cardCornerRadius)
                .strokeBorder(ExplorerTheme.amber.opacity(0.6), lineWidth: 1)
        )
    }
}

private struct ConceptCard: View {
    let symbol: InequalitySymbol

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(symbol.rawValue)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(ExplorerTheme.purple)
                Text(symbol.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ExplorerTheme.textPrimary)
            }
            Text(symbol.conceptDescription)
                .font(.system(size: 11))
                .foregroundStyle(ExplorerTheme.textSecondary)
            MiniNumberLine(pointsRight: symbol.pointsRight, dotClosed: symbol.dotIsClosed)
                .frame(width: 120, height: 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: ExplorerTheme.cardCornerRadius)
                .fill(ExplorerTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ExplorerTheme.cardCornerRadius)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        )
    }
}

/// A tiny schematic number line for the reference cards: boundary dot in the
/// middle, shading toward one end with a small arrow cap.
private struct MiniNumberLine: View {
    let pointsRight: Bool
    let dotClosed: Bool

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let left: CGFloat = 2
            let right = size.width - 6
            let center = size.width / 2
            let purple = ExplorerTheme.purple

            var base = Path()
            base.move(to: CGPoint(x: left, y: midY))
            base.addLine(to: CGPoint(x: right, y: midY))
            context.stroke(base, with: .color(Color.black.opacity(0.25)), lineWidth: 1.5)

            let shadeEnd = pointsRight ? right : left
            var shade = Path()
            shade.move(to: CGPoint(x: center, y: midY))
            shade.addLine(to: CGPoint(x: shadeEnd, y: midY))
            context.stroke(shade, with: .color(purple), lineWidth: 3)

            var arrow = Path()
            let tipX = pointsRight ? shadeEnd + 5 : shadeEnd - 5
            arrow.move(to: CGPoint(x: tipX, y: midY))
            arrow.addLine(to: CGPoint(x: shadeEnd, y: midY - 4))
            arrow.addLine(to: CGPoint(x: shadeEnd, y: midY + 4))
            arrow.closeSubpath()
            context.fill(arrow, with: .color(purple))

            let dotRect = CGRect(x: center - 4.5, y: midY - 4.5, width: 9, height: 9)
            if dotClosed {
                context.fill(Path(ellipseIn: dotRect), with: .color(purple))
            } else {
                context.fill(Path(ellipseIn: dotRect), with: .color(.white))
                context.stroke(Path(ellipseIn: dotRect.insetBy(dx: 1, dy: 1)), with: .color(purple), lineWidth: 2)
            }
        }
    }
}

private struct BackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.title3.weight(.semibold))
                .foregroundStyle(ExplorerTheme.purple)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: ExplorerTheme.buttonCornerRadius)
                        .fill(ExplorerTheme.card)
                )
                .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Mode 1: Symbol → Graph") {
    @Previewable @State var session = StudentSession()
    @Previewable @State var draft = SymbolToGraphDraft.initial(for: StoryProblem.all[0], reviewStatus: .none)
    ZStack {
        ExplorerTheme.canvas.ignoresSafeArea()
        SymbolToGraphWorkspace(problem: StoryProblem.all[0], session: $session, draft: $draft, onNextProblem: {})
            .padding(40)
    }
    .frame(width: 900, height: 700)
}

#Preview("Mode 2: Graph → Symbol") {
    @Previewable @State var session = StudentSession()
    ZStack {
        ExplorerTheme.canvas.ignoresSafeArea()
        GraphToSymbolWorkspace(problem: StoryProblem.all[0], session: $session, onNextProblem: {})
            .padding(40)
    }
    .frame(width: 900, height: 700)
}

#Preview("Student Mode") {
    ZStack {
        ExplorerTheme.canvas.ignoresSafeArea()
        StudentModeView(state: InequalityExplorerState())
    }
    .frame(width: 1194, height: 834)
}

#Preview("iPad Landscape") {
    CompoundInequalitiesInteractiveView()
        .frame(width: 1194, height: 834)
}

#Preview("Wide 16:9") {
    CompoundInequalitiesInteractiveView()
        .frame(width: 1280, height: 720)
}

#Preview("iPad Portrait") {
    CompoundInequalitiesInteractiveView()
        .frame(width: 834, height: 1194)
}
