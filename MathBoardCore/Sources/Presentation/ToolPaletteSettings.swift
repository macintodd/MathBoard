//
//  ToolPaletteSettings.swift
//  MathBoardCore — Presentation module
//
//  Feature flag for the custom radial tool palette integration. Default OFF, so
//  the app behaves exactly as before until the teacher turns it on. Persisted in
//  UserDefaults like CalculatorState's preferences. See ToolPalette_integration.md.
//

import CoreGraphics
import Foundation
import Observation

public enum ToolPaletteStyle: String, CaseIterable, Identifiable, Sendable {
    case radial
    case compact

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .radial:
            return "Radial"
        case .compact:
            return "Compact"
        }
    }
}

public enum ToolPaletteSize: String, CaseIterable, Identifiable, Sendable {
    case small
    case medium

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .small:
            return "Small"
        case .medium:
            return "Medium"
        }
    }

    public var dialSize: CGFloat {
        switch self {
        case .small:
            return 360
        case .medium:
            return 432
        }
    }

    public var collapsedSize: CGFloat {
        switch self {
        case .small:
            return 92
        case .medium:
            return 110
        }
    }
}

@MainActor
@Observable
public final class ToolPaletteSettings {
    public static let shared = ToolPaletteSettings()

    private let store: UserDefaults
    private static let enabledKey = "toolPalette.isCustomPaletteEnabled"
    private static let styleKey = "toolPalette.style"
    private static let sizeKey = "toolPalette.size"

    /// When true, `PresentingCanvasView` shows the floating radial palette.
    /// (Phase 1 is visual only; later phases drive PencilKit and hide the system
    /// tool picker behind this same flag.)
    public var isCustomPaletteEnabled: Bool {
        didSet {
            guard oldValue != isCustomPaletteEnabled else { return }
            store.set(isCustomPaletteEnabled, forKey: Self.enabledKey)
        }
    }

    public var paletteSize: ToolPaletteSize {
        didSet {
            guard oldValue != paletteSize else { return }
            store.set(paletteSize.rawValue, forKey: Self.sizeKey)
        }
    }

    public var paletteStyle: ToolPaletteStyle {
        didSet {
            guard oldValue != paletteStyle else { return }
            store.set(paletteStyle.rawValue, forKey: Self.styleKey)
        }
    }

    /// `init(store:)` accepts an injectable `UserDefaults` for test isolation.
    public init(store: UserDefaults = .standard) {
        self.store = store
        self.isCustomPaletteEnabled = store.bool(forKey: Self.enabledKey)
        if let rawStyle = store.string(forKey: Self.styleKey),
           let style = ToolPaletteStyle(rawValue: rawStyle) {
            self.paletteStyle = style
        } else {
            self.paletteStyle = .radial
        }
        if let rawSize = store.string(forKey: Self.sizeKey),
           let size = ToolPaletteSize(rawValue: rawSize) {
            self.paletteSize = size
        } else {
            self.paletteSize = .small
        }
    }
}
