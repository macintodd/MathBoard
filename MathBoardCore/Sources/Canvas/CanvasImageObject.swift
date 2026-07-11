//
//  CanvasImageObject.swift
//  MathBoardCore - Canvas module
//

import CoreGraphics
import Foundation

public struct CanvasImageObject: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var imageFileName: String
    public var x: CGFloat
    public var y: CGFloat
    public var width: CGFloat
    public var height: CGFloat
    /// Rotation in radians, applied about the image frame center.
    public var rotation: CGFloat
    public var isLocked: Bool?

    public init(
        id: UUID = UUID(),
        imageFileName: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        rotation: CGFloat = 0,
        isLocked: Bool? = nil
    ) {
        self.id = id
        self.imageFileName = imageFileName
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.rotation = rotation
        self.isLocked = isLocked
    }

    public var frame: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    public var center: CGPoint {
        CGPoint(x: x + width / 2, y: y + height / 2)
    }

    public var renderedBounds: CGRect {
        guard rotation != 0 else { return frame }
        let corners = [
            CGPoint(x: frame.minX, y: frame.minY),
            CGPoint(x: frame.maxX, y: frame.minY),
            CGPoint(x: frame.maxX, y: frame.maxY),
            CGPoint(x: frame.minX, y: frame.maxY)
        ].map { point -> CGPoint in
            let dx = point.x - center.x
            let dy = point.y - center.y
            let cosR = cos(rotation)
            let sinR = sin(rotation)
            return CGPoint(x: center.x + dx * cosR - dy * sinR, y: center.y + dx * sinR + dy * cosR)
        }
        let minX = corners.map(\.x).min() ?? frame.minX
        let maxX = corners.map(\.x).max() ?? frame.maxX
        let minY = corners.map(\.y).min() ?? frame.minY
        let maxY = corners.map(\.y).max() ?? frame.maxY
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private enum CodingKeys: String, CodingKey {
        case id, imageFileName, x, y, width, height, rotation, isLocked
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        imageFileName = try container.decode(String.self, forKey: .imageFileName)
        x = try container.decode(CGFloat.self, forKey: .x)
        y = try container.decode(CGFloat.self, forKey: .y)
        width = try container.decode(CGFloat.self, forKey: .width)
        height = try container.decode(CGFloat.self, forKey: .height)
        rotation = try container.decodeIfPresent(CGFloat.self, forKey: .rotation) ?? 0
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked)
    }

    public static func sidecarURL(forDrawingURL drawingURL: URL) -> URL {
        drawingURL
            .deletingPathExtension()
            .appendingPathExtension("imageobjects.json")
    }

    public static func assetDirectoryURL(forDrawingURL drawingURL: URL) -> URL {
        drawingURL
            .deletingPathExtension()
            .appendingPathExtension("imageobjects")
    }

    public static func load(from url: URL) -> [CanvasImageObject] {
        guard let data = try? Data(contentsOf: url),
              let imageObjects = try? JSONDecoder().decode([CanvasImageObject].self, from: data) else {
            return []
        }
        return imageObjects
    }

    public static func save(_ imageObjects: [CanvasImageObject], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(imageObjects)
        try data.write(to: url, options: .atomic)
    }
}
