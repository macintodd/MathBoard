//
//  SlideNavigator.swift
//  MathBoardCore — Slides module
//
//  Floating bottom-pill navigator that shows the current slide position
//  and lets the teacher navigate, reorder, delete, or add slides.
//

import SwiftUI

struct SlideNavigator: View {
    let currentIndex: Int
    let totalCount: Int
    let isFilmstripExpanded: Bool
    let onToggleFilmstrip: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onMoveLeft: () -> Void
    let onMoveRight: () -> Void
    let onDelete: () -> Void
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
            }
            .disabled(currentIndex <= 0)

            Button(action: onToggleFilmstrip) {
                HStack(spacing: 5) {
                    Text(positionLabel)
                        .font(.subheadline.monospacedDigit().weight(.medium))
                    Image(systemName: isFilmstripExpanded ? "chevron.down" : "chevron.up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 112)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFilmstripExpanded ? "Hide slide thumbnails" : "Show slide thumbnails")

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
            }
            .disabled(currentIndex >= totalCount - 1)

            Divider()
                .frame(height: 18)

            Button(action: onMoveLeft) {
                Image(systemName: "arrow.left.to.line")
                    .font(.body.weight(.semibold))
            }
            .disabled(currentIndex <= 0)
            .accessibilityLabel("Move slide left")

            Button(action: onMoveRight) {
                Image(systemName: "arrow.right.to.line")
                    .font(.body.weight(.semibold))
            }
            .disabled(currentIndex >= totalCount - 1)
            .accessibilityLabel("Move slide right")

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.body.weight(.semibold))
            }
            .disabled(totalCount <= 1)
            .accessibilityLabel("Delete slide")

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
            }
            .accessibilityLabel("Add slide")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }

    private var positionLabel: String {
        guard totalCount > 0 else { return "No slides" }
        return "Slide \(currentIndex + 1) of \(totalCount)"
    }
}
