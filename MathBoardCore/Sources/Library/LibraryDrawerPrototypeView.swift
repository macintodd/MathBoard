//
//  LibraryDrawerPrototypeView.swift
//  MathBoardCore - Library module (PROTOTYPE)
//
//  A previewable, UI-only prototype of the MathBoard Library drawer: a
//  skeuomorphic gold "folder tab" on the right edge of the board that pulls out
//  a materials panel. The panel has two modes — Recent and Libraries — matching
//  the design mockups.
//
//  The drawer is live on the canvas overlay. Recents and starred global library
//  items persist, while drawer-to-canvas insertion is still future work. See
//  MathBoard/LibraryDrawer_status.md.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Drawer

/// Right-edge slide-out Library drawer. Owns its UI state (open/closed, mode,
/// opened library, and star destination), bridges persisted Recents with the
/// global Library store, and emits PNG-backed items for canvas insertion.
public struct LibraryDrawerPrototypeView: View {
    @State private var isOpen: Bool
    @State private var mode: LibraryMode = .recent
    /// The library currently opened inside the Libraries tab (nil = show the
    /// library grid). Opening a library also makes it the star destination.
    @State private var openedFolder: LibraryFolder?
    /// Where starring a Recent item files it — the last library opened.
    @State private var destination: LibraryFolder = LibraryMock.defaultDestination
    /// Local, mutable copy of Recent so stars can toggle in the prototype.
    @State private var recentItems: [LibraryObject] = LibraryMock.recent
    /// Local, mutable copy of persisted global libraries.
    @State private var folders: [LibraryFolder] = LibraryMock.folders
    @State private var storedFolders: [LibraryStoredFolder] = []
    @State private var storedLibraryItems: [String: [LibraryObject]] = [:]
    @State private var isNewLibrarySheetPresented = false
    @State private var newLibraryName = ""
    @State private var folderBeingRenamed: LibraryFolder?
    @State private var renameLibraryName = ""
    @State private var folderPendingDeletion: LibraryFolder?
    @State private var itemBeingRenamed: LibraryObject?
    @State private var renameItemTitle = ""
    /// Grid vs. list presentation for the Libraries browser.
    @State private var libraryLayout: LibraryLayout = .grid
    /// Smart-search query for the Libraries browser (matches name + keywords).
    @State private var librarySearch: String = ""
    /// Transient footer feedback (e.g. "Added … to Quadratics").
    @State private var feedback: String?

    private let recentLessonURL: URL?
    private let recentRefreshID: UUID
    private let onInsertItem: (@MainActor (LibraryCanvasDragPayload) -> Void)?

    /// - Parameters:
    ///   - startOpen: whether the drawer begins open (handy for previews).
    ///   - recentLessonURL: optional `.mathboard` package URL whose persisted Recent items should replace mock Recent.
    ///   - recentRefreshID: change this value after recording a Recent item to reload the drawer.
    ///   - onInsertItem: called when the user taps a PNG-backed Recent/Library item for quick canvas insertion.
    public init(
        startOpen: Bool = true,
        recentLessonURL: URL? = nil,
        recentRefreshID: UUID = UUID(),
        onInsertItem: (@MainActor (LibraryCanvasDragPayload) -> Void)? = nil
    ) {
        self.recentLessonURL = recentLessonURL
        self.recentRefreshID = recentRefreshID
        self.onInsertItem = onInsertItem
        _isOpen = State(initialValue: startOpen)
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            drawer
                .offset(x: isOpen ? 0 : LibraryTheme.openWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .task(id: feedback) {
            guard feedback != nil else { return }
            try? await Task.sleep(for: .seconds(1.8))
            feedback = nil
        }
        .task(id: recentRefreshID) {
            loadPersistedRecentItems()
            reloadStoredLibraries()
        }
        .alert("New Library", isPresented: $isNewLibrarySheetPresented) {
            TextField("Library name", text: $newLibraryName)
            Button("Cancel", role: .cancel) {
                newLibraryName = ""
            }
            Button("Create") {
                createLibrary()
            }
        } message: {
            Text("Create a reusable library for starred Recent items.")
        }
        .alert("Rename Library", isPresented: isRenameLibrarySheetPresented) {
            TextField("Library name", text: $renameLibraryName)
            Button("Cancel", role: .cancel) {
                folderBeingRenamed = nil
                renameLibraryName = ""
            }
            Button("Rename") {
                renameLibrary()
            }
        } message: {
            Text("Update the name for this reusable library.")
        }
        .alert("Rename Item", isPresented: isRenameItemSheetPresented) {
            TextField("Item title", text: $renameItemTitle)
            Button("Cancel", role: .cancel) {
                itemBeingRenamed = nil
                renameItemTitle = ""
            }
            Button("Rename") {
                renameItem()
            }
        } message: {
            Text("Update the title shown in this library.")
        }
        .alert("Delete Library?", isPresented: isDeleteLibraryAlertPresented) {
            Button("Cancel", role: .cancel) {
                folderPendingDeletion = nil
            }
            Button("Delete", role: .destructive) {
                deletePendingLibrary()
            }
        } message: {
            Text("This removes the library and its stored items. Board Recents are not affected.")
        }
    }

    private var drawer: some View {
        ZStack(alignment: .topTrailing) {
            panel

            // Gold folder tab, top-aligned near the top of the board.
            folderTab
                .padding(.top, LibraryTheme.folderTabTopInset)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .zIndex(1)
        }
        .frame(width: LibraryTheme.openWidth + LibraryTheme.folderTabWidth, alignment: .topTrailing)
        .frame(maxHeight: .infinity, alignment: .top)
        .compositingGroup()
    }

    private var isRenameLibrarySheetPresented: Binding<Bool> {
        Binding(
            get: { folderBeingRenamed != nil },
            set: { isPresented in
                if !isPresented {
                    folderBeingRenamed = nil
                    renameLibraryName = ""
                }
            }
        )
    }

    private var isDeleteLibraryAlertPresented: Binding<Bool> {
        Binding(
            get: { folderPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    folderPendingDeletion = nil
                }
            }
        )
    }

