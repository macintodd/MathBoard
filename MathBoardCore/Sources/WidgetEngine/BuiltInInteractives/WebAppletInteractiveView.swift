//
//  WebAppletInteractiveView.swift
//  WidgetEngine
//
//  Teacher-demo web applet support. Local bundled HTML/JS applets run inside a
//  WKWebView on the teacher canvas and mirror state to the external display
//  through a small JavaScript bridge.
//

import Foundation
import Observation
import SwiftUI
import WebKit

@MainActor
@Observable
public final class WebAppletRuntimeState {
    public var stateJSON: String
    public var revision: Int

    public init(stateJSON: String = "{}", revision: Int = 0) {
        self.stateJSON = stateJSON
        self.revision = revision
    }

    public func publishTeacherState(_ json: String) {
        guard stateJSON != json else { return }
        stateJSON = json
        revision += 1
    }
}

@MainActor
public enum WebAppletStateRegistry {
    private static var states: [UUID: WebAppletRuntimeState] = [:]

    public static func state(for id: UUID) -> WebAppletRuntimeState {
        if let existing = states[id] { return existing }
        let state = WebAppletRuntimeState()
        states[id] = state
        return state
    }

    public static func removeState(for id: UUID) {
        states.removeValue(forKey: id)
    }
}

public enum WebAppletResource: String, Sendable {
    case quadraticSlider = "quadratic-slider"
    case domainRangeFromGraphs = "domain-range-from-graphs"
    case analizingGraphs1 = "analizing-graphs-1"
    case projectileMotionGraphAnalysis = "projectile-motion-graph-analysis"
    case constantRateDemo = "constant-rate-demo"
    case completingTheSquareLab = "completing-the-square-lab"
    case andOrAttributeFilter = "and-or-attribute-filter"
    case andOrInequalityNumberLine = "and-or-inequality-number-line"
    case compoundInequalityGraphingDemo = "compound-inequality-graphing-demo"
    case absoluteValueAsDistance = "absolute-value-as-distance"

    public var displayName: String {
        switch self {
        case .quadraticSlider:
            return "Quadratic Web Applet"
        case .domainRangeFromGraphs:
            return "Domain and Range from Graphs"
        case .analizingGraphs1:
            return "Analizing Graphs 1"
        case .projectileMotionGraphAnalysis:
            return "Projectile Motion Graph Analysis"
        case .constantRateDemo:
            return "Constant Rate Demo"
        case .completingTheSquareLab:
            return "Completing the Square Lab"
        case .andOrAttributeFilter:
            return "AND / OR Attribute Filter"
        case .andOrInequalityNumberLine:
            return "AND / OR Inequality Number Lines"
        case .compoundInequalityGraphingDemo:
            return "Graphing Compound Inequalities Demo"
        case .absoluteValueAsDistance:
            return "Absolute Value as Distance"
        }
    }

    public var description: String {
        switch self {
        case .quadraticSlider:
            return "Local HTML/JavaScript demo for exploring y = a(x - h)^2 + k with mirrored external-display state."
        case .domainRangeFromGraphs:
            return "Local HTML/JavaScript demo for exploring domain and range from graphs with mirrored external-display state."
        case .analizingGraphs1:
            return "Local HTML/JavaScript demo for exploring average rate of change, increasing and decreasing intervals, extrema, and concavity with mirrored external-display state."
        case .projectileMotionGraphAnalysis:
            return "Local HTML/JavaScript demo for exploring projectile motion through a ball-toss height-time graph, average velocity, concavity, and gravity with mirrored external-display state."
        case .constantRateDemo:
            return "Local HTML/JavaScript demo for exploring constant-rate problems (y = b + r·m) through interactive ice-cream and streaming-service scenarios with mirrored external-display state."
        case .completingTheSquareLab:
            return "Local HTML/JavaScript demo for exploring completing the square with an area model, coefficient sliders, and mirrored external-display state."
        case .andOrAttributeFilter:
            return "Local HTML/JavaScript demo for introducing AND and OR by filtering shape attributes before moving to inequalities."
        case .andOrInequalityNumberLine:
            return "Local HTML/JavaScript demo for manually graphing two solved inequalities and combining their solution sets with AND or OR on aligned number lines."
        case .compoundInequalityGraphingDemo:
            return "Interactive teacher demo: graph Condition A, Condition B, and their combined AND/OR solution on three aligned number lines with draggable boundary points and arrow tips."
        case .absoluteValueAsDistance:
            return "Six-phase teacher-led demonstration guiding students to discover that absolute value measures distance on a number line, using animated racing cars, a distance bar, and progressive equation reveals."
        }
    }

