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

    private enum PromptMode {
        case create
        case remix
    }

    private enum ActivityStarter: String, CaseIterable, Identifiable {
        case multipleChoice
        case fillInTheBlank

        var id: String { rawValue }

        var title: String {
            switch self {
            case .multipleChoice:
                return "Multiple Choice"
            case .fillInTheBlank:
                return "Fill in the Blank"
            }
        }

        var systemImage: String {
            switch self {
            case .multipleChoice:
                return "checklist"
            case .fillInTheBlank:
                return "rectangle.and.pencil.and.ellipsis"
            }
        }

        var activityKind: WidgetObjectActivityKind {
            switch self {
            case .multipleChoice:
                return .multipleChoice
            case .fillInTheBlank:
                return .fillInTheBlank
            }
        }

        var starterJSON: String {
            WidgetMathtivityPromptFactory.starterJSON(for: activityKind)
        }

        static func starter(for source: String) -> ActivityStarter {
            guard let document = WidgetActivityJSONCodec.decode(source).document else {
                return .multipleChoice
            }

            switch document.activity {
            case .multipleChoice:
                return .multipleChoice
            case .fillInTheBlank:
                return .fillInTheBlank
            }
        }
    }

    private let insertButtonTitle: String
    private let onInsertWidget: ((WidgetEditorInsertion) -> Void)?
    private let onCancel: (() -> Void)?

    @State private var editorMode: EditorMode
    @State private var jsonSource: String
    @State private var htmlSource: String = WidgetSamples.advancedHTML
    @State private var didCopyInstructions = false
    @State private var copiedInstructionsTitle = "Copy"
    @State private var didPasteWidgetCode = false
    @State private var didCopyErrorReport = false
    @State private var selectedActivityStarter: ActivityStarter
    @State private var promptMode: PromptMode

    public init(
        initialJSONSource: String? = nil,
        insertButtonTitle: String = "Insert Widget",
        onInsertWidget: ((WidgetEditorInsertion) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.insertButtonTitle = insertButtonTitle
        self.onInsertWidget = onInsertWidget
        self.onCancel = onCancel
        let startingSource = initialJSONSource ?? WidgetSamples.orderOpsActivityJSON
        _editorMode = State(initialValue: .nativeJSON)
        _jsonSource = State(initialValue: startingSource)
        _selectedActivityStarter = State(initialValue: ActivityStarter.starter(for: startingSource))
        _promptMode = State(initialValue: initialJSONSource == nil ? .create : .remix)
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

            Divider()

            nativeJSONEditor
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
                Text("Use AI-generated widget code to build interactive MathBoard activities.")
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

        }
    }

    private var nativeJSONEditor: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                widgetWorkflowPane
                nativePreviewPane
            }

            VStack(alignment: .leading, spacing: 16) {
                widgetWorkflowPane
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
                onPaste: { pastedSource in
                    jsonSource = pastedSource
                    selectedActivityStarter = ActivityStarter.starter(for: pastedSource)
                    promptMode = .remix
                },
                onSelectAll: selectAllJSON,
                resetTitle: "First Move"
            ) {
                loadJSONSample(WidgetSamples.orderOpsActivityJSON)
            }

            activityTypeChooser

            Menu {
                Button("First Move") {
                    loadJSONSample(WidgetSamples.orderOpsActivityJSON)
                }
                Button("Vertex or Roots?") {
                    loadJSONSample(WidgetSamples.quadraticFormActivityJSON)
                }
                Divider()
                ForEach(JSONMathtivityCatalog.bundledEntries) { entry in
                    Button("\(entry.title) (\(entry.topic))") {
                        if let source = JSONMathtivityCatalog.source(for: entry) {
                            loadJSONSample(source)
                        }
                    }
                }
            } label: {
                Label("More Samples", systemImage: "square.grid.2x2")
            }
            .buttonStyle(.bordered)

            WidgetReadOnlyCodeView(source: jsonSource)
        }
    }

    private var activityTypeChooser: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Activity Type")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    activityTypeButtons
                }

                VStack(alignment: .leading, spacing: 8) {
                    activityTypeButtons
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("JSON Mathtivity Activity Type")
    }

    private var activityTypeButtons: some View {
        ForEach(ActivityStarter.allCases) { starter in
            activityTypeButton(for: starter)
        }
    }

    @ViewBuilder
    private func activityTypeButton(for starter: ActivityStarter) -> some View {
        if selectedActivityStarter == starter {
            Button {
                selectActivityStarter(starter)
            } label: {
                Label(starter.title, systemImage: starter.systemImage)
                    .lineLimit(1)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button {
                selectActivityStarter(starter)
            } label: {
                Label(starter.title, systemImage: starter.systemImage)
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
        }
    }

    private var widgetWorkflowPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Label("MathBoard Widget Engine", systemImage: "square.grid.2x2")
                    .font(.headline)
                Text("The widget engine is where you can enter code generated by the AI of your choice to generate your own widgets. Follow the steps to render your widget:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            activityTypeChooser

            VStack(alignment: .leading, spacing: 12) {
                workflowStep(number: 1, text: "Choose a JSON activity structure, then copy its AI prompt.") {
                    Button {
                        copyCurrentMathtivityPrompt()
                    } label: {
                        Label(promptButtonTitle, systemImage: didCopyInstructions ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                }

                workflowStep(number: 2, text: "Paste the prompt into an AI chatbot and describe what skill, topic, or edits you want.")
                workflowStep(number: 3, text: "Copy the generated code.")

                workflowStep(number: 4, text: "Press Paste to load the generated code.") {
                    HStack(spacing: 8) {
                        WidgetPasteTextButton { pastedSource in
                            jsonSource = pastedSource
                            selectedActivityStarter = ActivityStarter.starter(for: pastedSource)
                            promptMode = .remix
                            didPasteWidgetCode = true
                        }
                        if didPasteWidgetCode {
                            Label("Code received", systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(validationResult.isValid ? .green : .orange)
                        }
                    }
                }

                workflowStep(number: 5, text: validationResult.isValid ? "No errors found. Press Insert Widget." : "If the code has errors, press Copy Errors.") {
                    if validationResult.isValid {
                        Label("Ready", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    } else {
                        Button {
                            copyCurrentErrorReport()
                        } label: {
                            Label(didCopyErrorReport ? "Copied Errors" : "Copy Errors", systemImage: didCopyErrorReport ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                workflowStep(number: 6, text: "If there were errors, paste the copied errors back into the AI, then paste the corrected code here.")
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(minWidth: 300, maxWidth: 420, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
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
            WidgetNativeJSONPreview(
                validationResult: validationResult,
                jsonSource: jsonSource
            )
                .id(jsonSource)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                )
        }
    }

    private func workflowStep<Accessory: View>(
        number: Int,
        text: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.blue, in: Circle())

            VStack(alignment: .leading, spacing: 8) {
                Text(text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                accessory()
            }
        }
    }

    private func workflowStep(number: Int, text: String) -> some View {
        workflowStep(number: number, text: text) {
            EmptyView()
        }
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

    private var promptButtonTitle: String {
        if didCopyInstructions {
            return "Copied Prompt"
        }

        switch promptMode {
        case .create:
            return "Copy \(selectedActivityStarter.title) Prompt"
        case .remix:
            return "Copy Remix Prompt"
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

    private func copyCurrentErrorReport() {
        setClipboard(currentErrorReport())
        didCopyErrorReport = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            didCopyErrorReport = false
        }
    }

    private func copyCurrentMathtivityPrompt() {
        copyAIInstructions(currentMathtivityPrompt(), title: "Prompt")
    }

    private func currentMathtivityPrompt() -> String {
        let intent: WidgetMathtivityPromptIntent
        switch promptMode {
        case .create:
            intent = .create
        case .remix:
            intent = .remix(sourceJSON: jsonSource)
        }

        return WidgetMathtivityPromptFactory.prompt(
            for: currentPromptActivityKind,
            intent: intent
        )
    }

    private var currentPromptActivityKind: WidgetObjectActivityKind {
        if let document = activityDocument {
            switch document.activity {
            case .multipleChoice:
                return .multipleChoice
            case .fillInTheBlank:
                return .fillInTheBlank
            }
        }

        return selectedActivityStarter.activityKind
    }

    private func currentErrorReport() -> String {
        let errors: [String]
        switch validationResult {
        case .activity(let result):
            errors = result.errors
        case .component(let result):
            errors = result.errors
        case .invalid(let activityErrors, let componentErrors):
            errors = ["Activity JSON:"] + activityErrors + ["Component JSON:"] + componentErrors
        }

        var sections: [String] = [
            "MathBoard widget JSON needs correction.",
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

    private func insertCurrentWidget() {
        guard validationResult.canPlaceOnCanvas else { return }
        onInsertWidget?(WidgetEditorInsertion(
            name: widgetName,
            codeString: jsonSource
        ))
    }

    private func selectActivityStarter(_ starter: ActivityStarter) {
        selectedActivityStarter = starter
        jsonSource = starter.starterJSON
        promptMode = .create
    }

    private func loadJSONSample(_ source: String) {
        jsonSource = source
        selectedActivityStarter = ActivityStarter.starter(for: source)
        promptMode = .remix
        selectAllJSON()
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

    @State private var didCopyErrorReport = false

    var body: some View {
        switch validationResult {
        case .activity(let result):
            if let document = result.document {
                WidgetActivityRenderer(document: document)
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
