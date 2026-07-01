//
//  CalculatorKey.swift
//  MathBoardCore — Calculator module
//
//  Pure model for the compute-mode keypad: a key's label, what it does,
//  the default keypad layout, a pure reducer that applies a key action
//  to the expression text, and a result formatter. Kept free of SwiftUI
//  so it can be unit-tested without a view host.
//
//  Keypad keys append to / edit the END of the expression string. The
//  editable text field (in the view layer) handles in-string cursor
//  editing for typed input; the keypad intentionally stays simple.
//

import Foundation

// MARK: - Key action

public enum CalculatorKeyAction: Equatable, Sendable {
    /// Insert literal text at the end of the expression (e.g. "7",
    /// "+", "sin(", "pi").
    case insert(String)
    /// Evaluate the current expression.
    case evaluate
    /// Clear the whole expression.
    case clear
    /// Delete the last character.
    case deleteBackward
    /// Flip between degrees and radians.
    case toggleAngleMode
    /// Toggle the `2nd` modifier (next key uses its secondary function).
    case toggleSecond
}

// MARK: - Key style (presentation hint, not layout)

public enum CalculatorKeyStyle: Equatable, Sendable {
    case digit       // 0-9, decimal point
    case `operator`  // + - × ÷ ^
    case function    // sin, log, sqrt, …
    case action      // =, C, ⌫
    case modifier    // DEG/RAD toggle, +/-
}

// MARK: - Key

public struct CalculatorKey: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let action: CalculatorKeyAction
    public let style: CalculatorKeyStyle

    /// Optional `2nd`-shifted label/action. When the `2nd` modifier is
    /// active and this is non-nil, the key displays `secondLabel` and
    /// performs `secondAction`.
    public let secondLabel: String?
    public let secondAction: CalculatorKeyAction?

    public init(
        id: String? = nil,
        label: String,
        action: CalculatorKeyAction,
        style: CalculatorKeyStyle,
        secondLabel: String? = nil,
        secondAction: CalculatorKeyAction? = nil
    ) {
        self.id = id ?? label
        self.label = label
        self.action = action
        self.style = style
        self.secondLabel = secondLabel
        self.secondAction = secondAction
    }

    /// True if this key has a `2nd`-shifted function.
    public var hasSecond: Bool { secondAction != nil }

    // Convenience constructors for the common cases.
    static func digit(_ text: String) -> CalculatorKey {
        CalculatorKey(label: text, action: .insert(text), style: .digit)
    }

    static func op(_ text: String, inserts: String? = nil) -> CalculatorKey {
        CalculatorKey(label: text, action: .insert(inserts ?? text), style: .operator)
    }

    static func fn(
        _ label: String,
        inserts: String,
        secondLabel: String? = nil,
        secondInserts: String? = nil
    ) -> CalculatorKey {
        CalculatorKey(
            id: label,
            label: label,
            action: .insert(inserts),
            style: .function,
            secondLabel: secondLabel,
            secondAction: secondInserts.map { .insert($0) }
        )
    }
}

// MARK: - Default keypad layout

public enum CalculatorKeypadLayout {

