//
//  ClassroomRosterView.swift
//  MathBoardCore — Documents module
//

import SwiftUI
import UniformTypeIdentifiers

struct ClassroomRosterView: View {
    @Environment(ClassroomRosterStore.self) private var rosterStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedClassroomID: UUID?
    @State private var selectedStudentIDs: Set<UUID> = []
    @State private var showNewClassSheet = false
    @State private var showCSVImporter = false
    @State private var csvImportDraft: CSVImportDraft?
    @State private var classToRename: Classroom?
    @State private var classToDelete: Classroom?
    @State private var studentToDelete: PendingRosterStudentDeletion?
    @State private var showMoveDestinationPicker = false
    @State private var classIDPendingIDRegeneration: UUID?
    @State private var csvImportTargetClassroomID: UUID?
    @State private var actionErrorMessage: String?
    @State private var classNameDraft = ""
    @State private var alternateIDPrefixDraft = ""
    @FocusState private var isClassNameFocused: Bool
    @FocusState private var isAlternateIDPrefixFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                classTabBar
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 10)

                Divider()

                if let selectedClassroom {
                    rosterContent(for: selectedClassroom)
                } else {
                    emptyState
                }
            }
            .background(AppColors.canvasBackground.ignoresSafeArea())
            .frame(minWidth: 1100, minHeight: 760)
            .navigationTitle("Classroom Rosters")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        importCSVAsNewClass()
                    } label: {
                        Label("Import CSV", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        showNewClassSheet = true
                    } label: {
                        Label("New Class", systemImage: "person.3.sequence")
                    }
                }
            }
        }
        .onAppear(perform: selectFirstClassIfNeeded)
        .onChange(of: rosterStore.classrooms) { _, _ in
            repairSelectedClassIfNeeded()
            syncClassNameDraft()
            syncAlternateIDPrefixDraft()
        }
        .onChange(of: selectedClassroomID) { _, _ in
            selectedStudentIDs = []
            syncClassNameDraft()
            syncAlternateIDPrefixDraft()
        }
        .onChange(of: isClassNameFocused) { _, isFocused in
            if !isFocused {
                commitClassName()
            }
        }
        .onChange(of: isAlternateIDPrefixFocused) { _, isFocused in
            if !isFocused {
                commitAlternateIDPrefix()
            }
        }
        .sheet(isPresented: $showNewClassSheet) {
            NameEntrySheet(
                title: "New Class",
                placeholder: "Class name",
                confirmLabel: "Create"
            ) { name in
                let classroom = try rosterStore.createClassroom(named: name)
                selectedClassroomID = classroom.id
                selectedStudentIDs = []
            }
        }
        .sheet(item: $classToRename) { classroom in
            NameEntrySheet(
                title: "Rename Class",
                placeholder: "Class name",
                confirmLabel: "Rename",
                initialName: classroom.name
            ) { name in
                try rosterStore.renameClassroom(classroom.id, to: name)
            }
        }
        .sheet(item: $csvImportDraft) { draft in
            CSVImportMappingView(draft: draft, allowsClassNameEditing: csvImportTargetClassroomID == nil) { preview, className in
                let classroom: Classroom
                if let csvImportTargetClassroomID {
                    classroom = try rosterStore.importCSV(preview: preview, into: csvImportTargetClassroomID)
                } else {
                    classroom = try rosterStore.importCSV(preview: preview, className: className)
                }
                selectedClassroomID = classroom.id
                selectedStudentIDs = []
                self.csvImportTargetClassroomID = nil
                csvImportDraft = nil
            }
        }
        .fileImporter(
            isPresented: $showCSVImporter,
            allowedContentTypes: Self.csvTypes,
            allowsMultipleSelection: false,
            onCompletion: handleCSVImport
        )
        .confirmationDialog("Move Students", isPresented: $showMoveDestinationPicker) {
            ForEach(moveDestinationClassrooms) { classroom in
                Button(classroom.name) {
                    moveSelectedStudents(to: classroom.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose the class where the selected students should move.")
        }
        .confirmationDialog("Regenerate IDs?", isPresented: regenerateIDsConfirmationBinding) {
            Button("Regenerate IDs", role: .destructive) {
                if let classIDPendingIDRegeneration {
                    generateAlternateIDs(for: classIDPendingIDRegeneration, overwriteExisting: true)
                }
                classIDPendingIDRegeneration = nil
            }
            Button("Cancel", role: .cancel) {
                classIDPendingIDRegeneration = nil
            }
        } message: {
            Text("This replaces the alternate ID numbers currently assigned to this roster.")
        }
        .alert("Delete Class?", isPresented: deleteClassAlertBinding) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let classToDelete {
                    deleteClass(classToDelete.id)
                }
            }
        } message: {
            Text("This removes \(classToDelete?.name ?? "this class") and its roster from this iPad.")
        }
        .alert("Delete Student?", isPresented: deleteStudentAlertBinding) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let studentToDelete {
                    deleteStudent(studentToDelete.studentID, from: studentToDelete.classroomID)
                }
            }
        } message: {
            Text("This removes \(studentToDelete?.displayName ?? "this student") from the roster.")
        }
        .alert("Roster Action Failed", isPresented: actionErrorAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionErrorMessage ?? "Something went wrong.")
        }
    }

    private static let csvTypes: [UTType] = {
        var types: [UTType] = [.plainText]
        if let csv = UTType(filenameExtension: "csv") {
            types.insert(csv, at: 0)
        }
        return types
    }()

    private var selectedClassroom: Classroom? {
        guard let selectedClassroomID else { return nil }
        return rosterStore.classrooms.first { $0.id == selectedClassroomID }
    }

    private var moveDestinationClassrooms: [Classroom] {
        rosterStore.classrooms.filter { $0.id != selectedClassroomID }
    }

    private var deleteClassAlertBinding: Binding<Bool> {
        Binding(
            get: { classToDelete != nil },
            set: { isPresented in
                if !isPresented {
                    classToDelete = nil
                }
            }
        )
    }

    private var deleteStudentAlertBinding: Binding<Bool> {
        Binding(
            get: { studentToDelete != nil },
            set: { isPresented in
                if !isPresented {
                    studentToDelete = nil
                }
            }
        )
    }

    private var actionErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { actionErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    actionErrorMessage = nil
                }
            }
        )
    }

    private var regenerateIDsConfirmationBinding: Binding<Bool> {
        Binding(
            get: { classIDPendingIDRegeneration != nil },
            set: { isPresented in
                if !isPresented {
                    classIDPendingIDRegeneration = nil
                }
            }
        )
    }

    private var classTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(rosterStore.classrooms) { classroom in
                    Button {
                        selectedClassroomID = classroom.id
                        selectedStudentIDs = []
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(classroom.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text("^[\(classroom.students.count) student](inflect: true)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(minWidth: 120, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .background(
                        selectedClassroomID == classroom.id ? .regularMaterial : .thinMaterial,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(selectedClassroomID == classroom.id ? AppColors.accent : .clear, lineWidth: 2)
                    )
                    .contextMenu {
                        Button {
                            classToRename = classroom
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            classToDelete = classroom
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }

                Button {
                    showNewClassSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("New Class")
            }
        }
    }

    @ViewBuilder
    private func rosterContent(for classroom: Classroom) -> some View {
        let duplicateReport = (try? rosterStore.duplicateIDReport(for: classroom.id))
            ?? DuplicateRosterIDReport(officialStudentIDs: [], alternateStudentIDs: [])

        VStack(spacing: 0) {
            rosterToolbar(for: classroom)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

            if duplicateReport.hasDuplicates {
                duplicateIDWarning(report: duplicateReport)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }

            Divider()

            ScrollView([.horizontal, .vertical]) {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(classroom.students) { student in
                            EditableRosterStudentRow(
                                student: student,
                                isSelected: selectedStudentIDs.contains(student.id),
                                duplicateOfficialIDs: Set(duplicateReport.officialStudentIDs),
                                duplicateAlternateIDs: Set(duplicateReport.alternateStudentIDs),
                                destinationClassrooms: moveDestinationClassrooms,
                                onSelectionChanged: { isSelected in
                                    updateSelection(for: student.id, isSelected: isSelected)
                                },
                                onCommit: { updatedStudent in
                                    updateStudent(updatedStudent, in: classroom.id)
                                },
                                onMove: { destinationClassroomID in
                                    moveStudent(student.id, from: classroom.id, to: destinationClassroomID)
                                },
                                onDelete: {
                                    studentToDelete = PendingRosterStudentDeletion(student: student, classroomID: classroom.id)
                                }
                            )
                            Divider()
                                .padding(.leading, 20)
                        }
                    } header: {
                        rosterHeader
                    }
                }
                .frame(minWidth: 1040)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
        }
    }

    private func duplicateIDWarning(report: DuplicateRosterIDReport) -> some View {
        Label {
            Text("Duplicate IDs found. \(report.summary)")
                .font(.caption.weight(.semibold))
                .lineLimit(2)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.orange.opacity(0.35), lineWidth: 1)
        )
    }

    private func rosterToolbar(for classroom: Classroom) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                TextField("Class name", text: $classNameDraft)
                    .font(.title3.weight(.semibold))
                    .textFieldStyle(.plain)
                    .focused($isClassNameFocused)
                    .onSubmit(commitClassName)
                    .accessibilityLabel("Class Name")
                Text("^[\(classroom.students.count) student](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button {
                addStudent(to: classroom.id)
            } label: {
                Label("Add Student", systemImage: "person.badge.plus")
            }
            .buttonStyle(.bordered)

            Button {
                importCSV(into: classroom.id)
            } label: {
                Label("Import CSV", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)

            VStack(alignment: .leading, spacing: 4) {
                Button {
                    prepareToGenerateAlternateIDs(for: classroom.id)
                } label: {
                    Label("Generate IDs", systemImage: "number")
                }
                .buttonStyle(.bordered)
                .disabled(classroom.students.isEmpty)

                HStack(spacing: 6) {
                    Text("Number prefix")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField("Prefix", text: $alternateIDPrefixDraft)
                        .textFieldStyle(.roundedBorder)
                        .focused($isAlternateIDPrefixFocused)
                        .onSubmit(commitAlternateIDPrefix)
                        .frame(width: 120)
                }
            }
        }
    }

    private var rosterHeader: some View {
        HStack(spacing: 12) {
            Text("")
                .frame(width: 32)
            Text("First Name")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Last Name")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Student ID")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Alternate ID")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Actions")
                .frame(width: 112, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppColors.canvasBackground)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.3.sequence")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No classes yet")
                .font(.headline)
            Text("Import a CSV roster or create a class manually.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    importCSVAsNewClass()
                } label: {
                    Label("Import CSV", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    showNewClassSheet = true
                } label: {
                    Label("New Class", systemImage: "person.3.sequence")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func handleCSVImport(_ result: Result<[URL], any Error>) {
        do {
            let urls = try result.get()
            guard let sourceURL = urls.first else { return }

            let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let preview = try rosterStore.previewCSV(at: sourceURL)
            let fileName = csvImportTargetClassroomID.flatMap { targetID in
                rosterStore.classrooms.first { $0.id == targetID }?.name
            } ?? sourceURL.deletingPathExtension().lastPathComponent
            csvImportDraft = CSVImportDraft(fileName: fileName, preview: preview)
        } catch {
            csvImportTargetClassroomID = nil
            actionErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func selectFirstClassIfNeeded() {
        guard selectedClassroomID == nil else { return }
        selectedClassroomID = rosterStore.classrooms.first?.id
        syncClassNameDraft()
        syncAlternateIDPrefixDraft()
    }

    private func repairSelectedClassIfNeeded() {
        guard let selectedClassroomID else {
            self.selectedClassroomID = rosterStore.classrooms.first?.id
            return
        }
        if !rosterStore.classrooms.contains(where: { $0.id == selectedClassroomID }) {
            self.selectedClassroomID = rosterStore.classrooms.first?.id
            selectedStudentIDs = []
        }
    }

    private func syncClassNameDraft() {
        guard !isClassNameFocused else { return }
        classNameDraft = selectedClassroom?.name ?? ""
    }

    private func syncAlternateIDPrefixDraft() {
        guard !isAlternateIDPrefixFocused else { return }
        alternateIDPrefixDraft = selectedClassroom?.alternateIDPrefix ?? ""
    }

    private func commitClassName() {
        guard let selectedClassroom else { return }
        let trimmedName = classNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName != selectedClassroom.name else { return }

        do {
            try rosterStore.renameClassroom(selectedClassroom.id, to: trimmedName)
            classNameDraft = trimmedName
        } catch {
            classNameDraft = selectedClassroom.name
            actionErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func commitAlternateIDPrefix() {
        _ = saveAlternateIDPrefix()
    }

    @discardableResult
    private func saveAlternateIDPrefix() -> Bool {
        guard let selectedClassroom else { return false }
        let trimmedPrefix = alternateIDPrefixDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPrefix != selectedClassroom.alternateIDPrefix else { return true }

        do {
            try rosterStore.updateAlternateIDPrefix(trimmedPrefix, for: selectedClassroom.id)
            alternateIDPrefixDraft = trimmedPrefix.uppercased()
            return true
        } catch {
            alternateIDPrefixDraft = selectedClassroom.alternateIDPrefix
            actionErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    private func importCSV(into classroomID: UUID) {
        csvImportTargetClassroomID = classroomID
        showCSVImporter = true
    }

    private func importCSVAsNewClass() {
        csvImportTargetClassroomID = nil
        showCSVImporter = true
    }

    private func addStudent(to classroomID: UUID) {
        do {
            _ = try rosterStore.addStudent(to: classroomID)
        } catch {
            actionErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func updateStudent(_ student: RosterStudent, in classroomID: UUID) {
        do {
            try rosterStore.updateStudent(student, in: classroomID)
        } catch {
            actionErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func updateSelection(for studentID: UUID, isSelected: Bool) {
        if isSelected {
            selectedStudentIDs.insert(studentID)
        } else {
            selectedStudentIDs.remove(studentID)
        }
    }

    private func deleteSelectedStudents(from classroomID: UUID) {
        do {
            try rosterStore.deleteStudents(selectedStudentIDs, from: classroomID)
            selectedStudentIDs = []
        } catch {
            actionErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func deleteStudent(_ studentID: UUID, from classroomID: UUID) {
        do {
            try rosterStore.deleteStudents([studentID], from: classroomID)
            selectedStudentIDs.remove(studentID)
            studentToDelete = nil
        } catch {
            actionErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func moveSelectedStudents(to destinationClassroomID: UUID) {
        guard let selectedClassroomID else { return }
        do {
            try rosterStore.moveStudents(selectedStudentIDs, from: selectedClassroomID, to: destinationClassroomID)
            selectedStudentIDs = []
            self.selectedClassroomID = destinationClassroomID
        } catch {
            actionErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func moveStudent(_ studentID: UUID, from sourceClassroomID: UUID, to destinationClassroomID: UUID) {
        do {
            try rosterStore.moveStudents([studentID], from: sourceClassroomID, to: destinationClassroomID)
            selectedStudentIDs.remove(studentID)
        } catch {
            actionErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func prepareToGenerateAlternateIDs(for classroomID: UUID) {
        guard saveAlternateIDPrefix() else { return }
        if rosterStore.hasGeneratedAlternateIDs(in: classroomID) {
            classIDPendingIDRegeneration = classroomID
        } else {
            generateAlternateIDs(for: classroomID, overwriteExisting: false)
        }
    }

    private func generateAlternateIDs(for classroomID: UUID, overwriteExisting: Bool) {
        do {
            try rosterStore.generateAlternateIDs(for: classroomID, overwriteExisting: overwriteExisting)
            syncAlternateIDPrefixDraft()
        } catch {
            actionErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func deleteClass(_ classroomID: UUID) {
        do {
            try rosterStore.deleteClassroom(classroomID)
            classToDelete = nil
        } catch {
            actionErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct EditableRosterStudentRow: View {
    let student: RosterStudent
    var isSelected: Bool
    var duplicateOfficialIDs: Set<String>
    var duplicateAlternateIDs: Set<String>
    var destinationClassrooms: [Classroom]
    var onSelectionChanged: (Bool) -> Void
    var onCommit: (RosterStudent) -> Void
    var onMove: (UUID) -> Void
    var onDelete: () -> Void

    @State private var draft: RosterStudent

    init(
        student: RosterStudent,
        isSelected: Bool,
        duplicateOfficialIDs: Set<String>,
        duplicateAlternateIDs: Set<String>,
        destinationClassrooms: [Classroom],
        onSelectionChanged: @escaping (Bool) -> Void,
        onCommit: @escaping (RosterStudent) -> Void,
        onMove: @escaping (UUID) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.student = student
        self.isSelected = isSelected
        self.duplicateOfficialIDs = duplicateOfficialIDs
        self.duplicateAlternateIDs = duplicateAlternateIDs
        self.destinationClassrooms = destinationClassrooms
        self.onSelectionChanged = onSelectionChanged
        self.onCommit = onCommit
        self.onMove = onMove
        self.onDelete = onDelete
        _draft = State(initialValue: student)
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onSelectionChanged(!isSelected)
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AppColors.accent : .secondary)
                    .frame(width: 32, height: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSelected ? "Deselect Student" : "Select Student")

            rosterTextField("First Name", text: $draft.firstName)
            rosterTextField("Last Name", text: $draft.lastName)
            rosterTextField(
                "Student ID",
                text: $draft.officialStudentID,
                isDuplicate: duplicateOfficialIDs.contains(Self.normalizedID(draft.officialStudentID))
            )
            rosterTextField(
                "Alternate ID",
                text: $draft.alternateStudentID,
                isDuplicate: duplicateAlternateIDs.contains(Self.normalizedID(draft.alternateStudentID))
            )
            rowActions
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? AppColors.accent.opacity(0.12) : Color.clear)
        .onChange(of: student) { _, newStudent in
            draft = newStudent
        }
        .onSubmit(commit)
        .onDisappear(perform: commit)
    }

    private func rosterTextField(_ title: String, text: Binding<String>, isDuplicate: Bool = false) -> some View {
        TextField(title, text: text)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isDuplicate ? .red : .clear, lineWidth: 2)
            )
    }

    private var rowActions: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(destinationClassrooms) { classroom in
                    Button(classroom.name) {
                        commit()
                        onMove(classroom.id)
                    }
                }
            } label: {
                Image(systemName: "arrowshape.turn.up.right")
                    .frame(width: 36, height: 36)
            }
            .menuStyle(.button)
            .disabled(destinationClassrooms.isEmpty)
            .accessibilityLabel("Move Student")

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete Student")
        }
        .frame(width: 112, alignment: .trailing)
    }

    private func commit() {
        guard draft != student else { return }
        onCommit(draft)
    }

    private static func normalizedID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

private struct PendingRosterStudentDeletion {
    var studentID: UUID
    var classroomID: UUID
    var displayName: String

    init(student: RosterStudent, classroomID: UUID) {
        studentID = student.id
        self.classroomID = classroomID
        let trimmedName = "\(student.firstName) \(student.lastName)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
        displayName = trimmedName.isEmpty ? "this student" : trimmedName
    }
}

private struct CSVImportDraft: Identifiable {
    let id = UUID()
    var fileName: String
    var preview: RosterCSVPreview
}

private struct CSVImportMappingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ClassroomRosterStore.self) private var rosterStore

    @State private var draft: CSVImportDraft
    @State private var className: String
    @State private var errorMessage: String?

    var allowsClassNameEditing: Bool
    var onImport: (RosterCSVPreview, String) throws -> Void

    init(
        draft: CSVImportDraft,
        allowsClassNameEditing: Bool = true,
        onImport: @escaping (RosterCSVPreview, String) throws -> Void
    ) {
        self.allowsClassNameEditing = allowsClassNameEditing
        self.onImport = onImport
        _draft = State(initialValue: draft)
        _className = State(initialValue: draft.fileName)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                if allowsClassNameEditing {
                    TextField("Class name", text: $className)
                        .textFieldStyle(.roundedBorder)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Importing into")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(className)
                            .font(.headline)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Column Mapping")
                        .font(.headline)

                    mappingPicker("First Name", selection: $draft.preview.mapping.firstNameIndex)
                    mappingPicker("Last Name", selection: $draft.preview.mapping.lastNameIndex)
                    mappingPicker("Student ID", selection: $draft.preview.mapping.officialStudentIDIndex)
                    mappingPicker("Alternate ID", selection: $draft.preview.mapping.alternateStudentIDIndex)
                }

                if duplicateReport.hasDuplicates {
                    duplicateIDWarning(report: duplicateReport)
                }

                previewTable
            }
            .padding(20)
            .background(AppColors.canvasBackground.ignoresSafeArea())
            .navigationTitle("Import Roster")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        importRoster()
                    }
                    .disabled(!draft.preview.mapping.canImport || className.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Import Failed", isPresented: errorAlertBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Something went wrong.")
            }
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

    private var duplicateReport: DuplicateRosterIDReport {
        rosterStore.duplicateIDReport(for: draft.preview)
    }

    private func duplicateIDWarning(report: DuplicateRosterIDReport) -> some View {
        Label {
            Text("This CSV contains duplicate IDs. \(report.summary)")
                .font(.caption.weight(.semibold))
                .lineLimit(2)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.orange.opacity(0.35), lineWidth: 1)
        )
    }

    private var previewTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.headline)

            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow {
                        ForEach(Array(draft.preview.headers.enumerated()), id: \.offset) { _, header in
                            Text(header)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 120, alignment: .leading)
                        }
                    }

                    ForEach(Array(draft.preview.rows.prefix(8).enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(0..<draft.preview.headers.count, id: \.self) { index in
                                Text(row.indices.contains(index) ? row[index] : "")
                                    .font(.caption)
                                    .lineLimit(1)
                                    .frame(minWidth: 120, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 260)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func mappingPicker(_ title: String, selection: Binding<Int?>) -> some View {
        Picker(title, selection: selection) {
            Text("Not Used").tag(Optional<Int>.none)
            ForEach(Array(draft.preview.headers.enumerated()), id: \.offset) { index, header in
                Text(header).tag(Optional<Int>.some(index))
            }
        }
    }

    private func importRoster() {
        do {
            try onImport(draft.preview, className)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview {
    ClassroomRosterView()
        .environment(ClassroomRosterStore())
}