    private var isRenameItemSheetPresented: Binding<Bool> {
        Binding(
            get: { itemBeingRenamed != nil },
            set: { isPresented in
                if !isPresented {
                    itemBeingRenamed = nil
                    renameItemTitle = ""
                }
            }
        )
    }

    // MARK: Folder tab

    private var folderTab: some View {
        Button {
            loadPersistedRecentItems()
            reloadStoredLibraries()
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                isOpen.toggle()
            }
        } label: {
            Text("LIBRARY")
                .font(.system(size: 13, weight: .heavy))
                .tracking(2)
                .foregroundStyle(LibraryTheme.folderTabText)
                .fixedSize()
                .rotationEffect(.degrees(-90))
                .frame(width: LibraryTheme.folderTabWidth, height: LibraryTheme.folderTabHeight)
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
                            colors: [LibraryTheme.folderTab, LibraryTheme.folderTabEdge],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: LibraryTheme.panelShadow, radius: 6, x: -2, y: 3)
                )
                .overlay(alignment: .leading) {
                    // Thin darker seam where the tab meets the panel.
                    Rectangle()
                        .fill(LibraryTheme.folderTabEdge.opacity(0.6))
                        .frame(width: 1)
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: Panel

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            modePicker
            Divider().overlay(LibraryTheme.hairline)
            content
            if let feedback {
                footerBar(feedback)
            }
        }
        .frame(width: LibraryTheme.openWidth)
        .frame(maxHeight: .infinity)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: LibraryTheme.panelCornerRadius,
                bottomLeadingRadius: LibraryTheme.panelCornerRadius,
                style: .continuous
            )
            .fill(LibraryTheme.panel)
            .shadow(color: LibraryTheme.panelShadow, radius: 18, x: -6, y: 6)
        )
    }

    private var header: some View {
        HStack {
            Text("Library")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(LibraryTheme.ink)
            Spacer()
            Button {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    isOpen = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LibraryTheme.muted)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var modePicker: some View {
        HStack(spacing: 6) {
            ForEach(LibraryMode.allCases) { item in
                let selected = mode == item
                Button {
                    mode = item
                } label: {
                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selected ? LibraryTheme.ink : LibraryTheme.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selected ? LibraryTheme.card : Color.clear)
                                .shadow(color: selected ? LibraryTheme.panelShadow.opacity(0.6) : .clear,
                                        radius: 3, x: 0, y: 1)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(selected ? LibraryTheme.accent.opacity(0.7) : Color.clear,
                                              lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(LibraryTheme.recessed)
        )
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    // MARK: Content router

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .recent:
            recentContent
        case .libraries:
            if let openedFolder {
                libraryDetailContent(openedFolder)
            } else {
                libraryGridContent
            }
        }
    }

    // MARK: Recent

    private var recentContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                destinationBanner
                LazyVGrid(columns: gridColumns, spacing: 14) {
                    ForEach(recentItems) { item in
                        recentCard(item)
                    }
                }
            }
            .padding(18)
        }
    }

    private var destinationBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "star.fill")
                .font(.system(size: 13))
                .foregroundStyle(LibraryTheme.star)
            (
                Text("Starred items will be added to ")
                    .foregroundStyle(LibraryTheme.muted)
                + Text(destination.name)
                    .foregroundStyle(LibraryTheme.ink)
                    .fontWeight(.semibold)
            )
            .font(.system(size: 12.5))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LibraryTheme.bannerFill)
        )
    }

    private func recentCard(_ item: LibraryObject) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .top) {
                LibraryObjectThumbnail(item: item)
                    .frame(height: LibraryTheme.thumbnailHeight)
                    .frame(maxWidth: .infinity)
                    .clipped()

                HStack {
                    if let badge = item.badge {
                        LibraryBadgePill(badge: badge)
                    }
                    Spacer()
                    starButton(for: item)
                }
                .padding(8)
            }

            Divider().overlay(LibraryTheme.hairline)

            Text(item.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LibraryTheme.ink)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
        }
        .background(
            RoundedRectangle(cornerRadius: LibraryTheme.cardCornerRadius, style: .continuous)
                .fill(LibraryTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LibraryTheme.cardCornerRadius, style: .continuous)
                .strokeBorder(LibraryTheme.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: LibraryTheme.cardCornerRadius, style: .continuous))
        .onTapGesture {
            insertItemIfPossible(item)
        }
        .onDrag {
            dragItemProvider(for: item)
        }
        .contextMenu {
            if canRemoveFromOpenedLibrary(item) {
                Button(role: .destructive) {
                    removeFromOpenedLibrary(item)
                } label: {
                    Label("Remove from Library", systemImage: "trash")
                }
            }
        }
    }

    private func starButton(for item: LibraryObject) -> some View {
        Button {
            toggleStar(item)
        } label: {
            Image(systemName: item.isStarred ? "star.fill" : "star")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(item.isStarred ? LibraryTheme.star : LibraryTheme.muted)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.white.opacity(0.9)))
                .overlay(Circle().strokeBorder(LibraryTheme.hairline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func toggleStar(_ item: LibraryObject) {
        guard let index = recentItems.firstIndex(where: { $0.id == item.id }) else { return }
        guard let folderID = storedFolderID(for: destination) else {
            recentItems[index].isStarred.toggle()
            feedback = recentItems[index].isStarred
                ? "Added “\(item.title)” to \(destination.name)"
                : "Removed “\(item.title)” from \(destination.name)"
            return
        }

        do {
            if recentItems[index].isStarred {
                try LibraryStore.removeRecentItem(item.id, from: folderID)
                recentItems[index].isStarred = false
                feedback = "Removed “\(item.title)” from \(destination.name)"
            } else {
                try LibraryStore.addRecentItem(
                    recentID: item.id,
                    title: item.title,
                    kind: item.recentKind ?? .sticker,
                    thumbnailURL: item.thumbnailURL,
                    widgetCodeString: item.widgetCodeString,
                    textPayload: item.textPayload,
                    latexPayload: item.latexPayload,
                    to: folderID
                )
                recentItems[index].isStarred = true
                feedback = "Added “\(item.title)” to \(destination.name)"
            }
            reloadStoredLibraries()
        } catch {
            feedback = "Couldn’t update \(destination.name)"
        }
    }

    // MARK: Libraries — grid

    private var libraryGridContent: some View {
        VStack(spacing: 0) {
            librariesToolbar
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    let results = filteredFolders()
                    if !librarySearch.isEmpty {
                        if results.isEmpty {
                            emptyLibrariesState
                        } else {
                            librarySection("\(results.count) result\(results.count == 1 ? "" : "s")",
                                           results, showNewCard: false)
                        }
                    } else {
                        let pinned = results.filter(\.isPinned)
                        if !pinned.isEmpty {
                            librarySection("Pinned", pinned, showNewCard: false)
                        }
                        librarySection("All Libraries", results.filter { !$0.isPinned }, showNewCard: true)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
        }
    }

    /// Search field + grid/list toggle above the Libraries browser.
    private var librariesToolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(LibraryTheme.muted)
                TextField("Search libraries & contents", text: $librarySearch)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(LibraryTheme.ink)
                if !librarySearch.isEmpty {
                    Button { librarySearch = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(LibraryTheme.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(LibraryTheme.recessed))

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    libraryLayout = (libraryLayout == .grid ? .list : .grid)
                }
            } label: {
                Image(systemName: libraryLayout.toggleIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LibraryTheme.accent)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(LibraryTheme.recessed))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func librarySection(_ title: String, _ items: [LibraryFolder], showNewCard: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.5)
                .foregroundStyle(LibraryTheme.muted)

            if libraryLayout == .grid {
                LazyVGrid(columns: gridColumns, spacing: 14) {
                    ForEach(items) { folderCard($0) }
                    if showNewCard { newLibraryCard }
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(items) { folderRow($0) }
                    if showNewCard { newLibraryRow }
                }
            }
        }
    }

    private var emptyLibrariesState: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22))
                .foregroundStyle(LibraryTheme.hairline)
            Text("No libraries match “\(librarySearch)”")
                .font(.system(size: 12))
                .foregroundStyle(LibraryTheme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func filteredFolders() -> [LibraryFolder] {
        folders.filter { $0.matches(librarySearch) }
    }

    private func togglePin(_ folder: LibraryFolder) {
        guard let folderID = storedFolderID(for: folder) else {
            guard let index = folders.firstIndex(where: { $0.id == folder.id }) else { return }
            folders[index].isPinned.toggle()
            feedback = folders[index].isPinned ? "Pinned \(folder.name)" : "Unpinned \(folder.name)"
            return
        }

        do {
            let newValue = !folder.isPinned
            try LibraryStore.setPinned(newValue, for: folderID)
            reloadStoredLibraries()
            feedback = newValue ? "Pinned \(folder.name)" : "Unpinned \(folder.name)"
        } catch {
            feedback = "Couldn’t update \(folder.name)"
        }
    }

    /// 📌 pin toggle used on both the grid card and the list row.
    private func pinButton(_ folder: LibraryFolder) -> some View {
        Button {
            togglePin(folder)
        } label: {
            Image(systemName: folder.isPinned ? "pin.fill" : "pin")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(folder.isPinned ? LibraryTheme.accent : LibraryTheme.muted)
                .frame(width: 26, height: 26)
                .background(Circle().fill(.white.opacity(0.92)))
                .overlay(Circle().strokeBorder(LibraryTheme.hairline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    /// Compact list row used in List layout.
    private func folderRow(_ folder: LibraryFolder) -> some View {
        Button {
            open(folder)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: folder.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(folder.tint)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(folder.tint.opacity(0.16)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LibraryTheme.ink)
                        .lineLimit(1)
                    Text("\(folder.itemCount) items")
                        .font(.system(size: 11.5))
                        .foregroundStyle(LibraryTheme.muted)
                }
                Spacer(minLength: 6)
                pinButton(folder)
                folderMenuButton(folder)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LibraryTheme.muted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: LibraryTheme.cardCornerRadius, style: .continuous).fill(LibraryTheme.card))
            .overlay(RoundedRectangle(cornerRadius: LibraryTheme.cardCornerRadius, style: .continuous).strokeBorder(LibraryTheme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var newLibraryRow: some View {
        Button {
            newLibraryName = ""
            isNewLibrarySheetPresented = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LibraryTheme.muted)
                    .frame(width: 36, height: 36)
                Text("New library")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LibraryTheme.muted)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: LibraryTheme.cardCornerRadius, style: .continuous)
                    .strokeBorder(LibraryTheme.hairline, style: .init(lineWidth: 1.5, dash: [6, 4]))
            )
        }
        .buttonStyle(.plain)
    }

    private func folderCard(_ folder: LibraryFolder) -> some View {
        Button {
            open(folder)
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 10) {
                    Image(systemName: folder.symbol)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(folder.tint)
                        .frame(width: 56, height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(folder.tint.opacity(0.16))
                        )
                    Text(folder.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LibraryTheme.ink)
                        .lineLimit(1)
                    Text("\(folder.itemCount) items")
                        .font(.system(size: 11.5))
                        .foregroundStyle(LibraryTheme.muted)
                }
                .frame(maxWidth: .infinity)

                folderMenuButton(folder)
                    .padding(8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: LibraryTheme.cardCornerRadius, style: .continuous)
                    .fill(LibraryTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LibraryTheme.cardCornerRadius, style: .continuous)
                    .strokeBorder(LibraryTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var newLibraryCard: some View {
        Button {
            newLibraryName = ""
            isNewLibrarySheetPresented = true
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(LibraryTheme.muted)
                    .frame(width: 56, height: 56)
                Text("New library")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LibraryTheme.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: LibraryTheme.cardCornerRadius, style: .continuous)
                    .strokeBorder(LibraryTheme.hairline, style: .init(lineWidth: 1.5, dash: [6, 4]))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Libraries — opened detail

    private func libraryDetailContent(_ folder: LibraryFolder) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    openedFolder = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(LibraryTheme.ink)
                }
                .buttonStyle(.plain)

                Text(folder.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(LibraryTheme.ink)
                Spacer()
                folderMenuButton(folder)
                Text("\(folder.itemCount) items")
                    .font(.system(size: 12.5))
                    .foregroundStyle(LibraryTheme.muted)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            Divider().overlay(LibraryTheme.hairline)

            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 14) {
                    ForEach(libraryObjects(in: folder)) { item in
                        libraryObjectCard(item)
                    }
                }
                .padding(18)
            }
        }
    }

    private func libraryObjectCard(_ item: LibraryObject) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                LibraryObjectThumbnail(item: item)
                    .frame(height: LibraryTheme.thumbnailHeight)
                    .frame(maxWidth: .infinity)
                    .clipped()

                if canRemoveFromOpenedLibrary(item) {
                    libraryItemMenuButton(item)
                        .padding(8)
                }
            }

            Divider().overlay(LibraryTheme.hairline)

            Text(item.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LibraryTheme.ink)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
        }
        .background(
            RoundedRectangle(cornerRadius: LibraryTheme.cardCornerRadius, style: .continuous)
                .fill(LibraryTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LibraryTheme.cardCornerRadius, style: .continuous)
                .strokeBorder(LibraryTheme.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: LibraryTheme.cardCornerRadius, style: .continuous))
        .onTapGesture {
            insertItemIfPossible(item)
        }
        .onDrag {
            dragItemProvider(for: item)
        }
    }

    private func libraryItemMenuButton(_ item: LibraryObject) -> some View {
        Menu {
            Button {
                beginRenamingItem(item)
            } label: {
                Label("Rename Item", systemImage: "pencil")
            }

            Button(role: .destructive) {
                removeFromOpenedLibrary(item)
            } label: {
                Label("Remove from Library", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LibraryTheme.muted)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.white.opacity(0.92)))
                .overlay(Circle().strokeBorder(LibraryTheme.hairline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func folderMenuButton(_ folder: LibraryFolder) -> some View {
        Menu {
            Button {
                beginRenaming(folder)
            } label: {
                Label("Rename Library", systemImage: "pencil")
            }

            Button(role: .destructive) {
                beginDeleting(folder)
            } label: {
                Label("Delete Library", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LibraryTheme.muted)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.white.opacity(0.92)))
                .overlay(Circle().strokeBorder(LibraryTheme.hairline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: Shared

    private func reloadStoredLibraries() {
        storedFolders = LibraryStore.loadFolders()
        storedLibraryItems = Dictionary(
            uniqueKeysWithValues: storedFolders.map { folder in
                (folder.id.uuidString, storedObjects(in: folder))
            }
        )
        folders = storedFolders.map(libraryFolder(from:))

        if let refreshedDestination = folders.first(where: { $0.id == destination.id }) {
            destination = refreshedDestination
        } else if let first = folders.first {
            destination = first
        } else {
            destination = LibraryMock.defaultDestination
        }

        if let openedFolder {
            self.openedFolder = folders.first(where: { $0.id == openedFolder.id })
        }

        refreshRecentStarStates()
    }

    private func createLibrary() {
        do {
            let folder = try LibraryStore.createFolder(named: newLibraryName)
            newLibraryName = ""
            reloadStoredLibraries()
            if let opened = folders.first(where: { $0.id == folder.id.uuidString }) {
                open(opened)
                mode = .libraries
            }
            feedback = "Created \(folder.name)"
        } catch {
            feedback = "Couldn’t create library"
        }
    }

    private func beginRenaming(_ folder: LibraryFolder) {
        folderBeingRenamed = folder
        renameLibraryName = folder.name
    }

    private func renameLibrary() {
        guard let folder = folderBeingRenamed,
              let folderID = storedFolderID(for: folder) else {
            folderBeingRenamed = nil
            renameLibraryName = ""
            return
        }

        do {
            let renamed = try LibraryStore.renameFolder(folderID, to: renameLibraryName)
            folderBeingRenamed = nil
            renameLibraryName = ""
            reloadStoredLibraries()
            if let renamed,
               let refreshed = folders.first(where: { $0.id == renamed.id.uuidString }) {
                destination = refreshed
                if openedFolder?.id == refreshed.id {
                    openedFolder = refreshed
                }
            }
            feedback = renamed.map { "Renamed library to \($0.name)" } ?? "Renamed library"
        } catch {
            feedback = "Couldn’t rename \(folder.name)"
        }
    }

    private func beginDeleting(_ folder: LibraryFolder) {
        folderPendingDeletion = folder
    }

    private func deletePendingLibrary() {
        guard let folder = folderPendingDeletion,
              let folderID = storedFolderID(for: folder) else {
            folderPendingDeletion = nil
            return
        }

        do {
            try LibraryStore.deleteFolder(folderID)
            folderPendingDeletion = nil
            if openedFolder?.id == folder.id {
                openedFolder = nil
            }
            reloadStoredLibraries()
            feedback = "Deleted \(folder.name)"
        } catch {
            feedback = "Couldn’t delete \(folder.name)"
        }
    }

    private func libraryObjects(in folder: LibraryFolder) -> [LibraryObject] {
        storedLibraryItems[folder.id] ?? LibraryMock.objects(in: folder)
    }

    private func libraryFolder(from storedFolder: LibraryStoredFolder) -> LibraryFolder {
        let items = storedLibraryItems[storedFolder.id.uuidString] ?? []
        return LibraryFolder(
            id: storedFolder.id.uuidString,
            name: storedFolder.name,
            symbol: storedFolder.symbol,
            itemCount: items.count,
            tint: LibraryMock.tint(at: storedFolder.tintIndex),
            keywords: storedFolder.keywords,
            isPinned: storedFolder.isPinned
        )
    }

    private func storedObjects(in folder: LibraryStoredFolder) -> [LibraryObject] {
        LibraryStore.loadItems(in: folder.id).map { item in
            LibraryObject(
                id: item.id.uuidString,
                title: item.title,
                badge: item.kind.libraryBadge,
                thumbnail: item.kind.fallbackThumbnail,
                recentKind: item.kind,
                recentID: item.recentID,
                thumbnailURL: item.thumbnailPNGFileName.map {
                    LibraryStore.thumbnailURL(fileName: $0, in: folder.id)
                },
                widgetCodeString: item.widgetCodeString,
                textPayload: item.textPayload,
                latexPayload: item.latexPayload
            )
        }
    }

    private func refreshRecentStarStates() {
        guard let folderID = storedFolderID(for: destination) else { return }
        for index in recentItems.indices {
            recentItems[index].isStarred = LibraryStore.containsRecentItem(recentItems[index].id, in: folderID)
        }
    }

    private func isRecentItemStarred(_ recentID: String) -> Bool {
        guard let folderID = storedFolderID(for: destination) else { return false }
        return LibraryStore.containsRecentItem(recentID, in: folderID)
    }

    private func storedFolderID(for folder: LibraryFolder) -> UUID? {
        UUID(uuidString: folder.id)
    }

    private func canRemoveFromOpenedLibrary(_ item: LibraryObject) -> Bool {
        openedFolder != nil && item.recentID != nil
    }

    private func beginRenamingItem(_ item: LibraryObject) {
        itemBeingRenamed = item
        renameItemTitle = item.title
    }

    private func renameItem() {
        guard let item = itemBeingRenamed,
              let openedFolder,
              let folderID = storedFolderID(for: openedFolder),
              let itemID = UUID(uuidString: item.id) else {
            itemBeingRenamed = nil
            renameItemTitle = ""
            return
        }

        do {
            let renamed = try LibraryStore.renameItem(itemID, in: folderID, to: renameItemTitle)
            itemBeingRenamed = nil
            renameItemTitle = ""
            reloadStoredLibraries()
            feedback = renamed.map { "Renamed item to \($0.title)" } ?? "Renamed item"
        } catch {
            feedback = "Couldn’t rename \(item.title)"
        }
    }

    private func removeFromOpenedLibrary(_ item: LibraryObject) {
        guard let openedFolder,
              let folderID = storedFolderID(for: openedFolder),
              let recentID = item.recentID else {
            return
        }

        do {
            try LibraryStore.removeRecentItem(recentID, from: folderID)
            reloadStoredLibraries()
            feedback = "Removed “\(item.title)” from \(openedFolder.name)"
        } catch {
            feedback = "Couldn’t remove \(item.title)"
        }
    }

    private func dragItemProvider(for item: LibraryObject) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = item.title

        guard let payload = canvasPayload(for: item),
              let encodedPayload = try? JSONEncoder().encode(payload) else {
            return provider
        }

        provider.registerDataRepresentation(
            forTypeIdentifier: LibraryCanvasDragPayload.typeIdentifier,
            visibility: .all
        ) { completion in
            completion(encodedPayload, nil)
            return nil
        }
        return provider
    }

    private func insertItemIfPossible(_ item: LibraryObject) {
        guard let payload = canvasPayload(for: item) else { return }
        onInsertItem?(payload)
        feedback = "Placed “\(item.title)” on canvas"
    }

    private func canvasPayload(for item: LibraryObject) -> LibraryCanvasDragPayload? {
        guard let recentKind = item.recentKind else { return nil }

        if recentKind == .widget,
           let widgetCodeString = item.widgetCodeString {
            return LibraryCanvasDragPayload(
                title: item.title,
                kind: recentKind,
                displaySize: CGSize(width: 820, height: 420),
                widgetCodeString: widgetCodeString
            )
        }

        if recentKind == .text,
           let textPayload = item.textPayload {
            return LibraryCanvasDragPayload(
                title: item.title,
                kind: recentKind,
                displaySize: CGSize(width: textPayload.width, height: textPayload.height),
                textPayload: textPayload
            )
        }

        if recentKind == .latex,
           let latexPayload = item.latexPayload,
           let thumbnailURL = item.thumbnailURL,
           let pngData = try? Data(contentsOf: thumbnailURL) {
            return LibraryCanvasDragPayload(
                title: item.title,
                kind: recentKind,
                pngData: pngData,
                displaySize: CGSize(width: latexPayload.width, height: latexPayload.height),
                latexPayload: latexPayload
            )
        }

        guard let thumbnailURL = item.thumbnailURL,
              let pngData = try? Data(contentsOf: thumbnailURL) else {
            return nil
        }

        return LibraryCanvasDragPayload(
            title: item.title,
            kind: recentKind,
            pngData: pngData,
            displaySize: dragDisplaySize(forThumbnailAt: thumbnailURL)
        )
    }

    private func dragDisplaySize(forThumbnailAt url: URL) -> CGSize {
        let fallback = CGSize(width: 220, height: 160)
        guard let image = PlatformImage(contentsOfFile: url.path) else { return fallback }
        let width = max(image.size.width, 1)
        let height = max(image.size.height, 1)
        let maxSide: CGFloat = 320
        let scale = min(1, maxSide / max(width, height))
        return CGSize(width: width * scale, height: height * scale)
    }

    private func loadPersistedRecentItems() {
        guard let recentLessonURL else { return }
        let items = LibraryRecentStore.loadItems(forLessonURL: recentLessonURL)
        guard !items.isEmpty else {
            recentItems = []
            return
        }
        recentItems = items.map { item in
            LibraryObject(
                id: item.id.uuidString,
                title: item.title,
                badge: item.kind.libraryBadge,
                thumbnail: item.kind.fallbackThumbnail,
                recentKind: item.kind,
                thumbnailURL: item.thumbnailPNGFileName.map {
                    LibraryRecentStore.thumbnailURL(fileName: $0, forLessonURL: recentLessonURL)
                },
                widgetCodeString: item.widgetCodeString,
                textPayload: item.textPayload,
                latexPayload: item.latexPayload,
                isStarred: isRecentItemStarred(item.id.uuidString)
            )
        }
    }

    private let gridColumns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    private func open(_ folder: LibraryFolder) {
        openedFolder = folder
        destination = folder
        refreshRecentStarStates()
    }

    private func footerBar(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer()
        }
        .foregroundStyle(LibraryTheme.accent)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Rectangle().fill(LibraryTheme.accent.opacity(0.08)))
    }
}

private extension LibraryRecentKind {
    var libraryBadge: LibraryBadge {
        switch self {
        case .extractedInk:
            return .ink
        case .sticker:
            return .sticker
        case .image:
            return .sticker
        case .gif:
            return .gif
        case .text:
            return .text
        case .latex:
            return .latex
        case .widget:
            return .html
        case .graphSnapshot:
            return .ink
        }
    }

    var fallbackThumbnail: LibraryThumbnailStyle {
        switch self {
        case .extractedInk:
            return .inkSquare
        case .sticker, .image:
            return .goldStarSticker
        case .gif:
            return .gifCard
        case .text:
            return .genericGraph
        case .latex:
            return .genericGraph
        case .widget:
            return .timerWidget
        case .graphSnapshot:
            return .genericGraph
        }
    }
}

// MARK: - Badge pill

struct LibraryBadgePill: View {
    let badge: LibraryBadge
    var body: some View {
        Text(badge.rawValue)
            .font(.system(size: 10, weight: .heavy))
            .tracking(0.5)
            .foregroundStyle(badge.foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(badge.background))
    }
}

// MARK: - Thumbnails

private struct LibraryObjectThumbnail: View {
    let item: LibraryObject

    var body: some View {
        if let thumbnailURL = item.thumbnailURL,
           let image = PlatformImage(contentsOfFile: thumbnailURL.path) {
            Image(platformImage: image)
                .resizable()
                .scaledToFit()
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.97, green: 0.98, blue: 0.99))
        } else {
            LibraryThumbnail(style: item.thumbnail)
        }
    }
}

