//
//  CompactToolPaletteView.swift
//  MathBoardCore - ToolPalette module
//
//  A compact, professional teaching-whiteboard tool palette — an alternative to
//  the radial dial (`RadialToolPaletteView`). It is a slim vertical dock of tool
//  buttons with a contextual controls drawer that only appears for the active
//  tool, so it never blocks much of the canvas.
//
//  It reuses the *existing* model end-to-end:
//   - `ToolPaletteState` / `ToolPaletteCommand`             (single command model)
//   - `ToolPaletteDefinitions.definition(for:).configuration(for:)`  (per-tool UI)
//   - `ToolPaletteReducer.reduce(_:command:)`               (state transitions)
//
//  The dock is intentionally driven by the same `ToolPaletteConfiguration`
//  (topOrbit + leftArc/rightArc) the radial dial consumes, so every tool
//  definition works here unchanged and new tools/controls extend automatically.
//
//  This is a standalone prototype — it is NOT wired into the live canvas. Use
//  `CompactToolPalettePrototypeView` (or the #Previews below) to compare it with
//  the radial palette.
//

import SwiftUI

public struct CompactToolPaletteView: View {
    @Binding private var state: ToolPaletteState
    private let onCommand: (ToolPaletteCommand) -> Void
    private let onResolvedCommand: (ToolPaletteCommand, ToolPaletteState) -> Void

    // Contextual drawer visibility. Collapsing leaves only the slim tool rail so
    // the palette shrinks to almost nothing while teaching.
    @State private var isDrawerOpen = true

    // Popover hosts, mirroring the radial palette's "open…" command handling.
    @State private var isColorPickerPresented = false
    @State private var isPaletteChooserPresented = false
    @State private var isLatexEditorPresented = false
    @State private var isFontPickerPresented = false
    @State private var colorPickerTarget: CompactColorTarget = .stroke
    @State private var latexDraft = ""

    public init(
        state: Binding<ToolPaletteState>,
        onCommand: @escaping (ToolPaletteCommand) -> Void = { _ in },
        onResolvedCommand: @escaping (ToolPaletteCommand, ToolPaletteState) -> Void = { _, _ in }
    ) {
        self._state = state
        self.onCommand = onCommand
        self.onResolvedCommand = onResolvedCommand
    }

