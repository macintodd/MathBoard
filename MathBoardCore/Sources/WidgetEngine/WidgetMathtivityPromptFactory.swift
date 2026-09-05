//
//  WidgetMathtivityPromptFactory.swift
//  WidgetEngine
//
//  Builds teacher-facing AI prompts from app-owned JSON mathtivity contracts.
//

import Foundation

enum WidgetMathtivityPromptIntent: Equatable, Sendable {
    case create
    case createBellRingerExitTicket
    case remix(sourceJSON: String)
}

enum WidgetMathtivityPromptFactory {
    static func prompt(
        for activityKind: WidgetObjectActivityKind,
        intent: WidgetMathtivityPromptIntent
    ) -> String {
        let normalizedKind = supportedKind(from: activityKind)
        let sourceJSON: String
        let opening: String

        switch intent {
        case .create, .createBellRingerExitTicket:
            opening = "You are helping create a MathBoard \(normalizedKind.displayName) JSON bell ringer or exit ticket."
            sourceJSON = singleQuestionStarterJSON(for: normalizedKind)
        case .remix(let json):
            opening = "You are helping revise a MathBoard \(normalizedKind.displayName) JSON mathtivity."
            sourceJSON = json
        }

        return [
            opening,
            "",
            "First ask me what I want changed. Do not rewrite the JSON until I answer.",
            "",
            "When you do rewrite it, return only valid JSON. Do not include Markdown, prose, comments, or a code fence.",
            "Use plain ASCII straight double quotes for JSON keys and strings. Do not use smart quotes or curly quotes.",
            "Inside JSON strings, every LaTeX backslash must be doubled. Write \\\\frac, \\\\quad, and \\\\_ in JSON, never \\frac, \\quad, or \\_.",
            "For simple fill-in blanks in expressions, use a visible blank marker like \\\\_ or a named blank such as ____; never end a JSON string with a single backslash.",
            "For numerator and denominator answer cells, do not fake blanks with LaTeX such as \\\\frac{\\\\}{\\\\}. Define normal blanks, then add responseLayout: { \"type\": \"fraction\", \"label\": \"m =\", \"numeratorBlankId\": \"numerator\", \"denominatorBlankId\": \"denominator\" }.",
            "Keep schemaVersion as 1 and keep activity as \"\(normalizedKind.rawValue)\" unless I explicitly ask to change the activity type.",
            "Do not add teacher-facing theme, experience, CSS, scoring visual, animation, image, audio, or custom code fields. MathBoard owns the visual renderer and score presentation.",
            workflowInstructions(for: intent),
            "",
            "Activity-specific JSON contract:",
            contract(for: normalizedKind),
            "",
            sourceHeader(for: intent, kind: normalizedKind),
            sourceJSON
        ].joined(separator: "\n")
    }

    static func starterJSON(for activityKind: WidgetObjectActivityKind) -> String {
        switch supportedKind(from: activityKind) {
        case .multipleChoice:
            return singleQuestionStarterJSON(for: .multipleChoice)
        case .fillInTheBlank:
            return singleQuestionStarterJSON(for: .fillInTheBlank)
        case .builtInInteractive, .unknown:
            return singleQuestionStarterJSON(for: .multipleChoice)
        }
    }

    private static func supportedKind(from activityKind: WidgetObjectActivityKind) -> WidgetObjectActivityKind {
        switch activityKind {
        case .multipleChoice, .fillInTheBlank:
            return activityKind
        case .builtInInteractive, .unknown:
            return .multipleChoice
        }
    }

    private static func sourceHeader(
        for intent: WidgetMathtivityPromptIntent,
        kind: WidgetObjectActivityKind
    ) -> String {
        switch intent {
        case .create, .createBellRingerExitTicket:
            return "Single-question starter JSON structure for \(kind.displayName):"
        case .remix:
            return "Existing JSON mathtivity to revise:"
        }
    }

