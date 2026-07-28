//
//  LessonFileIconView.swift
//  MathBoardCore — Documents module
//
//  Shared icon for MathBoard lesson files in document browser rows.
//

import SwiftUI

struct LessonFileIconView: View {
    var body: some View {
        Image("MathBoardFileIcon")
            .resizable()
            .scaledToFit()
            .frame(width: 42, height: 42)
            .accessibilityHidden(true)
    }
}
