//
//  MathInputKeyboardView.swift
//  MathBoardCore - GraphCalculator module
//
//  Shared math input keyboard surfaces for hosts that need graph-calculator
//  style entry without depending on the graph calculator state or workflow.
//

import SwiftUI

public struct MathInputKeyboardView: View {
    public enum Profile: Equatable, Sendable {
        case numericAnswer
        case alphanumericAnswer
        case graphExpression
    }

    private enum Page: Equatable {
        case numeric
        case alphabet
        case graph
    }

    private enum KeyAction: Equatable {
        case insert(String)
        case deleteBackward
        case clear
        case returnKey
        case showNumbers
        case showAlphabet
        case moveLeft
        case moveRight
    }

    private struct Key: Identifiable, Equatable {
        var id: String { "\(label)-\(action)-\(width)" }
        let label: String
        var action: KeyAction
        var style: KeyStyle = .plain
        var width: CGFloat = 1
        var icon: String?
    }

    private enum KeyStyle {
        case plain
        case number
        case utility
        case returnKey
    }

    private let profile: Profile
    private let onInsert: (String) -> Void
    private let onDelete: () -> Void
    private let onClear: () -> Void
    private let onReturn: () -> Void
    private let onMoveLeft: () -> Void
    private let onMoveRight: () -> Void

    @State private var page: Page

    public init(
        profile: Profile,
        onInsert: @escaping (String) -> Void,
        onDelete: @escaping () -> Void,
        onClear: @escaping () -> Void = {},
        onReturn: @escaping () -> Void,
        onMoveLeft: @escaping () -> Void = {},
        onMoveRight: @escaping () -> Void = {}
    ) {
        self.profile = profile
        self.onInsert = onInsert
        self.onDelete = onDelete
        self.onClear = onClear
        self.onReturn = onReturn
        self.onMoveLeft = onMoveLeft
        self.onMoveRight = onMoveRight
        _page = State(initialValue: Self.initialPage(for: profile))
    }

