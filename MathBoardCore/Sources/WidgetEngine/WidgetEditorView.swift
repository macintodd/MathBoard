//
//  WidgetEditorView.swift
//  WidgetEngine
//
//  Standalone authoring surface for MathBoard widgets:
//   1. Copy AI instructions for the native Widget JSON schema.
//   2. Paste/edit Widget JSON.
//   3. Validate and preview with the native SwiftUI renderer.
//   4. Keep HTML/WKWebView as an advanced experimental preview path.
//

import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private enum WidgetNativeJSONValidation {
    case activity(WidgetActivityValidationResult)
    case component(WidgetValidationResult)
    case invalid(activityErrors: [String], componentErrors: [String])

    var isValid: Bool {
        switch self {
        case .activity(let result):
            return result.isValid
        case .component(let result):
            return result.isValid
        case .invalid:
            return false
        }
    }

    var canPlaceOnCanvas: Bool {
        if case .activity(let result) = self {
            return result.isValid
        }
        return false
    }

    var statusText: String {
        switch self {
        case .activity:
            return "Valid Activity"
        case .component:
            return "Valid Component"
        case .invalid:
            return "Needs attention"
        }
    }
}

public struct WidgetEditorInsertion: Sendable, Equatable {
    public var name: String
    public var codeString: String

    public init(name: String, codeString: String) {
        self.name = name
        self.codeString = codeString
    }
}

public struct WidgetEditorView: View {
    private enum EditorMode: String, CaseIterable, Identifiable {
        case nativeJSON = "Widget JSON"
        case advancedHTML = "HTML"

        var id: String { rawValue }
    }

    private let insertButtonTitle: String
    private let onInsertWidget: ((WidgetEditorInsertion) -> Void)?
    private let onCancel: (() -> Void)?

    @State private var editorMode: EditorMode
    @State private var jsonSource: String
    @State private var htmlSource: String = WidgetSamples.advancedHTML
    @State private var didCopyInstructions = false
    @State private var copiedInstructionsTitle = "Copy"
    @State private var themeOverride: WidgetActivityTheme?
    @State private var experienceOverride: WidgetActivityExperience?

