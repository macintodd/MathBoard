//
//  WidgetActivityRuntimeState.swift
//  WidgetEngine
//
//  Persistable runtime state for activity widgets. These models intentionally
//  stay UI-free so they can be stored with MathBoard documents.
//

import Foundation

public struct WidgetActivityRuntimeState: Codable, Equatable, Sendable {
    public var multipleChoice: WidgetMultipleChoiceRuntimeState
    public var fillInTheBlank: WidgetFillInTheBlankRuntimeState

    public init(
        multipleChoice: WidgetMultipleChoiceRuntimeState = WidgetMultipleChoiceRuntimeState(),
        fillInTheBlank: WidgetFillInTheBlankRuntimeState = WidgetFillInTheBlankRuntimeState()
    ) {
        self.multipleChoice = multipleChoice
        self.fillInTheBlank = fillInTheBlank
    }

    private enum CodingKeys: String, CodingKey {
        case multipleChoice
        case fillInTheBlank
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        multipleChoice = try container.decodeIfPresent(WidgetMultipleChoiceRuntimeState.self, forKey: .multipleChoice) ?? WidgetMultipleChoiceRuntimeState()
        fillInTheBlank = try container.decodeIfPresent(WidgetFillInTheBlankRuntimeState.self, forKey: .fillInTheBlank) ?? WidgetFillInTheBlankRuntimeState()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(multipleChoice, forKey: .multipleChoice)
        try container.encode(fillInTheBlank, forKey: .fillInTheBlank)
    }
}

extension WidgetActivityRuntimeState {
    func scoreRecord(for document: ActivityWidgetDocument) -> WidgetActivityScoreRecord {
        switch document.activity {
        case .multipleChoice:
            return multipleChoice.scoreRecord(for: document)
        case .fillInTheBlank:
            return fillInTheBlank.scoreRecord(for: document)
        }
    }
}

public struct WidgetMultipleChoiceRuntimeState: Codable, Equatable, Sendable {
    public var currentQuestionIndex: Int
    public var questionOrder: [Int]
    public var choiceOrders: [String: [String]]
    public var selectedChoiceID: String?
    public var submittedChoiceID: String?
    public var submittedChoiceIDsByQuestionID: [String: String]?
    public var score: Int
    public var attempts: Int
    public var streak: Int
    public var longestStreak: Int
    public var hintLevel: Int
    public var feedbackMessage: String?
    public var feedbackKind: WidgetActivityFeedbackStateKind
    public var answeredQuestionIDs: Set<String>
    public var correctlyAnsweredQuestionIDs: Set<String>
    public var questionAttempts: [String: Int]
    public var nextButtonPressToken: Int?
    public var flow: WidgetActivityAttemptFlowState?

    public init(
        currentQuestionIndex: Int = 0,
        questionOrder: [Int] = [],
        choiceOrders: [String: [String]] = [:],
        selectedChoiceID: String? = nil,
        submittedChoiceID: String? = nil,
        submittedChoiceIDsByQuestionID: [String: String]? = nil,
        score: Int = 0,
        attempts: Int = 0,
        streak: Int = 0,
        longestStreak: Int = 0,
        hintLevel: Int = 0,
        feedbackMessage: String? = nil,
        feedbackKind: WidgetActivityFeedbackStateKind = .neutral,
        answeredQuestionIDs: Set<String> = [],
        correctlyAnsweredQuestionIDs: Set<String> = [],
        questionAttempts: [String: Int] = [:],
        nextButtonPressToken: Int? = nil,
        flow: WidgetActivityAttemptFlowState? = nil
    ) {
        self.currentQuestionIndex = currentQuestionIndex
        self.questionOrder = questionOrder
        self.choiceOrders = choiceOrders
        self.selectedChoiceID = selectedChoiceID
        self.submittedChoiceID = submittedChoiceID
        self.submittedChoiceIDsByQuestionID = submittedChoiceIDsByQuestionID
        self.score = score
        self.attempts = attempts
        self.streak = streak
        self.longestStreak = longestStreak
        self.hintLevel = hintLevel
        self.feedbackMessage = feedbackMessage
        self.feedbackKind = feedbackKind
        self.answeredQuestionIDs = answeredQuestionIDs
        self.correctlyAnsweredQuestionIDs = correctlyAnsweredQuestionIDs
        self.questionAttempts = questionAttempts
        self.nextButtonPressToken = nextButtonPressToken
        self.flow = flow
    }

    var isStarted: Bool {
        attempts > 0 || !answeredQuestionIDs.isEmpty
    }

    func isComplete(totalQuestions: Int) -> Bool {
        totalQuestions > 0 && answeredQuestionIDs.count >= totalQuestions
    }

    func scoreRecord(for document: ActivityWidgetDocument) -> WidgetActivityScoreRecord {
        let status: WidgetActivityScoreStatus
        if isComplete(totalQuestions: document.questions.count) {
            status = .complete
        } else {
            status = isStarted ? .inProgress : .notStarted
        }

        return WidgetActivityScoreRecord(
            id: document.widgetId ?? document.title,
            title: document.title,
            status: status,
            score: score,
            attempts: attempts,
            points: points,
            pointsPossible: attempts,
            numberCorrectFirstTry: numberCorrectFirstTry,
            numberCorrectAfterRetry: numberCorrectAfterRetry,
            longestStreak: longestStreak
        )
    }

