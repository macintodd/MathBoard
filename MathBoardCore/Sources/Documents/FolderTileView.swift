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
        ZStack(alignment: .center) {
            Image(folder.color.assetName)
                .resizable()
                .scaledToFill()
                .accessibilityHidden(true)
                .shadow(color: folder.color.shadowColor, radius: 8, y: 4)

            VStack(alignment: .center, spacing: 4) {
                Text(folder.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.82)
                Text("^[\(folder.lessonCount) lesson](inflect: true)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .shadow(color: .white.opacity(0.85), radius: 3)
            .shadow(color: .white.opacity(0.55), radius: 7)
            .padding(.horizontal, 18)
            .offset(y: 12)
        }
        .aspectRatio(1.42, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipped()
        .padding(4)
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

extension FolderColor {
    var assetName: String {
        switch self {
        case .plain, .gray:
            "MathBoardFolderIconPlain"
        case .gold:
            "MathBoardFolderIconGold"
        case .blue:
            "MathBoardFolderIconBlue"
        case .green:
            "MathBoardFolderIconGreen"
        case .coral:
            "MathBoardFolderIconCoral"
        case .purple:
            "MathBoardFolderIconPurple"
        case .red:
            "MathBoardFolderIconRed"
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