    public var tags: [String] {
        switch self {
        case .quadraticSlider:
            return ["web applet", "demo", "quadratics", "transformations", "external display"]
        case .domainRangeFromGraphs:
            return ["web applet", "demo", "domain", "range", "graphs", "external display"]
        case .analizingGraphs1:
            return ["web applet", "demo", "average rate of change", "concavity", "graphs", "external display"]
        case .projectileMotionGraphAnalysis:
            return ["web applet", "demo", "projectile motion", "height", "time", "average velocity", "concavity", "gravity", "external display"]
        case .constantRateDemo:
            return ["web applet", "demo", "constant rate", "linear equations", "slope", "y-intercept", "external display"]
        case .completingTheSquareLab:
            return ["web applet", "demo", "quadratics", "completing the square", "vertex form", "area model", "external display"]
        case .andOrAttributeFilter:
            return ["web applet", "demo", "and", "or", "logic", "attributes", "inequalities", "external display"]
        case .andOrInequalityNumberLine:
            return ["web applet", "demo", "and", "or", "compound inequalities", "number line", "solution sets", "external display"]
        case .compoundInequalityGraphingDemo:
            return ["web applet", "demo", "compound inequalities", "number line", "and", "or", "boundary point", "ray", "solution sets", "external display"]
        case .absoluteValueAsDistance:
            return ["web applet", "demo", "absolute value", "distance", "number line", "racing cars", "conceptual", "algebra", "external display"]
        }
    }

    public static func resource(for kind: BuiltInInteractiveKind) -> WebAppletResource? {
        switch kind {
        case .quadraticWebApplet:
            return .quadraticSlider
        case .domainRangeWebApplet:
            return .domainRangeFromGraphs
        case .analizingGraphs1WebApplet:
            return .analizingGraphs1
        case .projectileMotionGraphAnalysisWebApplet:
            return .projectileMotionGraphAnalysis
        case .constantRateWebApplet:
            return .constantRateDemo
        case .completingTheSquareWebApplet:
            return .completingTheSquareLab
        case .andOrAttributeFilterWebApplet:
            return .andOrAttributeFilter
        case .andOrInequalityNumberLineWebApplet:
            return .andOrInequalityNumberLine
        case .compoundInequalityGraphingDemoWebApplet:
            return .compoundInequalityGraphingDemo
        case .absoluteValueAsDemonstrationWebApplet:
            return .absoluteValueAsDistance
        case .inequalitiesExplorer, .countdownTimer, .randomNumberGenerator, .coordinateGridGenerator,
             .functionTransformationExplorer, .matchGrid, .actDailyPractice, .introPointSlopeWebApplet,
             .writeLinearEquationWebApplet, .parallelPerpendicularWebApplet:
            return nil
        }
    }

    public func htmlSource() -> String {
        let nestedURL = Bundle.module.url(
            forResource: rawValue,
            withExtension: "html",
            subdirectory: "WebApplets"
        )
        let flatURL = Bundle.module.url(forResource: rawValue, withExtension: "html")
        guard let url = nestedURL ?? flatURL,
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            return Self.fallbackHTML
        }
        return source
    }

    private static let fallbackHTML = """
    <!doctype html>
    <html>
    <head>
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <style>
        body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, sans-serif; background: #f8fafc; color: #1f2937; }
        main { display: grid; place-items: center; height: 100vh; text-align: center; padding: 24px; box-sizing: border-box; }
        h1 { margin: 0 0 8px; font-size: 28px; }
        p { margin: 0; font-size: 16px; color: #5f6b7a; }
      </style>
    </head>
    <body>
      <main>
        <section>
          <h1>Web Applet Missing</h1>
          <p>The bundled HTML resource could not be loaded.</p>
        </section>
      </main>
    </body>
    </html>
    """
}

public struct WebAppletInteractiveView: View {
    private let resource: WebAppletResource
    private let runtimeState: WebAppletRuntimeState
    private let isExternalDisplay: Bool

