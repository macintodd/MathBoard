//
//  MathBoardTests.swift
//  MathBoardTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Documents
@testable import Canvas
import Slides
@testable import WidgetEngine

struct MathBoardTests {

    @Test func textObjectSidecarURLUsesDrawingBaseName() throws {
        let drawingURL = URL(fileURLWithPath: "/tmp/slide-123.drawing")
        let sidecarURL = PresentationCanvasTextObject.sidecarURL(forDrawingURL: drawingURL)

        #expect(sidecarURL.lastPathComponent == "slide-123.textobjects.json")
        #expect(sidecarURL.deletingLastPathComponent() == drawingURL.deletingLastPathComponent())
    }

    @Test func textObjectRoundTripsThroughSidecarJSON() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MathBoardTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let drawingURL = directoryURL.appendingPathComponent("slide-abc.drawing")
        let sidecarURL = PresentationCanvasTextObject.sidecarURL(forDrawingURL: drawingURL)
        let textObjects = [
            PresentationCanvasTextObject(
                text: "Factored form",
                x: 24,
                y: 48,
                width: 320,
                height: 88,
                fontSize: 36,
                red: 0.92,
                green: 0.08,
                blue: 0.12,
                alpha: 1
            )
        ]

        try PresentationCanvasTextObject.save(textObjects, to: sidecarURL)
        let loaded = PresentationCanvasTextObject.load(from: sidecarURL)

