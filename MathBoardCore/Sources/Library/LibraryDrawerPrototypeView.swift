//
//  LibraryDrawerPrototypeView.swift
//  MathBoardCore - Library module (PROTOTYPE)
//
//  A previewable, UI-only prototype for the future MathBoard Library drawer:
//  a right-side slide-out "materials drawer" for finding and (later) inserting
//  reusable teaching materials — stickers, widgets, collections, recents.
//
//  This is scaffolding for design exploration ONLY. It does NOT touch the
//  canvas, tool palette, slides, documents, or presentation, and implements no
//  persistence, drag/drop, or Extract → Sticker saving. All content is mock
//  data from `LibraryMock`. See MathBoard/LibraryDrawer_status.md.
//

import SwiftUI

// MARK: - Drawer

/// Right-side slide-out Library drawer prototype.
///
/// Owns its own open/closed and selection state so it can be dropped into any
/// preview host without external wiring. Every interaction is local: tapping a
/// tile only updates `selectedItemTitle`; nothing is placed on a canvas.
public struct LibraryDrawerPrototypeView: View {
    @State private var isOpen: Bool
    @State private var section: LibrarySection = .stickers
    @State private var stickerScope: StickerScope = .thisLesson
    @State private var searchText: String = ""
    @State private var selectedItemTitle: String?

    // Purely-mocked drag-to-place state. None of this touches a real canvas —
    // dropping over the left region only shows preview feedback.
    @State private var draggingItem: LibraryPrototypeItem?
    @State private var dragLocation: CGPoint = .zero
    @State private var placedItemTitle: String?
    @State private var containerWidth: CGFloat = 0

    private static let dragSpace = "LibraryDragSpace"

