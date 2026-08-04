import SwiftUI

private enum SourceMathBoardPublishChoice: String, CaseIterable, Identifiable {
    case publishNewVersion
    case useCurrentPublishedVersion

    var id: Self { self }

    var title: String {
        switch self {
        case .publishNewVersion:
            "Publish New Version"
        case .useCurrentPublishedVersion:
            "Use Current Published Version"
        }
    }
}

struct LessonAssignmentSheet: View {
    let lesson: Lesson
    @Environment(DocumentStore.self) private var documentStore
    @Environment(ClassroomRosterStore.self) private var rosterStore
    @Environment(ClassroomAssignmentStore.self) private var assignmentStore
    @Environment(MathBoardTeacherAuthStore.self) private var teacherAuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedClassroomIDs: Set<UUID> = []
    @State private var widgetSummaries: [AssignedWidgetSummary] = []
    @State private var sourceContentChecksum: String?
    @State private var publishChoice: SourceMathBoardPublishChoice = .publishNewVersion
    @State private var assignmentActivityByID: [UUID: Bool] = [:]
    @State private var isCheckingAssignmentActivity = false
    @State private var errorMessage: String?
    @State private var isAssigning = false

    private var availableClassrooms: [Classroom] {
        rosterStore.classrooms
    }

    private var assignedClassroomIDs: Set<UUID> {
        Set(assignmentStore.assignments(for: lesson.id).map(\.classroomID))
    }

