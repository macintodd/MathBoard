//
//  CanvasStrokeColorRecord.swift
//  MathBoardCore - Canvas module
//

import CoreGraphics
import Foundation

struct CanvasStrokeColorRecord: Codable, Hashable, Sendable {
    var creationTime: TimeInterval
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    init(creationTime: TimeInterval, red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.creationTime = creationTime
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    var stableKey: Int64 {
        Self.stableKey(for: creationTime)
    }

    static func stableKey(for creationTime: TimeInterval) -> Int64 {
        Int64((creationTime * 1_000_000).rounded())
    }

    static func sidecarURL(forDrawingURL drawingURL: URL) -> URL {
        drawingURL
            .deletingPathExtension()
            .appendingPathExtension("strokecolors.json")
    }

    static func load(from url: URL) -> [CanvasStrokeColorRecord] {
        guard let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([CanvasStrokeColorRecord].self, from: data) else {
            return []
        }
        return records
    }

    static func save(_ records: [CanvasStrokeColorRecord], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(records)
        try data.write(to: url, options: .atomic)
    }
}
