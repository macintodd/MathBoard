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

final class AppDelegate: NSObject, UIApplicationDelegate {

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
            configuration.delegateClass = ExternalDisplaySceneDelegate.self
        }

        return configuration
    }
}

#endif