    private var selectedActionableClassroomIDs: [UUID] {
        selectedClassroomIDs.filter { classroomID in
            guard let assignment = assignmentStore.assignment(for: lesson.id, classroomID: classroomID) else {
                return true
            }
            return assignmentActivityByID[assignment.id] != true
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(lesson.name)
                            .font(.headline)
                        Text(widgetSummaryText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Lesson")
                }

                Section {
                    sourceMathBoardPublishControls
                } header: {
                    Text("Source MathBoard")
                } footer: {
                    Text(sourceMathBoardFooterText)
                }

                if availableClassrooms.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No Classroom Rosters",
                            systemImage: "person.3.sequence",
                            description: Text("Create or import a classroom roster before assigning lessons.")
                        )
                    }
                } else {
                    Section {
                        ForEach(availableClassrooms) { classroom in
                            Button {
                                toggleSelection(for: classroom)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selectedClassroomIDs.contains(classroom.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(selectedClassroomIDs.contains(classroom.id) ? .blue : .secondary)
                                        .frame(width: 28)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(classroom.name)
                                            .font(.headline)
                                        Text("^[\(classroom.students.count) student](inflect: true)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer(minLength: 8)

                                    if let assignment = assignmentStore.assignment(for: lesson.id, classroomID: classroom.id) {
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(assignment.versionDisplayName)
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                            Text(classroomAssignmentStatusText(assignment))
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(classroomAssignmentStatusColor(assignment))
                                        }
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(isClassroomLocked(classroom))
                        }
                    } header: {
                        Text("Classes")
                    } footer: {
                        Text("Unassigned classes get new lesson codes. Assigned classes with no student activity can be updated while keeping the same code.")
                    }
                }
            }
            .navigationTitle("Assign Lesson")
            .disabled(isAssigning)
            .overlay {
                if isAssigning {
                    assignmentProgressOverlay
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isAssigning)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await assignLesson()
                        }
                    } label: {
                        if isAssigning {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Assign")
                        }
                    }
                    .disabled(selectedActionableClassroomIDs.isEmpty || isAssigning || isCheckingAssignmentActivity)
                }
            }
            .interactiveDismissDisabled(isAssigning)
            .alert("Assignment Failed", isPresented: errorAlertBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Something went wrong.")
            }
            .task {
                widgetSummaries = assignmentStore.widgetSummaries(for: lesson)
                refreshSourceMathBoardPublishState()
                await refreshAssignmentActivity()
            }
        }
        .frame(minWidth: 520, minHeight: 520)
    }

    private var widgetSummaryText: String {
        guard !widgetSummaries.isEmpty else {
            return "No MathBoard widgets found yet."
        }
        return "^[\(widgetSummaries.count) widget](inflect: true) ready for reporting"
    }

    @ViewBuilder
    private var sourceMathBoardPublishControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(sourceMathBoardStatusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if lesson.publishedVersion != nil {
                Picker("Version", selection: $publishChoice) {
                    ForEach(SourceMathBoardPublishChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.vertical, 4)
    }

    private var sourceMathBoardStatusText: String {
        guard let publishedVersion = lesson.publishedVersion else {
            return "This Source MathBoard has not been published yet. Assigning it will create Published Version 1."
        }
        guard let sourceContentChecksum else {
            return "Checking whether this Source MathBoard has unpublished changes."
        }
        if publishedVersion.sourceContentChecksum == sourceContentChecksum {
            return "Published Version \(publishedVersion.versionNumber) matches the current Source MathBoard."
        }
        return "This Source MathBoard has unpublished changes since Published Version \(publishedVersion.versionNumber)."
    }

    private var sourceMathBoardFooterText: String {
        switch publishChoice {
        case .publishNewVersion:
            "Selected classes will point to a newly frozen Published Version. Existing class assignments stay on their original versions."
        case .useCurrentPublishedVersion:
            "Selected classes will point to the last Published Version. New edits in the Source MathBoard will not be included."
        }
    }

    private var assignmentProgressOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.12))
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text("Assigning lesson...")
                    .font(.headline)
                Text("Uploading the lesson package and creating class access codes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(radius: 18, y: 8)
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )
    }

    private func toggleSelection(for classroom: Classroom) {
        guard !isClassroomLocked(classroom) else { return }
        if selectedClassroomIDs.contains(classroom.id) {
            selectedClassroomIDs.remove(classroom.id)
        } else {
            selectedClassroomIDs.insert(classroom.id)
        }
    }

    private func isClassroomLocked(_ classroom: Classroom) -> Bool {
        guard let assignment = assignmentStore.assignment(for: lesson.id, classroomID: classroom.id) else {
            return false
        }
        return assignmentActivityByID[assignment.id] == true
    }

    private func classroomAssignmentStatusText(_ assignment: ClassroomAssignment) -> String {
        if isCheckingAssignmentActivity {
            return "Checking"
        }
        if assignmentActivityByID[assignment.id] == true {
            return "In use"
        }
        return "Can update"
    }

    private func classroomAssignmentStatusColor(_ assignment: ClassroomAssignment) -> Color {
        assignmentActivityByID[assignment.id] == true ? .orange : .blue
    }

    private func refreshSourceMathBoardPublishState() {
        sourceContentChecksum = try? documentStore.sourceContentChecksum(for: lesson)
        guard let publishedVersion = lesson.publishedVersion else {
            publishChoice = .publishNewVersion
            return
        }
        publishChoice = publishedVersion.sourceContentChecksum == sourceContentChecksum
            ? .useCurrentPublishedVersion
            : .publishNewVersion
    }

    private func refreshAssignmentActivity() async {
        let lessonAssignments = assignmentStore.assignments(for: lesson.id)
        guard !lessonAssignments.isEmpty else {
            assignmentActivityByID = [:]
            return
        }
        isCheckingAssignmentActivity = true
        defer { isCheckingAssignmentActivity = false }

        let syncService = FirebaseClassroomSyncService(
            teacherUserID: teacherAuthStore.state.userID,
            teacherEmail: teacherAuthStore.state.email
        )
        var activity: [UUID: Bool] = [:]
        for assignment in lessonAssignments {
            activity[assignment.id] = await assignmentHasStudentActivity(
                assignment,
                syncService: syncService
            )
        }
        assignmentActivityByID = activity
    }

    private func assignmentHasStudentActivity(
        _ assignment: ClassroomAssignment,
        syncService: FirebaseClassroomSyncService
    ) async -> Bool {
        if assignmentStore.assignmentHasLocalActivity(assignment) {
            return true
        }
        do {
            return try await syncService.assignmentHasStudentActivity(classLessonCode: assignment.classLessonCode)
        } catch {
            return true
        }
    }

    private func assignLesson() async {
        guard let teacherUserID = teacherAuthStore.state.userID else {
            errorMessage = "Sign in with a teacher account before assigning lessons online."
            return
        }

        isAssigning = true
        defer { isAssigning = false }

        do {
            let syncService = FirebaseClassroomSyncService(
                teacherUserID: teacherUserID,
                teacherEmail: teacherAuthStore.state.email
            )
            let latestActivity = try await assignmentActivity(syncService: syncService)
            let blockedAssignments = selectedExistingAssignments()
                .filter { latestActivity[$0.id] == true }
            guard blockedAssignments.isEmpty else {
                let classNames = blockedAssignments
                    .compactMap { assignment in
                        rosterStore.classrooms.first(where: { $0.id == assignment.classroomID })?.name
                    }
                    .joined(separator: ", ")
                errorMessage = "One or more selected classes already have student activity and cannot be reassigned: \(classNames)."
                assignmentActivityByID = latestActivity
                return
            }
            assignmentActivityByID = latestActivity

            let sourceChecksum = try documentStore.sourceContentChecksum(for: lesson)
            let lessonManifest = try await lessonManifest(
                sourceChecksum: sourceChecksum,
                anyAssignmentHasStudentActivity: latestActivity.values.contains(true),
                syncService: syncService
            )
            let newClassroomIDs = selectedActionableClassroomIDs.filter {
                assignmentStore.assignment(for: lesson.id, classroomID: $0) == nil
            }
            let assignments = newClassroomIDs.isEmpty
                ? []
                : try assignmentStore.createAssignments(
                    for: lesson,
                    classroomIDs: Array(newClassroomIDs),
                    widgetSummaries: widgetSummaries,
                    lessonManifest: lessonManifest
                )
            let updatedAssignments = try selectedExistingAssignments().map { assignment in
                try assignmentStore.updateAssignment(
                    assignment,
                    lesson: lesson,
                    widgetSummaries: widgetSummaries,
                    lessonManifest: lessonManifest
                )
            }
            for assignment in assignments + updatedAssignments {
                guard let classroom = rosterStore.classrooms.first(where: { $0.id == assignment.classroomID }) else {
                    throw ClassroomAssignmentStoreError.classroomMismatch
                }
                try await syncService.publishAssignment(
                    assignment,
                    classroom: classroom,
                    lessonManifest: lessonManifest
                )
            }
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func lessonManifest(
        sourceChecksum: String,
        anyAssignmentHasStudentActivity: Bool,
        syncService: FirebaseClassroomSyncService
    ) async throws -> LessonPackageManifest {
        if publishChoice == .useCurrentPublishedVersion,
           let publishedVersion = lesson.publishedVersion {
            return publishedVersion.manifest(sourceLessonID: lesson.id)
        }

        let replacementVersion = anyAssignmentHasStudentActivity ? nil : lesson.publishedVersion
        let manifest = try await syncService.uploadLessonPackage(
            for: lesson,
            replacingPublishedVersion: replacementVersion
        )
        try documentStore.recordPublishedVersion(manifest, sourceContentChecksum: sourceChecksum, for: lesson)
        return manifest
    }

    private func assignmentActivity(
        syncService: FirebaseClassroomSyncService
    ) async throws -> [UUID: Bool] {
        var activity = assignmentActivityByID
        for assignment in assignmentStore.assignments(for: lesson.id) {
            activity[assignment.id] = await assignmentHasStudentActivity(assignment, syncService: syncService)
        }
        return activity
    }

    private func selectedExistingAssignments() -> [ClassroomAssignment] {
        selectedClassroomIDs.compactMap { classroomID in
            assignmentStore.assignment(for: lesson.id, classroomID: classroomID)
        }
    }
}

struct ClassroomAssignmentsView: View {
    @Environment(ClassroomRosterStore.self) private var rosterStore
    @Environment(ClassroomAssignmentStore.self) private var assignmentStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedClassroomID: UUID?
    @State private var selectedAssignmentID: UUID?
    @State private var selectedStudentIDs: Set<UUID> = []

    private var selectedClassroom: Classroom? {
        guard let selectedClassroomID else { return rosterStore.classrooms.first }
        return rosterStore.classrooms.first { $0.id == selectedClassroomID } ?? rosterStore.classrooms.first
    }

    private var selectedAssignment: ClassroomAssignment? {
        guard let selectedAssignmentID else { return assignmentsForSelectedClassroom.first }
        return assignmentsForSelectedClassroom.first { $0.id == selectedAssignmentID } ?? assignmentsForSelectedClassroom.first
    }

    private var assignmentsForSelectedClassroom: [ClassroomAssignment] {
        guard let classroom = selectedClassroom else { return [] }
        return assignmentStore.assignments(forClassroomID: classroom.id)
    }

    var body: some View {
        NavigationStack {
            Group {
                if rosterStore.classrooms.isEmpty {
                    ContentUnavailableView(
                        "No Classroom Rosters",
                        systemImage: "person.3.sequence",
                        description: Text("Import or create classroom rosters before assigning lessons.")
                    )
                } else if assignmentStore.assignments.isEmpty {
                    ContentUnavailableView(
                        "No Assignments Yet",
                        systemImage: "tray",
                        description: Text("Use Assign Lesson from a lesson row to create class assignments.")
                    )
                } else {
                    assignmentBrowser
                }
            }
            .navigationTitle("Assignments / Reports")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                selectedClassroomID = selectedClassroom?.id
                selectedAssignmentID = selectedAssignment?.id
            }
            .onChange(of: selectedClassroomID) { _, _ in
                selectedAssignmentID = assignmentsForSelectedClassroom.first?.id
                selectedStudentIDs = []
            }
        }
        .frame(minWidth: 980, minHeight: 680)
    }

    private var assignmentBrowser: some View {
        HStack(spacing: 0) {
            classSidebar
                .frame(width: 230)

            Divider()

            assignmentList
                .frame(width: 280)

            Divider()

            if let classroom = selectedClassroom, let assignment = selectedAssignment {
                AssignmentReportDetailView(
                    classroom: classroom,
                    assignment: assignment,
                    selectedStudentIDs: $selectedStudentIDs
                )
            } else {
                ContentUnavailableView(
                    "No Assignments",
                    systemImage: "tray",
                    description: Text("Select another class or assign a lesson to this class.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var classSidebar: some View {
        List(selection: $selectedClassroomID) {
            Section("Classes") {
                ForEach(rosterStore.classrooms) { classroom in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(classroom.name)
                            .font(.headline)
                        Text("^[\(assignmentStore.assignments(forClassroomID: classroom.id).count) assignment](inflect: true)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(classroom.id)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.canvasBackground)
    }

    private var assignmentList: some View {
        List(selection: $selectedAssignmentID) {
            Section("Lessons") {
                ForEach(assignmentsForSelectedClassroom) { assignment in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(assignment.lessonTitle)
                            .font(.headline)
                        Text("Code \(assignment.classLessonCode)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.blue)
                        Text("Published Version \(assignment.versionDisplayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("^[\(assignment.widgetSummaries.count) widget](inflect: true)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .tag(assignment.id)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.canvasBackground)
    }
}

private struct AssignmentReportDetailView: View {
    @Environment(ClassroomAssignmentStore.self) private var assignmentStore
    let classroom: Classroom
    let assignment: ClassroomAssignment
    @Binding var selectedStudentIDs: Set<UUID>
    @State private var isRefreshingOnlineScores = false
    @State private var statusMessage: AssignmentReportStatusMessage?
    @State private var studentReportToInspect: StudentLessonReport?
    @State private var widgetSummaryToInspect: AssignedWidgetSummary?

    private var report: ClassroomAssignmentReport? {
        try? assignmentStore.report(
            for: assignment.id,
            classroom: classroom,
            selectedStudentIDs: selectedStudentIDs
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            widgetSummary
            studentToolbar
            studentReportTable
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColors.canvasBackground)
        .alert("Online Scores", isPresented: statusAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(statusMessage?.message ?? "")
        }
        .sheet(item: $studentReportToInspect) { studentReport in
            StudentWidgetReportDetailSheet(
                studentReport: studentReport,
                widgetSummaries: assignment.widgetSummaries
            )
        }
        .sheet(item: $widgetSummaryToInspect) { widget in
            AssignmentWidgetSummaryDetailSheet(
                widget: widget,
                results: widgetResults(for: widget),
                studentCount: classroom.students.count
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(assignment.lessonTitle)
                .font(.title2.weight(.bold))
            HStack(spacing: 12) {
                Label(classroom.name, systemImage: "person.3")
                Label("Code \(assignment.classLessonCode)", systemImage: "number")
                Label("Published Version \(assignment.versionDisplayName)", systemImage: "doc.badge.clock")
                if let classAverage = report?.classAveragePercentScore {
                    Label("\(classAverage.formatted(.number.precision(.fractionLength(0))))%", systemImage: "chart.bar")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private var widgetSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Widgets")
                .font(.headline)
            if assignment.widgetSummaries.isEmpty {
                Text("No MathBoard widgets were found when this lesson was assigned.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(assignment.widgetSummaries) { widget in
                        Button {
                            widgetSummaryToInspect = widget
                        } label: {
                            Text(widget.title)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.regularMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var studentToolbar: some View {
        HStack(spacing: 10) {
            Text("Students")
                .font(.headline)
            Text(selectedStudentIDs.isEmpty ? "All shown" : "\(selectedStudentIDs.count) selected")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                Task {
                    await refreshOnlineScores()
                }
            } label: {
                if isRefreshingOnlineScores {
                    ProgressView()
                } else {
                    Label("Refresh Online Scores", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isRefreshingOnlineScores)
            .accessibilityIdentifier("assignmentReport.refreshOnlineScoresButton")

            Button(selectedStudentIDs.count == classroom.students.count ? "Select None" : "Select All") {
                if selectedStudentIDs.count == classroom.students.count {
                    selectedStudentIDs = []
                } else {
                    selectedStudentIDs = Set(classroom.students.map(\.id))
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var studentReportTable: some View {
        ScrollView(.horizontal) {
            ScrollView {
                LazyVStack(spacing: 8) {
                    reportHeader
                    ForEach(report?.studentReports ?? []) { studentReport in
                        StudentReportRow(
                            report: studentReport,
                            widgetSummaries: assignment.widgetSummaries,
                            isSelected: selectedStudentIDs.contains(studentReport.studentID),
                            onToggleSelection: {
                                toggleSelection(studentReport.studentID)
                            },
                            onInspect: {
                                studentReportToInspect = studentReport
                            }
                        )
                    }
                }
                .frame(minWidth: reportTableMinimumWidth, alignment: .leading)
            }
        }
    }

    private var reportHeader: some View {
        HStack(spacing: 12) {
            Text("")
                .frame(width: 28)
            Text("Student")
                .frame(width: 180, alignment: .leading)
            Text("ID")
                .frame(width: 110, alignment: .leading)
            Text("Alt ID")
                .frame(width: 110, alignment: .leading)
            Text("First Try")
                .frame(width: 80, alignment: .trailing)
            Text("Corrected")
                .frame(width: 80, alignment: .trailing)
            Text("Streak")
                .frame(width: 70, alignment: .trailing)
            Text("Score")
                .frame(width: 70, alignment: .trailing)
            ForEach(assignment.widgetSummaries) { widget in
                Button {
                    widgetSummaryToInspect = widget
                } label: {
                    Text(widget.title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: 96, alignment: .trailing)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
    }

    private var reportTableMinimumWidth: CGFloat {
        28 + 12 + 180 + 12 + 110 + 12 + 110 + 12 + 80 + 12 + 80 + 12 + 70 + 12 + 70 + CGFloat(assignment.widgetSummaries.count) * (12 + 96)
    }

    private var statusAlertBinding: Binding<Bool> {
        Binding(
            get: { statusMessage != nil },
            set: { isPresented in
                if !isPresented {
                    statusMessage = nil
                }
            }
        )
    }

    private func toggleSelection(_ studentID: UUID) {
        if selectedStudentIDs.contains(studentID) {
            selectedStudentIDs.remove(studentID)
        } else {
            selectedStudentIDs.insert(studentID)
        }
    }

    private func widgetResults(for widget: AssignedWidgetSummary) -> [StudentWidgetResult] {
        (report?.studentReports ?? [])
            .flatMap(\.widgetResults)
            .filter { $0.widgetID == widget.widgetID }
    }

    private func refreshOnlineScores() async {
        isRefreshingOnlineScores = true
        defer { isRefreshingOnlineScores = false }

        do {
            let results = try await FirebaseClassroomSyncService()
                .fetchSubmissions(classLessonCode: assignment.classLessonCode)
            let matchingResults = results.filter {
                $0.assignmentID == assignment.id && $0.classroomID == assignment.classroomID
            }
            for result in matchingResults {
                try assignmentStore.recordWidgetResult(result)
            }
            statusMessage = AssignmentReportStatusMessage(
                message: "Imported \(matchingResults.count) online score \(matchingResults.count == 1 ? "submission" : "submissions")."
            )
        } catch {
            statusMessage = AssignmentReportStatusMessage(
                message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }
}

private struct AssignmentReportStatusMessage: Identifiable {
    var id = UUID()
    var message: String
}

private struct StudentReportRow: View {
    let report: StudentLessonReport
    let widgetSummaries: [AssignedWidgetSummary]
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onInspect: () -> Void

    private var firstTryCorrect: Int {
        report.widgetResults.reduce(0) { $0 + $1.numberCorrectFirstTry }
    }

    private var corrected: Int {
        report.widgetResults.reduce(0) { $0 + $1.numberCorrectAfterRetry }
    }

    private var longestStreak: Int {
        report.widgetResults.map(\.longestStreak).max() ?? 0
    }

    private var scoreText: String {
        guard let averagePercentScore = report.averagePercentScore else { return "--" }
        return "\(averagePercentScore.formatted(.number.precision(.fractionLength(0))))%"
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggleSelection) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 28)

            Button(action: onInspect) {
                Text(report.studentName.isEmpty ? "Unnamed Student" : report.studentName)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .frame(width: 180, alignment: .leading)
            Text(report.officialStudentID)
                .frame(width: 110, alignment: .leading)
            Text(report.alternateStudentID)
                .frame(width: 110, alignment: .leading)
            Text("\(firstTryCorrect)")
                .frame(width: 80, alignment: .trailing)
            Text("\(corrected)")
                .frame(width: 80, alignment: .trailing)
            Text("\(longestStreak)")
                .frame(width: 70, alignment: .trailing)
            Text(scoreText)
                .frame(width: 70, alignment: .trailing)
            ForEach(widgetSummaries) { widget in
                Button {
                    onInspect()
                } label: {
                    Text(scoreText(for: widget))
                        .frame(width: 96, alignment: .trailing)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func scoreText(for widget: AssignedWidgetSummary) -> String {
        guard let result = result(for: widget) else { return "--" }
        return "\(result.finalPercentScore.formatted(.number.precision(.fractionLength(0))))%"
    }

    private func result(for widget: AssignedWidgetSummary) -> StudentWidgetResult? {
        report.widgetResults.first { $0.widgetID == widget.widgetID }
    }
}

private struct AssignmentWidgetSummaryDetailSheet: View {
    let widget: AssignedWidgetSummary
    let results: [StudentWidgetResult]
    let studentCount: Int
    @Environment(\.dismiss) private var dismiss

    private var submittedStudentCount: Int {
        Set(results.map(\.studentID)).count
    }

    private var averageScore: Double? {
        guard !results.isEmpty else { return nil }
        return results.reduce(0) { $0 + $1.finalPercentScore } / Double(results.count)
    }

    private var highScore: Double? {
        results.map(\.finalPercentScore).max()
    }

    private var lowScore: Double? {
        results.map(\.finalPercentScore).min()
    }

    private var recentResults: [StudentWidgetResult] {
        Array(results.sorted { $0.submittedAt > $1.submittedAt }.prefix(5))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Full Name", value: widget.title)
                    LabeledContent("Points Possible", value: pointsPossibleText)
                    LabeledContent("Score Type", value: widget.scoreMode.reportDisplayName)
                }

                Section("Class Results") {
                    LabeledContent("Submitted", value: "\(submittedStudentCount) of \(studentCount)")
                    LabeledContent("Class Average", value: percentText(averageScore))
                    LabeledContent("Highest", value: percentText(highScore))
                    LabeledContent("Lowest", value: percentText(lowScore))
                }

                if !recentResults.isEmpty {
                    Section("Recent Submissions") {
                        ForEach(recentResults) { result in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(percentText(result.finalPercentScore))
                                        .font(.headline)
                                    Spacer()
                                    Text(result.submittedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                HStack(spacing: 16) {
                                    Label("\(result.numberCorrectFirstTry) first try", systemImage: "checkmark.circle")
                                    Label("\(result.numberCorrectAfterRetry) corrected", systemImage: "arrow.triangle.2.circlepath")
                                    Label("\(result.longestStreak) streak", systemImage: "flame")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Widget Details")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 480)
    }

    private var pointsPossibleText: String {
        widget.maxScore.formatted(.number.precision(.fractionLength(0)))
    }

    private func percentText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return percentText(value)
    }

    private func percentText(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0))))%"
    }
}

private struct StudentWidgetReportDetailSheet: View {
    let studentReport: StudentLessonReport
    let widgetSummaries: [AssignedWidgetSummary]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Student", value: studentReport.studentName.isEmpty ? "Unnamed Student" : studentReport.studentName)
                    LabeledContent("Student ID", value: studentReport.officialStudentID)
                    LabeledContent("Alternate ID", value: studentReport.alternateStudentID.isEmpty ? "--" : studentReport.alternateStudentID)
                    LabeledContent("Average", value: averageText)
                }

                Section("Widgets") {
                    ForEach(widgetSummaries) { widget in
                        WidgetScoreDetailRow(
                            widget: widget,
                            result: result(for: widget)
                        )
                    }
                }
            }
            .navigationTitle("Student Scores")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 520)
    }

    private var averageText: String {
        guard let averagePercentScore = studentReport.averagePercentScore else { return "--" }
        return "\(averagePercentScore.formatted(.number.precision(.fractionLength(0))))%"
    }

    private func result(for widget: AssignedWidgetSummary) -> StudentWidgetResult? {
        studentReport.widgetResults.first { $0.widgetID == widget.widgetID }
    }
}

private struct WidgetScoreDetailRow: View {
    let widget: AssignedWidgetSummary
    let result: StudentWidgetResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(widget.title)
                    .font(.headline)
                Spacer()
                Text(scoreText)
                    .font(.headline)
                    .foregroundStyle(result == nil ? .secondary : .primary)
            }

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                GridRow {
                    Text("First Try")
                    Text("Corrected")
                    Text("Streak")
                    Text("Submitted")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

                GridRow {
                    Text(result.map { "\($0.numberCorrectFirstTry)" } ?? "--")
                    Text(result.map { "\($0.numberCorrectAfterRetry)" } ?? "--")
                    Text(result.map { "\($0.longestStreak)" } ?? "--")
                    Text(submittedText)
                }
                .font(.subheadline)
            }
        }
        .padding(.vertical, 6)
    }

    private var scoreText: String {
        guard let result else { return "--" }
        return "\(result.finalPercentScore.formatted(.number.precision(.fractionLength(0))))%"
    }

    private var submittedText: String {
        guard let result else { return "--" }
        return result.submittedAt.formatted(date: .abbreviated, time: .shortened)
    }
}

private extension WidgetScoreMode {
    var reportDisplayName: String {
        switch self {
        case .percentAverage:
            "Percent average"
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 600
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > 0 && currentX + size.width > maxWidth {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return CGSize(width: maxWidth, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > bounds.minX && currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
