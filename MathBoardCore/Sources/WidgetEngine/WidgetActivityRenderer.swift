//
//  WidgetActivityRenderer.swift
//  WidgetEngine
//
//  Native SwiftUI renderer for high-level activity JSON documents.
//

import SwiftUI

struct WidgetActivityRenderer: View {
    let document: ActivityWidgetDocument
    var themeOverride: WidgetActivityTheme?
    var experienceOverride: WidgetActivityExperience?
    var scoreSheet: WidgetActivityScoreSheet?
    var onEditWidget: (() -> Void)?
    var onMathInputRequested: (@MainActor (WidgetMathInputKeypadRequest) -> Void)?
    private var runtimeStateBinding: Binding<WidgetActivityRuntimeState>?
    @State private var localRuntimeState: WidgetActivityRuntimeState

    init(
        document: ActivityWidgetDocument,
        themeOverride: WidgetActivityTheme? = nil,
        experienceOverride: WidgetActivityExperience? = nil,
        scoreSheet: WidgetActivityScoreSheet? = nil,
        onEditWidget: (() -> Void)? = nil,
        onMathInputRequested: (@MainActor (WidgetMathInputKeypadRequest) -> Void)? = nil,
        runtimeState: Binding<WidgetActivityRuntimeState>? = nil
    ) {
        self.document = document
        self.themeOverride = themeOverride
        self.experienceOverride = experienceOverride
        self.scoreSheet = scoreSheet
        self.onEditWidget = onEditWidget
        self.onMathInputRequested = onMathInputRequested
        self.runtimeStateBinding = runtimeState
        _localRuntimeState = State(
            initialValue: WidgetActivityRuntimeState(
                multipleChoice: WidgetMultipleChoiceRuntimeState.initial(for: document),
                fillInTheBlank: WidgetFillInTheBlankRuntimeState.initial(for: document)
            )
        )
    }

    private var resolvedTheme: WidgetActivityVisualTheme {
        WidgetActivityVisualTheme(
            themeOverride ?? document.presentation?.preferredTheme ?? .cleanClassroom
        )
    }

    var body: some View {
        let activityRuntimeState = runtimeStateBinding ?? $localRuntimeState

        switch document.activity {
        case .multipleChoice:
            MultipleChoiceActivityView(
                document: document,
                runtimeState: activityRuntimeState.multipleChoice,
                scoreSheet: scoreSheet,
                onEditWidget: onEditWidget,
                theme: resolvedTheme,
                experience: experienceOverride ?? document.presentation?.preferredExperience
            )
        case .fillInTheBlank:
            FillInTheBlankActivityView(
                document: document,
                runtimeState: activityRuntimeState.fillInTheBlank,
                scoreSheet: scoreSheet,
                onEditWidget: onEditWidget,
                theme: resolvedTheme,
                onMathInputRequested: onMathInputRequested
            )
        }
    }
}

struct WidgetActivityValidationView: View {
    let source: String

    private var result: WidgetActivityValidationResult {
        WidgetActivityJSONCodec.decode(source)
    }

