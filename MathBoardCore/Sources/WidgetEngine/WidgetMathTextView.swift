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

struct WidgetInlineMathTextView: View {
    let source: String
    var fontSize: CGFloat
    var weight: Font.Weight = .bold
    var fallbackDesign: Font.Design = .rounded
    var foregroundColor: Color
    var alignment: TextAlignment = .leading
    var lineLimit: Int? = nil
    var minimumScaleFactor: CGFloat = 0.7
    var mathFontSizeMultiplier: CGFloat = 1

    private var tokens: [WidgetInlineMathToken] {
        WidgetInlineMathParser.tokens(in: source)
    }

    private var containsMath: Bool {
        tokens.contains { token in
            if case .math = token.content { return true }
            return false
        }
    }

    private var mathFont: Math.Font {
        Math.Font(name: .latinModern, size: fontSize * mathFontSizeMultiplier)
    }

    var body: some View {
        if containsMath {
            WidgetInlineMathFlowLayout(alignment: alignment, spacing: 0, lineSpacing: 4) {
                ForEach(tokens) { token in
                    switch token.content {
                    case .plain(let text):
                        Text(text)
                            .font(.system(size: fontSize, weight: weight, design: fallbackDesign))
                            .foregroundStyle(foregroundColor)
                            .fixedSize()
                    case .math(let latex):
                        Math(latex)
                            .mathTypesettingStyle(.display)
                            .mathFont(mathFont)
                            .foregroundStyle(foregroundColor)
                            .fixedSize()
                    }
                }
            }
        } else {
            WidgetMathTextView(
                source: source,
                fontSize: fontSize,
                weight: weight,
                fallbackDesign: fallbackDesign,
                foregroundColor: foregroundColor,
                alignment: alignment,
                lineLimit: lineLimit,
                minimumScaleFactor: minimumScaleFactor,
                mathFontSizeMultiplier: mathFontSizeMultiplier
            )
        }
    }
}

private struct WidgetInlineMathToken: Identifiable {
    enum Content {
        case plain(String)
        case math(String)
    }

    let id: String
    let content: Content
}

private enum WidgetInlineMathParser {
    static func tokens(in source: String) -> [WidgetInlineMathToken] {
        var tokens: [WidgetInlineMathToken] = []
        var plainBuffer = ""
        var index = source.startIndex
        var tokenIndex = 0

        func appendPlain(_ text: String) {
            guard !text.isEmpty else { return }
            for chunk in plainChunks(from: text) {
                tokens.append(WidgetInlineMathToken(id: "plain-\(tokenIndex)", content: .plain(chunk)))
                tokenIndex += 1
            }
        }

        func flushPlainBuffer() {
            appendPlain(plainBuffer)
            plainBuffer = ""
        }

        func appendMath(_ latex: String) {
            let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            tokens.append(WidgetInlineMathToken(id: "math-\(tokenIndex)", content: .math(NormalizedMathSource.normalizedLaTeX(trimmed))))
            tokenIndex += 1
        }

        while index < source.endIndex {
            if source[index...].hasPrefix("$$"),
               let closeRange = source.range(of: "$$", range: source.index(index, offsetBy: 2)..<source.endIndex) {
                flushPlainBuffer()
                appendMath(String(source[source.index(index, offsetBy: 2)..<closeRange.lowerBound]))
                index = closeRange.upperBound
                continue
            }

            if source[index...].hasPrefix("\\("),
               let closeRange = source.range(of: "\\)", range: source.index(index, offsetBy: 2)..<source.endIndex) {
                flushPlainBuffer()
                appendMath(String(source[source.index(index, offsetBy: 2)..<closeRange.lowerBound]))
                index = closeRange.upperBound
                continue
            }

            if source[index] == "$",
               let nextIndex = source.index(index, offsetBy: 1, limitedBy: source.endIndex),
               nextIndex < source.endIndex,
               source[nextIndex] != "$",
               let closeRange = source.range(of: "$", range: nextIndex..<source.endIndex) {
                flushPlainBuffer()
                appendMath(String(source[nextIndex..<closeRange.lowerBound]))
                index = closeRange.upperBound
                continue
            }

            plainBuffer.append(source[index])
            index = source.index(after: index)
        }

        flushPlainBuffer()
        return tokens.isEmpty ? [WidgetInlineMathToken(id: "plain-0", content: .plain(source))] : tokens
    }

    private static func plainChunks(from source: String) -> [String] {
        var chunks: [String] = []
        var chunk = ""

        for character in source {
            chunk.append(character)
            if character.isWhitespace {
                chunks.append(chunk)
                chunk = ""
            }
        }

        if !chunk.isEmpty {
            chunks.append(chunk)
        }

        return chunks
    }
}

