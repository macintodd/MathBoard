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

private enum AssignmentReportMode: String, CaseIterable, Identifiable {
    case classView
    case compareClasses

    var id: Self { self }

    var title: String {
        switch self {
        case .classView:
            "Class View"
        case .compareClasses:
            "Compare Classes"
        }
    }
}

private enum ClassReportSubview: String, CaseIterable, Identifiable {
    case overview
    case students
    case interactives

    var id: Self { self }

    var title: String {
        switch self {
        case .overview:
            "Overview"
        case .students:
            "Students"
        case .interactives:
            "Interactives"
        }
    }
}

private enum AssignmentReportTheme {
    static let page = Color(red: 0.955, green: 0.935, blue: 0.895)
    static let sidebar = Color(red: 0.905, green: 0.885, blue: 0.845)
    static let card = Color(red: 0.985, green: 0.975, blue: 0.955)
    static let ink = Color(red: 0.075, green: 0.065, blue: 0.055)
    static let muted = Color(red: 0.43, green: 0.395, blue: 0.35)
    static let rule = Color(red: 0.82, green: 0.79, blue: 0.72)
    static let accent = Color(red: 0.78, green: 0.30, blue: 0.21)
    static let green = Color(red: 0.25, green: 0.43, blue: 0.22)
    static let tan = Color(red: 0.88, green: 0.84, blue: 0.77)
}

struct ClassroomAssignmentsView: View {
    @Environment(ClassroomRosterStore.self) private var rosterStore
    @Environment(ClassroomAssignmentStore.self) private var assignmentStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMode: AssignmentReportMode = .classView
    @State private var selectedSubview: ClassReportSubview = .overview
    @State private var selectedClassroomID: UUID?
    @State private var selectedAssignmentID: UUID?
    @State private var selectedStudentIDs: Set<UUID> = []
    @State private var isSidebarCollapsed = false

    private var selectedClassroom: Classroom? {
        guard let selectedClassroomID else { return defaultClassroom }
        return rosterStore.classrooms.first { $0.id == selectedClassroomID } ?? defaultClassroom
    }

    private var defaultClassroom: Classroom? {
        currentClassrooms.first ?? rosterStore.classrooms.first
    }

    private var currentClassrooms: [Classroom] {
        let current = rosterStore.classrooms.filter(\.isCurrent)
        return (current.isEmpty ? rosterStore.classrooms : current)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var selectedAssignment: ClassroomAssignment? {
        guard let selectedAssignmentID else { return assignmentsForSelectedClassroom.first }
        return assignmentsForSelectedClassroom.first { $0.id == selectedAssignmentID } ?? assignmentsForSelectedClassroom.first
    }

    private var assignmentsForSelectedClassroom: [ClassroomAssignment] {
        guard let classroom = selectedClassroom else { return [] }
        return assignmentStore.assignments(forClassroomID: classroom.id)
            .sorted { $0.assignedAt > $1.assignedAt }
    }

    private var recentAssignments: [ClassroomAssignment] {
        Array(assignmentStore.assignments.sorted { $0.assignedAt > $1.assignedAt }.prefix(4))
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AssignmentReportTheme.page)
                } else if assignmentStore.assignments.isEmpty {
                    ContentUnavailableView(
                        "No Assignments Yet",
                        systemImage: "tray",
                        description: Text("Use Assign Lesson from a lesson row to create class assignments.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AssignmentReportTheme.page)
                } else if let classroom = selectedClassroom, let assignment = selectedAssignment {
                    reportWorkspace(classroom: classroom, assignment: assignment)
                } else {
                    ContentUnavailableView(
                        "No Assignments",
                        systemImage: "tray",
                        description: Text("Select another class or assign a lesson to this class.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AssignmentReportTheme.page)
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
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
        .frame(minWidth: 1080, minHeight: 720)
    }

    private func reportWorkspace(classroom: Classroom, assignment: ClassroomAssignment) -> some View {
        HStack(spacing: 0) {
            if isSidebarCollapsed {
                collapsedSidebarButton
                    .frame(width: 54)
            } else {
                reportSidebar(classroom: classroom)
                    .frame(width: 270)
            }

            VStack(spacing: 0) {
                reportPickerBar
                    .padding(.horizontal, 30)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .background(AssignmentReportTheme.page)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(AssignmentReportTheme.rule.opacity(0.75))
                            .frame(height: 1)
                    }

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        reportHeader(classroom: classroom, assignment: assignment)

                        switch selectedMode {
                        case .classView:
                            AssignmentReportDetailView(
                                classroom: classroom,
                                assignment: assignment,
                                selectedSubview: $selectedSubview,
                                selectedStudentIDs: $selectedStudentIDs
                            )
                        case .compareClasses:
                            AssignmentCompareClassesView(
                                baseAssignment: assignment,
                                classrooms: rosterStore.classrooms
                            )
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .background(AssignmentReportTheme.page)
            }
        }
        .background(AssignmentReportTheme.page)
    }

    private var collapsedSidebarButton: some View {
        VStack(spacing: 10) {
            Button {
                isSidebarCollapsed = false
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AssignmentReportTheme.ink)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show reports sidebar")

            Text("Reports")
                .font(.caption2.weight(.bold))
                .foregroundStyle(AssignmentReportTheme.muted)
                .rotationEffect(.degrees(-90))
                .fixedSize()
                .padding(.top, 28)

            Spacer()
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AssignmentReportTheme.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AssignmentReportTheme.rule.opacity(0.7))
                .frame(width: 1)
        }
    }

    private func reportSidebar(classroom: Classroom) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) {
                Image(systemName: "book.pages.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(AssignmentReportTheme.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Lesson Library")
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(AssignmentReportTheme.ink)
                    Text("Reports Workspace")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AssignmentReportTheme.muted)
                }
                Spacer(minLength: 0)
                Button {
                    isSidebarCollapsed = true
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AssignmentReportTheme.muted)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Collapse reports sidebar")
            }
            .padding(.top, 22)

