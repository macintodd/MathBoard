//
//  ToolPaletteModels.swift
//  MathBoardCore - ToolPalette module
//
//  App-independent state and command types for the standalone radial palette.
//  PencilKit mapping belongs in a future Canvas-side adapter, not here.
//

import Foundation

public enum ToolID: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case selection
    case extract
    case reserved
    case pen
    case marker
    case eraser
    case geometry
    case laser
    case equation
    case cover

    public var displayName: String {
        switch self {
        case .selection: return "Select"
        case .extract: return "Extract"
        case .reserved: return "Add"
        case .pen: return "Pen"
        case .marker: return "Marker"
        case .eraser: return "Eraser"
        case .geometry: return "Geometry"
        case .laser: return "Laser"
        case .equation: return "Text"
        case .cover: return "Tape"
        }
    }

    public var iconSystemName: String {
        switch self {
        case .selection: return "cursorarrow.motionlines"
        case .extract: return "crop"
        case .reserved: return "plus"
        case .pen: return "pencil.tip"
        case .marker: return "highlighter"
        case .eraser: return "eraser"
        case .geometry: return "ruler"
        case .laser: return "laser.burst"
        case .equation: return "textformat"
        case .cover: return "square.dashed.inset.filled"
        }
    }
}

/// Kinds of content the "Add" tool (`.reserved`) can insert. Selecting the Add
/// tool opens a mini strip of these options in the contextual drawer; picking
/// one later triggers the matching insertion flow (file import, widget config,
/// sticker placement, or the coordinate-axis creator). Wiring is added later —
/// for now the command is a no-op in the reducer.
public enum AddItemKind: String, CaseIterable, Codable, Equatable, Sendable {
    /// Images, PDFs, and GIFs imported from the file system / photo library.
    case file
    /// An interactive/configurable widget (timer, RNG, table, HTML, …).
    case widget
    /// A reusable sticker from the Library.
    case sticker
    /// The coordinate-axis creator.
    case axis

    public var displayName: String {
        switch self {
        case .file: return "File"
        case .widget: return "Widget"
        case .sticker: return "Sticker"
        case .axis: return "Axis"
        }
    }

    public var iconSystemName: String {
        switch self {
        case .file: return "doc.badge.plus"
        case .widget: return "square.grid.2x2"
        case .sticker: return "sparkles.rectangle.stack"
        case .axis: return "chart.xyaxis.line"
        }
    }
}

public enum GeometryType: String, CaseIterable, Codable, Equatable, Sendable {
    case line
    case circle
    case rightTriangle
    case triangle
    case rectangle
    case polygon

    public var displayName: String {
        switch self {
        case .line: return "Line"
        case .circle: return "Circle"
        case .rightTriangle: return "Right"
        case .triangle: return "Tri"
        case .rectangle: return "Rect"
        case .polygon: return "Poly"
        }
    }

    public var iconSystemName: String {
        switch self {
        case .line: return "line.diagonal"
        case .circle: return "circle"
        case .rightTriangle: return "righttriangle"
        case .triangle: return "triangle"
        case .rectangle: return "rectangle"
        case .polygon: return "hexagon"
        }
    }
}

public enum GeometryLineArrowMode: String, CaseIterable, Codable, Equatable, Sendable {
    case none
    case start
    case end
    case both
}

public enum SelectionTarget: String, CaseIterable, Codable, Equatable, Sendable {
    case object
    case region
}

public enum SelectionMode: String, CaseIterable, Codable, Equatable, Sendable {
    case lasso
    case marquee
}

public enum EraserMode: String, CaseIterable, Codable, Equatable, Sendable {
    case pixel
    case stroke
}

public enum LaserMode: String, CaseIterable, Codable, Equatable, Sendable {
    case dot
    case trail
}

public enum PaletteTextStyle: String, CaseIterable, Codable, Equatable, Sendable {
    case normal
    case bold
}