    public init(
        initialJSONSource: String? = nil,
        insertButtonTitle: String = "Insert Widget",
        onInsertWidget: ((WidgetEditorInsertion) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.insertButtonTitle = insertButtonTitle
        self.onInsertWidget = onInsertWidget
        self.onCancel = onCancel
        _editorMode = State(initialValue: .nativeJSON)
        _jsonSource = State(initialValue: initialJSONSource ?? WidgetSamples.orderOpsActivityJSON)
    }

    private var validationResult: WidgetNativeJSONValidation {
        let activityResult = WidgetActivityJSONCodec.decode(jsonSource)
        if activityResult.isValid {
            return .activity(activityResult)
        }

        let componentResult = WidgetJSONCodec.decode(jsonSource)
        if componentResult.isValid {
            return .component(componentResult)
        }

        return .invalid(
            activityErrors: activityResult.errors,
            componentErrors: componentResult.errors
        )
    }

    private var activityDocument: ActivityWidgetDocument? {
        if case .activity(let result) = validationResult {
            return result.document
        }
        return nil
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Picker("Widget format", selection: $editorMode) {
                ForEach(EditorMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Divider()

            switch editorMode {
            case .nativeJSON:
                nativeJSONEditor
            case .advancedHTML:
                advancedHTMLEditor
            }
        }
        .padding(20)
        .frame(minWidth: 360, minHeight: 660)
        .background(.background)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label("MathBoard Widget Engine", systemImage: "square.grid.2x2")
                    .font(.title3.weight(.bold))
                Text("Activity JSON is the recommended path. Component JSON and HTML remain available for advanced experiments.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if let onCancel {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
            }

            Menu {
                Button("Activity Prompt") {
                    copyAIInstructions(WidgetSamples.activityAuthoringInstructions, title: "Activity")
                }
                Divider()
                Button("Full Schema Prompt") {
                    copyAIInstructions(WidgetSamples.aiInstructions, title: "Full")
                }
                Button("Logic Pass") {
                    copyAIInstructions(WidgetSamples.logicPassInstructions, title: "Logic")
                }
                Button("Layout Pass") {
                    copyAIInstructions(WidgetSamples.layoutPassInstructions, title: "Layout")
                }
                Button("Interaction Pass") {
                    copyAIInstructions(WidgetSamples.interactionPassInstructions, title: "Interaction")
                }
                Button("Decoration Pass") {
                    copyAIInstructions(WidgetSamples.decorationPassInstructions, title: "Decoration")
                }
            } label: {
                Label(didCopyInstructions ? "Copied \(copiedInstructionsTitle)" : "Copy Prompt",
                      systemImage: didCopyInstructions ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var nativeJSONEditor: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                jsonEditorPane
                nativePreviewPane
            }

            VStack(alignment: .leading, spacing: 16) {
                jsonEditorPane
                    .frame(height: 320)
                nativePreviewPane
                    .frame(height: 420)
            }
        }
    }

    private var advancedHTMLEditor: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                htmlEditorPane
                htmlPreviewPane
            }

            VStack(alignment: .leading, spacing: 16) {
                htmlEditorPane
                    .frame(height: 320)
                htmlPreviewPane
                    .frame(height: 420)
            }
        }
    }

    private var jsonEditorPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetEditorToolbar(
                title: "Widget JSON",
                systemImage: "curlybraces",
                statusText: validationResult.statusText,
                isValid: validationResult.isValid,
                onPaste: { jsonSource = $0 },
                onSelectAll: selectAllJSON,
                resetTitle: "Load Sample"
            ) {
                jsonSource = WidgetSamples.orderOpsActivityJSON
                selectAllJSON()
            }

            WidgetReadOnlyCodeView(source: jsonSource)
        }
    }

    private var nativePreviewPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label("Native Preview", systemImage: "eye")
                    .font(.headline)

                Spacer(minLength: 12)

                if onInsertWidget != nil {
                    Button {
                        insertCurrentWidget()
                    } label: {
                        Label(insertButtonTitle, systemImage: "plus.square.on.square")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!validationResult.canPlaceOnCanvas)
                }
            }
            activityPresentationControls
            WidgetNativeJSONPreview(
                validationResult: validationResult,
                jsonSource: jsonSource,
                themeOverride: themeOverride,
                experienceOverride: experienceOverride
            )
                .id(jsonSource)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                )
        }
    }

    @ViewBuilder
    private var activityPresentationControls: some View {
        if activityDocument != nil {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    themePicker
                    experiencePicker
                }

                VStack(alignment: .leading, spacing: 8) {
                    themePicker
                    experiencePicker
                }
            }
        }
    }

    private var themePicker: some View {
        Picker("Theme", selection: $themeOverride) {
            Text("AI Theme").tag(WidgetActivityTheme?.none)
            ForEach(WidgetActivityTheme.allCases, id: \.self) { theme in
                Text(theme.rawValue).tag(WidgetActivityTheme?.some(theme))
            }
        }
        .pickerStyle(.menu)
    }

    private var experiencePicker: some View {
        Picker("Experience", selection: $experienceOverride) {
            Text("AI Experience").tag(WidgetActivityExperience?.none)
            ForEach(WidgetActivityExperience.allCases, id: \.self) { experience in
                Text(experience.rawValue).tag(WidgetActivityExperience?.some(experience))
            }
        }
        .pickerStyle(.menu)
    }

    private var htmlEditorPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetEditorToolbar(
                title: "Advanced HTML",
                systemImage: "chevron.left.forwardslash.chevron.right",
                statusText: "Experimental",
                isValid: false,
                onPaste: { htmlSource = $0 },
                onSelectAll: nil,
                resetTitle: "Load Sample"
            ) {
                htmlSource = WidgetSamples.advancedHTML
            }

            TextEditor(text: $htmlSource)
                .font(.callout.monospaced())
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                )
        }
    }

    private var htmlPreviewPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("WKWebView Preview", systemImage: "globe")
                .font(.headline)
            WidgetWebView(htmlString: htmlSource)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                )
        }
    }

    private func copyAIInstructions(_ instructions: String, title: String) {
        setClipboard(instructions)
        copiedInstructionsTitle = title
        didCopyInstructions = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            didCopyInstructions = false
            copiedInstructionsTitle = "Copy"
        }
    }

    private func setClipboard(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }

    private func selectAllJSON() {
        setClipboard(jsonSource)
    }

    private func insertCurrentWidget() {
        guard validationResult.canPlaceOnCanvas else { return }
        onInsertWidget?(WidgetEditorInsertion(
            name: widgetName,
            codeString: jsonSource
        ))
    }

    private var widgetName: String {
        if let title = activityDocument?.title.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }
        return "MathBoard Widget"
    }
}

private struct WidgetEditorToolbar: View {
    let title: String
    let systemImage: String
    let statusText: String
    let isValid: Bool
    let onPaste: (String) -> Void
    let onSelectAll: (() -> Void)?
    let resetTitle: String
    let onReset: () -> Void

    var body: some View {
        AnyView(
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: systemImage)
                    Text(title)
                }
                .font(.headline)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: isValid ? "checkmark.circle.fill" : "info.circle")
                    Text(statusText)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(isValid ? .green : .secondary)
                if let onSelectAll {
                    Button {
                        onSelectAll()
                    } label: {
                        Label("Copy All", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                }
                WidgetPasteTextButton(onPaste: onPaste)
                Button(resetTitle, action: onReset)
                    .buttonStyle(.bordered)
            }
        )
    }
}

private struct WidgetNativeJSONPreview: View {
    let validationResult: WidgetNativeJSONValidation
    let jsonSource: String
    var themeOverride: WidgetActivityTheme?
    var experienceOverride: WidgetActivityExperience?

