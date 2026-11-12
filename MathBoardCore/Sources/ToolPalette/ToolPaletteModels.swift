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
    case fountainPen
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
        case .fountainPen: return "Fountain"
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
        case .selection: return "cursorarrow"
        case .extract: return "crop"
        case .reserved: return "plus"
        case .pen: return "pencil.tip"
        case .fountainPen: return "pencil.and.scribble"
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
/// one later triggers the matching insertion flow.
public enum AddItemKind: String, CaseIterable, Codable, Equatable, Sendable {
    /// Images imported from the file system. PDF objects are a separate flow.
    case file
    /// Images imported from Apple Photos.
    case photo
    /// Images captured with the device camera.
    case camera
    /// Animated GIFs and movie files rendered by the widget layer.
    case media
    /// A formatted text object created in the Text Editor.
    case text
    /// A rendered LaTeX equation object created in the LaTeX editor.
    case latex
    /// An interactive/configurable widget (timer, RNG, table, HTML, …).
    case widget
    /// A reusable sticker from the Library.
    case sticker
    /// The coordinate-axis creator.
    case axis

    public static let visibleItems: [AddItemKind] = [.file, .photo, .camera, .media, .text, .latex, .widget]

    public var displayName: String {
        switch self {
        case .file: return "File"
        case .photo: return "Photo"
        case .camera: return "Camera"
        case .media: return "Media"
        case .text: return "Text"
        case .latex: return "LaTeX"
        case .widget: return "Widget"
        case .sticker: return "Sticker"
        case .axis: return "Axis"
        }
    }

    public var iconSystemName: String {
        switch self {
        case .file: return "doc.badge.plus"
        case .photo: return "photo.on.rectangle"
        case .camera: return "camera"
        case .media: return "play.rectangle"
        case .text: return "textformat"
        case .latex: return "function"
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
    case tap
    case lasso
    case marquee
}

public enum SelectionBehavior: String, CaseIterable, Codable, Equatable, Sendable {
    case single
    case multi

    public var displayName: String {
        switch self {
        case .single: return "Select"
        case .multi: return "Multi Select"
        }
    }

    public var iconSystemName: String {
        switch self {
        case .single: return "cursorarrow"
        case .multi: return "cursorarrow.motionlines"
        }
    }

    public var toggled: SelectionBehavior {
        switch self {
        case .single: return .multi
        case .multi: return .single
        }
    }
}

public enum ExtractAction: String, CaseIterable, Codable, Equatable, Sendable {
    case copy
    case clone
    case send
    case sticker
    case delete

    public static let visibleActions: [ExtractAction] = [.copy, .sticker, .send]

    public var displayName: String {
        switch self {
        case .copy: return "Copy"
        case .clone: return "Clone"
        case .send: return "Send"
        case .sticker: return "Sticker"
        case .delete: return "Delete"
        }
    }

    public var iconSystemName: String {
        switch self {
        case .copy: return "doc.on.doc"
        case .clone: return "plus.square.on.square"
        case .send: return "arrow.right.doc.on.clipboard"
        case .sticker: return "photo.badge.plus"
        case .delete: return "trash"
        }
    }
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
    case neon
    case retro
    case ocean
    case dusk
    case ink

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .bright: return "Bright"
        case .jewel: return "Jewel"
        case .pastel: return "Pastel"
        case .earth: return "Earth"
        case .neon: return "Neon"
        case .retro: return "Retro"
        case .ocean: return "Ocean"
        case .dusk: return "Dusk"
        case .ink: return "Ink"
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
        case .neon:
            return [
                PaletteColor(name: "Electric", red: 0.00, green: 0.55, blue: 1.00),
                PaletteColor(name: "Magenta", red: 1.00, green: 0.08, blue: 0.60),
                PaletteColor(name: "Acid", red: 0.22, green: 1.00, blue: 0.40),
                PaletteColor(name: "Plasma", red: 1.00, green: 0.45, blue: 0.00)
            ]
        case .retro:
            return [
                PaletteColor(name: "Burnt", red: 0.84, green: 0.42, blue: 0.14),
                PaletteColor(name: "Avocado", red: 0.52, green: 0.58, blue: 0.22),
                PaletteColor(name: "Rust", red: 0.70, green: 0.28, blue: 0.14),
                PaletteColor(name: "Harvest", red: 0.86, green: 0.66, blue: 0.12)
            ]
        case .ocean:
            return [
                PaletteColor(name: "Abyss", red: 0.06, green: 0.22, blue: 0.48),
                PaletteColor(name: "Pacific", red: 0.10, green: 0.52, blue: 0.78),
                PaletteColor(name: "Seafoam", red: 0.22, green: 0.78, blue: 0.72),
                PaletteColor(name: "Reef", red: 0.94, green: 0.38, blue: 0.30)
            ]
        case .dusk:
            return [
                PaletteColor(name: "Twilight", red: 0.30, green: 0.20, blue: 0.56),
                PaletteColor(name: "Violet", red: 0.58, green: 0.36, blue: 0.88),
                PaletteColor(name: "Blush", red: 0.92, green: 0.48, blue: 0.62),
                PaletteColor(name: "Marigold", red: 0.96, green: 0.70, blue: 0.14)
            ]
        case .ink:
            return [
                PaletteColor(name: "Black", red: 0.04, green: 0.04, blue: 0.04),
                PaletteColor(name: "White", red: 0.97, green: 0.96, blue: 0.94),
                PaletteColor(name: "Cyan", red: 0.00, green: 0.73, blue: 0.90),
                PaletteColor(name: "Gold", red: 1.00, green: 0.75, blue: 0.00)
            ]
        }
    }
}