            VStack(alignment: .leading, spacing: 10) {
                Text("Class Management")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AssignmentReportTheme.muted)
                    .textCase(.uppercase)
                sidebarButton("Reports Home", systemImage: "square.grid.2x2", isSelected: false) { }
                sidebarButton("Class View", systemImage: "clipboard", isSelected: selectedMode == .classView) {
                    selectedMode = .classView
                }
                sidebarButton("Compare Classes", systemImage: "chart.bar.xaxis", isSelected: selectedMode == .compareClasses) {
                    selectedMode = .compareClasses
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Recent Lessons")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AssignmentReportTheme.muted)
                    .textCase(.uppercase)

                ForEach(recentAssignments) { recentAssignment in
                    Button {
                        selectAssignment(recentAssignment)
                    } label: {
                        RecentLessonRow(
                            title: recentAssignment.lessonTitle,
                            detail: quickAssignmentDetail(recentAssignment),
                            accent: recentAssignment.id == selectedAssignment?.id ? AssignmentReportTheme.accent : AssignmentReportTheme.green.opacity(0.65),
                            isSelected: recentAssignment.id == selectedAssignment?.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 20)

            HStack(spacing: 12) {
                Circle()
                    .fill(AssignmentReportTheme.green)
                    .frame(width: 42, height: 42)
                    .overlay {
                        Text(teacherInitials)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Teacher")
                        .font(.headline.weight(.bold))
                    Text("^[\(currentClassrooms.count) active class](inflect: true)")
                        .font(.caption)
                        .foregroundStyle(AssignmentReportTheme.muted)
                }
            }
            .padding(.bottom, 18)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AssignmentReportTheme.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AssignmentReportTheme.rule.opacity(0.7))
                .frame(width: 1)
        }
    }

