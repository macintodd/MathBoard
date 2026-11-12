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
    /// When true, this widget is only visible to the teacher and is stripped from student copies of the canvas.
    public var isTeacherOnly: Bool

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
        requiresStudentWork: Bool = false,
        isTeacherOnly: Bool = false
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
        self.isTeacherOnly = isTeacherOnly
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
        case isTeacherOnly
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
        isTeacherOnly = try container.decodeIfPresent(Bool.self, forKey: .isTeacherOnly) ?? false
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
    case quadraticWebApplet
    case domainRangeWebApplet
    case analizingGraphs1WebApplet
    case projectileMotionGraphAnalysisWebApplet
    case constantRateWebApplet
    case completingTheSquareWebApplet
    case andOrAttributeFilterWebApplet
    case andOrInequalityNumberLineWebApplet
    case compoundInequalityGraphingDemoWebApplet
    case absoluteValueAsDemonstrationWebApplet
    case introPointSlopeWebApplet
    case writeLinearEquationWebApplet
    case parallelPerpendicularWebApplet

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
        case .quadraticWebApplet: return WebAppletResource.quadraticSlider.displayName
        case .domainRangeWebApplet: return WebAppletResource.domainRangeFromGraphs.displayName
        case .analizingGraphs1WebApplet: return WebAppletResource.analizingGraphs1.displayName
        case .projectileMotionGraphAnalysisWebApplet: return WebAppletResource.projectileMotionGraphAnalysis.displayName
        case .constantRateWebApplet: return WebAppletResource.constantRateDemo.displayName
        case .completingTheSquareWebApplet: return WebAppletResource.completingTheSquareLab.displayName
        case .andOrAttributeFilterWebApplet: return WebAppletResource.andOrAttributeFilter.displayName
        case .andOrInequalityNumberLineWebApplet: return WebAppletResource.andOrInequalityNumberLine.displayName
        case .compoundInequalityGraphingDemoWebApplet: return WebAppletResource.compoundInequalityGraphingDemo.displayName
        case .absoluteValueAsDemonstrationWebApplet: return WebAppletResource.absoluteValueAsDistance.displayName
        case .introPointSlopeWebApplet: return "Intro to Point-Slope Form"
        case .writeLinearEquationWebApplet: return "Write Linear Equation"
        case .parallelPerpendicularWebApplet: return "Parallel & Perpendicular Lines"
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
        case .quadraticWebApplet:
            return WebAppletResource.quadraticSlider.description
        case .domainRangeWebApplet:
            return WebAppletResource.domainRangeFromGraphs.description
        case .analizingGraphs1WebApplet:
            return WebAppletResource.analizingGraphs1.description
        case .projectileMotionGraphAnalysisWebApplet:
            return WebAppletResource.projectileMotionGraphAnalysis.description
        case .constantRateWebApplet:
            return WebAppletResource.constantRateDemo.description
        case .completingTheSquareWebApplet:
            return WebAppletResource.completingTheSquareLab.description
        case .andOrAttributeFilterWebApplet:
            return WebAppletResource.andOrAttributeFilter.description
        case .andOrInequalityNumberLineWebApplet:
            return WebAppletResource.andOrInequalityNumberLine.description
        case .compoundInequalityGraphingDemoWebApplet:
            return WebAppletResource.compoundInequalityGraphingDemo.description
        case .absoluteValueAsDemonstrationWebApplet:
            return WebAppletResource.absoluteValueAsDistance.description
        case .introPointSlopeWebApplet:
            return "Algebra 2 / Precalculus student practice: drag a slope and point into point-slope form, distribute, write the final equation. Deterministic first problem; ten problems with first-try streak scoring. Mirrored to external display."
        case .writeLinearEquationWebApplet:
            return "Teacher demo for writing linear equations from a graph or given conditions. Covers slope-intercept and point-slope form. Mirrored to external display."
        case .parallelPerpendicularWebApplet:
            return "Teacher demo for exploring parallel and perpendicular lines — slope relationships, graphing, and identifying line pairs. Mirrored to external display."
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
        case .quadraticWebApplet:
            return WebAppletResource.quadraticSlider.tags
        case .domainRangeWebApplet:
            return WebAppletResource.domainRangeFromGraphs.tags
        case .analizingGraphs1WebApplet:
            return WebAppletResource.analizingGraphs1.tags
        case .projectileMotionGraphAnalysisWebApplet:
            return WebAppletResource.projectileMotionGraphAnalysis.tags
        case .constantRateWebApplet:
            return WebAppletResource.constantRateDemo.tags
        case .completingTheSquareWebApplet:
            return WebAppletResource.completingTheSquareLab.tags
        case .andOrAttributeFilterWebApplet:
            return WebAppletResource.andOrAttributeFilter.tags
        case .andOrInequalityNumberLineWebApplet:
            return WebAppletResource.andOrInequalityNumberLine.tags
        case .compoundInequalityGraphingDemoWebApplet:
            return WebAppletResource.compoundInequalityGraphingDemo.tags
        case .absoluteValueAsDemonstrationWebApplet:
            return WebAppletResource.absoluteValueAsDistance.tags
        case .introPointSlopeWebApplet:
            return ["web applet", "demo", "point-slope", "linear equations", "algebra 2", "precalculus", "external display", "student practice"]
        case .writeLinearEquationWebApplet:
            return ["web applet", "demo", "linear equations", "writing equations", "slope-intercept", "point-slope", "algebra", "external display"]
        case .parallelPerpendicularWebApplet:
            return ["web applet", "demo", "parallel lines", "perpendicular lines", "slope", "linear equations", "algebra", "external display"]
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
        case .quadraticWebApplet: return CGSize(width: 900, height: 560)
        case .domainRangeWebApplet: return CGSize(width: 900, height: 620)
        case .analizingGraphs1WebApplet: return CGSize(width: 900, height: 620)
        case .projectileMotionGraphAnalysisWebApplet: return CGSize(width: 960, height: 680)
        case .constantRateWebApplet: return CGSize(width: 960, height: 660)
        case .completingTheSquareWebApplet: return CGSize(width: 960, height: 660)
        case .andOrAttributeFilterWebApplet: return CGSize(width: 900, height: 640)
        case .andOrInequalityNumberLineWebApplet: return CGSize(width: 1040, height: 780)
        case .compoundInequalityGraphingDemoWebApplet: return CGSize(width: 1040, height: 600)
        case .absoluteValueAsDemonstrationWebApplet: return CGSize(width: 1060, height: 720)
        case .introPointSlopeWebApplet: return CGSize(width: 1060, height: 760)
        case .writeLinearEquationWebApplet: return CGSize(width: 1060, height: 760)
        case .parallelPerpendicularWebApplet: return CGSize(width: 1060, height: 760)
        }
    }

    public var scoreableTaskCount: Int {
        switch self {
        case .inequalitiesExplorer: return 50
        case .actDailyPractice: return 1
        case .countdownTimer, .randomNumberGenerator, .coordinateGridGenerator, .functionTransformationExplorer, .matchGrid, .quadraticWebApplet, .domainRangeWebApplet, .analizingGraphs1WebApplet, .projectileMotionGraphAnalysisWebApplet, .constantRateWebApplet, .completingTheSquareWebApplet, .andOrAttributeFilterWebApplet, .andOrInequalityNumberLineWebApplet, .compoundInequalityGraphingDemoWebApplet, .absoluteValueAsDemonstrationWebApplet, .introPointSlopeWebApplet, .writeLinearEquationWebApplet, .parallelPerpendicularWebApplet: return 0
        }
    }

    public var pointsPerTask: Int {
        switch self {
        case .inequalitiesExplorer: return 10
        case .actDailyPractice: return 1
        case .countdownTimer, .randomNumberGenerator, .coordinateGridGenerator, .functionTransformationExplorer, .matchGrid, .quadraticWebApplet, .domainRangeWebApplet, .analizingGraphs1WebApplet, .projectileMotionGraphAnalysisWebApplet, .constantRateWebApplet, .completingTheSquareWebApplet, .andOrAttributeFilterWebApplet, .andOrInequalityNumberLineWebApplet, .compoundInequalityGraphingDemoWebApplet, .absoluteValueAsDemonstrationWebApplet, .introPointSlopeWebApplet, .writeLinearEquationWebApplet, .parallelPerpendicularWebApplet: return 0
        }
    }

    public var isScoreable: Bool {
        scoreableTaskCount > 0 && pointsPerTask > 0
    }

    public var isTeacherDemoWebApplet: Bool {
        WebAppletResource.resource(for: self) != nil || self == .introPointSlopeWebApplet || self == .writeLinearEquationWebApplet || self == .parallelPerpendicularWebApplet
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
    case trivialPursuit
    case builtInInteractive
    case unknown

    public var displayCode: String {
        switch self {
        case .multipleChoice: return "MC"
        case .fillInTheBlank: return "FIB"
        case .trivialPursuit: return "TP"
        case .builtInInteractive: return "BI"
        case .unknown: return "W"
        }
    }

    public var displayName: String {
        switch self {
        case .multipleChoice: return "Multiple Choice"
        case .fillInTheBlank: return "Fill in the Blank"
        case .trivialPursuit: return "Trivial Pursuit Party"
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
        case .trivialPursuit:
            return .trivialPursuit
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
                return InequalityExplorerStateRegistry.scoreRecord(for: self)
            case .actDailyPractice:
                return ACTDailyPracticeStateRegistry.state(for: self).scoreRecord(widgetID: id, title: name)
            case .countdownTimer, .randomNumberGenerator, .coordinateGridGenerator, .functionTransformationExplorer, .matchGrid, .quadraticWebApplet, .domainRangeWebApplet, .analizingGraphs1WebApplet, .projectileMotionGraphAnalysisWebApplet, .constantRateWebApplet, .completingTheSquareWebApplet, .andOrAttributeFilterWebApplet, .andOrInequalityNumberLineWebApplet, .compoundInequalityGraphingDemoWebApplet, .absoluteValueAsDemonstrationWebApplet, .introPointSlopeWebApplet, .writeLinearEquationWebApplet, .parallelPerpendicularWebApplet:
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
            case .quadraticWebApplet, .domainRangeWebApplet, .analizingGraphs1WebApplet, .projectileMotionGraphAnalysisWebApplet, .constantRateWebApplet, .completingTheSquareWebApplet, .andOrAttributeFilterWebApplet, .andOrInequalityNumberLineWebApplet, .compoundInequalityGraphingDemoWebApplet, .absoluteValueAsDemonstrationWebApplet, .introPointSlopeWebApplet, .writeLinearEquationWebApplet, .parallelPerpendicularWebApplet:
                WebAppletStateRegistry.removeState(for: widget.id)
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

public enum WidgetClassroomParticipantRole: String, Sendable {
    case teacher
    case student
}

public struct WidgetClassroomParticipant: Identifiable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var role: WidgetClassroomParticipantRole

    public init(
        id: String,
        displayName: String,
        role: WidgetClassroomParticipantRole
    ) {
        self.id = id
        self.displayName = displayName
        self.role = role
    }
}

public struct WidgetClassroomLiveProgressRecord: Equatable, Sendable {
    public var widgetID: UUID
    public var participantID: String
    public var displayName: String
    public var correctCount: Int
    public var attemptedCount: Int
    public var isActiveOnStudentScreen: Bool
    public var updatedAt: Date
    public var metadata: [String: String]

    public init(
        widgetID: UUID,
        participantID: String,
        displayName: String,
        correctCount: Int,
        attemptedCount: Int,
        isActiveOnStudentScreen: Bool = false,
        updatedAt: Date,
        metadata: [String: String] = [:]
    ) {
        self.widgetID = widgetID
        self.participantID = participantID
        self.displayName = displayName
        self.correctCount = max(0, correctCount)
        self.attemptedCount = max(0, attemptedCount)
        self.isActiveOnStudentScreen = isActiveOnStudentScreen
        self.updatedAt = updatedAt
        self.metadata = metadata
    }
}

public struct WidgetClassroomGameContext: Equatable, Sendable {
    public var role: WidgetClassroomParticipantRole
    public var currentParticipantID: String?
    public var participants: [WidgetClassroomParticipant]
    public var liveProgressRecords: [WidgetClassroomLiveProgressRecord]

    public init(
        role: WidgetClassroomParticipantRole,
        currentParticipantID: String? = nil,
        participants: [WidgetClassroomParticipant] = [],
        liveProgressRecords: [WidgetClassroomLiveProgressRecord] = []
    ) {
        self.role = role
        self.currentParticipantID = currentParticipantID
        self.participants = participants
        self.liveProgressRecords = liveProgressRecords
    }
}

public struct WidgetGearConfiguration {
    public var widgetID: UUID?
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
        widgetID: UUID? = nil,
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
        self.widgetID = widgetID
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

public struct WidgetClassroomGameContextKey: EnvironmentKey {
    public static let defaultValue: WidgetClassroomGameContext? = nil
}

extension EnvironmentValues {
    public var widgetSubmit: WidgetSubmitEnvironment? {
        get { self[WidgetSubmitEnvironmentKey.self] }
        set { self[WidgetSubmitEnvironmentKey.self] = newValue }
    }

    public var widgetClassroomGameContext: WidgetClassroomGameContext? {
        get { self[WidgetClassroomGameContextKey.self] }
        set { self[WidgetClassroomGameContextKey.self] = newValue }
    }
}
