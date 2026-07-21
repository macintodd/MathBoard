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
    var shuffleQuestions: Bool?
    var shuffleChoices: Bool?
    var maxAttemptsPerQuestion: Int?
    var calculatorAllowed: Bool?

    init(
        scoreMode: WidgetActivityScoreMode? = nil,
        advanceMode: WidgetActivityAdvanceMode? = nil,
        allowRetry: Bool? = nil,
        shuffleQuestions: Bool? = nil,
        shuffleChoices: Bool? = nil,
        maxAttemptsPerQuestion: Int? = nil,
        calculatorAllowed: Bool? = nil
    ) {
        self.scoreMode = scoreMode
        self.advanceMode = advanceMode
        self.allowRetry = allowRetry
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
        choices = try container.decode([WidgetActivityChoice].self, forKey: .choices)
        hints = try container.decodeIfPresent([String].self, forKey: .hints) ?? []
        correctFeedback = try container.decodeIfPresent(String.self, forKey: .correctFeedback)
        incorrectFeedback = try container.decodeIfPresent(String.self, forKey: .incorrectFeedback)
        explanation = try container.decodeIfPresent(String.self, forKey: .explanation)
        difficulty = try container.decodeIfPresent(WidgetActivityDifficulty.self, forKey: .difficulty)
        skillTag = try container.decodeIfPresent(String.self, forKey: .skillTag)
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

    private static func evaluatedMathValue(from source: String) -> Double? {
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

    private static func valuesMatch(_ lhs: Double, _ rhs: Double) -> Bool {
        let tolerance = max(1e-8, max(abs(lhs), abs(rhs)) * 1e-8)
        return abs(lhs - rhs) <= tolerance
    }

    private static func formattedAuditValue(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 1e12 {
            return String(Int64(value))
        }
        return String(format: "%.8g", value)
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