    private func sidebarButton(_ title: String, systemImage: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? AssignmentReportTheme.ink : AssignmentReportTheme.muted)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 12)
                .background(isSelected ? Color.white.opacity(0.82) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var reportPickerBar: some View {
        HStack(alignment: .top, spacing: 18) {
            PickerField(title: "Class") {
                Picker("Class", selection: selectedClassroomBinding) {
                    ForEach(currentClassrooms) { classroom in
                        Text(classroom.name).tag(Optional(classroom.id))
                    }
                }
                .labelsHidden()
            }
            .frame(maxWidth: 300)

            PickerField(title: "Lesson") {
                Picker("Lesson", selection: selectedAssignmentBinding) {
                    ForEach(assignmentsForSelectedClassroom) { assignment in
                        Text(assignment.lessonTitle).tag(Optional(assignment.id))
                    }
                }
                .labelsHidden()
            }
            .frame(maxWidth: 330)

            Spacer(minLength: 12)

            Picker("Report", selection: $selectedMode) {
                Label("Class View", systemImage: "list.bullet.rectangle").tag(AssignmentReportMode.classView)
                Label("Compare Classes", systemImage: "chart.bar.xaxis").tag(AssignmentReportMode.compareClasses)
            }
            .pickerStyle(.segmented)
            .frame(width: 360)
        }
    }

    private func reportHeader(classroom: Classroom, assignment: ClassroomAssignment) -> some View {
        let report = try? assignmentStore.report(for: assignment.id, classroom: classroom, selectedStudentIDs: selectedStudentIDs)
        let completed = submittedStudentCount(report: report)
        let average = percentText(report?.classAveragePercentScore)
        let highLow = highLowText(report: report)

        return HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text(selectedMode == .classView ? "Lesson Report" : "Cross-Class Report")
                .font(.caption.weight(.heavy))
                .foregroundStyle(AssignmentReportTheme.accent)
                .textCase(.uppercase)

            Text("\(completed) of \(classroom.students.count) students completed")
                .font(.headline.weight(.semibold))
                .foregroundStyle(AssignmentReportTheme.green)

            Spacer(minLength: 18)

            HStack(spacing: 16) {
                reportHeaderMetric("Average", average)
                Rectangle()
                    .fill(AssignmentReportTheme.rule)
                    .frame(width: 1, height: 36)
                reportHeaderMetric("High / Low", highLow)
            }
        }
    }

    private func reportHeaderMetric(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(AssignmentReportTheme.muted)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(AssignmentReportTheme.ink)
                .monospacedDigit()
        }
    }

    private func submittedStudentCount(report: ClassroomAssignmentReport?) -> Int {
        Set((report?.studentReports ?? []).flatMap { studentReport in
            studentReport.widgetResults.map { $0.studentID }
        }).count
    }

    private func highLowText(report: ClassroomAssignmentReport?) -> String {
        let scores = (report?.studentReports ?? []).compactMap(\.averagePercentScore)
        guard let high = scores.max(), let low = scores.min() else { return "-- / --" }
        return "\(high.formatted(.number.precision(.fractionLength(0)))) / \(low.formatted(.number.precision(.fractionLength(0))))"
    }

    private func percentText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(value.formatted(.number.precision(.fractionLength(0))))%"
    }

    private var selectedClassroomBinding: Binding<UUID?> {
        Binding(
            get: { selectedClassroom?.id },
            set: { selectedClassroomID = $0 }
        )
    }

    private var selectedAssignmentBinding: Binding<UUID?> {
        Binding(
            get: { selectedAssignment?.id },
            set: { selectedAssignmentID = $0 }
        )
    }

    private func quickAssignmentDetail(_ assignment: ClassroomAssignment) -> String {
        let className = rosterStore.classrooms.first { $0.id == assignment.classroomID }?.name ?? "Class"
        let dateText = Calendar.current.isDateInToday(assignment.assignedAt)
            ? "Today"
            : assignment.assignedAt.formatted(date: .abbreviated, time: .omitted)
        return "\(className) · \(dateText)"
    }

    private func selectClassroom(_ classroomID: UUID) {
        selectedClassroomID = classroomID
        selectedAssignmentID = assignmentStore.assignments(forClassroomID: classroomID)
            .sorted { $0.assignedAt > $1.assignedAt }
            .first?.id
        selectedStudentIDs = []
    }

    private func selectAssignment(_ assignment: ClassroomAssignment) {
        selectedClassroomID = assignment.classroomID
        selectedAssignmentID = assignment.id
        selectedStudentIDs = []
    }

    private var teacherInitials: String { "MA" }
}

