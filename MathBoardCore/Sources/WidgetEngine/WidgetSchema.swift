//
//  WidgetSchema.swift
//  WidgetEngine
//
//  Native MathBoard Widget JSON schema and runtime helpers. This file stays
//  independent of MathBoard.app, Canvas, and Presentation so the schema can be
//  designed and previewed before canvas integration.
//

import Foundation

struct MathBoardWidgetDocument: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var widgetId: String?
    var title: String
    var description: String?
    var learningObjective: String?
    var analytics: WidgetAnalyticsMetadata?
    var presentation: WidgetPresentationMetadata?
    var initialState: [String: WidgetValue]
    var body: WidgetComponent

    init(
        schemaVersion: Int = 1,
        widgetId: String? = nil,
        title: String,
        description: String? = nil,
        learningObjective: String? = nil,
        analytics: WidgetAnalyticsMetadata? = nil,
        presentation: WidgetPresentationMetadata? = nil,
        initialState: [String: WidgetValue] = [:],
        body: WidgetComponent
    ) {
        self.schemaVersion = schemaVersion
        self.widgetId = widgetId
        self.title = title
        self.description = description
        self.learningObjective = learningObjective
        self.analytics = analytics
        self.presentation = presentation
        self.initialState = initialState
        self.body = body
    }
}

struct WidgetAnalyticsMetadata: Codable, Equatable, Sendable {
    var enabled: Bool
}

struct WidgetPresentationMetadata: Codable, Equatable, Sendable {
    enum ScrollBehavior: String, Codable, Sendable {
        case enabled
        case disabled
    }

    var preferredWidth: Double?
    var preferredHeight: Double?
    var scroll: ScrollBehavior?
}

enum WidgetValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)

    var displayString: String {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            if value.rounded() == value {
                return String(Int(value))
            }
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        }
    }

    var numberValue: Double? {
        switch self {
        case .number(let value):
            return value
        case .string(let value):
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        case .bool(let value):
            return value ? 1 : 0
        }
    }

    var boolValue: Bool {
        switch self {
        case .bool(let value):
            return value
        case .number(let value):
            return value != 0
        case .string(let value):
            return !value.isEmpty
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        }
    }
}

enum WidgetComponent: Codable, Equatable, Sendable {
    case stack(WidgetStack)
    case grid(WidgetGrid)
    case text(WidgetText)
    case formula(WidgetFormula)
    case mathTemplate(WidgetMathTemplate)
    case numberInput(WidgetNumberInput)
    case mathBox(WidgetMathBox)
    case numberBox(WidgetNumberBox)
    case digitPad(WidgetDigitPad)
    case mathPad(WidgetMathPad)
    case valueStepper(WidgetValueStepper)
    case valueSlider(WidgetValueSlider)
    case choiceGroup(WidgetChoiceGroup)
    case goalMeter(WidgetGoalMeter)
    case hintProvider(WidgetHintProvider)
    case symbolCollection(WidgetSymbolCollection)
    case graphic(WidgetGraphic)
    case nativeGraph(WidgetNativeGraph)
    case questionSet(WidgetQuestionSet)
    case button(WidgetButton)
    case feedback(WidgetFeedback)
    case score(WidgetScore)
    case divider