    public var body: some View {
        GeometryReader { proxy in
            let rows = rows(for: page)
            let metrics = keypadMetrics(for: proxy.size, rows: rows)

            VStack(spacing: metrics.spacing) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: metrics.spacing) {
                        ForEach(row) { key in
                            keyButton(key, metrics: metrics)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, metrics.verticalPadding)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .background(MathInputKeyboardTheme.keypad)
        .onChange(of: profile) { _, newProfile in
            page = Self.initialPage(for: newProfile)
        }
    }

    private static func initialPage(for profile: Profile) -> Page {
        switch profile {
        case .numericAnswer:
            return .numeric
        case .alphanumericAnswer:
            return .alphabet
        case .graphExpression:
            return .graph
        }
    }

    private func rows(for page: Page) -> [[Key]] {
        switch page {
        case .numeric:
            return numericAnswerRows
        case .alphabet:
            return alphabetRows
        case .graph:
            return graphExpressionRows
        }
    }

    private var numericAnswerRows: [[Key]] {
        [
            [
                number("7"), number("8"), number("9"),
                plain("/", insert: "/"),
                utility("⌫", .deleteBackward, width: 2)
            ],
            [
                number("4"), number("5"), number("6"),
                plain("-", insert: "-"),
                utility("Clear", .clear, width: 2)
            ],
            [
                number("1"), number("2"), number("3"),
                plain(".", insert: "."),
                utility("←", .moveLeft),
                utility("→", .moveRight)
            ],
            [
                number("0", width: 2),
                plain("+", insert: "+"),
                plain("=", insert: "="),
                Key(label: "Return", action: .returnKey, style: .returnKey, width: 2, icon: "checkmark.circle.fill")
            ]
        ]
    }

    private var alphabetRows: [[Key]] {
        [
            "qwertyuiop".map { plain(String($0), insert: String($0)) },
            "asdfghjkl".map { plain(String($0), insert: String($0)) },
            [
                utility("123", .showNumbers, width: 1.4),
                plain("z", insert: "z"), plain("x", insert: "x"), plain("c", insert: "c"),
                plain("v", insert: "v"), plain("b", insert: "b"), plain("n", insert: "n"),
                plain("m", insert: "m"),
                utility("⌫", .deleteBackward, width: 1.6)
            ],
            [
                plain("(", insert: "("), plain(")", insert: ")"),
                plain("/", insert: "/", width: 1.4),
                plain("^", insert: "^"),
                plain("√", insert: "sqrt("),
                plain("π", insert: "pi"),
                utility("←", .moveLeft),
                utility("→", .moveRight),
                plain("Space", insert: " ", width: 1.6),
                Key(label: "Return", action: .returnKey, style: .returnKey, width: 2, icon: "checkmark.circle.fill")
            ]
        ]
    }

    private var graphExpressionRows: [[Key]] {
        [
            [
                plain("x", insert: "x"), plain("y", insert: "y"),
                plain("a²", insert: "^2"), plain("aᵇ", insert: "^"),
                number("7"), number("8"), number("9"),
                plain("÷", insert: "/"), plain("funcs", insert: "f(", width: 2)
            ],
            [
                plain("(", insert: "("), plain(")", insert: ")"),
                plain("<", insert: "<"), plain(">", insert: ">"),
                number("4"), number("5"), number("6"),
                plain("×", insert: "*"),
                utility("←", .moveLeft), utility("→", .moveRight)
            ],
            [
                plain("|a|", insert: "abs("), plain(",", insert: ","),
                plain("≤", insert: "<="), plain("≥", insert: ">="),
                number("1"), number("2"), number("3"),
                plain("−", insert: "-"),
                utility("⌫", .deleteBackward, width: 2)
            ],
            [
                utility("ABC", .showAlphabet), fraction(), plain("√", insert: "sqrt("), plain("π", insert: "pi"),
                number("0"), plain(".", insert: "."), plain("=", insert: "="), plain("+", insert: "+"),
                Key(label: "Return", action: .returnKey, style: .returnKey, width: 2, icon: "return")
            ]
        ]
    }

    private func number(_ label: String, width: CGFloat = 1) -> Key {
        Key(label: label, action: .insert(label), style: .number, width: width)
    }

    private func plain(_ label: String, insert text: String, width: CGFloat = 1) -> Key {
        Key(label: label, action: .insert(text), style: .plain, width: width)
    }

    private func utility(_ label: String, _ action: KeyAction, width: CGFloat = 1) -> Key {
        Key(label: label, action: action, style: .utility, width: width)
    }

    private func fraction(width: CGFloat = 1) -> Key {
        Key(label: "a/b", action: .insert("/"), style: .plain, width: width)
    }

    private func keypadMetrics(for size: CGSize, rows: [[Key]]) -> KeypadMetrics {
        let spacing: CGFloat = 7
        let horizontalPadding: CGFloat = 10
        let verticalPadding: CGFloat = 9
        let columns = max(rows.map { row in row.reduce(CGFloat(0)) { $0 + $1.width } }.max() ?? 1, 1)
        let maxRowKeyCount = max(rows.map(\.count).max() ?? 1, 1)
        let availableWidth = max(0, size.width - horizontalPadding * 2)
        let availableHeight = max(0, size.height - verticalPadding * 2)
        let columnWidth = max(32, (availableWidth - spacing * CGFloat(maxRowKeyCount - 1)) / columns)
        let rowHeight = min(58, max(38, (availableHeight - spacing * CGFloat(rows.count - 1)) / CGFloat(max(rows.count, 1))))

        return KeypadMetrics(
            columnWidth: columnWidth,
            rowHeight: rowHeight,
            spacing: spacing,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding
        )
    }

    private func keyButton(_ key: Key, metrics: KeypadMetrics) -> some View {
        Button {
            perform(key.action)
        } label: {
            keyLabel(key, metrics: metrics)
        }
        .buttonStyle(MathInputKeyButtonStyle(fill: keyFill(for: key.style), emphasized: key.style == .returnKey))
    }

    @ViewBuilder
    private func keyLabel(_ key: Key, metrics: KeypadMetrics) -> some View {
        let width = metrics.width(for: key.width)

        if key.label == "a/b" {
            VStack(spacing: 1) {
                Text("a")
                Rectangle()
                    .fill(.black.opacity(0.82))
                    .frame(width: min(width * 0.42, 38), height: 1.4)
                Text("b")
            }
            .font(.system(size: min(metrics.rowHeight * 0.32, 17), weight: .semibold, design: .serif))
            .foregroundStyle(.black.opacity(0.88))
            .frame(width: width, height: metrics.rowHeight)
        } else if let icon = key.icon {
            Label(key.label, systemImage: icon)
                .font(.system(size: keyFontSize(for: key.label, metrics: metrics), weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .foregroundStyle(key.style == .returnKey ? .white : .black.opacity(0.88))
                .labelStyle(.titleAndIcon)
                .frame(width: width, height: metrics.rowHeight)
        } else {
            Text(key.label)
                .font(.system(size: keyFontSize(for: key.label, metrics: metrics), weight: .medium, design: .serif))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(key.style == .returnKey ? .white : .black.opacity(0.88))
                .frame(width: width, height: metrics.rowHeight)
        }
    }

    private func keyFontSize(for label: String, metrics: KeypadMetrics) -> CGFloat {
        let base = min(metrics.rowHeight * 0.5, metrics.columnWidth * 0.66)
        if label.count > 5 {
            return min(base * 0.72, 18)
        }
        if label.count > 3 {
            return min(base * 0.82, 20)
        }
        return min(max(base, 17), 30)
    }

    private func keyFill(for style: KeyStyle) -> Color {
        switch style {
        case .plain:
            return Color.white
        case .number:
            return Color(red: 0.77, green: 0.77, blue: 0.76)
        case .utility:
            return Color(red: 0.84, green: 0.85, blue: 0.86)
        case .returnKey:
            return MathInputKeyboardTheme.blue
        }
    }

    private func perform(_ action: KeyAction) {
        switch action {
        case .insert(let text):
            onInsert(text)
        case .deleteBackward:
            onDelete()
        case .clear:
            onClear()
        case .returnKey:
            onReturn()
        case .showNumbers:
            page = .numeric
        case .showAlphabet:
            page = .alphabet
        case .moveLeft:
            onMoveLeft()
        case .moveRight:
            onMoveRight()
        }
    }

    private struct KeypadMetrics {
        let columnWidth: CGFloat
        let rowHeight: CGFloat
        let spacing: CGFloat
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat

        func width(for units: CGFloat) -> CGFloat {
            columnWidth * units + spacing * max(0, units - 1)
        }
    }

    private struct MathInputKeyButtonStyle: ButtonStyle {
        let fill: Color
        let emphasized: Bool

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.black.opacity(emphasized ? 0.22 : 0.16), lineWidth: 1)
                )
                .shadow(color: .black.opacity(configuration.isPressed ? 0.04 : 0.18), radius: configuration.isPressed ? 0 : 1.5, x: 0, y: configuration.isPressed ? 0 : 1)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
        }
    }
}

