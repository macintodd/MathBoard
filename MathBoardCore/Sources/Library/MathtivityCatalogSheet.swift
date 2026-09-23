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
    @State private var selectedWorkflow: CatalogWorkflowSelection = .all
    @State private var selectedKind: MathtivityCatalogKind?
    @State private var selectedTopic: String?
    @State private var selectedActivityType: MathtivityCatalogActivityType?
    @State private var selectedDifficulty: String?
    @State private var selectedQuestionCount: CatalogQuestionCountFilter = .any
    @State private var previewItem: MathtivityCatalogItem?

    private var filteredItems: [MathtivityCatalogItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            let matchesSearch = query.isEmpty
                || item.title.localizedCaseInsensitiveContains(query)
                || item.resolvedPedagogicalWorkflow.displayName.localizedCaseInsensitiveContains(query)
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

    private var selectedItems: [MathtivityCatalogItem] {
        filteredItems
            .filter { selectedWorkflow.matches($0) }
            .sorted(by: mathtivitySort)
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                catalogHeader
                    .padding(.horizontal, 28)
                    .padding(.top, 18)
                    .padding(.bottom, 14)

                Divider()

                catalogSearchTools
                    .padding(.horizontal, 28)
                    .padding(.top, 18)
                    .padding(.bottom, 14)

                workflowTabs
                    .padding(.horizontal, 28)
                    .padding(.bottom, 10)

                Divider()

                HStack(alignment: .top, spacing: 24) {
                    filterSidebar
                        .frame(width: 250)

                    resultPane
                }
                .padding(.horizontal, 28)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .background(catalogBackground)
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
        }
        .frame(minWidth: 980, idealWidth: 1180, minHeight: 700, idealHeight: 840)
        .sheet(item: $previewItem) { item in
            CatalogStaticPreviewSheet(item: item)
        }
        .task {
            if items.isEmpty {
                await onRefresh()
            }
        }
    }

    private var catalogHeader: some View {
        HStack(spacing: 16) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Catalog")

            Text("Activity Catalog")
                .font(.system(size: 31, weight: .heavy, design: .rounded))
                .foregroundStyle(catalogInk)

            Spacer()

            Button {
                Task { await onRefresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .accessibilityLabel("Refresh Activity Catalog")
        }
    }

    private var catalogSearchTools: some View {
        HStack(alignment: .center, spacing: 18) {
            catalogSearchField
                .frame(width: 340)

            Label("Filters combine together", systemImage: "checkmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 0.25, green: 0.36, blue: 0.18))

            Spacer()

            Text("Sorted by relevance")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var catalogSearchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search activities, topics, or skills", text: $searchText)
                .font(.system(size: 16))
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
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
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.76))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.black.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.07), radius: 5, y: 2)
    }

    private var workflowTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CatalogWorkflowSelection.allCases, id: \.self) { workflow in
                    workflowTabButton(for: workflow)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func workflowTabButton(for workflow: CatalogWorkflowSelection) -> some View {
        Button {
            selectedWorkflow = workflow
        } label: {
            Label(workflow.displayName, systemImage: workflow.iconName)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selectedWorkflow == workflow ? catalogAccent : Color.white.opacity(0.72))
                )
                .foregroundStyle(selectedWorkflow == workflow ? .white : catalogInk)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(selectedWorkflow == workflow ? Color.clear : Color.black.opacity(0.10), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(workflow.displayName), \(count(for: workflow)) activities")
    }

    private var filterSidebar: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Refine results")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(catalogInk)

                Divider()

                filterSection("Topic") {
                    filterOptionGrid(availableTopics, selectedValue: $selectedTopic)
                }

                filterSection("Activity type") {
                    filterOptionGrid(MathtivityCatalogActivityType.allCases.map(\.displayName), selectedValue: activityTypeBinding)
                }

                filterSection("Difficulty") {
                    filterOptionGrid(availableDifficulties.map { $0.capitalized }, selectedValue: difficultyBinding)
                }

                filterSection("Format") {
                    filterOptionGrid(MathtivityCatalogKind.allCases.map(\.displayName), selectedValue: kindBinding)
                }

                filterSection("Length") {
                    filterOptionGrid(CatalogQuestionCountFilter.allCases.map(\.displayName), selectedValue: questionCountBinding)
                }

                if hasActiveFilters {
                    Button {
                        clearFilters()
                    } label: {
                        Label("Clear filters", systemImage: "xmark.circle")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.bottom, 20)
        }
    }

    private var resultPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(selectedItems.count) matching \(selectedItems.count == 1 ? "activity" : "activities")")
                    .font(.system(size: 25, weight: .heavy, design: .rounded))
                    .foregroundStyle(catalogInk)
                Spacer()
            }

            if let errorMessage {
                catalogStatus(errorMessage, systemImage: "exclamationmark.triangle")
            }

            if isLoading && items.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if selectedItems.isEmpty {
                catalogStatus("No catalog items found.", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(selectedItems) { item in
                            catalogRow(item)
                            Divider()
                        }
                    }
                }
                .refreshable {
                    await onRefresh()
                }
            }
        }
    }

    private func catalogRow(_ item: MathtivityCatalogItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: iconName(for: item))
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(catalogAccent)
                .frame(width: 46, height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(iconColor(for: item).opacity(0.22))
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(item.resolvedPedagogicalWorkflow.displayName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(catalogAccent)

                Text(item.title)
                    .font(.system(size: 21, weight: .heavy, design: .rounded))
                    .foregroundStyle(catalogInk)
                    .lineLimit(2)

                if let description = item.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                catalogMetadataLine(for: item)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                Button {
                    Task { await onOpen(item) }
                } label: {
                    if openingItemIDs.contains(item.id) {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 92, height: 34)
                    } else {
                        Text("Add")
                            .font(.system(size: 15, weight: .bold))
                            .frame(width: 92, height: 34)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(catalogAccent)
                .disabled(openingItemIDs.contains(item.id))
                .accessibilityLabel("Add \(item.title)")

                Button {
                    previewItem = item
                } label: {
                    Text("Preview")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 92, height: 34)
                }
                .buttonStyle(.bordered)
                .tint(catalogInk)
                .accessibilityLabel("Preview \(item.title)")
            }
        }
        .padding(.vertical, 20)
    }

    private func catalogMetadataLine(for item: MathtivityCatalogItem) -> some View {
        FlowLayout(spacing: 16, lineSpacing: 6) {
            metadataText(item.topic)
            if let course = item.course, course != item.topic {
                metadataText(course)
            }
            metadataText(item.activityType.displayName)
            if let difficulty = item.difficulty {
                metadataText(difficulty.capitalized)
            }
            if let questionCount = item.questionCount {
                metadataText("\(questionCount) \(questionCount == 1 ? "question" : "questions")")
            }
            if let topicLevel = item.topicLevel {
                metadataText("Level \(topicLevel)")
            }
            ForEach(item.tags.prefix(2), id: \.self) { tag in
                metadataText(tag)
            }
        }
    }

    private func metadataText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func filterSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(catalogInk)
            content()
        }
    }

    private func filterOptionGrid(_ values: [String], selectedValue: Binding<String?>) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 12) {
            ForEach(values, id: \.self) { value in
                filterCheckbox(title: value, isSelected: selectedValue.wrappedValue == value) {
                    selectedValue.wrappedValue = selectedValue.wrappedValue == value ? nil : value
                }
            }
        }
    }

    private func filterCheckbox(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSelected ? catalogAccent : .secondary)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(catalogInk)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private var kindBinding: Binding<String?> {
        Binding(
            get: { selectedKind?.displayName },
            set: { newValue in
                selectedKind = MathtivityCatalogKind.allCases.first { $0.displayName == newValue }
            }
        )
    }

    private var activityTypeBinding: Binding<String?> {
        Binding(
            get: { selectedActivityType?.displayName },
            set: { newValue in
                selectedActivityType = MathtivityCatalogActivityType.allCases.first { $0.displayName == newValue }
            }
        )
    }

    private var difficultyBinding: Binding<String?> {
        Binding(
            get: { selectedDifficulty?.capitalized },
            set: { newValue in
                selectedDifficulty = availableDifficulties.first { $0.capitalized == newValue }
            }
        )
    }

    private var questionCountBinding: Binding<String?> {
        Binding(
            get: { selectedQuestionCount == .any ? nil : selectedQuestionCount.displayName },
            set: { newValue in
                selectedQuestionCount = CatalogQuestionCountFilter.allCases.first { $0.displayName == newValue } ?? .any
            }
        )
    }

    private func catalogStatus(_ message: String, systemImage: String) -> some View {
        Label(message, systemImage: systemImage)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.64))
            )
    }

    private func iconName(for item: MathtivityCatalogItem) -> String {
        switch item.resolvedPedagogicalWorkflow {
        case .bellRingerExitTicket:
            return "bell"
        case .conceptualInteractive:
            if item.catalogKind == .builtInInteractive {
                return "hand.point.up.left"
            }
        case .assessment:
            return "checkmark.clipboard"
        case .tools:
            return "wrench.and.screwdriver"
        case .classPlay:
            return "gamecontroller"
        }

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
        case .trivialPursuit:
            return "star.circle"
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
        switch item.resolvedPedagogicalWorkflow {
        case .bellRingerExitTicket:
            return Color(red: 0.82, green: 0.40, blue: 0.20)
        case .conceptualInteractive:
            return Color(red: 0.35, green: 0.70, blue: 0.48)
        case .assessment:
            return Color(red: 0.29, green: 0.53, blue: 0.86)
        case .tools:
            return Color(red: 0.42, green: 0.48, blue: 0.56)
        case .classPlay:
            return Color(red: 0.58, green: 0.40, blue: 0.76)
        }
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
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private func clearFilters() {
        selectedKind = nil
        selectedTopic = nil
        selectedActivityType = nil
        selectedDifficulty = nil
        selectedQuestionCount = .any
    }

    private func count(for workflow: CatalogWorkflowSelection) -> Int {
        filteredItems.filter { workflow.matches($0) }.count
    }

    private func sortedUnique(_ values: [String]) -> [String] {
        Array(Set(values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var catalogBackground: some ShapeStyle {
        Color(red: 0.98, green: 0.95, blue: 0.89)
    }

    private var catalogInk: Color {
        Color(red: 0.17, green: 0.12, blue: 0.09)
    }

    private var catalogAccent: Color {
        Color(red: 0.73, green: 0.28, blue: 0.17)
    }
}

private enum CatalogWorkflowSelection: Hashable, CaseIterable {
    case all
    case workflow(MathtivityCatalogWorkflow)

    static var allCases: [CatalogWorkflowSelection] {
        [.all] + MathtivityCatalogWorkflow.allCases.map { .workflow($0) }
    }

    var displayName: String {
        switch self {
        case .all:
            return "All categories"
        case .workflow(let workflow):
            return workflow.displayName
        }
    }

    var iconName: String {
        switch self {
        case .all:
            return "square.grid.2x2"
        case .workflow(let workflow):
            switch workflow {
            case .bellRingerExitTicket:
                return "bell"
            case .conceptualInteractive:
                return "hand.point.up.left"
            case .assessment:
                return "checkmark.clipboard"
            case .tools:
                return "wrench.and.screwdriver"
            case .classPlay:
                return "gamecontroller"
            }
        }
    }

    func matches(_ item: MathtivityCatalogItem) -> Bool {
        switch self {
        case .all:
            return true
        case .workflow(let workflow):
            return item.resolvedPedagogicalWorkflow == workflow
        }
    }
}

private struct CatalogStaticPreviewSheet: View {
    let item: MathtivityCatalogItem
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPage = 0

    private var pages: [CatalogPreviewPage] {
        var result: [CatalogPreviewPage] = [
            CatalogPreviewPage(
                title: item.title,
                subtitle: item.resolvedPedagogicalWorkflow.displayName,
                body: item.description ?? "Preview this activity before adding it to the board."
            )
        ]

        if let questionCount = item.questionCount, questionCount > 0 {
            let cappedCount = min(questionCount, 8)
            for index in 1...cappedCount {
                result.append(
                    CatalogPreviewPage(
                        title: "Question \(index)",
                        subtitle: item.topic,
                        body: staticQuestionPreviewText(for: index, total: questionCount)
                    )
                )
            }
        } else {
            result.append(
                CatalogPreviewPage(
                    title: "Activity View",
                    subtitle: item.topic,
                    body: "This preview is static. Add the activity to interact with the live widget on the canvas."
                )
            )
        }

        return result
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                TabView(selection: $selectedPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        previewPage(page)
                            .tag(index)
                    }
                }
                #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .always))
                #endif
                .frame(minHeight: 430)

                HStack {
                    Button {
                        selectedPage = max(selectedPage - 1, 0)
                    } label: {
                        Label("Previous", systemImage: "chevron.left")
                    }
                    .disabled(selectedPage == 0)

                    Spacer()

                    Text("\(selectedPage + 1) of \(pages.count)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        selectedPage = min(selectedPage + 1, pages.count - 1)
                    } label: {
                        Label("Next", systemImage: "chevron.right")
                    }
                    .disabled(selectedPage == pages.count - 1)
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
            .navigationTitle("Preview")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 520, idealWidth: 620, minHeight: 560, idealHeight: 640)
    }

    private func previewPage(_ page: CatalogPreviewPage) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(page.subtitle)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(red: 0.73, green: 0.28, blue: 0.17))

            Text(page.title)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.17, green: 0.12, blue: 0.09))
                .lineLimit(3)

            Text(page.body)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)
                .lineSpacing(4)

            Spacer()

            FlowLayout(spacing: 10, lineSpacing: 10) {
                previewBadge(item.source.displayName)
                previewBadge(item.activityType.displayName)
                if let difficulty = item.difficulty {
                    previewBadge(difficulty.capitalized)
                }
                if let questionCount = item.questionCount {
                    previewBadge("\(questionCount) questions")
                }
                ForEach(item.tags.prefix(4), id: \.self) { tag in
                    previewBadge(tag)
                }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 0.99, green: 0.97, blue: 0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.black.opacity(0.10), lineWidth: 1)
        )
    }

    private func previewBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.07))
            )
    }

    private func staticQuestionPreviewText(for index: Int, total: Int) -> String {
        if total == 1 {
            return "Static preview of the single prompt. Add it to the board to show the full interactive student version."
        }
        return "Static preview of prompt \(index). Add the activity to the board to interact with the full question set."
    }
}

private struct CatalogPreviewPage: Hashable {
    var title: String
    var subtitle: String
    var body: String
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
