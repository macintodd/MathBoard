//
//  MathtivityCatalogSheet.swift
//  Library
//
//  Teacher-facing browser for online JSON mathtivities.
//

import SwiftUI

struct MathtivityCatalogSheet: View {
    let destinationName: String
    let items: [MathtivityCatalogItem]
    @Binding var searchText: String
    let isLoading: Bool
    let errorMessage: String?
    let openingItemIDs: Set<String>
    let onRefresh: @MainActor () async -> Void
    let onOpen: @MainActor (MathtivityCatalogItem) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedKind: MathtivityCatalogKind?
    @State private var selectedTopic: String?
    @State private var selectedActivityType: MathtivityCatalogActivityType?
    @State private var selectedDifficulty: String?
    @State private var selectedQuestionCount: CatalogQuestionCountFilter = .any

    private var filteredItems: [MathtivityCatalogItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            let matchesSearch = query.isEmpty
                || item.title.localizedCaseInsensitiveContains(query)
                || item.catalogKind.displayName.localizedCaseInsensitiveContains(query)
                || item.topic.localizedCaseInsensitiveContains(query)
                || (item.course?.localizedCaseInsensitiveContains(query) ?? false)
                || (item.answerMode?.displayName.localizedCaseInsensitiveContains(query) ?? false)
                || (item.difficulty?.localizedCaseInsensitiveContains(query) ?? false)
                || item.tags.contains { $0.localizedCaseInsensitiveContains(query) }

            let matchesKind = selectedKind.map { item.catalogKind == $0 } ?? true
            let matchesTopic = selectedTopic.map { item.topic == $0 } ?? true
            let matchesActivity = selectedActivityType.map { item.activityType == $0 } ?? true
            let matchesDifficulty = selectedDifficulty.map { item.difficulty == $0 } ?? true
            let matchesQuestionCount = selectedQuestionCount.matches(item.questionCount)
            return matchesSearch && matchesKind && matchesTopic && matchesActivity && matchesDifficulty && matchesQuestionCount
        }
    }

    private var availableTopics: [String] {
        sortedUnique(items.map(\.topic))
    }

    private var availableDifficulties: [String] {
        sortedUnique(items.compactMap(\.difficulty))
    }

    private var hasActiveFilters: Bool {
        selectedKind != nil
            || selectedTopic != nil
            || selectedActivityType != nil
            || selectedDifficulty != nil
            || selectedQuestionCount != .any
    }

    private var catalogSections: [CatalogSection] {
        [
            CatalogSection(
                title: "Widget Types",
                subtitle: "Starter formats teachers can customize",
                items: filteredItems
                    .filter { $0.catalogKind == .widgetTemplate }
                    .sorted(by: catalogSort)
            ),
            CatalogSection(
                title: "Built-In Interactives",
                subtitle: "Native classroom tools and interactive generators",
                items: filteredItems
                    .filter { $0.catalogKind == .builtInInteractive }
                    .sorted(by: catalogSort)
            ),
            CatalogSection(
                title: "Premade Mathtivities",
                subtitle: "Ready-to-edit activities organized by topic",
                items: filteredItems
                    .filter { $0.catalogKind == .premadeMathtivity }
                    .sorted(by: mathtivitySort)
            )
        ]
        .filter { !$0.items.isEmpty }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                catalogSearchField
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                catalogFilterBar
                    .padding(.bottom, 10)

                if let errorMessage {
                    catalogStatus(errorMessage, systemImage: "exclamationmark.triangle")
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                }

                if isLoading && items.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if catalogSections.isEmpty {
                    catalogStatus("No mathtivities found.", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(catalogSections) { section in
                            Section {
                                ForEach(section.items) { item in
                                    catalogRow(item)
                                }
                            } header: {
                                catalogSectionHeader(section)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable {
                        await onRefresh()
                    }
                }
            }
            .navigationTitle("Catalog")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await onRefresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                    .accessibilityLabel("Refresh Mathtivity Catalog")
                }
            }
        }
        .task {
            if items.isEmpty {
                await onRefresh()
            }
        }
    }

    private var catalogSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search catalog", text: $searchText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
            }
        }
        .font(.system(size: 15))
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
        )
    }

    private var catalogFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterMenu(
                    title: selectedKind?.displayName ?? "All Content",
                    systemImage: "square.grid.2x2"
                ) {
                    Button("All Content") { selectedKind = nil }
                    Divider()
                    ForEach(MathtivityCatalogKind.allCases, id: \.self) { kind in
                        Button(kind.displayName) { selectedKind = kind }
                    }
                }

                filterMenu(
                    title: selectedTopic ?? "All Topics",
                    systemImage: "tag"
                ) {
                    Button("All Topics") { selectedTopic = nil }
                    Divider()
                    ForEach(availableTopics, id: \.self) { topic in
                        Button(topic) { selectedTopic = topic }
                    }
                }

                filterMenu(
                    title: selectedActivityType?.displayName ?? "All Activity Types",
                    systemImage: "checklist"
                ) {
                    Button("All Activity Types") { selectedActivityType = nil }
                    Divider()
                    ForEach(MathtivityCatalogActivityType.allCases, id: \.self) { activityType in
                        Button(activityType.displayName) { selectedActivityType = activityType }
                    }
                }

                filterMenu(
                    title: selectedDifficulty?.capitalized ?? "All Difficulty",
                    systemImage: "speedometer"
                ) {
                    Button("All Difficulty") { selectedDifficulty = nil }
                    Divider()
                    ForEach(availableDifficulties, id: \.self) { difficulty in
                        Button(difficulty.capitalized) { selectedDifficulty = difficulty }
                    }
                }

                filterMenu(
                    title: selectedQuestionCount.displayName,
                    systemImage: "number"
                ) {
                    ForEach(CatalogQuestionCountFilter.allCases) { filter in
                        Button(filter.displayName) { selectedQuestionCount = filter }
                    }
                }

                if hasActiveFilters {
                    Button {
                        clearFilters()
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func filterMenu<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func catalogRow(_ item: MathtivityCatalogItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName(for: item))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(iconColor(for: item))
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                catalogBadges(for: item)
                if let description = item.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 10)
            Button {
                Task { await onOpen(item) }
            } label: {
                if openingItemIDs.contains(item.id) {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 54, height: 30)
                } else {
                    Text(buttonTitle(for: item))
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 54, height: 30)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(openingItemIDs.contains(item.id))
            .accessibilityLabel("Open \(item.title) in the Widget Engine")
        }
        .padding(.vertical, 6)
    }

    private func catalogSectionHeader(_ section: CatalogSection) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(section.title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.primary)
            Text(section.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .textCase(nil)
        .padding(.top, 6)
    }

    private func catalogBadges(for item: MathtivityCatalogItem) -> some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            catalogBadge(item.source.displayName)
            if item.catalogKind != .premadeMathtivity {
                catalogBadge(item.catalogKind.displayName)
            }
            if item.catalogKind != .builtInInteractive {
                catalogBadge(item.activityType.displayName)
            }
            if let answerMode = item.answerMode {
                catalogBadge(answerMode.displayName)
            }
            if let questionCount = item.questionCount {
                catalogBadge("\(questionCount) \(questionCount == 1 ? "question" : "questions")")
            }
            if let topicLevel = item.topicLevel {
                catalogBadge("Level \(topicLevel)")
            }
            if let difficulty = item.difficulty {
                catalogBadge(difficulty.capitalized)
            }
            catalogBadge(item.topic)
            ForEach(item.tags.prefix(2), id: \.self) { tag in
                catalogBadge(tag)
            }
        }
    }

    private func catalogBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.secondary.opacity(0.12))
            )
    }

    private func catalogStatus(_ message: String, systemImage: String) -> some View {
        Label(message, systemImage: systemImage)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.10))
            )
    }

    private func rowSubtitle(for item: MathtivityCatalogItem) -> String {
        [
            item.course,
            item.topic,
            item.activityType.displayName,
            item.difficulty
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " - ")
    }

    private func iconName(for item: MathtivityCatalogItem) -> String {
        switch item.catalogKind {
        case .widgetTemplate:
            return "square.on.square"
        case .builtInInteractive:
            return "hand.point.up.left"
        case .premadeMathtivity:
            break
        }

        switch item.activityType {
        case .multipleChoice:
            return item.mode == .scored ? "checklist" : "rectangle.on.rectangle"
        case .fillInTheBlank:
            return item.mode == .scored ? "text.cursor" : "text.alignleft"
        case .numericAnswer:
            return "number"
        case .expressionAnswer:
            return "function"
        case .matching:
            return "arrow.left.arrow.right"
        case .ordering:
            return "arrow.up.arrow.down"
        case .multiStep:
            return "list.number"
        }
    }

    private func iconColor(for item: MathtivityCatalogItem) -> Color {
        switch item.catalogKind {
        case .widgetTemplate:
            return Color(red: 0.35, green: 0.66, blue: 0.68)
        case .builtInInteractive:
            return Color(red: 0.35, green: 0.70, blue: 0.48)
        case .premadeMathtivity:
            break
        }

        switch item.mode {
        case .scored:
            return Color(red: 0.29, green: 0.53, blue: 0.86)
        case .demo:
            return Color(red: 0.42, green: 0.48, blue: 0.56)
        }
    }

    private func buttonTitle(for item: MathtivityCatalogItem) -> String {
        item.catalogKind == .builtInInteractive ? "Add" : "Open"
    }

    private func catalogSort(_ lhs: MathtivityCatalogItem, _ rhs: MathtivityCatalogItem) -> Bool {
        lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private func mathtivitySort(_ lhs: MathtivityCatalogItem, _ rhs: MathtivityCatalogItem) -> Bool {
        let lhsCourse = lhs.course ?? ""
        let rhsCourse = rhs.course ?? ""
        if lhsCourse.localizedCaseInsensitiveCompare(rhsCourse) != .orderedSame {
            return lhsCourse.localizedCaseInsensitiveCompare(rhsCourse) == .orderedAscending
        }
        if lhs.topic.localizedCaseInsensitiveCompare(rhs.topic) != .orderedSame {
            return lhs.topic.localizedCaseInsensitiveCompare(rhs.topic) == .orderedAscending
        }
        return catalogSort(lhs, rhs)
    }

    private func clearFilters() {
        selectedKind = nil
        selectedTopic = nil
        selectedActivityType = nil
        selectedDifficulty = nil
        selectedQuestionCount = .any
    }

    private func sortedUnique(_ values: [String]) -> [String] {
        Array(Set(values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

private struct CatalogSection: Identifiable {
    var id: String { title }
    var title: String
    var subtitle: String
    var items: [MathtivityCatalogItem]
}

private enum CatalogQuestionCountFilter: String, CaseIterable, Identifiable {
    case any
    case single
    case short
    case extended

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .any:
            return "Any Length"
        case .single:
            return "1 Question"
        case .short:
            return "2-5 Questions"
        case .extended:
            return "6+ Questions"
        }
    }

    func matches(_ questionCount: Int?) -> Bool {
        switch self {
        case .any:
            return true
        case .single:
            return questionCount == 1
        case .short:
            guard let questionCount else { return false }
            return (2...5).contains(questionCount)
        case .extended:
            guard let questionCount else { return false }
            return questionCount >= 6
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrangedRows(proposal: proposal, subviews: subviews)
        return CGSize(
            width: rows.map(\.width).max() ?? 0,
            height: rows.last.map { $0.y + $0.height } ?? 0
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrangedRows(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews) {
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(item.size)
                )
            }
        }
    }

    private func arrangedRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? 320
        var rows: [Row] = []
        var current = Row(y: 0)

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let nextX = current.items.isEmpty ? 0 : current.width + spacing
            if nextX + size.width > maxWidth, !current.items.isEmpty {
                rows.append(current)
                current = Row(y: (rows.last?.y ?? 0) + (rows.last?.height ?? 0) + lineSpacing)
            }
            let x = current.items.isEmpty ? 0 : current.width + spacing
            current.items.append(RowItem(index: index, x: x, size: size))
            current.width = x + size.width
            current.height = max(current.height, size.height)
        }

        if !current.items.isEmpty {
            rows.append(current)
        }
        return rows
    }

    private struct Row {
        var items: [RowItem] = []
        var y: CGFloat
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private struct RowItem {
        var index: Int
        var x: CGFloat
        var size: CGSize
    }
}
