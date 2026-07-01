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
        fontName: String? = nil
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
    }

    public var frame: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
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
    }
}
