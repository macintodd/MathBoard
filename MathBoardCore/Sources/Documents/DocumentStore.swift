//
//  DocumentStore.swift
//  MathBoardCore — Documents module
//
//  Reads and writes folders and `.mathboard` documents in the app's
//  sandboxed Documents directory. `@MainActor @Observable` — SwiftUI
//  views observe changes automatically; methods run on the main thread.
//
//  Concurrency / performance note: file I/O is currently synchronous on
//  the main actor. For v1 file counts (dozens to low hundreds), this is
//  comfortably within frame budget. If profiling later shows main-thread
//  hitches, methods can be wrapped in `Task.detached` without changing
//  any call sites.
//

import Foundation
import Observation

@MainActor
@Observable
public final class DocumentStore {

    /// Folders at the root of the store, sorted alphabetically.
    var folders: [Folder] = []

    /// Lessons across all folders, sorted by `modifiedAt` descending.
    /// Currently capped at 6 entries for the start-screen "Recent" strip.
    var recentLessons: [Lesson] = []

    private let rootURL: URL?
    private let fileManager: FileManager
    private static let libraryRecentDirectoryName = "library"

    public init(loadImmediately: Bool = true) {
        self.fileManager = .default
        self.rootURL = Self.locateRootURL(using: fileManager)
        if let root = rootURL {
            resetForUITestsIfRequested(at: root)
            bootstrapIfNeeded(at: root)
            seedDocumentWorkflowUITestFixtureIfRequested(at: root)
        }
        if loadImmediately {
            reload()
        }
    }

    init(rootURL: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.rootURL = rootURL
        reload()
    }

    private static func locateRootURL(using fileManager: FileManager) -> URL? {
        do {
            return try fileManager.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            print("[DocumentStore] Failed to locate Documents directory: \(error)")
            return nil
        }
    }

