//
//  SlideFilmstripView.swift
//  MathBoardCore - Slides module
//

import PDFKit
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct SlideFilmstripView: View {
    let slides: [SlideMetadata]
    let currentIndex: Int
    let backgroundURL: (SlideBackground) -> URL
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(slides.enumerated()), id: \.element.id) { index, slide in
                        SlideThumbnailTile(
                            slide: slide,
                            index: index,
                            isSelected: index == currentIndex,
                            backgroundURL: backgroundURL
                        ) {
                            onSelect(index)
                        }
                        .id(slide.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .frame(height: 132)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.quaternary, lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            .onAppear {
                scrollToCurrent(proxy)
            }
            .onChange(of: currentIndex) { _, _ in
                scrollToCurrent(proxy)
            }
        }
    }

    private func scrollToCurrent(_ proxy: ScrollViewProxy) {
        guard slides.indices.contains(currentIndex) else { return }
        withAnimation(.snappy(duration: 0.2)) {
            proxy.scrollTo(slides[currentIndex].id, anchor: .center)
        }
    }
}

private struct SlideThumbnailTile: View {
    let slide: SlideMetadata
    let index: Int
    let isSelected: Bool
    let backgroundURL: (SlideBackground) -> URL
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    thumbnail
                        .frame(width: 78, height: 96)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(
                                    isSelected ? Color.accentColor : Color.secondary.opacity(0.28),
                                    lineWidth: isSelected ? 3 : 1
                                )
                        }
                        .shadow(color: .black.opacity(0.14), radius: 4, y: 2)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                            .background(.white, in: Circle())
                            .padding(4)
                    }
                }

                Text("\(index + 1)")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Slide \(index + 1)")
        .accessibilityValue(isSelected ? "Current slide" : "")
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let background = slide.background,
           let image = thumbnailImage(for: background) {
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
            ZStack {
                Color.white
                Image(systemName: "square.and.pencil")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func thumbnailImage(for background: SlideBackground) -> PlatformImage? {
        guard background.kind == .pdfPage,
              let document = PDFDocument(url: backgroundURL(background)),
              let page = document.page(at: background.pageIndex) else { return nil }
        return page.thumbnail(of: CGSize(width: 160, height: 210), for: .mediaBox)
    }
}

#if os(iOS)
private typealias PlatformImage = UIImage
#elseif os(macOS)
private typealias PlatformImage = NSImage
#endif
