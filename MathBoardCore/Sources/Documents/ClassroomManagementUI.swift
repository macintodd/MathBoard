//
//  ClassroomManagementUI.swift
//  MathBoardCore — Documents module
//
//  Shared tile view and presentation-modifier helpers for classroom management
//  navigation. Used by StartScreenView and FolderDetailView.
//

import SwiftUI

// MARK: - Tile view

struct ClassManagementTileView: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .aspectRatio(1.42, contentMode: .fit)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(accentColor.opacity(0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(accentColor.opacity(0.20), lineWidth: 1)
                )
        )
        .shadow(color: accentColor.opacity(0.12), radius: 6, y: 3)
        .padding(4)
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Presentation modifiers

extension View {
    @ViewBuilder
    func classroomRosterPresentation(
        isPresented: Binding<Bool>,
        classroomRosterStore: ClassroomRosterStore
    ) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented) {
            ClassroomRosterView()
                .environment(classroomRosterStore)
        }
        #else
        sheet(isPresented: isPresented) {
            ClassroomRosterView()
                .environment(classroomRosterStore)
                .frame(minWidth: 1100, minHeight: 760)
        }
        #endif
    }

    @ViewBuilder
    func classroomAssignmentsPresentation(
        isPresented: Binding<Bool>,
        classroomRosterStore: ClassroomRosterStore,
        classroomAssignmentStore: ClassroomAssignmentStore
    ) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented) {
            ClassroomAssignmentsView()
                .environment(classroomRosterStore)
                .environment(classroomAssignmentStore)
        }
        #else
        sheet(isPresented: isPresented) {
            ClassroomAssignmentsView()
                .environment(classroomRosterStore)
                .environment(classroomAssignmentStore)
                .frame(minWidth: 980, minHeight: 680)
        }
        #endif
    }
}
