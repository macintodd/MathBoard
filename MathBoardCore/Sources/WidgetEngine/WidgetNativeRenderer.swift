//
//  WidgetNativeRenderer.swift
//  WidgetEngine
//
//  Native SwiftUI renderer for MathBoard Widget JSON. The renderer owns widget
//  state locally for previews; future canvas integration can lift this state out.
//

import SwiftUI

struct WidgetNativeRenderer: View {
    let document: MathBoardWidgetDocument

    @State private var state: [String: WidgetValue]
    @State private var feedbackMessage = "Ready"
    @State private var feedbackStyle = WidgetAction.FeedbackStyle.neutral
    @State private var activeNumberBoxKey: String?
    @State private var feedbackAnimation: WidgetAnimationPreset?
    @State private var animationTick = 0

    init(document: MathBoardWidgetDocument) {
        self.document = document
        _state = State(initialValue: document.initialState)
    }

    var body: some View {
        Group {
            if document.presentation?.scroll == .disabled {
                widgetContent
            } else {
                ScrollView {
                    widgetContent
                }
            }
        }
        .background(Color(white: 0.97))
    }

    private var widgetContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(document.title)
                    .font(.title2.weight(.bold))
                if let description = document.description, !description.isEmpty {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            render(document.body)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func render(_ component: WidgetComponent) -> AnyView {
        switch component {
        case .stack(let stack):
            if stack.axis == .horizontal {
                return decorated(AnyView(HStack(alignment: .center, spacing: CGFloat(stack.spacing)) {
                    ForEach(Array(stack.children.enumerated()), id: \.offset) { _, child in
                        render(child)
                    }
                }), with: stack.decoration)
            } else {
                return decorated(AnyView(VStack(alignment: .leading, spacing: CGFloat(stack.spacing)) {
                    ForEach(Array(stack.children.enumerated()), id: \.offset) { _, child in
                        render(child)
                    }
                }), with: stack.decoration)
            }
        case .grid(let grid):
            let columns = Array(repeating: GridItem(.flexible(), spacing: CGFloat(grid.spacing)), count: grid.columns)
            return decorated(AnyView(LazyVGrid(columns: columns, alignment: .leading, spacing: CGFloat(grid.spacing)) {
                ForEach(Array(grid.children.enumerated()), id: \.offset) { _, child in
                    render(child)
                }
            }), with: grid.decoration)
        case .text(let text):
            return AnyView(textView(text))
        case .formula(let formula):
            return AnyView(formulaView(formula))
        case .mathTemplate(let template):
            return AnyView(mathTemplate(template))
        case .numberInput(let input):
            return AnyView(numberInput(input))
        case .mathBox(let box):
            return AnyView(mathBox(box))
        case .numberBox(let box):
            return AnyView(numberBox(box))
        case .digitPad(let pad):
            return AnyView(digitPad(pad))
        case .mathPad(let pad):
            return AnyView(mathPad(pad))
        case .valueStepper(let stepper):
            return AnyView(valueStepper(stepper))
        case .valueSlider(let slider):
            return AnyView(valueSlider(slider))
        case .choiceGroup(let group):
            return AnyView(choiceGroup(group))
        case .goalMeter(let meter):
            return AnyView(goalMeter(meter))
        case .hintProvider(let provider):
            return AnyView(hintProvider(provider))
        case .symbolCollection(let collection):
            return AnyView(symbolCollection(collection))
        case .graphic(let graphic):
            return AnyView(graphicView(graphic))
        case .nativeGraph(let graph):
            return AnyView(nativeGraph(graph))
        case .questionSet(let set):
            return AnyView(questionSet(set))
        case .button(let button):
            return buttonView(button)
        case .feedback:
            return AnyView(feedbackView)
        case .score(let score):
            return AnyView(scoreView(score))
        case .divider:
            return AnyView(Divider())
        }
    }

    private func textView(_ text: WidgetText) -> some View {
        let renderedText = interpolated(text.text)
        return Group {
            if text.role == .math {
                WidgetMathTextView(
                    source: renderedText,
                    fontSize: 21,
                    weight: .semibold,
                    fallbackDesign: .serif,
                    foregroundColor: .primary,
                    alignment: .leading,
                    lineLimit: 2,
                    minimumScaleFactor: 0.75
                )
            } else {
                Text(renderedText)
                    .font(font(for: text.role))
                    .foregroundStyle(text.role == .caption ? .secondary : .primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func font(for role: WidgetText.Role) -> Font {
        switch role {
        case .title:
            return .title3.weight(.bold)
        case .subtitle:
            return .headline
        case .body:
            return .body
        case .caption:
            return .caption
        case .math:
            return .system(.title3, design: .serif).weight(.semibold)
        }
    }

    private func formulaView(_ formula: WidgetFormula) -> some View {
        let renderedTemplate = formula.template.map(interpolated) ?? ""
        let renderedResult = formula.result.map { evaluate($0).displayString } ?? ""

        return VStack(alignment: .leading, spacing: 6) {
            if let label = formula.label, !label.isEmpty {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            switch formula.displayMode {
            case .formulaOnly:
                WidgetMathTextView(
                    source: renderedTemplate,
                    fontSize: 21,
                    weight: .semibold,
                    fallbackDesign: .serif,
                    foregroundColor: .primary,
                    alignment: .leading,
                    lineLimit: 2,
                    minimumScaleFactor: 0.75
                )
            case .valueOnly:
                WidgetMathTextView(
                    source: renderedResult,
                    fontSize: 21,
                    weight: .semibold,
                    fallbackDesign: .serif,
                    foregroundColor: .primary,
                    alignment: .leading,
                    lineLimit: 1,
                    minimumScaleFactor: 0.75
                )
            case .formulaAndValue:
                HStack(spacing: 8) {
                    WidgetMathTextView(
                        source: renderedTemplate,
                        fontSize: 21,
                        weight: .semibold,
                        fallbackDesign: .serif,
                        foregroundColor: .primary,
                        alignment: .leading,
                        lineLimit: 1,
                        minimumScaleFactor: 0.7
                    )
                    Text("=")
                    WidgetMathTextView(
                        source: renderedResult,
                        fontSize: 21,
                        weight: .semibold,
                        fallbackDesign: .serif,
                        foregroundColor: .primary,
                        alignment: .leading,
                        lineLimit: 1,
                        minimumScaleFactor: 0.7
                    )
                }
                .font(.system(.title3, design: .serif).weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func mathTemplate(_ template: WidgetMathTemplate) -> some View {
        let metrics = mathTemplateMetrics(for: template.fontScale)

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .center, spacing: CGFloat(template.spacing)) {
                ForEach(Array(template.parts.enumerated()), id: \.offset) { _, part in
                    switch part {
                    case .text(let text):
                        Text(interpolated(text.text))
                            .font(.system(size: metrics.fontSize, weight: .semibold, design: .serif))
                            .minimumScaleFactor(0.72)
                            .lineLimit(1)
                            .frame(height: metrics.boxSize, alignment: .center)
                    case .numberBox(let box):
                        mathTemplateNumberBox(box, metrics: metrics)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func mathTemplateNumberBox(_ box: WidgetMathTemplateNumberBoxPart, metrics: WidgetMathTemplateMetrics) -> some View {
        let isActive = activeNumberBoxKey == box.stateKey
        let value = state[box.stateKey]?.displayString ?? ""
        let displayText = value.isEmpty ? (box.placeholder ?? "") : value

        return Button {
            if box.clearOnSelect {
                state[box.stateKey] = .string("")
            }
            activeNumberBoxKey = box.stateKey
        } label: {
            Text(displayText)
                .font(.system(size: metrics.inputFontSize, weight: .bold, design: .rounded))
                .foregroundStyle(value.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(width: metrics.boxSize, height: metrics.boxSize)
                .background(isActive ? Color.blue.opacity(0.18) : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                        .strokeBorder(isActive ? Color.blue : Color.primary.opacity(0.18), lineWidth: isActive ? 3 : 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func mathTemplateMetrics(for scale: WidgetMathTemplate.FontScale) -> WidgetMathTemplateMetrics {
        switch scale {
        case .compact:
            return WidgetMathTemplateMetrics(fontSize: 30, inputFontSize: 22, boxSize: 46, cornerRadius: 8)
        case .regular:
            return WidgetMathTemplateMetrics(fontSize: 38, inputFontSize: 26, boxSize: 54, cornerRadius: 9)
        case .large:
            return WidgetMathTemplateMetrics(fontSize: 46, inputFontSize: 30, boxSize: 62, cornerRadius: 10)
        }
    }

    private func numberInput(_ input: WidgetNumberInput) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(input.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(input.placeholder ?? "Enter a number", text: binding(for: input.stateKey))
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .keyboardType(.numbersAndPunctuation)
                #endif
        }
        .frame(maxWidth: 220, alignment: .leading)
    }

    private func numberBox(_ box: WidgetNumberBox) -> some View {
        let isActive = activeNumberBoxKey == box.stateKey
        let value = state[box.stateKey]?.displayString ?? ""
        let displayText = value.isEmpty ? (box.placeholder ?? "") : value

        return VStack(spacing: 6) {
            if let label = box.label, !label.isEmpty {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Button {
                if box.clearOnSelect {
                    state[box.stateKey] = .string("")
                }
                activeNumberBoxKey = box.stateKey
            } label: {
                Text(displayText)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(value.isEmpty ? .secondary : .primary)
                    .frame(width: 58, height: 58)
                    .background(isActive ? Color.blue.opacity(0.18) : Color.white)
                    .overlay(numberBoxBorder(shape: box.shape, isActive: isActive))
                    .clipShape(shape(for: box.shape))
            }
            .buttonStyle(.plain)
        }
    }

    private func mathBox(_ box: WidgetMathBox) -> some View {
        let isActive = activeNumberBoxKey == box.stateKey
        let value = state[box.stateKey]?.displayString ?? ""
        let displayText = value.isEmpty ? (box.placeholder ?? "") : value

        return VStack(alignment: .leading, spacing: 6) {
            if let label = box.label, !label.isEmpty {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Button {
                if box.clearOnSelect {
                    state[box.stateKey] = .string("")
                }
                activeNumberBoxKey = box.stateKey
            } label: {
                Text(displayText)
                    .font(.title3.weight(.bold).monospaced())
                    .foregroundStyle(value.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .frame(minWidth: 92, maxWidth: .infinity, minHeight: 54, alignment: .center)
                    .padding(.horizontal, 12)
                    .background(isActive ? Color.blue.opacity(0.18) : Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(isActive ? Color.blue : Color.primary.opacity(0.18), lineWidth: isActive ? 3 : 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: 320, alignment: .leading)
    }

    private func digitPad(_ pad: WidgetDigitPad) -> some View {
        let columns = Array(repeating: GridItem(.fixed(46), spacing: 8), count: 5)

        return LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(pad.digits, id: \.self) { digit in
                Button {
                    appendDigit(digit)
                } label: {
                    Text(String(digit))
                        .font(.title3.weight(.bold))
                        .frame(width: 46, height: 46)
                        .background(Color.blue.opacity(activeNumberBoxKey == nil ? 0.06 : 0.14))
                        .overlay(digitPadBorder(shape: pad.shape))
                        .clipShape(shape(for: pad.shape))
                }
                .buttonStyle(.plain)
                .disabled(activeNumberBoxKey == nil)
                .opacity(activeNumberBoxKey == nil ? 0.45 : 1)
            }
        }
    }

    private func mathPad(_ pad: WidgetMathPad) -> some View {
        let keys = mathPadKeys(for: pad)
        let columns = [GridItem(.adaptive(minimum: 46), spacing: 8)]

        return LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(keys, id: \.self) { key in
                Button {
                    appendInput(key)
                } label: {
                    Text(mathPadLabel(for: key))
                        .font(.callout.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: key == "clear" ? 70 : 46, height: 46)
                        .background(Color.blue.opacity(activeNumberBoxKey == nil ? 0.06 : 0.14))
                        .overlay(digitPadBorder(shape: pad.shape))
                        .clipShape(shape(for: pad.shape))
                }
                .buttonStyle(.plain)
                .disabled(activeNumberBoxKey == nil)
                .opacity(activeNumberBoxKey == nil ? 0.45 : 1)
            }
        }
    }

    private func valueStepper(_ stepper: WidgetValueStepper) -> some View {
        HStack(spacing: 10) {
            Text(stepper.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                adjust(stepper.stateKey, by: -stepper.step, min: stepper.min, max: stepper.max)
            } label: {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.plain)
            Text(state[stepper.stateKey]?.displayString ?? "0")
                .font(.headline.monospacedDigit())
                .frame(minWidth: 44)
            Button {
                adjust(stepper.stateKey, by: stepper.step, min: stepper.min, max: stepper.max)
            } label: {
                Image(systemName: "plus.circle.fill")
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.white.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func valueSlider(_ slider: WidgetValueSlider) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(slider.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(state[slider.stateKey]?.displayString ?? "0")
                    .font(.caption.weight(.bold).monospacedDigit())
            }
            Slider(
                value: Binding(
                    get: { state[slider.stateKey]?.numberValue ?? slider.min },
                    set: { newValue in
                        let stepped = (newValue / slider.step).rounded() * slider.step
                        state[slider.stateKey] = .number(min(max(stepped, slider.min), slider.max))
                    }
                ),
                in: slider.min...slider.max
            )
        }
        .padding(10)
        .background(Color.white.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func buttonView(_ button: WidgetButton) -> AnyView {
        switch button.style {
        case .primary:
            return AnyView(Button {
                run(button.actions)
            } label: {
                Text(button.title)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue))
        case .secondary:
            return AnyView(Button {
                run(button.actions)
            } label: {
                Text(button.title)
            }
            .buttonStyle(.bordered))
        case .destructive:
            return AnyView(Button(role: .destructive) {
                run(button.actions)
            } label: {
                Text(button.title)
            }
            .buttonStyle(.bordered)
            .tint(.red))
        }
    }

    private var feedbackView: some View {
        Text(feedbackMessage)
            .font(.callout.weight(.semibold))
            .foregroundStyle(feedbackColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(feedbackColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(feedbackAnimation == .pulse ? 1.03 : 1)
            .offset(x: feedbackAnimation == .shake && animationTick.isMultiple(of: 2) ? -4 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.45), value: animationTick)
    }

    private func scoreView(_ score: WidgetScore) -> some View {
        HStack(spacing: 8) {
            Text(score.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(state[score.stateKey]?.displayString ?? "0")
                .font(.title3.weight(.bold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func choiceGroup(_ group: WidgetChoiceGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let label = group.label, !label.isEmpty {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            let selected = state[group.stateKey]?.displayString
            let columns = [GridItem(.adaptive(minimum: group.style == .buttons ? 120 : 72), spacing: 8)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(Array(group.choices.enumerated()), id: \.offset) { _, choice in
                    Button {
                        state[group.stateKey] = choice.value
                    } label: {
                        Text(choice.label)
                            .font(.callout.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(selected == choice.value.displayString ? Color.blue.opacity(0.20) : Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: group.style == .pills ? 18 : 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: group.style == .pills ? 18 : 8, style: .continuous)
                                    .strokeBorder(selected == choice.value.displayString ? Color.blue : Color.primary.opacity(0.14), lineWidth: selected == choice.value.displayString ? 2 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func goalMeter(_ meter: WidgetGoalMeter) -> some View {
        let current = state[meter.stateKey]?.numberValue ?? 0
        let progress = min(max(current / max(meter.goalValue, 1), 0), 1)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(meter.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(current))/\(Int(meter.goalValue))")
                    .font(.caption.weight(.bold))
            }

            if meter.style == .radial {
                ZStack {
                    Circle()
                        .stroke(Color.blue.opacity(0.16), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(progress * 100))%")
                        .font(.caption.weight(.bold))
                }
                .frame(width: 72, height: 72)
            } else {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.blue.opacity(0.12))
                        Capsule()
                            .fill(Color.blue)
                            .frame(width: proxy.size.width * progress)
                    }
                }
                .frame(height: 14)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func hintProvider(_ provider: WidgetHintProvider) -> some View {
        let level = Int(state[provider.stateKey]?.numberValue ?? 0)
        let visibleHints = provider.hints.prefix(max(0, min(level, provider.hints.count)))

        return VStack(alignment: .leading, spacing: 8) {
            Button(provider.title) {
                let next = min(level + 1, provider.hints.count)
                state[provider.stateKey] = .number(Double(next))
            }
            .buttonStyle(.bordered)

            ForEach(Array(visibleHints.enumerated()), id: \.offset) { index, hint in
                Text("\(index + 1). \(interpolated(hint))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.yellow.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func symbolCollection(_ collection: WidgetSymbolCollection) -> some View {
        let count = min(max(Int(state[collection.countStateKey]?.numberValue ?? 0), 0), collection.maxCount)
        let columns = collection.style == .wrap ? [GridItem(.adaptive(minimum: 34), spacing: 6)] : Array(repeating: GridItem(.fixed(34), spacing: 6), count: max(collection.maxCount, 1))

        return LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(0..<collection.maxCount, id: \.self) { index in
                Image(systemName: systemImageName(for: collection.symbol))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(index < count ? Color.orange : Color.primary.opacity(0.18))
                    .frame(width: 34, height: 34)
                    .background(index < count ? Color.orange.opacity(0.12) : Color.clear)
                    .clipShape(Circle())
            }
        }
    }

    private func graphicView(_ graphic: WidgetGraphic) -> some View {
        ZStack {
            Canvas { context, size in
                for element in graphic.elements {
                    drawGraphicElement(element, context: &context, size: size)
                }
            }
            ForEach(Array(graphic.elements.enumerated()), id: \.offset) { _, element in
                if case .label(let label) = element {
                    Text(interpolated(label.text))
                        .font(.caption.weight(.semibold))
                        .position(x: label.x * graphic.width, y: label.y * graphic.height)
                } else if case .symbol(let symbol) = element {
                    Image(systemName: systemImageName(for: symbol.symbol))
                        .font(.system(size: symbol.size ?? 32, weight: .bold))
                        .foregroundStyle(.orange)
                        .position(x: symbol.x * graphic.width, y: symbol.y * graphic.height)
                }
            }
        }
        .frame(width: graphic.width, height: graphic.height)
        .modifier(WidgetDecorationModifier(decoration: graphic.decoration))
    }

    private func nativeGraph(_ graph: WidgetNativeGraph) -> some View {
        ZStack {
            Canvas { context, size in
                drawGraphGrid(graph, context: &context, size: size)
                for element in graph.elements {
                    drawGraphElement(element, graph: graph, context: &context, size: size)
                }
            }
        }
        .frame(width: graph.width, height: graph.height)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
        )
    }

    private func questionSet(_ set: WidgetQuestionSet) -> some View {
        let count = set.questions.count
        let rawIndex = Int(state[set.currentIndexStateKey]?.numberValue ?? 0)
        let index = min(max(rawIndex, 0), max(count - 1, 0))

        return VStack(alignment: .leading, spacing: 10) {
            if count > 0 {
                HStack {
                    Text("Question \(index + 1) of \(count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let completedKey = set.completedCountStateKey {
                        Text("\(Int(state[completedKey]?.numberValue ?? 0)) complete")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                if let title = set.questions[index].title {
                    Text(interpolated(title))
                        .font(.headline)
                }

                render(set.questions[index].body)
            }
        }
    }

    private var feedbackColor: Color {
        switch feedbackStyle {
        case .neutral:
            return .secondary
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { state[key]?.displayString ?? "" },
            set: { newValue in
                if let number = Double(newValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    state[key] = .number(number)
                } else {
                    state[key] = .string(newValue)
                }
            }
        )
    }

    private func interpolated(_ template: String) -> String {
        var output = template
        for (key, value) in state {
            output = output.replacingOccurrences(of: "{{\(key)}}", with: value.displayString)
        }
        return output
    }

    private func run(_ actions: [WidgetAction]) {
        for action in actions {
            run(action)
        }
    }

    private func run(_ action: WidgetAction) {
        switch action {
        case .set(let stateKey, let value):
            state[stateKey] = evaluate(value)
        case .increment(let stateKey, let by):
            let current = state[stateKey]?.numberValue ?? 0
            let delta = evaluate(by).numberValue ?? 0
            state[stateKey] = .number(current + delta)
        case .showFeedback(let message, let style, let animation):
            feedbackMessage = interpolated(message)
            feedbackStyle = style
            trigger(animation)
        case .clearFeedback:
            feedbackMessage = "Ready"
            feedbackStyle = .neutral
            feedbackAnimation = nil
        case .playAnimation(_, let animation):
            trigger(animation)
        case .recordAttempt:
            break
        case .checkAnswer(let check):
            run(answerCheckPassed(check) ? check.success : check.failure)
        case .nextQuestion(let stateKey, let count, let mode):
            let current = Int(state[stateKey]?.numberValue ?? 0)
            switch mode {
            case .sequential:
                state[stateKey] = .number(Double((current + 1) % max(count, 1)))
            case .random:
                state[stateKey] = .number(Double(Int.random(in: 0..<max(count, 1))))
            }
        case .previousQuestion(let stateKey, let count):
            let current = Int(state[stateKey]?.numberValue ?? 0)
            state[stateKey] = .number(Double((current - 1 + max(count, 1)) % max(count, 1)))
        case .jumpToQuestion(let stateKey, let index):
            let target = max(Int(evaluate(index).numberValue ?? 0), 0)
            state[stateKey] = .number(Double(target))
        case .if(let condition, let thenActions, let elseActions):
            run(evaluate(condition) ? thenActions : elseActions)
        case .reset:
            state = document.initialState
            activeNumberBoxKey = nil
            feedbackMessage = "Ready"
            feedbackStyle = .neutral
            feedbackAnimation = nil
        }
    }

    private func evaluate(_ expression: WidgetExpression) -> WidgetValue {
        switch expression {
        case .value(let value):
            return value
        case .state(let key):
            return state[key] ?? .string("")
        case .randomInt(let min, let max):
            return .number(Double(Int.random(in: min...max)))
        case .randomChoice(let values):
            return values.randomElement().map(evaluate) ?? .string("")
        case .unary(let op, let value):
            let evaluated = evaluate(value)
            switch op {
            case .abs:
                return .number(abs(evaluated.numberValue ?? 0))
            case .sqrt:
                return .number(sqrt(max(evaluated.numberValue ?? 0, 0)))
            case .sin:
                return .number(sin(evaluated.numberValue ?? 0))
            case .cos:
                return .number(cos(evaluated.numberValue ?? 0))
            case .tan:
                return .number(tan(evaluated.numberValue ?? 0))
            case .not:
                return .bool(!evaluated.boolValue)
            }
        case .binary(let op, let left, let right):
            let leftValue = evaluate(left).numberValue ?? 0
            let rightValue = evaluate(right).numberValue ?? 0
            switch op {
            case .add:
                return .number(leftValue + rightValue)
            case .subtract:
                return .number(leftValue - rightValue)
            case .multiply:
                return .number(leftValue * rightValue)
            case .divide:
                guard rightValue != 0 else { return .number(0) }
                return .number(leftValue / rightValue)
            case .modulo:
                guard rightValue != 0 else { return .number(0) }
                return .number(leftValue.truncatingRemainder(dividingBy: rightValue))
            case .power:
                return .number(pow(leftValue, rightValue))
            case .min:
                return .number(min(leftValue, rightValue))
            case .max:
                return .number(max(leftValue, rightValue))
            }
        case .logical(let op, let values):
            switch op {
            case .and:
                return .bool(values.allSatisfy { evaluate($0).boolValue })
            case .or:
                return .bool(values.contains { evaluate($0).boolValue })
            }
        case .comparison(let condition):
            return .bool(evaluate(condition))
        case .ternary(let condition, let trueValue, let falseValue):
            return evaluate(evaluate(condition) ? trueValue : falseValue)
        }
    }

    private func answerCheckPassed(_ check: WidgetAnswerCheck) -> Bool {
        let answer = evaluate(check.answer)
        return check.accepted.contains { acceptedExpression in
            let accepted = evaluate(acceptedExpression)
            if let tolerance = check.tolerance,
               let answerNumber = answer.numberValue,
               let acceptedNumber = accepted.numberValue {
                return abs(answerNumber - acceptedNumber) <= tolerance
            }

            let answerText = answer.displayString.trimmingCharacters(in: .whitespacesAndNewlines)
            let acceptedText = accepted.displayString.trimmingCharacters(in: .whitespacesAndNewlines)
            if check.caseSensitive == true {
                return answerText == acceptedText
            }
            return answerText.lowercased() == acceptedText.lowercased()
        }
    }

    private func evaluate(_ condition: WidgetCondition) -> Bool {
        let left = evaluate(condition.left)
        let right = evaluate(condition.right)
        if let leftNumber = left.numberValue, let rightNumber = right.numberValue {
            switch condition.relation {
            case .equals:
                return leftNumber == rightNumber
            case .notEquals:
                return leftNumber != rightNumber
            case .greaterThan:
                return leftNumber > rightNumber
            case .lessThan:
                return leftNumber < rightNumber
            case .greaterThanOrEquals:
                return leftNumber >= rightNumber
            case .lessThanOrEquals:
                return leftNumber <= rightNumber
            }
        }

        switch condition.relation {
        case .equals:
            return left.displayString == right.displayString
        case .notEquals:
            return left.displayString != right.displayString
        case .greaterThan, .lessThan, .greaterThanOrEquals, .lessThanOrEquals:
            return false
        }
    }

    private func appendDigit(_ digit: Int) {
        appendInput(String(digit))
    }

    private func appendInput(_ input: String) {
        guard let key = activeNumberBoxKey else { return }
        let maxLength = maxLength(for: key)
        let current = state[key]?.displayString ?? ""
        let nextValue: String

        switch input {
        case "delete":
            nextValue = String(current.dropLast())
        case "clear":
            nextValue = ""
        default:
            nextValue = String((current + input).prefix(maxLength))
        }

        if !isMathBoxStateKey(key), let number = Double(nextValue), !nextValue.isEmpty {
            state[key] = .number(number)
        } else {
            state[key] = .string(nextValue)
        }
    }

    private func maxLength(for stateKey: String) -> Int {
        maxLength(for: document.body, stateKey: stateKey) ?? 2
    }

    private func maxLength(for component: WidgetComponent, stateKey: String) -> Int? {
        switch component {
        case .stack(let stack):
            for child in stack.children {
                if let maxLength = maxLength(for: child, stateKey: stateKey) {
                    return maxLength
                }
            }
            return nil
        case .grid(let grid):
            for child in grid.children {
                if let maxLength = maxLength(for: child, stateKey: stateKey) {
                    return maxLength
                }
            }
            return nil
        case .mathBox(let box):
            return box.stateKey == stateKey ? box.maxLength : nil
        case .numberBox(let box):
            return box.stateKey == stateKey ? box.maxLength : nil
        case .text, .formula, .numberInput, .digitPad, .mathPad, .valueStepper, .valueSlider, .choiceGroup, .goalMeter, .hintProvider,
                .symbolCollection, .graphic, .nativeGraph, .questionSet, .button, .feedback, .score, .divider:
            return nil
        case .mathTemplate(let template):
            for part in template.parts {
                if case .numberBox(let box) = part, box.stateKey == stateKey {
                    return box.maxLength
                }
            }
            return nil
        }
    }

    private func isMathBoxStateKey(_ stateKey: String) -> Bool {
        isMathBoxStateKey(stateKey, in: document.body)
    }

    private func isMathBoxStateKey(_ stateKey: String, in component: WidgetComponent) -> Bool {
        switch component {
        case .stack(let stack):
            return stack.children.contains { isMathBoxStateKey(stateKey, in: $0) }
        case .grid(let grid):
            return grid.children.contains { isMathBoxStateKey(stateKey, in: $0) }
        case .mathBox(let box):
            return box.stateKey == stateKey
        case .text, .formula, .mathTemplate, .numberInput, .numberBox, .digitPad, .mathPad, .valueStepper, .valueSlider,
                .choiceGroup, .goalMeter, .hintProvider, .symbolCollection, .graphic, .nativeGraph, .questionSet, .button,
                .feedback, .score, .divider:
            return false
        }
    }

    private func mathPadKeys(for pad: WidgetMathPad) -> [String] {
        var keys: [String]
        switch pad.preset {
        case .numeric:
            keys = ["7", "8", "9", "4", "5", "6", "1", "2", "3", "0"]
        case .integer:
            keys = ["7", "8", "9", "4", "5", "6", "1", "2", "3", "-", "0"]
        case .operations:
            keys = ["+", "-", "*", "/", "^", "=", "(", ")"]
        case .algebra:
            keys = ["x", "y", "n", "+", "-", "*", "/", "^", "(", ")", "2"]
        case .calculator:
            keys = ["7", "8", "9", "/", "4", "5", "6", "*", "1", "2", "3", "-", "0", ".", "^", "+", "(", ")"]
        }
        keys.append(contentsOf: pad.extraKeys)
        keys.append(contentsOf: ["delete", "clear"])
        return keys
    }

    private func mathPadLabel(for key: String) -> String {
        switch key {
        case "delete":
            return "del"
        case "clear":
            return "clear"
        default:
            return key
        }
    }

    private func numberBoxBorder(shape inputShape: WidgetInputShape, isActive: Bool) -> some View {
        shape(for: inputShape)
            .strokeBorder(isActive ? Color.blue : Color.primary.opacity(0.18), lineWidth: isActive ? 3 : 1)
    }

    private func digitPadBorder(shape inputShape: WidgetInputShape) -> some View {
        shape(for: inputShape)
            .strokeBorder(Color.blue.opacity(0.28), lineWidth: 1)
    }

    private func shape(for shape: WidgetInputShape) -> WidgetInputClipShape {
        WidgetInputClipShape(shape: shape)
    }

    private func trigger(_ animation: WidgetAnimationPreset?) {
        feedbackAnimation = animation
        animationTick += 1
        guard animation != nil else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            feedbackAnimation = nil
        }
    }

    private func adjust(_ stateKey: String, by delta: Double, min: Double, max: Double) {
        let current = state[stateKey]?.numberValue ?? 0
        state[stateKey] = .number(Swift.min(Swift.max(current + delta, min), max))
    }

    private func decorated(_ view: AnyView, with decoration: WidgetDecoration?) -> AnyView {
        AnyView(view.modifier(WidgetDecorationModifier(decoration: decoration)))
    }

    private func drawGraphicElement(_ element: WidgetGraphicElement, context: inout GraphicsContext, size: CGSize) {
        switch element {
        case .line(let line), .arrow(let line):
            var path = Path()
            path.move(to: CGPoint(x: line.x1 * size.width, y: line.y1 * size.height))
            path.addLine(to: CGPoint(x: line.x2 * size.width, y: line.y2 * size.height))
            context.stroke(path, with: .color(color(line.strokeColor, fallback: .blue)), lineWidth: line.strokeWidth ?? 3)
        case .point(let point):
            let radius = (point.size ?? 10) / 2
            let rect = CGRect(x: point.x * size.width - radius, y: point.y * size.height - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(color(point.fillColor, fallback: .orange)))
        case .parabola(let curve):
            context.stroke(curvePath(curve, absoluteValue: false, size: size), with: .color(color(curve.strokeColor, fallback: .orange)), lineWidth: curve.strokeWidth ?? 3)
        case .absoluteValue(let curve):
            context.stroke(curvePath(curve, absoluteValue: true, size: size), with: .color(color(curve.strokeColor, fallback: .purple)), lineWidth: curve.strokeWidth ?? 3)
        case .label, .symbol:
            break
        }
    }

    private func curvePath(_ curve: WidgetGraphicCurve, absoluteValue: Bool, size: CGSize) -> Path {
        let a = evaluate(curve.a).numberValue ?? 1
        let h = evaluate(curve.h).numberValue ?? 0
        let k = evaluate(curve.k).numberValue ?? 0
        var path = Path()
        for index in 0...80 {
            let t = Double(index) / 80
            let x = (t - 0.5) * 4
            let y = absoluteValue ? a * abs(x - h) + k : a * pow(x - h, 2) + k
            let point = CGPoint(x: t * size.width, y: size.height * (0.82 - y / 8))
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }

    private func drawGraphGrid(_ graph: WidgetNativeGraph, context: inout GraphicsContext, size: CGSize) {
        var grid = Path()
        for x in Int(ceil(graph.xMin))...Int(floor(graph.xMax)) {
            let pointX = graphPoint(x: Double(x), y: 0, graph: graph, size: size).x
            grid.move(to: CGPoint(x: pointX, y: 0))
            grid.addLine(to: CGPoint(x: pointX, y: size.height))
        }
        for y in Int(ceil(graph.yMin))...Int(floor(graph.yMax)) {
            let pointY = graphPoint(x: 0, y: Double(y), graph: graph, size: size).y
            grid.move(to: CGPoint(x: 0, y: pointY))
            grid.addLine(to: CGPoint(x: size.width, y: pointY))
        }
        context.stroke(grid, with: .color(Color.primary.opacity(0.08)), lineWidth: 1)

        var axes = Path()
        let origin = graphPoint(x: 0, y: 0, graph: graph, size: size)
        axes.move(to: CGPoint(x: 0, y: origin.y))
        axes.addLine(to: CGPoint(x: size.width, y: origin.y))
        axes.move(to: CGPoint(x: origin.x, y: 0))
        axes.addLine(to: CGPoint(x: origin.x, y: size.height))
        context.stroke(axes, with: .color(Color.primary.opacity(0.32)), lineWidth: 1.5)
    }

    private func drawGraphElement(_ element: WidgetGraphElement, graph: WidgetNativeGraph, context: inout GraphicsContext, size: CGSize) {
        switch element {
        case .line(let line):
            let slope = evaluate(line.slope).numberValue ?? 1
            let intercept = evaluate(line.intercept).numberValue ?? 0
            var path = Path()
            let left = graphPoint(x: graph.xMin, y: slope * graph.xMin + intercept, graph: graph, size: size)
            let right = graphPoint(x: graph.xMax, y: slope * graph.xMax + intercept, graph: graph, size: size)
            path.move(to: left)
            path.addLine(to: right)
            context.stroke(path, with: .color(color(line.color, fallback: .blue)), lineWidth: line.width ?? 3)
        case .parabola(let curve):
            context.stroke(graphCurvePath(curve, absoluteValue: false, graph: graph, size: size), with: .color(color(curve.color, fallback: .orange)), lineWidth: curve.width ?? 3)
        case .absoluteValue(let curve):
            context.stroke(graphCurvePath(curve, absoluteValue: true, graph: graph, size: size), with: .color(color(curve.color, fallback: .purple)), lineWidth: curve.width ?? 3)
        case .point(let point):
            let x = evaluate(point.x).numberValue ?? 0
            let y = evaluate(point.y).numberValue ?? 0
            let center = graphPoint(x: x, y: y, graph: graph, size: size)
            context.fill(Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)), with: .color(color(point.color, fallback: .red)))
        }
    }

    private func graphCurvePath(_ curve: WidgetGraphCurve, absoluteValue: Bool, graph: WidgetNativeGraph, size: CGSize) -> Path {
        let a = evaluate(curve.a).numberValue ?? 1
        let h = evaluate(curve.h).numberValue ?? 0
        let k = evaluate(curve.k).numberValue ?? 0
        var path = Path()
        for index in 0...120 {
            let t = Double(index) / 120
            let x = graph.xMin + (graph.xMax - graph.xMin) * t
            let y = absoluteValue ? a * abs(x - h) + k : a * pow(x - h, 2) + k
            let point = graphPoint(x: x, y: y, graph: graph, size: size)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }

    private func graphPoint(x: Double, y: Double, graph: WidgetNativeGraph, size: CGSize) -> CGPoint {
        let xRatio = (x - graph.xMin) / (graph.xMax - graph.xMin)
        let yRatio = (y - graph.yMin) / (graph.yMax - graph.yMin)
        return CGPoint(x: xRatio * size.width, y: (1 - yRatio) * size.height)
    }

    private func systemImageName(for symbol: WidgetBuiltInSymbol) -> String {
        switch symbol {
        case .star:
            return "star.fill"
        case .basketball:
            return "basketball.fill"
        case .target:
            return "target"
        case .coin:
            return "centsign.circle.fill"
        case .numberTile:
            return "number.square.fill"
        case .trophy:
            return "trophy.fill"
        case .rocket:
            return "rocket.fill"
        case .checkmark:
            return "checkmark.circle.fill"
        }
    }

    private func color(_ hex: String?, fallback: Color) -> Color {
        guard let hex else { return fallback }
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard trimmed.count == 6, let value = Int(trimmed, radix: 16) else { return fallback }
        let red = Double((value >> 16) & 0xff) / 255
        let green = Double((value >> 8) & 0xff) / 255
        let blue = Double(value & 0xff) / 255
        return Color(red: red, green: green, blue: blue)
    }
}

private struct WidgetDecorationModifier: ViewModifier {
    var decoration: WidgetDecoration?

    func body(content: Content) -> some View {
        let padding = decoration?.padding ?? 0
        let cornerRadius = decoration?.cornerRadius ?? 0
        let fill = color(decoration?.fill, fallback: .clear)
        let border = color(decoration?.borderColor, fallback: .clear)
        let borderWidth = decoration?.borderWidth ?? 0

        content
            .padding(CGFloat(padding))
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(border, lineWidth: borderWidth)
            )
    }

    private func color(_ hex: String?, fallback: Color) -> Color {
        guard let hex else { return fallback }
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard trimmed.count == 6, let value = Int(trimmed, radix: 16) else { return fallback }
        let red = Double((value >> 16) & 0xff) / 255
        let green = Double((value >> 8) & 0xff) / 255
        let blue = Double(value & 0xff) / 255
        return Color(red: red, green: green, blue: blue)
    }
}

private struct WidgetInputClipShape: InsettableShape {
    var shape: WidgetInputShape
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        switch shape {
        case .circle:
            return Circle().path(in: insetRect)
        case .square:
            return Rectangle().path(in: insetRect)
        case .roundedSquare:
            return RoundedRectangle(cornerRadius: 10, style: .continuous).path(in: insetRect)
        }
    }

    func inset(by amount: CGFloat) -> WidgetInputClipShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

private struct WidgetMathTemplateMetrics {
    var fontSize: CGFloat
    var inputFontSize: CGFloat
    var boxSize: CGFloat
    var cornerRadius: CGFloat
}

struct WidgetValidationView: View {
    let source: String

    private var result: WidgetValidationResult {
        WidgetJSONCodec.decode(source)
    }

    var body: some View {
        if let document = result.document {
            WidgetNativeRenderer(document: document)
                .frame(
                    width: preferredWidth(for: document),
                    height: preferredHeight(for: document)
                )
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Label("Widget JSON is not valid", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                    .foregroundStyle(.red)
                ForEach(result.errors, id: \.self) { error in
                    Text(error)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.red.opacity(0.05))
        }
    }

    private func preferredWidth(for document: MathBoardWidgetDocument) -> CGFloat? {
        guard let width = document.presentation?.preferredWidth else { return nil }
        return CGFloat(width)
    }

    private func preferredHeight(for document: MathBoardWidgetDocument) -> CGFloat? {
        guard let height = document.presentation?.preferredHeight else { return nil }
        return CGFloat(height)
    }
}

#Preview("Native Widget") {
    WidgetNativeRenderer(document: WidgetSamples.factorPairsDocument)
        .frame(width: 420, height: 560)
}

#Preview("Schema Showcase") {
    WidgetValidationView(source: WidgetSamples.algebraShowcaseJSON)
        .frame(width: 420, height: 720)
}

#Preview("Math Template") {
    WidgetValidationView(source: WidgetSamples.mathTemplateShowcaseJSON)
        .frame(width: 520, height: 420)
}