    /// - Parameter startOpen: whether the drawer begins open (handy for previews).
    public init(startOpen: Bool = true) {
        _isOpen = State(initialValue: startOpen)
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                // Mocked drop target over the canvas region, shown while dragging.
                if draggingItem != nil {
                    dropZone(containerWidth: proxy.size.width)
                        .transition(.opacity)
                }

                HStack(spacing: 0) {
                    Spacer(minLength: 0)

                    if isOpen {
                        panel
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    } else {
                        edgeTab
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.42, dampingFraction: 0.86), value: isOpen)
                .padding(.vertical, 24)

                // Ghost of the item following the finger (mock drag-to-place).
                if let draggingItem {
                    dragGhost(for: draggingItem)
                        .position(dragLocation)
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: Self.dragSpace)
            .animation(.easeInOut(duration: 0.15), value: draggingItem != nil)
            .onAppear { containerWidth = proxy.size.width }
            .onChange(of: proxy.size.width) { _, newValue in containerWidth = newValue }
            .task(id: placedItemTitle) {
                // Auto-clear the mocked "placed" feedback after a moment.
                guard placedItemTitle != nil else { return }
                try? await Task.sleep(for: .seconds(1.8))
                placedItemTitle = nil
            }
        }
    }

    // MARK: Mocked drag-to-place

    /// A simultaneous drag gesture so a quick tap still selects (tap-to-place),
    /// while a drag summons the ghost (drag-to-place). Both are mocked.
    private func dragGesture(for item: LibraryPrototypeItem) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .named(Self.dragSpace))
            .onChanged { value in
                draggingItem = item
                dragLocation = value.location
            }
            .onEnded { value in
                // Treat a release left of the panel as a drop on the canvas.
                let leadingEdge = containerWidth - LibraryTheme.openWidth
                if value.location.x < leadingEdge {
                    placedItemTitle = item.title
                    selectedItemTitle = item.title
                }
                draggingItem = nil
            }
    }

    private func dragGhost(for item: LibraryPrototypeItem) -> some View {
        HStack(spacing: 8) {
            Group {
                if item.kind == .widget {
                    WidgetTileGraphic(symbol: item.symbol ?? "square.grid.2x2")
                } else {
                    StickerThumbnail(style: item.thumbnail)
                }
            }
            .frame(width: 44, height: 44)
            Text(item.title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(LibraryTheme.ink)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white)
                .shadow(color: LibraryTheme.panelShadow, radius: 10, x: 0, y: 4)
        )
        .opacity(0.96)
        .rotationEffect(.degrees(-2))
    }

    private func dropZone(containerWidth: CGFloat) -> some View {
        let width = max(0, containerWidth - LibraryTheme.openWidth)
        return VStack(spacing: 8) {
            Image(systemName: "plus.viewfinder")
                .font(.system(size: 26, weight: .medium))
            Text("Drop to place on canvas")
                .font(.system(size: 13, weight: .semibold))
            Text("(mock — nothing is placed yet)")
                .font(.system(size: 11))
                .foregroundStyle(LibraryTheme.muted)
        }
        .foregroundStyle(LibraryTheme.accent)
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LibraryTheme.accent.opacity(0.06))
                .padding(24)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(LibraryTheme.accent.opacity(0.5),
                              style: .init(lineWidth: 2, dash: [8, 6]))
                .padding(24)
        )
        .allowsHitTesting(false)
    }

    // MARK: Closed edge tab

    private var edgeTab: some View {
        Button {
            isOpen = true
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 17, weight: .semibold))
                Text("Library")
                    .font(.system(size: 13, weight: .semibold))
                    .rotationEffect(.degrees(90))
                    .fixedSize()
                    .frame(height: 56)
            }
            .foregroundStyle(LibraryTheme.accent)
            .frame(width: LibraryTheme.edgeTabWidth, height: LibraryTheme.edgeTabHeight)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 16,
                    bottomLeadingRadius: 16,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0,
                    style: .continuous
                )
                .fill(LibraryTheme.panel)
                .shadow(color: LibraryTheme.panelShadow, radius: 8, x: -3, y: 3)
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 16,
                    bottomLeadingRadius: 16,
                    style: .continuous
                )
                .strokeBorder(LibraryTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Open panel

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            sectionTabs
            Divider().overlay(LibraryTheme.hairline)
            content
            footer
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
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: LibraryTheme.panelCornerRadius,
                bottomLeadingRadius: LibraryTheme.panelCornerRadius,
                style: .continuous
            )
            .strokeBorder(LibraryTheme.hairline.opacity(0.7), lineWidth: 1)
        )
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(LibraryTheme.accent)
                Text("Library")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(LibraryTheme.ink)
                Spacer()
                Button {
                    isOpen = false
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LibraryTheme.muted)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(LibraryTheme.recessed))
                }
                .buttonStyle(.plain)
            }

            searchField
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(LibraryTheme.muted)
            TextField("Search materials", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(LibraryTheme.ink)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(LibraryTheme.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LibraryTheme.recessed)
        )
    }

    private var sectionTabs: some View {
        HStack(spacing: 6) {
            ForEach(LibrarySection.allCases) { item in
                let selected = section == item
                Button {
                    section = item
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 15, weight: .semibold))
                        Text(item.title)
                            .font(.system(size: 10.5, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selected ? LibraryTheme.accent : LibraryTheme.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selected ? LibraryTheme.accent.opacity(0.12) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    // MARK: Content router

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch section {
                case .stickers: stickersContent
                case .widgets: widgetsContent
                case .collections: collectionsContent
                case .recent: recentContent
                }
            }
            .padding(16)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Stickers

    private var stickersContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            scopePicker
            let items = filtered(LibraryMock.stickers(for: stickerScope))
            if items.isEmpty {
                emptyState(text: "No stickers match “\(searchText)”.")
            } else {
                itemGrid(items)
            }
        }
    }

    private var scopePicker: some View {
        HStack(spacing: 4) {
            ForEach(StickerScope.allCases) { scope in
                let selected = stickerScope == scope
                Button {
                    stickerScope = scope
                } label: {
                    Text(scope.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selected ? Color.white : LibraryTheme.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selected ? LibraryTheme.accent : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(LibraryTheme.recessed)
        )
    }

    // MARK: Widgets

    private var widgetsContent: some View {
        let items = filtered(LibraryMock.widgets)
        return VStack(alignment: .leading, spacing: 10) {
            sectionCaption("Interactive objects — tap later to configure & place.")
            if items.isEmpty {
                emptyState(text: "No widgets match “\(searchText)”.")
            } else {
                itemGrid(items)
            }
        }
    }

    // MARK: Collections

    private var collectionsContent: some View {
        let rows = LibraryMock.collections.filter {
            searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText)
        }
        return VStack(alignment: .leading, spacing: 10) {
            sectionCaption("Organized sets by teaching context.")
            if rows.isEmpty {
                emptyState(text: "No collections match “\(searchText)”.")
            } else {
                ForEach(rows) { row in
                    collectionRow(row)
                }
            }
        }
    }

    private func collectionRow(_ row: LibraryCollectionRow) -> some View {
        let selected = selectedItemTitle == row.title
        return Button {
            selectedItemTitle = row.title
        } label: {
            HStack(spacing: 12) {
                Image(systemName: row.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(row.tint)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(row.tint.opacity(0.14))
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LibraryTheme.ink)
                    Text(row.metadata)
                        .font(.system(size: 11.5))
                        .foregroundStyle(LibraryTheme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LibraryTheme.muted)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: LibraryTheme.cardCornerRadius, style: .continuous)
                    .fill(LibraryTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LibraryTheme.cardCornerRadius, style: .continuous)
                    .strokeBorder(selected ? LibraryTheme.accent : LibraryTheme.hairline,
                                  lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Recent

    private var recentContent: some View {
        let items = filtered(LibraryMock.recent)
        return VStack(alignment: .leading, spacing: 10) {
            sectionCaption("Recently used stickers & widgets.")
            if items.isEmpty {
                emptyState(text: "Nothing recent matches “\(searchText)”.")
            } else {
                itemGrid(items)
            }
        }
    }

    // MARK: Shared grid + tile

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private func itemGrid(_ items: [LibraryPrototypeItem]) -> some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(items) { item in
                tile(item)
            }
        }
    }

    private func tile(_ item: LibraryPrototypeItem) -> some View {
        let selected = selectedItemTitle == item.title
        return Button {
            selectedItemTitle = item.title
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    if item.kind == .widget {
                        WidgetTileGraphic(symbol: item.symbol ?? "square.grid.2x2")
                    } else {
                        StickerThumbnail(style: item.thumbnail)
                    }
                }
                .frame(height: LibraryTheme.thumbnailHeight)
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(LibraryTheme.ink)
                        .lineLimit(1)
                    if let caption = item.caption {
                        Text(caption)
                            .font(.system(size: 10.5))
                            .foregroundStyle(LibraryTheme.muted)
                            .lineLimit(1)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: LibraryTheme.cardCornerRadius, style: .continuous)
                    .fill(LibraryTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LibraryTheme.cardCornerRadius, style: .continuous)
                    .strokeBorder(selected ? LibraryTheme.accent : LibraryTheme.hairline,
                                  lineWidth: selected ? 2 : 1)
            )
            .opacity(draggingItem == item ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(dragGesture(for: item))
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        if let placedItemTitle {
            footerBar(icon: "checkmark.circle.fill", text: "Placed on canvas: \(placedItemTitle)")
        } else if let selectedItemTitle {
            footerBar(icon: "hand.tap", text: "Selected: \(selectedItemTitle)")
        }
    }

    private func footerBar(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer()
        }
        .foregroundStyle(LibraryTheme.accent)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Rectangle().fill(LibraryTheme.accent.opacity(0.08))
        )
    }

    // MARK: Small helpers

    private func sectionCaption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(LibraryTheme.muted)
    }

    private func emptyState(text: String) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "tray")
                    .font(.system(size: 22))
                    .foregroundStyle(LibraryTheme.hairline)
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(LibraryTheme.muted)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(.vertical, 30)
    }

    /// Filters mock items by title against the search field (case-insensitive).
    private func filtered(_ items: [LibraryPrototypeItem]) -> [LibraryPrototypeItem] {
        guard !searchText.isEmpty else { return items }
        return items.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }
}