public struct ToolPaletteState: Equatable, Sendable {
    public var activeTool: ToolID
    public var strokeColor: PaletteColor
    public var penColor: PaletteColor
    public var fountainPenColor: PaletteColor
    public var markerColor: PaletteColor
    public var laserColor: PaletteColor
    public var fillColor: PaletteColor
    public var palettePreset: PalettePreset
    public var penPalettePreset: PalettePreset
    public var fountainPenPalettePreset: PalettePreset
    public var markerPalettePreset: PalettePreset
    public var laserPalettePreset: PalettePreset
    public var penPaletteColors: [PaletteColor]
    public var fountainPenPaletteColors: [PaletteColor]
    public var markerPaletteColors: [PaletteColor]
    public var laserPaletteColors: [PaletteColor]
    public var coverPaletteColors: [PaletteColor]
    public var strokeWidth: Double
    public var opacity: Double
    public var penStrokeWidth: Double
    public var fountainPenStrokeWidth: Double
    public var markerStrokeWidth: Double
    public var eraserWidth: Double
    public var laserDiameter: Double
    public var penOpacity: Double
    public var fountainPenOpacity: Double
    public var markerOpacity: Double
    public var laserDuration: Double
    public var geometryType: GeometryType
    public var polygonSides: Int
    public var geometryLineArrowMode: GeometryLineArrowMode
    public var geometryFillOpacity: Double
    public var selectionTarget: SelectionTarget
    public var selectionMode: SelectionMode
    public var selectionBehavior: SelectionBehavior
    public var extractAction: ExtractAction
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
    /// Compact-palette contextual drawer visibility. Kept in shared state so
    /// the mirrored external display matches the iPad.
    public var isCompactDrawerOpen: Bool
    /// Compact-palette mini strip visibility for quick tool choices.
    public var isCompactQuickStripOpen: Bool