    var body: some View {
        if let document = result.document {
            WidgetActivityRenderer(document: document)
                .frame(maxWidth: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Label("Activity JSON is not valid", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                    .foregroundStyle(.red)
                ForEach(result.errors, id: \.self) { error in
                    Text(error)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.red.opacity(0.05))
        }
    }
}

private struct MultipleChoiceActivityView: View {
    let document: ActivityWidgetDocument
    @Binding var runtimeState: WidgetMultipleChoiceRuntimeState
    let scoreSheet: WidgetActivityScoreSheet?
    let onEditWidget: (() -> Void)?
    let theme: WidgetActivityVisualTheme
    let experience: WidgetActivityExperience?

    @State private var celebrate = false
    @State private var shake = false
    @State private var showsLearningObjective = false
    @State private var showsScoreSheet = false
    @State private var borderGlowRotates = false
    @State private var flashingMeterIndex: Int?
    @State private var displayedPrompt = ""
    @State private var isQuestionTyping = false
    @State private var isExpressionRevealed = false
    @State private var questionRevealToken = UUID()
    @State private var revealedQuestionID: String?
    @State private var isNextButtonHighlighted = false

    init(
        document: ActivityWidgetDocument,
        runtimeState: Binding<WidgetMultipleChoiceRuntimeState>,
        scoreSheet: WidgetActivityScoreSheet? = nil,
        onEditWidget: (() -> Void)? = nil,
        theme: WidgetActivityVisualTheme,
        experience: WidgetActivityExperience? = nil
    ) {
        self.document = document
        _runtimeState = runtimeState
        self.scoreSheet = scoreSheet
        self.onEditWidget = onEditWidget
        self.theme = theme
        self.experience = experience
    }

    private var currentQuestionIndex: Int {
        get { runtimeState.currentQuestionIndex }
        nonmutating set { runtimeState.currentQuestionIndex = newValue }
    }

    private var questionOrder: [Int] {
        get { runtimeState.questionOrder }
        nonmutating set { runtimeState.questionOrder = newValue }
    }

    private var choiceOrders: [String: [String]] {
        get { runtimeState.choiceOrders }
        nonmutating set { runtimeState.choiceOrders = newValue }
    }

    private var selectedChoiceID: String? {
        get { runtimeState.selectedChoiceID }
        nonmutating set { runtimeState.selectedChoiceID = newValue }
    }

    private var submittedChoiceID: String? {
        get { runtimeState.submittedChoiceID }
        nonmutating set { runtimeState.submittedChoiceID = newValue }
    }

    private var submittedChoiceIDsByQuestionID: [String: String] {
        get { runtimeState.submittedChoiceIDsByQuestionID ?? [:] }
        nonmutating set { runtimeState.submittedChoiceIDsByQuestionID = newValue }
    }

    private var score: Int {
        get { runtimeState.score }
        nonmutating set { runtimeState.score = newValue }
    }

    private var attempts: Int {
        get { runtimeState.attempts }
        nonmutating set { runtimeState.attempts = newValue }
    }

    private var streak: Int {
        get { runtimeState.streak }
        nonmutating set { runtimeState.streak = newValue }
    }

    private var longestStreak: Int {
        get { runtimeState.longestStreak }
        nonmutating set { runtimeState.longestStreak = newValue }
    }

    private var hintLevel: Int {
        get { runtimeState.hintLevel }
        nonmutating set { runtimeState.hintLevel = newValue }
    }

    private var feedbackMessage: String? {
        get { runtimeState.feedbackMessage }
        nonmutating set { runtimeState.feedbackMessage = newValue }
    }

    private var feedbackKind: FeedbackKind {
        get { FeedbackKind(runtimeState.feedbackKind) }
        nonmutating set { runtimeState.feedbackKind = newValue.runtimeKind }
    }

    private var answeredQuestionIDs: Set<String> {
        get { runtimeState.answeredQuestionIDs }
        nonmutating set { runtimeState.answeredQuestionIDs = newValue }
    }

    private var correctlyAnsweredQuestionIDs: Set<String> {
        get { runtimeState.correctlyAnsweredQuestionIDs }
        nonmutating set { runtimeState.correctlyAnsweredQuestionIDs = newValue }
    }

    private var questionAttempts: [String: Int] {
        get { runtimeState.questionAttempts }
        nonmutating set { runtimeState.questionAttempts = newValue }
    }

    private var nextButtonPressToken: Int? {
        get { runtimeState.nextButtonPressToken }
        nonmutating set { runtimeState.nextButtonPressToken = newValue }
    }

    private var flow: WidgetActivityAttemptFlowState {
        get { runtimeState.flow ?? WidgetActivityAttemptFlowState() }
        nonmutating set { runtimeState.flow = newValue }
    }

    private var hasQuestions: Bool {
        !document.questions.isEmpty
    }

    private var currentQuestion: WidgetActivityQuestion? {
        guard hasQuestions else { return nil }
        if flow.isRetryingMissed,
           let questionID = flow.retryQuestionIDs[safe: flow.retryQuestionIndex],
           let retryQuestion = document.questions.first(where: { $0.id == questionID }) {
            return retryQuestion
        }
        let orderedIndex = questionOrder[safe: currentQuestionIndex] ?? currentQuestionIndex
        return document.questions[safe: orderedIndex] ?? document.questions[0]
    }

    private var currentQuestionID: String {
        currentQuestion?.id ?? ""
    }

    private var isReviewingAnswers: Bool {
        flow.isReviewingAnswers == true
    }

    private var currentChoices: [WidgetActivityChoice] {
        guard let currentQuestion else { return [] }
        guard let order = choiceOrders[currentQuestion.id] else {
            return currentQuestion.choices
        }
        return order.compactMap { choiceID in
            currentQuestion.choices.first { $0.id == choiceID }
        }
    }

    private var progressValue: Double {
        guard !document.questions.isEmpty else { return 0 }
        return Double(answeredQuestionIDs.count) / Double(document.questions.count)
    }

    private var missedQuestionIDs: [String] {
        document.questions
            .map(\.id)
            .filter { answeredQuestionIDs.contains($0) && !correctlyAnsweredQuestionIDs.contains($0) }
    }

    private var missedQuestionCount: Int {
        missedQuestionIDs.count
    }

    private var accuracyValue: Double {
        guard attempts > 0 else { return 0 }
        return Double(score) / Double(attempts)
    }

    private var simplifiedAccuracyLabel: String {
        guard attempts > 0 else { return "0/0" }
        let divisor = Self.greatestCommonDivisor(score, attempts)
        return "\(score / divisor)/\(attempts / divisor)"
    }

    private var equivalentAccuracyLabel: String {
        guard attempts > 0 else { return "0/100" }
        return "\(Int((accuracyValue * 100).rounded()))/100"
    }

    private var decimalAccuracyLabel: String {
        String(format: "%.2f", accuracyValue)
    }

    private var percentAccuracyLabel: String {
        "\(Int((accuracyValue * 100).rounded()))%"
    }

    private var bonusLabel: String {
        String(format: "%.1f", bonusValue)
    }

    private var pointsLabel: String {
        String(format: "%.1f", pointsValue)
    }

    private var bonusValue: Double {
        runtimeState.bonus
    }

    private var pointsValue: Double {
        runtimeState.points
    }

    private var currentScoreRecord: WidgetActivityScoreRecord {
        runtimeState.scoreRecord(for: document)
    }

    private var fileScoreSheet: WidgetActivityScoreSheet {
        scoreSheet ?? WidgetActivityScoreSheet(records: [currentScoreRecord])
    }

    private var allowRetry: Bool {
        document.rules?.allowRetry ?? true
    }

    private var canShowHint: Bool {
        guard let currentQuestion else { return false }
        guard !flow.isShowingFinalScore else { return false }
        guard !isReviewingAnswers else { return false }
        return hintLevel < currentQuestion.hints.count
    }

    private var isCurrentQuestionLocked: Bool {
        guard let currentQuestion else { return true }
        guard !flow.isShowingFinalScore else { return true }
        guard !isReviewingAnswers else { return true }
        if submittedChoiceID != nil {
            return true
        }

        if flow.isRetryingMissed {
            return false
        }

        if correctlyAnsweredQuestionIDs.contains(currentQuestion.id) {
            return true
        }

        if answeredQuestionIDs.contains(currentQuestion.id) {
            return true
        }

        if let maxAttempts = document.rules?.maxAttemptsPerQuestion,
           maxAttempts > 0,
           (questionAttempts[currentQuestion.id] ?? 0) >= maxAttempts {
            return true
        }

        return false
    }

    private var scoreLabel: String {
        switch document.rules?.scoreMode ?? .correctOutOfAttempted {
        case .correctOutOfAttempted:
            return "\(score)/\(attempts)"
        case .correctOutOfTotal:
            return "\(score)/\(document.questions.count)"
        case .streak:
            return "\(streak)"
        }
    }

    var body: some View {
        Group {
            if hasQuestions {
                GeometryReader { proxy in
                    let contentInset: CGFloat = 22
                    let contentWidth = max(proxy.size.width - contentInset * 2, 0)

                    ScrollView {
                        activityContent(usesWideLayout: contentWidth >= 720)
                            .padding(contentInset)
                    }
                }
            } else {
                emptyState
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            quietWidgetBorder
        }
        .onAppear {
            prepareRuntimeStateIfNeeded()
            startQuestionRevealIfNeeded()
            withAnimation(.linear(duration: 4.2).repeatForever(autoreverses: false)) {
                borderGlowRotates = true
            }
        }
    }

    @ViewBuilder
    private func activityContent(usesWideLayout: Bool) -> some View {
        if usesWideLayout {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    practicePanel
                    feedbackPanel
                }
                .frame(minWidth: 380, maxWidth: .infinity, alignment: .topLeading)
                .layoutPriority(1)

                progressPanel
                    .frame(width: 320)
            }
        } else {
            VStack(alignment: .leading, spacing: 18) {
                header
                practicePanel
                feedbackPanel
                progressPanel
            }
        }
    }

    private var quietWidgetBorder: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color.black.opacity(0.82), lineWidth: 1)
            .allowsHitTesting(false)
    }

    private var focusedPracticeBorder: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(
                AngularGradient(
                    colors: [
                        Color(red: 0.14, green: 0.54, blue: 1.00),
                        Color(red: 0.37, green: 0.92, blue: 1.00),
                        Color(red: 0.66, green: 0.40, blue: 1.00),
                        Color(red: 1.00, green: 0.36, blue: 0.80),
                        Color(red: 0.24, green: 0.74, blue: 1.00)
                    ],
                    center: .center
                ),
                lineWidth: 2
            )
            .hueRotation(.degrees(borderGlowRotates ? 360 : 0))
            .shadow(color: Color(red: 0.16, green: 0.63, blue: 1.00).opacity(borderGlowRotates ? 0.46 : 0.22), radius: borderGlowRotates ? 9 : 4)
            .shadow(color: Color(red: 0.94, green: 0.38, blue: 1.00).opacity(borderGlowRotates ? 0.28 : 0.12), radius: borderGlowRotates ? 14 : 6)
            .allowsHitTesting(false)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Label("This activity needs at least one question.", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(theme.warning)
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(22)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showsLearningObjective.toggle()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(document.title)
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .lineLimit(2)

                    Image(systemName: "info.circle")
                        .font(.caption.weight(.bold))
                        .opacity(0.45)
                }
                .foregroundStyle(theme.primaryText)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showsLearningObjective, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Learning Objective")
                        .font(.headline.weight(.bold))
                    Text(document.learningObjective)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    if let difficulty = document.difficulty {
                        Text("Level - \(difficulty.rawValue.capitalized)")
                            .font(.callout.weight(.black))
                            .foregroundStyle(theme.accent)
                            .padding(.top, 4)
                    }
                }
                .foregroundStyle(theme.primaryText)
                .padding(16)
                .frame(width: 280, alignment: .leading)
                .background(theme.card)
            }

            if let description = document.description, !description.isEmpty {
                Text(description)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .padding(.trailing, 70)
    }

    private var progressPanel: some View {
        ActivityScoreGaugePanel(
            progress: progressValue,
            answeredCount: answeredQuestionIDs.count,
            totalCount: document.questions.count,
            score: score,
            attempts: attempts,
            streak: streak,
            longestStreak: longestStreak,
            simplifiedFraction: simplifiedAccuracyLabel,
            equivalentFraction: equivalentAccuracyLabel,
            decimal: decimalAccuracyLabel,
            percent: percentAccuracyLabel,
            bonus: bonusLabel,
            points: pointsLabel,
            questionStarItems: questionStarItems,
            onSelectQuestion: navigateToQuestion,
            onShowFinalScore: showFinalScore,
            flashingMeterIndex: flashingMeterIndex,
            scoreSheet: fileScoreSheet,
            showsScoreSheet: $showsScoreSheet,
            onResetWidget: resetWidget,
            onEditWidget: onEditWidget,
            theme: theme
        )
    }

    private var practicePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            if flow.isShowingFinalScore {
                finalScorePanel
            } else {
                questionCard
                choiceGrid
                controls
                hintPanel
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color.white,
                    Color(red: 0.97, green: 0.99, blue: 1.00)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(theme.border.opacity(0.55), lineWidth: 1)
                focusedPracticeBorder
            }
        )
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
    }

    private var finalScorePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: missedQuestionCount == 0 ? "checkmark.seal.fill" : "flag.checkered")
                    .font(.system(size: 42, weight: .black))
                    .foregroundStyle(missedQuestionCount == 0 ? theme.correct : theme.accent)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Final Score")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(theme.primaryText)
                    Text(finalScoreMessage)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(theme.secondaryText)
                }
            }

            HStack(spacing: 12) {
                finalScoreMetric(title: "Score", value: "\(score)/\(document.questions.count)", tint: theme.correct)
                finalScoreMetric(title: "Missed", value: "\(missedQuestionCount)", tint: missedQuestionCount == 0 ? theme.correct : theme.incorrect)
            }

            HStack(spacing: 10) {
                Button {
                    beginReviewMathtivity()
                } label: {
                    Label("Review Mathtivity", systemImage: "list.bullet.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(theme.accent)

                Button {
                    beginRetryMissed()
                } label: {
                    Label("Retry Missed", systemImage: "arrow.counterclockwise.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(theme.accent)
                .disabled(missedQuestionCount == 0)

                Button {
                    resetWidget()
                } label: {
                    Label("Reset", systemImage: "restart.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(theme.warning)

                Button {
                    submitCurrentScore()
                } label: {
                    Label(flow.hasSubmittedScore ? "Resubmit" : "Submit", systemImage: "paperplane.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                .disabled(!isMathtivityComplete)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(theme.accent.opacity(0.35), lineWidth: 1.5)
        )
    }

    private var isMathtivityComplete: Bool {
        answeredQuestionIDs.count >= document.questions.count
    }

    private var finalScoreMessage: String {
        if !isMathtivityComplete {
            return "You have answered \(answeredQuestionIDs.count) of \(document.questions.count) questions. Finish the mathtivity before submitting."
        }
        if flow.isRetryingMissed {
            return "Review missed questions, then come back to this screen."
        }
        if missedQuestionCount == 0 {
            return flow.hasSubmittedScore ? "All questions are correct. Your score has been submitted." : "All questions are correct. Submit when ready."
        }
        return "You missed \(missedQuestionCount) \(missedQuestionCount == 1 ? "question" : "questions"). Retry them or submit this score."
    }

    private func finalScoreMetric(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.black))
                .foregroundStyle(theme.secondaryText)
            Text(value)
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(tint)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var questionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Question:")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(theme.accent)
                Text(displayedPrompt.isEmpty && !isQuestionTyping ? currentQuestion?.prompt ?? "" : displayedPrompt)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.primaryText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.easeOut(duration: 0.12), value: displayedPrompt)
            }

            if isExpressionRevealed, let expression = currentQuestion?.expression, !expression.isEmpty {
                WidgetMathTextView(
                    source: expression,
                    fontSize: 42,
                    weight: .black,
                    foregroundColor: theme.expressionText,
                    alignment: .center,
                    lineLimit: 2,
                    minimumScaleFactor: 0.55
                )
                    .minimumScaleFactor(0.55)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
                    .padding(.horizontal, 14)
                    .background(theme.expressionBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(theme.accent.opacity(0.35), lineWidth: 2)
                    )
                    .scaleEffect(celebrate ? 1.035 : 1)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                    .offset(x: shake ? -8 : 0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.45), value: celebrate)
                    .animation(.default.repeatCount(3, autoreverses: true), value: shake)
            }
        }
    }

    private var choiceGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(currentChoices) { choice in
                Button {
                    guard canSelectChoice else { return }
                    selectedChoiceID = choice.id
                } label: {
                    HStack(spacing: 10) {
                        Text(choice.id.uppercased())
                            .font(.caption.weight(.black))
                            .foregroundStyle(choiceBadgeText(for: choice))
                            .frame(width: 28, height: 28)
                            .background(choiceBadgeFill(for: choice), in: Circle())

                        WidgetMathTextView(
                            source: choice.label,
                            fontSize: 22,
                            weight: .bold,
                            foregroundColor: choiceText(for: choice),
                            alignment: .leading,
                            lineLimit: 3,
                            minimumScaleFactor: 0.82,
                            mathFontSizeMultiplier: 1.4
                        )

                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .frame(minHeight: 88, maxHeight: 118)
                    .background(
                        LinearGradient(
                            colors: [
                                choiceFill(for: choice),
                                choiceFill(for: choice).opacity(0.84)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(choiceBorder(for: choice), lineWidth: choice.id == selectedChoiceID ? 3 : 1.5)
                    )
                    .shadow(color: .black.opacity(choice.id == selectedChoiceID ? 0.18 : 0.10), radius: choice.id == selectedChoiceID ? 10 : 6, x: 0, y: choice.id == selectedChoiceID ? 5 : 3)
                    .overlay(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.70), lineWidth: 1)
                            .padding(1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canSelectChoice)
            }
        }
    }

    private var canSelectChoice: Bool {
        !flow.isShowingFinalScore && !isReviewingAnswers && !isQuestionTyping && isExpressionRevealed && !isCurrentQuestionLocked
    }

    private var canCheckAnswer: Bool {
        guard !flow.isShowingFinalScore, !isReviewingAnswers, !isQuestionTyping, isExpressionRevealed, !isCurrentQuestionLocked, let selectedChoiceID else { return false }
        return selectedChoiceID != submittedChoiceID
    }

    private var canAdvanceToNextQuestion: Bool {
        guard !flow.isShowingFinalScore else { return false }
        guard !isQuestionTyping, isExpressionRevealed else { return false }
        if isReviewingAnswers {
            return true
        }
        guard let currentQuestion else { return false }
        return submittedChoiceID != nil || answeredQuestionIDs.contains(currentQuestion.id)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            if !isReviewingAnswers {
                Button {
                    revealHint()
                } label: {
                    Image(systemName: "lightbulb.fill")
                        .font(.headline.weight(.bold))
                        .frame(width: 44, height: 38)
                }
                .buttonStyle(.bordered)
                .tint(theme.accent)
                .disabled(!canShowHint)
                .accessibilityLabel("Show hint")

                Button {
                    checkAnswer()
                } label: {
                    Label("Check", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                .controlSize(.regular)
                .disabled(!canCheckAnswer)
            }

            if flow.isRetryingMissed {
                Button {
                    skipRetryQuestion()
                } label: {
                    Label("Skip", systemImage: "forward.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(theme.warning)
                .controlSize(.regular)
            }

            Button {
                nextQuestion()
            } label: {
                Label("Next", systemImage: "arrow.right.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WidgetNextButtonStyle(
                theme: theme,
                isEnabled: canAdvanceToNextQuestion,
                isHighlighted: isNextButtonHighlighted
            ))
            .controlSize(.regular)
            .disabled(!canAdvanceToNextQuestion)
        }
        .onChange(of: nextButtonPressToken) { _, _ in
            pulseNextButton()
        }
    }

    @ViewBuilder
    private var hintPanel: some View {
        if let currentQuestion, !currentQuestion.hints.isEmpty, hintLevel > 0 {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(currentQuestion.hints.prefix(hintLevel).enumerated()), id: \.offset) { index, hint in
                    Text("Hint \(index + 1): \(hint)")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(theme.primaryText)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.hintBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    @ViewBuilder
    private var feedbackPanel: some View {
        if let feedbackMessage {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: feedbackKind.systemImage)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(feedbackKind.color(theme: theme))
                    .frame(width: 30, height: 30)

                Text(feedbackMessage)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(14)
            .background(feedbackKind.background(theme: theme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var questionStarItems: [ActivityQuestionStarItem] {
        document.questions.enumerated().map { index, question in
            ActivityQuestionStarItem(
                index: index,
                title: "Question \(index + 1)",
                status: starStatus(for: question),
                isCurrent: question.id == currentQuestionID && !flow.isShowingFinalScore
            )
        }
    }

    private func starStatus(for question: WidgetActivityQuestion) -> ActivityQuestionStarStatus {
        if correctlyAnsweredQuestionIDs.contains(question.id) {
            return (questionAttempts[question.id] ?? 0) > 1 ? .corrected : .correct
        }

        if answeredQuestionIDs.contains(question.id) {
            return .incorrect
        }

        return .unanswered
    }

    private func navigateToQuestion(_ index: Int) {
        guard document.questions.indices.contains(index) else { return }
        var nextFlow = flow
        nextFlow.isShowingFinalScore = false
        nextFlow.isRetryingMissed = false
        nextFlow.isReviewingAnswers = false
        nextFlow.retryQuestionIDs = []
        nextFlow.retryQuestionIndex = 0
        flow = nextFlow

        currentQuestionIndex = questionOrder.firstIndex(of: index) ?? index
        if let question = currentQuestion {
            let submittedChoice = submittedChoiceIDsByQuestionID[question.id]
            selectedChoiceID = submittedChoice
            submittedChoiceID = submittedChoice
            if answeredQuestionIDs.contains(question.id) {
                feedbackKind = correctlyAnsweredQuestionIDs.contains(question.id) ? .correct : .incorrect
                feedbackMessage = reviewFeedback(for: question)
            } else {
                feedbackKind = .neutral
                feedbackMessage = nil
            }
        }

        hintLevel = 0
        startQuestionReveal(force: true)
    }

    private func checkAnswer() {
        guard let currentQuestion else { return }

        if correctlyAnsweredQuestionIDs.contains(currentQuestion.id) {
            feedbackKind = .neutral
            feedbackMessage = "This question is already correct. Move to the next one."
            return
        }

        if let maxAttempts = document.rules?.maxAttemptsPerQuestion,
           maxAttempts > 0,
           (questionAttempts[currentQuestion.id] ?? 0) >= maxAttempts {
            feedbackKind = .warning
            feedbackMessage = "You have used all attempts for this question. Move to the next one."
            triggerShake()
            return
        }

        guard let selectedChoiceID else {
            feedbackKind = .warning
            feedbackMessage = "Pick one answer first, then check it."
            triggerShake()
            return
        }

        guard let choice = currentQuestion.choices.first(where: { $0.id == selectedChoiceID }) else {
            feedbackKind = .warning
            feedbackMessage = "That choice is not available for this question."
            triggerShake()
            return
        }

        let alreadyAnswered = answeredQuestionIDs.contains(currentQuestion.id)
        if alreadyAnswered && !allowRetry {
            feedbackKind = .neutral
            feedbackMessage = "This one is already locked in. Move to the next question."
            return
        }

        submittedChoiceID = choice.id
        var submittedChoices = submittedChoiceIDsByQuestionID
        submittedChoices[currentQuestion.id] = choice.id
        submittedChoiceIDsByQuestionID = submittedChoices
        attempts += 1
        questionAttempts[currentQuestion.id, default: 0] += 1
        answeredQuestionIDs.insert(currentQuestion.id)

        if choice.isCorrect {
            if !correctlyAnsweredQuestionIDs.contains(currentQuestion.id) {
                score += 1
            }
            correctlyAnsweredQuestionIDs.insert(currentQuestion.id)
            streak += 1
            longestStreak = max(longestStreak, streak)
            feedbackKind = .correct
            feedbackMessage = choice.feedback
                ?? currentQuestion.correctFeedback
                ?? document.feedback?.defaultCorrect
                ?? "Correct. Nice work."
            triggerCelebration()
            triggerMeterFlashSequence()
            scheduleAdvanceIfNeeded(correct: true)
        } else {
            streak = 0
            feedbackKind = .incorrect
            feedbackMessage = choice.feedback
                ?? currentQuestion.incorrectFeedback
                ?? document.feedback?.defaultIncorrect
                ?? document.feedback?.defaultEncouragement
                ?? "Not yet. Check the operation priority and try again."
            triggerShake()
            scheduleAdvanceIfNeeded(correct: false)
        }
    }

    private func nextQuestion() {
        guard !document.questions.isEmpty, canAdvanceToNextQuestion else { return }
        nextButtonPressToken = (nextButtonPressToken ?? 0) + 1

        if isReviewingAnswers {
            guard currentQuestionIndex < document.questions.count - 1 else {
                showFinalScore()
                return
            }
            currentQuestionIndex += 1
            prepareReviewQuestion()
            startQuestionReveal(force: true)
            return
        }

        if flow.isRetryingMissed {
            advanceRetryQuestionOrFinish()
            return
        }

        guard currentQuestionIndex < document.questions.count - 1 else {
            showFinalScore()
            return
        }

        currentQuestionIndex += 1
        selectedChoiceID = nil
        submittedChoiceID = nil
        hintLevel = 0
        feedbackKind = .neutral
        feedbackMessage = nil
        startQuestionReveal(force: true)
    }

    private func revealHint() {
        guard let currentQuestion else { return }
        hintLevel = min(hintLevel + 1, currentQuestion.hints.count)
    }

    private func resetWidget() {
        let submittedState = flow
        questionRevealToken = UUID()
        runtimeState = WidgetMultipleChoiceRuntimeState.initial(for: document)
        runtimeState.flow = WidgetActivityAttemptFlowState(
            hasSubmittedScore: submittedState.hasSubmittedScore,
            submittedRecord: submittedState.submittedRecord
        )
        feedbackKind = .neutral
        feedbackMessage = nil
        celebrate = false
        shake = false
        flashingMeterIndex = nil
        answeredQuestionIDs = []
        correctlyAnsweredQuestionIDs = []
        questionAttempts = [:]
        showsScoreSheet = false
        startQuestionReveal(force: true)
    }

    private func showFinalScore() {
        var nextFlow = flow
        nextFlow.isShowingFinalScore = true
        nextFlow.isRetryingMissed = false
        nextFlow.isReviewingAnswers = false
        nextFlow.retryQuestionIndex = 0
        nextFlow.retryQuestionIDs = []
        flow = nextFlow
        selectedChoiceID = nil
        submittedChoiceID = nil
        hintLevel = 0
        feedbackKind = .neutral
        feedbackMessage = nil
    }

    private func beginRetryMissed() {
        let missedIDs = missedQuestionIDs
        guard !missedIDs.isEmpty else { return }
        var nextFlow = flow
        nextFlow.isShowingFinalScore = false
        nextFlow.isRetryingMissed = true
        nextFlow.isReviewingAnswers = false
        nextFlow.retryQuestionIDs = missedIDs
        nextFlow.retryQuestionIndex = 0
        nextFlow.skippedRetryQuestionIDs = []
        flow = nextFlow
        selectedChoiceID = nil
        submittedChoiceID = nil
        hintLevel = 0
        feedbackKind = .neutral
        feedbackMessage = nil
        startQuestionReveal(force: true)
    }

    private func beginReviewMathtivity() {
        guard !document.questions.isEmpty else { return }
        var nextFlow = flow
        nextFlow.isShowingFinalScore = false
        nextFlow.isRetryingMissed = false
        nextFlow.isReviewingAnswers = true
        nextFlow.retryQuestionIDs = []
        nextFlow.retryQuestionIndex = 0
        flow = nextFlow
        currentQuestionIndex = 0
        prepareReviewQuestion()
        startQuestionReveal(force: true)
    }

    private func prepareReviewQuestion() {
        guard let currentQuestion else { return }
        let submittedChoice = submittedChoiceIDsByQuestionID[currentQuestion.id]
        selectedChoiceID = submittedChoice
        submittedChoiceID = submittedChoice
        hintLevel = 0
        feedbackKind = correctlyAnsweredQuestionIDs.contains(currentQuestion.id) ? .correct : .incorrect
        feedbackMessage = reviewFeedback(for: currentQuestion)
    }

    private func reviewFeedback(for question: WidgetActivityQuestion) -> String {
        let status = correctlyAnsweredQuestionIDs.contains(question.id) ? "Correct." : "Missed."
        if let explanation = question.explanation, !explanation.isEmpty {
            return "\(status) \(explanation)"
        }
        return status
    }

    private func skipRetryQuestion() {
        guard flow.isRetryingMissed, let currentQuestion else { return }
        var nextFlow = flow
        nextFlow.skippedRetryQuestionIDs.insert(currentQuestion.id)
        flow = nextFlow
        advanceRetryQuestionOrFinish()
    }

    private func advanceRetryQuestionOrFinish() {
        var nextFlow = flow
        let nextIndex = nextFlow.retryQuestionIndex + 1
        guard nextIndex < nextFlow.retryQuestionIDs.count else {
            showFinalScore()
            return
        }

        nextFlow.retryQuestionIndex = nextIndex
        flow = nextFlow
        selectedChoiceID = nil
        submittedChoiceID = nil
        hintLevel = 0
        feedbackKind = .neutral
        feedbackMessage = nil
        startQuestionReveal(force: true)
    }

    private func submitCurrentScore() {
        var nextFlow = flow
        nextFlow.hasSubmittedScore = true
        nextFlow.submittedRecord = currentScoreRecord
        flow = nextFlow
        feedbackKind = .correct
        feedbackMessage = nextFlow.submittedRecord == nil ? "Score submitted." : "Score submitted. You can resubmit if you retry or reset."
        triggerMeterFlashSequence()
    }

    private func prepareRuntimeStateIfNeeded() {
        if questionOrder.count != document.questions.count {
            runtimeState.questionOrder = WidgetMultipleChoiceRuntimeState.initial(for: document).questionOrder
        }

        let missingChoiceOrder = document.questions.contains { question in
            choiceOrders[question.id] == nil
        }
        if missingChoiceOrder {
            runtimeState.choiceOrders = WidgetMultipleChoiceRuntimeState.initial(for: document).choiceOrders
        }

        if currentQuestionIndex >= max(document.questions.count, 1) {
            currentQuestionIndex = 0
        }
    }

    private func startQuestionRevealIfNeeded() {
        guard revealedQuestionID != currentQuestionID else { return }
        startQuestionReveal(force: false)
    }

    private func startQuestionReveal(force: Bool) {
        if !force, revealedQuestionID == currentQuestionID {
            return
        }

        let prompt = currentQuestion?.prompt ?? ""
        let token = UUID()
        questionRevealToken = token
        revealedQuestionID = currentQuestionID
        displayedPrompt = ""
        isQuestionTyping = !prompt.isEmpty
        isExpressionRevealed = false

        guard !prompt.isEmpty else {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                isQuestionTyping = false
                isExpressionRevealed = true
            }
            return
        }

        Task { @MainActor in
            for character in prompt {
                guard token == questionRevealToken else { return }
                displayedPrompt.append(character)
                try? await Task.sleep(for: .milliseconds(22))
            }

            guard token == questionRevealToken else { return }
            withAnimation(.spring(response: 0.26, dampingFraction: 0.78)) {
                isQuestionTyping = false
                isExpressionRevealed = true
            }
        }
    }

    private func scheduleAdvanceIfNeeded(correct: Bool) {
        // MathBoard lesson widgets keep students in control of pacing. Generated
        // JSON may still contain older automatic advance modes, but the native
        // multiple-choice runtime always waits for the enabled Next button.
        _ = correct
    }

    private static func makeQuestionOrder(for document: ActivityWidgetDocument) -> [Int] {
        let order = Array(document.questions.indices)
        return document.rules?.shuffleQuestions == true ? order.shuffled() : order
    }

    private static func makeChoiceOrders(for document: ActivityWidgetDocument) -> [String: [String]] {
        var orders: [String: [String]] = [:]
        for question in document.questions {
            let ids = question.choices.map(\.id)
            orders[question.id] = document.rules?.shuffleChoices == true ? ids.shuffled() : ids
        }
        return orders
    }

    private static func greatestCommonDivisor(_ left: Int, _ right: Int) -> Int {
        var a = abs(left)
        var b = abs(right)
        while b != 0 {
            let remainder = a % b
            a = b
            b = remainder
        }
        return max(a, 1)
    }

    private func triggerCelebration() {
        celebrate = true
        Task {
            try? await Task.sleep(for: .milliseconds(420))
            celebrate = false
        }
    }

    private func triggerMeterFlashSequence() {
        Task {
            for index in [0, 1, 3, 2] {
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.08)) {
                        flashingMeterIndex = index
                    }
                }
                try? await Task.sleep(for: .milliseconds(130))
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.18)) {
                        flashingMeterIndex = nil
                    }
                }
                try? await Task.sleep(for: .milliseconds(55))
            }
        }
    }

    private func triggerShake() {
        shake = true
        Task {
            try? await Task.sleep(for: .milliseconds(360))
            shake = false
        }
    }

    private func pulseNextButton() {
        isNextButtonHighlighted = true
        Task {
            try? await Task.sleep(for: .milliseconds(260))
            isNextButtonHighlighted = false
        }
    }

    private func choiceFill(for choice: WidgetActivityChoice) -> Color {
        guard submittedChoiceID != nil else {
            return choice.id == selectedChoiceID ? theme.selectedChoice : theme.choice
        }

        if choice.isCorrect {
            return theme.correct.opacity(0.20)
        }

        if choice.id == submittedChoiceID {
            return theme.incorrect.opacity(0.18)
        }

        return theme.choice
    }

    private func choiceBorder(for choice: WidgetActivityChoice) -> Color {
        guard submittedChoiceID != nil else {
            return choice.id == selectedChoiceID ? theme.accent : theme.border
        }

        if choice.isCorrect {
            return theme.correct
        }

        if choice.id == submittedChoiceID {
            return theme.incorrect
        }

        return theme.border
    }

    private func choiceText(for choice: WidgetActivityChoice) -> Color {
        return theme.primaryText
    }

    private func choiceBadgeFill(for choice: WidgetActivityChoice) -> Color {
        choice.id == selectedChoiceID ? theme.accent : theme.badge
    }

    private func choiceBadgeText(for choice: WidgetActivityChoice) -> Color {
        choice.id == selectedChoiceID ? theme.badgeSelectedText : theme.secondaryText
    }
}

private struct FillInTheBlankActivityView: View {
    let document: ActivityWidgetDocument
    @Binding var runtimeState: WidgetFillInTheBlankRuntimeState
    let scoreSheet: WidgetActivityScoreSheet?
    let onEditWidget: (() -> Void)?
    let theme: WidgetActivityVisualTheme
    let onMathInputRequested: (@MainActor (WidgetMathInputKeypadRequest) -> Void)?

    @State private var showsLearningObjective = false
    @State private var showsScoreSheet = false
    @State private var celebrate = false
    @State private var shake = false
    @State private var flashingMeterIndex: Int?
    @State private var isNextButtonHighlighted = false
    @State private var activeMathInputRequestID: String?
    @State private var mathInputCursorOffsets: [String: Int] = [:]
    @State private var isMathInputCursorVisible = true

    private var currentQuestionIndex: Int {
        get { runtimeState.currentQuestionIndex }
        nonmutating set { runtimeState.currentQuestionIndex = newValue }
    }

    private var questionOrder: [Int] {
        get { runtimeState.questionOrder }
        nonmutating set { runtimeState.questionOrder = newValue }
    }

    private var responsesByBlankID: [String: String] {
        get { runtimeState.responsesByBlankID }
        nonmutating set { runtimeState.responsesByBlankID = newValue }
    }

    private var score: Int {
        get { runtimeState.score }
        nonmutating set { runtimeState.score = newValue }
    }

    private var attempts: Int {
        get { runtimeState.attempts }
        nonmutating set { runtimeState.attempts = newValue }
    }

    private var streak: Int {
        get { runtimeState.streak }
        nonmutating set { runtimeState.streak = newValue }
    }

    private var longestStreak: Int {
        get { runtimeState.longestStreak }
        nonmutating set { runtimeState.longestStreak = newValue }
    }

    private var hintLevel: Int {
        get { runtimeState.hintLevel }
        nonmutating set { runtimeState.hintLevel = newValue }
    }

    private var feedbackMessage: String? {
        get { runtimeState.feedbackMessage }
        nonmutating set { runtimeState.feedbackMessage = newValue }
    }

    private var feedbackKind: FeedbackKind {
        get { FeedbackKind(runtimeState.feedbackKind) }
        nonmutating set { runtimeState.feedbackKind = newValue.runtimeKind }
    }

    private var answeredQuestionIDs: Set<String> {
        get { runtimeState.answeredQuestionIDs }
        nonmutating set { runtimeState.answeredQuestionIDs = newValue }
    }

    private var correctlyAnsweredQuestionIDs: Set<String> {
        get { runtimeState.correctlyAnsweredQuestionIDs }
        nonmutating set { runtimeState.correctlyAnsweredQuestionIDs = newValue }
    }

    private var questionAttempts: [String: Int] {
        get { runtimeState.questionAttempts }
        nonmutating set { runtimeState.questionAttempts = newValue }
    }

    private var nextButtonPressToken: Int? {
        get { runtimeState.nextButtonPressToken }
        nonmutating set { runtimeState.nextButtonPressToken = newValue }
    }

    private var flow: WidgetActivityAttemptFlowState {
        get { runtimeState.flow ?? WidgetActivityAttemptFlowState() }
        nonmutating set { runtimeState.flow = newValue }
    }

    private var hasQuestions: Bool {
        !document.questions.isEmpty
    }

    private var currentQuestion: WidgetActivityQuestion? {
        guard hasQuestions else { return nil }
        if flow.isRetryingMissed,
           let questionID = flow.retryQuestionIDs[safe: flow.retryQuestionIndex],
           let retryQuestion = document.questions.first(where: { $0.id == questionID }) {
            return retryQuestion
        }
        let orderedIndex = questionOrder[safe: currentQuestionIndex] ?? currentQuestionIndex
        return document.questions[safe: orderedIndex] ?? document.questions[0]
    }

    private var isReviewingAnswers: Bool {
        flow.isReviewingAnswers == true
    }

    private var progressValue: Double {
        guard !document.questions.isEmpty else { return 0 }
        return Double(answeredQuestionIDs.count) / Double(document.questions.count)
    }

    private var missedQuestionIDs: [String] {
        document.questions
            .map(\.id)
            .filter { answeredQuestionIDs.contains($0) && !correctlyAnsweredQuestionIDs.contains($0) }
    }

    private var missedQuestionCount: Int {
        missedQuestionIDs.count
    }

    private var accuracyValue: Double {
        guard attempts > 0 else { return 0 }
        return Double(score) / Double(attempts)
    }

    private var simplifiedAccuracyLabel: String {
        guard attempts > 0 else { return "0/0" }
        let divisor = Self.greatestCommonDivisor(score, attempts)
        return "\(score / divisor)/\(attempts / divisor)"
    }

    private var equivalentAccuracyLabel: String {
        guard attempts > 0 else { return "0/100" }
        return "\(Int((accuracyValue * 100).rounded()))/100"
    }

    private var currentScoreRecord: WidgetActivityScoreRecord {
        runtimeState.scoreRecord(for: document)
    }

    private var fileScoreSheet: WidgetActivityScoreSheet {
        scoreSheet ?? WidgetActivityScoreSheet(records: [currentScoreRecord])
    }

    private var questionStarItems: [ActivityQuestionStarItem] {
        document.questions.enumerated().map { index, question in
            ActivityQuestionStarItem(
                index: index,
                title: "Question \(index + 1)",
                status: starStatus(for: question),
                isCurrent: question.id == currentQuestion?.id && !flow.isShowingFinalScore
            )
        }
    }

    private func starStatus(for question: WidgetActivityQuestion) -> ActivityQuestionStarStatus {
        if correctlyAnsweredQuestionIDs.contains(question.id) {
            return (questionAttempts[question.id] ?? 0) > 1 ? .corrected : .correct
        }

        if answeredQuestionIDs.contains(question.id) {
            return .incorrect
        }

        return .unanswered
    }

    private func navigateToQuestion(_ index: Int) {
        guard document.questions.indices.contains(index) else { return }
        var nextFlow = flow
        nextFlow.isShowingFinalScore = false
        nextFlow.isRetryingMissed = false
        nextFlow.isReviewingAnswers = false
        nextFlow.retryQuestionIDs = []
        nextFlow.retryQuestionIndex = 0
        flow = nextFlow

        currentQuestionIndex = questionOrder.firstIndex(of: index) ?? index
        activeMathInputRequestID = nil
        if let question = currentQuestion, answeredQuestionIDs.contains(question.id) {
            feedbackKind = correctlyAnsweredQuestionIDs.contains(question.id) ? .correct : .incorrect
            feedbackMessage = reviewFeedback(for: question)
        } else {
            feedbackKind = .neutral
            feedbackMessage = nil
        }

        hintLevel = 0
    }

    private var canShowHint: Bool {
        guard let currentQuestion else { return false }
        guard !flow.isShowingFinalScore else { return false }
        guard !isReviewingAnswers else { return false }
        return hintLevel < currentQuestion.hints.count
    }

    private var isCurrentQuestionLocked: Bool {
        guard let currentQuestion else { return true }
        guard !flow.isShowingFinalScore else { return true }
        guard !isReviewingAnswers else { return true }
        if flow.isRetryingMissed {
            return false
        }
        if correctlyAnsweredQuestionIDs.contains(currentQuestion.id) {
            return true
        }
        if answeredQuestionIDs.contains(currentQuestion.id), document.rules?.allowRetry == false {
            return true
        }
        if let maxAttempts = document.rules?.maxAttemptsPerQuestion,
           maxAttempts > 0,
           (questionAttempts[currentQuestion.id] ?? 0) >= maxAttempts {
            return true
        }
        return false
    }

    private var canCheckAnswer: Bool {
        guard !flow.isShowingFinalScore, !isReviewingAnswers, let currentQuestion, !isCurrentQuestionLocked else { return false }
        return currentQuestion.blanks.allSatisfy { blank in
            !response(for: blank, in: currentQuestion).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var canAdvanceToNextQuestion: Bool {
        guard !flow.isShowingFinalScore else { return false }
        if isReviewingAnswers {
            return true
        }
        guard let currentQuestion else { return false }
        return answeredQuestionIDs.contains(currentQuestion.id)
    }

    var body: some View {
        Group {
            if hasQuestions {
                GeometryReader { proxy in
                    let contentInset: CGFloat = 22
                    let contentWidth = max(proxy.size.width - contentInset * 2, 0)

                    ScrollView {
                        activityContent(usesWideLayout: contentWidth >= 720)
                            .padding(contentInset)
                    }
                }
            } else {
                emptyState
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.black.opacity(0.82), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .onAppear {
            prepareRuntimeStateIfNeeded()
        }
    }

    @ViewBuilder
    private func activityContent(usesWideLayout: Bool) -> some View {
        if usesWideLayout {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    practicePanel
                    feedbackPanel
                }
                .frame(minWidth: 380, maxWidth: .infinity, alignment: .topLeading)
                .layoutPriority(1)

                progressPanel
                    .frame(width: 320)
            }
        } else {
            VStack(alignment: .leading, spacing: 18) {
                header
                practicePanel
                feedbackPanel
                progressPanel
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Label("This activity needs at least one question.", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(theme.warning)
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(22)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showsLearningObjective.toggle()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(document.title)
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .lineLimit(2)

                    Image(systemName: "info.circle")
                        .font(.caption.weight(.bold))
                        .opacity(0.45)
                }
                .foregroundStyle(theme.primaryText)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showsLearningObjective, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Learning Objective")
                        .font(.headline.weight(.bold))
                    Text(document.learningObjective)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(theme.primaryText)
                .padding(16)
                .frame(width: 280, alignment: .leading)
                .background(theme.card)
            }

            if let description = document.description, !description.isEmpty {
                Text(description)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .padding(.trailing, 70)
    }

    private var progressPanel: some View {
        ActivityScoreGaugePanel(
            progress: progressValue,
            answeredCount: answeredQuestionIDs.count,
            totalCount: document.questions.count,
            score: score,
            attempts: attempts,
            streak: streak,
            longestStreak: longestStreak,
            simplifiedFraction: simplifiedAccuracyLabel,
            equivalentFraction: equivalentAccuracyLabel,
            decimal: String(format: "%.2f", accuracyValue),
            percent: "\(Int((accuracyValue * 100).rounded()))%",
            bonus: String(format: "%.1f", runtimeState.bonus),
            points: String(format: "%.1f", runtimeState.points),
            questionStarItems: questionStarItems,
            onSelectQuestion: navigateToQuestion,
            onShowFinalScore: showFinalScore,
            flashingMeterIndex: flashingMeterIndex,
            scoreSheet: fileScoreSheet,
            showsScoreSheet: $showsScoreSheet,
            onResetWidget: resetWidget,
            onEditWidget: onEditWidget,
            theme: theme
        )
    }

    private var practicePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            if flow.isShowingFinalScore {
                finalScorePanel
            } else {
                questionCard
                blankFields
                controls
                hintPanel
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color.white,
                    Color(red: 0.97, green: 0.99, blue: 1.00)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(theme.border.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
        .offset(x: shake ? -8 : 0)
        .animation(.default.repeatCount(3, autoreverses: true), value: shake)
    }

    private var finalScorePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: missedQuestionCount == 0 ? "checkmark.seal.fill" : "flag.checkered")
                    .font(.system(size: 42, weight: .black))
                    .foregroundStyle(missedQuestionCount == 0 ? theme.correct : theme.accent)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Final Score")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(theme.primaryText)
                    Text(finalScoreMessage)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(theme.secondaryText)
                }
            }

            HStack(spacing: 12) {
                finalScoreMetric(title: "Score", value: "\(score)/\(document.questions.count)", tint: theme.correct)
                finalScoreMetric(title: "Missed", value: "\(missedQuestionCount)", tint: missedQuestionCount == 0 ? theme.correct : theme.incorrect)
            }

            HStack(spacing: 10) {
                Button {
                    beginReviewMathtivity()
                } label: {
                    Label("Review Mathtivity", systemImage: "list.bullet.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(theme.accent)

                Button {
                    beginRetryMissed()
                } label: {
                    Label("Retry Missed", systemImage: "arrow.counterclockwise.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(theme.accent)
                .disabled(missedQuestionCount == 0)

                Button {
                    resetWidget()
                } label: {
                    Label("Reset", systemImage: "restart.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(theme.warning)

                Button {
                    submitCurrentScore()
                } label: {
                    Label(flow.hasSubmittedScore ? "Resubmit" : "Submit", systemImage: "paperplane.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                .disabled(!isMathtivityComplete)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(theme.accent.opacity(0.35), lineWidth: 1.5)
        )
    }

    private var isMathtivityComplete: Bool {
        answeredQuestionIDs.count >= document.questions.count
    }

    private var finalScoreMessage: String {
        if !isMathtivityComplete {
            return "You have answered \(answeredQuestionIDs.count) of \(document.questions.count) questions. Finish the mathtivity before submitting."
        }
        if missedQuestionCount == 0 {
            return flow.hasSubmittedScore ? "All questions are correct. Your score has been submitted." : "All questions are correct. Submit when ready."
        }
        return "You missed \(missedQuestionCount) \(missedQuestionCount == 1 ? "question" : "questions"). Retry them or submit this score."
    }

    private func finalScoreMetric(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.black))
                .foregroundStyle(theme.secondaryText)
            Text(value)
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(tint)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var questionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Question:")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(theme.accent)
                Text(currentQuestion?.prompt ?? "")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.primaryText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let expression = currentQuestion?.expression, !expression.isEmpty {
                WidgetMathTextView(
                    source: expression,
                    fontSize: 42,
                    weight: .black,
                    foregroundColor: theme.expressionText,
                    alignment: .center,
                    lineLimit: 2,
                    minimumScaleFactor: 0.55
                )
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
                .padding(.horizontal, 14)
                .background(theme.expressionBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(theme.accent.opacity(0.35), lineWidth: 2)
                )
                .scaleEffect(celebrate ? 1.035 : 1)
            }
        }
    }

    @ViewBuilder
    private var blankFields: some View {
        if let currentQuestion {
            if let fractionLayout = fractionResponseLayout(for: currentQuestion) {
                VStack(alignment: .leading, spacing: 12) {
                    fractionResponseField(
                        fractionLayout,
                        label: currentQuestion.responseLayout?.label,
                        in: currentQuestion
                    )

                    ForEach(remainingBlanks(after: fractionLayout, in: currentQuestion)) { blank in
                        blankField(for: blank, in: currentQuestion)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(currentQuestion.blanks) { blank in
                        blankField(for: blank, in: currentQuestion)
                    }
                }
            }
        }
    }

    private func fractionResponseLayout(for question: WidgetActivityQuestion) -> (numerator: WidgetActivityBlank, denominator: WidgetActivityBlank)? {
        guard question.responseLayout?.type == .fraction,
              let numeratorID = question.responseLayout?.numeratorBlankId,
              let denominatorID = question.responseLayout?.denominatorBlankId,
              let numerator = question.blanks.first(where: { $0.id == numeratorID }),
              let denominator = question.blanks.first(where: { $0.id == denominatorID })
        else {
            return nil
        }

        return (numerator, denominator)
    }

    private func remainingBlanks(
        after fractionLayout: (numerator: WidgetActivityBlank, denominator: WidgetActivityBlank),
        in question: WidgetActivityQuestion
    ) -> [WidgetActivityBlank] {
        question.blanks.filter { blank in
            blank.id != fractionLayout.numerator.id && blank.id != fractionLayout.denominator.id
        }
    }

    private func fractionResponseField(
        _ fractionLayout: (numerator: WidgetActivityBlank, denominator: WidgetActivityBlank),
        label: String?,
        in question: WidgetActivityQuestion
    ) -> some View {
        let trimmedLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayLabel = trimmedLabel?.isEmpty == false ? trimmedLabel ?? "Answer" : "Answer"

        return VStack(alignment: .leading, spacing: 8) {
            Text("Fraction Answer")
                .font(.caption.weight(.black))
                .foregroundStyle(theme.secondaryText)

            HStack(alignment: .center, spacing: 14) {
                Text(displayLabel)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(theme.expressionText)

                VStack(spacing: 7) {
                    compactBlankTextField(
                        for: fractionLayout.numerator,
                        in: question,
                        placeholder: fractionLayout.numerator.label ?? "Numerator"
                    )
                    .frame(width: 118)

                    Rectangle()
                        .fill(theme.expressionText.opacity(0.82))
                        .frame(width: 132, height: 2)

                    compactBlankTextField(
                        for: fractionLayout.denominator,
                        in: question,
                        placeholder: fractionLayout.denominator.label ?? "Denominator"
                    )
                    .frame(width: 118)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.expressionBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(theme.accent.opacity(0.28), lineWidth: 1)
            )
        }
    }

    private func blankField(for blank: WidgetActivityBlank, in question: WidgetActivityQuestion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(blank.label ?? blank.id)
                .font(.caption.weight(.black))
                .foregroundStyle(theme.secondaryText)
            compactBlankTextField(for: blank, in: question, placeholder: "Answer")
        }
    }

    @ViewBuilder
    private func compactBlankTextField(
        for blank: WidgetActivityBlank,
        in question: WidgetActivityQuestion,
        placeholder: String
    ) -> some View {
        #if os(iOS)
        if onMathInputRequested != nil {
            Button {
                requestMathInput(for: blank, in: question)
            } label: {
                let isActive = activeMathInputRequestID == mathInputRequestID(for: blank, in: question)
                HStack {
                    let value = responseBinding(for: blank, in: question).wrappedValue
                    HStack(spacing: 2) {
                        if isActive {
                            activeMathInputText(value: value, placeholder: placeholder, requestID: mathInputRequestID(for: blank, in: question))
                        } else if value.isEmpty {
                            Text(placeholder)
                                .foregroundStyle(theme.secondaryText.opacity(0.72))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        } else {
                            WidgetMathTextView(
                                source: value,
                                fontSize: 22,
                                weight: .semibold,
                                foregroundColor: theme.primaryText,
                                lineLimit: 1,
                                minimumScaleFactor: 0.7
                            )
                        }

                    }
                    Spacer(minLength: 6)
                    Image(systemName: blank.kind == .numeric ? "number" : "keyboard")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(theme.secondaryText)
                }
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 10)
                .frame(minHeight: 38)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(isActive ? theme.accent : theme.border.opacity(0.85), lineWidth: isActive ? 3 : 1)
                )
                .shadow(color: isActive ? theme.accent.opacity(0.28) : .clear, radius: 5, x: 0, y: 0)
            }
            .buttonStyle(.plain)
            .disabled(isCurrentQuestionLocked)
            .accessibilityLabel(blank.label ?? blank.id)
            .accessibilityValue(responseBinding(for: blank, in: question).wrappedValue)
        } else {
            fallbackTextField(for: blank, in: question, placeholder: placeholder)
        }
        #else
        fallbackTextField(for: blank, in: question, placeholder: placeholder)
        #endif
    }

    private func fallbackTextField(
        for blank: WidgetActivityBlank,
        in question: WidgetActivityQuestion,
        placeholder: String
    ) -> some View {
        TextField(placeholder, text: responseBinding(for: blank, in: question))
            .textFieldStyle(.roundedBorder)
            .font(.title3.weight(.semibold))
            .disabled(isCurrentQuestionLocked)
#if os(iOS)
            .keyboardType(blank.kind == .numeric ? .numbersAndPunctuation : .default)
            .textInputAutocapitalization(.never)
#endif
    }

    private func requestMathInput(for blank: WidgetActivityBlank, in question: WidgetActivityQuestion) {
        guard let onMathInputRequested else { return }

        let binding = responseBinding(for: blank, in: question)
        let title = blank.label ?? question.prompt
        let kind: WidgetMathInputKeypadKind = blank.kind == .numeric ? .numeric : .alphanumeric
        let requestID = mathInputRequestID(for: blank, in: question)
        mathInputCursorOffsets[requestID] = cursorOffset(for: requestID, value: binding.wrappedValue)
        activeMathInputRequestID = requestID
        restartMathInputCursorBlink()

        onMathInputRequested(
            WidgetMathInputKeypadRequest(
                id: requestID,
                title: title,
                kind: kind,
                applyAction: { action in
                    switch action {
                    case .insert(let text):
                        insertMathInputText(text, into: binding, requestID: requestID)
                    case .deleteBackward:
                        deleteMathInputText(from: binding, requestID: requestID)
                    case .clear:
                        binding.wrappedValue = ""
                        mathInputCursorOffsets[requestID] = 0
                    case .moveCursorLeft:
                        moveMathInputCursor(for: requestID, value: binding.wrappedValue, delta: -1)
                    case .moveCursorRight:
                        moveMathInputCursor(for: requestID, value: binding.wrappedValue, delta: 1)
                    case .returnKey:
                        handleMathInputReturn(from: blank, in: question)
                    }
                }
            )
        )
    }

    private func mathInputRequestID(for blank: WidgetActivityBlank, in question: WidgetActivityQuestion) -> String {
        let widgetID = document.widgetId ?? document.title
        return "\(widgetID)-\(question.id)-\(blank.id)"
    }

    private func handleMathInputReturn(from blank: WidgetActivityBlank, in question: WidgetActivityQuestion) {
        guard !isCurrentQuestionLocked else { return }
        if let currentIndex = question.blanks.firstIndex(where: { $0.id == blank.id }) {
            let remainingBlanks = question.blanks[(currentIndex + 1)...]
            if let nextBlank = remainingBlanks.first(where: { nextBlank in
                response(for: nextBlank, in: question).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) {
                requestMathInput(for: nextBlank, in: question)
                return
            }
        }

        if canCheckAnswer {
            checkAnswer()
        }
    }

    private func activeMathInputText(value: String, placeholder: String, requestID: String) -> some View {
        let offset = cursorOffset(for: requestID, value: value)
        let parts = split(value, at: offset)

        return HStack(spacing: 2) {
            if value.isEmpty {
                Text(placeholder)
                    .foregroundStyle(theme.secondaryText.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                if !parts.leading.isEmpty {
                    Text(parts.leading)
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                mathInputCursor
                if !parts.trailing.isEmpty {
                    Text(parts.trailing)
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }

            if value.isEmpty {
                mathInputCursor
            }
        }
    }

    private var mathInputCursor: some View {
        Rectangle()
            .fill(theme.accent)
            .frame(width: 2, height: 24)
            .opacity(isMathInputCursorVisible ? 1 : 0.18)
            .accessibilityHidden(true)
    }

    private func insertMathInputText(
        _ text: String,
        into binding: Binding<String>,
        requestID: String
    ) {
        var value = binding.wrappedValue
        let offset = cursorOffset(for: requestID, value: value)
        let index = value.index(value.startIndex, offsetBy: offset)
        value.insert(contentsOf: text, at: index)
        binding.wrappedValue = value
        mathInputCursorOffsets[requestID] = offset + text.count
    }

    private func deleteMathInputText(from binding: Binding<String>, requestID: String) {
        var value = binding.wrappedValue
        let offset = cursorOffset(for: requestID, value: value)
        guard offset > 0 else { return }
        let removalIndex = value.index(value.startIndex, offsetBy: offset - 1)
        value.remove(at: removalIndex)
        binding.wrappedValue = value
        mathInputCursorOffsets[requestID] = offset - 1
    }

    private func moveMathInputCursor(for requestID: String, value: String, delta: Int) {
        let offset = cursorOffset(for: requestID, value: value)
        mathInputCursorOffsets[requestID] = min(max(offset + delta, 0), value.count)
        restartMathInputCursorBlink()
    }

    private func cursorOffset(for requestID: String, value: String) -> Int {
        min(max(mathInputCursorOffsets[requestID] ?? value.count, 0), value.count)
    }

    private func split(_ value: String, at offset: Int) -> (leading: String, trailing: String) {
        let splitIndex = value.index(value.startIndex, offsetBy: min(max(offset, 0), value.count))
        return (String(value[..<splitIndex]), String(value[splitIndex...]))
    }

    private func restartMathInputCursorBlink() {
        isMathInputCursorVisible = true
        withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
            isMathInputCursorVisible = false
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            if !isReviewingAnswers {
                Button {
                    revealHint()
                } label: {
                    Image(systemName: "lightbulb.fill")
                        .font(.headline.weight(.bold))
                        .frame(width: 44, height: 38)
                }
                .buttonStyle(.bordered)
                .tint(theme.accent)
                .disabled(!canShowHint)
                .accessibilityLabel("Show hint")

                Button {
                    checkAnswer()
                } label: {
                    Label("Check", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                .disabled(!canCheckAnswer)
            }

            if flow.isRetryingMissed {
                Button {
                    skipRetryQuestion()
                } label: {
                    Label("Skip", systemImage: "forward.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(theme.warning)
            }

            Button {
                nextQuestion()
            } label: {
                Label("Next", systemImage: "arrow.right.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WidgetNextButtonStyle(
                theme: theme,
                isEnabled: canAdvanceToNextQuestion,
                isHighlighted: isNextButtonHighlighted
            ))
            .disabled(!canAdvanceToNextQuestion)
        }
        .onChange(of: nextButtonPressToken) { _, _ in
            pulseNextButton()
        }
    }

    @ViewBuilder
    private var hintPanel: some View {
        if let currentQuestion, !currentQuestion.hints.isEmpty, hintLevel > 0 {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(currentQuestion.hints.prefix(hintLevel).enumerated()), id: \.offset) { index, hint in
                    Text("Hint \(index + 1): \(hint)")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(theme.primaryText)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.hintBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    @ViewBuilder
    private var feedbackPanel: some View {
        if let feedbackMessage {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: feedbackKind.systemImage)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(feedbackKind.color(theme: theme))
                    .frame(width: 30, height: 30)

                Text(feedbackMessage)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(14)
            .background(feedbackKind.background(theme: theme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func checkAnswer() {
        guard let currentQuestion else { return }

        if correctlyAnsweredQuestionIDs.contains(currentQuestion.id) {
            feedbackKind = .neutral
            feedbackMessage = "This question is already correct. Move to the next one."
            return
        }

        if let maxAttempts = document.rules?.maxAttemptsPerQuestion,
           maxAttempts > 0,
           (questionAttempts[currentQuestion.id] ?? 0) >= maxAttempts {
            feedbackKind = .warning
            feedbackMessage = "You have used all attempts for this question. Move to the next one."
            triggerShake()
            return
        }

        let unansweredBlank = currentQuestion.blanks.first { blank in
            response(for: blank, in: currentQuestion).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if let unansweredBlank {
            feedbackKind = .warning
            feedbackMessage = "Fill in \(unansweredBlank.label ?? unansweredBlank.id) first, then check it."
            triggerShake()
            return
        }

        let alreadyAnswered = answeredQuestionIDs.contains(currentQuestion.id)
        if alreadyAnswered && document.rules?.allowRetry == false {
            feedbackKind = .neutral
            feedbackMessage = "This one is already locked in. Move to the next question."
            return
        }

        let incorrectBlanks = currentQuestion.blanks.filter { blank in
            !WidgetActivityAnswerChecker.response(response(for: blank, in: currentQuestion), matches: blank)
        }

        attempts += 1
        questionAttempts[currentQuestion.id, default: 0] += 1
        answeredQuestionIDs.insert(currentQuestion.id)

        if incorrectBlanks.isEmpty {
            if !correctlyAnsweredQuestionIDs.contains(currentQuestion.id) {
                score += 1
            }
            correctlyAnsweredQuestionIDs.insert(currentQuestion.id)
            streak += 1
            longestStreak = max(longestStreak, streak)
            feedbackKind = .correct
            feedbackMessage = currentQuestion.correctFeedback
                ?? document.feedback?.defaultCorrect
                ?? "Correct. Nice work."
            triggerCelebration()
            triggerMeterFlashSequence()
        } else {
            streak = 0
            feedbackKind = .incorrect
            feedbackMessage = incorrectBlanks.first?.feedback
                ?? currentQuestion.incorrectFeedback
                ?? document.feedback?.defaultIncorrect
                ?? document.feedback?.defaultEncouragement
                ?? "Not yet. Check your answer and try again."
            triggerShake()
        }
    }

    private func nextQuestion() {
        guard !document.questions.isEmpty, canAdvanceToNextQuestion else { return }
        nextButtonPressToken = (nextButtonPressToken ?? 0) + 1

        if isReviewingAnswers {
            guard currentQuestionIndex < document.questions.count - 1 else {
                showFinalScore()
                return
            }
            currentQuestionIndex += 1
            prepareReviewQuestion()
            return
        }

        if flow.isRetryingMissed {
            advanceRetryQuestionOrFinish()
            return
        }

        guard currentQuestionIndex < document.questions.count - 1 else {
            showFinalScore()
            return
        }

        currentQuestionIndex += 1
        hintLevel = 0
        feedbackKind = .neutral
        feedbackMessage = nil
    }

    private func revealHint() {
        guard let currentQuestion else { return }
        hintLevel = min(hintLevel + 1, currentQuestion.hints.count)
    }

    private func resetWidget() {
        let submittedState = flow
        runtimeState = WidgetFillInTheBlankRuntimeState.initial(for: document)
        runtimeState.flow = WidgetActivityAttemptFlowState(
            hasSubmittedScore: submittedState.hasSubmittedScore,
            submittedRecord: submittedState.submittedRecord
        )
        feedbackKind = .neutral
        feedbackMessage = nil
        celebrate = false
        shake = false
        flashingMeterIndex = nil
        answeredQuestionIDs = []
        correctlyAnsweredQuestionIDs = []
        questionAttempts = [:]
        showsScoreSheet = false
    }

    private func showFinalScore() {
        var nextFlow = flow
        nextFlow.isShowingFinalScore = true
        nextFlow.isRetryingMissed = false
        nextFlow.isReviewingAnswers = false
        nextFlow.retryQuestionIndex = 0
        nextFlow.retryQuestionIDs = []
        flow = nextFlow
        hintLevel = 0
        feedbackKind = .neutral
        feedbackMessage = nil
    }

    private func beginReviewMathtivity() {
        guard !document.questions.isEmpty else { return }
        var nextFlow = flow
        nextFlow.isShowingFinalScore = false
        nextFlow.isRetryingMissed = false
        nextFlow.isReviewingAnswers = true
        nextFlow.retryQuestionIDs = []
        nextFlow.retryQuestionIndex = 0
        flow = nextFlow
        currentQuestionIndex = 0
        prepareReviewQuestion()
    }

    private func prepareReviewQuestion() {
        guard let currentQuestion else { return }
        activeMathInputRequestID = nil
        hintLevel = 0
        feedbackKind = correctlyAnsweredQuestionIDs.contains(currentQuestion.id) ? .correct : .incorrect
        feedbackMessage = reviewFeedback(for: currentQuestion)
    }

    private func reviewFeedback(for question: WidgetActivityQuestion) -> String {
        let status = correctlyAnsweredQuestionIDs.contains(question.id) ? "Correct." : "Missed."
        if let explanation = question.explanation, !explanation.isEmpty {
            return "\(status) \(explanation)"
        }
        return status
    }

    private func beginRetryMissed() {
        let missedIDs = missedQuestionIDs
        guard !missedIDs.isEmpty else { return }
        var nextFlow = flow
        nextFlow.isShowingFinalScore = false
        nextFlow.isRetryingMissed = true
        nextFlow.isReviewingAnswers = false
        nextFlow.retryQuestionIDs = missedIDs
        nextFlow.retryQuestionIndex = 0
        nextFlow.skippedRetryQuestionIDs = []
        flow = nextFlow
        hintLevel = 0
        feedbackKind = .neutral
        feedbackMessage = nil
    }

    private func skipRetryQuestion() {
        guard flow.isRetryingMissed, let currentQuestion else { return }
        var nextFlow = flow
        nextFlow.skippedRetryQuestionIDs.insert(currentQuestion.id)
        flow = nextFlow
        advanceRetryQuestionOrFinish()
    }

    private func advanceRetryQuestionOrFinish() {
        var nextFlow = flow
        let nextIndex = nextFlow.retryQuestionIndex + 1
        guard nextIndex < nextFlow.retryQuestionIDs.count else {
            showFinalScore()
            return
        }

        nextFlow.retryQuestionIndex = nextIndex
        flow = nextFlow
        hintLevel = 0
        feedbackKind = .neutral
        feedbackMessage = nil
    }

    private func submitCurrentScore() {
        var nextFlow = flow
        nextFlow.hasSubmittedScore = true
        nextFlow.submittedRecord = currentScoreRecord
        flow = nextFlow
        feedbackKind = .correct
        feedbackMessage = "Score submitted. You can resubmit if you retry or reset."
        triggerMeterFlashSequence()
    }

    private func prepareRuntimeStateIfNeeded() {
        if questionOrder.count != document.questions.count {
            runtimeState.questionOrder = WidgetFillInTheBlankRuntimeState.initial(for: document).questionOrder
        }

        if currentQuestionIndex >= max(document.questions.count, 1) {
            currentQuestionIndex = 0
        }
    }

    private func responseBinding(for blank: WidgetActivityBlank, in question: WidgetActivityQuestion) -> Binding<String> {
        let key = responseKey(for: blank, in: question)
        return Binding(
            get: { responsesByBlankID[key] ?? "" },
            set: { responsesByBlankID[key] = $0 }
        )
    }

    private func response(for blank: WidgetActivityBlank, in question: WidgetActivityQuestion) -> String {
        responsesByBlankID[responseKey(for: blank, in: question)] ?? ""
    }

    private func responseKey(for blank: WidgetActivityBlank, in question: WidgetActivityQuestion) -> String {
        "\(question.id)::\(blank.id)"
    }

    private func triggerCelebration() {
        celebrate = true
        Task {
            try? await Task.sleep(for: .milliseconds(420))
            celebrate = false
        }
    }

    private func triggerMeterFlashSequence() {
        Task {
            for index in [0, 1, 3, 2] {
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.08)) {
                        flashingMeterIndex = index
                    }
                }
                try? await Task.sleep(for: .milliseconds(130))
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.18)) {
                        flashingMeterIndex = nil
                    }
                }
                try? await Task.sleep(for: .milliseconds(55))
            }
        }
    }

    private func triggerShake() {
        shake = true
        Task {
            try? await Task.sleep(for: .milliseconds(360))
            shake = false
        }
    }

    private func pulseNextButton() {
        isNextButtonHighlighted = true
        Task {
            try? await Task.sleep(for: .milliseconds(260))
            isNextButtonHighlighted = false
        }
    }

    private static func greatestCommonDivisor(_ left: Int, _ right: Int) -> Int {
        var a = abs(left)
        var b = abs(right)
        while b != 0 {
            let remainder = a % b
            a = b
            b = remainder
        }
        return max(a, 1)
    }
}

private struct WidgetNextButtonStyle: ButtonStyle {
    let theme: WidgetActivityVisualTheme
    let isEnabled: Bool
    let isHighlighted: Bool

    func makeBody(configuration: Configuration) -> some View {
        let isActive = isEnabled && (configuration.isPressed || isHighlighted)
        configuration.label
            .font(.headline.weight(.black))
            .foregroundStyle(isEnabled ? activeTextColor(isActive: isActive) : theme.secondaryText.opacity(0.72))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(backgroundColor(isActive: isActive))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(borderColor(isActive: isActive), lineWidth: isActive ? 2.5 : 1.5)
            )
            .shadow(
                color: isActive ? theme.accent.opacity(0.34) : .black.opacity(isEnabled ? 0.08 : 0),
                radius: isActive ? 10 : 4,
                x: 0,
                y: isActive ? 5 : 2
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.16), value: isHighlighted)
    }

    private func activeTextColor(isActive: Bool) -> Color {
        isActive ? theme.badgeSelectedText : theme.primaryText
    }

    private func backgroundColor(isActive: Bool) -> Color {
        guard isEnabled else { return theme.panel.opacity(0.45) }
        return isActive ? theme.accent : theme.card.opacity(0.92)
    }

    private func borderColor(isActive: Bool) -> Color {
        guard isEnabled else { return theme.border.opacity(0.45) }
        return isActive ? theme.accent.opacity(0.95) : theme.border
    }
}

private struct ActivityScoreGaugePanel: View {
    let progress: Double
    let answeredCount: Int
    let totalCount: Int
    let score: Int
    let attempts: Int
    let streak: Int
    let longestStreak: Int
    let simplifiedFraction: String
    let equivalentFraction: String
    let decimal: String
    let percent: String
    let bonus: String
    let points: String
    let questionStarItems: [ActivityQuestionStarItem]
    let onSelectQuestion: (Int) -> Void
    let onShowFinalScore: () -> Void
    let flashingMeterIndex: Int?
    let scoreSheet: WidgetActivityScoreSheet
    @Binding var showsScoreSheet: Bool
    let onResetWidget: () -> Void
    let onEditWidget: (() -> Void)?
    let theme: WidgetActivityVisualTheme

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 18) {
                gaugeCluster
                    .frame(width: 340, height: 230)

                scoreTable
                    .frame(width: 190)
            }

            VStack(spacing: 14) {
                gaugeCluster
                    .frame(height: 230)

                scoreTable
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(theme.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 16, x: 0, y: 10)
        .animation(.spring(response: 0.55, dampingFraction: 0.78), value: progress)
        .animation(.spring(response: 0.45, dampingFraction: 0.72), value: score)
        .animation(.spring(response: 0.45, dampingFraction: 0.72), value: attempts)
    }

    private var gaugeCluster: some View {
        GaugeClusterView(
            progress: progress,
            answeredCount: answeredCount,
            totalCount: totalCount,
            score: score,
            attempts: attempts,
            simplifiedFraction: simplifiedFraction,
            decimal: decimal,
            percent: percent,
            flashingMeterIndex: flashingMeterIndex,
            theme: theme
        )
    }

    private var scoreTable: some View {
        ScoreSummaryTable(
            streak: streak,
            longestStreak: longestStreak,
            totalCount: totalCount,
            score: "\(score)/\(attempts)",
            bonus: bonus,
            points: points,
            questionStarItems: questionStarItems,
            onSelectQuestion: onSelectQuestion,
            onShowFinalScore: onShowFinalScore,
            scoreSheet: scoreSheet,
            showsScoreSheet: $showsScoreSheet,
            onResetWidget: onResetWidget,
            onEditWidget: onEditWidget,
            theme: theme
        )
    }
}

private struct GaugeClusterView: View {
    let progress: Double
    let answeredCount: Int
    let totalCount: Int
    let score: Int
    let attempts: Int
    let simplifiedFraction: String
    let decimal: String
    let percent: String
    let flashingMeterIndex: Int?
    let theme: WidgetActivityVisualTheme

    var body: some View {
        GeometryReader { proxy in
            let gaugeSize = min(max(proxy.size.width * 0.56, 142), min(proxy.size.height * 0.82, 188))
            let bubbleSize = min(max(gaugeSize * 0.48, 66), 84)
            let upperBubbleSize = bubbleSize * 1.16
            let centerX = proxy.size.width / 2
            let centerY = proxy.size.height * 0.50
            let upperBezelOverlap = upperBubbleSize * 0.28
            let lowerBezelOverlap = bubbleSize * 0.34
            let upperReach = gaugeSize / 2 + upperBubbleSize / 2 - upperBezelOverlap
            let lowerReach = gaugeSize / 2 + bubbleSize / 2 - lowerBezelOverlap
            let upperDialY = centerY - gaugeSize * 0.36
            let lowerDialY = centerY + gaugeSize * 0.40

            ZStack {
                RealisticProgressGauge(
                    progress: progress,
                    answeredCount: answeredCount,
                    totalCount: totalCount,
                    theme: theme
                )
                .frame(width: gaugeSize, height: gaugeSize)
                .position(x: centerX, y: centerY)

                ScoreMetricBubble(
                    title: "SCORE",
                    value: "\(score)/\(attempts)",
                    symbol: "checkmark",
                    tint: theme.correct,
                    isFlashing: flashingMeterIndex == 0,
                    theme: theme
                )
                .frame(width: upperBubbleSize, height: upperBubbleSize)
                .position(x: centerX - upperReach, y: upperDialY)

                ScoreMetricBubble(
                    title: "FRACTION",
                    value: simplifiedFraction,
                    symbol: "divide",
                    tint: theme.incorrect.opacity(0.90),
                    isFlashing: flashingMeterIndex == 1,
                    theme: theme
                )
                .frame(width: upperBubbleSize, height: upperBubbleSize)
                .position(x: centerX + upperReach, y: upperDialY)

                ScoreMetricBubble(
                    title: "DECIMAL",
                    value: decimal,
                    symbol: "number",
                    tint: Color(red: 0.24, green: 0.88, blue: 1.00),
                    isFlashing: flashingMeterIndex == 2,
                    theme: theme
                )
                .frame(width: bubbleSize, height: bubbleSize)
                .position(x: centerX - lowerReach * 0.72, y: lowerDialY)

                ScoreMetricBubble(
                    title: "PERCENT",
                    value: percent,
                    symbol: "percent",
                    tint: Color(red: 1.00, green: 0.86, blue: 0.25),
                    isFlashing: flashingMeterIndex == 3,
                    theme: theme
                )
                .frame(width: bubbleSize, height: bubbleSize)
                .position(x: centerX + lowerReach * 0.72, y: lowerDialY)
            }
        }
    }
}

private struct RealisticProgressGauge: View {
    let progress: Double
    let answeredCount: Int
    let totalCount: Int
    let theme: WidgetActivityVisualTheme

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    private var needleAngle: Double {
        -128 + clampedProgress * 256
    }

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let lineWidth = max(size * 0.055, 7)

            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [
                                Color.white.opacity(0.72),
                                Color.black.opacity(0.26),
                                Color.white.opacity(0.38),
                                Color.black.opacity(0.18),
                                Color.white.opacity(0.66)
                            ],
                            center: .center
                        )
                    )
                    .shadow(color: .black.opacity(0.34), radius: 15, x: 0, y: 8)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                theme.card.opacity(0.95),
                                theme.panel.opacity(0.88),
                                Color.black.opacity(0.26)
                            ],
                            center: .center,
                            startRadius: size * 0.08,
                            endRadius: size * 0.54
                        )
                    )
                    .padding(size * 0.045)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                AngularGradient(
                                    colors: [
                                        Color.white.opacity(0.46),
                                        Color.black.opacity(0.20),
                                        Color.white.opacity(0.30),
                                        Color.black.opacity(0.16),
                                        Color.white.opacity(0.46)
                                    ],
                                    center: .center
                                ),
                                lineWidth: lineWidth * 1.20
                            )
                            .blur(radius: 0.15)
                            .padding(size * 0.045)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color.black.opacity(0.22), lineWidth: lineWidth * 1.45)
                            .padding(size * 0.045)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                            .padding(size * 0.115)
                    )
                    .overlay(alignment: .topLeading) {
                        Ellipse()
                            .fill(Color.white.opacity(0.26))
                            .frame(width: size * 0.48, height: size * 0.20)
                            .blur(radius: 8)
                            .offset(x: size * 0.16, y: size * 0.12)
                    }
                    .shadow(color: .black.opacity(0.30), radius: 14, x: 0, y: 8)

                Circle()
                    .stroke(theme.progressTrack, lineWidth: lineWidth)
                    .padding(size * 0.16)

                Circle()
                    .trim(from: 0.14, to: 0.14 + clampedProgress * 0.72)
                    .stroke(
                        theme.progressFill,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                    .padding(size * 0.16)
                    .shadow(color: theme.accent.opacity(0.40), radius: 5, x: 0, y: 0)

                ForEach(0..<29, id: \.self) { index in
                    let isMajor = index % 4 == 0
                    let angle = -128 + Double(index) * (256.0 / 28.0)
                    Capsule()
                        .fill(isMajor ? theme.primaryText.opacity(0.78) : theme.secondaryText.opacity(0.42))
                        .frame(width: isMajor ? 2.8 : 1.4, height: isMajor ? size * 0.070 : size * 0.044)
                        .offset(y: -size * 0.300)
                        .rotationEffect(.degrees(angle))
                }

                GaugeNeedle(angle: needleAngle, size: size, theme: theme)

                Text("PROGRESS")
                    .font(.system(size: max(size * 0.043, 8), weight: .black, design: .rounded))
                    .foregroundStyle(theme.secondaryText)
                    .tracking(1.2)
                    .offset(y: size * 0.285)
            }
            .frame(width: size, height: size)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }
}

private struct GaugeNeedle: View {
    let angle: Double
    let size: Double
    let theme: WidgetActivityVisualTheme

    private var shadowX: Double {
        sin(angle * .pi / 180) * 4
    }

    private var shadowY: Double {
        cos(angle * .pi / 180) * 4
    }

    var body: some View {
        ZStack {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.96),
                            theme.accent.opacity(0.95),
                            Color.black.opacity(0.32)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: max(size * 0.030, 5), height: size * 0.38)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.48), lineWidth: 1)
                )
                .offset(y: -size * 0.19)
                .shadow(color: .black.opacity(0.38), radius: 4, x: shadowX, y: shadowY)
                .rotationEffect(.degrees(angle))

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.96),
                            theme.card,
                            Color.black.opacity(0.40)
                        ],
                        center: .topLeading,
                        startRadius: 2,
                        endRadius: size * 0.095
                    )
                )
                .frame(width: size * 0.18, height: size * 0.18)
                .overlay(Circle().strokeBorder(theme.border, lineWidth: 1))
                .shadow(color: .black.opacity(0.32), radius: 6, x: 0, y: 4)

            Circle()
                .fill(theme.accent.opacity(0.78))
                .frame(width: size * 0.055, height: size * 0.055)
        }
    }
}