    private enum CodingKeys: String, CodingKey {
        case type
        case axis
        case spacing
        case children
        case text
        case template
        case result
        case displayMode
        case role
        case id
        case label
        case stateKey
        case placeholder
        case title
        case actions
        case style
        case shape
        case maxLength
        case clearOnSelect
        case digits
        case preset
        case extraKeys
        case choices
        case value
        case goalValue
        case hints
        case symbol
        case countStateKey
        case maxCount
        case decoration
        case elements
        case width
        case height
        case columns
        case parts
        case fontScale
        case min
        case max
        case step
        case xMin
        case xMax
        case yMin
        case yMax
        case mode
        case questions
        case currentIndexStateKey
        case completedCountStateKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "stack":
            self = .stack(WidgetStack(
                axis: try container.decodeIfPresent(WidgetStack.Axis.self, forKey: .axis) ?? .vertical,
                spacing: try container.decodeIfPresent(Double.self, forKey: .spacing) ?? 12,
                children: try container.decode([WidgetComponent].self, forKey: .children),
                decoration: try container.decodeIfPresent(WidgetDecoration.self, forKey: .decoration)
            ))
        case "grid":
            self = .grid(WidgetGrid(
                columns: try container.decodeIfPresent(Int.self, forKey: .columns) ?? 2,
                spacing: try container.decodeIfPresent(Double.self, forKey: .spacing) ?? 10,
                children: try container.decode([WidgetComponent].self, forKey: .children),
                decoration: try container.decodeIfPresent(WidgetDecoration.self, forKey: .decoration)
            ))
        case "text":
            self = .text(WidgetText(
                id: try container.decodeIfPresent(String.self, forKey: .id),
                text: try container.decode(String.self, forKey: .text),
                role: try container.decodeIfPresent(WidgetText.Role.self, forKey: .role) ?? .body
            ))
        case "formula":
            self = .formula(WidgetFormula(
                id: try container.decodeIfPresent(String.self, forKey: .id),
                label: try container.decodeIfPresent(String.self, forKey: .label),
                template: try container.decodeIfPresent(String.self, forKey: .template),
                result: try container.decodeIfPresent(WidgetExpression.self, forKey: .result),
                displayMode: try container.decodeIfPresent(WidgetFormula.DisplayMode.self, forKey: .displayMode) ?? .formulaOnly
            ))
        case "mathTemplate":
            self = .mathTemplate(WidgetMathTemplate(
                id: try container.decodeIfPresent(String.self, forKey: .id),
                parts: try container.decode([WidgetMathTemplatePart].self, forKey: .parts),
                spacing: try container.decodeIfPresent(Double.self, forKey: .spacing) ?? 6,
                fontScale: try container.decodeIfPresent(WidgetMathTemplate.FontScale.self, forKey: .fontScale) ?? .large
            ))
        case "numberInput":
            self = .numberInput(WidgetNumberInput(
                id: try container.decodeIfPresent(String.self, forKey: .id),
                label: try container.decode(String.self, forKey: .label),
                stateKey: try container.decode(String.self, forKey: .stateKey),
                placeholder: try container.decodeIfPresent(String.self, forKey: .placeholder)
            ))
        case "mathBox":
            self = .mathBox(WidgetMathBox(
                id: try container.decodeIfPresent(String.self, forKey: .id),
                label: try container.decodeIfPresent(String.self, forKey: .label),
                stateKey: try container.decode(String.self, forKey: .stateKey),
                placeholder: try container.decodeIfPresent(String.self, forKey: .placeholder),
                maxLength: try container.decodeIfPresent(Int.self, forKey: .maxLength) ?? 24,
                clearOnSelect: try container.decodeIfPresent(Bool.self, forKey: .clearOnSelect) ?? false
            ))
        case "numberBox":
            self = .numberBox(WidgetNumberBox(
                id: try container.decodeIfPresent(String.self, forKey: .id),
                label: try container.decodeIfPresent(String.self, forKey: .label),
                stateKey: try container.decode(String.self, forKey: .stateKey),
                placeholder: try container.decodeIfPresent(String.self, forKey: .placeholder),
                shape: try container.decodeIfPresent(WidgetInputShape.self, forKey: .shape) ?? .roundedSquare,
                maxLength: try container.decodeIfPresent(Int.self, forKey: .maxLength) ?? 2,
                clearOnSelect: try container.decodeIfPresent(Bool.self, forKey: .clearOnSelect) ?? true
            ))
        case "digitPad":
            self = .digitPad(WidgetDigitPad(
                digits: try container.decodeIfPresent([Int].self, forKey: .digits) ?? Array(0...9),
                shape: try container.decodeIfPresent(WidgetInputShape.self, forKey: .shape) ?? .circle
            ))
        case "mathPad":
            self = .mathPad(WidgetMathPad(
                preset: try container.decodeIfPresent(WidgetMathPad.Preset.self, forKey: .preset) ?? .numeric,
                extraKeys: try container.decodeIfPresent([String].self, forKey: .extraKeys) ?? [],
                shape: try container.decodeIfPresent(WidgetInputShape.self, forKey: .shape) ?? .roundedSquare
            ))
        case "valueStepper":
            self = .valueStepper(WidgetValueStepper(
                label: try container.decode(String.self, forKey: .label),
                stateKey: try container.decode(String.self, forKey: .stateKey),
                min: try container.decodeIfPresent(Double.self, forKey: .min) ?? -10,
                max: try container.decodeIfPresent(Double.self, forKey: .max) ?? 10,
                step: try container.decodeIfPresent(Double.self, forKey: .step) ?? 1
            ))
        case "valueSlider":
            self = .valueSlider(WidgetValueSlider(
                label: try container.decode(String.self, forKey: .label),
                stateKey: try container.decode(String.self, forKey: .stateKey),
                min: try container.decodeIfPresent(Double.self, forKey: .min) ?? -10,
                max: try container.decodeIfPresent(Double.self, forKey: .max) ?? 10,
                step: try container.decodeIfPresent(Double.self, forKey: .step) ?? 1
            ))
        case "choiceGroup":
            self = .choiceGroup(WidgetChoiceGroup(
                id: try container.decodeIfPresent(String.self, forKey: .id),
                label: try container.decodeIfPresent(String.self, forKey: .label),
                stateKey: try container.decode(String.self, forKey: .stateKey),
                style: try container.decodeIfPresent(WidgetChoiceGroup.Style.self, forKey: .style) ?? .tiles,
                choices: try container.decode([WidgetChoice].self, forKey: .choices)
            ))
        case "goalMeter":
            self = .goalMeter(WidgetGoalMeter(
                label: try container.decodeIfPresent(String.self, forKey: .label) ?? "Progress",
                stateKey: try container.decode(String.self, forKey: .stateKey),
                goalValue: try container.decodeIfPresent(Double.self, forKey: .goalValue) ?? 10,
                style: try container.decodeIfPresent(WidgetGoalMeter.Style.self, forKey: .style) ?? .bar
            ))
        case "hintProvider":
            self = .hintProvider(WidgetHintProvider(
                title: try container.decodeIfPresent(String.self, forKey: .title) ?? "Need a hint?",
                stateKey: try container.decode(String.self, forKey: .stateKey),
                hints: try container.decode([String].self, forKey: .hints)
            ))
        case "symbolCollection":
            self = .symbolCollection(WidgetSymbolCollection(
                id: try container.decodeIfPresent(String.self, forKey: .id),
                symbol: try container.decode(WidgetBuiltInSymbol.self, forKey: .symbol),
                countStateKey: try container.decode(String.self, forKey: .countStateKey),
                maxCount: try container.decodeIfPresent(Int.self, forKey: .maxCount) ?? 5,
                style: try container.decodeIfPresent(WidgetSymbolCollection.Style.self, forKey: .style) ?? .row
            ))
        case "graphic":
            self = .graphic(WidgetGraphic(
                width: try container.decodeIfPresent(Double.self, forKey: .width) ?? 320,
                height: try container.decodeIfPresent(Double.self, forKey: .height) ?? 180,
                decoration: try container.decodeIfPresent(WidgetDecoration.self, forKey: .decoration),
                elements: try container.decode([WidgetGraphicElement].self, forKey: .elements)
            ))
        case "nativeGraph":
            self = .nativeGraph(WidgetNativeGraph(
                width: try container.decodeIfPresent(Double.self, forKey: .width) ?? 320,
                height: try container.decodeIfPresent(Double.self, forKey: .height) ?? 220,
                xMin: try container.decodeIfPresent(Double.self, forKey: .xMin) ?? -10,
                xMax: try container.decodeIfPresent(Double.self, forKey: .xMax) ?? 10,
                yMin: try container.decodeIfPresent(Double.self, forKey: .yMin) ?? -10,
                yMax: try container.decodeIfPresent(Double.self, forKey: .yMax) ?? 10,
                elements: try container.decode([WidgetGraphElement].self, forKey: .elements)
            ))
        case "questionSet":
            self = .questionSet(WidgetQuestionSet(
                id: try container.decodeIfPresent(String.self, forKey: .id),
                mode: try container.decodeIfPresent(WidgetQuestionSet.Mode.self, forKey: .mode) ?? .sequential,
                currentIndexStateKey: try container.decodeIfPresent(String.self, forKey: .currentIndexStateKey) ?? "currentQuestionIndex",
                completedCountStateKey: try container.decodeIfPresent(String.self, forKey: .completedCountStateKey),
                questions: try container.decode([WidgetQuestion].self, forKey: .questions)
            ))
        case "button":
            self = .button(WidgetButton(
                id: try container.decodeIfPresent(String.self, forKey: .id),
                title: try container.decode(String.self, forKey: .title),
                style: try container.decodeIfPresent(WidgetButton.Style.self, forKey: .style) ?? .primary,
                actions: try container.decode([WidgetAction].self, forKey: .actions)
            ))
        case "feedback":
            self = .feedback(WidgetFeedback(id: try container.decodeIfPresent(String.self, forKey: .id)))
        case "score":
            self = .score(WidgetScore(
                label: try container.decodeIfPresent(String.self, forKey: .label) ?? "Score",
                stateKey: try container.decode(String.self, forKey: .stateKey)
            ))
        case "divider":
            self = .divider
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unsupported widget component type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .stack(let value):
            try container.encode("stack", forKey: .type)
            try container.encode(value.axis, forKey: .axis)
            try container.encode(value.spacing, forKey: .spacing)
            try container.encode(value.children, forKey: .children)
            try container.encodeIfPresent(value.decoration, forKey: .decoration)
        case .grid(let value):
            try container.encode("grid", forKey: .type)
            try container.encode(value.columns, forKey: .columns)
            try container.encode(value.spacing, forKey: .spacing)
            try container.encode(value.children, forKey: .children)
            try container.encodeIfPresent(value.decoration, forKey: .decoration)
        case .text(let value):
            try container.encode("text", forKey: .type)
            try container.encodeIfPresent(value.id, forKey: .id)
            try container.encode(value.text, forKey: .text)
            try container.encode(value.role, forKey: .role)
        case .formula(let value):
            try container.encode("formula", forKey: .type)
            try container.encodeIfPresent(value.id, forKey: .id)
            try container.encodeIfPresent(value.label, forKey: .label)
            try container.encodeIfPresent(value.template, forKey: .template)
            try container.encodeIfPresent(value.result, forKey: .result)
            try container.encode(value.displayMode, forKey: .displayMode)
        case .mathTemplate(let value):
            try container.encode("mathTemplate", forKey: .type)
            try container.encodeIfPresent(value.id, forKey: .id)
            try container.encode(value.parts, forKey: .parts)
            try container.encode(value.spacing, forKey: .spacing)
            try container.encode(value.fontScale, forKey: .fontScale)
        case .numberInput(let value):
            try container.encode("numberInput", forKey: .type)
            try container.encodeIfPresent(value.id, forKey: .id)
            try container.encode(value.label, forKey: .label)
            try container.encode(value.stateKey, forKey: .stateKey)
            try container.encodeIfPresent(value.placeholder, forKey: .placeholder)
        case .mathBox(let value):
            try container.encode("mathBox", forKey: .type)
            try container.encodeIfPresent(value.id, forKey: .id)
            try container.encodeIfPresent(value.label, forKey: .label)
            try container.encode(value.stateKey, forKey: .stateKey)
            try container.encodeIfPresent(value.placeholder, forKey: .placeholder)
            try container.encode(value.maxLength, forKey: .maxLength)
            try container.encode(value.clearOnSelect, forKey: .clearOnSelect)
        case .numberBox(let value):
            try container.encode("numberBox", forKey: .type)
            try container.encodeIfPresent(value.id, forKey: .id)
            try container.encodeIfPresent(value.label, forKey: .label)
            try container.encode(value.stateKey, forKey: .stateKey)
            try container.encodeIfPresent(value.placeholder, forKey: .placeholder)
            try container.encode(value.shape, forKey: .shape)
            try container.encode(value.maxLength, forKey: .maxLength)
            try container.encode(value.clearOnSelect, forKey: .clearOnSelect)
        case .digitPad(let value):
            try container.encode("digitPad", forKey: .type)
            try container.encode(value.digits, forKey: .digits)
            try container.encode(value.shape, forKey: .shape)
        case .mathPad(let value):
            try container.encode("mathPad", forKey: .type)
            try container.encode(value.preset, forKey: .preset)
            try container.encode(value.extraKeys, forKey: .extraKeys)
            try container.encode(value.shape, forKey: .shape)
        case .valueStepper(let value):
            try container.encode("valueStepper", forKey: .type)
            try container.encode(value.label, forKey: .label)
            try container.encode(value.stateKey, forKey: .stateKey)
            try container.encode(value.min, forKey: .min)
            try container.encode(value.max, forKey: .max)
            try container.encode(value.step, forKey: .step)
        case .valueSlider(let value):
            try container.encode("valueSlider", forKey: .type)
            try container.encode(value.label, forKey: .label)
            try container.encode(value.stateKey, forKey: .stateKey)
            try container.encode(value.min, forKey: .min)
            try container.encode(value.max, forKey: .max)
            try container.encode(value.step, forKey: .step)
        case .choiceGroup(let value):
            try container.encode("choiceGroup", forKey: .type)
            try container.encodeIfPresent(value.id, forKey: .id)
            try container.encodeIfPresent(value.label, forKey: .label)
            try container.encode(value.stateKey, forKey: .stateKey)
            try container.encode(value.style, forKey: .style)
            try container.encode(value.choices, forKey: .choices)
        case .goalMeter(let value):
            try container.encode("goalMeter", forKey: .type)
            try container.encode(value.label, forKey: .label)
            try container.encode(value.stateKey, forKey: .stateKey)
            try container.encode(value.goalValue, forKey: .goalValue)
            try container.encode(value.style, forKey: .style)
        case .hintProvider(let value):
            try container.encode("hintProvider", forKey: .type)
            try container.encode(value.title, forKey: .title)
            try container.encode(value.stateKey, forKey: .stateKey)
            try container.encode(value.hints, forKey: .hints)
        case .symbolCollection(let value):
            try container.encode("symbolCollection", forKey: .type)
            try container.encodeIfPresent(value.id, forKey: .id)
            try container.encode(value.symbol, forKey: .symbol)
            try container.encode(value.countStateKey, forKey: .countStateKey)
            try container.encode(value.maxCount, forKey: .maxCount)
            try container.encode(value.style, forKey: .style)
        case .graphic(let value):
            try container.encode("graphic", forKey: .type)
            try container.encode(value.width, forKey: .width)
            try container.encode(value.height, forKey: .height)
            try container.encodeIfPresent(value.decoration, forKey: .decoration)
            try container.encode(value.elements, forKey: .elements)
        case .nativeGraph(let value):
            try container.encode("nativeGraph", forKey: .type)
            try container.encode(value.width, forKey: .width)
            try container.encode(value.height, forKey: .height)
            try container.encode(value.xMin, forKey: .xMin)
            try container.encode(value.xMax, forKey: .xMax)
            try container.encode(value.yMin, forKey: .yMin)
            try container.encode(value.yMax, forKey: .yMax)
            try container.encode(value.elements, forKey: .elements)
        case .questionSet(let value):
            try container.encode("questionSet", forKey: .type)
            try container.encodeIfPresent(value.id, forKey: .id)
            try container.encode(value.mode, forKey: .mode)
            try container.encode(value.currentIndexStateKey, forKey: .currentIndexStateKey)
            try container.encodeIfPresent(value.completedCountStateKey, forKey: .completedCountStateKey)
            try container.encode(value.questions, forKey: .questions)
        case .button(let value):
            try container.encode("button", forKey: .type)
            try container.encodeIfPresent(value.id, forKey: .id)
            try container.encode(value.title, forKey: .title)
            try container.encode(value.style, forKey: .style)
            try container.encode(value.actions, forKey: .actions)
        case .feedback(let value):
            try container.encode("feedback", forKey: .type)
            try container.encodeIfPresent(value.id, forKey: .id)
        case .score(let value):
            try container.encode("score", forKey: .type)
            try container.encode(value.label, forKey: .label)
            try container.encode(value.stateKey, forKey: .stateKey)
        case .divider:
            try container.encode("divider", forKey: .type)
        }
    }
}

