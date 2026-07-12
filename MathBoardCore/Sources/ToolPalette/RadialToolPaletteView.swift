//
//  RadialToolPaletteView.swift
//  MathBoardCore - ToolPalette module
//

import SwiftUI

public struct RadialToolPaletteView: View {
    @Binding private var state: ToolPaletteState
    @State private var isColorPickerPresented = false
    @State private var isPaletteChooserPresented = false
    @State private var isLatexEditorPresented = false
    @State private var isFontPickerPresented = false
    @State private var colorPickerTarget: PaletteColorPickerTarget = .stroke
    @State private var latexDraft = ""
    private let dialSize: CGFloat
    private let onCommand: (ToolPaletteCommand) -> Void
    private let onResolvedCommand: (ToolPaletteCommand, ToolPaletteState) -> Void
    /// When set, tapping the center hero invokes this instead of re-selecting the
    /// active tool. The floating wrapper uses it to collapse the dial.
    private let onHeroTap: (() -> Void)?

    // `onCommand` stays the first function parameter so existing trailing-closure
    // call sites bind to it; `onHeroTap` follows with a default.
    public init(
        state: Binding<ToolPaletteState>,
        dialSize: CGFloat = 360,
        onCommand: @escaping (ToolPaletteCommand) -> Void = { _ in },
        onResolvedCommand: @escaping (ToolPaletteCommand, ToolPaletteState) -> Void = { _, _ in },
        onHeroTap: (() -> Void)? = nil
    ) {
        self._state = state
        self.dialSize = dialSize
        self.onCommand = onCommand
        self.onResolvedCommand = onResolvedCommand
        self.onHeroTap = onHeroTap
    }

    public var body: some View {
        let layout = RadialPaletteLayout(dialSize: dialSize)
        let definition = ToolPaletteDefinitions.definition(for: state.activeTool)
        let configuration = definition.configuration(for: state)

        ZStack {
            paletteShell
            toolSegments(layout: layout)
            topOrbit(configuration.topOrbit, layout: layout)
            bottomArc(configuration.leftArc, side: .left)
            bottomArc(configuration.rightArc, side: .right)
            heroButton
        }
        .frame(width: dialSize, height: dialSize)
        .background(
            Circle()
                .fill(ToolPaletteTheme.shell)
                .shadow(color: .black.opacity(0.45), radius: dialSize * 0.045, x: 0, y: dialSize * 0.025)
        )
        .overlay(Circle().strokeBorder(.black.opacity(0.45), lineWidth: 2))
        .popover(isPresented: $isColorPickerPresented) {
            VStack(alignment: .leading, spacing: 12) {
                Text(colorPickerTarget.title)
                    .font(.headline)
                ColorPicker("Custom", selection: customColorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 220)
            }
            .padding(16)
            .presentationCompactAdaptation(.popover)
        }
        .popover(isPresented: $isPaletteChooserPresented) {
            PalettePresetChooserView(
                selectedPreset: state.palettePreset,
                onSelect: { preset in
                    send(.setPalettePreset(preset))
                    isPaletteChooserPresented = false
                }
            )
            .padding(14)
            .presentationCompactAdaptation(.popover)
        }
        .popover(isPresented: $isLatexEditorPresented) {
            LatexEditorView(
                latexSource: $latexDraft,
                onApply: {
                    send(.setLatexSource(latexDraft))
                    isLatexEditorPresented = false
                }
            )
            .padding(14)
            .presentationCompactAdaptation(.popover)
        }
        .popover(isPresented: $isFontPickerPresented) {
            TextFontChooserView(
                selectedFontName: state.textFontName,
                onSelect: { fontName in
                    send(.setTextFontName(fontName))
                    isFontPickerPresented = false
                }
            )
            .padding(14)
            .presentationCompactAdaptation(.popover)
        }
        .environment(\.colorScheme, .dark)
    }

