//
//  LaTeXPreviewView.swift
//  TextEngine
//
//  Offline preview of the `$$ ... $$` LaTeX regions found in a piece of text.
//
//  Rendering strategy:
//   • NO CDN MathJax, NO network access. Xcode Previews must build and render
//     with zero connectivity.
//   • Each detected equation is shown in a small "math card". The actual math is
//     typeset by `EquationRenderer` — the single, isolated seam that wraps the
//     LaTeX renderer (currently SwiftUIMath: native, offline, no WebView).
//   • Everything else in TextEngine talks to `EquationRenderer`, never to the
//     renderer directly, so it can be swapped later if SwiftUIMath doesn't cover
//     enough LaTeX for classroom use — without touching this view's public API.
//

import SwiftUI
// `Textual` SPI exposes `Math.typographicBounds`, the only public hook for
// detecting whether SwiftUIMath can actually parse/typeset a string (its `Math`
// view silently draws nothing for invalid LaTeX). Used to fall back to raw text.
@_spi(Textual) import SwiftUIMath

/// Renders the LaTeX regions detected inside `source`, offline.
public struct LaTeXPreviewView: View {
    /// The text to scan for `$$ ... $$` regions.
    private let source: String

    public init(source: String) {
        self.source = source
    }

    /// Detected regions, recomputed when `source` changes.
    private var regions: [DetectedLaTeXRegion] {
        DetectedLaTeXRegion.detect(in: source)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if regions.isEmpty {
                emptyState
            } else {
                // Each equation gets its own small, self-contained card. They lay
                // out in a horizontal row that scrolls, so every card stays fully
                // visible no matter how many equations are detected.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Array(regions.enumerated()), id: \.element.id) { index, region in
                            MathCard(index: index + 1, latex: region.latex)
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "function")
            Text("LaTeX Preview")
                .font(.headline)
            Spacer()
            if !regions.isEmpty {
                Text("^[\(regions.count) equation](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyState: some View {
        Text("No math detected. Wrap an equation in $$ … $$ to preview it here.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }
}

// MARK: - Math card

/// The single, isolated seam that turns a LaTeX string into a rendered view.
///
/// Backed by SwiftUIMath today (native, offline, no WebView). To swap renderers
/// later, change only this view's body — nothing else in TextEngine references
/// the underlying library.
private struct EquationRenderer: View {
    let latex: String

    private let mathFont = Math.Font(name: .latinModern, size: 22)

    /// SwiftUIMath draws nothing for LaTeX it can't parse. Measure first: a zero
    /// width means it won't typeset, so we show the raw source instead of a blank.
    private var canTypeset: Bool {
        let bounds = Math.typographicBounds(
            for: latex,
            fitting: ProposedViewSize(width: 100_000, height: 100_000),
            font: mathFont,
            style: .display
        )
        return bounds.size.width > 0
    }

    var body: some View {
        if canTypeset {
            Math(latex)
                .mathTypesettingStyle(.display)
                .mathFont(mathFont)
        } else {
            rawFallback
        }
    }

    /// Shown when SwiftUIMath can't render the expression — the raw LaTeX plus a
    /// small marker, so a malformed equation never renders as an empty card.
    private var rawFallback: some View {
        VStack(spacing: 4) {
            Label("Can't render", systemImage: "exclamationmark.triangle")
                .labelStyle(.iconOnly)
                .font(.caption)
                .foregroundStyle(.orange)
            Text(latex)
                .font(.system(.callout, design: .monospaced))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
                .foregroundStyle(.secondary)
        }
    }
}

/// A single, compact equation card. Its rendered math comes from
/// `EquationRenderer`; the card only owns the chrome (tag, divider, source line).
private struct MathCard: View {
    /// 1-based position, shown as a small "EQ n" tag in the card header.
    let index: Int
    let latex: String

    /// Fixed width keeps every card the same compact size in the scrolling row.
    private let cardWidth: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EQ \(index)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            content

            Divider()

            Text(latex)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .frame(width: cardWidth, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1)
        )
    }

    /// The typeset equation, centered so the card reads like a math block.
    private var content: some View {
        EquationRenderer(latex: latex)
            .frame(maxWidth: .infinity, minHeight: 40)
    }
}

// MARK: - Previews

#Preview("With equation") {
    LaTeXPreviewView(source: "Area: $$A = \\pi r^2$$")
        .padding()
}

#Preview("Multiple equations") {
    LaTeXPreviewView(source: """
    Pythagoras: $$a^2 + b^2 = c^2$$, the quadratic roots
    $$x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}$$, area $$A = \\pi r^2$$
    and circumference $$C = 2 \\pi r$$.
    """)
    .padding()
}

#Preview("No math") {
    LaTeXPreviewView(source: "Just some plain text with no equations.")
        .padding()
}

#Preview("Invalid LaTeX falls back to raw") {
    // The second region is malformed (unclosed brace) — SwiftUIMath can't render
    // it, so the card shows the raw source instead of a blank.
    LaTeXPreviewView(source: "Good: $$A = \\pi r^2$$ and bad: $$\\frac{1}{$$")
        .padding()
}
