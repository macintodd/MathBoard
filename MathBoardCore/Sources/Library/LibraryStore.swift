//
//  LibraryStore.swift
//  MathBoardCore - Library module
//
//  Global reusable library persistence. This stores real Libraries tab folders
//  and the Recent items starred into them; it does not yet handle inserting
//  library items back onto the canvas.
//

import Foundation

public struct LibraryStoredFolder: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var symbol: String
    public var tintIndex: Int
    public var keywords: [String]
    public var isPinned: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        symbol: String = "folder",
        tintIndex: Int = 0,
        keywords: [String] = [],
        isPinned: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.tintIndex = tintIndex
        self.keywords = keywords
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct LibraryStoredItem: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var recentID: String
    public var title: String
    public var kind: LibraryRecentKind
    public var createdAt: Date
    public var thumbnailPNGFileName: String?
    public var widgetCodeString: String?
    public var textPayload: LibraryTextPayload?
    public var latexPayload: LibraryLaTeXPayload?

    public init(
        id: UUID = UUID(),
        recentID: String,
        title: String,
        kind: LibraryRecentKind,
        createdAt: Date = Date(),
        thumbnailPNGFileName: String? = nil,
        widgetCodeString: String? = nil,
        textPayload: LibraryTextPayload? = nil,
        latexPayload: LibraryLaTeXPayload? = nil
    ) {
        self.id = id
        self.recentID = recentID
        self.title = title
        self.kind = kind
        self.createdAt = createdAt
        self.thumbnailPNGFileName = thumbnailPNGFileName
        self.widgetCodeString = widgetCodeString
        self.textPayload = textPayload
        self.latexPayload = latexPayload
    }
}

public enum LibraryStore {
    private struct Manifest: Codable {
        var folders: [LibraryStoredFolder]
    }

    private static let rootDirectoryName = "Library"
    private static let manifestFileName = "libraries.json"
    private static let itemsFileName = "items.json"
    private static let assetsDirectoryName = "assets"
    private static let maximumItemsPerLibrary = 240

