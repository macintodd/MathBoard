//
//  MathtivityCatalogModels.swift
//  Library
//
//  Catalog metadata for MathBoard-owned widgets, built-in interactives, and
//  downloadable JSON mathtivities.
//

import Foundation
import WidgetEngine

public enum MathtivityCatalogActivityType: String, Codable, CaseIterable, Sendable {
    case multipleChoice
    case fillInTheBlank
    case numericAnswer
    case expressionAnswer
    case matching
    case ordering
    case multiStep

    public var displayName: String {
        switch self {
        case .multipleChoice:
            return "Multiple Choice"
        case .fillInTheBlank:
            return "Fill in the Blank"
        case .numericAnswer:
            return "Numeric Answer"
        case .expressionAnswer:
            return "Expression Answer"
        case .matching:
            return "Matching"
        case .ordering:
            return "Ordering"
        case .multiStep:
            return "Multi-Step"
        }
    }

    public var widgetActivityKind: WidgetObjectActivityKind? {
        switch self {
        case .multipleChoice:
            return .multipleChoice
        case .fillInTheBlank:
            return .fillInTheBlank
        case .numericAnswer, .expressionAnswer, .matching, .ordering, .multiStep:
            return nil
        }
    }
}

public enum MathtivityCatalogWorkflow: String, Codable, CaseIterable, Sendable {
    case bellRingerExitTicket
    case conceptualInteractive
    case assessment
    case tools
    case classPlay

    public var displayName: String {
        switch self {
        case .bellRingerExitTicket:
            return "Bell Ringers & Exit Tickets"
        case .conceptualInteractive:
            return "Conceptual Interactives"
        case .assessment:
            return "Assessments"
        case .tools:
            return "Tools"
        case .classPlay:
            return "Class Play"
        }
    }

    public var sectionSubtitle: String {
        switch self {
        case .bellRingerExitTicket:
            return "Single-question warmups and closure checks"
        case .conceptualInteractive:
            return "Zero-score canvas tools for exploration and demonstration"
        case .assessment:
            return "Scored CFUs and quizzes for reports and live progress"
        case .tools:
            return "Canvas utilities for generating lesson materials"
        case .classPlay:
            return "Whole-class review games and shared activities"
        }
    }
}

public enum MathtivityCatalogKind: String, Codable, CaseIterable, Sendable {
    case widgetTemplate
    case builtInInteractive
    case premadeMathtivity

    public var displayName: String {
        switch self {
        case .widgetTemplate:
            return "Widget Type"
        case .builtInInteractive:
            return "Built-In Interactive"
        case .premadeMathtivity:
            return "Premade Mathtivity"
        }
    }
}

public enum MathtivityCatalogSource: String, Codable, CaseIterable, Sendable {
    case bundled
    case firebase

    public var displayName: String {
        switch self {
        case .bundled:
            return "Built in"
        case .firebase:
            return "Online"
        }
    }
}

public enum MathtivityCatalogAnswerMode: String, Codable, CaseIterable, Sendable {
    case text
    case expression
    case textAndExpression
    case graphic
    case numeric

    public var displayName: String {
        switch self {
        case .text:
            return "Text Answers"
        case .expression:
            return "Expression Answers"
        case .textAndExpression:
            return "Text & Expression Answers"
        case .graphic:
            return "Graphic Answers"
        case .numeric:
            return "Numeric Answers"
        }
    }
}

public enum MathtivityCatalogMode: String, Codable, CaseIterable, Sendable {
    case scored
    case demo

    public var displayName: String {
        switch self {
        case .scored:
            return "Scored"
        case .demo:
            return "Demo"
        }
    }
}

