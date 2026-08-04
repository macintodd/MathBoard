//
//  CanvasLiveInkPersistence.swift
//  MathBoardCore - Canvas module
//
//  Persists received live classroom ink into the local PencilKit drawing file.
//

import CoreGraphics
import Foundation

#if os(iOS)
import PencilKit
import UIKit

public enum CanvasLiveInkPersistence {
    private static let drawingOriginOffset = CGPoint(x: 3000, y: 3000)

    public static func mergeLiveInkStrokes(
        _ strokes: [CanvasLiveStroke],
        strokeIDs: [UUID],
        into drawingURL: URL
    ) throws -> Int {
        let strokePairs = zip(strokeIDs, strokes).filter { pair in
            pair.1.kind == .ink && !pair.1.samples.isEmpty
        }
        guard !strokePairs.isEmpty else { return 0 }

        var persistedStrokeIDs = loadPersistedStrokeIDs(for: drawingURL)
        let newStrokePairs = strokePairs.filter { pair in
            !persistedStrokeIDs.contains(pair.0)
        }
        guard !newStrokePairs.isEmpty else { return 0 }

        let existingDrawing = loadCanvasDrawing(at: drawingURL)
        var mergedStrokes = existingDrawing.strokes
        let newPKStrokes = newStrokePairs.map { pair in
            makePKStroke(from: pair.1)
        }
        mergedStrokes.append(contentsOf: newPKStrokes)

        try FileManager.default.createDirectory(
            at: drawingURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let storageDrawing = PKDrawing(strokes: mergedStrokes)
            .transformed(using: canvasToStorageTransform)
        try storageDrawing.dataRepresentation().write(to: drawingURL, options: .atomic)

        persistedStrokeIDs.formUnion(newStrokePairs.map(\.0))
        try savePersistedStrokeIDs(persistedStrokeIDs, for: drawingURL)
        return newPKStrokes.count
    }

    public static func sidecarURL(forDrawingURL drawingURL: URL) -> URL {
        drawingURL
            .deletingPathExtension()
            .appendingPathExtension("teacherliveink.json")
    }

    private static var storageToCanvasTransform: CGAffineTransform {
        CGAffineTransform(
            translationX: drawingOriginOffset.x,
            y: drawingOriginOffset.y
        )
    }

    private static var canvasToStorageTransform: CGAffineTransform {
        CGAffineTransform(
            translationX: -drawingOriginOffset.x,
            y: -drawingOriginOffset.y
        )
    }

    private static func loadCanvasDrawing(at url: URL) -> PKDrawing {
        guard let data = try? Data(contentsOf: url),
              let drawing = try? PKDrawing(data: data) else {
            return PKDrawing()
        }
        return drawing.transformed(using: storageToCanvasTransform)
    }

    private static func makePKStroke(from stroke: CanvasLiveStroke) -> PKStroke {
        let creationDate = Date(
            timeIntervalSinceReferenceDate: stroke.samples.first?.timestamp ?? Date().timeIntervalSinceReferenceDate
        )
        let firstTimestamp = stroke.samples.first?.timestamp ?? 0
        let pointSize = persistedStrokePointSize(for: stroke)
        let controlPoints = stroke.samples.map { sample in
            PKStrokePoint(
                location: sample.location,
                timeOffset: max(sample.timestamp - firstTimestamp, 0),
                size: pointSize,
                opacity: stroke.color.alpha,
                force: sample.pressure,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        let path = PKStrokePath(controlPoints: controlPoints, creationDate: creationDate)
        return PKStroke(
            ink: PKInk(.pen, color: stroke.color.uiColor),
            path: path
        )
    }

    static func persistedStrokePointSize(for stroke: CanvasLiveStroke) -> CGSize {
        let lineWidth = stroke.color.alpha >= 0.95
            ? CanvasVectorInk.crispLineWidth(baseLineWidth: stroke.lineWidth)
            : stroke.lineWidth
        let clampedLineWidth = max(lineWidth, 1)
        return CGSize(width: clampedLineWidth, height: clampedLineWidth)
    }

    private static func loadPersistedStrokeIDs(for drawingURL: URL) -> Set<UUID> {
        let url = sidecarURL(forDrawingURL: drawingURL)
        guard let data = try? Data(contentsOf: url),
              let strings = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(strings.compactMap(UUID.init(uuidString:)))
    }

    private static func savePersistedStrokeIDs(_ strokeIDs: Set<UUID>, for drawingURL: URL) throws {
        let url = sidecarURL(forDrawingURL: drawingURL)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let strings = strokeIDs.map(\.uuidString).sorted()
        let data = try JSONEncoder().encode(strings)
        try data.write(to: url, options: .atomic)
    }
}

private extension CanvasStrokeColor {
    var uiColor: UIColor {
        UIColor(
            red: min(max(red, 0), 1),
            green: min(max(green, 0), 1),
            blue: min(max(blue, 0), 1),
            alpha: min(max(alpha, 0), 1)
        )
    }
}
#endif
