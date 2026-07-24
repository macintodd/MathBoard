//
//  LibraryRecentStore.swift
//  MathBoardCore - Library module
//
//  Per-.mathboard Recent library persistence. This is intentionally small: it
//  records reusable objects that were inserted onto a board so the live Library
//  drawer can show them before the full global library store exists.
//

import Foundation

public enum LibraryRecentKind: String, Codable, Sendable {
    case extractedInk
    case sticker
    case image
    case gif
    case text
    case latex
    case widget
    case graphSnapshot
}

public struct LibraryRecentItem: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var title: String
    public var kind: LibraryRecentKind
    public var createdAt: Date
    public var thumbnailPNGFileName: String?
    public var widgetCodeString: String?
    public var textPayload: LibraryTextPayload?
    public var latexPayload: LibraryLaTeXPayload?

    public init(
        id: UUID = UUID(),
        title: String,
        kind: LibraryRecentKind,
        createdAt: Date = Date(),
        thumbnailPNGFileName: String? = nil,
        widgetCodeString: String? = nil,
        textPayload: LibraryTextPayload? = nil,
        latexPayload: LibraryLaTeXPayload? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.createdAt = createdAt
        self.thumbnailPNGFileName = thumbnailPNGFileName
        self.widgetCodeString = widgetCodeString
        self.textPayload = textPayload
        self.latexPayload = latexPayload
    }
}

public enum LibraryRecentStore {
    private static let directoryName = "library"
    private static let recentFileName = "recent.json"
    private static let recentAssetsDirectoryName = "recent-assets"
    private static let maximumRecentCount = 80

    public static func lessonURL(forDrawingURL drawingURL: URL) -> URL? {
        let strokesURL = drawingURL.deletingLastPathComponent()
        let lessonURL = strokesURL.deletingLastPathComponent()
        return lessonURL.pathExtension == "mathboard" ? lessonURL : nil
    }

    public static func recentFileURL(forLessonURL lessonURL: URL) -> URL {
        directoryURL(forLessonURL: lessonURL).appendingPathComponent(recentFileName)
    }

    public static func thumbnailURL(fileName: String, forLessonURL lessonURL: URL) -> URL {
        assetsDirectoryURL(forLessonURL: lessonURL).appendingPathComponent(fileName)
    }

    public static func loadItems(forLessonURL lessonURL: URL) -> [LibraryRecentItem] {
        let url = recentFileURL(forLessonURL: lessonURL)
        guard let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder.libraryRecent.decode([LibraryRecentItem].self, from: data) else {
            return []
        }
        return items.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    public static func record(
        title: String,
        kind: LibraryRecentKind,
        thumbnailPNGData: Data? = nil,
        widgetCodeString: String? = nil,
        textPayload: LibraryTextPayload? = nil,
        latexPayload: LibraryLaTeXPayload? = nil,
        forDrawingURL drawingURL: URL
    ) throws -> LibraryRecentItem? {
        guard let lessonURL = lessonURL(forDrawingURL: drawingURL) else { return nil }
        return try record(
            title: title,
            kind: kind,
            thumbnailPNGData: thumbnailPNGData,
            widgetCodeString: widgetCodeString,
            textPayload: textPayload,
            latexPayload: latexPayload,
            forLessonURL: lessonURL
        )
    }

    @discardableResult
    public static func record(
        title: String,
        kind: LibraryRecentKind,
        thumbnailPNGData: Data? = nil,
        widgetCodeString: String? = nil,
        textPayload: LibraryTextPayload? = nil,
        latexPayload: LibraryLaTeXPayload? = nil,
        forLessonURL lessonURL: URL
    ) throws -> LibraryRecentItem {
        try FileManager.default.createDirectory(
            at: directoryURL(forLessonURL: lessonURL),
            withIntermediateDirectories: true
        )

        let id = UUID()
        let thumbnailFileName: String?
        if let thumbnailPNGData {
            try FileManager.default.createDirectory(
                at: assetsDirectoryURL(forLessonURL: lessonURL),
                withIntermediateDirectories: true
            )
            let fileName = "\(id.uuidString).png"
            try thumbnailPNGData.write(
                to: thumbnailURL(fileName: fileName, forLessonURL: lessonURL),
                options: .atomic
            )
            thumbnailFileName = fileName
        } else {
            thumbnailFileName = nil
        }

        let item = LibraryRecentItem(
            id: id,
            title: title,
            kind: kind,
            thumbnailPNGFileName: thumbnailFileName,
            widgetCodeString: kind == .widget ? widgetCodeString : nil,
            textPayload: kind == .text ? textPayload : nil,
            latexPayload: kind == .latex ? latexPayload : nil
        )
        var items = loadItems(forLessonURL: lessonURL)
        items.insert(item, at: 0)
        if items.count > maximumRecentCount {
            items = Array(items.prefix(maximumRecentCount))
        }

        let data = try JSONEncoder.libraryRecent.encode(items)
        try data.write(to: recentFileURL(forLessonURL: lessonURL), options: .atomic)
        return item
    }

    private static func directoryURL(forLessonURL lessonURL: URL) -> URL {
        lessonURL.appendingPathComponent(directoryName, isDirectory: true)
    }

    private static func assetsDirectoryURL(forLessonURL lessonURL: URL) -> URL {
        directoryURL(forLessonURL: lessonURL).appendingPathComponent(recentAssetsDirectoryName, isDirectory: true)
    }
}

private extension JSONEncoder {
    static var libraryRecent: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var libraryRecent: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