    /// Scientific compute-mode keypad, TI-84-Plus-CE-inspired so the
    /// teacher can demonstrate the keys students press. Rows top-to-bottom,
    /// 5 columns. The `2nd` modifier shifts trig→inverse and log/ln→10ˣ/eˣ.
    public static var compute: [[CalculatorKey]] {
        [
            [
                CalculatorKey(label: "2nd", action: .toggleSecond, style: .modifier),
                CalculatorKey(label: "DEG/RAD", action: .toggleAngleMode, style: .modifier),
                CalculatorKey(id: "xvar", label: "x", action: .insert("x"), style: .function),
                CalculatorKey(label: "C", action: .clear, style: .action),
                CalculatorKey(label: "⌫", action: .deleteBackward, style: .action)
            ],
            [
                .fn("x⁻¹", inserts: "^-1"),
                .fn("sin", inserts: "sin(", secondLabel: "sin⁻¹", secondInserts: "asin("),
                .fn("cos", inserts: "cos(", secondLabel: "cos⁻¹", secondInserts: "acos("),
                .fn("tan", inserts: "tan(", secondLabel: "tan⁻¹", secondInserts: "atan("),
                .fn("xⁿ", inserts: "^")
            ],
            [
                .fn("x²", inserts: "^2"),
                .fn("√", inserts: "sqrt("),
                .fn("∛", inserts: "cbrt("),
                CalculatorKey(label: "(", action: .insert("("), style: .function),
                CalculatorKey(label: ")", action: .insert(")"), style: .function)
            ],
            [
                .fn("log", inserts: "log(", secondLabel: "10ˣ", secondInserts: "10^("),
                .fn("ln", inserts: "ln(", secondLabel: "eˣ", secondInserts: "e^("),
                .fn("π", inserts: "pi"),
                .fn("e", inserts: "e"),
                .fn("EE", inserts: "e")
            ],
            [
                .digit("7"), .digit("8"), .digit("9"),
                .op("÷", inserts: "/"),
                .fn(",", inserts: ",")
            ],
            [
                .digit("4"), .digit("5"), .digit("6"),
                .op("×", inserts: "*"),
                .fn("!", inserts: "!")
            ],
            [
                .digit("1"), .digit("2"), .digit("3"),
                .op("−", inserts: "-"),
                CalculatorKey(label: "ans", action: .insert("ans"), style: .function)
            ],
            [
                .digit("0"), .digit("."),
                CalculatorKey(label: "(−)", action: .insert("-"), style: .operator),
                .op("+"),
                CalculatorKey(label: "=", action: .evaluate, style: .action)
            ]
        ]
    }
}

// MARK: - Graph entry keypad (family-specific)

public enum GraphKeypadLayout {

    /// Keys for the graph equation-entry keypad, customized per family.
    /// Family-specific function rows sit on top of a shared numeric/operator
    /// base. No `=` (equations are implicit `y =`); the `−` key doubles as
    /// unary negation since the parser handles `-x`.
    public static func keys(for family: GraphFunctionFamily) -> [[CalculatorKey]] {
        if family == .oneVariable { return oneVariableRows }
        return functionRows(for: family) + baseRows
    }

    /// Bespoke keypad for the number-line "1 Variable" topic: only `x`,
    /// the relations, `and`/`or`, and a number pad (per design — no other
    /// operators; negatives via `(−)`, implicit multiply gives `2x`).
    private static let oneVariableRows: [[CalculatorKey]] = [
        // x = | < >   (inequalities form a 2×2 block at cols 3–4, rows 1–2)
        [
            CalculatorKey(id: "gx1", label: "x", action: .insert("x"), style: .function),
            CalculatorKey(id: "eq", label: "=", action: .insert("="), style: .operator),
            CalculatorKey(id: "lt", label: "<", action: .insert("<"), style: .operator),
            CalculatorKey(id: "gt", label: ">", action: .insert(">"), style: .operator)
        ],
        // and / or sit directly under x / =
        [
            CalculatorKey(id: "andKey", label: "and", action: .insert(" and "), style: .function),
            CalculatorKey(id: "orKey", label: "or", action: .insert(" or "), style: .function),
            CalculatorKey(id: "le", label: "≤", action: .insert("<="), style: .operator),
            CalculatorKey(id: "ge", label: "≥", action: .insert(">="), style: .operator)
        ],
        [.digit("7"), .digit("8"), .digit("9"), CalculatorKey(label: "⌫", action: .deleteBackward, style: .action)],
        [.digit("4"), .digit("5"), .digit("6"), CalculatorKey(label: "C", action: .clear, style: .action)],
        [.digit("1"), .digit("2"), .digit("3"), CalculatorKey(id: "neg", label: "(−)", action: .insert("-"), style: .operator)],
        [.digit("0"), .digit(".")]
    ]

