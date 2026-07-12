//
//  CanvasObjectLayerState.swift
//  MathBoardCore - Canvas module
//

import Foundation

public struct CanvasObjectGroup: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var textObjectIDs: Set<UUID>
    public var imageObjectIDs: Set<UUID>
    public var geometryObjectIDs: Set<UUID>
    public var isExplicit: Bool

    public init(
        id: UUID = UUID(),
        textObjectIDs: Set<UUID> = [],
        imageObjectIDs: Set<UUID> = [],
        geometryObjectIDs: Set<UUID> = [],
        isExplicit: Bool = false
    ) {
        self.id = id
        self.textObjectIDs = textObjectIDs
        self.imageObjectIDs = imageObjectIDs
        self.geometryObjectIDs = geometryObjectIDs
        self.isExplicit = isExplicit
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case textObjectIDs
        case imageObjectIDs
        case geometryObjectIDs
        case isExplicit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        textObjectIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .textObjectIDs) ?? []
        imageObjectIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .imageObjectIDs) ?? []
        geometryObjectIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .geometryObjectIDs) ?? []
        isExplicit = try container.decodeIfPresent(Bool.self, forKey: .isExplicit) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(textObjectIDs, forKey: .textObjectIDs)
        try container.encode(imageObjectIDs, forKey: .imageObjectIDs)
        try container.encode(geometryObjectIDs, forKey: .geometryObjectIDs)
        try container.encode(isExplicit, forKey: .isExplicit)
    }

    public var objectCount: Int {
        textObjectIDs.count + imageObjectIDs.count + geometryObjectIDs.count
    }

    public func contains(_ object: CanvasSelectionState.Object) -> Bool {
        switch object {
        case .text(let id):
            return textObjectIDs.contains(id)
        case .image(let id):
            return imageObjectIDs.contains(id)
        case .geometry(let id):
            return geometryObjectIDs.contains(id)
        }
    }
}

public struct CanvasObjectLayerState: Codable, Equatable, Sendable {
    public enum ImageLayerPosition: String, Codable, Sendable {
        case belowGeometry
        case betweenGeometryAndText
        case aboveText

        var lowered: ImageLayerPosition {
            switch self {
            case .aboveText: return .betweenGeometryAndText
            case .betweenGeometryAndText, .belowGeometry: return .belowGeometry
            }
        }

        var raised: ImageLayerPosition {
            switch self {
            case .belowGeometry: return .betweenGeometryAndText
            case .betweenGeometryAndText, .aboveText: return .aboveText
            }
        }
    }

    public var imageLayerPosition: ImageLayerPosition
    public var objectGroups: [CanvasObjectGroup]

    public init(
        imageLayerPosition: ImageLayerPosition = .belowGeometry,
        objectGroups: [CanvasObjectGroup] = []
    ) {
        self.imageLayerPosition = imageLayerPosition
        self.objectGroups = objectGroups
    }

    private enum CodingKeys: String, CodingKey {
        case imageLayerPosition
        case objectGroups
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        imageLayerPosition = try container.decodeIfPresent(ImageLayerPosition.self, forKey: .imageLayerPosition) ?? .belowGeometry
        objectGroups = try container.decodeIfPresent([CanvasObjectGroup].self, forKey: .objectGroups) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(imageLayerPosition, forKey: .imageLayerPosition)
        try container.encode(objectGroups, forKey: .objectGroups)
    }

    public static func sidecarURL(forDrawingURL drawingURL: URL) -> URL {
        drawingURL
            .deletingPathExtension()
            .appendingPathExtension("objectlayers.json")
    }

    public static func load(from url: URL) -> CanvasObjectLayerState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(CanvasObjectLayerState.self, from: data) else {
            return CanvasObjectLayerState()
        }
        return state
    }

    public static func save(_ state: CanvasObjectLayerState, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(state)
        try data.write(to: url, options: .atomic)
    }
}