public struct PaletteColor: Codable, Equatable, Identifiable, Sendable {
    public var id: String { name }
    public var name: String
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(name: String, red: Double, green: Double, blue: Double) {
        self.name = name
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let graphite = PaletteColor(name: "Graphite", red: 0.07, green: 0.10, blue: 0.14)
    public static let sky = PaletteColor(name: "Sky", red: 0.13, green: 0.68, blue: 0.95)
    public static let mint = PaletteColor(name: "Mint", red: 0.12, green: 0.76, blue: 0.52)
    public static let amber = PaletteColor(name: "Amber", red: 0.96, green: 0.64, blue: 0.18)
    public static let coral = PaletteColor(name: "Coral", red: 0.94, green: 0.28, blue: 0.25)
    public static let yellow = PaletteColor(name: "Yellow", red: 1.0, green: 0.86, blue: 0.18)

    public static let penPresets: [PaletteColor] = [.graphite, .sky, .mint, .amber, .coral]
}

public enum PalettePreset: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case bright
    case jewel
    case pastel
    case earth

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .bright: return "Bright"
        case .jewel: return "Jewel"
        case .pastel: return "Pastel"
        case .earth: return "Earth"
        }
    }

    public var colors: [PaletteColor] {
        switch self {
        case .bright:
            return [.sky, .mint, .amber, .coral]
        case .jewel:
            return [
                PaletteColor(name: "Sapphire", red: 0.18, green: 0.42, blue: 0.93),
                PaletteColor(name: "Emerald", red: 0.05, green: 0.62, blue: 0.38),
                PaletteColor(name: "Amethyst", red: 0.56, green: 0.32, blue: 0.88),
                PaletteColor(name: "Ruby", red: 0.78, green: 0.12, blue: 0.24)
            ]
        case .pastel:
            return [
                PaletteColor(name: "Pool", red: 0.48, green: 0.78, blue: 0.94),
                PaletteColor(name: "Sage", red: 0.56, green: 0.78, blue: 0.58),
                PaletteColor(name: "Peach", red: 0.96, green: 0.66, blue: 0.45),
                PaletteColor(name: "Rose", red: 0.92, green: 0.52, blue: 0.68)
            ]
        case .earth:
            return [
                PaletteColor(name: "Lake", red: 0.18, green: 0.50, blue: 0.68),
                PaletteColor(name: "Moss", red: 0.34, green: 0.52, blue: 0.26),
                PaletteColor(name: "Ochre", red: 0.74, green: 0.52, blue: 0.20),
                PaletteColor(name: "Clay", red: 0.70, green: 0.30, blue: 0.20)
            ]
        }
    }
}

public struct ToolPaletteState: Equatable, Sendable {
    public var activeTool: ToolID
    public var strokeColor: PaletteColor
    public var penColor: PaletteColor
    public var markerColor: PaletteColor
    public var laserColor: PaletteColor
    public var fillColor: PaletteColor
    public var palettePreset: PalettePreset
    public var penPalettePreset: PalettePreset
    public var markerPalettePreset: PalettePreset
    public var laserPalettePreset: PalettePreset
    public var penPaletteColors: [PaletteColor]
    public var markerPaletteColors: [PaletteColor]
    public var laserPaletteColors: [PaletteColor]
    public var strokeWidth: Double
    public var opacity: Double
    public var penStrokeWidth: Double
    public var markerStrokeWidth: Double
    public var eraserWidth: Double
    public var laserDiameter: Double
    public var penOpacity: Double
    public var markerOpacity: Double
    public var laserDuration: Double
    public var geometryType: GeometryType
    public var polygonSides: Int
    public var geometryLineArrowMode: GeometryLineArrowMode
    public var geometryFillOpacity: Double
    public var selectionTarget: SelectionTarget
    public var selectionMode: SelectionMode
    public var eraserMode: EraserMode
    public var laserMode: LaserMode
    public var textStyle: PaletteTextStyle
    public var textIsItalic: Bool
    public var textIsUnderlined: Bool
    public var textSize: Double
    public var textFontName: String
    public var latexSource: String
    public var rotation: Double
    public var isColorBloomOpen: Bool
    public var selectionActionSequence: Int
    /// Compact-palette contextual drawer visibility. When false, tools that have
    /// a quick-strip show the slim mini-strip instead of the full drawer. Kept in
    /// shared state so the mirrored external display matches the iPad.
    public var isCompactDrawerOpen: Bool

