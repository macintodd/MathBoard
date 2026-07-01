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

    /// `init(store:)` accepts an injectable `UserDefaults` for test isolation.
    public init(store: UserDefaults = .standard) {
        self.store = store
        self.isCustomPaletteEnabled = store.bool(forKey: Self.enabledKey)
        if let rawSize = store.string(forKey: Self.sizeKey),
           let size = ToolPaletteSize(rawValue: rawSize) {
            self.paletteSize = size
        } else {
            self.paletteSize = .small
        }
    }
}
