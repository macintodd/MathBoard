//
//  FolderDetailView.swift
//  MathBoardCore — Documents module
//
//  Lists the lessons inside one folder. Loads from `DocumentStore` on
//  appear so navigation away and back picks up any creates / deletes.
//

import SwiftUI
import UniformTypeIdentifiers

enum LessonSortOrder: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case nameAscending
    case nameDescending

    var id: Self { self }

    var title: String {
        switch self {
        case .newest:
            return "Newest First"
        case .oldest:
            return "Oldest First"
        case .nameAscending:
            return "Name A-Z"
        case .nameDescending:
            return "Name Z-A"
        }
    }

    var systemImage: String {
        switch self {
        case .newest:
            return "arrow.down"
        case .oldest:
            return "arrow.up"
        case .nameAscending:
            return "textformat.abc"
        case .nameDescending:
            return "textformat.abc.dottedunderline"
        }
    }
}

struct FolderDetailView: View {
    let folder: Folder
    @Environment(DocumentStore.self) private var store
    @Environment(ClassroomRosterStore.self) private var classroomRosterStore
    @Environment(ClassroomAssignmentStore.self) private var classroomAssignmentStore
    @Environment(MathBoardTeacherAuthStore.self) private var teacherAuthStore
    @State private var childFolders: [Folder] = []
    @State private var lessons: [Lesson] = []
    @State private var showNewFolderSheet = false
    @State private var showNewLessonSheet = false
    @State private var showLessonImporter = false
    @State private var selectedLesson: Lesson?
    @State private var folderToRename: Folder?
    @State private var folderToDelete: Folder?
    @State private var lessonToRename: Lesson?
    @State private var lessonToDuplicate: Lesson?
    @State private var lessonToDelete: Lesson?
    @State private var lessonToMove: Lesson?
    @State private var lessonToAssign: Lesson?
    @State private var selectedLessonIDs: Set<UUID> = []
    @State private var searchText = ""
    @State private var sortOrder: LessonSortOrder = .newest
    @State private var isSelecting = false
    @State private var isShowingMoveSheet = false
    @State private var isShowingBulkDeleteConfirmation = false
    @State private var errorMessage: String?