        #expect(loaded == textObjects)
    }

    @Test func missingTextObjectSidecarLoadsAsEmptyArray() {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).textobjects.json")

        #expect(PresentationCanvasTextObject.load(from: missingURL).isEmpty)
    }

    @Test func latexObjectSidecarURLUsesDrawingBaseName() throws {
        let drawingURL = URL(fileURLWithPath: "/tmp/slide-123.drawing")
        let sidecarURL = CanvasLaTeXObject.sidecarURL(forDrawingURL: drawingURL)

        #expect(sidecarURL.lastPathComponent == "slide-123.latexobjects.json")
        #expect(sidecarURL.deletingLastPathComponent() == drawingURL.deletingLastPathComponent())
    }

    @Test func latexObjectRoundTripsThroughSidecarJSON() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MathBoardTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let drawingURL = directoryURL.appendingPathComponent("slide-abc.drawing")
        let sidecarURL = CanvasLaTeXObject.sidecarURL(forDrawingURL: drawingURL)
        let imageID = UUID()
        let latexObjects = [
            CanvasLaTeXObject(
                imageObjectID: imageID,
                latexSource: "\\frac{x}{2}=7",
                librarySourceLaTeX: "\\frac{x}{2}=7",
                hasRecordedLibraryDerivative: true
            )
        ]

        try CanvasLaTeXObject.save(latexObjects, to: sidecarURL)
        let loaded = CanvasLaTeXObject.load(from: sidecarURL)

        #expect(loaded == latexObjects)
    }

    @Test func missingLaTeXObjectSidecarLoadsAsEmptyArray() {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).latexobjects.json")

        #expect(CanvasLaTeXObject.load(from: missingURL).isEmpty)
    }

    @Test func geometryObjectSidecarURLUsesDrawingBaseName() throws {
        let drawingURL = URL(fileURLWithPath: "/tmp/slide-123.drawing")
        let sidecarURL = CanvasGeometryObject.sidecarURL(forDrawingURL: drawingURL)

        #expect(sidecarURL.lastPathComponent == "slide-123.geometryobjects.json")
        #expect(sidecarURL.deletingLastPathComponent() == drawingURL.deletingLastPathComponent())
    }

    @Test func geometryObjectRoundTripsThroughSidecarJSON() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MathBoardTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let drawingURL = directoryURL.appendingPathComponent("slide-abc.drawing")
        let sidecarURL = CanvasGeometryObject.sidecarURL(forDrawingURL: drawingURL)
        let geometryObjects = [
            CanvasGeometryObject(
                shape: .rectangle,
                x: 10,
                y: 20,
                width: 120,
                height: 80,
                strokeRed: 0.1,
                strokeGreen: 0.2,
                strokeBlue: 0.3,
                strokeAlpha: 1,
                strokeWidth: 4,
                fillRed: 0.5,
                fillGreen: 0.6,
                fillBlue: 0.7,
                fillOpacity: 0.35,
                polygonSides: 6,
                arrow: .end
            ),
            CanvasGeometryObject(
                shape: .line,
                x: 0,
                y: 0,
                width: -50,
                height: 30,
                arrow: .both
            )
        ]

        try CanvasGeometryObject.save(geometryObjects, to: sidecarURL)
        let loaded = CanvasGeometryObject.load(from: sidecarURL)

        #expect(loaded == geometryObjects)
    }

    @Test func missingGeometryObjectSidecarLoadsAsEmptyArray() {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).geometryobjects.json")

        #expect(CanvasGeometryObject.load(from: missingURL).isEmpty)
    }

    @Test func geometryObjectNormalizedFrameStandardizesNegativeExtent() {
        let object = CanvasGeometryObject(shape: .line, x: 100, y: 100, width: -40, height: -20)
        let normalized = object.normalizedFrame

        #expect(normalized.minX == 60)
        #expect(normalized.minY == 80)
        #expect(normalized.width == 40)
        #expect(normalized.height == 20)
    }

    @Test func strokeColorSidecarURLUsesDrawingBaseName() {
        let drawingURL = URL(fileURLWithPath: "/tmp/slide-123.drawing")
        let sidecarURL = CanvasStrokeColorRecord.sidecarURL(forDrawingURL: drawingURL)

        #expect(sidecarURL.lastPathComponent == "slide-123.strokecolors.json")
        #expect(sidecarURL.deletingLastPathComponent() == drawingURL.deletingLastPathComponent())
    }

    @Test func strokeColorStableKeyUsesMicrosecondPrecision() {
        let creationTime = 1_800_000_000.123456
        let record = CanvasStrokeColorRecord(
            creationTime: creationTime,
            red: 0.0001,
            green: 0.0001,
            blue: 0.0001,
            alpha: 1
        )

        #expect(record.stableKey == CanvasStrokeColorRecord.stableKey(for: creationTime))
        #expect(record.stableKey == 1_800_000_000_123_456)
    }

    @Test func strokeColorRecordsRoundTripThroughSidecarJSON() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MathBoardTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let drawingURL = directoryURL.appendingPathComponent("slide-abc.drawing")
        let sidecarURL = CanvasStrokeColorRecord.sidecarURL(forDrawingURL: drawingURL)
        let records = [
            CanvasStrokeColorRecord(
                creationTime: 1_800_000_000.25,
                red: 0.0001,
                green: 0.0001,
                blue: 0.0001,
                alpha: 1
            ),
            CanvasStrokeColorRecord(
                creationTime: 1_800_000_001.5,
                red: 0,
                green: 0.32,
                blue: 0.92,
                alpha: 1
            )
        ]

        try CanvasStrokeColorRecord.save(records, to: sidecarURL)
        let loaded = CanvasStrokeColorRecord.load(from: sidecarURL)

        #expect(loaded == records)
    }

    @Test func missingStrokeColorSidecarLoadsAsEmptyArray() {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).strokecolors.json")

        #expect(CanvasStrokeColorRecord.load(from: missingURL).isEmpty)
    }

    @Test func legacyTextObjectJSONDefaultsToBlack() throws {
        let json = """
        [{
            "id": "22222222-3333-4444-5555-666666666666",
            "text": "Legacy",
            "x": 10,
            "y": 20,
            "width": 200,
            "height": 80,
            "fontSize": 32
        }]
        """
        let objects = try JSONDecoder().decode([PresentationCanvasTextObject].self, from: Data(json.utf8))
        let object = try #require(objects.first)

        #expect(object.red == 0)
        #expect(object.green == 0)
        #expect(object.blue == 0)
        #expect(object.alpha == 1)
    }

    @Test func contentBoundsUsesPDFWhenThereIsNoInk() {
        let bounds = CanvasContentBounds.combinedBounds(
            drawingBounds: .null,
            backgroundSize: CGSize(width: 612, height: 792),
            textObjects: [],
            canvasOrigin: CGPoint(x: 3000, y: 3000)
        )

        #expect(bounds == CGRect(x: 3000, y: 3000, width: 612, height: 792))
    }

    @Test func contentBoundsUnionsInkPDFAndText() throws {
        let text = PresentationCanvasTextObject(
            text: "Directions",
            x: 700,
            y: 820,
            width: 240,
            height: 72,
            fontSize: 32
        )

        let bounds = try #require(CanvasContentBounds.combinedBounds(
            drawingBounds: CGRect(x: 3020, y: 3050, width: 120, height: 80),
            backgroundSize: CGSize(width: 612, height: 792),
            textObjects: [text],
            canvasOrigin: CGPoint(x: 3000, y: 3000)
        ))

        #expect(bounds.minX == 3000)
        #expect(bounds.minY == 3000)
        #expect(bounds.maxX == 3940)
        #expect(bounds.maxY == 3892)
    }

    @Test func contentBoundsIgnoresEmptyTextAndInvalidDrawingBounds() {
        let emptyText = PresentationCanvasTextObject(
            text: "",
            x: 10,
            y: 20,
            width: 100,
            height: 40,
            fontSize: 20
        )

        let bounds = CanvasContentBounds.combinedBounds(
            drawingBounds: .null,
            backgroundSize: nil,
            textObjects: [emptyText]
        )

        #expect(bounds == nil)
    }

    @Test func slideMetadataRoundTripsViewportAndBackground() throws {
        let slideID = try #require(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let slide = SlideMetadata(
            id: slideID,
            createdAt: createdAt,
            viewport: SlideViewportState(
                zoomScale: 2.5,
                contentOffsetX: 120,
                contentOffsetY: 240,
                platform: "iPadOS"
            ),
            background: SlideBackground(kind: .pdfPage, assetFileName: "notes.pdf", pageIndex: 3)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(slide)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SlideMetadata.self, from: data)

        #expect(decoded == slide)
        #expect(decoded.viewport?.zoomScale == 2.5)
        #expect(decoded.viewport?.platform == "iPadOS")
        #expect(decoded.background?.assetFileName == "notes.pdf")
    }

    @Test func activityWidgetJSONRepairsAIAuthoredLaTeXBackslashes() throws {
        let json = #"""
        {
          "schemaVersion": 1,
          "widgetId": "evaluating-expressions-001",
          "activity": "multipleChoice",
          "title": "Evaluating Expressions",
          "learningObjective": "Evaluate expressions accurately using the standard order of operations.",
          "rules": {
            "scoreMode": "streak",
            "advanceMode": "manual",
            "allowRetry": true,
            "shuffleQuestions": false,
            "shuffleChoices": false,
            "maxAttemptsPerQuestion": 2,
            "calculatorAllowed": false
          },
          "questions": [
            {
              "id": "q1",
              "prompt": "Evaluate the following expression:",
              "expression": "5 + 3 \cdot 4",
              "choices": [
                { "id": "a", "label": "32", "isCorrect": false },
                { "id": "b", "label": "17", "isCorrect": true }
              ],
              "hints": []
            },
            {
              "id": "q2",
              "prompt": "Evaluate the expression:",
              "expression": "\frac{4^2 - 6}{2} + 5",
              "choices": [
                { "id": "a", "label": "7", "isCorrect": false },
                { "id": "b", "label": "10", "isCorrect": true }
              ],
              "hints": []
            }
          ]
        }
        """#

        let result = WidgetActivityJSONCodec.decode(json)
        let document = try #require(result.document)

        #expect(result.errors.isEmpty)
        #expect(document.questions[0].expression == #"5 + 3 \cdot 4"#)
        #expect(document.questions[1].expression == #"\frac{4^2 - 6}{2} + 5"#)
    }

    @Test func activityWidgetJSONRejectsWrongNumericCorrectChoice() {
        let json = #"""
        {
          "schemaVersion": 1,
          "widgetId": "wrong-answer-audit",
          "activity": "multipleChoice",
          "title": "Wrong Answer Audit",
          "learningObjective": "Catch incorrect generated answer keys.",
          "questions": [
            {
              "id": "q1",
              "prompt": "Evaluate.",
              "expression": "5 + 3 \cdot 4",
              "choices": [
                { "id": "a", "label": "32", "isCorrect": true },
                { "id": "b", "label": "17", "isCorrect": false }
              ]
            }
          ]
        }
        """#

        let result = WidgetActivityJSONCodec.decode(json)

        #expect(result.document == nil)
        #expect(result.errors.contains { $0.contains("expression evaluates to 17") })
    }

    @Test func activityWidgetJSONRejectsDuplicateChoiceLabels() {
        let json = #"""
        {
          "schemaVersion": 1,
          "widgetId": "duplicate-choice-audit",
          "activity": "multipleChoice",
          "title": "Duplicate Choice Audit",
          "learningObjective": "Catch duplicate generated choices.",
          "questions": [
            {
              "id": "q1",
              "prompt": "Choose 17.",
              "choices": [
                { "id": "a", "label": "17", "isCorrect": true },
                { "id": "b", "label": "$17$", "isCorrect": false }
              ]
            }
          ]
        }
        """#

        let result = WidgetActivityJSONCodec.decode(json)

        #expect(result.document == nil)
        #expect(result.errors.contains { $0.contains("duplicate choice label") })
    }

    @Test func activityWidgetJSONRejectsIncorrectChoiceThatMatchesEvaluatedAnswer() {
        let json = #"""
        {
          "schemaVersion": 1,
          "widgetId": "incorrect-matching-answer-audit",
          "activity": "multipleChoice",
          "title": "Incorrect Matching Answer Audit",
          "learningObjective": "Catch distractors that are actually correct.",
          "questions": [
            {
              "id": "q1",
              "prompt": "Evaluate.",
              "expression": "\frac{10}{2}",
              "choices": [
                { "id": "a", "label": "4", "isCorrect": true },
                { "id": "b", "label": "5", "isCorrect": false }
              ]
            }
          ]
        }
        """#

        let result = WidgetActivityJSONCodec.decode(json)

        #expect(result.document == nil)
        #expect(result.errors.contains { $0.contains("marked incorrect but matches") })
    }

    @Test func activityWidgetJSONDefaultsMissingHintsToEmptyArray() throws {
        let json = #"""
        {
          "schemaVersion": 1,
          "widgetId": "minimal-multiple-choice",
          "activity": "multipleChoice",
          "title": "Minimal",
          "learningObjective": "Decode minimal valid activity questions.",
          "questions": [
            {
              "id": "q1",
              "prompt": "Choose.",
              "choices": [
                { "id": "a", "label": "Correct", "isCorrect": true },
                { "id": "b", "label": "Incorrect", "isCorrect": false }
              ]
            }
          ]
        }
        """#

        let result = WidgetActivityJSONCodec.decode(json)
        let question = try #require(result.document?.questions.first)

        #expect(result.errors.isEmpty)
        #expect(question.hints.isEmpty)
    }

    @Test func widgetJSONRepairPreservesOrdinaryJSONEscapes() {
        let json = #"""
        { "message": "Line one\nLine two", "quote": "She said \"yes\"." }
        """#

        let repaired = WidgetJSONRepair.escapingUnescapedLaTeXCommands(in: json)

        #expect(repaired == json)
    }

    @Test func widgetJSONRepairDoesNotDoubleEscapeValidLaTeXCommands() {
        let json = #"""
        { "expression": "\\frac{12}{3} + 4 \\cdot 2" }
        """#

        let repaired = WidgetJSONRepair.escapingUnescapedLaTeXCommands(in: json)

        #expect(repaired == json)
    }

    @Test func widgetScoreSheetTotalsOnlyCompletedWidgets() throws {
        let completedID = try #require(UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"))
        let inProgressID = try #require(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let notStartedID = try #require(UUID(uuidString: "66666666-7777-8888-9999-000000000000"))
        let widgets = [
            WidgetObject(
                id: completedID,
                name: "Completed",
                codeString: WidgetSamples.orderOpsActivityJSON,
                frame: CGRect(x: 0, y: 0, width: 700, height: 360),
                activityRuntimeState: WidgetActivityRuntimeState(
                    multipleChoice: WidgetMultipleChoiceRuntimeState(
                        score: 5,
                        attempts: 6,
                        streak: 3,
                        answeredQuestionIDs: Set(["a", "b", "c", "d", "e", "f"])
                    )
                )
            ),
            WidgetObject(
                id: inProgressID,
                name: "In Progress",
                codeString: WidgetSamples.orderOpsActivityJSON,
                frame: CGRect(x: 0, y: 380, width: 700, height: 360),
                activityRuntimeState: WidgetActivityRuntimeState(
                    multipleChoice: WidgetMultipleChoiceRuntimeState(
                        score: 2,
                        attempts: 3,
                        streak: 1,
                        answeredQuestionIDs: Set(["a", "b", "c"])
                    )
                )
            ),
            WidgetObject(
                id: notStartedID,
                name: "Not Started",
                codeString: WidgetSamples.orderOpsActivityJSON,
                frame: CGRect(x: 0, y: 760, width: 700, height: 360),
                activityRuntimeState: WidgetActivityRuntimeState()
            )
        ]

        let sheet = WidgetActivityScoreSheet(widgets: widgets)

        #expect(sheet.completedRecords.map(\.id) == [completedID.uuidString])
        #expect(sheet.averagePercent == 83)
        #expect(sheet.pointsPossible == 6)
        #expect(sheet.totalPoints == 5.3)
    }

    @Test func legacyWidgetObjectDefaultsToUnpinned() throws {
        let json = #"""
        {
          "id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
          "frame": [[10, 20], [300, 200]],
          "name": "Legacy Widget",
          "codeString": "{}"
        }
        """#

        let widget = try JSONDecoder().decode(WidgetObject.self, from: Data(json.utf8))

        #expect(widget.isPinnedToCanvas == false)
    }

    @Test func builtInInteractiveWidgetMarkerRoutesOutsideJSONActivitySchema() {
        let kind = BuiltInInteractiveKind.inequalitiesExplorer
        let widget = WidgetObject(
            name: kind.displayName,
            codeString: kind.widgetCodeString,
            frame: CGRect(origin: .zero, size: kind.defaultSize)
        )

        #expect(widget.builtInInteractiveKind == .inequalitiesExplorer)
        #expect(widget.activityDocument == nil)
        #expect(widget.activityKind == .builtInInteractive)
        #expect(kind.defaultSize == CGSize(width: 900, height: 640))
    }

    @Test func pinnedWidgetViewportFrameScalesWithZoom() {
        let viewport = WidgetCanvasViewport(
            zoomScale: 2,
            contentOffset: CGPoint(x: 100, y: 80),
            canvasOrigin: CGPoint(x: 3000, y: 3000)
        )
        let sourceFrame = CGRect(x: 50, y: 70, width: 320, height: 180)

        let displayFrame = viewport.pinnedDisplayFrame(for: sourceFrame)
        let roundTrip = viewport.pinnedSourceFrame(for: displayFrame)

        #expect(displayFrame.origin == CGPoint(x: 6000, y: 6060))
        #expect(displayFrame.size == CGSize(width: 640, height: 360))
        #expect(roundTrip == sourceFrame)
    }

    @MainActor
    @Test func slideStoreCreatesManifestForNewLessonPackage() throws {
        let lessonURL = try makeTemporaryLessonPackage()
        defer { try? FileManager.default.removeItem(at: lessonURL) }

        let store = SlideStore(lessonURL: lessonURL)

        #expect(store.slides.count == 1)
        #expect(FileManager.default.fileExists(atPath: lessonURL.appendingPathComponent("slides.json").path))
        #expect(store.drawingURL(for: store.slides[0]).lastPathComponent == "slide-\(store.slides[0].id.uuidString).drawing")
        #expect(store.isBlankSlide(at: 0))
    }

    @MainActor
    @Test func slideStorePersistsViewportUpdates() throws {
        let lessonURL = try makeTemporaryLessonPackage()
        defer { try? FileManager.default.removeItem(at: lessonURL) }
        let store = SlideStore(lessonURL: lessonURL)
        let viewport = SlideViewportState(zoomScale: 0.75, contentOffsetX: -320, contentOffsetY: 144)

        try store.updateViewport(viewport, forSlideAt: 0)
        let reloaded = SlideStore(lessonURL: lessonURL)

        #expect(reloaded.slides.count == 1)
        #expect(reloaded.slides[0].viewport == viewport)
        #expect(!reloaded.isBlankSlide(at: 0))
    }

    @MainActor
    @Test func slideStoreAddsMovesAndDeletesSlides() throws {
        let lessonURL = try makeTemporaryLessonPackage()
        defer { try? FileManager.default.removeItem(at: lessonURL) }
        let store = SlideStore(lessonURL: lessonURL)
        let firstID = store.slides[0].id
        let second = store.addSlide()
        let third = store.addSlide()

        #expect(store.slides.map(\.id) == [firstID, second.id, third.id])

        let movedIndex = try store.moveSlide(at: 2, to: 0)
        #expect(movedIndex == 0)
        #expect(store.slides.map(\.id) == [third.id, firstID, second.id])

        let activeIndex = try store.deleteSlide(at: 0)
        #expect(activeIndex == 0)
        #expect(store.slides.map(\.id) == [firstID, second.id])

        let reloaded = SlideStore(lessonURL: lessonURL)
        #expect(reloaded.slides.map(\.id) == [firstID, second.id])
    }

    @MainActor
    @Test func slideStorePreventsDeletingLastSlide() throws {
        let lessonURL = try makeTemporaryLessonPackage()
        defer { try? FileManager.default.removeItem(at: lessonURL) }
        let store = SlideStore(lessonURL: lessonURL)

        do {
            _ = try store.deleteSlide(at: 0)
            Issue.record("Deleting the final slide should throw")
        } catch let error as SlideStoreError {
            #expect(error.localizedDescription == SlideStoreError.cannotDeleteLastSlide.localizedDescription)
        }
    }

    @MainActor
    @Test func slideStoreMigratesLegacyMainDrawing() throws {
        let lessonURL = try makeTemporaryLessonPackage()
        defer { try? FileManager.default.removeItem(at: lessonURL) }
        let strokesURL = lessonURL.appendingPathComponent("strokes", isDirectory: true)
        let legacyURL = strokesURL.appendingPathComponent("main.drawing")
        let legacyData = Data([0x4d, 0x42, 0x01])
        try legacyData.write(to: legacyURL)

        let store = SlideStore(lessonURL: lessonURL)
        let migratedDrawingURL = store.drawingURL(for: store.slides[0])

        #expect(store.slides.count == 1)
        #expect(!FileManager.default.fileExists(atPath: legacyURL.path))
        #expect(try Data(contentsOf: migratedDrawingURL) == legacyData)
        #expect(FileManager.default.fileExists(atPath: lessonURL.appendingPathComponent("slides.json").path))
    }

    @MainActor
    @Test func documentStoreCreatesAndListsNestedFolders() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = DocumentStore(rootURL: rootURL)

        let algebra = try store.createFolder(named: "Algebra 2")
        let quadratics = try store.createFolder(named: "Quadratics", at: algebra.url)

        #expect(algebra.color == .plain)
        #expect(store.folders.map(\.name) == ["Algebra 2"])
        #expect(store.folders(in: algebra).map(\.name) == ["Quadratics"])
        #expect(store.allFolders().map(\.url) == [algebra.url, quadratics.url])
    }

    @MainActor
    @Test func documentStoreCreatesLessonsInsideNestedFoldersAndIncludesThemInRecentLessons() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = DocumentStore(rootURL: rootURL)

        let algebra = try store.createFolder(named: "Algebra 2")
        let quadratics = try store.createFolder(named: "Quadratics", at: algebra.url)
        let lesson = try store.createLesson(named: "Solving by Factoring", in: quadratics)

        #expect(store.lessons(in: quadratics).map(\.id) == [lesson.id])
        #expect(store.allLessons().map(\.id).contains(lesson.id))
        #expect(store.recentLessons.map(\.id).contains(lesson.id))
    }

    @MainActor
    @Test func documentStoreImportsLessonPackageIntoTargetFolderWithFreshIdentity() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        let sourceURL = try makeTemporaryExternalLessonPackage(named: "Compound Inequalities")
        defer {
            try? FileManager.default.removeItem(at: rootURL)
            try? FileManager.default.removeItem(at: sourceURL.deletingLastPathComponent())
        }
        let store = DocumentStore(rootURL: rootURL)
        let algebra = try store.createFolder(named: "Algebra 2")
        let inequalities = try store.createFolder(named: "Inequalities", at: algebra.url)
        let sourceID = try readDocumentMetadataID(at: sourceURL)

        let imported = try store.importLessonPackage(from: sourceURL, into: inequalities)
        let importedAgain = try store.importLessonPackage(from: sourceURL, into: inequalities)

        #expect(imported.name == "Compound Inequalities")
        #expect(imported.url.deletingLastPathComponent() == inequalities.url)
        #expect(imported.id != sourceID)
        #expect(importedAgain.name == "Compound Inequalities 2")
        #expect(importedAgain.url.deletingLastPathComponent() == inequalities.url)
        #expect(importedAgain.id != sourceID)
        #expect(store.lessons(in: inequalities).map(\.name).sorted() == [
            "Compound Inequalities",
            "Compound Inequalities 2"
        ])
    }

    @MainActor
    @Test func documentStoreMovesLessonBetweenNestedFoldersAndKeepsIdentity() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = DocumentStore(rootURL: rootURL)
        let algebra = try store.createFolder(named: "Algebra 2")
        let sourceFolder = try store.createFolder(named: "Unit 1", at: algebra.url)
        let destinationFolder = try store.createFolder(named: "Unit 2", at: algebra.url)
        let lesson = try store.createLesson(named: "Warmup", in: sourceFolder)

        let moved = try store.moveLessons([lesson], to: destinationFolder)

        #expect(moved.map(\.id) == [lesson.id])
        #expect(moved[0].url.deletingLastPathComponent() == destinationFolder.url)
        #expect(store.lessons(in: sourceFolder).isEmpty)
        #expect(store.lessons(in: destinationFolder).map(\.id) == [lesson.id])
    }

    @MainActor
    @Test func documentStoreRenamesNestedFolderWithinItsParent() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = DocumentStore(rootURL: rootURL)
        let algebra = try store.createFolder(named: "Algebra 2")
        let inequalities = try store.createFolder(named: "Inequalities", at: algebra.url)

        let renamed = try store.renameFolder(inequalities, to: "Compound Inequalities")

        #expect(renamed.name == "Compound Inequalities")
        #expect(renamed.url.deletingLastPathComponent() == algebra.url)
        #expect(store.folders(in: algebra).map(\.name) == ["Compound Inequalities"])
        #expect(!FileManager.default.fileExists(atPath: inequalities.url.path))
    }

    @MainActor
    @Test func documentStorePersistsFolderColorMetadata() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = DocumentStore(rootURL: rootURL)

        let algebra = try store.createFolder(named: "Algebra 2")
        let updated = try store.updateFolderColor(algebra, to: .blue)
        let reloadedStore = DocumentStore(rootURL: rootURL)

        #expect(updated.color == .blue)
        #expect(reloadedStore.folders.first?.color == .blue)
    }

    @MainActor
    @Test func classroomRosterStoreImportsCSVWithInferredColumns() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = ClassroomRosterStore(rootURL: rootURL)
        let csvURL = rootURL.appendingPathComponent("Period 1.csv")
        try """
        First Name,Last Name,Student ID,Alternate ID
        Ada,Lovelace,A100,ADA-1
        Grace,Hopper,G200,
        """.write(to: csvURL, atomically: true, encoding: .utf8)

        let preview = try store.previewCSV(at: csvURL)
        let classroom = try store.importCSV(preview: preview, className: "Period 1")
        let reloadedStore = ClassroomRosterStore(rootURL: rootURL)

        #expect(classroom.name == "Period 1")
        #expect(classroom.students.map(\.lastName) == ["Hopper", "Lovelace"])
        #expect(classroom.students.first(where: { $0.lastName == "Lovelace" })?.officialStudentID == "A100")
        #expect(reloadedStore.classrooms.first?.students.count == 2)
    }

    @MainActor
    @Test func classroomRosterStoreGeneratesAlternateIDsOnlyWhenMissing() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = ClassroomRosterStore(rootURL: rootURL)
        let preview = RosterCSVPreview(
            headers: ["First Name", "Last Name", "Student ID", "Alternate ID"],
            rows: [
                ["Ada", "Lovelace", "A100", ""],
                ["Grace", "Hopper", "G200", "KEEP-ME"]
            ],
            mapping: CSVColumnMapping(firstNameIndex: 0, lastNameIndex: 1, officialStudentIDIndex: 2, alternateStudentIDIndex: 3)
        )
        let classroom = try store.importCSV(preview: preview, className: "Algebra 2")

        try store.generateAlternateIDs(for: classroom.id)

        let students = try #require(store.classrooms.first?.students)
        #expect(students.first(where: { $0.lastName == "Hopper" })?.alternateStudentID == "KEEP-ME")
        #expect(students.first(where: { $0.lastName == "Lovelace" })?.alternateStudentID == "ALG2-002")
    }

    @MainActor
    @Test func classroomRosterStoreRegeneratesAlternateIDsWithCustomPrefix() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = ClassroomRosterStore(rootURL: rootURL)
        let classroom = try store.importCSV(
            preview: RosterCSVPreview(
                headers: ["First", "Last", "ID", "Alternate"],
                rows: [
                    ["Ada", "Lovelace", "A100", "OLD-1"],
                    ["Grace", "Hopper", "G200", ""]
                ],
                mapping: CSVColumnMapping(firstNameIndex: 0, lastNameIndex: 1, officialStudentIDIndex: 2, alternateStudentIDIndex: 3)
            ),
            className: "Period 4 Algebra"
        )

        try store.updateAlternateIDPrefix("p4alg", for: classroom.id)
        try store.generateAlternateIDs(for: classroom.id, overwriteExisting: true)

        let reloadedStore = ClassroomRosterStore(rootURL: rootURL)
        let students = try #require(reloadedStore.classrooms.first?.students)
        #expect(reloadedStore.classrooms.first?.alternateIDPrefix == "P4ALG")
        #expect(students.map(\.alternateStudentID) == ["P4ALG-001", "P4ALG-002"])
    }

    @MainActor
    @Test func classroomRosterStoreAddsManualStudentAtTopOfRoster() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = ClassroomRosterStore(rootURL: rootURL)
        let classroom = try store.importCSV(
            preview: RosterCSVPreview(
                headers: ["First", "Last", "ID"],
                rows: [
                    ["Ada", "Lovelace", "A100"],
                    ["Grace", "Hopper", "G200"]
                ],
                mapping: CSVColumnMapping(firstNameIndex: 0, lastNameIndex: 1, officialStudentIDIndex: 2)
            ),
            className: "Period 1"
        )

        let newStudent = try store.addStudent(to: classroom.id)

        let students = try #require(store.classrooms.first?.students)
        #expect(students.first?.id == newStudent.id)
    }

    @MainActor
    @Test func classroomRosterStoreMovesSelectedStudentsBetweenClasses() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = ClassroomRosterStore(rootURL: rootURL)
        let source = try store.importCSV(
            preview: RosterCSVPreview(
                headers: ["First", "Last", "ID"],
                rows: [
                    ["Ada", "Lovelace", "A100"],
                    ["Grace", "Hopper", "G200"]
                ],
                mapping: CSVColumnMapping(firstNameIndex: 0, lastNameIndex: 1, officialStudentIDIndex: 2)
            ),
            className: "Period 1"
        )
        let destination = try store.createClassroom(named: "Period 2")
        let movingID = try #require(store.classrooms.first(where: { $0.id == source.id })?.students.first?.id)

        try store.moveStudents([movingID], from: source.id, to: destination.id)

        let updatedSource = try #require(store.classrooms.first { $0.id == source.id })
        let updatedDestination = try #require(store.classrooms.first { $0.id == destination.id })
        #expect(updatedSource.students.count == 1)
        #expect(updatedDestination.students.count == 1)
        #expect(updatedDestination.students[0].id == movingID)
    }

    private func makeTemporaryLessonPackage() throws -> URL {
        let lessonURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MathBoardTests-\(UUID().uuidString).mathboard", isDirectory: true)
        try FileManager.default.createDirectory(
            at: lessonURL.appendingPathComponent("strokes", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: lessonURL.appendingPathComponent("assets", isDirectory: true),
            withIntermediateDirectories: true
        )
        return lessonURL
    }

    private func makeTemporaryDocumentRoot() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MathBoardDocumentWorkflowTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }

    private func makeTemporaryExternalLessonPackage(named name: String) throws -> URL {
        let containerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MathBoardExternalLessonTests-\(UUID().uuidString)", isDirectory: true)
        let packageURL = containerURL.appendingPathComponent("\(name).mathboard", isDirectory: true)
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: packageURL.appendingPathComponent("strokes", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: packageURL.appendingPathComponent("assets", isDirectory: true),
            withIntermediateDirectories: true
        )
        let metadata = DocumentMetadata(id: UUID(), createdAt: Date(), version: DocumentMetadata.currentVersion)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metadata)
        try data.write(to: packageURL.appendingPathComponent("document.json"), options: .atomic)
        return packageURL
    }

    private func readDocumentMetadataID(at packageURL: URL) throws -> UUID {
        let data = try Data(contentsOf: packageURL.appendingPathComponent("document.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DocumentMetadata.self, from: data).id
    }
}
