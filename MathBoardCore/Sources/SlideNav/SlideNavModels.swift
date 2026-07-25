//
//  SlideNavModels.swift
//  MathBoardCore — SlideNav prototype module
//
//  Mock state for the redesigned slide navigator. This module is fully
//  isolated: nothing in MathBoard links it, and it links nothing. The state
//  here stands in for SlideStore so the navigator's look and interactions can
//  be designed in previews; when the design is approved, SlidesView will
//  drive the real view with its own store and callbacks.
//

import SwiftUI

/// A mock slide. `artVariant` picks which decorative doodle the thumbnail
/// (and the harness's fake canvas) draws, so slides are visually distinct.
/// `nil` means a blank slide — freshly added, nothing drawn yet.
struct SlideNavSlide: Identifiable, Equatable {
    let id = UUID()
    var artVariant: Int?
}

/// Where the navigator is anchored on the whiteboard. Controls which way the
/// filmstrip blooms (always toward the canvas) and its alignment.
enum SlideNavPlacement {
    case bottomTrailing
    case topLeading

    /// The filmstrip opens away from the anchored screen edge.
    var filmstripOpensDownward: Bool { self == .topLeading }

    /// Scale-bloom anchor for the filmstrip transition — the corner nearest
    /// the pill, so the panel appears to grow out of it.
    var bloomAnchor: UnitPoint {
        self == .bottomTrailing ? .bottomTrailing : .topLeading
    }
}

/// Interactive mock of the slide store, so previews behave like the real app.
@MainActor @Observable
final class SlideNavState {
    var slides: [SlideNavSlide]
    var currentIndex = 0
    var isFilmstripOpen = false {
        didSet {
            // Selection is a filmstrip-session concept; closing the strip clears it.
            if !isFilmstripOpen { selectedIDs.removeAll() }
        }
    }

    /// Multi-selection in the filmstrip, tracked by ID so it survives moves.
    var selectedIDs: Set<UUID> = []

    init(slideCount: Int = 9) {
        slides = (0..<slideCount).map { SlideNavSlide(artVariant: $0 % SlideNavMockArt.variantCount) }
    }

    var totalCount: Int { slides.count }
    var canGoPrevious: Bool { currentIndex > 0 }
    var canGoNext: Bool { currentIndex < slides.count - 1 }
    var currentSlide: SlideNavSlide? {
        slides.indices.contains(currentIndex) ? slides[currentIndex] : nil
    }

    func goToPrevious() {
        guard canGoPrevious else { return }
        currentIndex -= 1
    }

    func goToNext() {
        guard canGoNext else { return }
        currentIndex += 1
    }

    /// Inserts a blank slide after the current one and makes it the active
    /// slide, so pressing + on the last slide lands you on the new blank page.
    func addSlide() {
        let insertion = min(currentIndex + 1, slides.count)
        slides.insert(SlideNavSlide(artVariant: nil), at: insertion)
        currentIndex = insertion
    }

    // MARK: - Selection

    var hasSelection: Bool { !selectedIDs.isEmpty }
    var isAllSelected: Bool { !slides.isEmpty && selectedIDs.count == slides.count }
    var selectionCount: Int { selectedIDs.count }

    func isSelected(_ slide: SlideNavSlide) -> Bool {
        selectedIDs.contains(slide.id)
    }

    func goTo(_ index: Int) {
        guard slides.indices.contains(index) else { return }
        currentIndex = index
    }

    /// Adds or removes a slide from the selection. Selection is decoupled from
    /// navigation: selecting a slide does not make it current.
    func toggleSelection(at index: Int) {
        guard slides.indices.contains(index) else { return }
        let id = slides[index].id
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    /// Filmstrip tap: in normal browsing a tap navigates; while a selection
    /// exists (selection mode), taps toggle membership instead — long press is
    /// what starts a selection. Deselecting the last slide exits selection
    /// mode, so taps navigate again.
    func handleTap(at index: Int) {
        if hasSelection {
            toggleSelection(at: index)
        } else {
            goTo(index)
        }
    }

    func toggleSelectAll() {
        if isAllSelected {
            selectedIDs.removeAll()
        } else {
            selectedIDs = Set(slides.map(\.id))
        }
    }

    /// The indices header actions (move/delete) operate on: the selection when
    /// one exists, otherwise the current slide.
    private var actionIndices: [Int] {
        if hasSelection {
            return slides.enumerated().filter { selectedIDs.contains($0.element.id) }.map(\.offset)
        }
        return slides.indices.contains(currentIndex) ? [currentIndex] : []
    }

    // MARK: - Move / delete (selection-aware)

    /// Enabled until the action slides are packed against the left edge.
    var canMoveActionSlidesLeft: Bool {
        let indices = actionIndices
        return indices != Array(0..<indices.count)
    }

    /// Enabled until the action slides are packed against the right edge.
    var canMoveActionSlidesRight: Bool {
        let indices = actionIndices
        return indices != Array((slides.count - indices.count)..<slides.count)
    }

    /// At least one slide must survive a delete.
    var canDeleteActionSlides: Bool {
        let count = actionIndices.count
        return count > 0 && count < slides.count
    }

    /// Moves every action slide one step. Non-contiguous selections all shift
    /// together; slides already packed against the edge stay put and become a
    /// boundary the rest pack up against on further clicks.
    func moveActionSlides(by direction: Int) {
        let indices = actionIndices
        guard !indices.isEmpty else { return }
        let currentID = currentSlide?.id

        if direction < 0 {
            var boundary = 0
            for index in indices {
                if index > boundary {
                    slides.swapAt(index, index - 1)
                } else {
                    boundary = index + 1
                }
            }
        } else if direction > 0 {
            var boundary = slides.count - 1
            for index in indices.reversed() {
                if index < boundary {
                    slides.swapAt(index, index + 1)
                } else {
                    boundary = index - 1
                }
            }
        }

        if let currentID, let newIndex = slides.firstIndex(where: { $0.id == currentID }) {
            currentIndex = newIndex
        }
    }

    /// Deletes all action slides, then lands on the nearest survivor at or
    /// after the old current position (or the nearest one before it).
    func deleteActionSlides() {
        guard canDeleteActionSlides else { return }
        let doomed = Set(actionIndices)
        let survivorAfter = slides.enumerated().first { $0.offset >= currentIndex && !doomed.contains($0.offset) }?.element.id
        let survivorBefore = slides.enumerated().reversed().first { $0.offset < currentIndex && !doomed.contains($0.offset) }?.element.id

        slides = slides.enumerated().filter { !doomed.contains($0.offset) }.map(\.element)
        selectedIDs.removeAll()

        if let survivor = survivorAfter ?? survivorBefore,
           let index = slides.firstIndex(where: { $0.id == survivor }) {
            currentIndex = index
        } else {
            currentIndex = min(currentIndex, slides.count - 1)
        }
    }
}

/// Local copies of the app's warm color tokens (AppColors is internal to the
/// Documents module; the prototype must not depend on it).
enum SlideNavColors {
    static let canvasCream = Color(red: 0.98, green: 0.97, blue: 0.94)
    static let shellCream = Color(red: 0.97, green: 0.95, blue: 0.90)
    static let accent = Color(red: 0.91, green: 0.45, blue: 0.32)      // terracotta
    static let secondary = Color(red: 0.96, green: 0.78, blue: 0.45)   // mustard
    static let ink = Color(red: 0.24, green: 0.22, blue: 0.20)
    // Inner-outline glow on the depressed counter button.
    static let glow = Color(red: 1.0, green: 0.58, blue: 0.22)         // amber
}