private struct GaugeConnectorPanel: View {
    let theme: WidgetActivityVisualTheme

    var body: some View {
        GeometryReader { proxy in
            let strutWidth = proxy.size.width * 0.34
            let strutHeight = max(proxy.size.height * 0.12, 8)

            ZStack {
                HStack {
                    MechanicalStrut(theme: theme)
                        .frame(width: strutWidth, height: strutHeight)
                        .rotationEffect(.degrees(-12))
                    Spacer()
                    MechanicalStrut(theme: theme)
                        .frame(width: strutWidth, height: strutHeight)
                        .rotationEffect(.degrees(12))
                }
                .padding(.horizontal, proxy.size.width * 0.06)

                HStack {
                    MechanicalStrut(theme: theme)
                        .frame(width: strutWidth * 0.72, height: strutHeight)
                        .rotationEffect(.degrees(22))
                    Spacer()
                    MechanicalStrut(theme: theme)
                        .frame(width: strutWidth * 0.72, height: strutHeight)
                        .rotationEffect(.degrees(-22))
                }
                .padding(.horizontal, proxy.size.width * 0.16)
                .offset(y: proxy.size.height * 0.28)
            }
        }
    }
}

private struct MechanicalStrut: View {
    let theme: WidgetActivityVisualTheme

    var body: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.34),
                        Color(red: 0.35, green: 0.36, blue: 0.36).opacity(0.82),
                        Color.black.opacity(0.58)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
            .shadow(color: .black.opacity(0.28), radius: 6, x: 0, y: 4)
    }
}

