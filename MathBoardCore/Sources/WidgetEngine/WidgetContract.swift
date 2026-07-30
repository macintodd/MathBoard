//
//  WidgetContract.swift
//  WidgetEngine
//
//  Public prototype contract for widget-like whiteboard objects. The native
//  Widget JSON schema lives beside this file; this contract remains deliberately
//  small so future canvas integration can bridge either native JSON widgets or
//  advanced HTML widgets without WidgetEngine depending on MathBoard.app.
//

import Foundation
import CoreGraphics

public protocol MathBoardObject: Identifiable {
    var id: UUID { get }
    var frame: CGRect { get set }
}

public struct WidgetObject: MathBoardObject, Codable, Equatable {
    public let id: UUID
    public var frame: CGRect
    public var name: String
    public var codeString: String
    public var activityRuntimeState: WidgetActivityRuntimeState?
    public var isPinnedToCanvas: Bool
    public var librarySourceCodeString: String?
    public var hasRecordedLibraryDerivative: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        codeString: String,
        frame: CGRect,
        activityRuntimeState: WidgetActivityRuntimeState? = nil,
        isPinnedToCanvas: Bool = false,
        librarySourceCodeString: String? = nil,
        hasRecordedLibraryDerivative: Bool = false
    ) {
        self.id = id
        self.name = name
        self.codeString = codeString
        self.frame = frame
        self.activityRuntimeState = activityRuntimeState
        self.isPinnedToCanvas = isPinnedToCanvas
        self.librarySourceCodeString = librarySourceCodeString
        self.hasRecordedLibraryDerivative = hasRecordedLibraryDerivative
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case frame
        case name
        case codeString
        case activityRuntimeState
        case isPinnedToCanvas
        case librarySourceCodeString
        case hasRecordedLibraryDerivative
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        frame = try container.decode(CGRect.self, forKey: .frame)
        name = try container.decode(String.self, forKey: .name)
        codeString = try container.decode(String.self, forKey: .codeString)
        activityRuntimeState = try container.decodeIfPresent(WidgetActivityRuntimeState.self, forKey: .activityRuntimeState)
        isPinnedToCanvas = try container.decodeIfPresent(Bool.self, forKey: .isPinnedToCanvas) ?? false
        librarySourceCodeString = try container.decodeIfPresent(String.self, forKey: .librarySourceCodeString)
        hasRecordedLibraryDerivative = try container.decodeIfPresent(Bool.self, forKey: .hasRecordedLibraryDerivative) ?? false
    }
}

public enum BuiltInInteractiveKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case inequalitiesExplorer

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .inequalitiesExplorer: return "Inequality Explorer"
        }
    }

    public var defaultSize: CGSize {
        switch self {
        case .inequalitiesExplorer: return CGSize(width: 900, height: 640)
        }
    }

    public var scoreableTaskCount: Int {
        switch self {
        case .inequalitiesExplorer: return 50
        }
    }

    public var pointsPerTask: Int {
        switch self {
        case .inequalitiesExplorer: return 10
        }
    }

    public var pointsPossible: Int {
        scoreableTaskCount * pointsPerTask
    }

    public var widgetCodeString: String {
        "__mathboard_builtin_interactive__:\(rawValue)"
    }

    public func defaultScoreRecord(widgetID: WidgetObject.ID, title: String) -> WidgetActivityScoreRecord {
        WidgetActivityScoreRecord(
            id: widgetID.uuidString,
            title: title.isEmpty ? displayName : title,
            status: .notStarted,
            score: 0,
            attempts: 0,
            points: 0,
            pointsPossible: pointsPossible,
            numberCorrectFirstTry: 0,
            numberCorrectAfterRetry: 0,
            longestStreak: 0
        )
    }

    public static func kind(for codeString: String) -> BuiltInInteractiveKind? {
        let prefix = "__mathboard_builtin_interactive__:"
        guard codeString.hasPrefix(prefix) else { return nil }
        let rawValue = String(codeString.dropFirst(prefix.count))
        return BuiltInInteractiveKind(rawValue: rawValue)
    }
}

public enum WidgetObjectActivityKind: String, Sendable {
    case multipleChoice
    case builtInInteractive
    case unknown

    public var displayCode: String {
        switch self {
        case .multipleChoice: return "MC"
        case .builtInInteractive: return "BI"
        case .unknown: return "W"
        }
    }

    public var displayName: String {
        switch self {
        case .multipleChoice: return "Multiple Choice"
        case .builtInInteractive: return "Built-In Interactive"
        case .unknown: return "Widget"
        }
    }
}

extension WidgetObject {
    public var builtInInteractiveKind: BuiltInInteractiveKind? {
        BuiltInInteractiveKind.kind(for: codeString)
    }

    var activityDocument: ActivityWidgetDocument? {
        guard builtInInteractiveKind == nil else { return nil }
        return WidgetActivityJSONCodec.decode(codeString).document
    }

    public var activityKind: WidgetObjectActivityKind {
        if builtInInteractiveKind != nil { return .builtInInteractive }
        guard let document = activityDocument else { return .unknown }
        switch document.activity {
        case .multipleChoice:
            return .multipleChoice
        }
    }

    public var activityScoreRecord: WidgetActivityScoreRecord? {
        if let builtInInteractiveKind {
            return builtInInteractiveKind.defaultScoreRecord(widgetID: id, title: name)
        }

        guard let document = activityDocument else { return nil }
        let runtimeState = activityRuntimeState ?? WidgetActivityRuntimeState(
            multipleChoice: WidgetMultipleChoiceRuntimeState.initial(for: document)
        )
        var record = runtimeState.scoreRecord(for: document)
        record.id = id.uuidString
        record.title = name.isEmpty ? record.title : name
        return record
    }

    @MainActor public var liveActivityScoreRecord: WidgetActivityScoreRecord? {
        if let builtInInteractiveKind {
            switch builtInInteractiveKind {
            case .inequalitiesExplorer:
                return InequalityExplorerStateRegistry.scoreRecord(for: id, title: name)
            }
        }

        return activityScoreRecord
    }

    @MainActor public static func resetBuiltInRuntimeStates(for widgets: [WidgetObject]) {
        for widget in widgets {
            switch widget.builtInInteractiveKind {
            case .inequalitiesExplorer:
                InequalityExplorerStateRegistry.removeState(for: widget.id)
            case .none:
                continue
            }
        }
    }

    public static func sidecarURL(forDrawingURL drawingURL: URL) -> URL {
        drawingURL
            .deletingPathExtension()
            .appendingPathExtension("widgets.json")
    }

    public static func load(from url: URL) -> [WidgetObject] {
        guard let data = try? Data(contentsOf: url),
              let widgets = try? JSONDecoder().decode([WidgetObject].self, from: data) else {
            return []
        }
        return widgets
    }

    public static func save(_ widgets: [WidgetObject], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(widgets)
        try data.write(to: url, options: .atomic)
    }

    static var sample: WidgetObject {
        WidgetObject(
            name: "Advanced HTML Widget",
            codeString: WidgetSamples.advancedHTML,
            frame: CGRect(x: 80, y: 120, width: 360, height: 280)
        )
    }
}
