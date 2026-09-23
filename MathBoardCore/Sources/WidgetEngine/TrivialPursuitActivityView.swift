//
//  TrivialPursuitActivityView.swift
//  WidgetEngine
//
//  Host-controlled party trivia game. The teacher iPad runs the full game;
//  live multi-device sync is a future phase.
//

import SwiftUI

#if os(macOS)
import AppKit
#endif

private extension Color {
    static var trivialSystemBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #elseif os(iOS)
        Color(uiColor: .systemBackground)
        #else
        Color.gray.opacity(0.04)
        #endif
    }

    static var trivialSecondarySystemBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #elseif os(iOS)
        Color(uiColor: .secondarySystemBackground)
        #else
        Color.secondary.opacity(0.08)
        #endif
    }

    static var trivialTertiarySystemBackground: Color {
        #if os(macOS)
        Color(nsColor: .underPageBackgroundColor)
        #elseif os(iOS)
        Color(uiColor: .tertiarySystemBackground)
        #else
        Color.secondary.opacity(0.05)
        #endif
    }

    static var trivialSeparator: Color {
        #if os(macOS)
        Color(nsColor: .separatorColor)
        #elseif os(iOS)
        Color(uiColor: .separator)
        #else
        Color.gray.opacity(0.35)
        #endif
    }
}

// MARK: - Root View

struct TrivialPursuitActivityView: View {
    @Environment(\.widgetClassroomGameContext) private var classroomGameContext

    let document: ActivityWidgetDocument
    @Binding var runtimeState: WidgetTrivialPursuitRuntimeState
    var scoreSheet: WidgetActivityScoreSheet?
    var onEditWidget: (() -> Void)?
    var gearConfiguration: WidgetGearConfiguration?

    @State private var engine: TrivialPursuitGameEngine

    init(
        document: ActivityWidgetDocument,
        runtimeState: Binding<WidgetTrivialPursuitRuntimeState> = .constant(WidgetTrivialPursuitRuntimeState()),
        scoreSheet: WidgetActivityScoreSheet? = nil,
        onEditWidget: (() -> Void)? = nil,
        gearConfiguration: WidgetGearConfiguration? = nil
    ) {
        self.document = document
        _runtimeState = runtimeState
        self.scoreSheet = scoreSheet
        self.onEditWidget = onEditWidget
        self.gearConfiguration = gearConfiguration
        _engine = State(initialValue: TrivialPursuitGameEngine(document: document))
    }

