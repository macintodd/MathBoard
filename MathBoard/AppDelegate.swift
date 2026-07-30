//
//  AppDelegate.swift
//  MathBoard
//
//  UIKit app delegate — exists only to dispatch external-display scenes
//  to a dedicated scene delegate. SwiftUI handles everything else via
//  `WindowGroup`, but UIScene's external-display role requires a UIKit
//  scene delegate, which is registered here.
//

#if canImport(UIKit)

import UIKit
import SwiftUI
import Documents
import OSLog

final class AppDelegate: NSObject, UIApplicationDelegate {

    private let logger = Logger(subsystem: "MathBoard", category: "ExternalDisplay")

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        print("MATHBOARD_EXTERNAL_DISPLAY: application did finish launching")
        LegacyExternalDisplayWindowController.shared.startObservingScreens()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: connectingSceneSession.role == .windowExternalDisplayNonInteractive
                ? "External Display"
                : "Default",
            sessionRole: connectingSceneSession.role
        )

        if connectingSceneSession.role == .windowExternalDisplayNonInteractive {
            logger.info("Configuring external display scene")
            print("MATHBOARD_EXTERNAL_DISPLAY: configuring external display scene")
            configuration.delegateClass = ExternalDisplaySceneDelegate.self
        } else {
            logger.debug("Configuring scene role: \(String(describing: connectingSceneSession.role), privacy: .public)")
        }

        return configuration
    }
}

@MainActor
final class LegacyExternalDisplayWindowController {

    static let shared = LegacyExternalDisplayWindowController()

    private let logger = Logger(subsystem: "MathBoard", category: "ExternalDisplay")
    private var externalWindow: UIWindow?
    private var isObservingScreens = false
    private var isSceneManaged = false

    func startObservingScreens() {
        guard !isObservingScreens else { return }
        if #available(iOS 27.0, *) {
            print("MATHBOARD_EXTERNAL_DISPLAY: legacy external screen fallback disabled on iOS 27+")
            return
        }
        isObservingScreens = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidConnect(_:)),
            name: UIScreen.didConnectNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidDisconnect(_:)),
            name: UIScreen.didDisconnectNotification,
            object: nil
        )

        attachFallbackWindowIfNeeded(reason: "launch")
    }

    func setSceneManagedExternalDisplay(_ sceneManaged: Bool) {
        isSceneManaged = sceneManaged
        if sceneManaged {
            closeFallbackWindow(reason: "scene connected")
        } else {
            attachFallbackWindowIfNeeded(reason: "scene disconnected")
        }
    }

    private func attachFallbackWindowIfNeeded(reason: String) {
        guard !isSceneManaged, externalWindow == nil else { return }
        if #available(iOS 27.0, *) {
            DisplayBroker.shared.externalDisplayConnectionRoute = .none
            print("MATHBOARD_EXTERNAL_DISPLAY: legacy external screen fallback disabled reason=\(reason)")
            return
        }
        guard let screen = UIScreen.screens.first(where: { $0 !== UIScreen.main }) else {
            DisplayBroker.shared.externalDisplayConnectionRoute = .none
            print("MATHBOARD_EXTERNAL_DISPLAY: no legacy external screen found reason=\(reason)")
            return
        }

        let window = UIWindow(frame: screen.bounds)
        window.screen = screen
        window.rootViewController = UIHostingController(rootView: ExternalCanvasView())
        externalWindow = window
        window.makeKeyAndVisible()
        DisplayBroker.shared.isExternalDisplayConnected = true
        DisplayBroker.shared.externalDisplayConnectionRoute = .legacyScreen

        logger.info("Legacy external display window attached: \(String(describing: screen), privacy: .public)")
        print("MATHBOARD_EXTERNAL_DISPLAY: legacy external window attached reason=\(reason) screen=\(screen)")
    }

    private func closeFallbackWindow(reason: String) {
        guard let externalWindow else { return }
        externalWindow.isHidden = true
        externalWindow.rootViewController = nil
        self.externalWindow = nil
        DisplayBroker.shared.isExternalDisplayConnected = false
        DisplayBroker.shared.externalDisplayConnectionRoute = .none

        logger.info("Legacy external display window closed")
        print("MATHBOARD_EXTERNAL_DISPLAY: legacy external window closed reason=\(reason)")
    }

    @objc private func screenDidConnect(_ notification: Notification) {
        attachFallbackWindowIfNeeded(reason: "screen connected")
    }

    @objc private func screenDidDisconnect(_ notification: Notification) {
        closeFallbackWindow(reason: "screen disconnected")
    }

    private init() {}
}

#endif