    private var paletteShell: some View {
        ZStack {
            // Base / outer rim.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            ToolPaletteTheme.segmentRaised,
                            ToolPaletteTheme.segment,
                            ToolPaletteTheme.shell
                        ],
                        center: .top,
                        startRadius: dialSize * 0.05,
                        endRadius: dialSize * 0.58
                    )
                )

            // Ring 3 — active-tool option band (outermost). Colors and the
            // width/opacity sliders are laid out on top of this band.
            AnnularSector(startDegrees: 0, endDegrees: 360, innerRadiusRatio: 0.355, outerRadiusRatio: 0.492)
                .fill(ToolPaletteTheme.optionBand)
                .overlay(
                    AnnularSector(startDegrees: 0, endDegrees: 360, innerRadiusRatio: 0.355, outerRadiusRatio: 0.492)
                        .stroke(.white.opacity(0.05), lineWidth: 1)
                )

            // Divider between the option ring and the tool ring.
            Circle()
                .strokeBorder(.black.opacity(0.40), lineWidth: 1)
                .frame(width: dialSize * 0.69, height: dialSize * 0.69)

            // Ring 2 — tool-selection band (middle).
            AnnularSector(startDegrees: 0, endDegrees: 360, innerRadiusRatio: 0.18, outerRadiusRatio: 0.345)
                .fill(ToolPaletteTheme.segment)

            // Divider between the tool ring and the inner hero.
            Circle()
                .strokeBorder(.black.opacity(0.40), lineWidth: 1)
                .frame(width: dialSize * 0.36, height: dialSize * 0.36)
        }
        .overlay(Circle().strokeBorder(.white.opacity(0.08), lineWidth: 1))
    }

    private func toolSegments(layout: RadialPaletteLayout) -> some View {
        ZStack {
            ForEach(Array(ToolPaletteDefinitions.orderedToolIDs.enumerated()), id: \.element) { index, toolID in
                let angle = layout.toolSlotAngle(index: index)
                let selected = toolID == state.activeTool

                toolWedgeBackground(angle: angle, selected: selected)

                toolWedgeButton(angle: angle, toolID: toolID)

                ToolSlotLabel(toolID: toolID, iconSystemName: state.iconSystemName(for: toolID), isSelected: selected, dialSize: dialSize)
                    .position(layout.toolSlotCenter(index: index))
                    .allowsHitTesting(false)
            }
        }
    }

    private func toolWedgeButton(angle: Double, toolID: ToolID) -> some View {
        let sector = AnnularSector(
            startDegrees: angle - 21.5,
            endDegrees: angle + 21.5,
            innerRadiusRatio: 0.18,
            outerRadiusRatio: 0.345
        )

        return Button {
            if toolID == .selection && state.activeTool == .selection {
                send(.setSelectionBehavior(state.selectionBehavior.toggled))
            } else {
                send(.selectTool(toolID))
            }
        } label: {
            sector
                .fill(.white.opacity(0.001))
                .frame(width: dialSize, height: dialSize)
                .contentShape(sector)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(toolID.displayName)
    }

    private func toolWedgeBackground(angle: Double, selected: Bool) -> some View {
        let sector = AnnularSector(
            startDegrees: angle - 21.5,
            endDegrees: angle + 21.5,
            innerRadiusRatio: 0.18,
            outerRadiusRatio: 0.345
        )

        return ZStack {
            sector
                .fill(selected ? ToolPaletteTheme.hero : ToolPaletteTheme.segment)

            if selected {
                sector
                    .stroke(.black.opacity(0.50), lineWidth: dialSize * 0.020)
                    .blur(radius: dialSize * 0.010)
                    .offset(x: -dialSize * 0.007, y: -dialSize * 0.007)
                    .mask(sector.fill(.white))
                sector
                    .stroke(.white.opacity(0.10), lineWidth: dialSize * 0.014)
                    .blur(radius: dialSize * 0.008)
                    .offset(x: dialSize * 0.007, y: dialSize * 0.007)
                    .mask(sector.fill(.white))
            } else {
                sector
                    .fill(
                        LinearGradient(
                            colors: [
                                ToolPaletteTheme.segmentRaised.opacity(0.92),
                                ToolPaletteTheme.segment
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .black.opacity(0.34), radius: dialSize * 0.010, x: dialSize * 0.006, y: dialSize * 0.008)
                    .shadow(color: .white.opacity(0.045), radius: dialSize * 0.006, x: -dialSize * 0.004, y: -dialSize * 0.004)
                sector
                    .stroke(.white.opacity(0.11), lineWidth: 1)
                    .offset(x: -0.8, y: -0.8)
                    .mask(sector.fill(.white))
                sector
                    .stroke(.black.opacity(0.30), lineWidth: 1)
                    .offset(x: 0.8, y: 0.8)
                    .mask(sector.fill(.white))
            }

            sector
                .stroke(ToolPaletteTheme.divider, lineWidth: 1)

            if selected {
                let selectionArc = AnnularSector(
                    startDegrees: angle - 18,
                    endDegrees: angle + 18,
                    innerRadiusRatio: 0.323,
                    outerRadiusRatio: 0.345
                )

                selectionArc
                    .fill(ToolPaletteTheme.cyan.opacity(0.92))

                AnnularSector(
                    startDegrees: angle - 18,
                    endDegrees: angle + 18,
                    innerRadiusRatio: 0.337,
                    outerRadiusRatio: 0.345
                )
                .fill(.black.opacity(0.34))
                .blur(radius: dialSize * 0.004)
                .mask(selectionArc.fill(.white))

                AnnularSector(
                    startDegrees: angle - 18,
                    endDegrees: angle + 18,
                    innerRadiusRatio: 0.323,
                    outerRadiusRatio: 0.329
                )
                .fill(ToolPaletteTheme.cyan.opacity(0.34))

                selectionArc
                    .stroke(.black.opacity(0.24), lineWidth: 1)
                    .mask(selectionArc.fill(.white))
            }
        }
    }

    private func topOrbit(_ items: [PaletteOrbitItem], layout: RadialPaletteLayout) -> some View {
        ZStack {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let angle = orbitAngle(for: item, index: index, count: items.count)
                let selected = isOrbitItemSelected(item)

                if selected && shouldShowOuterSelectionArc(for: item) {
                    AnnularSector(
                        startDegrees: angle - 9,
                        endDegrees: angle + 9,
                        innerRadiusRatio: 0.470,
                        outerRadiusRatio: 0.492
                    )
                    .fill(ToolPaletteTheme.cyan)
                    .shadow(color: ToolPaletteTheme.glow.opacity(0.55), radius: 6)
                }

                Button {
                    send(item.command)
                } label: {
                    OrbitItemView(
                        item: item,
                        isSelected: selected,
                        dialSize: dialSize
                    )
                    .frame(
                        width: orbitHitSize(for: item).width,
                        height: orbitHitSize(for: item).height
                    )
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .position(layout.point(angleDegrees: angle, radius: layout.orbitRadius))
                .accessibilityLabel(item.label)
            }
        }
    }

    private func orbitHitSize(for item: PaletteOrbitItem) -> CGSize {
        if item.id.hasPrefix("selection.") {
            return CGSize(width: dialSize * 0.20, height: dialSize * 0.16)
        }
        return CGSize(
            width: item.color == nil ? dialSize * 0.13 : dialSize * 0.15,
            height: item.color == nil ? dialSize * 0.105 : dialSize * 0.125
        )
    }

    private func orbitAngle(for item: PaletteOrbitItem, index: Int, count: Int) -> Double {
        if item.id.hasPrefix("text.") {
            switch item.id {
            case "text.bold":
                return -125
            case "text.italic":
                return -102
            case "text.underline":
                return -78
            case "text.latex":
                return -55
            default:
                break
            }
        }

        if item.id.hasPrefix("geometry.") {
            switch item.id {
            case "geometry.outlineColor":
                return -102
            case "geometry.fillColor":
                return -78
            case "geometry.shape.line":
                return -150
            case "geometry.shape.rightTriangle":
                return -130
            case "geometry.shape.triangle":
                return -118
            case "geometry.shape.rectangle":
                return -62
            case "geometry.shape.circle":
                return -50
            case "geometry.shape.polygon":
                return -30
            default:
                break
            }
        }

        if count <= 1 {
            return -90
        }
        let start = -140.0
        let end = -40.0
        return start + ((end - start) * Double(index) / Double(count - 1))
    }

    private func shouldShowOuterSelectionArc(for item: PaletteOrbitItem) -> Bool {
        !item.id.hasPrefix("selection.")
    }

    @ViewBuilder
    private func bottomArc(_ configuration: PaletteArcConfiguration, side: PaletteArcSide) -> some View {
        switch configuration {
        case .slider(let slider):
            PaletteArcSliderView(
                configuration: slider,
                side: side,
                dialSize: dialSize,
                onCommand: send
            )
        case .segmented(let segmented):
            PaletteSegmentedArcView(configuration: segmented, side: side, dialSize: dialSize, onCommand: send)
        case .disabled(let label):
            DisabledArcView(label: label, side: side, dialSize: dialSize)
        }
    }

    private var heroButton: some View {
        Button {
            if let onHeroTap {
                onHeroTap()
            } else {
                send(.selectTool(state.activeTool))
            }
        } label: {
            VStack(spacing: dialSize * 0.016) {
                if state.activeTool == .geometry {
                    GeometrySymbolView(
                        outlineColor: state.strokeColor.swiftUIColor,
                        fillColor: state.fillColor.swiftUIColor.opacity(state.geometryFillOpacity),
                        lineWidth: dialSize * 0.010
                    )
                    .frame(width: dialSize * 0.102, height: dialSize * 0.102)
                } else {
                    Image(systemName: state.activeTool.iconSystemName)
                        .font(.system(size: dialSize * 0.092, weight: .medium))
                        .foregroundStyle(heroIconColor)
                }
                Text(state.activeTool.displayName)
                    .font(.system(size: dialSize * 0.034, weight: .semibold))
                    .foregroundStyle(ToolPaletteTheme.label)
            }
            .frame(width: dialSize * 0.30, height: dialSize * 0.30)
            .background(heroBackground)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Active tool \(state.activeTool.displayName)")
    }

    private var heroBackground: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color(red: 0.16, green: 0.31, blue: 0.48),
                        Color(red: 0.11, green: 0.23, blue: 0.38)
                    ],
                    center: .topLeading,
                    startRadius: dialSize * 0.03,
                    endRadius: dialSize * 0.19
                )
            )
            .overlay(Circle().strokeBorder(.black.opacity(0.48), lineWidth: 2))
            .overlay(
                Circle()
                    .stroke(.black.opacity(0.42), lineWidth: dialSize * 0.022)
                    .blur(radius: dialSize * 0.012)
                    .offset(x: -dialSize * 0.012, y: -dialSize * 0.012)
                    .clipShape(Circle())
            )
            .overlay(
                Circle()
                    .stroke(.white.opacity(0.16), lineWidth: dialSize * 0.018)
                    .blur(radius: dialSize * 0.010)
                    .offset(x: dialSize * 0.012, y: dialSize * 0.012)
                    .clipShape(Circle())
            )
            .shadow(color: .black.opacity(0.50), radius: 7, y: 3)
    }

    private var heroIconColor: Color {
        switch state.activeTool {
        case .pen, .marker, .laser:
            return state.activeStrokeColor.swiftUIColor
        case .selection, .extract, .reserved, .eraser, .geometry, .equation, .cover:
            return ToolPaletteTheme.label
        }
    }

    private var customColorBinding: Binding<Color> {
        Binding(
            get: {
                switch colorPickerTarget {
                case .stroke:
                    return state.activeStrokeColor.swiftUIColor
                case .fill:
                    return state.fillColor.swiftUIColor
                }
            },
            set: { color in
                if let paletteColor = PaletteColor(name: "Custom", color: color) {
                    switch colorPickerTarget {
                    case .stroke:
                        send(.setStrokeColor(paletteColor))
                    case .fill:
                        send(.setFillColor(paletteColor))
                    }
                }
            }
        )
    }

    private func send(_ command: ToolPaletteCommand) {
        if command == .openColorPicker {
            colorPickerTarget = .stroke
            isColorPickerPresented = true
        } else if command == .openFillColorPicker {
            colorPickerTarget = .fill
            isColorPickerPresented = true
        } else if command == .openColorPaletteChooser {
            isPaletteChooserPresented = true
        } else if command == .openLatexEditor {
            latexDraft = state.latexSource
            isLatexEditorPresented = true
        } else if command == .openFontPicker {
            isFontPickerPresented = true
        }
        ToolPaletteReducer.reduce(&state, command: command)
        onCommand(command)
        onResolvedCommand(command, state)
    }

    private func isOrbitItemSelected(_ item: PaletteOrbitItem) -> Bool {
        switch item.command {
        case .setGeometryType(let type):
            return state.activeTool == .geometry && state.geometryType == type
        case .setTextBold:
            return state.activeTool == .equation && state.textStyle == .bold
        case .setTextItalic:
            return state.activeTool == .equation && state.textIsItalic
        case .setTextUnderlined:
            return state.activeTool == .equation && state.textIsUnderlined
        case .openLatexEditor:
            return state.activeTool == .equation && !state.latexSource.isEmpty
        default:
            if item.id == "geometry.fillColor" {
                return item.color == state.fillColor
            }
            return item.color == state.activeStrokeColor
        }
    }
}

