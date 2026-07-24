//
//  LaTeXEditorView.swift
//  TextEngine
//

import CoreGraphics
import Foundation
import SwiftUI
@_spi(Textual) import SwiftUIMath

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public struct LaTeXEditorResult: Hashable, Sendable {
    public var latexSource: String
    public var pngData: Data
    public var displaySize: CGSize

    public init(latexSource: String, pngData: Data, displaySize: CGSize) {
        self.latexSource = latexSource
        self.pngData = pngData
        self.displaySize = displaySize
    }
}

public struct LaTeXEditorView: View {
    private let initialSource: String
    private let submitTitle: String
    private let onSave: (LaTeXEditorResult) -> Void
    private let onCancel: () -> Void

    @State private var source: String
    @State private var fontSize: CGFloat
    @State private var sourceSelection: TextSelection?
    #if os(iOS)
    @State private var sourceNSRange = NSRange(location: 0, length: 0)
    #endif

    public init(
        initialSource: String = "",
        fontSize: CGFloat = 28,
        submitTitle: String = "Insert",
        onSave: @escaping (LaTeXEditorResult) -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        self.initialSource = initialSource
        self.submitTitle = submitTitle
        self.onSave = onSave
        self.onCancel = onCancel
        _source = State(initialValue: initialSource)
        _fontSize = State(initialValue: fontSize)
        #if os(iOS)
        _sourceNSRange = State(initialValue: NSRange(location: initialSource.utf16.count, length: 0))
        #endif
    }

