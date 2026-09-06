//
//  LessonDetailView.swift
//  MathBoardCore — Documents module
//
//  Embeds the presenting canvas for a single lesson. Thin wrapper —
//  Presentation owns the toolbar (viewfinder toggle, and later present /
//  mirror, freeze) and Canvas owns its drawing surface lifecycle.
//

import SwiftUI
import GraphCalculator
import LiveClassroom
import Presentation
import Slides
import WidgetEngine

struct LessonDetailView: View {
    let lesson: Lesson

    @Environment(ClassroomRosterStore.self) private var rosterStore
    @Environment(ClassroomAssignmentStore.self) private var assignmentStore
    @Environment(MathBoardTeacherAuthStore.self) private var teacherAuthStore
    @AppStorage(LiveClassroomSettings.enabledKey) private var isLiveTeacherInkEnabled = false
    @AppStorage(LiveClassroomSettings.ablyAPIKeyKey) private var liveTeacherInkAblyAPIKey = ""
    @State private var classroomMode: MathBoardClassroomMode = .teacher
    @State private var selectedTeachingAssignmentID: UUID?
    @State private var isLiveProgressDrawerOpen = false
    @State private var selectedLiveProgressAssignmentID: UUID?
    @State private var selectedLiveProgressWidgetID: UUID?
    @State private var liveProgressRows: [StudentWidgetLiveProgress] = []
    @State private var localLiveProgressPointValue = 1
    @State private var isRefreshingLiveProgress = false
    @State private var liveProgressErrorMessage: String?
    @State private var isLiveTeacherInkSettingsPresented = false
    @State private var isLibraryDrawerOpen = false
    @State private var isMasterLessonUnlocked = false
    @State private var isFollowMeEnabled = false

    #if canImport(UIKit)
    @Environment(\.dismiss) private var dismiss
    #endif

