//
//  TextEditorResult.swift
//  TextEngine
//
//  TextEngine's own result model — the value the editor hands back when the user
//  taps Save. It is deliberately independent of the app's `CanvasTextObject`:
//  a future Coordinator/adaptor will translate a `TextEditorResult` into whatever
//  the canvas needs, so TextEngine never has to know how the canvas works.
//
//  This file has no dependency on MathBoard.app or any other MathBoardCore module.
//

import Foundation
import CoreGraphics

/// Describes how inline formatting is encoded inside `TextEditorResult.sourceText`.
///
/// TextEngine stores formatting as lightweight in-text markup rather than a rich
/// attributed string, so the source stays plain-text portable and a Coordinator
/// can decide how to interpret it. The single convention shipped today:
///
/// - **Bold** — Markdown `**bold**`
/// - **Italic** — Markdown `*italic*`
/// - **Underline** — HTML-style `<u>underline</u>` (underline is not standard Markdown)
/// - **Math** — `$$ ... $$` LaTeX regions
public enum TextMarkupConvention: String, Codable, Sendable, Hashable {
    /// Markdown emphasis + HTML underline + `$$` math delimiters (see type docs).
    case markdownWithHTMLUnderlineAndDollarMath
}

/// A LaTeX region detected inside the source text, delimited by `$$ ... $$`.
///
/// Offsets are stored as **character** offsets into the source string (not
/// `String.Index`, which would not survive being handed to another module), so a
/// Coordinator can map a region back onto the original text deterministically.
public struct DetectedLaTeXRegion: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID

    /// The LaTeX body between the `$$` delimiters, trimmed of surrounding whitespace.
    public let latex: String

    /// The full matched span including both `$$` delimiters.
    public let fullMatch: String

    /// Character offset of the first `$` of the opening delimiter in the source.
    public let startOffset: Int

    /// Number of characters spanned by `fullMatch` (delimiters included).
    public let length: Int

    public init(
        id: UUID = UUID(),
        latex: String,
        fullMatch: String,
        startOffset: Int,
        length: Int
    ) {
        self.id = id
        self.latex = latex
        self.fullMatch = fullMatch
        self.startOffset = startOffset
        self.length = length
    }
}

public extension DetectedLaTeXRegion {
    /// Detects every `$$ ... $$` LaTeX region in `text`, in source order.
    ///
    /// Shared by `TextEditorViewModel` and `LaTeXPreviewView` so detection stays
    /// consistent wherever it is used. Regions whose body is empty after trimming
    /// are skipped (e.g. a stray `$$$$`).
    static func detect(in text: String) -> [DetectedLaTeXRegion] {
        // Opening `$$`, a lazily-captured body (newlines allowed), closing `$$`.
        // Kept local because a `Regex` value is not `Sendable`.
        let regex = /\$\$([\s\S]*?)\$\$/
        return text.matches(of: regex).compactMap { match in
            let body = String(match.output.1).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return nil }
            let range = match.range
            let startOffset = text.distance(from: text.startIndex, to: range.lowerBound)
            let length = text.distance(from: range.lowerBound, to: range.upperBound)
            return DetectedLaTeXRegion(
                latex: body,
                fullMatch: String(text[range]),
                startOffset: startOffset,
                length: length
            )
        }
    }
}

/// The value the editor returns through its Save closure.
///
/// Carries everything a future Coordinator needs to build the app's canvas text
/// object without TextEngine ever importing `CanvasTextObject`.
public struct TextEditorResult: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID

    /// The raw text, including any inline markup (see `markupConvention`).
    public var sourceText: String

    /// Point size the text should render at.
    public var fontSize: CGFloat

    /// Selected font name, or `nil` for the system default. A placeholder choice
    /// today (see `TextEditorViewModel.availableFonts`); a Coordinator maps it to
    /// a concrete `UIFont`/`NSFont` at integration time.
    public var fontName: String?

    /// Block-level formatting intent, mirrored from the editor's toolbar toggles.
    /// Inline spans are additionally encoded in `sourceText` per `markupConvention`.
    public var isBold: Bool
    public var isItalic: Bool
    public var isUnderline: Bool

    /// How inline formatting is encoded inside `sourceText`.
    public var markupConvention: TextMarkupConvention

    /// LaTeX regions detected in `sourceText`, in source order.
    public var detectedLaTeXRegions: [DetectedLaTeXRegion]

    public init(
        id: UUID = UUID(),
        sourceText: String,
        fontSize: CGFloat,
        fontName: String? = nil,
        isBold: Bool = false,
        isItalic: Bool = false,
        isUnderline: Bool = false,
        markupConvention: TextMarkupConvention = .markdownWithHTMLUnderlineAndDollarMath,
        detectedLaTeXRegions: [DetectedLaTeXRegion]
    ) {
        self.id = id
        self.sourceText = sourceText
        self.fontSize = fontSize
        self.fontName = fontName
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderline = isUnderline
        self.markupConvention = markupConvention
        self.detectedLaTeXRegions = detectedLaTeXRegions
    }

    /// `true` when the text contains at least one detected LaTeX region.
    public var containsLaTeX: Bool { !detectedLaTeXRegions.isEmpty }
}
