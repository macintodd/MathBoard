//
//  CanvasLaTeXObject.swift
//  MathBoardCore - Canvas module
//

import Foundation

/// Metadata tying an image-backed canvas object to editable LaTeX source.
///
/// The rendered equation lives as a normal `CanvasImageObject`, so it gets image
/// movement, resizing, layering, export, and external-display behavior. This
/// sidecar preserves the source string needed to reopen the LaTeX editor.
public struct CanvasLaTeXObject: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var imageObjectID: UUID
    public var latexSource: String
    public var librarySourceLaTeX: String?
    public var hasRecordedLibraryDerivative: Bool

    public init(
        id: UUID = UUID(),
        imageObjectID: UUID,
        latexSource: String,
        librarySourceLaTeX: String? = nil,
        hasRecordedLibraryDerivative: Bool = false
    ) {
        self.id = id
        self.imageObjectID = imageObjectID
        self.latexSource = latexSource
        self.librarySourceLaTeX = librarySourceLaTeX
        self.hasRecordedLibraryDerivative = hasRecordedLibraryDerivative
    }

    public static func sidecarURL(forDrawingURL drawingURL: URL) -> URL {
        drawingURL
            .deletingPathExtension()
            .appendingPathExtension("latexobjects.json")
    }

    public static func load(from url: URL) -> [CanvasLaTeXObject] {
        guard let data = try? Data(contentsOf: url),
              let objects = try? JSONDecoder().decode([CanvasLaTeXObject].self, from: data) else {
            return []
        }
        return objects
    }

    public static func save(_ objects: [CanvasLaTeXObject], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(objects)
        try data.write(to: url, options: .atomic)
    }
}
