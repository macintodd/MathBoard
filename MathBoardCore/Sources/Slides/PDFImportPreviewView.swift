//
//  PDFImportPreviewView.swift
//  MathBoardCore - Slides module
//

import PDFKit
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct PDFImportPreviewView: View {
    let pdfURL: URL
    let onCancel: () -> Void
    let onImport: ([Int]) -> Void

    @State private var selectedPages: Set<Int>

    private let document: PDFDocument?
    private let pageCount: Int
    private let columns = [
        GridItem(.adaptive(minimum: 132, maximum: 180), spacing: 16)
    ]

    init(
        pdfURL: URL,
        onCancel: @escaping () -> Void,
        onImport: @escaping ([Int]) -> Void
    ) {
        self.pdfURL = pdfURL
        self.onCancel = onCancel
        self.onImport = onImport

        let document = PDFDocument(url: pdfURL)
        self.document = document
        self.pageCount = document?.pageCount ?? 0
        _selectedPages = State(initialValue: Set(0..<(document?.pageCount ?? 0)))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(0..<pageCount, id: \.self) { pageIndex in
                        PDFPageSelectionTile(
                            document: document,
                            pageIndex: pageIndex,
                            isSelected: selectedPages.contains(pageIndex)
                        ) {
                            togglePage(pageIndex)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Import PDF Pages")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }

                ToolbarItemGroup(placement: .secondaryAction) {
                    Button("Select All") {
                        selectedPages = Set(0..<pageCount)
                    }
                    .disabled(selectedPages.count == pageCount)

                    Button("Select None") {
                        selectedPages.removeAll()
                    }
                    .disabled(selectedPages.isEmpty)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        onImport(selectedPages.sorted())
                    }
                    .disabled(selectedPages.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Text("\(selectedPages.count) of \(pageCount) pages selected")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Separate slides")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.regularMaterial)
            }
        }
    }

    private func togglePage(_ pageIndex: Int) {
        if selectedPages.contains(pageIndex) {
            selectedPages.remove(pageIndex)
        } else {
            selectedPages.insert(pageIndex)
        }
    }
}

private struct PDFPageSelectionTile: View {
    let document: PDFDocument?
    let pageIndex: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    PDFThumbnailView(document: document, pageIndex: pageIndex)
                        .aspectRatio(0.72, contentMode: .fit)
                        .background(Color.white)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(
                                    isSelected ? Color.accentColor : Color.secondary.opacity(0.28),
                                    lineWidth: isSelected ? 3 : 1
                                )
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .shadow(color: .black.opacity(0.12), radius: 5, y: 2)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .background(.white, in: Circle())
                        .padding(6)
                }

                Text("Page \(pageIndex + 1)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Page \(pageIndex + 1)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct PDFThumbnailView: View {
    let document: PDFDocument?
    let pageIndex: Int

    var body: some View {
        Group {
            if let image = thumbnailImage {
                #if os(iOS)
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                #else
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                #endif
            } else {
                Image(systemName: "doc")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var thumbnailImage: PlatformImage? {
        guard let page = document?.page(at: pageIndex) else { return nil }
        return page.thumbnail(of: CGSize(width: 220, height: 300), for: .mediaBox)
    }
}

#if os(iOS)
private typealias PlatformImage = UIImage
#elseif os(macOS)
private typealias PlatformImage = NSImage
#endif