    private static func functionRows(for family: GraphFunctionFamily) -> [[CalculatorKey]] {
        switch family {
        case .oneVariable:
            return [] // handled by `keys(for:)` via `oneVariableRows`
        case .linear:
            return [] // no powers / functions
        case .quadratic:
            return [[
                .fn("x²", inserts: "^2"),
                .fn("√", inserts: "sqrt("),
                .fn("^", inserts: "^"),
                .fn("π", inserts: "pi"),
                .fn("|x|", inserts: "abs(")
            ]]
        case .polynomial:
            return [[
                .fn("x²", inserts: "^2"),
                .fn("x³", inserts: "^3"),
                .fn("^", inserts: "^"),
                .fn("√", inserts: "sqrt("),
                .fn("∛", inserts: "cbrt(")
            ]]
        case .trig:
            return [[
                .fn("sin", inserts: "sin("),
                .fn("cos", inserts: "cos("),
                .fn("tan", inserts: "tan("),
                .fn("π", inserts: "pi"),
                .fn("^", inserts: "^")
            ]]
        case .exponential:
            return [[
                .fn("eˣ", inserts: "e^("),
                .fn("ln", inserts: "ln("),
                .fn("10ˣ", inserts: "10^("),
                .fn("log", inserts: "log("),
                .fn("^", inserts: "^")
            ]]
        case .general:
            return [
                [
                    .fn("sin", inserts: "sin("),
                    .fn("cos", inserts: "cos("),
                    .fn("tan", inserts: "tan("),
                    .fn("√", inserts: "sqrt("),
                    .fn("^", inserts: "^")
                ],
                [
                    .fn("log", inserts: "log("),
                    .fn("ln", inserts: "ln("),
                    .fn("π", inserts: "pi"),
                    .fn("e", inserts: "e"),
                    .fn("x²", inserts: "^2")
                ]
            ]
        }
    }

    /// Shared numeric / operator / variable base. 4 rows × 5.
    private static let baseRows: [[CalculatorKey]] = [
        [
            CalculatorKey(id: "gx", label: "x", action: .insert("x"), style: .function),
            CalculatorKey(label: "(", action: .insert("("), style: .function),
            CalculatorKey(label: ")", action: .insert(")"), style: .function),
            CalculatorKey(label: "C", action: .clear, style: .action),
            CalculatorKey(label: "⌫", action: .deleteBackward, style: .action)
        ],
        [.digit("7"), .digit("8"), .digit("9"), .op("÷", inserts: "/"), .op("×", inserts: "*")],
        [.digit("4"), .digit("5"), .digit("6"), .op("−", inserts: "-"), .op("+")],
        [.digit("1"), .digit("2"), .digit("3"), .digit("0"), .digit(".")]
    ]
}

// MARK: - Expression reducer

public enum CalculatorExpressionReducer {

    /// Apply a key action to an expression's text. `evaluate` and
    /// `toggleAngleMode` don't change the text — they're handled by the
    /// view layer — so they return the input unchanged.
    public static func reduce(expression: String, action: CalculatorKeyAction) -> String {
        switch action {
        case .insert(let text):
            return expression + text
        case .deleteBackward:
            return String(expression.dropLast())
        case .clear:
            return ""
        case .evaluate, .toggleAngleMode, .toggleSecond:
            return expression
        }
    }
}

// MARK: - Result formatting

public enum CalculatorResultFormatter {

    /// Format an evaluation result for the display. Integers render
    /// without a trailing ".0"; very large/small magnitudes fall back to
    /// scientific notation; non-finite values become a short label.
    public static func string(for value: Double) -> String {
        if value.isNaN { return "NaN" }
        if value.isInfinite { return value < 0 ? "−∞" : "∞" }
        if value == 0 { return "0" }

        let magnitude = abs(value)

        // Whole numbers within a safe integer range render as integers.
        // Use the unicode minus so all formatter paths are consistent.
        if value.rounded() == value, magnitude < 1e15 {
            return String(Int64(value)).replacingOccurrences(of: "-", with: "−")
        }

        // Very large or very small → scientific notation.
        if magnitude >= 1e12 || magnitude < 1e-6 {
            return scientific(value)
        }

        // Otherwise show up to 10 significant digits and trim trailing zeros.
        return fixed(value)
    }

    private static func fixed(_ value: Double) -> String {
        var text = String(format: "%.10g", value)
        // %g can still emit exponent form for some values — normalize the
        // minus sign and return as-is if so.
        text = text.replacingOccurrences(of: "-", with: "−")
        return text
    }

    private static func scientific(_ value: Double) -> String {
        let text = String(format: "%.6e", value)
        return text.replacingOccurrences(of: "-", with: "−")
    }
}
