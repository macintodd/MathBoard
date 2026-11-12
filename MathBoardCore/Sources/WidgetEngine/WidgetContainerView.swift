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
#if os(iOS)
import UIKit
#endif

// MARK: - WidgetWebView (cross-platform WKWebView wrapper)

/// A thin SwiftUI wrapper around `WKWebView` that live-renders an HTML/JS string
/// and reloads only when that string actually changes. Shared by both the editor
/// preview and the floating container.
struct WidgetWebView {
    /// The raw HTML/JS source to render.
    let htmlString: String
    /// Optional directory for relative media URLs embedded in the HTML.
    let baseURL: URL?
    /// When true, the WKWebView is kept opaque so the GPU video compositor can
    /// route decoded video frames correctly. Transparent WKWebViews on an
    /// external UIWindowScene render video audio-only with a black frame.
    let isExternalDisplay: Bool

    init(htmlString: String, baseURL: URL? = nil, isExternalDisplay: Bool = false) {
        self.htmlString = htmlString
        self.baseURL = baseURL
        self.isExternalDisplay = isExternalDisplay
    }

    /// Builds and configures a `WKWebView`. Transparent on the primary display;
    /// opaque on the external display so video compositing works correctly.
    @MainActor
    fileprivate func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        #if os(iOS)
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        #endif
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = false
        #if os(iOS)
        if isExternalDisplay {
            // Opaque keeps the GPU video compositor on the external display's
            // layer tree. HTML content supplies its own background (#111).
            webView.isOpaque = true
            webView.backgroundColor = .black
            webView.scrollView.backgroundColor = .black
        } else {
            webView.isOpaque = false
            webView.backgroundColor = .clear
            webView.scrollView.backgroundColor = .clear
        }
        webView.scrollView.bounces = false
        #elseif os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
        #endif
        return webView
    }

    /// Reloads the web view only when the source differs from what was last
    /// loaded, so typing in the editor doesn't thrash the renderer.
    @MainActor
    fileprivate func reloadIfNeeded(_ webView: WKWebView, coordinator: Coordinator) {
        guard coordinator.loadedHTML != htmlString || coordinator.loadedBaseURL != baseURL else { return }
        coordinator.loadedHTML = htmlString
        coordinator.loadedBaseURL = baseURL
        if let baseURL, loadFileBackedHTML(in: webView, baseURL: baseURL, coordinator: coordinator) {
            return
        }
        webView.loadHTMLString(htmlString, baseURL: baseURL)
    }

    @MainActor
    private func loadFileBackedHTML(in webView: WKWebView, baseURL: URL, coordinator: Coordinator) -> Bool {
        do {
            try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
            let htmlURL = baseURL.appendingPathComponent(
                ".widget-webview-\(coordinator.htmlFileID.uuidString).html",
                isDirectory: false
            )
            try htmlString.write(to: htmlURL, atomically: true, encoding: .utf8)
            coordinator.loadedHTMLFileURL = htmlURL
            webView.loadFileURL(htmlURL, allowingReadAccessTo: baseURL)
            return true
        } catch {
            return false
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Tracks the last-loaded HTML and handles WKWebView process recovery.
    final class Coordinator: NSObject, WKNavigationDelegate {
        nonisolated override init() { super.init() }
        let htmlFileID = UUID()
        var loadedHTML: String?
        var loadedBaseURL: URL?
        var loadedHTMLFileURL: URL?
        /// Called when the web content process is killed (memory pressure, crash).
        /// Set in updateUIView/updateNSView so it always captures current HTML.
        var onProcessTerminated: ((WKWebView) -> Void)?

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            // Force reloadIfNeeded to re-run on next SwiftUI update pass.
            loadedHTML = nil
            loadedBaseURL = nil
            // Reload immediately so the widget recovers without waiting for
            // another SwiftUI state change to trigger updateUIView.
            onProcessTerminated?(webView)
        }
    }
}