private struct AssignmentReportDetailView: View {
    @Environment(ClassroomAssignmentStore.self) private var assignmentStore
    let classroom: Classroom
    let assignment: ClassroomAssignment
    @Binding var selectedSubview: ClassReportSubview
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
        VStack(alignment: .leading, spacing: 18) {
            classViewTabs
            switch selectedSubview {
            case .overview:
                overviewDashboard
            case .students:
                studentToolbar
                studentReportTable
            case .interactives:
                interactivesDashboard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    private var classViewTabs: some View {
        HStack(spacing: 34) {
            ForEach(ClassReportSubview.allCases) { subview in
                Button {
                    selectedSubview = subview
                } label: {
                    VStack(spacing: 9) {
                        Text(subview.title)
                            .font(.headline.weight(selectedSubview == subview ? .bold : .semibold))
                            .foregroundStyle(selectedSubview == subview ? AssignmentReportTheme.ink : AssignmentReportTheme.muted)
                        Rectangle()
                            .fill(selectedSubview == subview ? AssignmentReportTheme.accent : Color.clear)
                            .frame(height: 2)
                    }
                    .frame(minWidth: 98)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 16)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AssignmentReportTheme.rule.opacity(0.75))
                .frame(height: 1)
        }
    }

    private var summaryMetrics: some View {
        HStack(spacing: 10) {
            ReportMetricTile(
                title: "Class Average",
                value: percentText(report?.classAveragePercentScore),
                systemImage: "chart.bar.fill",
                tint: .green
            )
            ReportMetricTile(
                title: "Completed",
                value: "\(submittedStudentCount) / \(classroom.students.count)",
                systemImage: "checkmark.circle.fill",
                tint: .blue
            )
            ReportMetricTile(
                title: "Interactives",
                value: "\(assignment.widgetSummaries.count)",
                systemImage: "square.grid.2x2.fill",
                tint: AppColors.accent
            )
            ReportMetricTile(
                title: "Best Interactive",
                value: bestWidgetSnapshot?.shortTitle ?? "--",
                systemImage: "star.fill",
                tint: .orange
            )
        }
    }

    private var overviewDashboard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                reportColumnHeader("Interactive", width: nil, alignment: .leading)
                reportColumnHeader("Completed", width: 130, alignment: .trailing)
                reportColumnHeader("Correct First Try", width: 230, alignment: .leading)
                reportColumnHeader("Correct Second Try", width: 230, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(AssignmentReportTheme.tan.opacity(0.45))

            ForEach(widgetSnapshots) { snapshot in
                Button {
                    widgetSummaryToInspect = snapshot.widget
                } label: {
                    OverviewInteractiveRow(snapshot: snapshot, studentCount: classroom.students.count)
                }
                .buttonStyle(.plain)

                if snapshot.id != widgetSnapshots.last?.id {
                    Divider()
                        .overlay(AssignmentReportTheme.rule.opacity(0.45))
                }
            }
        }
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AssignmentReportTheme.rule.opacity(0.5), lineWidth: 1)
        )
    }

    private func reportColumnHeader(_ title: String, width: CGFloat?, alignment: Alignment) -> some View {
        Text(title)
            .font(.caption.weight(.heavy))
            .foregroundStyle(AssignmentReportTheme.muted)
            .textCase(.uppercase)
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
    }

    private var interactivesDashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if assignment.widgetSummaries.isEmpty {
                    Text("No MathBoard widgets were found when this lesson was assigned.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(widgetSnapshots) { snapshot in
                    Button {
                        widgetSummaryToInspect = snapshot.widget
                    } label: {
                        InteractiveDetailRow(snapshot: snapshot, studentCount: classroom.students.count)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var submittedStudentCount: Int {
        Set((report?.studentReports ?? []).flatMap { studentReport in
            studentReport.widgetResults.map { $0.studentID }
        }).count
    }

    private var widgetSnapshots: [AssignmentWidgetSnapshot] {
        assignment.widgetSummaries.enumerated().map { index, widget in
            AssignmentWidgetSnapshot(
                index: index,
                widget: widget,
                results: widgetResults(for: widget)
            )
        }
    }

    private var bestWidgetSnapshot: AssignmentWidgetSnapshot? {
        widgetSnapshots
            .filter { $0.averageScore != nil }
            .max { ($0.averageScore ?? 0) < ($1.averageScore ?? 0) }
    }

    private func percentText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(value.formatted(.number.precision(.fractionLength(0))))%"
    }

    private var studentToolbar: some View {
        HStack(spacing: 10) {
            Text("Students")
                .font(.headline.weight(.bold))
                .foregroundStyle(AssignmentReportTheme.ink)
            Text(selectedStudentIDs.isEmpty ? "All shown" : "\(selectedStudentIDs.count) selected")
                .font(.subheadline)
                .foregroundStyle(AssignmentReportTheme.muted)
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
            .tint(AssignmentReportTheme.accent)
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
            .tint(AssignmentReportTheme.accent)
        }
    }

    private var studentReportTable: some View {
        let studentReports = report?.studentReports ?? []

        return ScrollView {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    fixedReportHeader
                    ForEach(studentReports) { studentReport in
                        FixedStudentReportCell(
                            report: studentReport,
                            isSelected: selectedStudentIDs.contains(studentReport.studentID),
                            onToggleSelection: {
                                toggleSelection(studentReport.studentID)
                            },
                            onInspect: {
                                studentReportToInspect = studentReport
                            }
                        )

                        if studentReport.id != studentReports.last?.id {
                            Divider()
                                .overlay(AssignmentReportTheme.rule.opacity(0.45))
                        }
                    }
                }
                .frame(width: fixedStudentColumnWidth, alignment: .leading)
                .background(Color.white.opacity(0.86))
                .zIndex(1)

                ScrollView(.horizontal) {
                    VStack(spacing: 0) {
                        scoreReportHeader
                        ForEach(studentReports) { studentReport in
                            StudentScoreReportRow(
                                report: studentReport,
                                widgetSummaries: assignment.widgetSummaries,
                                teacherPoints: teacherPoints(for: studentReport.studentID)
                            )

                            if studentReport.id != studentReports.last?.id {
                                Divider()
                                    .overlay(AssignmentReportTheme.rule.opacity(0.45))
                            }
                        }
                    }
                    .frame(minWidth: scoreTableMinimumWidth, alignment: .leading)
                }
            }
            .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(AssignmentReportTheme.rule.opacity(0.5), lineWidth: 1)
            )
        }
    }

    private var fixedReportHeader: some View {
        HStack(spacing: 12) {
            Text("")
                .frame(width: 28)
            Text("Student")
                .frame(width: studentNameColumnWidth, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .bottomLeading)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(AssignmentReportTheme.muted)
        .padding(.horizontal, 12)
        .frame(height: reportHeaderHeight)
        .background(AssignmentReportTheme.tan.opacity(0.45))
    }

    private var scoreReportHeader: some View {
        HStack(spacing: 12) {
            Text("Teacher Pts")
                .frame(width: teacherPointsColumnWidth, alignment: .trailing)
            ForEach(assignment.widgetSummaries) { widget in
                Button {
                    widgetSummaryToInspect = widget
                } label: {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(widget.title)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text("\(widget.maxScore.formatted(.number.precision(.fractionLength(0)))) pts")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AssignmentReportTheme.green)
                    }
                    .frame(width: widgetScoreColumnWidth, alignment: .trailing)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(AssignmentReportTheme.muted)
        .padding(.horizontal, 12)
        .frame(height: reportHeaderHeight)
        .background(AssignmentReportTheme.tan.opacity(0.45))
    }

    private var fixedStudentColumnWidth: CGFloat {
        28 + 12 + studentNameColumnWidth + 24
    }

    private var scoreTableMinimumWidth: CGFloat {
        teacherPointsColumnWidth + CGFloat(assignment.widgetSummaries.count) * (12 + widgetScoreColumnWidth)
    }

    private var studentNameColumnWidth: CGFloat {
        230
    }

    private var teacherPointsColumnWidth: CGFloat {
        96
    }

    private var widgetScoreColumnWidth: CGFloat {
        132
    }

    private var reportHeaderHeight: CGFloat {
        70
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

    private func teacherPoints(for studentID: UUID) -> Int {
        assignmentStore.localWidgetScore(
            assignmentID: assignment.id,
            widgetID: assignment.id,
            studentID: studentID
        )?.points ?? 0
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

private struct AssignmentCompareClassesView: View {
    @Environment(ClassroomAssignmentStore.self) private var assignmentStore
    let baseAssignment: ClassroomAssignment
    let classrooms: [Classroom]

    private var comparableRows: [ClassComparisonRow] {
        assignmentStore.assignments
            .filter { $0.lessonID == baseAssignment.lessonID }
            .compactMap { assignment in
                guard let classroom = classrooms.first(where: { $0.id == assignment.classroomID }),
                      let report = try? assignmentStore.report(for: assignment.id, classroom: classroom) else {
                    return nil
                }
                return ClassComparisonRow(classroom: classroom, assignment: assignment, report: report)
            }
            .sorted { $0.classroom.name.localizedStandardCompare($1.classroom.name) == .orderedAscending }
    }

    private var widgetTitles: [String] {
        baseAssignment.widgetSummaries.map(\.title)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    ReportMetricTile(
                        title: "Classes",
                        value: "\(comparableRows.count)",
                        systemImage: "person.3.fill",
                        tint: .blue
                    )
                    ReportMetricTile(
                        title: "Students",
                        value: "\(comparableRows.reduce(0) { $0 + $1.classroom.students.count })",
                        systemImage: "graduationcap.fill",
                        tint: .green
                    )
                    ReportMetricTile(
                        title: "Overall Average",
                        value: percentText(overallAverage),
                        systemImage: "chart.line.uptrend.xyaxis",
                        tint: AssignmentReportTheme.accent
                    )
                }

                compareSummaryTable
                compareInteractiveHeatmap
            }
            .padding(.vertical, 2)
        }
    }

    private var compareSummaryTable: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Class Summary")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow {
                    Text("Class")
                    Text("Students")
                    Text("Completed")
                    Text("Average")
                    Text("Best Interactive")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

                ForEach(comparableRows) { row in
                    GridRow {
                        Text(row.classroom.name)
                            .frame(minWidth: 180, alignment: .leading)
                        Text("\(row.classroom.students.count)")
                        Text("\(row.submittedStudentCount)")
                        Text(percentText(row.report.classAveragePercentScore))
                            .fontWeight(.semibold)
                        Text(row.bestWidgetTitle ?? "--")
                            .lineLimit(1)
                    }
                    .font(.subheadline)
                }
            }
        }
        .reportPanel()
    }

    private var compareInteractiveHeatmap: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Interactive Performance by Class")
                .font(.headline)
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        Text("Interactive")
                            .frame(width: 220, alignment: .leading)
                        ForEach(comparableRows) { row in
                            Text(row.shortClassName)
                                .frame(width: 76, alignment: .center)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                    ForEach(Array(widgetTitles.enumerated()), id: \.offset) { index, title in
                        GridRow {
                            Text("\(index + 1). \(title)")
                                .lineLimit(1)
                                .frame(width: 220, alignment: .leading)
                            ForEach(comparableRows) { row in
                                let value = row.averageScore(forWidgetAt: index)
                                Text(percentText(value))
                                    .font(.caption.weight(.semibold))
                                    .frame(width: 76, height: 30)
                                    .background(scoreTint(value), in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }
            }
        }
        .reportPanel()
    }

    private var overallAverage: Double? {
        let averages = comparableRows.compactMap { $0.report.classAveragePercentScore }
        guard !averages.isEmpty else { return nil }
        return averages.reduce(0, +) / Double(averages.count)
    }

    private func percentText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(value.formatted(.number.precision(.fractionLength(0))))%"
    }

    private func scoreTint(_ value: Double?) -> Color {
        guard let value else { return Color.secondary.opacity(0.12) }
        if value >= 85 { return Color.green.opacity(0.18) }
        if value >= 70 { return Color.yellow.opacity(0.22) }
        return Color.red.opacity(0.16)
    }
}