private struct WidgetInlineMathFlowLayout: Layout {
    var alignment: TextAlignment = .leading
    var spacing: CGFloat = 0
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrangedRows(for: subviews, maxWidth: availableWidth(for: proposal, subviews: subviews))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.totalHeight(lineSpacing: lineSpacing))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrangedRows(for: subviews, maxWidth: bounds.width)
        var y = bounds.minY

        for row in rows {
            let rowOffset: CGFloat
            switch alignment {
            case .center:
                rowOffset = max(0, (bounds.width - row.width) / 2)
            case .trailing:
                rowOffset = max(0, bounds.width - row.width)
            default:
                rowOffset = 0
            }

            var x = bounds.minX + rowOffset
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + max(0, (row.height - item.size.height) / 2)),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private func availableWidth(for proposal: ProposedViewSize, subviews: Subviews) -> CGFloat {
        if let width = proposal.width, width.isFinite {
            return width
        }
        return subviews.reduce(CGFloat.zero) { partialResult, subview in
            partialResult + subview.sizeThatFits(.unspecified).width + spacing
        }
    }

    private func arrangedRows(for subviews: Subviews, maxWidth: CGFloat) -> [WidgetInlineMathRow] {
        var rows: [WidgetInlineMathRow] = []
        var currentItems: [WidgetInlineMathRow.Item] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0
        let wrappingWidth = maxWidth.isFinite ? maxWidth : availableWidth(for: .unspecified, subviews: subviews)

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let proposedWidth = currentItems.isEmpty ? size.width : currentWidth + spacing + size.width
            if proposedWidth > wrappingWidth, !currentItems.isEmpty {
                rows.append(WidgetInlineMathRow(items: currentItems, width: currentWidth, height: currentHeight))
                currentItems = []
                currentWidth = 0
                currentHeight = 0
            }

            currentItems.append(WidgetInlineMathRow.Item(index: index, size: size))
            currentWidth = currentWidth == 0 ? size.width : currentWidth + spacing + size.width
            currentHeight = max(currentHeight, size.height)
        }

        if !currentItems.isEmpty {
            rows.append(WidgetInlineMathRow(items: currentItems, width: currentWidth, height: currentHeight))
        }

        return rows
    }
}

private struct WidgetInlineMathRow {
    struct Item {
        let index: Int
        let size: CGSize
    }

    let items: [Item]
    let width: CGFloat
    let height: CGFloat
}

private extension Array where Element == WidgetInlineMathRow {
    func totalHeight(lineSpacing: CGFloat) -> CGFloat {
        guard !isEmpty else { return 0 }
        return reduce(CGFloat.zero) { $0 + $1.height } + CGFloat(count - 1) * lineSpacing
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

        let mathCharacters = CharacterSet(charactersIn: #"0123456789\^_=<>+-*/()[]{}×÷√π"#)
        let hasMathCharacter = source.unicodeScalars.contains { mathCharacters.contains($0) }
        let containsLaTeXCommand = source.range(of: #"\\[A-Za-z]+"#, options: .regularExpression) != nil
        guard hasMathCharacter || containsLaTeXCommand else { return false }

        if containsLaTeXCommand {
            return true
        }

        let textWithoutTextCommands = source.replacingOccurrences(
            of: #"\\text\{[^}]*\}"#,
            with: "",
            options: .regularExpression
        )
        let textWithoutCommands = textWithoutTextCommands.replacingOccurrences(
            of: #"\\[A-Za-z]+"#,
            with: "",
            options: .regularExpression
        )
        let letterRuns = textWithoutCommands.split { !$0.isLetter }
        return !letterRuns.contains { $0.count > 2 }
    }

    static func normalizedLaTeX(_ source: String) -> String {
        let withoutSizingDelimiters = source
            .replacingOccurrences(of: "\\left", with: "")
            .replacingOccurrences(of: "\\right", with: "")
        return normalizedUnaryMinus(withoutSizingDelimiters)
    }

    private static func normalizedUnaryMinus(_ source: String) -> String {
        var result = ""
        var previousNonWhitespace: Character?
        var index = source.startIndex

        while index < source.endIndex {
            let character = source[index]
            let nextIndex = source.index(after: index)
            let isAlreadyGroupedUnaryMinus = character == "-"
                && previousNonWhitespace == "{"
                && nextIndex < source.endIndex
                && source[nextIndex] == "}"

            if character == "-", isUnaryMinusContext(previousNonWhitespace), !isAlreadyGroupedUnaryMinus {
                result += "{-}"
            } else {
                result.append(character)
            }

            if !character.isWhitespace {
                previousNonWhitespace = character
            }
            index = nextIndex
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