// MARK: - Generated thumbnails

/// Code-drawn sticker thumbnail. No image assets — every style is composed from
/// SwiftUI shapes so the prototype ships zero resources.
struct StickerThumbnail: View {
    let style: StickerThumbnailStyle

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(LibraryTheme.accent.opacity(0.6), lineWidth: 1)
            content
                .padding(10)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch style {
        case .slopeTriangle: SlopeTriangleGlyph()
        case .workedExample: WorkedExampleGlyph()
        case .graphCutout: GraphCutoutGlyph()
        case .formulaCard: FormulaGlyph(text: "y = mx + b")
        case .numberLine: NumberLineGlyph()
        case .coordinateGrid: CoordinateGridGlyph()
        case .highlightBox: HighlightBoxGlyph()
        case .arrowCallout: ArrowCalloutGlyph()
        case .genericCard: FormulaGlyph(text: "abc")
        }
    }
}

private struct SlopeTriangleGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: w * 0.15, y: h * 0.85))
                    p.addLine(to: CGPoint(x: w * 0.85, y: h * 0.15))
                }
                .stroke(LibraryTheme.accent, style: .init(lineWidth: 2, lineCap: .round))
                Path { p in
                    p.move(to: CGPoint(x: w * 0.30, y: h * 0.70))
                    p.addLine(to: CGPoint(x: w * 0.70, y: h * 0.70))
                    p.addLine(to: CGPoint(x: w * 0.70, y: h * 0.30))
                }
                .stroke(LibraryTheme.ink.opacity(0.55), style: .init(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

private struct WorkedExampleGlyph: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(LibraryTheme.ink.opacity(0.35))
                    .frame(width: i == 1 ? 44 : 58, height: 4)
            }
            Capsule()
                .fill(LibraryTheme.accent.opacity(0.55))
                .frame(width: 30, height: 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct GraphCutoutGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            Path { p in
                p.move(to: CGPoint(x: 0, y: h * 0.8))
                p.addCurve(
                    to: CGPoint(x: w, y: h * 0.2),
                    control1: CGPoint(x: w * 0.4, y: h * 0.9),
                    control2: CGPoint(x: w * 0.6, y: h * 0.1)
                )
            }
            .stroke(LibraryTheme.accent, style: .init(lineWidth: 2, lineCap: .round))
        }
    }
}

