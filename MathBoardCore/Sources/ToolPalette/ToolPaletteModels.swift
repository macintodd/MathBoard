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
    case reserved
    case pen
    case marker
    case eraser
    case geometry
    case laser
    case equation

    public var displayName: String {
        switch self {
        case .selection: return "Select"
        case .reserved: return "Widget"
        case .pen: return "Pen"
        case .marker: return "Marker"
        case .eraser: return "Eraser"
        case .geometry: return "Geometry"
        case .laser: return "Laser"
        case .equation: return "Text"
        }
    }

    public var iconSystemName: String {
        switch self {
        case .selection: return "cursorarrow.motionlines"
        case .reserved: return "curlybraces.square"
        case .pen: return "pencil.tip"
        case .marker: return "highlighter"
        case .eraser: return "eraser"
        case .geometry: return "ruler"
        case .laser: return "laser.burst"
        case .equation: return "textformat"
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

    public init(
        activeTool: ToolID = .pen,
        strokeColor: PaletteColor = .graphite,
        penColor: PaletteColor? = nil,
        markerColor: PaletteColor? = nil,
        laserColor: PaletteColor? = nil,
        fillColor: PaletteColor = .sky,
        palettePreset: PalettePreset = .bright,
        strokeWidth: Double = 6,
        opacity: Double = 1,
        penStrokeWidth: Double? = nil,
        markerStrokeWidth: Double = 18,
        eraserWidth: Double? = nil,
        laserDiameter: Double? = nil,
        penOpacity: Double? = nil,
        markerOpacity: Double = 0.5,
        laserDuration: Double = 3,
        geometryType: GeometryType = .line,
        polygonSides: Int = 5,
        geometryLineArrowMode: GeometryLineArrowMode = .none,
        geometryFillOpacity: Double = 0.35,
        selectionTarget: SelectionTarget = .region,
        selectionMode: SelectionMode = .lasso,
        eraserMode: EraserMode = .pixel,
        laserMode: LaserMode = .trail,
        textStyle: PaletteTextStyle = .normal,
        textIsItalic: Bool = false,
        textIsUnderlined: Bool = false,
        textSize: Double = 28,
        textFontName: String = "System",
        latexSource: String = "",
        rotation: Double = 0,
        isColorBloomOpen: Bool = false,
        selectionActionSequence: Int = 0
    ) {
        self.activeTool = activeTool
        self.strokeColor = strokeColor
        self.penColor = penColor ?? strokeColor
        self.markerColor = markerColor ?? strokeColor
        self.laserColor = laserColor ?? strokeColor
        self.fillColor = fillColor
        self.palettePreset = palettePreset
        self.strokeWidth = strokeWidth
        self.opacity = opacity
        self.penStrokeWidth = penStrokeWidth ?? strokeWidth
        self.markerStrokeWidth = markerStrokeWidth
        self.eraserWidth = eraserWidth ?? strokeWidth
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
    }

    public var activeStrokeColor: PaletteColor {
        switch activeTool {
        case .pen:
            return penColor
        case .marker:
            return markerColor
        case .laser:
            return laserColor
        case .selection, .reserved, .eraser, .geometry, .equation:
            return strokeColor
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
        case .selection, .geometry, .reserved, .equation:
            return strokeWidth
        }
    }

    public var activeOpacity: Double {
        switch activeTool {
        case .pen:
            return penOpacity
        case .marker:
            return markerOpacity
        case .selection, .reserved, .eraser, .geometry, .laser, .equation:
            return opacity
        }
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
    case createWidget
    case editWidget
    case openWidget
    case removeWidget
    case undo
    case redo
    case copySelection
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
