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
    public var interactiveParts: WidgetInteractivePartsRuntimeState

    public init(
        multipleChoice: WidgetMultipleChoiceRuntimeState = WidgetMultipleChoiceRuntimeState(),
        fillInTheBlank: WidgetFillInTheBlankRuntimeState = WidgetFillInTheBlankRuntimeState(),
        interactiveParts: WidgetInteractivePartsRuntimeState = WidgetInteractivePartsRuntimeState()
    ) {
        self.multipleChoice = multipleChoice
        self.fillInTheBlank = fillInTheBlank
        self.interactiveParts = interactiveParts
    }

    private enum CodingKeys: String, CodingKey {
        case multipleChoice
        case fillInTheBlank
        case interactiveParts
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        multipleChoice = try container.decodeIfPresent(WidgetMultipleChoiceRuntimeState.self, forKey: .multipleChoice) ?? WidgetMultipleChoiceRuntimeState()
        fillInTheBlank = try container.decodeIfPresent(WidgetFillInTheBlankRuntimeState.self, forKey: .fillInTheBlank) ?? WidgetFillInTheBlankRuntimeState()
        interactiveParts = try container.decodeIfPresent(WidgetInteractivePartsRuntimeState.self, forKey: .interactiveParts) ?? WidgetInteractivePartsRuntimeState()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(multipleChoice, forKey: .multipleChoice)
        try container.encode(fillInTheBlank, forKey: .fillInTheBlank)
        try container.encode(interactiveParts, forKey: .interactiveParts)
    }
}

extension WidgetActivityRuntimeState {
    func scoreRecord(for document: ActivityWidgetDocument) -> WidgetActivityScoreRecord {
        let baseRecord: WidgetActivityScoreRecord
        switch document.activity {
        case .multipleChoice:
            baseRecord = multipleChoice.scoreRecord(for: document)
        case .fillInTheBlank:
            baseRecord = fillInTheBlank.scoreRecord(for: document)
        }
        return interactiveParts.combinedScoreRecord(base: baseRecord, document: document)
    }
}

public struct WidgetInteractivePartsRuntimeState: Codable, Equatable, Sendable {
    public var numberLineResponsesByPartID: [String: WidgetNumberLineRuntimeResponse]

    public init(numberLineResponsesByPartID: [String: WidgetNumberLineRuntimeResponse] = [:]) {
        self.numberLineResponsesByPartID = numberLineResponsesByPartID
    }

    var isStarted: Bool {
        numberLineResponsesByPartID.values.contains { !$0.isEmpty }
    }

    func response(for partID: String) -> WidgetNumberLineRuntimeResponse {
        numberLineResponsesByPartID[partID] ?? WidgetNumberLineRuntimeResponse()
    }

    mutating func setResponse(_ response: WidgetNumberLineRuntimeResponse, for partID: String) {
        if response.isEmpty {
            numberLineResponsesByPartID.removeValue(forKey: partID)
        } else {
            numberLineResponsesByPartID[partID] = response
        }
    }

    func combinedScoreRecord(
        base: WidgetActivityScoreRecord,
        document: ActivityWidgetDocument
    ) -> WidgetActivityScoreRecord {
        let scorableParts = document.questions.flatMap(\.interactiveParts).compactMap { part -> WidgetActivityNumberLinePart? in
            guard case .numberLine(let numberLine) = part, numberLine.answer != nil else { return nil }
            return numberLine
        }
        guard !scorableParts.isEmpty else { return base }

        let correctPartCount = scorableParts.filter { part in
            guard let answer = part.answer else { return false }
            return response(for: part.id).matches(answer, step: part.domain.step)
        }.count
        let attemptedPartCount = scorableParts.filter { !response(for: $0.id).isEmpty }.count
        let completePartCount = scorableParts.count

        let allOuterQuestionsComplete = base.status == .complete
        let allPartsComplete = attemptedPartCount >= completePartCount
        let status: WidgetActivityScoreStatus
        if allOuterQuestionsComplete && allPartsComplete {
            status = .complete
        } else if base.status == .inProgress || base.attempts > 0 || attemptedPartCount > 0 {
            status = .inProgress
        } else {
            status = .notStarted
        }

        // When interactive parts exist they ARE the score — the outer MC/FITB
        // choices are scaffolding ("Done" / "I need to revise"), not real questions.
        // Combining both would double-count pointsPossible and score.
        return WidgetActivityScoreRecord(
            id: base.id,
            title: base.title,
            status: status,
            score: correctPartCount,
            attempts: attemptedPartCount,
            points: Double(correctPartCount),
            pointsPossible: completePartCount,
            numberCorrectFirstTry: correctPartCount,
            numberCorrectAfterRetry: base.numberCorrectAfterRetry,
            longestStreak: correctPartCount
        )
    }
}

public struct WidgetNumberLineRuntimeResponse: Codable, Equatable, Sendable {
    public var selectedPoints: [Double]
    public var points: [WidgetActivityNumberLinePoint]
    public var rays: [WidgetActivityNumberLineRay]
    public var segments: [WidgetActivityNumberLineSegment]

    public init(
        selectedPoints: [Double] = [],
        points: [WidgetActivityNumberLinePoint] = [],
        rays: [WidgetActivityNumberLineRay] = [],
        segments: [WidgetActivityNumberLineSegment] = []
    ) {
        self.selectedPoints = selectedPoints
        self.points = points
        self.rays = rays
        self.segments = segments
    }

