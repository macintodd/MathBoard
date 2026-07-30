import SwiftUI
import Slides
import WidgetEngine

public struct StudentModeView: View {
    @Environment(MathBoardUserModeStore.self) private var modeStore
    @Environment(ClassroomRosterStore.self) private var rosterStore
    @Environment(ClassroomAssignmentStore.self) private var assignmentStore
    @Environment(DocumentStore.self) private var documentStore
    @State private var lessonCode = ""
    @State private var studentIdentifier = ""
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

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    accessForm

                    if let assignmentPacket = resolvedAssignmentPacket {
                        assignmentCard(assignmentPacket)
                        submissionForm(assignmentPacket)
                    } else if isFindingOnlineLesson {
                        ContentUnavailableView(
                            "Searching for Lesson",
                            systemImage: "magnifyingglass",
                            description: Text("Checking MathBoard online assignments.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 220)
                    } else if hasEnteredLessonCode && hasSearchedOnlineLesson {
                        ContentUnavailableView(
                            "Lesson Code Not Found",
                            systemImage: "number",
                            description: Text("Check the class lesson code with your teacher, or find it online.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 220)
                    } else if hasEnteredLessonCode {
                        ContentUnavailableView(
                            "Ready to Search",
                            systemImage: "magnifyingglass",
                            description: Text("Tap Find Online Lesson when your code and student ID are entered.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 220)
                    }
                }
                .padding(24)
                .frame(maxWidth: 760, alignment: .leading)
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
                scheduleLiveProgressUpdate()
            }
            .onChange(of: selectedWidgetID) { _, _ in
                scheduleLiveProgressUpdate()
            }
            .onChange(of: currentScoreDraft) { _, _ in
                scheduleLiveProgressUpdate()
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

    private var canSubmit: Bool {
        resolvedAssignmentPacket != nil &&
        selectedWidget != nil &&
        !studentIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
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
            Text("Enter the class lesson code and your student ID.")
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

            TextField("Student ID or alternate ID", text: $studentIdentifier)
                .textInputAutocapitalization(.characters)
                #if os(iOS)
                .keyboardType(.asciiCapable)
                #endif
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("studentMode.studentIDField")

            Button {
                Task {
                    await findOnlineLesson()
                }
            } label: {
                if isFindingOnlineLesson {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Find Online Lesson", systemImage: "icloud.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .disabled(!hasEnteredLessonCode || isFindingOnlineLesson || (try? syncService.resolveAssignment(classLessonCode: lessonCode)) != nil)
            .accessibilityIdentifier("studentMode.findOnlineLessonButton")
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
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
            studentIdentifier: studentIdentifier,
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
            let packet = try await FirebaseClassroomSyncService().resolveAssignment(classLessonCode: code)
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
        isDownloadingLesson = true
        defer { isDownloadingLesson = false }

        do {
            let archiveData = try await FirebaseClassroomSyncService()
                .downloadLessonPackageData(for: assignmentPacket.lesson)
            let sourceLesson = try documentStore.importSharedLessonPackageArchive(
                archiveData,
                suggestedFileName: assignmentPacket.lesson.packageFileName
            )
            let studentLesson = try documentStore.studentAssignedLessonWorkingCopy(
                for: sourceLesson,
                assignmentID: assignmentPacket.id,
                studentIdentifier: studentIdentifier
            )
            openedAssignedLesson = StudentAssignedLessonDestination(
                lesson: studentLesson,
                assignmentPacket: assignmentPacket,
                studentIdentifier: studentIdentifier
            )
        } catch {
            statusMessage = StudentSubmissionStatusMessage(
                message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
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
              !studentIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return StudentSubmissionPacket(
            teacherID: assignmentPacket.teacherID,
            classroomID: assignmentPacket.classroomID,
            assignmentID: assignmentPacket.id,
            classLessonCode: assignmentPacket.classLessonCode,
            studentIdentifier: studentIdentifier,
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

private struct StudentSubmissionStatusMessage: Identifiable {
    var id = UUID()
    var message: String
}

private struct StudentAssignedLessonDestination: Identifiable, Hashable {
    var lesson: Lesson
    var assignmentPacket: AssignmentSyncPacket
    var studentIdentifier: String

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
    var submittedWidgetIDs: Set<UUID>
    var scoreRecordsByWidgetID: [UUID: WidgetActivityScoreRecord] = [:]

    func updates(
        activeWidgetIDs: Set<UUID>,
        submittedAt: Date = Date()
    ) -> [StudentAssignedLessonLiveProgressUpdate] {
        assignmentPacket.widgetSummaries.map { widget in
            let isActive = activeWidgetIDs.contains(widget.widgetID)
            let fallbackStatus: WidgetActivityScoreStatus = submittedWidgetIDs.contains(widget.widgetID) ? .complete : .inProgress
            let scoreRecord = scoreRecord(for: widget, fallbackStatus: fallbackStatus)
            let submission = StudentSubmissionPacket(
                teacherID: assignmentPacket.teacherID,
                classroomID: assignmentPacket.classroomID,
                assignmentID: assignmentPacket.id,
                classLessonCode: assignmentPacket.classLessonCode,
                studentIdentifier: studentIdentifier,
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
            if submittedWidgetIDs.contains(widget.widgetID) {
                scoreRecord.status = .complete
            }
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
    let destination: StudentAssignedLessonDestination
    let submittedWidgetIDs: Set<UUID>
    @State private var activeWidgetIDs: Set<UUID> = []
    @State private var activeWidgets: [WidgetObject] = []
    @State private var scoreRecordsByWidgetID: [UUID: WidgetActivityScoreRecord]
    @State private var localSubmittedWidgetIDs: Set<UUID>
    @State private var submissionMessage: String?
    @State private var hasResetBuiltInRuntimeStates = false

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
        SlidesView(
            lessonURL: destination.lesson.url,
            classroomMode: .constant(.student),
            onActiveWidgetIDsChanged: handleActiveWidgetIDsChanged,
            onActiveWidgetsChanged: handleActiveWidgetsChanged
        )
            .navigationTitle(destination.lesson.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    submitWidgetMenu
                }
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
            }
            .task {
                await runLiveProgressLoop()
            }
            .onDisappear {
                publishLiveProgress(forActiveWidgetIDs: [], activeWidgets: [])
            }
    }

    @ViewBuilder
    private var submitWidgetMenu: some View {
        let records = currentSubmittableScoreRecords
        if records.count == 1, let record = records.first {
            Button {
                submitWidgetScore(record)
            } label: {
                Label("Submit Widget", systemImage: "checkmark.circle")
            }
            .disabled(record.attempts == 0)
        } else {
            Menu {
                ForEach(records, id: \.id) { record in
                    Button(record.title) {
                        submitWidgetScore(record)
                    }
                    .disabled(record.attempts == 0)
                }
            } label: {
                Label("Submit", systemImage: "checkmark.circle")
            }
            .disabled(records.isEmpty)
        }
    }

    private func handleActiveWidgetIDsChanged(_ widgetIDs: Set<UUID>) {
        guard widgetIDs != activeWidgetIDs else { return }
        activeWidgetIDs = widgetIDs
        publishLiveProgress(forActiveWidgetIDs: widgetIDs, activeWidgets: activeWidgets)
    }

    private func handleActiveWidgetsChanged(_ widgets: [WidgetObject]) {
        guard widgets.map(\.id) != activeWidgets.map(\.id) else { return }
        activeWidgets = widgets
        publishLiveProgress(forActiveWidgetIDs: activeWidgetIDs, activeWidgets: widgets)
    }

    private func runLiveProgressLoop() async {
        while !Task.isCancelled {
            let refreshedActiveWidgets = refreshedWidgets(forActiveWidgetIDs: activeWidgetIDs)
            publishLiveProgress(
                forActiveWidgetIDs: activeWidgetIDs,
                activeWidgets: refreshedActiveWidgets.isEmpty ? activeWidgets : refreshedActiveWidgets
            )
            try? await Task.sleep(for: .seconds(2))
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
        let mergedScoreRecords = mergeScoreRecords(from: activeWidgets)
        let builder = StudentAssignedLessonLiveProgressBuilder(
            assignmentPacket: destination.assignmentPacket,
            studentIdentifier: destination.studentIdentifier,
            submittedWidgetIDs: localSubmittedWidgetIDs,
            scoreRecordsByWidgetID: mergedScoreRecords
        )

        for update in builder.updates(activeWidgetIDs: activeWidgetIDs) {
            Task { @MainActor in
                do {
                    _ = try await FirebaseClassroomSyncService().publishLiveProgress(
                        update.submission,
                        isActiveOnStudentScreen: update.isActiveOnStudentScreen
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

    private var currentSubmittableScoreRecords: [WidgetActivityScoreRecord] {
        destination.assignmentPacket.widgetSummaries.compactMap { widget in
            guard activeWidgetIDs.contains(widget.widgetID),
                  var scoreRecord = scoreRecordsByWidgetID[widget.widgetID] else {
                return nil
            }
            scoreRecord.id = widget.widgetID.uuidString
            scoreRecord.title = widget.title
            return scoreRecord
        }
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
            widgetScoreRecord: completedScoreRecord,
            submittedAt: Date()
        )

        Task { @MainActor in
            do {
                _ = try await FirebaseClassroomSyncService().submitWidgetScore(submission)
                _ = try await FirebaseClassroomSyncService().publishLiveProgress(
                    submission,
                    isActiveOnStudentScreen: activeWidgetIDs.contains(widgetID)
                )
                localSubmittedWidgetIDs.insert(widgetID)
                scoreRecordsByWidgetID[widgetID] = completedScoreRecord
                saveCachedScoreRecords()
                submissionMessage = "Submitted \(completedScoreRecord.title)."
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
        lessonURL
            .appendingPathComponent("student-progress", isDirectory: true)
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
