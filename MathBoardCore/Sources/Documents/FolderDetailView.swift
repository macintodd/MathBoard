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
    @State private var showClassroomRosters = false
    @State private var showClassroomAssignments = false
    @State private var errorMessage: String?
    @State private var selectedChildFolderURL: URL? = nil

    var body: some View {
        HStack(spacing: 0) {
            leftFolderPanel
            Divider()
            rightLessonPanel
        }
        .background(AppColors.canvasBackground.ignoresSafeArea())
        .navigationTitle(folder.name)
        .searchable(text: $searchText, prompt: "Search lessons")
        .navigationDestination(for: Folder.self) { nestedFolder in
            FolderDetailView(folder: nestedFolder)
        }
        .navigationDestination(item: $selectedLesson) { lesson in
            LessonDetailView(lesson: lesson)
        }
        .toolbar {
            ToolbarItemGroup(placement: .secondaryAction) {
                if !rawActiveLessons.isEmpty {
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
        .onChange(of: selectedChildFolderURL) { _, _ in
            isSelecting = false
            selectedLessonIDs = []
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
                let targetFolder: Folder
                if let id = selectedChildFolderURL,
                   let child = childFolders.first(where: { $0.id == id }) {
                    targetFolder = child
                } else {
                    targetFolder = folder
                }
                let lesson = try store.createLesson(named: name, in: targetFolder)
                reloadFolderContents()
                selectedLesson = lesson
            }
        }
        .sheet(item: $folderToRename) { folderTarget in
            NameEntrySheet(
                title: "Rename Folder",
                placeholder: "Folder name",
                confirmLabel: "Rename",
                initialName: folderTarget.name
            ) { name in
                _ = try store.renameFolder(folderTarget, to: name)
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
                let activeFolderForRename: Folder
                if let id = selectedChildFolderURL,
                   let child = childFolders.first(where: { $0.id == id }) {
                    activeFolderForRename = child
                } else {
                    activeFolderForRename = folder
                }
                let renamedLesson = try store.renameLesson(lesson, to: name, in: activeFolderForRename)
                classroomAssignmentStore.updateLessonTitle(renamedLesson.name, forLessonID: renamedLesson.id)
                reloadFolderContents()
                if selectedLesson?.id == lesson.id {
                    selectedLesson = renamedLesson
                }
            }
        }
        .sheet(isPresented: $isShowingMoveSheet) {
            MoveLessonsSheet(
                folders: moveDestinationFolders,
                selectedCount: selectedLessonIDs.count,
                onCancel: { isShowingMoveSheet = false },
                onMove: { destination in moveSelectedLessons(to: destination) }
            )
        }
        .sheet(item: $lessonToMove) { lesson in
            MoveLessonsSheet(
                folders: moveDestinationFolders,
                selectedCount: 1,
                onCancel: { lessonToMove = nil },
                onMove: { destination in move(lesson, to: destination) }
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
                    onCancel: { self.lessonToDuplicate = nil },
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
                if let folderToDelete { delete(folderToDelete) }
            }
        } message: {
            Text("This permanently deletes \(folderToDelete?.name ?? "this folder") and all folders and lessons inside it.")
        }
        .alert("Delete Lesson?", isPresented: deleteAlertBinding) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let lessonToDelete { delete(lessonToDelete) }
            }
        } message: {
            Text("This permanently deletes \(lessonToDelete?.name ?? "this lesson") from this folder.")
        }
        .alert("Delete Selected Lessons?", isPresented: $isShowingBulkDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteSelectedLessons() }
        } message: {
            Text("This permanently deletes ^[\(selectedLessonIDs.count) selected lesson](inflect: true) from this folder.")
        }
        .alert("Lesson Action Failed", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Something went wrong.")
        }
        .classroomRosterPresentation(
            isPresented: $showClassroomRosters,
            classroomRosterStore: classroomRosterStore
        )
        .classroomAssignmentsPresentation(
            isPresented: $showClassroomAssignments,
            classroomRosterStore: classroomRosterStore,
            classroomAssignmentStore: classroomAssignmentStore
        )
        .task {
            reloadFolderContents()
        }
    }

    // MARK: - Two-panel layout

    private var leftFolderPanel: some View {
        VStack(spacing: 0) {
            // Root folder — acts like the parent row at the top of the sidebar
            Button {
                selectedChildFolderURL = nil
            } label: {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(folder.color.cardColor)
                        .frame(width: 36, height: 36)
                        .overlay {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(folder.color.baseColor)
                        }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(folder.name)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(summaryText)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.50))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    selectedChildFolderURL == nil
                        ? Color.white.opacity(0.12)
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.top, 16)
            .dropDestination(for: String.self) { lessonIDStrings, _ in
                handleLessonDrop(lessonIDStrings, into: folder)
            }

            if !childFolders.isEmpty {
                Text("FOLDERS")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.38))
                    .kerning(1.2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 8)

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(sortedChildFolders) { child in
                            Button {
                                selectedChildFolderURL = child.id
                            } label: {
                                sidebarFolderCard(child)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { folderToRename = child } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                folderColorMenu(for: child)
                                Button(role: .destructive) { folderToDelete = child } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .dropDestination(for: String.self) { lessonIDStrings, _ in
                                handleLessonDrop(lessonIDStrings, into: child)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 16)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(width: 258)
        .background(AppColors.sidebarBackground)
    }

    private func sidebarFolderCard(_ child: Folder) -> some View {
        let isSelected = selectedChildFolderURL == child.id
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(child.color.baseColor)
                Spacer()
                Circle()
                    .fill(child.color.baseColor)
                    .frame(width: 9, height: 9)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            Spacer(minLength: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(child.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text("^[\(child.lessonCount) lesson](inflect: true)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, minHeight: 94)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(child.color.cardColor)
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(child.color.baseColor, lineWidth: 2.5)
            }
        }
        .shadow(
            color: child.color.baseColor.opacity(isSelected ? 0.40 : 0.20),
            radius: isSelected ? 9 : 5,
            y: isSelected ? 4 : 2
        )
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    private var rightLessonPanel: some View {
        VStack(spacing: 0) {
            // Drawer header — shows which folder you've opened
            drawerHeader

            // Lesson list inside the drawer
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if isSelecting {
                        selectionActionBar
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                    }

                    if displayedLessons.isEmpty {
                        if rawActiveLessons.isEmpty {
                            FolderContentsEmptyState()
                                .padding(.horizontal, 16)
                                .padding(.top, 14)
                        } else {
                            FolderContentsSearchEmptyState()
                                .padding(.horizontal, 16)
                                .padding(.top, 14)
                        }
                    } else {
                        ForEach(displayedLessons) { lesson in
                            LessonRow(
                                lesson: lesson,
                                isSelecting: isSelecting,
                                isSelected: selectedLessonIDs.contains(lesson.id),
                                onOpen: {
                                    if isSelecting {
                                        toggleSelection(for: lesson)
                                    } else {
                                        selectedLesson = lesson
                                    }
                                },
                                onRename: { lessonToRename = lesson },
                                onDuplicate: { lessonToDuplicate = lesson },
                                onMove: { lessonToMove = lesson },
                                canMove: hasMoveDestinations,
                                onAssign: { lessonToAssign = lesson },
                                onDelete: { lessonToDelete = lesson }
                            )
                            .draggable(lesson.id.uuidString)
                            .padding(.horizontal, 16)
                            .accessibilityIdentifier("lessonRow.\(lesson.name)")
                        }
                    }
                }
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            .background(AppColors.canvasBackground)
        }
    }

    private var drawerHeader: some View {
        let activeChild = childFolders.first { $0.id == selectedChildFolderURL }
        let activeName = activeChild?.name ?? folder.name
        let activeColor = (activeChild?.color ?? folder.color).baseColor
        let activeCardColor = (activeChild?.color ?? folder.color).cardColor
        let lessonCountText = "\(rawActiveLessons.count) " + (rawActiveLessons.count == 1 ? "lesson" : "lessons")
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(activeCardColor)
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(activeColor)
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(activeName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(lessonCountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Divider()
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

    private var rawActiveLessons: [Lesson] {
        if let id = selectedChildFolderURL,
           let child = childFolders.first(where: { $0.id == id }) {
            return store.lessons(in: child)
        }
        return lessons
    }

    private var displayedLessons: [Lesson] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = trimmedSearch.isEmpty
            ? rawActiveLessons
            : rawActiveLessons.filter { $0.name.localizedCaseInsensitiveContains(trimmedSearch) }

        return filtered.sorted { first, second in
            switch sortOrder {
            case .newest:      return first.modifiedAt > second.modifiedAt
            case .oldest:      return first.modifiedAt < second.modifiedAt
            case .nameAscending:
                return first.name.localizedStandardCompare(second.name) == .orderedAscending
            case .nameDescending:
                return first.name.localizedStandardCompare(second.name) == .orderedDescending
            }
        }
    }

    private var sortedChildFolders: [Folder] {
        childFolders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var selectedLessons: [Lesson] {
        rawActiveLessons.filter { selectedLessonIDs.contains($0.id) }
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

    @discardableResult
    private func handleLessonDrop(_ lessonIDStrings: [String], into destination: Folder) -> Bool {
        guard let uuidString = lessonIDStrings.first,
              let lessonID = UUID(uuidString: uuidString),
              let lesson = rawActiveLessons.first(where: { $0.id == lessonID }) else { return false }
        guard lesson.url.deletingLastPathComponent().standardizedFileURL
                != destination.url.standardizedFileURL else { return false }
        do {
            _ = try store.moveLessons([lesson], to: destination)
            reloadFolderContents()
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
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
        if let id = selectedChildFolderURL, !childFolders.contains(where: { $0.id == id }) {
            selectedChildFolderURL = nil
        }
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

    private var summaryText: String {
        let folderText = "\(childFolders.count) " + (childFolders.count == 1 ? "folder" : "folders")
        let lessonText = "\(lessons.count) " + (lessons.count == 1 ? "lesson" : "lessons")
        return "\(folderText) · \(lessonText)"
    }

    private func folderColorMenu(for folder: Folder) -> some View {
        Menu {
            ForEach(FolderColor.allCases) { color in
                Button {
                    updateColor(of: folder, to: color)
                } label: {
                    Label {
                        Text(color.title)
                    } icon: {
                        colorDotImage(for: color, selected: folder.color == color)
                    }
                }
            }
        } label: {
            Label("Color", systemImage: "paintpalette")
        }
    }

    /// Renders a colored filled circle as an always-original UIImage so UIKit's
    /// menu system preserves the color (SF Symbol template images lose color).
    @MainActor
    private func colorDotImage(for folderColor: FolderColor, selected: Bool) -> Image {
        #if os(iOS)
        let size = CGSize(width: 20, height: 20)
        let renderer = UIGraphicsImageRenderer(size: size)
        let uiImage = renderer.image { _ in
            UIColor(folderColor.baseColor).setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
            if selected {
                let checkPath = UIBezierPath()
                checkPath.lineWidth = 2
                checkPath.lineCapStyle = .round
                checkPath.lineJoinStyle = .round
                checkPath.move(to: CGPoint(x: 4.5, y: 10))
                checkPath.addLine(to: CGPoint(x: 8, y: 14))
                checkPath.addLine(to: CGPoint(x: 15.5, y: 6))
                UIColor.white.setStroke()
                checkPath.stroke()
            }
        }
        return Image(uiImage: uiImage.withRenderingMode(.alwaysOriginal))
        #else
        return Image(systemName: selected ? "checkmark.circle.fill" : "circle.fill")
            .symbolRenderingMode(.monochrome)
        #endif
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
    let onOpen: () -> Void
    let onRename: () -> Void
    let onDuplicate: () -> Void
    let onMove: () -> Void
    let canMove: Bool
    let onAssign: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onOpen) {
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
                }
                .padding(.leading, 12)
                .padding(.trailing, isSelecting ? 12 : 4)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isSelecting {
                Divider()
                    .frame(height: 28)

                HStack(spacing: 0) {
                    rowActionButton("rectangle.and.pencil.and.ellipsis", label: "Rename", action: onRename)
                    rowActionButton("doc.on.doc", label: "Duplicate", action: onDuplicate)
                    rowActionButton("folder", label: "Move to Folder", action: onMove, disabled: !canMove)
                    rowActionButton("person.3.sequence", label: "Assign Lesson", action: onAssign)
                    rowActionButton("trash", label: "Delete", action: onDelete, isDestructive: true)
                }
                .padding(.trailing, 4)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func rowActionButton(
        _ systemImage: String,
        label: String,
        action: @escaping () -> Void,
        disabled: Bool = false,
        isDestructive: Bool = false
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isDestructive ? Color.red : Color.secondary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
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