#if os(iOS)
extension WidgetWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let webView = makeWebView()
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onProcessTerminated = { [htmlString, baseURL] wv in
            wv.loadHTMLString(htmlString, baseURL: baseURL)
        }
        reloadIfNeeded(webView, coordinator: context.coordinator)
    }
}
#elseif os(macOS)
extension WidgetWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let webView = makeWebView()
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onProcessTerminated = { [htmlString, baseURL] wv in
            wv.loadHTMLString(htmlString, baseURL: baseURL)
        }
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
    private let onMathInputRequested: (@MainActor (WidgetMathInputKeypadRequest) -> Void)?
    private let onImageInsertionRequested: (@MainActor (WidgetCanvasImageInsertionRequest) -> Void)?
    private let gearConfiguration: WidgetGearConfiguration?
    private let widgetAssetBaseURL: URL?
    private let isExternalDisplay: Bool

    @Environment(\.widgetSubmit) private var widgetSubmit

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
    @GestureState private var isHeaderGestureActive = false
    @GestureState private var isResizeGestureActive = false

    private let headerHeight: CGFloat = 34
    private let externalVideoContentAlignmentOffset: CGFloat = 30
    private let externalVideoHorizontalInset: CGFloat = 15
    private let handleSize: CGFloat = 22
    private let minSize = CGSize(width: 200, height: 160)

    public init(
        widget: Binding<WidgetObject>,
        scoreSheet: WidgetActivityScoreSheet? = nil,
        allowsPinning: Bool = true,
        onEditWidget: (() -> Void)? = nil,
        onDeleteWidget: (() -> Void)? = nil,
        onInteractionChanged: ((Bool) -> Void)? = nil,
        onDisplayFrameChanged: ((CGRect?) -> Void)? = nil,
        onMathInputRequested: (@MainActor (WidgetMathInputKeypadRequest) -> Void)? = nil,
        onImageInsertionRequested: (@MainActor (WidgetCanvasImageInsertionRequest) -> Void)? = nil,
        gearConfiguration: WidgetGearConfiguration? = nil,
        widgetAssetBaseURL: URL? = nil,
        isExternalDisplay: Bool = false
    ) {
        _widget = widget
        self.scoreSheet = scoreSheet
        self.allowsPinning = allowsPinning
        self.onEditWidget = onEditWidget
        self.onDeleteWidget = onDeleteWidget
        self.onInteractionChanged = onInteractionChanged
        self.onDisplayFrameChanged = onDisplayFrameChanged
        self.onMathInputRequested = onMathInputRequested
        self.onImageInsertionRequested = onImageInsertionRequested
        self.gearConfiguration = gearConfiguration
        self.widgetAssetBaseURL = widgetAssetBaseURL
        self.isExternalDisplay = isExternalDisplay
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
        self.onMathInputRequested = nil
        self.onImageInsertionRequested = nil
        self.gearConfiguration = nil
        self.widgetAssetBaseURL = nil
        self.isExternalDisplay = false
        _frame = State(initialValue: widget.frame)
        _committedOrigin = State(initialValue: widget.frame.origin)
        _committedSize = State(initialValue: widget.frame.size)
    }

    public var body: some View {
        if isExternalVideoWidget {
            externalVideoBody
                .position(x: frame.midX, y: frame.midY)
                .onChange(of: widget.frame) { _, newFrame in
                    guard newFrame != frame else { return }
                    frame = newFrame
                    committedOrigin = newFrame.origin
                    committedSize = newFrame.size
                }
                .onAppear {
                    frame = widget.frame
                    committedOrigin = widget.frame.origin
                    committedSize = widget.frame.size
                    onDisplayFrameChanged?(nil)
                }
        } else {
            VStack(spacing: 0) {
                if !isExternalDisplay {
                    header
                        .zIndex(2)
                }
                renderedContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .clipped()
                    .zIndex(1)
            }
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .overlay(alignment: .bottomTrailing) {
                if !widget.isPinnedToCanvas && !isExternalDisplay {
                    resizeHandle
                        .zIndex(3)
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
                releaseInteractionLock()
            }
            .onChange(of: isHeaderGestureActive) { _, isActive in
                if !isActive, isDraggingHeader {
                    finishHeaderDrag()
                }
            }
            .onChange(of: isResizeGestureActive) { _, isActive in
                if !isActive, isResizing {
                    finishResize()
                }
            }
        }
    }

    private var externalVideoBody: some View {
        let contentTopOffset = headerHeight + externalVideoContentAlignmentOffset
        let contentHeight = max(frame.height - contentTopOffset, 1)
        let contentWidth = max(frame.width - externalVideoHorizontalInset * 2, 1)

        return ZStack(alignment: .topLeading) {
            renderedContent
                .frame(width: contentWidth, height: contentHeight)
                .background(Color.white)
                .clipped()
                .offset(x: externalVideoHorizontalInset, y: contentTopOffset)
        }
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var renderedContent: some View {
        if let builtInInteractiveKind = widget.builtInInteractiveKind {
            builtInInteractiveView(for: builtInInteractiveKind)
        } else if let document = widget.activityDocument {
            WidgetActivityRenderer(
                document: document,
                scoreSheet: scoreSheet,
                onEditWidget: onEditWidget,
                onMathInputRequested: onMathInputRequested,
                gearConfiguration: effectiveGearConfiguration(for: document),
                runtimeState: activityRuntimeStateBinding(for: document)
            )
        } else if let videoURL = videoAssetURL {
            nativeVideoView(url: videoURL)
        } else {
            WidgetWebView(htmlString: effectiveCodeString, baseURL: widgetAssetBaseURL, isExternalDisplay: isExternalDisplay)
        }
    }

    /// Routes to the appropriate video view for each display.
    /// Both share one AVPlayer from VideoPlayerRegistry for frame-perfect sync.
    @ViewBuilder
    private func nativeVideoView(url: URL) -> some View {
        let player = VideoPlayerRegistry.shared.player(for: widget.id, url: url)
        if isExternalDisplay {
            // Bare video layer — no controls, no chrome. Frames are composited
            // directly by AVPlayerLayer on the external display's CALayer tree.
            AVPlayerLayerView(player: player, backgroundColor: .white)
                .background(Color.white)
        } else {
            WidgetVideoPlayerView(player: player)
        }
    }

    private var isExternalVideoWidget: Bool {
        isExternalDisplay && videoAssetURL != nil
    }

    /// Parses the video file URL from a movie widget's HTML.
    /// Returns nil for non-video widgets (GIFs, custom HTML, built-ins).
    private var videoAssetURL: URL? {
        guard let baseURL = widgetAssetBaseURL,
              widget.codeString.contains(#"id="media""#) else { return nil }
        let html = widget.codeString
        let prefix = #"<source src=""#
        guard let range = html.range(of: prefix + #"[^"]+"#, options: .regularExpression) else { return nil }
        let tag = String(html[range])
        guard tag.hasPrefix(prefix) else { return nil }
        let filename = String(tag.dropFirst(prefix.count))
        guard !filename.isEmpty else { return nil }
        return baseURL.appendingPathComponent(filename)
    }

    /// Strips teacher-only chrome from HTML widgets on the external display.
    /// Video widgets bypass this entirely — they use AVPlayerLayerView instead.
    private var effectiveCodeString: String {
        guard isExternalDisplay else { return widget.codeString }
        let css = "<style>.loop-toggle{display:none!important}</style>"
        var html = widget.codeString
        if html.contains("</head>") {
            html = html.replacingOccurrences(of: "</head>", with: "\(css)</head>")
        }
        return html
    }

    private func effectiveGearConfiguration(for document: ActivityWidgetDocument) -> WidgetGearConfiguration {
        let widgetBinding = $widget
        let widgetID = widget.id
        var config = gearConfiguration ?? WidgetGearConfiguration(questionCount: questionCount(for: document))
        config.widgetID = widgetID
        config.questionCount = questionCount(for: document)
        config.tags = widget.tags
        config.requiresStudentWork = widget.requiresStudentWork
        if config.onTagsChanged == nil {
            config.onTagsChanged = { newTags in
                widgetBinding.wrappedValue.tags = newTags
            }
        }
        if config.onRequiresStudentWorkChanged == nil {
            config.onRequiresStudentWorkChanged = { value in
                widgetBinding.wrappedValue.requiresStudentWork = value
            }
        }
        if let widgetSubmit {
            config.isWidgetSubmitted = widgetSubmit.isWidgetSubmitted(widgetID)
            config.isWidgetReset = widgetSubmit.isWidgetReset(widgetID)
            config.onSubmitWidget = { widgetSubmit.onSubmitWidget(widgetID) }
            config.onResetAfterSubmit = { widgetSubmit.onResetAfterSubmit(widgetID) }
        }
        return config
    }

    private func questionCount(for document: ActivityWidgetDocument) -> Int {
        switch document.activity {
        case .multipleChoice, .fillInTheBlank:
            return document.questions.count
        case .trivialPursuit:
            return document.categories?.reduce(0) { $0 + $1.questions.count } ?? 0
        }
    }

    @ViewBuilder
    private func builtInInteractiveView(for kind: BuiltInInteractiveKind) -> some View {
        switch kind {
        case .inequalitiesExplorer:
            CompoundInequalitiesInteractiveView(
                state: InequalityExplorerStateRegistry.state(for: widget) { encodedState in
                    if let encodedState {
                        widget.builtInRuntimeState[InequalityExplorerState.runtimeStateKey] = encodedState
                    } else {
                        widget.builtInRuntimeState.removeValue(forKey: InequalityExplorerState.runtimeStateKey)
                    }
                }
            )
        case .countdownTimer:
            CountdownTimerInteractiveView(
                state: CountdownTimerStateRegistry.state(for: widget.id)
            )
        case .randomNumberGenerator:
            RandomNumberGeneratorInteractiveView(
                state: RandomNumberGeneratorStateRegistry.state(for: widget.id)
            )
        case .coordinateGridGenerator:
            CoordinateGridGeneratorInteractiveView(
                state: CoordinateGridGeneratorStateRegistry.state(for: widget.id),
                onMathInputRequested: onMathInputRequested,
                onImageInsertionRequested: onImageInsertionRequested
            )
        case .functionTransformationExplorer:
            FunctionTransformationExplorerInteractiveView(
                state: FunctionTransformationExplorerStateRegistry.state(for: widget.id)
            )
        case .matchGrid:
            MatchGridInteractiveView(
                state: MatchGridStateRegistry.state(for: widget.id)
            )
        case .actDailyPractice:
            ACTDailyPracticeInteractiveView(
                state: ACTDailyPracticeStateRegistry.state(for: widget) { encodedState in
                    if let encodedState {
                        widget.builtInRuntimeState[ACTDailyPracticeState.runtimeStateKey] = encodedState
                    } else {
                        widget.builtInRuntimeState.removeValue(forKey: ACTDailyPracticeState.runtimeStateKey)
                    }
                }
            )
        case .quadraticWebApplet:
            WebAppletInteractiveView(
                resource: .quadraticSlider,
                runtimeState: WebAppletStateRegistry.state(for: widget.id),
                isExternalDisplay: isExternalDisplay
            )
        case .domainRangeWebApplet:
            WebAppletInteractiveView(
                resource: .domainRangeFromGraphs,
                runtimeState: WebAppletStateRegistry.state(for: widget.id),
                isExternalDisplay: isExternalDisplay
            )
        case .analizingGraphs1WebApplet:
            WebAppletInteractiveView(
                resource: .analizingGraphs1,
                runtimeState: WebAppletStateRegistry.state(for: widget.id),
                isExternalDisplay: isExternalDisplay
            )
        case .projectileMotionGraphAnalysisWebApplet:
            WebAppletInteractiveView(
                resource: .projectileMotionGraphAnalysis,
                runtimeState: WebAppletStateRegistry.state(for: widget.id),
                isExternalDisplay: isExternalDisplay
            )
        case .constantRateWebApplet:
            WebAppletInteractiveView(
                resource: .constantRateDemo,
                runtimeState: WebAppletStateRegistry.state(for: widget.id),
                isExternalDisplay: isExternalDisplay
            )
        case .completingTheSquareWebApplet:
            WebAppletInteractiveView(
                resource: .completingTheSquareLab,
                runtimeState: WebAppletStateRegistry.state(for: widget.id),
                isExternalDisplay: isExternalDisplay
            )
        case .andOrAttributeFilterWebApplet:
            WebAppletInteractiveView(
                resource: .andOrAttributeFilter,
                runtimeState: WebAppletStateRegistry.state(for: widget.id),
                isExternalDisplay: isExternalDisplay
            )
        case .andOrInequalityNumberLineWebApplet:
            WebAppletInteractiveView(
                resource: .andOrInequalityNumberLine,
                runtimeState: WebAppletStateRegistry.state(for: widget.id),
                isExternalDisplay: isExternalDisplay
            )
        case .compoundInequalityGraphingDemoWebApplet:
            WebAppletInteractiveView(
                resource: .compoundInequalityGraphingDemo,
                runtimeState: WebAppletStateRegistry.state(for: widget.id),
                isExternalDisplay: isExternalDisplay
            )
        case .absoluteValueAsDemonstrationWebApplet:
            WebAppletInteractiveView(
                resource: .absoluteValueAsDistance,
                runtimeState: WebAppletStateRegistry.state(for: widget.id),
                isExternalDisplay: isExternalDisplay
            )
        case .introPointSlopeWebApplet:
            RemoteWebAppletInteractiveView(
                url: URL(string: "https://www.macintodd.net/apps/intro-point-slope")!,
                runtimeState: WebAppletStateRegistry.state(for: widget.id),
                isExternalDisplay: isExternalDisplay
            )
        case .writeLinearEquationWebApplet:
            RemoteWebAppletInteractiveView(
                url: URL(string: "https://www.macintodd.net/apps/write-linear-equation/teacher")!,
                runtimeState: WebAppletStateRegistry.state(for: widget.id),
                isExternalDisplay: isExternalDisplay
            )
        case .parallelPerpendicularWebApplet:
            RemoteWebAppletInteractiveView(
                url: URL(string: "https://www.macintodd.net/apps/beta/parallel-perpendicular-lesson")!,
                runtimeState: WebAppletStateRegistry.state(for: widget.id),
                isExternalDisplay: isExternalDisplay
            )
        }
    }

    private func activityRuntimeStateBinding(for document: ActivityWidgetDocument) -> Binding<WidgetActivityRuntimeState> {
        Binding {
            widget.activityRuntimeState ?? WidgetActivityRuntimeState(
                multipleChoice: WidgetMultipleChoiceRuntimeState.initial(for: document),
                fillInTheBlank: WidgetFillInTheBlankRuntimeState.initial(for: document),
                interactiveParts: WidgetInteractivePartsRuntimeState()
            )
        } set: { newValue in
            widget.activityRuntimeState = newValue
        }
    }

    // MARK: Header (drag to move)

    private var header: some View {
        headerContent
            .padding(.horizontal, 12)
            .frame(height: headerHeight)
            .frame(maxWidth: .infinity)
            .background(.thinMaterial)
            .contentShape(Rectangle())
            #if os(iOS)
            .overlay(alignment: .leading) {
                if !widget.isPinnedToCanvas {
                    WidgetPanGestureCaptureView(
                        cancelsTouchesInView: false,
                        onChanged: handleHeaderDragChanged,
                        onEnded: finishHeaderDrag
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.trailing, headerControlExclusionWidth)
                }
            }
            #else
            .highPriorityGesture(headerDragGesture)
            #endif
    }

    private var headerControlExclusionWidth: CGFloat {
        var width: CGFloat = 28
        if allowsPinning { width += 32 }
        if onDeleteWidget != nil { width += 32 }
        return width
    }

    private var headerContent: some View {
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
    }

    private var headerDragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .updating($isHeaderGestureActive) { _, isActive, _ in
                isActive = true
            }
            .onChanged { value in
                handleHeaderDragChanged(value.translation)
            }
            .onEnded { _ in
                finishHeaderDrag()
            }
    }

    private func handleHeaderDragChanged(_ translation: CGSize) {
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
                x: base.x + translation.width,
                y: base.y + translation.height
            )
            onDisplayFrameChanged?(frame)
        }
    }

    private func finishHeaderDrag() {
        guard isDraggingHeader else { return }
        let finalFrame = frame
        committedOrigin = finalFrame.origin
        dragStartOrigin = nil
        isDraggingHeader = false
        onInteractionChanged?(false)
        onDisplayFrameChanged?(nil)
        widget.frame = finalFrame
    }

    private func releaseInteractionLock() {
        dragStartOrigin = nil
        resizeStartSize = nil
        isDraggingHeader = false
        isResizing = false
        onDisplayFrameChanged?(nil)
        onInteractionChanged?(false)
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
        #if os(iOS)
        .overlay {
            WidgetPanGestureCaptureView(
                cancelsTouchesInView: true,
                onChanged: handleResizeChanged,
                onEnded: finishResize
            )
        }
        #else
        .highPriorityGesture(resizeGesture)
        #endif
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .updating($isResizeGestureActive) { _, isActive, _ in
                isActive = true
            }
            .onChanged { value in
                handleResizeChanged(value.translation)
            }
            .onEnded { _ in
                finishResize()
            }
    }

    private func handleResizeChanged(_ translation: CGSize) {
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
                width: max(minSize.width, base.width + translation.width),
                height: max(minSize.height, base.height + translation.height)
            )
            onDisplayFrameChanged?(frame)
        }
    }

    private func finishResize() {
        guard isResizing else { return }
        let finalFrame = frame
        committedSize = finalFrame.size
        resizeStartSize = nil
        isResizing = false
        onInteractionChanged?(false)
        onDisplayFrameChanged?(nil)
        widget.frame = finalFrame
    }
}

