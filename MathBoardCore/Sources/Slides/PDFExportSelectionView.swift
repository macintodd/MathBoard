//
//  PDFExportSelectionView.swift
//  MathBoardCore - Slides module
//

import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ExportedPDFDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }

    let data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private enum ExportAction {
    case share
    case save

    var progressTitle: String {
        switch self {
        case .share:
            return "Preparing Share..."
        case .save:
            return "Preparing Save..."
        }
    }

    var overlayTitle: String {
        switch self {
        case .share:
            return "Creating PDF..."
        case .save:
            return "Preparing Save..."
        }
    }
}

struct PDFExportSelectionView: View {
    let slides: [SlideMetadata]
    let initialIndex: Int
    let onCancel: () -> Void
    let onExport: ([Int]) async throws -> URL

    @State private var selectedIndices: Set<Int>
    @State private var exportedPDFURL: URL?
    @State private var exportedPDFIndices: [Int]?
    @State private var exportedPDFDocument = ExportedPDFDocument()
    @State private var isShowingFileExporter = false
    @State private var isShowingSharePresenter = false
    @State private var isShowingPreparationOverlay = false
    @State private var exportAction: ExportAction?
    @State private var isExporting = false
    @State private var exportErrorMessage: String?

    init(
        slides: [SlideMetadata],
        initialIndex: Int,
        onCancel: @escaping () -> Void,
        onExport: @escaping ([Int]) async throws -> URL
    ) {
        self.slides = slides
        self.initialIndex = initialIndex
        self.onCancel = onCancel
        self.onExport = onExport
        _selectedIndices = State(initialValue: [initialIndex])
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Presets")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        presetButton("Current") {
                            selectedIndices = [initialIndex]
                            resetGeneratedExport()
                        }

                        presetButton("PDF Slides") {
                            selectedIndices = Set(pdfBackedIndices)
                            resetGeneratedExport()
                        }
                        .disabled(pdfBackedIndices.isEmpty)

                        presetButton("All") {
                            selectedIndices = Set(slides.indices)
                            resetGeneratedExport()
                        }

