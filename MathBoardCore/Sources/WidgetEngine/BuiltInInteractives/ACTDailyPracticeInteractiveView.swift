//
//  ACTDailyPracticeInteractiveView.swift
//  WidgetEngine
//
//  Daily ACT-style math practice backed by a bundled question bank.
//

import Foundation
import Observation
import SwiftUI

struct ACTDailyPracticeBank: Codable, Equatable, Sendable {
    var title: String
    var version: Int
    var subject: String
    var questions: [ACTDailyPracticeQuestion]
}

struct ACTDailyPracticeQuestion: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var day: Int
    var domain: String
    var skill: String
    var difficulty: String
    var prompt: String
    var choices: [ACTDailyPracticeChoice]
    var correctChoiceID: String
    var explanation: String

    var searchableText: String {
        ([id, domain, skill, difficulty, prompt, explanation] + choices.map(\.text))
            .joined(separator: " ")
            .lowercased()
    }
}

struct ACTDailyPracticeChoice: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var text: String
}

enum ACTDailyPracticeSortMode: String, CaseIterable, Identifiable {
    case question
    case domain
    case skill
    case difficulty

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .question:
            "Question"
        case .domain:
            "Domain"
        case .skill:
            "Skill"
        case .difficulty:
            "Difficulty"
        }
    }
}

enum ACTDailyPracticeQuestionBank {
    static let resourceName = "act-math-daily-practice"

    static var bundled: ACTDailyPracticeBank {
        guard let source = bundledSource,
              let data = source.data(using: .utf8),
              let bank = try? JSONDecoder().decode(ACTDailyPracticeBank.self, from: data) else {
            return ACTDailyPracticeBank(title: "ACT Math Daily Practice", version: 1, subject: "ACT Math", questions: [])
        }
        return bank
    }

    static var bundledSource: String? {
        let nestedURL = Bundle.module.url(
            forResource: resourceName,
            withExtension: "json",
            subdirectory: "JSONMathtivities"
        )
        let flatURL = Bundle.module.url(forResource: resourceName, withExtension: "json")
        guard let url = nestedURL ?? flatURL else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func validationErrors(for bank: ACTDailyPracticeBank) -> [String] {
        var errors: [String] = []
        var seenIDs: Set<String> = []

        if bank.questions.count != 180 {
            errors.append("Expected 180 ACT daily practice questions; found \(bank.questions.count).")
        }

        for question in bank.questions {
            let location = question.id
            if !seenIDs.insert(question.id).inserted {
                errors.append("Duplicate question id: \(question.id).")
            }
            if question.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("\(location) has an empty prompt.")
            }
            if question.domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("\(location) has an empty domain tag.")
            }
            if question.skill.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("\(location) has an empty skill tag.")
            }
            if question.choices.map(\.id) != ["A", "B", "C", "D"] {
                errors.append("\(location) must have exactly four choices labeled A, B, C, and D.")
            }
            let choiceIDs = Set(question.choices.map(\.id))
            if !choiceIDs.contains(question.correctChoiceID) {
                errors.append("\(location) has a correctChoiceID that is not one of its choices.")
            }
            if question.choices.contains(where: { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                errors.append("\(location) has an empty choice.")
            }
            if containsDraftLanguage(question.prompt) || containsDraftLanguage(question.explanation) {
                errors.append("\(location) still contains AI draft-correction language.")
            }
        }

        return errors
    }

    private static func containsDraftLanguage(_ text: String) -> Bool {
        let lowercasedText = text.lowercased()
        return ["wait,", "let's check", "let's re", "change choice", "rewrite prompt", "none of the choices"]
            .contains { lowercasedText.contains($0) }
    }
}

private struct ACTDailyPracticeUsedQuestionRecord: Codable, Equatable, Sendable {
    var questionID: String
    var usedAt: Date
}

private struct ACTDailyPracticeRuntimeState: Codable, Equatable, Sendable {
    var selectedQuestionID: String?
    var usedRecords: [ACTDailyPracticeUsedQuestionRecord] = []
}

@MainActor
@Observable
final class ACTDailyPracticeState {
    static let runtimeStateKey = BuiltInInteractiveKind.actDailyPractice.rawValue
    private static let recentWindowDays = 180

    var searchText = ""
    var selectedDomain: String?
    var selectedSkill: String?
    var selectedDifficulty: String?
    var sortMode: ACTDailyPracticeSortMode = .question
    var selectedQuestionID: String?
    var selectedChoiceID: String?
    var submittedChoiceID: String?
    var isBrowserOpen = false
    var usedHistoryRevision = 0
    var onRuntimeStateChange: ((String?) -> Void)?

