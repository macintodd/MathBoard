//
//  FolderTileView.swift
//  MathBoardCore — Documents module
//
//  Shared folder tile used by the root browser and nested folder browser.
//

import SwiftUI

struct FolderTileView: View {
    let folder: Folder

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(folder.color.baseColor)
                Spacer()
                Circle()
                    .fill(folder.color.baseColor)
                    .frame(width: 11, height: 11)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            Spacer(minLength: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                Text("^[\(folder.lessonCount) lesson](inflect: true)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1.3, contentMode: .fit)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(folder.color.cardColor)
        )
        .shadow(color: folder.color.baseColor.opacity(0.18), radius: 6, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

extension FolderColor {
    var cardColor: Color {
        switch self {
        case .plain:  Color(red: 0.88, green: 0.83, blue: 0.72)
        case .gray:   Color(red: 0.56, green: 0.66, blue: 0.78)
        case .gold:   Color(red: 0.95, green: 0.86, blue: 0.50)
        case .blue:   Color(red: 0.55, green: 0.69, blue: 0.87)
        case .green:  Color(red: 0.58, green: 0.83, blue: 0.63)
        case .coral:  Color(red: 0.94, green: 0.71, blue: 0.62)
        case .purple: Color(red: 0.72, green: 0.64, blue: 0.88)
        case .red:    Color(red: 0.91, green: 0.57, blue: 0.57)
        }
    }

    var baseColor: Color {
        switch self {
        case .plain:
            Color(red: 0.74, green: 0.66, blue: 0.52)
        case .gold:
            AppColors.folderTint
        case .blue:
            Color(red: 0.35, green: 0.56, blue: 0.86)
        case .green:
            Color(red: 0.37, green: 0.64, blue: 0.42)
        case .coral:
            Color(red: 0.88, green: 0.42, blue: 0.34)
        case .purple:
            Color(red: 0.58, green: 0.45, blue: 0.78)
        case .red:
            Color(red: 0.78, green: 0.22, blue: 0.22)
        case .gray:
            Color(red: 0.55, green: 0.58, blue: 0.62)
        }
    }

    var shadowColor: Color {
        baseColor.opacity(0.24)
    }
}
