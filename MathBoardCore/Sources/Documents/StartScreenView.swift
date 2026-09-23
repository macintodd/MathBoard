//
//  StartScreenView.swift
//  MathBoardCore — Documents module
//
//  The first screen a teacher sees. Two-panel layout: dark sidebar (teacher
//  header, class management, recents) + cream main area (search, folder grid).
//

import SwiftUI
import UniformTypeIdentifiers

private enum FolderSortOrder: String, CaseIterable, Identifiable {
    case recent
    case nameAscending
    case nameDescending
    case mostLessons
    case fewestLessons

    var id: Self { self }

    var title: String {
        switch self {
        case .recent:         return "Recent"
        case .nameAscending:  return "A–Z"
        case .nameDescending: return "Z–A"
        case .mostLessons:    return "Most Lessons"
        case .fewestLessons:  return "Fewest Lessons"
        }
    }
}

public struct StartScreenView: View {
    @Environment(DocumentStore.self) private var store
    @Environment(ClassroomRosterStore.self) private var classroomRosterStore
    @Environment(ClassroomAssignmentStore.self) private var classroomAssignmentStore
    @Environment(MathBoardUserModeStore.self) private var userModeStore
    @Environment(MathBoardTeacherAuthStore.self) private var teacherAuthStore
    @State private var searchText: String = ""
    @State private var folderSortOrder: FolderSortOrder = .recent
    @State private var isFolderListView: Bool = false
    @State private var lessonSortOrder: LessonSortOrder = .newest
    @State private var showNewFolderSheet = false
    @State private var showLessonImporter = false
    @State private var showClassroomRosters = false
    @State private var showClassroomAssignments = false
    @State private var showTeacherAccount = false
    @State private var importedLesson: Lesson?
    @State private var folderToRename: Folder?
    @State private var folderToDelete: Folder?
    @State private var selectedSearchLessonIDs: Set<UUID> = []
    @State private var isSelectingSearchResults = false
    @State private var isShowingSearchMoveSheet = false
    @State private var importErrorMessage: String?
    @State private var folderActionErrorMessage: String?