    public var body: some View {
        let configuration = ToolPaletteDefinitions.definition(for: state.activeTool).configuration(for: state)

        HStack(alignment: .top, spacing: 0) {
            toolRail
            if isDrawerOpen {
                contextDrawer(configuration)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(ToolPaletteTheme.shell)
                .shadow(color: .black.opacity(0.42), radius: 14, x: 0, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isDrawerOpen)
        .animation(.snappy(duration: 0.2), value: state.activeTool)
        .environment(\.colorScheme, .dark)
        // Popovers reuse the shared reducer via `send`, just like the radial dial.
        .popover(isPresented: $isColorPickerPresented) {
            VStack(alignment: .leading, spacing: 12) {
                Text(colorPickerTarget.title).font(.headline)
                ColorPicker("Custom", selection: customColorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 220)
            }
            .padding(16)
            .presentationCompactAdaptation(.popover)
        }
        .popover(isPresented: $isPaletteChooserPresented) {
            CompactPaletteChooser(selectedPreset: state.palettePreset) { preset in
                send(.setPalettePreset(preset))
                isPaletteChooserPresented = false
            }
            .padding(14)
            .presentationCompactAdaptation(.popover)
        }
        .popover(isPresented: $isLatexEditorPresented) {
            CompactLatexEditor(latexSource: $latexDraft) {
                send(.setLatexSource(latexDraft))
                isLatexEditorPresented = false
            }
            .padding(14)
            .presentationCompactAdaptation(.popover)
        }
        .popover(isPresented: $isFontPickerPresented) {
            CompactFontChooser(selectedFontName: state.textFontName) { fontName in
                send(.setTextFontName(fontName))
                isFontPickerPresented = false
            }
            .padding(14)
            .presentationCompactAdaptation(.popover)
        }
    }

    // MARK: - Tool rail

    private var toolRail: some View {
        VStack(spacing: 6) {
            ForEach(ToolPaletteDefinitions.orderedToolIDs, id: \.self) { toolID in
                CompactToolButton(
                    toolID: toolID,
                    isActive: toolID == state.activeTool,
                    accentColor: railAccentColor(for: toolID),
                    outlineColor: state.strokeColor.swiftUIColor,
                    fillColor: state.fillColor.swiftUIColor.opacity(state.geometryFillOpacity)
                ) {
                    send(.selectTool(toolID))
                    // Re-selecting the already-active tool toggles the drawer, so
                    // the palette can shrink to just the rail with one more tap.
                    if state.activeTool == toolID {
                        withAnimation { isDrawerOpen.toggle() }
                    } else {
                        isDrawerOpen = true
                    }
                }
            }

            Divider()
                .overlay(Color.white.opacity(0.12))
                .padding(.horizontal, 10)

            // Explicit drawer toggle for discoverability.
            Button {
                withAnimation { isDrawerOpen.toggle() }
            } label: {
                Image(systemName: isDrawerOpen ? "chevron.left" : "chevron.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(ToolPaletteTheme.mutedLabel.opacity(0.8))
                    .frame(width: 44, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDrawerOpen ? "Hide tool options" : "Show tool options")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .frame(width: 68)
    }

    private func railAccentColor(for toolID: ToolID) -> Color {
        switch toolID {
        case .pen: return state.penColor.swiftUIColor
        case .marker: return state.markerColor.swiftUIColor
        case .laser: return state.laserColor.swiftUIColor
        case .selection, .reserved, .eraser, .geometry, .equation:
            return ToolPaletteTheme.cyan
        }
    }

    // MARK: - Contextual drawer

    private func contextDrawer(_ configuration: ToolPaletteConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(state.activeTool.displayName.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(ToolPaletteTheme.mutedLabel.opacity(0.65))

            if !configuration.topOrbit.isEmpty {
                orbitSection(configuration.topOrbit)
            }

            arcSection(configuration.leftArc)
            arcSection(configuration.rightArc)
        }
        .frame(width: 280, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
        }
    }

    @ViewBuilder
    private func orbitSection(_ items: [PaletteOrbitItem]) -> some View {
        // Colors flow in a wrapping row; action/shape buttons sit in their own row.
        let colorItems = items.filter { $0.color != nil }
        let actionItems = items.filter { $0.color == nil }

        VStack(alignment: .leading, spacing: 10) {
            if !colorItems.isEmpty {
                CompactFlowRow(spacing: 8) {
                    ForEach(colorItems) { item in
                        CompactOrbitChip(item: item, isSelected: isOrbitItemSelected(item)) {
                            send(item.command)
                        }
                    }
                }
            }
            if !actionItems.isEmpty {
                CompactFlowRow(spacing: 8) {
                    ForEach(actionItems) { item in
                        CompactOrbitChip(item: item, isSelected: isOrbitItemSelected(item)) {
                            send(item.command)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func arcSection(_ arc: PaletteArcConfiguration) -> some View {
        switch arc {
        case .slider(let slider):
            CompactSlider(configuration: slider, onCommand: send)
        case .segmented(let segmented):
            CompactSegmentedControl(configuration: segmented, onCommand: send)
        case .disabled(let label):
            HStack {
                Image(systemName: "lock")
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(ToolPaletteTheme.mutedLabel.opacity(0.5))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(Color.black.opacity(0.18)))
        }
    }

    // MARK: - Command plumbing (mirrors RadialToolPaletteView.send)

    private func send(_ command: ToolPaletteCommand) {
        switch command {
        case .openColorPicker:
            colorPickerTarget = .stroke
            isColorPickerPresented = true
        case .openFillColorPicker:
            colorPickerTarget = .fill
            isColorPickerPresented = true
        case .openColorPaletteChooser:
            isPaletteChooserPresented = true
        case .openLatexEditor:
            latexDraft = state.latexSource
            isLatexEditorPresented = true
        case .openFontPicker:
            isFontPickerPresented = true
        default:
            break
        }
        ToolPaletteReducer.reduce(&state, command: command)
        onCommand(command)
        onResolvedCommand(command, state)
    }

    /// Selection highlight for orbit items — same rules as the radial dial.
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

    private var customColorBinding: Binding<Color> {
        Binding(
            get: {
                switch colorPickerTarget {
                case .stroke: return state.activeStrokeColor.swiftUIColor
                case .fill: return state.fillColor.swiftUIColor
                }
            },
            set: { color in
                if let paletteColor = PaletteColor(name: "Custom", color: color) {
                    switch colorPickerTarget {
                    case .stroke: send(.setStrokeColor(paletteColor))
                    case .fill: send(.setFillColor(paletteColor))
                    }
                }
            }
        )
    }
}

private enum CompactColorTarget {
    case stroke
    case fill

    var title: String {
        switch self {
        case .stroke: return "Outline Color"
        case .fill: return "Fill Color"
        }
    }
}

// MARK: - Tool button

private struct CompactToolButton: View {
    var toolID: ToolID
    var isActive: Bool
    var accentColor: Color
    var outlineColor: Color
    var fillColor: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isActive ? ToolPaletteTheme.segmentRaised : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isActive ? ToolPaletteTheme.cyan.opacity(0.9) : .clear, lineWidth: 2)
                    )

                icon
                    .frame(width: 26, height: 26)

                if isActive, toolID == .pen || toolID == .marker || toolID == .laser {
                    // Small live-color indicator so the active ink color is visible
                    // even while the drawer is collapsed.
                    Circle()
                        .fill(accentColor)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(6)
                }
            }
            .frame(width: 52, height: 46)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(toolID.displayName)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    @ViewBuilder
    private var icon: some View {
        if toolID == .geometry {
            GeometrySymbolView(
                outlineColor: isActive ? outlineColor : ToolPaletteTheme.label,
                fillColor: isActive ? fillColor : ToolPaletteTheme.label.opacity(0.22),
                lineWidth: 1.4
            )
        } else {
            Image(systemName: toolID.iconSystemName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(iconColor)
        }
    }

    private var iconColor: Color {
        switch toolID {
        case .pen, .marker, .laser:
            return isActive ? accentColor : ToolPaletteTheme.label
        case .selection, .reserved, .eraser, .geometry, .equation:
            return ToolPaletteTheme.label
        }
    }
}

// MARK: - Orbit chip (color swatch or icon/action button)

private struct CompactOrbitChip: View {
    var item: PaletteOrbitItem
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            if let color = item.color {
                Circle()
                    .fill(color.swiftUIColor)
                    .frame(width: 30, height: 30)
                    .overlay(Circle().strokeBorder(.white.opacity(isSelected ? 0.95 : 0.35), lineWidth: isSelected ? 3 : 1.5))
                    .shadow(color: color.swiftUIColor.opacity(isSelected ? 0.55 : 0), radius: 5)
                    .accessibilityLabel(item.label)
            } else {
                HStack(spacing: 6) {
                    if let iconSystemName = item.iconSystemName {
                        Image(systemName: iconSystemName)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text(item.label)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(isSelected ? Color(red: 0.05, green: 0.11, blue: 0.18) : ToolPaletteTheme.label)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(isSelected ? ToolPaletteTheme.cyan.opacity(0.92) : ToolPaletteTheme.segment)
                )
                .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 1))
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Slider control

private struct CompactSlider: View {
    var configuration: PaletteSliderConfiguration
    var onCommand: (ToolPaletteCommand) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: configuration.iconSystemName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ToolPaletteTheme.mutedLabel.opacity(0.8))
                Text(configuration.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ToolPaletteTheme.label)
                Spacer()
                Text(readout)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(ToolPaletteTheme.cyan)
                    .monospacedDigit()
            }

            Slider(value: valueBinding, in: configuration.range)
                .tint(ToolPaletteTheme.cyan)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ToolPaletteTheme.segment))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.06), lineWidth: 1))
    }

    private var valueBinding: Binding<Double> {
        Binding(
            get: { configuration.value },
            set: { onCommand(configuration.command($0)) }
        )
    }

    private var readout: String {
        let id = configuration.id.lowercased()
        if id.contains("opacity") {
            return "\(Int((configuration.value * 100).rounded()))%"
        }
        if id.contains("duration") {
            let rounded = (configuration.value * 2).rounded() / 2
            return rounded == rounded.rounded() ? "\(Int(rounded))s" : "\(String(format: "%.1f", rounded))s"
        }
        if id.contains("linearrows") {
            switch Int(configuration.value.rounded()) {
            case 1: return "←"
            case 2: return "→"
            case 3: return "↔"
            default: return "•"
            }
        }
        return "\(Int(configuration.value.rounded()))"
    }
}

// MARK: - Segmented control

private struct CompactSegmentedControl: View {
    var configuration: PaletteSegmentedConfiguration
    var onCommand: (ToolPaletteCommand) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(configuration.label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ToolPaletteTheme.label)

            HStack(spacing: 4) {
                ForEach(configuration.segments) { segment in
                    Button {
                        onCommand(segment.command)
                    } label: {
                        HStack(spacing: 5) {
                            if let iconSystemName = segment.iconSystemName {
                                Image(systemName: iconSystemName)
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            Text(segment.label)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(segment.isSelected ? Color(red: 0.05, green: 0.11, blue: 0.18) : ToolPaletteTheme.label)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(segment.isSelected ? ToolPaletteTheme.cyan.opacity(0.92) : Color.clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.black.opacity(0.22)))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ToolPaletteTheme.segment))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.06), lineWidth: 1))
    }
}