#if os(iOS)
@MainActor
private struct WidgetPanGestureCaptureView: UIViewRepresentable {
    var cancelsTouchesInView: Bool
    var onChanged: (CGSize) -> Void
    var onEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChanged: onChanged, onEnded: onEnded)
    }

    func makeUIView(context: Context) -> UIView {
        let view = WidgetPanGestureCaptureUIView()
        view.backgroundColor = .clear
        view.isOpaque = false
        let recognizer = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        recognizer.minimumNumberOfTouches = 1
        recognizer.maximumNumberOfTouches = 1
        recognizer.cancelsTouchesInView = cancelsTouchesInView
        view.addGestureRecognizer(recognizer)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        view.gestureRecognizers?.compactMap { $0 as? UIPanGestureRecognizer }.forEach { recognizer in
            recognizer.cancelsTouchesInView = cancelsTouchesInView
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var onChanged: (CGSize) -> Void
        var onEnded: () -> Void

        init(onChanged: @escaping (CGSize) -> Void, onEnded: @escaping () -> Void) {
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began, .changed:
                let translation = recognizer.translation(in: recognizer.view)
                onChanged(CGSize(width: translation.x, height: translation.y))
            case .ended, .cancelled, .failed:
                onEnded()
                recognizer.setTranslation(.zero, in: recognizer.view)
            default:
                break
            }
        }
    }
}

private final class WidgetPanGestureCaptureUIView: UIView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if let touches = event?.allTouches, touches.count > 1 {
            return false
        }
        return bounds.contains(point)
    }
}
#endif

// MARK: - Preview

#Preview("Widget Container") {
    ZStack {
        // A light "whiteboard" backdrop so the floating object reads clearly.
        Color(white: 0.96).ignoresSafeArea()

        WidgetContainerView(widget: .sample)
    }
}
