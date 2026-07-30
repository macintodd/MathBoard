//
//  ExternalDisplaySceneDelegate.swift
//  MathBoard
//
//  Owns the second UIWindow that appears on a connected HDMI / AirPlay
//  display. Hosts a SwiftUI `ExternalCanvasView` which observes
//  `DisplayBroker.shared` and renders whatever the iPad is currently
//  drawing.
//

#if canImport(UIKit)

import UIKit
import SwiftUI
import Documents
import OSLog

final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {

    private let logger = Logger(subsystem: "MathBoard", category: "ExternalDisplay")
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else {
            logger.error("External display scene connection received a non-window scene")
            print("MATHBOARD_EXTERNAL_DISPLAY: non-window external scene received")
            return
        }

        logger.info("External display scene connected on screen: \(String(describing: windowScene.screen), privacy: .public)")
        print("MATHBOARD_EXTERNAL_DISPLAY: external scene connected screen=\(windowScene.screen)")

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: ExternalCanvasView())
        self.window = window
        window.makeKeyAndVisible()
        logger.info("External display window made key and visible")
        print("MATHBOARD_EXTERNAL_DISPLAY: external window made key and visible")

        Task { @MainActor in
            LegacyExternalDisplayWindowController.shared.setSceneManagedExternalDisplay(true)
            DisplayBroker.shared.isExternalDisplayConnected = true
            DisplayBroker.shared.externalDisplayConnectionRoute = .scene
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        logger.info("External display scene disconnected")
        print("MATHBOARD_EXTERNAL_DISPLAY: external scene disconnected")
        Task { @MainActor in
            DisplayBroker.shared.isExternalDisplayConnected = false
            DisplayBroker.shared.externalDisplayConnectionRoute = .none
            LegacyExternalDisplayWindowController.shared.setSceneManagedExternalDisplay(false)
        }
    }
}

#endif
