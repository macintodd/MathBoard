//
//  StartScreenView.swift
//  MathBoardCore — Documents module
//
//  The first screen a teacher sees. Folder-first browsing with a small
//  "Recent Lessons" strip for fast pre-class re-entry. Data is supplied
//  by `DocumentStore` injected through the environment.
//

import SwiftUI
import UniformTypeIdentifiers

private enum FolderSortOrder: String, CaseIterable, Identifiable {
    case nameAscending
    case nameDescending
    case mostLessons
    case fewestLessons

    var id: Self { self }

    var title: String {
        switch self {
        case .nameAscending:
            return "Name A-Z"
        case .nameDescending:
            return "Name Z-A"
        case .mostLessons:
            return "Most Lessons"
        case .fewestLessons:
            return "Fewest Lessons"
        }
    }

    var systemImage: String {
        switch self {
        case .nameAscending:
            return "textformat.abc"
        case .nameDescending:
            return "textformat.abc.dottedunderline"
        case .mostLessons:
            return "arrow.down"
        case .fewestLessons:
            return "arrow.up"
        }
    }
}

public struct StartScreenView: View {
    @Environment(DocumentStore.self) private var store
    @State private var searchText: String = ""
    @State private var isSearchPresented = false
    @State private var folderSortOrder: FolderSortOrder = .nameAscending
    @State private var lessonSortOrder: LessonSortOrder = .newest
    @State private var showNewFolderSheet = false
    @State private var showLessonImporter = false
    @State private var importedLesson: Lesson?
    @State private var folderToRename: Folder?
    @State private var folderToDelete: Folder?
    @State private var selectedSearchLessonIDs: Set<UUID> = []
    @State private var isSelectingSearchResults = false
    @State private var isShowingSearchMoveSheet = false
    @State private var importErrorMessage: String?
    @State private var folderActionErrorMessage: String?

    private let folderColumns = [
        GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 20)
    ]

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                headerSection
                if isSearching {
                    searchResultsSection
                } else {
                    foldersSection
                    if !store.recentLessons.isEmpty {
                        recentSection
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppColors.canvasBackground.ignoresSafeArea())
        .navigationTitle("MathBoard")
        .toolbar {
            ToolbarItemGroup(placement: .secondaryAction) {
                sortMenu

                Button {
                    showLessonImporter = true
                } label: {
                    Label("Open Lesson", systemImage: "folder")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNewFolderSheet = true
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
            }
        }
        .searchable(
            text: $searchText,
            isPresented: $isSearchPresented,
            prompt: "Search folders and lessons"
        )
        .onSubmit(of: .search) {
            isSearchPresented = false
        }
        .onChange(of: searchText) { _, _ in
            clearSearchSelectionIfNeeded()
        }
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
        .alert("Couldn’t Open Lesson", isPresented: importErrorAlertBinding) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importErrorMessage ?? "Something went wrong.")
        }
        .alert("Delete Folder?", isPresented: deleteFolderAlertBinding) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let folderToDelete {
                    delete(folderToDelete)
                }
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
                folders: store.folders,
                selectedCount: selectedSearchLessonIDs.count,
                onCancel: {
                    isShowingSearchMoveSheet = false
                },
                onMove: { destination in
                    moveSelectedSearchLessons(to: destination)
                }
            )
        }
    }

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

    private var isSearching: Bool {
        !trimmedSearchText.isEmpty
    }

    private var sortedFolders: [Folder] {
        sort(store.folders)
    }

    private var matchingFolders: [Folder] {
        guard isSearching else { return [] }
        return sort(store.folders.filter {
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

    private func sort(_ folders: [Folder]) -> [Folder] {
        folders.sorted { first, second in
            switch folderSortOrder {
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

    private func sort(_ lessons: [Lesson]) -> [Lesson] {
        lessons.sorted { first, second in
            switch lessonSortOrder {
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

    private var importErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { importErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    importErrorMessage = nil
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

    private var folderActionErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { folderActionErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    folderActionErrorMessage = nil
                }
            }
        )
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
        if matchingIDs.isEmpty {
            isSelectingSearchResults = false
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Welcome back, Professor")
                .font(.title2.weight(.semibold))
            Text("Pick up where you left off or start a new lesson.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var sortMenu: some View {
        Menu {
            Section("Folders") {
                Picker("Sort Folders", selection: $folderSortOrder) {
                    ForEach(FolderSortOrder.allCases) { order in
                        Label(order.title, systemImage: order.systemImage)
                            .tag(order)
                    }
                }
            }

            if isSearching {
                Section("Lessons") {
                    Picker("Sort Lessons", selection: $lessonSortOrder) {
                        ForEach(LessonSortOrder.allCases) { order in
                            Label(order.title, systemImage: order.systemImage)
                                .tag(order)
                        }
                    }
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .disabled(store.folders.isEmpty && !isSearching)
    }

    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Folders", systemImage: "folder.fill")
            if store.folders.isEmpty {
                FoldersEmptyState()
            } else {
                LazyVGrid(columns: folderColumns, spacing: 20) {
                    ForEach(sortedFolders) { folder in
                        NavigationLink(value: folder) {
                            FolderTile(folder: folder)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                folderToRename = folder
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                folderToDelete = folder
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Recent Lessons", systemImage: "clock")
            VStack(spacing: 8) {
                ForEach(store.recentLessons) { lesson in
                    Button {
                        importedLesson = lesson
                    } label: {
                        RecentLessonRow(lesson: lesson)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            if hasSearchResults {
                if !matchingFolders.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("Matching Folders", systemImage: "folder.fill")
                        LazyVGrid(columns: folderColumns, spacing: 20) {
                            ForEach(matchingFolders) { folder in
                                NavigationLink(value: folder) {
                                    FolderTile(folder: folder)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if !matchingLessons.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            sectionHeader("Matching Lessons", systemImage: "doc.richtext")
                            Spacer()
                            Button(isSelectingSearchResults ? "Done" : "Select") {
                                isSelectingSearchResults.toggle()
                                if !isSelectingSearchResults {
                                    selectedSearchLessonIDs = []
                                }
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
            .disabled(selectedSearchLessonIDs.isEmpty || store.folders.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(.primary)
    }
}

private struct FolderTile: View {
    let folder: Folder

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(AppColors.folderTint)
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("^[\(folder.lessonCount) lesson](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct RecentLessonRow: View {
    let lesson: Lesson

    var body: some View {
        LessonResultRow(
            lesson: lesson,
            detail: lesson.modifiedAt.formatted(.relative(presentation: .named))
        )
    }
}

private struct SearchLessonRow: View {
    let lesson: Lesson
    var isSelecting = false
    var isSelected = false

    var body: some View {
        LessonResultRow(
            lesson: lesson,
            detail: folderName,
            isSelecting: isSelecting,
            isSelected: isSelected
        )
    }

    private var folderName: String {
        lesson.url.deletingLastPathComponent().lastPathComponent
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

            Image(systemName: "doc.richtext")
                .font(.title3)
                .foregroundStyle(AppColors.accent)
                .frame(width: 36, height: 36)
                .background(AppColors.accent.opacity(0.12), in: Circle())
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

private struct FoldersEmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No folders yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
}
