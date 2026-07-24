//
//  WidgetContainerView.swift
//  WidgetEngine
//
//  Renders a `WidgetObject` as a floating, draggable, resizable "object" on the
//  whiteboard. When initialized with a binding, frame and activity runtime state
//  changes are written back to document storage.
//

import SwiftUI
import WebKit

// MARK: - WidgetWebView (cross-platform WKWebView wrapper)

/// A thin SwiftUI wrapper around `WKWebView` that live-renders an HTML/JS string
/// and reloads only when that string actually changes. Shared by both the editor
/// preview and the floating container.
struct WidgetWebView {
    /// The raw HTML/JS source to render.
    let htmlString: String

    /// Builds and configures a fresh transparent `WKWebView`.
    fileprivate func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = false
        #if os(iOS)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.bounces = false
        #elseif os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
        #endif
        return webView
    }

    /// Reloads the web view only when the source differs from what was last
    /// loaded, so typing in the editor doesn't thrash the renderer.
    fileprivate func reloadIfNeeded(_ webView: WKWebView, coordinator: Coordinator) {
        guard coordinator.loadedHTML != htmlString else { return }
        coordinator.loadedHTML = htmlString
        webView.loadHTMLString(htmlString, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Tracks the last-loaded HTML to avoid redundant reloads.
    final class Coordinator {
        var loadedHTML: String?
    }
}

#if os(iOS)
extension WidgetWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView() }

    func updateUIView(_ webView: WKWebView, context: Context) {
        reloadIfNeeded(webView, coordinator: context.coordinator)
    }
}
#elseif os(macOS)
extension WidgetWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView() }

    func updateNSView(_ webView: WKWebView, context: Context) {
        reloadIfNeeded(webView, coordinator: context.coordinator)
    }
}
#endif

// MARK: - WidgetContainerView

/// A floating widget "object". Drag the header to move it; drag the bottom-right
/// handle to resize it. The embedded web view always fills the container.
public struct WidgetContainerView: View {
    /// The widget being presented. Its code drives the rendered content.
    @Binding private var widget: WidgetObject
    private let scoreSheet: WidgetActivityScoreSheet?
    private let allowsPinning: Bool
    private let onEditWidget: (() -> Void)?
    private let onDeleteWidget: (() -> Void)?
    private let onInteractionChanged: ((Bool) -> Void)?
    private let onDisplayFrameChanged: ((CGRect?) -> Void)?

    /// Live frame, seeded from `widget.frame`. This is the single source of
    /// truth for position and size while the object floats on the board.
    @State private var frame: CGRect

    /// Committed origin/size captured at the end of each gesture so the next
    /// drag's translation is applied from a stable baseline.
    @State private var committedOrigin: CGPoint
    @State private var committedSize: CGSize

    /// Whichever gesture is currently active, for subtle visual feedback.
    @State private var isDraggingHeader = false
    @State private var isResizing = false
    @State private var dragStartOrigin: CGPoint?
    @State private var resizeStartSize: CGSize?

    private let headerHeight: CGFloat = 34
    private let handleSize: CGFloat = 22
    private let minSize = CGSize(width: 200, height: 160)

    public init(
        widget: Binding<WidgetObject>,
        scoreSheet: WidgetActivityScoreSheet? = nil,
        allowsPinning: Bool = true,
        onEditWidget: (() -> Void)? = nil,
        onDeleteWidget: (() -> Void)? = nil,
        onInteractionChanged: ((Bool) -> Void)? = nil,
        onDisplayFrameChanged: ((CGRect?) -> Void)? = nil
    ) {
        _widget = widget
        self.scoreSheet = scoreSheet
        self.allowsPinning = allowsPinning
        self.onEditWidget = onEditWidget
        self.onDeleteWidget = onDeleteWidget
        self.onInteractionChanged = onInteractionChanged
        self.onDisplayFrameChanged = onDisplayFrameChanged
        _frame = State(initialValue: widget.wrappedValue.frame)
        _committedOrigin = State(initialValue: widget.wrappedValue.frame.origin)
        _committedSize = State(initialValue: widget.wrappedValue.frame.size)
    }