public struct GraphCalculatorKeypadView: View {
    public enum InputMode: Sendable {
        case numeric
        case alphanumeric
    }

    private let initialMode: InputMode
    private let onInsert: (String) -> Void
    private let onDelete: () -> Void
    private let onReturn: () -> Void
    private let onMoveLeft: () -> Void
    private let onMoveRight: () -> Void

    public init(
        initialMode: InputMode = .numeric,
        onInsert: @escaping (String) -> Void,
        onDelete: @escaping () -> Void,
        onReturn: @escaping () -> Void,
        onMoveLeft: @escaping () -> Void = {},
        onMoveRight: @escaping () -> Void = {}
    ) {
        self.initialMode = initialMode
        self.onInsert = onInsert
        self.onDelete = onDelete
        self.onReturn = onReturn
        self.onMoveLeft = onMoveLeft
        self.onMoveRight = onMoveRight
    }

    public var body: some View {
        MathInputKeyboardView(
            profile: initialMode == .numeric ? .numericAnswer : .alphanumericAnswer,
            onInsert: onInsert,
            onDelete: onDelete,
            onReturn: onReturn,
            onMoveLeft: onMoveLeft,
            onMoveRight: onMoveRight
        )
    }
}

private enum MathInputKeyboardTheme {
    static let keypad = Color(red: 0.90, green: 0.90, blue: 0.89)
    static let blue = Color(red: 0.19, green: 0.47, blue: 0.86)
}

#if DEBUG
#Preview("Math Input Keyboard") {
    MathInputKeyboardView(
        profile: .alphanumericAnswer,
        onInsert: { _ in },
        onDelete: {},
        onClear: {},
        onReturn: {}
    )
    .frame(width: 680, height: 210)
}
#endif
