//
//  CalculatorComputeView.swift
//  MathBoardCore — Calculator module
//
//  Compute-mode body: an editable expression field + result line on top,
//  a scientific keypad below. Equation entry is "both" per the locked-in
//  design — the teacher can type directly in the field or tap keypad
//  buttons, which append to the field.
//
//  This view owns only ephemeral UI state (the last result / error). The
//  durable expression and angle mode live in `CalculatorState`.
//

import SwiftUI

struct CalculatorComputeView: View {
    @Bindable var state: CalculatorState

    private let engine = CalculatorEngine()

    @State private var isSecondActive = false

    var body: some View {
        VStack(spacing: 10) {
            display
            keypad
        }
        .padding(10)
    }

    // MARK: - Display

    private var display: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack {
                Text(state.angleMode.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                Spacer()
            }

            TextField("Enter expression", text: $state.computeExpression, axis: .vertical)
                .font(.system(.title3, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.plain)
                .lineLimit(1...2)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.asciiCapable)
                #endif
                .onSubmit(evaluate)

            Text(state.computeResult.isEmpty ? " " : state.computeResult)
                .font(.system(.title2, design: .monospaced).weight(.semibold))
                .foregroundStyle(state.computeIsError ? Color.red : Color.primary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Keypad

    private var keypad: some View {
        VStack(spacing: 6) {
            ForEach(Array(CalculatorKeypadLayout.compute.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(row) { key in
                        keyButton(key)
                    }
                }
            }
        }
    }

    private func keyButton(_ key: CalculatorKey) -> some View {
        // When 2nd is active and this key has a secondary, show/use it.
        let showSecond = isSecondActive && key.hasSecond
        let label = showSecond ? (key.secondLabel ?? key.label) : key.label
        let action = showSecond ? (key.secondAction ?? key.action) : key.action
        let isArmed = key.action == .toggleSecond && isSecondActive

        let fill: Color = isArmed
            ? CalculatorTheme.accent
            : (showSecond ? Color(red: 0.30, green: 0.26, blue: 0.42) : CalculatorTheme.keyFill(for: key.style))
        return Button {
            handle(action, isSecondShifted: showSecond)
        } label: {
            Text(label).font(keyFont(for: key.style))
        }
        .buttonStyle(CalculatorKeyButtonStyle(fill: fill))
    }

    private func keyFont(for style: CalculatorKeyStyle) -> Font {
        switch style {
        case .digit: return .title3.weight(.medium)
        case .operator: return .title3.weight(.semibold)
        case .function, .modifier: return .callout
        case .action: return .title3.weight(.bold)
        }
    }

    // MARK: - Actions

    private func handle(_ action: CalculatorKeyAction, isSecondShifted: Bool) {
        switch action {
        case .toggleSecond:
            isSecondActive.toggle()
            return // don't consume the 2nd state below
        case .evaluate:
            evaluate()
        case .toggleAngleMode:
            state.angleMode = state.angleMode == .degrees ? .radians : .degrees
            // Re-evaluate so the result reflects the new mode, if there's
            // something to evaluate.
            if !state.computeExpression.isEmpty { evaluate() }
        case .insert, .deleteBackward, .clear:
            state.computeExpression = CalculatorExpressionReducer.reduce(
                expression: state.computeExpression,
                action: action
            )
            if action == .clear {
                state.computeResult = ""
                state.computeIsError = false
            }
        }

        // TI behavior: 2nd auto-deactivates after one shifted key press.
        if isSecondActive { isSecondActive = false }
    }

    private func evaluate() {
        let trimmed = state.computeExpression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state.computeResult = ""
            state.computeIsError = false
            return
        }

        do {
            // Inject the previous answer as `ans` (TI-style).
            let variables: [String: Double] = state.lastAnswer.map { ["ans": $0] } ?? [:]
            let value = try engine.evaluate(trimmed, angleMode: state.angleMode, variables: variables)
            state.computeResult = CalculatorResultFormatter.string(for: value)
            state.computeIsError = false
            state.lastAnswer = value
        } catch {
            state.computeResult = (error as? LocalizedError)?.errorDescription ?? "Error"
            state.computeIsError = true
        }
    }
}

#if DEBUG
#Preview("Compute mode") {
    CalculatorComputeView(state: {
        let state = CalculatorState(store: UserDefaults(suiteName: "preview.calculator")!)
        state.computeExpression = "2sin(30) + sqrt(9)"
        return state
    }())
    .frame(width: 360, height: 540)
    .padding()
}
#endif
