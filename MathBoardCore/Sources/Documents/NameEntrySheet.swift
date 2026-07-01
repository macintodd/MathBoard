//
//  NameEntrySheet.swift
//  MathBoardCore — Documents module
//
//  A small modal sheet that asks the user for a single name string.
//  Reused for creating folders and creating lessons; the parent supplies
//  the title, placeholder, confirm-button label, and the action to run
//  on submit.
//

import SwiftUI

struct NameEntrySheet: View {
    let title: String
    let placeholder: String
    let confirmLabel: String
    let onConfirm: (String) throws -> Void

    @State private var name: String
    @State private var selection: TextSelection?
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    init(
        title: String,
        placeholder: String,
        confirmLabel: String,
        initialName: String = "",
        onConfirm: @escaping (String) throws -> Void
    ) {
        self.title = title
        self.placeholder = placeholder
        self.confirmLabel = confirmLabel
        self.onConfirm = onConfirm
        _name = State(initialValue: initialName)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                TextField(placeholder, text: $name, selection: $selection)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit(submit)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.top, 8)
                }
            }
            .padding(20)
            .onChange(of: name) { _, _ in
                errorMessage = nil
            }
            .frame(minWidth: 320)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmLabel, action: submit)
                        .disabled(trimmedName.isEmpty)
                }
            }
            .presentationDetents([.height(180)])
            .onAppear {
                isFocused = true
                selectAllTextIfNeeded()
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func selectAllTextIfNeeded() {
        guard !name.isEmpty else { return }
        selection = TextSelection(range: name.startIndex..<name.endIndex)
    }

    private func submit() {
        let final = trimmedName
        guard !final.isEmpty else { return }

        do {
            try onConfirm(final)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