    public var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 0) {
                    editorWorkspace
                    Divider()
                    keypad
                }

                LaTeXAlphaGreekKeypadView { command in
                    handle(command)
                }
            }
            .padding(12)
        }
        .frame(width: 930)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 10)
    }

    private var titleBar: some View {
        HStack {
            Button("Cancel", role: .cancel, action: onCancel)
            Spacer()
            Label("LaTeX", systemImage: "function")
                .font(.headline)
            Spacer()
            Button(submitTitle) {
                let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let result = LaTeXImageRenderer.result(for: trimmed, fontSize: fontSize) else { return }
                onSave(result)
            }
            .buttonStyle(.borderedProminent)
            .disabled(source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var editorWorkspace: some View {
        HStack(spacing: 12) {
            VStack(spacing: 10) {
                previewPane
                editorPane
            }

            fontSizeControl
        }
    }

    private var previewPane: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.84))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

            if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("f(x)")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.tertiary)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    LaTeXPreviewEquation(source: source, fontSize: fontSize)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 26)
                        .frame(maxWidth: .infinity, minHeight: 132)
                }
            }
        }
        .frame(height: 152)
    }

    private var editorPane: some View {
        #if os(iOS)
        NoKeyboardLaTeXSourceEditor(text: $source, selectedRange: $sourceNSRange, fontSize: 18)
            .overlay(alignment: .topLeading) {
                if source.isEmpty {
                    Text("LaTeX source")
                        .font(.system(size: 18, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 88)
            .background(Color.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        #else
        TextEditor(text: $source, selection: $sourceSelection)
            .font(.system(size: 18, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(8)
            .overlay(alignment: .topLeading) {
                if source.isEmpty {
                    Text("LaTeX source")
                        .font(.system(size: 18, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
        .frame(height: 88)
        .background(Color.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        #endif
    }

    private var fontSizeControl: some View {
        VStack(spacing: 8) {
            Text("\(Int(fontSize))")
                .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Color(red: 0.12, green: 0.30, blue: 0.44))

            Text("pt")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Slider(value: $fontSize, in: 12...96)
                .rotationEffect(.degrees(-90))
                .frame(width: 150, height: 34)
                .padding(.vertical, 58)

            Image(systemName: "textformat.size")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: 54)
        .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var keypad: some View {
        LaTeXFullKeypadView { command in
            handle(command)
        }
    }

    private func handle(_ command: LaTeXKeyCommand) {
        switch command {
        case .insert(let text, let cursorOffset):
            insert(text, cursorOffset: cursorOffset)
        case .deleteBackward:
            deleteBackward()
        case .clear:
            source.removeAll()
            setInsertionPoint(source.startIndex)
        case .newLine:
            insert("\\\\\n")
        case .tabToNextSlot:
            tabToNextSlot()
        }
    }

    private func insert(_ text: String, cursorOffset: Int? = nil) {
        let selectedRange = currentSelectedRange()
        let insertionStart = selectedRange.lowerBound
        source.replaceSubrange(selectedRange, with: text)

        let offset = cursorOffset ?? text.count
        let insertionPoint = source.index(insertionStart, offsetBy: offset, limitedBy: source.endIndex) ?? source.endIndex
        setInsertionPoint(insertionPoint)
    }

    private func deleteBackward() {
        let selectedRange = currentSelectedRange()
        if !selectedRange.isEmpty {
            source.removeSubrange(selectedRange)
            setInsertionPoint(selectedRange.lowerBound)
            return
        }

        guard selectedRange.lowerBound > source.startIndex else { return }
        let previousIndex = source.index(before: selectedRange.lowerBound)
        source.removeSubrange(previousIndex..<selectedRange.lowerBound)
        setInsertionPoint(previousIndex)
    }

    private func currentSelectedRange() -> Range<String.Index> {
        #if os(iOS)
        return stringRange(for: sourceNSRange) ?? source.endIndex..<source.endIndex
        #else
        guard let sourceSelection else {
            return source.endIndex..<source.endIndex
        }

        switch sourceSelection.indices {
        case .selection(let range):
            return range
        case .multiSelection(let ranges):
            return ranges.ranges.first ?? source.endIndex..<source.endIndex
        @unknown default:
            return source.endIndex..<source.endIndex
        }
        #endif
    }

    private func tabToNextSlot() {
        let selectedRange = currentSelectedRange()
        let searchStart = selectedRange.upperBound
        let rightRange = searchStart..<source.endIndex
        let target = source[rightRange].firstIndex(of: "{")
            ?? source.firstIndex(of: "{")

        guard let target else { return }
        let insertionPoint = source.index(after: target)
        setInsertionPoint(insertionPoint)
    }

    private func setInsertionPoint(_ index: String.Index) {
        #if os(iOS)
        sourceNSRange = nsRange(for: index..<index)
        #else
        sourceSelection = TextSelection(insertionPoint: index)
        #endif
    }

    #if os(iOS)
    private func stringRange(for nsRange: NSRange) -> Range<String.Index>? {
        Range(nsRange, in: source)
    }

    private func nsRange(for range: Range<String.Index>) -> NSRange {
        NSRange(range, in: source)
    }
    #endif
}

public enum LaTeXImageRenderer {
    @MainActor
    public static func result(for source: String, fontSize: CGFloat) -> LaTeXEditorResult? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let rendered = renderPNGData(for: trimmed, fontSize: fontSize) else {
            return nil
        }
        return LaTeXEditorResult(
            latexSource: trimmed,
            pngData: rendered.pngData,
            displaySize: rendered.displaySize
        )
    }

    @MainActor
    public static func renderPNGData(for source: String, fontSize: CGFloat) -> (pngData: Data, displaySize: CGSize)? {
        let mathFont = Math.Font(name: .latinModern, size: fontSize)
        let bounds = Math.typographicBounds(
            for: source,
            fitting: ProposedViewSize(width: 10_000, height: 10_000),
            font: mathFont,
            style: .display
        )
        let measured = bounds.size.width > 0 && bounds.size.height > 0
            ? bounds.size
            : CGSize(width: max(fontSize * 4, 180), height: max(fontSize * 1.6, 64))
        let padding = max(fontSize * 0.45, 16)
        let displaySize = CGSize(
            width: ceil(measured.width + padding * 2),
            height: ceil(measured.height + padding * 2)
        )
        let content = LaTeXPreviewEquation(source: source, fontSize: fontSize)
            .foregroundStyle(Color.black)
            .padding(padding)
            .frame(width: displaySize.width, height: displaySize.height)
            .background(Color.clear)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(displaySize)

        #if os(iOS)
        guard let image = renderer.uiImage,
              let data = image.pngData() else {
            return nil
        }
        #elseif os(macOS)
        guard let image = renderer.nsImage,
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        #else
        return nil
        #endif

        return (data, displaySize)
    }
}

private struct LaTeXPreviewEquation: View {
    let source: String
    let fontSize: CGFloat

    private var mathFont: Math.Font {
        Math.Font(name: .latinModern, size: fontSize)
    }

    private var canTypeset: Bool {
        Math.typographicBounds(
            for: source,
            fitting: ProposedViewSize(width: 10_000, height: 10_000),
            font: mathFont,
            style: .display
        ).size.width > 0
    }

    var body: some View {
        if canTypeset {
            Math(source)
                .mathTypesettingStyle(.display)
                .mathFont(mathFont)
                .fixedSize()
        } else {
            Text(source)
                .font(.system(size: max(fontSize * 0.55, 14), design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

#if os(iOS)
private struct NoKeyboardLaTeXSourceEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    var fontSize: CGFloat

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textColor = UIColor.label
        textView.tintColor = UIColor.systemBlue
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.inputView = UIView(frame: .zero)
        textView.inputAssistantItem.leadingBarButtonGroups = []
        textView.inputAssistantItem.trailingBarButtonGroups = []
        textView.addInteraction(UIScribbleInteraction(delegate: context.coordinator))
        textView.writingToolsBehavior = .none
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text {
            textView.text = text
        }

        let clampedRange = clamped(selectedRange, to: textView.textStorage.length)
        if textView.selectedRange != clampedRange {
            textView.selectedRange = clampedRange
        }
        textView.scrollRangeToVisible(clampedRange)

        textView.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.reloadInputViews()

        if textView.window != nil && !textView.isFirstResponder {
            DispatchQueue.main.async {
                textView.becomeFirstResponder()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, selectedRange: $selectedRange)
    }

    private func clamped(_ range: NSRange, to length: Int) -> NSRange {
        let location = min(max(range.location, 0), length)
        let maxLength = max(length - location, 0)
        return NSRange(location: location, length: min(max(range.length, 0), maxLength))
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIScribbleInteractionDelegate {
        @Binding var text: String
        @Binding var selectedRange: NSRange

        init(text: Binding<String>, selectedRange: Binding<NSRange>) {
            _text = text
            _selectedRange = selectedRange
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
            selectedRange = textView.selectedRange
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            selectedRange = textView.selectedRange
        }

        func scribbleInteraction(_ interaction: UIScribbleInteraction, shouldBeginAt location: CGPoint) -> Bool {
            false
        }
    }
}
#endif

private enum LaTeXKeyCommand: Equatable {
    case insert(String, cursorOffset: Int? = nil)
    case deleteBackward
    case clear
    case newLine
    case tabToNextSlot
}

private enum LaTeXKeyStyle: Equatable {
    case function
    case digit
    case `operator`
    case action
    case modifier
}

private struct LaTeXFullKeypadView: View {
    var action: (LaTeXKeyCommand) -> Void

    private static let keyWidth: CGFloat = 78
    private static let keyHeight: CGFloat = 46
    private static let spacing: CGFloat = 6
    private static let padding: CGFloat = 10

    var body: some View {
        VStack(spacing: Self.spacing) {
            Text("LaTeX · Numeric")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity)

            ForEach(Array(Self.rows.enumerated()), id: \.offset) { _, row in
                keyRow(row)
            }
        }
        .padding(Self.padding)
        .frame(width: Self.keyWidth * 6 + Self.spacing * 5 + Self.padding * 2)
        .background(Color(red: 0.92, green: 0.97, blue: 1.0).opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func keyRow(_ keys: [LaTeXFullKey]) -> some View {
        HStack(spacing: Self.spacing) {
            ForEach(keys) { key in
                keyView(key)
            }
        }
    }

    private func keyView(_ key: LaTeXFullKey) -> some View {
        Button {
            handle(key)
        } label: {
            ZStack {
                Text(key.label)
                    .font(.system(size: key.primaryFontSize, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .foregroundStyle(keyForeground(for: key))

                if let second = key.secondLabel {
                    Text(second)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .foregroundStyle(Color(red: 0.09, green: 0.42, blue: 0.88))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.leading, 7)
                        .padding(.top, 5)
                }

                if let alpha = key.alphaLabel {
                    Text(alpha)
                        .font(.system(size: 12, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .foregroundStyle(Color(red: 0.12, green: 0.50, blue: 0.30))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.trailing, 7)
                        .padding(.top, 5)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(LaTeXKeyButtonStyle(fill: keyFill(for: key), stroke: keyStroke(for: key)))
        .frame(width: Self.keyWidth, height: Self.keyHeight)
    }

    private func handle(_ key: LaTeXFullKey) {
        switch key.baseCommand {
        case .emit(let text, let cursorOffset):
            action(.insert(text, cursorOffset: cursorOffset))
        case .deleteBackward:
            action(.deleteBackward)
        case .clear:
            action(.clear)
        case .newLine:
            action(.newLine)
        case .tabToNextSlot:
            action(.tabToNextSlot)
        case .noop, .toggleSecond, .toggleAlpha:
            break
        }
    }

    private func keyFill(for key: LaTeXFullKey) -> Color {
        switch key.style {
        case .function:
            return Color.white.opacity(0.92)
        case .digit:
            return Color.white
        case .operator:
            return Color(red: 0.86, green: 0.94, blue: 1.0)
        case .action:
            return Color(red: 0.18, green: 0.58, blue: 0.95)
        case .modifier:
            return key.label == "alpha"
                ? Color(red: 0.80, green: 0.94, blue: 0.86)
                : Color(red: 0.78, green: 0.89, blue: 1.0)
        }
    }

    private func keyStroke(for key: LaTeXFullKey) -> Color {
        switch key.style {
        case .action:
            return Color.blue.opacity(0.28)
        case .modifier:
            return Color.black.opacity(0.10)
        default:
            return Color.black.opacity(0.08)
        }
    }

    private func keyForeground(for key: LaTeXFullKey) -> Color {
        key.style == .action ? .white : Color(red: 0.08, green: 0.12, blue: 0.18)
    }

    private static func key(
        _ label: String,
        _ command: LaTeXFullKey.Command,
        _ style: LaTeXKeyStyle,
        second: String? = nil,
        secondCommand: LaTeXFullKey.Command? = nil,
        alpha: String? = nil,
        alphaCommand: LaTeXFullKey.Command? = nil
    ) -> LaTeXFullKey {
        LaTeXFullKey(
            label: label,
            baseCommand: command,
            style: style,
            secondLabel: second,
            secondCommand: secondCommand,
            alphaLabel: alpha,
            alphaCommand: alphaCommand
        )
    }

    private static func insert(
        _ label: String,
        _ text: String,
        _ style: LaTeXKeyStyle,
        second: String? = nil,
        secondText: String? = nil,
        cursorOffset: Int? = nil,
        alpha: String? = nil,
        alphaText: String? = nil
    ) -> LaTeXFullKey {
        key(
            label,
            .emit(text, cursorOffset: cursorOffset),
            style,
            second: second,
            secondCommand: secondText.map { .emit($0) },
            alpha: alpha,
            alphaCommand: alphaText.map { .emit($0) }
        )
    }

    private static let rows: [[LaTeXFullKey]] = [
        [
            insert("frac", "\\frac{}{}", .function, cursorOffset: 6),
            insert("sqrt", "\\sqrt{}", .function, cursorOffset: 6),
            insert("system", "\\begin{cases}\n & \\\\\n & \n\\end{cases}", .function, cursorOffset: 16),
            insert("aligned", "\\begin{aligned}\n &= \\\\\n &= \n\\end{aligned}", .function, cursorOffset: 18),
            insert("matrix", "\\begin{bmatrix}\n & \\\\\n & \n\\end{bmatrix}", .function, cursorOffset: 16),
            insert("cases", "\\begin{cases}\n & \\\\\n & \n\\end{cases}", .function, cursorOffset: 16)
        ],
        [
            insert("sum", "\\sum_{}^{}", .function, cursorOffset: 6),
            insert("over", "\\overline{}", .function, cursorOffset: 10),
            insert("under", "\\underline{}", .function, cursorOffset: 11),
            insert("lim", "\\lim_{}", .function, cursorOffset: 6),
            insert("vec", "\\vec{}", .function, cursorOffset: 5),
            insert("hat", "\\hat{}", .function, cursorOffset: 5)
        ],
        [
            insert("sin", "\\sin\\left(  \\right)", .function),
            insert("cos", "\\cos\\left(  \\right)", .function),
            insert("tan", "\\tan\\left(  \\right)", .function),
            insert("log", "\\log\\left(  \\right)", .function),
            insert("ln", "\\ln\\left(  \\right)", .function),
            insert("^", "^{}", .function, cursorOffset: 2)
        ],
        [
            insert("(", "\\left(", .function),
            insert(")", "\\right)", .function),
            insert("{", "{", .function),
            insert("}", "}", .function),
            insert("|x|", "\\left|  \\right|", .function),
            key("tab", .tabToNextSlot, .action)
        ],
        [
            insert("≤", " \\le ", .operator),
            insert("≥", " \\ge ", .operator),
            insert("\\", "\\", .function),
            insert("≠", " \\ne ", .operator),
            insert("≈", " \\approx ", .operator),
            key("del", .deleteBackward, .action)
        ],
        [
            insert(">", " > ", .operator),
            insert("<", " < ", .operator),
            insert("&", "&", .function),
            insert(",", ",", .function),
            key("return", .newLine, .function),
            key("clear", .clear, .action)
        ],
        [
            insert("7", "7", .digit),
            insert("8", "8", .digit),
            insert("9", "9", .digit),
            insert("+", " + ", .operator),
            insert("×", " \\cdot ", .operator),
            insert("=", " = ", .action)
        ],
        [
            insert("4", "4", .digit),
            insert("5", "5", .digit),
            insert("6", "6", .digit),
            insert("−", " - ", .operator),
            insert("÷", " \\div ", .operator),
            insert("±", "\\pm ", .operator)
        ],
        [
            insert("1", "1", .digit),
            insert("2", "2", .digit),
            insert("3", "3", .digit),
            insert(".", ".", .digit),
            insert("0", "0", .digit),
            insert("x²", "^{2}", .function),
        ],
        [
            insert("space", " ", .function),
            insert("°", "^{\\circ}", .function),
            insert("π", "\\pi", .function),
            insert("e", "e", .function),
            insert("i", "i", .function),
            insert("ⁿ√x", "\\sqrt[]{}", .function, cursorOffset: 6)
        ]
    ]
}

private enum LaTeXAlphaGreekMode: Equatable {
    case alpha
    case greek
}

private struct LaTeXAlphaGreekKeypadView: View {
    var action: (LaTeXKeyCommand) -> Void

    @State private var mode: LaTeXAlphaGreekMode = .alpha

    private static let keyWidth: CGFloat = 52
    private static let keyHeight: CGFloat = 58
    private static let spacing: CGFloat = 6
    private static let padding: CGFloat = 10

    var body: some View {
        VStack(spacing: Self.spacing) {
            Text(mode == .alpha ? "Alpha" : "Greek · Geometry")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity)

            ForEach(Array(activeRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: Self.spacing) {
                    ForEach(row) { key in
                        keyView(key)
                    }
                }
            }

            Button {
                mode = mode == .alpha ? .greek : .alpha
            } label: {
                Text(mode == .alpha ? "Greek" : "Alpha")
                    .font(.system(size: 17, weight: .bold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(LaTeXKeyButtonStyle(
                fill: Color(red: 0.82, green: 0.90, blue: 1.0),
                stroke: Color.blue.opacity(0.16)
            ))
            .frame(height: Self.keyHeight)
        }
        .padding(Self.padding)
        .frame(width: Self.keyWidth * 4 + Self.spacing * 3 + Self.padding * 2)
        .background(Color(red: 0.92, green: 0.97, blue: 1.0).opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var activeRows: [[LaTeXFullKey]] {
        mode == .alpha ? Self.alphaRows : Self.greekRows
    }

    private func keyView(_ key: LaTeXFullKey) -> some View {
        Button {
            if case .emit(let text, let cursorOffset) = key.baseCommand {
                action(.insert(text, cursorOffset: cursorOffset))
            }
        } label: {
            VStack(spacing: 3) {
                Text(key.label)
                    .font(.system(size: key.primaryFontSize, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                if let secondLabel = key.secondLabel {
                    Text(secondLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                }
            }
            .foregroundStyle(Color(red: 0.08, green: 0.12, blue: 0.18))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(LaTeXKeyButtonStyle(
            fill: Color.white.opacity(0.92),
            stroke: Color.black.opacity(0.08)
        ))
        .frame(width: Self.keyWidth, height: Self.keyHeight)
    }

    private static func insert(_ label: String, _ text: String, subtitle: String? = nil, cursorOffset: Int? = nil) -> LaTeXFullKey {
        LaTeXFullKey(
            label: label,
            baseCommand: .emit(text, cursorOffset: cursorOffset),
            style: .function,
            secondLabel: subtitle
        )
    }

    private static let alphaRows: [[LaTeXFullKey]] = [
        [insert("y", "y"), insert("f(x)", "f(x)"), insert("g(x)", "g(x)"), insert("h(x)", "h(x)")],
        [insert("x", "x"), insert("z", "z"), insert("t", "t"), insert("n", "n")],
        [insert("a", "a"), insert("b", "b"), insert("c", "c"), insert("d", "d")],
        [insert("e", "e"), insert("f", "f"), insert("g", "g"), insert("h", "h")],
        [insert("i", "i"), insert("j", "j"), insert("k", "k"), insert("L", "L")],
        [insert("m", "m"), insert("p", "p"), insert("q", "q"), insert("r", "r")],
        [insert("s", "s"), insert("u", "u"), insert("v", "v"), insert("w", "w")]
    ]

    private static let greekRows: [[LaTeXFullKey]] = [
        [insert("π", "\\pi"), insert("θ", "\\theta"), insert("φ", "\\phi"), insert("α", "\\alpha")],
        [insert("β", "\\beta"), insert("γ", "\\gamma"), insert("δ", "\\delta"), insert("λ", "\\lambda")],
        [insert("μ", "\\mu"), insert("σ", "\\sigma"), insert("ω", "\\omega"), insert("ρ", "\\rho")],
        [insert("ℝ", "\\mathbb{R}", subtitle: "reals"), insert("ℤ", "\\mathbb{Z}", subtitle: "integers"), insert("ℕ", "\\mathbb{N}", subtitle: "natural"), insert("e", "e", subtitle: "Euler")],
        [insert("°", "^{\\circ}", subtitle: "degree"), insert("△", "\\triangle ", subtitle: "triangle"), insert("∠", "\\angle ", subtitle: "angle"), insert("⊥", "\\perp ", subtitle: "perp")],
        [insert("∥", "\\parallel ", subtitle: "parallel"), insert("ray", "\\overrightarrow{}", subtitle: "overright", cursorOffset: 16), insert("seg", "\\overline{}", subtitle: "overline", cursorOffset: 10), insert("line", "\\overleftrightarrow{}", subtitle: "overleft", cursorOffset: 20)],
        [insert("∪", "\\cup ", subtitle: "union"), insert("∩", "\\cap ", subtitle: "intersect"), insert("⊙", "\\odot ", subtitle: "circle"), insert("≅", "\\cong ", subtitle: "congruent")]
    ]
}

private struct LaTeXFullKey: Identifiable, Equatable {
    enum Command: Equatable {
        case emit(String, cursorOffset: Int? = nil)
        case deleteBackward
        case clear
        case newLine
        case toggleSecond
        case toggleAlpha
        case tabToNextSlot
        case noop
    }

    let id = UUID()
    var label: String
    var baseCommand: Command
    var style: LaTeXKeyStyle
    var secondLabel: String?
    var secondCommand: Command?
    var alphaLabel: String?
    var alphaCommand: Command?

    var primaryFontSize: CGFloat {
        label.count > 5 ? 15 : 18
    }
}

private struct LaTeXKeyButtonStyle: ButtonStyle {
    var fill: Color
    var stroke: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(configuration.isPressed ? 0.04 : 0.10),
                radius: configuration.isPressed ? 1 : 3,
                x: 0,
                y: configuration.isPressed ? 1 : 2
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

#Preview {
    LaTeXEditorView { _ in }
        .padding()
}
