//
//  StudentPersonalLibraryStore.swift
//  MathBoardCore — Documents module
//
//  Persistent store for clips a student saves from the canvas via the Extract tool.
//  Clips live in the app's Documents directory so they survive lesson deletion and
//  device restores from backup, independent of any lesson package.
//

import Foundation

public struct StudentClip: Codable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    /// PNG filename inside the assets subdirectory.
    public let fileName: String
}

public final class StudentPersonalLibraryStore: @unchecked Sendable {
    public static let shared = StudentPersonalLibraryStore()
    private init() {}

    private var rootURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StudentPersonalLibrary", isDirectory: true)
    }

    private var assetsURL: URL { rootURL.appendingPathComponent("assets", isDirectory: true) }
    private var clipsURL: URL { rootURL.appendingPathComponent("clips.json") }

    public func loadClips() -> [StudentClip] {
        guard let data = try? Data(contentsOf: clipsURL),
              let clips = try? JSONDecoder().decode([StudentClip].self, from: data) else { return [] }
        return clips
    }

    @discardableResult
    public func saveClip(pngData: Data) -> StudentClip? {
        do {
            try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
            let clip = StudentClip(id: UUID(), date: Date(), fileName: "\(UUID().uuidString).png")
            try pngData.write(to: assetsURL.appendingPathComponent(clip.fileName), options: .atomic)
            var clips = loadClips()
            clips.insert(clip, at: 0)
            try JSONEncoder().encode(clips).write(to: clipsURL, options: .atomic)
            return clip
        } catch {
            print("[StudentPersonalLibrary] save error: \(error)")
            return nil
        }
    }

    public func imageData(for clip: StudentClip) -> Data? {
        try? Data(contentsOf: assetsURL.appendingPathComponent(clip.fileName))
    }

    public func deleteClip(_ clip: StudentClip) {
        try? FileManager.default.removeItem(at: assetsURL.appendingPathComponent(clip.fileName))
        var clips = loadClips()
        clips.removeAll { $0.id == clip.id }
        if let data = try? JSONEncoder().encode(clips) {
            try? data.write(to: clipsURL, options: .atomic)
        }
    }
}