private struct FormulaGlyph: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold, design: .serif))
            .italic()
            .foregroundStyle(LibraryTheme.ink)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NumberLineGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, y = geo.size.height * 0.5
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: w, y: y))
                }
                .stroke(LibraryTheme.ink.opacity(0.5), lineWidth: 1.5)
                ForEach(0..<5, id: \.self) { i in
                    let x = w * (0.1 + 0.2 * Double(i))
                    Path { p in
                        p.move(to: CGPoint(x: x, y: y - 5))
                        p.addLine(to: CGPoint(x: x, y: y + 5))
                    }
                    .stroke(i == 2 ? LibraryTheme.accent : LibraryTheme.ink.opacity(0.5),
                            lineWidth: i == 2 ? 2 : 1.5)
                }
            }
        }
    }
}

private struct CoordinateGridGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                ForEach(1..<4, id: \.self) { i in
                    let x = w * Double(i) / 4
                    Path { p in
                        p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: h))
                    }.stroke(LibraryTheme.hairline, lineWidth: 1)
                    let y = h * Double(i) / 4
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y))
                    }.stroke(LibraryTheme.hairline, lineWidth: 1)
                }
                Path { p in
                    p.move(to: CGPoint(x: w * 0.5, y: 0)); p.addLine(to: CGPoint(x: w * 0.5, y: h))
                    p.move(to: CGPoint(x: 0, y: h * 0.5)); p.addLine(to: CGPoint(x: w, y: h * 0.5))
                }.stroke(LibraryTheme.accent, lineWidth: 1.5)
            }
        }
    }
}

