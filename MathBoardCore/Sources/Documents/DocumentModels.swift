//
//  DocumentModels.swift
//  MathBoardCore — Documents module
//
//  On-disk representation of folders and lessons. A folder is a plain
//  directory; a lesson is a `.mathboard` file package — a directory with
//  a unique extension that the OS treats as a single document.
//

import Foundation

/// A folder on disk that contains lessons. Identity is its URL; rename = new identity.
struct Folder: Identifiable, Hashable {
    var name: String
    var url: URL
    var lessonCount: Int
    var color: FolderColor

    var id: URL { url }

    init(name: String, url: URL, lessonCount: Int, color: FolderColor = .plain) {
        self.name = name
        self.url = url
        self.lessonCount = lessonCount
        self.color = color
    }
}

/// A `.mathboard` document on disk. Identity is the stable UUID persisted
/// inside the package's `document.json` — identity survives rename and move.
struct Lesson: Identifiable, Hashable {
    let id: UUID
    var name: String
    var url: URL
    var createdAt: Date
    var modifiedAt: Date
    var publishedVersion: LessonPublishedVersionMetadata?

    init(
        id: UUID,
        name: String,
        url: URL,
        createdAt: Date,
        modifiedAt: Date,
        publishedVersion: LessonPublishedVersionMetadata? = nil
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.publishedVersion = publishedVersion
    }
}

struct LessonPublishedVersionMetadata: Codable, Hashable {
    var versionID: UUID
    var versionNumber: Int
    var title: String
    var packageFileName: String?
    var packageStoragePath: String
    var packageChecksum: String
    var publishedAt: Date
    var sourceContentChecksum: String

    init(
        versionID: UUID,
        versionNumber: Int,
        title: String,
        packageFileName: String?,
        packageStoragePath: String,
        packageChecksum: String,
        publishedAt: Date,
        sourceContentChecksum: String
    ) {
        self.versionID = versionID
        self.versionNumber = versionNumber
        self.title = title
        self.packageFileName = packageFileName
        self.packageStoragePath = packageStoragePath
        self.packageChecksum = packageChecksum
        self.publishedAt = publishedAt
        self.sourceContentChecksum = sourceContentChecksum
    }

    init?(manifest: LessonPackageManifest, sourceContentChecksum: String) {
        guard let versionID = manifest.versionID,
              let versionNumber = manifest.versionNumber,
              let packageStoragePath = manifest.packageStoragePath,
              let packageChecksum = manifest.packageChecksum,
              let publishedAt = manifest.publishedAt else {
            return nil
        }
        self.init(
            versionID: versionID,
            versionNumber: versionNumber,
            title: manifest.title,
            packageFileName: manifest.packageFileName,
            packageStoragePath: packageStoragePath,
            packageChecksum: packageChecksum,
            publishedAt: publishedAt,
            sourceContentChecksum: sourceContentChecksum
        )
    }

    func manifest(sourceLessonID: UUID) -> LessonPackageManifest {
        LessonPackageManifest(
            id: sourceLessonID,
            title: title,
            versionID: versionID,
            versionNumber: versionNumber,
            packageFileName: packageFileName,
            packageStoragePath: packageStoragePath,
            packageChecksum: packageChecksum,
            publishedAt: publishedAt
        )
    }
}

/// Persisted metadata inside `<package>.mathboard/document.json`.
/// `version` exists so future schemas can migrate older documents forward.
struct DocumentMetadata: Codable {
    let id: UUID
    let createdAt: Date
    let version: Int
    var publishedVersion: LessonPublishedVersionMetadata?

    static let currentVersion = 1

    init(
        id: UUID,
        createdAt: Date,
        version: Int,
        publishedVersion: LessonPublishedVersionMetadata? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.version = version
        self.publishedVersion = publishedVersion
    }
}

enum FolderColor: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case plain
    case gold
    case blue
    case green
    case coral
    case purple
    case red
    case gray

    var id: String { rawValue }

    static var allCases: [FolderColor] {
        [.plain, .gold, .blue, .green, .coral, .purple, .red]
    }

    var title: String {
        switch self {
        case .plain:
            "Plain"
        case .gold:
            "Gold"
        case .blue:
            "Blue"
        case .green:
            "Green"
        case .coral:
            "Coral"
        case .purple:
            "Purple"
        case .red:
            "Red"
        case .gray:
            "Gray"
        }
    }
}

struct FolderMetadata: Codable, Hashable {
    var color: FolderColor

    static let fileName = ".mathboard-folder.json"
    static let `default` = FolderMetadata(color: .plain)
}