private struct ScoreMetricBubble: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color
    let isFlashing: Bool
    let theme: WidgetActivityVisualTheme

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            Color.white.opacity(0.60),
                            Color.black.opacity(0.22),
                            Color.white.opacity(0.34),
                            Color.black.opacity(0.28),
                            Color.white.opacity(0.58)
                        ],
                        center: .center
                    )
                )
                .shadow(color: .black.opacity(0.24), radius: 10, x: 0, y: 6)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            theme.card.opacity(0.96),
                            theme.panel.opacity(0.88),
                            Color.black.opacity(0.24)
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: 58
                    )
                )
                .padding(7)
                .overlay(
                    Circle()
                        .strokeBorder(tint.opacity(0.86), lineWidth: 2)
                        .padding(10)
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.32), lineWidth: 1)
                        .padding(6)
                )
                .shadow(color: tint.opacity(0.18), radius: 7, x: 0, y: 0)

            VStack(spacing: 1) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(tint)

                if let fraction = FractionParts(value) {
                    FractionValueView(
                        numerator: fraction.numerator,
                        denominator: fraction.denominator,
                        theme: theme
                    )
                } else {
                    Text(value)
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.62)
                        .lineLimit(1)
                        .foregroundStyle(theme.primaryText)
                }

                Text(title)
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(isFlashing ? 0.96 : 0.0),
                            Color.white.opacity(isFlashing ? 0.58 : 0.0),
                            Color.white.opacity(0.0)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 44
                    )
                )
                .padding(5)
                .blendMode(.screen)
                .allowsHitTesting(false)
        }
        .scaleEffect(isFlashing ? 1.07 : 1)
        .shadow(color: Color.white.opacity(isFlashing ? 0.86 : 0), radius: isFlashing ? 18 : 0)
        .animation(.easeOut(duration: 0.16), value: isFlashing)
    }
}