    public static func loadFolders() -> [LibraryStoredFolder] {
        ensureBootstrapIfNeeded()
        guard let data = try? Data(contentsOf: manifestURL()),
              let manifest = try? JSONDecoder.libraryStore.decode(Manifest.self, from: data) else {
            return []
        }
        return manifest.folders.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    public static func loadItems(in folderID: UUID) -> [LibraryStoredItem] {
        let url = itemsURL(for: folderID)
        guard let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder.libraryStore.decode([LibraryStoredItem].self, from: data) else {
            return []
        }
        return items.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    public static func createFolder(named requestedName: String) throws -> LibraryStoredFolder {
        let name = uniqueFolderName(for: requestedName)
        var folders = loadFolders()
        let folder = LibraryStoredFolder(
            name: name,
            symbol: "folder",
            tintIndex: folders.count
        )
        folders.append(folder)
        try saveFolders(folders)
        try FileManager.default.createDirectory(
            at: folderDirectoryURL(for: folder.id),
            withIntermediateDirectories: true
        )
        return folder
    }

    @discardableResult
    public static func renameFolder(_ folderID: UUID, to requestedName: String) throws -> LibraryStoredFolder? {
        var folders = loadFolders()
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else { return nil }
        let name = uniqueFolderName(for: requestedName, excluding: folderID)
        folders[index].name = name
        folders[index].updatedAt = Date()
        try saveFolders(folders)
        return folders[index]
    }

    public static func deleteFolder(_ folderID: UUID) throws {
        var folders = loadFolders()
        guard folders.contains(where: { $0.id == folderID }) else { return }
        folders.removeAll { $0.id == folderID }
        try saveFolders(folders)

        let folderURL = folderDirectoryURL(for: folderID)
        if FileManager.default.fileExists(atPath: folderURL.path) {
            try FileManager.default.removeItem(at: folderURL)
        }
    }

    @discardableResult
    public static func setPinned(_ isPinned: Bool, for folderID: UUID) throws -> LibraryStoredFolder? {
        var folders = loadFolders()
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else { return nil }
        folders[index].isPinned = isPinned
        folders[index].updatedAt = Date()
        try saveFolders(folders)
        return folders[index]
    }

    public static func containsRecentItem(_ recentID: String, in folderID: UUID) -> Bool {
        loadItems(in: folderID).contains { $0.recentID == recentID }
    }

    public static func addRecentItem(
        recentID: String,
        title: String,
        kind: LibraryRecentKind,
        thumbnailURL: URL?,
        widgetCodeString: String? = nil,
        textPayload: LibraryTextPayload? = nil,
        latexPayload: LibraryLaTeXPayload? = nil,
        to folderID: UUID
    ) throws {
        try FileManager.default.createDirectory(
            at: folderDirectoryURL(for: folderID),
            withIntermediateDirectories: true
        )

        let itemID = UUID()
        let thumbnailFileName: String?
        if let thumbnailURL,
           FileManager.default.fileExists(atPath: thumbnailURL.path) {
            try FileManager.default.createDirectory(
                at: assetsDirectoryURL(for: folderID),
                withIntermediateDirectories: true
            )
            let fileName = "\(itemID.uuidString).png"
            try FileManager.default.copyItem(
                at: thumbnailURL,
                to: assetsDirectoryURL(for: folderID).appendingPathComponent(fileName)
            )
            thumbnailFileName = fileName
        } else {
            thumbnailFileName = nil
        }

        let item = LibraryStoredItem(
            id: itemID,
            recentID: recentID,
            title: title,
            kind: kind,
            thumbnailPNGFileName: thumbnailFileName,
            widgetCodeString: kind == .widget ? widgetCodeString : nil,
            textPayload: kind == .text ? textPayload : nil,
            latexPayload: kind == .latex ? latexPayload : nil
        )
        var items = loadItems(in: folderID)
        items.removeAll { $0.recentID == recentID }
        items.insert(item, at: 0)
        if items.count > maximumItemsPerLibrary {
            items = Array(items.prefix(maximumItemsPerLibrary))
        }
        try saveItems(items, in: folderID)
        try touchFolder(folderID)
    }

    public static func removeRecentItem(_ recentID: String, from folderID: UUID) throws {
        var items = loadItems(in: folderID)
        let removed = items.filter { $0.recentID == recentID }
        items.removeAll { $0.recentID == recentID }
        try saveItems(items, in: folderID)
        for item in removed {
            if let thumbnailPNGFileName = item.thumbnailPNGFileName {
                try? FileManager.default.removeItem(
                    at: thumbnailURL(fileName: thumbnailPNGFileName, in: folderID)
                )
            }
        }
        try touchFolder(folderID)
    }

    @discardableResult
    public static func renameItem(_ itemID: UUID, in folderID: UUID, to requestedTitle: String) throws -> LibraryStoredItem? {
        var items = loadItems(in: folderID)
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return nil }
        let trimmedTitle = requestedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        items[index].title = trimmedTitle.isEmpty ? "Library item" : trimmedTitle
        try saveItems(items, in: folderID)
        try touchFolder(folderID)
        return items[index]
    }

    public static func thumbnailURL(fileName: String, in folderID: UUID) -> URL {
        assetsDirectoryURL(for: folderID).appendingPathComponent(fileName)
    }

    private static func ensureBootstrapIfNeeded() {
        if FileManager.default.fileExists(atPath: manifestURL().path) {
            return
        }
        let folders = LibraryMock.folders.prefix(6).enumerated().map { index, folder in
            LibraryStoredFolder(
                name: folder.name,
                symbol: folder.symbol,
                tintIndex: index,
                keywords: folder.keywords,
                isPinned: folder.isPinned
            )
        }
        try? FileManager.default.createDirectory(at: rootDirectoryURL(), withIntermediateDirectories: true)
        try? saveFolders(Array(folders))
    }

    private static func uniqueFolderName(for requestedName: String, excluding excludedID: UUID? = nil) -> String {
        let trimmed = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "New Library" : trimmed
        let existingNames = Set(
            loadFolders()
                .filter { $0.id != excludedID }
                .map { $0.name.lowercased() }
        )
        guard existingNames.contains(base.lowercased()) else { return base }
        var index = 2
        while existingNames.contains("\(base) \(index)".lowercased()) {
            index += 1
        }
        return "\(base) \(index)"
    }

    private static func touchFolder(_ folderID: UUID) throws {
        var folders = loadFolders()
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[index].updatedAt = Date()
        try saveFolders(folders)
    }

    private static func saveFolders(_ folders: [LibraryStoredFolder]) throws {
        try FileManager.default.createDirectory(at: rootDirectoryURL(), withIntermediateDirectories: true)
        let data = try JSONEncoder.libraryStore.encode(Manifest(folders: folders))
        try data.write(to: manifestURL(), options: .atomic)
    }

    private static func saveItems(_ items: [LibraryStoredItem], in folderID: UUID) throws {
        try FileManager.default.createDirectory(
            at: folderDirectoryURL(for: folderID),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.libraryStore.encode(items)
        try data.write(to: itemsURL(for: folderID), options: .atomic)
    }

    private static func manifestURL() -> URL {
        rootDirectoryURL().appendingPathComponent(manifestFileName)
    }

    private static func itemsURL(for folderID: UUID) -> URL {
        folderDirectoryURL(for: folderID).appendingPathComponent(itemsFileName)
    }

    private static func folderDirectoryURL(for folderID: UUID) -> URL {
        rootDirectoryURL().appendingPathComponent(folderID.uuidString, isDirectory: true)
    }

    private static func assetsDirectoryURL(for folderID: UUID) -> URL {
        folderDirectoryURL(for: folderID).appendingPathComponent(assetsDirectoryName, isDirectory: true)
    }

    private static func rootDirectoryURL() -> URL {
        let baseURL = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("MathBoard", isDirectory: true)
            .appendingPathComponent(rootDirectoryName, isDirectory: true)
    }
}

private extension JSONEncoder {
    static var libraryStore: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var libraryStore: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
