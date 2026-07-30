import CryptoKit
import Foundation

struct MathBoardPackageArchiver {
    static let archiveExtension = "mathboardpkg"

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func archivePackage(at packageURL: URL) throws -> Data {
        try archivePackage(at: packageURL, normalizingDocumentMetadata: true)
    }

    func archivePackage(at packageURL: URL, normalizingDocumentMetadata: Bool) throws -> Data {
        guard packageURL.pathExtension == "mathboard" else {
            throw MathBoardPackageArchiveError.invalidPackage
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: packageURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw MathBoardPackageArchiveError.invalidPackage
        }

        var entries: [MathBoardPackageArchiveEntry] = []
        guard let enumerator = fileManager.enumerator(
            at: packageURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [],
            errorHandler: nil
        ) else {
            throw MathBoardPackageArchiveError.invalidPackage
        }

        for case let url as URL in enumerator {
            guard url.lastPathComponent != ".DS_Store" else { continue }
            let relativePath = try Self.relativePath(for: url, packageURL: packageURL)
            guard !relativePath.isEmpty else { continue }
            let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
            let isDirectory = resourceValues.isDirectory ?? false
            entries.append(MathBoardPackageArchiveEntry(
                relativePath: relativePath,
                isDirectory: isDirectory,
                data: isDirectory ? nil : try archiveData(for: url, relativePath: relativePath, normalizingDocumentMetadata: normalizingDocumentMetadata)
            ))
        }

        entries.sort { $0.relativePath < $1.relativePath }
        let archive = MathBoardPackageArchive(
            formatVersion: MathBoardPackageArchive.currentFormatVersion,
            packageFileName: packageURL.lastPathComponent,
            entries: entries
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(archive)
    }

    func restorePackage(from archiveData: Data, to destinationURL: URL) throws {
        let archive = try PropertyListDecoder().decode(MathBoardPackageArchive.self, from: archiveData)
        guard archive.formatVersion == MathBoardPackageArchive.currentFormatVersion else {
            throw MathBoardPackageArchiveError.unsupportedFormat
        }
        if fileManager.fileExists(atPath: destinationURL.path) {
            throw MathBoardPackageArchiveError.destinationExists
        }
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: false)

        do {
            for entry in archive.entries {
                let entryURL = try Self.destinationURL(for: entry.relativePath, rootURL: destinationURL)
                if entry.isDirectory {
                    try fileManager.createDirectory(at: entryURL, withIntermediateDirectories: true)
                } else {
                    try fileManager.createDirectory(at: entryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try (entry.data ?? Data()).write(to: entryURL, options: .atomic)
                }
            }
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
    }

    static func checksum(for data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func packageFileName(from archiveData: Data) throws -> String {
        try PropertyListDecoder().decode(MathBoardPackageArchive.self, from: archiveData).packageFileName
    }

    private func archiveData(
        for url: URL,
        relativePath: String,
        normalizingDocumentMetadata: Bool
    ) throws -> Data {
        let data = try Data(contentsOf: url)
        guard normalizingDocumentMetadata, relativePath == "document.json" else { return data }
        guard var metadata = try? Self.jsonDecoder.decode(DocumentMetadata.self, from: data) else { return data }
        metadata.publishedVersion = nil
        return try Self.jsonEncoder.encode(metadata)
    }

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

    private static func relativePath(for url: URL, packageURL: URL) throws -> String {
        let packagePath = packageURL.resolvingSymlinksInPath().standardizedFileURL.path
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard path.hasPrefix(packagePath + "/") else {
            throw MathBoardPackageArchiveError.invalidPath
        }
        let relativePath = String(path.dropFirst(packagePath.count + 1))
        try validateRelativePath(relativePath)
        return relativePath
    }

    private static func destinationURL(for relativePath: String, rootURL: URL) throws -> URL {
        try validateRelativePath(relativePath)
        return relativePath.split(separator: "/").reduce(rootURL) { partialURL, component in
            partialURL.appendingPathComponent(String(component))
        }
    }

    private static func validateRelativePath(_ relativePath: String) throws {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !components.contains(".."),
              !components.contains(".") else {
            throw MathBoardPackageArchiveError.invalidPath
        }
    }
}

private struct MathBoardPackageArchive: Codable {
    static let currentFormatVersion = 1

    var formatVersion: Int
    var packageFileName: String
    var entries: [MathBoardPackageArchiveEntry]
}

private struct MathBoardPackageArchiveEntry: Codable {
    var relativePath: String
    var isDirectory: Bool
    var data: Data?
}

enum MathBoardPackageArchiveError: LocalizedError {
    case invalidPackage
    case invalidPath
    case unsupportedFormat
    case destinationExists

    var errorDescription: String? {
        switch self {
        case .invalidPackage:
            "MathBoard could not package that lesson."
        case .invalidPath:
            "MathBoard found an invalid file path inside that lesson package."
        case .unsupportedFormat:
            "That MathBoard lesson package uses an unsupported format."
        case .destinationExists:
            "A lesson package already exists at the download destination."
        }
    }
}