private enum PaletteColorPickerTarget {
    case stroke
    case fill

    var title: String {
        switch self {
        case .stroke: return "Outline Color"
        case .fill: return "Fill Color"
        }
    }
}

private struct PalettePresetChooserView: View {
    var selectedPreset: PalettePreset
    var onSelect: (PalettePreset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Color Palette")
                .font(.headline)

            ForEach(PalettePreset.allCases) { preset in
                Button {
                    onSelect(preset)
                } label: {
                    HStack(spacing: 10) {
                        HStack(spacing: 4) {
                            ForEach(preset.colors) { color in
                                Circle()
                                    .fill(color.swiftUIColor)
                                    .frame(width: 18, height: 18)
                                    .overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1))
                            }
                        }
                        Text(preset.displayName)
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        if preset == selectedPreset {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(ToolPaletteTheme.cyan)
                        }
                    }
                    .foregroundStyle(ToolPaletteTheme.label)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(preset == selectedPreset ? ToolPaletteTheme.segmentRaised : ToolPaletteTheme.segment)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 260)
        .environment(\.colorScheme, .dark)
    }
}

private struct LatexEditorView: View {
    @Binding var latexSource: String
    var onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LaTeX")
                .font(.headline)
            TextEditor(text: $latexSource)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(ToolPaletteTheme.label)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(width: 280, height: 120)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ToolPaletteTheme.segment))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))

            Button("Apply") {
                onApply()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(width: 300)
        .environment(\.colorScheme, .dark)
    }
}

