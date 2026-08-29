//
//  WidgetActivitySchema.swift
//  WidgetEngine
//
//  Higher-level MathBoard activity JSON contract. Activity documents describe
//  educational content and rules; native SwiftUI experiences own presentation.
//

import Foundation

struct ActivityWidgetDocument: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var widgetId: String?
    var activity: WidgetActivityKind
    var title: String
    var description: String?
    var learningObjective: String
    var difficulty: WidgetActivityDifficulty?
    var presentation: WidgetActivityPresentation?
    var rules: WidgetActivityRules?
    var feedback: WidgetActivityFeedback?
    var questions: [WidgetActivityQuestion]

    init(
        schemaVersion: Int = 1,
        widgetId: String? = nil,
        activity: WidgetActivityKind,
        title: String,
        description: String? = nil,
        learningObjective: String,
        difficulty: WidgetActivityDifficulty? = nil,
        presentation: WidgetActivityPresentation? = nil,
        rules: WidgetActivityRules? = nil,
        feedback: WidgetActivityFeedback? = nil,
        questions: [WidgetActivityQuestion]
    ) {
        self.schemaVersion = schemaVersion
        self.widgetId = widgetId
        self.activity = activity
        self.title = title
        self.description = description
        self.learningObjective = learningObjective
        self.difficulty = difficulty
        self.presentation = presentation
        self.rules = rules
        self.feedback = feedback
        self.questions = questions
    }
}

enum WidgetActivityKind: String, Codable, CaseIterable, Sendable {
    case multipleChoice
    case fillInTheBlank
}

enum WidgetActivityDifficulty: String, Codable, CaseIterable, Sendable {
    case easy
    case medium
    case hard
}

struct WidgetActivityPresentation: Codable, Equatable, Sendable {
    var preferredTheme: WidgetActivityTheme?
    var preferredExperience: WidgetActivityExperience?

    init(
        preferredTheme: WidgetActivityTheme? = nil,
        preferredExperience: WidgetActivityExperience? = nil
    ) {
        self.preferredTheme = preferredTheme
        self.preferredExperience = preferredExperience
    }
}

enum WidgetActivityTheme: String, Codable, CaseIterable, Sendable {
    case cleanClassroom
    case neonMath
    case paperArcade
    case chalkboard
    case sportsCourt
}

enum WidgetActivityExperience: String, Codable, CaseIterable, Sendable {
    case arcadeChoiceChallenge
    case paperQuiz
    case sportsArena
    case mysteryReveal
    case bossBattle
}

struct WidgetActivityRules: Codable, Equatable, Sendable {
    var scoreMode: WidgetActivityScoreMode?
    var advanceMode: WidgetActivityAdvanceMode?
    var allowRetry: Bool?
    /// Number of retries allowed per question after the first incorrect attempt.
    /// `maxRetries: 1` means one retry (2 total checks). Takes precedence over `maxAttemptsPerQuestion`.
    var maxRetries: Int?
    var shuffleQuestions: Bool?
    var shuffleChoices: Bool?
    var maxAttemptsPerQuestion: Int?
    var calculatorAllowed: Bool?

    init(
        scoreMode: WidgetActivityScoreMode? = nil,
        advanceMode: WidgetActivityAdvanceMode? = nil,
        allowRetry: Bool? = nil,
        maxRetries: Int? = nil,
        shuffleQuestions: Bool? = nil,
        shuffleChoices: Bool? = nil,
        maxAttemptsPerQuestion: Int? = nil,
        calculatorAllowed: Bool? = nil
    ) {
        self.scoreMode = scoreMode
        self.advanceMode = advanceMode
        self.allowRetry = allowRetry
        self.maxRetries = maxRetries
        self.shuffleQuestions = shuffleQuestions
        self.shuffleChoices = shuffleChoices
        self.maxAttemptsPerQuestion = maxAttemptsPerQuestion
        self.calculatorAllowed = calculatorAllowed
    }
}

enum WidgetActivityScoreMode: String, Codable, CaseIterable, Sendable {
    case correctOutOfAttempted
    case correctOutOfTotal
    case streak
}

enum WidgetActivityAdvanceMode: String, Codable, CaseIterable, Sendable {
    case manual
    case automaticOnCorrect
    case automaticAfterAnswer
}

struct WidgetActivityFeedback: Codable, Equatable, Sendable {
    var defaultCorrect: String?
    var defaultIncorrect: String?
    var defaultEncouragement: String?

    init(
        defaultCorrect: String? = nil,
        defaultIncorrect: String? = nil,
        defaultEncouragement: String? = nil
    ) {
        self.defaultCorrect = defaultCorrect
        self.defaultIncorrect = defaultIncorrect
        self.defaultEncouragement = defaultEncouragement
    }
}

struct WidgetActivityQuestion: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var prompt: String
    var expression: String?
    var choices: [WidgetActivityChoice]
    var blanks: [WidgetActivityBlank]
    var responseLayout: WidgetActivityResponseLayout?
    var interactiveParts: [WidgetActivityInteractivePart]
    var hints: [String]
    var correctFeedback: String?
    var incorrectFeedback: String?
    var explanation: String?
    var difficulty: WidgetActivityDifficulty?
    var skillTag: String?

    init(
        id: String,
        prompt: String,
        expression: String? = nil,
        choices: [WidgetActivityChoice],
        blanks: [WidgetActivityBlank] = [],
        responseLayout: WidgetActivityResponseLayout? = nil,
        interactiveParts: [WidgetActivityInteractivePart] = [],
        hints: [String] = [],
        correctFeedback: String? = nil,
        incorrectFeedback: String? = nil,
        explanation: String? = nil,
        difficulty: WidgetActivityDifficulty? = nil,
        skillTag: String? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.expression = expression
        self.choices = choices
        self.blanks = blanks
        self.responseLayout = responseLayout
        self.interactiveParts = interactiveParts
        self.hints = hints
        self.correctFeedback = correctFeedback
        self.incorrectFeedback = incorrectFeedback
        self.explanation = explanation
        self.difficulty = difficulty
        self.skillTag = skillTag
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case prompt
        case expression
        case choices
        case blanks
        case responseLayout
        case interactiveParts
        case hints
        case correctFeedback
        case incorrectFeedback
        case explanation
        case difficulty
        case skillTag
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        expression = try container.decodeIfPresent(String.self, forKey: .expression)
        choices = try container.decodeIfPresent([WidgetActivityChoice].self, forKey: .choices) ?? []
        blanks = try container.decodeIfPresent([WidgetActivityBlank].self, forKey: .blanks) ?? []
        responseLayout = try container.decodeIfPresent(WidgetActivityResponseLayout.self, forKey: .responseLayout)
        interactiveParts = try container.decodeIfPresent([WidgetActivityInteractivePart].self, forKey: .interactiveParts) ?? []
        hints = try container.decodeIfPresent([String].self, forKey: .hints) ?? []
        correctFeedback = try container.decodeIfPresent(String.self, forKey: .correctFeedback)
        incorrectFeedback = try container.decodeIfPresent(String.self, forKey: .incorrectFeedback)
        explanation = try container.decodeIfPresent(String.self, forKey: .explanation)
        difficulty = try container.decodeIfPresent(WidgetActivityDifficulty.self, forKey: .difficulty)
        skillTag = try container.decodeIfPresent(String.self, forKey: .skillTag)
    }
}