private struct HighlightBoxGlyph: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.yellow.opacity(0.28))
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color.orange.opacity(0.7), style: .init(lineWidth: 1.5, dash: [4, 3]))
            Text("!")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.orange)
        }
    }
}

private struct ArrowCalloutGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            Path { p in
                p.move(to: CGPoint(x: w * 0.15, y: h * 0.8))
                p.addLine(to: CGPoint(x: w * 0.8, y: h * 0.25))
                p.move(to: CGPoint(x: w * 0.55, y: h * 0.22))
                p.addLine(to: CGPoint(x: w * 0.8, y: h * 0.25))
                p.addLine(to: CGPoint(x: w * 0.72, y: h * 0.5))
            }
            .stroke(LibraryTheme.accent, style: .init(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

/// Widget tile graphic — an SF Symbol on a soft blue chip communicating
/// "interactive object, tap to configure".
struct WidgetTileGraphic: View {
    let symbol: String
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LibraryTheme.accent.opacity(0.10))
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(LibraryTheme.accent)
        }
    }
}

// MARK: - Preview host

/// Mock whiteboard host so the drawer's scale and visual fit can be judged
/// against a realistic canvas. Nothing here represents the real Canvas module.
private struct LibraryDrawerPreviewHost: View {
    let startOpen: Bool

    var body: some View {
        ZStack {
            // Warm-white canvas with a faint page boundary and light grid.
            LibraryTheme.canvas.ignoresSafeArea()

            GridBackdrop()
                .opacity(0.5)

            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(LibraryTheme.hairline, lineWidth: 1)
                .padding(28)

            // A tiny mocked palette hint on the left (NOT the real tool palette).
            VStack(spacing: 8) {
                ForEach(["pencil.tip", "lasso", "textformat", "eraser"], id: \.self) { s in
                    Image(systemName: s)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(LibraryTheme.muted)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.white))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(LibraryTheme.hairline))
                }
            }
            .padding(.leading, 20)
            .frame(maxWidth: .infinity, alignment: .leading)

            // The drawer under test.
            LibraryDrawerPrototypeView(startOpen: startOpen)
        }
    }
}

private struct GridBackdrop: View {
    var body: some View {
        GeometryReader { geo in
            Path { p in
                let step: CGFloat = 32
                var x: CGFloat = 0
                while x < geo.size.width { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: geo.size.height)); x += step }
                var y: CGFloat = 0
                while y < geo.size.height { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: geo.size.width, y: y)); y += step }
            }
            .stroke(LibraryTheme.hairline.opacity(0.5), lineWidth: 0.5)
        }
        .ignoresSafeArea()
    }
}

// `traits: .landscapeLeft` forces the preview (and the iPad simulator device
// hosting it) into landscape — the orientation this drawer is designed for.
#Preview("Library Drawer — Open over canvas", traits: .landscapeLeft) {
    LibraryDrawerPreviewHost(startOpen: true)
}

#Preview("Library Drawer — Closed (edge tab)", traits: .landscapeLeft) {
    LibraryDrawerPreviewHost(startOpen: false)
}

#Preview("Library Drawer — Panel only", traits: .landscapeLeft) {
    ZStack {
        LibraryTheme.canvas.ignoresSafeArea()
        LibraryDrawerPrototypeView(startOpen: true)
    }
}
