//
//  MathBoardApp.swift
//  MathBoard
//
//  Created by Shawn Todd on 6/18/26.
//

import SwiftUI
import Documents

@main
struct MathBoardApp: App {
    @State private var documentStore: DocumentStore
    @State private var classroomRosterStore = ClassroomRosterStore()
    @State private var classroomAssignmentStore = ClassroomAssignmentStore()
    @State private var userModeStore: MathBoardUserModeStore
    @State private var teacherAuthStore = MathBoardTeacherAuthStore()

    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    init() {
        MathBoardFirebaseBootstrap.configureIfPossible()
        let userModeStore = MathBoardUserModeStore()
        _userModeStore = State(initialValue: userModeStore)
        _documentStore = State(initialValue: DocumentStore(loadImmediately: userModeStore.mode == .teacher))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(documentStore)
                .environment(classroomRosterStore)
                .environment(classroomAssignmentStore)
                .environment(userModeStore)
                .environment(teacherAuthStore)
        }
    }
}