    private let folderColumns = [
        GridItem(.adaptive(minimum: 190, maximum: 280), spacing: 14)
    ]

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 350)
            Divider()
                .overlay(Color.black.opacity(0.25))
            mainContent
        }
        .ignoresSafeArea()
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .navigationDestination(for: Folder.self) { folder in
            FolderDetailView(folder: folder)
        }
        .navigationDestination(item: $importedLesson) { lesson in
            LessonDetailView(lesson: lesson)
        }
        .fileImporter(
            isPresented: $showLessonImporter,
            allowedContentTypes: Self.importableLessonTypes,
            allowsMultipleSelection: false,
            onCompletion: handleLessonImport
        )
        .alert("Couldn't Open Lesson", isPresented: importErrorAlertBinding) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importErrorMessage ?? "Something went wrong.")
        }
        .alert("Delete Folder?", isPresented: deleteFolderAlertBinding) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let folderToDelete { delete(folderToDelete) }
            }
        } message: {
            Text("This permanently deletes \(folderToDelete?.name ?? "this folder") and all lessons inside it.")
        }
        .alert("Folder Action Failed", isPresented: folderActionErrorAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(folderActionErrorMessage ?? "Something went wrong.")
        }
        .sheet(isPresented: $showNewFolderSheet) {
            NameEntrySheet(
                title: "New Folder",
                placeholder: "Folder name",
                confirmLabel: "Create"
            ) { name in
                try store.createFolder(named: name)
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
            }
        }
        .sheet(isPresented: $isShowingSearchMoveSheet) {
            MoveLessonsSheet(
                folders: store.allFolders(),
                selectedCount: selectedSearchLessonIDs.count,
                onCancel: { isShowingSearchMoveSheet = false },
                onMove: { destination in moveSelectedSearchLessons(to: destination) }
            )
        }
        .sheet(isPresented: $showTeacherAccount) {
            TeacherAccountView()
                .environment(teacherAuthStore)
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
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader
            sidebarClassManagement
            Divider()
                .overlay(Color.white.opacity(0.10))
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            sidebarRecent
            Spacer()
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(AppColors.sidebarBackground)
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LESSON LIBRARY")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.40))
                .kerning(1.4)
                .padding(.bottom, 2)

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Welcome back,")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                    Text(teacherDisplayName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.80)
                }
                Spacer(minLength: 4)
                gearMenu
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 52)
        .padding(.bottom, 20)
    }

    private var gearMenu: some View {
        Menu {
            Button {
                showTeacherAccount = true
            } label: {
                Label(
                    teacherAuthStore.state.isSignedIn ? "Teacher Account" : "Teacher Sign In",
                    systemImage: "person.crop.circle"
                )
            }

            Divider()

            Button {
                showLessonImporter = true
            } label: {
                Label("Open Lesson File…", systemImage: "folder")
            }

            Button {
                userModeStore.switchToStudentMode()
            } label: {
                Label("Student Mode", systemImage: "person.crop.circle.badge.checkmark")
            }
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.12), in: Circle())
        }
    }

    private var sidebarClassManagement: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("CLASS MANAGEMENT")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.38))
                .kerning(1.2)
                .padding(.horizontal, 20)
                .padding(.bottom, 4)

            sidebarManagementRow(
                title: "Classroom Rosters",
                subtitle: classroomRosterSubtitle,
                systemImage: "person.3.sequence.fill",
                iconColor: Color(red: 0.88, green: 0.35, blue: 0.35)
            ) {
                showClassroomRosters = true
            }

            sidebarManagementRow(
                title: "Assignments & Reports",
                subtitle: "",
                systemImage: "chart.bar.doc.horizontal.fill",
                iconColor: Color(red: 0.94, green: 0.60, blue: 0.22)
            ) {
                showClassroomAssignments = true
            }
        }
        .padding(.bottom, 12)
    }

    private var sidebarRecent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !store.recentLessons.isEmpty {
                Text("RECENT")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.38))
                    .kerning(1.2)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 6)

                ForEach(store.recentLessons) { lesson in
                    Button {
                        importedLesson = lesson
                    } label: {
                        sidebarRecentRow(lesson: lesson)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sidebarManagementRow(
        title: String,
        subtitle: String,
        systemImage: String,
        iconColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(iconColor)
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: systemImage)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.50))
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sidebarRecentRow(lesson: Lesson) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(lessonAccentColor(for: lesson))
                .frame(width: 3, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(lessonFolderName(for: lesson)) · \(lesson.modifiedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    // MARK: - Main content

    private var mainContent: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if isSearching {
                        searchResultsSection
                    } else {
                        foldersSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 28)
            }
        }
        .background(AppColors.canvasBackground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Search folders and lessons", text: $searchText)
                    .font(.subheadline)
                    .submitLabel(.search)
                    .onSubmit { searchText = searchText }
                    .onChange(of: searchText) { _, _ in clearSearchSelectionIfNeeded() }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

            Button {
                showNewFolderSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(AppColors.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New Folder")
            .accessibilityIdentifier("start.newFolderButton")
        }
    }

    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            foldersHeader
            if store.folders.isEmpty {
                FoldersEmptyState()
            } else if isFolderListView {
                VStack(spacing: 8) {
                    ForEach(sortedFolders) { folder in
                        NavigationLink(value: folder) {
                            FolderListRow(folder: folder)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("folderTile.\(folder.name)")
                        .contextMenu { folderContextMenu(for: folder) }
                    }
                }
            } else {
                LazyVGrid(columns: folderColumns, spacing: 14) {
                    ForEach(sortedFolders) { folder in
                        NavigationLink(value: folder) {
                            FolderTileView(folder: folder)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("folderTile.\(folder.name)")
                        .contextMenu { folderContextMenu(for: folder) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func folderContextMenu(for folder: Folder) -> some View {
        Button {
            folderToRename = folder
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        folderColorMenu(for: folder)
        Button(role: .destructive) {
            folderToDelete = folder
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private var foldersHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("FOLDERS")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .kerning(1.2)
                    Text("All lesson folders")
                        .font(.title3.weight(.bold))
                }
                Spacer()
                if !store.folders.isEmpty {
                    Text("^[\(sortedFolders.count) folder](inflect: true)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 8)
                    Button {
                        isFolderListView.toggle()
                    } label: {
                        Image(systemName: isFolderListView ? "square.grid.2x2" : "list.bullet")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isFolderListView ? "Grid view" : "List view")
                }
            }

            // Sort pills
            if !store.folders.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(FolderSortOrder.allCases) { order in
                            Button {
                                folderSortOrder = order
                            } label: {
                                Text(order.title)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        folderSortOrder == order
                                            ? AppColors.accent.opacity(0.18)
                                            : Color.secondary.opacity(0.10),
                                        in: Capsule()
                                    )
                                    .foregroundStyle(folderSortOrder == order ? AppColors.accent : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Search results

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            if hasSearchResults {
                if !matchingFolders.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionLabel("Matching Folders")
                        LazyVGrid(columns: folderColumns, spacing: 14) {
                            ForEach(matchingFolders) { folder in
                                NavigationLink(value: folder) {
                                    FolderTileView(folder: folder)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    folderColorMenu(for: folder)
                                }
                            }
                        }
                    }
                }

                if !matchingLessons.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            sectionLabel("Matching Lessons")
                            Spacer()
                            Button(isSelectingSearchResults ? "Done" : "Select") {
                                isSelectingSearchResults.toggle()
                                if !isSelectingSearchResults { selectedSearchLessonIDs = [] }
                            }
                            .buttonStyle(.bordered)
                        }

                        if isSelectingSearchResults {
                            searchSelectionActionBar
                        }

                        VStack(spacing: 8) {
                            ForEach(matchingLessons) { lesson in
                                Button {
                                    if isSelectingSearchResults {
                                        toggleSearchLessonSelection(for: lesson)
                                    } else {
                                        importedLesson = lesson
                                    }
                                } label: {
                                    SearchLessonRow(
                                        lesson: lesson,
                                        isSelecting: isSelectingSearchResults,
                                        isSelected: selectedSearchLessonIDs.contains(lesson.id)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            } else {
                SearchEmptyState()
            }
        }
    }

    private var searchSelectionActionBar: some View {
        HStack(spacing: 10) {
            Text("^[\(selectedSearchLessonIDs.count) selected](inflect: true)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Button(areAllMatchingLessonsSelected ? "Select None" : "Select All") {
                if areAllMatchingLessonsSelected {
                    selectedSearchLessonIDs.subtract(matchingLessons.map(\.id))
                } else {
                    selectedSearchLessonIDs.formUnion(matchingLessons.map(\.id))
                }
            }
            .buttonStyle(.bordered)

            Button {
                isShowingSearchMoveSheet = true
            } label: {
                Label("Move", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .disabled(selectedSearchLessonIDs.isEmpty || store.allFolders().isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
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

    // MARK: - Computed properties

    private static let importableLessonTypes: [UTType] = {
        var types: [UTType] = [.folder]
        if let mathboard = UTType(filenameExtension: "mathboard") {
            types.insert(mathboard, at: 0)
        }
        return types
    }()

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool { !trimmedSearchText.isEmpty }

    private var sortedFolders: [Folder] { sort(store.folders) }

    private var matchingFolders: [Folder] {
        guard isSearching else { return [] }
        return sort(store.allFolders().filter {
            $0.name.localizedCaseInsensitiveContains(trimmedSearchText)
        })
    }

    private var matchingLessons: [Lesson] {
        guard isSearching else { return [] }
        return sort(store.allLessons().filter {
            $0.name.localizedCaseInsensitiveContains(trimmedSearchText)
        })
    }

    private var hasSearchResults: Bool {
        !matchingFolders.isEmpty || !matchingLessons.isEmpty
    }

    private var selectedSearchLessons: [Lesson] {
        matchingLessons.filter { selectedSearchLessonIDs.contains($0.id) }
    }

    private var areAllMatchingLessonsSelected: Bool {
        !matchingLessons.isEmpty && matchingLessons.allSatisfy { selectedSearchLessonIDs.contains($0.id) }
    }

    private var teacherDisplayName: String {
        guard let email = teacherAuthStore.state.email else { return "Professor" }
        let username = email.components(separatedBy: "@").first ?? email
        let parts = username
            .components(separatedBy: ".")
            .filter { !$0.isEmpty }
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return parts.isEmpty ? "Teacher" : parts.joined(separator: " ")
    }

    private var classroomRosterSubtitle: String {
        let count = classroomRosterStore.classrooms.count
        if count == 0 { return "No classes yet" }
        let students = classroomRosterStore.classrooms.flatMap(\.students).count
        return "\(count) class\(count == 1 ? "" : "es") · \(students) student\(students == 1 ? "" : "s")"
    }

    private func lessonFolderName(for lesson: Lesson) -> String {
        lesson.url.deletingLastPathComponent().lastPathComponent
    }

    private func lessonAccentColor(for lesson: Lesson) -> Color {
        let folderURL = lesson.url.deletingLastPathComponent()
        let folder = store.allFolders().first { $0.url == folderURL }
        return folder?.color.baseColor ?? AppColors.accent
    }

    private func sort(_ folders: [Folder]) -> [Folder] {
        folders.sorted { first, second in
            switch folderSortOrder {
            case .recent:
                let dateA = folderModificationDate(first)
                let dateB = folderModificationDate(second)
                if dateA == dateB {
                    return first.name.localizedStandardCompare(second.name) == .orderedAscending
                }
                return dateA > dateB
            case .nameAscending:
                return first.name.localizedStandardCompare(second.name) == .orderedAscending
            case .nameDescending:
                return first.name.localizedStandardCompare(second.name) == .orderedDescending
            case .mostLessons:
                if first.lessonCount == second.lessonCount {
                    return first.name.localizedStandardCompare(second.name) == .orderedAscending
                }
                return first.lessonCount > second.lessonCount
            case .fewestLessons:
                if first.lessonCount == second.lessonCount {
                    return first.name.localizedStandardCompare(second.name) == .orderedAscending
                }
                return first.lessonCount < second.lessonCount
            }
        }
    }

    private func folderModificationDate(_ folder: Folder) -> Date {
        (try? folder.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private func sort(_ lessons: [Lesson]) -> [Lesson] {
        lessons.sorted { first, second in
            switch lessonSortOrder {
            case .newest:      return first.modifiedAt > second.modifiedAt
            case .oldest:      return first.modifiedAt < second.modifiedAt
            case .nameAscending:
                return first.name.localizedStandardCompare(second.name) == .orderedAscending
            case .nameDescending:
                return first.name.localizedStandardCompare(second.name) == .orderedDescending
            }
        }
    }

    private var importErrorAlertBinding: Binding<Bool> {
        Binding(get: { importErrorMessage != nil }, set: { if !$0 { importErrorMessage = nil } })
    }

    private var deleteFolderAlertBinding: Binding<Bool> {
        Binding(get: { folderToDelete != nil }, set: { if !$0 { folderToDelete = nil } })
    }

    private var folderActionErrorAlertBinding: Binding<Bool> {
        Binding(get: { folderActionErrorMessage != nil }, set: { if !$0 { folderActionErrorMessage = nil } })
    }

    private func handleLessonImport(_ result: Result<[URL], any Error>) {
        do {
            let urls = try result.get()
            guard let sourceURL = urls.first else { return }
            let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
            defer { if didStartAccessing { sourceURL.stopAccessingSecurityScopedResource() } }
            importedLesson = try store.importLessonPackage(from: sourceURL)
        } catch {
            importErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func delete(_ folder: Folder) {
        do {
            try store.deleteFolder(folder)
            folderToDelete = nil
        } catch {
            folderActionErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func updateColor(of folder: Folder, to color: FolderColor) {
        do {
            _ = try store.updateFolderColor(folder, to: color)
        } catch {
            folderActionErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func toggleSearchLessonSelection(for lesson: Lesson) {
        if selectedSearchLessonIDs.contains(lesson.id) {
            selectedSearchLessonIDs.remove(lesson.id)
        } else {
            selectedSearchLessonIDs.insert(lesson.id)
        }
    }

    private func moveSelectedSearchLessons(to destination: Folder) {
        do {
            _ = try store.moveLessons(selectedSearchLessons, to: destination)
            selectedSearchLessonIDs = []
            isSelectingSearchResults = false
            isShowingSearchMoveSheet = false
        } catch {
            folderActionErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func clearSearchSelectionIfNeeded() {
        let matchingIDs = Set(matchingLessons.map(\.id))
        selectedSearchLessonIDs = selectedSearchLessonIDs.intersection(matchingIDs)
        if matchingIDs.isEmpty { isSelectingSearchResults = false }
    }
}

// MARK: - Row / empty-state subviews

private struct SearchLessonRow: View {
    let lesson: Lesson
    var isSelecting = false
    var isSelected = false

    var body: some View {
        LessonResultRow(
            lesson: lesson,
            detail: lesson.url.deletingLastPathComponent().lastPathComponent,
            isSelecting: isSelecting,
            isSelected: isSelected
        )
    }
}

private struct LessonResultRow: View {
    let lesson: Lesson
    let detail: String
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
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct FolderListRow: View {
    let folder: Folder

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(folder.color.cardColor)
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(folder.color.baseColor)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("^[\(folder.lessonCount) lesson](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct FoldersEmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No folders yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Tap + to create your first folder.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct SearchEmptyState: View {
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
        StartScreenView()
    }
    .environment(DocumentStore())
    .environment(ClassroomRosterStore())
    .environment(ClassroomAssignmentStore())
    .environment(MathBoardUserModeStore())
    .environment(MathBoardTeacherAuthStore(authProvider: DisabledTeacherAuthProvider()))
}
