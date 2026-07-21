//
//  CanvasEditControls.swift
//  MathBoardCore - Canvas module
//

import CoreGraphics
import Foundation
import WidgetEngine

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
    public var selectedImageObject: CanvasImageObject?
    public var selectedImageCanMoveBackward: Bool
    public var selectedImageCanMoveForward: Bool
    public var selectedGeometryObject: CanvasGeometryObject?
    public var viewportFrame: CGRect?
    public var selectedGroupObjectCount: Int
    public var selectedObjectGroupID: UUID?

    public init(
        selectedObject: Object? = nil,
        selectedTextObject: CanvasTextObject? = nil,
        selectedImageObject: CanvasImageObject? = nil,
        selectedImageCanMoveBackward: Bool = false,
        selectedImageCanMoveForward: Bool = false,
        selectedGeometryObject: CanvasGeometryObject? = nil,
        viewportFrame: CGRect? = nil,
        selectedGroupObjectCount: Int = 0,
        selectedObjectGroupID: UUID? = nil
    ) {
        self.selectedObject = selectedObject
        self.selectedTextObject = selectedTextObject
        self.selectedImageObject = selectedImageObject
        self.selectedImageCanMoveBackward = selectedImageCanMoveBackward
        self.selectedImageCanMoveForward = selectedImageCanMoveForward
        self.selectedGeometryObject = selectedGeometryObject
        self.viewportFrame = viewportFrame
        self.selectedGroupObjectCount = selectedGroupObjectCount
        self.selectedObjectGroupID = selectedObjectGroupID
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
    public enum ImageLayerAction: Sendable, Equatable {
        case bringForward
        case sendBackward
        case bringToFront
        case sendToBack
    }

    public enum Action: Sendable, Equatable {
        case insertText(CanvasTextInsertion)
        case insertImage(CanvasImageInsertion)
        case insertImageNearViewport(CanvasViewportImageInsertion)
        case insertImagesNearViewport([CanvasViewportImageInsertion])
        case insertWidget(CanvasWidgetInsertion)
        case updateWidget(CanvasWidgetUpdate)
        case updateText(CanvasTextUpdate)
        case updateGeometry(CanvasGeometryUpdate)
        case clearSelection
        case copy(CanvasSelectionState.Object)
        case pasteClipboard
        case duplicate(CanvasSelectionState.Object)
        case delete(CanvasSelectionState.Object)
        case reorderImage(UUID, ImageLayerAction)
        case setImageLocked(UUID, Bool)
        case groupSelection
        case ungroupSelection
    }

    public let id: UUID
    public let action: Action

    public init(_ action: Action) {
        self.id = UUID()
        self.action = action
    }
}

public struct CanvasWidgetInsertion: Sendable, Equatable {
    public var name: String
    public var codeString: String
    public var displaySize: CGSize
    public var referenceRect: CGRect?
    public var containerSize: CGSize?
    public var margin: CGFloat

    public init(
        name: String,
        codeString: String,
        displaySize: CGSize = CGSize(width: 820, height: 420),
        referenceRect: CGRect? = nil,
        containerSize: CGSize? = nil,
        margin: CGFloat = 24
    ) {
        self.name = name
        self.codeString = codeString
        self.displaySize = displaySize
        self.referenceRect = referenceRect
        self.containerSize = containerSize
        self.margin = margin
    }

    public var widgetObject: WidgetObject {
        WidgetObject(
            name: name,
            codeString: codeString,
            frame: CGRect(origin: .zero, size: displaySize)
        )
    }
}

public struct CanvasWidgetUpdate: Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var codeString: String
    public var resetsRuntimeState: Bool

    public init(
        id: UUID,
        name: String,
        codeString: String,
        resetsRuntimeState: Bool = true
    ) {
        self.id = id
        self.name = name
        self.codeString = codeString
        self.resetsRuntimeState = resetsRuntimeState
    }
}

public struct CanvasImageInsertion: Sendable, Equatable {
    public var pngData: Data
    public var frame: CGRect
    public var selectAfterInsert: Bool
    public var isLocked: Bool

    public init(
        pngData: Data,
        frame: CGRect,
        selectAfterInsert: Bool = true,
        isLocked: Bool = false
    ) {
        self.pngData = pngData
        self.frame = frame
        self.selectAfterInsert = selectAfterInsert
        self.isLocked = isLocked
    }
}

public struct CanvasViewportImageInsertion: Sendable, Equatable {
    public var pngData: Data
    public var displaySize: CGSize
    public var referenceRect: CGRect?
    public var containerSize: CGSize?
    public var margin: CGFloat
    public var selectAfterInsert: Bool
    public var isLocked: Bool

    public init(
        pngData: Data,
        displaySize: CGSize,
        referenceRect: CGRect? = nil,
        containerSize: CGSize? = nil,
        margin: CGFloat = 20,
        selectAfterInsert: Bool = true,
        isLocked: Bool = false
    ) {
        self.pngData = pngData
        self.displaySize = displaySize
        self.referenceRect = referenceRect
        self.containerSize = containerSize
        self.margin = margin
        self.selectAfterInsert = selectAfterInsert
        self.isLocked = isLocked
    }
}

public enum CanvasSemanticClipboardPayload: Codable, Equatable, Sendable {
    case text(CanvasTextObject)
    case image(CanvasImageObject, Data)
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
        case select(target: SelectionTarget, mode: SelectionMode, behavior: SelectionBehavior, extractAction: ExtractAction?)
        case copySelection
        case pasteSelection
        case duplicateSelection
        case deleteSelection
        case extractSelectionAsImageSticker
        case sendSelectionToNextSlide
        case setExtractAction(ExtractAction)
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
        case tap
        case lasso
        case marquee
    }

    public enum SelectionBehavior: Sendable, Equatable {
        case single
        case multi
    }

    public enum ExtractAction: Sendable, Equatable {
        case copy
        case clone
        case send
        case sticker
        case delete
    }

    public let id: UUID
    public let action: Action

    public init(_ action: Action) {
        self.id = UUID()
        self.action = action
    }
}
