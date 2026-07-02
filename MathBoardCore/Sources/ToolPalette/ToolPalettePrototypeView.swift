//
//  ToolPalettePrototypeView.swift
//  MathBoardCore - ToolPalette module
//

import SwiftUI

public struct ToolPalettePrototypeView: View {
    @State private var state = ToolPaletteState()
    @State private var commandLog: [ToolPaletteCommand] = []
    @State private var isExpanded = false

    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                MockCanvasBackground()

                FloatingToolPaletteView(
                    state: $state,
                    isExpanded: $isExpanded,
                    dialSize: min(380, max(320, proxy.size.width * 0.44)),
                    onCommand: { command in
                        commandLog.insert(command, at: 0)
                        if commandLog.count > 8 {
                            commandLog.removeLast()
                        }
                    }
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Command Log")
                        .font(.headline)
                    ForEach(Array(commandLog.enumerated()), id: \.offset) { _, command in
                        Text(command.debugLabel)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if commandLog.isEmpty {
                        Text("Interact with the palette")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(width: 240, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.black.opacity(0.08), lineWidth: 1))
                .position(x: min(proxy.size.width - 140, 150), y: proxy.size.height - 115)
            }
        }
    }
}

private struct MockCanvasBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.94, green: 0.96, blue: 0.98)
            GridPattern()
                .stroke(Color(red: 0.72, green: 0.78, blue: 0.86).opacity(0.35), lineWidth: 1)
            VStack(alignment: .leading, spacing: 10) {
                Text("Pen tool prototype")
                    .font(.title2.weight(.semibold))
                Text("Standalone mock canvas")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(28)
        }
    }
}

private struct GridPattern: Shape {
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
    var debugLabel: String {
        switch self {
        case .selectTool(let tool):
            return "selectTool(\(tool.rawValue))"
        case .setStrokeColor(let color):
            return "setStrokeColor(\(color.name))"
        case .setFillColor(let color):
            return "setFillColor(\(color.name))"
        case .setStrokeWidth(let width):
            return "setStrokeWidth(\(String(format: "%.1f", width)))"
        case .setOpacity(let opacity):
            return "setOpacity(\(String(format: "%.2f", opacity)))"
        case .setLaserDuration(let duration):
            return "setLaserDuration(\(String(format: "%.1f", duration)))"
        case .openColorPicker:
            return "openColorPicker"
        case .openFillColorPicker:
            return "openFillColorPicker"
        case .openColorPaletteChooser:
            return "openColorPaletteChooser"
        case .setPalettePreset(let preset):
            return "setPalettePreset(\(preset.rawValue))"
        case .setPaletteColor(let tool, let index, let color):
            return "setPaletteColor(\(tool.rawValue), \(index), \(color.name))"
        case .setGeometryType(let type):
            return "setGeometryType(\(type.rawValue))"
        case .setPolygonSides(let sides):
            return "setPolygonSides(\(sides))"
        case .setGeometryLineArrowMode(let mode):
            return "setGeometryLineArrowMode(\(mode.rawValue))"
        case .setGeometryFillOpacity(let opacity):
            return "setGeometryFillOpacity(\(String(format: "%.2f", opacity)))"
        case .setSelectionTarget(let target):
            return "setSelectionTarget(\(target.rawValue))"
        case .setSelectionMode(let mode):
            return "setSelectionMode(\(mode.rawValue))"
        case .setEraserMode(let mode):
            return "setEraserMode(\(mode.rawValue))"
        case .setLaserMode(let mode):
            return "setLaserMode(\(mode.rawValue))"
        case .setTextBold(let isBold):
            return "setTextBold(\(isBold))"
        case .setTextItalic(let isItalic):
            return "setTextItalic(\(isItalic))"
        case .setTextUnderlined(let isUnderlined):
            return "setTextUnderlined(\(isUnderlined))"
        case .setTextSize(let size):
            return "setTextSize(\(String(format: "%.1f", size)))"
        case .setTextFontName(let fontName):
            return "setTextFontName(\(fontName))"
        case .openLatexEditor:
            return "openLatexEditor"
        case .setLatexSource(let source):
            return "setLatexSource(\(source))"
        case .openFontPicker:
            return "openFontPicker"
        case .createWidget:
            return "createWidget"
        case .editWidget:
            return "editWidget"
        case .openWidget:
            return "openWidget"
        case .removeWidget:
            return "removeWidget"
        case .undo:
            return "undo"
        case .redo:
            return "redo"
        case .copySelection:
            return "copySelection"
        case .duplicateSelection:
            return "duplicateSelection"
        case .deleteSelection:
            return "deleteSelection"
        case .extractSelectionAsImageSticker:
            return "extractSelectionAsImageSticker"
        case .sendSelectionToNextSlide:
            return "sendSelectionToNextSlide"
        }
    }
}

#Preview("Prototype Host") {
    ToolPalettePrototypeView()
}
