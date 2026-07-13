//
//  ToolPaletteDefinitions.swift
//  MathBoardCore - ToolPalette module
//

import Foundation

public protocol ToolDefinition: Sendable {
    var id: ToolID { get }
    var iconSystemName: String { get }
    var label: String { get }
    func configuration(for state: ToolPaletteState) -> ToolPaletteConfiguration
}

public enum ToolPaletteDefinitions {
    public static let orderedToolIDs: [ToolID] = [
        .selection,
        .extract,
        .pen,
        .marker,
        .laser,
        .eraser,
        .geometry,
        .reserved,
        .equation,
        .cover
    ]

    public static let all: [any ToolDefinition] = orderedToolIDs.map { definition(for: $0) }

    public static func definition(for id: ToolID) -> any ToolDefinition {
        switch id {
        case .pen:
            return PenToolDefinition()
        case .marker:
            return MarkerToolDefinition()
        case .eraser:
            return EraserToolDefinition()
        case .laser:
            return LaserToolDefinition()
        case .selection:
            return SelectionToolDefinition()
        case .extract:
            return ExtractToolDefinition()
        case .geometry:
            return GeometryToolDefinition()
        case .equation:
            return TextToolDefinition()
        case .reserved:
            return AddToolDefinition()
        case .cover:
            return CoverToolDefinition()
        }
    }
}

public enum ToolPaletteReducer {
    public static func reduce(_ state: inout ToolPaletteState, command: ToolPaletteCommand) {
        switch command {
        case .selectTool(let tool):
            let wasSelection = state.activeTool == .selection
            state.activeTool = tool
            if tool == .selection && !wasSelection {
                state.selectionBehavior = .single
            }
            if tool == .extract && state.selectionMode == .tap {
                state.selectionMode = .marquee
            }
            state.isColorBloomOpen = false
        case .setStrokeColor(let color):
            switch state.activeTool {
            case .pen:
                state.penColor = color
            case .marker:
                state.markerColor = color
            case .laser:
                state.laserColor = color
            case .selection, .extract, .reserved, .eraser, .geometry, .equation, .cover:
                state.strokeColor = color
            }
        case .setFillColor(let color):
            state.fillColor = color
        case .setStrokeWidth(let width):
            let clampedWidth = min(max(width, 1), 40)
            state.strokeWidth = clampedWidth
            switch state.activeTool {
            case .pen:
                state.penStrokeWidth = min(max(width, 1), 24)
            case .marker:
                state.markerStrokeWidth = min(max(width, 4), 36)
            case .eraser:
                state.eraserWidth = min(max(width, 16), 80)
            case .laser:
                state.laserDiameter = min(max(width, 3), 56)
            case .selection, .extract, .geometry, .reserved, .equation, .cover:
                break
            }
        case .setOpacity(let opacity):
            let clampedOpacity = min(max(opacity, 0.1), 1)
            state.opacity = clampedOpacity
            switch state.activeTool {
            case .pen:
                state.penOpacity = clampedOpacity
            case .marker:
                state.markerOpacity = clampedOpacity
            case .selection, .extract, .reserved, .eraser, .geometry, .laser, .equation, .cover:
                break
            }
        case .setLaserDuration(let duration):
            state.laserDuration = min(max(duration, 0), 10)
        case .openColorPicker, .openFillColorPicker, .openColorPaletteChooser:
            break
        case .setPalettePreset(let preset):
            state.palettePreset = preset
            switch state.activeTool {
            case .pen:
                state.penPalettePreset = preset
                state.penPaletteColors = ToolPaletteState.paletteColors(for: preset)
            case .marker:
                state.markerPalettePreset = preset
                state.markerPaletteColors = ToolPaletteState.defaultMarkerPaletteColors(for: preset)
            case .laser:
                state.laserPalettePreset = preset
                state.laserPaletteColors = ToolPaletteState.paletteColors(for: preset)
            case .selection, .extract, .reserved, .eraser, .geometry, .equation, .cover:
                break
            }
        case .setPaletteColor(let tool, let index, let color):
            switch tool {
            case .pen:
                replacePaletteColor(&state.penPaletteColors, at: index, with: color)
                state.penColor = color
            case .marker:
                replacePaletteColor(&state.markerPaletteColors, at: index, with: color)
                state.markerColor = color
            case .laser:
                replacePaletteColor(&state.laserPaletteColors, at: index, with: color)
                state.laserColor = color
            case .selection, .extract, .reserved, .eraser, .geometry, .equation, .cover:
                break
            }
        case .setGeometryType(let geometryType):
            state.geometryType = geometryType
        case .setPolygonSides(let sides):
            state.polygonSides = min(max(sides, 3), 12)
        case .setGeometryLineArrowMode(let mode):
            state.geometryLineArrowMode = mode
        case .setGeometryFillOpacity(let opacity):
            state.geometryFillOpacity = min(max(opacity, 0), 1)
        case .setSelectionTarget(let target):
            state.selectionTarget = target
        case .setSelectionMode(let mode):
            state.selectionMode = mode
        case .setSelectionBehavior(let behavior):
            state.selectionBehavior = behavior
        case .setExtractAction(let action):
            state.extractAction = action
        case .setEraserMode(let mode):
            state.eraserMode = mode
        case .setLaserMode(let mode):
            state.laserMode = mode
        case .setTextBold(let isBold):
            state.textStyle = isBold ? .bold : .normal
        case .setTextItalic(let isItalic):
            state.textIsItalic = isItalic
        case .setTextUnderlined(let isUnderlined):
            state.textIsUnderlined = isUnderlined
        case .setTextSize(let size):
            state.textSize = min(max(size, 8), 96)
        case .setTextFontName(let fontName):
            state.textFontName = fontName
        case .setLatexSource(let source):
            state.latexSource = source
        case .openLatexEditor, .openFontPicker:
            break
        case .addItem:
            // Insertion is wired later (file import, widget config, sticker
            // placement, axis creator); selecting an option is a no-op for now.
            break
        case .copySelection, .pasteSelection, .duplicateSelection, .deleteSelection,
             .extractSelectionAsImageSticker, .sendSelectionToNextSlide:
            state.selectionActionSequence += 1
        case .undo, .redo:
            break
        }
    }
}