    @State private var didCopyErrorReport = false

    var body: some View {
        switch validationResult {
        case .activity(let result):
            if let document = result.document {
                WidgetActivityRenderer(
                    document: document,
                    themeOverride: themeOverride,
                    experienceOverride: experienceOverride
                )
                    .frame(maxWidth: .infinity)
            } else {
                errorView(title: "Activity JSON is not valid", errors: result.errors)
            }
        case .component(let result):
            if let document = result.document {
                WidgetNativeRenderer(document: document)
                    .frame(
                        width: preferredWidth(for: document),
                        height: preferredHeight(for: document)
                    )
            } else {
                errorView(title: "Component JSON is not valid", errors: result.errors)
            }
        case .invalid(let activityErrors, let componentErrors):
            errorView(
                title: "Widget JSON is not valid",
                errors: ["Activity JSON:"] + activityErrors + ["Component JSON:"] + componentErrors
            )
        }
    }

    private func errorView(title: String, errors: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label(title, systemImage: "exclamationmark.triangle")
                    .font(.headline)
                    .foregroundStyle(.red)

                Spacer()

                Button {
                    copyErrorReport(title: title, errors: errors)
                } label: {
                    Label(didCopyErrorReport ? "Copied" : "Copy Errors", systemImage: didCopyErrorReport ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }

            ForEach(errors, id: \.self) { error in
                Text(error)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.red.opacity(0.05))
    }

    private func copyErrorReport(title: String, errors: [String]) {
        setClipboard(errorReport(title: title, errors: errors))
        didCopyErrorReport = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            didCopyErrorReport = false
        }
    }

    private func errorReport(title: String, errors: [String]) -> String {
        var sections: [String] = [
            "MathBoard widget JSON needs correction.",
            "",
            "Problem:",
            title,
            "",
            "Validation errors:",
            errors.isEmpty ? "- No validation errors were reported." : errors.map { "- \($0)" }.joined(separator: "\n")
        ]

        let questions = questionSummaries(from: jsonSource)
        if !questions.isEmpty {
            sections.append(contentsOf: [
                "",
                "Questions in the widget:",
                questions.joined(separator: "\n")
            ])
        }

        sections.append(contentsOf: [
            "",
            "Please return corrected MathBoard widget JSON only. Do not include Markdown, prose, comments, or a code fence."
        ])

        return sections.joined(separator: "\n")
    }

    private func questionSummaries(from source: String) -> [String] {
        let repairedSource = WidgetJSONRepair.escapingUnescapedLaTeXCommands(in: source)
        guard let data = repairedSource.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let questions = root["questions"] as? [[String: Any]]
        else {
            return []
        }

        return questions.enumerated().map { index, question in
            let fallbackID = "Question \(index + 1)"
            let id = trimmedString(question["id"]) ?? fallbackID
            let prompt = trimmedString(question["prompt"])
            let expression = trimmedString(question["expression"])
            let choices = choiceSummary(from: question["choices"])

            var pieces = ["- \(id)"]
            if let prompt {
                pieces.append("prompt: \(prompt)")
            }
            if let expression {
                pieces.append("expression: \(expression)")
            }
            if !choices.isEmpty {
                pieces.append("choices: \(choices)")
            }
            return pieces.joined(separator: " | ")
        }
    }

    private func choiceSummary(from value: Any?) -> String {
        guard let choices = value as? [[String: Any]] else {
            return ""
        }

        return choices.compactMap { choice in
            guard let label = trimmedString(choice["label"]) else {
                return nil
            }
            let id = trimmedString(choice["id"])
            let isCorrect = choice["isCorrect"] as? Bool ?? false
            let prefix = id.map { "\($0): " } ?? ""
            let suffix = isCorrect ? " [marked correct]" : ""
            return "\(prefix)\(label)\(suffix)"
        }
        .joined(separator: "; ")
    }

    private func trimmedString(_ value: Any?) -> String? {
        guard let string = value as? String else {
            return nil
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func setClipboard(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }

    private func preferredWidth(for document: MathBoardWidgetDocument) -> CGFloat? {
        guard let width = document.presentation?.preferredWidth else { return nil }
        return CGFloat(width)
    }

    private func preferredHeight(for document: MathBoardWidgetDocument) -> CGFloat? {
        guard let height = document.presentation?.preferredHeight else { return nil }
        return CGFloat(height)
    }
}

private struct WidgetPasteTextButton: View {
    let onPaste: (String) -> Void

    var body: some View {
        PasteButton(payloadType: String.self) { strings in
            if let string = strings.first {
                onPaste(string)
            }
        }
    }
}

private struct WidgetReadOnlyCodeView: View {
    let source: String

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(source)
                .font(.callout.monospaced())
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(8)
        }
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }
}

#Preview("Widget Editor") {
    WidgetEditorView()
}
