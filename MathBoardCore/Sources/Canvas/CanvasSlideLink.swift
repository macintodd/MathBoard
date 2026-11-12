//
//  CanvasSlideLink.swift
//  MathBoardCore — Canvas module
//
//  A forward hyperlink stored on a source slide pointing to an image object
//  that was sent to another slide via the extract-send action.
//
//  Keyed by imageObjectID (not by destination slideID) so the link survives
//  the image being moved to a different slide. Navigation scans for the ID
//  at tap time.
//
//  Persisted in a sidecar beside the source slide's drawing file:
//  slide-<uuid>.slidelinks.json
//

import CoreGraphics
import Foundation

public struct CanvasSlideLink: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    /// The image object that was extracted from this slide and sent elsewhere.
    public let imageObjectID: UUID
    /// The extraction region in storage coordinate space (same space as CanvasImageObject.x/y).
    public let sourceRect: CGRect
    /// User-dragged chip offset from its default anchor position, in screen points.
    public var chipOffset: CGPoint

    public init(
        id: UUID = UUID(),
        imageObjectID: UUID,
        sourceRect: CGRect,
        chipOffset: CGPoint = .zero
    ) {
        self.id = id
        self.imageObjectID = imageObjectID
        self.sourceRect = sourceRect
        self.chipOffset = chipOffset
    }

    public static func sidecarURL(forDrawingURL drawingURL: URL) -> URL {
        drawingURL
            .deletingPathExtension()
            .appendingPathExtension("slidelinks.json")
    }

    public static func load(from url: URL) -> [CanvasSlideLink] {
        guard let data = try? Data(contentsOf: url),
              let links = try? JSONDecoder().decode([CanvasSlideLink].self, from: data) else {
            return []
        }
        return links
    }

    public static func save(_ links: [CanvasSlideLink], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(links)
        try data.write(to: url, options: .atomic)
    }
}