private struct TextFontChooserView: View {
    var selectedFontName: String
    var onSelect: (String) -> Void

    private let fontNames = ["System", "Serif", "Rounded", "Monospaced"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Font")
                .font(.headline)

            ForEach(fontNames, id: \.self) { fontName in
                Button {
                    onSelect(fontName)
                } label: {
                    HStack {
                        Text("Aa")
                            .font(sampleFont(for: fontName))
                        Text(fontName)
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        if fontName == selectedFontName {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(ToolPaletteTheme.cyan)
                        }
                    }
                    .foregroundStyle(ToolPaletteTheme.label)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(fontName == selectedFontName ? ToolPaletteTheme.segmentRaised : ToolPaletteTheme.segment)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 230)
        .environment(\.colorScheme, .dark)
    }

    private func sampleFont(for fontName: String) -> Font {
        switch fontName {
        case "Serif":
            return .system(size: 22, weight: .semibold, design: .serif)
        case "Rounded":
            return .system(size: 22, weight: .semibold, design: .rounded)
        case "Monospaced":
            return .system(size: 22, weight: .semibold, design: .monospaced)
        default:
            return .system(size: 22, weight: .semibold)
        }
    }
}

private struct ToolSlotLabel: View {
    var toolID: ToolID
    var iconSystemName: String
    var isSelected: Bool
    var dialSize: CGFloat

