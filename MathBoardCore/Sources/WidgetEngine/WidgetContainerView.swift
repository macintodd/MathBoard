//
//  WidgetContainerView.swift
//  WidgetEngine
//
//  Renders a `WidgetObject` as a floating, draggable, resizable "object" on the
//  whiteboard. All position/size state is owned internally here, completely
//  independent of the main app canvas — a future Coordinator can read the final
//  frame back out when it wires widgets into the real document.
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
struct WidgetContainerView: View {
    /// The widget being presented. Its code drives the rendered content.
    let widget: WidgetObject

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

    private let headerHeight: CGFloat = 34
    private let handleSize: CGFloat = 22
    private let minSize = CGSize(width: 200, height: 160)

    init(widget: WidgetObject) {
        self.widget = widget
        _frame = State(initialValue: widget.frame)
        _committedOrigin = State(initialValue: widget.frame.origin)
        _committedSize = State(initialValue: widget.frame.size)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            WidgetWebView(htmlString: widget.codeString)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) { resizeHandle }
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
        .animation(.interactiveSpring(duration: 0.2), value: isDraggingHeader)
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
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(height: headerHeight)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
        .contentShape(Rectangle())
        .gesture(headerDragGesture)
    }

    private var headerDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                isDraggingHeader = true
                frame.origin = CGPoint(
                    x: committedOrigin.x + value.translation.width,
                    y: committedOrigin.y + value.translation.height
                )
            }
            .onEnded { _ in
                committedOrigin = frame.origin
                isDraggingHeader = false
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
        .gesture(resizeGesture)
    }

    private var resizeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                isResizing = true
                // Origin stays fixed; growing the size while `.position` tracks
                // `midX/midY` keeps the top-left anchored, so the box expands
                // toward the bottom-right handle.
                frame.size = CGSize(
                    width: max(minSize.width, committedSize.width + value.translation.width),
                    height: max(minSize.height, committedSize.height + value.translation.height)
                )
            }
            .onEnded { _ in
                committedSize = frame.size
                isResizing = false
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
