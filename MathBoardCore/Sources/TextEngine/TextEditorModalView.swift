//
//  TextEditorModalView.swift
//  TextEngine
//
//  A large, word-processor-style modal text editor. Standalone and previewable:
//  it owns a `TextEditorViewModel`, edits text with inline markup, previews any
//  `$$ ... $$` LaTeX live, and returns a `TextEditorResult` through its Save
//  closure. Nothing here touches the app's canvas or text objects.
//

import SwiftUI

public struct TextEditorModalView: View {

    /// Called with the finished result when the user taps Save.
    private let onSave: (TextEditorResult) -> Void

    /// Called when the user taps Cancel (nothing is returned).
    private let onCancel: () -> Void

    /// Observable editor state. Owned by the view so the modal is self-contained.
    @State private var viewModel: TextEditorViewModel

    /// Live selection from the `TextEditor`, translated into a `String.Index`
    /// range for the view model's editing helpers.
    @State private var selection: TextSelection?

    @FocusState private var editorFocused: Bool

    /// - Parameters:
    ///   - viewModel: Optional pre-seeded state (defaults to an empty document).
    ///   - onSave: Receives the `TextEditorResult` when Save is tapped.
    ///   - onCancel: Invoked when Cancel is tapped. Defaults to a no-op.
    public init(
        viewModel: TextEditorViewModel = TextEditorViewModel(),
        onSave: @escaping (TextEditorResult) -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            formattingToolbar
            Divider()
            editorPane
            Divider()
            previewPane
        }
        .frame(minWidth: 560, minHeight: 640)
        .background(.background)
    }

    // MARK: Top bar (Cancel / title / Save)

    private var topBar: some View {
        HStack {
            Button("Cancel", role: .cancel) { onCancel() }
                .keyboardShortcut(.cancelAction)

            Spacer()

            Text("Text Editor")
                .font(.headline)

            Spacer()

            Button("Save") { onSave(viewModel.result) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Editor

    private var editorPane: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $viewModel.text, selection: $selection)
                .font(editorFont)
                .scrollContentBackground(.hidden)
                .padding(12)
                .focused($editorFocused)

            if viewModel.text.isEmpty {
                Text("Start typing… use the toolbar for formatting, or wrap math in $$ … $$.")
                    .font(editorFont)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 17)
                    .padding(.vertical, 20)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Live LaTeX preview

    private var previewPane: some View {
        LaTeXPreviewView(source: viewModel.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.03))
    }

    // MARK: Formatting toolbar

    private var formattingToolbar: some View {
        HStack(spacing: 8) {
            toggleButton(
                systemImage: "bold",
                label: "Bold",
                isOn: viewModel.isBold
            ) {
                viewModel.toggleBold(in: currentRange)
                resetSelection()
            }

            toggleButton(
                systemImage: "italic",
                label: "Italic",
                isOn: viewModel.isItalic
            ) {
                viewModel.toggleItalic(in: currentRange)
                resetSelection()
            }

            toggleButton(
                systemImage: "underline",
                label: "Underline",
                isOn: viewModel.isUnderline
            ) {
                viewModel.toggleUnderline(in: currentRange)
                resetSelection()
            }

            Divider().frame(height: 24)

            fontMenu

            Button {
                viewModel.insertMathMode(in: currentRange)
                resetSelection()
            } label: {
                Label("Math", systemImage: "function")
            }
            .buttonStyle(.bordered)

            Divider().frame(height: 24)

            presetSizes

            Spacer(minLength: 12)

            sizeControl
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    /// Quick font-size presets. Tapping one sets `fontSize`, which also moves the
    /// slider (both are bound to the same value).
    private var presetSizes: some View {
        HStack(spacing: 4) {
            ForEach(TextEditorViewModel.presetFontSizes, id: \.self) { size in
                Button {
                    viewModel.fontSize = size
                } label: {
                    Text("\(Int(size))")
                        .font(.caption.monospacedDigit())
                        .frame(minWidth: 26, minHeight: 26)
                }
                .buttonStyle(.bordered)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(viewModel.fontSize == size ? Color.accentColor.opacity(0.22) : .clear)
                )
                .accessibilityLabel("Font size \(Int(size))")
            }
        }
    }

    /// Compact size control: a short slider plus the current point size.
    private var sizeControl: some View {
        HStack(spacing: 8) {
            Image(systemName: "textformat.size")
                .foregroundStyle(.secondary)
            Slider(
                value: $viewModel.fontSize,
                in: TextEditorViewModel.minimumFontSize...TextEditorViewModel.maximumFontSize
            )
            .frame(width: 150)
            Text("\(Int(viewModel.fontSize)) pt")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .trailing)
        }
    }

    private var fontMenu: some View {
        Menu {
            Picker("Font", selection: $viewModel.fontName) {
                ForEach(TextEditorViewModel.availableFonts, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
        } label: {
            Label(viewModel.fontName, systemImage: "textformat")
                .frame(maxWidth: 140, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: Toolbar button builder

    private func toggleButton(
        systemImage: String,
        label: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 30, height: 26)
        }
        .buttonStyle(.bordered)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isOn ? Color.accentColor.opacity(0.22) : .clear)
        )
        .accessibilityLabel(label)
        .help(label)
    }

    // MARK: Selection helpers

    /// The current single-selection range over `viewModel.text`, if any. A caret
    /// (empty selection) is returned as an empty range so helpers can insert at it.
    private var currentRange: Range<String.Index>? {
        guard let selection else { return nil }
        switch selection.indices {
        case .selection(let range):
            return range
        case .multiSelection(let set):
            return set.ranges.first
        @unknown default:
            return nil
        }
    }

    /// After an edit the previous selection indices are invalid, so clear them.
    private func resetSelection() {
        selection = nil
    }

    // MARK: Font resolution

    /// Resolves the placeholder font name + size + toggles into a SwiftUI `Font`.
    /// (Underline is not applied here — the plain `TextEditor` shows raw `<u>…</u>`
    /// markup; visual underline arrives with the real renderer at integration.)
    private var editorFont: Font {
        let design: Font.Design = switch viewModel.fontName {
        case "Serif": .serif
        case "Monospaced": .monospaced
        case "Rounded": .rounded
        default: .default
        }
        var font = Font.system(size: viewModel.fontSize, design: design)
        if viewModel.isBold { font = font.bold() }
        if viewModel.isItalic { font = font.italic() }
        return font
    }
}

// MARK: - Previews

#Preview("Empty editor", traits: .landscapeLeft) {
    TextEditorModalView { result in
        print("Saved: \(result.sourceText)")
    }
}

