//
//  MathtivityCatalogModels.swift
//  Library
//
//  Firestore-backed catalog metadata for downloadable JSON mathtivities.
//

import Foundation
import WidgetEngine

public enum MathtivityCatalogActivityType: String, Codable, CaseIterable, Sendable {
    case multipleChoice
    case fillInTheBlank
    case numericAnswer
    case expressionAnswer
    case matching
    case ordering
    case multiStep

    public var displayName: String {
        switch self {
        case .multipleChoice:
            return "Multiple Choice"
        case .fillInTheBlank:
            return "Fill in the Blank"
        case .numericAnswer:
            return "Numeric Answer"
        case .expressionAnswer:
            return "Expression Answer"
        case .matching:
            return "Matching"
        case .ordering:
            return "Ordering"
        case .multiStep:
            return "Multi-Step"
        }
    }

    public var widgetActivityKind: WidgetObjectActivityKind? {
        switch self {
        case .multipleChoice:
            return .multipleChoice
        case .fillInTheBlank:
            return .fillInTheBlank
        case .numericAnswer, .expressionAnswer, .matching, .ordering, .multiStep:
            return nil
        }
    }
}

public enum MathtivityCatalogMode: String, Codable, CaseIterable, Sendable {
    case scored
    case demo

    public var displayName: String {
        switch self {
        case .scored:
            return "Scored"
        case .demo:
            return "Demo"
        }
    }
}

public struct MathtivityCatalogItem: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var topic: String
    public var course: String?
    public var activityType: MathtivityCatalogActivityType
    public var mode: MathtivityCatalogMode
    public var topicLevel: Int?
    public var difficulty: String?
    public var description: String?
    public var tags: [String]
    public var schemaVersion: Int
    public var requiredAppVersion: String?
    public var jsonStoragePath: String
    public var thumbnailStoragePath: String?
    public var bundledResourceName: String?
    public var isPublished: Bool
    public var version: Int
    public var updatedAt: Date?

    public init(
        id: String,
        title: String,
        topic: String,
        course: String? = nil,
        activityType: MathtivityCatalogActivityType,
        mode: MathtivityCatalogMode = .scored,
        topicLevel: Int? = nil,
        difficulty: String? = nil,
        description: String? = nil,
        tags: [String] = [],
        schemaVersion: Int = 1,
        requiredAppVersion: String? = nil,
        jsonStoragePath: String,
        thumbnailStoragePath: String? = nil,
        bundledResourceName: String? = nil,
        isPublished: Bool = true,
        version: Int = 1,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.topic = topic
        self.course = course
        self.activityType = activityType
        self.mode = mode
        self.topicLevel = topicLevel
        self.difficulty = difficulty
        self.description = description
        self.tags = tags
        self.schemaVersion = schemaVersion
        self.requiredAppVersion = requiredAppVersion
        self.jsonStoragePath = jsonStoragePath
        self.thumbnailStoragePath = thumbnailStoragePath
        self.bundledResourceName = bundledResourceName
        self.isPublished = isPublished
        self.version = version
        self.updatedAt = updatedAt
    }

    public init?(id: String, firestoreData data: [String: Any]) {
        guard
            let title = Self.stringValue(data["title"]),
            let topic = Self.stringValue(data["topic"]),
            let activityTypeRawValue = Self.stringValue(data["activityType"]),
            let activityType = MathtivityCatalogActivityType(rawValue: activityTypeRawValue),
            let jsonStoragePath = Self.stringValue(data["jsonStoragePath"])
        else {
            return nil
        }

        self.init(
            id: id,
            title: title,
            topic: topic,
            course: Self.stringValue(data["course"]),
            activityType: activityType,
            mode: Self.modeValue(data["mode"]) ?? .scored,
            topicLevel: Self.intValue(data["topicLevel"]),
            difficulty: Self.stringValue(data["difficulty"]),
            description: Self.stringValue(data["description"]),
            tags: Self.stringArrayValue(data["tags"]),
            schemaVersion: Self.intValue(data["schemaVersion"]) ?? 1,
            requiredAppVersion: Self.stringValue(data["requiredAppVersion"]),
            jsonStoragePath: jsonStoragePath,
            thumbnailStoragePath: Self.stringValue(data["thumbnailStoragePath"]),
            bundledResourceName: nil,
            isPublished: Self.boolValue(data["isPublished"]) ?? false,
            version: Self.intValue(data["version"]) ?? 1,
            updatedAt: data["updatedAt"] as? Date
        )
    }

    public init?(bundledEntry entry: JSONMathtivityCatalog.Entry) {
        let activityType: MathtivityCatalogActivityType
        switch entry.activityType {
        case .multipleChoice:
            activityType = .multipleChoice
        case .fillInTheBlank:
            activityType = .fillInTheBlank
        case .builtInInteractive, .unknown:
            return nil
        }

        let mode: MathtivityCatalogMode
        switch entry.mode {
        case .scored:
            mode = .scored
        case .demo:
            mode = .demo
        }

        self.init(
            id: "bundled.\(entry.resourceName)",
            title: entry.title,
            topic: entry.topic,
            course: entry.topic,
            activityType: activityType,
            mode: mode,
            topicLevel: entry.topicLevel,
            description: "Bundled starter mathtivity.",
            tags: entry.tags,
            schemaVersion: 1,
            jsonStoragePath: "bundled://\(entry.resourceName)",
            bundledResourceName: entry.resourceName,
            isPublished: true,
            version: 1
        )
    }

    public var catalogLibraryRecentID: String {
        "catalog.\(id)"
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func stringArrayValue(_ value: Any?) -> [String] {
        (value as? [String])?.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static func modeValue(_ value: Any?) -> MathtivityCatalogMode? {
        guard let rawValue = stringValue(value) else { return nil }
        return MathtivityCatalogMode(rawValue: rawValue)
    }
}

public struct DownloadedMathtivityCatalogItem: Sendable, Equatable {
    public var item: MathtivityCatalogItem
    public var jsonSource: String
    public var thumbnailPNGData: Data?

    public init(
        item: MathtivityCatalogItem,
        jsonSource: String,
        thumbnailPNGData: Data? = nil
    ) {
        self.item = item
        self.jsonSource = jsonSource
        self.thumbnailPNGData = thumbnailPNGData
    }
}

@MainActor
public protocol MathtivityCatalogProviding {
    func fetchPublishedCatalog(limit: Int) async throws -> [MathtivityCatalogItem]
    func downloadMathtivity(_ item: MathtivityCatalogItem) async throws -> DownloadedMathtivityCatalogItem
}