enum WidgetActivityInteractivePart: Codable, Equatable, Identifiable, Sendable {
    case numberLine(WidgetActivityNumberLinePart)
    case coordinatePlane(WidgetActivityCoordinatePlanePart)

    var id: String {
        switch self {
        case .numberLine(let part):
            return part.id
        case .coordinatePlane(let part):
            return part.id
        }
    }

    private enum PartType: String, Codable {
        case numberLine
        case coordinatePlane
    }

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(PartType.self, forKey: .type)
        switch type {
        case .numberLine:
            self = .numberLine(try WidgetActivityNumberLinePart(from: decoder))
        case .coordinatePlane:
            self = .coordinatePlane(try WidgetActivityCoordinatePlanePart(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .numberLine(let part):
            try part.encode(to: encoder)
        case .coordinatePlane(let part):
            try part.encode(to: encoder)
        }
    }
}

struct WidgetActivityNumberLinePart: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var domain: WidgetActivityNumberLineDomain
    var features: WidgetActivityNumberLineFeatures
    var initialResponse: WidgetActivityNumberLineAnswer?
    var answer: WidgetActivityNumberLineAnswer?

    init(
        id: String,
        domain: WidgetActivityNumberLineDomain,
        features: WidgetActivityNumberLineFeatures = WidgetActivityNumberLineFeatures(),
        initialResponse: WidgetActivityNumberLineAnswer? = nil,
        answer: WidgetActivityNumberLineAnswer? = nil
    ) {
        self.id = id
        self.domain = domain
        self.features = features
        self.initialResponse = initialResponse
        self.answer = answer
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case domain
        case features
        case initialResponse
        case answer
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        domain = try container.decode(WidgetActivityNumberLineDomain.self, forKey: .domain)
        features = try container.decodeIfPresent(WidgetActivityNumberLineFeatures.self, forKey: .features)
            ?? WidgetActivityNumberLineFeatures()
        initialResponse = try container.decodeIfPresent(WidgetActivityNumberLineAnswer.self, forKey: .initialResponse)
        answer = try container.decodeIfPresent(WidgetActivityNumberLineAnswer.self, forKey: .answer)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("numberLine", forKey: .type)
        try container.encode(id, forKey: .id)
        try container.encode(domain, forKey: .domain)
        try container.encode(features, forKey: .features)
        try container.encodeIfPresent(initialResponse, forKey: .initialResponse)
        try container.encodeIfPresent(answer, forKey: .answer)
    }
}

struct WidgetActivityNumberLineDomain: Codable, Equatable, Sendable {
    var min: Double
    var max: Double
    var step: Double

    init(min: Double, max: Double, step: Double = 1) {
        self.min = min
        self.max = max
        self.step = step
    }
}

struct WidgetActivityNumberLineFeatures: Codable, Equatable, Sendable {
    var pointsTappable: Bool
    var pointsDraggable: Bool
    var raysEnabled: Bool
    var segmentsEnabled: Bool
    var openClosedEndpoints: Bool
    var pointHasRay: Bool
    var maxPoints: Int?
    var labelsVisible: Bool
    var snapToTicks: Bool

    init(
        pointsTappable: Bool = false,
        pointsDraggable: Bool = false,
        raysEnabled: Bool = false,
        segmentsEnabled: Bool = false,
        openClosedEndpoints: Bool = false,
        pointHasRay: Bool = false,
        maxPoints: Int? = nil,
        labelsVisible: Bool = true,
        snapToTicks: Bool = true
    ) {
        self.pointsTappable = pointsTappable
        self.pointsDraggable = pointsDraggable
        self.raysEnabled = raysEnabled
        self.segmentsEnabled = segmentsEnabled
        self.openClosedEndpoints = openClosedEndpoints
        self.pointHasRay = pointHasRay
        self.maxPoints = maxPoints
        self.labelsVisible = labelsVisible
        self.snapToTicks = snapToTicks
    }

    private enum CodingKeys: String, CodingKey {
        case pointsTappable
        case pointsDraggable
        case raysEnabled
        case segmentsEnabled
        case openClosedEndpoints
        case pointHasRay
        case maxPoints
        case labelsVisible
        case snapToTicks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = WidgetActivityNumberLineFeatures()
        pointsTappable = try container.decodeIfPresent(Bool.self, forKey: .pointsTappable) ?? defaults.pointsTappable
        pointsDraggable = try container.decodeIfPresent(Bool.self, forKey: .pointsDraggable) ?? defaults.pointsDraggable
        raysEnabled = try container.decodeIfPresent(Bool.self, forKey: .raysEnabled) ?? defaults.raysEnabled
        segmentsEnabled = try container.decodeIfPresent(Bool.self, forKey: .segmentsEnabled) ?? defaults.segmentsEnabled
        openClosedEndpoints = try container.decodeIfPresent(Bool.self, forKey: .openClosedEndpoints) ?? defaults.openClosedEndpoints
        pointHasRay = try container.decodeIfPresent(Bool.self, forKey: .pointHasRay) ?? defaults.pointHasRay
        maxPoints = try container.decodeIfPresent(Int.self, forKey: .maxPoints)
        labelsVisible = try container.decodeIfPresent(Bool.self, forKey: .labelsVisible) ?? defaults.labelsVisible
        snapToTicks = try container.decodeIfPresent(Bool.self, forKey: .snapToTicks) ?? defaults.snapToTicks
    }
}

struct WidgetActivityNumberLineAnswer: Codable, Equatable, Sendable {
    var selectedPoints: [Double]
    var points: [WidgetActivityNumberLinePoint]
    var rays: [WidgetActivityNumberLineRay]
    var segments: [WidgetActivityNumberLineSegment]