    public init(
        activeTool: ToolID = .pen,
        strokeColor: PaletteColor = .graphite,
        penColor: PaletteColor? = nil,
        fountainPenColor: PaletteColor? = nil,
        markerColor: PaletteColor? = .yellow,
        laserColor: PaletteColor? = .coral,
        fillColor: PaletteColor = .sky,
        palettePreset: PalettePreset = .bright,
        penPalettePreset: PalettePreset? = nil,
        fountainPenPalettePreset: PalettePreset? = nil,
        markerPalettePreset: PalettePreset? = nil,
        laserPalettePreset: PalettePreset? = nil,
        penPaletteColors: [PaletteColor]? = nil,
        fountainPenPaletteColors: [PaletteColor]? = nil,
        markerPaletteColors: [PaletteColor]? = nil,
        laserPaletteColors: [PaletteColor]? = nil,
        coverPaletteColors: [PaletteColor]? = nil,
        strokeWidth: Double = 10,
        opacity: Double = 1,
        penStrokeWidth: Double? = 24,
        fountainPenStrokeWidth: Double? = nil,
        markerStrokeWidth: Double = 36,
        eraserWidth: Double? = nil,
        laserDiameter: Double? = 60,
        penOpacity: Double? = nil,
        fountainPenOpacity: Double? = nil,
        markerOpacity: Double = 0.5,
        laserDuration: Double = 0,
        geometryType: GeometryType = .line,
        polygonSides: Int = 5,
        geometryLineArrowMode: GeometryLineArrowMode = .none,
        geometryFillOpacity: Double = 0.35,
        selectionTarget: SelectionTarget = .region,
        selectionMode: SelectionMode = .tap,
        selectionBehavior: SelectionBehavior = .single,
        extractAction: ExtractAction = .copy,
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
        isCompactDrawerOpen: Bool = true,
        isCompactQuickStripOpen: Bool = false
    ) {
        self.activeTool = activeTool
        self.strokeColor = strokeColor
        self.penColor = penColor ?? strokeColor
        self.fountainPenColor = fountainPenColor ?? strokeColor
        self.markerColor = markerColor ?? strokeColor
        self.laserColor = laserColor ?? strokeColor
        self.fillColor = fillColor
        self.palettePreset = palettePreset
        self.penPalettePreset = penPalettePreset ?? palettePreset
        self.fountainPenPalettePreset = fountainPenPalettePreset ?? palettePreset
        self.markerPalettePreset = markerPalettePreset ?? palettePreset
        self.laserPalettePreset = laserPalettePreset ?? palettePreset
        self.penPaletteColors = penPaletteColors ?? Self.paletteColors(for: self.penPalettePreset)
        self.fountainPenPaletteColors = fountainPenPaletteColors ?? Self.paletteColors(for: self.fountainPenPalettePreset)
        self.markerPaletteColors = markerPaletteColors ?? Self.defaultMarkerPaletteColors(for: self.markerPalettePreset)
        self.laserPaletteColors = laserPaletteColors ?? Self.paletteColors(for: self.laserPalettePreset)
        self.coverPaletteColors = coverPaletteColors ?? Self.paletteColors(for: palettePreset)
        self.strokeWidth = strokeWidth
        self.opacity = opacity
        self.penStrokeWidth = penStrokeWidth ?? strokeWidth
        self.fountainPenStrokeWidth = fountainPenStrokeWidth ?? strokeWidth
        self.markerStrokeWidth = markerStrokeWidth
        self.eraserWidth = eraserWidth ?? 24
        self.laserDiameter = laserDiameter ?? strokeWidth
        self.penOpacity = penOpacity ?? opacity
        self.fountainPenOpacity = fountainPenOpacity ?? opacity
        self.markerOpacity = markerOpacity
        self.laserDuration = laserDuration
        self.geometryType = geometryType
        self.polygonSides = polygonSides
        self.geometryLineArrowMode = geometryLineArrowMode
        self.geometryFillOpacity = geometryFillOpacity
        self.selectionTarget = selectionTarget
        self.selectionMode = selectionMode
        self.selectionBehavior = selectionBehavior
        self.extractAction = extractAction
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
        self.isCompactQuickStripOpen = isCompactQuickStripOpen
    }

    public func iconSystemName(for tool: ToolID) -> String {
        tool == .selection ? selectionBehavior.iconSystemName : tool.iconSystemName
    }