struct WidgetStack: Codable, Equatable, Sendable {
    enum Axis: String, Codable, Sendable {
        case vertical
        case horizontal
    }

    var axis: Axis
    var spacing: Double
    var children: [WidgetComponent]
    var decoration: WidgetDecoration?

    init(axis: Axis, spacing: Double, children: [WidgetComponent], decoration: WidgetDecoration? = nil) {
        self.axis = axis
        self.spacing = spacing
        self.children = children
        self.decoration = decoration
    }
}

struct WidgetDecoration: Codable, Equatable, Sendable {
    var fill: String?
    var borderColor: String?
    var borderWidth: Double?
    var cornerRadius: Double?
    var padding: Double?
}

struct WidgetGrid: Codable, Equatable, Sendable {
    var columns: Int
    var spacing: Double
    var children: [WidgetComponent]
    var decoration: WidgetDecoration?
}

struct WidgetText: Codable, Equatable, Sendable {
    enum Role: String, Codable, Sendable {
        case title
        case subtitle
        case body
        case caption
        case math
    }

    var id: String?
    var text: String
    var role: Role
}

struct WidgetFormula: Codable, Equatable, Sendable {
    enum DisplayMode: String, Codable, Sendable {
        case formulaOnly
        case valueOnly
        case formulaAndValue
    }