private struct ClassComparisonRow: Identifiable {
    var id: UUID { assignment.id }
    let classroom: Classroom
    let assignment: ClassroomAssignment
    let report: ClassroomAssignmentReport

    var shortClassName: String {
        classroom.name
            .split(separator: " ")
            .last
            .map(String.init) ?? classroom.name
    }

    var submittedStudentCount: Int {
        Set(report.studentReports.flatMap { studentReport in
            studentReport.widgetResults.map { $0.studentID }
        }).count
    }

    var bestWidgetTitle: String? {
        assignment.widgetSummaries.enumerated()
            .compactMap { index, widget -> (String, Double)? in
                guard let average = averageScore(forWidgetAt: index) else { return nil }
                return (widget.title, average)
            }
            .max { $0.1 < $1.1 }?.0
    }

    func averageScore(forWidgetAt index: Int) -> Double? {
        guard assignment.widgetSummaries.indices.contains(index) else { return nil }
        let widget = assignment.widgetSummaries[index]
        let results = report.studentReports
            .flatMap(\.widgetResults)
            .filter { $0.widgetID == widget.widgetID }
        guard !results.isEmpty else { return nil }
        return results.reduce(0) { $0 + $1.finalPercentScore } / Double(results.count)
    }
}

private struct AssignmentWidgetSnapshot: Identifiable {
    var id: UUID { widget.id }
    let index: Int
    let widget: AssignedWidgetSummary
    let results: [StudentWidgetResult]