    public var activeStrokeColor: PaletteColor {
        switch activeTool {
        case .pen:
            return penColor
        case .fountainPen:
            return fountainPenColor
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
        case .fountainPen:
            return fountainPenPalettePreset
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
        case .fountainPen:
            return fountainPenPaletteColors
        case .marker:
            return markerPaletteColors
        case .laser:
            return laserPaletteColors
        case .cover:
            return coverPaletteColors
        case .selection, .extract, .reserved, .eraser, .geometry, .equation:
            return Self.paletteColors(for: palettePreset)
        }
    }

    public var activeStrokeWidth: Double {
        switch activeTool {
        case .pen:
            return penStrokeWidth
        case .fountainPen:
            return fountainPenStrokeWidth
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
        case .fountainPen:
            return fountainPenOpacity
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

/// Ink-tool settings that survive lesson close/reopen. Saved to UserDefaults as
/// JSON so only drawing-relevant state is persisted (no transient UI flags).
public struct PersistedInkToolSettings: Codable, Sendable {
    public var penStrokeWidth: Double
    public var penOpacity: Double
    public var penColor: PaletteColor
    public var penPalettePreset: PalettePreset
    public var penPaletteColors: [PaletteColor]
    public var fountainPenStrokeWidth: Double
    public var fountainPenOpacity: Double
    public var fountainPenColor: PaletteColor
    public var fountainPenPalettePreset: PalettePreset
    public var fountainPenPaletteColors: [PaletteColor]
    public var markerStrokeWidth: Double
    public var markerOpacity: Double
    public var markerColor: PaletteColor
    public var markerPalettePreset: PalettePreset
    public var markerPaletteColors: [PaletteColor]
    public var laserDiameter: Double
    public var laserColor: PaletteColor
    public var laserPalettePreset: PalettePreset
    public var laserPaletteColors: [PaletteColor]

    private static let userDefaultsKey = "MathBoard.inkToolSettings"

    public init(from state: ToolPaletteState) {
        penStrokeWidth = state.penStrokeWidth
        penOpacity = state.penOpacity
        penColor = state.penColor
        penPalettePreset = state.penPalettePreset
        penPaletteColors = state.penPaletteColors
        fountainPenStrokeWidth = state.fountainPenStrokeWidth
        fountainPenOpacity = state.fountainPenOpacity
        fountainPenColor = state.fountainPenColor
        fountainPenPalettePreset = state.fountainPenPalettePreset
        fountainPenPaletteColors = state.fountainPenPaletteColors
        markerStrokeWidth = state.markerStrokeWidth
        markerOpacity = state.markerOpacity
        markerColor = state.markerColor
        markerPalettePreset = state.markerPalettePreset
        markerPaletteColors = state.markerPaletteColors
        laserDiameter = state.laserDiameter
        laserColor = state.laserColor
        laserPalettePreset = state.laserPalettePreset
        laserPaletteColors = state.laserPaletteColors
    }

    public func apply(to state: inout ToolPaletteState) {
        state.penStrokeWidth = penStrokeWidth
        state.penOpacity = penOpacity
        state.penColor = penColor
        state.penPalettePreset = penPalettePreset
        state.penPaletteColors = penPaletteColors
        state.fountainPenStrokeWidth = fountainPenStrokeWidth
        state.fountainPenOpacity = fountainPenOpacity
        state.fountainPenColor = fountainPenColor
        state.fountainPenPalettePreset = fountainPenPalettePreset
        state.fountainPenPaletteColors = fountainPenPaletteColors
        state.markerStrokeWidth = markerStrokeWidth
        state.markerOpacity = markerOpacity
        state.markerColor = markerColor
        state.markerPalettePreset = markerPalettePreset
        state.markerPaletteColors = markerPaletteColors
        state.laserDiameter = laserDiameter
        state.laserColor = laserColor
        state.laserPalettePreset = laserPalettePreset
        state.laserPaletteColors = laserPaletteColors
    }

    public static func load() -> PersistedInkToolSettings? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let settings = try? JSONDecoder().decode(PersistedInkToolSettings.self, from: data) else {
            return nil
        }
        return settings
    }

    public func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
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
    case setSelectionBehavior(SelectionBehavior)
    case setExtractAction(ExtractAction)
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
    case collapseCompactDrawerForCanvasInteraction
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
    case hidden
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
