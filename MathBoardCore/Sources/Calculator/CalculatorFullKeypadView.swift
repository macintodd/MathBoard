//
//  CalculatorFullKeypadView.swift
//  MathBoardCore — Calculator module
//
//  The full TI-84-style keypad that slides out beside the calculator palette
//  when the user taps the grid button in the graph action row. It mirrors the
//  familiar physical layout so students recognize it, but only the keys the
//  compact graph keypad already provides are wired up — the variable `x`,
//  parentheses, digits, decimal, clear, delete, and the four arithmetic
//  operators. Every other key is present for familiarity and simply does
//  nothing when tapped. All keys use the same dark neumorphic style as the
//  compact keypad (`CalculatorKeyButtonStyle`).
//
//  Editing targets `CalculatorState.selectedGraphEquationID` via
//  `applyGraphKey`, exactly like the compact keypad, so the two stay in sync.
//

import SwiftUI

struct CalculatorFullKeypadView: View {
    @Bindable var state: CalculatorState

    // Fixed key metrics so the 5-column grid and the 2×2 direction pad align
    // perfectly and the panel has a deterministic width.
    static let keyW: CGFloat = 46
    static let keyH: CGFloat = 40
    static let spacing: CGFloat = 5
    static let padding: CGFloat = 12

    /// Full panel width (5 columns + gaps + padding). Used by the host view to
    /// position the slide-out panel beside the palette.
    static var width: CGFloat { keyW * 5 + spacing * 4 + padding * 2 }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: Self.spacing) {
                    keyRow(Self.topFunctionRow)

                    // 2nd/mode/del + alpha/x/stat on the left, arrow pad on
                    // the right — the TI's distinctive top-right cluster.
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
        }
        .background(CalculatorTheme.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.10), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
        .environment(\.colorScheme, .dark)
        .tint(CalculatorTheme.accent)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Keypad")
                .font(.headline)
                .foregroundStyle(CalculatorTheme.label)
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.28)) { state.showFullKeypad = false }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close keypad")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(CalculatorTheme.surface)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18))
    }

    // MARK: - Key rendering

    private func keyRow(_ keys: [FullKey]) -> some View {
        HStack(spacing: Self.spacing) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                keyView(key)
            }
        }
    }

    private func keyView(_ key: FullKey) -> some View {
        Button {
            // Only the wired-up keys act; decorative keys are inert.
            if let action = key.action { state.applyGraphKey(action) }
        } label: {
            Text(key.label)
                .font(.system(size: 15, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                // Fill the key so the 2nd-function overlay lands in its corner.
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
        }
        .buttonStyle(CalculatorKeyButtonStyle(fill: key.fill ?? CalculatorTheme.keyFill(for: key.style), minHeight: Self.keyH))
        .frame(width: Self.keyW, height: Self.keyH)
    }

    /// Inert direction pad: four separate arrow keys in a N/S/E/W compass
    /// diamond, filling the 2×2 block. The keys are small so the diamond fits.
    private var directionPad: some View {
        let blockW = Self.keyW * 2 + Self.spacing
        let blockH = Self.keyH * 2 + Self.spacing
        return ZStack {
            directionKey("arrow.up").offset(y: -blockH / 2 + 17)
            directionKey("arrow.down").offset(y: blockH / 2 - 17)
            directionKey("arrow.left").offset(x: -blockW / 2 + 19)
            directionKey("arrow.right").offset(x: blockW / 2 - 19)
        }
        .frame(width: blockW, height: blockH)
    }

    private func directionKey(_ systemName: String) -> some View {
        Button {} label: {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
        }
        .buttonStyle(CalculatorKeyButtonStyle(fill: CalculatorTheme.keyFill(for: .modifier), minHeight: 30))
        .frame(width: 32, height: 30)
    }

    // MARK: - Layout data

    /// One key on the full keypad. `action == nil` means it's decorative
    /// (present for familiarity, does nothing). `second` is the blue TI-style
    /// "2nd function" label shown in the key's top-left corner.
    private struct FullKey {
        let label: String
        let second: String?
        let action: CalculatorKeyAction?
        let style: CalculatorKeyStyle
        /// Overrides the style-derived fill (used for the blue `2nd` / green
        /// `alpha` keys).
        var fill: Color? = nil
    }

    /// Decorative (non-functional) key.
    private static func dec(_ label: String, second: String? = nil, fill: Color? = nil) -> FullKey {
        FullKey(label: label, second: second, action: nil, style: .function, fill: fill)
    }
    /// Functional key.
    private static func act(_ label: String, _ action: CalculatorKeyAction, _ style: CalculatorKeyStyle, second: String? = nil) -> FullKey {
        FullKey(label: label, second: second, action: action, style: style)
    }
    /// Functional digit / decimal.
    private static func digit(_ label: String, second: String? = nil) -> FullKey {
        FullKey(label: label, second: second, action: .insert(label), style: .digit)
    }

    private static let topFunctionRow: [FullKey] = [
        dec("y=", second: "statplot"), dec("window", second: "tblset"), dec("zoom", second: "format"),
        dec("trace", second: "calc"), dec("graph", second: "table")
    ]

    private static let leftClusterRow1: [FullKey] =
        [dec("2nd", fill: CalculatorTheme.keypadBlue), dec("mode", second: "quit"), act("del", .deleteBackward, .action, second: "ins")]
    private static let leftClusterRow2: [FullKey] =
        [dec("alpha", second: "A-lock", fill: CalculatorTheme.keypadGreen), act("X,T,θ,n", .insert("x"), .function, second: "link"), dec("stat", second: "list")]

    private static let mainRows: [[FullKey]] = [
        [dec("math", second: "test"), dec("apps", second: "angle"), dec("prgm", second: "draw"), dec("vars", second: "distr"), act("clear", .clear, .action)],
        [dec("x⁻¹", second: "matrix"), dec("sin", second: "sin⁻¹"), dec("cos", second: "cos⁻¹"), dec("tan", second: "tan⁻¹"), dec("^", second: "π")],
        [dec("x²", second: "√"), dec(",", second: "EE"), act("(", .insert("("), .function, second: "{"), act(")", .insert(")"), .function, second: "}"), act("÷", .insert("/"), .operator, second: "e")],
        [dec("log", second: "10ˣ"), digit("7", second: "u"), digit("8", second: "v"), digit("9", second: "w"), act("×", .insert("*"), .operator, second: "[")],
        [dec("ln", second: "eˣ"), digit("4", second: "L4"), digit("5", second: "L5"), digit("6", second: "L6"), act("−", .insert("-"), .operator, second: "]")],
        [dec("sto→", second: "rcl"), digit("1", second: "L1"), digit("2", second: "L2"), digit("3", second: "L3"), act("+", .insert("+"), .operator, second: "mem")],
        [dec("on", second: "off"), digit("0", second: "catalog"), act(".", .insert("."), .digit, second: "i"), dec("(−)", second: "ans"), dec("enter", second: "entry")]
    ]
}

#if DEBUG
#Preview("Full keypad") {
    CalculatorFullKeypadView(state: {
        let state = CalculatorState(store: UserDefaults(suiteName: "preview.fullkeypad")!)
        state.showFullKeypad = true
        return state
    }())
    .frame(width: CalculatorFullKeypadView.width, height: 560)
    .padding()
    .background(Color(white: 0.9))
}
#endif