    init(answer: WidgetActivityNumberLineAnswer?) {
        self.init(
            selectedPoints: answer?.selectedPoints ?? [],
            points: answer?.points ?? [],
            rays: answer?.rays ?? [],
            segments: answer?.segments ?? []
        )
    }

    private enum CodingKeys: String, CodingKey {
        case selectedPoints
        case points
        case rays
        case segments
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedPoints = try container.decodeIfPresent([Double].self, forKey: .selectedPoints) ?? []
        points = try container.decodeIfPresent([WidgetActivityNumberLinePoint].self, forKey: .points) ?? []
        rays = try container.decodeIfPresent([WidgetActivityNumberLineRay].self, forKey: .rays) ?? []
        segments = try container.decodeIfPresent([WidgetActivityNumberLineSegment].self, forKey: .segments) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(selectedPoints, forKey: .selectedPoints)
        try container.encode(points, forKey: .points)
        try container.encode(rays, forKey: .rays)
        try container.encode(segments, forKey: .segments)
    }

    public var isEmpty: Bool {
        selectedPoints.isEmpty && points.isEmpty && rays.isEmpty && segments.isEmpty
    }

    func matches(_ answer: WidgetActivityNumberLineAnswer, step: Double) -> Bool {
        normalizedPoints(selectedPoints: selectedPoints, points: points, step: step) == normalizedPoints(selectedPoints: answer.selectedPoints, points: answer.points, step: step)
            && normalizedRays(rays, step: step) == normalizedRays(answer.rays, step: step)
            && normalizedSegments(segments, step: step) == normalizedSegments(answer.segments, step: step)
    }

    private func normalizedPoints(
        selectedPoints: [Double],
        points: [WidgetActivityNumberLinePoint],
        step: Double
    ) -> [NormalizedNumberLinePoint] {
        let legacyPoints = selectedPoints.map { WidgetActivityNumberLinePoint(value: $0, isClosed: true) }
        return Array(Set((legacyPoints + points).map { point in
            NormalizedNumberLinePoint(
                value: normalizedValue(point.value, step: step),
                isClosed: point.isClosed
            )
        })).sorted()
    }

    private func normalizedRays(_ rays: [WidgetActivityNumberLineRay], step: Double) -> [NormalizedNumberLineRay] {
        Array(Set(rays.map { ray in
            NormalizedNumberLineRay(
                endpoint: normalizedValue(ray.endpoint, step: step),
                direction: ray.direction,
                isClosed: ray.isClosed
            )
        })).sorted()
    }

    private func normalizedSegments(_ segments: [WidgetActivityNumberLineSegment], step: Double) -> [NormalizedNumberLineSegment] {
        Array(Set(segments.map { segment in
            let normalizedStart = normalizedValue(segment.start, step: step)
            let normalizedEnd = normalizedValue(segment.end, step: step)
            if normalizedStart <= normalizedEnd {
                return NormalizedNumberLineSegment(
                    start: normalizedStart,
                    end: normalizedEnd,
                    startClosed: segment.startClosed,
                    endClosed: segment.endClosed
                )
            } else {
                return NormalizedNumberLineSegment(
                    start: normalizedEnd,
                    end: normalizedStart,
                    startClosed: segment.endClosed,
                    endClosed: segment.startClosed
                )
            }
        })).sorted()
    }

    private func normalizedValue(_ value: Double, step: Double) -> Double {
        guard step > 0, step.isFinite else { return (value * 1_000_000).rounded() / 1_000_000 }
        return (value / step).rounded() * step
    }
}

private struct NormalizedNumberLinePoint: Hashable, Comparable {
    var value: Double
    var isClosed: Bool

    static func < (lhs: NormalizedNumberLinePoint, rhs: NormalizedNumberLinePoint) -> Bool {
        if lhs.value != rhs.value { return lhs.value < rhs.value }
        return !lhs.isClosed && rhs.isClosed
    }
}

private struct NormalizedNumberLineRay: Hashable, Comparable {
    var endpoint: Double
    var direction: WidgetActivityNumberLineRayDirection
    var isClosed: Bool

    static func < (lhs: NormalizedNumberLineRay, rhs: NormalizedNumberLineRay) -> Bool {
        if lhs.endpoint != rhs.endpoint { return lhs.endpoint < rhs.endpoint }
        if lhs.direction.rawValue != rhs.direction.rawValue { return lhs.direction.rawValue < rhs.direction.rawValue }
        return !lhs.isClosed && rhs.isClosed
    }
}

private struct NormalizedNumberLineSegment: Hashable, Comparable {
    var start: Double
    var end: Double
    var startClosed: Bool
    var endClosed: Bool

    static func < (lhs: NormalizedNumberLineSegment, rhs: NormalizedNumberLineSegment) -> Bool {
        if lhs.start != rhs.start { return lhs.start < rhs.start }
        if lhs.end != rhs.end { return lhs.end < rhs.end }
        if lhs.startClosed != rhs.startClosed { return !lhs.startClosed && rhs.startClosed }
        return !lhs.endClosed && rhs.endClosed
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
            pointsPossible: document.questions.count,
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
            pointsPossible: document.questions.count,
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
        if pointsPossible > 0 {
            return Int((points / Double(pointsPossible) * 100).rounded())
        }
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