struct PenToolDefinition: ToolDefinition {
    let id: ToolID = .pen
    let iconSystemName = ToolID.pen.iconSystemName
    let label = ToolID.pen.displayName

    func configuration(for state: ToolPaletteState) -> ToolPaletteConfiguration {
        ToolPaletteConfiguration(
            topOrbit: colorOrbitItems(state.penPaletteColors, prefix: "pen"),
            leftArc: .slider(
                PaletteSliderConfiguration(
                    id: "pen.width",
                    label: "Width",
                    iconSystemName: "lineweight",
                    value: state.penStrokeWidth,
                    range: 1...24,
                    minEndMarker: .thinLine,
                    maxEndMarker: .thickLine,
                    trackStyle: .graduatedThickness,
                    command: { .setStrokeWidth($0) }
                )
            ),
            rightArc: .slider(
                PaletteSliderConfiguration(
                    id: "pen.opacity",
                    label: "Opacity",
                    iconSystemName: "circle.lefthalf.filled",
                    value: state.penOpacity,
                    range: 0.1...1,
                    minEndMarker: .lightCircle,
                    maxEndMarker: .darkCircle,
                    command: { .setOpacity($0) }
                )
            )
        )
    }
}

struct MarkerToolDefinition: ToolDefinition {
    let id: ToolID = .marker
    let iconSystemName = ToolID.marker.iconSystemName
    let label = ToolID.marker.displayName

    func configuration(for state: ToolPaletteState) -> ToolPaletteConfiguration {
        ToolPaletteConfiguration(
            topOrbit: colorOrbitItems(state.markerPaletteColors, prefix: "marker"),
            leftArc: .slider(
                PaletteSliderConfiguration(
                    id: "marker.width",
                    label: "Width",
                    iconSystemName: "lineweight",
                    value: state.markerStrokeWidth,
                    range: 4...36,
                    minEndMarker: .thinLine,
                    maxEndMarker: .thickLine,
                    trackStyle: .graduatedThickness,
                    command: { .setStrokeWidth($0) }
                )
            ),
            rightArc: .slider(
                PaletteSliderConfiguration(
                    id: "marker.opacity",
                    label: "Opacity",
                    iconSystemName: "circle.lefthalf.filled",
                    value: state.markerOpacity,
                    range: 0.1...1,
                    minEndMarker: .lightCircle,
                    maxEndMarker: .darkCircle,
                    command: { .setOpacity($0) }
                )
            )
        )
    }
}

struct EraserToolDefinition: ToolDefinition {
    let id: ToolID = .eraser
    let iconSystemName = ToolID.eraser.iconSystemName
    let label = ToolID.eraser.displayName