    var body: some View {
        Group {
            if classroomGameContext?.role == .student {
                TrivialPursuitStudentAnswerView(
                    document: document,
                    runtimeState: $runtimeState,
                    context: classroomGameContext
                )
            } else {
                switch engine.phase {
                case .setup:
                    TrivialPursuitSetupView(
                        engine: engine,
                        runtimeState: $runtimeState,
                        hasClassroomPlayers: !(classroomGameContext?.participants.isEmpty ?? true)
                    )
                case .categoryPick(let activePlayerIndex):
                    twoPanel {
                        TrivialPursuitCategoryPickView(
                            engine: engine,
                            runtimeState: $runtimeState,
                            activePlayerIndex: activePlayerIndex
                        )
                    }
                case .questionActive(let categoryID, let questionIndex, let activePlayerIndex):
                    twoPanel {
                        TrivialPursuitQuestionView(
                            engine: engine,
                            runtimeState: $runtimeState,
                            classroomGameContext: classroomGameContext,
                            widgetID: gearConfiguration?.widgetID,
                            categoryID: categoryID,
                            questionIndex: questionIndex,
                            activePlayerIndex: activePlayerIndex
                        )
                    }
                case .questionResult(let categoryID, let questionIndex, let winnerPlayerIndex, let activePlayerIndex):
                    twoPanel {
                        TrivialPursuitResultView(
                            engine: engine,
                            runtimeState: $runtimeState,
                            categoryID: categoryID,
                            questionIndex: questionIndex,
                            winnerPlayerIndex: winnerPlayerIndex,
                            activePlayerIndex: activePlayerIndex
                        )
                    }
                case .gameWon(let playerIndex):
                    TrivialPursuitGameWonView(engine: engine, runtimeState: $runtimeState, playerIndex: playerIndex)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: engine.phase)
        .onAppear {
            configureClassroomPlayersIfNeeded()
            syncEnginePhaseFromRuntimeState()
        }
        .onChange(of: classroomGameContext?.participants ?? []) { _, _ in
            configureClassroomPlayersIfNeeded()
            syncEnginePhaseFromRuntimeState()
        }
        .onChange(of: runtimeState) { _, _ in
            syncEnginePhaseFromRuntimeState()
        }
    }

    private func configureClassroomPlayersIfNeeded() {
        guard let classroomGameContext,
              classroomGameContext.role == .teacher,
              !classroomGameContext.participants.isEmpty,
              engine.phase == .setup else { return }
        engine.configurePlayers(from: classroomGameContext.participants)
    }

    private func syncEnginePhaseFromRuntimeState() {
        guard classroomGameContext?.role == .teacher else { return }
        if engine.players.isEmpty {
            configureClassroomPlayersIfNeeded()
        }
        guard runtimeState.isGameStarted, !engine.players.isEmpty else { return }
        engine.applyEarnedCategoryIDs(runtimeState.earnedCategoryIDsByParticipantID)

        let activePlayerIndex = min(runtimeState.activePlayerIndex, max(engine.players.count - 1, 0))
        let desiredPhase: TrivialPursuitGamePhase
        if let categoryID = runtimeState.activeCategoryID,
           let questionIndex = runtimeState.activeQuestionIndex {
            if runtimeState.winnerDisplayName != nil {
                let winnerIndex = runtimeState.winnerParticipantID.flatMap { participantID in
                    engine.players.firstIndex { $0.id == participantID }
                }
                if let winnerIndex,
                   engine.players[winnerIndex].earnedCategoryIDs.count == engine.categories.count {
                    desiredPhase = .gameWon(playerIndex: winnerIndex)
                } else {
                    desiredPhase = .questionResult(
                        categoryID: categoryID,
                        questionIndex: questionIndex,
                        winnerPlayerIndex: winnerIndex,
                        activePlayerIndex: activePlayerIndex
                    )
                }
            } else {
                desiredPhase = .questionActive(
                    categoryID: categoryID,
                    questionIndex: questionIndex,
                    activePlayerIndex: activePlayerIndex
                )
            }
        } else {
            desiredPhase = .categoryPick(activePlayerIndex: activePlayerIndex)
        }

        if engine.phase != desiredPhase {
            engine.phase = desiredPhase
        }
    }

    @ViewBuilder
    func twoPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 0) {
            TrivialPursuitScoreboardPanel(engine: engine)
                .frame(width: 250)
            Divider()
            content()
        }
    }
}

// MARK: - Scoreboard Panel

private struct TrivialPursuitScoreboardPanel: View {
    let engine: TrivialPursuitGameEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Scoreboard")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(engine.players.enumerated()), id: \.element.id) { index, player in
                        TrivialPursuitPlayerRow(player: player, categories: engine.categories, index: index)
                        if index < engine.players.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .padding(.top, 8)
            }

            Spacer()
        }
        .background(Color.trivialSecondarySystemBackground)
    }
}

private struct TrivialPursuitPlayerRow: View {
    let player: TrivialPursuitGamePlayer
    let categories: [TrivialPursuitCategory]
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("\(index + 1)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.secondary)
                    .clipShape(Circle())
                Text(player.name)
                    .font(.subheadline.bold())
                    .lineLimit(1)
            }

