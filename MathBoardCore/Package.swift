// swift-tools-version: 6.2
//
// MathBoardCore — local Swift package containing MathBoard's core modules.
//
// `Documents` — start screen, folder browsing, `.mathboard` file format, store.
// `Slides` — per-lesson slide management (slides.json + per-slide drawing files).
// `Presentation` — viewfinder overlay, external display routing, viewport controls.
// `Canvas` — PencilKit drawing surface (iPad) + Mac placeholder.
// Future targets: Collaboration.
//
// Dependency chain: Documents → Slides → Presentation → Canvas. Only Documents
// is a library product; everything else is transitively linked through it, so
// the app target needs no Xcode framework-link work as internal modules
// are added.

import PackageDescription

let package = Package(
    name: "MathBoardCore",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(name: "Documents", targets: ["Documents"]),
        .library(name: "ToolPalette", targets: ["ToolPalette"]),

        // Exposed so Xcode offers a "Calculator" scheme for SwiftUI previews.
        // Presentation already links the target for integration; this product
        // only makes the calculator module directly buildable in Xcode.
        .library(name: "Calculator", targets: ["Calculator"]),

        // Isolated Desmos-style teaching calculator prototype. Exposed so Xcode
        // offers a "GraphCalculator" scheme for SwiftUI previews.
        .library(name: "GraphCalculator", targets: ["GraphCalculator"]),

        // Exposed as a product only so Xcode offers a "WidgetEngine" scheme that
        // builds this target for SwiftUI previews. Nothing links it — the app
        // target does not depend on it, so the module stays fully isolated.
        .library(name: "WidgetEngine", targets: ["WidgetEngine"]),

        // Exposed so Xcode offers a "TextEngine" scheme for SwiftUI previews.
        // Presentation links this target as an adapter client; TextEngine itself
        // stays independent of Canvas and app-specific models.
        .library(name: "TextEngine", targets: ["TextEngine"]),

        // Exposed only so Xcode offers a "Library" scheme that builds the
        // Library drawer PROTOTYPE for SwiftUI previews. Nothing links it — the
        // app target does not depend on it, so the module stays fully isolated
        // and is trivial to delete. See MathBoard/LibraryDrawer_status.md.
        .library(name: "Library", targets: ["Library"])
    ],
    dependencies: [
        // Native, offline SwiftUI LaTeX renderer used only by TextEngine's
        // LaTeXPreviewView. No WebView / no network. Isolated behind a single
        // renderer seam so it can be swapped later. See TextEngine_status.md.
        .package(url: "https://github.com/gonzalezreal/swiftui-math", from: "0.1.0")
    ],
    targets: [
        .target(
            name: "Canvas",
            dependencies: [
                .product(name: "SwiftUIMath", package: "swiftui-math")
            ]
        ),
        .target(name: "Presentation", dependencies: ["Canvas", "Calculator", "GraphCalculator", "TextEngine", "ToolPalette"]),
        .target(name: "Slides", dependencies: ["Presentation"]),
        .target(name: "Documents", dependencies: ["Slides"]),

        // Self-contained calculator/graphing tool. Not yet integrated;
        // nothing else in MathBoardCore depends on it. See Calculator_status.md.
        .target(name: "Calculator"),
        .testTarget(name: "CalculatorTests", dependencies: ["Calculator"]),

        // Self-contained Desmos-style graph calculator prototype. It reuses the
        // Calculator target's expression engine and graph geometry, but remains
        // isolated from the MathBoard app until explicitly integrated.
        .target(
            name: "GraphCalculator",
            dependencies: [
                "Calculator",
                .product(name: "SwiftUIMath", package: "swiftui-math")
            ]
        ),

        // Radial drawing palette. Now linked into `Presentation` for the
        // phased, feature-flagged integration (see ToolPalette_integration.md);
        // still dependency-free itself (pure SwiftUI, no UIKit/PencilKit).
        .target(name: "ToolPalette"),
        .testTarget(name: "ToolPaletteTests", dependencies: ["ToolPalette"]),

        // Interactive HTML/JS widget engine (prototype). Fully self-contained:
        // zero dependencies on MathBoard.app or the other MathBoardCore modules.
        // Previewed independently in Xcode; wired into the canvas later via a
        // Coordinator. See WidgetEngine/ and Widget_Engine_status.md.
        .target(name: "WidgetEngine"),

        // Standalone, previewable rich-text/LaTeX editor. Self-contained apart
        // from the SwiftUIMath renderer (used only for LaTeX preview); zero
        // dependencies on MathBoard.app or the other MathBoardCore modules.
        // Presentation translates TextEditorResult into Canvas text commands,
        // keeping the editor reusable and previewable. See TextEngine/.
        .target(
            name: "TextEngine",
            dependencies: [
                .product(name: "SwiftUIMath", package: "swiftui-math")
            ]
        ),

        // Library drawer PROTOTYPE (UI-only). Fully self-contained: zero
        // dependencies on MathBoard.app or the other MathBoardCore modules, and
        // no persistence / canvas wiring. Previewed independently in Xcode via
        // the "Library" scheme. See MathBoard/LibraryDrawer_status.md.
        .target(name: "Library")
    ]
)
