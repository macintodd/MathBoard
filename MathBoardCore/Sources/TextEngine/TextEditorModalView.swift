//
//  TextEditorModalView.swift
//  TextEngine
//
//  A large, word-processor-style modal text editor. Standalone and previewable:
//  it owns a `TextEditorViewModel`, edits plain text formatting, and returns a
//  `TextEditorResult` through its Save closure. Nothing here touches the app's
//  canvas or text objects.
//

import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

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
    @State private var keyboardHeight: CGFloat = 0

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
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                topBar
                Divider()
                formattingToolbar
                Divider()
                editorPane
                    .padding(.bottom, bottomActionBarReservedHeight)
            }

            bottomActionBar
                .padding(.bottom, keyboardHeight)
        }
        .frame(minWidth: 560, minHeight: 640)
        .background(.background)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            updateKeyboardHeight(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.22)) {
                keyboardHeight = 0
            }
        }
        #endif
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Spacer()

            Text("Text Editor")
                .font(.headline)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var bottomActionBar: some View {
        HStack(spacing: 10) {
            Spacer()

            Button("Save") { onSave(viewModel.result) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)

            Button("Cancel", role: .cancel) { onCancel() }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var bottomActionBarReservedHeight: CGFloat {
        58
    }

    #if os(iOS)
    private func updateKeyboardHeight(from notification: Notification) {
        guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }
        let height = max(0, endFrame.height)
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.22
        withAnimation(.easeOut(duration: duration)) {
            keyboardHeight = height
        }
    }
    #endif

    // MARK: Editor

    private var editorPane: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $viewModel.text, selection: $selection)
                .font(editorFont)
                .foregroundStyle(viewModel.textColor.swiftUIColor)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(editorBackgroundColor)
                )
                .focused($editorFocused)

            if viewModel.text.isEmpty {
                Text("Start typing... use the toolbar for formatting.")
                    .font(editorFont)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 17)
                    .padding(.vertical, 20)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(editorBackgroundColor)
    }

    private var editorBackgroundColor: Color {
        (viewModel.backgroundColor ?? TextEditorColor(red: 1, green: 1, blue: 1, alpha: 0)).swiftUIColor
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

            Divider().frame(height: 24)

            colorControls

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

    private var colorControls: some View {
        HStack(spacing: 8) {
            ColorPicker(
                "Text Color",
                selection: textColorBinding,
                supportsOpacity: true
            )
            .labelsHidden()
            .frame(width: 34)
            .help("Text Color")

            Button {
                viewModel.backgroundColor = viewModel.backgroundColor == nil ? .yellowHighlight : nil
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill((viewModel.backgroundColor ?? .yellowHighlight).swiftUIColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                        )
                    Image(systemName: viewModel.backgroundColor == nil ? "square.dashed" : "textformat.alt")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(viewModel.backgroundColor == nil ? .secondary : .primary)
                }
                .frame(width: 30, height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.backgroundColor == nil ? "Enable text background" : "Remove text background")
            .help(viewModel.backgroundColor == nil ? "Enable Text Background" : "Remove Text Background")

            ColorPicker(
                "Background Color",
                selection: backgroundColorBinding,
                supportsOpacity: true
            )
            .labelsHidden()
            .frame(width: 34)
            .help("Background Color")
        }
    }

    private var textColorBinding: Binding<Color> {
        Binding {
            viewModel.textColor.swiftUIColor
        } set: { color in
            viewModel.textColor = TextEditorColor(color)
        }
    }

    private var backgroundColorBinding: Binding<Color> {
        Binding {
            (viewModel.backgroundColor ?? .yellowHighlight).swiftUIColor
        } set: { color in
            viewModel.backgroundColor = TextEditorColor(color)
        }
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
        var font = Self.font(for: viewModel.fontName, size: viewModel.fontSize)
        if viewModel.isBold { font = font.bold() }
        if viewModel.isItalic { font = font.italic() }
        return font
    }

    private static func font(for name: String, size: CGFloat) -> Font {
        switch name {
        case "Serif":
            return .system(size: size, design: .serif)
        case "Rounded":
            return .system(size: size, design: .rounded)
        case "Monospaced":
            return .system(size: size, design: .monospaced)
        case "Avenir Next":
            return .custom("AvenirNext-Regular", size: size)
        case "Futura":
            return .custom("Futura-Medium", size: size)
        case "Helvetica Neue":
            return .custom("HelveticaNeue", size: size)
        case "Georgia":
            return .custom("Georgia", size: size)
        case "Chalkboard SE":
            return .custom("ChalkboardSE-Regular", size: size)
        case "Marker Felt":
            return .custom("MarkerFelt-Thin", size: size)
        default:
            return .system(size: size)
        }
    }
}

private extension TextEditorColor {
    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    init(_ color: Color) {
        #if os(iOS)
        let platformColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        platformColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.init(red: red, green: green, blue: blue, alpha: alpha)
        #elseif os(macOS)
        let platformColor = NSColor(color).usingColorSpace(.deviceRGB) ?? .black
        self.init(
            red: platformColor.redComponent,
            green: platformColor.greenComponent,
            blue: platformColor.blueComponent,
            alpha: platformColor.alphaComponent
        )
        #else
        self.init(red: 0, green: 0, blue: 0, alpha: 1)
        #endif
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
