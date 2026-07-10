//
//  CanvasCoverObject.swift
//  MathBoardCore - Canvas module
//
//  A "tape" cover: an opaque region drawn on top of all other content that
//  hides whatever is beneath it until revealed. Stored as a polygon in canvas
//  source coordinates (a 4-point rectangle for marquee covers, the drawn path
//  for lasso covers).
//

import CoreGraphics
import Foundation

public struct CanvasCoverObject: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var points: [CGPoint]
    public var red: CGFloat
    public var green: CGFloat
    public var blue: CGFloat
    public var alpha: CGFloat
    public var isRevealed: Bool

    public init(
        id: UUID = UUID(),
        points: [CGPoint],
        red: CGFloat = 0.16,
        green: CGFloat = 0.17,
        blue: CGFloat = 0.20,
        alpha: CGFloat = 1,
        isRevealed: Bool = false
    ) {
        self.id = id
        self.points = points
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
        self.isRevealed = isRevealed
    }

    /// Axis-aligned bounds of the polygon in source coordinates.
    public var boundingBox: CGRect {
        guard let first = points.first else { return .null }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Even-odd point-in-polygon test in source coordinates.
    public func contains(_ point: CGPoint) -> Bool {
        guard points.count >= 3 else { return boundingBox.contains(point) }
        var isInside = false
        var j = points.count - 1
        for i in 0..<points.count {
            let pi = points[i]
            let pj = points[j]
            if (pi.y > point.y) != (pj.y > point.y) {
                let slope = (point.y - pi.y) / (pj.y - pi.y)
                let crossingX = pi.x + slope * (pj.x - pi.x)
                if point.x < crossingX {
                    isInside.toggle()
                }
            }
            j = i
        }
        return isInside
    }

    /// A rectangular (marquee) cover from an axis-aligned rect.
    public static func rectangle(
        _ rect: CGRect,
        red: CGFloat = 0.16,
        green: CGFloat = 0.17,
        blue: CGFloat = 0.20,
        alpha: CGFloat = 1
    ) -> CanvasCoverObject {
        let standardized = rect.standardized
        return CanvasCoverObject(
            points: [
                CGPoint(x: standardized.minX, y: standardized.minY),
                CGPoint(x: standardized.maxX, y: standardized.minY),
                CGPoint(x: standardized.maxX, y: standardized.maxY),
                CGPoint(x: standardized.minX, y: standardized.maxY)
            ],
            red: red,
            green: green,
            blue: blue,
            alpha: alpha
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, points, red, green, blue, alpha, isRevealed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        points = try container.decode([CGPoint].self, forKey: .points)
        red = try container.decodeIfPresent(CGFloat.self, forKey: .red) ?? 0.16
        green = try container.decodeIfPresent(CGFloat.self, forKey: .green) ?? 0.17
        blue = try container.decodeIfPresent(CGFloat.self, forKey: .blue) ?? 0.20
        alpha = try container.decodeIfPresent(CGFloat.self, forKey: .alpha) ?? 1
        isRevealed = try container.decodeIfPresent(Bool.self, forKey: .isRevealed) ?? false
    }

    public static func sidecarURL(forDrawingURL drawingURL: URL) -> URL {
        drawingURL
            .deletingPathExtension()
            .appendingPathExtension("coverobjects.json")
    }

    public static func load(from url: URL) -> [CanvasCoverObject] {
        guard let data = try? Data(contentsOf: url),
              let coverObjects = try? JSONDecoder().decode([CanvasCoverObject].self, from: data) else {
            return []
        }
        return coverObjects
    }

    public static func save(_ coverObjects: [CanvasCoverObject], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(coverObjects)
        try data.write(to: url, options: .atomic)
    }
}