#Preview("Seeded with math", traits: .landscapeLeft) {
    TextEditorModalView(
        viewModel: TextEditorViewModel(
            text: """
            The area of a circle is $$A = \\pi r^2$$ and its **circumference** \
            is $$C = 2 \\pi r$$.
            """,
            fontSize: 28
        )
    ) { result in
        print("Saved \(result.detectedLaTeXRegions.count) equations")
    }
}

// Demonstrates the intended integration look: the editor presented as a rounded,
// centered floating "window" with the host app dimmed behind it. The actual
// scrim + framing is the host's responsibility (a Coordinator/sheet at
// integration time) — the modal itself just fills whatever frame it is given.
#Preview("As a floating window", traits: .landscapeLeft) {
    ZStack {
        // Stand-in for the MathBoard canvas sitting behind the editor.
        LinearGradient(
            colors: [Color(white: 0.98), Color(white: 0.88)],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(
            Text("MathBoard canvas")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(.quaternary)
        )
        .ignoresSafeArea()

        // The app "fades out" behind the editor via a dimming scrim.
        Color.black.opacity(0.35).ignoresSafeArea()

        TextEditorModalView(
            viewModel: TextEditorViewModel(
                text: "Enter text here $$A = \\pi r^2$$ more text. $$C = 2 \\pi r$$",
                fontSize: 28
            )
        ) { _ in }
        .frame(maxWidth: 900, maxHeight: 620)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(radius: 30, y: 10)
        .padding(40)
    }
}