    public init(
        activeTool: ToolID = .pen,
        strokeColor: PaletteColor = .graphite,
        penColor: PaletteColor? = nil,
        markerColor: PaletteColor? = .yellow,
        laserColor: PaletteColor? = .coral,
        fillColor: PaletteColor = .sky,
        palettePreset: PalettePreset = .bright,
        penPalettePreset: PalettePreset? = nil,
        markerPalettePreset: PalettePreset? = nil,
        laserPalettePreset: PalettePreset? = nil,
        penPaletteColors: [PaletteColor]? = nil,
        markerPaletteColors: [PaletteColor]? = nil,
        laserPaletteColors: [PaletteColor]? = nil,
        strokeWidth: Double = 10,
        opacity: Double = 1,
        penStrokeWidth: Double? = nil,
        markerStrokeWidth: Double = 18,
        eraserWidth: Double? = nil,
        laserDiameter: Double? = 20,
        penOpacity: Double? = nil,
        markerOpacity: Double = 0.5,
        laserDuration: Double = 0,
        geometryType: GeometryType = .line,
        polygonSides: Int = 5,
        geometryLineArrowMode: GeometryLineArrowMode = .none,
        geometryFillOpacity: Double = 0.35,
        selectionTarget: SelectionTarget = .region,
        selectionMode: SelectionMode = .lasso,
        eraserMode: EraserMode = .pixel,
        laserMode: LaserMode = .dot,
        textStyle: PaletteTextStyle = .normal,
        textIsItalic: Bool = false,
        textIsUnderlined: Bool = false,
        textSize: Double = 28,
        textFontName: String = "System",
        latexSource: String = "",
        rotation: Double = 0,
        isColorBloomOpen: Bool = false,
        selectionActionSequence: Int = 0,
        isCompactDrawerOpen: Bool = true
    ) {
        self.activeTool = activeTool
        self.strokeColor = strokeColor
        self.penColor = penColor ?? strokeColor
        self.markerColor = markerColor ?? strokeColor
        self.laserColor = laserColor ?? strokeColor
        self.fillColor = fillColor
        self.palettePreset = palettePreset
        self.penPalettePreset = penPalettePreset ?? palettePreset
        self.markerPalettePreset = markerPalettePreset ?? palettePreset
        self.laserPalettePreset = laserPalettePreset ?? palettePreset
        self.penPaletteColors = penPaletteColors ?? Self.paletteColors(for: self.penPalettePreset)
        self.markerPaletteColors = markerPaletteColors ?? Self.defaultMarkerPaletteColors(for: self.markerPalettePreset)
        self.laserPaletteColors = laserPaletteColors ?? Self.paletteColors(for: self.laserPalettePreset)
        self.strokeWidth = strokeWidth
        self.opacity = opacity
        self.penStrokeWidth = penStrokeWidth ?? strokeWidth
        self.markerStrokeWidth = markerStrokeWidth
        self.eraserWidth = eraserWidth ?? 24
        self.laserDiameter = laserDiameter ?? strokeWidth
        self.penOpacity = penOpacity ?? opacity
        self.markerOpacity = markerOpacity
        self.laserDuration = laserDuration
        self.geometryType = geometryType
        self.polygonSides = polygonSides
        self.geometryLineArrowMode = geometryLineArrowMode
        self.geometryFillOpacity = geometryFillOpacity
        self.selectionTarget = selectionTarget
        self.selectionMode = selectionMode
        self.eraserMode = eraserMode
        self.laserMode = laserMode
        self.textStyle = textStyle
        self.textIsItalic = textIsItalic
        self.textIsUnderlined = textIsUnderlined
        self.textSize = textSize
        self.textFontName = textFontName
        self.latexSource = latexSource
        self.rotation = rotation
        self.isColorBloomOpen = isColorBloomOpen
        self.selectionActionSequence = selectionActionSequence
        self.isCompactDrawerOpen = isCompactDrawerOpen
    }