    var id: String?
    var label: String?
    var template: String?
    var result: WidgetExpression?
    var displayMode: DisplayMode
}

struct WidgetMathTemplate: Codable, Equatable, Sendable {
    enum FontScale: String, Codable, Sendable {
        case compact
        case regular
        case large
    }

    var id: String?
    var parts: [WidgetMathTemplatePart]
    var spacing: Double
    var fontScale: FontScale
}

enum WidgetMathTemplatePart: Codable, Equatable, Sendable {
    case text(WidgetMathTemplateTextPart)
    case numberBox(WidgetMathTemplateNumberBoxPart)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case stateKey
        case placeholder
        case maxLength
        case clearOnSelect
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(WidgetMathTemplateTextPart(text: try container.decode(String.self, forKey: .text)))
        case "numberBox":
            self = .numberBox(WidgetMathTemplateNumberBoxPart(
                stateKey: try container.decode(String.self, forKey: .stateKey),
                placeholder: try container.decodeIfPresent(String.self, forKey: .placeholder),
                maxLength: try container.decodeIfPresent(Int.self, forKey: .maxLength) ?? 2,
                clearOnSelect: try container.decodeIfPresent(Bool.self, forKey: .clearOnSelect) ?? true
            ))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unsupported mathTemplate part type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try container.encode("text", forKey: .type)
            try container.encode(value.text, forKey: .text)
        case .numberBox(let value):
            try container.encode("numberBox", forKey: .type)
            try container.encode(value.stateKey, forKey: .stateKey)
            try container.encodeIfPresent(value.placeholder, forKey: .placeholder)
            try container.encode(value.maxLength, forKey: .maxLength)
            try container.encode(value.clearOnSelect, forKey: .clearOnSelect)
        }
    }
}

struct WidgetMathTemplateTextPart: Codable, Equatable, Sendable {
    var text: String
}

struct WidgetMathTemplateNumberBoxPart: Codable, Equatable, Sendable {
    var stateKey: String
    var placeholder: String?
    var maxLength: Int
    var clearOnSelect: Bool
}

struct WidgetNumberInput: Codable, Equatable, Sendable {
    var id: String?
    var label: String
    var stateKey: String
    var placeholder: String?
}

struct WidgetMathBox: Codable, Equatable, Sendable {
    var id: String?
    var label: String?
    var stateKey: String
    var placeholder: String?
    var maxLength: Int
    var clearOnSelect: Bool
}

enum WidgetInputShape: String, Codable, Sendable {
    case circle
    case square
    case roundedSquare
}

struct WidgetNumberBox: Codable, Equatable, Sendable {
    var id: String?
    var label: String?
    var stateKey: String
    var placeholder: String?
    var shape: WidgetInputShape
    var maxLength: Int
    var clearOnSelect: Bool
}

struct WidgetDigitPad: Codable, Equatable, Sendable {
    var digits: [Int]
    var shape: WidgetInputShape
}

struct WidgetMathPad: Codable, Equatable, Sendable {
    enum Preset: String, Codable, Sendable {
        case numeric
        case integer
        case operations
        case algebra
        case calculator
    }

    var preset: Preset
    var extraKeys: [String]
    var shape: WidgetInputShape
}

struct WidgetValueStepper: Codable, Equatable, Sendable {
    var label: String
    var stateKey: String
    var min: Double
    var max: Double
    var step: Double
}

struct WidgetValueSlider: Codable, Equatable, Sendable {
    var label: String
    var stateKey: String
    var min: Double
    var max: Double
    var step: Double
}

struct WidgetChoiceGroup: Codable, Equatable, Sendable {
    enum Style: String, Codable, Sendable {
        case tiles
        case pills
        case buttons
    }

    var id: String?
    var label: String?
    var stateKey: String
    var style: Style
    var choices: [WidgetChoice]
}

struct WidgetChoice: Codable, Equatable, Sendable {
    var label: String
    var value: WidgetValue
}

struct WidgetGoalMeter: Codable, Equatable, Sendable {
    enum Style: String, Codable, Sendable {
        case bar
        case radial
    }

    var label: String
    var stateKey: String
    var goalValue: Double
    var style: Style
}

struct WidgetHintProvider: Codable, Equatable, Sendable {
    var title: String
    var stateKey: String
    var hints: [String]
}

enum WidgetBuiltInSymbol: String, Codable, Sendable {
    case star
    case basketball
    case target
    case coin
    case numberTile
    case trophy
    case rocket
    case checkmark
}

struct WidgetSymbolCollection: Codable, Equatable, Sendable {
    enum Style: String, Codable, Sendable {
        case row
        case wrap
    }

    var id: String?
    var symbol: WidgetBuiltInSymbol
    var countStateKey: String
    var maxCount: Int
    var style: Style
}

enum WidgetAnimationPreset: String, Codable, Sendable {
    case pulse
    case shake
    case fall
    case successHighlight
    case fadeDim
}

struct WidgetGraphic: Codable, Equatable, Sendable {
    var width: Double
    var height: Double
    var decoration: WidgetDecoration?
    var elements: [WidgetGraphicElement]
}

enum WidgetGraphicElement: Codable, Equatable, Sendable {
    case line(WidgetGraphicLine)
    case arrow(WidgetGraphicLine)
    case point(WidgetGraphicPoint)
    case label(WidgetGraphicLabel)
    case parabola(WidgetGraphicCurve)
    case absoluteValue(WidgetGraphicCurve)
    case symbol(WidgetGraphicSymbol)

    enum CodingKeys: String, CodingKey {
        case type
        case x1
        case y1
        case x2
        case y2
        case x
        case y
        case text
        case a
        case h
        case k
        case strokeColor
        case fillColor
        case strokeWidth
        case symbol
        case size
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "line":
            self = .line(try WidgetGraphicLine(container: container))
        case "arrow":
            self = .arrow(try WidgetGraphicLine(container: container))
        case "point":
            self = .point(try WidgetGraphicPoint(container: container))
        case "label":
            self = .label(try WidgetGraphicLabel(container: container))
        case "parabola":
            self = .parabola(try WidgetGraphicCurve(container: container))
        case "absoluteValue":
            self = .absoluteValue(try WidgetGraphicCurve(container: container))
        case "symbol":
            self = .symbol(try WidgetGraphicSymbol(container: container))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unsupported graphic element type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .line(let value):
            try value.encode(into: &container, type: "line")
        case .arrow(let value):
            try value.encode(into: &container, type: "arrow")
        case .point(let value):
            try value.encode(into: &container, type: "point")
        case .label(let value):
            try value.encode(into: &container, type: "label")
        case .parabola(let value):
            try value.encode(into: &container, type: "parabola")
        case .absoluteValue(let value):
            try value.encode(into: &container, type: "absoluteValue")
        case .symbol(let value):
            try value.encode(into: &container, type: "symbol")
        }
    }
}

struct WidgetGraphicLine: Equatable, Sendable {
    var x1: Double
    var y1: Double
    var x2: Double
    var y2: Double
    var strokeColor: String?
    var strokeWidth: Double?

