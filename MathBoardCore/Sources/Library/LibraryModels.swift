//
//  LibraryModels.swift
//  MathBoardCore - Library module (PROTOTYPE)
//
//  Prototype-only data model, design tokens, and mock content for the future
//  MathBoard Library drawer. Nothing here is wired to persistence, the canvas,
//  or the Extract → Sticker flow. All types are intentionally named with a
//  `Prototype` suffix (or grouped under `LibraryMock`) to make clear this is
//  scaffolding for UI exploration, not production state. See
//  MathBoard/LibraryDrawer_status.md.
//

import SwiftUI

// MARK: - Design tokens

/// Light, classroom-friendly design tokens for the Library drawer.
///
/// Deliberately *lighter* than `ToolPaletteTheme` (which is dark slate/ink):
/// the Library is a "materials drawer", so it uses warm white / soft blue-gray
/// tones with restrained blue accents rather than the palette's sci-fi look.
enum LibraryTheme {
    /// Warm-white panel surface for the open drawer.
    static let panel = Color(red: 0.98, green: 0.98, blue: 0.99)
    /// Slightly cooler recessed surface for search fields, segmented controls.
    static let recessed = Color(red: 0.94, green: 0.95, blue: 0.97)
    /// Card fill for item tiles.
    static let card = Color.white
    /// Soft classroom blue used for accents, selection, and mini-graphics.
    static let accent = Color(red: 0.29, green: 0.53, blue: 0.86)
    /// Muted blue-gray used for hairlines and inactive borders.
    static let hairline = Color(red: 0.82, green: 0.85, blue: 0.90)
    /// Primary slate/ink text.
    static let ink = Color(red: 0.16, green: 0.21, blue: 0.29)
    /// Secondary muted text.
    static let muted = Color(red: 0.45, green: 0.51, blue: 0.60)
    /// The warm-white canvas behind the drawer (matches the app canvas tone).
    static let canvas = Color(red: 0.98, green: 0.97, blue: 0.94)

    // Stable geometry so layout never jumps.
    static let panelCornerRadius: CGFloat = 22
    static let cardCornerRadius: CGFloat = 11
    static let openWidth: CGFloat = 348
    static let thumbnailHeight: CGFloat = 78
    static let edgeTabWidth: CGFloat = 40
    static let edgeTabHeight: CGFloat = 132

    /// Dual soft shadow used on the drawer panel.
    static let panelShadow = Color.black.opacity(0.18)
}

// MARK: - Top-level sections

/// The four top-level Library sections. Names are fixed for the prototype.
enum LibrarySection: String, CaseIterable, Identifiable {
    case stickers = "Stickers"
    case widgets = "Widgets"
    case collections = "Collections"
    case recent = "Recent"

    var id: String { rawValue }

    var title: String { rawValue }

    /// SF Symbol shown in the section tab bar.
    var systemImage: String {
        switch self {
        case .stickers: return "sparkles.rectangle.stack"
        case .widgets: return "square.grid.2x2"
        case .collections: return "folder"
        case .recent: return "clock"
        }
    }
}

// MARK: - Sticker sub-filters

/// Segmented sub-filters shown inside the Stickers section.
enum StickerScope: String, CaseIterable, Identifiable {
    case thisLesson = "This Lesson"
    case saved = "Saved"
    case builtIn = "Built In"

    var id: String { rawValue }
    var title: String { rawValue }
}

// MARK: - Item kinds & thumbnails

/// What a library item represents. Drives the tile presentation.
enum LibraryItemKind: String, Hashable {
    case sticker
    case widget
}

/// Simple, code-generated thumbnail styles. No image assets — each case is
/// drawn with SwiftUI shapes so the prototype needs no bundled resources.
enum StickerThumbnailStyle: Hashable {
    case slopeTriangle
    case workedExample
    case graphCutout
    case formulaCard
    case numberLine
    case coordinateGrid
    case highlightBox
    case arrowCallout
    /// Generic fallback used by Recent / mixed content.
    case genericCard
}

// MARK: - Prototype item

/// A single mock library item (sticker or widget) used purely for layout and
/// interaction exploration. Not persisted, not backed by any real object.
struct LibraryPrototypeItem: Identifiable, Hashable {
    /// Titles are unique within the mock data, so they double as stable IDs.
    var id: String { title }
    let title: String
    let kind: LibraryItemKind
    let thumbnail: StickerThumbnailStyle
    /// Optional small caption (e.g. widget hint or scope tag).
    let caption: String?
    /// SF Symbol for widget tiles (ignored for sticker thumbnails).
    let symbol: String?

    init(
        title: String,
        kind: LibraryItemKind = .sticker,
        thumbnail: StickerThumbnailStyle = .genericCard,
        caption: String? = nil,
        symbol: String? = nil
    ) {
        self.title = title
        self.kind = kind
        self.thumbnail = thumbnail
        self.caption = caption
        self.symbol = symbol
    }
}