    func configuration(for state: ToolPaletteState) -> ToolPaletteConfiguration {
        ToolPaletteConfiguration(
            topOrbit: [],
            leftArc: .slider(
                PaletteSliderConfiguration(
                    id: "eraser.size",
                    label: "Size",
                    iconSystemName: "circle.dotted",
                    value: state.eraserWidth,
                    range: 16...80,
                    minEndMarker: .thinLine,
                    maxEndMarker: .thickLine,
                    trackStyle: .graduatedThickness,
                    command: { .setStrokeWidth($0) }
                )
            ),
            rightArc: .segmented(
                PaletteSegmentedConfiguration(
                    id: "eraser.mode",
                    label: "Mode",
                    segments: [
                        PaletteSegment(
                            id: "eraser.mode.pixel",
                            label: "Pixels",
                            iconSystemName: "circle.grid.cross",
                            isSelected: state.eraserMode == .pixel,
                            command: .setEraserMode(.pixel)
                        ),
                        PaletteSegment(
                            id: "eraser.mode.stroke",
                            label: "Stroke",
                            iconSystemName: "scribble.variable",
                            isSelected: state.eraserMode == .stroke,
                            command: .setEraserMode(.stroke)
                        )
                    ]
                )
            )
        )
    }
}

struct LaserToolDefinition: ToolDefinition {
    let id: ToolID = .laser
    let iconSystemName = ToolID.laser.iconSystemName
    let label = ToolID.laser.displayName

    func configuration(for state: ToolPaletteState) -> ToolPaletteConfiguration {
        ToolPaletteConfiguration(
            topOrbit: colorOrbitItems(state.laserPaletteColors, prefix: "laser"),
            leftArc: .slider(
                PaletteSliderConfiguration(
                    id: "laser.diameter",
                    label: "Diameter",
                    iconSystemName: "smallcircle.filled.circle",
                    value: state.laserDiameter,
                    range: 3...56,
                    minEndMarker: .thinLine,
                    maxEndMarker: .thickLine,
                    trackStyle: .graduatedThickness,
                    command: { .setStrokeWidth($0) }
                )
            ),
            rightArc: .slider(
                PaletteSliderConfiguration(
                    id: "laser.duration",
                    label: "Fade",
                    iconSystemName: "timer",
                    value: state.laserDuration,
                    range: 0...10,
                    command: { .setLaserDuration($0) }
                )
            )
        )
    }
}

struct SelectionToolDefinition: ToolDefinition {
    let id: ToolID = .selection
    let iconSystemName = ToolID.selection.iconSystemName
    let label = ToolID.selection.displayName

    func configuration(for state: ToolPaletteState) -> ToolPaletteConfiguration {
        ToolPaletteConfiguration(
            topOrbit: [
                PaletteOrbitItem(
                    id: "selection.copy",
                    iconSystemName: "doc.on.doc",
                    label: "Copy",
                    command: .copySelection
                ),
                PaletteOrbitItem(
                    id: "selection.paste",
                    iconSystemName: "doc.on.clipboard",
                    label: "Paste",
                    command: .pasteSelection
                ),
                PaletteOrbitItem(
                    id: "selection.duplicate",
                    iconSystemName: "plus.square.on.square",
                    label: "Clone",
                    command: .duplicateSelection
                ),
                PaletteOrbitItem(
                    id: "selection.delete",
                    iconSystemName: "trash",
                    label: "Delete",
                    command: .deleteSelection
                )
            ],
            leftArc: .disabled(label: "Objects"),
            rightArc: .disabled(label: "Select")
        )
    }
}

struct ExtractToolDefinition: ToolDefinition {
    let id: ToolID = .extract
    let iconSystemName = ToolID.extract.iconSystemName
    let label = ToolID.extract.displayName

    func configuration(for state: ToolPaletteState) -> ToolPaletteConfiguration {
        ToolPaletteConfiguration(
            topOrbit: [
                PaletteOrbitItem(
                    id: "extract.copy",
                    iconSystemName: "doc.on.doc",
                    label: "Copy",
                    command: .copySelection
                ),
                PaletteOrbitItem(
                    id: "extract.paste",
                    iconSystemName: "doc.on.clipboard",
                    label: "Paste",
                    command: .pasteSelection
                ),
                PaletteOrbitItem(
                    id: "extract.duplicate",
                    iconSystemName: "plus.square.on.square",
                    label: "Clone",
                    command: .duplicateSelection
                ),
                PaletteOrbitItem(
                    id: "extract.delete",
                    iconSystemName: "trash",
                    label: "Delete",
                    command: .deleteSelection
                ),
                PaletteOrbitItem(
                    id: "extract.sticker",
                    iconSystemName: "photo.badge.plus",
                    label: "Sticker",
                    command: .extractSelectionAsImageSticker
                ),
                PaletteOrbitItem(
                    id: "extract.send",
                    iconSystemName: "arrow.right.doc.on.clipboard",
                    label: "Send",
                    command: .sendSelectionToNextSlide
                )
            ],
            leftArc: .disabled(label: "Region"),
            rightArc: .segmented(
                PaletteSegmentedConfiguration(
                    id: "extract.mode",
                    label: "Mode",
                    segments: [
                        PaletteSegment(
                            id: "extract.mode.lasso",
                            label: "Lasso",
                            iconSystemName: "lasso",
                            isSelected: state.selectionMode == .lasso,
                            command: .setSelectionMode(.lasso)
                        ),
                        PaletteSegment(
                            id: "extract.mode.marquee",
                            label: "Box",
                            iconSystemName: "rectangle.dashed",
                            isSelected: state.selectionMode == .marquee,
                            command: .setSelectionMode(.marquee)
                        )
                    ]
                )
            )
        )
    }
}