    init(container: KeyedDecodingContainer<WidgetGraphicElement.CodingKeys>) throws {
        x1 = try container.decode(Double.self, forKey: .x1)
        y1 = try container.decode(Double.self, forKey: .y1)
        x2 = try container.decode(Double.self, forKey: .x2)
        y2 = try container.decode(Double.self, forKey: .y2)
        strokeColor = try container.decodeIfPresent(String.self, forKey: .strokeColor)
        strokeWidth = try container.decodeIfPresent(Double.self, forKey: .strokeWidth)
    }

    func encode(into container: inout KeyedEncodingContainer<WidgetGraphicElement.CodingKeys>, type: String) throws {
        try container.encode(type, forKey: .type)
        try container.encode(x1, forKey: .x1)
        try container.encode(y1, forKey: .y1)
        try container.encode(x2, forKey: .x2)
        try container.encode(y2, forKey: .y2)
        try container.encodeIfPresent(strokeColor, forKey: .strokeColor)
        try container.encodeIfPresent(strokeWidth, forKey: .strokeWidth)
    }
}

struct WidgetGraphicPoint: Equatable, Sendable {
    var x: Double
    var y: Double
    var fillColor: String?
    var size: Double?

    init(container: KeyedDecodingContainer<WidgetGraphicElement.CodingKeys>) throws {
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        fillColor = try container.decodeIfPresent(String.self, forKey: .fillColor)
        size = try container.decodeIfPresent(Double.self, forKey: .size)
    }

    func encode(into container: inout KeyedEncodingContainer<WidgetGraphicElement.CodingKeys>, type: String) throws {
        try container.encode(type, forKey: .type)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encodeIfPresent(fillColor, forKey: .fillColor)
        try container.encodeIfPresent(size, forKey: .size)
    }
}

struct WidgetGraphicLabel: Equatable, Sendable {
    var x: Double
    var y: Double
    var text: String

    init(container: KeyedDecodingContainer<WidgetGraphicElement.CodingKeys>) throws {
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        text = try container.decode(String.self, forKey: .text)
    }

    func encode(into container: inout KeyedEncodingContainer<WidgetGraphicElement.CodingKeys>, type: String) throws {
        try container.encode(type, forKey: .type)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(text, forKey: .text)
    }
}

struct WidgetGraphicCurve: Equatable, Sendable {
    var a: WidgetExpression
    var h: WidgetExpression
    var k: WidgetExpression
    var strokeColor: String?
    var strokeWidth: Double?

    init(container: KeyedDecodingContainer<WidgetGraphicElement.CodingKeys>) throws {
        a = try container.decodeIfPresent(WidgetExpression.self, forKey: .a) ?? .value(.number(1))
        h = try container.decodeIfPresent(WidgetExpression.self, forKey: .h) ?? .value(.number(0))
        k = try container.decodeIfPresent(WidgetExpression.self, forKey: .k) ?? .value(.number(0))
        strokeColor = try container.decodeIfPresent(String.self, forKey: .strokeColor)
        strokeWidth = try container.decodeIfPresent(Double.self, forKey: .strokeWidth)
    }

    func encode(into container: inout KeyedEncodingContainer<WidgetGraphicElement.CodingKeys>, type: String) throws {
        try container.encode(type, forKey: .type)
        try container.encode(a, forKey: .a)
        try container.encode(h, forKey: .h)
        try container.encode(k, forKey: .k)
        try container.encodeIfPresent(strokeColor, forKey: .strokeColor)
        try container.encodeIfPresent(strokeWidth, forKey: .strokeWidth)
    }
}

struct WidgetGraphicSymbol: Equatable, Sendable {
    var symbol: WidgetBuiltInSymbol
    var x: Double
    var y: Double
    var size: Double?

    init(container: KeyedDecodingContainer<WidgetGraphicElement.CodingKeys>) throws {
        symbol = try container.decode(WidgetBuiltInSymbol.self, forKey: .symbol)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        size = try container.decodeIfPresent(Double.self, forKey: .size)
    }

    func encode(into container: inout KeyedEncodingContainer<WidgetGraphicElement.CodingKeys>, type: String) throws {
        try container.encode(type, forKey: .type)
        try container.encode(symbol, forKey: .symbol)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encodeIfPresent(size, forKey: .size)
    }
}

struct WidgetNativeGraph: Codable, Equatable, Sendable {
    var width: Double
    var height: Double
    var xMin: Double
    var xMax: Double
    var yMin: Double
    var yMax: Double
    var elements: [WidgetGraphElement]
}

enum WidgetGraphElement: Codable, Equatable, Sendable {
    case line(WidgetGraphLine)
    case parabola(WidgetGraphCurve)
    case absoluteValue(WidgetGraphCurve)
    case point(WidgetGraphPoint)

    enum CodingKeys: String, CodingKey {
        case type
        case slope
        case intercept
        case a
        case h
        case k
        case x
        case y
        case label
        case color
        case width
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "line":
            self = .line(try WidgetGraphLine(container: container))
        case "parabola":
            self = .parabola(try WidgetGraphCurve(container: container))
        case "absoluteValue":
            self = .absoluteValue(try WidgetGraphCurve(container: container))
        case "point":
            self = .point(try WidgetGraphPoint(container: container))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unsupported graph element type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .line(let value):
            try value.encode(into: &container)
        case .parabola(let value):
            try value.encode(into: &container, type: "parabola")
        case .absoluteValue(let value):
            try value.encode(into: &container, type: "absoluteValue")
        case .point(let value):
            try value.encode(into: &container)
        }
    }
}

struct WidgetGraphLine: Equatable, Sendable {
    var slope: WidgetExpression
    var intercept: WidgetExpression
    var color: String?
    var width: Double?

    init(container: KeyedDecodingContainer<WidgetGraphElement.CodingKeys>) throws {
        slope = try container.decodeIfPresent(WidgetExpression.self, forKey: .slope) ?? .value(.number(1))
        intercept = try container.decodeIfPresent(WidgetExpression.self, forKey: .intercept) ?? .value(.number(0))
        color = try container.decodeIfPresent(String.self, forKey: .color)
        width = try container.decodeIfPresent(Double.self, forKey: .width)
    }

    func encode(into container: inout KeyedEncodingContainer<WidgetGraphElement.CodingKeys>) throws {
        try container.encode("line", forKey: .type)
        try container.encode(slope, forKey: .slope)
        try container.encode(intercept, forKey: .intercept)
        try container.encodeIfPresent(color, forKey: .color)
        try container.encodeIfPresent(width, forKey: .width)
    }
}

struct WidgetGraphCurve: Equatable, Sendable {
    var a: WidgetExpression
    var h: WidgetExpression
    var k: WidgetExpression
    var color: String?
    var width: Double?

    init(container: KeyedDecodingContainer<WidgetGraphElement.CodingKeys>) throws {
        a = try container.decodeIfPresent(WidgetExpression.self, forKey: .a) ?? .value(.number(1))
        h = try container.decodeIfPresent(WidgetExpression.self, forKey: .h) ?? .value(.number(0))
        k = try container.decodeIfPresent(WidgetExpression.self, forKey: .k) ?? .value(.number(0))
        color = try container.decodeIfPresent(String.self, forKey: .color)
        width = try container.decodeIfPresent(Double.self, forKey: .width)
    }