#if os(iOS)
private typealias PlatformImage = UIImage
private extension Image {
    init(platformImage: PlatformImage) {
        self.init(uiImage: platformImage)
    }
}
#elseif os(macOS)
private typealias PlatformImage = NSImage
private extension Image {
    init(platformImage: PlatformImage) {
        self.init(nsImage: platformImage)
    }
}
#endif

/// Code-drawn thumbnail. No image assets — every style is composed from SwiftUI
/// shapes so the prototype ships zero resources.
struct LibraryThumbnail: View {
    let style: LibraryThumbnailStyle

    var body: some View {
        ZStack {
            backdrop
            content.padding(14)
        }
    }

    @ViewBuilder
    private var backdrop: some View {
        switch style {
        case .goldStarSticker:
            CheckerboardBackdrop()
        case .gifCard:
            Color(red: 0.08, green: 0.09, blue: 0.11)
        case .timerWidget:
            Color(red: 0.93, green: 0.96, blue: 1.0)
        default:
            Color(red: 0.97, green: 0.98, blue: 0.99)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch style {
        case .parabola: ParabolaGlyph()
        case .sine: SineGlyph()
        case .circleRadius: CircleRadiusGlyph()
        case .barChart: BarChartGlyph()
        case .rightTriangle: RightTriangleGlyph()
        case .arrowUp: ArrowUpGlyph()
        case .goldStarSticker: GoldStarStickerGlyph()
        case .timerWidget: TimerWidgetGlyph()
        case .gifCard: GifGlyph()
        case .inkSquare: InkSquareGlyph()
        case .genericGraph: GenericGraphGlyph()
        }
    }
}

private struct AxesGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            Path { p in
                p.move(to: CGPoint(x: w * 0.5, y: 0)); p.addLine(to: CGPoint(x: w * 0.5, y: h))
                p.move(to: CGPoint(x: 0, y: h * 0.5)); p.addLine(to: CGPoint(x: w, y: h * 0.5))
            }
            .stroke(LibraryTheme.hairline, lineWidth: 1)
        }
    }
}