    var body: some View {
        VStack(spacing: 2) {
            if toolID == .geometry {
                GeometrySymbolView(
                    outlineColor: isSelected ? ToolPaletteTheme.label : ToolPaletteTheme.mutedLabel,
                    fillColor: (isSelected ? ToolPaletteTheme.label : ToolPaletteTheme.mutedLabel).opacity(0.22),
                    lineWidth: dialSize * 0.005
                )
                .frame(width: dialSize * 0.052, height: dialSize * 0.052)
            } else {
                Image(systemName: iconSystemName)
                    .font(.system(size: dialSize * 0.046, weight: .medium))
            }
            Text(toolID.displayName)
                .font(.system(size: dialSize * 0.023, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(isSelected ? ToolPaletteTheme.label : ToolPaletteTheme.mutedLabel)
        .frame(width: dialSize * 0.15, height: dialSize * 0.135)
    }
}

struct GeometrySymbolView: View {
    var outlineColor: Color
    var fillColor: Color
    var lineWidth: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle()
                    .fill(fillColor)
                    .overlay(Circle().stroke(outlineColor, lineWidth: lineWidth))
                    .frame(width: size * 0.78, height: size * 0.78)
                    .offset(x: -size * 0.10, y: -size * 0.06)

                TriangleShape()
                    .fill(fillColor)
                    .overlay(TriangleShape().stroke(outlineColor, lineWidth: lineWidth))
                    .frame(width: size * 0.74, height: size * 0.66)
                    .offset(x: size * 0.10, y: size * 0.08)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

private struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct OrbitItemView: View {
    var item: PaletteOrbitItem
    var isSelected: Bool
    var dialSize: CGFloat

    var body: some View {
        VStack(spacing: 2) {
            if let color = item.color {
                Circle()
                    .fill(color.swiftUIColor)
                    .frame(width: dialSize * 0.078, height: dialSize * 0.078)
                    .overlay(Circle().strokeBorder(.white.opacity(isSelected ? 0.95 : 0.4), lineWidth: isSelected ? 4 : 1.5))
                    .shadow(color: color.swiftUIColor.opacity(isSelected ? 0.55 : 0), radius: 6)
            } else if let iconSystemName = item.iconSystemName {
                Image(systemName: iconSystemName)
                    .font(.system(size: dialSize * 0.045, weight: .medium))
            }
            Text(item.label)
                .font(.system(size: dialSize * 0.024, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .foregroundStyle(isSelected ? ToolPaletteTheme.label : ToolPaletteTheme.mutedLabel)
        .frame(width: item.color == nil ? dialSize * 0.13 : dialSize * 0.15, height: item.color == nil ? dialSize * 0.105 : dialSize * 0.125)
        .contentShape(Circle())
    }
}

private struct PaletteArcSliderView: View {
    var configuration: PaletteSliderConfiguration
    var side: PaletteArcSide
    var dialSize: CGFloat
    var onCommand: (ToolPaletteCommand) -> Void

    var body: some View {
        let angleRange = ToolPaletteArcMath.angleRange(for: side)
        let progressAngle = ToolPaletteArcMath.angle(for: configuration.value, side: side, range: configuration.range)
        let layout = RadialPaletteLayout(dialSize: dialSize)
        let arcRatio: CGFloat = 0.425
        let knob = layout.point(angleDegrees: progressAngle, radius: layout.optionRingRadius)

        ZStack {
            ArcStrokeShape(startDegrees: angleRange.lowerBound, endDegrees: angleRange.upperBound, radiusRatio: arcRatio)
                .stroke(.black.opacity(0.48), style: StrokeStyle(lineWidth: dialSize * 0.040, lineCap: .round))
            ArcStrokeShape(startDegrees: angleRange.lowerBound, endDegrees: angleRange.upperBound, radiusRatio: arcRatio)
                .stroke(.white.opacity(0.08), style: StrokeStyle(lineWidth: dialSize * 0.026, lineCap: .round))
                .blur(radius: dialSize * 0.003)
                .offset(x: -dialSize * 0.004, y: -dialSize * 0.004)
            ArcStrokeShape(startDegrees: angleRange.lowerBound, endDegrees: angleRange.upperBound, radiusRatio: arcRatio)
                .stroke(.black.opacity(0.36), style: StrokeStyle(lineWidth: dialSize * 0.022, lineCap: .round))
                .blur(radius: dialSize * 0.004)
                .offset(x: dialSize * 0.004, y: dialSize * 0.004)

            // Filled portion grows from the minimum (outer) end of the track,
            // which is angleRange.upperBound, inward to the current value.
            ArcStrokeShape(startDegrees: progressAngle, endDegrees: angleRange.upperBound, radiusRatio: arcRatio)
                .stroke(ToolPaletteTheme.cyan.opacity(0.92), style: StrokeStyle(lineWidth: dialSize * 0.018, lineCap: .round))
                .shadow(color: ToolPaletteTheme.glow.opacity(0.22), radius: 3)

            // Graduated hash marks sit on the width track, with separate
            // endpoint samples just beyond each end of the slider travel.
            if configuration.trackStyle == .graduatedThickness {
                let tickCount = 5
                ForEach(0..<tickCount, id: \.self) { index in
                    let t = Double(index + 1) / Double(tickCount + 1)
                    let tickAngle = angleRange.upperBound + (angleRange.lowerBound - angleRange.upperBound) * t
                    Capsule()
                        .fill(ToolPaletteTheme.label.opacity(0.9))
                        .frame(width: dialSize * (0.005 + 0.015 * t), height: dialSize * 0.05)
                        .rotationEffect(.degrees(tickAngle - 90))
                        .position(layout.point(angleDegrees: tickAngle, radius: layout.optionRingRadius))
                        .allowsHitTesting(false)
                }
            }

            // End markers stay on the slider's arc radius, then move past each
            // endpoint by angle so they read inline without entering knob travel.
            let markerRadius = layout.optionRingRadius
            let minAngle = angleRange.upperBound + 6
            let maxAngle = angleRange.lowerBound - 6
            if let minMarker = configuration.minEndMarker {
                SliderEndMarkerView(marker: minMarker, dialSize: dialSize, angle: minAngle)
                    .position(layout.point(angleDegrees: minAngle, radius: markerRadius))
                    .allowsHitTesting(false)
            }
            if let maxMarker = configuration.maxEndMarker {
                SliderEndMarkerView(marker: maxMarker, dialSize: dialSize, angle: maxAngle)
                    .position(layout.point(angleDegrees: maxAngle, radius: markerRadius))
                    .allowsHitTesting(false)
            }

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.30, green: 0.45, blue: 0.64),
                                Color(red: 0.16, green: 0.28, blue: 0.43)
                            ],
                            center: .topLeading,
                            startRadius: dialSize * 0.008,
                            endRadius: dialSize * 0.064
                        )
                    )
                    .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                    .shadow(color: .white.opacity(0.09), radius: dialSize * 0.006, x: -dialSize * 0.004, y: -dialSize * 0.004)
                    .shadow(color: .black.opacity(0.48), radius: dialSize * 0.012, x: dialSize * 0.005, y: dialSize * 0.007)

                Circle()
                    .stroke(.black.opacity(0.24), lineWidth: dialSize * 0.006)
                    .blur(radius: dialSize * 0.003)
                    .offset(x: dialSize * 0.003, y: dialSize * 0.003)
                    .clipShape(Circle())
            }
            .frame(width: dialSize * 0.094, height: dialSize * 0.094)
            .position(knob)

            if configuration.trackStyle == .plain {
                Text(displayValue)
                    .font(.system(size: dialSize * 0.032, weight: .bold))
                    .foregroundStyle(ToolPaletteTheme.label)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.22)))
                    .position(labelPosition(layout: layout))
            }
        }
        .frame(width: dialSize, height: dialSize)
        // Restrict the drag hit-area to this slider's own arc wedge so the two
        // sliders never capture taps meant for the rest of the dial.
        .contentShape(
            AnnularSector(
                startDegrees: sliderHitAngleRange.lowerBound,
                endDegrees: sliderHitAngleRange.upperBound,
                innerRadiusRatio: 0.300,
                outerRadiusRatio: 0.550
            )
        )
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let angle = angleDegrees(for: value.location)
                    let nextValue = ToolPaletteArcMath.value(for: angle, side: side, range: configuration.range)
                    onCommand(configuration.command(nextValue))
                }
        )
    }

    private var sliderHitAngleRange: ClosedRange<Double> {
        let range = ToolPaletteArcMath.angleRange(for: side)
        let endpointPadding = 12.0
        return (range.lowerBound - endpointPadding)...(range.upperBound + endpointPadding)
    }

    private var displayValue: String {
        let lowercaseID = configuration.id.lowercased()
        if lowercaseID.contains("opacity") {
            return "\(Int((configuration.value * 100).rounded()))%"
        }
        if lowercaseID.contains("duration") {
            let rounded = (configuration.value * 2).rounded() / 2
            if rounded.rounded() == rounded {
                return "\(Int(rounded))s"
            }
            return "\(String(format: "%.1f", rounded))s"
        }
        if lowercaseID.contains("linearrows") {
            switch Int(configuration.value.rounded()) {
            case 1:
                return "←"
            case 2:
                return "→"
            case 3:
                return "↔"
            default:
                return "•"
            }
        }
        return "\(Int(configuration.value.rounded()))"
    }

    private func labelPosition(layout: RadialPaletteLayout) -> CGPoint {
        // Readout sits at the arc midpoint, nudged inside the track so the knob
        // (which rides on the track) doesn't cover it.
        let radius = layout.optionRingRadius - dialSize * 0.055
        switch side {
        case .left:
            return layout.point(angleDegrees: 135, radius: radius)
        case .right:
            return layout.point(angleDegrees: 45, radius: radius)
        }
    }

    private func angleDegrees(for point: CGPoint) -> Double {
        let center = CGPoint(x: dialSize / 2, y: dialSize / 2)
        var degrees = atan2(point.y - center.y, point.x - center.x) * 180 / .pi
        if degrees < 0 {
            degrees += 360
        }
        return degrees
    }
}