    func encode(into container: inout KeyedEncodingContainer<WidgetGraphElement.CodingKeys>, type: String) throws {
        try container.encode(type, forKey: .type)
        try container.encode(a, forKey: .a)
        try container.encode(h, forKey: .h)
        try container.encode(k, forKey: .k)
        try container.encodeIfPresent(color, forKey: .color)
        try container.encodeIfPresent(width, forKey: .width)
    }
}

struct WidgetGraphPoint: Equatable, Sendable {
    var x: WidgetExpression
    var y: WidgetExpression
    var label: String?
    var color: String?

    init(container: KeyedDecodingContainer<WidgetGraphElement.CodingKeys>) throws {
        x = try container.decode(WidgetExpression.self, forKey: .x)
        y = try container.decode(WidgetExpression.self, forKey: .y)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        color = try container.decodeIfPresent(String.self, forKey: .color)
    }

    func encode(into container: inout KeyedEncodingContainer<WidgetGraphElement.CodingKeys>) throws {
        try container.encode("point", forKey: .type)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(color, forKey: .color)
    }
}

struct WidgetQuestionSet: Codable, Equatable, Sendable {
    enum Mode: String, Codable, Sendable {
        case sequential
        case random
    }

    var id: String?
    var mode: Mode
    var currentIndexStateKey: String
    var completedCountStateKey: String?
    var questions: [WidgetQuestion]
}

struct WidgetQuestion: Codable, Equatable, Sendable {
    var id: String
    var title: String?
    var metadata: [String: WidgetValue]?
    var body: WidgetComponent
}

struct WidgetAnswerCheck: Codable, Equatable, Sendable {
    var answer: WidgetExpression
    var accepted: [WidgetExpression]
    var tolerance: Double?
    var caseSensitive: Bool?
    var success: [WidgetAction]
    var failure: [WidgetAction]
}

struct WidgetButton: Codable, Equatable, Sendable {
    enum Style: String, Codable, Sendable {
        case primary
        case secondary
        case destructive
    }

    var id: String?
    var title: String
    var style: Style
    var actions: [WidgetAction]
}

struct WidgetFeedback: Codable, Equatable, Sendable {
    var id: String?
}

struct WidgetScore: Codable, Equatable, Sendable {
    var label: String
    var stateKey: String
}

enum WidgetAction: Codable, Equatable, Sendable {
    case set(stateKey: String, value: WidgetExpression)
    case increment(stateKey: String, by: WidgetExpression)
    case showFeedback(message: String, style: FeedbackStyle, animation: WidgetAnimationPreset?)
    case clearFeedback
    case playAnimation(target: String?, animation: WidgetAnimationPreset)
    case recordAttempt(questionId: String?, answerStateKeys: [String], correct: WidgetExpression)
    case checkAnswer(WidgetAnswerCheck)
    case nextQuestion(stateKey: String, count: Int, mode: WidgetQuestionSet.Mode)
    case previousQuestion(stateKey: String, count: Int)
    case jumpToQuestion(stateKey: String, index: WidgetExpression)
    case `if`(condition: WidgetCondition, then: [WidgetAction], else: [WidgetAction])
    case reset

    enum FeedbackStyle: String, Codable, Sendable {
        case neutral
        case success
        case warning
        case error
    }

    private enum CodingKeys: String, CodingKey {
        case action
        case stateKey
        case value
        case by
        case message
        case style
        case target
        case animation
        case questionId
        case answerStateKeys
        case correct
        case check
        case count
        case mode
        case index
        case condition
        case then
        case `else`
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let action = try container.decode(String.self, forKey: .action)
        switch action {
        case "set":
            self = .set(
                stateKey: try container.decode(String.self, forKey: .stateKey),
                value: try container.decode(WidgetExpression.self, forKey: .value)
            )
        case "increment":
            self = .increment(
                stateKey: try container.decode(String.self, forKey: .stateKey),
                by: try container.decodeIfPresent(WidgetExpression.self, forKey: .by) ?? .value(.number(1))
            )
        case "showFeedback":
            self = .showFeedback(
                message: try container.decode(String.self, forKey: .message),
                style: try container.decodeIfPresent(FeedbackStyle.self, forKey: .style) ?? .neutral,
                animation: try container.decodeIfPresent(WidgetAnimationPreset.self, forKey: .animation)
            )
        case "clearFeedback":
            self = .clearFeedback
        case "playAnimation":
            self = .playAnimation(
                target: try container.decodeIfPresent(String.self, forKey: .target),
                animation: try container.decode(WidgetAnimationPreset.self, forKey: .animation)
            )
        case "recordAttempt":
            self = .recordAttempt(
                questionId: try container.decodeIfPresent(String.self, forKey: .questionId),
                answerStateKeys: try container.decodeIfPresent([String].self, forKey: .answerStateKeys) ?? [],
                correct: try container.decodeIfPresent(WidgetExpression.self, forKey: .correct) ?? .value(.bool(false))
            )
        case "checkAnswer":
            self = .checkAnswer(try container.decode(WidgetAnswerCheck.self, forKey: .check))
        case "nextQuestion":
            self = .nextQuestion(
                stateKey: try container.decode(String.self, forKey: .stateKey),
                count: try container.decode(Int.self, forKey: .count),
                mode: try container.decodeIfPresent(WidgetQuestionSet.Mode.self, forKey: .mode) ?? .sequential
            )
        case "previousQuestion":
            self = .previousQuestion(
                stateKey: try container.decode(String.self, forKey: .stateKey),
                count: try container.decode(Int.self, forKey: .count)
            )
        case "jumpToQuestion":
            self = .jumpToQuestion(
                stateKey: try container.decode(String.self, forKey: .stateKey),
                index: try container.decode(WidgetExpression.self, forKey: .index)
            )
        case "if":
            self = .if(
                condition: try container.decode(WidgetCondition.self, forKey: .condition),
                then: try container.decode([WidgetAction].self, forKey: .then),
                else: try container.decodeIfPresent([WidgetAction].self, forKey: .else) ?? []
            )
        case "reset":
            self = .reset
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .action,
                in: container,
                debugDescription: "Unsupported widget action: \(action)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .set(let stateKey, let value):
            try container.encode("set", forKey: .action)
            try container.encode(stateKey, forKey: .stateKey)
            try container.encode(value, forKey: .value)
        case .increment(let stateKey, let by):
            try container.encode("increment", forKey: .action)
            try container.encode(stateKey, forKey: .stateKey)
            try container.encode(by, forKey: .by)
        case .showFeedback(let message, let style, let animation):
            try container.encode("showFeedback", forKey: .action)
            try container.encode(message, forKey: .message)
            try container.encode(style, forKey: .style)
            try container.encodeIfPresent(animation, forKey: .animation)
        case .clearFeedback:
            try container.encode("clearFeedback", forKey: .action)
        case .playAnimation(let target, let animation):
            try container.encode("playAnimation", forKey: .action)
            try container.encodeIfPresent(target, forKey: .target)
            try container.encode(animation, forKey: .animation)
        case .recordAttempt(let questionId, let answerStateKeys, let correct):
            try container.encode("recordAttempt", forKey: .action)
            try container.encodeIfPresent(questionId, forKey: .questionId)
            try container.encode(answerStateKeys, forKey: .answerStateKeys)
            try container.encode(correct, forKey: .correct)
        case .checkAnswer(let check):
            try container.encode("checkAnswer", forKey: .action)
            try container.encode(check, forKey: .check)
        case .nextQuestion(let stateKey, let count, let mode):
            try container.encode("nextQuestion", forKey: .action)
            try container.encode(stateKey, forKey: .stateKey)
            try container.encode(count, forKey: .count)
            try container.encode(mode, forKey: .mode)
        case .previousQuestion(let stateKey, let count):
            try container.encode("previousQuestion", forKey: .action)
            try container.encode(stateKey, forKey: .stateKey)
            try container.encode(count, forKey: .count)
        case .jumpToQuestion(let stateKey, let index):
            try container.encode("jumpToQuestion", forKey: .action)
            try container.encode(stateKey, forKey: .stateKey)
            try container.encode(index, forKey: .index)
        case .if(let condition, let thenActions, let elseActions):
            try container.encode("if", forKey: .action)
            try container.encode(condition, forKey: .condition)
            try container.encode(thenActions, forKey: .then)
            try container.encode(elseActions, forKey: .else)
        case .reset:
            try container.encode("reset", forKey: .action)
        }
    }
}