    init(
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

    var isEmpty: Bool {
        selectedPoints.isEmpty && points.isEmpty && rays.isEmpty && segments.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case selectedPoints
        case points
        case rays
        case segments
    }

    init(from decoder: Decoder) throws {
        if let source = try? decoder.singleValueContainer().decode(String.self) {
            self = try WidgetActivityNumberLineGraphUtility.compile(source)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedPoints = try container.decodeIfPresent([Double].self, forKey: .selectedPoints) ?? []
        points = try container.decodeIfPresent([WidgetActivityNumberLinePoint].self, forKey: .points) ?? []
        rays = try container.decodeIfPresent([WidgetActivityNumberLineRay].self, forKey: .rays) ?? []
        segments = try container.decodeIfPresent([WidgetActivityNumberLineSegment].self, forKey: .segments) ?? []
    }
}

private enum WidgetActivityNumberLineGraphUtility {
    private struct Relation {
        var left: String
        var operation: String
        var right: String
    }

    static func compile(_ source: String) throws -> WidgetActivityNumberLineAnswer {
        let expression = try expressionBody(from: source)
        let normalized = expression
            .replacingOccurrences(of: "≤", with: "<=")
            .replacingOccurrences(of: "≥", with: ">=")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()

        if let compound = try compileCompound(normalized) {
            return compound
        }
        if let simple = try compileSimple(normalized) {
            return simple
        }

        throw DecodingError.dataCorrupted(DecodingError.Context(
            codingPath: [],
            debugDescription: "linearGraphUtility supports x comparisons such as x>1, x<=5, -2<x<=5, or x=3."
        ))
    }

    private static func expressionBody(from source: String) throws -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "linearGraphUtility{"
        guard trimmed.lowercased().hasPrefix(prefix.lowercased()), trimmed.hasSuffix("}") else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "Number-line graph utility strings must use linearGraphUtility{...}."
            ))
        }
        let start = trimmed.index(trimmed.startIndex, offsetBy: prefix.count)
        let end = trimmed.index(before: trimmed.endIndex)
        return String(trimmed[start..<end])
    }

    private static func compileCompound(_ expression: String) throws -> WidgetActivityNumberLineAnswer? {
        let relations = parseRelations(expression)
        guard relations.count == 2 else { return nil }
        guard relations[0].right == "x", relations[1].left == "x" else { return nil }
        guard relations[0].operation == "<" || relations[0].operation == "<=" else { return nil }
        guard relations[1].operation == "<" || relations[1].operation == "<=" else { return nil }
        let start = try parseNumber(relations[0].left)
        let end = try parseNumber(relations[1].right)
        return WidgetActivityNumberLineAnswer(segments: [
            WidgetActivityNumberLineSegment(
                start: start,
                end: end,
                startClosed: relations[0].operation == "<=",
                endClosed: relations[1].operation == "<="
            )
        ])
    }

    private static func compileSimple(_ expression: String) throws -> WidgetActivityNumberLineAnswer? {
        let relations = parseRelations(expression)
        guard relations.count == 1 else { return nil }
        let relation = relations[0]

        if relation.left == "x" {
            let value = try parseNumber(relation.right)
            switch relation.operation {
            case "<":
                return WidgetActivityNumberLineAnswer(rays: [WidgetActivityNumberLineRay(endpoint: value, direction: .left, isClosed: false)])
            case "<=":
                return WidgetActivityNumberLineAnswer(rays: [WidgetActivityNumberLineRay(endpoint: value, direction: .left, isClosed: true)])
            case ">":
                return WidgetActivityNumberLineAnswer(rays: [WidgetActivityNumberLineRay(endpoint: value, direction: .right, isClosed: false)])
            case ">=":
                return WidgetActivityNumberLineAnswer(rays: [WidgetActivityNumberLineRay(endpoint: value, direction: .right, isClosed: true)])
            case "=":
                return WidgetActivityNumberLineAnswer(points: [WidgetActivityNumberLinePoint(value: value, isClosed: true)])
            default:
                return nil
            }
        }

        if relation.right == "x" {
            let value = try parseNumber(relation.left)
            switch relation.operation {
            case "<":
                return WidgetActivityNumberLineAnswer(rays: [WidgetActivityNumberLineRay(endpoint: value, direction: .right, isClosed: false)])
            case "<=":
                return WidgetActivityNumberLineAnswer(rays: [WidgetActivityNumberLineRay(endpoint: value, direction: .right, isClosed: true)])
            case ">":
                return WidgetActivityNumberLineAnswer(rays: [WidgetActivityNumberLineRay(endpoint: value, direction: .left, isClosed: false)])
            case ">=":
                return WidgetActivityNumberLineAnswer(rays: [WidgetActivityNumberLineRay(endpoint: value, direction: .left, isClosed: true)])
            case "=":
                return WidgetActivityNumberLineAnswer(points: [WidgetActivityNumberLinePoint(value: value, isClosed: true)])
            default:
                return nil
            }
        }

        return nil
    }

    private static func parseRelations(_ expression: String) -> [Relation] {
        var tokens: [(range: Range<String.Index>, operation: String)] = []
        var index = expression.startIndex
        while index < expression.endIndex {
            let nextIndex = expression.index(after: index)
            if nextIndex < expression.endIndex {
                let twoCharacterOperation = String(expression[index...nextIndex])
                if twoCharacterOperation == "<=" || twoCharacterOperation == ">=" {
                    tokens.append((index..<expression.index(after: nextIndex), twoCharacterOperation))
                    index = expression.index(after: nextIndex)
                    continue
                }
            }
            let character = expression[index]
            if character == "<" || character == ">" || character == "=" {
                tokens.append((index..<nextIndex, String(character)))
            }
            index = nextIndex
        }

        guard !tokens.isEmpty else { return [] }
        var relations: [Relation] = []

        for tokenIndex in tokens.indices {
            let leftStartIndex = tokenIndex == 0 ? expression.startIndex : tokens[tokenIndex - 1].range.upperBound
            let rightEndIndex = tokenIndex == tokens.indices.last ? expression.endIndex : tokens[tokenIndex + 1].range.lowerBound
            let left = String(expression[leftStartIndex..<tokens[tokenIndex].range.lowerBound])
            let right = String(expression[tokens[tokenIndex].range.upperBound..<rightEndIndex])
            guard !left.isEmpty, !right.isEmpty else { return [] }
            relations.append(Relation(left: left, operation: tokens[tokenIndex].operation, right: right))
        }
        return relations
    }

    private static func parseNumber(_ source: String) throws -> Double {
        guard let value = Double(source), value.isFinite else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "linearGraphUtility value '\(source)' must be a finite number."
            ))
        }
        return value
    }
}

public struct WidgetActivityNumberLinePoint: Codable, Equatable, Sendable {
    public var value: Double
    public var isClosed: Bool

    public init(value: Double, isClosed: Bool = true) {
        self.value = value
        self.isClosed = isClosed
    }

    private enum CodingKeys: String, CodingKey {
        case value
        case isClosed
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decode(Double.self, forKey: .value)
        isClosed = try container.decodeIfPresent(Bool.self, forKey: .isClosed) ?? true
    }
}

public struct WidgetActivityNumberLineRay: Codable, Equatable, Sendable {
    public var endpoint: Double
    public var direction: WidgetActivityNumberLineRayDirection
    public var isClosed: Bool
    public var visualEndValue: Double?

    public init(
        endpoint: Double,
        direction: WidgetActivityNumberLineRayDirection,
        isClosed: Bool = true,
        visualEndValue: Double? = nil
    ) {
        self.endpoint = endpoint
        self.direction = direction
        self.isClosed = isClosed
        self.visualEndValue = visualEndValue
    }

    private enum CodingKeys: String, CodingKey {
        case endpoint
        case direction
        case isClosed
        case visualEndValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        endpoint = try container.decode(Double.self, forKey: .endpoint)
        direction = try container.decode(WidgetActivityNumberLineRayDirection.self, forKey: .direction)
        isClosed = try container.decodeIfPresent(Bool.self, forKey: .isClosed) ?? true
        visualEndValue = try container.decodeIfPresent(Double.self, forKey: .visualEndValue)
    }
}

public enum WidgetActivityNumberLineRayDirection: String, Codable, Sendable {
    case left
    case right
}