private struct ParabolaGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                AxesGlyph()
                Path { p in
                    p.move(to: CGPoint(x: w * 0.08, y: h * 0.1))
                    p.addQuadCurve(to: CGPoint(x: w * 0.92, y: h * 0.1),
                                   control: CGPoint(x: w * 0.5, y: h * 1.25))
                }
                .stroke(Color(red: 0.83, green: 0.24, blue: 0.22),
                        style: .init(lineWidth: 3, lineCap: .round))
            }
        }
    }
}

private struct SineGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            Path { p in
                p.move(to: CGPoint(x: 0, y: h * 0.5))
                for i in 0...40 {
                    let t = CGFloat(i) / 40
                    let x = t * w
                    let y = h * 0.5 - sin(t * .pi * 2) * h * 0.32
                    p.addLine(to: CGPoint(x: x, y: y))
                }
            }
            .stroke(Color(red: 0.16, green: 0.55, blue: 0.30),
                    style: .init(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct CircleRadiusGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let r = s * 0.42
            ZStack {
                Circle()
                    .strokeBorder(Color(red: 0.24, green: 0.36, blue: 0.80), lineWidth: 2.5)
                    .frame(width: r * 2, height: r * 2)
                    .position(c)
                Path { p in
                    p.move(to: c); p.addLine(to: CGPoint(x: c.x + r, y: c.y))
                }
                .stroke(Color(red: 0.24, green: 0.36, blue: 0.80), lineWidth: 2)
            }
        }
    }
}

