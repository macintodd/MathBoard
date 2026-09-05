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
    public var builtInRuntimeState: [String: String]
    public var isPinnedToCanvas: Bool
    public var librarySourceCodeString: String?
    public var hasRecordedLibraryDerivative: Bool
    public var tags: [String]
    public var requiresStudentWork: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        codeString: String,
        frame: CGRect,
        activityRuntimeState: WidgetActivityRuntimeState? = nil,
        builtInRuntimeState: [String: String] = [:],
        isPinnedToCanvas: Bool = false,
        librarySourceCodeString: String? = nil,
        hasRecordedLibraryDerivative: Bool = false,
        tags: [String] = [],
        requiresStudentWork: Bool = false
    ) {
        self.id = id
        self.name = name
        self.codeString = codeString
        self.frame = frame
        self.activityRuntimeState = activityRuntimeState
        self.builtInRuntimeState = builtInRuntimeState
        self.isPinnedToCanvas = isPinnedToCanvas
        self.librarySourceCodeString = librarySourceCodeString
        self.hasRecordedLibraryDerivative = hasRecordedLibraryDerivative
        self.tags = tags
        self.requiresStudentWork = requiresStudentWork
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case frame
        case name
        case codeString
        case activityRuntimeState
        case builtInRuntimeState
        case isPinnedToCanvas
        case librarySourceCodeString
        case hasRecordedLibraryDerivative
        case tags
        case requiresStudentWork
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        frame = try container.decode(CGRect.self, forKey: .frame)
        name = try container.decode(String.self, forKey: .name)
        codeString = try container.decode(String.self, forKey: .codeString)
        activityRuntimeState = try container.decodeIfPresent(WidgetActivityRuntimeState.self, forKey: .activityRuntimeState)
        builtInRuntimeState = try container.decodeIfPresent([String: String].self, forKey: .builtInRuntimeState) ?? [:]
        isPinnedToCanvas = try container.decodeIfPresent(Bool.self, forKey: .isPinnedToCanvas) ?? false
        librarySourceCodeString = try container.decodeIfPresent(String.self, forKey: .librarySourceCodeString)
        hasRecordedLibraryDerivative = try container.decodeIfPresent(Bool.self, forKey: .hasRecordedLibraryDerivative) ?? false
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        requiresStudentWork = try container.decodeIfPresent(Bool.self, forKey: .requiresStudentWork) ?? false
    }
}

