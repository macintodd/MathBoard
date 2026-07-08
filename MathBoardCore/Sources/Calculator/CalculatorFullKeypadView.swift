//
//  CalculatorFullKeypadView.swift
//  MathBoardCore — Calculator module
//
//  Full TI-84-style keypad used as the primary calculator input surface. Keys
//  needed for class are wired through callbacks; the rest remain visual no-ops
//  so the layout stays familiar without pretending every TI feature exists.
//

import SwiftUI

enum CalculatorKeypadDirection: Equatable {
    case up
    case down
    case left
    case right
}

struct CalculatorFullKeypadView: View {
    @Bindable var state: CalculatorState

    var showsHeader = false
    var keyAction: (CalculatorKeyAction) -> Void = { _ in }
    var graphAction: () -> Void = {}
    var equationAction: () -> Void = {}
    var zoomAction: () -> Void = {}
    var mathAction: () -> Void = {}
    var statAction: () -> Void = {}
    var navigationAction: (CalculatorKeypadDirection) -> Void = { _ in }

    static let keyW: CGFloat = 46
    static let keyH: CGFloat = 40
    static let spacing: CGFloat = 5
    static let padding: CGFloat = 12

    static var width: CGFloat { keyW * 5 + spacing * 4 + padding * 2 }
    static var height: CGFloat {
        let keyRows: CGFloat = 1 + 2 + 7
        return padding * 2 + keyRows * keyH + 9 * spacing
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                header
                Divider()
            }