private struct BarChartGlyph: View {
    private let heights: [CGFloat] = [0.45, 0.7, 0.9, 0.6]
    private let colors: [Color] = [
        Color(red: 0.16, green: 0.55, blue: 0.60),
        Color(red: 0.30, green: 0.66, blue: 0.42),
        Color(red: 0.85, green: 0.58, blue: 0.20),
        Color(red: 0.82, green: 0.34, blue: 0.30)
    ]
    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<heights.count, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(colors[i])
                        .frame(height: h * heights[i])
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

private struct RightTriangleGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            Path { p in
                p.move(to: CGPoint(x: w * 0.12, y: h * 0.85))
                p.addLine(to: CGPoint(x: w * 0.88, y: h * 0.85))
                p.addLine(to: CGPoint(x: w * 0.88, y: h * 0.15))
                p.closeSubpath()
            }
            .stroke(Color(red: 0.16, green: 0.52, blue: 0.55),
                    style: .init(lineWidth: 2.5, lineJoin: .round))
        }
    }
}

private struct ArrowUpGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            Path { p in
                p.move(to: CGPoint(x: w * 0.15, y: h * 0.85))
                p.addLine(to: CGPoint(x: w * 0.82, y: h * 0.18))
                p.move(to: CGPoint(x: w * 0.55, y: h * 0.16))
                p.addLine(to: CGPoint(x: w * 0.85, y: h * 0.15))
                p.addLine(to: CGPoint(x: w * 0.82, y: h * 0.45))
            }
            .stroke(Color(red: 0.83, green: 0.24, blue: 0.22),
                    style: .init(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct GoldStarStickerGlyph: View {
    var body: some View {
        Image(systemName: "star.fill")
            .font(.system(size: 34))
            .foregroundStyle(LibraryTheme.star)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.98, green: 0.72, blue: 0.36))
            )
            .rotationEffect(.degrees(-6))
            .shadow(color: .black.opacity(0.18), radius: 4, x: 1, y: 2)
    }
}