private struct FractionParts {
    let numerator: String
    let denominator: String

    init?(_ value: String) {
        let pieces = value.split(separator: "/", maxSplits: 1).map(String.init)
        guard pieces.count == 2 else { return nil }
        numerator = pieces[0]
        denominator = pieces[1]
    }
}

private struct FractionValueView: View {
    let numerator: String
    let denominator: String
    let theme: WidgetActivityVisualTheme

    var body: some View {
        VStack(spacing: 1) {
            Text(numerator)
            Rectangle()
                .fill(theme.primaryText.opacity(0.86))
                .frame(width: 24, height: 2)
            Text(denominator)
        }
        .font(.system(size: 17, weight: .black, design: .rounded))
        .monospacedDigit()
        .minimumScaleFactor(0.60)
        .foregroundStyle(theme.primaryText)
        .lineLimit(1)
    }
}

private struct ScoreSummaryTable: View {
    let streak: Int
    let longestStreak: Int
    let totalCount: Int
    let score: String
    let bonus: String
    let points: String
    let questionStarItems: [ActivityQuestionStarItem]
    let onSelectQuestion: (Int) -> Void
    let onShowFinalScore: () -> Void
    let scoreSheet: WidgetActivityScoreSheet
    @Binding var showsScoreSheet: Bool
    let onResetWidget: () -> Void
    let onEditWidget: (() -> Void)?
    let theme: WidgetActivityVisualTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("STREAK")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(theme.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.card.opacity(0.88), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(theme.border, lineWidth: 1)
                )

