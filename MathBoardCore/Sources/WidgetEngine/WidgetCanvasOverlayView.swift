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
    private let widgetAssetBaseURL: URL?
    private let scoreSheet: WidgetActivityScoreSheet
    private let onEditWidget: ((WidgetObject) -> Void)?
    private let allowsWidgetAuthoring: Bool
    private let onWidgetInteractionChanged: ((Bool) -> Void)?
    private let onWidgetDisplayFrameChanged: ((WidgetObject.ID, CGRect?) -> Void)?
    private let onMathInputRequested: (@MainActor (WidgetMathInputKeypadRequest) -> Void)?
    private let onImageInsertionRequested: (@MainActor (WidgetCanvasImageInsertionRequest) -> Void)?
    private let showsTeacherDemoWebApplets: Bool
    private let isExternalDisplay: Bool

    public init(
        widgets: Binding<[WidgetObject]>,
        viewport: WidgetCanvasViewport,
        canvasIdentity: String = "",
        widgetAssetBaseURL: URL? = nil,
        scoreSheet: WidgetActivityScoreSheet,
        onEditWidget: ((WidgetObject) -> Void)? = nil,
        allowsWidgetAuthoring: Bool = true,
        onWidgetInteractionChanged: ((Bool) -> Void)? = nil,
        onWidgetDisplayFrameChanged: ((WidgetObject.ID, CGRect?) -> Void)? = nil,
        onMathInputRequested: (@MainActor (WidgetMathInputKeypadRequest) -> Void)? = nil,
        onImageInsertionRequested: (@MainActor (WidgetCanvasImageInsertionRequest) -> Void)? = nil,
        showsTeacherDemoWebApplets: Bool = true,
        isExternalDisplay: Bool = false
    ) {
        _widgets = widgets
        self.viewport = viewport
        self.canvasIdentity = canvasIdentity
        self.widgetAssetBaseURL = widgetAssetBaseURL
        self.scoreSheet = scoreSheet
        self.onEditWidget = onEditWidget
        self.allowsWidgetAuthoring = allowsWidgetAuthoring
        self.onWidgetInteractionChanged = onWidgetInteractionChanged
        self.onWidgetDisplayFrameChanged = onWidgetDisplayFrameChanged
        self.onMathInputRequested = onMathInputRequested
        self.onImageInsertionRequested = onImageInsertionRequested
        self.showsTeacherDemoWebApplets = showsTeacherDemoWebApplets
        self.isExternalDisplay = isExternalDisplay
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(widgets) { widget in
                if shouldRender(widget), let widgetBinding = sourceBinding(for: widget.id) {
                    WidgetContainerView(
                        widget: displayBinding(for: widgetBinding),
                        scoreSheet: scoreSheet,
                        allowsPinning: allowsWidgetAuthoring,
                        onEditWidget: allowsWidgetAuthoring ? { onEditWidget?(widget) } : nil,
                        onDeleteWidget: allowsWidgetAuthoring ? { deleteWidget(id: widget.id) } : nil,
                        onInteractionChanged: onWidgetInteractionChanged,
                        onDisplayFrameChanged: { frame in
                            onWidgetDisplayFrameChanged?(widget.id, frame)
                        },
                        onMathInputRequested: onMathInputRequested,
                        onImageInsertionRequested: onImageInsertionRequested,
                        widgetAssetBaseURL: widgetAssetBaseURL,
                        isExternalDisplay: isExternalDisplay
                    )
                    .id("\(canvasIdentity)-\(widget.id.uuidString)")
                }
            }
        }
        .ignoresSafeArea()
    }

    private func shouldRender(_ widget: WidgetObject) -> Bool {
        showsTeacherDemoWebApplets || widget.builtInInteractiveKind?.isTeacherDemoWebApplet != true
    }

    private func deleteWidget(id: WidgetObject.ID) {
        Task { @MainActor in
            await Task.yield()
            let removedWidgets = widgets.filter { $0.id == id }
            widgets.removeAll { $0.id == id }
            onWidgetInteractionChanged?(false)
            onWidgetDisplayFrameChanged?(id, nil)
            WidgetObject.resetBuiltInRuntimeStates(for: removedWidgets)
        }
    }

    private func sourceBinding(for id: WidgetObject.ID) -> Binding<WidgetObject>? {
        guard let index = widgets.firstIndex(where: { $0.id == id }) else { return nil }
        let snapshot = widgets[index]
        return Binding {
            // Fast path: index still valid and identity matches.
            guard self.widgets.indices.contains(index), self.widgets[index].id == id else {
                return self.widgets.first(where: { $0.id == id }) ?? snapshot
            }
            return self.widgets[index]
        } set: { updatedWidget in
            guard self.widgets.indices.contains(index), self.widgets[index].id == id else { return }
            self.widgets[index] = updatedWidget
        }
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