/// A mock collection row (organized set of stickers/widgets by teaching context).
struct LibraryCollectionRow: Identifiable, Hashable {
    var id: String { title }
    let title: String
    let symbol: String
    /// Small metadata line, e.g. "3 widgets · 5 stickers".
    let metadata: String
    let tint: Color
}

// MARK: - Mock content

/// Namespace holding all prototype mock data. Isolated so it is obvious what is
/// fake and trivial to delete when real content sources are wired in.
enum LibraryMock {

    // Stickers — "This Lesson": items extracted from the current .mathboard file.
    static let thisLessonStickers: [LibraryPrototypeItem] = [
        .init(title: "Slope Triangle", thumbnail: .slopeTriangle, caption: "Extracted"),
        .init(title: "Worked Example", thumbnail: .workedExample, caption: "Extracted"),
        .init(title: "Graph Cutout", thumbnail: .graphCutout, caption: "Extracted"),
        .init(title: "Highlight Box", thumbnail: .highlightBox, caption: "Extracted")
    ]

    // Stickers — "Saved": reusable stickers saved across lessons.
    static let savedStickers: [LibraryPrototypeItem] = [
        .init(title: "Formula Card", thumbnail: .formulaCard, caption: "Saved"),
        .init(title: "Number Line", thumbnail: .numberLine, caption: "Saved"),
        .init(title: "Coordinate Grid", thumbnail: .coordinateGrid, caption: "Saved"),
        .init(title: "Arrow Callout", thumbnail: .arrowCallout, caption: "Saved"),
        .init(title: "Slope Triangle", thumbnail: .slopeTriangle, caption: "Saved")
    ]

    // Stickers — "Built In": future prefab packs shipped with MathBoard.
    static let builtInStickers: [LibraryPrototypeItem] = [
        .init(title: "Coordinate Grid", thumbnail: .coordinateGrid, caption: "Built In"),
        .init(title: "Number Line", thumbnail: .numberLine, caption: "Built In"),
        .init(title: "Formula Card", thumbnail: .formulaCard, caption: "Built In"),
        .init(title: "Highlight Box", thumbnail: .highlightBox, caption: "Built In"),
        .init(title: "Arrow Callout", thumbnail: .arrowCallout, caption: "Built In"),
        .init(title: "Graph Cutout", thumbnail: .graphCutout, caption: "Built In")
    ]

    static func stickers(for scope: StickerScope) -> [LibraryPrototypeItem] {
        switch scope {
        case .thisLesson: return thisLessonStickers
        case .saved: return savedStickers
        case .builtIn: return builtInStickers
        }
    }

    // Widgets — interactive/configurable objects.
    static let widgets: [LibraryPrototypeItem] = [
        .init(title: "Timer", kind: .widget, caption: "Tap to configure", symbol: "timer"),
        .init(title: "Random Number", kind: .widget, caption: "Tap to configure", symbol: "dice"),
        .init(title: "Coordinate Axis", kind: .widget, caption: "Tap to place", symbol: "chart.xyaxis.line"),
        .init(title: "Number Line", kind: .widget, caption: "Tap to place", symbol: "ruler"),
        .init(title: "Table", kind: .widget, caption: "Tap to configure", symbol: "tablecells"),
        .init(title: "Graph Grid", kind: .widget, caption: "Tap to place", symbol: "grid"),
        .init(title: "HTML Widget", kind: .widget, caption: "Tap to configure", symbol: "chevron.left.forwardslash.chevron.right")
    ]

    // Collections — organized teaching sets.
    static let collections: [LibraryCollectionRow] = [
        .init(title: "Linear Equations", symbol: "chart.xyaxis.line", metadata: "3 widgets · 5 stickers", tint: LibraryTheme.accent),
        .init(title: "Quadratics", symbol: "function", metadata: "8 items", tint: Color(red: 0.86, green: 0.45, blue: 0.32)),
        .init(title: "Trig Identities", symbol: "angle", metadata: "6 stickers", tint: Color(red: 0.35, green: 0.63, blue: 0.52)),
        .init(title: "AP Precalc Unit 1", symbol: "books.vertical", metadata: "12 items", tint: Color(red: 0.55, green: 0.45, blue: 0.78)),
        .init(title: "Geometry Proofs", symbol: "ruler", metadata: "2 widgets · 9 stickers", tint: Color(red: 0.36, green: 0.55, blue: 0.72))
    ]

    // Recent — mixed recently-used stickers and widgets.
    static let recent: [LibraryPrototypeItem] = [
        .init(title: "Slope Triangle", thumbnail: .slopeTriangle, caption: "2m ago"),
        .init(title: "Timer", kind: .widget, caption: "5m ago", symbol: "timer"),
        .init(title: "Coordinate Grid", thumbnail: .coordinateGrid, caption: "12m ago"),
        .init(title: "Formula Card", thumbnail: .formulaCard, caption: "Today"),
        .init(title: "Random Number", kind: .widget, caption: "Today", symbol: "dice"),
        .init(title: "Graph Cutout", thumbnail: .graphCutout, caption: "Yesterday")
    ]
}