    private let folderColumns = [
        GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 20)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summarySection
                if childFolders.isEmpty && lessons.isEmpty {
                    FolderContentsEmptyState()
                } else if displayedChildFolders.isEmpty && displayedLessons.isEmpty {
                    FolderContentsSearchEmptyState()
                } else {
                    if !isSelecting && !displayedChildFolders.isEmpty {
                        childFoldersSection
                    }
                    if !displayedLessons.isEmpty {
                        lessonsSection
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppColors.canvasBackground.ignoresSafeArea())
        .navigationTitle(folder.name)
        .searchable(text: $searchText, prompt: "Search lessons")
        .navigationDestination(for: Folder.self) { folder in
            FolderDetailView(folder: folder)
        }
        .navigationDestination(item: $selectedLesson) { lesson in
            LessonDetailView(lesson: lesson)
        }
        .toolbar {
            ToolbarItemGroup(placement: .secondaryAction) {
                if !lessons.isEmpty {
                    Menu {
                        Picker("Sort Lessons", selection: $sortOrder) {
                            ForEach(LessonSortOrder.allCases) { order in
                                Label(order.title, systemImage: order.systemImage)
                                    .tag(order)
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                    .disabled(isSelecting)

                    Button(isSelecting ? "Done" : "Select") {
                        toggleSelectionMode()
                    }
                    .accessibilityIdentifier("folder.selectButton")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showNewFolderSheet = true
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                    .accessibilityIdentifier("folder.newFolderButton")

                    Button {
                        showNewLessonSheet = true
                    } label: {
                        Label("New Lesson", systemImage: "doc.badge.plus")
                    }
                    .accessibilityIdentifier("folder.newLessonButton")

                    Button {
                        showLessonImporter = true
                    } label: {
                        Label("Import Lesson", systemImage: "square.and.arrow.down")
                    }
                    .accessibilityIdentifier("folder.importLessonButton")
                } label: {
                    Label("Add Lesson", systemImage: "plus")
                }
                .accessibilityIdentifier("folder.addMenu")
                .disabled(isSelecting)
            }
        }
        .sheet(isPresented: $showNewFolderSheet) {
            NameEntrySheet(
                title: "New Folder",
                placeholder: "Folder name",
                confirmLabel: "Create"
            ) { name in
                _ = try store.createFolder(named: name, at: folder.url)
                reloadFolderContents()
            }
        }
        .sheet(isPresented: $showNewLessonSheet) {
            NameEntrySheet(
                title: "New Lesson",
                placeholder: "Lesson name",
                confirmLabel: "Create",
                initialName: defaultLessonName
            ) { name in
                let lesson = try store.createLesson(named: name, in: folder)
                lessons = store.lessons(in: folder)
                selectedLesson = lesson
            }
        }
        .sheet(item: $folderToRename) { folder in
            NameEntrySheet(
                title: "Rename Folder",
                placeholder: "Folder name",
                confirmLabel: "Rename",
                initialName: folder.name
            ) { name in
                _ = try store.renameFolder(folder, to: name)
                reloadFolderContents()
            }
        }
        .fileImporter(
            isPresented: $showLessonImporter,
            allowedContentTypes: Self.importableLessonTypes,
            allowsMultipleSelection: false,
            onCompletion: handleLessonImport
        )
        .sheet(item: $lessonToRename) { lesson in
            NameEntrySheet(
                title: "Rename Lesson",
                placeholder: "Lesson name",
                confirmLabel: "Rename",
                initialName: lesson.name
            ) { name in
                let renamedLesson = try store.renameLesson(lesson, to: name, in: folder)
                lessons = store.lessons(in: folder)
                if selectedLesson?.id == lesson.id {
                    selectedLesson = renamedLesson
                }
            }
        }
        .sheet(isPresented: $isShowingMoveSheet) {
            MoveLessonsSheet(
                folders: moveDestinationFolders,
                selectedCount: selectedLessonIDs.count,
                onCancel: {
                    isShowingMoveSheet = false
                },
                onMove: { destination in
                    moveSelectedLessons(to: destination)
                }
            )
        }
        .sheet(item: $lessonToMove) { lesson in
            MoveLessonsSheet(
                folders: moveDestinationFolders,
                selectedCount: 1,
                onCancel: {
                    lessonToMove = nil
                },
                onMove: { destination in
                    move(lesson, to: destination)
                }
            )
        }
        .sheet(item: $lessonToAssign) { lesson in
            LessonAssignmentSheet(lesson: lesson)
                .environment(classroomRosterStore)
                .environment(classroomAssignmentStore)
                .environment(teacherAuthStore)
        }
        .overlay {
            if let lessonToDuplicate {
            DuplicateLessonOverlay(
                    lessonName: lessonToDuplicate.name,
                    onCancel: {
                        self.lessonToDuplicate = nil
                    },
                    onConfirm: { count in
                        duplicate(lessonToDuplicate, count: count)
                        self.lessonToDuplicate = nil
                    }
                )
                .transition(.opacity)
            }
        }
        .alert("Delete Folder?", isPresented: deleteFolderAlertBinding) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let folderToDelete {
                    delete(folderToDelete)
                }
            }
        } message: {
            Text("This permanently deletes \(folderToDelete?.name ?? "this folder") and all folders and lessons inside it.")
        }
        .alert("Delete Lesson?", isPresented: deleteAlertBinding) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let lessonToDelete {
                    delete(lessonToDelete)
                }
            }
        } message: {
            Text("This permanently deletes \(lessonToDelete?.name ?? "this lesson") from this folder.")
        }
        .alert("Delete Selected Lessons?", isPresented: $isShowingBulkDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteSelectedLessons()
            }
        } message: {
            Text("This permanently deletes ^[\(selectedLessonIDs.count) selected lesson](inflect: true) from this folder.")
        }
        .alert("Lesson Action Failed", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Something went wrong.")
        }
        .task {
            reloadFolderContents()
        }
    }

    private var defaultLessonName: String {
        "lesson \(Self.lessonDateFormatter.string(from: Date()))"
    }

    private static let lessonDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "ddMMyy"
        return formatter
    }()

    private static let importableLessonTypes: [UTType] = {
        var types: [UTType] = [.folder]
        if let mathboard = UTType(filenameExtension: "mathboard") {
            types.insert(mathboard, at: 0)
        }
        return types
    }()

    private var displayedLessons: [Lesson] {
        let filteredLessons: [Lesson]
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSearch.isEmpty {
            filteredLessons = lessons
        } else {
            filteredLessons = lessons.filter {
                $0.name.localizedCaseInsensitiveContains(trimmedSearch)
            }
        }

        return filteredLessons.sorted { first, second in
            switch sortOrder {
            case .newest:
                return first.modifiedAt > second.modifiedAt
            case .oldest:
                return first.modifiedAt < second.modifiedAt
            case .nameAscending:
                return first.name.localizedStandardCompare(second.name) == .orderedAscending
            case .nameDescending:
                return first.name.localizedStandardCompare(second.name) == .orderedDescending
            }
        }
    }

    private var displayedChildFolders: [Folder] {
        let filteredFolders: [Folder]
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSearch.isEmpty {
            filteredFolders = childFolders
        } else {
            filteredFolders = childFolders.filter {
                $0.name.localizedCaseInsensitiveContains(trimmedSearch)
            }
        }

        return filteredFolders.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private var selectedLessons: [Lesson] {
        lessons.filter { selectedLessonIDs.contains($0.id) }
    }

    private var moveDestinationFolders: [Folder] {
        store.allFolders().filter { $0.id != folder.id }
    }

    private var hasMoveDestinations: Bool {
        !moveDestinationFolders.isEmpty
    }

    private var areAllDisplayedLessonsSelected: Bool {
        !displayedLessons.isEmpty && displayedLessons.allSatisfy { selectedLessonIDs.contains($0.id) }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { lessonToDelete != nil },
            set: { isPresented in
                if !isPresented {
                    lessonToDelete = nil
                }
            }
        )
    }

    private var deleteFolderAlertBinding: Binding<Bool> {
        Binding(
            get: { folderToDelete != nil },
            set: { isPresented in
                if !isPresented {
                    folderToDelete = nil
                }
            }
        )
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

    private func toggleSelectionMode() {
        isSelecting.toggle()
        if !isSelecting {
            selectedLessonIDs = []
        }
    }

    private func toggleSelection(for lesson: Lesson) {
        if selectedLessonIDs.contains(lesson.id) {
            selectedLessonIDs.remove(lesson.id)
        } else {
            selectedLessonIDs.insert(lesson.id)
        }
    }

    private func duplicate(_ lesson: Lesson, count: Int) {
        do {
            let duplicatedLessons = try store.duplicateLessons(lesson, in: folder, count: count)
            lessons = store.lessons(in: folder)
            if count == 1 {
                selectedLesson = duplicatedLessons.first
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func reloadFolderContents() {
        childFolders = store.folders(in: folder)
        lessons = store.lessons(in: folder)
    }

    private func moveSelectedLessons(to destination: Folder) {
        do {
            _ = try store.moveLessons(selectedLessons, to: destination)
            lessons = store.lessons(in: folder)
            selectedLessonIDs = []
            isSelecting = false
            isShowingMoveSheet = false
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func move(_ lesson: Lesson, to destination: Folder) {
        do {
            _ = try store.moveLessons([lesson], to: destination)
            lessons = store.lessons(in: folder)
            selectedLessonIDs.remove(lesson.id)
            lessonToMove = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func handleLessonImport(_ result: Result<[URL], any Error>) {
        do {
            let urls = try result.get()
            guard let sourceURL = urls.first else { return }

            let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let imported = try store.importLessonPackage(from: sourceURL, into: folder)
            reloadFolderContents()
            selectedLesson = imported
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func delete(_ childFolder: Folder) {
        do {
            try store.deleteFolder(childFolder)
            reloadFolderContents()
            folderToDelete = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func updateColor(of childFolder: Folder, to color: FolderColor) {
        do {
            _ = try store.updateFolderColor(childFolder, to: color)
            reloadFolderContents()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func deleteSelectedLessons() {
        do {
            try store.deleteLessons(selectedLessons)
            lessons = store.lessons(in: folder)
            selectedLessonIDs = []
            isSelecting = false
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func delete(_ lesson: Lesson) {
        do {
            try store.deleteLesson(lesson)
            lessons = store.lessons(in: folder)
            if selectedLesson?.id == lesson.id {
                selectedLesson = nil
            }
            lessonToDelete = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private var summarySection: some View {
        HStack(spacing: 12) {
            Image(folder.color.assetName)
                .resizable()
                .scaledToFit()
                .frame(width: 58, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(summaryText)
                    .font(.headline)
                Text("Open a folder or tap a lesson.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var summaryText: String {
        let folderText = "\(childFolders.count) " + (childFolders.count == 1 ? "folder" : "folders")
        let lessonText = "\(lessons.count) " + (lessons.count == 1 ? "lesson" : "lessons")
        return "\(folderText) · \(lessonText)"
    }

    private var childFoldersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Folders", systemImage: "folder.fill")
            LazyVGrid(columns: folderColumns, spacing: 20) {
                ForEach(displayedChildFolders) { childFolder in
                    NavigationLink(value: childFolder) {
                        FolderTileView(folder: childFolder)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("folderTile.\(childFolder.name)")
                    .contextMenu {
                        Button {
                            folderToRename = childFolder
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }

                        folderColorMenu(for: childFolder)

                        Button(role: .destructive) {
                            folderToDelete = childFolder
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(.primary)
    }

    private func folderColorMenu(for folder: Folder) -> some View {
        Menu {
            ForEach(FolderColor.allCases) { color in
                Button {
                    updateColor(of: folder, to: color)
                } label: {
                    Label(color.title, systemImage: folder.color == color ? "checkmark.circle.fill" : "circle.fill")
                }
            }
        } label: {
            Label("Color", systemImage: "paintpalette")
        }
    }

    private var lessonsSection: some View {
        VStack(spacing: 8) {
            if isSelecting {
                selectionActionBar
            }

            ForEach(displayedLessons) { lesson in
                Button {
                    if isSelecting {
                        toggleSelection(for: lesson)
                    } else {
                        selectedLesson = lesson
                    }
                } label: {
                    LessonRow(
                        lesson: lesson,
                        isSelecting: isSelecting,
                        isSelected: selectedLessonIDs.contains(lesson.id)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("lessonRow.\(lesson.name)")
                .contextMenu {
                    if !isSelecting {
                        Button {
                            lessonToRename = lesson
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }

                        Button {
                            lessonToDuplicate = lesson
                        } label: {
                            Label("Duplicate", systemImage: "doc.on.doc")
                        }

                        Button {
                            lessonToMove = lesson
                        } label: {
                            Label("Move to Folder", systemImage: "folder")
                        }
                        .disabled(!hasMoveDestinations)

                        Button {
                            lessonToAssign = lesson
                        } label: {
                            Label("Assign Lesson", systemImage: "person.3.sequence")
                        }

                        Button(role: .destructive) {
                            lessonToDelete = lesson
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private var selectionActionBar: some View {
        HStack(spacing: 10) {
            Text("^[\(selectedLessonIDs.count) selected](inflect: true)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Button(areAllDisplayedLessonsSelected ? "Select None" : "Select All") {
                if areAllDisplayedLessonsSelected {
                    selectedLessonIDs.subtract(displayedLessons.map(\.id))
                } else {
                    selectedLessonIDs.formUnion(displayedLessons.map(\.id))
                }
            }
            .buttonStyle(.bordered)

            Button {
                isShowingMoveSheet = true
            } label: {
                Label("Move", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("folder.moveSelectedButton")
            .disabled(selectedLessonIDs.isEmpty || !hasMoveDestinations)

            Button(role: .destructive) {
                isShowingBulkDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .disabled(selectedLessonIDs.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct MoveLessonsSheet: View {
    let folders: [Folder]
    let selectedCount: Int
    let onCancel: () -> Void
    let onMove: (Folder) -> Void

    var body: some View {
        NavigationStack {
            List(folders) { folder in
                Button {
                    onMove(folder)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(AppColors.folderTint)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(folder.name)
                                .font(.headline)
                                .accessibilityIdentifier("moveDestination.name.\(folder.name)")
                            Text(folderPath(for: folder))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .accessibilityIdentifier("moveDestination.path.\(folderPath(for: folder))")
                            Text("^[\(folder.lessonCount) lesson](inflect: true)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("moveDestination.\(folder.name)")
                    .accessibilityLabel("\(folder.name), \(folderPath(for: folder))")
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Move ^[\(selectedCount) Lesson](inflect: true)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
            .frame(minWidth: 360, minHeight: 320)
        }
    }

    private func folderPath(for folder: Folder) -> String {
        let pathComponents = relativePathComponents(for: folder)
        guard !pathComponents.isEmpty else { return folder.name }
        return pathComponents.joined(separator: " / ")
    }

    private func relativePathComponents(for folder: Folder) -> [String] {
        let components = folder.url.standardizedFileURL.pathComponents
        let prefixCount = commonParentPathComponents.count
        guard components.count > prefixCount else { return [folder.name] }
        return Array(components.dropFirst(prefixCount))
    }

    private var commonParentPathComponents: [String] {
        guard let first = folders.first else { return [] }
        var prefix = first.url.deletingLastPathComponent().standardizedFileURL.pathComponents
        for folder in folders.dropFirst() {
            let components = folder.url.deletingLastPathComponent().standardizedFileURL.pathComponents
            prefix = Array(zip(prefix, components).prefix { $0 == $1 }.map(\.0))
        }
        return prefix
    }
}

private struct DuplicateLessonOverlay: View {
    let lessonName: String
    let onCancel: () -> Void
    let onConfirm: (Int) -> Void

    @State private var duplicateCount = 1

    var body: some View {
        ZStack {
            Color.black.opacity(0.14)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.bordered)

                    Spacer()

                    Button("Duplicate") {
                        onConfirm(duplicateCount)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Text("Duplicate Lesson")
                    .font(.largeTitle.weight(.bold))

                Text(lessonName)
                    .font(.headline)
                    .lineLimit(2)
                    .padding(.top, 18)

                Stepper(value: $duplicateCount, in: 1...10) {
                    LabeledContent("Number of duplicates", value: "\(duplicateCount)")
                        .font(.body)
                }
            }
            .padding(20)
            .frame(width: 560)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
            .shadow(radius: 18, y: 8)
        }
    }
}

private struct LessonRow: View {
    let lesson: Lesson
    var isSelecting = false
    var isSelected = false

    var body: some View {
        HStack(spacing: 12) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .frame(width: 28, height: 36)
            }

            LessonFileIconView()
            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.name)
                    .font(.subheadline.weight(.medium))
                Text(lesson.modifiedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if !isSelecting {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct FolderContentsEmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Nothing here yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Use Add Lesson to create a folder, create a lesson, or import one.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct FolderContentsSearchEmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No matching folders or lessons")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Try a different search term.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    NavigationStack {
        FolderDetailView(folder: Folder(
            name: "Algebra 2",
            url: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Algebra 2"),
            lessonCount: 0
        ))
    }
    .environment(DocumentStore())
    .environment(ClassroomRosterStore())
    .environment(ClassroomAssignmentStore())
}