struct GeometryToolDefinition: ToolDefinition {
    let id: ToolID = .geometry
    let iconSystemName = ToolID.geometry.iconSystemName
    let label = ToolID.geometry.displayName

    func configuration(for state: ToolPaletteState) -> ToolPaletteConfiguration {
        ToolPaletteConfiguration(
            topOrbit: geometryOrbitItems(for: state),
            leftArc: .slider(
                PaletteSliderConfiguration(
                    id: "geometry.strokeWidth",
                    label: "Stroke",
                    iconSystemName: "lineweight",
                    value: state.strokeWidth,
                    range: 1...24,
                    minEndMarker: .thinLine,
                    maxEndMarker: .thickLine,
                    trackStyle: .graduatedThickness,
                    command: { .setStrokeWidth($0) }
                )
            ),
            rightArc: geometryRightArc(for: state)
        )
    }

    private func geometryOrbitItems(for state: ToolPaletteState) -> [PaletteOrbitItem] {
        [
            PaletteOrbitItem(
                id: "geometry.outlineColor",
                label: "Outline",
                color: state.strokeColor,
                command: .openColorPicker
            ),
            PaletteOrbitItem(
                id: "geometry.fillColor",
                label: "Fill",
                color: state.fillColor,
                command: .openFillColorPicker
            )
        ]
        + GeometryType.allCases.map { shape in
            PaletteOrbitItem(
                id: "geometry.shape.\(shape.rawValue)",
                iconSystemName: shape.iconSystemName,
                label: shape.displayName,
                command: .setGeometryType(shape)
            )
        }
    }

    private func geometryRightArc(for state: ToolPaletteState) -> PaletteArcConfiguration {
        switch state.geometryType {
        case .line:
            return .slider(
                PaletteSliderConfiguration(
                    id: "geometry.lineArrows",
                    label: "Arrows",
                    iconSystemName: state.geometryLineArrowMode.iconSystemName,
                    value: Double(state.geometryLineArrowMode.sliderIndex),
                    range: 0...3,
                    command: { .setGeometryLineArrowMode(GeometryLineArrowMode(nearestSliderValue: $0)) }
                )
            )
        case .polygon:
            return .slider(
                PaletteSliderConfiguration(
                    id: "geometry.polygonSides",
                    label: "Sides",
                    iconSystemName: "number",
                    value: Double(state.polygonSides),
                    range: 3...12,
                    command: { .setPolygonSides(Int($0.rounded())) }
                )
            )
        case .circle, .rightTriangle, .triangle, .rectangle:
            return .slider(
                PaletteSliderConfiguration(
                    id: "geometry.fillOpacity",
                    label: "Fill",
                    iconSystemName: "circle.lefthalf.filled",
                    value: state.geometryFillOpacity,
                    range: 0...1,
                    minEndMarker: .lightCircle,
                    maxEndMarker: .darkCircle,
                    command: { .setGeometryFillOpacity($0) }
                )
            )
        }
    }
}

struct TextToolDefinition: ToolDefinition {
    let id: ToolID = .equation
    let iconSystemName = ToolID.equation.iconSystemName
    let label = ToolID.equation.displayName