public struct WidgetActivityNumberLineSegment: Codable, Equatable, Sendable {
    public var start: Double
    public var end: Double
    public var startClosed: Bool
    public var endClosed: Bool

    public init(
        start: Double,
        end: Double,
        startClosed: Bool = true,
        endClosed: Bool = true
    ) {
        self.start = start
        self.end = end
        self.startClosed = startClosed
        self.endClosed = endClosed
    }

    private enum CodingKeys: String, CodingKey {
        case start
        case end
        case startClosed
        case endClosed
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try container.decode(Double.self, forKey: .start)
        end = try container.decode(Double.self, forKey: .end)
        startClosed = try container.decodeIfPresent(Bool.self, forKey: .startClosed) ?? true
        endClosed = try container.decodeIfPresent(Bool.self, forKey: .endClosed) ?? true
    }
}

struct WidgetActivityCoordinatePlanePart: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var domain: WidgetActivityCoordinatePlaneDomain
    var features: WidgetActivityCoordinatePlaneFeatures

    init(
        id: String,
        domain: WidgetActivityCoordinatePlaneDomain,
        features: WidgetActivityCoordinatePlaneFeatures = WidgetActivityCoordinatePlaneFeatures()
    ) {
        self.id = id
        self.domain = domain
        self.features = features
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case domain
        case features
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        domain = try container.decode(WidgetActivityCoordinatePlaneDomain.self, forKey: .domain)
        features = try container.decodeIfPresent(WidgetActivityCoordinatePlaneFeatures.self, forKey: .features)
            ?? WidgetActivityCoordinatePlaneFeatures()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("coordinatePlane", forKey: .type)
        try container.encode(id, forKey: .id)
        try container.encode(domain, forKey: .domain)
        try container.encode(features, forKey: .features)
    }
}

struct WidgetActivityCoordinatePlaneDomain: Codable, Equatable, Sendable {
    var xMin: Double
    var xMax: Double
    var yMin: Double
    var yMax: Double
    var xStep: Double
    var yStep: Double

    init(
        xMin: Double,
        xMax: Double,
        yMin: Double,
        yMax: Double,
        xStep: Double = 1,
        yStep: Double = 1
    ) {
        self.xMin = xMin
        self.xMax = xMax
        self.yMin = yMin
        self.yMax = yMax
        self.xStep = xStep
        self.yStep = yStep
    }
}

struct WidgetActivityCoordinatePlaneFeatures: Codable, Equatable, Sendable {
    var pointsTappable: Bool
    var pointsDraggable: Bool
    var linesEnabled: Bool
    var segmentsEnabled: Bool
    var raysEnabled: Bool
    var parabolasEnabled: Bool
    var labelsVisible: Bool
    var snapToGrid: Bool

    init(
        pointsTappable: Bool = false,
        pointsDraggable: Bool = false,
        linesEnabled: Bool = false,
        segmentsEnabled: Bool = false,
        raysEnabled: Bool = false,
        parabolasEnabled: Bool = false,
        labelsVisible: Bool = true,
        snapToGrid: Bool = true
    ) {
        self.pointsTappable = pointsTappable
        self.pointsDraggable = pointsDraggable
        self.linesEnabled = linesEnabled
        self.segmentsEnabled = segmentsEnabled
        self.raysEnabled = raysEnabled
        self.parabolasEnabled = parabolasEnabled
        self.labelsVisible = labelsVisible
        self.snapToGrid = snapToGrid
    }

    private enum CodingKeys: String, CodingKey {
        case pointsTappable
        case pointsDraggable
        case linesEnabled
        case segmentsEnabled
        case raysEnabled
        case parabolasEnabled
        case labelsVisible
        case snapToGrid
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = WidgetActivityCoordinatePlaneFeatures()
        pointsTappable = try container.decodeIfPresent(Bool.self, forKey: .pointsTappable) ?? defaults.pointsTappable
        pointsDraggable = try container.decodeIfPresent(Bool.self, forKey: .pointsDraggable) ?? defaults.pointsDraggable
        linesEnabled = try container.decodeIfPresent(Bool.self, forKey: .linesEnabled) ?? defaults.linesEnabled
        segmentsEnabled = try container.decodeIfPresent(Bool.self, forKey: .segmentsEnabled) ?? defaults.segmentsEnabled
        raysEnabled = try container.decodeIfPresent(Bool.self, forKey: .raysEnabled) ?? defaults.raysEnabled
        parabolasEnabled = try container.decodeIfPresent(Bool.self, forKey: .parabolasEnabled) ?? defaults.parabolasEnabled
        labelsVisible = try container.decodeIfPresent(Bool.self, forKey: .labelsVisible) ?? defaults.labelsVisible
        snapToGrid = try container.decodeIfPresent(Bool.self, forKey: .snapToGrid) ?? defaults.snapToGrid
    }
}

enum WidgetActivityResponseLayoutType: String, Codable, Sendable {
    case fraction
}

struct WidgetActivityResponseLayout: Codable, Equatable, Sendable {
    var type: WidgetActivityResponseLayoutType
    var label: String?
    var numeratorBlankId: String?
    var denominatorBlankId: String?

    init(
        type: WidgetActivityResponseLayoutType,
        label: String? = nil,
        numeratorBlankId: String? = nil,
        denominatorBlankId: String? = nil
    ) {
        self.type = type
        self.label = label
        self.numeratorBlankId = numeratorBlankId
        self.denominatorBlankId = denominatorBlankId
    }
}

enum WidgetActivityBlankKind: String, Codable, CaseIterable, Sendable {
    case text
    case numeric
}

struct WidgetActivityBlank: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var label: String?
    var kind: WidgetActivityBlankKind
    var acceptedAnswers: [String]
    var tolerance: Double?
    var caseSensitive: Bool?
    var feedback: String?

    init(
        id: String,
        label: String? = nil,
        kind: WidgetActivityBlankKind = .text,
        acceptedAnswers: [String],
        tolerance: Double? = nil,
        caseSensitive: Bool? = nil,
        feedback: String? = nil
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.acceptedAnswers = acceptedAnswers
        self.tolerance = tolerance
        self.caseSensitive = caseSensitive
        self.feedback = feedback
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case kind
        case acceptedAnswers
        case tolerance
        case caseSensitive
        case feedback
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        kind = try container.decodeIfPresent(WidgetActivityBlankKind.self, forKey: .kind) ?? .text
        acceptedAnswers = try container.decodeIfPresent([String].self, forKey: .acceptedAnswers) ?? []
        tolerance = try container.decodeIfPresent(Double.self, forKey: .tolerance)
        caseSensitive = try container.decodeIfPresent(Bool.self, forKey: .caseSensitive)
        feedback = try container.decodeIfPresent(String.self, forKey: .feedback)
    }
}

struct WidgetActivityChoice: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var label: String
    var isCorrect: Bool
    var feedback: String?

    init(
        id: String,
        label: String,
        isCorrect: Bool,
        feedback: String? = nil
    ) {
        self.id = id
        self.label = label
        self.isCorrect = isCorrect
        self.feedback = feedback
    }
}

