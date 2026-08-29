//
//  JSONMathtivityCatalog.swift
//  WidgetEngine
//
//  Bundled JSON mathtivities that ship as editable starter activities.
//

import Foundation

public enum JSONMathtivityCatalog {
    public struct Entry: Identifiable, Equatable, Sendable {
        public var id: String { resourceName }
        public let title: String
        public let topic: String
        public let topicLevel: Int
        public let activityType: WidgetObjectActivityKind
        public let mode: JSONMathtivityMode
        public let tags: [String]
        public let resourceName: String
    }

    public enum JSONMathtivityMode: String, Sendable {
        case scored
        case demo

        public var displayName: String {
            switch self {
            case .scored: return "Scored"
            case .demo: return "Demo"
            }
        }
    }

    public static let linearEquationFillInTheBlank = Entry(
        title: "Equation Blanks",
        topic: "Algebra 1",
        topicLevel: 1,
        activityType: .fillInTheBlank,
        mode: .scored,
        tags: ["linear equations", "inverse operations", "fill in the blank"],
        resourceName: "linear-equation-fill-in-the-blank"
    )

    public static let quadraticFeaturesMultipleChoice = Entry(
        title: "Quadratic Features",
        topic: "Algebra 2",
        topicLevel: 2,
        activityType: .multipleChoice,
        mode: .scored,
        tags: ["quadratics", "forms", "vertex", "roots"],
        resourceName: "quadratic-features-multiple-choice"
    )

    public static let exponentRulesFillInTheBlank = Entry(
        title: "Exponent Rule Blanks",
        topic: "Algebra 2",
        topicLevel: 2,
        activityType: .fillInTheBlank,
        mode: .scored,
        tags: ["exponents", "product rule", "quotient rule", "power rule"],
        resourceName: "exponent-rules-fill-in-the-blank"
    )

    public static let inequalityMatchNumberLine = Entry(
        title: "Inequality Match",
        topic: "Algebra 1",
        topicLevel: 1,
        activityType: .multipleChoice,
        mode: .scored,
        tags: ["inequalities", "number line", "graph matching"],
        resourceName: "inequality-match-number-line"
    )

    public static let graphTheInequalityNumberLine = Entry(
        title: "Graph the Inequality",
        topic: "Algebra 1",
        topicLevel: 1,
        activityType: .multipleChoice,
        mode: .scored,
        tags: ["inequalities", "number line", "graphing"],
        resourceName: "graph-the-inequality-number-line"
    )

    public static let compoundInequalityNumberLine = Entry(
        title: "Compound Inequality",
        topic: "Algebra 1",
        topicLevel: 1,
        activityType: .multipleChoice,
        mode: .scored,
        tags: ["compound inequalities", "number line", "intervals"],
        resourceName: "compound-inequality-number-line"
    )

    public static let whichGraphIsCorrectNumberLine = Entry(
        title: "Which Graph Is Correct?",
        topic: "Algebra 1",
        topicLevel: 1,
        activityType: .multipleChoice,
        mode: .scored,
        tags: ["inequalities", "number line", "graph matching"],
        resourceName: "which-graph-is-correct-number-line"
    )

    public static let absoluteValueInequalityNumberLine = Entry(
        title: "Absolute Value Inequality",
        topic: "Algebra 2",
        topicLevel: 2,
        activityType: .multipleChoice,
        mode: .scored,
        tags: ["absolute value", "inequalities", "number line"],
        resourceName: "absolute-value-inequality-number-line"
    )

    public static let bundledEntries: [Entry] = [
        linearEquationFillInTheBlank,
        quadraticFeaturesMultipleChoice,
        exponentRulesFillInTheBlank,
        inequalityMatchNumberLine,
        graphTheInequalityNumberLine,
        compoundInequalityNumberLine,
        whichGraphIsCorrectNumberLine,
        absoluteValueInequalityNumberLine
    ]

    public static func source(for entry: Entry) -> String? {
        let nestedURL = Bundle.module.url(
            forResource: entry.resourceName,
            withExtension: "json",
            subdirectory: "JSONMathtivities"
        )
        let flatURL = Bundle.module.url(
            forResource: entry.resourceName,
            withExtension: "json"
        )

        guard let url = nestedURL ?? flatURL else {
            return nil
        }

        return try? String(contentsOf: url, encoding: .utf8)
    }
}
