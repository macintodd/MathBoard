//
//  LessonDetailView.swift
//  MathBoardCore — Documents module
//
//  Embeds the presenting canvas for a single lesson. Thin wrapper —
//  Presentation owns the toolbar (viewfinder toggle, and later present /
//  mirror, freeze) and Canvas owns its drawing surface lifecycle.
//

import SwiftUI
import Presentation
import Slides

struct LessonDetailView: View {
    let lesson: Lesson

    var body: some View {
        SlidesView(lessonURL: lesson.url)
            .navigationTitle(lesson.name)
            .onAppear { DisplayBroker.shared.lessonURL = lesson.url }
    }
}

#Preview {
    NavigationStack {
        LessonDetailView(lesson: Lesson(
            id: UUID(),
            name: "Quadratic Functions Day 1",
            url: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("Quadratic Functions Day 1.mathboard"),
            createdAt: .now.addingTimeInterval(-86_400),
            modifiedAt: .now.addingTimeInterval(-3_600)
        ))
    }
}
