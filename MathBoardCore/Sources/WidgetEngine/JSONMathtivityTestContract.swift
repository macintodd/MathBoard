//
//  JSONMathtivityTestContract.swift
//  WidgetEngine
//
//  Standardized acceptance contract for JSON mathtivities. The renderer can be
//  permissive while editing, but catalog imports and regression tests should use
//  this contract before a JSON widget is treated as a reusable mathtivity.
//

import CoreGraphics
import Foundation

public struct JSONMathtivityTestContractReport: Equatable, Sendable {
    public var widgetID: String?
    public var title: String?
    public var activityKind: WidgetObjectActivityKind
    public var questionCount: Int
    public var pointsPossible: Int
    public var errors: [String]

    public var isValid: Bool { errors.isEmpty }

    public init(
        widgetID: String? = nil,
        title: String? = nil,
        activityKind: WidgetObjectActivityKind = .unknown,
        questionCount: Int = 0,
        pointsPossible: Int = 0,
        errors: [String]
    ) {
        self.widgetID = widgetID
        self.title = title
        self.activityKind = activityKind
        self.questionCount = questionCount
        self.pointsPossible = pointsPossible
        self.errors = errors
    }
}

public enum JSONMathtivityTestContract {
    public static func evaluate(
        source: String,
        expectedActivityKind: WidgetObjectActivityKind? = nil
    ) -> JSONMathtivityTestContractReport {
        let validation = WidgetActivityJSONCodec.decode(source)
        guard let document = validation.document else {
            return JSONMathtivityTestContractReport(errors: validation.errors)
        }

        var errors = validation.errors
        let trimmedWidgetID = document.widgetId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedWidgetID.isEmpty {
            errors.append("Catalog JSON mathtivities need a stable widgetId.")
        }

        let widget = WidgetObject(
            name: document.title,
            codeString: source,
            frame: CGRect(x: 0, y: 0, width: 820, height: 420)
        )
        let activityKind = widget.activityKind
        if activityKind == .unknown {
            errors.append("JSON mathtivity must resolve to a supported widget activity kind.")
        }
        if let expectedActivityKind, activityKind != expectedActivityKind {
            errors.append("Expected \(expectedActivityKind.rawValue), got \(activityKind.rawValue).")
        }

        validateDefaultScoreRecord(widget.activityScoreRecord, document: document, errors: &errors)
        validateActivitySpecificBehavior(document, errors: &errors)

        return JSONMathtivityTestContractReport(
            widgetID: document.widgetId,
            title: document.title,
            activityKind: activityKind,
            questionCount: document.questions.count,
            pointsPossible: document.questions.count,
            errors: errors
        )
    }

    private static func validateDefaultScoreRecord(
        _ record: WidgetActivityScoreRecord?,
        document: ActivityWidgetDocument,
        errors: inout [String]
    ) {
        guard let record else {
            errors.append("JSON mathtivity must produce a score record for teacher reports.")
            return
        }

        if record.status != .notStarted {
            errors.append("Default score record should start as notStarted.")
        }
        if record.score != 0 || record.attempts != 0 || record.points != 0 {
            errors.append("Default score record should start with zero score, attempts, and points.")
        }
        if record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Default score record needs a non-empty title.")
        }
        if record.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Default score record needs a non-empty id.")
        }
        if record.title != document.title {
            errors.append("Default score record title should match the mathtivity title.")
        }
    }

    private static func validateActivitySpecificBehavior(
        _ document: ActivityWidgetDocument,
        errors: inout [String]
    ) {
        switch document.activity {
        case .multipleChoice:
            for question in document.questions {
                if question.choices.filter(\.isCorrect).count != 1 {
                    errors.append("Question \(question.id) must have exactly one correct choice.")
                }
            }
        case .fillInTheBlank:
            for question in document.questions {
                for blank in question.blanks {
                    guard let acceptedAnswer = blank.acceptedAnswers.first else {
                        errors.append("Question \(question.id) blank \(blank.id) needs an accepted answer.")
                        continue
                    }
                    if !WidgetActivityAnswerChecker.response(acceptedAnswer, matches: blank) {
                        errors.append("Question \(question.id) blank \(blank.id) accepted answer must pass its own checker.")
                    }
                }
            }
        }
    }
}
