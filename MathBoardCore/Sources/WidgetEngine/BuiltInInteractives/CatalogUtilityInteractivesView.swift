//
//  CatalogUtilityInteractivesView.swift
//  WidgetEngine
//
//  Lightweight built-in classroom utilities exposed through the Mathtivity Catalog.
//

import Observation
import SwiftUI

@MainActor
@Observable
final class CountdownTimerState {
    var durationMinutes = 5
    var remainingSeconds = 300
    var isRunning = false

    @ObservationIgnored private var timerTask: Task<Void, Never>?

    var timeDisplay: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func setDurationMinutes(_ value: Int) {
        durationMinutes = value
        guard !isRunning else { return }
        remainingSeconds = value * 60
    }

    func toggleRunning() {
        isRunning ? pause() : start()
    }

    func reset() {
        pause()
        remainingSeconds = durationMinutes * 60
    }

    func stop() {
        pause()
    }

    private func start() {
        if remainingSeconds == 0 {
            remainingSeconds = durationMinutes * 60
        }
        isRunning = true
        timerTask?.cancel()
        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, self.isRunning else { return }
                if self.remainingSeconds > 0 {
                    self.remainingSeconds -= 1
                }
                if self.remainingSeconds == 0 {
                    self.pause()
                    return
                }
            }
        }
    }

    private func pause() {
        isRunning = false
        timerTask?.cancel()
        timerTask = nil
    }
}

@MainActor
enum CountdownTimerStateRegistry {
    private static var statesByWidgetID: [WidgetObject.ID: CountdownTimerState] = [:]

    static func state(for widgetID: WidgetObject.ID) -> CountdownTimerState {
        if let state = statesByWidgetID[widgetID] {
            return state
        }
        let state = CountdownTimerState()
        statesByWidgetID[widgetID] = state
        return state
    }

    static func removeState(for widgetID: WidgetObject.ID) {
        statesByWidgetID[widgetID]?.stop()
        statesByWidgetID.removeValue(forKey: widgetID)
    }
}

struct CountdownTimerInteractiveView: View {
    @Bindable var state: CountdownTimerState