    public init(
        resource: WebAppletResource,
        runtimeState: WebAppletRuntimeState,
        isExternalDisplay: Bool = false
    ) {
        self.resource = resource
        self.runtimeState = runtimeState
        self.isExternalDisplay = isExternalDisplay
    }

    public var body: some View {
        WebAppletWebView(
            htmlString: resource.htmlSource(),
            stateJSON: runtimeState.stateJSON,
            stateRevision: runtimeState.revision,
            isExternalDisplay: isExternalDisplay,
            onTeacherStateChanged: { json in
                runtimeState.publishTeacherState(json)
            }
        )
        .background(Color(red: 0.96, green: 0.97, blue: 0.98))
    }
}

private struct WebAppletWebView {
    let htmlString: String
    let stateJSON: String
    let stateRevision: Int
    let isExternalDisplay: Bool
    let onTeacherStateChanged: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isExternalDisplay: isExternalDisplay,
            onTeacherStateChanged: onTeacherStateChanged
        )
    }

    fileprivate func makeWebView(coordinator: Coordinator) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.addUserScript(WKUserScript(
            source: Self.bridgeScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        contentController.add(coordinator, name: Self.stateMessageName)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        webView.allowsBackForwardNavigationGestures = false
        #if os(iOS)
        webView.scrollView.bounces = false
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        #elseif os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
        #endif
        return webView
    }

    fileprivate func updateWebView(_ webView: WKWebView, coordinator: Coordinator) {
        if coordinator.loadedHTML != htmlString {
            coordinator.loadedHTML = htmlString
            coordinator.appliedRevision = -1
            webView.loadHTMLString(htmlString, baseURL: nil)
            return
        }

        applyExternalStateIfNeeded(to: webView, coordinator: coordinator)
    }

    fileprivate func applyExternalStateIfNeeded(to webView: WKWebView, coordinator: Coordinator) {
        guard isExternalDisplay else { return }
        guard coordinator.appliedRevision != stateRevision else { return }
        coordinator.appliedRevision = stateRevision
        coordinator.pendingStateJSON = stateJSON
        let escapedState = Self.javascriptStringLiteral(stateJSON)
        webView.evaluateJavaScript("window.MathBoardApplet && window.MathBoardApplet.applyState(JSON.parse(\(escapedState)));") { _, _ in
            coordinator.pendingStateJSON = nil
        }
    }

    fileprivate static func dismantle(_ webView: WKWebView) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: stateMessageName)
        webView.navigationDelegate = nil
    }

    private static let stateMessageName = "mathBoardAppletState"

    private static let bridgeScript = """
    (function() {
      if (window.MathBoardApplet) { return; }
      window.MathBoardApplet = {
        publishState: function(state) {
          try {
            window.webkit.messageHandlers.mathBoardAppletState.postMessage(JSON.stringify(state || {}));
          } catch (error) {}
        },
        applyState: function(state) {
          if (typeof window.mathBoardAppletSetState === 'function') {
            window.mathBoardAppletSetState(state || {});
          }
        }
      };
    })();
    """

    private static func javascriptStringLiteral(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8) else {
            return "\"{}\""
        }
        return encoded
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var loadedHTML: String?
        var appliedRevision = -1
        var pendingStateJSON: String?
        private let isExternalDisplay: Bool
        private let onTeacherStateChanged: @MainActor (String) -> Void

        init(isExternalDisplay: Bool, onTeacherStateChanged: @escaping @MainActor (String) -> Void) {
            self.isExternalDisplay = isExternalDisplay
            self.onTeacherStateChanged = onTeacherStateChanged
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard !isExternalDisplay else { return }
            if let json = message.body as? String {
                onTeacherStateChanged(json)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard isExternalDisplay, let pendingStateJSON else { return }
            let escapedState = WebAppletWebView.javascriptStringLiteral(pendingStateJSON)
            webView.evaluateJavaScript("window.MathBoardApplet && window.MathBoardApplet.applyState(JSON.parse(\(escapedState)));")
            self.pendingStateJSON = nil
        }
    }
}

#if os(iOS)
extension WebAppletWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        makeWebView(coordinator: context.coordinator)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        updateWebView(webView, coordinator: context.coordinator)
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        dismantle(uiView)
    }
}
#elseif os(macOS)
extension WebAppletWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        makeWebView(coordinator: context.coordinator)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        updateWebView(webView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        dismantle(nsView)
    }
}
#endif
