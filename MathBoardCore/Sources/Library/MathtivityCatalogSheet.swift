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

    private var filteredItems: [MathtivityCatalogItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter { item in
            item.title.localizedCaseInsensitiveContains(query)
                || item.topic.localizedCaseInsensitiveContains(query)
                || (item.course?.localizedCaseInsensitiveContains(query) ?? false)
                || item.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                catalogSearchField
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)

                if let errorMessage {
                    catalogStatus(errorMessage, systemImage: "exclamationmark.triangle")
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                }

                if isLoading && items.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredItems.isEmpty {
                    catalogStatus("No mathtivities found.", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredItems) { item in
                        catalogRow(item)
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await onRefresh()
                    }
                }
            }
            .navigationTitle("Mathtivity Catalog")
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
                    Text("Open")
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

    private func catalogBadges(for item: MathtivityCatalogItem) -> some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            catalogBadge(item.mode.displayName)
            catalogBadge(item.activityType.displayName)
            if let topicLevel = item.topicLevel {
                catalogBadge("Level \(topicLevel)")
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
        switch item.mode {
        case .scored:
            return Color(red: 0.29, green: 0.53, blue: 0.86)
        case .demo:
            return Color(red: 0.42, green: 0.48, blue: 0.56)
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