            StreakStars(
                count: streak,
                totalCount: totalCount,
                questionItems: questionStarItems,
                theme: theme,
                onSelectQuestion: onSelectQuestion
            )

            VStack(alignment: .leading, spacing: 8) {
                scoreNavigationRow
                ScoreSummaryRow(label: "Longest Streak", value: "\(longestStreak)", theme: theme)
                ScoreSummaryRow(label: "Bonus", value: bonus, theme: theme)
                ScoreSummaryRow(label: "Points", value: points, theme: theme)
                scoreSheetButton
            }
            .padding(12)
            .background(theme.card.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(theme.border, lineWidth: 1)
            )

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [
                    theme.card.opacity(0.80),
                    theme.panel.opacity(0.70),
                    Color.black.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(theme.border, lineWidth: 1)
        )
    }

    private var scoreNavigationRow: some View {
        Button(action: onShowFinalScore) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Score")
                    .font(.caption.weight(.black))
                    .textCase(.uppercase)
                    .foregroundStyle(theme.accent)
                Spacer(minLength: 8)
                Text(score)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(theme.primaryText)
                Image(systemName: "arrow.right.circle.fill")
                    .font(.caption.weight(.black))
                    .foregroundStyle(theme.accent)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show final score")
        .accessibilityValue(score)
    }

    private var scoreSheetButton: some View {
        Button {
            showsScoreSheet.toggle()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 14, weight: .bold))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.bordered)
        .tint(theme.accent)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityLabel("Score sheet and widget settings")
        .popover(isPresented: $showsScoreSheet, arrowEdge: .trailing) {
            WidgetScoreSheetPopover(
                scoreSheet: scoreSheet,
                onResetWidget: onResetWidget,
                onEditWidget: onEditWidget,
                theme: theme
            )
        }
    }
}