struct WidgetActivityValidationResult: Equatable, Sendable {
    var document: ActivityWidgetDocument?
    var errors: [String]

    var isValid: Bool {
        document != nil && errors.isEmpty
    }
}

enum WidgetActivityJSONCodec {
    static func decode(_ source: String) -> WidgetActivityValidationResult {
        let repairedSource = WidgetJSONRepair.escapingUnescapedLaTeXCommands(in: source)
        guard let data = repairedSource.data(using: .utf8) else {
            return WidgetActivityValidationResult(
                document: nil,
                errors: ["Activity JSON must be valid UTF-8 text."]
            )
        }

        do {
            let decoder = JSONDecoder()
            let document = try decoder.decode(ActivityWidgetDocument.self, from: data)
            let errors = WidgetActivityValidator.validate(document)
            return WidgetActivityValidationResult(document: errors.isEmpty ? document : nil, errors: errors)
        } catch {
            return WidgetActivityValidationResult(document: nil, errors: [error.localizedDescription])
        }
    }
}

enum WidgetActivityValidator {
    static func validate(_ document: ActivityWidgetDocument) -> [String] {
        var errors: [String] = []

        if document.schemaVersion < 1 {
            errors.append("schemaVersion must be 1 or greater.")
        }

        if document.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("title is required.")
        }

