//
//  DisplayBroker.swift
//  MathBoardCore — Presentation module
//
//  Shared state between the iPad UI scene and any connected external
//  display scene. The iPad publishes committed canvas frames (CGImage)
//  plus a lightweight vector representation of the active Apple Pencil
//  stroke, so the external display can show live ink without snapshotting
//  PencilKit's live renderer.
//
//  Singleton because UIScenes don't share a SwiftUI environment — the
//  external scene's UIHostingController is constructed with no parent
//  environment. A shared singleton bridges them.
//
//  CGImage is used because it's cross-platform (works in both iOS and
//  macOS builds of the Presentation module) and avoids a per-frame
//  PNG/JPEG encode-decode round trip.
//

import Foundation
import CoreGraphics
import Observation
import Canvas
import GraphCalculator
import ToolPalette
import WidgetEngine

@MainActor
@Observable
public final class DisplayBroker {

    public static let shared = DisplayBroker()

    /// The URL of the lesson the iPad is currently showing.
    public var lessonURL: URL?

    /// Controls whether the TV receives the full visible canvas or the
    /// centered 16:9 viewfinder crop.
    public var mode: CanvasPresentationMode = .mirror

    /// The latest rendered frame of the iPad's committed drawing surface,
    /// or nil before the first frame is published.
    public var currentFrame: CGImage?

    /// Source rect in canvas coordinates represented by `currentFrame`.
    public var currentFrameSourceRect: CGRect?

    /// Latest visible source rect in canvas coordinates. During pan/zoom this
    /// updates cheaply so the external display can transform the last rendered
    /// frame while waiting for a refreshed committed raster frame.
    public var currentViewportSourceRect: CGRect?

    /// The active Apple Pencil stroke, in the same zero-origin coordinate
    /// space as `currentFrame`. Nil when no live stroke is in progress.
    public var currentLiveStroke: CanvasLiveStroke?

    /// Presentation-only vector strokes that have ended but have not yet been
    /// absorbed by the next committed PencilKit frame. Keeping these visible
    /// avoids the pen-up flash where the TV swaps from MathBoard live ink to
    /// PencilKit's rasterized committed stroke.
    public var completedLiveStrokes: [CanvasLiveStroke] = []

    private static let maximumCompletedLiveStrokes = 200

    /// The latest iPad canvas viewport state for toolbar controls.
    public var viewportState: CanvasViewportState?

    /// True while an external display scene is connected.
    public var isExternalDisplayConnected: Bool = false

    /// Size of the iPad canvas container the calculator palette position is
    /// measured in. Published by PresentingCanvasView; read by the external
    /// scene to place CalculatorTVOverlay at the matching relative spot.
    public var calculatorReferenceSize: CGSize?

    /// Shared state for the Desmos-style graphCalc test mount. The iPad owns
    /// interaction; the external display renders this same state read-only.
    public var graphCalculator = GraphCalculatorState()
    public var isGraphCalculatorVisible = false

    /// Visual state for the custom radial palette while Phase 1 integration is
    /// still display-only. The iPad owns interaction; the external display reads
    /// this state so full-canvas sharing can match what the teacher sees.
    public var toolPaletteState = ToolPaletteState(activeTool: .selection, isCompactDrawerOpen: false)
    public var isToolPaletteExpanded = false
    public var toolPaletteCenter: CGPoint?
    public var compactToolPaletteCenter: CGPoint?
    public var toolPaletteReferenceSize: CGSize?

    /// Live widget objects and viewport from the iPad canvas. The iPad owns
    /// interaction and persistence; the external display renders this read-only
    /// so widget progress, score, and gauge state stay in sync.
    public var widgetObjects: [WidgetObject] = []
    public var widgetViewport: WidgetCanvasViewport?
    public var widgetReferenceSize: CGSize?
    public var widgetCanvasIdentity = ""

    public func publishFrame(_ frame: CGImage, sourceRect: CGRect, viewportSourceRect: CGRect) {
        currentFrame = frame
        currentFrameSourceRect = sourceRect
        currentViewportSourceRect = viewportSourceRect
        completedLiveStrokes.removeAll()
    }

    public func publishViewportSourceRect(_ sourceRect: CGRect) {
        currentViewportSourceRect = sourceRect
    }

    public func publishLiveStroke(_ stroke: CanvasLiveStroke?) {
        if let stroke {
            currentLiveStroke = stroke
            return
        }

        if let currentLiveStroke, !currentLiveStroke.isTransient, currentLiveStroke.points.count > 1 {
            completedLiveStrokes.append(currentLiveStroke)
            if completedLiveStrokes.count > Self.maximumCompletedLiveStrokes {
                completedLiveStrokes.removeFirst(completedLiveStrokes.count - Self.maximumCompletedLiveStrokes)
            }
        }
        currentLiveStroke = nil
    }

    public func publishWidgets(
        _ widgets: [WidgetObject],
        viewport: WidgetCanvasViewport,
        referenceSize: CGSize,
        canvasIdentity: String
    ) {
        widgetObjects = widgets
        widgetViewport = viewport
        widgetReferenceSize = referenceSize
        widgetCanvasIdentity = canvasIdentity
    }

    private init() {}
}