private struct WidgetScoreSheetPopover: View {
    let scoreSheet: WidgetActivityScoreSheet
    let onResetWidget: () -> Void
    let onEditWidget: (() -> Void)?
    let theme: WidgetActivityVisualTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("File Score")
                    .font(.title3.weight(.black))
                    .foregroundStyle(theme.primaryText)

                Spacer(minLength: 12)

                Button(role: .destructive) {
                    onResetWidget()
                } label: {
                    Label("Reset Widget", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if let onEditWidget {
                    Button {
                        onEditWidget()
                    } label: {
                        Label("Edit Widget", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            VStack(spacing: 0) {
                scoreSheetHeader

                ForEach(scoreSheet.records) { record in
                    WidgetScoreSheetRow(record: record, theme: theme)
                }
            }
            .background(theme.card.opacity(0.74), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(theme.border, lineWidth: 1)
            )

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                ScoreSheetTotalRow(label: "Average", value: averageLabel, theme: theme)
                ScoreSheetTotalRow(label: "Points", value: pointsLabel, theme: theme)
                ScoreSheetTotalRow(label: "Points Possible", value: "\(scoreSheet.pointsPossible)", theme: theme)
            }
        }
        .padding(16)
        .frame(width: 430, alignment: .leading)
        .background(Color.white)
    }

    private var scoreSheetHeader: some View {
        HStack(spacing: 10) {
            Text("Widget")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Status")
                .frame(width: 84, alignment: .leading)
            Text("Score")
                .frame(width: 56, alignment: .trailing)
            Text("Pts")
                .frame(width: 52, alignment: .trailing)
        }
        .font(.caption.weight(.black))
        .foregroundStyle(theme.secondaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(theme.panel.opacity(0.75))
    }

    private var averageLabel: String {
        guard let averagePercent = scoreSheet.averagePercent else { return "N/A" }
        return "\(averagePercent)%"
    }

    private var pointsLabel: String {
        String(format: "%.1f", scoreSheet.totalPoints)
    }
}

private struct WidgetScoreSheetRow: View {
    let record: WidgetActivityScoreRecord
    let theme: WidgetActivityVisualTheme

    var body: some View {
        HStack(spacing: 10) {
            Text(record.title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(record.status.displayName)
                .font(.caption.weight(.bold))
                .foregroundStyle(statusColor)
                .frame(width: 84, alignment: .leading)

            Text(scoreLabel)
                .font(.callout.weight(.black))
                .monospacedDigit()
                .foregroundStyle(theme.primaryText)
                .frame(width: 56, alignment: .trailing)

            Text(pointsLabel)
                .font(.callout.weight(.black))
                .monospacedDigit()
                .foregroundStyle(theme.primaryText)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.border.opacity(0.55))
                .frame(height: 1)
        }
    }

    private var statusColor: Color {
        switch record.status {
        case .notStarted:
            return theme.secondaryText
        case .inProgress:
            return theme.warning
        case .complete:
            return theme.correct
        }
    }

    private var scoreLabel: String {
        guard record.attempts > 0 else { return "N/A" }
        return "\(record.score)/\(record.attempts)"
    }

    private var pointsLabel: String {
        guard record.attempts > 0 else { return "N/A" }
        return String(format: "%.1f", record.points)
    }
}

private struct ScoreSheetTotalRow: View {
    let label: String
    let value: String
    let theme: WidgetActivityVisualTheme

    var body: some View {
        HStack {
            Text(label)
                .font(.callout.weight(.semibold))
                .foregroundStyle(theme.secondaryText)
            Spacer(minLength: 10)
            Text(value)
                .font(.callout.weight(.black))
                .monospacedDigit()
                .foregroundStyle(theme.primaryText)
        }
    }
}

private struct ScoreSummaryRow: View {
    let label: String
    let value: String
    let theme: WidgetActivityVisualTheme

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.callout.weight(.semibold))
                .foregroundStyle(theme.secondaryText)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(theme.primaryText)
        }
    }
}

