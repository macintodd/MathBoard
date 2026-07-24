//
//  WidgetMathTextView.swift
//  WidgetEngine
//
//  Shared math text rendering for native widgets.
//

import SwiftUI
@_spi(Textual) import SwiftUIMath

struct WidgetMathTextView: View {
    let source: String
    var fontSize: CGFloat
    var weight: Font.Weight = .bold
    var fallbackDesign: Font.Design = .rounded
    var foregroundColor: Color
    var alignment: TextAlignment = .center
    var lineLimit: Int? = nil
    var minimumScaleFactor: CGFloat = 0.7
    var mathFontSizeMultiplier: CGFloat = 1

    @State private var renderMode: RenderMode = .pending

    private var mathFont: Math.Font {
        Math.Font(name: .latinModern, size: fontSize * mathFontSizeMultiplier)
    }

    var body: some View {
        Group {
            switch renderMode {
            case .math(let latex):
                Math(latex)
                    .mathTypesettingStyle(.display)
                    .mathFont(mathFont)
                    .foregroundStyle(foregroundColor)
            case .plain, .pending:
                fallbackText
            }
        }
        .onAppear(perform: resolveRenderMode)
        .onChange(of: source) { _, _ in
            resolveRenderMode()
        }
        .onChange(of: fontSize) { _, _ in
            resolveRenderMode()
        }
        .onChange(of: mathFontSizeMultiplier) { _, _ in
            resolveRenderMode()
        }
    }

    private var fallbackText: some View {
        Text(source)
            .font(.system(size: fontSize, weight: weight, design: fallbackDesign))
            .foregroundStyle(foregroundColor)
            .multilineTextAlignment(alignment)
            .lineLimit(lineLimit)
            .minimumScaleFactor(minimumScaleFactor)
    }

    private func resolveRenderMode() {
        let normalizedSource = NormalizedMathSource(source)
        guard normalizedSource.shouldRenderAsMath else {
            renderMode = .plain
            return
        }

        let bounds = Math.typographicBounds(
            for: normalizedSource.latex,
            fitting: ProposedViewSize(width: 100_000, height: 100_000),
            font: mathFont,
            style: .display
        )
        renderMode = bounds.size.width > 0 ? .math(normalizedSource.latex) : .plain
    }
}

private enum RenderMode: Equatable {
    case pending
    case plain
    case math(String)
}

private struct NormalizedMathSource {
    let latex: String
    let shouldRenderAsMath: Bool

    init(_ source: String) {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let unwrapped = Self.unwrappedMathDelimiter(trimmed)
        latex = Self.normalizedLaTeX(unwrapped.text)
        shouldRenderAsMath = (unwrapped.wasDelimited || Self.looksLikeMath(unwrapped.text))
            && !Self.isPlainNumericLabel(unwrapped.text)
    }

    private static func unwrappedMathDelimiter(_ source: String) -> (text: String, wasDelimited: Bool) {
        if source.hasPrefix("$$"), source.hasSuffix("$$"), source.count >= 4 {
            return (String(source.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines), true)
        }

        if source.hasPrefix("\\("), source.hasSuffix("\\)"), source.count >= 4 {
            return (String(source.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines), true)
        }

        if source.hasPrefix("$"), source.hasSuffix("$"), source.count >= 2 {
            return (String(source.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines), true)
        }

        return (source, false)
    }

    private static func looksLikeMath(_ source: String) -> Bool {
        guard !source.isEmpty else { return false }

        let mathCharacters = CharacterSet(charactersIn: #"0123456789\^_=+-*/()[]{}×÷√π"#)
        let hasMathCharacter = source.unicodeScalars.contains { mathCharacters.contains($0) }
        guard hasMathCharacter else { return false }

        let textWithoutCommands = source.replacingOccurrences(
            of: #"\\[A-Za-z]+"#,
            with: "",
            options: .regularExpression
        )
        let letterRuns = textWithoutCommands.split { !$0.isLetter }
        return !letterRuns.contains { $0.count > 2 }
    }

    private static func normalizedLaTeX(_ source: String) -> String {
        let withoutSizingDelimiters = source
            .replacingOccurrences(of: "\\left", with: "")
            .replacingOccurrences(of: "\\right", with: "")
        return normalizedUnaryMinus(withoutSizingDelimiters)
    }

    private static func normalizedUnaryMinus(_ source: String) -> String {
        var result = ""
        var previousNonWhitespace: Character?

        for character in source {
            if character == "-", isUnaryMinusContext(previousNonWhitespace) {
                result += "{-}"
            } else {
                result.append(character)
            }

            if !character.isWhitespace {
                previousNonWhitespace = character
            }
        }

        return result
    }

    private static func isUnaryMinusContext(_ previousNonWhitespace: Character?) -> Bool {
        guard let previousNonWhitespace else { return true }
        switch previousNonWhitespace {
        case "=", "(", "[", "{", "+", "-", "*", "/", "×", "÷", "^":
            return true
        default:
            return false
        }
    }

    private static func isPlainNumericLabel(_ source: String) -> Bool {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^[+-]?(?:\d+|\d*\.\d+)$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }
}