    func configuration(for state: ToolPaletteState) -> ToolPaletteConfiguration {
        ToolPaletteConfiguration(
            topOrbit: [
                PaletteOrbitItem(
                    id: "text.bold",
                    iconSystemName: "bold",
                    label: "Bold",
                    command: .setTextBold(state.textStyle != .bold)
                ),
                PaletteOrbitItem(
                    id: "text.italic",
                    iconSystemName: "italic",
                    label: "Italic",
                    command: .setTextItalic(!state.textIsItalic)
                ),
                PaletteOrbitItem(
                    id: "text.underline",
                    iconSystemName: "underline",
                    label: "Under",
                    command: .setTextUnderlined(!state.textIsUnderlined)
                ),
                PaletteOrbitItem(
                    id: "text.latex",
                    iconSystemName: "sum",
                    label: "LaTeX",
                    command: .openLatexEditor
                )
            ],
            leftArc: .slider(
                PaletteSliderConfiguration(
                    id: "text.size",
                    label: "Size",
                    iconSystemName: "textformat.size",
                    value: state.textSize,
                    range: 8...96,
                    command: { .setTextSize($0) }
                )
            ),
            rightArc: .segmented(
                PaletteSegmentedConfiguration(
                    id: "text.font",
                    label: "Font",
                    segments: [
                        PaletteSegment(
                            id: "text.font.sample",
                            label: "Aa",
                            iconSystemName: nil,
                            isSelected: false,
                            command: .openFontPicker
                        )
                    ]
                )
            )
        )
    }
}

/// The "Add" tool (`.reserved`). Selecting it opens a mini strip of insert
/// options — File (images/PDFs/GIFs), Widget, Sticker, and the Axis creator —
/// rendered as the contextual drawer's orbit chips. Each chip emits
/// `.addItem(kind)`; the actual insertion flow is wired later.
struct AddToolDefinition: ToolDefinition {
    let id: ToolID = .reserved
    let iconSystemName = ToolID.reserved.iconSystemName
    let label = ToolID.reserved.displayName

    func configuration(for state: ToolPaletteState) -> ToolPaletteConfiguration {
        ToolPaletteConfiguration(
            topOrbit: AddItemKind.allCases.map { kind in
                PaletteOrbitItem(
                    id: "add.\(kind.rawValue)",
                    iconSystemName: kind.iconSystemName,
                    label: kind.displayName,
                    command: .addItem(kind)
                )
            },
            leftArc: .disabled(label: "Insert"),
            rightArc: .disabled(label: "Tap to add")
        )
    }
}

private extension GeometryLineArrowMode {
    init(nearestSliderValue value: Double) {
        let index = min(max(Int(value.rounded()), 0), 3)
        switch index {
        case 1:
            self = .start
        case 2:
            self = .end
        case 3:
            self = .both
        default:
            self = .none
        }
    }

    var sliderIndex: Int {
        switch self {
        case .none: return 0
        case .start: return 1
        case .end: return 2
        case .both: return 3
        }
    }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .start: return "Left"
        case .end: return "Right"
        case .both: return "Both"
        }
    }

    var iconSystemName: String {
        switch self {
        case .none: return "circle"
        case .start: return "arrow.left"
        case .end: return "arrow.right"
        case .both: return "arrow.left.and.right"
        }
    }
}

private func replacePaletteColor(_ colors: inout [PaletteColor], at index: Int, with color: PaletteColor) {
    guard colors.indices.contains(index) else { return }
    colors[index] = color
}

struct CoverToolDefinition: ToolDefinition {
    let id: ToolID = .cover
    let iconSystemName = ToolID.cover.iconSystemName
    let label = ToolID.cover.displayName

    func configuration(for state: ToolPaletteState) -> ToolPaletteConfiguration {
        ToolPaletteConfiguration(
            topOrbit: colorOrbitItems(state.penPaletteColors, prefix: "cover"),
            leftArc: .disabled(label: "Region"),
            rightArc: .disabled(label: "Tap to reveal")
        )
    }
}

private func colorOrbitItems(_ colors: [PaletteColor], prefix: String) -> [PaletteOrbitItem] {
    [
        PaletteOrbitItem(
            id: "\(prefix).paletteChooser",
            iconSystemName: "paintpalette",
            label: "Palette",
            command: .openColorPaletteChooser
        )
    ]
    + colors.enumerated().map { index, color in
        PaletteOrbitItem(
            id: "\(prefix).color.\(index)",
            label: color.name,
            color: color,
            command: .setStrokeColor(color)
        )
    }
}

struct PlaceholderToolDefinition: ToolDefinition {
    let id: ToolID
    var iconSystemName: String { id.iconSystemName }
    var label: String { id.displayName }

    func configuration(for state: ToolPaletteState) -> ToolPaletteConfiguration {
        ToolPaletteConfiguration(
            topOrbit: [
                PaletteOrbitItem(
                    id: "\(id.rawValue).placeholder",
                    iconSystemName: id.iconSystemName,
                    label: "Later",
                    command: .selectTool(id)
                )
            ],
            leftArc: .disabled(label: "Pending"),
            rightArc: .disabled(label: "Pending")
        )
    }
}
