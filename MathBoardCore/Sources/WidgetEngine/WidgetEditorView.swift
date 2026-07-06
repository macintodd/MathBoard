//
//  WidgetEditorView.swift
//  WidgetEngine
//
//  Authoring surface for the Widget Engine prototype:
//   1. A read-only "boilerplate prompt" the user copies into their AI assistant.
//   2. A "Copy Template" button.
//   3. An editable field where the user pastes the AI-generated HTML/JS.
//   4. A live WKWebView preview that re-renders as the code changes.
//
//  Fully self-contained and previewable in Xcode with no app dependencies.
//

import SwiftUI

struct WidgetEditorView: View {
    /// The prompt the user copies out to their AI assistant. Read-only.
    private let boilerplatePrompt = WidgetSampleCode.boilerplatePrompt

    /// The AI-generated HTML/JS the user pastes in. Drives the live preview.
    @State private var codeString: String = WidgetSampleCode.counter

    /// Brief confirmation shown after copying the template.
    @State private var didCopyTemplate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            promptSection
            Divider()
            editorAndPreview
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 620)
        .background(.background)
    }

    // MARK: Boilerplate prompt + copy button

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Boilerplate Prompt", systemImage: "text.quote")
                .font(.headline)

            Text("Copy the following text to your AI to generate a widget:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextEditor(text: .constant(boilerplatePrompt))
                .font(.callout.monospaced())
            #imageLiteral(resourceName: "Screenshot 2026-07-04 at 6.40.31 AM.png")
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 96)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                )
                // Read-only: the field is display-only, editing is disabled.
                .disabled(true)

            Button {
                copyTemplate()
            } label: {
                Label(didCopyTemplate ? "Copied!" : "Copy Template",
                      systemImage: didCopyTemplate ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: Code editor + live preview

    private var editorAndPreview: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Widget Code (HTML / JS)", systemImage: "chevron.left.forwardslash.chevron.right")
                    .font(.headline)
                TextEditor(text: $codeString)
                    .font(.callout.monospaced())
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("Live Preview", systemImage: "eye")
                    .font(.headline)
                WidgetWebView(htmlString: codeString)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                    )
            }
        }
    }

    // MARK: Actions

    private func copyTemplate() {
        setClipboard(boilerplatePrompt)
        didCopyTemplate = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            didCopyTemplate = false
        }
    }

    /// Cross-platform clipboard write.
    private func setClipboard(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Preview

#Preview("Widget Editor") {
    WidgetEditorView()
}
