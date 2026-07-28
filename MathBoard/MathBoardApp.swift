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
    @State private var documentStore = DocumentStore()
    @State private var classroomRosterStore = ClassroomRosterStore()

    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(documentStore)
                .environment(classroomRosterStore)
        }
    }
}
