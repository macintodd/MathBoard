//
//  WidgetMediaAssetStore.swift
//  WidgetEngine
//

import Foundation

public enum WidgetMediaKind: String, Codable, Equatable, Sendable {
    case gif
    case movie
}

public struct WidgetMediaAsset: Equatable, Sendable {
    public var fileName: String
    public var displayName: String
    public var kind: WidgetMediaKind

    public init(fileName: String, displayName: String, kind: WidgetMediaKind) {
        self.fileName = fileName
        self.displayName = displayName
        self.kind = kind
    }
}

public enum WidgetMediaAssetStore {
    public enum ImportError: LocalizedError, Equatable {
        case unsupportedFileType(String)
        case missingFileName

        public var errorDescription: String? {
            switch self {
            case .unsupportedFileType(let extensionName):
                return "MathBoard can add GIF, MP4, M4V, and MOV files. This file uses .\(extensionName)."
            case .missingFileName:
                return "MathBoard could not read the selected file name."
            }
        }
    }

    public static func assetDirectoryURL(forDrawingURL drawingURL: URL) -> URL {
        drawingURL
            .deletingPathExtension()
            .appendingPathExtension("widgetmedia")
    }

    public static func mediaKind(for url: URL) -> WidgetMediaKind? {
        switch url.pathExtension.lowercased() {
        case "gif":
            return .gif
        case "mp4", "m4v", "mov":
            return .movie
        default:
            return nil
        }
    }

    public static func copyMediaFile(
        from sourceURL: URL,
        forDrawingURL drawingURL: URL,
        fileManager: FileManager = .default
    ) throws -> WidgetMediaAsset {
        guard let kind = mediaKind(for: sourceURL) else {
            let extensionName = sourceURL.pathExtension.isEmpty ? "unknown" : sourceURL.pathExtension
            throw ImportError.unsupportedFileType(extensionName)
        }

        let originalName = sourceURL.deletingPathExtension().lastPathComponent
        guard !originalName.isEmpty else {
            throw ImportError.missingFileName
        }

        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let directoryURL = assetDirectoryURL(forDrawingURL: drawingURL)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let safeBaseName = sanitizedFileBaseName(originalName)
        let fileName = "\(UUID().uuidString.lowercased())-\(safeBaseName).\(sourceURL.pathExtension.lowercased())"
        let destinationURL = directoryURL.appendingPathComponent(fileName, isDirectory: false)
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        return WidgetMediaAsset(
            fileName: fileName,
            displayName: originalName,
            kind: kind
        )
    }

    public static func html(for asset: WidgetMediaAsset) -> String {
        let title = escapeHTML(asset.displayName)
        let source = escapeHTML(asset.fileName)
        switch asset.kind {
        case .gif:
            return """
            <!doctype html>
            <html>
            <head>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
            html, body { margin: 0; width: 100%; height: 100%; background: #111; overflow: hidden; }
            body { display: flex; align-items: center; justify-content: center; }
            img { width: 100%; height: 100%; object-fit: contain; }
            </style>
            </head>
            <body>
            <img src="\(source)" alt="\(title)">
            </body>
            </html>
            """
        case .movie:
            return """
            <!doctype html>
            <html>
            <head>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
            html, body { margin: 0; width: 100%; height: 100%; background: #111; overflow: hidden; }
            body { display: flex; align-items: center; justify-content: center; }
            video { width: 100%; height: 100%; object-fit: contain; background: #111; }
            .loop-toggle {
                position: fixed;
                top: 10px;
                right: 10px;
                z-index: 2;
                border: 2px solid rgba(255, 255, 255, 0.72);
                border-radius: 8px;
                background: rgba(0, 0, 0, 0.58);
                color: #fff;
                font: 700 14px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
                padding: 8px 12px;
            }
            .loop-toggle[aria-pressed="true"] {
                border-color: #35d96d;
                background: rgba(9, 92, 42, 0.84);
            }
            </style>
            </head>
            <body>
            <button class="loop-toggle" type="button" aria-pressed="false">Loop</button>
            <video id="media" controls playsinline preload="metadata" title="\(title)">
              <source src="\(source)" type="\(mimeType(forFileName: asset.fileName))">
            </video>
            <script>
            const video = document.getElementById('media');
            const loopToggle = document.querySelector('.loop-toggle');
            loopToggle.addEventListener('click', () => {
                video.loop = !video.loop;
                loopToggle.setAttribute('aria-pressed', video.loop ? 'true' : 'false');
            });
            </script>
            </body>
            </html>
            """
        }
    }

    private static func sanitizedFileBaseName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = name.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let sanitized = String(scalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return sanitized.isEmpty ? "media" : sanitized
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func mimeType(forFileName fileName: String) -> String {
        switch URL(fileURLWithPath: fileName).pathExtension.lowercased() {
        case "mp4":
            return "video/mp4"
        case "m4v":
            return "video/x-m4v"
        case "mov":
            return "video/quicktime"
        default:
            return "application/octet-stream"
        }
    }
}
