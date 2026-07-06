//
//  LibraryModels.swift
//  MathBoardCore - Library module (PROTOTYPE)
//
//  Prototype-only data model, design tokens, and mock content for the MathBoard
//  Library drawer. Nothing here is wired to persistence, the canvas, or the
//  Extract → Sticker flow. The drawer is a skeuomorphic "materials folder" that
//  slides out from the right edge and offers two modes:
//
//   • Recent    — every object inserted on THIS board (text, GIFs, widgets,
//                 stickers, and ink that was Extracted into a sticker), newest
//                 first. Starring an item files it into the currently-open
//                 library. The Recent library is conceptually saved with the
//                 .mathboard file (each file has its own); duplicating a file
//                 copies its Recent library. All mocked here.
//   • Libraries — reusable libraries shared across every .mathboard file. Browse
//                 the library grid, open one to see its objects, use the back
//                 arrow to return and pick another.
//
//  All content is mock data from `LibraryMock`. See
//  MathBoard/LibraryDrawer_status.md.
//

import SwiftUI

// MARK: - Design tokens

/// Light, classroom-friendly tokens for the Library drawer, plus the warm gold
/// used for the skeuomorphic folder tab.
enum LibraryTheme {
    /// Warm-white panel surface for the open drawer.
    static let panel = Color(red: 0.99, green: 0.99, blue: 1.0)
    /// Cooler recessed surface for the segmented control / search field.
    static let recessed = Color(red: 0.93, green: 0.94, blue: 0.96)
    /// Card fill for item / folder tiles.
    static let card = Color.white
    /// Soft classroom blue used for accents and selection.
    static let accent = Color(red: 0.29, green: 0.53, blue: 0.86)
    /// Muted blue-gray hairline / inactive border.
    static let hairline = Color(red: 0.86, green: 0.88, blue: 0.92)
    /// Primary slate/ink text.
    static let ink = Color(red: 0.13, green: 0.16, blue: 0.22)
    /// Secondary muted text.
    static let muted = Color(red: 0.48, green: 0.53, blue: 0.60)
    /// The faint dotted canvas behind the drawer (preview host).
    static let canvas = Color(red: 0.97, green: 0.98, blue: 0.99)

    /// Light-blue fill behind the "Starred items will be added to …" banner.
    static let bannerFill = Color(red: 0.91, green: 0.95, blue: 1.0)

    /// Gold star used for the "starred" state.
    static let star = Color(red: 0.98, green: 0.74, blue: 0.16)

    // Skeuomorphic manila folder tab.
    static let folderTab = Color(red: 0.84, green: 0.66, blue: 0.40)
    static let folderTabEdge = Color(red: 0.70, green: 0.52, blue: 0.28)
    static let folderTabText = Color(red: 0.33, green: 0.23, blue: 0.09)

    // Stable geometry so layout never jumps.
    static let panelCornerRadius: CGFloat = 20
    static let cardCornerRadius: CGFloat = 12
    static let openWidth: CGFloat = 366
    static let thumbnailHeight: CGFloat = 118
    static let folderTabWidth: CGFloat = 34
    static let folderTabHeight: CGFloat = 152
    /// Distance from the top of the app to the folder tab — kept small so the
    /// tab sits near the top of the board, per the mockup.
    static let folderTabTopInset: CGFloat = 84

    static let panelShadow = Color.black.opacity(0.16)
}

// MARK: - Modes

/// Top-level segmented control: the two ways to browse the Library.
enum LibraryMode: String, CaseIterable, Identifiable {
    case recent = "Recent"
    case libraries = "Libraries"

    var id: String { rawValue }
    var title: String { rawValue }
}

// MARK: - Object type badge

/// Small pill shown on a Recent card describing what kind of object it is.
/// Colors approximate the mockups. `.ink` marks a drawing that was Extracted
/// into a sticker (raw handwriting never appears in Recent).
enum LibraryBadge: String, Hashable {
    case ink = "INK"
    case sticker = "STICKER"
    case html = "HTML"
    case gif = "GIF"
    case text = "TEXT"

    var background: Color {
        switch self {
        case .ink: return Color(red: 0.92, green: 0.94, blue: 0.97)
        case .sticker: return Color(red: 0.98, green: 0.90, blue: 0.98)
        case .html: return Color(red: 0.88, green: 0.94, blue: 1.0)
        case .gif: return Color(red: 0.20, green: 0.78, blue: 0.45)
        case .text: return Color(red: 0.93, green: 0.93, blue: 0.95)
        }
    }

    var foreground: Color {
        switch self {
        case .ink: return Color(red: 0.30, green: 0.36, blue: 0.46)
        case .sticker: return Color(red: 0.72, green: 0.32, blue: 0.80)
        case .html: return Color(red: 0.20, green: 0.48, blue: 0.86)
        case .gif: return .white
        case .text: return Color(red: 0.36, green: 0.40, blue: 0.48)
        }
    }
}

// MARK: - Thumbnails