        if document.learningObjective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("learningObjective is required.")
        }

        switch document.activity {
        case .multipleChoice:
            errors.append(contentsOf: validateMultipleChoice(document))
        case .fillInTheBlank:
            errors.append(contentsOf: validateFillInTheBlank(document))
        }

        return errors
    }

    private static func validateFillInTheBlank(_ document: ActivityWidgetDocument) -> [String] {
        var errors: [String] = []

        if document.questions.isEmpty {
            errors.append("fillInTheBlank activities need at least one question.")
        }

        for (questionIndex, question) in document.questions.enumerated() {
            let questionLabel = question.id.isEmpty ? "Question \(questionIndex + 1)" : "Question \(question.id)"
            let hasPrompt = !question.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasExpression = !(question.expression?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

            if !hasPrompt && !hasExpression {
                errors.append("\(questionLabel) needs a prompt or expression.")
            }

            if question.blanks.isEmpty {
                errors.append("\(questionLabel) needs at least one blank.")
            }

            var blankIDs = Set<String>()
            for (blankIndex, blank) in question.blanks.enumerated() {
                let blankLabel = blank.id.isEmpty ? "blank \(blankIndex + 1)" : "blank \(blank.id)"
                let trimmedID = blank.id.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedID.isEmpty {
                    errors.append("\(questionLabel) blank \(blankIndex + 1) needs an id.")
                } else if !blankIDs.insert(trimmedID).inserted {
                    errors.append("\(questionLabel) has duplicate blank id '\(trimmedID)'.")
                }

                let cleanedAnswers = blank.acceptedAnswers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                if cleanedAnswers.isEmpty || cleanedAnswers.contains(where: \.isEmpty) {
                    errors.append("\(questionLabel) \(blankLabel) needs at least one non-empty accepted answer.")
                }

                if let tolerance = blank.tolerance, tolerance < 0 {
                    errors.append("\(questionLabel) \(blankLabel) tolerance cannot be negative.")
                }

                if blank.kind == .numeric {
                    for answer in cleanedAnswers where !answer.isEmpty && evaluatedMathValue(from: answer) == nil {
                        errors.append("\(questionLabel) \(blankLabel) numeric answer '\(answer)' must be a numeric value or expression.")
                    }
                }
            }

            if let responseLayout = question.responseLayout {
                errors.append(contentsOf: validateResponseLayout(
                    responseLayout,
                    blankIDs: blankIDs,
                    questionLabel: questionLabel
                ))
            }

            errors.append(contentsOf: validateInteractiveParts(question.interactiveParts, questionLabel: questionLabel))
        }

        return errors
    }

    private static func validateResponseLayout(
        _ responseLayout: WidgetActivityResponseLayout,
        blankIDs: Set<String>,
        questionLabel: String
    ) -> [String] {
        var errors: [String] = []

        switch responseLayout.type {
        case .fraction:
            let numeratorID = responseLayout.numeratorBlankId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let denominatorID = responseLayout.denominatorBlankId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if numeratorID.isEmpty {
                errors.append("\(questionLabel) fraction responseLayout needs numeratorBlankId.")
            } else if !blankIDs.contains(numeratorID) {
                errors.append("\(questionLabel) fraction responseLayout numeratorBlankId '\(numeratorID)' must match a blank id.")
            }

            if denominatorID.isEmpty {
                errors.append("\(questionLabel) fraction responseLayout needs denominatorBlankId.")
            } else if !blankIDs.contains(denominatorID) {
                errors.append("\(questionLabel) fraction responseLayout denominatorBlankId '\(denominatorID)' must match a blank id.")
            }

            if !numeratorID.isEmpty, numeratorID == denominatorID {
                errors.append("\(questionLabel) fraction responseLayout numeratorBlankId and denominatorBlankId must be different.")
            }
        }

        return errors
    }

    private static func validateMultipleChoice(_ document: ActivityWidgetDocument) -> [String] {
        var errors: [String] = []

        if document.questions.isEmpty {
            errors.append("multipleChoice activities need at least one question.")
        }

        for (questionIndex, question) in document.questions.enumerated() {
            let questionLabel = question.id.isEmpty ? "Question \(questionIndex + 1)" : "Question \(question.id)"
            let hasPrompt = !question.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasExpression = !(question.expression?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

            if !hasPrompt && !hasExpression {
                errors.append("\(questionLabel) needs a prompt or expression.")
            }

            if question.choices.count < 2 || question.choices.count > 6 {
                errors.append("\(questionLabel) needs 2-6 choices.")
            }

            let correctCount = question.choices.filter(\.isCorrect).count
            if correctCount != 1 {
                errors.append("\(questionLabel) needs exactly one correct choice.")
            }

            let duplicateChoiceLabels = duplicateNormalizedChoiceLabels(in: question.choices)
            for label in duplicateChoiceLabels {
                errors.append("\(questionLabel) has duplicate choice label '\(label)'.")
            }

            for (choiceIndex, choice) in question.choices.enumerated() {
                if choice.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    errors.append("\(questionLabel) choice \(choiceIndex + 1) needs an id.")
                }

                if choice.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    errors.append("\(questionLabel) choice \(choiceIndex + 1) needs a label.")
                }
            }

            if correctCount == 1 {
                errors.append(contentsOf: validateNumericAnswer(for: question, questionLabel: questionLabel))
            }

            errors.append(contentsOf: validateInteractiveParts(question.interactiveParts, questionLabel: questionLabel))
        }

        return errors
    }

    private static func validateInteractiveParts(
        _ parts: [WidgetActivityInteractivePart],
        questionLabel: String
    ) -> [String] {
        var errors: [String] = []
        var partIDs = Set<String>()

        for (partIndex, part) in parts.enumerated() {
            let trimmedID = part.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let partLabel = trimmedID.isEmpty ? "interactive part \(partIndex + 1)" : "interactive part '\(trimmedID)'"
            if trimmedID.isEmpty {
                errors.append("\(questionLabel) interactive part \(partIndex + 1) needs an id.")
            } else if !partIDs.insert(trimmedID).inserted {
                errors.append("\(questionLabel) has duplicate interactive part id '\(trimmedID)'.")
            }

            switch part {
            case .numberLine(let numberLine):
                errors.append(contentsOf: validateNumberLine(numberLine, questionLabel: questionLabel, partLabel: partLabel))
            case .coordinatePlane(let coordinatePlane):
                errors.append(contentsOf: validateCoordinatePlane(coordinatePlane, questionLabel: questionLabel, partLabel: partLabel))
            }
        }

        return errors
    }

    private static func validateNumberLine(
        _ part: WidgetActivityNumberLinePart,
        questionLabel: String,
        partLabel: String
    ) -> [String] {
        var errors: [String] = []
        let domain = part.domain
        if !domain.min.isFinite || !domain.max.isFinite || !domain.step.isFinite {
            errors.append("\(questionLabel) \(partLabel) numberLine domain values must be finite.")
        }
        if domain.min >= domain.max {
            errors.append("\(questionLabel) \(partLabel) numberLine domain min must be less than max.")
        }
        if domain.step <= 0 {
            errors.append("\(questionLabel) \(partLabel) numberLine step must be greater than 0.")
        }
        if domain.max > domain.min, domain.step > 0, ((domain.max - domain.min) / domain.step) > 200 {
            errors.append("\(questionLabel) \(partLabel) numberLine domain is too dense; use 200 ticks or fewer.")
        }
        if part.features.pointHasRay, part.features.raysEnabled == false {
            errors.append("\(questionLabel) \(partLabel) numberLine pointHasRay requires raysEnabled.")
        }
        if let maxPoints = part.features.maxPoints, maxPoints <= 0 {
            errors.append("\(questionLabel) \(partLabel) numberLine maxPoints must be greater than 0.")
        }
        if let initialResponse = part.initialResponse {
            errors.append(contentsOf: validateNumberLineGraph(
                initialResponse,
                domain: domain,
                features: part.features,
                questionLabel: questionLabel,
                partLabel: partLabel,
                graphLabel: "initialResponse",
                requiresNonEmpty: false
            ))
        }
        if let answer = part.answer {
            errors.append(contentsOf: validateNumberLineGraph(
                answer,
                domain: domain,
                features: part.features,
                questionLabel: questionLabel,
                partLabel: partLabel,
                graphLabel: "answer",
                requiresNonEmpty: true
            ))
        }
        return errors
    }

    private static func validateNumberLineGraph(
        _ graph: WidgetActivityNumberLineAnswer,
        domain: WidgetActivityNumberLineDomain,
        features: WidgetActivityNumberLineFeatures,
        questionLabel: String,
        partLabel: String,
        graphLabel: String,
        requiresNonEmpty: Bool
    ) -> [String] {
        var errors: [String] = []
        if requiresNonEmpty && graph.isEmpty {
            errors.append("\(questionLabel) \(partLabel) numberLine \(graphLabel) must include at least one point, ray, or segment.")
        }
        for point in graph.selectedPoints {
            if !isNumberLineValueInDomain(point, domain: domain) {
                errors.append("\(questionLabel) \(partLabel) numberLine \(graphLabel) point \(formattedAuditValue(point)) must be inside the domain.")
            }
        }
        for point in graph.points {
            if !isNumberLineValueInDomain(point.value, domain: domain) {
                errors.append("\(questionLabel) \(partLabel) numberLine \(graphLabel) point \(formattedAuditValue(point.value)) must be inside the domain.")
            }
            if point.isClosed == false && features.openClosedEndpoints == false {
                errors.append("\(questionLabel) \(partLabel) numberLine \(graphLabel) includes an open point, but openClosedEndpoints is false.")
            }
        }
        for ray in graph.rays {
            if !isNumberLineValueInDomain(ray.endpoint, domain: domain) {
                errors.append("\(questionLabel) \(partLabel) numberLine \(graphLabel) ray endpoint \(formattedAuditValue(ray.endpoint)) must be inside the domain.")
            }
            if let visualEndValue = ray.visualEndValue {
                if !isNumberLineValueInDomain(visualEndValue, domain: domain) {
                    errors.append("\(questionLabel) \(partLabel) numberLine \(graphLabel) ray visualEndValue \(formattedAuditValue(visualEndValue)) must be inside the domain.")
                }
                if ray.direction == .left, visualEndValue > ray.endpoint {
                    errors.append("\(questionLabel) \(partLabel) numberLine \(graphLabel) left ray visualEndValue must be less than or equal to its endpoint.")
                }
                if ray.direction == .right, visualEndValue < ray.endpoint {
                    errors.append("\(questionLabel) \(partLabel) numberLine \(graphLabel) right ray visualEndValue must be greater than or equal to its endpoint.")
                }
            }
            if features.raysEnabled == false {
                errors.append("\(questionLabel) \(partLabel) numberLine \(graphLabel) includes a ray, but raysEnabled is false.")
            }
            if ray.isClosed == false && features.openClosedEndpoints == false {
                errors.append("\(questionLabel) \(partLabel) numberLine \(graphLabel) includes an open ray endpoint, but openClosedEndpoints is false.")
            }
        }
        for segment in graph.segments {
            if !isNumberLineValueInDomain(segment.start, domain: domain) || !isNumberLineValueInDomain(segment.end, domain: domain) {
                errors.append("\(questionLabel) \(partLabel) numberLine \(graphLabel) segment endpoints must be inside the domain.")
            }
            if segment.start == segment.end {
                errors.append("\(questionLabel) \(partLabel) numberLine \(graphLabel) segment endpoints must be different.")
            }
            if features.segmentsEnabled == false {
                errors.append("\(questionLabel) \(partLabel) numberLine \(graphLabel) includes a segment, but segmentsEnabled is false.")
            }
            if (segment.startClosed == false || segment.endClosed == false) && features.openClosedEndpoints == false {
                errors.append("\(questionLabel) \(partLabel) numberLine \(graphLabel) includes an open segment endpoint, but openClosedEndpoints is false.")
            }
        }
        return errors
    }

    private static func isNumberLineValueInDomain(_ value: Double, domain: WidgetActivityNumberLineDomain) -> Bool {
        value.isFinite && value >= domain.min && value <= domain.max
    }

    private static func validateCoordinatePlane(
        _ part: WidgetActivityCoordinatePlanePart,
        questionLabel: String,
        partLabel: String
    ) -> [String] {
        var errors: [String] = []
        let domain = part.domain
        let values = [domain.xMin, domain.xMax, domain.yMin, domain.yMax, domain.xStep, domain.yStep]
        if values.contains(where: { !$0.isFinite }) {
            errors.append("\(questionLabel) \(partLabel) coordinatePlane domain values must be finite.")
        }
        if domain.xMin >= domain.xMax {
            errors.append("\(questionLabel) \(partLabel) coordinatePlane xMin must be less than xMax.")
        }
        if domain.yMin >= domain.yMax {
            errors.append("\(questionLabel) \(partLabel) coordinatePlane yMin must be less than yMax.")
        }
        if domain.xStep <= 0 || domain.yStep <= 0 {
            errors.append("\(questionLabel) \(partLabel) coordinatePlane steps must be greater than 0.")
        }
        if domain.xMax > domain.xMin, domain.xStep > 0, ((domain.xMax - domain.xMin) / domain.xStep) > 200 {
            errors.append("\(questionLabel) \(partLabel) coordinatePlane x-axis is too dense; use 200 ticks or fewer.")
        }
        if domain.yMax > domain.yMin, domain.yStep > 0, ((domain.yMax - domain.yMin) / domain.yStep) > 200 {
            errors.append("\(questionLabel) \(partLabel) coordinatePlane y-axis is too dense; use 200 ticks or fewer.")
        }
        return errors
    }

    private static func duplicateNormalizedChoiceLabels(in choices: [WidgetActivityChoice]) -> [String] {
        var seen: [String: String] = [:]
        var duplicates: [String] = []
        var duplicateKeys = Set<String>()

        for choice in choices {
            let label = choice.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalizedChoiceLabelKey(label)
            guard !key.isEmpty else { continue }

            if let original = seen[key] {
                if !duplicateKeys.contains(key) {
                    duplicates.append(original)
                    duplicateKeys.insert(key)
                }
            } else {
                seen[key] = label
            }
        }

        return duplicates
    }

    private static func validateNumericAnswer(
        for question: WidgetActivityQuestion,
        questionLabel: String
    ) -> [String] {
        guard let expression = question.expression,
              let expectedValue = evaluatedMathValue(from: expression)
        else {
            return []
        }

        guard let correctChoice = question.choices.first(where: \.isCorrect) else {
            return []
        }

        var errors: [String] = []
        if let correctChoiceValue = evaluatedMathValue(from: correctChoice.label),
           !valuesMatch(correctChoiceValue, expectedValue) {
            errors.append(
                "\(questionLabel) expression evaluates to \(formattedAuditValue(expectedValue)), but the marked correct choice '\(correctChoice.label)' evaluates to \(formattedAuditValue(correctChoiceValue))."
            )
        }

        for choice in question.choices where !choice.isCorrect {
            guard let choiceValue = evaluatedMathValue(from: choice.label),
                  valuesMatch(choiceValue, expectedValue)
            else {
                continue
            }

            errors.append(
                "\(questionLabel) choice '\(choice.label)' is marked incorrect but matches the evaluated answer \(formattedAuditValue(expectedValue))."
            )
        }

        return errors
    }

    static func evaluatedMathValue(from source: String) -> Double? {
        guard let calculatorSource = calculatorSource(from: source),
              isAuditableNumericExpression(calculatorSource)
        else {
            return nil
        }

        do {
            let value = try WidgetNumericExpressionEvaluator.evaluate(calculatorSource)
            return value.isFinite ? value : nil
        } catch {
            return nil
        }
    }

    private static func calculatorSource(from source: String) -> String? {
        var result = unwrapMathDelimiters(source.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !result.isEmpty, !result.contains("=") else { return nil }

        result = result
            .replacingOccurrences(of: "\\left", with: "")
            .replacingOccurrences(of: "\\right", with: "")
            .replacingOccurrences(of: "\\cdot", with: "*")
            .replacingOccurrences(of: "\\times", with: "*")
            .replacingOccurrences(of: "\\div", with: "/")
            .replacingOccurrences(of: "\\pi", with: "pi")
            .replacingOccurrences(of: "−", with: "-")

        guard let withFractions = replaceLaTeXFractions(in: result),
              let withRoots = replaceLaTeXSquareRoots(in: withFractions)
        else {
            return nil
        }

        return withRoots
            .replacingOccurrences(of: "{", with: "(")
            .replacingOccurrences(of: "}", with: ")")
    }

    private static func unwrapMathDelimiters(_ source: String) -> String {
        var result = source
        if result.hasPrefix("$$"), result.hasSuffix("$$"), result.count >= 4 {
            result = String(result.dropFirst(2).dropLast(2))
        } else if result.hasPrefix("$"), result.hasSuffix("$"), result.count >= 2 {
            result = String(result.dropFirst().dropLast())
        } else if result.hasPrefix("\\("), result.hasSuffix("\\)"), result.count >= 4 {
            result = String(result.dropFirst(2).dropLast(2))
        } else if result.hasPrefix("\\["), result.hasSuffix("\\]"), result.count >= 4 {
            result = String(result.dropFirst(2).dropLast(2))
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replaceLaTeXFractions(in source: String) -> String? {
        replaceLaTeXCommandWithTwoArguments(source, command: "\\frac") { numerator, denominator in
            "((\(numerator))/(\(denominator)))"
        }
    }

    private static func replaceLaTeXSquareRoots(in source: String) -> String? {
        replaceLaTeXCommandWithOneArgument(source, command: "\\sqrt") { radicand in
            "sqrt(\(radicand))"
        }
    }

    private static func replaceLaTeXCommandWithTwoArguments(
        _ source: String,
        command: String,
        transform: (String, String) -> String
    ) -> String? {
        var result = source
        while let commandRange = result.range(of: command) {
            guard let first = bracedArgument(in: result, after: commandRange.upperBound),
                  let second = bracedArgument(in: result, after: first.fullRange.upperBound)
            else {
                return nil
            }

            let replacement = transform(first.content, second.content)
            result.replaceSubrange(commandRange.lowerBound..<second.fullRange.upperBound, with: replacement)
        }
        return result
    }

    private static func replaceLaTeXCommandWithOneArgument(
        _ source: String,
        command: String,
        transform: (String) -> String
    ) -> String? {
        var result = source
        while let commandRange = result.range(of: command) {
            guard let argument = bracedArgument(in: result, after: commandRange.upperBound) else {
                return nil
            }

            let replacement = transform(argument.content)
            result.replaceSubrange(commandRange.lowerBound..<argument.fullRange.upperBound, with: replacement)
        }
        return result
    }

    private static func bracedArgument(
        in source: String,
        after startIndex: String.Index
    ) -> (content: String, fullRange: Range<String.Index>)? {
        var openIndex = startIndex
        while openIndex < source.endIndex, source[openIndex].isWhitespace {
            openIndex = source.index(after: openIndex)
        }

        guard openIndex < source.endIndex, source[openIndex] == "{" else {
            return nil
        }

        var depth = 0
        var index = openIndex
        while index < source.endIndex {
            let character = source[index]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    let contentStart = source.index(after: openIndex)
                    return (
                        String(source[contentStart..<index]),
                        openIndex..<source.index(after: index)
                    )
                }
            }
            index = source.index(after: index)
        }

        return nil
    }

    private static func isAuditableNumericExpression(_ source: String) -> Bool {
        let allowedIdentifiers = Set(["pi", "e", "sqrt", "sin", "cos", "tan", "ln", "log", "abs"])
        let identifierPattern = #"[A-Za-zπ]+"#
        guard let regex = try? NSRegularExpression(pattern: identifierPattern) else {
            return false
        }

        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        let matches = regex.matches(in: source, range: range)
        for match in matches {
            guard let matchRange = Range(match.range, in: source) else {
                return false
            }
            let identifier = String(source[matchRange]).lowercased()
            if !allowedIdentifiers.contains(identifier) {
                return false
            }
        }

        return source.rangeOfCharacter(from: .decimalDigits) != nil
    }

    private static func normalizedChoiceLabelKey(_ label: String) -> String {
        let calculator = calculatorSource(from: label) ?? unwrapMathDelimiters(label)
        return calculator
            .lowercased()
            .replacingOccurrences(of: "\\left", with: "")
            .replacingOccurrences(of: "\\right", with: "")
            .replacingOccurrences(of: "\\cdot", with: "*")
            .replacingOccurrences(of: "\\times", with: "*")
            .replacingOccurrences(of: "\\div", with: "/")
            .filter { !$0.isWhitespace }
    }

    static func valuesMatch(_ lhs: Double, _ rhs: Double, tolerance explicitTolerance: Double? = nil) -> Bool {
        let tolerance = explicitTolerance ?? max(1e-8, max(abs(lhs), abs(rhs)) * 1e-8)
        return abs(lhs - rhs) <= tolerance
    }

    private static func formattedAuditValue(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 1e12 {
            return String(Int64(value))
        }
        return String(format: "%.8g", value)
    }
}

