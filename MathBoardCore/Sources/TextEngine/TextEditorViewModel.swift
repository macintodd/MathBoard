//
//  TextEditorViewModel.swift
//  TextEngine
//
//  Observable state + editing helpers backing `TextEditorModalView`.
//
//  Uses Swift's `@Observable` model style (no Combine/@Published). The view model
//  owns the mutable text and formatting state and produces an immutable
//  `TextEditorResult` on demand. It has no dependency on the app or the canvas.
//

import Foundation
import Observation
import CoreGraphics

@Observable
public final class TextEditorViewModel {

    // MARK: Editable state

    /// The full source text being edited, including inline markup.
    public var text: String

    /// Toolbar toggle states. These mirror the block-level formatting intent that
    /// flows into `TextEditorResult`; the actual inline spans are additionally
    /// written into `text` as markup by the editing helpers below.
    public var isBold: Bool
    public var isItalic: Bool
    public var isUnderline: Bool

    /// Point size for the text. Driven by the size slider in the editor.
    public var fontSize: CGFloat

    /// Currently selected font name. One of `availableFonts` — a placeholder set
    /// until real font handling lands during integration.
    public var fontName: String

    // MARK: Placeholder font choices

    /// Placeholder font options surfaced by the font selector. Names are mapped to
    /// concrete `Font.Design` values in the view; a Coordinator resolves them to a
    /// real font family at integration time.
    public static let availableFonts: [String] = ["System", "Serif", "Monospaced", "Rounded"]

    // MARK: Bounds

    /// Reasonable slider bounds for the editor's size control.
    public static let minimumFontSize: CGFloat = 10
    public static let maximumFontSize: CGFloat = 96

    /// Quick-pick sizes surfaced as preset buttons next to the size slider.
    public static let presetFontSizes: [CGFloat] = [10, 11, 12, 25, 50]

    // MARK: Init

    public init(
        text: String = "",
        isBold: Bool = false,
        isItalic: Bool = false,
        isUnderline: Bool = false,
        fontSize: CGFloat = 24,
        fontName: String = "System"
    ) {
        self.text = text
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderline = isUnderline
        self.fontSize = fontSize
        self.fontName = fontName
    }

    // MARK: Derived values

    /// LaTeX regions currently present in `text`, recomputed on access.
    public var detectedLaTeXRegions: [DetectedLaTeXRegion] {
        DetectedLaTeXRegion.detect(in: text)
    }

    /// The immutable result to hand back through the editor's Save closure.
    public var result: TextEditorResult {
        TextEditorResult(
            sourceText: text,
            fontSize: fontSize,
            fontName: fontName == "System" ? nil : fontName,
            isBold: isBold,
            isItalic: isItalic,
            isUnderline: isUnderline,
            markupConvention: .markdownWithHTMLUnderlineAndDollarMath,
            detectedLaTeXRegions: detectedLaTeXRegions
        )
    }

    // MARK: Editing helpers
    //
    // Each helper takes the caller's current selection (as a `Range<String.Index>`
    // over `text`). Behavior:
    //   • non-empty selection  → wrap the selected span in markers
    //   • empty selection      → insert a wrapped placeholder at the caret
    //   • nil selection        → append a wrapped placeholder at the end
    //
    // After any helper mutates `text`, the previous selection indices are no
    // longer valid; the view is expected to reset its selection binding.

    /// Toggle the Bold toolbar state and wrap/insert Markdown `**bold**` markers.
    public func toggleBold(in selection: Range<String.Index>?) {
        isBold.toggle()
        wrapOrInsert(prefix: "**", suffix: "**", placeholder: "bold text", in: selection)
    }

    /// Toggle the Italic toolbar state and wrap/insert Markdown `*italic*` markers.
    public func toggleItalic(in selection: Range<String.Index>?) {
        isItalic.toggle()
        wrapOrInsert(prefix: "*", suffix: "*", placeholder: "italic text", in: selection)
    }

    /// Toggle the Underline toolbar state and wrap/insert `<u>underline</u>` markers.
    /// Underline is not standard Markdown, so an explicit HTML-style tag is used.
    public func toggleUnderline(in selection: Range<String.Index>?) {
        isUnderline.toggle()
        wrapOrInsert(prefix: "<u>", suffix: "</u>", placeholder: "underlined text", in: selection)
    }

    /// Wrap/insert a `$$ … $$` LaTeX region (Math Mode) and return the range of
    /// the region's inner content — the wrapped selection, or the `x = y`
    /// placeholder — so the caller can highlight it for immediate typing. Does not
    /// change any toolbar toggle — math is a region, not a block-level style.
    @discardableResult
    public func insertMathMode(in selection: Range<String.Index>?) -> Range<String.Index>? {
        let prefix = "$$"
        let suffix = "$$"
        let placeholder = "x = y"

        // Splice the region in, tracking where its inner content lands as a
        // character offset (indices are recomputed afterward, since mutating the
        // string invalidates the old ones).
        let contentOffset: Int
        let contentLength: Int

        if let selection, !selection.isEmpty {
            let selected = String(text[selection])
            let startOffset = text.distance(from: text.startIndex, to: selection.lowerBound)
            text.replaceSubrange(selection, with: prefix + selected + suffix)
            contentOffset = startOffset + prefix.count
            contentLength = selected.count
        } else if let caret = selection?.lowerBound {
            let caretOffset = text.distance(from: text.startIndex, to: caret)
            text.insert(contentsOf: prefix + placeholder + suffix, at: caret)
            contentOffset = caretOffset + prefix.count
            contentLength = placeholder.count
        } else {
            if let last = text.last, last != "\n", last != " " {
                text.append(" ")
            }
            let baseOffset = text.count
            text.append(prefix + placeholder + suffix)
            contentOffset = baseOffset + prefix.count
            contentLength = placeholder.count
        }

        let start = text.index(text.startIndex, offsetBy: contentOffset)
        let end = text.index(start, offsetBy: contentLength)
        return start..<end
    }

    // MARK: Private

    /// Shared wrap-or-insert routine used by every editing helper.
    private func wrapOrInsert(
        prefix: String,
        suffix: String,
        placeholder: String,
        in selection: Range<String.Index>?
    ) {
        if let selection, !selection.isEmpty {
            // Wrap the selected span.
            let selected = String(text[selection])
            text.replaceSubrange(selection, with: prefix + selected + suffix)
        } else if let caret = selection?.lowerBound {
            // Empty selection = caret position; insert a wrapped placeholder there.
            text.insert(contentsOf: prefix + placeholder + suffix, at: caret)
        } else {
            // No selection info at all; append a wrapped placeholder.
            if let last = text.last, last != "\n", last != " " {
                text.append(" ")
            }
            text.append(prefix + placeholder + suffix)
        }
    }
}