    @ObservationIgnored private let bank: ACTDailyPracticeBank
    @ObservationIgnored private var usedRecords: [ACTDailyPracticeUsedQuestionRecord]

    init(bank: ACTDailyPracticeBank = ACTDailyPracticeQuestionBank.bundled, encodedRuntimeState: String? = nil) {
        self.bank = bank
        let runtimeState = Self.decodeRuntimeState(encodedRuntimeState)
        self.usedRecords = Self.pruned(runtimeState?.usedRecords ?? [])
        if let savedQuestionID = runtimeState?.selectedQuestionID,
           bank.questions.contains(where: { $0.id == savedQuestionID }) {
            selectedQuestionID = savedQuestionID
        } else if let question = bank.questions.sorted(by: { $0.day < $1.day }).first {
            selectedQuestionID = question.id
            markUsed(question.id, shouldPersist: false)
        }
    }

    var questionCount: Int { bank.questions.count }

    var selectedQuestion: ACTDailyPracticeQuestion? {
        guard let selectedQuestionID else { return bank.questions.first }
        return bank.questions.first { $0.id == selectedQuestionID } ?? bank.questions.first
    }

    var filteredQuestions: [ACTDailyPracticeQuestion] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = bank.questions.filter { question in
            if let selectedDomain, question.domain != selectedDomain { return false }
            if let selectedSkill, question.skill != selectedSkill { return false }
            if let selectedDifficulty, question.difficulty != selectedDifficulty { return false }
            if !query.isEmpty, !question.searchableText.contains(query) { return false }
            return true
        }
        return sortQuestions(filtered)
    }

    var availableDomains: [String] {
        Array(Set(bank.questions.map(\.domain))).sorted()
    }

    var availableSkills: [String] {
        let domainFilteredQuestions = selectedDomain.map { domain in
            bank.questions.filter { $0.domain == domain }
        } ?? bank.questions
        return Array(Set(domainFilteredQuestions.map(\.skill))).sorted()
    }

    var availableDifficulties: [String] {
        ["easy", "medium", "hard"].filter { difficulty in
            bank.questions.contains { $0.difficulty == difficulty }
        }
    }

    var recentlyUsedCount: Int {
        _ = usedHistoryRevision
        return recentlyUsedQuestionIDs().count
    }

    var isAnswerSubmitted: Bool {
        submittedChoiceID != nil
    }

    var isCorrect: Bool {
        guard let submittedChoiceID, let question = selectedQuestion else { return false }
        return submittedChoiceID == question.correctChoiceID
    }

    func selectChoice(_ choiceID: String) {
        selectedChoiceID = choiceID
        submittedChoiceID = choiceID
    }

    func useQuestion(_ question: ACTDailyPracticeQuestion) {
        selectedQuestionID = question.id
        selectedChoiceID = nil
        submittedChoiceID = nil
        isBrowserOpen = false
        markUsed(question.id)
    }

    func nextUnusedQuestion() {
        let candidates = filteredQuestions.isEmpty ? bank.questions : filteredQuestions
        if let question = nextUnusedQuestion(in: candidates) ?? candidates.first {
            useQuestion(question)
        }
    }

    func resetAnswer() {
        selectedChoiceID = nil
        submittedChoiceID = nil
    }

    func clearUsedHistory() {
        usedRecords = []
        usedHistoryRevision += 1
        persistRuntimeState()
    }

    func isRecentlyUsed(_ question: ACTDailyPracticeQuestion) -> Bool {
        usedWithinDays(question, days: Self.recentWindowDays) != nil
    }

    func usedWithinDays(_ question: ACTDailyPracticeQuestion, days: Int) -> Int? {
        _ = usedHistoryRevision
        guard let record = usedRecords.first(where: { $0.questionID == question.id }) else { return nil }
        let age = Calendar.current.dateComponents([.day], from: record.usedAt, to: Date()).day ?? 0
        guard age <= days else { return nil }
        return max(age, 0)
    }

    func scoreRecord(widgetID: WidgetObject.ID, title: String) -> WidgetActivityScoreRecord {
        let status: WidgetActivityScoreStatus
        if submittedChoiceID == nil {
            status = selectedChoiceID == nil ? .notStarted : .inProgress
        } else {
            status = .complete
        }

        return WidgetActivityScoreRecord(
            id: widgetID.uuidString,
            title: title.isEmpty ? BuiltInInteractiveKind.actDailyPractice.displayName : title,
            status: status,
            score: isCorrect ? 1 : 0,
            attempts: submittedChoiceID == nil ? 0 : 1,
            points: isCorrect ? 1 : 0,
            pointsPossible: 1,
            numberCorrectFirstTry: isCorrect ? 1 : 0,
            numberCorrectAfterRetry: 0,
            longestStreak: isCorrect ? 1 : 0
        )
    }

    private func nextUnusedQuestion(in questions: [ACTDailyPracticeQuestion]) -> ACTDailyPracticeQuestion? {
        let recentlyUsedIDs = recentlyUsedQuestionIDs()
        return questions.sorted { $0.day < $1.day }.first { !recentlyUsedIDs.contains($0.id) }
    }

    private func sortQuestions(_ questions: [ACTDailyPracticeQuestion]) -> [ACTDailyPracticeQuestion] {
        questions.sorted { lhs, rhs in
            switch sortMode {
            case .question:
                lhs.day < rhs.day
            case .domain:
                (lhs.domain, lhs.day) < (rhs.domain, rhs.day)
            case .skill:
                (lhs.skill, lhs.day) < (rhs.skill, rhs.day)
            case .difficulty:
                (difficultyRank(lhs.difficulty), lhs.day) < (difficultyRank(rhs.difficulty), rhs.day)
            }
        }
    }

    private func difficultyRank(_ difficulty: String) -> Int {
        switch difficulty.lowercased() {
        case "easy":
            0
        case "medium":
            1
        case "hard":
            2
        default:
            3
        }
    }

    private func recentlyUsedQuestionIDs(now: Date = Date()) -> Set<String> {
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.recentWindowDays, to: now) ?? now
        return Set(usedRecords.filter { $0.usedAt >= cutoff }.map(\.questionID))
    }

    private func markUsed(_ questionID: String, now: Date = Date(), shouldPersist: Bool = true) {
        usedRecords = Self.pruned(usedRecords, now: now).filter { $0.questionID != questionID }
        usedRecords.append(ACTDailyPracticeUsedQuestionRecord(questionID: questionID, usedAt: now))
        usedHistoryRevision += 1
        if shouldPersist {
            persistRuntimeState()
        }
    }

    func persistRuntimeState() {
        let state = ACTDailyPracticeRuntimeState(
            selectedQuestionID: selectedQuestionID,
            usedRecords: Self.pruned(usedRecords)
        )
        guard let data = try? JSONEncoder().encode(state) else {
            onRuntimeStateChange?(nil)
            return
        }
        onRuntimeStateChange?(String(data: data, encoding: .utf8))
    }

    private static func decodeRuntimeState(_ encoded: String?) -> ACTDailyPracticeRuntimeState? {
        guard let encoded,
              let data = encoded.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ACTDailyPracticeRuntimeState.self, from: data)
    }

    private static func pruned(_ records: [ACTDailyPracticeUsedQuestionRecord], now: Date = Date()) -> [ACTDailyPracticeUsedQuestionRecord] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -recentWindowDays, to: now) ?? now
        return records.filter { $0.usedAt >= cutoff }
    }
}