    var submittedStudentCount: Int {
        Set(results.map(\.studentID)).count
    }

    var averageScore: Double? {
        guard !results.isEmpty else { return nil }
        return results.reduce(0) { $0 + $1.finalPercentScore } / Double(results.count)
    }

    var firstTryTotal: Int {
        results.reduce(0) { $0 + $1.numberCorrectFirstTry }
    }

    var correctedTotal: Int {
        results.reduce(0) { $0 + $1.numberCorrectAfterRetry }
    }

    var highScore: Double? {
        results.map(\.finalPercentScore).max()
    }

    var lowScore: Double? {
        results.map(\.finalPercentScore).min()
    }

    var shortTitle: String {
        widget.title
    }

    var iconName: String {
        switch index % 4 {
        case 0: "plus.forwardslash.minus"
        case 1: "list.bullet.rectangle"
        case 2: "doc.text.fill"
        default: "link"
        }
    }

    var tint: Color {
        switch index % 4 {
        case 0: .blue
        case 1: .purple
        case 2: .green
        default: .orange
        }
    }

    func percentText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(value.formatted(.number.precision(.fractionLength(0))))%"
    }
}

private struct PickerField<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.heavy))
                .foregroundStyle(AssignmentReportTheme.muted)
                .textCase(.uppercase)
            content
                .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                .padding(.horizontal, 8)
                .background(Color.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(AssignmentReportTheme.rule.opacity(0.55), lineWidth: 1)
                )
        }
    }
}

