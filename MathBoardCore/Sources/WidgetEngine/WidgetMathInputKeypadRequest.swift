//
//  WidgetMathInputKeypadRequest.swift
//  WidgetEngine
//
//  Lightweight bridge that lets host apps provide a shared math keypad for
//  widget answer inputs without making WidgetEngine depend on Calculator.
//

import Foundation

public enum WidgetMathInputKeypadKind: String, Sendable {
    case numeric
    case alphanumeric
}

public enum WidgetMathInputKeypadAction: Equatable, Sendable {
    case insert(String)
    case deleteBackward
    case clear
    case moveCursorLeft
    case moveCursorRight
    case returnKey
}

public struct WidgetMathInputKeypadRequest {
    public var id: String
    public var title: String
    public var kind: WidgetMathInputKeypadKind
    public var applyAction: @MainActor (WidgetMathInputKeypadAction) -> Void

    public init(
        id: String,
        title: String,
        kind: WidgetMathInputKeypadKind,
        applyAction: @escaping @MainActor (WidgetMathInputKeypadAction) -> Void
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.applyAction = applyAction
    }
}