@MainActor
enum ACTDailyPracticeStateRegistry {
    private static var statesByWidgetID: [WidgetObject.ID: ACTDailyPracticeState] = [:]

    static func state(for widget: WidgetObject, onRuntimeStateChange: ((String?) -> Void)? = nil) -> ACTDailyPracticeState {
        let widgetID = widget.id
        if let state = statesByWidgetID[widgetID] {
            state.onRuntimeStateChange = onRuntimeStateChange
            return state
        }
        let state = ACTDailyPracticeState(encodedRuntimeState: widget.builtInRuntimeState[ACTDailyPracticeState.runtimeStateKey])
        state.onRuntimeStateChange = onRuntimeStateChange
        statesByWidgetID[widgetID] = state
        state.persistRuntimeState()
        return state
    }

    static func state(for widgetID: WidgetObject.ID) -> ACTDailyPracticeState {
        let widget = WidgetObject(
            id: widgetID,
            name: BuiltInInteractiveKind.actDailyPractice.displayName,
            codeString: BuiltInInteractiveKind.actDailyPractice.widgetCodeString,
            frame: .zero
        )
        return state(for: widget)
    }

    static func removeState(for widgetID: WidgetObject.ID) {
        statesByWidgetID.removeValue(forKey: widgetID)
    }