    public var activeStrokeColor: PaletteColor {
        switch activeTool {
        case .pen:
            return penColor
        case .marker:
            return markerColor
        case .laser:
            return laserColor
        case .selection, .extract, .reserved, .eraser, .geometry, .equation, .cover:
            return strokeColor
        }
    }

    public var activePalettePreset: PalettePreset {
        switch activeTool {
        case .pen:
            return penPalettePreset
        case .marker:
            return markerPalettePreset
        case .laser:
            return laserPalettePreset
        case .selection, .extract, .reserved, .eraser, .geometry, .equation, .cover:
            return palettePreset
        }
    }

    public var activePaletteColors: [PaletteColor] {
        switch activeTool {
        case .pen:
            return penPaletteColors
        case .marker:
            return markerPaletteColors
        case .laser:
            return laserPaletteColors
        case .selection, .extract, .reserved, .eraser, .geometry, .equation, .cover:
            return Self.paletteColors(for: palettePreset)
        }
    }

    public var activeStrokeWidth: Double {
        switch activeTool {
        case .pen:
            return penStrokeWidth
        case .marker:
            return markerStrokeWidth
        case .eraser:
            return eraserWidth
        case .laser:
            return laserDiameter
        case .selection, .extract, .geometry, .reserved, .equation, .cover:
            return strokeWidth
        }
    }

    public var activeOpacity: Double {
        switch activeTool {
        case .pen:
            return penOpacity
        case .marker:
            return markerOpacity
        case .selection, .extract, .reserved, .eraser, .geometry, .laser, .equation, .cover:
            return opacity
        }
    }

    public static func paletteColors(for preset: PalettePreset) -> [PaletteColor] {
        [.graphite] + preset.colors
    }

    public static func defaultMarkerPaletteColors(for preset: PalettePreset) -> [PaletteColor] {
        var colors = paletteColors(for: preset)
        if colors.indices.contains(1) {
            colors[1] = .yellow
        }
        return colors
    }
}

public enum ToolPaletteCommand: Equatable, Sendable {
    case selectTool(ToolID)
    case setStrokeColor(PaletteColor)
    case setFillColor(PaletteColor)
    case setStrokeWidth(Double)
    case setOpacity(Double)
    case setLaserDuration(Double)
    case openColorPicker
    case openFillColorPicker
    case openColorPaletteChooser
    case setPalettePreset(PalettePreset)
    case setPaletteColor(ToolID, Int, PaletteColor)
    case setGeometryType(GeometryType)
    case setPolygonSides(Int)
    case setGeometryLineArrowMode(GeometryLineArrowMode)
    case setGeometryFillOpacity(Double)
    case setSelectionTarget(SelectionTarget)
    case setSelectionMode(SelectionMode)
    case setEraserMode(EraserMode)
    case setLaserMode(LaserMode)
    case setTextBold(Bool)
    case setTextItalic(Bool)
    case setTextUnderlined(Bool)
    case setTextSize(Double)
    case setTextFontName(String)
    case openLatexEditor
    case setLatexSource(String)
    case openFontPicker
    /// Insert a piece of content via the "Add" tool's mini strip.
    case addItem(AddItemKind)
    case undo
    case redo
    case copySelection
    case pasteSelection
    case duplicateSelection
    case deleteSelection
    case extractSelectionAsImageSticker
    case sendSelectionToNextSlide
}

public struct PaletteOrbitItem: Identifiable, Equatable, Sendable {
    public var id: String
    public var iconSystemName: String?
    public var label: String
    public var color: PaletteColor?
    public var command: ToolPaletteCommand