enum WidgetActivityAnswerChecker {
    static func response(_ response: String, matches blank: WidgetActivityBlank) -> Bool {
        switch blank.kind {
        case .text:
            return textResponse(response, matches: blank)
        case .numeric:
            return numericResponse(response, matches: blank)
        }
    }

    private static func textResponse(_ response: String, matches blank: WidgetActivityBlank) -> Bool {
        let normalizedResponse = normalizedText(response, caseSensitive: blank.caseSensitive == true)
        return blank.acceptedAnswers.contains { answer in
            normalizedText(answer, caseSensitive: blank.caseSensitive == true) == normalizedResponse
        }
    }

    private static func numericResponse(_ response: String, matches blank: WidgetActivityBlank) -> Bool {
        guard let responseValue = WidgetActivityValidator.evaluatedMathValue(from: response) else { return false }
        return blank.acceptedAnswers.contains { answer in
            guard let acceptedValue = WidgetActivityValidator.evaluatedMathValue(from: answer) else { return false }
            return WidgetActivityValidator.valuesMatch(responseValue, acceptedValue, tolerance: blank.tolerance)
        }
    }

    private static func normalizedText(_ source: String, caseSensitive: Bool) -> String {
        let collapsedWhitespace = source
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return caseSensitive ? collapsedWhitespace : collapsedWhitespace.lowercased()
    }
}

