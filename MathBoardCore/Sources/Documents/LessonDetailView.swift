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
import WidgetEngine

struct LessonDetailView: View {
    let lesson: Lesson

    @Environment(ClassroomRosterStore.self) private var rosterStore
    @Environment(ClassroomAssignmentStore.self) private var assignmentStore
    @State private var classroomMode: MathBoardClassroomMode = .teacher
    @State private var isLiveProgressDrawerOpen = false
    @State private var selectedLiveProgressAssignmentID: UUID?
    @State private var selectedLiveProgressWidgetID: UUID?
    @State private var liveProgressRows: [StudentWidgetLiveProgress] = []
    @State private var isRefreshingLiveProgress = false
    @State private var liveProgressErrorMessage: String?

    #if canImport(UIKit)
    @Environment(\.dismiss) private var dismiss
    #endif

    var body: some View {
        SlidesView(lessonURL: lesson.url, classroomMode: $classroomMode)
            .onAppear { DisplayBroker.shared.lessonURL = lesson.url }
            .overlay(alignment: .trailing) {
                liveProgressOverlay
            }
            .task(id: liveProgressTaskKey) {
                await pollLiveProgressIfNeeded()
            }
            .onChange(of: selectedLiveProgressAssignmentID) { _, _ in
                selectedLiveProgressWidgetID = nil
                liveProgressRows = []
            }
            .alert("Live Progress", isPresented: liveProgressErrorAlertBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(liveProgressErrorMessage ?? "")
            }
            #if canImport(UIKit)
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .topLeading) {
                lessonChrome
            }
            .background(InteractivePopGestureDisabler())
            #endif
    }

    private var lessonAssignments: [ClassroomAssignment] {
        assignmentStore.assignments(for: lesson.id)
    }

    private var selectedLiveProgressAssignment: ClassroomAssignment? {
        if let selectedLiveProgressAssignmentID,
           let assignment = lessonAssignments.first(where: { $0.id == selectedLiveProgressAssignmentID }) {
            return assignment
        }
        return lessonAssignments.first
    }

    private var selectedLiveProgressClassroom: Classroom? {
        guard let selectedLiveProgressAssignment else { return nil }
        return rosterStore.classrooms.first { $0.id == selectedLiveProgressAssignment.classroomID }
    }

    private var selectedLiveProgressWidget: AssignedWidgetSummary? {
        guard let assignment = selectedLiveProgressAssignment else { return nil }
        if let selectedLiveProgressWidgetID,
           let widget = assignment.widgetSummaries.first(where: { $0.widgetID == selectedLiveProgressWidgetID }) {
            return widget
        }
        return assignment.widgetSummaries.first
    }

    private var liveProgressTaskKey: String {
        [
            isLiveProgressDrawerOpen ? "open" : "closed",
            selectedLiveProgressAssignment?.classLessonCode ?? "none",
            selectedLiveProgressWidget?.widgetID.uuidString ?? "none"
        ].joined(separator: "|")
    }

    private var liveProgressErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { liveProgressErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    liveProgressErrorMessage = nil
                }
            }
        )
    }

    @ViewBuilder
    private var liveProgressOverlay: some View {
        if !lessonAssignments.isEmpty {
            ZStack(alignment: .topTrailing) {
                ZStack(alignment: .topTrailing) {
                    if let assignment = selectedLiveProgressAssignment {
                        liveProgressPanel(assignment)
                    }
                    liveProgressTab
                        .padding(.top, LiveProgressDrawerTheme.tabTopInset)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .zIndex(1)
                }
                .frame(
                    width: LiveProgressDrawerTheme.openWidth + LiveProgressDrawerTheme.tabWidth,
                    alignment: .topTrailing
                )
                .frame(maxHeight: .infinity, alignment: .top)
                .offset(x: isLiveProgressDrawerOpen ? 0 : LiveProgressDrawerTheme.openWidth)
                .compositingGroup()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
    }

    private func liveProgressPanel(_ assignment: ClassroomAssignment) -> some View {
        LiveProgressDrawerView(
            assignments: lessonAssignments,
            selectedAssignmentID: liveProgressAssignmentBinding,
            selectedWidgetID: liveProgressWidgetBinding(for: assignment),
            classroom: selectedLiveProgressClassroom,
            assignment: assignment,
            selectedWidget: selectedLiveProgressWidget,
            progressRows: liveProgressRows,
            isRefreshing: isRefreshingLiveProgress,
            onRefresh: {
                Task {
                    await refreshLiveProgress()
                }
            }
        )
    }

    private var liveProgressTab: some View {
        Button {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                isLiveProgressDrawerOpen.toggle()
            }
        } label: {
            Text("PROGRESS")
                .font(.system(size: 13, weight: .heavy))
                .tracking(2)
                .foregroundStyle(LiveProgressDrawerTheme.tabText)
                .fixedSize()
                .rotationEffect(.degrees(-90))
                .frame(width: LiveProgressDrawerTheme.tabWidth, height: LiveProgressDrawerTheme.tabHeight)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 12,
                        bottomLeadingRadius: 12,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0,
                        style: .continuous
                    )
                    .fill(
                        LinearGradient(
                            colors: [LiveProgressDrawerTheme.tab, LiveProgressDrawerTheme.tabEdge],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: LiveProgressDrawerTheme.panelShadow, radius: 6, x: -2, y: 3)
                )
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(LiveProgressDrawerTheme.tabEdge.opacity(0.6))
                        .frame(width: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLiveProgressDrawerOpen ? "Close live progress" : "Open live progress")
    }

    private var liveProgressAssignmentBinding: Binding<UUID?> {
        Binding(
            get: { selectedLiveProgressAssignment?.id },
            set: { newAssignmentID in
                selectedLiveProgressAssignmentID = newAssignmentID
            }
        )
    }

    private func liveProgressWidgetBinding(for assignment: ClassroomAssignment) -> Binding<UUID?> {
        Binding(
            get: {
                selectedLiveProgressWidget?.widgetID ?? assignment.widgetSummaries.first?.widgetID
            },
            set: { newWidgetID in
                selectedLiveProgressWidgetID = newWidgetID
            }
        )
    }

    private func pollLiveProgressIfNeeded() async {
        guard isLiveProgressDrawerOpen else { return }
        await refreshLiveProgress()

        while !Task.isCancelled && isLiveProgressDrawerOpen {
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await refreshLiveProgress()
        }
    }

    private func refreshLiveProgress() async {
        guard let assignment = selectedLiveProgressAssignment else { return }
        isRefreshingLiveProgress = true
        defer { isRefreshingLiveProgress = false }

        do {
            let rows = try await FirebaseClassroomSyncService()
                .fetchLiveProgress(classLessonCode: assignment.classLessonCode)
            liveProgressRows = rows.filter { row in
                row.assignmentID == assignment.id &&
                row.classroomID == assignment.classroomID
            }
        } catch {
            liveProgressErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
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

private struct LiveProgressDrawerView: View {
    let assignments: [ClassroomAssignment]
    @Binding var selectedAssignmentID: UUID?
    @Binding var selectedWidgetID: UUID?
    let classroom: Classroom?
    let assignment: ClassroomAssignment
    let selectedWidget: AssignedWidgetSummary?
    let progressRows: [StudentWidgetLiveProgress]
    let isRefreshing: Bool
    let onRefresh: () -> Void

    private var filteredProgressRows: [StudentWidgetLiveProgress] {
        guard let selectedWidget else { return progressRows }
        return progressRows.filter { $0.widgetID == selectedWidget.widgetID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            controls
            progressList
        }
        .padding(16)
        .frame(width: LiveProgressDrawerTheme.openWidth)
        .frame(maxHeight: .infinity)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: LiveProgressDrawerTheme.panelCornerRadius,
                bottomLeadingRadius: LiveProgressDrawerTheme.panelCornerRadius,
                style: .continuous
            )
            .fill(LiveProgressDrawerTheme.panel)
            .shadow(color: LiveProgressDrawerTheme.panelShadow, radius: 18, x: -6, y: 6)
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Live Progress")
                    .font(.headline)
                Text(classroom?.name ?? "Class assignment")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onRefresh) {
                if isRefreshing {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Refresh live progress")
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if assignments.count > 1 {
                Picker("Class", selection: $selectedAssignmentID) {
                    ForEach(assignments) { assignment in
                        Text(assignment.classLessonCode)
                            .tag(Optional(assignment.id))
                    }
                }
                .pickerStyle(.menu)
            }

            Picker("Widget", selection: $selectedWidgetID) {
                ForEach(assignment.widgetSummaries) { widget in
                    Text(widget.title)
                        .tag(Optional(widget.widgetID))
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var progressList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if let classroom {
                    ForEach(classroom.students) { student in
                        LiveProgressStudentRow(
                            studentName: student.displayName,
                            progress: progress(for: student.id)
                        )
                    }
                } else {
                    ForEach(filteredProgressRows) { progress in
                        LiveProgressStudentRow(
                            studentName: progress.studentName,
                            progress: progress
                        )
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func progress(for studentID: UUID) -> StudentWidgetLiveProgress? {
        filteredProgressRows.first { $0.studentID == studentID }
    }
}

private enum LiveProgressDrawerTheme {
    static let panel = Color(red: 0.99, green: 0.99, blue: 1.0)
    static let tab = Color(red: 0.84, green: 0.66, blue: 0.40)
    static let tabEdge = Color(red: 0.70, green: 0.52, blue: 0.28)
    static let tabText = Color(red: 0.33, green: 0.23, blue: 0.09)
    static let panelShadow = Color.black.opacity(0.16)

    static let panelCornerRadius: CGFloat = 20
    static let openWidth: CGFloat = 366
    static let tabWidth: CGFloat = 34
    static let tabHeight: CGFloat = 152
    static let tabTopInset: CGFloat = 252
}

private struct LiveProgressStudentRow: View {
    let studentName: String
    let progress: StudentWidgetLiveProgress?

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(studentName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(scoreText)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                Text(updatedText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var scoreText: String {
        guard let progress else { return "--" }
        return "\(progress.correctCount)/\(progress.attemptedCount)"
    }

    private var statusText: String {
        progress.liveProgressIndicatorState().displayName
    }

    private var updatedText: String {
        guard let progress else { return "" }
        return progress.updatedAt.formatted(date: .omitted, time: .shortened)
    }

    private var statusColor: Color {
        switch progress.liveProgressIndicatorState() {
        case .notStarted, .inactive, .offline:
            return .secondary
        case .active:
            return .blue
        case .submitted:
            return .green
        }
    }
}

private extension RosterStudent {
    var displayName: String {
        let name = [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return name.isEmpty ? "Unnamed Student" : name
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
