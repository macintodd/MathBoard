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

extension WidgetObject {
    var activityDocument: ActivityWidgetDocument? {
        WidgetActivityJSONCodec.decode(codeString).document
    }

    public var activityScoreRecord: WidgetActivityScoreRecord? {
        guard let document = activityDocument else { return nil }
        let runtimeState = activityRuntimeState ?? WidgetActivityRuntimeState(
            multipleChoice: WidgetMultipleChoiceRuntimeState.initial(for: document)
        )
        var record = runtimeState.scoreRecord(for: document)
        record.id = id.uuidString
        record.title = name.isEmpty ? record.title : name
        return record
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