private struct RecentLessonRow: View {
    let title: String
    let detail: String
    let accent: Color
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accent)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AssignmentReportTheme.ink)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AssignmentReportTheme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .background(isSelected ? Color.white.opacity(0.54) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AssignmentReportTheme.rule.opacity(0.55), lineWidth: 1)
        )
    }
}

private struct OverviewInteractiveRow: View {
    let snapshot: AssignmentWidgetSnapshot
    let studentCount: Int

    private var firstTryPercent: Double? {
        percent(total: snapshot.firstTryTotal)
    }

    private var correctedPercent: Double? {
        percent(total: snapshot.correctedTotal)
    }

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: snapshot.iconName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AssignmentReportTheme.green)
                    .frame(width: 42, height: 42)
                    .background(AssignmentReportTheme.tan.opacity(0.7), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.widget.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AssignmentReportTheme.ink)
                        .lineLimit(1)
                    Text("Event \(snapshot.index + 1) · \(snapshot.widget.maxScore.formatted(.number.precision(.fractionLength(0)))) pts")
                        .font(.caption)
                        .foregroundStyle(AssignmentReportTheme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(snapshot.submittedStudentCount) / \(studentCount)")
                .font(.title3.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(AssignmentReportTheme.ink)
                .frame(width: 130, alignment: .trailing)

            OverviewProgressMetric(value: firstTryPercent, tint: AssignmentReportTheme.green)
                .frame(width: 230)

            OverviewProgressMetric(value: correctedPercent, tint: AssignmentReportTheme.accent)
                .frame(width: 230)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .contentShape(Rectangle())
    }

    private func percent(total: Int) -> Double? {
        guard !snapshot.results.isEmpty, snapshot.widget.maxScore > 0 else { return nil }
        let denominator = snapshot.widget.maxScore * Double(snapshot.results.count)
        return min(100, max(0, Double(total) / denominator * 100))
    }
}

private struct OverviewProgressMetric: View {
    let value: Double?
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Text(percentText)
                .font(.subheadline.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(value == nil ? AssignmentReportTheme.muted : tint)
                .frame(width: 46, alignment: .trailing)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AssignmentReportTheme.tan.opacity(0.7))
                    Capsule()
                        .fill(tint)
                        .frame(width: proxy.size.width * CGFloat((value ?? 0) / 100))
                }
            }
            .frame(height: 7)
        }
    }

    private var percentText: String {
        guard let value else { return "--" }
        return "\(value.formatted(.number.precision(.fractionLength(0))))%"
    }
}

private struct QuickAccessRow: View {
    let title: String
    let detail: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.caption.weight(.bold))
                .foregroundStyle(isSelected ? AppColors.accent : .secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .background(isSelected ? AppColors.accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ReportMetricTile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(AssignmentReportTheme.tan.opacity(0.7), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(AssignmentReportTheme.muted)
                    .textCase(.uppercase)
                Text(value)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AssignmentReportTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AssignmentReportTheme.rule.opacity(0.5), lineWidth: 1)
        )
    }
}

private struct WidgetOverviewCard: View {
    let snapshot: AssignmentWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: snapshot.iconName)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(snapshot.tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Spacer()
                Text(snapshot.percentText(snapshot.averageScore))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(scoreColor(snapshot.averageScore))
            }

            Text("\(snapshot.index + 1). \(snapshot.widget.title)")
                .font(.headline)
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 5) {
                LabeledContent("Completed", value: "\(snapshot.submittedStudentCount)")
                LabeledContent("First Try", value: "\(snapshot.firstTryTotal)")
                LabeledContent("After Corrections", value: "\(snapshot.correctedTotal)")
            }
            .font(.caption)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(scoreColor(snapshot.averageScore).opacity(0.18), lineWidth: 1)
        )
    }

    private func scoreColor(_ value: Double?) -> Color {
        guard let value else { return .secondary }
        if value >= 85 { return .green }
        if value >= 70 { return .orange }
        return .red
    }
}