    public init(widget: WidgetObject) {
        _widget = .constant(widget)
        self.scoreSheet = nil
        self.allowsPinning = false
        self.onEditWidget = nil
        self.onDeleteWidget = nil
        self.onInteractionChanged = nil
        self.onDisplayFrameChanged = nil
        _frame = State(initialValue: widget.frame)
        _committedOrigin = State(initialValue: widget.frame.origin)
        _committedSize = State(initialValue: widget.frame.size)
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            renderedContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            if !widget.isPinnedToCanvas {
                resizeHandle
            }
        }
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
        .onChange(of: widget.frame) { _, newFrame in
            guard !isDraggingHeader && !isResizing else { return }
            guard newFrame != frame else { return }
            frame = newFrame
            committedOrigin = newFrame.origin
            committedSize = newFrame.size
        }
        .onAppear {
            guard !isDraggingHeader && !isResizing else { return }
            frame = widget.frame
            committedOrigin = widget.frame.origin
            committedSize = widget.frame.size
            dragStartOrigin = nil
            resizeStartSize = nil
            onDisplayFrameChanged?(nil)
        }
        .onDisappear {
            onInteractionChanged?(false)
            onDisplayFrameChanged?(nil)
        }
    }

    @ViewBuilder
    private var renderedContent: some View {
        if let document = widget.activityDocument {
            WidgetActivityRenderer(
                document: document,
                scoreSheet: scoreSheet,
                onEditWidget: onEditWidget,
                runtimeState: activityRuntimeStateBinding(for: document)
            )
        } else {
            WidgetWebView(htmlString: widget.codeString)
        }
    }

    private func activityRuntimeStateBinding(for document: ActivityWidgetDocument) -> Binding<WidgetActivityRuntimeState> {
        Binding {
            widget.activityRuntimeState ?? WidgetActivityRuntimeState(
                multipleChoice: WidgetMultipleChoiceRuntimeState.initial(for: document)
            )
        } set: { newValue in
            widget.activityRuntimeState = newValue
        }
    }

    // MARK: Header (drag to move)

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.grid.2x2.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(widget.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            if allowsPinning {
                Button {
                    widget.isPinnedToCanvas.toggle()
                } label: {
                    Image(systemName: widget.isPinnedToCanvas ? "pin.fill" : "pin")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(widget.isPinnedToCanvas ? .blue : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(widget.isPinnedToCanvas ? "Unpin widget from canvas" : "Pin widget to canvas")
            }
            if !widget.isPinnedToCanvas {
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            if let onDeleteWidget {
                Button(role: .destructive) {
                    onDeleteWidget()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete widget")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: headerHeight)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
        .contentShape(Rectangle())
        .gesture(headerDragGesture)
    }

    private var headerDragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                guard !widget.isPinnedToCanvas else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    let base = dragStartOrigin ?? committedOrigin
                    if dragStartOrigin == nil {
                        dragStartOrigin = base
                        onInteractionChanged?(true)
                    }
                    isDraggingHeader = true
                    frame.origin = CGPoint(
                        x: base.x + value.translation.width,
                        y: base.y + value.translation.height
                    )
                    onDisplayFrameChanged?(frame)
                }
            }
            .onEnded { _ in
                guard !widget.isPinnedToCanvas else { return }
                committedOrigin = frame.origin
                widget.frame = frame
                onDisplayFrameChanged?(frame)
                dragStartOrigin = nil
                isDraggingHeader = false
                onInteractionChanged?(false)
            }
    }

    // MARK: Resize handle (bottom-right)

    private var resizeHandle: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.thinMaterial)
            Image(systemName: "arrow.down.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .frame(width: handleSize, height: handleSize)
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .padding(6)
        .contentShape(Rectangle())
        .highPriorityGesture(resizeGesture)
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                guard !widget.isPinnedToCanvas else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    let base = resizeStartSize ?? committedSize
                    if resizeStartSize == nil {
                        resizeStartSize = base
                        onInteractionChanged?(true)
                    }
                    isResizing = true
                    // Origin stays fixed; growing the size while `.position` tracks
                    // `midX/midY` keeps the top-left anchored, so the box expands
                    // toward the bottom-right handle.
                    frame.size = CGSize(
                        width: max(minSize.width, base.width + value.translation.width),
                        height: max(minSize.height, base.height + value.translation.height)
                    )
                    onDisplayFrameChanged?(frame)
                }
            }
            .onEnded { _ in
                guard !widget.isPinnedToCanvas else { return }
                committedSize = frame.size
                widget.frame = frame
                onDisplayFrameChanged?(frame)
                resizeStartSize = nil
                isResizing = false
                onInteractionChanged?(false)
            }
    }
}

// MARK: - Preview

#Preview("Widget Container") {
    ZStack {
        // A light "whiteboard" backdrop so the floating object reads clearly.
        Color(white: 0.96).ignoresSafeArea()

        WidgetContainerView(widget: .sample)
    }
}
