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

    var id: URL { url }
}

/// A `.mathboard` document on disk. Identity is the stable UUID persisted
/// inside the package's `document.json` — identity survives rename and move.
struct Lesson: Identifiable, Hashable {
    let id: UUID
    var name: String
    var url: URL
    var createdAt: Date
    var modifiedAt: Date
}

/// Persisted metadata inside `<package>.mathboard/document.json`.
/// `version` exists so future schemas can migrate older documents forward.
struct DocumentMetadata: Codable {
    let id: UUID
    let createdAt: Date
    let version: Int

    static let currentVersion = 1
}
