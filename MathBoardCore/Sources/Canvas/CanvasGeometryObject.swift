//
//  CanvasGeometryObject.swift
//  MathBoardCore - Canvas module
//

import CoreGraphics
import Foundation

/// Shape kind for a geometry object. Canvas-local (the Canvas module does not
/// depend on ToolPalette); the presentation layer maps `GeometryType` onto this.
public enum CanvasGeometryShape: String, Codable, Hashable, Sendable, CaseIterable {
    case line
    case circle
    case rightTriangle
    case triangle
    case rectangle
    case polygon
}

/// Arrowhead placement for line geometry objects.
public enum CanvasGeometryArrow: String, Codable, Hashable, Sendable {
    case none
    case start
    case end
    case both
}

/// A vector geometry object (line / shape) stored on its own layer alongside
/// text and image objects. Coordinates are canvas source coordinates, the same
/// space the `PKDrawing` and other objects use.
public struct CanvasGeometryObject: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var shape: CanvasGeometryShape
    public var x: CGFloat
    public var y: CGFloat
    public var width: CGFloat
    public var height: CGFloat
    public var strokeRed: CGFloat
    public var strokeGreen: CGFloat
    public var strokeBlue: CGFloat
    public var strokeAlpha: CGFloat
    public var strokeWidth: CGFloat
    public var fillRed: CGFloat
    public var fillGreen: CGFloat
    public var fillBlue: CGFloat
    public var fillOpacity: CGFloat
    public var polygonSides: Int
    public var arrow: CanvasGeometryArrow
    /// Rotation in radians, applied about `pivot`.
    public var rotation: CGFloat
    /// Rotation pivot in canvas source coordinates. Nil means the center of the
    /// normalized frame.
    public var pivotX: CGFloat?
    public var pivotY: CGFloat?
    public var isLocked: Bool?

    public init(
        id: UUID = UUID(),
        shape: CanvasGeometryShape,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        strokeRed: CGFloat = 0,
        strokeGreen: CGFloat = 0,
        strokeBlue: CGFloat = 0,
        strokeAlpha: CGFloat = 1,
        strokeWidth: CGFloat = 4,
        fillRed: CGFloat = 0.13,
        fillGreen: CGFloat = 0.68,
        fillBlue: CGFloat = 0.95,
        fillOpacity: CGFloat = 0,
        polygonSides: Int = 5,
        arrow: CanvasGeometryArrow = .none,
        rotation: CGFloat = 0,
        pivotX: CGFloat? = nil,
        pivotY: CGFloat? = nil,
        isLocked: Bool? = nil
    ) {
        self.id = id
        self.shape = shape
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.strokeRed = strokeRed
        self.strokeGreen = strokeGreen
        self.strokeBlue = strokeBlue
        self.strokeAlpha = strokeAlpha
        self.strokeWidth = strokeWidth
        self.fillRed = fillRed
        self.fillGreen = fillGreen
        self.fillBlue = fillBlue
        self.fillOpacity = fillOpacity
        self.polygonSides = polygonSides
        self.arrow = arrow
        self.rotation = rotation
        self.pivotX = pivotX
        self.pivotY = pivotY
        self.isLocked = isLocked
    }

    public var frame: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    /// Normalized frame with a positive width/height regardless of the drag
    /// direction used to create the object.
    public var normalizedFrame: CGRect {
        frame.standardized
    }

    /// True when the signed width crosses back over the source origin.
    public var isFlippedHorizontal: Bool {
        width < 0
    }

    /// True when the signed height crosses back over the source origin.
    public var isFlippedVertical: Bool {
        height < 0
    }

    /// Rotation pivot in source coordinates, defaulting to the frame center.
    public var pivot: CGPoint {
        CGPoint(x: pivotX ?? normalizedFrame.midX, y: pivotY ?? normalizedFrame.midY)
    }

    private enum CodingKeys: String, CodingKey {
        case id, shape, x, y, width, height
        case strokeRed, strokeGreen, strokeBlue, strokeAlpha, strokeWidth
        case fillRed, fillGreen, fillBlue, fillOpacity
        case polygonSides, arrow, rotation, pivotX, pivotY, isLocked
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        shape = try container.decodeIfPresent(CanvasGeometryShape.self, forKey: .shape) ?? .rectangle
        x = try container.decode(CGFloat.self, forKey: .x)
        y = try container.decode(CGFloat.self, forKey: .y)
        width = try container.decode(CGFloat.self, forKey: .width)
        height = try container.decode(CGFloat.self, forKey: .height)
        strokeRed = try container.decodeIfPresent(CGFloat.self, forKey: .strokeRed) ?? 0
        strokeGreen = try container.decodeIfPresent(CGFloat.self, forKey: .strokeGreen) ?? 0
        strokeBlue = try container.decodeIfPresent(CGFloat.self, forKey: .strokeBlue) ?? 0
        strokeAlpha = try container.decodeIfPresent(CGFloat.self, forKey: .strokeAlpha) ?? 1
        strokeWidth = try container.decodeIfPresent(CGFloat.self, forKey: .strokeWidth) ?? 4
        fillRed = try container.decodeIfPresent(CGFloat.self, forKey: .fillRed) ?? 0.13
        fillGreen = try container.decodeIfPresent(CGFloat.self, forKey: .fillGreen) ?? 0.68
        fillBlue = try container.decodeIfPresent(CGFloat.self, forKey: .fillBlue) ?? 0.95
        fillOpacity = try container.decodeIfPresent(CGFloat.self, forKey: .fillOpacity) ?? 0
        polygonSides = try container.decodeIfPresent(Int.self, forKey: .polygonSides) ?? 5
        arrow = try container.decodeIfPresent(CanvasGeometryArrow.self, forKey: .arrow) ?? .none
        rotation = try container.decodeIfPresent(CGFloat.self, forKey: .rotation) ?? 0
        pivotX = try container.decodeIfPresent(CGFloat.self, forKey: .pivotX)
        pivotY = try container.decodeIfPresent(CGFloat.self, forKey: .pivotY)
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked)
    }

    public static func sidecarURL(forDrawingURL drawingURL: URL) -> URL {
        drawingURL
            .deletingPathExtension()
            .appendingPathExtension("geometryobjects.json")
    }

    public static func load(from url: URL) -> [CanvasGeometryObject] {
        guard let data = try? Data(contentsOf: url),
              let geometryObjects = try? JSONDecoder().decode([CanvasGeometryObject].self, from: data) else {
            return []
        }
        return geometryObjects
    }

    public static func save(_ geometryObjects: [CanvasGeometryObject], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(geometryObjects)
        try data.write(to: url, options: .atomic)
    }
}
