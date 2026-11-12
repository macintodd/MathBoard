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
    #if os(iOS)
    @State private var isSplashVisible = true
    #endif

    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    init() {
        MathBoardFirebaseBootstrap.configureIfPossible()
        #if STUDENT_BUILD
        let userModeStore = MathBoardUserModeStore(allowsTeacherMode: false)
        #else
        let userModeStore = MathBoardUserModeStore()
        #endif
        _userModeStore = State(initialValue: userModeStore)
        _documentStore = State(initialValue: DocumentStore(loadImmediately: userModeStore.mode == .teacher))
    }

    var body: some Scene {
        WindowGroup {
            #if os(iOS)
            ZStack {
                ContentView()
                    .environment(documentStore)
                    .environment(classroomRosterStore)
                    .environment(classroomAssignmentStore)
                    .environment(userModeStore)
                    .environment(teacherAuthStore)
                if isSplashVisible {
                    AppSplashScreen()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .task {
                MathBoardDiagnostics.startRuntimeMonitoring()
                try? await Task.sleep(for: .milliseconds(900))
                withAnimation(.easeOut(duration: 0.45)) {
                    isSplashVisible = false
                }
            }
            #else
            ContentView()
                .environment(documentStore)
                .environment(classroomRosterStore)
                .environment(classroomAssignmentStore)
                .environment(userModeStore)
                .environment(teacherAuthStore)
                .task {
                    MathBoardDiagnostics.startRuntimeMonitoring()
                }
            #endif
        }
    }
}

#if os(iOS)
private struct AppSplashScreen: View {
    var body: some View {
        Image("AppSplash")
            .resizable()
            .scaledToFill()
            .ignoresSafeArea()
    }
}
#endif
