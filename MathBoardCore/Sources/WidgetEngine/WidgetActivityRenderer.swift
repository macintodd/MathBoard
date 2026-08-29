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
    var gearConfiguration: WidgetGearConfiguration?
    private var runtimeStateBinding: Binding<WidgetActivityRuntimeState>?
    @State private var localRuntimeState: WidgetActivityRuntimeState

    init(
        document: ActivityWidgetDocument,
        themeOverride: WidgetActivityTheme? = nil,
        experienceOverride: WidgetActivityExperience? = nil,
        scoreSheet: WidgetActivityScoreSheet? = nil,
        onEditWidget: (() -> Void)? = nil,
        onMathInputRequested: (@MainActor (WidgetMathInputKeypadRequest) -> Void)? = nil,
        gearConfiguration: WidgetGearConfiguration? = nil,
        runtimeState: Binding<WidgetActivityRuntimeState>? = nil
    ) {
        self.document = document
        self.themeOverride = themeOverride
        self.experienceOverride = experienceOverride
        self.scoreSheet = scoreSheet
        self.onEditWidget = onEditWidget
        self.onMathInputRequested = onMathInputRequested
        self.gearConfiguration = gearConfiguration
        self.runtimeStateBinding = runtimeState
        _localRuntimeState = State(
            initialValue: WidgetActivityRuntimeState(
                multipleChoice: WidgetMultipleChoiceRuntimeState.initial(for: document),
                fillInTheBlank: WidgetFillInTheBlankRuntimeState.initial(for: document),
                interactiveParts: WidgetInteractivePartsRuntimeState()
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
                interactivePartsRuntimeState: activityRuntimeState.interactiveParts,
                scoreSheet: scoreSheet,
                onEditWidget: onEditWidget,
                theme: resolvedTheme,
                experience: experienceOverride ?? document.presentation?.preferredExperience,
                gearConfiguration: gearConfiguration
            )
        case .fillInTheBlank:
            FillInTheBlankActivityView(
                document: document,
                runtimeState: activityRuntimeState.fillInTheBlank,
                interactivePartsRuntimeState: activityRuntimeState.interactiveParts,
                scoreSheet: scoreSheet,
                onEditWidget: onEditWidget,
                theme: resolvedTheme,
                onMathInputRequested: onMathInputRequested,
                gearConfiguration: gearConfiguration
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
    @Binding var interactivePartsRuntimeState: WidgetInteractivePartsRuntimeState
    let scoreSheet: WidgetActivityScoreSheet?
    let onEditWidget: (() -> Void)?
    let theme: WidgetActivityVisualTheme
    let experience: WidgetActivityExperience?
    let gearConfiguration: WidgetGearConfiguration?

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
    @State private var retryStartedQuestionIDs: Set<String> = []

    init(
        document: ActivityWidgetDocument,
        runtimeState: Binding<WidgetMultipleChoiceRuntimeState>,
        interactivePartsRuntimeState: Binding<WidgetInteractivePartsRuntimeState>,
        scoreSheet: WidgetActivityScoreSheet? = nil,
        onEditWidget: (() -> Void)? = nil,
        theme: WidgetActivityVisualTheme,
        experience: WidgetActivityExperience? = nil,
        gearConfiguration: WidgetGearConfiguration? = nil
    ) {
        self.document = document
        _runtimeState = runtimeState
        _interactivePartsRuntimeState = interactivePartsRuntimeState
        self.scoreSheet = scoreSheet
        self.onEditWidget = onEditWidget
        self.theme = theme
        self.experience = experience
        self.gearConfiguration = gearConfiguration
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

    private var usesCheckOnlyInteractiveAnswer: Bool {
        guard let currentQuestion else { return false }
        return currentQuestionHasScorableInteractiveAnswer(currentQuestion)
            && currentQuestion.choices.contains { $0.isCorrect }
    }

    private var checkOnlyChoiceID: String? {
        guard usesCheckOnlyInteractiveAnswer else { return nil }
        return currentQuestion?.choices.first(where: { $0.isCorrect })?.id
    }

    private func currentQuestionHasScorableInteractiveAnswer(_ question: WidgetActivityQuestion) -> Bool {
        question.interactiveParts.contains { part in
            if case .numberLine(let numberLine) = part {
                return numberLine.answer != nil
            }
            return false
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
        interactivePartsRuntimeState.combinedScoreRecord(
            base: runtimeState.scoreRecord(for: document),
            document: document
        )
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
        guard !flow.isRetryingMissed else { return false }
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
            // Locked until the student explicitly presses Retry on this question.
            return !retryStartedQuestionIDs.contains(currentQuestion.id)
        }

        if correctlyAnsweredQuestionIDs.contains(currentQuestion.id) {
            return true
        }

        if answeredQuestionIDs.contains(currentQuestion.id) {
            return true
        }

        let effectiveMaxAttempts = document.rules?.maxRetries.map { max(1, $0 + 1) } ?? document.rules?.maxAttemptsPerQuestion
        if let maxAttempts = effectiveMaxAttempts,
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
            numberCorrectFirstTry: runtimeState.numberCorrectFirstTry,
            hasSubmittedScore: gearConfiguration?.isWidgetSubmitted ?? flow.hasSubmittedScore,
            gearConfiguration: gearConfiguration,
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
                if !usesCheckOnlyInteractiveAnswer {
                    choiceGrid
                }
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
            return "You have answered \(answeredQuestionIDs.count) of \(document.questions.count) questions."
        }
        if flow.isRetryingMissed {
            return "Review missed questions, then come back to this screen."
        }
        if missedQuestionCount == 0 {
            return "All questions are correct."
        }
        return "You missed \(missedQuestionCount) \(missedQuestionCount == 1 ? "question" : "questions")."
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

            if let parts = currentQuestion?.interactiveParts, !parts.isEmpty {
                WidgetActivityInteractivePartsView(
                    parts: parts,
                    runtimeState: $interactivePartsRuntimeState,
                    theme: theme,
                    isLocked: isCurrentQuestionLocked
                )
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
        guard !flow.isShowingFinalScore, !isReviewingAnswers, !isQuestionTyping, isExpressionRevealed, !isCurrentQuestionLocked else { return false }
        if usesCheckOnlyInteractiveAnswer {
            guard let currentQuestion else { return false }
            return currentQuestion.interactiveParts.contains { part in
                guard case .numberLine(let nl) = part, nl.answer != nil else { return false }
                return !interactivePartsRuntimeState.response(for: nl.id).isEmpty || nl.initialResponse != nil
            }
        }
        guard let selectedChoiceID else { return false }
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
            if flow.isRetryingMissed {
                if retryStartedQuestionIDs.contains(currentQuestionID) {
                    // Retry is underway: Check + Next (Next advances to next missed problem)
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
                } else {
                    // Gate: Retry + Skip. Retry resets the graph and begins the attempt.
                    Button {
                        startRetryQuestion()
                    } label: {
                        Label("Retry", systemImage: "arrow.counterclockwise.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
                    .controlSize(.regular)

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
            } else if !isReviewingAnswers {
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
            } else {
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

        // Number-line interactive scoring: score the actual graph, not the auto-selected choice.
        if usesCheckOnlyInteractiveAnswer {
            let scorableParts = currentQuestion.interactiveParts.compactMap { part -> WidgetActivityNumberLinePart? in
                guard case .numberLine(let nl) = part, nl.answer != nil else { return nil }
                return nl
            }
            let effectiveResponse: (WidgetActivityNumberLinePart) -> WidgetNumberLineRuntimeResponse = { part in
                let r = interactivePartsRuntimeState.response(for: part.id)
                if r.isEmpty, let initial = part.initialResponse {
                    return WidgetNumberLineRuntimeResponse(answer: initial)
                }
                return r
            }
            guard scorableParts.contains(where: { !effectiveResponse($0).isEmpty }) else {
                feedbackKind = .warning
                feedbackMessage = "Complete the graph first, then check it."
                triggerShake()
                return
            }
            let isCorrect = scorableParts.allSatisfy { part in
                guard let answer = part.answer else { return false }
                return effectiveResponse(part).matches(answer, step: part.domain.step)
            }
            attempts += 1
            questionAttempts[currentQuestion.id, default: 0] += 1
            if isCorrect {
                if !correctlyAnsweredQuestionIDs.contains(currentQuestion.id) {
                    score += 1
                }
                correctlyAnsweredQuestionIDs.insert(currentQuestion.id)
                answeredQuestionIDs.insert(currentQuestion.id)
                if let choiceID = checkOnlyChoiceID {
                    selectedChoiceID = choiceID
                    submittedChoiceID = choiceID
                    var sc = submittedChoiceIDsByQuestionID
                    sc[currentQuestion.id] = choiceID
                    submittedChoiceIDsByQuestionID = sc
                }
                streak += 1
                longestStreak = max(longestStreak, streak)
                feedbackKind = .correct
                feedbackMessage = currentQuestion.correctFeedback
                    ?? document.feedback?.defaultCorrect
                    ?? "Correct. Great work!"
                triggerCelebration()
                triggerMeterFlashSequence()
                scheduleAdvanceIfNeeded(correct: true)
            } else {
                streak = 0
                feedbackKind = .incorrect
                feedbackMessage = currentQuestion.incorrectFeedback
                    ?? document.feedback?.defaultIncorrect
                    ?? document.feedback?.defaultEncouragement
                    ?? "Not quite. Revise your graph and try again."
                triggerShake()
                // Lock the question so the student must press Next; it will appear in Retry Missed.
                answeredQuestionIDs.insert(currentQuestion.id)
                scheduleAdvanceIfNeeded(correct: false)
            }
            return
        }

        guard let selectedChoiceID = selectedChoiceID else {
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

        self.selectedChoiceID = choice.id

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
        interactivePartsRuntimeState = WidgetInteractivePartsRuntimeState()
        feedbackKind = .neutral
        feedbackMessage = nil
        celebrate = false
        shake = false
        flashingMeterIndex = nil
        answeredQuestionIDs = []
        correctlyAnsweredQuestionIDs = []
        questionAttempts = [:]
        retryStartedQuestionIDs = []
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
        retryStartedQuestionIDs = []
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

    private func startRetryQuestion() {
        guard flow.isRetryingMissed, let currentQuestion else { return }
        // Reset number-line responses so the student starts from initial state on retry.
        for part in currentQuestion.interactiveParts {
            if case .numberLine(let nl) = part {
                interactivePartsRuntimeState.setResponse(WidgetNumberLineRuntimeResponse(), for: nl.id)
            }
        }
        feedbackKind = .neutral
        feedbackMessage = nil
        retryStartedQuestionIDs.insert(currentQuestion.id)
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
    @Binding var interactivePartsRuntimeState: WidgetInteractivePartsRuntimeState
    let scoreSheet: WidgetActivityScoreSheet?
    let onEditWidget: (() -> Void)?
    let theme: WidgetActivityVisualTheme
    let onMathInputRequested: (@MainActor (WidgetMathInputKeypadRequest) -> Void)?
    var gearConfiguration: WidgetGearConfiguration? = nil

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
        interactivePartsRuntimeState.combinedScoreRecord(
            base: runtimeState.scoreRecord(for: document),
            document: document
        )
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
        let effectiveMaxAttempts = document.rules?.maxRetries.map { max(1, $0 + 1) } ?? document.rules?.maxAttemptsPerQuestion
        if let maxAttempts = effectiveMaxAttempts,
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
            numberCorrectFirstTry: runtimeState.numberCorrectFirstTry,
            hasSubmittedScore: gearConfiguration?.isWidgetSubmitted ?? flow.hasSubmittedScore,
            gearConfiguration: gearConfiguration,
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
            return "You have answered \(answeredQuestionIDs.count) of \(document.questions.count) questions."
        }
        if missedQuestionCount == 0 {
            return "All questions are correct."
        }
        return "You missed \(missedQuestionCount) \(missedQuestionCount == 1 ? "question" : "questions")."
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

            if let parts = currentQuestion?.interactiveParts, !parts.isEmpty {
                WidgetActivityInteractivePartsView(
                    parts: parts,
                    runtimeState: $interactivePartsRuntimeState,
                    theme: theme,
                    isLocked: isCurrentQuestionLocked
                )
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
        interactivePartsRuntimeState = WidgetInteractivePartsRuntimeState()
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
    let numberCorrectFirstTry: Int
    let hasSubmittedScore: Bool
    let gearConfiguration: WidgetGearConfiguration?
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
            answeredCount: answeredCount,
            totalCount: totalCount,
            numberCorrectFirstTry: numberCorrectFirstTry,
            scoreCount: score,
            hasSubmittedScore: hasSubmittedScore,
            questionStarItems: questionStarItems,
            onSelectQuestion: onSelectQuestion,
            onShowFinalScore: onShowFinalScore,
            showsScoreSheet: $showsScoreSheet,
            onResetWidget: onResetWidget,
            onEditWidget: onEditWidget,
            gearConfiguration: gearConfiguration,
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
    let answeredCount: Int
    let totalCount: Int
    let numberCorrectFirstTry: Int
    let scoreCount: Int
    let hasSubmittedScore: Bool
    let questionStarItems: [ActivityQuestionStarItem]
    let onSelectQuestion: (Int) -> Void
    let onShowFinalScore: () -> Void
    @Binding var showsScoreSheet: Bool
    let onResetWidget: () -> Void
    let onEditWidget: (() -> Void)?
    let gearConfiguration: WidgetGearConfiguration?
    let theme: WidgetActivityVisualTheme

    @State private var starsFlashed = false

    private var egoScore: Double {
        Double(scoreCount) + 0.1 * Double(longestStreak)
    }

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
            .scaleEffect(starsFlashed ? 1.12 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.45), value: starsFlashed)

            VStack(alignment: .leading, spacing: 8) {
                scoreNavigationRow
                ScoreSummaryRow(label: "1st Attempt", value: "\(numberCorrectFirstTry)/\(totalCount)", theme: theme)
                ScoreSummaryRow(label: "After Corrections", value: "\(scoreCount)/\(totalCount)", theme: theme)

                if hasSubmittedScore {
                    ScoreSummaryRow(
                        label: "Ego Score",
                        value: String(format: "%.1f", egoScore),
                        theme: theme
                    )
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                }

                scoreSheetButton
            }
            .padding(12)
            .background(theme.card.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(theme.border, lineWidth: 1)
            )
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: hasSubmittedScore)

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
        .onChange(of: hasSubmittedScore) { _, submitted in
            guard submitted else { return }
            starsFlashed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                starsFlashed = false
            }
        }
    }

    private var scoreNavigationRow: some View {
        Button(action: onShowFinalScore) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Score")
                    .font(.caption.weight(.black))
                    .textCase(.uppercase)
                    .foregroundStyle(theme.accent)
                Spacer(minLength: 8)
                Text("\(scoreCount)/\(totalCount)")
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
        .accessibilityValue("\(scoreCount)/\(totalCount)")
    }

    private var scoreSheetButton: some View {
        HStack(spacing: 8) {
            submitButton
            Button {
                showsScoreSheet.toggle()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.bordered)
            .tint(theme.accent)
            .accessibilityLabel("Widget settings")
            .popover(isPresented: $showsScoreSheet, arrowEdge: .trailing) {
                WidgetScoreSheetPopover(
                    gearConfiguration: gearConfiguration,
                    onResetWidget: onResetWidget,
                    onEditWidget: onEditWidget,
                    theme: theme
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    private var submitButton: some View {
        if gearConfiguration?.onSubmitWidget != nil {
            let isSubmitted = gearConfiguration?.isWidgetSubmitted == true
            let isReset = gearConfiguration?.isWidgetReset == true
            if isSubmitted && !isReset {
                Button {
                    gearConfiguration?.onResetAfterSubmit?()
                    onResetWidget()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            } else {
                let canSubmit = answeredCount >= totalCount
                Button {
                    gearConfiguration?.onSubmitWidget?()
                } label: {
                    Label(isReset ? "Resubmit" : "Submit", systemImage: "paperplane.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(!canSubmit)
            }
        }
    }
}

private struct WidgetScoreSheetPopover: View {
    let gearConfiguration: WidgetGearConfiguration?
    let onResetWidget: () -> Void
    let onEditWidget: (() -> Void)?
    let theme: WidgetActivityVisualTheme

    @State private var selectedFolderID: UUID? = nil
    @State private var newTagText: String = ""
    @State private var localTags: [String] = []
    @State private var localRequiresStudentWork: Bool = false
    @State private var hasInitialized = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                actionRow
                Divider()
                infoSection
                Divider()
                tagsSection
            }
            .padding(20)
        }
        .frame(width: 380)
        .background(Color.white)
        .onAppear {
            guard !hasInitialized else { return }
            hasInitialized = true
            localTags = gearConfiguration?.tags ?? []
            localRequiresStudentWork = gearConfiguration?.requiresStudentWork ?? false
        }
    }

    // MARK: Action Row

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button(role: .destructive, action: onResetWidget) {
                Label("Reset Widget", systemImage: "arrow.counterclockwise")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            if let onEditWidget {
                Button(action: onEditWidget) {
                    Label("Edit Widget", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }

            Spacer(minLength: 0)

            libraryStarButton
        }
    }

    // MARK: Library Star

    private var libraryStarButton: some View {
        Menu {
            if let folders = gearConfiguration?.libraryFolders, !folders.isEmpty {
                ForEach(folders) { folder in
                    Button {
                        saveToLibrary(folderID: folder.id)
                    } label: {
                        Label(folder.name, systemImage: "folder")
                    }
                }
                Divider()
            }
            Button {
                saveToLibrary(folderID: nil)
            } label: {
                Label("Save without folder", systemImage: "star")
            }
        } label: {
            let isInLibrary = gearConfiguration?.isInLibrary ?? false
            Image(systemName: isInLibrary ? "star.fill" : "star")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isInLibrary ? Color.yellow : theme.accent)
                .frame(width: 36, height: 36)
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("Save to library")
    }

    private func saveToLibrary(folderID: UUID?) {
        gearConfiguration?.onSaveToLibrary?(localTags, localRequiresStudentWork, folderID)
    }

    // MARK: Info Section

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let questionCount = gearConfiguration?.questionCount {
                HStack {
                    Text("Questions")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.primaryText)
                    Spacer()
                    Text("\(questionCount)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(theme.secondaryText)
                }
            }

            HStack {
                Text("Requires Student Work")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Toggle("", isOn: $localRequiresStudentWork)
                    .labelsHidden()
                    .onChange(of: localRequiresStudentWork) { _, value in
                        gearConfiguration?.onRequiresStudentWorkChanged?(value)
                    }
            }
        }
    }

    // MARK: Tags Section

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tags")
                .font(.subheadline.weight(.black))
                .foregroundStyle(theme.primaryText)

            if !localTags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(localTags, id: \.self) { tag in
                        tagChip(tag)
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Add tag…", text: $newTagText)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
                    .onSubmit { commitNewTag() }

                Button(action: commitNewTag) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)
                .disabled(newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func tagChip(_ tag: String) -> some View {
        HStack(spacing: 4) {
            Text("#\(tag)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.primaryText)
            Button {
                removeTag(tag)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(theme.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(theme.card, in: Capsule())
        .overlay(Capsule().strokeBorder(theme.border, lineWidth: 1))
    }

    private func commitNewTag() {
        let trimmed = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !localTags.contains(trimmed) else {
            newTagText = ""
            return
        }
        localTags.append(trimmed)
        newTagText = ""
        gearConfiguration?.onTagsChanged?(localTags)
    }

    private func removeTag(_ tag: String) {
        localTags.removeAll { $0 == tag }
        gearConfiguration?.onTagsChanged?(localTags)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
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

private struct WidgetActivityInteractivePartsView: View {
    let parts: [WidgetActivityInteractivePart]
    @Binding var runtimeState: WidgetInteractivePartsRuntimeState
    let theme: WidgetActivityVisualTheme
    let isLocked: Bool

    var body: some View {
        VStack(spacing: 12) {
            ForEach(parts) { part in
                switch part {
                case .numberLine(let numberLine):
                    WidgetActivityNumberLineInput(
                        part: numberLine,
                        response: numberLineResponseBinding(for: numberLine.id),
                        theme: theme,
                        isLocked: isLocked
                    )
                case .coordinatePlane(let coordinatePlane):
                    WidgetActivityCoordinatePlanePreview(part: coordinatePlane, theme: theme)
                }
            }
        }
    }

    private func numberLineResponseBinding(for partID: String) -> Binding<WidgetNumberLineRuntimeResponse> {
        Binding {
            runtimeState.response(for: partID)
        } set: { newValue in
            runtimeState.setResponse(newValue, for: partID)
        }
    }
}

private struct WidgetActivityNumberLineInput: View {
    let part: WidgetActivityNumberLinePart
    @Binding var response: WidgetNumberLineRuntimeResponse
    let theme: WidgetActivityVisualTheme
    let isLocked: Bool
    @State private var selectedPointValue: Double?
    @State private var dragStartValue: Double?
    @State private var activeDragSourceValue: Double?
    @State private var rayDragPreview: NumberLineRayDragPreview?
    @State private var activeRayDragContext: NumberLineRayDragContext?

    var body: some View {
        VStack(spacing: 8) {
            if isEditable {
                controlBar
            }

            GeometryReader { proxy in
                let metrics = NumberLineMetrics(size: proxy.size, domain: part.domain)
                let renderedResponse = response.isEmpty ? WidgetNumberLineRuntimeResponse(answer: part.initialResponse) : response
                let displayResponse = responseWithRayDragPreview(renderedResponse)
                ZStack {
                    NumberLineCanvas(
                        part: part,
                        response: displayResponse,
                        metrics: metrics,
                        theme: theme
                    )

                    if isEditable {
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        if dragStartValue == nil {
                                            dragStartValue = metrics.snappedValue(forX: value.startLocation.x)
                                            activeRayDragContext = rayDragContext(startLocation: value.startLocation, metrics: metrics)
                                            activeDragSourceValue = existingAnchorValue(near: dragStartValue ?? metrics.snappedValue(forX: value.startLocation.x))
                                        }
                                        handleCanvasDragChanged(value, metrics: metrics)
                                    }
                                    .onEnded { value in
                                        handleCanvasGesture(value, metrics: metrics)
                                    }
                            )

                        NumberLineSelectionOverlay(
                            selectedValue: selectedPointValue,
                            selectedRay: selectedRay(in: displayResponse),
                            metrics: metrics,
                            theme: theme,
                            showsRayHandles: part.features.pointHasRay && part.features.raysEnabled,
                            previewRay: previewRay(fromSelectedPoint:direction:visualEndValue:),
                            commitRay: commitRay(fromSelectedPoint:direction:visualEndValue:),
                            endRayPreview: endRayPreview
                        )
                    }
                }
            }
            .frame(minHeight: 116)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(theme.panel.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(theme.border.opacity(0.55), lineWidth: 1)
        )
        .accessibilityLabel("Number line")
    }

    private var isEditable: Bool {
        !isLocked && part.answer != nil
    }

    private var controlBar: some View {
        HStack(spacing: 8) {
            if let selectedPointValue {
                Text(formattedAxisValue(selectedPointValue))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(theme.choice.opacity(0.65), in: Capsule())

            }

            Spacer(minLength: 4)

            Button {
                response = WidgetNumberLineRuntimeResponse()
                selectedPointValue = nil
            } label: {
                Label("Clear", systemImage: "xmark.circle")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .foregroundStyle(theme.primaryText)
                    .background(theme.choice.opacity(0.7), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(response.isEmpty)
            .opacity(response.isEmpty ? 0.45 : 1)
        }
    }

    private func handleCanvasGesture(_ value: DragGesture.Value, metrics: NumberLineMetrics) {
        defer {
            dragStartValue = nil
            activeDragSourceValue = nil
            activeRayDragContext = nil
        }
        if let activeRayDragContext {
            commitRay(
                fromSelectedPoint: activeRayDragContext.endpoint,
                direction: rayDirection(endpoint: activeRayDragContext.endpoint, value: metrics.value(forX: value.location.x)),
                visualEndValue: metrics.value(forX: value.location.x)
            )
            return
        }
        let dragDistance = hypot(value.translation.width, value.translation.height)
        if dragDistance > 12, let activeDragSourceValue, part.features.pointsDraggable {
            moveSelectedAnchor(from: activeDragSourceValue, to: metrics.snappedValue(forX: value.location.x))
        } else {
            placeOrSelectAnchor(at: metrics.snappedValue(forX: value.location.x))
        }
    }

    private func handleCanvasDragChanged(_ value: DragGesture.Value, metrics: NumberLineMetrics) {
        if let activeRayDragContext {
            previewRay(
                fromSelectedPoint: activeRayDragContext.endpoint,
                direction: rayDirection(endpoint: activeRayDragContext.endpoint, value: metrics.value(forX: value.location.x)),
                visualEndValue: metrics.value(forX: value.location.x)
            )
            return
        }
        let dragDistance = hypot(value.translation.width, value.translation.height)
        guard dragDistance > 4, let activeDragSourceValue, part.features.pointsDraggable else { return }
        moveSelectedAnchor(from: activeDragSourceValue, to: metrics.snappedValue(forX: value.location.x))
    }

    private func placeOrSelectAnchor(at value: Double) {
        guard part.features.pointsTappable || part.features.pointsDraggable else { return }
        prepareResponseForEditing()

        if let existingValue = existingAnchorValue(near: value) {
            if part.features.openClosedEndpoints, let current = selectedPointValue, valuesMatch(existingValue, current) {
                toggleSelectedEndpointClosed()
            } else {
                selectedPointValue = existingValue
            }
            return
        }

        if convertSelectedRayToSegment(endingAt: value) {
            selectedPointValue = value
            return
        }

        if let maxPoints = part.features.maxPoints {
            if maxPoints == 1 {
                response = WidgetNumberLineRuntimeResponse()
            } else if anchorValues.count >= maxPoints {
                return
            }
        }

        response.selectedPoints.removeAll { valuesMatch($0, value) }
        response.points.append(WidgetActivityNumberLinePoint(value: value, isClosed: true))
        response.points.sort { $0.value < $1.value }
        selectedPointValue = value
    }

    private func moveSelectedAnchor(from startValue: Double, to endValue: Double) {
        guard !valuesMatch(startValue, endValue), part.features.pointsDraggable else { return }
        prepareResponseForEditing()
        let sourceValue = selectedPointValue.flatMap { existingAnchorValue(near: $0) } ?? existingAnchorValue(near: startValue)
        guard let sourceValue else { return }

        for index in response.points.indices where valuesMatch(response.points[index].value, sourceValue) {
            response.points[index].value = endValue
            selectedPointValue = endValue
            sortResponse()
            return
        }
        for index in response.rays.indices where valuesMatch(response.rays[index].endpoint, sourceValue) {
            let delta = endValue - sourceValue
            response.rays[index].endpoint = endValue
            if let visualEndValue = response.rays[index].visualEndValue {
                response.rays[index].visualEndValue = normalizedRayVisualEnd(
                    endpoint: endValue,
                    direction: response.rays[index].direction,
                    visualEndValue: visualEndValue + delta
                )
            }
            selectedPointValue = endValue
            sortResponse()
            return
        }
        for index in response.segments.indices {
            if valuesMatch(response.segments[index].start, sourceValue) {
                response.segments[index].start = endValue
                selectedPointValue = endValue
                sortResponse()
                return
            }
            if valuesMatch(response.segments[index].end, sourceValue) {
                response.segments[index].end = endValue
                selectedPointValue = endValue
                sortResponse()
                return
            }
        }
    }

    private func previewRay(fromSelectedPoint endpoint: Double, direction: WidgetActivityNumberLineRayDirection, visualEndValue: Double?) {
        guard part.features.pointHasRay, part.features.raysEnabled else { return }
        rayDragPreview = NumberLineRayDragPreview(
            endpoint: endpoint,
            direction: direction,
            isClosed: endpointIsClosed(at: endpoint),
            visualEndValue: normalizedRayVisualEnd(endpoint: endpoint, direction: direction, visualEndValue: visualEndValue)
        )
    }

    private func endRayPreview() {
        rayDragPreview = nil
    }

    private func commitRay(fromSelectedPoint endpoint: Double, direction: WidgetActivityNumberLineRayDirection, visualEndValue: Double?) {
        guard part.features.pointHasRay, part.features.raysEnabled else { return }
        prepareResponseForEditing()
        let wasClosed = endpointIsClosed(at: endpoint)
        response.points.removeAll { valuesMatch($0.value, endpoint) }
        response.selectedPoints.removeAll { valuesMatch($0, endpoint) }
        response.rays.removeAll { valuesMatch($0.endpoint, endpoint) }
        response.rays.append(WidgetActivityNumberLineRay(
            endpoint: endpoint,
            direction: direction,
            isClosed: wasClosed,
            visualEndValue: normalizedRayVisualEnd(endpoint: endpoint, direction: direction, visualEndValue: visualEndValue)
        ))
        selectedPointValue = endpoint
        rayDragPreview = nil
        sortResponse()
    }

    private func responseWithRayDragPreview(_ baseResponse: WidgetNumberLineRuntimeResponse) -> WidgetNumberLineRuntimeResponse {
        guard let rayDragPreview else { return baseResponse }
        var previewResponse = baseResponse
        previewResponse.points.removeAll { valuesMatch($0.value, rayDragPreview.endpoint) }
        previewResponse.selectedPoints.removeAll { valuesMatch($0, rayDragPreview.endpoint) }
        previewResponse.rays.removeAll { valuesMatch($0.endpoint, rayDragPreview.endpoint) }
        previewResponse.rays.append(WidgetActivityNumberLineRay(
            endpoint: rayDragPreview.endpoint,
            direction: rayDragPreview.direction,
            isClosed: rayDragPreview.isClosed,
            visualEndValue: rayDragPreview.visualEndValue
        ))
        return previewResponse
    }

    private func normalizedRayVisualEnd(
        endpoint: Double,
        direction: WidgetActivityNumberLineRayDirection,
        visualEndValue: Double?
    ) -> Double? {
        guard let visualEndValue, !valuesMatch(endpoint, visualEndValue) else { return nil }
        switch direction {
        case .left:
            return min(max(visualEndValue, part.domain.min), endpoint)
        case .right:
            return max(min(visualEndValue, part.domain.max), endpoint)
        }
    }

    private func convertSelectedRayToSegment(endingAt endValue: Double) -> Bool {
        guard part.features.segmentsEnabled,
              part.features.maxPoints != 1,
              let selectedPointValue,
              let rayIndex = response.rays.firstIndex(where: { valuesMatch($0.endpoint, selectedPointValue) })
        else { return false }

        let ray = response.rays[rayIndex]
        let isOnRaySide = (ray.direction == .right && endValue > ray.endpoint) || (ray.direction == .left && endValue < ray.endpoint)
        guard isOnRaySide, !valuesMatch(ray.endpoint, endValue) else { return false }

        response.rays.remove(at: rayIndex)
        response.points.removeAll { valuesMatch($0.value, ray.endpoint) || valuesMatch($0.value, endValue) }
        response.selectedPoints.removeAll { valuesMatch($0, ray.endpoint) || valuesMatch($0, endValue) }

        if ray.direction == .right {
            response.segments.append(WidgetActivityNumberLineSegment(
                start: ray.endpoint,
                end: endValue,
                startClosed: ray.isClosed,
                endClosed: true
            ))
        } else {
            response.segments.append(WidgetActivityNumberLineSegment(
                start: endValue,
                end: ray.endpoint,
                startClosed: true,
                endClosed: ray.isClosed
            ))
        }
        sortResponse()
        return true
    }

    private func toggleSelectedEndpointClosed() {
        guard part.features.openClosedEndpoints, let selectedPointValue else { return }
        prepareResponseForEditing()

        for index in response.points.indices where valuesMatch(response.points[index].value, selectedPointValue) {
            response.points[index].isClosed.toggle()
            return
        }
        for index in response.rays.indices where valuesMatch(response.rays[index].endpoint, selectedPointValue) {
            response.rays[index].isClosed.toggle()
            return
        }
        for index in response.segments.indices {
            if valuesMatch(response.segments[index].start, selectedPointValue) {
                response.segments[index].startClosed.toggle()
                return
            }
            if valuesMatch(response.segments[index].end, selectedPointValue) {
                response.segments[index].endClosed.toggle()
                return
            }
        }
    }

    private func endpointIsClosed(at value: Double) -> Bool {
        if let point = response.points.first(where: { valuesMatch($0.value, value) }) {
            return point.isClosed
        }
        if let ray = response.rays.first(where: { valuesMatch($0.endpoint, value) }) {
            return ray.isClosed
        }
        if let segment = response.segments.first(where: { valuesMatch($0.start, value) }) {
            return segment.startClosed
        }
        if let segment = response.segments.first(where: { valuesMatch($0.end, value) }) {
            return segment.endClosed
        }
        return true
    }

    private func selectedRay(in graph: WidgetNumberLineRuntimeResponse) -> WidgetActivityNumberLineRay? {
        guard let selectedPointValue else { return nil }
        return graph.rays.first { valuesMatch($0.endpoint, selectedPointValue) }
    }

    private func rayDragContext(startLocation: CGPoint, metrics: NumberLineMetrics) -> NumberLineRayDragContext? {
        guard part.features.pointHasRay, part.features.raysEnabled, let selectedPointValue else { return nil }
        let endpointX = metrics.x(for: selectedPointValue)
        let existingRay = response.rays.first { valuesMatch($0.endpoint, selectedPointValue) } ?? rayDragPreview.map {
            WidgetActivityNumberLineRay(
                endpoint: $0.endpoint,
                direction: $0.direction,
                isClosed: $0.isClosed,
                visualEndValue: $0.visualEndValue
            )
        }

        let candidateHandleXs: [CGFloat]
        if let existingRay {
            candidateHandleXs = [handleX(for: existingRay, endpointX: endpointX, metrics: metrics)]
        } else {
            candidateHandleXs = [
                max(metrics.left + 22, endpointX - 36),
                min(metrics.right - 22, endpointX + 36)
            ]
        }

        guard candidateHandleXs.contains(where: { abs(startLocation.x - $0) <= 34 && abs(startLocation.y - metrics.axisY) <= 34 }) else {
            return nil
        }
        return NumberLineRayDragContext(endpoint: selectedPointValue)
    }

    private func handleX(for ray: WidgetActivityNumberLineRay, endpointX: CGFloat, metrics: NumberLineMetrics) -> CGFloat {
        if let visualEndValue = ray.visualEndValue {
            return metrics.x(for: visualEndValue)
        }
        switch ray.direction {
        case .left:
            return metrics.left
        case .right:
            return metrics.right
        }
    }

    private func rayDirection(endpoint: Double, value: Double) -> WidgetActivityNumberLineRayDirection {
        value < endpoint ? .left : .right
    }

    private func existingAnchorValue(near value: Double) -> Double? {
        let candidates = anchorValues
        return candidates.min { abs($0 - value) < abs($1 - value) }
            .flatMap { abs($0 - value) <= part.domain.step * 0.5 ? $0 : nil }
    }

    private var anchorValues: [Double] {
        var values: [Double] = response.selectedPoints
            + response.points.map { $0.value }
            + response.rays.map { $0.endpoint }
        for segment in response.segments {
            values.append(segment.start)
            values.append(segment.end)
        }
        return values.reduce(into: [Double]()) { result, value in
            if result.contains(where: { valuesMatch($0, value) }) == false {
                result.append(value)
            }
        }
    }

    private func sortResponse() {
        response.points.sort { $0.value < $1.value }
        response.rays.sort {
            if $0.endpoint != $1.endpoint { return $0.endpoint < $1.endpoint }
            return $0.direction.rawValue < $1.direction.rawValue
        }
        response.segments.sort {
            if min($0.start, $0.end) != min($1.start, $1.end) { return min($0.start, $0.end) < min($1.start, $1.end) }
            return max($0.start, $0.end) < max($1.start, $1.end)
        }
    }

    private func prepareResponseForEditing() {
        if response.isEmpty, let initialResponse = part.initialResponse {
            response = WidgetNumberLineRuntimeResponse(answer: initialResponse)
        }
    }

    private func valuesMatch(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) <= max(part.domain.step * 0.0001, 0.000001)
    }
}

private struct NumberLineRayDragPreview {
    var endpoint: Double
    var direction: WidgetActivityNumberLineRayDirection
    var isClosed: Bool
    var visualEndValue: Double?
}

private struct NumberLineRayDragContext {
    var endpoint: Double
}

private struct NumberLineSelectionOverlay: View {
    let selectedValue: Double?
    let selectedRay: WidgetActivityNumberLineRay?
    let metrics: NumberLineMetrics
    let theme: WidgetActivityVisualTheme
    let showsRayHandles: Bool
    let previewRay: (Double, WidgetActivityNumberLineRayDirection, Double?) -> Void
    let commitRay: (Double, WidgetActivityNumberLineRayDirection, Double?) -> Void
    let endRayPreview: () -> Void
    @State private var rayDragOriginX: CGFloat?

    var body: some View {
        if let selectedValue {
            let x = metrics.x(for: selectedValue)
            let y = metrics.axisY
            ZStack {
                if showsRayHandles {
                    if let selectedRay {
                        rayHandle(
                            direction: selectedRay.direction,
                            endpoint: selectedValue,
                            startX: handleX(for: selectedRay, endpointX: x),
                            allowsDirectionFlip: true
                        )
                            .position(x: handleX(for: selectedRay, endpointX: x), y: y)
                    } else {
                        rayHandle(
                            direction: .left,
                            endpoint: selectedValue,
                            startX: max(metrics.left + 22, x - 36),
                            allowsDirectionFlip: false
                        )
                            .position(x: max(metrics.left + 22, x - 36), y: y)
                        rayHandle(
                            direction: .right,
                            endpoint: selectedValue,
                            startX: min(metrics.right - 22, x + 36),
                            allowsDirectionFlip: false
                        )
                            .position(x: min(metrics.right - 22, x + 36), y: y)
                    }
                }
            }
        }
    }

    private func rayHandle(
        direction: WidgetActivityNumberLineRayDirection,
        endpoint: Double,
        startX: CGFloat,
        allowsDirectionFlip: Bool
    ) -> some View {
        Image(systemName: direction == .left ? "arrowtriangle.left.fill" : "arrowtriangle.right.fill")
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(theme.accent)
            .frame(width: 44, height: 44)
            .allowsHitTesting(false)
            .contentShape(Circle())
            .accessibilityLabel(direction == .left ? "Add left ray" : "Add right ray")
    }

    private func handleX(for ray: WidgetActivityNumberLineRay, endpointX: CGFloat) -> CGFloat {
        if let visualEndValue = ray.visualEndValue {
            return metrics.x(for: visualEndValue)
        }
        switch ray.direction {
        case .left:
            return metrics.left
        case .right:
            return metrics.right
        }
    }

    private func rayDragUpdate(
        direction: WidgetActivityNumberLineRayDirection,
        endpoint: Double,
        startX: CGFloat,
        translation: CGFloat,
        allowsDirectionFlip: Bool
    ) -> (direction: WidgetActivityNumberLineRayDirection, visualEndValue: Double)? {
        let proposedValue = metrics.value(forX: startX + translation)
        if allowsDirectionFlip {
            if proposedValue < endpoint {
                return (.left, proposedValue)
            }
            if proposedValue > endpoint {
                return (.right, proposedValue)
            }
            return nil
        }

        switch direction {
        case .left:
            return proposedValue < endpoint ? (.left, proposedValue) : nil
        case .right:
            return proposedValue > endpoint ? (.right, proposedValue) : nil
        }
    }
}

private struct NumberLineCanvas: View {
    let part: WidgetActivityNumberLinePart
    let response: WidgetNumberLineRuntimeResponse
    let metrics: NumberLineMetrics
    let theme: WidgetActivityVisualTheme

    var body: some View {
        Canvas { context, size in
            let domain = part.domain
            let tickCount = min(Int((domain.max - domain.min) / domain.step), 200)
            var axis = Path()
            axis.move(to: CGPoint(x: metrics.left, y: metrics.axisY))
            axis.addLine(to: CGPoint(x: metrics.right, y: metrics.axisY))
            context.stroke(axis, with: .color(theme.primaryText.opacity(0.78)), lineWidth: 3)

            for tickIndex in 0...tickCount {
                let value = domain.min + Double(tickIndex) * domain.step
                let x = metrics.x(for: value)
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: metrics.axisY - 8))
                tick.addLine(to: CGPoint(x: x, y: metrics.axisY + 8))
                context.stroke(tick, with: .color(theme.secondaryText.opacity(0.72)), lineWidth: 1.5)

                if part.features.labelsVisible && shouldLabelTick(tickIndex: tickIndex, tickCount: tickCount) {
                    let text = Text(formattedAxisValue(value))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(theme.secondaryText)
                    context.draw(text, at: CGPoint(x: x, y: metrics.axisY + 26), anchor: .center)
                }
            }

            for segment in response.segments {
                drawSegment(segment, context: context)
            }
            for ray in response.rays {
                drawRay(ray, context: context)
            }
            for point in response.selectedPoints {
                drawPoint(point, context: context)
            }
            for point in response.points {
                drawPoint(point.value, isClosed: point.isClosed, context: context)
            }
        }
    }

    private func drawSegment(_ segment: WidgetActivityNumberLineSegment, context: GraphicsContext) {
        let startX = metrics.x(for: segment.start)
        let endX = metrics.x(for: segment.end)
        var path = Path()
        path.move(to: CGPoint(x: startX, y: metrics.axisY))
        path.addLine(to: CGPoint(x: endX, y: metrics.axisY))
        context.stroke(path, with: .color(theme.accent), lineWidth: 6)
        drawEndpoint(at: segment.start, isClosed: segment.startClosed, context: context)
        drawEndpoint(at: segment.end, isClosed: segment.endClosed, context: context)
    }

    private func drawRay(_ ray: WidgetActivityNumberLineRay, context: GraphicsContext) {
        let startX = metrics.x(for: ray.endpoint)
        let endX = ray.visualEndValue.map { metrics.x(for: $0) } ?? (ray.direction == .left ? metrics.left : metrics.right)
        var path = Path()
        path.move(to: CGPoint(x: startX, y: metrics.axisY))
        path.addLine(to: CGPoint(x: endX, y: metrics.axisY))
        context.stroke(path, with: .color(theme.accent), lineWidth: 6)

        let arrowSize: CGFloat = 9
        var arrow = Path()
        if ray.direction == .left {
            arrow.move(to: CGPoint(x: endX, y: metrics.axisY))
            arrow.addLine(to: CGPoint(x: endX + arrowSize, y: metrics.axisY - arrowSize))
            arrow.move(to: CGPoint(x: endX, y: metrics.axisY))
            arrow.addLine(to: CGPoint(x: endX + arrowSize, y: metrics.axisY + arrowSize))
        } else {
            arrow.move(to: CGPoint(x: endX, y: metrics.axisY))
            arrow.addLine(to: CGPoint(x: endX - arrowSize, y: metrics.axisY - arrowSize))
            arrow.move(to: CGPoint(x: endX, y: metrics.axisY))
            arrow.addLine(to: CGPoint(x: endX - arrowSize, y: metrics.axisY + arrowSize))
        }
        context.stroke(arrow, with: .color(theme.accent), lineWidth: 3)
        drawEndpoint(at: ray.endpoint, isClosed: ray.isClosed, context: context)
    }

    private func drawPoint(_ value: Double, context: GraphicsContext) {
        drawPoint(value, isClosed: true, context: context)
    }

    private func drawPoint(_ value: Double, isClosed: Bool, context: GraphicsContext) {
        drawEndpoint(at: value, isClosed: isClosed, context: context)
    }

    private func drawEndpoint(at value: Double, isClosed: Bool, context: GraphicsContext) {
        let center = CGPoint(x: metrics.x(for: value), y: metrics.axisY)
        let r: CGFloat = 10
        let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        let path = Path(ellipseIn: rect)
        if isClosed {
            context.fill(path, with: .color(theme.accent))
        } else {
            context.stroke(path, with: .color(theme.accent), lineWidth: 2.5)
        }
    }

    private func shouldLabelTick(tickIndex: Int, tickCount: Int) -> Bool {
        if tickCount <= 12 { return true }
        let stride = max(Int(ceil(Double(tickCount) / 10.0)), 1)
        return tickIndex == 0 || tickIndex == tickCount || tickIndex.isMultiple(of: stride)
    }
}

private struct NumberLineMetrics {
    let size: CGSize
    let domain: WidgetActivityNumberLineDomain
    let left: CGFloat
    let right: CGFloat
    let axisY: CGFloat

    init(size: CGSize, domain: WidgetActivityNumberLineDomain) {
        self.size = size
        self.domain = domain
        left = 22
        right = max(left, size.width - 22)
        axisY = size.height * 0.48
    }

    func x(for value: Double) -> CGFloat {
        let span = max(domain.max - domain.min, domain.step)
        return left + CGFloat((value - domain.min) / span) * (right - left)
    }

    func value(forX x: CGFloat) -> Double {
        let percent = min(max((x - left) / max(right - left, 1), 0), 1)
        return domain.min + Double(percent) * (domain.max - domain.min)
    }

    func snappedValue(forX x: CGFloat) -> Double {
        let rawValue = value(forX: x)
        guard domain.step > 0 else { return rawValue }
        let snapped = (rawValue / domain.step).rounded() * domain.step
        return min(max(snapped, domain.min), domain.max)
    }
}

private struct WidgetActivityCoordinatePlanePreview: View {
    let part: WidgetActivityCoordinatePlanePart
    let theme: WidgetActivityVisualTheme

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 24
            let plotRect = CGRect(
                x: inset,
                y: inset,
                width: max(size.width - inset * 2, 1),
                height: max(size.height - inset * 2, 1)
            )
            let domain = part.domain
            let xSpan = max(domain.xMax - domain.xMin, domain.xStep)
            let ySpan = max(domain.yMax - domain.yMin, domain.yStep)

            let xTickCount = min(Int((domain.xMax - domain.xMin) / domain.xStep), 200)
            let yTickCount = min(Int((domain.yMax - domain.yMin) / domain.yStep), 200)

            for tickIndex in 0...xTickCount {
                let value = domain.xMin + Double(tickIndex) * domain.xStep
                let x = plotRect.minX + CGFloat((value - domain.xMin) / xSpan) * plotRect.width
                var line = Path()
                line.move(to: CGPoint(x: x, y: plotRect.minY))
                line.addLine(to: CGPoint(x: x, y: plotRect.maxY))
                context.stroke(line, with: .color(theme.border.opacity(0.5)), lineWidth: 1)
            }

            for tickIndex in 0...yTickCount {
                let value = domain.yMin + Double(tickIndex) * domain.yStep
                let y = plotRect.maxY - CGFloat((value - domain.yMin) / ySpan) * plotRect.height
                var line = Path()
                line.move(to: CGPoint(x: plotRect.minX, y: y))
                line.addLine(to: CGPoint(x: plotRect.maxX, y: y))
                context.stroke(line, with: .color(theme.border.opacity(0.5)), lineWidth: 1)
            }

            let axisColor = theme.primaryText.opacity(0.78)
            if domain.yMin <= 0, domain.yMax >= 0 {
                let zeroY = plotRect.maxY - CGFloat((0 - domain.yMin) / ySpan) * plotRect.height
                var xAxis = Path()
                xAxis.move(to: CGPoint(x: plotRect.minX, y: zeroY))
                xAxis.addLine(to: CGPoint(x: plotRect.maxX, y: zeroY))
                context.stroke(xAxis, with: .color(axisColor), lineWidth: 2)
            }
            if domain.xMin <= 0, domain.xMax >= 0 {
                let zeroX = plotRect.minX + CGFloat((0 - domain.xMin) / xSpan) * plotRect.width
                var yAxis = Path()
                yAxis.move(to: CGPoint(x: zeroX, y: plotRect.minY))
                yAxis.addLine(to: CGPoint(x: zeroX, y: plotRect.maxY))
                context.stroke(yAxis, with: .color(axisColor), lineWidth: 2)
            }

            if part.features.labelsVisible {
                let xMinText = Text(formattedAxisValue(domain.xMin)).font(.caption2.weight(.bold)).foregroundStyle(theme.secondaryText)
                let xMaxText = Text(formattedAxisValue(domain.xMax)).font(.caption2.weight(.bold)).foregroundStyle(theme.secondaryText)
                let yMaxText = Text(formattedAxisValue(domain.yMax)).font(.caption2.weight(.bold)).foregroundStyle(theme.secondaryText)
                context.draw(xMinText, at: CGPoint(x: plotRect.minX, y: plotRect.maxY + 13), anchor: .center)
                context.draw(xMaxText, at: CGPoint(x: plotRect.maxX, y: plotRect.maxY + 13), anchor: .center)
                context.draw(yMaxText, at: CGPoint(x: plotRect.minX - 12, y: plotRect.minY), anchor: .trailing)
            }
        }
        .frame(minHeight: 180)
        .background(theme.panel.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(theme.border.opacity(0.55), lineWidth: 1)
        )
        .accessibilityLabel("Coordinate plane")
    }
}

private func formattedAxisValue(_ value: Double) -> String {
    if value.rounded() == value {
        return String(Int(value))
    }
    return String(format: "%.1f", value)
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