    static func scoreRecord(for widgetID: WidgetObject.ID, title: String) -> WidgetActivityScoreRecord {
        scoreState(for: widgetID).scoreRecord(widgetID: widgetID, title: title)
    }

    private static func scoreState(for widgetID: WidgetObject.ID) -> ACTDailyPracticeState {
        if let state = statesByWidgetID[widgetID] {
            return state
        }
        let state = ACTDailyPracticeState()
        statesByWidgetID[widgetID] = state
        return state
    }
}

struct ACTDailyPracticeInteractiveView: View {
    @Bindable var state: ACTDailyPracticeState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if state.isBrowserOpen {
                browser
            } else if let question = state.selectedQuestion {
                questionView(question)
            } else {
                unavailableView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ACTDailyPracticePalette.background)
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ACT Daily Practice")
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                if let question = state.selectedQuestion {
                    Text("\(question.id) - \(question.domain) - \(question.skill)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button {
                state.nextUnusedQuestion()
            } label: {
                Label("Next", systemImage: "calendar.badge.plus")
            }
            .buttonStyle(.bordered)
            Button {
                state.isBrowserOpen.toggle()
            } label: {
                Label(state.isBrowserOpen ? "Problem" : "Browse", systemImage: state.isBrowserOpen ? "doc.text" : "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
        }
        .font(.system(size: 13, weight: .semibold))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func questionView(_ question: ACTDailyPracticeQuestion) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    tag(question.difficulty.capitalized)
                    tag(question.domain)
                    tag(question.skill)
                    Spacer(minLength: 0)
                }

                Text(ACTDailyPracticeTextFormatter.displayText(for: question.prompt))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(question.choices) { choice in
                        answerButton(choice, question: question)
                    }
                }