private struct StreakStars: View {
    let count: Int
    let totalCount: Int
    let questionItems: [ActivityQuestionStarItem]
    let theme: WidgetActivityVisualTheme
    let onSelectQuestion: (Int) -> Void

    var body: some View {
        let items = questionItems.isEmpty
            ? (0..<min(max(totalCount, 1), 25)).map { index in
                ActivityQuestionStarItem(
                    index: index,
                    title: "Question \(index + 1)",
                    status: index < count ? .correct : .unanswered,
                    isCurrent: false
                )
            }
            : Array(questionItems.prefix(25))
        let generalsBlue = Color(red: 0.00, green: 0.31, blue: 0.58)

        LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 6), count: 5), spacing: 8) {
            ForEach(items) { item in
                Button {
                    onSelectQuestion(item.index)
                } label: {
                    Image(systemName: item.status == .unanswered ? "star" : "star.fill")
                        .font(.system(size: 17, weight: .black))
                        .foregroundStyle(starColor(for: item.status, defaultBlue: generalsBlue))
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(starColor(for: item.status, defaultBlue: generalsBlue).opacity(item.status == .unanswered ? 0.04 : 0.14))
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(item.isCurrent ? theme.accent : starColor(for: item.status, defaultBlue: generalsBlue).opacity(item.status == .unanswered ? 0 : 0.46), lineWidth: item.isCurrent ? 2.5 : 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.title), \(accessibilityStatus(for: item.status))")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Question navigator")
    }

    private func starColor(for status: ActivityQuestionStarStatus, defaultBlue: Color) -> Color {
        switch status {
        case .unanswered:
            return theme.secondaryText.opacity(0.42)
        case .correct:
            return Color(red: 0.96, green: 0.67, blue: 0.08)
        case .incorrect:
            return theme.incorrect
        case .corrected:
            return theme.correct
        }
    }

    private func accessibilityStatus(for status: ActivityQuestionStarStatus) -> String {
        switch status {
        case .unanswered:
            return "not answered"
        case .correct:
            return "correct"
        case .incorrect:
            return "incorrect"
        case .corrected:
            return "corrected"
        }
    }
}

private enum ActivityQuestionStarStatus: Equatable {
    case unanswered
    case correct
    case incorrect
    case corrected
}

private struct ActivityQuestionStarItem: Identifiable, Equatable {
    let index: Int
    let title: String
    let status: ActivityQuestionStarStatus
    let isCurrent: Bool

    var id: Int { index }
}

private enum FeedbackKind {
    case neutral
    case correct
    case incorrect
    case warning

    init(_ runtimeKind: WidgetActivityFeedbackStateKind) {
        switch runtimeKind {
        case .neutral:
            self = .neutral
        case .correct:
            self = .correct
        case .incorrect:
            self = .incorrect
        case .warning:
            self = .warning
        }
    }

    var runtimeKind: WidgetActivityFeedbackStateKind {
        switch self {
        case .neutral:
            return .neutral
        case .correct:
            return .correct
        case .incorrect:
            return .incorrect
        case .warning:
            return .warning
        }
    }

    var systemImage: String {
        switch self {
        case .neutral:
            return "message.fill"
        case .correct:
            return "checkmark.seal.fill"
        case .incorrect:
            return "arrow.counterclockwise.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        }
    }

    func color(theme: WidgetActivityVisualTheme) -> Color {
        switch self {
        case .neutral:
            return theme.accent
        case .correct:
            return theme.correct
        case .incorrect:
            return theme.incorrect
        case .warning:
            return theme.warning
        }
    }

    func background(theme: WidgetActivityVisualTheme) -> Color {
        color(theme: theme).opacity(0.12)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