private struct SliderEndMarkerView: View {
    var marker: PaletteSliderEndMarker
    var dialSize: CGFloat
    var angle: Double

    var body: some View {
        switch marker {
        case .thinLine:
            Capsule()
                .fill(ToolPaletteTheme.label)
                .frame(width: dialSize * 0.055, height: dialSize * 0.007)
                .rotationEffect(.degrees(angle))
        case .thickLine:
            Capsule()
                .fill(ToolPaletteTheme.label)
                .frame(width: dialSize * 0.055, height: dialSize * 0.022)
                .rotationEffect(.degrees(angle))
        case .lightCircle:
            Circle()
                .fill(ToolPaletteTheme.label.opacity(0.85))
                .frame(width: dialSize * 0.05, height: dialSize * 0.05)
                .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1))
        case .darkCircle:
            Circle()
                .fill(Color.black.opacity(0.8))
                .frame(width: dialSize * 0.05, height: dialSize * 0.05)
                .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1))
        }
    }
}

private struct PaletteSegmentedArcView: View {
    var configuration: PaletteSegmentedConfiguration
    var side: PaletteArcSide
    var dialSize: CGFloat
    var onCommand: (ToolPaletteCommand) -> Void

    var body: some View {
        Group {
            if configuration.segments.count == 2 {
                CurvedBinarySwitchView(
                    segments: configuration.segments,
                    dialSize: dialSize,
                    rotationDegrees: switchRotationDegrees,
                    onCommand: onCommand
                )
            } else {
                HStack(spacing: 6) {
                    ForEach(configuration.segments) { segment in
                        Button {
                            onCommand(segment.command)
                        } label: {
                            HStack(spacing: 4) {
                                if let iconSystemName = segment.iconSystemName {
                                    Image(systemName: iconSystemName)
                                        .font(.system(size: dialSize * 0.020, weight: .bold))
                                }
                                Text(segment.label)
                                    .font(.system(size: dialSize * 0.022, weight: .bold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(segment.isSelected ? ToolPaletteTheme.cyan.opacity(0.9) : .black.opacity(0.22)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .foregroundStyle(ToolPaletteTheme.label)
        .position(position)
        .frame(width: dialSize, height: dialSize)
    }

    private var position: CGPoint {
        let layout = RadialPaletteLayout(dialSize: dialSize)
        if isSelectionControl {
            switch side {
            case .left:
                return layout.point(angleDegrees: 180, radius: layout.optionRingRadius)
            case .right:
                return layout.point(angleDegrees: 0, radius: layout.optionRingRadius)
            }
        }

        switch side {
        case .left:
            return layout.point(angleDegrees: 130, radius: layout.optionRingRadius - dialSize * 0.035)
        case .right:
            return layout.point(angleDegrees: 24, radius: layout.optionRingRadius)
        }
    }

    private var switchRotationDegrees: Double {
        if isSelectionControl {
            return -90
        }

        switch side {
        case .left:
            return 62
        case .right:
            return -62
        }
    }

    private var isSelectionControl: Bool {
        configuration.id.hasPrefix("selection.")
    }
}

private struct CurvedBinarySwitchView: View {
    var segments: [PaletteSegment]
    var dialSize: CGFloat
    var rotationDegrees: Double
    var onCommand: (ToolPaletteCommand) -> Void

    private var selectedIndex: Int {
        segments.firstIndex(where: \.isSelected) ?? 0
    }

    var body: some View {
        let width = dialSize * 0.27
        let height = dialSize * 0.055
        let handleWidth = width * 0.52

        ZStack(alignment: selectedIndex == 0 ? .leading : .trailing) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.06, green: 0.14, blue: 0.24),
                            Color(red: 0.13, green: 0.27, blue: 0.42)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(Capsule().strokeBorder(.black.opacity(0.48), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.36), radius: 4, x: 0, y: 2)
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                        .padding(2)
                )

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.90, green: 0.95, blue: 1.0),
                            Color(red: 0.56, green: 0.72, blue: 0.90)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: handleWidth, height: height - 5)
                .overlay(Capsule().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                .shadow(color: .black.opacity(0.38), radius: 4, x: 0, y: 2)
                .padding(2.5)

            HStack(spacing: 0) {
                ForEach(segments) { segment in
                    Button {
                        onCommand(segment.command)
                    } label: {
                        Text(segment.label)
                            .font(.system(size: dialSize * 0.021, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(segment.isSelected ? Color(red: 0.05, green: 0.11, blue: 0.18) : ToolPaletteTheme.mutedLabel)
                }
            }
        }
        .frame(width: width, height: height)
        .rotationEffect(.degrees(rotationDegrees))
        .animation(.snappy(duration: 0.18), value: selectedIndex)
        .accessibilityElement(children: .contain)
    }
}

private struct DisabledArcView: View {
    var label: String
    var side: PaletteArcSide
    var dialSize: CGFloat

    var body: some View {
        Text(label)
            .font(.system(size: dialSize * 0.026, weight: .semibold))
            .foregroundStyle(ToolPaletteTheme.mutedLabel)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.black.opacity(0.18)))
            .position(position)
            .frame(width: dialSize, height: dialSize)
    }

    private var position: CGPoint {
        let layout = RadialPaletteLayout(dialSize: dialSize)
        switch side {
        case .left:
            return layout.point(angleDegrees: 135, radius: layout.optionRingRadius)
        case .right:
            return layout.point(angleDegrees: 45, radius: layout.optionRingRadius)
        }
    }
}

// MARK: - Previews

/// Interactive single-tool dial preview over the mock canvas background.
private struct RadialPalettePreviewHost: View {
    @State private var state: ToolPaletteState
    let dialSize: CGFloat

    init(tool: ToolID, dialSize: CGFloat = 360) {
        _state = State(initialValue: ToolPaletteState(activeTool: tool))
        self.dialSize = dialSize
    }

    var body: some View {
        ZStack {
            Color(red: 0.94, green: 0.96, blue: 0.98)
            RadialToolPaletteView(state: $state, dialSize: dialSize)
        }
        .ignoresSafeArea()
    }
}

#Preview("Pen") {
    RadialPalettePreviewHost(tool: .pen)
}

#Preview("Marker") {
    RadialPalettePreviewHost(tool: .marker)
}

#Preview("Eraser") {
    RadialPalettePreviewHost(tool: .eraser)
}

#Preview("Laser") {
    RadialPalettePreviewHost(tool: .laser)
}

#Preview("Geometry (placeholder)") {
    RadialPalettePreviewHost(tool: .geometry)
}

#Preview("Selection (placeholder)") {
    RadialPalettePreviewHost(tool: .selection)
}

#Preview("Widget") {
    RadialPalettePreviewHost(tool: .reserved)
}

#Preview("Text") {
    RadialPalettePreviewHost(tool: .equation)
}

#Preview("Size sweep") {
    ScrollView(.horizontal) {
        HStack(spacing: 32) {
            ForEach([CGFloat(320), 360, 420], id: \.self) { size in
                RadialPalettePreviewHost(tool: .pen, dialSize: size)
                    .frame(width: size + 40, height: size + 40)
            }
        }
        .padding(40)
    }
    .background(Color(red: 0.94, green: 0.96, blue: 0.98))
}