    public init(id: String, iconSystemName: String? = nil, label: String, color: PaletteColor? = nil, command: ToolPaletteCommand) {
        self.id = id
        self.iconSystemName = iconSystemName
        self.label = label
        self.color = color
        self.command = command
    }
}

public enum PaletteArcConfiguration: Equatable, Sendable {
    case slider(PaletteSliderConfiguration)
    case segmented(PaletteSegmentedConfiguration)
    case disabled(label: String)
}

/// Glyph drawn at an end of a slider track to communicate what that extreme
/// represents (e.g. a thin vs. thick line for stroke width).
public enum PaletteSliderEndMarker: Equatable, Sendable {
    case thinLine
    case thickLine
    case lightCircle
    case darkCircle
}

/// Decoration drawn along a slider track.
public enum PaletteSliderTrackStyle: Equatable, Sendable {
    case plain
    /// Graduated hash marks that grow thicker toward the maximum-value end.
    case graduatedThickness
}

public struct PaletteSliderConfiguration: Equatable, Sendable {
    public var id: String
    public var label: String
    public var iconSystemName: String
    public var value: Double
    public var range: ClosedRange<Double>
    /// Marker shown at the minimum-value end of the track.
    public var minEndMarker: PaletteSliderEndMarker?
    /// Marker shown at the maximum-value end of the track.
    public var maxEndMarker: PaletteSliderEndMarker?
    /// Decoration drawn along the track between the two ends.
    public var trackStyle: PaletteSliderTrackStyle
    public var command: @Sendable (Double) -> ToolPaletteCommand

    public init(
        id: String,
        label: String,
        iconSystemName: String,
        value: Double,
        range: ClosedRange<Double>,
        minEndMarker: PaletteSliderEndMarker? = nil,
        maxEndMarker: PaletteSliderEndMarker? = nil,
        trackStyle: PaletteSliderTrackStyle = .plain,
        command: @escaping @Sendable (Double) -> ToolPaletteCommand
    ) {
        self.id = id
        self.label = label
        self.iconSystemName = iconSystemName
        self.value = value
        self.range = range
        self.minEndMarker = minEndMarker
        self.maxEndMarker = maxEndMarker
        self.trackStyle = trackStyle
        self.command = command
    }

    public static func == (lhs: PaletteSliderConfiguration, rhs: PaletteSliderConfiguration) -> Bool {
        lhs.id == rhs.id
            && lhs.label == rhs.label
            && lhs.iconSystemName == rhs.iconSystemName
            && lhs.value == rhs.value
            && lhs.range == rhs.range
            && lhs.minEndMarker == rhs.minEndMarker
            && lhs.maxEndMarker == rhs.maxEndMarker
            && lhs.trackStyle == rhs.trackStyle
    }
}

public struct PaletteSegmentedConfiguration: Equatable, Sendable {
    public var id: String
    public var label: String
    public var segments: [PaletteSegment]

    public init(id: String, label: String, segments: [PaletteSegment]) {
        self.id = id
        self.label = label
        self.segments = segments
    }
}

public struct PaletteSegment: Identifiable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var iconSystemName: String?
    public var isSelected: Bool
    public var command: ToolPaletteCommand

    public init(id: String, label: String, iconSystemName: String? = nil, isSelected: Bool, command: ToolPaletteCommand) {
        self.id = id
        self.label = label
        self.iconSystemName = iconSystemName
        self.isSelected = isSelected
        self.command = command
    }
}

public struct ToolPaletteConfiguration: Equatable, Sendable {
    public var topOrbit: [PaletteOrbitItem]
    public var leftArc: PaletteArcConfiguration
    public var rightArc: PaletteArcConfiguration

    public init(topOrbit: [PaletteOrbitItem], leftArc: PaletteArcConfiguration, rightArc: PaletteArcConfiguration) {
        self.topOrbit = topOrbit
        self.leftArc = leftArc
        self.rightArc = rightArc
    }
}
