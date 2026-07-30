//
//  MathBoardUITests.swift
//  MathBoardUITests
//
//  Created by Shawn Todd on 6/18/26.
//

import XCTest

@MainActor
final class MathBoardUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("-MathBoardUITestResetDocuments")
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testCreatesNestedFolderAndLessonFromDocumentBrowser() throws {
        app.launch()

        createRootFolder(named: "UI Algebra")
        openFolder(named: "UI Algebra")
        createChildFolder(named: "Unit 1")
        openFolder(named: "Unit 1")
        createLesson(named: "Practice 1")

        XCTAssertTrue(app.buttons["Lesson menu"].waitForExistence(timeout: 5))
    }

    func testMoveLessonSheetShowsDestinationPathLabels() throws {
        app.launchArguments.append("-MathBoardUITestDocumentWorkflowFixture")
        app.launch()

        openFolder(named: "UI Algebra")
        openFolder(named: "Unit 1")
        XCTAssertTrue(app.buttons["lessonRow.Warmup"].waitForExistence(timeout: 8), "Expected Warmup row in the seeded Unit 1 folder")

        openToolbarOverflowIfNeeded(forButtonIdentifier: "folder.selectButton")
        tapButton(named: "Select")
        tapElement(app.buttons["lessonRow.Warmup"])
        tapElement(app.buttons["folder.moveSelectedButton"])

        XCTAssertTrue(app.navigationBars["Move 1 Lesson"].waitForExistence(timeout: 5))
        let destination = app.buttons["moveDestination.Unit 2"]
        scrollUntilVisible(destination)
        XCTAssertTrue(destination.waitForExistence(timeout: 2))
        XCTAssertTrue(destination.label.contains("UI Algebra / Unit 2"))
    }

    private func createRootFolder(named name: String) {
        tapElement(app.buttons["start.newFolderButton"])
        enterName(name)
    }

    private func createChildFolder(named name: String) {
        tapElement(app.buttons["folder.addMenu"])
        tapButton(named: "New Folder")
        enterName(name)
    }

    private func createLesson(named name: String) {
        tapElement(app.buttons["folder.addMenu"])
        tapButton(named: "New Lesson")
        enterName(name)
    }

    private func openFolder(named name: String) {
        tapElement(app.buttons["folderTile.\(name)"])
    }

    private func enterName(_ name: String) {
        let field = app.textFields["nameEntry.nameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
        tapButton(named: "Create")
    }

    private func openToolbarOverflowIfNeeded(forButtonIdentifier identifier: String) {
        guard !app.buttons[identifier].waitForExistence(timeout: 1) else { return }
        tapButton(named: "More")
    }

    private func tapButton(named name: String) {
        let button = app.buttons[name]
        tapElement(button, named: name)
    }

    private func scrollUntilVisible(_ element: XCUIElement, maxSwipes: Int = 6) {
        var remainingSwipes = maxSwipes
        while !element.exists && remainingSwipes > 0 {
            app.swipeUp()
            remainingSwipes -= 1
        }
    }

    private func tapElement(_ element: XCUIElement, named name: String? = nil) {
        let description = name ?? element.identifier
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Expected to find UI element: \(description)")
        element.tap()
    }
}
