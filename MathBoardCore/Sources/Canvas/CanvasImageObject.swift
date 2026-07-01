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

    public init(
        id: UUID = UUID(),
        imageFileName: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) {
        self.id = id
        self.imageFileName = imageFileName
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var frame: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
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
