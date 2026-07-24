//
//  CanvasTextObject.swift
//  MathBoardCore - Canvas module
//

import CoreGraphics
import Foundation

public struct CanvasTextObject: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var text: String
    public var x: CGFloat
    public var y: CGFloat
    public var width: CGFloat
    public var height: CGFloat
    public var fontSize: CGFloat
    public var red: CGFloat
    public var green: CGFloat
    public var blue: CGFloat
    public var alpha: CGFloat
    public var isBold: Bool
    public var isItalic: Bool
    public var isUnderlined: Bool
    public var fontName: String?
    /// Rotation in radians, applied about the text frame center.
    public var rotation: CGFloat
    public var librarySourceText: String?
    public var hasRecordedLibraryDerivative: Bool

    public init(
        id: UUID = UUID(),
        text: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        fontSize: CGFloat,
        red: CGFloat = 0,
        green: CGFloat = 0,
        blue: CGFloat = 0,
        alpha: CGFloat = 1,
        isBold: Bool = false,
        isItalic: Bool = false,
        isUnderlined: Bool = false,
        fontName: String? = nil,
        rotation: CGFloat = 0,
        librarySourceText: String? = nil,
        hasRecordedLibraryDerivative: Bool = false
    ) {
        self.id = id
        self.text = text
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.fontSize = fontSize
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderlined = isUnderlined
        self.fontName = fontName
        self.rotation = rotation
        self.librarySourceText = librarySourceText
        self.hasRecordedLibraryDerivative = hasRecordedLibraryDerivative
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

    public var colorComponents: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        (red, green, blue, alpha)
    }

    public mutating func setColor(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static func sidecarURL(forDrawingURL drawingURL: URL) -> URL {
        drawingURL
            .deletingPathExtension()
            .appendingPathExtension("textobjects.json")
    }

    public static func load(from url: URL) -> [CanvasTextObject] {
        guard let data = try? Data(contentsOf: url),
              let textObjects = try? JSONDecoder().decode([CanvasTextObject].self, from: data) else {
            return []
        }
        return textObjects
    }

    public static func save(_ textObjects: [CanvasTextObject], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(textObjects)
        try data.write(to: url, options: .atomic)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case x
        case y
        case width
        case height
        case fontSize
        case red
        case green
        case blue
        case alpha
        case isBold
        case isItalic
        case isUnderlined
        case fontName
        case rotation
        case librarySourceText
        case hasRecordedLibraryDerivative
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        x = try container.decode(CGFloat.self, forKey: .x)
        y = try container.decode(CGFloat.self, forKey: .y)
        width = try container.decode(CGFloat.self, forKey: .width)
        height = try container.decode(CGFloat.self, forKey: .height)
        fontSize = try container.decode(CGFloat.self, forKey: .fontSize)
        red = try container.decodeIfPresent(CGFloat.self, forKey: .red) ?? 0
        green = try container.decodeIfPresent(CGFloat.self, forKey: .green) ?? 0
        blue = try container.decodeIfPresent(CGFloat.self, forKey: .blue) ?? 0
        alpha = try container.decodeIfPresent(CGFloat.self, forKey: .alpha) ?? 1
        isBold = try container.decodeIfPresent(Bool.self, forKey: .isBold) ?? false
        isItalic = try container.decodeIfPresent(Bool.self, forKey: .isItalic) ?? false
        isUnderlined = try container.decodeIfPresent(Bool.self, forKey: .isUnderlined) ?? false
        fontName = try container.decodeIfPresent(String.self, forKey: .fontName)
        rotation = try container.decodeIfPresent(CGFloat.self, forKey: .rotation) ?? 0
        librarySourceText = try container.decodeIfPresent(String.self, forKey: .librarySourceText)
        hasRecordedLibraryDerivative = try container.decodeIfPresent(Bool.self, forKey: .hasRecordedLibraryDerivative) ?? false
    }
}
