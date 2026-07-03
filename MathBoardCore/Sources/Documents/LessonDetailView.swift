//
//  LessonDetailView.swift
//  MathBoardCore — Documents module
//
//  Embeds the presenting canvas for a single lesson. Thin wrapper —
//  Presentation owns the toolbar (viewfinder toggle, and later present /
//  mirror, freeze) and Canvas owns its drawing surface lifecycle.
//

import SwiftUI
import Presentation
import Slides

struct LessonDetailView: View {
    let lesson: Lesson

    #if canImport(UIKit)
    @Environment(\.dismiss) private var dismiss
    #endif

    var body: some View {
        SlidesView(lessonURL: lesson.url)
            .navigationTitle(lesson.name)
            .onAppear { DisplayBroker.shared.lessonURL = lesson.url }
            #if canImport(UIKit)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Back", systemImage: "chevron.backward")
                    }
                }
            }
            .background(InteractivePopGestureDisabler())
            #endif
    }
}

#if canImport(UIKit)
private struct InteractivePopGestureDisabler: UIViewControllerRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        Task { @MainActor in
            await Task.yield()
            context.coordinator.disablePopGesture(from: controller)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        Task { @MainActor in
            await Task.yield()
            context.coordinator.disablePopGesture(from: uiViewController)
        }
    }

    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: Coordinator) {
        coordinator.restorePopGesture()
    }

    final class Coordinator {
        private weak var navigationController: UINavigationController?
        private var previousIsEnabled: Bool?

        @MainActor
        func disablePopGesture(from controller: UIViewController) {
            guard let navigationController = controller.nearestNavigationController,
                  self.navigationController !== navigationController else {
                return
            }

            restorePopGesture()
            self.navigationController = navigationController
            previousIsEnabled = navigationController.interactivePopGestureRecognizer?.isEnabled
            navigationController.interactivePopGestureRecognizer?.isEnabled = false
        }

        @MainActor
        func restorePopGesture() {
            guard let navigationController,
                  let previousIsEnabled else {
                return
            }
            navigationController.interactivePopGestureRecognizer?.isEnabled = previousIsEnabled
            self.navigationController = nil
            self.previousIsEnabled = nil
        }
    }
}

private extension UIViewController {
    var nearestNavigationController: UINavigationController? {
        if let navigationController {
            return navigationController
        }

        var ancestor = parent
        while let current = ancestor {
            if let navigationController = current as? UINavigationController {
                return navigationController
            }
            if let navigationController = current.navigationController {
                return navigationController
            }
            ancestor = current.parent
        }

        return view.window?.rootViewController?.findNavigationController()
    }

    func findNavigationController() -> UINavigationController? {
        if let navigationController = self as? UINavigationController {
            return navigationController
        }
        for child in children {
            if let navigationController = child.findNavigationController() {
                return navigationController
            }
        }
        return presentedViewController?.findNavigationController()
    }
}
#endif

#Preview {
    NavigationStack {
        LessonDetailView(lesson: Lesson(
            id: UUID(),
            name: "Quadratic Functions Day 1",
            url: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("Quadratic Functions Day 1.mathboard"),
            createdAt: .now.addingTimeInterval(-86_400),
            modifiedAt: .now.addingTimeInterval(-3_600)
        ))
    }
}