indirect enum WidgetExpression: Codable, Equatable, Sendable {
    case value(WidgetValue)
    case state(String)
    case randomInt(min: Int, max: Int)
    case randomChoice([WidgetExpression])
    case unary(operator: UnaryOperator, value: WidgetExpression)
    case binary(operator: BinaryOperator, left: WidgetExpression, right: WidgetExpression)
    case logical(operator: LogicalOperator, values: [WidgetExpression])
    case comparison(WidgetCondition)
    case ternary(condition: WidgetCondition, trueValue: WidgetExpression, falseValue: WidgetExpression)

    enum UnaryOperator: String, Codable, Sendable {
        case abs
        case sqrt
        case sin
        case cos
        case tan
        case not
    }

    enum BinaryOperator: String, Codable, Sendable {
        case add
        case subtract
        case multiply
        case divide
        case modulo
        case power
        case min
        case max
    }

    enum LogicalOperator: String, Codable, Sendable {
        case and
        case or
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
        case values
        case stateKey
        case min
        case max
        case `operator`
        case left
        case right
        case condition
        case trueValue
        case falseValue
    }

    init(from decoder: Decoder) throws {
        if let value = try? WidgetValue(from: decoder) {
            self = .value(value)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "value":
            self = .value(try container.decode(WidgetValue.self, forKey: .value))
        case "state":
            self = .state(try container.decode(String.self, forKey: .stateKey))
        case "randomInt":
            self = .randomInt(
                min: try container.decode(Int.self, forKey: .min),
                max: try container.decode(Int.self, forKey: .max)
            )
        case "randomChoice":
            self = .randomChoice(try container.decode([WidgetExpression].self, forKey: .values))
        case "unary":
            self = .unary(
                operator: try container.decode(UnaryOperator.self, forKey: .operator),
                value: try container.decode(WidgetExpression.self, forKey: .value)
            )
        case "binary":
            self = .binary(
                operator: try container.decode(BinaryOperator.self, forKey: .operator),
                left: try container.decode(WidgetExpression.self, forKey: .left),
                right: try container.decode(WidgetExpression.self, forKey: .right)
            )
        case "logical":
            self = .logical(
                operator: try container.decode(LogicalOperator.self, forKey: .operator),
                values: try container.decode([WidgetExpression].self, forKey: .values)
            )
        case "comparison":
            self = .comparison(try container.decode(WidgetCondition.self, forKey: .condition))
        case "ternary":
            self = .ternary(
                condition: try container.decode(WidgetCondition.self, forKey: .condition),
                trueValue: try container.decode(WidgetExpression.self, forKey: .trueValue),
                falseValue: try container.decode(WidgetExpression.self, forKey: .falseValue)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unsupported widget expression kind: \(kind)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .value(let value):
            try value.encode(to: encoder)
        case .state(let stateKey):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("state", forKey: .kind)
            try container.encode(stateKey, forKey: .stateKey)
        case .randomInt(let min, let max):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("randomInt", forKey: .kind)
            try container.encode(min, forKey: .min)
            try container.encode(max, forKey: .max)
        case .randomChoice(let values):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("randomChoice", forKey: .kind)
            try container.encode(values, forKey: .values)
        case .unary(let op, let value):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("unary", forKey: .kind)
            try container.encode(op, forKey: .operator)
            try container.encode(value, forKey: .value)
        case .binary(let op, let left, let right):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("binary", forKey: .kind)
            try container.encode(op, forKey: .operator)
            try container.encode(left, forKey: .left)
            try container.encode(right, forKey: .right)
        case .logical(let op, let values):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("logical", forKey: .kind)
            try container.encode(op, forKey: .operator)
            try container.encode(values, forKey: .values)
        case .comparison(let condition):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("comparison", forKey: .kind)
            try container.encode(condition, forKey: .condition)
        case .ternary(let condition, let trueValue, let falseValue):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("ternary", forKey: .kind)
            try container.encode(condition, forKey: .condition)
            try container.encode(trueValue, forKey: .trueValue)
            try container.encode(falseValue, forKey: .falseValue)
        }
    }
}

struct WidgetCondition: Codable, Equatable, Sendable {
    enum Relation: String, Codable, Sendable {
        case equals
        case notEquals
        case greaterThan
        case lessThan
        case greaterThanOrEquals
        case lessThanOrEquals
    }

    var left: WidgetExpression
    var relation: Relation
    var right: WidgetExpression
}

struct WidgetValidationResult: Equatable, Sendable {
    var document: MathBoardWidgetDocument?
    var errors: [String]

    var isValid: Bool {
        document != nil && errors.isEmpty
    }
}

enum WidgetJSONCodec {
    static func decode(_ source: String) -> WidgetValidationResult {
        let repairedSource = WidgetJSONRepair.escapingUnescapedLaTeXCommands(in: source)
        guard let data = repairedSource.data(using: .utf8) else {
            return WidgetValidationResult(document: nil, errors: ["Widget JSON must be valid UTF-8 text."])
        }

        do {
            let decoder = JSONDecoder()
            let document = try decoder.decode(MathBoardWidgetDocument.self, from: data)
            let errors = WidgetValidator.validate(document)
            return WidgetValidationResult(document: errors.isEmpty ? document : nil, errors: errors)
        } catch {
            return WidgetValidationResult(document: nil, errors: [error.localizedDescription])
        }
    }

    static func prettyPrint(_ document: MathBoardWidgetDocument) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(document),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

enum WidgetValidator {
    static func validate(_ document: MathBoardWidgetDocument) -> [String] {
        var errors: [String] = []
        var componentCount = 0
        if document.schemaVersion != 1 {
            errors.append("schemaVersion must be 1.")
        }
        if document.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("title is required.")
        }
        if let presentation = document.presentation {
            validate(presentation: presentation, errors: &errors)
        }
        validate(component: document.body, path: "body", depth: 0, componentCount: &componentCount, errors: &errors)
        if componentCount > 120 {
            errors.append("Widget is too large: maximum component count is 120.")
        }
        return errors
    }

    private static func validate(
        component: WidgetComponent,
        path: String,
        depth: Int,
        componentCount: inout Int,
        errors: inout [String]
    ) {
        componentCount += 1
        if depth > 12 {
            errors.append("\(path) is nested too deeply. Maximum nesting depth is 12.")
        }

        switch component {
        case .stack(let stack):
            if stack.children.isEmpty {
                errors.append("\(path).children must contain at least one component.")
            }
            for (index, child) in stack.children.enumerated() {
                validate(component: child, path: "\(path).children[\(index)]", depth: depth + 1, componentCount: &componentCount, errors: &errors)
            }
        case .grid(let grid):
            if grid.columns < 1 || grid.columns > 6 {
                errors.append("\(path).columns must be between 1 and 6.")
            }
            if grid.children.isEmpty {
                errors.append("\(path).children must contain at least one component.")
            }
            for (index, child) in grid.children.enumerated() {
                validate(component: child, path: "\(path).children[\(index)]", depth: depth + 1, componentCount: &componentCount, errors: &errors)
            }
        case .text(let text):
            if text.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("\(path).text cannot be empty.")
            }
            if text.text.count > 500 {
                errors.append("\(path).text is too long. Maximum length is 500 characters.")
            }
        case .formula(let formula):
            let hasTemplate = !(formula.template?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            let hasResult = formula.result != nil
            if !hasTemplate && !hasResult {
                errors.append("\(path) must include template, result, or both.")
            }
            if let template = formula.template, template.count > 500 {
                errors.append("\(path).template is too long. Maximum length is 500 characters.")
            }
        case .mathTemplate(let template):
            if template.parts.isEmpty {
                errors.append("\(path).parts must contain at least one part.")
            }
            if template.parts.count > 24 {
                errors.append("\(path).parts can contain at most 24 parts.")
            }
            for (index, part) in template.parts.enumerated() {
                validate(mathTemplatePart: part, path: "\(path).parts[\(index)]", errors: &errors)
            }
        case .numberInput(let input):
            if input.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("\(path).label is required.")
            }
            if input.stateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("\(path).stateKey is required.")
            }
        case .mathBox(let box):
            if box.stateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("\(path).stateKey is required.")
            }
            if box.maxLength < 1 || box.maxLength > 80 {
                errors.append("\(path).maxLength must be between 1 and 80.")
            }
        case .numberBox(let box):
            if box.stateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("\(path).stateKey is required.")
            }
            if box.maxLength < 1 {
                errors.append("\(path).maxLength must be at least 1.")
            }
        case .digitPad(let pad):
            if pad.digits.isEmpty {
                errors.append("\(path).digits must contain at least one digit.")
            }
            if pad.digits.contains(where: { $0 < 0 || $0 > 9 }) {
                errors.append("\(path).digits can only contain values from 0 through 9.")
            }
        case .mathPad(let pad):
            if pad.extraKeys.count > 12 {
                errors.append("\(path).extraKeys can contain at most 12 keys.")
            }
            for key in pad.extraKeys where key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || key.count > 8 {
                errors.append("\(path).extraKeys values must be non-empty and at most 8 characters.")
            }
        case .valueStepper(let stepper):
            validateNumericControl(label: stepper.label, stateKey: stepper.stateKey, min: stepper.min, max: stepper.max, step: stepper.step, path: path, errors: &errors)
        case .valueSlider(let slider):
            validateNumericControl(label: slider.label, stateKey: slider.stateKey, min: slider.min, max: slider.max, step: slider.step, path: path, errors: &errors)
        case .choiceGroup(let group):
            if group.stateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("\(path).stateKey is required.")
            }
            if group.choices.isEmpty {
                errors.append("\(path).choices must contain at least one choice.")
            }
            if group.choices.count > 8 {
                errors.append("\(path).choices can contain at most 8 choices.")
            }
        case .goalMeter(let meter):
            if meter.stateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("\(path).stateKey is required.")
            }
            if meter.goalValue <= 0 {
                errors.append("\(path).goalValue must be greater than 0.")
            }
        case .hintProvider(let hints):
            if hints.stateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("\(path).stateKey is required.")
            }
            if hints.hints.isEmpty {
                errors.append("\(path).hints must contain at least one hint.")
            }
            if hints.hints.count > 5 {
                errors.append("\(path).hints can contain at most 5 hints.")
            }
        case .symbolCollection(let symbols):
            if symbols.countStateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("\(path).countStateKey is required.")
            }
            if symbols.maxCount < 1 || symbols.maxCount > 20 {
                errors.append("\(path).maxCount must be between 1 and 20.")
            }
        case .graphic(let graphic):
            if graphic.elements.isEmpty {
                errors.append("\(path).elements must contain at least one graphic element.")
            }
            if graphic.elements.count > 40 {
                errors.append("\(path).elements can contain at most 40 elements.")
            }
        case .nativeGraph(let graph):
            if graph.xMin >= graph.xMax {
                errors.append("\(path).xMin must be less than xMax.")
            }
            if graph.yMin >= graph.yMax {
                errors.append("\(path).yMin must be less than yMax.")
            }
            if graph.elements.isEmpty {
                errors.append("\(path).elements must contain at least one graph element.")
            }
            if graph.elements.count > 16 {
                errors.append("\(path).elements can contain at most 16 elements.")
            }
        case .questionSet(let set):
            if set.currentIndexStateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("\(path).currentIndexStateKey is required.")
            }
            if set.questions.isEmpty {
                errors.append("\(path).questions must contain at least one question.")
            }
            if set.questions.count > 40 {
                errors.append("\(path).questions can contain at most 40 questions.")
            }
            for (index, question) in set.questions.enumerated() {
                if question.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    errors.append("\(path).questions[\(index)].id is required.")
                }
                validate(component: question.body, path: "\(path).questions[\(index)].body", depth: depth + 1, componentCount: &componentCount, errors: &errors)
            }
        case .button(let button):
            if button.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("\(path).title is required.")
            }
            if button.actions.isEmpty {
                errors.append("\(path).actions must contain at least one action.")
            }
        case .feedback, .score, .divider:
            break
        }
    }

    private static func validateNumericControl(
        label: String,
        stateKey: String,
        min: Double,
        max: Double,
        step: Double,
        path: String,
        errors: inout [String]
    ) {
        if label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("\(path).label is required.")
        }
        if stateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("\(path).stateKey is required.")
        }
        if min >= max {
            errors.append("\(path).min must be less than max.")
        }
        if step <= 0 {
            errors.append("\(path).step must be greater than 0.")
        }
    }

    private static func validate(presentation: WidgetPresentationMetadata, errors: inout [String]) {
        if let width = presentation.preferredWidth, width < 280 || width > 900 {
            errors.append("presentation.preferredWidth must be between 280 and 900.")
        }
        if let height = presentation.preferredHeight, height < 240 || height > 1200 {
            errors.append("presentation.preferredHeight must be between 240 and 1200.")
        }
    }

    private static func validate(mathTemplatePart: WidgetMathTemplatePart, path: String, errors: inout [String]) {
        switch mathTemplatePart {
        case .text(let text):
            if text.text.isEmpty {
                errors.append("\(path).text cannot be empty.")
            }
            if text.text.count > 40 {
                errors.append("\(path).text can contain at most 40 characters.")
            }
        case .numberBox(let box):
            if box.stateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("\(path).stateKey is required.")
            }
            if box.maxLength < 1 {
                errors.append("\(path).maxLength must be at least 1.")
            }
        }
    }
}
