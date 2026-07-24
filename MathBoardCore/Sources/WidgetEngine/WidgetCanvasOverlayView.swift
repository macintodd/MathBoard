//
//  WidgetCanvasOverlayView.swift
//  WidgetEngine
//
//  Places bound widget objects on a zoomable canvas. Origins live in board
//  coordinates. Unpinned widgets keep viewport-stable sizes; pinned widgets scale
//  with the whiteboard content.
//

import CoreGraphics
import SwiftUI

public struct WidgetCanvasViewport: Equatable, Sendable {
    public var zoomScale: CGFloat
    public var contentOffset: CGPoint
    public var canvasOrigin: CGPoint

    public init(
        zoomScale: CGFloat,
        contentOffset: CGPoint,
        canvasOrigin: CGPoint
    ) {
        self.zoomScale = zoomScale
        self.contentOffset = contentOffset
        self.canvasOrigin = canvasOrigin
    }

    public func displayFrame(for sourceFrame: CGRect) -> CGRect {
        let zoom = max(zoomScale, 0.001)
        return CGRect(
            x: (canvasOrigin.x + sourceFrame.minX) * zoom - contentOffset.x,
            y: (canvasOrigin.y + sourceFrame.minY) * zoom - contentOffset.y,
            width: sourceFrame.width,
            height: sourceFrame.height
        )
    }

    public func pinnedDisplayFrame(for sourceFrame: CGRect) -> CGRect {
        let zoom = max(zoomScale, 0.001)
        return CGRect(
            x: (canvasOrigin.x + sourceFrame.minX) * zoom - contentOffset.x,
            y: (canvasOrigin.y + sourceFrame.minY) * zoom - contentOffset.y,
            width: sourceFrame.width * zoom,
            height: sourceFrame.height * zoom
        )
    }

    public func sourceFrame(for displayFrame: CGRect) -> CGRect {
        let zoom = max(zoomScale, 0.001)
        return CGRect(
            x: (displayFrame.minX + contentOffset.x) / zoom - canvasOrigin.x,
            y: (displayFrame.minY + contentOffset.y) / zoom - canvasOrigin.y,
            width: displayFrame.width,
            height: displayFrame.height
        )
    }

    public func pinnedSourceFrame(for displayFrame: CGRect) -> CGRect {
        let zoom = max(zoomScale, 0.001)
        return CGRect(
            x: (displayFrame.minX + contentOffset.x) / zoom - canvasOrigin.x,
            y: (displayFrame.minY + contentOffset.y) / zoom - canvasOrigin.y,
            width: displayFrame.width / zoom,
            height: displayFrame.height / zoom
        )
    }
}

public struct WidgetCanvasOverlayView: View {
    @Binding private var widgets: [WidgetObject]
    private let viewport: WidgetCanvasViewport
    private let canvasIdentity: String
    private let scoreSheet: WidgetActivityScoreSheet
    private let onEditWidget: ((WidgetObject) -> Void)?
    private let allowsWidgetAuthoring: Bool
    private let onWidgetInteractionChanged: ((Bool) -> Void)?
    private let onWidgetDisplayFrameChanged: ((WidgetObject.ID, CGRect?) -> Void)?

    public init(
        widgets: Binding<[WidgetObject]>,
        viewport: WidgetCanvasViewport,
        canvasIdentity: String = "",
        scoreSheet: WidgetActivityScoreSheet,
        onEditWidget: ((WidgetObject) -> Void)? = nil,
        allowsWidgetAuthoring: Bool = true,
        onWidgetInteractionChanged: ((Bool) -> Void)? = nil,
        onWidgetDisplayFrameChanged: ((WidgetObject.ID, CGRect?) -> Void)? = nil
    ) {
        _widgets = widgets
        self.viewport = viewport
        self.canvasIdentity = canvasIdentity
        self.scoreSheet = scoreSheet
        self.onEditWidget = onEditWidget
        self.allowsWidgetAuthoring = allowsWidgetAuthoring
        self.onWidgetInteractionChanged = onWidgetInteractionChanged
        self.onWidgetDisplayFrameChanged = onWidgetDisplayFrameChanged
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach($widgets) { $widget in
                WidgetContainerView(
                    widget: displayBinding(for: $widget),
                    scoreSheet: scoreSheet,
                    allowsPinning: allowsWidgetAuthoring,
                    onEditWidget: allowsWidgetAuthoring ? { onEditWidget?(widget) } : nil,
                    onDeleteWidget: allowsWidgetAuthoring ? { deleteWidget(id: widget.id) } : nil,
                    onInteractionChanged: onWidgetInteractionChanged,
                    onDisplayFrameChanged: { frame in
                        onWidgetDisplayFrameChanged?(widget.id, frame)
                    }
                )
                .id("\(canvasIdentity)-\(widget.id.uuidString)")
            }
        }
    }

    private func deleteWidget(id: WidgetObject.ID) {
        widgets.removeAll { $0.id == id }
    }

    private func displayBinding(for source: Binding<WidgetObject>) -> Binding<WidgetObject> {
        Binding {
            var displayWidget = source.wrappedValue
            displayWidget.frame = source.wrappedValue.isPinnedToCanvas
                ? viewport.pinnedDisplayFrame(for: source.wrappedValue.frame)
                : viewport.displayFrame(for: source.wrappedValue.frame)
            return displayWidget
        } set: { displayWidget in
            var sourceWidget = displayWidget
            sourceWidget.frame = displayWidget.isPinnedToCanvas
                ? viewport.pinnedSourceFrame(for: displayWidget.frame)
                : viewport.sourceFrame(for: displayWidget.frame)
            source.wrappedValue = sourceWidget
        }
    }
}