public enum BuiltInInteractiveKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case inequalitiesExplorer
    case countdownTimer
    case randomNumberGenerator
    case coordinateGridGenerator
    case functionTransformationExplorer
    case matchGrid
    case actDailyPractice

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .inequalitiesExplorer: return "Inequality Explorer"
        case .countdownTimer: return "Countdown Timer"
        case .randomNumberGenerator: return "Random Number Generator"
        case .coordinateGridGenerator: return "Coordinate Grid Generator"
        case .functionTransformationExplorer: return "Function Transformation Explorer"
        case .matchGrid: return "MatchGrid"
        case .actDailyPractice: return "ACT Daily Practice"
        }
    }

    public var catalogDescription: String {
        switch self {
        case .inequalitiesExplorer:
            return "Native scored interactive for practicing compound inequalities."
        case .countdownTimer:
            return "On-canvas classroom timer for warmups, stations, and quick checks."
        case .randomNumberGenerator:
            return "On-canvas number picker for examples, teams, and randomized practice values."
        case .coordinateGridGenerator:
            return "Configurable Cartesian coordinate grid generator for canvas work."
        case .functionTransformationExplorer:
            return "Native applet for exploring y = a(x - h)^2 + k with live parameter sliders."
        case .matchGrid:
            return "Teacher-led 6 x 6 classroom matching game with equations, formulas, All Play prompts, and local scoring."
        case .actDailyPractice:
            return "Daily ACT Math practice problem bank with topic browsing, search, and scoreable live-progress reporting."
        }
    }

    public var catalogTags: [String] {
        switch self {
        case .inequalitiesExplorer:
            return ["built-in", "interactive", "inequalities", "scoreable"]
        case .countdownTimer:
            return ["built-in", "interactive", "timer", "classroom tool"]
        case .randomNumberGenerator:
            return ["built-in", "interactive", "random number", "classroom tool"]
        case .coordinateGridGenerator:
            return ["built-in", "interactive", "coordinate grid", "graphing"]
        case .functionTransformationExplorer:
            return ["built-in", "interactive", "function transformations", "quadratics", "graphing"]
        case .matchGrid:
            return ["built-in", "interactive", "matching game", "linear equations", "formulas", "local scoring"]
        case .actDailyPractice:
            return ["built-in", "interactive", "ACT", "daily practice", "test prep", "scoreable"]
        }
    }

    public var defaultSize: CGSize {
        switch self {
        case .inequalitiesExplorer: return CGSize(width: 900, height: 640)
        case .countdownTimer: return CGSize(width: 420, height: 300)
        case .randomNumberGenerator: return CGSize(width: 460, height: 320)
        case .coordinateGridGenerator: return CGSize(width: 720, height: 560)
        case .functionTransformationExplorer: return CGSize(width: 640, height: 520)
        case .matchGrid: return CGSize(width: 940, height: 680)
        case .actDailyPractice: return CGSize(width: 760, height: 620)
        }
    }

    public var scoreableTaskCount: Int {
        switch self {
        case .inequalitiesExplorer: return 50
        case .actDailyPractice: return 1
        case .countdownTimer, .randomNumberGenerator, .coordinateGridGenerator, .functionTransformationExplorer, .matchGrid: return 0
        }
    }

    public var pointsPerTask: Int {
        switch self {
        case .inequalitiesExplorer: return 10
        case .actDailyPractice: return 1
        case .countdownTimer, .randomNumberGenerator, .coordinateGridGenerator, .functionTransformationExplorer, .matchGrid: return 0
        }
    }

    public var isScoreable: Bool {
        scoreableTaskCount > 0 && pointsPerTask > 0
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
    case fillInTheBlank
    case builtInInteractive
    case unknown

    public var displayCode: String {
        switch self {
        case .multipleChoice: return "MC"
        case .fillInTheBlank: return "FIB"
        case .builtInInteractive: return "BI"
        case .unknown: return "W"
        }
    }

    public var displayName: String {
        switch self {
        case .multipleChoice: return "Multiple Choice"
        case .fillInTheBlank: return "Fill in the Blank"
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
        case .fillInTheBlank:
            return .fillInTheBlank
        }
    }

    public var activityScoreRecord: WidgetActivityScoreRecord? {
        if let builtInInteractiveKind {
            guard builtInInteractiveKind.isScoreable else { return nil }
            return builtInInteractiveKind.defaultScoreRecord(widgetID: id, title: name)
        }

        guard let document = activityDocument else { return nil }
        guard document.pedagogicalWorkflow != .conceptualInteractive else { return nil }
        let runtimeState = activityRuntimeState ?? WidgetActivityRuntimeState(
            multipleChoice: WidgetMultipleChoiceRuntimeState.initial(for: document),
            fillInTheBlank: WidgetFillInTheBlankRuntimeState.initial(for: document)
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
            case .actDailyPractice:
                return ACTDailyPracticeStateRegistry.scoreRecord(for: id, title: name)
            case .countdownTimer, .randomNumberGenerator, .coordinateGridGenerator, .functionTransformationExplorer, .matchGrid:
                return nil
            }
        }

        return activityScoreRecord
    }

    @MainActor public static func resetBuiltInRuntimeStates(for widgets: [WidgetObject]) {
        for widget in widgets {
            switch widget.builtInInteractiveKind {
            case .inequalitiesExplorer:
                InequalityExplorerStateRegistry.removeState(for: widget.id)
            case .countdownTimer:
                CountdownTimerStateRegistry.removeState(for: widget.id)
            case .randomNumberGenerator:
                RandomNumberGeneratorStateRegistry.removeState(for: widget.id)
            case .coordinateGridGenerator:
                CoordinateGridGeneratorStateRegistry.removeState(for: widget.id)
            case .functionTransformationExplorer:
                FunctionTransformationExplorerStateRegistry.removeState(for: widget.id)
            case .matchGrid:
                MatchGridStateRegistry.removeState(for: widget.id)
            case .actDailyPractice:
                ACTDailyPracticeStateRegistry.removeState(for: widget.id)
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

public struct WidgetLibraryFolderDescriptor: Identifiable, Sendable {
    public let id: UUID
    public let name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

public struct WidgetGearConfiguration {
    public var questionCount: Int
    public var tags: [String]
    public var requiresStudentWork: Bool
    public var isInLibrary: Bool
    public var libraryFolders: [WidgetLibraryFolderDescriptor]
    public var onResetWidget: (() -> Void)?
    public var onEditWidget: (() -> Void)?
    public var onSaveToLibrary: ((_ tags: [String], _ requiresStudentWork: Bool, _ folderID: UUID?) -> Void)?
    public var onTagsChanged: ((_ tags: [String]) -> Void)?
    public var onRequiresStudentWorkChanged: ((_ value: Bool) -> Void)?
    /// True when the student has submitted this widget's score to the teacher.
    public var isWidgetSubmitted: Bool
    /// True when the widget was submitted and then reset (awaiting resubmit).
    public var isWidgetReset: Bool
    public var onSubmitWidget: (() -> Void)?
    public var onResetAfterSubmit: (() -> Void)?

    public init(
        questionCount: Int,
        tags: [String] = [],
        requiresStudentWork: Bool = false,
        isInLibrary: Bool = false,
        libraryFolders: [WidgetLibraryFolderDescriptor] = [],
        onResetWidget: (() -> Void)? = nil,
        onEditWidget: (() -> Void)? = nil,
        onSaveToLibrary: ((_ tags: [String], _ requiresStudentWork: Bool, _ folderID: UUID?) -> Void)? = nil,
        onTagsChanged: ((_ tags: [String]) -> Void)? = nil,
        onRequiresStudentWorkChanged: ((_ value: Bool) -> Void)? = nil,
        isWidgetSubmitted: Bool = false,
        isWidgetReset: Bool = false,
        onSubmitWidget: (() -> Void)? = nil,
        onResetAfterSubmit: (() -> Void)? = nil
    ) {
        self.questionCount = questionCount
        self.tags = tags
        self.requiresStudentWork = requiresStudentWork
        self.isInLibrary = isInLibrary
        self.libraryFolders = libraryFolders
        self.onResetWidget = onResetWidget
        self.onEditWidget = onEditWidget
        self.onSaveToLibrary = onSaveToLibrary
        self.onTagsChanged = onTagsChanged
        self.onRequiresStudentWorkChanged = onRequiresStudentWorkChanged
        self.isWidgetSubmitted = isWidgetSubmitted
        self.isWidgetReset = isWidgetReset
        self.onSubmitWidget = onSubmitWidget
        self.onResetAfterSubmit = onResetAfterSubmit
    }
}

public struct WidgetCanvasImageInsertionRequest: Sendable {
    public var title: String
    public var pngData: Data
    public var displaySize: CGSize

    public init(title: String, pngData: Data, displaySize: CGSize) {
        self.title = title
        self.pngData = pngData
        self.displaySize = displaySize
    }
}

// MARK: - Widget Submit Environment

/// Injected from the lesson view into the widget hierarchy to wire up Submit/Reset/Resubmit
/// without threading through the canvas overlay chain.
public struct WidgetSubmitEnvironment: @unchecked Sendable {
    public var isWidgetSubmitted: (UUID) -> Bool
    public var isWidgetReset: (UUID) -> Bool
    public var onSubmitWidget: (UUID) -> Void
    public var onResetAfterSubmit: (UUID) -> Void

    public init(
        isWidgetSubmitted: @escaping (UUID) -> Bool,
        isWidgetReset: @escaping (UUID) -> Bool,
        onSubmitWidget: @escaping (UUID) -> Void,
        onResetAfterSubmit: @escaping (UUID) -> Void
    ) {
        self.isWidgetSubmitted = isWidgetSubmitted
        self.isWidgetReset = isWidgetReset
        self.onSubmitWidget = onSubmitWidget
        self.onResetAfterSubmit = onResetAfterSubmit
    }
}

import SwiftUI

public struct WidgetSubmitEnvironmentKey: EnvironmentKey {
    public static let defaultValue: WidgetSubmitEnvironment? = nil
}

extension EnvironmentValues {
    public var widgetSubmit: WidgetSubmitEnvironment? {
        get { self[WidgetSubmitEnvironmentKey.self] }
        set { self[WidgetSubmitEnvironmentKey.self] = newValue }
    }
}