private struct TimerWidgetGlyph: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("00:45")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(LibraryTheme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(.white)
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(LibraryTheme.accent.opacity(0.4)))
                )
            Text("TIMER WIDGET")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1)
                .foregroundStyle(LibraryTheme.accent)
        }
    }
}

private struct GifGlyph: View {
    var body: some View {
        Text("GIF")
            .font(.system(size: 24, weight: .heavy))
            .foregroundStyle(.white.opacity(0.85))
    }
}

private struct InkSquareGlyph: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color(red: 0.83, green: 0.24, blue: 0.22))
            .frame(width: 46, height: 46)
    }
}

private struct GenericGraphGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                AxesGlyph()
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h * 0.75))
                    p.addLine(to: CGPoint(x: w, y: h * 0.25))
                }
                .stroke(LibraryTheme.accent, style: .init(lineWidth: 2.5, lineCap: .round))
            }
        }
    }
}

/// Transparent-looking checkerboard used behind cut-out stickers.
private struct CheckerboardBackdrop: View {
    var body: some View {
        GeometryReader { geo in
            let tile: CGFloat = 12
            let cols = Int(geo.size.width / tile) + 1
            let rows = Int(geo.size.height / tile) + 1
            Canvas { ctx, _ in
                for r in 0..<rows {
                    for c in 0..<cols {
                        if (r + c).isMultiple(of: 2) {
                            let rect = CGRect(x: CGFloat(c) * tile, y: CGFloat(r) * tile, width: tile, height: tile)
                            ctx.fill(Path(rect), with: .color(Color(white: 0.90)))
                        }
                    }
                }
            }
            .background(Color.white)
        }
    }
}

// MARK: - Preview host

/// Mock whiteboard host so the drawer's scale and fit can be judged against a
/// realistic board. Nothing here represents the real Canvas module.
private struct LibraryDrawerPreviewHost: View {
    let startOpen: Bool

    var body: some View {
        ZStack {
            LibraryTheme.canvas.ignoresSafeArea()

            // A faint bit of board content on the left, for scale.
            Text("y = x²")
                .font(.system(size: 20, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(LibraryTheme.ink.opacity(0.7))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(40)

            LibraryDrawerPrototypeView(startOpen: startOpen)
        }
    }
}

// Fixed-size preview avoids simulator-orientation startup work and keeps Xcode's
// canvas focused on a single isolated prototype.
#Preview("Library Drawer Prototype") {
    LibraryDrawerPreviewHost(startOpen: true)
        .frame(width: 1194, height: 744)
}