    mutating func reset(questionOrder: [Int], choiceOrders: [String: [String]]) {
        self = WidgetMultipleChoiceRuntimeState(
            questionOrder: questionOrder,
            choiceOrders: choiceOrders
        )
    }

    static func initial(for document: ActivityWidgetDocument) -> WidgetMultipleChoiceRuntimeState {
        WidgetMultipleChoiceRuntimeState(
            questionOrder: makeQuestionOrder(for: document),
            choiceOrders: makeChoiceOrders(for: document)
        )
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

    var bonus: Double {
        min(Double(streak) * 0.1, 1.0)
    }

    var numberCorrectFirstTry: Int {
        correctlyAnsweredQuestionIDs.filter { questionAttempts[$0] == 1 }.count
    }

    var numberCorrectAfterRetry: Int {
        correctlyAnsweredQuestionIDs.filter { (questionAttempts[$0] ?? 0) > 1 }.count
    }

    var points: Double {
        Double(score) + bonus
    }
}

public struct WidgetFillInTheBlankRuntimeState: Codable, Equatable, Sendable {
    public var currentQuestionIndex: Int
    public var questionOrder: [Int]
    public var responsesByBlankID: [String: String]
    public var score: Int
    public var attempts: Int
    public var streak: Int
    public var longestStreak: Int
    public var hintLevel: Int
    public var feedbackMessage: String?
    public var feedbackKind: WidgetActivityFeedbackStateKind
    public var answeredQuestionIDs: Set<String>
    public var correctlyAnsweredQuestionIDs: Set<String>
    public var questionAttempts: [String: Int]
    public var nextButtonPressToken: Int?
    public var flow: WidgetActivityAttemptFlowState?

    public init(
        currentQuestionIndex: Int = 0,
        questionOrder: [Int] = [],
        responsesByBlankID: [String: String] = [:],
        score: Int = 0,
        attempts: Int = 0,
        streak: Int = 0,
        longestStreak: Int = 0,
        hintLevel: Int = 0,
        feedbackMessage: String? = nil,
        feedbackKind: WidgetActivityFeedbackStateKind = .neutral,
        answeredQuestionIDs: Set<String> = [],
        correctlyAnsweredQuestionIDs: Set<String> = [],
        questionAttempts: [String: Int] = [:],
        nextButtonPressToken: Int? = nil,
        flow: WidgetActivityAttemptFlowState? = nil
    ) {
        self.currentQuestionIndex = currentQuestionIndex
        self.questionOrder = questionOrder
        self.responsesByBlankID = responsesByBlankID
        self.score = score
        self.attempts = attempts
        self.streak = streak
        self.longestStreak = longestStreak
        self.hintLevel = hintLevel
        self.feedbackMessage = feedbackMessage
        self.feedbackKind = feedbackKind
        self.answeredQuestionIDs = answeredQuestionIDs
        self.correctlyAnsweredQuestionIDs = correctlyAnsweredQuestionIDs
        self.questionAttempts = questionAttempts
        self.nextButtonPressToken = nextButtonPressToken
        self.flow = flow
    }

    var isStarted: Bool {
        attempts > 0 || !answeredQuestionIDs.isEmpty || !responsesByBlankID.isEmpty
    }

    func isComplete(totalQuestions: Int) -> Bool {
        totalQuestions > 0 && answeredQuestionIDs.count >= totalQuestions
    }

    func scoreRecord(for document: ActivityWidgetDocument) -> WidgetActivityScoreRecord {
        let status: WidgetActivityScoreStatus
        if isComplete(totalQuestions: document.questions.count) {
            status = .complete
        } else {
            status = isStarted ? .inProgress : .notStarted
        }

        return WidgetActivityScoreRecord(
            id: document.widgetId ?? document.title,
            title: document.title,
            status: status,
            score: score,
            attempts: attempts,
            points: points,
            pointsPossible: attempts,
            numberCorrectFirstTry: numberCorrectFirstTry,
            numberCorrectAfterRetry: numberCorrectAfterRetry,
            longestStreak: longestStreak
        )
    }

    mutating func reset(questionOrder: [Int]) {
        self = WidgetFillInTheBlankRuntimeState(questionOrder: questionOrder)
    }

    static func initial(for document: ActivityWidgetDocument) -> WidgetFillInTheBlankRuntimeState {
        WidgetFillInTheBlankRuntimeState(questionOrder: makeQuestionOrder(for: document))
    }

    private static func makeQuestionOrder(for document: ActivityWidgetDocument) -> [Int] {
        let order = Array(document.questions.indices)
        return document.rules?.shuffleQuestions == true ? order.shuffled() : order
    }

    var bonus: Double {
        min(Double(streak) * 0.1, 1.0)
    }

