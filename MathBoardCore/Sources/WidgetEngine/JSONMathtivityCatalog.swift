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

    public static let bundledEntries: [Entry] = [
        linearEquationFillInTheBlank,
        quadraticFeaturesMultipleChoice,
        exponentRulesFillInTheBlank
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