    var body: some View {
        VStack(spacing: 18) {
            Text(state.timeDisplay)
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.55)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            Stepper("Duration: \(state.durationMinutes) min", value: durationMinutesBinding, in: 1...60)

            HStack(spacing: 12) {
                Button {
                    state.toggleRunning()
                } label: {
                    Label(state.isRunning ? "Pause" : "Start", systemImage: state.isRunning ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    state.reset()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private var durationMinutesBinding: Binding<Int> {
        Binding(
            get: { state.durationMinutes },
            set: { state.setDurationMinutes($0) }
        )
    }
}

@MainActor
@Observable
final class RandomNumberGeneratorState {
    var lowerBound = 1
    var upperBound = 10
    var result = 1

    func setLowerBound(_ value: Int) {
        lowerBound = value
        if lowerBound > upperBound { upperBound = lowerBound }
        result = result.clamped(to: lowerBound...upperBound)
    }

    func setUpperBound(_ value: Int) {
        upperBound = value
        if upperBound < lowerBound { lowerBound = upperBound }
        result = result.clamped(to: lowerBound...upperBound)
    }

    func generate() {
        result = Int.random(in: lowerBound...upperBound)
    }
}

@MainActor
enum RandomNumberGeneratorStateRegistry {
    private static var statesByWidgetID: [WidgetObject.ID: RandomNumberGeneratorState] = [:]

    static func state(for widgetID: WidgetObject.ID) -> RandomNumberGeneratorState {
        if let state = statesByWidgetID[widgetID] {
            return state
        }
        let state = RandomNumberGeneratorState()
        statesByWidgetID[widgetID] = state
        return state
    }

    static func removeState(for widgetID: WidgetObject.ID) {
        statesByWidgetID.removeValue(forKey: widgetID)
    }
}

struct RandomNumberGeneratorInteractiveView: View {
    @Bindable var state: RandomNumberGeneratorState

    var body: some View {
        VStack(spacing: 18) {
            Text("\(state.result)")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            VStack(spacing: 10) {
                Stepper("Minimum: \(state.lowerBound)", value: lowerBoundBinding, in: -999...999)
                Stepper("Maximum: \(state.upperBound)", value: upperBoundBinding, in: -999...999)
            }

            Button {
                state.generate()
            } label: {
                Label("Generate", systemImage: "dice.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private var lowerBoundBinding: Binding<Int> {
        Binding(
            get: { state.lowerBound },
            set: { state.setLowerBound($0) }
        )
    }

    private var upperBoundBinding: Binding<Int> {
        Binding(
            get: { state.upperBound },
            set: { state.setUpperBound($0) }
        )
    }
}

@MainActor
@Observable
final class FunctionTransformationExplorerState {
    var a: Double = 1
    var h: Double = 0
    var k: Double = 0

    var equationDisplay: String {
        let aText = Self.formatted(a)
        let hText = Self.formatted(abs(h))
        let kText = Self.formatted(abs(k))
        let hSign = h >= 0 ? "-" : "+"
        let kSign = k >= 0 ? "+" : "-"
        return "y = \(aText)(x \(hSign) \(hText))² \(kSign) \(kText)"
    }

    func reset() {
        a = 1
        h = 0
        k = 0
    }

    private static func formatted(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return "\(Int(rounded))"
        }
        return String(format: "%.1f", rounded)
    }
}

@MainActor
enum FunctionTransformationExplorerStateRegistry {
    private static var statesByWidgetID: [WidgetObject.ID: FunctionTransformationExplorerState] = [:]

    static func state(for widgetID: WidgetObject.ID) -> FunctionTransformationExplorerState {
        if let state = statesByWidgetID[widgetID] {
            return state
        }
        let state = FunctionTransformationExplorerState()
        statesByWidgetID[widgetID] = state
        return state
    }

    static func removeState(for widgetID: WidgetObject.ID) {
        statesByWidgetID.removeValue(forKey: widgetID)
    }
}

struct FunctionTransformationExplorerInteractiveView: View {
    @Bindable var state: FunctionTransformationExplorerState

    var body: some View {
        VStack(spacing: 14) {
            FunctionTransformationGraphView(a: state.a, h: state.h, k: state.k)
                .aspectRatio(1.35, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )

            VStack(spacing: 10) {
                Text(state.equationDisplay)
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                parameterSlider("a", value: $state.a, range: -3...3, step: 0.1)
                parameterSlider("h", value: $state.h, range: -6...6, step: 0.5)
                parameterSlider("k", value: $state.k, range: -6...6, step: 0.5)

                Button {
                    state.reset()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private func parameterSlider(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .frame(width: 18)
            Slider(value: value, in: range, step: step)
            Text(String(format: "%.1f", value.wrappedValue))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 46, alignment: .trailing)
        }
    }
}

private struct FunctionTransformationGraphView: View {
    var a: Double
    var h: Double
    var k: Double

    var body: some View {
        Canvas { context, size in
            let bounds = CoordinateBounds(xMinimum: -8, xMaximum: 8, yMinimum: -8, yMaximum: 8)
            let mapper = CoordinateGridMapper(size: size, bounds: bounds)
            drawGrid(in: &context, mapper: mapper, bounds: bounds)
            drawParabola(in: &context, mapper: mapper, bounds: bounds)
            drawVertex(in: &context, mapper: mapper)
        }
    }

    private func drawGrid(
        in context: inout GraphicsContext,
        mapper: CoordinateGridMapper,
        bounds: CoordinateBounds
    ) {
        for x in bounds.xMinimum...bounds.xMaximum {
            var path = Path()
            path.move(to: mapper.point(x: x, y: bounds.yMinimum))
            path.addLine(to: mapper.point(x: x, y: bounds.yMaximum))
            context.stroke(path, with: .color(x == 0 ? .black.opacity(0.75) : .gray.opacity(0.22)), lineWidth: x == 0 ? 1.6 : 0.6)
        }

        for y in bounds.yMinimum...bounds.yMaximum {
            var path = Path()
            path.move(to: mapper.point(x: bounds.xMinimum, y: y))
            path.addLine(to: mapper.point(x: bounds.xMaximum, y: y))
            context.stroke(path, with: .color(y == 0 ? .black.opacity(0.75) : .gray.opacity(0.22)), lineWidth: y == 0 ? 1.6 : 0.6)
        }
    }

    private func drawParabola(
        in context: inout GraphicsContext,
        mapper: CoordinateGridMapper,
        bounds: CoordinateBounds
    ) {
        var path = Path()
        var didMove = false
        let sampleCount = 240
        for index in 0...sampleCount {
            let ratio = Double(index) / Double(sampleCount)
            let x = Double(bounds.xMinimum) + (Double(bounds.xMaximum - bounds.xMinimum) * ratio)
            let y = a * pow(x - h, 2) + k
            guard y.isFinite,
                  y >= Double(bounds.yMinimum) - 2,
                  y <= Double(bounds.yMaximum) + 2 else {
                didMove = false
                continue
            }
            let point = mapper.point(x: x, y: y)
            if didMove {
                path.addLine(to: point)
            } else {
                path.move(to: point)
                didMove = true
            }
        }
        context.stroke(path, with: .color(.blue), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
    }

    private func drawVertex(in context: inout GraphicsContext, mapper: CoordinateGridMapper) {
        let point = mapper.point(x: h, y: k)
        let rect = CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
        context.fill(Path(ellipseIn: rect), with: .color(.red))
        context.stroke(Path(ellipseIn: rect.insetBy(dx: -2, dy: -2)), with: .color(.white), lineWidth: 2)
    }
}

@MainActor
@Observable
final class CoordinateGridGeneratorState {
    var xMinimum = 0
    var xMaximum = 10
    var yMinimum = 0
    var yMaximum = 10
    var gridStep = 1
    var majorStep = 5
    var labelStep = 5
    var showFullGridlines = true
    var showAxisNumbers = true
    var showAxisLabels = false
    var showAxisArrows = true
    var usesSquareUnits = false
    var xAxisLabel = ""
    var yAxisLabel = ""
    var minorGridDarkness = 0.38
    var majorGridDarkness = 0.58
    var axisDarkness = 0.9

    func normalizeBounds() {
        if xMinimum >= xMaximum { xMaximum = xMinimum + 1 }
        if yMinimum >= yMaximum { yMaximum = yMinimum + 1 }
        gridStep = max(1, gridStep)
        majorStep = max(gridStep, majorStep)
        labelStep = max(gridStep, labelStep)
    }
}

@MainActor
enum CoordinateGridGeneratorStateRegistry {
    private static var statesByWidgetID: [WidgetObject.ID: CoordinateGridGeneratorState] = [:]

    static func state(for widgetID: WidgetObject.ID) -> CoordinateGridGeneratorState {
        if let state = statesByWidgetID[widgetID] {
            return state
        }
        let state = CoordinateGridGeneratorState()
        statesByWidgetID[widgetID] = state
        return state
    }

    static func removeState(for widgetID: WidgetObject.ID) {
        statesByWidgetID.removeValue(forKey: widgetID)
    }
}

struct CoordinateGridGeneratorInteractiveView: View {
    @Bindable var state: CoordinateGridGeneratorState
    var onMathInputRequested: (@MainActor (WidgetMathInputKeypadRequest) -> Void)?
    var onImageInsertionRequested: (@MainActor (WidgetCanvasImageInsertionRequest) -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            CoordinateGridPreview(state: state)
                .aspectRatio(1.55, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )

            settingsPanel
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private var settingsPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    captureGridImage()
                } label: {
                    Label("Photo", systemImage: "camera.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(onImageInsertionRequested == nil)

                Toggle("Number axes", isOn: $state.showAxisNumbers)
                Toggle("Full gridlines", isOn: $state.showFullGridlines)
                Toggle("Axis arrows", isOn: $state.showAxisArrows)
                Button {
                    state.usesSquareUnits.toggle()
                } label: {
                    Label("Square", systemImage: state.usesSquareUnits ? "square.fill" : "square")
                }
                .buttonStyle(.bordered)
                .tint(state.usesSquareUnits ? .green : .secondary)
            }
            .font(.system(size: 13))

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    integerControl("x min", value: xMinimumBinding, range: -50...49, field: .xMinimum)
                    integerControl("x max", value: xMaximumBinding, range: -49...50, field: .xMaximum)
                }
                GridRow {
                    integerControl("y min", value: yMinimumBinding, range: -50...49, field: .yMinimum)
                    integerControl("y max", value: yMaximumBinding, range: -49...50, field: .yMaximum)
                }
                GridRow {
                    integerControl("Minor Grid", value: gridStepBinding, range: 1...10, field: .gridStep)
                    integerControl("Major Grid", value: majorStepBinding, range: 1...20, field: .majorStep)
                }
                GridRow {
                    integerControl("Labels", value: labelStepBinding, range: 1...20, field: .labelStep)
                    EmptyView()
                }
            }
            .font(.system(size: 13))

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    darknessSlider("Minor Grid", value: $state.minorGridDarkness)
                    darknessSlider("Major Grid", value: $state.majorGridDarkness)
                }
                GridRow {
                    darknessSlider("Axis", value: $state.axisDarkness)
                    EmptyView()
                }
            }

            HStack(spacing: 10) {
                Toggle("Axis labels", isOn: $state.showAxisLabels)
                    .fixedSize()
                textControl("x-axis", text: $state.xAxisLabel, field: .xAxisLabel)
                textControl("y-axis", text: $state.yAxisLabel, field: .yAxisLabel)
            }
            .font(.system(size: 13, weight: .semibold))
        }
        .onChange(of: state.xMinimum) { _, _ in state.normalizeBounds() }
        .onChange(of: state.xMaximum) { _, _ in state.normalizeBounds() }
        .onChange(of: state.yMinimum) { _, _ in state.normalizeBounds() }
        .onChange(of: state.yMaximum) { _, _ in state.normalizeBounds() }
        .onChange(of: state.gridStep) { _, _ in state.normalizeBounds() }
        .onChange(of: state.majorStep) { _, _ in state.normalizeBounds() }
        .onChange(of: state.labelStep) { _, _ in state.normalizeBounds() }
    }

    private func integerControl(
        _ label: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        field: CoordinateGridInputField
    ) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
            Button {
                requestIntegerInput(field, value: value, range: range)
            } label: {
                Text("\(value.wrappedValue)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(minWidth: 44)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Stepper(label, value: value, in: range)
                .labelsHidden()
                .fixedSize()
        }
    }

    private func textControl(
        _ label: String,
        text: Binding<String>,
        field: CoordinateGridInputField
    ) -> some View {
        Button {
            requestTextInput(field, text: text)
        } label: {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(text.wrappedValue.isEmpty ? " " : text.wrappedValue)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(text.wrappedValue.isEmpty ? Color.secondary.opacity(0.55) : Color.primary)
                    .frame(minWidth: 72, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private func darknessSlider(_ label: String, value: Binding<Double>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 74, alignment: .leading)
            Slider(value: value, in: 0.15...1)
                .frame(minWidth: 110)
        }
    }

    private var xMinimumBinding: Binding<Int> { integerBinding(\.xMinimum) }
    private var xMaximumBinding: Binding<Int> { integerBinding(\.xMaximum) }
    private var yMinimumBinding: Binding<Int> { integerBinding(\.yMinimum) }
    private var yMaximumBinding: Binding<Int> { integerBinding(\.yMaximum) }
    private var gridStepBinding: Binding<Int> { integerBinding(\.gridStep) }
    private var majorStepBinding: Binding<Int> { integerBinding(\.majorStep) }
    private var labelStepBinding: Binding<Int> { integerBinding(\.labelStep) }

    private func integerBinding(_ keyPath: ReferenceWritableKeyPath<CoordinateGridGeneratorState, Int>) -> Binding<Int> {
        Binding(
            get: { state[keyPath: keyPath] },
            set: {
                state[keyPath: keyPath] = $0
                state.normalizeBounds()
            }
        )
    }

    private func requestIntegerInput(
        _ field: CoordinateGridInputField,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) {
        guard let onMathInputRequested else { return }
        var draft = "\(value.wrappedValue)"
        var hasEdited = false
        onMathInputRequested(WidgetMathInputKeypadRequest(
            id: "coordinate-grid.\(field.rawValue)",
            title: field.title,
            kind: .numeric,
            applyAction: { action in
                switch action {
                case .insert(let text):
                    draft = hasEdited ? draft + text : text
                    hasEdited = true
                case .deleteBackward:
                    if !hasEdited {
                        draft = ""
                        hasEdited = true
                    } else if !draft.isEmpty {
                        draft.removeLast()
                    }
                case .clear:
                    draft = ""
                    hasEdited = true
                case .moveCursorLeft, .moveCursorRight:
                    break
                case .returnKey:
                    return
                }

                if let parsed = Int(draft) {
                    value.wrappedValue = parsed.clamped(to: range)
                }
            }
        ))
    }

    private func requestTextInput(
        _ field: CoordinateGridInputField,
        text: Binding<String>
    ) {
        guard let onMathInputRequested else { return }
        var draft = text.wrappedValue
        var hasEdited = false
        onMathInputRequested(WidgetMathInputKeypadRequest(
            id: "coordinate-grid.\(field.rawValue)",
            title: field.title,
            kind: .alphanumeric,
            applyAction: { action in
                switch action {
                case .insert(let value):
                    draft = hasEdited ? draft + value : value
                    hasEdited = true
                case .deleteBackward:
                    if !hasEdited {
                        draft = ""
                        hasEdited = true
                    } else if !draft.isEmpty {
                        draft.removeLast()
                    }
                case .clear:
                    draft = ""
                    hasEdited = true
                case .moveCursorLeft, .moveCursorRight:
                    break
                case .returnKey:
                    return
                }
                text.wrappedValue = draft
            }
        ))
    }

    private func captureGridImage() {
        guard let onImageInsertionRequested else { return }
        #if os(iOS)
        let size = CGSize(width: 900, height: 580)
        let renderer = ImageRenderer(
            content: CoordinateGridPreview(state: state)
                .frame(width: size.width, height: size.height)
                .background(Color.white)
        )
        renderer.scale = 2
        guard let image = renderer.uiImage,
              let pngData = image.pngData() else {
            return
        }
        onImageInsertionRequested(WidgetCanvasImageInsertionRequest(
            title: "Coordinate grid",
            pngData: pngData,
            displaySize: CGSize(width: 540, height: 348)
        ))
        #endif
    }
}

private struct CoordinateGridPreview: View {
    var state: CoordinateGridGeneratorState

    var body: some View {
        Canvas { context, size in
            let bounds = CoordinateBounds(
                xMinimum: state.xMinimum,
                xMaximum: max(state.xMinimum + 1, state.xMaximum),
                yMinimum: state.yMinimum,
                yMaximum: max(state.yMinimum + 1, state.yMaximum)
            )
            let mapper = CoordinateGridMapper(
                size: size,
                bounds: bounds,
                usesSquareUnits: state.usesSquareUnits
            )
            let gridStep = max(1, state.gridStep)
            let majorStep = max(gridStep, state.majorStep)
            let labelStep = max(gridStep, state.labelStep)

            drawGridLines(
                in: &context,
                mapper: mapper,
                bounds: bounds,
                gridStep: gridStep,
                majorStep: majorStep
            )
            drawAxis(in: &context, mapper: mapper, bounds: bounds)

            if state.showAxisNumbers {
                drawAxisNumbers(
                    in: &context,
                    mapper: mapper,
                    bounds: bounds,
                    labelStep: labelStep
                )
            }

            if state.showAxisLabels {
                drawAxisLabels(in: &context, size: size)
            }
        }
    }

    private func drawGridLines(
        in context: inout GraphicsContext,
        mapper: CoordinateGridMapper,
        bounds: CoordinateBounds,
        gridStep: Int,
        majorStep: Int
    ) {
        for x in stride(from: bounds.xMinimum, through: bounds.xMaximum, by: gridStep) {
            let isMajor = x == 0 || x.isMultiple(of: majorStep)
            if state.showFullGridlines {
                var path = Path()
                path.move(to: mapper.point(x: x, y: bounds.yMinimum))
                path.addLine(to: mapper.point(x: x, y: bounds.yMaximum))
                context.stroke(path, with: .color(isMajor ? majorGridColor : minorGridColor), lineWidth: isMajor ? 1.1 : 0.55)
            } else {
                drawTick(at: mapper.point(x: x, y: 0), orientation: .vertical, isMajor: isMajor, in: &context)
            }
        }

        for y in stride(from: bounds.yMinimum, through: bounds.yMaximum, by: gridStep) {
            let isMajor = y == 0 || y.isMultiple(of: majorStep)
            if state.showFullGridlines {
                var path = Path()
                path.move(to: mapper.point(x: bounds.xMinimum, y: y))
                path.addLine(to: mapper.point(x: bounds.xMaximum, y: y))
                context.stroke(path, with: .color(isMajor ? majorGridColor : minorGridColor), lineWidth: isMajor ? 1.1 : 0.55)
            } else {
                drawTick(at: mapper.point(x: 0, y: y), orientation: .horizontal, isMajor: isMajor, in: &context)
            }
        }
    }

    private func drawTick(
        at point: CGPoint,
        orientation: TickOrientation,
        isMajor: Bool,
        in context: inout GraphicsContext
    ) {
        let tickLength: CGFloat = isMajor ? 12 : 7
        var path = Path()
        switch orientation {
        case .vertical:
            path.move(to: CGPoint(x: point.x, y: point.y - tickLength / 2))
            path.addLine(to: CGPoint(x: point.x, y: point.y + tickLength / 2))
        case .horizontal:
            path.move(to: CGPoint(x: point.x - tickLength / 2, y: point.y))
            path.addLine(to: CGPoint(x: point.x + tickLength / 2, y: point.y))
        }
        context.stroke(path, with: .color(majorGridColor), lineWidth: isMajor ? 1.1 : 0.8)
    }

    private func drawAxis(
        in context: inout GraphicsContext,
        mapper: CoordinateGridMapper,
        bounds: CoordinateBounds
    ) {
        if bounds.yMinimum <= 0 && bounds.yMaximum >= 0 {
            var xAxis = Path()
            xAxis.move(to: mapper.point(x: bounds.xMinimum, y: 0))
            xAxis.addLine(to: mapper.point(x: bounds.xMaximum, y: 0))
            context.stroke(xAxis, with: .color(axisColor), lineWidth: 2.2)

            if state.showAxisArrows {
                drawArrowhead(at: mapper.point(x: bounds.xMaximum, y: 0), angle: 0, in: &context)
                drawArrowhead(at: mapper.point(x: bounds.xMinimum, y: 0), angle: .pi, in: &context)
            }
        }

        if bounds.xMinimum <= 0 && bounds.xMaximum >= 0 {
            var yAxis = Path()
            yAxis.move(to: mapper.point(x: 0, y: bounds.yMinimum))
            yAxis.addLine(to: mapper.point(x: 0, y: bounds.yMaximum))
            context.stroke(yAxis, with: .color(axisColor), lineWidth: 2.2)

            if state.showAxisArrows {
                drawArrowhead(at: mapper.point(x: 0, y: bounds.yMaximum), angle: -.pi / 2, in: &context)
                drawArrowhead(at: mapper.point(x: 0, y: bounds.yMinimum), angle: .pi / 2, in: &context)
            }
        }
    }

    private func drawAxisNumbers(
        in context: inout GraphicsContext,
        mapper: CoordinateGridMapper,
        bounds: CoordinateBounds,
        labelStep: Int
    ) {
        if bounds.yMinimum <= 0 && bounds.yMaximum >= 0 {
            for x in stride(from: bounds.xMinimum, through: bounds.xMaximum, by: labelStep) where x != 0 {
                let point = mapper.point(x: x, y: 0)
                drawLabel("\(x)", at: CGPoint(x: point.x, y: point.y + 16), anchor: .top, in: &context)
            }
        }

        if bounds.xMinimum <= 0 && bounds.xMaximum >= 0 {
            for y in stride(from: bounds.yMinimum, through: bounds.yMaximum, by: labelStep) where y != 0 {
                let point = mapper.point(x: 0, y: y)
                drawLabel("\(y)", at: CGPoint(x: point.x - 10, y: point.y), anchor: .trailing, in: &context)
            }
        }
    }

    private func drawAxisLabels(in context: inout GraphicsContext, size: CGSize) {
        let xLabel = state.xAxisLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let yLabel = state.yAxisLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !xLabel.isEmpty {
            drawLabel(xLabel, at: CGPoint(x: size.width - 18, y: size.height - 18), anchor: .trailing, in: &context)
        }
        if !yLabel.isEmpty {
            drawLabel(yLabel, at: CGPoint(x: 18, y: 18), anchor: .leading, in: &context)
        }
    }

    private func drawLabel(
        _ text: String,
        at point: CGPoint,
        anchor: UnitPoint,
        in context: inout GraphicsContext
    ) {
        let resolved = context.resolve(
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(axisColor)
        )
        context.draw(resolved, at: point, anchor: anchor)
    }

    private func drawArrowhead(at point: CGPoint, angle: CGFloat, in context: inout GraphicsContext) {
        let length: CGFloat = 10
        let spread: CGFloat = .pi / 7
        var path = Path()
        path.move(to: point)
        path.addLine(to: CGPoint(
            x: point.x - length * cos(angle - spread),
            y: point.y - length * sin(angle - spread)
        ))
        path.move(to: point)
        path.addLine(to: CGPoint(
            x: point.x - length * cos(angle + spread),
            y: point.y - length * sin(angle + spread)
        ))
        context.stroke(path, with: .color(axisColor), lineWidth: 2.2)
    }

    private var minorGridColor: Color {
        Color.black.opacity(state.minorGridDarkness * 0.45)
    }

    private var majorGridColor: Color {
        Color.black.opacity(state.majorGridDarkness * 0.62)
    }

    private var axisColor: Color {
        Color.black.opacity(state.axisDarkness)
    }
}

private enum CoordinateGridInputField: String {
    case xMinimum
    case xMaximum
    case yMinimum
    case yMaximum
    case gridStep
    case majorStep
    case labelStep
    case xAxisLabel
    case yAxisLabel

    var title: String {
        switch self {
        case .xMinimum: return "x minimum"
        case .xMaximum: return "x maximum"
        case .yMinimum: return "y minimum"
        case .yMaximum: return "y maximum"
        case .gridStep: return "Minor Grid"
        case .majorStep: return "Major Grid"
        case .labelStep: return "Labels"
        case .xAxisLabel: return "x-axis label"
        case .yAxisLabel: return "y-axis label"
        }
    }
}

private enum TickOrientation {
    case horizontal
    case vertical
}

private struct CoordinateBounds {
    var xMinimum: Int
    var xMaximum: Int
    var yMinimum: Int
    var yMaximum: Int
}

private struct CoordinateGridMapper {
    var size: CGSize
    var bounds: CoordinateBounds
    var usesSquareUnits: Bool = false

    func point(x: Int, y: Int) -> CGPoint {
        point(x: Double(x), y: Double(y))
    }

    func point(x: Double, y: Double) -> CGPoint {
        let xRange = CGFloat(bounds.xMaximum - bounds.xMinimum)
        let yRange = CGFloat(bounds.yMaximum - bounds.yMinimum)

        if usesSquareUnits {
            let unit = min(size.width / max(xRange, 0.001), size.height / max(yRange, 0.001))
            let plotWidth = xRange * unit
            let plotHeight = yRange * unit
            let xInset = (size.width - plotWidth) / 2
            let yInset = (size.height - plotHeight) / 2
            let xPosition = xInset + CGFloat(x - Double(bounds.xMinimum)) * unit
            let yPosition = yInset + plotHeight - CGFloat(y - Double(bounds.yMinimum)) * unit
            return CGPoint(x: xPosition, y: yPosition)
        }

        let xPosition = CGFloat(x - Double(bounds.xMinimum)) / xRange * size.width
        let yPosition = size.height - CGFloat(y - Double(bounds.yMinimum)) / yRange * size.height
        return CGPoint(x: xPosition, y: yPosition)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
