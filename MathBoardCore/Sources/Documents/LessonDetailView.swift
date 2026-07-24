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

    @State private var classroomMode: MathBoardClassroomMode = .teacher

    #if canImport(UIKit)
    @Environment(\.dismiss) private var dismiss
    #endif

    var body: some View {
        SlidesView(lessonURL: lesson.url, classroomMode: $classroomMode)
            .onAppear { DisplayBroker.shared.lessonURL = lesson.url }
            #if canImport(UIKit)
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .topLeading) {
                lessonChrome
            }
            .background(InteractivePopGestureDisabler())
            #endif
    }

    #if canImport(UIKit)
    // Floating back button + lesson title rendered over the whiteboard so the
    // canvas can extend to the very top of the screen. Tapping the title opens
    // lesson-level controls, including the classroom mode switch.
    private var lessonChrome: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Menu {
                Section("Classroom Mode") {
                    Picker("Classroom Mode", selection: $classroomMode) {
                        ForEach(MathBoardClassroomMode.allCases) { mode in
                            Label(mode.displayName, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(lesson.name)
                        .font(.headline)
                        .lineLimit(1)
                    Image(systemName: classroomMode.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Lesson menu")
        }
        .padding(.top, 8)
        .padding(.leading, 12)
    }
    #endif
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