            HStack(spacing: 5) {
                ForEach(categories) { category in
                    let earned = player.earnedCategoryIDs.contains(category.id)
                    Circle()
                        .fill(earned ? Color(hexString: category.color) : Color(hexString: category.color).opacity(0.15))
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle()
                                .strokeBorder(Color(hexString: category.color).opacity(earned ? 0 : 0.5), lineWidth: 1)
                        )
                        .overlay(
                            earned ? Text("★").font(.system(size: 9)).foregroundStyle(.white) : nil
                        )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Setup View

struct TrivialPursuitSetupView: View {
    @Bindable var engine: TrivialPursuitGameEngine
    @Binding var runtimeState: WidgetTrivialPursuitRuntimeState
    let hasClassroomPlayers: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Text("🎲")
                        .font(.system(size: 56))
                    Text("Trivial Pursuit Party")
                        .font(.largeTitle.bold())
                    Text(hasClassroomPlayers ? "Class roster loaded — first to collect all 6 wedges wins!" : "Enter player names — first to collect all 6 wedges wins!")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 32)

                VStack(spacing: 12) {
                    ForEach(engine.setupPlayerNames.indices, id: \.self) { index in
                        HStack(spacing: 12) {
                            Text("Player \(index + 1)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(width: 72, alignment: .leading)
                            TextField("Name", text: $engine.setupPlayerNames[index])
                                .textFieldStyle(.roundedBorder)
                                .disabled(hasClassroomPlayers)
                        }
                    }
                }
                .frame(maxWidth: 380)

                if !hasClassroomPlayers {
                    HStack(spacing: 12) {
                        if engine.setupPlayerNames.count > 2 {
                            Button(action: engine.removeLastSetupPlayer) {
                                Label("Remove", systemImage: "minus.circle")
                            }
                            .buttonStyle(.bordered)
                            .tint(.secondary)
                        }
                        if engine.setupPlayerNames.count < 8 {
                            Button(action: engine.addSetupPlayer) {
                                Label("Add Player", systemImage: "plus.circle")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                if !engine.categories.isEmpty {
                    VStack(spacing: 8) {
                        Text("Categories")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            ForEach(engine.categories) { category in
                                VStack(spacing: 4) {
                                    Text(category.emoji)
                                        .font(.title2)
                                    Text(category.name)
                                        .font(.caption2)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .frame(width: 60)
                                }
                                .padding(8)
                                .background(Color(hexString: category.color).opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }

                Button("Start Game") {
                    engine.startGame()
                    runtimeState.isGameStarted = true
                    runtimeState.earnedCategoryIDsByParticipantID = [:]
                    if case .categoryPick(let activePlayerIndex) = engine.phase {
                        runtimeState.activePlayerIndex = activePlayerIndex
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!engine.canStartGame)
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.trivialSystemBackground)
    }
}

// MARK: - Category Pick View

private struct TrivialPursuitCategoryPickView: View {
    let engine: TrivialPursuitGameEngine
    @Binding var runtimeState: WidgetTrivialPursuitRuntimeState
    let activePlayerIndex: Int

    var activePlayer: TrivialPursuitGamePlayer? {
        engine.players.indices.contains(activePlayerIndex) ? engine.players[activePlayerIndex] : nil
    }

    var body: some View {
        VStack(spacing: 20) {
            if let player = activePlayer {
                VStack(spacing: 4) {
                    Text(player.name)
                        .font(.title.bold())
                    Text("Pick a category")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)
            }

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 14
            ) {
                ForEach(engine.categories) { category in
                    let alreadyWon = activePlayer?.earnedCategoryIDs.contains(category.id) ?? false
                    TrivialPursuitCategoryTile(
                        category: category,
                        isWon: alreadyWon
                    ) {
                        engine.pickCategory(category.id, activePlayerIndex: activePlayerIndex)
                        if case .questionActive(let categoryID, let questionIndex, let activePlayerIndex) = engine.phase {
                            runtimeState.isGameStarted = true
                            runtimeState.roundID = UUID().uuidString
                            runtimeState.activeCategoryID = categoryID
                            runtimeState.activeQuestionIndex = questionIndex
                            runtimeState.activePlayerIndex = activePlayerIndex
                            runtimeState.didRevealChoices = false
                            runtimeState.choicesRevealedAt = nil
                            runtimeState.revealedCorrectChoiceID = nil
                            runtimeState.winnerParticipantID = nil
                            runtimeState.winnerDisplayName = nil
                            runtimeState.localAnswer = nil
                        }
                    }
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.trivialSystemBackground)
    }
}

private struct TrivialPursuitCategoryTile: View {
    let category: TrivialPursuitCategory
    let isWon: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Text(category.emoji)
                    .font(.system(size: 36))
                Text(category.name)
                    .font(.subheadline.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if isWon {
                    Label("Earned", systemImage: "star.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(.yellow)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 130)
            .padding(12)
            .background(Color(hexString: category.color).opacity(isWon ? 0.25 : 0.9))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color(hexString: category.color).opacity(0.3), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .scaleEffect(isWon ? 0.95 : 1.0)
    }
}

// MARK: - Question View

private struct TrivialPursuitQuestionView: View {
    let engine: TrivialPursuitGameEngine
    @Binding var runtimeState: WidgetTrivialPursuitRuntimeState
    let classroomGameContext: WidgetClassroomGameContext?
    let widgetID: UUID?
    let categoryID: String
    let questionIndex: Int
    let activePlayerIndex: Int

    @State private var showChoices = false
    @State private var isSendingChoices = false
    @State private var teacherAnswer: WidgetTrivialPursuitAnswer? = nil
    @State private var revealedChoiceIndex: Int? = nil
    @State private var now = Date()

    private static let choiceLabels = ["A", "B", "C", "D"]
    private static let answerWindowSeconds: TimeInterval = 10
    private static let studentRevealHeadStartSeconds: TimeInterval = 1.5

    private var category: TrivialPursuitCategory? { engine.category(forID: categoryID) }
    private var question: TrivialPursuitQuestion? { engine.question(forCategoryID: categoryID, at: questionIndex) }
    private var suggestedWinner: (playerIndex: Int?, displayName: String)? {
        guard let widgetID,
              let roundID = runtimeState.roundID else { return nil }
        var candidates: [(participantID: String, displayName: String, elapsedTime: Double)] = currentRoundAnswerRecords(widgetID: widgetID, roundID: roundID)
            .filter { $0.correctCount > 0 }
            .map { record in
                (
                    participantID: record.participantID,
                    displayName: record.displayName,
                    elapsedTime: answerElapsedTime(for: record)
                )
            }

        if let teacherAnswer, teacherAnswer.isCorrect {
            candidates.append((
                participantID: teacherAnswer.participantID,
                displayName: teacherDisplayName,
                elapsedTime: teacherAnswerElapsedTime(teacherAnswer)
            ))
        }

        guard let winner = candidates.min(by: { $0.elapsedTime < $1.elapsedTime }) else { return nil }
        let playerIndex = engine.players.firstIndex { $0.id == winner.participantID }
        return (playerIndex: playerIndex, displayName: winner.displayName)
    }

    private var teacherDisplayName: String {
        guard let teacherID = classroomGameContext?.currentParticipantID,
              let player = engine.players.first(where: { $0.id == teacherID }) else { return "Teacher" }
        return player.name
    }

    private func answerElapsedTime(for record: WidgetClassroomLiveProgressRecord) -> Double {
        if let elapsed = record.metadata["trivialPursuitAnswerElapsed"].flatMap(Double.init) {
            return elapsed
        }
        guard let revealedAt = runtimeState.choicesRevealedAt else {
            return record.updatedAt.timeIntervalSince1970
        }
        let answeredAt = record.metadata["trivialPursuitAnsweredAt"].flatMap(Double.init) ?? record.updatedAt.timeIntervalSince1970
        return max(0, answeredAt - revealedAt.timeIntervalSince1970)
    }

    private func teacherAnswerElapsedTime(_ answer: WidgetTrivialPursuitAnswer) -> Double {
        guard let revealedAt = runtimeState.choicesRevealedAt else {
            return answer.answeredAt.timeIntervalSince1970
        }
        return max(0, answer.answeredAt.timeIntervalSince(revealedAt))
    }

    private var answeredStudentCount: Int {
        guard let widgetID,
              let roundID = runtimeState.roundID else { return 0 }
        return currentRoundAnswerRecords(widgetID: widgetID, roundID: roundID).count
    }

    private var answeredContestantCount: Int {
        answeredStudentCount + (teacherAnswer == nil ? 0 : 1)
    }

    private var expectedContestantCount: Int {
        expectedStudentCount + 1
    }

    private var expectedStudentCount: Int {
        let activeStudentIDs = currentWidgetActiveStudentIDs
        if !activeStudentIDs.isEmpty {
            return activeStudentIDs.count
        }
        return classroomGameContext?.participants.filter { $0.role == .student }.count ?? 0
    }

    private var currentWidgetActiveStudentIDs: Set<String> {
        guard let widgetID else { return [] }
        return Set(classroomGameContext?.liveProgressRecords.compactMap { record in
            guard record.widgetID == widgetID,
                  record.isActiveOnStudentScreen else { return nil }
            return record.participantID
        } ?? [])
    }

    private var remainingSeconds: Int {
        guard let revealedAt = runtimeState.choicesRevealedAt else { return Int(Self.answerWindowSeconds) }
        let remaining = Self.answerWindowSeconds - now.timeIntervalSince(revealedAt)
        return max(0, min(Int(Self.answerWindowSeconds), Int(ceil(remaining))))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let cat = category {
                HStack(spacing: 8) {
                    Text(cat.emoji)
                        .font(.title3)
                    Text(cat.name)
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color(hexString: cat.color))
                .foregroundStyle(.white)
            }

            ScrollView {
                VStack(spacing: 20) {
                    if let q = question {
                        if let winnerDisplayName = runtimeState.winnerDisplayName {
                            winnerSplash(name: winnerDisplayName)
                                .padding(.horizontal, 20)
                                .padding(.top, 20)
                        }

                        Text(q.prompt)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.top, 20)

                        if !showChoices {
                            Button(isSendingChoices ? "Sending to Students..." : "Show Choices") {
                                sendChoicesToStudentsBeforeHostReveal()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(category.map { Color(hexString: $0.color) } ?? .blue)
                            .controlSize(.large)
                            .disabled(isSendingChoices)
                        } else {
                            HStack(spacing: 10) {
                                Label("\(remainingSeconds)s", systemImage: "timer")
                                    .font(.headline.monospacedDigit())
                                Text("\(answeredContestantCount)/\(max(expectedContestantCount, 1)) answered")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.trivialSecondarySystemBackground)
                            .clipShape(Capsule())

                            VStack(spacing: 10) {
                                ForEach(Array(q.choices.prefix(4).enumerated()), id: \.offset) { index, choice in
                                    TrivialPursuitChoiceTile(
                                        label: Self.choiceLabels[safe: index] ?? "\(index + 1)",
                                        text: choice.label,
                                        state: choiceState(for: index, choice: choice),
                                        isEnabled: teacherAnswer == nil && revealedChoiceIndex == nil && remainingSeconds > 0
                                    ) {
                                        submitTeacherAnswer(choice: choice, index: index)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)

                            if let revealed = revealedChoiceIndex {
                                awardSection(question: q, revealedIndex: revealed)
                                    .padding(.top, 4)
                            }
                        }
                    } else {
                        Text("Question not found.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.trivialSystemBackground)
        .onAppear {
            syncChoiceDisplayFromRuntime()
        }
        .onChange(of: runtimeState) { _, _ in
            syncChoiceDisplayFromRuntime()
        }
        .task(id: runtimeState.roundID) {
            while !Task.isCancelled {
                now = Date()
                syncChoiceDisplayFromRuntime()
                resolveRoundIfNeeded()
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    return
                }
            }
        }
        .onChange(of: classroomGameContext?.liveProgressRecords ?? []) { _, _ in
            resolveRoundIfNeeded()
        }
    }

    private func syncChoiceDisplayFromRuntime() {
        if runtimeState.didRevealChoices,
           let revealDate = runtimeState.choicesRevealedAt,
           now < revealDate,
           runtimeState.winnerDisplayName == nil {
            showChoices = false
        } else {
            showChoices = runtimeState.didRevealChoices
        }
        if let revealedCorrectChoiceID = runtimeState.revealedCorrectChoiceID,
           let correctIndex = question?.choices.firstIndex(where: { $0.id == revealedCorrectChoiceID }) {
            revealedChoiceIndex = correctIndex
        } else if runtimeState.winnerDisplayName == nil {
            revealedChoiceIndex = nil
        }
    }

    private func sendChoicesToStudentsBeforeHostReveal() {
        guard !isSendingChoices else { return }
        isSendingChoices = true
        runtimeState.didRevealChoices = true
        runtimeState.choicesRevealedAt = Date().addingTimeInterval(Self.studentRevealHeadStartSeconds)

        Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(Int(Self.studentRevealHeadStartSeconds * 1000)))
            } catch {
                return
            }
            now = Date()
            withAnimation(.easeOut(duration: 0.2)) {
                showChoices = true
                isSendingChoices = false
            }
        }
    }

    private func choiceState(for index: Int, choice: WidgetActivityChoice) -> TrivialPursuitChoiceTile.State {
        if let revealed = revealedChoiceIndex {
            if index == revealed { return .correct }
            if teacherAnswer?.choiceIndex == index { return .incorrect }
            return .normal
        }
        if teacherAnswer?.choiceID == choice.id { return .selected }
        return .normal
    }

    private func submitTeacherAnswer(choice: WidgetActivityChoice, index: Int) {
        guard teacherAnswer == nil,
              revealedChoiceIndex == nil,
              remainingSeconds > 0 else { return }
        let participantID = classroomGameContext?.currentParticipantID
            ?? (engine.players.indices.contains(activePlayerIndex) ? engine.players[activePlayerIndex].id : "teacher-local")
        teacherAnswer = WidgetTrivialPursuitAnswer(
            participantID: participantID,
            choiceID: choice.id,
            choiceIndex: index,
            isCorrect: choice.isCorrect,
            answeredAt: Date()
        )
    }

    @ViewBuilder
    private func awardSection(question: TrivialPursuitQuestion, revealedIndex: Int) -> some View {
        let isCorrectChoice = question.choices.indices.contains(revealedIndex) && question.choices[revealedIndex].isCorrect

        VStack(spacing: 12) {
            Divider()

            if isCorrectChoice {
                if let suggestedWinner {
                    VStack(spacing: 6) {
                        Text(suggestedWinner.displayName)
                            .font(.title2.bold())
                        Text("first correct answer")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Text("Who answered first?")
                    .font(.headline)

                let columns = Array(repeating: GridItem(.flexible()), count: min(engine.players.count, 3))
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(engine.players.enumerated()), id: \.element.id) { playerIndex, player in
                        Button(player.name) {
                            awardRound(toPlayerIndex: playerIndex, displayName: player.name)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(category.map { Color(hexString: $0.color) } ?? .blue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    }
                }
                .padding(.horizontal, 20)

                Button("No one got it") {
                    awardRound(toPlayerIndex: nil, displayName: "No winner this round")
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
            } else {
                Button("Skip — show correct answer") {
                    // reveal the correct choice by setting to its index
                    if let correctIndex = question.choices.firstIndex(where: \.isCorrect) {
                        revealedChoiceIndex = correctIndex
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 20)
    }

    private func currentRoundAnswerRecords(
        widgetID: UUID,
        roundID: String
    ) -> [WidgetClassroomLiveProgressRecord] {
        classroomGameContext?.liveProgressRecords.filter {
            $0.widgetID == widgetID &&
            $0.metadata["trivialPursuitRoundID"] == roundID &&
            $0.attemptedCount > 0
        } ?? []
    }

    private func resolveRoundIfNeeded() {
        guard showChoices,
              runtimeState.winnerDisplayName == nil else { return }
        let allContestantsAnswered = expectedContestantCount > 0 && answeredContestantCount >= expectedContestantCount
        guard remainingSeconds == 0 || allContestantsAnswered else { return }

        if revealedChoiceIndex == nil, let question,
           let correctIndex = question.choices.firstIndex(where: { $0.isCorrect }) {
            revealedChoiceIndex = correctIndex
            runtimeState.revealedCorrectChoiceID = question.choices[correctIndex].id
        }
    }

    private func awardRound(toPlayerIndex playerIndex: Int?, displayName: String) {
        engine.awardWedge(
            toPlayerIndex: playerIndex,
            forCategoryID: categoryID,
            questionIndex: questionIndex,
            activePlayerIndex: activePlayerIndex
        )
        runtimeState.winnerParticipantID = playerIndex.flatMap { engine.players.indices.contains($0) ? engine.players[$0].id : nil }
        runtimeState.winnerDisplayName = displayName
        runtimeState.earnedCategoryIDsByParticipantID = engine.earnedCategoryIDsByParticipantID
        runtimeState.localAnswer = nil
    }

    private func winnerSplash(name: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: name == "No winner this round" ? "timer" : "star.circle.fill")
                .font(.system(size: 42))
                .foregroundStyle(name == "No winner this round" ? Color.secondary : Color.yellow)
            Text(name)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(name == "No winner this round" ? "No correct answer in time" : "wins the wedge")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Color.trivialSecondarySystemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct TrivialPursuitStudentAnswerView: View {
    let document: ActivityWidgetDocument
    @Binding var runtimeState: WidgetTrivialPursuitRuntimeState
    let context: WidgetClassroomGameContext?

    @State private var now = Date()

    private static let choiceLabels = ["A", "B", "C", "D"]
    private static let answerWindowSeconds: TimeInterval = 10

    private var category: TrivialPursuitCategory? {
        guard let categoryID = runtimeState.activeCategoryID else { return nil }
        return document.categories?.first { $0.id == categoryID }
    }

    private var question: TrivialPursuitQuestion? {
        guard let category,
              let questionIndex = runtimeState.activeQuestionIndex,
              category.questions.indices.contains(questionIndex) else { return nil }
        return category.questions[questionIndex]
    }

    private var remainingSeconds: Int {
        guard let revealedAt = runtimeState.choicesRevealedAt else { return Int(Self.answerWindowSeconds) }
        let remaining = Self.answerWindowSeconds - now.timeIntervalSince(revealedAt)
        return max(0, min(Int(Self.answerWindowSeconds), Int(ceil(remaining))))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let category {
                HStack(spacing: 8) {
                    Text(category.emoji)
                        .font(.title3)
                    Text(category.name)
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color(hexString: category.color))
                .foregroundStyle(.white)
            }

            if let question {
                ScrollView {
                    VStack(spacing: 20) {
                        if let winnerDisplayName = runtimeState.winnerDisplayName {
                            winnerSplash(name: winnerDisplayName)
                                .padding(.horizontal, 20)
                                .padding(.top, 20)
                        }

                        Text(question.prompt)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.top, 24)

                        if runtimeState.didRevealChoices {
                            Label("\(remainingSeconds)s", systemImage: "timer")
                                .font(.headline.monospacedDigit())
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.trivialSecondarySystemBackground)
                                .clipShape(Capsule())

                            VStack(spacing: 12) {
                                ForEach(Array(question.choices.prefix(4).enumerated()), id: \.offset) { index, choice in
                                    TrivialPursuitChoiceTile(
                                        label: Self.choiceLabels[safe: index] ?? "\(index + 1)",
                                        text: choice.label,
                                        state: studentChoiceState(choiceID: choice.id),
                                        isEnabled: runtimeState.localAnswer == nil && runtimeState.winnerDisplayName == nil && remainingSeconds > 0
                                    ) {
                                        submit(choice: choice, index: index)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)

                            if runtimeState.localAnswer != nil {
                                Label("Answer submitted — waiting for results", systemImage: "checkmark.circle")
                                    .font(.headline)
                                    .foregroundStyle(Color.secondary)
                                    .padding(.top, 4)
                            }
                        } else {
                            VStack(spacing: 10) {
                                ProgressView()
                                Text("Waiting for the teacher to reveal answers")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 24)
                        }
                    }
                    .padding(.bottom, 24)
                }
            } else {
                categoryWaitingView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.trivialSystemBackground)
        .task(id: runtimeState.roundID) {
            while !Task.isCancelled {
                now = Date()
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    return
                }
            }
        }
    }

    private var categoryWaitingView: some View {
        VStack(spacing: 18) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(document.categories ?? []) { category in
                    VStack(spacing: 8) {
                        Text(category.emoji)
                            .font(.system(size: 34))
                        Text(category.name)
                            .font(.caption.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)
                    }
                    .frame(maxWidth: .infinity, minHeight: 92)
                    .padding(8)
                    .background(Color(hexString: category.color).opacity(0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color(hexString: category.color), lineWidth: 2)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 24)

            Text("Waiting for teacher to select category")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(Color.trivialSystemBackground)
    }

    private func studentChoiceState(choiceID: String) -> TrivialPursuitChoiceTile.State {
        if runtimeState.revealedCorrectChoiceID == choiceID {
            return .correct
        }
        guard let answer = runtimeState.localAnswer,
              answer.choiceID == choiceID else { return .normal }
        return runtimeState.revealedCorrectChoiceID == nil ? .selected : .incorrect
    }

    private func submit(choice: WidgetActivityChoice, index: Int) {
        guard runtimeState.localAnswer == nil,
              runtimeState.winnerDisplayName == nil,
              remainingSeconds > 0,
              let participantID = context?.currentParticipantID else { return }
        runtimeState.localAnswer = WidgetTrivialPursuitAnswer(
            participantID: participantID,
            choiceID: choice.id,
            choiceIndex: index,
            isCorrect: choice.isCorrect,
            answeredAt: Date()
        )
    }

    private func winnerSplash(name: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: name == "No winner this round" ? "timer" : "star.circle.fill")
                .font(.system(size: 42))
                .foregroundStyle(name == "No winner this round" ? Color.secondary : Color.yellow)
            Text(name)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(name == "No winner this round" ? "No correct answer in time" : "wins the wedge")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Color.trivialSecondarySystemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct TrivialPursuitChoiceTile: View {
    enum State { case normal, selected, correct, incorrect }

    let label: String
    let text: String
    let state: State
    var isEnabled = true
    let action: () -> Void

    private var bgColor: Color {
        switch state {
        case .normal, .correct: return Color.trivialSecondarySystemBackground
        case .selected: return Color.blue.opacity(0.12)
        case .incorrect: return Color.red.opacity(0.10)
        }
    }

    private var borderColor: Color {
        switch state {
        case .normal: return Color.trivialSeparator
        case .selected: return .blue
        case .correct: return .green
        case .incorrect: return .red
        }
    }

    private var labelBgColor: Color {
        switch state {
        case .normal, .correct: return Color.trivialTertiarySystemBackground
        case .selected: return .blue
        case .incorrect: return .red
        }
    }

    private var borderWidth: CGFloat {
        state == .correct ? 3.5 : 1.5
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(label)
                    .font(.headline.bold())
                    .foregroundStyle((state == .normal || state == .correct) ? Color.primary : Color.white)
                    .frame(width: 30, height: 30)
                    .background(labelBgColor)
                    .clipShape(Circle())

                Text(text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                Spacer()

                if state == .correct {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if state == .incorrect {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                } else if state == .selected {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || state != .normal)
    }
}

// MARK: - Result View

private struct TrivialPursuitResultView: View {
    let engine: TrivialPursuitGameEngine
    @Binding var runtimeState: WidgetTrivialPursuitRuntimeState
    let categoryID: String
    let questionIndex: Int
    let winnerPlayerIndex: Int?
    let activePlayerIndex: Int

    private var category: TrivialPursuitCategory? { engine.category(forID: categoryID) }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            if let winner = winnerPlayerIndex, engine.players.indices.contains(winner) {
                let player = engine.players[winner]
                if let cat = category {
                    VStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(Color(hexString: cat.color))
                                .frame(width: 90, height: 90)
                                .shadow(color: Color(hexString: cat.color).opacity(0.5), radius: 20)
                            Text(cat.emoji)
                                .font(.system(size: 44))
                        }

                        VStack(spacing: 6) {
                            Text(player.name)
                                .font(.title.bold())
                            Text("earns the \(cat.name) wedge!")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 5) {
                            ForEach(engine.categories) { c in
                                let earned = engine.players[winner].earnedCategoryIDs.contains(c.id)
                                Circle()
                                    .fill(earned ? Color(hexString: c.color) : Color(hexString: c.color).opacity(0.2))
                                    .frame(width: 24, height: 24)
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 56))
                        .foregroundStyle(.secondary)
                    Text("No wedge this round.")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Next Turn") {
                engine.advanceTurn(
                    winnerPlayerIndex: winnerPlayerIndex,
                    currentActivePlayerIndex: activePlayerIndex
                )
                runtimeState.activeCategoryID = nil
                runtimeState.activeQuestionIndex = nil
                runtimeState.roundID = nil
                runtimeState.activePlayerIndex = winnerPlayerIndex ?? ((activePlayerIndex + 1) % max(engine.players.count, 1))
                runtimeState.didRevealChoices = false
                runtimeState.choicesRevealedAt = nil
                runtimeState.revealedCorrectChoiceID = nil
                runtimeState.winnerParticipantID = nil
                runtimeState.winnerDisplayName = nil
                runtimeState.localAnswer = nil
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(category.map { Color(hexString: $0.color) } ?? .blue)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.trivialSystemBackground)
        .onAppear {
            engine.applyEarnedCategoryIDs(runtimeState.earnedCategoryIDsByParticipantID)
        }
        .onChange(of: runtimeState.earnedCategoryIDsByParticipantID) { _, earnedCategoryIDsByParticipantID in
            engine.applyEarnedCategoryIDs(earnedCategoryIDsByParticipantID)
        }
    }
}

// MARK: - Game Won View

private struct TrivialPursuitGameWonView: View {
    let engine: TrivialPursuitGameEngine
    @Binding var runtimeState: WidgetTrivialPursuitRuntimeState
    let playerIndex: Int

    var winner: TrivialPursuitGamePlayer? {
        engine.players.indices.contains(playerIndex) ? engine.players[playerIndex] : nil
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Text("🎉")
                .font(.system(size: 80))

            if let player = winner {
                VStack(spacing: 8) {
                    Text(player.name)
                        .font(.largeTitle.bold())
                    Text("wins the game!")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                ForEach(engine.categories) { category in
                    ZStack {
                        Circle()
                            .fill(Color(hexString: category.color))
                            .frame(width: 52, height: 52)
                            .shadow(color: Color(hexString: category.color).opacity(0.4), radius: 8)
                        Text(category.emoji)
                            .font(.title2)
                    }
                }
            }

            Text("All 6 category wedges collected!")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Play Again") {
                engine.resetGame()
                runtimeState = WidgetTrivialPursuitRuntimeState()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.trivialSystemBackground)
    }
}

// MARK: - Helpers

private extension Color {
    init(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