                if state.isAnswerSubmitted {
                    feedback(for: question)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func answerButton(_ choice: ACTDailyPracticeChoice, question: ACTDailyPracticeQuestion) -> some View {
        let isSubmittedChoice = state.submittedChoiceID == choice.id
        let isCorrectChoice = state.isAnswerSubmitted && choice.id == question.correctChoiceID
        return Button {
            state.selectChoice(choice.id)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Text(choice.id)
                    .font(.headline.weight(.heavy))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(choiceBadgeColor(isSubmittedChoice: isSubmittedChoice, isCorrectChoice: isCorrectChoice)))
                    .foregroundStyle(.white)
                WidgetMathTextView(
                    source: ACTDailyPracticeTextFormatter.mathText(for: choice.text),
                    fontSize: 18,
                    weight: .semibold,
                    foregroundColor: .primary,
                    alignment: .leading,
                    lineLimit: 3,
                    minimumScaleFactor: 0.62
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(answerBackground(isSubmittedChoice: isSubmittedChoice, isCorrectChoice: isCorrectChoice), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(answerBorder(isSubmittedChoice: isSubmittedChoice, isCorrectChoice: isCorrectChoice), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func feedback(for question: ACTDailyPracticeQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(state.isCorrect ? "Correct" : "Review", systemImage: state.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(state.isCorrect ? .green : .orange)
                Spacer()
                Button("Try Again") {
                    state.resetAnswer()
                }
                .buttonStyle(.bordered)
            }
            Text(ACTDailyPracticeTextFormatter.displayText(for: question.explanation))
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(ACTDailyPracticePalette.secondaryBackground, in: RoundedRectangle(cornerRadius: 8))
    }

    private var browser: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                TextField("Search", text: $state.searchText)
                    .textFieldStyle(.roundedBorder)
                filterMenu(title: state.selectedDomain ?? "Domain", values: state.availableDomains, selection: $state.selectedDomain)
                filterMenu(title: state.selectedSkill ?? "Skill", values: state.availableSkills, selection: $state.selectedSkill)
                filterMenu(title: state.selectedDifficulty?.capitalized ?? "Level", values: state.availableDifficulties, selection: $state.selectedDifficulty)
                sortMenu
            }
            .font(.caption.weight(.semibold))

            HStack {
                Text("\(state.filteredQuestions.count) of \(state.questionCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(state.recentlyUsedCount) used recently")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset Used") { state.clearUsedHistory() }
                    .buttonStyle(.bordered)
                Button("Reset Filters") {
                    state.searchText = ""
                    state.selectedDomain = nil
                    state.selectedSkill = nil
                    state.selectedDifficulty = nil
                }
                .buttonStyle(.bordered)
            }

            List(state.filteredQuestions) { question in
                Button {
                    state.useQuestion(question)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(question.id)
                                .font(.subheadline.weight(.bold))
                            Text(question.difficulty.capitalized)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            recentUseBadges(for: question)
                            Spacer()
                        }
                        Text("\(question.domain) - \(question.skill)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(ACTDailyPracticeTextFormatter.displayText(for: question.prompt))
                            .font(.caption)
                            .lineLimit(2)
                            .foregroundStyle(.primary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
        .padding(12)
    }

    private var unavailableView: some View {
        ContentUnavailableView(
            "ACT Daily Practice unavailable",
            systemImage: "exclamationmark.triangle",
            description: Text("The bundled question bank could not be loaded.")
        )
    }

    private func filterMenu(title: String, values: [String], selection: Binding<String?>) -> some View {
        Menu {
            Button("All") { selection.wrappedValue = nil }
            Divider()
            ForEach(values, id: \.self) { value in
                Button(value.capitalized) { selection.wrappedValue = value }
            }
        } label: {
            Text(title.capitalized)
                .lineLimit(1)
                .frame(minWidth: 72)
        }
        .buttonStyle(.bordered)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(ACTDailyPracticeSortMode.allCases) { mode in
                Button(mode.displayName) { state.sortMode = mode }
            }
        } label: {
            Label(state.sortMode.displayName, systemImage: "arrow.up.arrow.down")
                .lineLimit(1)
                .frame(minWidth: 86)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private func recentUseBadges(for question: ACTDailyPracticeQuestion) -> some View {
        let windows = [30, 60, 90, 120, 180]
        HStack(spacing: 4) {
            ForEach(windows, id: \.self) { days in
                if let age = state.usedWithinDays(question, days: days) {
                    Text(age == 0 ? "\(days)d today" : "\(days)d")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.14), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.blue.opacity(0.12), in: Capsule())
            .foregroundStyle(.blue)
    }

    private func choiceBadgeColor(isSubmittedChoice: Bool, isCorrectChoice: Bool) -> Color {
        if isCorrectChoice { return .green }
        if isSubmittedChoice { return .orange }
        return .blue
    }

    private func answerBackground(isSubmittedChoice: Bool, isCorrectChoice: Bool) -> Color {
        if isCorrectChoice { return Color.green.opacity(0.12) }
        if isSubmittedChoice { return Color.orange.opacity(0.12) }
        return ACTDailyPracticePalette.secondaryBackground
    }

    private func answerBorder(isSubmittedChoice: Bool, isCorrectChoice: Bool) -> Color {
        if isCorrectChoice { return .green }
        if isSubmittedChoice { return .orange }
        return ACTDailyPracticePalette.separator
    }
}

private enum ACTDailyPracticePalette {
    static let background = Color.white
    static let secondaryBackground = Color(red: 0.96, green: 0.97, blue: 0.98)
    static let separator = Color(red: 0.82, green: 0.84, blue: 0.87)
}

enum ACTDailyPracticeTextFormatter {
    static func mathText(for text: String) -> String {
        text.replacingOccurrences(of: "$", with: "")
    }

    static func displayText(for text: String) -> String {
        text
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "\\left", with: "")
            .replacingOccurrences(of: "\\right", with: "")
            .replacingOccurrences(of: "\\cdot", with: "*")
            .replacingOccurrences(of: "\\times", with: "x")
            .replacingOccurrences(of: "\\div", with: "/")
            .replacingOccurrences(of: "\\pi", with: "pi")
            .replacingOccurrences(of: "\\theta", with: "theta")
            .replacingOccurrences(of: "\\circ", with: "deg")
            .replacingOccurrences(of: "\\geq", with: ">=")
            .replacingOccurrences(of: "\\leq", with: "<=")
            .replacingOccurrences(of: "\\neq", with: "!=")
            .replacingOccurrences(of: "\\sqrt", with: "sqrt")
            .replacingOccurrences(of: "\\log", with: "log")
            .replacingOccurrences(of: "\\sin", with: "sin")
            .replacingOccurrences(of: "\\cos", with: "cos")
            .replacingOccurrences(of: "\\tan", with: "tan")
            .replacingOccurrences(of: "\\sec", with: "sec")
            .replacingOccurrences(of: "\\cot", with: "cot")
            .replacingOccurrences(of: "\\frac", with: "frac")
            .replacingOccurrences(of: "\\begin{cases}", with: "")
            .replacingOccurrences(of: "\\end{cases}", with: "")
            .replacingOccurrences(of: "\\text", with: "")
            .replacingOccurrences(of: "\\implies", with: "=>")
    }
}