private struct InteractiveDetailRow: View {
    let snapshot: AssignmentWidgetSnapshot
    let studentCount: Int

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: snapshot.iconName)
                .font(.headline)
                .foregroundStyle(AssignmentReportTheme.green)
                .frame(width: 38, height: 38)
                .background(AssignmentReportTheme.tan.opacity(0.7), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("\(snapshot.index + 1). \(snapshot.widget.title)")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AssignmentReportTheme.ink)
                Text("\(snapshot.submittedStudentCount) of \(studentCount) submitted • \(snapshot.widget.maxScore.formatted(.number.precision(.fractionLength(0)))) points")
                    .font(.caption)
                    .foregroundStyle(AssignmentReportTheme.muted)
            }

            Spacer()

            Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 4) {
                GridRow {
                    Text("Avg")
                    Text("High")
                    Text("Low")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AssignmentReportTheme.muted)

                GridRow {
                    Text(snapshot.percentText(snapshot.averageScore))
                    Text(snapshot.percentText(snapshot.highScore))
                    Text(snapshot.percentText(snapshot.lowScore))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AssignmentReportTheme.ink)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AssignmentReportTheme.rule.opacity(0.5), lineWidth: 1)
        )
    }
}

private extension View {
    func reportPanel() -> some View {
        padding(14)
            .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(AssignmentReportTheme.rule.opacity(0.5), lineWidth: 1)
            )
    }
}
private struct AssignmentReportStatusMessage: Identifiable {
    var id = UUID()
    var message: String
}

private enum AssignmentReportTableMetrics {
    static let selectionWidth: CGFloat = 28
    static let studentNameWidth: CGFloat = 230
    static let teacherPointsWidth: CGFloat = 96
    static let widgetScoreWidth: CGFloat = 132
    static let horizontalPadding: CGFloat = 12
    static let rowHeight: CGFloat = 76
}

private struct FixedStudentReportCell: View {
    let report: StudentLessonReport
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onInspect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggleSelection) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AssignmentReportTheme.accent : AssignmentReportTheme.muted)
            }
            .buttonStyle(.plain)
            .frame(width: AssignmentReportTableMetrics.selectionWidth)

            Button(action: onInspect) {
                Text(report.studentName.isEmpty ? "Unnamed Student" : report.studentName)
                    .fontWeight(.semibold)
                    .foregroundStyle(AssignmentReportTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            .buttonStyle(.plain)
            .frame(width: AssignmentReportTableMetrics.studentNameWidth, alignment: .leading)
        }
        .font(.subheadline)
        .foregroundStyle(AssignmentReportTheme.ink)
        .padding(.horizontal, AssignmentReportTableMetrics.horizontalPadding)
        .frame(height: AssignmentReportTableMetrics.rowHeight)
        .background(isSelected ? AssignmentReportTheme.accent.opacity(0.08) : Color.clear)
    }
}

private struct StudentScoreReportRow: View {
    let report: StudentLessonReport
    let widgetSummaries: [AssignedWidgetSummary]
    let teacherPoints: Int

    var body: some View {
        HStack(spacing: 12) {
            Text("\(teacherPoints)")
                .fontWeight(teacherPoints > 0 ? .semibold : .regular)
                .foregroundStyle(teacherPoints > 0 ? AssignmentReportTheme.green : AssignmentReportTheme.muted)
                .frame(width: AssignmentReportTableMetrics.teacherPointsWidth, alignment: .trailing)
            ForEach(widgetSummaries) { widget in
                Text(scoreText(for: widget))
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(result(for: widget) == nil ? AssignmentReportTheme.muted : AssignmentReportTheme.ink)
                    .frame(width: AssignmentReportTableMetrics.widgetScoreWidth, alignment: .trailing)
            }
        }
        .font(.subheadline)
        .foregroundStyle(AssignmentReportTheme.ink)
        .padding(.horizontal, AssignmentReportTableMetrics.horizontalPadding)
        .frame(height: AssignmentReportTableMetrics.rowHeight)
    }

    private func scoreText(for widget: AssignedWidgetSummary) -> String {
        guard let result = result(for: widget) else { return "--" }
        let earnedPoints = Double(widget.maxScore) * result.finalPercentScore / 100
        return "\(result.numberCorrectFirstTry)/\(result.longestStreak)/\(pointsText(earnedPoints))"
    }

    private func result(for widget: AssignedWidgetSummary) -> StudentWidgetResult? {
        report.widgetResults.first { $0.widgetID == widget.widgetID }
    }

    private func pointsText(_ points: Double) -> String {
        if points.rounded() == points {
            return points.formatted(.number.precision(.fractionLength(0)))
        }
        return points.formatted(.number.precision(.fractionLength(1)))
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