// MARK: - Simple wrapping row layout

/// Lays children left-to-right, wrapping to the next line when they overflow the
/// proposed width. Keeps color swatches / action chips compact without a fixed
/// column count.
private struct CompactFlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                maxRowWidth = max(maxRowWidth, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        maxRowWidth = max(maxRowWidth, rowWidth)
        return CGSize(width: min(maxRowWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxX = bounds.maxX
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Popover content

private struct CompactPaletteChooser: View {
    var selectedPreset: PalettePreset
    var onSelect: (PalettePreset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Color Palette").font(.headline)
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
                        Text(preset.displayName).font(.system(size: 13, weight: .semibold))
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

private struct CompactLatexEditor: View {
    @Binding var latexSource: String
    var onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LaTeX").font(.headline)
            TextEditor(text: $latexSource)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(ToolPaletteTheme.label)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(width: 280, height: 120)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ToolPaletteTheme.segment))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
            Button("Apply", action: onApply)
                .buttonStyle(.borderedProminent)
        }
        .frame(width: 300)
        .environment(\.colorScheme, .dark)
    }
}

private struct CompactFontChooser: View {
    var selectedFontName: String
    var onSelect: (String) -> Void

    private let fontNames = ["System", "Serif", "Rounded", "Monospaced"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Font").font(.headline)
            ForEach(fontNames, id: \.self) { fontName in
                Button {
                    onSelect(fontName)
                } label: {
                    HStack {
                        Text("Aa").font(sampleFont(for: fontName))
                        Text(fontName).font(.system(size: 13, weight: .semibold))
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
        case "Serif": return .system(size: 22, weight: .semibold, design: .serif)
        case "Rounded": return .system(size: 22, weight: .semibold, design: .rounded)
        case "Monospaced": return .system(size: 22, weight: .semibold, design: .monospaced)
        default: return .system(size: 22, weight: .semibold)
        }
    }
}

// MARK: - Prototype host

/// Standalone host that floats the compact palette over a mock canvas and logs
/// the emitted `ToolPaletteCommand`s — the compact-palette analogue of
/// `ToolPalettePrototypeView`, for side-by-side comparison with the radial dial.
public struct CompactToolPalettePrototypeView: View {
    @State private var state = ToolPaletteState()
    @State private var commandLog: [ToolPaletteCommand] = []

    public init() {}

    public var body: some View {
        ZStack(alignment: .topLeading) {
            CompactMockCanvasBackground()

            CompactToolPaletteView(
                state: $state,
                onCommand: { command in
                    commandLog.insert(command, at: 0)
                    if commandLog.count > 8 { commandLog.removeLast() }
                }
            )
            .padding(.leading, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text("Command Log").font(.headline)
                if commandLog.isEmpty {
                    Text("Interact with the palette")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(commandLog.enumerated()), id: \.offset) { _, command in
                    Text(command.compactDebugLabel)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(12)
            .frame(width: 260, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.black.opacity(0.08), lineWidth: 1))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(20)
        }
    }
}

private struct CompactMockCanvasBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.94, green: 0.96, blue: 0.98)
            CompactGridPattern()
                .stroke(Color(red: 0.72, green: 0.78, blue: 0.86).opacity(0.35), lineWidth: 1)
            VStack(alignment: .leading, spacing: 10) {
                Text("Compact palette prototype")
                    .font(.title2.weight(.semibold))
                Text("Standalone mock canvas — dock docks to the left edge")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(28)
        }
        .ignoresSafeArea()
    }
}

private struct CompactGridPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 32
        var x = rect.minX
        while x <= rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += spacing
        }
        var y = rect.minY
        while y <= rect.maxY {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += spacing
        }
        return path
    }
}