                        presetButton("None") {
                            selectedIndices = []
                            resetGeneratedExport()
                        }
                    }
                }
                .padding()

                List(slides.indices, id: \.self) { index in
                    Button {
                        toggle(index)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selectedIndices.contains(index) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedIndices.contains(index) ? .blue : .secondary)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Slide \(index + 1)")
                                    .font(.headline)

                                Text(slideDescription(slides[index]))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Button {
                            exportSelectedSlides(for: .share)
                        } label: {
                            Label("Share PDF", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedIndices.isEmpty || isExporting)

                        Button {
                            exportSelectedSlides(for: .save)
                        } label: {
                            Label("Save PDF...", systemImage: "folder.badge.plus")
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                        }
                        .buttonStyle(.bordered)
                        .disabled(selectedIndices.isEmpty || isExporting)
                    }

                    HStack(spacing: 8) {
                        ProgressView()
                        Text(exportAction?.progressTitle ?? "Preparing PDF...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .opacity(isExporting ? 1 : 0)
                    .frame(height: 20)

                    if let exportErrorMessage {
                        Text(exportErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .navigationTitle("Export PDF")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }

                ToolbarItemGroup(placement: .secondaryAction) {
                    Text("\(selectedIndices.count) selected")
                        .foregroundStyle(.secondary)
                }

            }
        }
        .frame(minWidth: 360, minHeight: 420)
        .fileExporter(
            isPresented: $isShowingFileExporter,
            document: exportedPDFDocument,
            contentType: .pdf,
            defaultFilename: defaultExportFileName
        ) { result in
            switch result {
            case .success:
                onCancel()
            case .failure(let error):
                exportErrorMessage = error.localizedDescription
            }
        }
        .task(id: selectedIndices) {
            await prepareExportCache()
        }
        .overlay {
            if isShowingPreparationOverlay {
                CreatingPDFOverlay(title: exportAction?.overlayTitle ?? "Creating PDF...")
                    .transition(.opacity)
            }
        }
        .overlay {
            if let exportedPDFURL, isShowingSharePresenter {
                PDFSharePresenter(
                    isPresented: $isShowingSharePresenter,
                    url: exportedPDFURL,
                    onPresented: {
                        isShowingPreparationOverlay = false
                    },
                    onComplete: onCancel,
                    onFailure: { error in
                        isShowingPreparationOverlay = false
                        exportAction = nil
                        exportErrorMessage = error.localizedDescription
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }
        }
    }

    private var pdfBackedIndices: [Int] {
        slides.indices.filter { slides[$0].background != nil }
    }

    private var defaultExportFileName: String {
        selectedIndices.count == 1
            ? "MathBoard Slide \(selectedIndices.sorted().first.map { $0 + 1 } ?? initialIndex + 1)"
            : "MathBoard Slides"
    }

    private func toggle(_ index: Int) {
        if selectedIndices.contains(index) {
            selectedIndices.remove(index)
        } else {
            selectedIndices.insert(index)
        }
        resetGeneratedExport()
    }

    private func slideDescription(_ slide: SlideMetadata) -> String {
        if let background = slide.background {
            switch background.kind {
            case .pdfPage:
                return "PDF page \(background.pageIndex + 1)"
            }
        }

        return "Whiteboard slide"
    }

    private func exportSelectedSlides(for action: ExportAction) {
        let indices = selectedIndices.sorted()
        exportAction = action
        exportErrorMessage = nil
        isShowingPreparationOverlay = true

        if let exportedPDFURL, exportedPDFIndices == indices {
            Task { @MainActor in
                await Task.yield()
                perform(action, with: exportedPDFURL)
            }
            return
        }

        isExporting = true
        exportedPDFURL = nil
        exportedPDFIndices = nil

        Task {
            await Task.yield()
            do {
                let url = try await onExport(indices)
                await MainActor.run {
                    exportedPDFURL = url
                    exportedPDFIndices = indices
                    isExporting = false
                    perform(action, with: url)
                }
            } catch {
                await MainActor.run {
                    exportErrorMessage = error.localizedDescription
                    isExporting = false
                    isShowingPreparationOverlay = false
                    exportAction = nil
                }
            }
        }
    }

    private func prepareExportCache() async {
        let indices = selectedIndices.sorted()
        guard !indices.isEmpty else {
            await MainActor.run {
                exportedPDFURL = nil
                exportedPDFIndices = nil
            }
            return
        }

        if exportedPDFURL != nil, exportedPDFIndices == indices {
            return
        }

        do {
            let url = try await onExport(indices)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard selectedIndices.sorted() == indices, !isExporting else { return }
                exportedPDFURL = url
                exportedPDFIndices = indices
            }
        } catch {
            guard !Task.isCancelled else { return }
        }
    }

    private func perform(_ action: ExportAction, with url: URL) {
        switch action {
        case .share:
            isShowingSharePresenter = true
        case .save:
            prepareSaveDocument(from: url)
        }
    }

    private func prepareSaveDocument(from url: URL) {
        do {
            exportedPDFDocument = ExportedPDFDocument(data: try Data(contentsOf: url))
            exportErrorMessage = nil
            isShowingFileExporter = true
            isShowingPreparationOverlay = false
        } catch {
            isShowingPreparationOverlay = false
            exportErrorMessage = error.localizedDescription
        }
    }

    private func resetGeneratedExport() {
        exportedPDFURL = nil
        exportedPDFIndices = nil
        isShowingFileExporter = false
        isShowingSharePresenter = false
        isShowingPreparationOverlay = false
        exportAction = nil
        exportErrorMessage = nil
    }


    private func presetButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
    }
}

private struct CreatingPDFOverlay: View {
    let title: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.08)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                Text(title)
                    .font(.headline)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 12, y: 4)
        }
    }
}

