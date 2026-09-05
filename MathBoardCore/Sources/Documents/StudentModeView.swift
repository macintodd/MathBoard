import SwiftUI
import FirebaseFirestore
import LiveClassroom
import Slides
import WidgetEngine

public struct StudentModeView: View {
    @Environment(MathBoardUserModeStore.self) private var modeStore
    @Environment(ClassroomRosterStore.self) private var rosterStore
    @Environment(ClassroomAssignmentStore.self) private var assignmentStore
    @Environment(DocumentStore.self) private var documentStore
    @AppStorage("MathBoardStudentPreferredFirstName") private var studentPreferredFirstName = ""
    @AppStorage("MathBoardStudentIdentifier") private var studentIdentifier = ""
    @State private var lessonCode = ""
    @State private var selectedWidgetID: UUID?
    @State private var score = 0
    @State private var attempts = 1
    @State private var numberCorrectFirstTry = 0
    @State private var numberCorrectAfterRetry = 0
    @State private var longestStreak = 0
    @State private var statusMessage: StudentSubmissionStatusMessage?
    @State private var remoteAssignmentPacket: AssignmentSyncPacket?
    @State private var remoteAssignmentCode = ""
    @State private var isFindingOnlineLesson = false
    @State private var hasSearchedOnlineLesson = false
    @State private var scoreDraftsByWidgetID: [UUID: StudentWidgetScoreDraft] = [:]
    @State private var submittedWidgetIDs: Set<UUID> = []
    @State private var liveProgressTask: Task<Void, Never>?
    @State private var isDownloadingLesson = false
    @State private var openedAssignedLesson: StudentAssignedLessonDestination?
    @State private var isStudentProfilePresented = false
    @State private var openedLessonCatalog: [StudentOpenedAssignedLessonRecord] = []
    @State private var catalogFolders: [StudentOpenedAssignedLessonFolder] = StudentOpenedAssignedLessonFolder.defaultFolders
    @State private var selectedCatalogFolderID = StudentOpenedAssignedLessonFolder.allLessonsID
    @State private var isNewCatalogFolderPresented = false
    @State private var newCatalogFolderName = ""

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 18) {
                            accessForm
                            catalogFoldersView
                        }
                        .frame(width: 330)

                        openedLessonsCatalogView
                            .frame(maxWidth: .infinity, alignment: .top)
                    }

                    assignmentStatusView
                }
                .padding(24)
                .frame(maxWidth: 1180, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(AppColors.canvasBackground.ignoresSafeArea())
            .navigationTitle("MathBoard Student")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        modeStore.switchToTeacherMode()
                    } label: {
                        Label("Teacher Mode", systemImage: "graduationcap")
                    }
                }
            }
            .alert("Submission", isPresented: statusAlertBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(statusMessage?.message ?? "")
            }
            .onChange(of: resolvedAssignmentPacket?.id) { _, _ in
                syncSelectedWidget()
            }
            .onChange(of: normalizedLessonCode) { _, newCode in
                liveProgressTask?.cancel()
                publishCurrentWidgetAsInactive()
                if newCode != remoteAssignmentCode {
                    remoteAssignmentPacket = nil
                    remoteAssignmentCode = ""
                }
                hasSearchedOnlineLesson = false
                scoreDraftsByWidgetID = [:]
                submittedWidgetIDs = []
            }
            .onChange(of: studentIdentifier) { _, _ in
                resetResolvedOnlineAssignmentState()
                loadStudentCatalogState()
            }
            .onChange(of: studentPreferredFirstName) { _, _ in
                scheduleLiveProgressUpdate()
            }
            .onChange(of: selectedWidgetID) { _, _ in
                scheduleLiveProgressUpdate()
            }
            .onChange(of: currentScoreDraft) { _, _ in
                scheduleLiveProgressUpdate()
            }
            .sheet(isPresented: $isStudentProfilePresented) {
                StudentProfileSettingsView(
                    preferredFirstName: $studentPreferredFirstName,
                    studentIdentifier: $studentIdentifier
                )
                .interactiveDismissDisabled(!hasCompleteStudentProfile)
            }
            .sheet(isPresented: $isNewCatalogFolderPresented) {
                StudentCatalogFolderSheet(
                    folderName: $newCatalogFolderName,
                    onSave: { folderName in
                        addCatalogFolder(named: folderName)
                    }
                )
            }
            .onAppear {
                loadStudentCatalogState()
                if !hasCompleteStudentProfile {
                    isStudentProfilePresented = true
                }
            }
            .onDisappear {
                liveProgressTask?.cancel()
                publishCurrentWidgetAsInactive()
            }
            .navigationDestination(item: $openedAssignedLesson) { destination in
                StudentAssignedLessonView(
                    destination: destination,
                    submittedWidgetIDs: submittedWidgetIDs
                )
            }
        }
    }

    private var syncService: LocalClassroomSyncService {
        LocalClassroomSyncService(rosterStore: rosterStore, assignmentStore: assignmentStore)
    }

    private var normalizedLessonCode: String {
        ClassroomAssignmentStore.normalizedClassLessonCode(lessonCode)
    }

    private var hasEnteredLessonCode: Bool {
        !normalizedLessonCode.isEmpty
    }

    private var normalizedStudentIdentifier: String {
        studentIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedPreferredFirstName: String {
        studentPreferredFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasCompleteStudentProfile: Bool {
        !normalizedPreferredFirstName.isEmpty && !normalizedStudentIdentifier.isEmpty
    }

    private var resolvedAssignmentPacket: AssignmentSyncPacket? {
        if let localPacket = try? syncService.resolveAssignment(classLessonCode: lessonCode) {
            return localPacket
        }
        guard remoteAssignmentCode == normalizedLessonCode else { return nil }
        return remoteAssignmentPacket
    }

    private var selectedWidget: AssignedWidgetSummary? {
        guard let selectedWidgetID else { return resolvedAssignmentPacket?.widgetSummaries.first }
        return resolvedAssignmentPacket?.widgetSummaries.first { $0.widgetID == selectedWidgetID }
    }

    private var selectedCatalogFolder: StudentOpenedAssignedLessonFolder {
        catalogFolders.first { $0.id == selectedCatalogFolderID } ?? StudentOpenedAssignedLessonFolder.allLessons
    }

    private var visibleOpenedLessons: [StudentOpenedAssignedLessonRecord] {
        guard selectedCatalogFolderID != StudentOpenedAssignedLessonFolder.allLessonsID else {
            return openedLessonCatalog
        }
        return openedLessonCatalog.filter { $0.folderID == selectedCatalogFolderID }
    }

    private var canSubmit: Bool {
        resolvedAssignmentPacket != nil &&
        selectedWidget != nil &&
        hasCompleteStudentProfile &&
        attempts > 0
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Join an Assigned Lesson")
                .font(.largeTitle.weight(.bold))
            Text("Enter the class lesson code. Your student profile is saved on this device.")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private var accessForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Student Access")
                .font(.headline)

            TextField("Class lesson code", text: $lessonCode)
                .textInputAutocapitalization(.characters)
                #if os(iOS)
                .keyboardType(.asciiCapable)
                #endif
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("studentMode.lessonCodeField")

            studentProfileSummary

            Button {
                Task {
                    await findOnlineLesson()
                }
            } label: {
                if isFindingOnlineLesson {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Download Lesson", systemImage: "icloud.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .disabled(!hasEnteredLessonCode || !hasCompleteStudentProfile || isFindingOnlineLesson || (try? syncService.resolveAssignment(classLessonCode: lessonCode)) != nil)
            .accessibilityIdentifier("studentMode.findOnlineLessonButton")
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var openedLessonsCatalogView: some View {
        if hasCompleteStudentProfile {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(normalizedPreferredFirstName)'s Catalog")
                            .font(.title2.weight(.bold))
                            .lineLimit(1)
                        Text("\(selectedCatalogFolder.name) • ^[\(visibleOpenedLessons.count) lesson](inflect: true)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    Text("Offline ready")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())
                }

                if openedLessonCatalog.isEmpty {
                    ContentUnavailableView(
                        "No Opened Lessons Yet",
                        systemImage: "book.closed",
                        description: Text("Lessons you open with this student ID will appear here.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else if visibleOpenedLessons.isEmpty {
                    ContentUnavailableView(
                        "No Lessons in \(selectedCatalogFolder.name)",
                        systemImage: "folder",
                        description: Text("Move an opened lesson into this folder, or choose All Lessons.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(visibleOpenedLessons) { record in
                            StudentCatalogLessonRow(
                                record: record,
                                folderName: folderName(for: record.folderID),
                                folders: catalogFolders,
                                onOpen: {
                                    openCatalogRecord(record)
                                },
                                onMove: { folderID in
                                    moveCatalogRecord(record, to: folderID)
                                }
                            )
                        }
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, minHeight: 520, alignment: .topLeading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Student Catalog")
                    .font(.title2.weight(.bold))
                ContentUnavailableView(
                    "Profile Needed",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text("Add your first name and teacher-supplied ID to show this iPad's saved lessons for that student.")
                )
                .frame(maxWidth: .infinity, minHeight: 260)
            }
            .padding(22)
            .frame(maxWidth: .infinity, minHeight: 520, alignment: .topLeading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var catalogFoldersView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Folders")
                    .font(.headline)
                Spacer()
                Button {
                    newCatalogFolderName = ""
                    isNewCatalogFolderPresented = true
                } label: {
                    Label("New", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!hasCompleteStudentProfile)
            }

            ForEach(catalogFolders) { folder in
                Button {
                    selectedCatalogFolderID = folder.id
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: folder.id == StudentOpenedAssignedLessonFolder.allLessonsID ? "tray.full" : "folder")
                            .frame(width: 22)
                        Text(folder.name)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(catalogCount(for: folder.id))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.thinMaterial, in: Capsule())
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selectedCatalogFolderID == folder.id ? .primary : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .background(folderBackground(for: folder.id), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var assignmentStatusView: some View {
        Group {
            if let assignmentPacket = resolvedAssignmentPacket {
                VStack(alignment: .leading, spacing: 16) {
                    assignmentCard(assignmentPacket)
                    submissionForm(assignmentPacket)
                }
            } else if isFindingOnlineLesson {
                ContentUnavailableView(
                    "Searching for Lesson",
                    systemImage: "magnifyingglass",
                    description: Text("Checking MathBoard online assignments.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else if hasEnteredLessonCode && hasSearchedOnlineLesson {
                ContentUnavailableView(
                    "Lesson Code Not Found",
                    systemImage: "number",
                    description: Text("Check the class lesson code with your teacher, or find it online.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else if hasEnteredLessonCode {
                ContentUnavailableView(
                    "Ready to Search",
                    systemImage: "magnifyingglass",
                    description: Text("Tap Download Lesson after entering the class lesson code.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            }
        }
    }

    private var studentProfileSummary: some View {
        HStack(spacing: 12) {
            Image(systemName: hasCompleteStudentProfile ? "person.crop.circle.fill.badge.checkmark" : "person.crop.circle.badge.exclamationmark")
                .foregroundStyle(hasCompleteStudentProfile ? .green : .orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(hasCompleteStudentProfile ? normalizedPreferredFirstName : "Student profile needed")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(hasCompleteStudentProfile ? "ID: \(normalizedStudentIdentifier)" : "Add your first name and teacher-supplied ID.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button("Edit") {
                isStudentProfilePresented = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(hasCompleteStudentProfile ? "Student profile, \(normalizedPreferredFirstName), ID \(normalizedStudentIdentifier)" : "Student profile needed")
    }

    private func folderBackground(for folderID: String) -> Color {
        selectedCatalogFolderID == folderID ? AppColors.folderTint.opacity(0.22) : Color.clear
    }

    private func folderName(for folderID: String) -> String {
        catalogFolders.first { $0.id == folderID }?.name ?? StudentOpenedAssignedLessonFolder.allLessons.name
    }

    private func catalogCount(for folderID: String) -> Int {
        guard folderID != StudentOpenedAssignedLessonFolder.allLessonsID else {
            return openedLessonCatalog.count
        }
        return openedLessonCatalog.filter { $0.folderID == folderID }.count
    }

    private func loadStudentCatalogState() {
        openedLessonCatalog = StudentOpenedAssignedLessonCatalog.load(studentIdentifier: normalizedStudentIdentifier)
        catalogFolders = StudentOpenedAssignedLessonCatalog.loadFolders(studentIdentifier: normalizedStudentIdentifier)
        if !catalogFolders.contains(where: { $0.id == selectedCatalogFolderID }) {
            selectedCatalogFolderID = StudentOpenedAssignedLessonFolder.allLessonsID
        }
    }

    private func resetResolvedOnlineAssignmentState() {
        liveProgressTask?.cancel()
        liveProgressTask = nil
        remoteAssignmentPacket = nil
        remoteAssignmentCode = ""
        hasSearchedOnlineLesson = false
        selectedWidgetID = nil
        scoreDraftsByWidgetID = [:]
        submittedWidgetIDs = []
        score = 0
        attempts = 1
        numberCorrectFirstTry = 0
        numberCorrectAfterRetry = 0
        longestStreak = 0
        statusMessage = nil
    }

    private func addCatalogFolder(named name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        catalogFolders = StudentOpenedAssignedLessonCatalog.addFolder(
            named: trimmedName,
            studentIdentifier: normalizedStudentIdentifier
        )
        selectedCatalogFolderID = catalogFolders.last?.id ?? StudentOpenedAssignedLessonFolder.allLessonsID
    }

    private func moveCatalogRecord(_ record: StudentOpenedAssignedLessonRecord, to folderID: String) {
        openedLessonCatalog = StudentOpenedAssignedLessonCatalog.move(
            assignmentID: record.assignmentPacket.id,
            to: folderID,
            studentIdentifier: normalizedStudentIdentifier
        )
    }

    private func assignmentCard(_ assignmentPacket: AssignmentSyncPacket) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(assignmentPacket.lesson.title)
                .font(.title2.weight(.semibold))
            HStack(spacing: 12) {
                Label(assignmentPacket.classroomName, systemImage: "person.3")
                Label("Code \(assignmentPacket.classLessonCode)", systemImage: "number")
                Label("^[\(assignmentPacket.widgetSummaries.count) widget](inflect: true)", systemImage: "square.grid.2x2")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if assignmentPacket.lesson.packageStoragePath != nil {
                Button {
                    Task {
                        await downloadAssignedLesson(assignmentPacket)
                    }
                } label: {
                    if isDownloadingLesson {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Open Student MathBoard", systemImage: "book.pages")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isDownloadingLesson)
                .accessibilityIdentifier("studentMode.openAssignedLessonButton")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func submissionForm(_ assignmentPacket: AssignmentSyncPacket) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Score Submission")
                .font(.headline)

            if assignmentPacket.widgetSummaries.isEmpty {
                ContentUnavailableView(
                    "No Widgets Assigned",
                    systemImage: "square.grid.2x2",
                    description: Text("This assigned lesson does not have MathBoard widgets ready for scoring.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Picker("Widget", selection: selectedWidgetBinding(for: assignmentPacket)) {
                    ForEach(assignmentPacket.widgetSummaries) { widget in
                        Text(widget.title).tag(Optional(widget.widgetID))
                    }
                }
                .pickerStyle(.menu)

                Stepper("Score: \(score)", value: $score, in: 0...max(1, attempts))
                Stepper("Attempts: \(attempts)", value: $attempts, in: 1...100)
                Stepper("First try correct: \(numberCorrectFirstTry)", value: $numberCorrectFirstTry, in: 0...100)
                Stepper("Corrected after retry: \(numberCorrectAfterRetry)", value: $numberCorrectAfterRetry, in: 0...100)
                Stepper("Longest streak: \(longestStreak)", value: $longestStreak, in: 0...100)

                Button {
                    submitScore(for: assignmentPacket)
                } label: {
                    Label("Submit Score", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
                .accessibilityIdentifier("studentMode.submitScoreButton")
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func selectedWidgetBinding(for assignmentPacket: AssignmentSyncPacket) -> Binding<UUID?> {
        Binding(
            get: {
                selectedWidgetID ?? assignmentPacket.widgetSummaries.first?.widgetID
            },
            set: { newWidgetID in
                let previousWidget = selectedWidget
                saveCurrentScoreDraft()
                if let previousWidget, previousWidget.widgetID != newWidgetID {
                    publishLiveProgress(
                        for: previousWidget,
                        draft: scoreDraftsByWidgetID[previousWidget.widgetID] ?? currentScoreDraft,
                        status: submittedWidgetIDs.contains(previousWidget.widgetID) ? .complete : .inProgress,
                        isActiveOnStudentScreen: false
                    )
                }
                selectedWidgetID = newWidgetID
                loadScoreDraft(for: selectedWidget)
            }
        )
    }

    private func syncSelectedWidget() {
        guard let assignmentPacket = resolvedAssignmentPacket else {
            saveCurrentScoreDraft()
            selectedWidgetID = nil
            resetScoreDraft()
            return
        }
        if let selectedWidgetID, assignmentPacket.widgetSummaries.contains(where: { $0.widgetID == selectedWidgetID }) {
            loadScoreDraft(for: selectedWidget)
            return
        }
        saveCurrentScoreDraft()
        selectedWidgetID = assignmentPacket.widgetSummaries.first?.widgetID
        loadScoreDraft(for: selectedWidget)
    }

    private func submitScore(for assignmentPacket: AssignmentSyncPacket) {
        guard let selectedWidget else { return }
        saveCurrentScoreDraft()

        let scoreRecord = scoreRecord(for: selectedWidget, status: .complete)
        let submission = StudentSubmissionPacket(
            teacherID: assignmentPacket.teacherID,
            classroomID: assignmentPacket.classroomID,
            assignmentID: assignmentPacket.id,
            classLessonCode: assignmentPacket.classLessonCode,
            studentIdentifier: normalizedStudentIdentifier,
            studentPreferredFirstName: normalizedPreferredFirstName,
            widgetScoreRecord: scoreRecord
        )

        if (try? syncService.resolveAssignment(classLessonCode: assignmentPacket.classLessonCode)) != nil {
            submitLocalScore(submission)
        } else {
            Task {
                await submitOnlineScore(submission)
            }
        }
    }

    private func findOnlineLesson() async {
        let code = normalizedLessonCode
        guard !code.isEmpty else { return }
        hasSearchedOnlineLesson = true
        isFindingOnlineLesson = true
        defer { isFindingOnlineLesson = false }

        do {
            try await ensureOnlineStudentAccess()
            let packet = try await FirebaseClassroomSyncService().resolveAssignment(
                classLessonCode: code,
                studentIdentifier: normalizedStudentIdentifier
            )
            remoteAssignmentPacket = packet
            remoteAssignmentCode = code
            syncSelectedWidget()
        } catch {
            statusMessage = StudentSubmissionStatusMessage(
                message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    private func downloadAssignedLesson(_ assignmentPacket: AssignmentSyncPacket) async {
        if openCatalogRecord(for: assignmentPacket) {
            return
        }

        isDownloadingLesson = true
        defer { isDownloadingLesson = false }

        do {
            try await ensureOnlineStudentAccess()
            let archiveData = try await FirebaseClassroomSyncService()
                .downloadLessonPackageData(for: assignmentPacket.lesson)
            let sourceLesson = try documentStore.importSharedLessonPackageArchive(
                archiveData,
                suggestedFileName: assignmentPacket.lesson.packageFileName
            )
            let studentLesson = try documentStore.studentAssignedLessonWorkingCopy(
                for: sourceLesson,
                assignmentID: assignmentPacket.id,
                studentIdentifier: normalizedStudentIdentifier
            )
            openAssignedLesson(
                lesson: studentLesson,
                assignmentPacket: assignmentPacket,
                recordInCatalog: true
            )
        } catch {
            statusMessage = StudentSubmissionStatusMessage(
                message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    private func openCatalogRecord(_ record: StudentOpenedAssignedLessonRecord) {
        guard FileManager.default.fileExists(atPath: record.workingCopyURL.path) else {
            openedLessonCatalog = StudentOpenedAssignedLessonCatalog.remove(
                assignmentID: record.assignmentPacket.id,
                studentIdentifier: normalizedStudentIdentifier
            )
            statusMessage = StudentSubmissionStatusMessage(message: "That saved lesson is no longer on this iPad. Enter the lesson code to download it again.")
            return
        }

        do {
            let lesson = try documentStore.loadManagedLesson(at: record.workingCopyURL)
            openAssignedLesson(
                lesson: lesson,
                assignmentPacket: record.assignmentPacket,
                recordInCatalog: true
            )
        } catch {
            statusMessage = StudentSubmissionStatusMessage(
                message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    private func openCatalogRecord(for assignmentPacket: AssignmentSyncPacket) -> Bool {
        let normalizedCode = ClassroomAssignmentStore.normalizedClassLessonCode(assignmentPacket.classLessonCode)
        guard let record = openedLessonCatalog.first(where: { record in
            record.assignmentPacket.id == assignmentPacket.id ||
            ClassroomAssignmentStore.normalizedClassLessonCode(record.classLessonCode) == normalizedCode
        }) else {
            return false
        }
        openCatalogRecord(record)
        return true
    }

    private func openAssignedLesson(
        lesson: Lesson,
        assignmentPacket: AssignmentSyncPacket,
        recordInCatalog: Bool
    ) {
        if recordInCatalog {
            openedLessonCatalog = StudentOpenedAssignedLessonCatalog.upsert(
                StudentOpenedAssignedLessonRecord(
                    assignmentPacket: assignmentPacket,
                    workingCopyURL: lesson.url,
                    lastOpenedAt: Date(),
                    folderID: selectedCatalogFolderID == StudentOpenedAssignedLessonFolder.allLessonsID ? StudentOpenedAssignedLessonFolder.allLessonsID : selectedCatalogFolderID
                ),
                studentIdentifier: normalizedStudentIdentifier
            )
        }
        openedAssignedLesson = StudentAssignedLessonDestination(
            lesson: lesson,
            assignmentPacket: assignmentPacket,
            studentIdentifier: normalizedStudentIdentifier,
            studentPreferredFirstName: normalizedPreferredFirstName
        )
    }

    private func submitLocalScore(_ submission: StudentSubmissionPacket) {
        do {
            let result = try syncService.submitWidgetScore(submission)
            submittedWidgetIDs.insert(result.widgetID)
            statusMessage = StudentSubmissionStatusMessage(
                message: "Score submitted. Report score: \(result.finalPercentScore.formatted(.number.precision(.fractionLength(0))))%."
            )
        } catch {
            statusMessage = StudentSubmissionStatusMessage(
                message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    private func submitOnlineScore(_ submission: StudentSubmissionPacket) async {
        do {
            try await ensureOnlineStudentAccess()
            let result = try await FirebaseClassroomSyncService().submitWidgetScore(submission)
            _ = try await FirebaseClassroomSyncService().publishLiveProgress(
                submission,
                isActiveOnStudentScreen: true
            )
            submittedWidgetIDs.insert(result.widgetID)
            statusMessage = StudentSubmissionStatusMessage(
                message: "Score submitted online. Report score: \(result.finalPercentScore.formatted(.number.precision(.fractionLength(0))))%."
            )
        } catch {
            statusMessage = StudentSubmissionStatusMessage(
                message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    private func scheduleLiveProgressUpdate() {
        // JSON-mathtivity lessons use StudentAssignedLessonView's own live progress system.
        // The outer view must not interfere — its draft state (attempts=1, score=0) would
        // write a stale 0/1 record to the same Firebase documents the inner view manages.
        guard resolvedAssignmentPacket?.lesson.packageStoragePath == nil else { return }
        saveCurrentScoreDraft()
        liveProgressTask?.cancel()
        guard let selectedWidget,
              let submission = liveProgressSubmission(
                widget: selectedWidget,
                draft: currentScoreDraft,
                status: submittedWidgetIDs.contains(selectedWidget.widgetID) ? .complete : .inProgress
              ) else {
            return
        }
        liveProgressTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                try await ensureOnlineStudentAccess()
                _ = try await FirebaseClassroomSyncService().publishLiveProgress(
                    submission,
                    isActiveOnStudentScreen: true
                )
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private func liveProgressSubmission(status: WidgetActivityScoreStatus) -> StudentSubmissionPacket? {
        guard let selectedWidget else { return nil }
        return liveProgressSubmission(
            widget: selectedWidget,
            draft: currentScoreDraft,
            status: status
        )
    }

    private func liveProgressSubmission(
        widget: AssignedWidgetSummary,
        draft: StudentWidgetScoreDraft,
        status: WidgetActivityScoreStatus
    ) -> StudentSubmissionPacket? {
        guard let assignmentPacket = resolvedAssignmentPacket,
              remoteAssignmentCode == normalizedLessonCode,
              (try? syncService.resolveAssignment(classLessonCode: assignmentPacket.classLessonCode)) == nil,
              draft.attempts > 0,
              hasCompleteStudentProfile else {
            return nil
        }

        return StudentSubmissionPacket(
            teacherID: assignmentPacket.teacherID,
            classroomID: assignmentPacket.classroomID,
            assignmentID: assignmentPacket.id,
            classLessonCode: assignmentPacket.classLessonCode,
            studentIdentifier: normalizedStudentIdentifier,
            studentPreferredFirstName: normalizedPreferredFirstName,
            widgetScoreRecord: scoreRecord(for: widget, draft: draft, status: status),
            submittedAt: Date()
        )
    }

    private func scoreRecord(for widget: AssignedWidgetSummary, status: WidgetActivityScoreStatus) -> WidgetActivityScoreRecord {
        scoreRecord(for: widget, draft: currentScoreDraft, status: status)
    }

    private func scoreRecord(
        for widget: AssignedWidgetSummary,
        draft: StudentWidgetScoreDraft,
        status: WidgetActivityScoreStatus
    ) -> WidgetActivityScoreRecord {
        WidgetActivityScoreRecord(
            id: widget.widgetID.uuidString,
            title: widget.title,
            status: status,
            score: draft.score,
            attempts: draft.attempts,
            points: Double(draft.score),
            pointsPossible: draft.attempts,
            numberCorrectFirstTry: draft.numberCorrectFirstTry,
            numberCorrectAfterRetry: draft.numberCorrectAfterRetry,
            longestStreak: draft.longestStreak
        )
    }

    private func publishLiveProgress(
        for widget: AssignedWidgetSummary,
        draft: StudentWidgetScoreDraft,
        status: WidgetActivityScoreStatus,
        isActiveOnStudentScreen: Bool
    ) {
        guard let submission = liveProgressSubmission(
            widget: widget,
            draft: draft,
            status: status
        ) else {
            return
        }

        Task { @MainActor in
            do {
                try await ensureOnlineStudentAccess()
                _ = try await FirebaseClassroomSyncService().publishLiveProgress(
                    submission,
                    isActiveOnStudentScreen: isActiveOnStudentScreen
                )
            } catch {
                return
            }
        }
    }

    private func publishCurrentWidgetAsInactive() {
        saveCurrentScoreDraft()
        // JSON-mathtivity lessons are handled entirely by StudentAssignedLessonView.
        // Writing here would overwrite the inner view's submitted score with 0/1 (draft default).
        guard resolvedAssignmentPacket?.lesson.packageStoragePath == nil else { return }
        guard let selectedWidget else { return }
        publishLiveProgress(
            for: selectedWidget,
            draft: scoreDraftsByWidgetID[selectedWidget.widgetID] ?? currentScoreDraft,
            status: submittedWidgetIDs.contains(selectedWidget.widgetID) ? .complete : .inProgress,
            isActiveOnStudentScreen: false
        )
    }

    private var currentScoreDraft: StudentWidgetScoreDraft {
        StudentWidgetScoreDraft(
            score: score,
            attempts: attempts,
            numberCorrectFirstTry: numberCorrectFirstTry,
            numberCorrectAfterRetry: numberCorrectAfterRetry,
            longestStreak: longestStreak
        )
    }

    private func saveCurrentScoreDraft() {
        guard let widgetID = selectedWidget?.widgetID else { return }
        scoreDraftsByWidgetID[widgetID] = currentScoreDraft
    }

    private func loadScoreDraft(for widget: AssignedWidgetSummary?) {
        guard let widget else {
            resetScoreDraft()
            return
        }
        let draft = scoreDraftsByWidgetID[widget.widgetID] ?? StudentWidgetScoreDraft.defaultDraft(for: widget)
        attempts = max(1, draft.attempts)
        score = min(max(0, draft.score), attempts)
        numberCorrectFirstTry = max(0, draft.numberCorrectFirstTry)
        numberCorrectAfterRetry = max(0, draft.numberCorrectAfterRetry)
        longestStreak = max(0, draft.longestStreak)
    }

    private func resetScoreDraft() {
        score = 0
        attempts = 1
        numberCorrectFirstTry = 0
        numberCorrectAfterRetry = 0
        longestStreak = 0
    }
}

private struct StudentProfileSettingsView: View {
    @Binding var preferredFirstName: String
    @Binding var studentIdentifier: String
    @Environment(\.dismiss) private var dismiss
    @AppStorage(LiveClassroomSettings.enabledKey) private var isLiveTeacherInkEnabled = false
    @AppStorage(LiveClassroomSettings.ablyAPIKeyKey) private var liveTeacherInkAblyAPIKey = ""

    private var trimmedPreferredFirstName: String {
        preferredFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedStudentIdentifier: String {
        studentIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedPreferredFirstName.isEmpty && !trimmedStudentIdentifier.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("First name", text: $preferredFirstName)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("studentProfile.firstNameField")
                    TextField("Teacher-supplied ID", text: $studentIdentifier)
                        .textInputAutocapitalization(.characters)
                        #if os(iOS)
                        .keyboardType(.asciiCapable)
                        #endif
                        .accessibilityIdentifier("studentProfile.studentIDField")
                } header: {
                    Text("Student Profile")
                } footer: {
                    Text("This stays saved on this device. Your teacher uses the ID to match your classroom roster row.")
                }

                Section {
                    Toggle("Receive live teacher ink", isOn: $isLiveTeacherInkEnabled)
                    SecureField("Ably API key", text: $liveTeacherInkAblyAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Live Ink POC")
                } footer: {
                    Text("Temporary testing setting. Production should use a short-lived token instead of an API key on student devices.")
                }
            }
            .navigationTitle("Student Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        preferredFirstName = String(trimmedPreferredFirstName.prefix(40))
                        studentIdentifier = trimmedStudentIdentifier
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

private struct StudentCatalogLessonRow: View {
    let record: StudentOpenedAssignedLessonRecord
    let folderName: String
    let folders: [StudentOpenedAssignedLessonFolder]
    let onOpen: () -> Void
    let onMove: (String) -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 14) {
                Image(systemName: "book.pages")
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: 5) {
                    Text(record.lessonTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 10) {
                        Text("Code \(record.classLessonCode)")
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.thinMaterial, in: Capsule())
                        Label(record.lastOpenedAt.formatted(date: .abbreviated, time: .omitted), systemImage: "clock")
                        Label(folderName, systemImage: "folder")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 8)

                Menu {
                    ForEach(folders) { folder in
                        Button {
                            onMove(folder.id)
                        } label: {
                            Label(folder.name, systemImage: folder.id == record.folderID ? "checkmark" : "folder")
                        }
                    }
                } label: {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 38, height: 38)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)

                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

private struct StudentCatalogFolderSheet: View {
    @Binding var folderName: String
    var onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private var trimmedFolderName: String {
        folderName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Folder name", text: $folderName)
                        .textInputAutocapitalization(.words)
                } footer: {
                    Text("Folders are saved only for this student profile on this iPad.")
                }
            }
            .navigationTitle("New Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onSave(trimmedFolderName)
                        dismiss()
                    }
                    .disabled(trimmedFolderName.isEmpty)
                }
            }
        }
    }
}

private struct StudentSubmissionStatusMessage: Identifiable {
    var id = UUID()
    var message: String
}

private struct StudentAssignedLessonDestination: Identifiable, Hashable {
    var lesson: Lesson
    var assignmentPacket: AssignmentSyncPacket
    var studentIdentifier: String
    var studentPreferredFirstName: String

    var id: String {
        "\(assignmentPacket.id.uuidString)-\(lesson.url.path)-\(studentIdentifier)"
    }
}

struct StudentAssignedLessonLiveProgressUpdate {
    var submission: StudentSubmissionPacket
    var isActiveOnStudentScreen: Bool
}

struct StudentAssignedLessonLiveProgressBuilder {
    var assignmentPacket: AssignmentSyncPacket
    var studentIdentifier: String
    var studentPreferredFirstName: String = ""
    var submittedWidgetIDs: Set<UUID>
    var scoreRecordsByWidgetID: [UUID: WidgetActivityScoreRecord] = [:]

    func updates(
        activeWidgetIDs: Set<UUID>,
        submittedAt: Date = Date()
    ) -> [StudentAssignedLessonLiveProgressUpdate] {
        assignmentPacket.widgetSummaries.filter { $0.maxScore > 0 }.map { widget in
            let isActive = activeWidgetIDs.contains(widget.widgetID)
            let fallbackStatus: WidgetActivityScoreStatus = submittedWidgetIDs.contains(widget.widgetID) ? .complete : .inProgress
            let scoreRecord = scoreRecord(for: widget, fallbackStatus: fallbackStatus)
            let submission = StudentSubmissionPacket(
                teacherID: assignmentPacket.teacherID,
                classroomID: assignmentPacket.classroomID,
                assignmentID: assignmentPacket.id,
                classLessonCode: assignmentPacket.classLessonCode,
                studentIdentifier: studentIdentifier,
                studentPreferredFirstName: studentPreferredFirstName,
                widgetScoreRecord: scoreRecord,
                submittedAt: submittedAt
            )

            return StudentAssignedLessonLiveProgressUpdate(
                submission: submission,
                isActiveOnStudentScreen: isActive
            )
        }
    }

    private func scoreRecord(
        for widget: AssignedWidgetSummary,
        fallbackStatus: WidgetActivityScoreStatus
    ) -> WidgetActivityScoreRecord {
        if var scoreRecord = scoreRecordsByWidgetID[widget.widgetID] {
            scoreRecord.id = widget.widgetID.uuidString
            scoreRecord.title = widget.title
            // Never publish .complete from the live loop — only submitWidgetScore() should
            // trigger green. A widget whose questions are all answered but not yet submitted
            // must show .inProgress so the dot stays yellow, not green.
            scoreRecord.status = submittedWidgetIDs.contains(widget.widgetID) ? .complete : .inProgress
            return scoreRecord
        }

        return WidgetActivityScoreRecord(
            id: widget.widgetID.uuidString,
            title: widget.title,
            status: fallbackStatus,
            score: 0,
            attempts: 0,
            points: 0,
            pointsPossible: Int(widget.maxScore.rounded()),
            numberCorrectFirstTry: 0,
            numberCorrectAfterRetry: 0,
            longestStreak: 0
        )
    }
}

private struct StudentAssignedLessonView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(LiveClassroomSettings.enabledKey) private var isLiveTeacherInkEnabled = false
    @AppStorage(LiveClassroomSettings.ablyAPIKeyKey) private var liveTeacherInkAblyAPIKey = ""

    let destination: StudentAssignedLessonDestination
    let submittedWidgetIDs: Set<UUID>
    @State private var activeWidgetIDs: Set<UUID> = []
    @State private var activeWidgets: [WidgetObject] = []
    @State private var scoreRecordsByWidgetID: [UUID: WidgetActivityScoreRecord]
    @State private var localSubmittedWidgetIDs: Set<UUID>
    @State private var everSubmittedWidgetIDs: Set<UUID> = []
    @State private var submissionMessage: String?
    @State private var hasResetBuiltInRuntimeStates = false
    @State private var hasLoadedDurableTeacherState = false
    @State private var durableTeacherSlideManifestSnapshot: TeacherSlideManifestSnapshot?
    @State private var durableTeacherInkChunks: [TeacherInkStrokeChunk] = []
    @State private var durableTeacherInkDrawingSnapshots: [TeacherInkDrawingSnapshot] = []
    @State private var durableTeacherObjectSnapshots: [TeacherObjectSnapshot] = []
    @State private var teacherSlideManifestListener: ListenerRegistration?
    @State private var teacherObjectSnapshotListener: ListenerRegistration?
    @State private var isStartingTeacherSlideManifestListener = false
    @State private var isStartingTeacherObjectSnapshotListener = false

    private static let durableTeacherSlideManifestRefreshRetryDelaysMilliseconds = [0, 750, 1_500, 3_000, 5_000, 8_000, 13_000, 21_000]

    init(destination: StudentAssignedLessonDestination, submittedWidgetIDs: Set<UUID>) {
        self.destination = destination
        self.submittedWidgetIDs = submittedWidgetIDs
        let cachedScoreRecords = Self.loadCachedScoreRecords(
            lessonURL: destination.lesson.url,
            assignmentID: destination.assignmentPacket.id,
            studentIdentifier: destination.studentIdentifier
        )
        let cachedSubmittedWidgetIDs = Set(cachedScoreRecords.compactMap { widgetID, scoreRecord in
            scoreRecord.status == .complete ? widgetID : nil
        })
        _scoreRecordsByWidgetID = State(initialValue: cachedScoreRecords)
        _localSubmittedWidgetIDs = State(initialValue: submittedWidgetIDs.union(cachedSubmittedWidgetIDs))
    }

    var body: some View {
        assignedLessonContent
            .navigationTitle(studentDisplayName)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    studentNameTitle
                }
            }
            .overlay(alignment: .topLeading) {
                studentLessonChrome
            }
            .alert(
                "Widget Submission",
                isPresented: Binding(
                    get: { submissionMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            submissionMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) { }
            } message: {
                if let submissionMessage {
                    Text(submissionMessage)
                }
            }
            .onAppear {
                resetBuiltInRuntimeStatesForWorkingCopy()
                publishLessonPresence()
                startDurableTeacherSlideManifestListener()
                startDurableTeacherObjectSnapshotListener()
            }
            .task {
                await runLiveProgressLoop()
            }
            .onChange(of: hasLoadedDurableTeacherState) { _, isLoaded in
                if isLoaded { publishLessonPresence() }
            }
            .onDisappear {
                teacherSlideManifestListener?.remove()
                teacherSlideManifestListener = nil
                teacherObjectSnapshotListener?.remove()
                teacherObjectSnapshotListener = nil
                // Do NOT publish here — writing a fresh updatedAt on exit would reset the
                // 10-second stale timer and keep the dot blue. Instead, let the existing
                // records go stale naturally from the last loop publish (~2 seconds ago).
                removeLessonPresence()
            }
    }

    @ViewBuilder
    private var assignedLessonContent: some View {
        if hasLoadedDurableTeacherState {
            SlidesView(
                lessonURL: destination.lesson.url,
                classroomMode: .constant(.student),
                liveClassroomConfiguration: liveClassroomConfiguration,
                initialTeacherInkChunks: durableTeacherInkChunks,
                initialTeacherInkDrawingSnapshots: durableTeacherInkDrawingSnapshots,
                initialTeacherSlideManifestSnapshot: durableTeacherSlideManifestSnapshot,
                initialTeacherObjectSnapshots: durableTeacherObjectSnapshots,
                onActiveWidgetIDsChanged: handleActiveWidgetIDsChanged,
                onActiveWidgetsChanged: handleActiveWidgetsChanged,
                onLiveTeacherSlideManifestRefreshRequested: refreshDurableTeacherSlideManifest
            )
            .environment(\.widgetSubmit, WidgetSubmitEnvironment(
                isWidgetSubmitted: { widgetID in localSubmittedWidgetIDs.contains(widgetID) },
                isWidgetReset: { widgetID in everSubmittedWidgetIDs.contains(widgetID) && !localSubmittedWidgetIDs.contains(widgetID) },
                onSubmitWidget: { widgetID in
                    guard let summary = destination.assignmentPacket.widgetSummaries.first(where: { $0.widgetID == widgetID }),
                          var record = scoreRecordsByWidgetID[widgetID] else { return }
                    record.id = widgetID.uuidString
                    record.title = summary.title
                    submitWidgetScore(record)
                },
                onResetAfterSubmit: { widgetID in
                    localSubmittedWidgetIDs.remove(widgetID)
                    everSubmittedWidgetIDs.insert(widgetID)
                    scoreRecordsByWidgetID.removeValue(forKey: widgetID)
                    saveCachedScoreRecords()
                }
            ))
        } else {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading teacher notes...")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.canvasBackground.ignoresSafeArea())
            .task(id: destination.id) {
                await loadDurableTeacherState()
            }
        }
    }

    private var studentLessonChrome: some View {
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

            Text(shortStudentLessonHeaderTitle)
                .font(.headline)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(.ultraThinMaterial, in: Capsule())
                .accessibilityLabel("Lesson file \(studentLessonFileName)")
        }
        .padding(.top, 8)
        .padding(.leading, 12)
    }

    private func refreshDurableTeacherSlideManifest(_ snapshot: TeacherSlideManifestSnapshot) async -> TeacherSlideManifestSnapshot? {
        var lastError: Error?
        let service = FirebaseClassroomSyncService()

        for delay in Self.durableTeacherSlideManifestRefreshRetryDelaysMilliseconds {
            if delay > 0 {
                try? await Task.sleep(for: .milliseconds(delay))
            }

            do {
                try await ensureOnlineStudentAccess()
                guard let refreshedSnapshot = try await service
                    .fetchTeacherSlideManifestSnapshot(classLessonCode: destination.assignmentPacket.classLessonCode),
                    refreshedSnapshot.revision >= snapshot.revision else {
                    continue
                }

                durableTeacherSlideManifestSnapshot = refreshedSnapshot
                if Self.hasHydratedBackgroundAssets(in: refreshedSnapshot, for: snapshot) {
                    return refreshedSnapshot
                }
            } catch {
                lastError = error
            }
        }

        if let lastError {
            print("[StudentMode] durable teacher slide manifest refresh error: \(lastError)")
        }
        return nil
    }

    private static func hasHydratedBackgroundAssets(
        in refreshedSnapshot: TeacherSlideManifestSnapshot,
        for liveSnapshot: TeacherSlideManifestSnapshot
    ) -> Bool {
        let refreshedSlidesByID = Dictionary(uniqueKeysWithValues: refreshedSnapshot.slides.map { ($0.id, $0) })
        for liveSlide in liveSnapshot.slides {
            guard let liveBackground = liveSlide.background,
                  liveBackground.assetBase64Data == nil else {
                continue
            }
            guard let refreshedBackground = refreshedSlidesByID[liveSlide.id]?.background,
                  refreshedBackground.assetBase64Data != nil else {
                return false
            }
        }
        return true
    }

    private func loadDurableTeacherState() async {
        do {
            try await ensureOnlineStudentAccess()
            let service = FirebaseClassroomSyncService()
            durableTeacherSlideManifestSnapshot = try await service
                .fetchTeacherSlideManifestSnapshot(classLessonCode: destination.assignmentPacket.classLessonCode)
            durableTeacherObjectSnapshots = try await service
                .fetchTeacherObjectSnapshots(classLessonCode: destination.assignmentPacket.classLessonCode)
            durableTeacherInkDrawingSnapshots = try await service
                .fetchTeacherInkDrawingSnapshots(classLessonCode: destination.assignmentPacket.classLessonCode)
            if durableTeacherInkDrawingSnapshots.isEmpty {
                durableTeacherInkChunks = try await service
                    .fetchTeacherInkChunks(classLessonCode: destination.assignmentPacket.classLessonCode)
            } else {
                durableTeacherInkChunks = []
            }
        } catch {
            durableTeacherSlideManifestSnapshot = nil
            durableTeacherInkChunks = []
            durableTeacherInkDrawingSnapshots = []
            durableTeacherObjectSnapshots = []
            print("[StudentMode] durable teacher state fetch error: \(error)")
        }
        await restoreSubmittedScoresFromFirebase()
        hasLoadedDurableTeacherState = true
        startDurableTeacherSlideManifestListener()
        startDurableTeacherObjectSnapshotListener()
    }

    private func restoreSubmittedScoresFromFirebase() async {
        do {
            try await ensureOnlineStudentAccess()
            let firebaseProgress = try await FirebaseClassroomSyncService().fetchStudentWidgetProgress(
                assignmentPacket: destination.assignmentPacket,
                studentIdentifier: destination.studentIdentifier
            )
            var didChange = false
            for progress in firebaseProgress where progress.status == .complete {
                let widgetID = progress.widgetID
                if !localSubmittedWidgetIDs.contains(widgetID) {
                    localSubmittedWidgetIDs.insert(widgetID)
                    didChange = true
                }
                everSubmittedWidgetIDs.insert(widgetID)
                if scoreRecordsByWidgetID[widgetID] == nil {
                    let title = destination.assignmentPacket.widgetSummaries
                        .first { $0.widgetID == widgetID }?.title ?? ""
                    scoreRecordsByWidgetID[widgetID] = WidgetActivityScoreRecord(
                        id: widgetID.uuidString,
                        title: title,
                        status: .complete,
                        score: progress.correctCount,
                        attempts: progress.attemptedCount,
                        points: Double(progress.correctCount),
                        pointsPossible: progress.attemptedCount,
                        numberCorrectFirstTry: progress.correctCount,
                        numberCorrectAfterRetry: 0,
                        longestStreak: progress.correctCount
                    )
                    didChange = true
                }
            }
            if didChange { saveCachedScoreRecords() }
        } catch {
            return
        }
    }

    private func startDurableTeacherSlideManifestListener() {
        guard teacherSlideManifestListener == nil,
              !isStartingTeacherSlideManifestListener else { return }
        isStartingTeacherSlideManifestListener = true
        Task { @MainActor in
            defer { isStartingTeacherSlideManifestListener = false }
            do {
                try await ensureOnlineStudentAccess()
                guard teacherSlideManifestListener == nil else { return }
                let service = FirebaseClassroomSyncService()
                teacherSlideManifestListener = service.listenToTeacherSlideManifestSnapshot(
                    classLessonCode: destination.assignmentPacket.classLessonCode
                ) { snapshot in
                    guard (durableTeacherSlideManifestSnapshot?.revision ?? 0) <= snapshot.revision else { return }
                    durableTeacherSlideManifestSnapshot = snapshot
                }
                if teacherSlideManifestListener == nil {
                    print("[StudentMode] durable teacher slide manifest listener was not started")
                }
            } catch {
                print("[StudentMode] durable teacher slide manifest listener start error: \(error)")
            }
        }
    }

    private func startDurableTeacherObjectSnapshotListener() {
        guard teacherObjectSnapshotListener == nil,
              !isStartingTeacherObjectSnapshotListener else { return }
        isStartingTeacherObjectSnapshotListener = true
        Task { @MainActor in
            defer { isStartingTeacherObjectSnapshotListener = false }
            do {
                try await ensureOnlineStudentAccess()
                guard teacherObjectSnapshotListener == nil else { return }
                let service = FirebaseClassroomSyncService()
                teacherObjectSnapshotListener = service.listenToTeacherObjectSnapshots(
                    classLessonCode: destination.assignmentPacket.classLessonCode
                ) { snapshots in
                    durableTeacherObjectSnapshots = snapshots
                }
                if teacherObjectSnapshotListener == nil {
                    print("[StudentMode] durable teacher object listener was not started")
                }
            } catch {
                print("[StudentMode] durable teacher object listener start error: \(error)")
            }
        }
    }

    private var liveClassroomConfiguration: LiveClassroomSessionConfiguration? {
        guard isLiveTeacherInkEnabled else { return nil }
        let configuration = LiveClassroomSessionConfiguration(
            lessonCode: destination.assignmentPacket.classLessonCode,
            role: .student,
            clientID: "student-\(destination.studentIdentifier)",
            apiKey: liveTeacherInkAblyAPIKey
        )
        return configuration.isUsable ? configuration : nil
    }

    private var studentNameTitle: some View {
        Text(studentDisplayName)
            .font(.headline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityLabel("Student \(studentDisplayName)")
    }

    private var shortStudentLessonHeaderTitle: String {
        String(studentLessonFileName.prefix(20))
    }

    private var studentLessonFileName: String {
        if let packageFileName = destination.assignmentPacket.lesson.packageFileName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !packageFileName.isEmpty {
            return packageFileName.replacingOccurrences(of: ".mathboard", with: "")
        }
        return destination.lesson.url.deletingPathExtension().lastPathComponent
    }

    private var studentLessonHeaderTitle: String {
        let title = destination.assignmentPacket.lesson.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            return title
        }
        if let packageFileName = destination.assignmentPacket.lesson.packageFileName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !packageFileName.isEmpty {
            return packageFileName.replacingOccurrences(of: ".mathboard", with: "")
        }
        return destination.lesson.url.deletingPathExtension().lastPathComponent
    }

    private var studentDisplayName: String {
        let preferredFirstName = destination.studentPreferredFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preferredFirstName.isEmpty {
            return preferredFirstName
        }
        let identifier = destination.studentIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return identifier.isEmpty ? "Unknown" : identifier
    }

    private func handleActiveWidgetIDsChanged(_ widgetIDs: Set<UUID>) {
        guard widgetIDs != activeWidgetIDs else { return }
        activeWidgetIDs = widgetIDs
        // Publish presence immediately so teacher's fallback dot reflects current widget
        // activity without waiting for the next 2-second loop tick.
        publishLessonPresence()
        publishLiveProgress(forActiveWidgetIDs: widgetIDs, activeWidgets: activeWidgets)
    }

    private func handleActiveWidgetsChanged(_ widgets: [WidgetObject]) {
        guard widgets.map(\.id) != activeWidgets.map(\.id) else { return }
        activeWidgets = widgets
        publishLiveProgress(forActiveWidgetIDs: activeWidgetIDs, activeWidgets: widgets)
    }

    private func runLiveProgressLoop() async {
        while !Task.isCancelled {
            publishLessonPresence()
            let refreshedActiveWidgets = refreshedWidgets(forActiveWidgetIDs: activeWidgetIDs)
            publishLiveProgress(
                forActiveWidgetIDs: activeWidgetIDs,
                activeWidgets: refreshedActiveWidgets.isEmpty ? activeWidgets : refreshedActiveWidgets
            )
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func publishLessonPresence() {
        // Don't publish until the lesson is actually loaded and visible — publishing
        // earlier would turn the teacher's dot blue while the student is still on the
        // loading screen (or just entering the lesson code).
        guard hasLoadedDurableTeacherState else { return }
        // Presence reflects whether the student is on a widget slide so the teacher's
        // dot turns yellow even when the teacher's widget picker shows a different widget.
        let onWidgetSlide = !activeWidgetIDs.isEmpty
        Task { @MainActor in
            do {
                try await ensureOnlineStudentAccess()
                _ = try await FirebaseClassroomSyncService().publishLessonPresence(
                    assignmentPacket: destination.assignmentPacket,
                    studentIdentifier: destination.studentIdentifier,
                    studentPreferredFirstName: destination.studentPreferredFirstName,
                    isActiveOnStudentScreen: onWidgetSlide
                )
            } catch {
                return
            }
        }
    }

    private func removeLessonPresence() {
        Task { @MainActor in
            try? await FirebaseClassroomSyncService().deleteLessonPresence(
                assignmentPacket: destination.assignmentPacket,
                studentIdentifier: destination.studentIdentifier
            )
        }
    }

    private func refreshedWidgets(forActiveWidgetIDs activeWidgetIDs: Set<UUID>) -> [WidgetObject] {
        guard !activeWidgetIDs.isEmpty else { return [] }
        return allWidgetsInWorkingCopy().filter { activeWidgetIDs.contains($0.id) }
    }

    private func allWidgetsInWorkingCopy() -> [WidgetObject] {
        let slideStore = SlideStore(lessonURL: destination.lesson.url)
        return slideStore.slides.flatMap { slide in
            let sidecarURL = WidgetObject.sidecarURL(forDrawingURL: slideStore.drawingURL(for: slide))
            return WidgetObject.load(from: sidecarURL)
        }
    }

    private func resetBuiltInRuntimeStatesForWorkingCopy() {
        guard !hasResetBuiltInRuntimeStates else { return }
        hasResetBuiltInRuntimeStates = true
        WidgetObject.resetBuiltInRuntimeStates(for: allWidgetsInWorkingCopy())
    }

    private func publishLiveProgress(
        forActiveWidgetIDs activeWidgetIDs: Set<UUID>,
        activeWidgets: [WidgetObject]
    ) {
        // Don't publish until the lesson has loaded and any previously-submitted
        // Firebase scores have been restored. This prevents the first loop iteration
        // from publishing a stale 0/N record that would overwrite a real submission.
        guard hasLoadedDurableTeacherState else { return }
        let mergedScoreRecords = mergeScoreRecords(from: activeWidgets)
        let builder = StudentAssignedLessonLiveProgressBuilder(
            assignmentPacket: destination.assignmentPacket,
            studentIdentifier: destination.studentIdentifier,
            studentPreferredFirstName: destination.studentPreferredFirstName,
            submittedWidgetIDs: localSubmittedWidgetIDs,
            scoreRecordsByWidgetID: mergedScoreRecords
        )

        for update in builder.updates(activeWidgetIDs: activeWidgetIDs) {
            guard let widgetID = UUID(uuidString: update.submission.widgetScoreRecord.id) else { continue }
            // Skip widgets that are currently locked in submitted state (their score is already in Firebase).
            guard !localSubmittedWidgetIDs.contains(widgetID) else { continue }
            let hasEverBeenSubmitted = everSubmittedWidgetIDs.contains(widgetID)
            Task { @MainActor in
                do {
                    try await ensureOnlineStudentAccess()
                    _ = try await FirebaseClassroomSyncService().publishLiveProgress(
                        update.submission,
                        isActiveOnStudentScreen: update.isActiveOnStudentScreen,
                        hasEverBeenSubmitted: hasEverBeenSubmitted
                    )
                } catch {
                    return
                }
            }
        }
    }

    private func mergeScoreRecords(from widgets: [WidgetObject]) -> [UUID: WidgetActivityScoreRecord] {
        var updatedScoreRecords = scoreRecordsByWidgetID
        for widget in widgets {
            // Widget was previously submitted but its on-disk runtime state is now nil —
            // the student reset it via the gear menu. Clear the submission lock so the
            // loop can re-publish the fresh 0/N state. The explicit Reset button goes
            // through onResetAfterSubmit instead, but this handles edge cases.
            if widget.activityRuntimeState == nil, localSubmittedWidgetIDs.contains(widget.id) {
                everSubmittedWidgetIDs.insert(widget.id)
                localSubmittedWidgetIDs.remove(widget.id)
                updatedScoreRecords.removeValue(forKey: widget.id)
                continue
            }
            guard var scoreRecord = widget.liveActivityScoreRecord else { continue }
            if scoreRecord.attempts == 0,
               let cachedScoreRecord = updatedScoreRecords[widget.id],
               cachedScoreRecord.attempts > 0 {
                continue
            }
            scoreRecord.id = widget.id.uuidString
            if localSubmittedWidgetIDs.contains(widget.id) {
                scoreRecord.status = .complete
            }
            updatedScoreRecords[widget.id] = scoreRecord
        }
        guard updatedScoreRecords != scoreRecordsByWidgetID else { return updatedScoreRecords }
        scoreRecordsByWidgetID = updatedScoreRecords
        StudentAssignedLessonScoreRecordCache.save(
            updatedScoreRecords,
            lessonURL: destination.lesson.url,
            assignmentID: destination.assignmentPacket.id,
            studentIdentifier: destination.studentIdentifier
        )
        return updatedScoreRecords
    }

    private func submitWidgetScore(_ scoreRecord: WidgetActivityScoreRecord) {
        guard let widgetID = UUID(uuidString: scoreRecord.id) else { return }
        guard scoreRecord.attempts > 0 else {
            submissionMessage = "Answer at least one item before submitting this widget."
            return
        }

        var completedScoreRecord = scoreRecord
        completedScoreRecord.status = .complete
        let submission = StudentSubmissionPacket(
            teacherID: destination.assignmentPacket.teacherID,
            classroomID: destination.assignmentPacket.classroomID,
            assignmentID: destination.assignmentPacket.id,
            classLessonCode: destination.assignmentPacket.classLessonCode,
            studentIdentifier: destination.studentIdentifier,
            studentPreferredFirstName: destination.studentPreferredFirstName,
            widgetScoreRecord: completedScoreRecord,
            submittedAt: Date()
        )

        Task { @MainActor in
            do {
                try await ensureOnlineStudentAccess()
                _ = try await FirebaseClassroomSyncService().submitWidgetScore(submission)
                _ = try await FirebaseClassroomSyncService().publishLiveProgress(
                    submission,
                    isActiveOnStudentScreen: activeWidgetIDs.contains(widgetID),
                    hasEverBeenSubmitted: true
                )
                localSubmittedWidgetIDs.insert(widgetID)
                everSubmittedWidgetIDs.insert(widgetID)
                scoreRecordsByWidgetID[widgetID] = completedScoreRecord
                saveCachedScoreRecords()
            } catch {
                submissionMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func saveCachedScoreRecords() {
        StudentAssignedLessonScoreRecordCache.save(
            scoreRecordsByWidgetID,
            lessonURL: destination.lesson.url,
            assignmentID: destination.assignmentPacket.id,
            studentIdentifier: destination.studentIdentifier
        )
    }

    private static func loadCachedScoreRecords(
        lessonURL: URL,
        assignmentID: UUID,
        studentIdentifier: String
    ) -> [UUID: WidgetActivityScoreRecord] {
        StudentAssignedLessonScoreRecordCache.load(
            lessonURL: lessonURL,
            assignmentID: assignmentID,
            studentIdentifier: studentIdentifier
        )
    }
}

@MainActor
@discardableResult
private func ensureOnlineStudentAccess() async throws -> String {
    try await MathBoardStudentFirebaseAccessAuthorizer()
        .ensureAuthenticatedForOnlineLessonAccess()
}

private enum StudentAssignedLessonScoreRecordCache {
    static func load(
        lessonURL: URL,
        assignmentID: UUID,
        studentIdentifier: String
    ) -> [UUID: WidgetActivityScoreRecord] {
        guard let data = try? Data(contentsOf: cacheURL(
            lessonURL: lessonURL,
            assignmentID: assignmentID,
            studentIdentifier: studentIdentifier
        )),
              let recordsByID = try? JSONDecoder().decode([String: WidgetActivityScoreRecord].self, from: data) else {
            return [:]
        }
        return recordsByID.reduce(into: [UUID: WidgetActivityScoreRecord]()) { result, element in
            guard let widgetID = UUID(uuidString: element.key) else { return }
            result[widgetID] = element.value
        }
    }

    static func save(
        _ recordsByWidgetID: [UUID: WidgetActivityScoreRecord],
        lessonURL: URL,
        assignmentID: UUID,
        studentIdentifier: String
    ) {
        let recordsByID = Dictionary(
            uniqueKeysWithValues: recordsByWidgetID.map { ($0.key.uuidString, $0.value) }
        )
        guard let data = try? JSONEncoder().encode(recordsByID) else { return }
        let url = cacheURL(
            lessonURL: lessonURL,
            assignmentID: assignmentID,
            studentIdentifier: studentIdentifier
        )
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    private static func cacheURL(
        lessonURL: URL,
        assignmentID: UUID,
        studentIdentifier: String
    ) -> URL {
        // Store in app support, not inside the lesson bundle, so the cache survives
        // lesson re-downloads and iCloud sync operations that may replace the bundle.
        let appSupport = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("MathBoard", isDirectory: true)
            .appendingPathComponent("StudentProgress", isDirectory: true)
            .appendingPathComponent("\(assignmentID.uuidString)-\(safeFileComponent(studentIdentifier)).score-records.json")
    }

    private static func safeFileComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let component = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return component.isEmpty ? "student" : component
    }
}

private struct StudentOpenedAssignedLessonRecord: Codable, Hashable, Identifiable {
    var assignmentPacket: AssignmentSyncPacket
    var workingCopyURL: URL
    var lastOpenedAt: Date
    var folderID: String

    var id: UUID { assignmentPacket.id }
    var lessonTitle: String { assignmentPacket.lesson.title }
    var classroomName: String { assignmentPacket.classroomName }
    var classLessonCode: String { assignmentPacket.classLessonCode }

    init(
        assignmentPacket: AssignmentSyncPacket,
        workingCopyURL: URL,
        lastOpenedAt: Date,
        folderID: String = StudentOpenedAssignedLessonFolder.allLessonsID
    ) {
        self.assignmentPacket = assignmentPacket
        self.workingCopyURL = workingCopyURL
        self.lastOpenedAt = lastOpenedAt
        self.folderID = folderID
    }

    private enum CodingKeys: String, CodingKey {
        case assignmentPacket
        case workingCopyURL
        case lastOpenedAt
        case folderID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        assignmentPacket = try container.decode(AssignmentSyncPacket.self, forKey: .assignmentPacket)
        workingCopyURL = try container.decode(URL.self, forKey: .workingCopyURL)
        lastOpenedAt = try container.decode(Date.self, forKey: .lastOpenedAt)
        folderID = try container.decodeIfPresent(String.self, forKey: .folderID) ?? StudentOpenedAssignedLessonFolder.allLessonsID
    }
}

private struct StudentOpenedAssignedLessonFolder: Codable, Hashable, Identifiable {
    static let allLessonsID = "all-lessons"
    static let allLessons = StudentOpenedAssignedLessonFolder(id: allLessonsID, name: "All Lessons", createdAt: Date(timeIntervalSince1970: 0))
    static let defaultFolders = [allLessons]

    var id: String
    var name: String
    var createdAt: Date
}

private enum StudentOpenedAssignedLessonCatalog {
    static func load(studentIdentifier: String) -> [StudentOpenedAssignedLessonRecord] {
        guard let data = try? Data(contentsOf: catalogURL(studentIdentifier: studentIdentifier)),
              let records = try? JSONDecoder().decode([StudentOpenedAssignedLessonRecord].self, from: data) else {
            return []
        }
        return records
            .filter { FileManager.default.fileExists(atPath: $0.workingCopyURL.path) }
            .sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    static func loadFolders(studentIdentifier: String) -> [StudentOpenedAssignedLessonFolder] {
        guard let data = try? Data(contentsOf: foldersURL(studentIdentifier: studentIdentifier)),
              let storedFolders = try? JSONDecoder().decode([StudentOpenedAssignedLessonFolder].self, from: data) else {
            return StudentOpenedAssignedLessonFolder.defaultFolders
        }
        let customFolders = storedFolders
            .filter { $0.id != StudentOpenedAssignedLessonFolder.allLessonsID }
            .sorted { $0.createdAt < $1.createdAt }
        return [StudentOpenedAssignedLessonFolder.allLessons] + customFolders
    }

    static func addFolder(named name: String, studentIdentifier: String) -> [StudentOpenedAssignedLessonFolder] {
        var folders = loadFolders(studentIdentifier: studentIdentifier)
        let trimmedName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
        guard !trimmedName.isEmpty else { return folders }
        guard !folders.contains(where: { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }) else {
            return folders
        }
        folders.append(
            StudentOpenedAssignedLessonFolder(
                id: UUID().uuidString,
                name: trimmedName,
                createdAt: Date()
            )
        )
        saveFolders(folders, studentIdentifier: studentIdentifier)
        return folders
    }

    static func upsert(
        _ record: StudentOpenedAssignedLessonRecord,
        studentIdentifier: String
    ) -> [StudentOpenedAssignedLessonRecord] {
        var records = load(studentIdentifier: studentIdentifier)
        var recordToSave = record
        if let existingRecord = records.first(where: { matches($0, assignmentPacket: record.assignmentPacket) }),
           record.folderID == StudentOpenedAssignedLessonFolder.allLessonsID {
            recordToSave.folderID = existingRecord.folderID
        }
        records.removeAll { matches($0, assignmentPacket: record.assignmentPacket) }
        records.insert(recordToSave, at: 0)
        save(records, studentIdentifier: studentIdentifier)
        return records
    }

    static func move(assignmentID: UUID, to folderID: String, studentIdentifier: String) -> [StudentOpenedAssignedLessonRecord] {
        var records = load(studentIdentifier: studentIdentifier)
        if let index = records.firstIndex(where: { $0.assignmentPacket.id == assignmentID }) {
            records[index].folderID = folderID
            records[index].lastOpenedAt = Date()
        }
        save(records, studentIdentifier: studentIdentifier)
        return records
    }

    static func remove(assignmentID: UUID, studentIdentifier: String) -> [StudentOpenedAssignedLessonRecord] {
        var records = load(studentIdentifier: studentIdentifier)
        records.removeAll { $0.assignmentPacket.id == assignmentID }
        save(records, studentIdentifier: studentIdentifier)
        return records
    }

    private static func save(_ records: [StudentOpenedAssignedLessonRecord], studentIdentifier: String) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        let url = catalogURL(studentIdentifier: studentIdentifier)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    private static func saveFolders(_ folders: [StudentOpenedAssignedLessonFolder], studentIdentifier: String) {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        let url = foldersURL(studentIdentifier: studentIdentifier)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    private static func matches(_ record: StudentOpenedAssignedLessonRecord, assignmentPacket: AssignmentSyncPacket) -> Bool {
        record.assignmentPacket.id == assignmentPacket.id ||
        normalizedClassLessonCode(record.classLessonCode) == normalizedClassLessonCode(assignmentPacket.classLessonCode)
    }

    private static func normalizedClassLessonCode(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func catalogURL(studentIdentifier: String) -> URL {
        catalogDirectoryURL()
            .appendingPathComponent("\(safeFileComponent(studentIdentifier)).opened-lessons.json")
    }

    private static func foldersURL(studentIdentifier: String) -> URL {
        catalogDirectoryURL()
            .appendingPathComponent("\(safeFileComponent(studentIdentifier)).folders.json")
    }

    private static func catalogDirectoryURL() -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsURL
            .appendingPathComponent("Assigned Lessons", isDirectory: true)
            .appendingPathComponent("Student Catalog", isDirectory: true)
    }

    private static func safeFileComponent(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = trimmed.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let component = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return component.isEmpty ? "student" : component
    }
}

private struct StudentWidgetScoreDraft: Equatable {
    var score: Int
    var attempts: Int
    var numberCorrectFirstTry: Int
    var numberCorrectAfterRetry: Int
    var longestStreak: Int

    static func defaultDraft(for widget: AssignedWidgetSummary) -> StudentWidgetScoreDraft {
        StudentWidgetScoreDraft(
            score: 0,
            attempts: max(1, widget.maxScore.roundedInt),
            numberCorrectFirstTry: 0,
            numberCorrectAfterRetry: 0,
            longestStreak: 0
        )
    }
}

private extension Double {
    var roundedInt: Int {
        Int(rounded())
    }
}

#Preview {
    StudentModeView()
        .environment(MathBoardUserModeStore())
        .environment(ClassroomRosterStore())
        .environment(ClassroomAssignmentStore())
        .environment(DocumentStore())
}