            VStack(spacing: Self.spacing) {
                keyRow(Self.topFunctionRow)

                HStack(spacing: Self.spacing) {
                    VStack(spacing: Self.spacing) {
                        keyRow(Self.leftClusterRow1)
                        keyRow(Self.leftClusterRow2)
                    }
                    directionPad
                }

                ForEach(Array(Self.mainRows.enumerated()), id: \.offset) { _, row in
                    keyRow(row)
                }
            }
            .padding(Self.padding)
        }
        .background(CalculatorTheme.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.10), lineWidth: 0.5))
        .environment(\.colorScheme, .dark)
        .tint(CalculatorTheme.accent)
    }

    private var header: some View {
        HStack {
            Text("Keypad")
                .font(.headline)
                .foregroundStyle(CalculatorTheme.label)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(CalculatorTheme.surface)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18))
    }

    private func keyRow(_ keys: [FullKey]) -> some View {
        HStack(spacing: Self.spacing) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                keyView(key)
            }
        }
    }

    private func keyView(_ key: FullKey) -> some View {
        Button {
            handle(key)
        } label: {
            Text(key.label)
                .font(.system(size: 15, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    if let second = key.second {
                        Text(second)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(CalculatorTheme.secondFunction)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .padding(.leading, 3)
                            .padding(.top, 1)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let alpha = key.alpha {
                        Text(alpha)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(CalculatorTheme.keypadGreen.opacity(0.95))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .padding(.trailing, 3)
                            .padding(.top, 1)
                    }
                }
        }
        .buttonStyle(CalculatorKeyButtonStyle(fill: keyFill(for: key), minHeight: Self.keyH))
        .frame(width: Self.keyW, height: Self.keyH)
        .disabled(key.command == .noop)
        .opacity(key.command == .noop ? 0.78 : 1)
    }

    private func keyFill(for key: FullKey) -> Color {
        if state.isSecondActive, key.secondCommand != nil {
            return CalculatorTheme.keypadBlue.opacity(0.85)
        }
        if state.isAlphaActive, key.alpha != nil {
            return CalculatorTheme.keypadGreen.opacity(0.85)
        }
        return key.fill ?? CalculatorTheme.keyFill(for: key.style)
    }

    private func handle(_ key: FullKey) {
        let effectiveCommand = effectiveCommand(for: key)
        let consumesModifier = effectiveCommand != .calculator(.toggleSecond)
            && effectiveCommand != .alpha
            && effectiveCommand != .noop

        switch effectiveCommand {
        case .calculator(let action):
            keyAction(action)
        case .graph:
            graphAction()
        case .equation:
            equationAction()
        case .zoom:
            zoomAction()
        case .math:
            mathAction()
        case .stat:
            statAction()
        case .navigate(let direction):
            navigationAction(direction)
        case .angle:
            keyAction(.toggleAngleMode)
        case .alpha:
            state.isAlphaActive.toggle()
            state.isSecondActive = false
        case .noop:
            break
        }

        if consumesModifier {
            state.isSecondActive = false
            state.isAlphaActive = false
        }
    }

    private func effectiveCommand(for key: FullKey) -> FullKeyCommand {
        if state.isSecondActive, let secondCommand = key.secondCommand {
            return secondCommand
        }
        return key.command
    }

    private var directionPad: some View {
        let blockW = Self.keyW * 2 + Self.spacing
        let blockH = Self.keyH * 2 + Self.spacing
        return ZStack {
            directionKey("arrow.up", .up).offset(y: -blockH / 2 + 17)
            directionKey("arrow.down", .down).offset(y: blockH / 2 - 17)
            directionKey("arrow.left", .left).offset(x: -blockW / 2 + 19)
            directionKey("arrow.right", .right).offset(x: blockW / 2 - 19)
        }
        .frame(width: blockW, height: blockH)
    }

    private func directionKey(_ systemName: String, _ direction: CalculatorKeypadDirection) -> some View {
        Button { navigationAction(direction) } label: {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
        }
        .buttonStyle(CalculatorKeyButtonStyle(fill: CalculatorTheme.keyFill(for: .modifier), minHeight: 30))
        .frame(width: 32, height: 30)
    }

    private struct FullKey: Equatable {
        let label: String
        let second: String?
        let alpha: String?
        let command: FullKeyCommand
        let secondCommand: FullKeyCommand?
        let style: CalculatorKeyStyle
        var fill: Color? = nil
    }

    private enum FullKeyCommand: Equatable {
        case calculator(CalculatorKeyAction)
        case graph
        case equation
        case zoom
        case math
        case stat
        case navigate(CalculatorKeypadDirection)
        case angle
        case alpha
        case noop
    }

    private static func dec(_ label: String, second: String? = nil, alpha: String? = nil, fill: Color? = nil) -> FullKey {
        FullKey(label: label, second: second, alpha: alpha, command: .noop, secondCommand: nil, style: .function, fill: fill)
    }

    private static func cmd(
        _ label: String,
        _ command: FullKeyCommand,
        _ style: CalculatorKeyStyle,
        second: String? = nil,
        secondCommand: FullKeyCommand? = nil,
        alpha: String? = nil,
        fill: Color? = nil
    ) -> FullKey {
        FullKey(label: label, second: second, alpha: alpha, command: command, secondCommand: secondCommand, style: style, fill: fill)
    }

    private static func act(
        _ label: String,
        _ action: CalculatorKeyAction,
        _ style: CalculatorKeyStyle,
        second: String? = nil,
        secondAction: CalculatorKeyAction? = nil,
        alpha: String? = nil,
        fill: Color? = nil
    ) -> FullKey {
        cmd(
            label,
            .calculator(action),
            style,
            second: second,
            secondCommand: secondAction.map { .calculator($0) },
            alpha: alpha,
            fill: fill
        )
    }

    private static func digit(_ label: String, second: String? = nil) -> FullKey {
        act(label, .insert(label), .digit, second: second)
    }

    private static let topFunctionRow: [FullKey] = [
        cmd("y=", .equation, .function, second: "statplot"),
        dec("window", second: "tblset"),
        cmd("zoom", .zoom, .function, second: "format"),
        dec("trace", second: "calc", alpha: "F4"),
        cmd("graph", .graph, .action, second: "table")
    ]

    private static let leftClusterRow1: [FullKey] = [
        act("2nd", .toggleSecond, .modifier, fill: CalculatorTheme.keypadBlue),
        cmd("mode", .angle, .modifier, second: "quit"),
        act("del", .deleteBackward, .action, second: "ins")
    ]

    private static let leftClusterRow2: [FullKey] = [
        cmd("alpha", .alpha, .modifier, second: "A-lock", fill: CalculatorTheme.keypadGreen),
        act("X,T,θ,n", .insert("x"), .function, second: "link"),
        cmd("stat", .stat, .function, second: "list")
    ]

    private static let mainRows: [[FullKey]] = [
        [cmd("math", .math, .function, second: "test", alpha: "A"), dec("apps", second: "angle", alpha: "B"), dec("prgm", second: "draw", alpha: "C"), dec("vars", second: "distr"), act("clear", .clear, .action)],
        [act("x⁻¹", .insert("^-1"), .function, second: "matrix", alpha: "D"), act("sin", .insert("sin("), .function, second: "sin⁻¹", secondAction: .insert("asin("), alpha: "E"), act("cos", .insert("cos("), .function, second: "cos⁻¹", secondAction: .insert("acos("), alpha: "F"), act("tan", .insert("tan("), .function, second: "tan⁻¹", secondAction: .insert("atan("), alpha: "G"), act("^", .insert("^"), .function, second: "π", secondAction: .insert("pi"))],
        [act("x²", .insert("^2"), .function, second: "√", secondAction: .insert("sqrt(")), act(",", .insert(","), .function, second: "EE", secondAction: .insert("e")), act("(", .insert("("), .function, second: "{"), act(")", .insert(")"), .function, second: "}"), act("÷", .insert("/"), .operator, second: "e", secondAction: .insert("e"))],
        [act("log", .insert("log("), .function, second: "10ˣ", secondAction: .insert("10^(")), digit("7", second: "u"), digit("8", second: "v"), digit("9", second: "w"), act("×", .insert("*"), .operator, second: "[")],
        [act("ln", .insert("ln("), .function, second: "eˣ", secondAction: .insert("e^(")), digit("4", second: "L4"), digit("5", second: "L5"), digit("6", second: "L6"), act("−", .insert("-"), .operator, second: "]")],
        [dec("sto→", second: "rcl"), digit("1", second: "L1"), digit("2", second: "L2"), digit("3", second: "L3"), act("+", .insert("+"), .operator, second: "mem")],
        [dec("on", second: "off"), digit("0", second: "catalog"), act(".", .insert("."), .digit, second: "i"), act("(−)", .insert("-"), .operator, second: "ans", secondAction: .insert("ans")), act("enter", .evaluate, .action, second: "entry")]
    ]
}

#if DEBUG
#Preview("Full keypad") {
    CalculatorFullKeypadView(state: {
        CalculatorState(store: UserDefaults(suiteName: "preview.fullkeypad")!)
    }())
    .frame(width: CalculatorFullKeypadView.width, height: CalculatorFullKeypadView.height)
    .padding()
    .background(Color(white: 0.9))
}
#endif