public struct MathtivityCatalogItem: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var catalogKind: MathtivityCatalogKind
    public var source: MathtivityCatalogSource
    public var topic: String
    public var course: String?
    public var activityType: MathtivityCatalogActivityType
    public var answerMode: MathtivityCatalogAnswerMode?
    public var mode: MathtivityCatalogMode
    public var pedagogicalWorkflow: MathtivityCatalogWorkflow?
    public var topicLevel: Int?
    public var questionCount: Int?
    public var difficulty: String?
    public var description: String?
    public var tags: [String]
    public var schemaVersion: Int
    public var requiredAppVersion: String?
    public var jsonStoragePath: String
    public var thumbnailStoragePath: String?
    public var bundledResourceName: String?
    public var builtInKind: BuiltInInteractiveKind?
    public var isPublished: Bool
    public var version: Int
    public var updatedAt: Date?

    public init(
        id: String,
        title: String,
        catalogKind: MathtivityCatalogKind = .premadeMathtivity,
        source: MathtivityCatalogSource = .firebase,
        topic: String,
        course: String? = nil,
        activityType: MathtivityCatalogActivityType,
        answerMode: MathtivityCatalogAnswerMode? = nil,
        mode: MathtivityCatalogMode = .scored,
        pedagogicalWorkflow: MathtivityCatalogWorkflow? = nil,
        topicLevel: Int? = nil,
        questionCount: Int? = nil,
        difficulty: String? = nil,
        description: String? = nil,
        tags: [String] = [],
        schemaVersion: Int = 1,
        requiredAppVersion: String? = nil,
        jsonStoragePath: String,
        thumbnailStoragePath: String? = nil,
        bundledResourceName: String? = nil,
        builtInKind: BuiltInInteractiveKind? = nil,
        isPublished: Bool = true,
        version: Int = 1,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.catalogKind = catalogKind
        self.source = source
        self.topic = topic
        self.course = course
        self.activityType = activityType
        self.answerMode = answerMode
        self.mode = mode
        self.pedagogicalWorkflow = pedagogicalWorkflow
        self.topicLevel = topicLevel
        self.questionCount = questionCount
        self.difficulty = difficulty
        self.description = description
        self.tags = tags
        self.schemaVersion = schemaVersion
        self.requiredAppVersion = requiredAppVersion
        self.jsonStoragePath = jsonStoragePath
        self.thumbnailStoragePath = thumbnailStoragePath
        self.bundledResourceName = bundledResourceName
        self.builtInKind = builtInKind
        self.isPublished = isPublished
        self.version = version
        self.updatedAt = updatedAt
    }

    public init?(id: String, firestoreData data: [String: Any]) {
        guard
            let title = Self.stringValue(data["title"]),
            let topic = Self.stringValue(data["topic"])
        else {
            return nil
        }
        let catalogKind = Self.catalogKindValue(data["catalogKind"]) ?? .premadeMathtivity
        let builtInKind = Self.builtInKindValue(data["builtInKind"])
        let activityType = Self.activityTypeValue(data["activityType"]) ?? .multipleChoice
        let jsonStoragePath = Self.stringValue(data["jsonStoragePath"])
            ?? builtInKind.map { "\(MathtivityCatalogLocalRegistry.builtInPrefix)\($0.rawValue)" }
            ?? ""
        guard !jsonStoragePath.isEmpty else { return nil }

        self.init(
            id: id,
            title: title,
            catalogKind: catalogKind,
            source: .firebase,
            topic: topic,
            course: Self.stringValue(data["course"]),
            activityType: activityType,
            answerMode: Self.answerModeValue(data["answerMode"]),
            mode: Self.modeValue(data["mode"]) ?? .scored,
            pedagogicalWorkflow: Self.workflowValue(data["pedagogicalWorkflow"]),
            topicLevel: Self.intValue(data["topicLevel"]),
            questionCount: Self.intValue(data["questionCount"]),
            difficulty: Self.stringValue(data["difficulty"]),
            description: Self.stringValue(data["description"]),
            tags: Self.stringArrayValue(data["tags"]),
            schemaVersion: Self.intValue(data["schemaVersion"]) ?? 1,
            requiredAppVersion: Self.stringValue(data["requiredAppVersion"]),
            jsonStoragePath: jsonStoragePath,
            thumbnailStoragePath: Self.stringValue(data["thumbnailStoragePath"]),
            bundledResourceName: nil,
            builtInKind: builtInKind,
            isPublished: Self.boolValue(data["isPublished"]) ?? false,
            version: Self.intValue(data["version"]) ?? 1,
            updatedAt: data["updatedAt"] as? Date
        )
    }

    public init?(bundledEntry entry: JSONMathtivityCatalog.Entry) {
        let activityType: MathtivityCatalogActivityType
        switch entry.activityType {
        case .multipleChoice:
            activityType = .multipleChoice
        case .fillInTheBlank:
            activityType = .fillInTheBlank
        case .builtInInteractive, .unknown:
            return nil
        }

        let mode: MathtivityCatalogMode
        switch entry.mode {
        case .scored:
            mode = .scored
        case .demo:
            mode = .demo
        }
        let questionCount = Self.questionCount(forBundledResourceName: entry.resourceName)

        self.init(
            id: "bundled.\(entry.resourceName)",
            title: entry.title,
            catalogKind: .premadeMathtivity,
            source: .bundled,
            topic: questionCount == 1 ? "Bell Ringers & Exit Tickets" : entry.topic,
            course: entry.topic,
            activityType: activityType,
            mode: mode,
            pedagogicalWorkflow: questionCount == 1 ? .bellRingerExitTicket : .assessment,
            topicLevel: entry.topicLevel,
            questionCount: questionCount,
            description: "Bundled starter mathtivity.",
            tags: entry.tags,
            schemaVersion: 1,
            jsonStoragePath: "bundled://\(entry.resourceName)",
            bundledResourceName: entry.resourceName,
            isPublished: true,
            version: 1
        )
    }

    public var catalogLibraryRecentID: String {
        "catalog.\(id)"
    }

    public var resolvedPedagogicalWorkflow: MathtivityCatalogWorkflow {
        if let pedagogicalWorkflow {
            return pedagogicalWorkflow
        }
        if let builtInKind {
            switch builtInKind {
            case .actDailyPractice:
                return .bellRingerExitTicket
            case .countdownTimer, .randomNumberGenerator, .coordinateGridGenerator:
                return .tools
            case .functionTransformationExplorer:
                return .conceptualInteractive
            case .matchGrid:
                return .classPlay
            case .inequalitiesExplorer:
                return .assessment
            }
        }
        if catalogKind == .builtInInteractive || mode == .demo {
            return .conceptualInteractive
        }
        if questionCount == 1 {
            return .bellRingerExitTicket
        }
        return .assessment
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func stringArrayValue(_ value: Any?) -> [String] {
        (value as? [String])?.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static func modeValue(_ value: Any?) -> MathtivityCatalogMode? {
        guard let rawValue = stringValue(value) else { return nil }
        return MathtivityCatalogMode(rawValue: rawValue)
    }

    private static func activityTypeValue(_ value: Any?) -> MathtivityCatalogActivityType? {
        guard let rawValue = stringValue(value) else { return nil }
        return MathtivityCatalogActivityType(rawValue: rawValue)
    }

    private static func catalogKindValue(_ value: Any?) -> MathtivityCatalogKind? {
        guard let rawValue = stringValue(value) else { return nil }
        return MathtivityCatalogKind(rawValue: rawValue)
    }

    private static func answerModeValue(_ value: Any?) -> MathtivityCatalogAnswerMode? {
        guard let rawValue = stringValue(value) else { return nil }
        return MathtivityCatalogAnswerMode(rawValue: rawValue)
    }

    private static func workflowValue(_ value: Any?) -> MathtivityCatalogWorkflow? {
        guard let rawValue = stringValue(value) else { return nil }
        return MathtivityCatalogWorkflow(rawValue: rawValue)
    }

    private static func builtInKindValue(_ value: Any?) -> BuiltInInteractiveKind? {
        guard let rawValue = stringValue(value) else { return nil }
        return BuiltInInteractiveKind(rawValue: rawValue)
    }

    private static func questionCount(forBundledResourceName resourceName: String) -> Int? {
        guard let entry = JSONMathtivityCatalog.bundledEntries.first(where: { $0.resourceName == resourceName }),
              let source = JSONMathtivityCatalog.source(for: entry) else {
            return nil
        }
        let repairedSource = source.replacingOccurrences(of: "\u{feff}", with: "")
        guard let data = repairedSource.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let questions = root["questions"] as? [Any] else {
            return nil
        }
        return questions.count
    }
}

public enum MathtivityCatalogLocalRegistry {
    public static let templatePrefix = "template://"
    public static let builtInPrefix = "builtin://"

    public static let widgetTemplates: [MathtivityCatalogItem] = [
        MathtivityCatalogItem(
            id: "template.multiple-choice-text-expression",
            title: "Multiple Choice - Text & Expression Answers",
            catalogKind: .widgetTemplate,
            source: .bundled,
            topic: "Bell Ringers & Exit Tickets",
            activityType: .multipleChoice,
            answerMode: .textAndExpression,
            mode: .scored,
            pedagogicalWorkflow: .bellRingerExitTicket,
            questionCount: 1,
            description: "Single-question multiple-choice container for quick warmups or closure checks.",
            tags: ["bell ringer", "exit ticket", "multiple choice", "template", "text answers", "expression answers"],
            jsonStoragePath: "\(templatePrefix)multiple-choice-text-expression"
        ),
        MathtivityCatalogItem(
            id: "template.multiple-choice-graphic",
            title: "Multiple Choice - Graphic Answers",
            catalogKind: .widgetTemplate,
            source: .bundled,
            topic: "Bell Ringers & Exit Tickets",
            activityType: .multipleChoice,
            answerMode: .graphic,
            mode: .scored,
            pedagogicalWorkflow: .bellRingerExitTicket,
            questionCount: 1,
            description: "Single-question visual-choice container for graph, number-line, or diagram checks.",
            tags: ["bell ringer", "exit ticket", "multiple choice", "template", "graphic answers", "visual choices"],
            jsonStoragePath: "\(templatePrefix)multiple-choice-graphic"
        ),
        MathtivityCatalogItem(
            id: "template.fill-in-the-blank",
            title: "Fill in the Blank",
            catalogKind: .widgetTemplate,
            source: .bundled,
            topic: "Bell Ringers & Exit Tickets",
            activityType: .fillInTheBlank,
            answerMode: .textAndExpression,
            mode: .scored,
            pedagogicalWorkflow: .bellRingerExitTicket,
            questionCount: 1,
            description: "Single-question fill-in container for short response warmups or exit tickets.",
            tags: ["bell ringer", "exit ticket", "fill in the blank", "template", "numeric answers", "text answers"],
            jsonStoragePath: "\(templatePrefix)fill-in-the-blank"
        )
    ]

    public static let builtInInteractives: [MathtivityCatalogItem] = BuiltInInteractiveKind.allCases.map { kind in
        let workflow = workflow(for: kind)
        return MathtivityCatalogItem(
            id: "builtin.\(kind.rawValue)",
            title: kind.displayName,
            catalogKind: .builtInInteractive,
            source: .bundled,
            topic: workflow.displayName,
            activityType: .multipleChoice,
            mode: kind.isScoreable ? .scored : .demo,
            pedagogicalWorkflow: workflow,
            questionCount: kind.isScoreable ? kind.scoreableTaskCount : nil,
            difficulty: "interactive",
            description: kind.catalogDescription,
            tags: kind.catalogTags,
            jsonStoragePath: "\(builtInPrefix)\(kind.rawValue)",
            builtInKind: kind
        )
    }

    private static func workflow(for kind: BuiltInInteractiveKind) -> MathtivityCatalogWorkflow {
        switch kind {
        case .actDailyPractice:
            return .bellRingerExitTicket
        case .countdownTimer, .randomNumberGenerator, .coordinateGridGenerator:
            return .tools
        case .functionTransformationExplorer:
            return .conceptualInteractive
        case .matchGrid:
            return .classPlay
        case .inequalitiesExplorer:
            return .assessment
        }
    }

    public static var bundledPremadeMathtivities: [MathtivityCatalogItem] {
        JSONMathtivityCatalog.bundledEntries.compactMap(MathtivityCatalogItem.init(bundledEntry:))
    }

    public static var bundledCatalog: [MathtivityCatalogItem] {
        widgetTemplates + builtInInteractives + bundledPremadeMathtivities
    }

    public static func source(for item: MathtivityCatalogItem) -> String? {
        if let bundledResourceName = item.bundledResourceName,
           let entry = JSONMathtivityCatalog.bundledEntries.first(where: { $0.resourceName == bundledResourceName }) {
            return JSONMathtivityCatalog.source(for: entry)
        }

        if let templateID = item.jsonStoragePath.removingPrefix(templatePrefix) {
            return templateSource(for: templateID)
        }

        if let builtInID = item.jsonStoragePath.removingPrefix(builtInPrefix),
           let kind = BuiltInInteractiveKind(rawValue: builtInID) {
            return kind.widgetCodeString
        }

        return nil
    }

    private static func templateSource(for templateID: String) -> String? {
        switch templateID {
        case "multiple-choice-text-expression":
            return #"""
            {
              "schemaVersion": 1,
              "widgetId": "multiple-choice-text-expression-template",
              "activity": "multipleChoice",
              "title": "Multiple Choice",
              "description": "Editable starter multiple-choice widget.",
              "learningObjective": "Students choose the correct answer from text or expression choices.",
              "pedagogicalWorkflow": "bellRingerExitTicket",
              "usageTracking": {
                "lastUsedDate": null,
                "associatedClass": null
              },
              "difficulty": "easy",
              "presentation": {
                "preferredTheme": "cleanClassroom",
                "preferredExperience": "paperQuiz"
              },
              "rules": {
                "scoreMode": "correctOutOfAttempted",
                "advanceMode": "manual",
                "allowRetry": true,
                "shuffleQuestions": false,
                "shuffleChoices": false,
                "maxAttemptsPerQuestion": 2,
                "calculatorAllowed": false
              },
              "feedback": {
                "defaultCorrect": "Correct.",
                "defaultIncorrect": "Not yet. Try again.",
                "defaultEncouragement": "Look at the structure of the problem."
              },
              "questions": [
                {
                  "id": "q1",
                  "prompt": "Replace this prompt with your question.",
                  "expression": "2x + 3 = 11",
                  "choices": [
                    { "id": "a", "label": "x = 4", "isCorrect": true },
                    { "id": "b", "label": "x = 7", "isCorrect": false },
                    { "id": "c", "label": "x = 8", "isCorrect": false },
                    { "id": "d", "label": "x = 14", "isCorrect": false }
                  ],
                  "hints": [
                    "Undo addition first.",
                    "Then divide both sides."
                  ],
                  "correctFeedback": "Yes. Subtract 3, then divide by 2.",
                  "incorrectFeedback": "Check the inverse operations."
                }
              ]
            }
            """#
        case "multiple-choice-graphic":
            return #"""
            {
              "schemaVersion": 1,
              "widgetId": "multiple-choice-graphic-template",
              "activity": "multipleChoice",
              "title": "Graphic Choice",
              "description": "Editable starter multiple-choice widget for visual answers.",
              "learningObjective": "Students choose the correct visual representation.",
              "pedagogicalWorkflow": "bellRingerExitTicket",
              "usageTracking": {
                "lastUsedDate": null,
                "associatedClass": null
              },
              "difficulty": "easy",
              "presentation": {
                "preferredTheme": "cleanClassroom",
                "preferredExperience": "paperQuiz"
              },
              "rules": {
                "scoreMode": "correctOutOfAttempted",
                "advanceMode": "manual",
                "allowRetry": true,
                "shuffleQuestions": false,
                "shuffleChoices": false,
                "maxAttemptsPerQuestion": 2,
                "calculatorAllowed": false
              },
              "questions": [
                {
                  "id": "q1",
                  "prompt": "Which graph matches the inequality?",
                  "expression": "x > 2",
                  "choices": [
                    { "id": "a", "label": "Open circle at 2, shaded right", "isCorrect": true },
                    { "id": "b", "label": "Closed circle at 2, shaded right", "isCorrect": false },
                    { "id": "c", "label": "Open circle at 2, shaded left", "isCorrect": false },
                    { "id": "d", "label": "Closed circle at 2, shaded left", "isCorrect": false }
                  ],
                  "interactiveParts": [
                    {
                      "type": "numberLine",
                      "id": "line",
                      "domain": { "min": -5, "max": 5, "step": 1 },
                      "features": {
                        "pointsTappable": false,
                        "pointsDraggable": false,
                        "raysEnabled": true,
                        "segmentsEnabled": false,
                        "openClosedEndpoints": true,
                        "pointHasRay": true,
                        "labelsVisible": true,
                        "snapToTicks": true
                      },
                      "answer": "linearGraphUtility{x>2}"
                    }
                  ],
                  "hints": [
                    "A strict inequality uses an open circle.",
                    "Greater than shades to the right."
                  ],
                  "correctFeedback": "Correct. x > 2 uses an open endpoint and a right ray.",
                  "incorrectFeedback": "Check both the endpoint and shading direction."
                }
              ]
            }
            """#
        case "fill-in-the-blank":
            return #"""
            {
              "schemaVersion": 1,
              "widgetId": "fill-in-the-blank-template",
              "activity": "fillInTheBlank",
              "title": "Fill in the Blank",
              "description": "Editable starter fill-in-the-blank widget.",
              "learningObjective": "Students complete missing values or short responses.",
              "pedagogicalWorkflow": "bellRingerExitTicket",
              "usageTracking": {
                "lastUsedDate": null,
                "associatedClass": null
              },
              "difficulty": "easy",
              "presentation": {
                "preferredTheme": "cleanClassroom",
                "preferredExperience": "paperQuiz"
              },
              "rules": {
                "scoreMode": "correctOutOfAttempted",
                "advanceMode": "manual",
                "allowRetry": true,
                "shuffleQuestions": false,
                "maxAttemptsPerQuestion": 2,
                "calculatorAllowed": false
              },
              "questions": [
                {
                  "id": "q1",
                  "prompt": "Solve for x: 2x + 3 = 11",
                  "blanks": [
                    {
                      "id": "x",
                      "kind": "numeric",
                      "acceptedAnswers": ["4"],
                      "tolerance": 0.0001
                    }
                  ],
                  "hints": [
                    "Subtract 3 from both sides.",
                    "Divide by 2."
                  ],
                  "correctFeedback": "Correct. x = 4.",
                  "incorrectFeedback": "Check the inverse operations."
                }
              ]
            }
            """#
        default:
            return nil
        }
    }
}

private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}

public struct DownloadedMathtivityCatalogItem: Sendable, Equatable {
    public var item: MathtivityCatalogItem
    public var jsonSource: String
    public var thumbnailPNGData: Data?

    public init(
        item: MathtivityCatalogItem,
        jsonSource: String,
        thumbnailPNGData: Data? = nil
    ) {
        self.item = item
        self.jsonSource = jsonSource
        self.thumbnailPNGData = thumbnailPNGData
    }
}

@MainActor
public protocol MathtivityCatalogProviding {
    func fetchPublishedCatalog(limit: Int) async throws -> [MathtivityCatalogItem]
    func downloadMathtivity(_ item: MathtivityCatalogItem) async throws -> DownloadedMathtivityCatalogItem
}