#if os(iOS)
private struct PDFSharePresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let url: URL
    let onPresented: () -> Void
    let onComplete: () -> Void
    let onFailure: (Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .clear
        return viewController
    }

    func updateUIViewController(_ viewController: UIViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.presentIfNeeded(from: viewController)
    }

    @MainActor
    final class Coordinator {
        var parent: PDFSharePresenter
        private var isPresenting = false

        init(_ parent: PDFSharePresenter) {
            self.parent = parent
        }

        func presentIfNeeded(from viewController: UIViewController) {
            guard parent.isPresented, !isPresenting, viewController.presentedViewController == nil else {
                return
            }

            isPresenting = true
            let activityViewController = UIActivityViewController(
                activityItems: [parent.url],
                applicationActivities: nil
            )
            activityViewController.popoverPresentationController?.sourceView = viewController.view
            activityViewController.popoverPresentationController?.sourceRect = CGRect(
                x: viewController.view.bounds.midX,
                y: viewController.view.bounds.midY,
                width: 0,
                height: 0
            )
            activityViewController.completionWithItemsHandler = { _, completed, _, error in
                Task { @MainActor in
                    self.isPresenting = false
                    self.parent.isPresented = false
                    if let error {
                        self.parent.onFailure(error)
                    } else if completed {
                        self.parent.onComplete()
                    }
                }
            }
            viewController.present(activityViewController, animated: true) {
                self.parent.onPresented()
            }
        }
    }
}
#elseif os(macOS)
private struct PDFSharePresenter: NSViewRepresentable {
    @Binding var isPresented: Bool
    let url: URL
    let onPresented: () -> Void
    let onComplete: () -> Void
    let onFailure: (Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> ShareAnchorView {
        let view = ShareAnchorView(frame: .zero)
        view.onWindowAvailable = { [weak coordinator = context.coordinator] view in
            coordinator?.showIfNeeded(from: view)
        }
        return view
    }

    func updateNSView(_ view: ShareAnchorView, context: Context) {
        context.coordinator.parent = self
        view.requestPresentation()
    }

    final class ShareAnchorView: NSView {
        var onWindowAvailable: ((NSView) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            requestPresentation()
        }

        func requestPresentation() {
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                self.onWindowAvailable?(self)
            }
        }
    }

    final class Coordinator: NSObject, NSSharingServicePickerDelegate, NSSharingServiceDelegate {
        var parent: PDFSharePresenter
        private var picker: NSSharingServicePicker?
        private var isPresenting = false

        init(_ parent: PDFSharePresenter) {
            self.parent = parent
        }

        func showIfNeeded(from view: NSView) {
            guard parent.isPresented, !isPresenting else { return }
            guard let anchorView = view.window?.contentView ?? view.superview else { return }

            isPresenting = true
            let picker = NSSharingServicePicker(items: [parent.url as NSURL])
            picker.delegate = self
            self.picker = picker
            parent.onPresented()
            picker.show(relativeTo: anchorRect(in: anchorView), of: anchorView, preferredEdge: .minY)
        }

        private func anchorRect(in view: NSView) -> NSRect {
            guard !view.bounds.isEmpty else { return NSRect(x: 0, y: 0, width: 1, height: 1) }
            return NSRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }

        func sharingServicePicker(
            _ sharingServicePicker: NSSharingServicePicker,
            didChoose service: NSSharingService?
        ) {
            guard service != nil else {
                finish()
                return
            }
        }

        func sharingServicePicker(
            _ sharingServicePicker: NSSharingServicePicker,
            delegateFor sharingService: NSSharingService
        ) -> NSSharingServiceDelegate? {
            self
        }

        func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
            finish(completed: true)
        }

        func sharingService(
            _ sharingService: NSSharingService,
            didFailToShareItems items: [Any],
            error: Error
        ) {
            let nsError = error as NSError
            if nsError.code == NSUserCancelledError {
                finish()
            } else {
                finish(error: error)
            }
        }

        private func finish(completed: Bool = false, error: Error? = nil) {
            isPresenting = false
            picker = nil
            parent.isPresented = false
            if let error {
                parent.onFailure(error)
            } else if completed {
                parent.onComplete()
            }
        }
    }
}
#endif
