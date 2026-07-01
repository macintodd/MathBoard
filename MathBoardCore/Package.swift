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
        .library(name: "ToolPalette", targets: ["ToolPalette"])
    ],
    targets: [
        .target(name: "Canvas"),
        .target(name: "Presentation", dependencies: ["Canvas", "Calculator", "ToolPalette"]),
        .target(name: "Slides", dependencies: ["Presentation"]),
        .target(name: "Documents", dependencies: ["Slides"]),

        // Self-contained calculator/graphing tool. Not yet integrated;
        // nothing else in MathBoardCore depends on it. See Calculator_status.md.
        .target(name: "Calculator"),
        .testTarget(name: "CalculatorTests", dependencies: ["Calculator"]),

        // Radial drawing palette. Now linked into `Presentation` for the
        // phased, feature-flagged integration (see ToolPalette_integration.md);
        // still dependency-free itself (pure SwiftUI, no UIKit/PencilKit).
        .target(name: "ToolPalette"),
        .testTarget(name: "ToolPaletteTests", dependencies: ["ToolPalette"])
    ]
)
