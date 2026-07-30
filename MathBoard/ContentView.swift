//
//  ContentView.swift
//  MathBoard
//
//  Created by Shawn Todd on 6/18/26.
//

import SwiftUI
import Documents

#if os(iOS)
import UIKit
#endif

struct ContentView: View {
    @Environment(DocumentStore.self) private var documentStore
    @Environment(MathBoardUserModeStore.self) private var userModeStore

    var body: some View {
        Group {
            switch userModeStore.mode {
            case .teacher:
                NavigationStack {
                    StartScreenView()
                }
                .task {
                    documentStore.reload()
                }
            case .student:
                StudentModeView()
            }
        }
        #if os(iOS)
        .background(ExternalDisplayAccessoryRegistrar())
        #endif
    }
}

#if os(iOS)
private struct ExternalDisplayAccessoryRegistrar: UIViewControllerRepresentable {

    func makeUIViewController(context: Context) -> UIViewController {
        if #available(iOS 27.0, *) {
            return ExternalDisplayAccessoryViewController()
        } else {
            return UIViewController()
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

@available(iOS 27.0, *)
private final class ExternalDisplayAccessoryViewController: UIViewController {

    private var registration: UISceneAccessoryRegistration?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        registerExternalDisplayAccessoryIfNeeded()
    }

    deinit {
        if let registration {
            unregisterSceneAccessory(registration)
        }
    }

    private func registerExternalDisplayAccessoryIfNeeded() {
        guard registration == nil else { return }

        let configuration = UISceneConfiguration(
            name: "External Display",
            sessionRole: .windowExternalDisplayNonInteractive
        )
        configuration.delegateClass = ExternalDisplaySceneDelegate.self

        let accessory = UISceneAccessory.externalNonInteractive(sceneConfiguration: configuration)
        let registration = registerSceneAccessory(accessory)
        registration.isEnabled = true
        self.registration = registration
        print("MATHBOARD_EXTERNAL_DISPLAY: registered external noninteractive scene accessory available=\(registration.isAvailable)")
    }
}
#endif

#Preview {
    ContentView()
        .environment(DocumentStore())
        .environment(ClassroomRosterStore())
        .environment(ClassroomAssignmentStore())
        .environment(MathBoardUserModeStore())
        .environment(MathBoardTeacherAuthStore())
}
