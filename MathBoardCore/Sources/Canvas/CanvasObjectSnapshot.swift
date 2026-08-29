//
//  CanvasObjectSnapshot.swift
//  MathBoardCore - Canvas module
//

import Foundation

public struct CanvasObjectSnapshotFile: Codable, Hashable, Sendable {
    public var name: String
    public var base64Data: String

    public init(name: String, data: Data) {
        self.name = name
        self.base64Data = data.base64EncodedString()
    }

    public init(name: String, base64Data: String) {
        self.name = name
        self.base64Data = base64Data
    }

    public var data: Data? {
        Data(base64Encoded: base64Data)
    }
}

public struct CanvasObjectSnapshot: Codable, Hashable, Sendable {
    public static let sidecarFileNames = [
        "textobjects.json",
        "imageobjects.json",
        "latexobjects.json",
        "geometryobjects.json",
        "coverobjects.json",
        "widgets.json",
        "objectlayers.json"
    ]

    public var slideID: UUID
    public var revision: Int
    public var capturedAt: Date
    public var sidecarFiles: [CanvasObjectSnapshotFile]
    public var imageAssetFiles: [CanvasObjectSnapshotFile]

    public init(
        slideID: UUID,
        revision: Int = 0,
        capturedAt: Date = Date(),
        sidecarFiles: [CanvasObjectSnapshotFile],
        imageAssetFiles: [CanvasObjectSnapshotFile]
    ) {
        self.slideID = slideID
        self.revision = revision
        self.capturedAt = capturedAt
        self.sidecarFiles = sidecarFiles
        self.imageAssetFiles = imageAssetFiles
    }

    public static func capture(
        slideID: UUID,
        drawingURL: URL,
        revision: Int = 0,
        fileManager: FileManager = .default
    ) -> CanvasObjectSnapshot {
        let baseURL = drawingURL.deletingPathExtension()
        let sidecarFiles = sidecarFileNames.compactMap { fileName -> CanvasObjectSnapshotFile? in
            let url = sidecarURL(named: fileName, baseURL: baseURL)
            guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
            return CanvasObjectSnapshotFile(name: fileName, data: data)
        }

        let imageAssetDirectory = CanvasImageObject.assetDirectoryURL(forDrawingURL: drawingURL)
        let imageAssetFiles = ((try? fileManager.contentsOfDirectory(
            at: imageAssetDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? [])
            .filter { !$0.hasDirectoryPath }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { url -> CanvasObjectSnapshotFile? in
                guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
                return CanvasObjectSnapshotFile(name: url.lastPathComponent, data: data)
            }

        return CanvasObjectSnapshot(
            slideID: slideID,
            revision: revision,
            sidecarFiles: sidecarFiles,
            imageAssetFiles: imageAssetFiles
        )
    }

    public var isEmpty: Bool {
        sidecarFiles.isEmpty && imageAssetFiles.isEmpty
    }

    /// Writes the snapshot to disk.
    /// - Parameter preserving: Sidecar file names to leave untouched — they
    ///   will neither be deleted nor overwritten even if present in the snapshot.
    public func write(to drawingURL: URL, preserving: Set<String> = [], fileManager: FileManager = .default) throws {
        let baseURL = drawingURL.deletingPathExtension()
        try fileManager.createDirectory(at: baseURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        for fileName in Self.sidecarFileNames {
            guard !preserving.contains(fileName) else { continue }
            let url = Self.sidecarURL(named: fileName, baseURL: baseURL)
            if fileManager.fileExists(atPath: url.path), !sidecarFiles.contains(where: { $0.name == fileName }) {
                try fileManager.removeItem(at: url)
            }
        }

        for file in sidecarFiles {
            guard !preserving.contains(file.name), let data = file.data else { continue }
            let url = Self.sidecarURL(named: file.name, baseURL: baseURL)
            try data.write(to: url, options: .atomic)
        }

        let imageAssetDirectory = CanvasImageObject.assetDirectoryURL(forDrawingURL: drawingURL)
        if fileManager.fileExists(atPath: imageAssetDirectory.path) {
            try fileManager.removeItem(at: imageAssetDirectory)
        }
        if !imageAssetFiles.isEmpty {
            try fileManager.createDirectory(at: imageAssetDirectory, withIntermediateDirectories: true)
        }
        for file in imageAssetFiles {
            guard let data = file.data else { continue }
            try data.write(to: imageAssetDirectory.appendingPathComponent(file.name), options: .atomic)
        }
    }

    private static func sidecarURL(named fileName: String, baseURL: URL) -> URL {
        baseURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(baseURL.lastPathComponent).\(fileName)")
    }
}