/// Code-drawn thumbnail styles (no image assets). Rendered by `LibraryThumbnail`
/// in the view file.
enum LibraryThumbnailStyle: Hashable {
    case parabola
    case sine
    case circleRadius
    case barChart
    case rightTriangle
    case arrowUp
    case goldStarSticker
    case timerWidget
    case gifCard
    case inkSquare
    case genericGraph
}

// MARK: - Objects

/// A single library object — used both in Recent and inside an opened library.
/// Prototype only; not backed by any real inserted object.
struct LibraryObject: Identifiable, Hashable {
    let id: String
    let title: String
    /// Type pill (shown in Recent; usually hidden inside a library).
    let badge: LibraryBadge?
    let thumbnail: LibraryThumbnailStyle
    /// Whether this Recent item has been filed into the open library.
    var isStarred: Bool

    init(
        id: String,
        title: String,
        badge: LibraryBadge? = nil,
        thumbnail: LibraryThumbnailStyle,
        isStarred: Bool = false
    ) {
        self.id = id
        self.title = title
        self.badge = badge
        self.thumbnail = thumbnail
        self.isStarred = isStarred
    }
}

// MARK: - Libraries

/// A reusable library (shared across every .mathboard file). Tapping opens it
/// to reveal its objects.
struct LibraryFolder: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let symbol: String
    let itemCount: Int
    let tint: Color
}

// MARK: - Mock content

/// Namespace holding all prototype mock data. Isolated so it is obvious what is
/// fake and trivial to delete when real content sources are wired in.
enum LibraryMock {

    /// Recent objects for the current board (newest first). Ink items are
    /// Extract-made stickers, per the "no raw handwriting" rule.
    static let recent: [LibraryObject] = [
        .init(id: "r.parabola", title: "Parabola y=x²", badge: .ink, thumbnail: .parabola, isStarred: true),
        .init(id: "r.goldstar", title: "Gold star", badge: .sticker, thumbnail: .goldStarSticker),
        .init(id: "r.sine", title: "Sine wave", badge: .ink, thumbnail: .sine),
        .init(id: "r.timer", title: "Timer widget", badge: .html, thumbnail: .timerWidget, isStarred: true),
        .init(id: "r.gif", title: "Reaction GIF", badge: .gif, thumbnail: .gifCard),
        .init(id: "r.ink", title: "Ink note", badge: .ink, thumbnail: .inkSquare),
        .init(id: "r.arrow", title: "Callout arrow", badge: .ink, thumbnail: .arrowUp),
        .init(id: "r.triangle", title: "Right triangle", badge: .ink, thumbnail: .rightTriangle)
    ]

    /// The reusable libraries shown in the Libraries grid.
    static let folders: [LibraryFolder] = [
        .init(name: "Math Tools", symbol: "sum", itemCount: 24, tint: Color(red: 0.42, green: 0.55, blue: 0.90)),
        .init(name: "Quadratics", symbol: "chart.line.uptrend.xyaxis", itemCount: 12, tint: Color(red: 0.35, green: 0.70, blue: 0.48)),
        .init(name: "Geometry", symbol: "compass.drawing", itemCount: 18, tint: Color(red: 0.90, green: 0.62, blue: 0.35)),
        .init(name: "Physics", symbol: "atom", itemCount: 9, tint: Color(red: 0.88, green: 0.45, blue: 0.45)),
        .init(name: "Chemistry", symbol: "flask", itemCount: 15, tint: Color(red: 0.66, green: 0.48, blue: 0.86)),
        .init(name: "Graphs", symbol: "chart.pie", itemCount: 7, tint: Color(red: 0.35, green: 0.66, blue: 0.68))
    ]

    /// The default star destination shown in the Recent banner until the user
    /// opens a different library.
    static var defaultDestination: LibraryFolder {
        folders.first(where: { $0.name == "Quadratics" }) ?? folders[0]
    }

    /// Objects inside a given library. Quadratics is hand-authored to match the
    /// mockup; the rest are generated so every library has browsable content.
    static func objects(in folder: LibraryFolder) -> [LibraryObject] {
        if folder.name == "Quadratics" {
            return [
                .init(id: "q1", title: "Quadratics · 1", thumbnail: .circleRadius),
                .init(id: "q2", title: "Quadratics · 2", thumbnail: .barChart),
                .init(id: "q3", title: "Quadratics · 3", thumbnail: .parabola),
                .init(id: "q4", title: "Quadratics · 4", thumbnail: .rightTriangle),
                .init(id: "q5", title: "Quadratics · 5", thumbnail: .sine),
                .init(id: "q6", title: "Quadratics · 6", thumbnail: .arrowUp)
            ]
        }
        let styles: [LibraryThumbnailStyle] = [
            .genericGraph, .circleRadius, .barChart, .rightTriangle, .sine, .parabola, .arrowUp
        ]
        return (1...folder.itemCount).map { index in
            LibraryObject(
                id: "\(folder.name).\(index)",
                title: "\(folder.name) · \(index)",
                thumbnail: styles[(index - 1) % styles.count]
            )
        }
    }
}