    private static func workflowInstructions(for intent: WidgetMathtivityPromptIntent) -> String {
        switch intent {
        case .create, .createBellRingerExitTicket:
            return [
                "Generate exactly one question in the questions array. This payload will be appended dynamically to a bell-ringer or exit-ticket bank.",
                "Set pedagogicalWorkflow to \"bellRingerExitTicket\".",
                "Include usageTracking with lastUsedDate as null and associatedClass as null so MathBoard can avoid repeating questions across periods.",
                "Keep the activity scoreable unless I explicitly ask for a demo-only activity."
            ].joined(separator: "\n")
        case .remix:
            return "Preserve scoring, pedagogicalWorkflow, usageTracking, and assessmentConfiguration unless I ask to change them."
        }
    }

    private static func singleQuestionStarterJSON(for activityKind: WidgetObjectActivityKind) -> String {
        switch supportedKind(from: activityKind) {
        case .multipleChoice:
            return #"""
            {
              "schemaVersion": 1,
              "widgetId": "single-question-multiple-choice-template",
              "activity": "multipleChoice",
              "title": "Bell Ringer",
              "description": "Single-question warmup or exit-ticket payload.",
              "learningObjective": "Students answer one focused check for understanding.",
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
                  "prompt": "Replace this prompt with one focused question.",
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
                  "correctFeedback": "Correct.",
                  "incorrectFeedback": "Check the inverse operations.",
                  "explanation": "Subtract 3 from both sides, then divide by 2."
                }
              ]
            }
            """#
        case .fillInTheBlank:
            return #"""
            {
              "schemaVersion": 1,
              "widgetId": "single-question-fill-in-the-blank-template",
              "activity": "fillInTheBlank",
              "title": "Exit Ticket",
              "description": "Single-question warmup or exit-ticket payload.",
              "learningObjective": "Students complete one focused short response.",
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
                  "prompt": "Solve for x.",
                  "expression": "2x + 3 = 11",
                  "blanks": [
                    {
                      "id": "x",
                      "label": "x",
                      "kind": "numeric",
                      "acceptedAnswers": ["4"],
                      "tolerance": 0.0001
                    }
                  ],
                  "hints": [
                    "Subtract 3 from both sides.",
                    "Divide by 2."
                  ],
                  "correctFeedback": "Correct.",
                  "incorrectFeedback": "Check the inverse operations.",
                  "explanation": "x = 4."
                }
              ]
            }
            """#
        case .builtInInteractive, .unknown:
            return singleQuestionStarterJSON(for: .multipleChoice)
        }
    }

    private static func contract(for activityKind: WidgetObjectActivityKind) -> String {
        switch supportedKind(from: activityKind) {
        case .multipleChoice:
            return [
                "- activity must be \"multipleChoice\".",
                "- Each question needs id, prompt, optional expression, choices, hints, correctFeedback, incorrectFeedback, explanation, optional difficulty, and optional skillTag.",
                "- Each question's choices array should have 2 to 6 choices with id, label, and isCorrect.",
                "- Mark exactly one choice per question with isCorrect: true.",
                "- Distractors should be plausible and tied to common student errors.",
                "- Keep feedback short, student-safe, and specific to the misconception."
            ].joined(separator: "\n")
        case .fillInTheBlank:
            return [
                "- activity must be \"fillInTheBlank\".",
                "- Each question needs id, prompt, optional expression, blanks, hints, correctFeedback, incorrectFeedback, explanation, optional difficulty, and optional skillTag.",
                "- Use blanks instead of choices. Each blank needs id, label, kind, and acceptedAnswers.",
                "- To show two blanks as a stacked fraction, define both blanks normally and add responseLayout with type \"fraction\", optional label, numeratorBlankId, and denominatorBlankId.",
                "- kind must be \"numeric\" or \"text\".",
                "- Numeric blanks may include tolerance. Use tolerance only when equivalent decimal answers should be accepted.",
                "- Text blanks may include caseSensitive. Default to false unless capitalization matters.",
                "- Put every expected student response in acceptedAnswers, including common equivalent forms."
            ].joined(separator: "\n")
        case .builtInInteractive, .unknown:
            return contract(for: .multipleChoice)
        }
    }
}
