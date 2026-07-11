//
//  CanvasEditControls.swift
//  MathBoardCore - Canvas module
//

import CoreGraphics
import Foundation

public struct CanvasEditState: Sendable, Equatable {
    public let canUndo: Bool
    public let canRedo: Bool

    public init(canUndo: Bool = false, canRedo: Bool = false) {
        self.canUndo = canUndo
        self.canRedo = canRedo
    }
}

public struct CanvasEditCommand: Sendable, Equatable, Identifiable {
    public enum Action: Sendable, Equatable {
        case undo
        case redo
    }

    public let id: UUID
    public let action: Action

    public init(_ action: Action) {
        self.id = UUID()
        self.action = action
    }
}

public struct CanvasSelectionState: Sendable, Equatable {
    public enum Object: Sendable, Equatable {
        case text(UUID)
        case image(UUID)
        case geometry(UUID)
    }

    public var selectedObject: Object?
    public var selectedTextObject: CanvasTextObject?
    public var selectedGeometryObject: CanvasGeometryObject?
    public var viewportFrame: CGRect?

    public init(
        selectedObject: Object? = nil,
        selectedTextObject: CanvasTextObject? = nil,
        selectedGeometryObject: CanvasGeometryObject? = nil,
        viewportFrame: CGRect? = nil
    ) {
        self.selectedObject = selectedObject
        self.selectedTextObject = selectedTextObject
        self.selectedGeometryObject = selectedGeometryObject
        self.viewportFrame = viewportFrame
    }
}

public struct CanvasGeometryUpdate: Sendable, Equatable {
    public var id: UUID
    public var shape: CanvasGeometryShape
    public var strokeColor: CanvasStrokeColor
    public var strokeWidth: CGFloat
    public var fillColor: CanvasStrokeColor
    public var fillOpacity: CGFloat
    public var polygonSides: Int
    public var arrow: CanvasGeometryArrow

    public init(
        id: UUID,
        shape: CanvasGeometryShape,
        strokeColor: CanvasStrokeColor,
        strokeWidth: CGFloat,
        fillColor: CanvasStrokeColor,
        fillOpacity: CGFloat,
        polygonSides: Int,
        arrow: CanvasGeometryArrow
    ) {
        self.id = id
        self.shape = shape
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.fillColor = fillColor
        self.fillOpacity = fillOpacity
        self.polygonSides = polygonSides
        self.arrow = arrow
    }
}

public struct CanvasObjectCommand: Sendable, Equatable, Identifiable {
    public enum Action: Sendable, Equatable {
        case insertText(CanvasTextInsertion)
        case updateText(CanvasTextUpdate)
        case updateGeometry(CanvasGeometryUpdate)
        case clearSelection
        case copy(CanvasSelectionState.Object)
        case pasteClipboard
        case duplicate(CanvasSelectionState.Object)
        case delete(CanvasSelectionState.Object)
    }

    public let id: UUID
    public let action: Action

    public init(_ action: Action) {
        self.id = UUID()
        self.action = action
    }
}

public enum CanvasSemanticClipboardPayload: Codable, Equatable, Sendable {
    case text(CanvasTextObject)
    case geometry(CanvasGeometryObject)
}

public struct CanvasTextInsertion: Sendable, Equatable {
    public var text: String
    public var sourcePoint: CGPoint
    public var fontSize: CGFloat
    public var color: CanvasStrokeColor
    public var isBold: Bool
    public var isItalic: Bool
    public var isUnderlined: Bool
    public var fontName: String?

    public init(
        text: String,
        sourcePoint: CGPoint,
        fontSize: CGFloat,
        color: CanvasStrokeColor,
        isBold: Bool = false,
        isItalic: Bool = false,
        isUnderlined: Bool = false,
        fontName: String? = nil
    ) {
        self.text = text
        self.sourcePoint = sourcePoint
        self.fontSize = fontSize
        self.color = color
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderlined = isUnderlined
        self.fontName = fontName
    }
}

public struct CanvasExtractedRegion: Sendable, Equatable {
    public var pngData: Data
    public var sourceBounds: CGRect

    public init(pngData: Data, sourceBounds: CGRect) {
        self.pngData = pngData
        self.sourceBounds = sourceBounds
    }
}

public struct CanvasTextUpdate: Sendable, Equatable {
    public var id: UUID
    public var text: String
    public var fontSize: CGFloat
    public var isBold: Bool
    public var isItalic: Bool
    public var isUnderlined: Bool
    public var fontName: String?
    public var expandsToFitContent: Bool

    public init(
        id: UUID,
        text: String,
        fontSize: CGFloat,
        isBold: Bool = false,
        isItalic: Bool = false,
        isUnderlined: Bool = false,
        fontName: String? = nil,
        expandsToFitContent: Bool = true
    ) {
        self.id = id
        self.text = text
        self.fontSize = fontSize
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderlined = isUnderlined
        self.fontName = fontName
        self.expandsToFitContent = expandsToFitContent
    }
}

public struct CanvasToolCommand: Sendable, Equatable, Identifiable {
    public enum Action: Sendable, Equatable {
        case idle
        case select(target: SelectionTarget, mode: SelectionMode)
        case copySelection
        case pasteSelection
        case duplicateSelection
        case deleteSelection
        case extractSelectionAsImageSticker
        case sendSelectionToNextSlide
        case pen(color: CanvasStrokeColor, width: CGFloat)
        case marker(color: CanvasStrokeColor, width: CGFloat)
        case eraser(mode: EraserMode, width: CGFloat)
        case laser(color: CanvasStrokeColor, diameter: CGFloat, duration: TimeInterval, mode: LaserMode)
        case text(color: CanvasStrokeColor, fontSize: CGFloat, isBold: Bool, isItalic: Bool, isUnderlined: Bool, fontName: String?)
        case geometry(shape: CanvasGeometryShape, strokeColor: CanvasStrokeColor, strokeWidth: CGFloat, fillColor: CanvasStrokeColor, fillOpacity: CGFloat, polygonSides: Int, arrow: CanvasGeometryArrow)
        case cover(color: CanvasStrokeColor, mode: SelectionMode)
    }

    public enum EraserMode: Sendable, Equatable {
        case pixel
        case stroke
    }

    public enum LaserMode: Sendable, Equatable {
        case dot
        case trail
    }

    public enum SelectionTarget: Sendable, Equatable {
        case object
        case region
    }

    public enum SelectionMode: Sendable, Equatable {
        case lasso
        case marquee
    }

    public let id: UUID
    public let action: Action

    public init(_ action: Action) {
        self.id = UUID()
        self.action = action
    }
}
