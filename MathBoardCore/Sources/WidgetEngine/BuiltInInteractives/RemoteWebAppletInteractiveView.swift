//
//  RemoteWebAppletInteractiveView.swift
//  WidgetEngine
//
//  Loads a remote URL in a WKWebView while injecting the same MathBoard
//  applet bridge used by bundled HTML applets. The teacher-canvas view
//  receives state via window.MathBoardApplet.publishState(); the external
//  display view applies it via window.MathBoardApplet.applyState().
//

import Foundation
import SwiftUI
import WebKit

public struct RemoteWebAppletInteractiveView: View {
    private let url: URL
    private let runtimeState: WebAppletRuntimeState
    private let isExternalDisplay: Bool

    public init(
        url: URL,
        runtimeState: WebAppletRuntimeState,
        isExternalDisplay: Bool = false
    ) {
        self.url = url
        self.runtimeState = runtimeState
        self.isExternalDisplay = isExternalDisplay
    }

    public var body: some View {
        RemoteWebAppletWebView(
            url: url,
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

private struct RemoteWebAppletWebView {
    let url: URL
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
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
#elseif os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
#endif
        return webView
    }

    fileprivate func updateWebView(_ webView: WKWebView, coordinator: Coordinator) {
        if coordinator.loadedURL != url {
            coordinator.loadedURL = url
            coordinator.appliedRevision = -1
            webView.load(URLRequest(url: url))
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

    // Same bridge script as WebAppletInteractiveView — compatible protocol.
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
        var loadedURL: URL?
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
            let escapedState = RemoteWebAppletWebView.javascriptStringLiteral(pendingStateJSON)
            webView.evaluateJavaScript("window.MathBoardApplet && window.MathBoardApplet.applyState(JSON.parse(\(escapedState)));")
            self.pendingStateJSON = nil
        }
    }
}

#if os(iOS)
extension RemoteWebAppletWebView: UIViewRepresentable {
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
extension RemoteWebAppletWebView: NSViewRepresentable {
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