private extension ToolPaletteCommand {
    var compactDebugLabel: String {
        switch self {
        case .selectTool(let tool): return "selectTool(\(tool.rawValue))"
        case .setStrokeColor(let color): return "setStrokeColor(\(color.name))"
        case .setFillColor(let color): return "setFillColor(\(color.name))"
        case .setStrokeWidth(let width): return "setStrokeWidth(\(String(format: "%.1f", width)))"
        case .setOpacity(let opacity): return "setOpacity(\(String(format: "%.2f", opacity)))"
        case .setLaserDuration(let duration): return "setLaserDuration(\(String(format: "%.1f", duration)))"
        case .openColorPicker: return "openColorPicker"
        case .openFillColorPicker: return "openFillColorPicker"
        case .openColorPaletteChooser: return "openColorPaletteChooser"
        case .setPalettePreset(let preset): return "setPalettePreset(\(preset.rawValue))"
        case .setGeometryType(let type): return "setGeometryType(\(type.rawValue))"
        case .setPolygonSides(let sides): return "setPolygonSides(\(sides))"
        case .setGeometryLineArrowMode(let mode): return "setGeometryLineArrowMode(\(mode.rawValue))"
        case .setGeometryFillOpacity(let opacity): return "setGeometryFillOpacity(\(String(format: "%.2f", opacity)))"
        case .setSelectionTarget(let target): return "setSelectionTarget(\(target.rawValue))"
        case .setSelectionMode(let mode): return "setSelectionMode(\(mode.rawValue))"
        case .setEraserMode(let mode): return "setEraserMode(\(mode.rawValue))"
        case .setLaserMode(let mode): return "setLaserMode(\(mode.rawValue))"
        case .setTextBold(let isBold): return "setTextBold(\(isBold))"
        case .setTextItalic(let isItalic): return "setTextItalic(\(isItalic))"
        case .setTextUnderlined(let isUnderlined): return "setTextUnderlined(\(isUnderlined))"
        case .setTextSize(let size): return "setTextSize(\(String(format: "%.1f", size)))"
        case .setTextFontName(let fontName): return "setTextFontName(\(fontName))"
        case .openLatexEditor: return "openLatexEditor"
        case .setLatexSource(let source): return "setLatexSource(\(source))"
        case .openFontPicker: return "openFontPicker"
        case .createWidget: return "createWidget"
        case .editWidget: return "editWidget"
        case .openWidget: return "openWidget"
        case .removeWidget: return "removeWidget"
        case .undo: return "undo"
        case .redo: return "redo"
        case .copySelection: return "copySelection"
        case .duplicateSelection: return "duplicateSelection"
        case .deleteSelection: return "deleteSelection"
        case .extractSelectionAsImageSticker: return "extractSelectionAsImageSticker"
        case .sendSelectionToNextSlide: return "sendSelectionToNextSlide"
        }
    }
}

// MARK: - Previews

#Preview("Compact — Prototype Host") {
    CompactToolPalettePrototypeView()
}

private struct CompactPalettePreviewHost: View {
    @State private var state: ToolPaletteState

    init(tool: ToolID) {
        _state = State(initialValue: ToolPaletteState(activeTool: tool))
    }

    var body: some View {
        ZStack {
            Color(red: 0.94, green: 0.96, blue: 0.98)
            CompactToolPaletteView(state: $state)
                .padding(.leading, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .ignoresSafeArea()
    }
}

#Preview("Compact — Pen") { CompactPalettePreviewHost(tool: .pen) }
#Preview("Compact — Marker") { CompactPalettePreviewHost(tool: .marker) }
#Preview("Compact — Eraser") { CompactPalettePreviewHost(tool: .eraser) }
#Preview("Compact — Laser") { CompactPalettePreviewHost(tool: .laser) }
#Preview("Compact — Geometry") { CompactPalettePreviewHost(tool: .geometry) }
#Preview("Compact — Selection") { CompactPalettePreviewHost(tool: .selection) }
#Preview("Compact — Text") { CompactPalettePreviewHost(tool: .equation) }
#Preview("Compact — Widget") { CompactPalettePreviewHost(tool: .reserved) }