    private func resetForUITestsIfRequested(at root: URL) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-MathBoardUITestResetDocuments") else { return }
        let contents = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for url in contents {
            try? fileManager.removeItem(at: url)
        }
        #endif
    }

    private func seedDocumentWorkflowUITestFixtureIfRequested(at root: URL) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-MathBoardUITestDocumentWorkflowFixture") else { return }
        let algebraURL = root.appendingPathComponent("UI Algebra", isDirectory: true)
        if fileManager.fileExists(atPath: algebraURL.path) {
            try? fileManager.removeItem(at: algebraURL)
        }

        do {
            let algebra = try createFolder(named: "UI Algebra", at: root)
            let unit1 = try createFolder(named: "Unit 1", at: algebra.url)
            _ = try createFolder(named: "Unit 2", at: algebra.url)
            _ = try createLesson(named: "Warmup", in: unit1)
        } catch {
            print("[DocumentStore] UI test fixture error: \(error)")
        }
        #endif
    }

    // MARK: - Read

    public func reload() {
        guard let rootURL else { return }
        folders = (try? loadFolders(at: rootURL)) ?? []
        recentLessons = computeRecentLessons(limit: 6)
    }

    func lessons(in folder: Folder) -> [Lesson] {
        let urls = (try? fileManager.contentsOfDirectory(
            at: folder.url,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        return urls
            .compactMap { url -> Lesson? in
                guard isMathBoardPackage(url) else { return nil }
                return try? loadLesson(at: url)
            }
            .sorted(by: { $0.modifiedAt > $1.modifiedAt })
    }

    func folders(in folder: Folder) -> [Folder] {
        (try? loadFolders(at: folder.url)) ?? []
    }

    func allFolders() -> [Folder] {
        folders.flatMap { folder in
            [folder] + descendantFolders(in: folder)
        }
    }

    func allLessons() -> [Lesson] {
        allFolders()
            .flatMap { lessons(in: $0) }
            .sorted(by: { $0.modifiedAt > $1.modifiedAt })
    }

    private func descendantFolders(in folder: Folder) -> [Folder] {
        folders(in: folder).flatMap { child in
            [child] + descendantFolders(in: child)
        }
    }

    private func loadFolders(at root: URL) throws -> [Folder] {
        let urls = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        var result: [Folder] = []
        for url in urls {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir, !isMathBoardPackage(url) else { continue }
            let count = countLessons(in: url)
            let metadata = loadFolderMetadata(at: url)
            result.append(Folder(
                name: url.lastPathComponent,
                url: url,
                lessonCount: count,
                color: metadata.color
            ))
        }
        return result.sorted(by: { $0.name < $1.name })
    }

    func loadManagedLesson(at url: URL) throws -> Lesson {
        try loadLesson(at: url)
    }

    private func loadLesson(at url: URL) throws -> Lesson {
        let metadata = try loadDocumentMetadata(at: url)
        let attrs = try fileManager.attributesOfItem(atPath: url.path)
        let modifiedAt = (attrs[.modificationDate] as? Date) ?? Date()
        return Lesson(
            id: metadata.id,
            name: url.deletingPathExtension().lastPathComponent,
            url: url,
            createdAt: metadata.createdAt,
            modifiedAt: modifiedAt,
            publishedVersion: metadata.publishedVersion
        )
    }

    private func countLessons(in folderURL: URL) -> Int {
        let urls = (try? fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil
        )) ?? []
        return urls.filter(isMathBoardPackage).count
    }

    private func computeRecentLessons(limit: Int) -> [Lesson] {
        var all: [Lesson] = []
        for folder in allFolders() {
            all.append(contentsOf: lessons(in: folder))
        }
        return Array(all.sorted(by: { $0.modifiedAt > $1.modifiedAt }).prefix(limit))
    }

    private func isMathBoardPackage(_ url: URL) -> Bool {
        url.pathExtension == "mathboard"
    }

    // MARK: - Write

    @discardableResult
    func createFolder(named name: String, at root: URL? = nil) throws -> Folder {
        guard let rootURL = root ?? self.rootURL else { throw DocumentStoreError.noRoot }
        let finalName = try validatedDisplayName(name, kind: .folder)
        try ensureNameIsAvailable(finalName, in: rootURL, pathExtension: nil, kind: .folder)

        let url = rootURL.appendingPathComponent(finalName, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
        try saveFolderMetadata(.default, at: url)
        reload()
        return Folder(name: finalName, url: url, lessonCount: 0)
    }

    @discardableResult
    func renameFolder(_ folder: Folder, to name: String) throws -> Folder {
        let finalName = try validatedDisplayName(name, kind: .folder)
        if finalName == folder.name {
            return folder
        }

        let parentURL = folder.url.deletingLastPathComponent()
        try ensureNameIsAvailable(finalName, in: parentURL, pathExtension: nil, kind: .folder)
        let destinationURL = parentURL.appendingPathComponent(finalName, isDirectory: true)
        try fileManager.moveItem(at: folder.url, to: destinationURL)
        reload()
        return Folder(
            name: finalName,
            url: destinationURL,
            lessonCount: countLessons(in: destinationURL),
            color: folder.color
        )
    }

    @discardableResult
    func updateFolderColor(_ folder: Folder, to color: FolderColor) throws -> Folder {
        var metadata = loadFolderMetadata(at: folder.url)
        metadata.color = color
        try saveFolderMetadata(metadata, at: folder.url)
        reload()
        return Folder(
            name: folder.name,
            url: folder.url,
            lessonCount: countLessons(in: folder.url),
            color: color
        )
    }

    func sourceContentChecksum(for lesson: Lesson) throws -> String {
        let archiveData = try MathBoardPackageArchiver(fileManager: fileManager).archivePackage(
            at: lesson.url,
            normalizingDocumentMetadata: true
        )
        return MathBoardPackageArchiver.checksum(for: archiveData)
    }

    func hasUnpublishedChanges(_ lesson: Lesson) -> Bool {
        guard let publishedVersion = lesson.publishedVersion,
              let checksum = try? sourceContentChecksum(for: lesson) else {
            return true
        }
        return publishedVersion.sourceContentChecksum != checksum
    }

    @discardableResult
    func recordPublishedVersion(_ manifest: LessonPackageManifest, sourceContentChecksum: String, for lesson: Lesson) throws -> Lesson {
        guard var metadata = try? loadDocumentMetadata(at: lesson.url) else {
            throw DocumentStoreError.invalidLessonPackage
        }
        guard let publishedVersion = LessonPublishedVersionMetadata(
            manifest: manifest,
            sourceContentChecksum: sourceContentChecksum
        ) else {
            throw DocumentStoreError.invalidLessonPackage
        }
        metadata.publishedVersion = publishedVersion
        try saveDocumentMetadata(metadata, at: lesson.url)
        reload()
        return try loadLesson(at: lesson.url)
    }

    func deleteFolder(_ folder: Folder) throws {
        try fileManager.removeItem(at: folder.url)
        reload()
    }

    @discardableResult
    func createLesson(named name: String, in folder: Folder) throws -> Lesson {
        let finalName = try validatedDisplayName(name, kind: .lesson)
        try ensureNameIsAvailable(finalName, in: folder.url, pathExtension: "mathboard", kind: .lesson)

        let packageURL = folder.url.appendingPathComponent("\(finalName).mathboard", isDirectory: true)
        try fileManager.createDirectory(at: packageURL, withIntermediateDirectories: false)
        return try finishCreatingLessonPackage(at: packageURL, named: finalName)
    }

    @discardableResult
    func duplicateLesson(_ lesson: Lesson, in folder: Folder) throws -> Lesson {
        try duplicateLessons(lesson, in: folder, count: 1)[0]
    }

    @discardableResult
    func duplicateLessons(_ lesson: Lesson, in folder: Folder, count: Int) throws -> [Lesson] {
        guard (1...10).contains(count) else {
            throw DocumentStoreError.invalidDuplicateCount
        }

        var duplicatedLessons: [Lesson] = []
        for _ in 0..<count {
            let finalName = try uniqueCopyName(for: lesson.name, in: folder.url)
            let packageURL = folder.url.appendingPathComponent("\(finalName).mathboard", isDirectory: true)
            try copyLessonPackage(from: lesson.url, to: packageURL)

            let metadata = DocumentMetadata(
                id: UUID(),
                createdAt: Date(),
                version: DocumentMetadata.currentVersion
            )
            try saveDocumentMetadata(metadata, at: packageURL)
            duplicatedLessons.append(try loadLesson(at: packageURL))
        }

        reload()
        return duplicatedLessons
    }

    @discardableResult
    func renameLesson(_ lesson: Lesson, to name: String, in folder: Folder) throws -> Lesson {
        let finalName = try validatedDisplayName(name, kind: .lesson)
        if finalName == lesson.name {
            return lesson
        }

        try ensureNameIsAvailable(finalName, in: folder.url, pathExtension: "mathboard", kind: .lesson)
        let destinationURL = folder.url.appendingPathComponent("\(finalName).mathboard", isDirectory: true)
        try fileManager.moveItem(at: lesson.url, to: destinationURL)
        reload()
        return try loadLesson(at: destinationURL)
    }

    func deleteLesson(_ lesson: Lesson) throws {
        try fileManager.removeItem(at: lesson.url)
        reload()
    }

    func deleteLessons(_ lessons: [Lesson]) throws {
        for lesson in lessons {
            try fileManager.removeItem(at: lesson.url)
        }
        reload()
    }

    @discardableResult
    func moveLessons(_ lessons: [Lesson], to destinationFolder: Folder) throws -> [Lesson] {
        var movedLessons: [Lesson] = []
        for lesson in lessons {
            let finalName = try uniqueMovedName(for: lesson.name, in: destinationFolder.url)
            let destinationURL = destinationFolder.url.appendingPathComponent("\(finalName).mathboard", isDirectory: true)
            try fileManager.moveItem(at: lesson.url, to: destinationURL)
            movedLessons.append(try loadLesson(at: destinationURL))
        }
        reload()
        return movedLessons
    }

    @discardableResult
    func importLessonPackage(from sourceURL: URL) throws -> Lesson {
        guard let rootURL else { throw DocumentStoreError.noRoot }
        guard isMathBoardPackage(sourceURL) else {
            throw DocumentStoreError.invalidLessonPackage
        }
        _ = try loadLesson(at: sourceURL)
        if isInsideRoot(sourceURL) {
            reload()
            return try loadLesson(at: sourceURL)
        }

        let importsFolderName = "Imported Lessons"
        let importsFolderURL = rootURL.appendingPathComponent(importsFolderName, isDirectory: true)
        if !fileManager.fileExists(atPath: importsFolderURL.path) {
            try fileManager.createDirectory(at: importsFolderURL, withIntermediateDirectories: false)
        }

        let sourceName = sourceURL.deletingPathExtension().lastPathComponent
        let baseName = (try? validatedDisplayName(sourceName, kind: .lesson)) ?? "Imported Lesson"
        let finalName = try uniqueImportedName(for: baseName, in: importsFolderURL)
        let destinationURL = importsFolderURL.appendingPathComponent("\(finalName).mathboard", isDirectory: true)
        try copyLessonPackage(from: sourceURL, to: destinationURL)

        let metadata = DocumentMetadata(
            id: UUID(),
            createdAt: Date(),
            version: DocumentMetadata.currentVersion
        )
        try saveDocumentMetadata(metadata, at: destinationURL)

        reload()
        return try loadLesson(at: destinationURL)
    }

    @discardableResult
    func importSharedLessonPackageArchive(_ archiveData: Data, suggestedFileName: String?) throws -> Lesson {
        guard let rootURL else { throw DocumentStoreError.noRoot }
        let assignedFolderURL = rootURL.appendingPathComponent("Assigned Lessons", isDirectory: true)
        if !fileManager.fileExists(atPath: assignedFolderURL.path) {
            try fileManager.createDirectory(at: assignedFolderURL, withIntermediateDirectories: false)
        }

        let archiveFileName = (try? MathBoardPackageArchiver.packageFileName(from: archiveData)) ?? suggestedFileName ?? "Assigned Lesson.mathboard"
        let archiveBaseName = URL(fileURLWithPath: archiveFileName).deletingPathExtension().lastPathComponent
        let baseName = (try? validatedDisplayName(archiveBaseName, kind: .lesson)) ?? "Assigned Lesson"
        let finalName = try uniqueImportedName(for: baseName, in: assignedFolderURL)
        let destinationURL = assignedFolderURL.appendingPathComponent("\(finalName).mathboard", isDirectory: true)

        try MathBoardPackageArchiver(fileManager: fileManager).restorePackage(from: archiveData, to: destinationURL)
        _ = try loadLesson(at: destinationURL)
        reload()
        return try loadLesson(at: destinationURL)
    }

    func studentAssignedLessonWorkingCopy(
        for sourceLesson: Lesson,
        assignmentID: UUID,
        studentIdentifier: String
    ) throws -> Lesson {
        guard let rootURL else { throw DocumentStoreError.noRoot }
        let studentWorkFolderURL = rootURL
            .appendingPathComponent("Assigned Lessons", isDirectory: true)
            .appendingPathComponent("Student Work", isDirectory: true)
        if !fileManager.fileExists(atPath: studentWorkFolderURL.path) {
            try fileManager.createDirectory(at: studentWorkFolderURL, withIntermediateDirectories: true)
        }

        let safeStudentIdentifier = Self.safeFileComponent(studentIdentifier)
        let workingCopyName = "\(assignmentID.uuidString)-\(safeStudentIdentifier)-\(sourceLesson.id.uuidString)"
        let destinationURL = studentWorkFolderURL.appendingPathComponent("\(workingCopyName).mathboard", isDirectory: true)
        if !fileManager.fileExists(atPath: destinationURL.path) {
            try copyLessonPackage(from: sourceLesson.url, to: destinationURL)
        }
        reload()
        return try loadLesson(at: destinationURL)
    }

    @discardableResult
    func importLessonPackage(from sourceURL: URL, into folder: Folder) throws -> Lesson {
        guard isMathBoardPackage(sourceURL) else {
            throw DocumentStoreError.invalidLessonPackage
        }
        _ = try loadLesson(at: sourceURL)

        let targetFolderURL = folder.url.standardizedFileURL
        let sourceParentURL = sourceURL.deletingLastPathComponent().standardizedFileURL
        if isInsideRoot(sourceURL), sourceParentURL == targetFolderURL {
            reload()
            return try loadLesson(at: sourceURL)
        }

        let sourceName = sourceURL.deletingPathExtension().lastPathComponent
        let baseName = (try? validatedDisplayName(sourceName, kind: .lesson)) ?? "Imported Lesson"
        let finalName = try uniqueImportedName(for: baseName, in: folder.url)
        let destinationURL = folder.url.appendingPathComponent("\(finalName).mathboard", isDirectory: true)
        try copyLessonPackage(from: sourceURL, to: destinationURL)

        let metadata = DocumentMetadata(
            id: UUID(),
            createdAt: Date(),
            version: DocumentMetadata.currentVersion
        )
        try saveDocumentMetadata(metadata, at: destinationURL)

        reload()
        return try loadLesson(at: destinationURL)
    }

    private func finishCreatingLessonPackage(at packageURL: URL, named name: String) throws -> Lesson {
        let metadata = DocumentMetadata(
            id: UUID(),
            createdAt: Date(),
            version: DocumentMetadata.currentVersion
        )
        try saveDocumentMetadata(metadata, at: packageURL)
        reload()
        return Lesson(
            id: metadata.id,
            name: name,
            url: packageURL,
            createdAt: metadata.createdAt,
            modifiedAt: Date()
        )
    }

    private enum DocumentKind {
        case folder
        case lesson

        var displayName: String {
            switch self {
            case .folder: "Folder"
            case .lesson: "Lesson"
            }
        }
    }

    private func validatedDisplayName(_ name: String, kind: DocumentKind) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DocumentStoreError.emptyName(kind.displayName) }
        guard trimmed != ".", trimmed != "..", !trimmed.hasPrefix(".") else {
            throw DocumentStoreError.invalidName(kind.displayName)
        }
        guard trimmed.rangeOfCharacter(from: Self.invalidNameCharacters) == nil else {
            throw DocumentStoreError.invalidName(kind.displayName)
        }
        if kind == .lesson, trimmed.lowercased().hasSuffix(".mathboard") {
            throw DocumentStoreError.lessonNameIncludesExtension
        }
        return trimmed
    }

    private func ensureNameIsAvailable(
        _ name: String,
        in parentURL: URL,
        pathExtension: String?,
        kind: DocumentKind
    ) throws {
        let candidate = filename(for: name, pathExtension: pathExtension).lowercased()
        let existing = try fileManager.contentsOfDirectory(atPath: parentURL.path)
            .map { $0.lowercased() }
        guard !existing.contains(candidate) else {
            throw DocumentStoreError.nameAlreadyExists(kind.displayName, name)
        }
    }

    private func uniqueCopyName(for originalName: String, in folderURL: URL) throws -> String {
        let baseName = try validatedDisplayName("\(originalName) Copy", kind: .lesson)
        var candidate = baseName
        var suffix = 2
        while try nameExists(candidate, in: folderURL, pathExtension: "mathboard") {
            candidate = "\(baseName) \(suffix)"
            suffix += 1
        }
        return candidate
    }

    private func uniqueImportedName(for baseName: String, in folderURL: URL) throws -> String {
        try uniqueAvailableLessonName(for: baseName, in: folderURL)
    }

    private func uniqueMovedName(for originalName: String, in folderURL: URL) throws -> String {
        let baseName = try validatedDisplayName(originalName, kind: .lesson)
        return try uniqueAvailableLessonName(for: baseName, in: folderURL)
    }

    private func uniqueAvailableLessonName(for baseName: String, in folderURL: URL) throws -> String {
        var candidate = baseName
        var suffix = 2
        while try nameExists(candidate, in: folderURL, pathExtension: "mathboard") {
            candidate = "\(baseName) \(suffix)"
            suffix += 1
        }
        return candidate
    }

    private func nameExists(_ name: String, in parentURL: URL, pathExtension: String?) throws -> Bool {
        let candidate = filename(for: name, pathExtension: pathExtension).lowercased()
        return try fileManager.contentsOfDirectory(atPath: parentURL.path)
            .map { $0.lowercased() }
            .contains(candidate)
    }

    private func isInsideRoot(_ url: URL) -> Bool {
        guard let rootURL else { return false }
        return url.standardizedFileURL.path.hasPrefix(rootURL.standardizedFileURL.path + "/")
    }

    private func filename(for name: String, pathExtension: String?) -> String {
        guard let pathExtension else { return name }
        return "\(name).\(pathExtension)"
    }

    private func loadFolderMetadata(at folderURL: URL) -> FolderMetadata {
        let metadataURL = folderURL.appendingPathComponent(FolderMetadata.fileName)
        guard let data = try? Data(contentsOf: metadataURL),
              let metadata = try? Self.jsonDecoder.decode(FolderMetadata.self, from: data) else {
            return .default
        }
        return metadata
    }

    private func saveFolderMetadata(_ metadata: FolderMetadata, at folderURL: URL) throws {
        let data = try Self.jsonEncoder.encode(metadata)
        try data.write(to: folderURL.appendingPathComponent(FolderMetadata.fileName), options: .atomic)
    }

    private func loadDocumentMetadata(at packageURL: URL) throws -> DocumentMetadata {
        let metadataURL = packageURL.appendingPathComponent("document.json")
        let data = try Data(contentsOf: metadataURL)
        return try Self.jsonDecoder.decode(DocumentMetadata.self, from: data)
    }

    private func saveDocumentMetadata(_ metadata: DocumentMetadata, at packageURL: URL) throws {
        let data = try Self.jsonEncoder.encode(metadata)
        try data.write(to: packageURL.appendingPathComponent("document.json"), options: .atomic)
    }

    private func copyLessonPackage(from sourceURL: URL, to destinationURL: URL) throws {
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        try copyLibraryRecentSidecar(from: sourceURL, to: destinationURL)
    }

    private func copyLibraryRecentSidecar(from sourceURL: URL, to destinationURL: URL) throws {
        let sourceSidecarURL = sourceURL.appendingPathComponent(Self.libraryRecentDirectoryName, isDirectory: true)
        guard fileManager.fileExists(atPath: sourceSidecarURL.path) else { return }

        let destinationSidecarURL = destinationURL.appendingPathComponent(Self.libraryRecentDirectoryName, isDirectory: true)
        if fileManager.fileExists(atPath: destinationSidecarURL.path) {
            try fileManager.removeItem(at: destinationSidecarURL)
        }
        try fileManager.copyItem(at: sourceSidecarURL, to: destinationSidecarURL)
    }

    private static let invalidNameCharacters: CharacterSet = {
        var characters = CharacterSet(charactersIn: "/:")
        characters.formUnion(.newlines)
        characters.formUnion(.controlCharacters)
        return characters
    }()

    private static func safeFileComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let component = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return component.isEmpty ? "student" : component
    }

    // MARK: - First-launch bootstrap

    /// Populates the store with starter folders and lessons the first time
    /// the app is launched. On subsequent launches (or if the user has
    /// already created any content), this is a no-op.
    private func bootstrapIfNeeded(at root: URL) {
        let existing = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        guard existing.isEmpty else { return }

        let starter: [(folder: String, lessons: [String])] = [
            ("Algebra 2", ["Linear Equations Review", "Quadratic Functions Day 1"]),
            ("Pre-Calculus", ["Trigonometry Basics", "Polar Coordinates"]),
            ("Geometry", ["Triangle Congruence Review", "Pythagorean Theorem"]),
            ("AP Pre-Calculus", ["Function Transformations", "Limits Introduction"]),
            ("Tutoring Sessions", ["Session – Welcome"])
        ]

        for entry in starter {
            do {
                let folder = try createFolder(named: entry.folder, at: root)
                for lesson in entry.lessons {
                    _ = try createLesson(named: lesson, in: folder)
                }
            } catch {
                print("[DocumentStore] bootstrap error for \(entry.folder): \(error)")
            }
        }
    }

    // MARK: - JSON

    private static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

enum DocumentStoreError: LocalizedError {
    case noRoot
    case emptyName(String)
    case invalidName(String)
    case nameAlreadyExists(String, String)
    case lessonNameIncludesExtension
    case invalidLessonPackage
    case invalidDuplicateCount

    var errorDescription: String? {
        switch self {
        case .noRoot:
            "MathBoard could not access the Documents folder."
        case .emptyName(let kind):
            "\(kind) name cannot be empty."
        case .invalidName(let kind):
            "\(kind) name cannot start with a period or contain /, :, line breaks, or control characters."
        case .nameAlreadyExists(let kind, let name):
            "A \(kind.lowercased()) named “\(name)” already exists."
        case .lessonNameIncludesExtension:
            "Lesson names should not include .mathboard. MathBoard adds that automatically."
        case .invalidLessonPackage:
            "Choose a valid .mathboard lesson package."
        case .invalidDuplicateCount:
            "Choose between 1 and 10 duplicates."
        }
    }
}