    var numberCorrectFirstTry: Int {
        correctlyAnsweredQuestionIDs.filter { questionAttempts[$0] == 1 }.count
    }

    var numberCorrectAfterRetry: Int {
        correctlyAnsweredQuestionIDs.filter { (questionAttempts[$0] ?? 0) > 1 }.count
    }

    var points: Double {
        Double(score) + bonus
    }
}

public struct WidgetActivityAttemptFlowState: Codable, Equatable, Sendable {
    public var isShowingFinalScore: Bool
    public var isRetryingMissed: Bool
    public var isReviewingAnswers: Bool?
    public var retryQuestionIDs: [String]
    public var retryQuestionIndex: Int
    public var skippedRetryQuestionIDs: Set<String>
    public var hasSubmittedScore: Bool
    public var submittedRecord: WidgetActivityScoreRecord?

    public init(
        isShowingFinalScore: Bool = false,
        isRetryingMissed: Bool = false,
        isReviewingAnswers: Bool? = nil,
        retryQuestionIDs: [String] = [],
        retryQuestionIndex: Int = 0,
        skippedRetryQuestionIDs: Set<String> = [],
        hasSubmittedScore: Bool = false,
        submittedRecord: WidgetActivityScoreRecord? = nil
    ) {
        self.isShowingFinalScore = isShowingFinalScore
        self.isRetryingMissed = isRetryingMissed
        self.isReviewingAnswers = isReviewingAnswers
        self.retryQuestionIDs = retryQuestionIDs
        self.retryQuestionIndex = retryQuestionIndex
        self.skippedRetryQuestionIDs = skippedRetryQuestionIDs
        self.hasSubmittedScore = hasSubmittedScore
        self.submittedRecord = submittedRecord
    }
}

public enum WidgetActivityFeedbackStateKind: String, Codable, Sendable {
    case neutral
    case correct
    case incorrect
    case warning
}

public struct WidgetActivityScoreRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var status: WidgetActivityScoreStatus
    public var score: Int
    public var attempts: Int
    public var points: Double
    public var pointsPossible: Int
    public var numberCorrectFirstTry: Int
    public var numberCorrectAfterRetry: Int
    public var longestStreak: Int

    public init(
        id: String,
        title: String,
        status: WidgetActivityScoreStatus,
        score: Int,
        attempts: Int,
        points: Double,
        pointsPossible: Int,
        numberCorrectFirstTry: Int = 0,
        numberCorrectAfterRetry: Int = 0,
        longestStreak: Int = 0
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.score = max(0, score)
        self.attempts = max(0, attempts)
        self.points = max(0, points)
        self.pointsPossible = max(0, pointsPossible)
        self.numberCorrectFirstTry = max(0, numberCorrectFirstTry)
        self.numberCorrectAfterRetry = max(0, numberCorrectAfterRetry)
        self.longestStreak = max(0, longestStreak)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        status = try container.decode(WidgetActivityScoreStatus.self, forKey: .status)
        score = max(0, try container.decode(Int.self, forKey: .score))
        attempts = max(0, try container.decode(Int.self, forKey: .attempts))
        points = max(0, try container.decode(Double.self, forKey: .points))
        pointsPossible = max(0, try container.decode(Int.self, forKey: .pointsPossible))
        numberCorrectFirstTry = max(0, try container.decodeIfPresent(Int.self, forKey: .numberCorrectFirstTry) ?? score)
        numberCorrectAfterRetry = max(0, try container.decodeIfPresent(Int.self, forKey: .numberCorrectAfterRetry) ?? 0)
        longestStreak = max(0, try container.decodeIfPresent(Int.self, forKey: .longestStreak) ?? score)
    }

    public var percent: Int? {
        guard attempts > 0 else { return nil }
        return Int((Double(score) / Double(attempts) * 100).rounded())
    }
}

public enum WidgetActivityScoreStatus: String, Codable, Sendable {
    case notStarted
    case inProgress
    case complete

    public var displayName: String {
        switch self {
        case .notStarted:
            return "Not started"
        case .inProgress:
            return "In progress"
        case .complete:
            return "Complete"
        }
    }
}

public struct WidgetActivityScoreSheet: Codable, Equatable, Sendable {
    public var records: [WidgetActivityScoreRecord]

    public init(records: [WidgetActivityScoreRecord]) {
        self.records = records
    }

    public init(widgets: [WidgetObject]) {
        self.records = widgets.compactMap(\.activityScoreRecord)
    }

    public var completedRecords: [WidgetActivityScoreRecord] {
        records.filter { $0.status == .complete && $0.attempts > 0 }
    }

    public var averagePercent: Int? {
        guard !completedRecords.isEmpty else { return nil }
        let total = completedRecords.compactMap(\.percent).reduce(0, +)
        return Int((Double(total) / Double(completedRecords.count)).rounded())
    }

    public var totalPoints: Double {
        completedRecords.reduce(0) { $0 + $1.points }
    }

    public var pointsPossible: Int {
        completedRecords.reduce(0) { $0 + $1.pointsPossible }
    }
}