    var body: some View {
        SlidesView(
            lessonURL: lesson.url,
            classroomMode: $classroomMode,
            isFollowMeEnabled: $isFollowMeEnabled,
            classroomSessionCode: selectedTeachingAssignment?.classLessonCode,
            liveClassroomConfiguration: liveClassroomConfiguration,
            onTeacherInkChunkPublished: persistTeacherInkChunk,
            onTeacherInkDrawingSnapshotPublished: persistTeacherInkDrawingSnapshot,
            onTeacherObjectSnapshotPublished: persistTeacherObjectSnapshot,
            onTeacherSlideManifestSnapshotPublished: persistTeacherSlideManifestSnapshot,
            onLibraryDrawerOpenChange: { isOpen in
                isLibraryDrawerOpen = isOpen
            },
            onLessonContentChanged: propagateMasterLessonChanges,
            isEditingLocked: isMasterLessonEditingLocked
        )
            .onAppear { DisplayBroker.shared.lessonURL = lesson.url }
            .overlay(alignment: .trailing) {
                liveProgressOverlay
            }
            .overlay(alignment: .topTrailing) {
                if !isLibraryDrawerOpen && !isLiveProgressDrawerOpen {
                    teachingSessionControls
                }
            }
            .overlay {
                let broker = DisplayBroker.shared
                if broker.isGraphCalculatorVisible && broker.graphCalculator.hasVisibleSection {
                    GraphCalculatorView(
                        state: broker.graphCalculator,
                        onGraphSnapshot: { snapshot in
                            DisplayBroker.shared.graphSnapshotHandler?(snapshot)
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .overlay {
                let broker = DisplayBroker.shared
                ForEach(broker.classroomCelebrationEvents) { celebrationEvent in
                    ShootingStarCelebrationOverlay(event: celebrationEvent)
                        .id(celebrationEvent.id)
                }
            }
            .task(id: liveProgressTaskKey) {
                await pollLiveProgressIfNeeded()
            }
            .onChange(of: selectedTeachingAssignmentID) { _, newAssignmentID in
                selectedLiveProgressAssignmentID = newAssignmentID
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
            .sheet(isPresented: $isLiveTeacherInkSettingsPresented) {
                LiveTeacherInkSettingsView(
                    isEnabled: $isLiveTeacherInkEnabled,
                    apiKey: $liveTeacherInkAblyAPIKey
                )
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

    private var selectedTeachingAssignment: ClassroomAssignment? {
        guard let selectedTeachingAssignmentID else { return nil }
        return lessonAssignments.first { $0.id == selectedTeachingAssignmentID }
    }

    private var isMasterLessonContext: Bool {
        selectedTeachingAssignmentID == nil
    }

    private var isMasterLessonEditingLocked: Bool {
        classroomMode == .teacher && isMasterLessonContext && !lessonAssignments.isEmpty && !isMasterLessonUnlocked
    }

    private var selectedTeachingClassroom: Classroom? {
        guard let selectedTeachingAssignment else { return nil }
        return rosterStore.classrooms.first { $0.id == selectedTeachingAssignment.classroomID }
    }

    private var selectedLiveProgressAssignment: ClassroomAssignment? {
        selectedTeachingAssignment
    }

    private var selectedLiveProgressClassroom: Classroom? {
        guard let selectedLiveProgressAssignment else { return nil }
        return rosterStore.classrooms.first { $0.id == selectedLiveProgressAssignment.classroomID }
    }

    private var selectedLiveProgressWidget: AssignedWidgetSummary? {
        guard let assignment = selectedLiveProgressAssignment,
              let selectedLiveProgressWidgetID else { return nil }
        return assignment.widgetSummaries.first(where: { $0.widgetID == selectedLiveProgressWidgetID })
    }

    private var isSelectedWidgetTeacherScored: Bool {
        guard let widget = selectedLiveProgressWidget else {
            // No widget selected — manual scoring is the default for all slides.
            return true
        }
        // Auto-scored widgets (isScoreable = true) provide Firebase scores.
        // Everything else (MatchGrid, timers, tools, unknown widgets) uses manual scoring.
        return !(widget.builtInKind?.isScoreable ?? false)
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

    private var liveClassroomConfiguration: LiveClassroomSessionConfiguration? {
        guard isLiveTeacherInkEnabled,
              let selectedTeachingAssignment else { return nil }
        let clientID = "teacher-\(teacherAuthStore.state.userID ?? "local")"
        let configuration = LiveClassroomSessionConfiguration(
            lessonCode: selectedTeachingAssignment.classLessonCode,
            role: .teacher,
            clientID: clientID,
            apiKey: liveTeacherInkAblyAPIKey
        )
        return configuration.isUsable ? configuration : nil
    }

    private var liveTeacherInkStatus: LiveTeacherInkStatus {
        if !isLiveTeacherInkEnabled {
            return .off
        }
        if lessonAssignments.isEmpty || selectedTeachingAssignment == nil {
            return .missingLessonCode
        }
        if liveTeacherInkAblyAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .missingAPIKey
        }
        return .ready
    }

    @ViewBuilder
    private var teachingSessionControls: some View {
        if classroomMode == .teacher && !lessonAssignments.isEmpty {
            HStack(spacing: 8) {
                if isMasterLessonContext {
                    masterLessonLockButton
                }
                if selectedTeachingAssignment != nil {
                    followMeButton
                }
                teachingSessionMenu
            }
            .padding(.top, 8)
            .padding(.trailing, 74)
        }
    }

    private var masterLessonLockButton: some View {
        Button {
            isMasterLessonUnlocked.toggle()
        } label: {
            Label(
                isMasterLessonUnlocked ? "Unlocked" : "Locked",
                systemImage: isMasterLessonUnlocked ? "lock.open" : "lock.fill"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(isMasterLessonUnlocked ? Color.orange : Color.secondary)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isMasterLessonUnlocked ? "Lock Master copy" : "Unlock Master copy")
    }

    private var followMeButton: some View {
        Button {
            isFollowMeEnabled.toggle()
        } label: {
            Label(
                isFollowMeEnabled ? "Following" : "Follow Me",
                systemImage: isFollowMeEnabled ? "figure.walk.motion" : "figure.walk"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(isFollowMeEnabled ? Color.white : Color.secondary)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(
                isFollowMeEnabled ? Color.blue : Color.clear,
                in: Capsule()
            )
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(liveTeacherInkStatus != .ready)
        .opacity(liveTeacherInkStatus == .ready ? 1 : 0.5)
        .accessibilityLabel(isFollowMeEnabled ? "Turn off Follow Me" : "Turn on Follow Me")
    }

    @ViewBuilder
    private var teachingSessionMenu: some View {
        if classroomMode == .teacher && !lessonAssignments.isEmpty {
            Menu {
                Button {
                    isFollowMeEnabled = false
                    selectedTeachingAssignmentID = nil
                } label: {
                    Label("Master copy", systemImage: masterCopyMenuIconName)
                }

                Section("Class Sessions") {
                    ForEach(lessonAssignments) { assignment in
                        Button {
                            isFollowMeEnabled = false
                            selectedTeachingAssignmentID = assignment.id
                            isMasterLessonUnlocked = false
                        } label: {
                            Label(
                                "\(classroomName(for: assignment)) - \(assignment.classLessonCode)",
                                systemImage: selectedTeachingAssignmentID == assignment.id ? "checkmark" : "person.3"
                            )
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: selectedTeachingAssignment == nil ? "doc" : "person.3")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(selectedTeachingClassroom?.name ?? "Master copy")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(selectedTeachingAssignment?.classLessonCode ?? "No class code")
                            .font(.caption2.monospaced().weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .frame(maxWidth: 240, alignment: .leading)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Teaching class session")
        }
    }

    private var masterCopyMenuIconName: String {
        if isMasterLessonContext {
            return isMasterLessonUnlocked ? "lock.open" : "lock.fill"
        }
        return "doc"
    }

    private func classroomName(for assignment: ClassroomAssignment) -> String {
        rosterStore.classrooms.first { $0.id == assignment.classroomID }?.name ?? "Class"
    }

    @ViewBuilder
    private var liveProgressOverlay: some View {
        if selectedTeachingAssignment != nil {
            HStack(alignment: .top, spacing: 0) {
                liveProgressTab
                    .padding(.top, LiveProgressDrawerTheme.tabTopInset)
                    .zIndex(1)

                if isLiveProgressDrawerOpen,
                   let assignment = selectedLiveProgressAssignment {
                    liveProgressPanel(assignment)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(
                width: isLiveProgressDrawerOpen
                    ? LiveProgressDrawerTheme.openWidth + LiveProgressDrawerTheme.tabWidth
                    : LiveProgressDrawerTheme.tabWidth,
                alignment: .topTrailing
            )
            .frame(maxHeight: .infinity, alignment: .topTrailing)
            .clipped()
        }
    }

    private func liveProgressPanel(_ assignment: ClassroomAssignment) -> some View {
        LiveProgressDrawerView(
            selectedWidgetID: liveProgressWidgetBinding(for: assignment),
            classroom: selectedLiveProgressClassroom,
            assignment: assignment,
            selectedWidget: selectedLiveProgressWidget,
            progressRows: liveProgressRows,
            localScoresByStudentID: localScoresByStudentID(for: assignment),
            localPointValue: $localLiveProgressPointValue,
            isLocalScoringEnabled: isSelectedWidgetTeacherScored,
            isRefreshing: isRefreshingLiveProgress,
            onRefresh: {
                Task {
                    await refreshLiveProgress()
                }
            },
            onAddLocalPoints: { student in
                updateLocalScore(for: student, assignment: assignment, delta: localLiveProgressPointValue)
            },
            onSubtractLocalPoints: { student in
                updateLocalScore(for: student, assignment: assignment, delta: -localLiveProgressPointValue)
            },
            onCelebrateStudent: presentStudentCelebration
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

    private func liveProgressWidgetBinding(for assignment: ClassroomAssignment) -> Binding<UUID?> {
        Binding(
            get: {
                selectedLiveProgressWidgetID
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

    private func presentStudentCelebration(_ studentName: String) {
        DisplayBroker.shared.presentClassroomCelebration(studentName: studentName)
    }

    private func refreshLiveProgress() async {
        guard let assignment = selectedLiveProgressAssignment else { return }
        // Always fetch Firebase so presence indicators (student login state) are shown
        // regardless of whether manual scoring or widget scoring is active.
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

    private func localScoresByStudentID(for assignment: ClassroomAssignment) -> [UUID: Int] {
        // When no specific widget is selected, use assignment.id as a stable key for
        // slide-level manual scores that aren't tied to any particular widget.
        let widgetID = selectedLiveProgressWidget?.widgetID ?? assignment.id
        return assignmentStore.localWidgetScores(
            assignmentID: assignment.id,
            widgetID: widgetID
        ).reduce(into: [:]) { result, score in
            result[score.studentID] = score.points
        }
    }

    private func updateLocalScore(
        for student: RosterStudent,
        assignment: ClassroomAssignment,
        delta: Int
    ) {
        guard isSelectedWidgetTeacherScored,
              let classroom = selectedLiveProgressClassroom else { return }
        do {
            if let widget = selectedLiveProgressWidget {
                // Widget-specific manual scoring (e.g., MatchGrid)
                try assignmentStore.updateLocalWidgetScore(
                    assignment: assignment,
                    classroom: classroom,
                    widgetID: widget.widgetID,
                    studentID: student.id,
                    delta: delta
                )
            } else {
                // Slide-level manual scoring — not tied to a specific widget
                try assignmentStore.updateLocalManualScore(
                    assignment: assignment,
                    classroom: classroom,
                    studentID: student.id,
                    delta: delta
                )
            }
        } catch {
            liveProgressErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func persistTeacherInkChunk(_ chunk: TeacherInkStrokeChunk) {
        guard chunk.isFinalChunk,
              let selectedTeachingAssignment,
              ClassroomAssignmentStore.normalizedClassLessonCode(selectedTeachingAssignment.classLessonCode) == chunk.lessonCode else {
            return
        }

        Task { @MainActor in
            do {
                try await FirebaseClassroomSyncService(
                    teacherUserID: teacherAuthStore.state.userID,
                    teacherEmail: teacherAuthStore.state.email
                ).publishTeacherInkChunk(chunk)
            } catch {
                print("[LessonDetail] teacher ink durable save error: \(error)")
            }
        }
    }

    private func persistTeacherInkDrawingSnapshot(_ snapshot: TeacherInkDrawingSnapshot) {
        guard let selectedTeachingAssignment,
              ClassroomAssignmentStore.normalizedClassLessonCode(selectedTeachingAssignment.classLessonCode) == snapshot.lessonCode else {
            return
        }

        Task { @MainActor in
            do {
                try await FirebaseClassroomSyncService(
                    teacherUserID: teacherAuthStore.state.userID,
                    teacherEmail: teacherAuthStore.state.email
                ).publishTeacherInkDrawingSnapshot(snapshot)
            } catch {
                print("[LessonDetail] teacher ink snapshot durable save error: \(error)")
            }
        }
    }

    private func persistTeacherObjectSnapshot(_ snapshot: TeacherObjectSnapshot) {
        guard let selectedTeachingAssignment,
              ClassroomAssignmentStore.normalizedClassLessonCode(selectedTeachingAssignment.classLessonCode) == snapshot.lessonCode else {
            return
        }

        Task { @MainActor in
            do {
                try await FirebaseClassroomSyncService(
                    teacherUserID: teacherAuthStore.state.userID,
                    teacherEmail: teacherAuthStore.state.email
                ).publishTeacherObjectSnapshot(snapshot)
            } catch {
                print("[LessonDetail] teacher object durable save error: \(error)")
            }
        }
    }

    private func persistTeacherSlideManifestSnapshot(_ snapshot: TeacherSlideManifestSnapshot) async throws {
        guard let selectedTeachingAssignment,
              ClassroomAssignmentStore.normalizedClassLessonCode(selectedTeachingAssignment.classLessonCode) == snapshot.lessonCode else {
            return
        }

        try await FirebaseClassroomSyncService(
            teacherUserID: teacherAuthStore.state.userID,
            teacherEmail: teacherAuthStore.state.email
        ).publishTeacherSlideManifestSnapshot(snapshot)
    }

    private func propagateMasterLessonChanges() {
        // Do NOT gate on isMasterLessonContext here. This callback fires 900 ms
        // after the last master edit, but the teacher may have already switched to
        // a class session view by then — that would make isMasterLessonContext false
        // and silently skip propagation. The callback is only ever scheduled when
        // classroomSessionCode is nil (master context), so guarding here creates a
        // race condition without providing any safety.
        guard !lessonAssignments.isEmpty else { return }
        SlideStore.propagateMasterContent(
            lessonURL: lesson.url,
            toClassSessionCodes: lessonAssignments.map(\.classLessonCode)
        )
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
                Section("Live Teacher Ink") {
                    Label(liveTeacherInkStatus.title, systemImage: liveTeacherInkStatus.systemImage)
                        .foregroundStyle(liveTeacherInkStatus.color)
                    Toggle("Sync teacher ink", isOn: $isLiveTeacherInkEnabled)
                    Button(liveTeacherInkAblyAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Set Ably API Key" : "Edit Ably API Key") {
                        isLiveTeacherInkSettingsPresented = true
                    }
                    .disabled(lessonAssignments.isEmpty)
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

private enum LiveTeacherInkStatus {
    case off
    case missingLessonCode
    case missingAPIKey
    case ready

    var title: String {
        switch self {
        case .off:
            return "Live ink off"
        case .missingLessonCode:
            return "Choose class session"
        case .missingAPIKey:
            return "Missing Ably key"
        case .ready:
            return "Ready to sync"
        }
    }

    var systemImage: String {
        switch self {
        case .off:
            return "icloud.slash"
        case .missingLessonCode, .missingAPIKey:
            return "exclamationmark.triangle"
        case .ready:
            return "dot.radiowaves.left.and.right"
        }
    }

    var color: Color {
        switch self {
        case .off:
            return .secondary
        case .missingLessonCode, .missingAPIKey:
            return .orange
        case .ready:
            return .green
        }
    }
}

private struct LiveTeacherInkSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var isEnabled: Bool
    @Binding var apiKey: String

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Sync teacher ink", isOn: $isEnabled)
                    SecureField("Ably API key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("This proof of concept stores the key locally on this device. Production should replace this with short-lived Ably tokens from a server.")
                }
            }
            .navigationTitle("Live Teacher Ink")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct LiveProgressDrawerView: View {
    @Binding var selectedWidgetID: UUID?
    let classroom: Classroom?
    let assignment: ClassroomAssignment
    let selectedWidget: AssignedWidgetSummary?
    let progressRows: [StudentWidgetLiveProgress]
    let localScoresByStudentID: [UUID: Int]
    @Binding var localPointValue: Int
    let isLocalScoringEnabled: Bool
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onAddLocalPoints: (RosterStudent) -> Void
    let onSubtractLocalPoints: (RosterStudent) -> Void
    let onCelebrateStudent: (String) -> Void

    // Ticked every 2 seconds so indicatorState(now:) re-evaluates without waiting for
    // a data change. This makes stale records (student left the lesson) turn red/gray
    // automatically rather than only when the teacher interacts with the widget picker.
    @State private var now = Date()

    private var widgetProgressRows: [StudentWidgetLiveProgress] {
        guard let selectedWidget else { return [] }
        return progressRows.filter { $0.widgetID == selectedWidget.widgetID }
    }

    private var lessonPresenceRows: [StudentWidgetLiveProgress] {
        progressRows.filter { $0.widgetID == StudentWidgetLiveProgress.lessonPresenceWidgetID }
    }

    private var fallbackProgressRows: [StudentWidgetLiveProgress] {
        selectedWidget == nil ? progressRows : widgetProgressRows + lessonPresenceRows
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
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                now = Date()
            }
        }
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
            if !assignment.widgetSummaries.isEmpty {
                Picker("Scoring", selection: $selectedWidgetID) {
                    Text("Manual scoring")
                        .tag(Optional<UUID>.none)
                    ForEach(assignment.widgetSummaries) { widget in
                        Text(widget.title)
                            .tag(Optional(widget.widgetID))
                    }
                }
                .pickerStyle(.menu)
            }

            if isLocalScoringEnabled {
                Stepper("Points per tap: \(localPointValue)", value: $localPointValue, in: 1...25, step: 1)
                    .font(.caption.weight(.semibold))
            }
        }
    }

    private var progressList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if let classroom {
                    ForEach(classroom.students) { student in
                        let studentProgress = progress(for: student)
                        LiveProgressStudentRow(
                            studentName: student.displayName,
                            preferredFirstName: studentProgress?.studentPreferredFirstName,
                            progress: studentProgress,
                            lessonPresence: lessonPresence(for: student),
                            now: now,
                            localScore: isLocalScoringEnabled ? localScoresByStudentID[student.id, default: 0] : nil,
                            onAddLocalPoints: isLocalScoringEnabled ? { onAddLocalPoints(student) } : nil,
                            onSubtractLocalPoints: isLocalScoringEnabled ? { onSubtractLocalPoints(student) } : nil,
                            onCelebrate: { onCelebrateStudent(celebrationName(for: student, progress: studentProgress)) }
                        )
                    }
                } else {
                    ForEach(fallbackProgressRows) { progress in
                        let presence = lessonPresenceRows.first {
                            $0.studentID == progress.studentID ||
                            $0.studentIdentifier == progress.studentIdentifier
                        }
                        LiveProgressStudentRow(
                            studentName: progress.studentName,
                            preferredFirstName: progress.studentPreferredFirstName,
                            progress: progress,
                            lessonPresence: presence,
                            now: now,
                            onCelebrate: { onCelebrateStudent(celebrationName(for: progress)) }
                        )
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func progress(for student: RosterStudent) -> StudentWidgetLiveProgress? {
        widgetProgress(for: student) ?? lessonPresence(for: student)
    }

    private func widgetProgress(for student: RosterStudent) -> StudentWidgetLiveProgress? {
        widgetProgressRows.first { matches($0, student: student) }
    }

    private func lessonPresence(for student: RosterStudent) -> StudentWidgetLiveProgress? {
        lessonPresenceRows.first { matches($0, student: student) }
    }

    private func matches(_ progress: StudentWidgetLiveProgress, student: RosterStudent) -> Bool {
        progress.studentID == student.id ||
        normalizedStudentIdentifier(progress.studentIdentifier) == normalizedStudentIdentifier(student.officialStudentID) ||
        normalizedStudentIdentifier(progress.studentIdentifier) == normalizedStudentIdentifier(student.alternateStudentID)
    }

    private func celebrationName(for student: RosterStudent, progress: StudentWidgetLiveProgress?) -> String {
        let preferred = progress?.studentPreferredFirstName ?? student.firstName
        let trimmedPreferred = preferred.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPreferred.isEmpty { return trimmedPreferred }
        return celebrationName(fromDisplayName: student.displayName)
    }

    private func celebrationName(for progress: StudentWidgetLiveProgress) -> String {
        let preferred = progress.studentPreferredFirstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !preferred.isEmpty { return preferred }
        return celebrationName(fromDisplayName: progress.studentName)
    }

    private func celebrationName(fromDisplayName displayName: String) -> String {
        displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .first
            .map(String.init) ?? "Student"
    }

    private func normalizedStudentIdentifier(_ identifier: String) -> String {
        identifier.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
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
    let preferredFirstName: String?
    let progress: StudentWidgetLiveProgress?
    var lessonPresence: StudentWidgetLiveProgress? = nil
    var now: Date = Date()
    var localScore: Int? = nil
    var onAddLocalPoints: (() -> Void)? = nil
    var onSubtractLocalPoints: (() -> Void)? = nil
    var onCelebrate: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Button {
                onCelebrate?()
            } label: {
                Image(systemName: "star.fill")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(dotColor)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Celebrate \(studentName)")
            .accessibilityHint("Shows a shooting star shout-out on the teacher and external display screens.")

            VStack(alignment: .leading, spacing: 2) {
                Text(studentName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(statusText)
                        .foregroundStyle(statusTextColor)
                    if let displayedPreferredFirstName {
                        Text(displayedPreferredFirstName)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.yellow.opacity(0.18), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }

            Spacer(minLength: 8)

            if let localScore {
                HStack(spacing: 7) {
                    Button {
                        onAddLocalPoints?()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add local points for \(studentName)")

                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(localScore)")
                            .font(.title3.monospacedDigit().weight(.bold))
                        Text("pts")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 42, alignment: .trailing)

                    Button {
                        onSubtractLocalPoints?()
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Subtract local points for \(studentName)")
                }
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(scoreText)
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                    Text(updatedText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var currentIndicatorState: LiveProgressIndicatorState {
        progress.indicatorState(now: now, lessonPresence: lessonPresence)
    }

    private var scoreText: String {
        guard let progress,
              progress.widgetID != StudentWidgetLiveProgress.lessonPresenceWidgetID else { return "--" }
        return "\(progress.correctCount)/\(progress.attemptedCount)"
    }

    private var displayedPreferredFirstName: String? {
        guard let preferredFirstName else { return nil }
        let trimmedName = preferredFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        return String(trimmedName.prefix(8))
    }

    private var statusText: String {
        if let localScore, localScore > 0 { return "Local score" }
        // Show "Submitted" even after reset so the teacher can see the student's prior submission.
        if progress?.hasEverBeenSubmitted == true { return "Submitted" }
        return currentIndicatorState.displayName
    }

    // "Submitted" is green whether the student is in-lesson (green dot) or gone (gray dot).
    private var statusTextColor: Color {
        if progress?.hasEverBeenSubmitted == true { return .green }
        switch currentIndicatorState {
        case .submitted, .submittedOffline: return .green
        default: return .secondary
        }
    }

    private var updatedText: String {
        guard let progress else { return "" }
        return progress.updatedAt.formatted(date: .omitted, time: .shortened)
    }

    private var dotColor: Color {
        // Only green when teacher has awarded actual points; 0-score keeps Firebase presence color.
        if let localScore, localScore > 0 { return .green }
        switch currentIndicatorState {
        case .notStarted, .offline:
            return .red
        case .inactive:
            return .blue
        case .active:
            return .yellow
        case .submitted:
            return .green
        case .submittedOffline:
            return .gray
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