private struct WidgetNumericExpressionEvaluator {
    private var characters: [Character]
    private var index = 0

    static func evaluate(_ source: String) throws -> Double {
        var evaluator = WidgetNumericExpressionEvaluator(characters: Array(source))
        let value = try evaluator.parseExpression()
        evaluator.skipWhitespace()
        guard evaluator.index == evaluator.characters.count else {
            throw EvaluationError.unexpectedCharacter
        }
        return value
    }

    private mutating func parseExpression() throws -> Double {
        var value = try parseTerm()
        while let character = peek() {
            switch character {
            case "+":
                advance()
                value += try parseTerm()
            case "-":
                advance()
                value -= try parseTerm()
            default:
                return value
            }
        }
        return value
    }

    private mutating func parseTerm() throws -> Double {
        var value = try parseUnary()
        while let character = peek() {
            switch character {
            case "*", "×", "·", "⋅":
                advance()
                value *= try parseUnary()
            case "/", "÷":
                advance()
                let divisor = try parseUnary()
                guard divisor != 0 else { throw EvaluationError.divisionByZero }
                value /= divisor
            case "(", ".", "0"..."9":
                value *= try parseUnary()
            default:
                if character.isLetter || character == "π" {
                    value *= try parseUnary()
                } else {
                    return value
                }
            }
        }
        return value
    }

    private mutating func parseUnary() throws -> Double {
        skipWhitespace()
        if peek() == "+" {
            advance()
            return try parseUnary()
        }
        if peek() == "-" || peek() == "−" {
            advance()
            return try -parseUnary()
        }
        return try parsePower()
    }

    private mutating func parsePower() throws -> Double {
        let base = try parsePrimary()
        skipWhitespace()
        if peek() == "^" {
            advance()
            return pow(base, try parsePower())
        }
        return base
    }

    private mutating func parsePrimary() throws -> Double {
        skipWhitespace()
        guard let character = peek() else {
            throw EvaluationError.unexpectedEnd
        }

        if character == "(" || character == "[" {
            advance()
            let value = try parseExpression()
            skipWhitespace()
            guard peek() == ")" || peek() == "]" else {
                throw EvaluationError.missingClosingParenthesis
            }
            advance()
            return value
        }

        if character.isNumber || character == "." {
            return try parseNumber()
        }

        if character.isLetter || character == "π" {
            return try parseIdentifier()
        }

        throw EvaluationError.unexpectedCharacter
    }

    private mutating func parseNumber() throws -> Double {
        skipWhitespace()
        var raw = ""

        while let character = peek(), character.isNumber || character == "." {
            raw.append(character)
            advance()
        }

        if let character = peek(), character == "e" || character == "E" {
            raw.append(character)
            advance()
            if let sign = peek(), sign == "+" || sign == "-" {
                raw.append(sign)
                advance()
            }
            while let character = peek(), character.isNumber {
                raw.append(character)
                advance()
            }
        }

        guard let value = Double(raw) else {
            throw EvaluationError.malformedNumber
        }
        return value
    }

    private mutating func parseIdentifier() throws -> Double {
        skipWhitespace()
        var name = ""
        while let character = peek(), character.isLetter || character.isNumber || character == "π" {
            name.append(character)
            advance()
        }

        switch name.lowercased() {
        case "pi", "π":
            return .pi
        case "e":
            return M_E
        case "sqrt":
            skipWhitespace()
            guard peek() == "(" else {
                throw EvaluationError.missingFunctionArgument
            }
            advance()
            let value = try parseExpression()
            guard value >= 0 else {
                throw EvaluationError.domain
            }
            skipWhitespace()
            guard peek() == ")" else {
                throw EvaluationError.missingClosingParenthesis
            }
            advance()
            return sqrt(value)
        default:
            throw EvaluationError.unsupportedIdentifier
        }
    }

    private mutating func skipWhitespace() {
        while let character = peek(), character.isWhitespace {
            advance()
        }
    }

    private func peek() -> Character? {
        index < characters.count ? characters[index] : nil
    }

    private mutating func advance() {
        index += 1
    }

    private enum EvaluationError: Error {
        case divisionByZero
        case domain
        case malformedNumber
        case missingClosingParenthesis
        case missingFunctionArgument
        case unexpectedCharacter
        case unexpectedEnd
        case unsupportedIdentifier
    }
}
