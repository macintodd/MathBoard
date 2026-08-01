//
//  WidgetMathtivityPromptFactory.swift
//  WidgetEngine
//
//  Builds teacher-facing AI prompts from app-owned JSON mathtivity contracts.
//

import Foundation

enum WidgetMathtivityPromptIntent: Equatable, Sendable {
    case create
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
        case .create:
            opening = "You are helping create a MathBoard \(normalizedKind.displayName) JSON mathtivity."
            sourceJSON = starterJSON(for: normalizedKind)
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
            "Preserve scoring rules unless I ask for a demo-only activity.",
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
            return JSONMathtivityCatalog.source(for: JSONMathtivityCatalog.quadraticFeaturesMultipleChoice)
                ?? WidgetSamples.orderOpsActivityJSON
        case .fillInTheBlank:
            return JSONMathtivityCatalog.source(for: JSONMathtivityCatalog.linearEquationFillInTheBlank)
                ?? WidgetSamples.orderOpsActivityJSON
        case .builtInInteractive, .unknown:
            return WidgetSamples.orderOpsActivityJSON
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
        case .create:
            return "Starter JSON structure for \(kind.displayName):"
        case .remix:
            return "Existing JSON mathtivity to revise:"
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
