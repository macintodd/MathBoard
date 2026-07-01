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
    }

    public var selectedObject: Object?

    public init(selectedObject: Object? = nil) {
        self.selectedObject = selectedObject
    }
}

public struct CanvasObjectCommand: Sendable, Equatable, Identifiable {
    public enum Action: Sendable, Equatable {
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

public struct CanvasToolCommand: Sendable, Equatable, Identifiable {
    public enum Action: Sendable, Equatable {
        case idle
        case select(target: SelectionTarget, mode: SelectionMode)
        case duplicateSelection
        case deleteSelection
        case pen(color: CanvasStrokeColor, width: CGFloat)
        case marker(color: CanvasStrokeColor, width: CGFloat)
        case eraser(mode: EraserMode, width: CGFloat)
        case laser(color: CanvasStrokeColor, diameter: CGFloat, duration: TimeInterval, mode: LaserMode)
        case text(color: CanvasStrokeColor, fontSize: CGFloat, isBold: Bool, isItalic: Bool, isUnderlined: Bool, fontName: String?)
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
