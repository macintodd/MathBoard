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

final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: ExternalCanvasView())
        window.isHidden = false
        self.window = window

        Task { @MainActor in
            DisplayBroker.shared.isExternalDisplayConnected = true
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        Task { @MainActor in
            DisplayBroker.shared.isExternalDisplayConnected = false
        }
    }
}

#endif
