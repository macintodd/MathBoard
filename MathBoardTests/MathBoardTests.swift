//
//  MathBoardTests.swift
//  MathBoardTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Documents
@testable import Canvas
@testable import Library
@testable import LiveClassroom
@testable import TextEngine
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
                alpha: 1,
                backgroundRed: 1,
                backgroundGreen: 0.92,
                backgroundBlue: 0.25,
                backgroundAlpha: 0.6
            )
        ]

        try PresentationCanvasTextObject.save(textObjects, to: sidecarURL)
        let loaded = PresentationCanvasTextObject.load(from: sidecarURL)

        #expect(loaded == textObjects)
        #expect(loaded.first?.backgroundColorComponents?.alpha == 0.6)
    }

    @Test func missingTextObjectSidecarLoadsAsEmptyArray() {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).textobjects.json")

        #expect(PresentationCanvasTextObject.load(from: missingURL).isEmpty)
    }

    @Test func textEditorOffersTenCuratedFonts() {
        #expect(TextEditorViewModel.availableFonts.count == 10)
        #expect(TextEditorViewModel.availableFonts.contains("Avenir Next"))
        #expect(TextEditorViewModel.availableFonts.contains("Marker Felt"))
    }

    @Test func textEditorResultCarriesTextAndBackgroundColors() {
        let viewModel = TextEditorViewModel(
            text: "Colored text",
            fontSize: 32,
            textColor: TextEditorColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 0.9),
            backgroundColor: TextEditorColor(red: 1, green: 0.9, blue: 0.2, alpha: 0.5)
        )

        let result = viewModel.result

        #expect(result.textColor.red == 0.2)
        #expect(result.textColor.alpha == 0.9)
        #expect(result.backgroundColor?.green == 0.9)
        #expect(result.backgroundColor?.alpha == 0.5)
    }

    @Test func animationSidecarURLUsesDrawingBaseName() {
        let drawingURL = URL(fileURLWithPath: "/tmp/slide-123.drawing")
        let sidecarURL = CanvasAnimationState.sidecarURL(forDrawingURL: drawingURL)

        #expect(sidecarURL.lastPathComponent == "slide-123.animations.json")
        #expect(sidecarURL.deletingLastPathComponent() == drawingURL.deletingLastPathComponent())
    }

    @Test func animationStateUsesExplicitObjectKindIdentity() {
        let sharedID = UUID()
        let textTarget = CanvasAnimatedObjectRef(kind: .text, id: sharedID)
        let imageTarget = CanvasAnimatedObjectRef(kind: .image, id: sharedID)
        var state = CanvasAnimationState()

        state.setPreset(.fade, for: textTarget)
        state.setPreset(.slide, for: imageTarget)

        #expect(state.animation(for: textTarget)?.preset == .fade)
        #expect(state.animation(for: imageTarget)?.preset == .slide)
        #expect(state.animations.count == 2)
    }

    @Test func animationStateIgnoresAndCanCleanMissingTargets() {
        let validTarget = CanvasAnimatedObjectRef(kind: .text, id: UUID())
        let missingTarget = CanvasAnimatedObjectRef(kind: .geometry, id: UUID())
        var state = CanvasAnimationState(animations: [
            CanvasObjectAnimation(target: validTarget, preset: .fade, order: 1),
            CanvasObjectAnimation(target: missingTarget, preset: .scale, order: 2)
        ])

        state.removeMissingTargets(validTargets: [validTarget])

        #expect(state.animation(for: validTarget) != nil)
        #expect(state.animation(for: missingTarget) == nil)
    }

    @Test func animationRenderEffectHidesFutureOrderedObjects() {
        let target = CanvasAnimatedObjectRef(kind: .image, id: UUID())
        let state = CanvasAnimationState(animations: [
            CanvasObjectAnimation(target: target, preset: .fade, order: 2, duration: 1)
        ])

        let effect = state.renderEffect(
            for: target,
            playback: CanvasAnimationPlaybackState(currentStep: 1, isPresenting: true)
        )

        #expect(effect.isVisible == false)
        #expect(effect.opacity == 0)
    }

    @Test func animationRenderEffectReturnsVisibleAfterStepCompletes() {
        let target = CanvasAnimatedObjectRef(kind: .geometry, id: UUID())
        let state = CanvasAnimationState(animations: [
            CanvasObjectAnimation(target: target, preset: .scale, order: 1, duration: 1)
        ])

        let effect = state.renderEffect(
            for: target,
            playback: CanvasAnimationPlaybackState(currentStep: 2, isPresenting: true)
        )

        #expect(effect == .visible)
    }

    @Test func animationNeedsRenderTicksOnlyDuringActiveWindow() {
        let target = CanvasAnimatedObjectRef(kind: .text, id: UUID())
        let state = CanvasAnimationState(animations: [
            CanvasObjectAnimation(target: target, preset: .slide, order: 1, duration: 0.5)
        ])

        let activePlayback = CanvasAnimationPlaybackState(
            currentStep: 1,
            isPresenting: true,
            stepStartedAt: Date()
        )
        let completedPlayback = CanvasAnimationPlaybackState(
            currentStep: 1,
            isPresenting: true,
            stepStartedAt: Date(timeIntervalSinceNow: -2)
        )

        #expect(state.needsRenderTicks(for: .text, playback: activePlayback))
        #expect(!state.needsRenderTicks(for: .text, playback: completedPlayback))
    }

    @Test func textEffectPresetsExposeTeacherFocusedChoices() {
        #expect(CanvasAnimationPreset.textEffectPresets == [
            .typewriter,
            .scrolling,
            .popIn,
            .glowPulse,
            .highlightSweep,
            .fancyTitle
        ])
    }

    @Test func textEffectHiddenOverridesRenderEffect() {
        let textID = UUID()
        let target = CanvasAnimatedObjectRef(kind: .text, id: textID)
        var state = CanvasAnimationState()

        state.setTextEffect(.typewriter, forTextObjectID: textID)
        state.toggleHidden(for: target)

        let effect = state.renderEffect(for: target, playback: CanvasAnimationPlaybackState())
        #expect(effect == .hidden)
    }

    @Test func typewriterEffectReportsTextRevealFractionDuringManualPlayback() {
        let textID = UUID()
        let target = CanvasAnimatedObjectRef(kind: .text, id: textID)
        let startedAt = Date(timeIntervalSince1970: 100)
        var state = CanvasAnimationState(animations: [
            CanvasObjectAnimation(target: target, preset: .typewriter, order: 1, duration: 2)
        ])

        state.playEffect(for: target, now: startedAt)
        let effect = state.renderEffect(
            for: target,
            playback: CanvasAnimationPlaybackState(),
            now: startedAt.addingTimeInterval(1)
        )

        #expect(effect.textRevealFraction == 0.5)
    }

    @Test func loopingTextEffectNeedsTicksOutsidePresentationMode() {
        let textID = UUID()
        let target = CanvasAnimatedObjectRef(kind: .text, id: textID)
        var state = CanvasAnimationState(animations: [
            CanvasObjectAnimation(target: target, preset: .glowPulse, order: 1, duration: 0.5)
        ])

        state.setRepeatMode(.loop, for: target)
        state.playEffect(for: target, now: Date(timeIntervalSince1970: 100))

        #expect(state.needsRenderTicks(
            for: .text,
            playback: CanvasAnimationPlaybackState(),
            now: Date(timeIntervalSince1970: 105)
        ))
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

    #if os(iOS)
    @Test func persistedLiveTeacherInkUsesCrispPenWidth() {
        let stroke = CanvasLiveStroke(
            samples: [
                CanvasLiveStrokePoint(location: CGPoint(x: 0, y: 0)),
                CanvasLiveStrokePoint(location: CGPoint(x: 20, y: 0))
            ],
            lineWidth: 10,
            color: CanvasStrokeColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 1)
        )

        let pointSize = CanvasLiveInkPersistence.persistedStrokePointSize(for: stroke)

        #expect(pointSize.width == 8.2)
        #expect(pointSize.height == 8.2)
    }
    #endif

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
        #expect(object.backgroundColorComponents == nil)
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

    @Test func slideViewportRejectsTopLeftBlueVoidRestore() {
        let viewport = SlideViewportState(
            zoomScale: 0.3,
            contentOffsetX: 0,
            contentOffsetY: 0,
            platform: "iPadOS"
        )

        #expect(!viewport.isUsableSavedCanvasViewport())
    }

    @Test func slideViewportAcceptsCenteredBoardRestore() {
        let viewport = SlideViewportState(
            zoomScale: 0.3,
            contentOffsetX: 520,
            contentOffsetY: 760,
            platform: "iPadOS"
        )

        #expect(viewport.isUsableSavedCanvasViewport())
    }

    @Test func slideViewportRejectsInvalidNumericRestore() {
        let negativeOffset = SlideViewportState(zoomScale: 0.3, contentOffsetX: -1, contentOffsetY: 760)
        let invalidZoom = SlideViewportState(zoomScale: 0, contentOffsetX: 520, contentOffsetY: 760)

        #expect(!negativeOffset.isUsableSavedCanvasViewport())
        #expect(!invalidZoom.isUsableSavedCanvasViewport())
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

    @Test func activityWidgetJSONDecodesInteractiveParts() throws {
        let json = #"""
        {
          "schemaVersion": 2,
          "widgetId": "interactive-parts",
          "activity": "multipleChoice",
          "title": "Interactive Parts",
          "learningObjective": "Decode reusable Mathtivity parts.",
          "questions": [
            {
              "id": "q1",
              "prompt": "Choose the matching graph.",
              "interactiveParts": [
                {
                  "type": "numberLine",
                  "id": "solution-line",
                  "domain": { "min": -5, "max": 5, "step": 1 },
                  "features": {
                    "pointsTappable": true,
                    "pointsDraggable": true,
                    "raysEnabled": true,
                    "segmentsEnabled": true,
                    "openClosedEndpoints": true,
                    "pointHasRay": true,
                    "maxPoints": 2,
                    "labelsVisible": true,
                    "snapToTicks": true
                  }
                },
                {
                  "type": "coordinatePlane",
                  "id": "graph",
                  "domain": { "xMin": 0, "xMax": 10, "yMin": 0, "yMax": 10, "xStep": 1, "yStep": 1 },
                  "features": {
                    "pointsTappable": true,
                    "pointsDraggable": false,
                    "linesEnabled": true,
                    "segmentsEnabled": true,
                    "raysEnabled": false,
                    "parabolasEnabled": false,
                    "labelsVisible": true,
                    "snapToGrid": true
                  }
                }
              ],
              "choices": [
                { "id": "a", "label": "A", "isCorrect": true },
                { "id": "b", "label": "B", "isCorrect": false }
              ]
            }
          ]
        }
        """#

        let result = WidgetActivityJSONCodec.decode(json)
        let parts = try #require(result.document?.questions.first?.interactiveParts)

        #expect(result.errors.isEmpty)
        #expect(parts.count == 2)
        if case .numberLine(let numberLine) = parts[0] {
            #expect(numberLine.id == "solution-line")
            #expect(numberLine.domain.min == -5)
            #expect(numberLine.features.pointsDraggable)
            #expect(numberLine.features.raysEnabled)
            #expect(numberLine.features.pointHasRay)
            #expect(numberLine.features.maxPoints == 2)
        } else {
            Issue.record("Expected first interactive part to be numberLine.")
        }
        if case .coordinatePlane(let coordinatePlane) = parts[1] {
            #expect(coordinatePlane.id == "graph")
            #expect(coordinatePlane.domain.xMin == 0)
            #expect(coordinatePlane.domain.yMax == 10)
            #expect(coordinatePlane.features.linesEnabled)
        } else {
            Issue.record("Expected second interactive part to be coordinatePlane.")
        }
    }

    @Test func activityWidgetJSONRejectsInvalidInteractivePartDomains() {
        let json = #"""
        {
          "schemaVersion": 2,
          "widgetId": "bad-interactive-parts",
          "activity": "multipleChoice",
          "title": "Bad Interactive Parts",
          "learningObjective": "Reject invalid reusable Mathtivity parts.",
          "questions": [
            {
              "id": "q1",
              "prompt": "Choose.",
              "interactiveParts": [
                {
                  "type": "numberLine",
                  "id": "line",
                  "domain": { "min": 5, "max": 5, "step": 1 }
                },
                {
                  "type": "coordinatePlane",
                  "id": "graph",
                  "domain": { "xMin": -10, "xMax": 10, "yMin": 0, "yMax": 10, "xStep": 0, "yStep": 1 }
                }
              ],
              "choices": [
                { "id": "a", "label": "A", "isCorrect": true },
                { "id": "b", "label": "B", "isCorrect": false }
              ]
            }
          ]
        }
        """#

        let result = WidgetActivityJSONCodec.decode(json)

        #expect(result.document == nil)
        #expect(result.errors.contains { $0.contains("numberLine domain min must be less than max") })
        #expect(result.errors.contains { $0.contains("coordinatePlane steps must be greater than 0") })
    }

    @Test func activityWidgetJSONRejectsInvalidNumberLineInteractionFeatures() {
        let json = #"""
        {
          "schemaVersion": 2,
          "widgetId": "bad-number-line-features",
          "activity": "multipleChoice",
          "title": "Bad Number Line Features",
          "learningObjective": "Reject invalid number-line interaction configuration.",
          "questions": [
            {
              "id": "q1",
              "prompt": "Choose.",
              "interactiveParts": [
                {
                  "type": "numberLine",
                  "id": "line",
                  "domain": { "min": -5, "max": 5, "step": 1 },
                  "features": {
                    "pointHasRay": true,
                    "maxPoints": 0
                  },
                  "answer": {
                    "points": [
                      { "value": 1, "isClosed": true }
                    ]
                  }
                }
              ],
              "choices": [
                { "id": "a", "label": "A", "isCorrect": true },
                { "id": "b", "label": "B", "isCorrect": false }
              ]
            }
          ]
        }
        """#

        let result = WidgetActivityJSONCodec.decode(json)

        #expect(result.document == nil)
        #expect(result.errors.contains { $0.contains("numberLine pointHasRay requires raysEnabled") })
        #expect(result.errors.contains { $0.contains("numberLine maxPoints must be greater than 0") })
    }

    @Test func activityWidgetNumberLineAnswerAddsInteractiveScoreRecordPoint() throws {
        let json = #"""
        {
          "schemaVersion": 2,
          "widgetId": "scored-number-line",
          "activity": "multipleChoice",
          "title": "Scored Number Line",
          "learningObjective": "Score a number-line response from JSON.",
          "questions": [
            {
              "id": "q1",
              "prompt": "Graph x >= 2.",
              "interactiveParts": [
                {
                  "type": "numberLine",
                  "id": "solution-line",
                  "domain": { "min": -5, "max": 5, "step": 1 },
                  "features": {
                    "pointsTappable": true,
                    "raysEnabled": true,
                    "openClosedEndpoints": true
                  },
                  "answer": {
                    "rays": [
                      { "endpoint": 2, "direction": "right", "isClosed": true }
                    ]
                  }
                }
              ],
              "choices": [
                { "id": "a", "label": "x \\ge 2", "isCorrect": true },
                { "id": "b", "label": "x \\le 2", "isCorrect": false }
              ]
            }
          ]
        }
        """#
        let document = try #require(WidgetActivityJSONCodec.decode(json).document)
        let runtimeState = WidgetActivityRuntimeState(
            multipleChoice: WidgetMultipleChoiceRuntimeState(
                selectedChoiceID: "a",
                submittedChoiceID: "a",
                submittedChoiceIDsByQuestionID: ["q1": "a"],
                score: 1,
                attempts: 1,
                streak: 1,
                longestStreak: 1,
                answeredQuestionIDs: ["q1"],
                correctlyAnsweredQuestionIDs: ["q1"],
                questionAttempts: ["q1": 1]
            ),
            interactiveParts: WidgetInteractivePartsRuntimeState(
                numberLineResponsesByPartID: [
                    "solution-line": WidgetNumberLineRuntimeResponse(
                        rays: [WidgetActivityNumberLineRay(endpoint: 2, direction: .right, isClosed: true)]
                    )
                ]
            )
        )

        let record = runtimeState.scoreRecord(for: document)

        #expect(record.status == .complete)
        #expect(record.score == 2)
        #expect(record.attempts == 2)
        #expect(record.pointsPossible == 2)
        #expect(record.numberCorrectFirstTry == 2)
    }

    @Test func activityWidgetJSONRejectsEmptyNumberLineAnswer() {
        let json = #"""
        {
          "schemaVersion": 2,
          "widgetId": "empty-answer",
          "activity": "multipleChoice",
          "title": "Empty Answer",
          "learningObjective": "Reject empty interactive answers.",
          "questions": [
            {
              "id": "q1",
              "prompt": "Choose.",
              "interactiveParts": [
                {
                  "type": "numberLine",
                  "id": "line",
                  "domain": { "min": -5, "max": 5, "step": 1 },
                  "answer": {}
                }
              ],
              "choices": [
                { "id": "a", "label": "A", "isCorrect": true },
                { "id": "b", "label": "B", "isCorrect": false }
              ]
            }
          ]
        }
        """#

        let result = WidgetActivityJSONCodec.decode(json)

        #expect(result.document == nil)
        #expect(result.errors.contains { $0.contains("numberLine answer must include at least one point, ray, or segment") })
    }

    @Test func activityWidgetJSONDecodesAuthoredNumberLineGraph() throws {
        let json = #"""
        {
          "schemaVersion": 2,
          "widgetId": "authored-number-line",
          "activity": "multipleChoice",
          "title": "Authored Number Line",
          "learningObjective": "Show authored graph states.",
          "questions": [
            {
              "id": "q1",
              "prompt": "Which inequality matches the graph?",
              "interactiveParts": [
                {
                  "type": "numberLine",
                  "id": "choice-graph",
                  "domain": { "min": -10, "max": 10, "step": 1 },
                  "features": {
                    "segmentsEnabled": true,
                    "openClosedEndpoints": true
                  },
                  "initialResponse": {
                    "points": [
                      { "value": -2, "isClosed": false }
                    ],
                    "segments": [
                      { "start": -2, "end": 5, "startClosed": false, "endClosed": true }
                    ]
                  }
                }
              ],
              "choices": [
                { "id": "a", "label": "-2 < x \\\\le 5", "isCorrect": true },
                { "id": "b", "label": "-2 \\\\le x < 5", "isCorrect": false }
              ]
            }
          ]
        }
        """#

        let result = WidgetActivityJSONCodec.decode(json)
        let part = try #require(result.document?.questions.first?.interactiveParts.first)

        #expect(result.errors.isEmpty)
        if case .numberLine(let numberLine) = part {
            let initialResponse = try #require(numberLine.initialResponse)
            #expect(initialResponse.points == [WidgetActivityNumberLinePoint(value: -2, isClosed: false)])
            #expect(initialResponse.segments == [WidgetActivityNumberLineSegment(start: -2, end: 5, startClosed: false, endClosed: true)])
        } else {
            Issue.record("Expected authored part to be numberLine.")
        }
    }

    @Test func activityWidgetNumberLineUtilityCompilesSimpleAndCompoundGraphs() throws {
        let json = #"""
        {
          "schemaVersion": 2,
          "widgetId": "compiled-number-line-utility",
          "activity": "multipleChoice",
          "title": "Compiled Number Line Utility",
          "learningObjective": "Compile algebraic graph shorthand.",
          "questions": [
            {
              "id": "q1",
              "prompt": "Graph and identify the solution.",
              "interactiveParts": [
                {
                  "type": "numberLine",
                  "id": "right-ray",
                  "domain": { "min": -10, "max": 10, "step": 1 },
                  "features": {
                    "raysEnabled": true,
                    "openClosedEndpoints": true
                  },
                  "initialResponse": "linearGraphUtility{x>1}",
                  "answer": "linearGraphUtility{x≥1}"
                },
                {
                  "type": "numberLine",
                  "id": "bounded",
                  "domain": { "min": -10, "max": 10, "step": 1 },
                  "features": {
                    "segmentsEnabled": true,
                    "openClosedEndpoints": true
                  },
                  "answer": "linearGraphUtility{-2<x<=5}"
                },
                {
                  "type": "numberLine",
                  "id": "point",
                  "domain": { "min": -10, "max": 10, "step": 1 },
                  "features": {
                    "pointsTappable": true
                  },
                  "answer": "linearGraphUtility{3=x}"
                }
              ],
              "choices": [
                { "id": "a", "label": "A", "isCorrect": true },
                { "id": "b", "label": "B", "isCorrect": false }
              ]
            }
          ]
        }
        """#

        let result = WidgetActivityJSONCodec.decode(json)
        let parts = try #require(result.document?.questions.first?.interactiveParts)

        #expect(result.errors.isEmpty)
        if case .numberLine(let rightRay) = parts[0] {
            #expect(rightRay.initialResponse?.rays == [
                WidgetActivityNumberLineRay(endpoint: 1, direction: .right, isClosed: false)
            ])
            #expect(rightRay.answer?.rays == [
                WidgetActivityNumberLineRay(endpoint: 1, direction: .right, isClosed: true)
            ])
        } else {
            Issue.record("Expected first compiled utility part to be numberLine.")
        }
        if case .numberLine(let bounded) = parts[1] {
            #expect(bounded.answer?.segments == [
                WidgetActivityNumberLineSegment(start: -2, end: 5, startClosed: false, endClosed: true)
            ])
        } else {
            Issue.record("Expected second compiled utility part to be numberLine.")
        }
        if case .numberLine(let point) = parts[2] {
            #expect(point.answer?.points == [
                WidgetActivityNumberLinePoint(value: 3, isClosed: true)
            ])
        } else {
            Issue.record("Expected third compiled utility part to be numberLine.")
        }
    }

    @Test func activityWidgetNumberLineAnswerScoresOpenPointAndSegment() throws {
        let json = #"""
        {
          "schemaVersion": 2,
          "widgetId": "segment-number-line",
          "activity": "multipleChoice",
          "title": "Segment Number Line",
          "learningObjective": "Score open and closed graph endpoints.",
          "questions": [
            {
              "id": "q1",
              "prompt": "Graph -2 < x <= 5.",
              "interactiveParts": [
                {
                  "type": "numberLine",
                  "id": "solution-line",
                  "domain": { "min": -10, "max": 10, "step": 1 },
                  "features": {
                    "segmentsEnabled": true,
                    "openClosedEndpoints": true
                  },
                  "answer": {
                    "segments": [
                      { "start": -2, "end": 5, "startClosed": false, "endClosed": true }
                    ]
                  }
                }
              ],
              "choices": [
                { "id": "a", "label": "-2 < x \\\\le 5", "isCorrect": true },
                { "id": "b", "label": "-2 \\\\le x < 5", "isCorrect": false }
              ]
            }
          ]
        }
        """#
        let document = try #require(WidgetActivityJSONCodec.decode(json).document)
        let runtimeState = WidgetActivityRuntimeState(
            multipleChoice: WidgetMultipleChoiceRuntimeState(
                selectedChoiceID: "a",
                submittedChoiceID: "a",
                submittedChoiceIDsByQuestionID: ["q1": "a"],
                score: 1,
                attempts: 1,
                streak: 1,
                longestStreak: 1,
                answeredQuestionIDs: ["q1"],
                correctlyAnsweredQuestionIDs: ["q1"],
                questionAttempts: ["q1": 1]
            ),
            interactiveParts: WidgetInteractivePartsRuntimeState(
                numberLineResponsesByPartID: [
                    "solution-line": WidgetNumberLineRuntimeResponse(
                        segments: [
                            WidgetActivityNumberLineSegment(start: 5, end: -2, startClosed: true, endClosed: false)
                        ]
                    )
                ]
            )
        )

        let record = runtimeState.scoreRecord(for: document)

        #expect(record.status == .complete)
        #expect(record.score == 2)
        #expect(record.pointsPossible == 2)
    }

    @Test func activityWidgetNumberLineRayVisualEndDoesNotAffectScoring() throws {
        let json = #"""
        {
          "schemaVersion": 2,
          "widgetId": "ray-visual-end",
          "activity": "multipleChoice",
          "title": "Ray Visual End",
          "learningObjective": "Score rays by endpoint and direction, not visual handle length.",
          "questions": [
            {
              "id": "q1",
              "prompt": "Graph x > 2.",
              "interactiveParts": [
                {
                  "type": "numberLine",
                  "id": "solution-line",
                  "domain": { "min": -5, "max": 10, "step": 1 },
                  "features": {
                    "pointsTappable": true,
                    "raysEnabled": true,
                    "openClosedEndpoints": true,
                    "pointHasRay": true,
                    "maxPoints": 1
                  },
                  "answer": "linearGraphUtility{x>2}"
                }
              ],
              "choices": [
                { "id": "done", "label": "Done", "isCorrect": true },
                { "id": "revise", "label": "Revise", "isCorrect": false }
              ]
            }
          ]
        }
        """#
        let document = try #require(WidgetActivityJSONCodec.decode(json).document)
        let runtimeState = WidgetActivityRuntimeState(
            multipleChoice: WidgetMultipleChoiceRuntimeState(
                selectedChoiceID: "done",
                submittedChoiceID: "done",
                submittedChoiceIDsByQuestionID: ["q1": "done"],
                score: 1,
                attempts: 1,
                streak: 1,
                longestStreak: 1,
                answeredQuestionIDs: ["q1"],
                correctlyAnsweredQuestionIDs: ["q1"],
                questionAttempts: ["q1": 1]
            ),
            interactiveParts: WidgetInteractivePartsRuntimeState(
                numberLineResponsesByPartID: [
                    "solution-line": WidgetNumberLineRuntimeResponse(
                        rays: [WidgetActivityNumberLineRay(endpoint: 2, direction: .right, isClosed: false, visualEndValue: 6)]
                    )
                ]
            )
        )

        let record = runtimeState.scoreRecord(for: document)

        #expect(record.score == 2)
        #expect(record.pointsPossible == 2)
    }

    @Test func activityWidgetJSONRejectsSegmentWhenSegmentsDisabled() {
        let json = #"""
        {
          "schemaVersion": 2,
          "widgetId": "bad-segment",
          "activity": "multipleChoice",
          "title": "Bad Segment",
          "learningObjective": "Reject disabled segment answers.",
          "questions": [
            {
              "id": "q1",
              "prompt": "Choose.",
              "interactiveParts": [
                {
                  "type": "numberLine",
                  "id": "line",
                  "domain": { "min": -5, "max": 5, "step": 1 },
                  "answer": {
                    "segments": [
                      { "start": -1, "end": 3 }
                    ]
                  }
                }
              ],
              "choices": [
                { "id": "a", "label": "A", "isCorrect": true },
                { "id": "b", "label": "B", "isCorrect": false }
              ]
            }
          ]
        }
        """#

        let result = WidgetActivityJSONCodec.decode(json)

        #expect(result.document == nil)
        #expect(result.errors.contains { $0.contains("numberLine answer includes a segment, but segmentsEnabled is false") })
    }

    @Test func activityWidgetNumberLineLegacySelectedPointsScoreAsClosedPoints() throws {
        let json = #"""
        {
          "schemaVersion": 2,
          "widgetId": "legacy-point",
          "activity": "multipleChoice",
          "title": "Legacy Point",
          "learningObjective": "Keep selectedPoints compatible.",
          "questions": [
            {
              "id": "q1",
              "prompt": "Plot x = 2.",
              "interactiveParts": [
                {
                  "type": "numberLine",
                  "id": "solution-line",
                  "domain": { "min": -5, "max": 5, "step": 1 },
                  "features": { "pointsTappable": true },
                  "answer": {
                    "points": [
                      { "value": 2, "isClosed": true }
                    ]
                  }
                }
              ],
              "choices": [
                { "id": "a", "label": "x = 2", "isCorrect": true },
                { "id": "b", "label": "x = 3", "isCorrect": false }
              ]
            }
          ]
        }
        """#
        let document = try #require(WidgetActivityJSONCodec.decode(json).document)
        let runtimeState = WidgetActivityRuntimeState(
            multipleChoice: WidgetMultipleChoiceRuntimeState(
                selectedChoiceID: "a",
                submittedChoiceID: "a",
                submittedChoiceIDsByQuestionID: ["q1": "a"],
                score: 1,
                attempts: 1,
                streak: 1,
                longestStreak: 1,
                answeredQuestionIDs: ["q1"],
                correctlyAnsweredQuestionIDs: ["q1"],
                questionAttempts: ["q1": 1]
            ),
            interactiveParts: WidgetInteractivePartsRuntimeState(
                numberLineResponsesByPartID: [
                    "solution-line": WidgetNumberLineRuntimeResponse(selectedPoints: [2])
                ]
            )
        )

        let record = runtimeState.scoreRecord(for: document)

        #expect(record.score == 2)
    }

    @Test func fillInTheBlankMathtivityResourceDecodesAsValidActivity() throws {
        let source = try #require(JSONMathtivityCatalog.source(for: JSONMathtivityCatalog.linearEquationFillInTheBlank))
        let result = WidgetActivityJSONCodec.decode(source)
        let document = try #require(result.document)

        #expect(result.errors.isEmpty)
        #expect(document.activity == WidgetActivityKind.fillInTheBlank)
        #expect(document.title == "Equation Blanks")
        #expect(document.questions.count == 4)
        #expect(document.questions.allSatisfy { !$0.blanks.isEmpty })
    }

    @Test func fillInTheBlankSupportsFractionResponseLayout() throws {
        let json = #"""
        {
          "schemaVersion": 1,
          "widgetId": "slope-fraction-layout",
          "activity": "fillInTheBlank",
          "title": "Slope Fraction",
          "learningObjective": "Enter numerator and denominator for a fractional slope.",
          "questions": [
            {
              "id": "q1",
              "prompt": "Enter the slope as a fraction.",
              "expression": "y = \\frac{2}{3}x + 5",
              "responseLayout": {
                "type": "fraction",
                "label": "m =",
                "numeratorBlankId": "numerator",
                "denominatorBlankId": "denominator"
              },
              "blanks": [
                {
                  "id": "numerator",
                  "label": "Numerator",
                  "kind": "numeric",
                  "acceptedAnswers": ["2"],
                  "tolerance": 0
                },
                {
                  "id": "denominator",
                  "label": "Denominator",
                  "kind": "numeric",
                  "acceptedAnswers": ["3"],
                  "tolerance": 0
                }
              ]
            }
          ]
        }
        """#

        let result = WidgetActivityJSONCodec.decode(json)
        let question = try #require(result.document?.questions.first)

        #expect(result.errors.isEmpty)
        #expect(question.responseLayout?.type == .fraction)
        #expect(question.responseLayout?.label == "m =")
        #expect(question.responseLayout?.numeratorBlankId == "numerator")
        #expect(question.responseLayout?.denominatorBlankId == "denominator")
    }

    @Test func fillInTheBlankRejectsFractionResponseLayoutWithMissingBlankIDs() {
        let json = #"""
        {
          "schemaVersion": 1,
          "widgetId": "bad-fraction-layout",
          "activity": "fillInTheBlank",
          "title": "Bad Fraction Layout",
          "learningObjective": "Reject broken response layouts.",
          "questions": [
            {
              "id": "q1",
              "prompt": "Enter the slope.",
              "responseLayout": {
                "type": "fraction",
                "numeratorBlankId": "top",
                "denominatorBlankId": "bottom"
              },
              "blanks": [
                {
                  "id": "numerator",
                  "kind": "numeric",
                  "acceptedAnswers": ["2"]
                },
                {
                  "id": "denominator",
                  "kind": "numeric",
                  "acceptedAnswers": ["3"]
                }
              ]
            }
          ]
        }
        """#

        let result = WidgetActivityJSONCodec.decode(json)

        #expect(result.document == nil)
        #expect(result.errors.contains { $0.contains("numeratorBlankId 'top' must match a blank id") })
        #expect(result.errors.contains { $0.contains("denominatorBlankId 'bottom' must match a blank id") })
    }

    @Test func bundledJSONMathtivitiesPassStandardTestContract() throws {
        for entry in JSONMathtivityCatalog.bundledEntries {
            let source = try #require(JSONMathtivityCatalog.source(for: entry))
            let report = JSONMathtivityTestContract.evaluate(source: source)

            #expect(report.isValid, "Contract failures for \(entry.resourceName): \(report.errors)")
            #expect(report.title == entry.title)
            #expect(report.activityKind != .unknown)
            #expect(report.questionCount > 0)
            #expect(report.pointsPossible > 0)
        }
    }

    @Test func mathtivityCatalogItemParsesFirestoreDocumentShape() throws {
        let item = try #require(MathtivityCatalogItem(
            id: "linear-equation-fill-in-the-blank",
            firestoreData: [
                "title": "Equation Blanks",
                "topic": "Linear Equations",
                "course": "Algebra 1",
                "activityType": "fillInTheBlank",
                "mode": "scored",
                "pedagogicalWorkflow": "assessment",
                "topicLevel": 1,
                "difficulty": "easy",
                "description": "Practice inverse operations.",
                "tags": ["equations", "fill-in-the-blank"],
                "schemaVersion": 1,
                "jsonStoragePath": "jsonMathtivities/linear-equation-fill-in-the-blank.json",
                "thumbnailStoragePath": "jsonMathtivities/thumbnails/linear-equation-fill-in-the-blank.png",
                "isPublished": true,
                "version": 3
            ]
        ))

        #expect(item.title == "Equation Blanks")
        #expect(item.activityType == .fillInTheBlank)
        #expect(item.mode == .scored)
        #expect(item.pedagogicalWorkflow == .assessment)
        #expect(item.resolvedPedagogicalWorkflow == .assessment)
        #expect(item.topicLevel == 1)
        #expect(item.catalogLibraryRecentID == "catalog.linear-equation-fill-in-the-blank")
        #expect(item.jsonStoragePath == "jsonMathtivities/linear-equation-fill-in-the-blank.json")
        #expect(item.version == 3)
    }

    @Test func localCatalogGroupsSystemContentOutsideTeacherLibrary() throws {
        let catalog = MathtivityCatalogLocalRegistry.bundledCatalog

        #expect(catalog.contains { $0.catalogKind == .widgetTemplate })
        #expect(catalog.contains { $0.catalogKind == .builtInInteractive })
        #expect(catalog.contains { $0.catalogKind == .premadeMathtivity })
        #expect(catalog.contains { $0.resolvedPedagogicalWorkflow == .bellRingerExitTicket })
        #expect(catalog.contains { $0.resolvedPedagogicalWorkflow == .conceptualInteractive })
        #expect(catalog.contains { $0.resolvedPedagogicalWorkflow == .assessment })
        #expect(catalog.contains { $0.resolvedPedagogicalWorkflow == .tools })
        #expect(catalog.contains { $0.resolvedPedagogicalWorkflow == .classPlay })
        #expect(MathtivityCatalogLocalRegistry.builtInInteractives.first { $0.builtInKind == .actDailyPractice }?.resolvedPedagogicalWorkflow == .bellRingerExitTicket)
        #expect(MathtivityCatalogLocalRegistry.builtInInteractives.first { $0.builtInKind == .inequalitiesExplorer }?.resolvedPedagogicalWorkflow == .assessment)
        #expect(MathtivityCatalogLocalRegistry.builtInInteractives.first { $0.builtInKind == .functionTransformationExplorer }?.resolvedPedagogicalWorkflow == .conceptualInteractive)
        #expect(MathtivityCatalogLocalRegistry.builtInInteractives.first { $0.builtInKind == .coordinateGridGenerator }?.resolvedPedagogicalWorkflow == .tools)
        #expect(MathtivityCatalogLocalRegistry.builtInInteractives.first { $0.builtInKind == .countdownTimer }?.resolvedPedagogicalWorkflow == .tools)
        #expect(MathtivityCatalogLocalRegistry.builtInInteractives.first { $0.builtInKind == .randomNumberGenerator }?.resolvedPedagogicalWorkflow == .tools)
        #expect(MathtivityCatalogLocalRegistry.builtInInteractives.first { $0.builtInKind == .matchGrid }?.resolvedPedagogicalWorkflow == .classPlay)
        #expect(catalog.allSatisfy { $0.source == .bundled })
        #expect(MathtivityCatalogLocalRegistry.bundledPremadeMathtivities.count == JSONMathtivityCatalog.bundledEntries.count)
    }

    @Test func localWidgetTemplateCatalogItemsProvideValidActivityJSON() throws {
        for item in MathtivityCatalogLocalRegistry.widgetTemplates {
            let source = try #require(MathtivityCatalogLocalRegistry.source(for: item))
            let report = JSONMathtivityTestContract.evaluate(
                source: source,
                expectedActivityKind: item.activityType.widgetActivityKind
            )

            #expect(report.isValid, "Template failures for \(item.id): \(report.errors)")
            #expect(report.questionCount == item.questionCount)
        }
    }

    @Test func builtInInteractiveCatalogItemProvidesMarkerPayload() throws {
        let items = MathtivityCatalogLocalRegistry.builtInInteractives

        #expect(items.map(\.builtInKind).contains(.inequalitiesExplorer))
        #expect(items.map(\.builtInKind).contains(.countdownTimer))
        #expect(items.map(\.builtInKind).contains(.randomNumberGenerator))
        #expect(items.map(\.builtInKind).contains(.coordinateGridGenerator))
        #expect(items.map(\.builtInKind).contains(.actDailyPractice))

        for item in items {
            let source = try #require(MathtivityCatalogLocalRegistry.source(for: item))
            let kind = try #require(item.builtInKind)

            #expect(item.catalogKind == .builtInInteractive)
            #expect(source == kind.widgetCodeString)
        }
    }

    @Test func nonScoreableBuiltInUtilitiesDoNotPublishScoreRecords() {
        for kind in [
            BuiltInInteractiveKind.countdownTimer,
            BuiltInInteractiveKind.randomNumberGenerator,
            BuiltInInteractiveKind.coordinateGridGenerator,
            BuiltInInteractiveKind.functionTransformationExplorer,
            BuiltInInteractiveKind.matchGrid
        ] {
            let widget = WidgetObject(
                name: kind.displayName,
                codeString: kind.widgetCodeString,
                frame: .zero
            )

            #expect(!kind.isScoreable)
            #expect(widget.activityScoreRecord == nil)
        }
    }

    @Test func conceptualJSONActivitiesDoNotPublishScoreRecords() throws {
        let source = #"""
        {
          "schemaVersion": 1,
          "widgetId": "conceptual-number-line",
          "activity": "multipleChoice",
          "title": "Explore the Number Line",
          "learningObjective": "Students explore equivalent locations without submitting a score.",
          "pedagogicalWorkflow": "conceptualInteractive",
          "rules": {
            "scoreMode": "correctOutOfAttempted",
            "advanceMode": "manual"
          },
          "questions": [
            {
              "id": "q1",
              "prompt": "Move points to compare values.",
              "choices": [
                { "id": "a", "label": "Ready", "isCorrect": true },
                { "id": "b", "label": "Not ready", "isCorrect": false }
              ]
            }
          ]
        }
        """#
        let document = try #require(WidgetActivityJSONCodec.decode(source).document)
        let widget = WidgetObject(
            name: document.title,
            codeString: source,
            frame: .zero
        )

        #expect(document.pedagogicalWorkflow == .conceptualInteractive)
        #expect(widget.activityScoreRecord == nil)
        #expect(WidgetActivityScoreSheet(widgets: [widget]).records.isEmpty)
    }

    @Test func bundledACTDailyPracticeBankPassesValidation() throws {
        let bank = ACTDailyPracticeQuestionBank.bundled
        let errors = ACTDailyPracticeQuestionBank.validationErrors(for: bank)

        #expect(bank.questions.count == 180)
        #expect(errors.isEmpty, "ACT Daily Practice bank validation failures: \(errors)")
        #expect(Set(bank.questions.map(\.day)) == Set(1...180))
        #expect(bank.questions.allSatisfy { $0.choices.map(\.id) == ["A", "B", "C", "D"] })
    }

    @MainActor
    @Test func actDailyPracticeStateFiltersAndAdvancesToUnusedQuestion() throws {
        let testRunID = UUID().uuidString
        let firstQuestionID = "act-test-\(testRunID)-001"
        let secondQuestionID = "act-test-\(testRunID)-002"
        let bank = ACTDailyPracticeBank(
            title: "ACT Math Daily Practice",
            version: 1,
            subject: "ACT Math",
            questions: [
                ACTDailyPracticeQuestion(
                    id: firstQuestionID,
                    day: 1,
                    domain: "Algebra",
                    skill: "linear equations",
                    difficulty: "easy",
                    prompt: "Solve x + 1 = 3.",
                    choices: [
                        ACTDailyPracticeChoice(id: "A", text: "1"),
                        ACTDailyPracticeChoice(id: "B", text: "2"),
                        ACTDailyPracticeChoice(id: "C", text: "3"),
                        ACTDailyPracticeChoice(id: "D", text: "4")
                    ],
                    correctChoiceID: "B",
                    explanation: "Subtract 1 from both sides."
                ),
                ACTDailyPracticeQuestion(
                    id: secondQuestionID,
                    day: 2,
                    domain: "Geometry",
                    skill: "area",
                    difficulty: "easy",
                    prompt: "Find the area of a 3 by 4 rectangle.",
                    choices: [
                        ACTDailyPracticeChoice(id: "A", text: "7"),
                        ACTDailyPracticeChoice(id: "B", text: "10"),
                        ACTDailyPracticeChoice(id: "C", text: "12"),
                        ACTDailyPracticeChoice(id: "D", text: "14")
                    ],
                    correctChoiceID: "C",
                    explanation: "Area is length times width."
                )
            ]
        )
        let state = ACTDailyPracticeState(bank: bank)

        #expect(state.selectedQuestion?.id == firstQuestionID)
        state.nextUnusedQuestion()
        #expect(state.selectedQuestion?.id == secondQuestionID)

        state.searchText = "linear"
        state.selectedDomain = "Algebra"
        #expect(state.filteredQuestions.map(\.id) == [firstQuestionID])
    }

    @MainActor
    @Test func actDailyPracticeScoreRecordReportsCurrentQuestionProgress() throws {
        let widgetID = try #require(UUID(uuidString: "55555555-5555-5555-5555-555555555555"))
        let question = ACTDailyPracticeQuestion(
            id: "act-score-unique-001",
            day: 1,
            domain: "Algebra",
            skill: "linear equations",
            difficulty: "easy",
            prompt: "Solve x + 1 = 3.",
            choices: [
                ACTDailyPracticeChoice(id: "A", text: "1"),
                ACTDailyPracticeChoice(id: "B", text: "2"),
                ACTDailyPracticeChoice(id: "C", text: "3"),
                ACTDailyPracticeChoice(id: "D", text: "4")
            ],
            correctChoiceID: "B",
            explanation: "Subtract 1 from both sides."
        )
        let state = ACTDailyPracticeState(
            bank: ACTDailyPracticeBank(
                title: "ACT Math Daily Practice",
                version: 1,
                subject: "ACT Math",
                questions: [question]
            )
        )

        #expect(BuiltInInteractiveKind.actDailyPractice.isScoreable)
        #expect(BuiltInInteractiveKind.actDailyPractice.pointsPossible == 1)
        #expect(state.scoreRecord(widgetID: widgetID, title: "").status == .notStarted)

        state.selectChoice("B")
        let record = state.scoreRecord(widgetID: widgetID, title: "")
        #expect(record.status == .complete)
        #expect(record.score == 1)
        #expect(record.points == 1)
        #expect(record.pointsPossible == 1)
        #expect(record.numberCorrectFirstTry == 1)
    }

    @Test func mathtivityCatalogItemParsesFirestoreBuiltInShape() throws {
        let item = try #require(MathtivityCatalogItem(
            id: "builtin-inequalities-explorer",
            firestoreData: [
                "title": "Inequality Explorer",
                "catalogKind": "builtInInteractive",
                "builtInKind": "inequalitiesExplorer",
                "topic": "Built-In Interactives",
                "isPublished": true
            ]
        ))

        #expect(item.catalogKind == .builtInInteractive)
        #expect(item.source == .firebase)
        #expect(item.builtInKind == .inequalitiesExplorer)
        #expect(item.jsonStoragePath == "builtin://inequalitiesExplorer")
    }

    @Test func fillInTheBlankAnswerCheckerMatchesTextAndNumericAnswers() {
        let numericBlank = WidgetActivityBlank(
            id: "x",
            kind: .numeric,
            acceptedAnswers: ["\\frac{1}{2}"],
            tolerance: 0.0001
        )
        let textBlank = WidgetActivityBlank(
            id: "operation",
            kind: .text,
            acceptedAnswers: ["subtract 2"],
            caseSensitive: false
        )

        #expect(WidgetActivityAnswerChecker.response("0.5", matches: numericBlank))
        #expect(WidgetActivityAnswerChecker.response(" Subtract   2 ", matches: textBlank))
        #expect(!WidgetActivityAnswerChecker.response("add 2", matches: textBlank))
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

    @Test func widgetJSONRepairNormalizesSmartQuotesFromAIPaste() {
        let json = """
        { “schemaVersion”: 1, “widgetId”: “smart-quotes”, “activity”: “multipleChoice”, “title”: “Smart Quotes”, “questions”: [] }
        """

        let repaired = WidgetJSONRepair.escapingUnescapedLaTeXCommands(in: json)

        #expect(repaired.contains(#""schemaVersion": 1"#))
        #expect(repaired.contains(#""widgetId": "smart-quotes""#))
        #expect(!repaired.contains("“"))
        #expect(!repaired.contains("”"))
    }

    @Test func activityWidgetJSONRepairsAIAuthoredFillInBlankLatexAndDanglingBlankMarker() throws {
        let json = #"""
        {
          “schemaVersion”: 1,
          “widgetId”: “slope-from-slope-intercept-form-level-1”,
          “activity”: “fillInTheBlank”,
          “title”: “Identify the Slope”,
          “learningObjective”: “Identify the fractional slope m in an equation written in the form y = mx + b.”,
          “questions”: [
            {
              “id”: “q1”,
              “prompt”: “Enter the slope as a fraction in simplest form.”,
              “expression”: “y = \frac{2}{3}x + 5,\quad m = \”,
              “blanks”: [
                {
                  “id”: “slope”,
                  “label”: “Slope”,
                  “kind”: “text”,
                  “acceptedAnswers”: [“2/3”, “2 / 3”],
                  “caseSensitive”: false
                }
              ],
              “hints”: [
                “Slope-intercept form is y = mx + b.”
              ],
              “correctFeedback”: “Correct. The coefficient of x is 2/3.”,
              “incorrectFeedback”: “Look at the fraction directly in front of x.”,
              “explanation”: “In y = mx + b, m is the slope.”
            }
          ]
        }
        """#

        let result = WidgetActivityJSONCodec.decode(json)
        let document = try #require(result.document)
        let expression = try #require(document.questions.first?.expression)

        #expect(result.errors.isEmpty)
        #expect(document.activity == WidgetActivityKind.fillInTheBlank)
        #expect(expression.contains(#"\frac{2}{3}"#))
        #expect(expression.contains(#"\quad"#))
        #expect(expression.hasSuffix(#"\_"#))
    }

    @Test func multipleChoicePromptUsesStarterContractAndHidesVisualSettings() {
        let prompt = WidgetMathtivityPromptFactory.prompt(
            for: .multipleChoice,
            intent: .create
        )

        #expect(prompt.contains("MathBoard Multiple Choice JSON bell ringer or exit ticket"))
        #expect(prompt.contains(#"activity as "multipleChoice""#))
        #expect(prompt.contains("Mark exactly one choice per question with isCorrect: true."))
        #expect(prompt.contains("Use plain ASCII straight double quotes"))
        #expect(prompt.contains(#"Write \\frac, \\quad, and \\_ in JSON"#))
        #expect(prompt.contains("Do not add teacher-facing theme, experience, CSS, scoring visual"))
        #expect(prompt.contains("Generate exactly one question"))
        #expect(prompt.contains(#"pedagogicalWorkflow": "bellRingerExitTicket""#))
        #expect(prompt.contains("associatedClass"))
        #expect(prompt.contains("Single-question starter JSON structure for Multiple Choice:"))
    }

    @Test func fillInTheBlankPromptAppendsCatalogJSONForRemix() throws {
        let source = try #require(JSONMathtivityCatalog.source(for: JSONMathtivityCatalog.linearEquationFillInTheBlank))

        let prompt = WidgetMathtivityPromptFactory.prompt(
            for: .fillInTheBlank,
            intent: .remix(sourceJSON: source)
        )

        #expect(prompt.contains("MathBoard Fill in the Blank JSON mathtivity"))
        #expect(prompt.contains(#"activity as "fillInTheBlank""#))
        #expect(prompt.contains("Use blanks instead of choices."))
        #expect(prompt.contains(#""type": "fraction""#))
        #expect(prompt.contains("numeratorBlankId"))
        #expect(prompt.contains("Existing JSON mathtivity to revise:"))
        #expect(prompt.contains(source))
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
    @Test func slideStoreMergeTeacherSlidesReportsBackgroundChanges() throws {
        let lessonURL = try makeTemporaryLessonPackage()
        defer { try? FileManager.default.removeItem(at: lessonURL) }
        let store = SlideStore(lessonURL: lessonURL)
        let originalSlide = try #require(store.slides.first)

        var teacherSlide = originalSlide
        teacherSlide.background = SlideBackground(
            kind: .pdfPage,
            assetFileName: "teacher-added.pdf",
            pageIndex: 0
        )

        #expect(store.mergeTeacherSlides([teacherSlide]))
        #expect(store.slides.first?.background == teacherSlide.background)
        #expect(!store.mergeTeacherSlides([teacherSlide]))
    }

    @MainActor
    @Test func slideStoreMergeTeacherSlidesAddsTeacherSlidesBeforeRemainingLocalSlides() throws {
        let lessonURL = try makeTemporaryLessonPackage()
        defer { try? FileManager.default.removeItem(at: lessonURL) }
        let store = SlideStore(lessonURL: lessonURL)
        let localSlide = try #require(store.slides.first)
        let teacherSlide = SlideMetadata(
            background: SlideBackground(
                kind: .pdfPage,
                assetFileName: "new-page.pdf",
                pageIndex: 0
            )
        )

        #expect(store.mergeTeacherSlides([teacherSlide]))
        #expect(store.slides.map(\.id) == [teacherSlide.id, localSlide.id])
    }

    @MainActor
    @Test func slideStoreMergeTeacherSlidesRemovesDeferredTeacherPlaceholders() throws {
        let lessonURL = try makeTemporaryLessonPackage()
        defer { try? FileManager.default.removeItem(at: lessonURL) }
        let store = SlideStore(lessonURL: lessonURL)
        let localSlide = try #require(store.slides.first)
        let deferredTeacherSlide = SlideMetadata(
            background: SlideBackground(
                kind: .pdfPage,
                assetFileName: "missing-live.pdf",
                pageIndex: 0
            )
        )

        #expect(store.mergeTeacherSlides([deferredTeacherSlide]))
        #expect(store.slides.map(\.id) == [deferredTeacherSlide.id, localSlide.id])
        #expect(store.mergeTeacherSlides([], deferredTeacherSlideIDs: [deferredTeacherSlide.id]))
        #expect(store.slides.map(\.id) == [localSlide.id])
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
    @Test func mathBoardPackageArchiveRoundTripsPackageFiles() throws {
        let sourceURL = try makeTemporaryExternalLessonPackage(named: "Teacher MathBoard")
        let restoreRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MathBoardArchiveRestore-\(UUID().uuidString)", isDirectory: true)
        let restoredURL = restoreRootURL.appendingPathComponent("Restored.mathboard", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: sourceURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: restoreRootURL)
        }

        let archiveData = try MathBoardPackageArchiver().archivePackage(at: sourceURL)
        try FileManager.default.createDirectory(at: restoreRootURL, withIntermediateDirectories: true)
        try MathBoardPackageArchiver().restorePackage(from: archiveData, to: restoredURL)

        #expect(try readDocumentMetadataID(at: restoredURL) == readDocumentMetadataID(at: sourceURL))
        #expect(try Data(contentsOf: restoredURL.appendingPathComponent("assets/sample.txt")) == Data("sample".utf8))
        #expect(MathBoardPackageArchiver.checksum(for: archiveData).count == 64)
    }

    @MainActor
    @Test func documentStoreImportsSharedLessonArchiveIntoAssignedLessonsAndKeepsIdentity() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        let sourceURL = try makeTemporaryExternalLessonPackage(named: "Teacher MathBoard")
        defer {
            try? FileManager.default.removeItem(at: rootURL)
            try? FileManager.default.removeItem(at: sourceURL.deletingLastPathComponent())
        }
        let store = DocumentStore(rootURL: rootURL)
        let sourceID = try readDocumentMetadataID(at: sourceURL)
        let archiveData = try MathBoardPackageArchiver().archivePackage(at: sourceURL)

        let imported = try store.importSharedLessonPackageArchive(
            archiveData,
            suggestedFileName: "Teacher MathBoard.mathboard"
        )

        #expect(imported.id == sourceID)
        #expect(imported.name == "Teacher MathBoard")
        #expect(imported.url.deletingLastPathComponent().lastPathComponent == "Assigned Lessons")
        #expect(store.allLessons().map(\.id).contains(sourceID))
    }

    @MainActor
    @Test func documentStoreCreatesStableStudentWorkingCopiesForAssignedLessons() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        let sourceURL = try makeTemporaryExternalLessonPackage(named: "Teacher MathBoard")
        defer {
            try? FileManager.default.removeItem(at: rootURL)
            try? FileManager.default.removeItem(at: sourceURL.deletingLastPathComponent())
        }
        let store = DocumentStore(rootURL: rootURL)
        let archiveData = try MathBoardPackageArchiver().archivePackage(at: sourceURL)
        let imported = try store.importSharedLessonPackageArchive(
            archiveData,
            suggestedFileName: "Teacher MathBoard.mathboard"
        )
        let assignmentID = UUID()

        let firstStudentCopy = try store.studentAssignedLessonWorkingCopy(
            for: imported,
            assignmentID: assignmentID,
            studentIdentifier: "student/one"
        )
        let firstStudentCopyAgain = try store.studentAssignedLessonWorkingCopy(
            for: imported,
            assignmentID: assignmentID,
            studentIdentifier: "student/one"
        )
        let secondStudentCopy = try store.studentAssignedLessonWorkingCopy(
            for: imported,
            assignmentID: assignmentID,
            studentIdentifier: "student/two"
        )

        #expect(firstStudentCopy.url == firstStudentCopyAgain.url)
        #expect(firstStudentCopy.url != imported.url)
        #expect(firstStudentCopy.url != secondStudentCopy.url)
        #expect(firstStudentCopy.url.deletingLastPathComponent().lastPathComponent == "Student Work")
        #expect(try readDocumentMetadataID(at: firstStudentCopy.url) == imported.id)
        #expect(try readDocumentMetadataID(at: secondStudentCopy.url) == imported.id)
    }

    @Test func lessonPackageManifestKeepsPublishedVersionMetadata() throws {
        let lessonID = UUID()
        let versionID = UUID()
        let publishedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let manifest = LessonPackageManifest(
            id: lessonID,
            title: "Quadratic Formula",
            versionID: versionID,
            versionNumber: 3,
            packageFileName: "Quadratic Formula.mathboard",
            packageStoragePath: "teacherLessonPackages/teacher/\(lessonID.uuidString)/versions/\(versionID.uuidString)/package.mathboardpkg",
            packageChecksum: String(repeating: "a", count: 64),
            publishedAt: publishedAt
        )

        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(LessonPackageManifest.self, from: data)

        #expect(decoded.id == lessonID)
        #expect(decoded.versionID == versionID)
        #expect(decoded.versionNumber == 3)
        #expect(decoded.publishedAt == publishedAt)
        #expect(decoded.packageStoragePath == manifest.packageStoragePath)
    }

    @MainActor
    @Test func documentStoreRecordsPublishedVersionAndDetectsSourceChanges() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = DocumentStore(rootURL: rootURL)
        let folder = try store.createFolder(named: "Algebra 2")
        let lesson = try store.createLesson(named: "Quadratic Formula", in: folder)
        let checksum = try store.sourceContentChecksum(for: lesson)
        let manifest = LessonPackageManifest(
            id: lesson.id,
            title: lesson.name,
            versionID: UUID(),
            versionNumber: 2,
            packageFileName: lesson.url.lastPathComponent,
            packageStoragePath: "teacherLessonPackages/teacher/\(lesson.id.uuidString)/versions/package.mathboardpkg",
            packageChecksum: checksum,
            publishedAt: Date(timeIntervalSince1970: 1_800_000_100)
        )

        let publishedLesson = try store.recordPublishedVersion(manifest, sourceContentChecksum: checksum, for: lesson)
        let reloadedLesson = try #require(store.allLessons().first { $0.id == lesson.id })

        #expect(publishedLesson.publishedVersion?.versionNumber == 2)
        #expect(reloadedLesson.publishedVersion?.sourceContentChecksum == checksum)
        #expect(!store.hasUnpublishedChanges(reloadedLesson))

        let assetsURL = lesson.url.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        try "changed".write(
            to: assetsURL.appendingPathComponent("change.txt"),
            atomically: true,
            encoding: .utf8
        )

        #expect(store.hasUnpublishedChanges(reloadedLesson))
    }

    @MainActor
    @Test func mathBoardPackageArchiveIgnoresPublishedVersionMetadata() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = DocumentStore(rootURL: rootURL)
        let folder = try store.createFolder(named: "Algebra 2")
        let lesson = try store.createLesson(named: "Factoring", in: folder)
        let checksum = try store.sourceContentChecksum(for: lesson)
        let manifest = LessonPackageManifest(
            id: lesson.id,
            title: lesson.name,
            versionID: UUID(),
            versionNumber: 1,
            packageFileName: lesson.url.lastPathComponent,
            packageStoragePath: "teacherLessonPackages/teacher/\(lesson.id.uuidString)/versions/package.mathboardpkg",
            packageChecksum: checksum,
            publishedAt: Date(timeIntervalSince1970: 1_800_000_200)
        )

        _ = try store.recordPublishedVersion(manifest, sourceContentChecksum: checksum, for: lesson)
        let checksumAfterRecordingPublish = try store.sourceContentChecksum(for: lesson)

        #expect(checksumAfterRecordingPublish == checksum)
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

    @MainActor
    @Test func classroomRosterStoreDeletesOneStudentAndPersistsRoster() throws {
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
        let deletingID = try #require(store.classrooms.first(where: { $0.id == classroom.id })?.students.first?.id)

        try store.deleteStudents([deletingID], from: classroom.id)

        let reloadedStore = ClassroomRosterStore(rootURL: rootURL)
        let reloadedClassroom = try #require(reloadedStore.classrooms.first { $0.id == classroom.id })
        #expect(reloadedClassroom.students.count == 1)
        #expect(!reloadedClassroom.students.contains { $0.id == deletingID })
    }

    @MainActor
    @Test func classroomRosterStoreReportsMissingStudentForDeleteAndMove() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = ClassroomRosterStore(rootURL: rootURL)
        let source = try store.createClassroom(named: "Period 1")
        let destination = try store.createClassroom(named: "Period 2")
        let missingID = UUID()

        do {
            try store.deleteStudents([missingID], from: source.id)
            Issue.record("Deleting a missing student should throw.")
        } catch ClassroomRosterStoreError.studentNotFound {
        } catch {
            Issue.record("Deleting a missing student threw an unexpected error: \(error)")
        }

        do {
            try store.moveStudents([missingID], from: source.id, to: destination.id)
            Issue.record("Moving a missing student should throw.")
        } catch ClassroomRosterStoreError.studentNotFound {
        } catch {
            Issue.record("Moving a missing student threw an unexpected error: \(error)")
        }
    }

    @MainActor
    @Test func classroomRosterStoreImportsCSVIntoExistingClassAndSortsCombinedRoster() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = ClassroomRosterStore(rootURL: rootURL)
        let classroom = try store.importCSV(
            preview: RosterCSVPreview(
                headers: ["First", "Last", "ID"],
                rows: [
                    ["Grace", "Hopper", "G200"],
                    ["Katherine", "Johnson", "K300"]
                ],
                mapping: CSVColumnMapping(firstNameIndex: 0, lastNameIndex: 1, officialStudentIDIndex: 2)
            ),
            className: "Period 1"
        )
        let importPreview = RosterCSVPreview(
            headers: ["First", "Last", "ID"],
            rows: [
                ["Ada", "Lovelace", "A100"],
                ["Dorothy", "Vaughan", "D400"]
            ],
            mapping: CSVColumnMapping(firstNameIndex: 0, lastNameIndex: 1, officialStudentIDIndex: 2)
        )

        try store.importCSV(preview: importPreview, into: classroom.id)

        let updatedClassroom = try #require(store.classrooms.first { $0.id == classroom.id })
        #expect(updatedClassroom.students.map(\.lastName) == ["Hopper", "Johnson", "Lovelace", "Vaughan"])
    }

    @MainActor
    @Test func classroomRosterStoreParsesQuotedCSVAndInfersAlternateHeader() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = ClassroomRosterStore(rootURL: rootURL)
        let csvURL = rootURL.appendingPathComponent("Quoted.csv")
        try """
        First,Last,ID,Alternate
        Ada,"Lovelace, Jr.",A100,ALT-1
        Grace,Hopper,G200,ALT-2
        """.write(to: csvURL, atomically: true, encoding: .utf8)

        let preview = try store.previewCSV(at: csvURL)
        let classroom = try store.importCSV(preview: preview, className: "Period 3")

        #expect(preview.mapping.alternateStudentIDIndex == 3)
        #expect(classroom.students.first(where: { $0.firstName == "Ada" })?.lastName == "Lovelace, Jr.")
        #expect(classroom.students.first(where: { $0.firstName == "Grace" })?.alternateStudentID == "ALT-2")
    }

    @MainActor
    @Test func classroomRosterStoreReportsDuplicateOfficialAndAlternateIDs() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = ClassroomRosterStore(rootURL: rootURL)
        let classroom = try store.importCSV(
            preview: RosterCSVPreview(
                headers: ["First", "Last", "ID", "Alternate"],
                rows: [
                    ["Ada", "Lovelace", "a100", "ALT-1"],
                    ["Grace", "Hopper", "A100", "alt-1"],
                    ["Katherine", "Johnson", "K300", ""]
                ],
                mapping: CSVColumnMapping(firstNameIndex: 0, lastNameIndex: 1, officialStudentIDIndex: 2, alternateStudentIDIndex: 3)
            ),
            className: "Period 1"
        )

        let report = try store.duplicateIDReport(for: classroom.id)

        #expect(report.officialStudentIDs == ["A100"])
        #expect(report.alternateStudentIDs == ["ALT-1"])
        #expect(report.hasDuplicates)
    }

    @MainActor
    @Test func classroomRosterStoreReportsDuplicateIDsInCSVPreview() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = ClassroomRosterStore(rootURL: rootURL)
        let preview = RosterCSVPreview(
            headers: ["First", "Last", "ID", "Alternate"],
            rows: [
                ["Ada", "Lovelace", "A100", "ALT-1"],
                ["Grace", "Hopper", "A100", "ALT-2"],
                ["Dorothy", "Vaughan", "D400", "alt-2"]
            ],
            mapping: CSVColumnMapping(firstNameIndex: 0, lastNameIndex: 1, officialStudentIDIndex: 2, alternateStudentIDIndex: 3)
        )

        let report = store.duplicateIDReport(for: preview)

        #expect(report.officialStudentIDs == ["A100"])
        #expect(report.alternateStudentIDs == ["ALT-2"])
    }

    @MainActor
    @Test func classroomRosterStorePreventsGeneratedAlternateIDCollision() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = ClassroomRosterStore(rootURL: rootURL)
        let classroom = try store.importCSV(
            preview: RosterCSVPreview(
                headers: ["First", "Last", "ID", "Alternate"],
                rows: [
                    ["Ada", "Lovelace", "A100", ""],
                    ["Grace", "Hopper", "G200", "ALG2-002"]
                ],
                mapping: CSVColumnMapping(firstNameIndex: 0, lastNameIndex: 1, officialStudentIDIndex: 2, alternateStudentIDIndex: 3)
            ),
            className: "Algebra 2"
        )

        do {
            try store.generateAlternateIDs(for: classroom.id)
            Issue.record("Generating alternate IDs should fail when it would create a duplicate.")
        } catch ClassroomRosterStoreError.duplicateAlternateStudentID {
        } catch {
            Issue.record("Generating alternate IDs threw an unexpected error: \(error)")
        }

        let students = try #require(store.classrooms.first?.students)
        #expect(students.first(where: { $0.lastName == "Lovelace" })?.alternateStudentID == "")
        #expect(students.first(where: { $0.lastName == "Hopper" })?.alternateStudentID == "ALG2-002")
    }

    @MainActor
    @Test func classroomAssignmentStoreCreatesAssignmentsWithUniqueCodesAndPersists() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        var generatedCodes = ["same-code", "same-code", "period-two"]
        let store = ClassroomAssignmentStore(rootURL: rootURL) {
            generatedCodes.removeFirst()
        }
        let lesson = Lesson(
            id: UUID(),
            name: "Quadratics Review",
            url: rootURL.appendingPathComponent("Quadratics Review.mathboard", isDirectory: true),
            createdAt: Date(),
            modifiedAt: Date()
        )
        let firstClassID = UUID()
        let secondClassID = UUID()
        let widget = AssignedWidgetSummary(widgetID: UUID(), title: "Factoring", maxScore: 5)

        let assignments = try store.createAssignments(
            for: lesson,
            classroomIDs: [firstClassID, secondClassID, firstClassID],
            widgetSummaries: [widget]
        )
        let reloadedStore = ClassroomAssignmentStore(rootURL: rootURL)

        #expect(assignments.count == 2)
        #expect(Set(assignments.map(\.classLessonCode)).count == 2)
        #expect(assignments.map(\.classLessonCode) == ["SAMECODE", "PERIODTW"])
        #expect(assignments.map(\.lessonID) == [lesson.id, lesson.id])
        #expect(reloadedStore.assignments.map(\.id) == assignments.map(\.id))
    }

    @MainActor
    @Test func classroomAssignmentStoreGeneratesSixCharacterLessonCodes() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = ClassroomAssignmentStore(rootURL: rootURL)
        let lesson = Lesson(
            id: UUID(),
            name: "Short Code Practice",
            url: rootURL.appendingPathComponent("Short Code Practice.mathboard", isDirectory: true),
            createdAt: Date(),
            modifiedAt: Date()
        )

        let assignment = try #require(store.createAssignments(
            for: lesson,
            classroomIDs: [UUID()],
            widgetSummaries: [AssignedWidgetSummary(widgetID: UUID(), title: "Widget", maxScore: 5)]
        ).first)

        #expect(assignment.classLessonCode.count == 6)
    }

    @MainActor
    @Test func classroomAssignmentStorePersistsPublishedVersionMetadata() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = ClassroomAssignmentStore(rootURL: rootURL) { "ALG010" }
        let lessonID = UUID()
        let versionID = UUID()
        let lesson = Lesson(
            id: lessonID,
            name: "Versioned Assignment",
            url: rootURL.appendingPathComponent("Versioned Assignment.mathboard", isDirectory: true),
            createdAt: Date(),
            modifiedAt: Date()
        )
        let manifest = LessonPackageManifest(
            id: lessonID,
            title: lesson.name,
            versionID: versionID,
            versionNumber: 1,
            packageFileName: "Versioned Assignment.mathboard",
            packageStoragePath: "teacherLessonPackages/teacher/\(lessonID.uuidString)/versions/\(versionID.uuidString)/package.mathboardpkg",
            packageChecksum: String(repeating: "b", count: 64),
            publishedAt: Date(timeIntervalSince1970: 1_800_000_300)
        )

        _ = try store.createAssignments(
            for: lesson,
            classroomIDs: [UUID()],
            widgetSummaries: [AssignedWidgetSummary(widgetID: UUID(), title: "Widget", maxScore: 5)],
            lessonManifest: manifest
        )
        let reloadedStore = ClassroomAssignmentStore(rootURL: rootURL)
        let assignment = try #require(reloadedStore.assignments.first)

        #expect(assignment.lessonVersionID == versionID)
        #expect(assignment.lessonVersionNumber == 1)
        #expect(assignment.lessonPackageStoragePath == manifest.packageStoragePath)
        #expect(assignment.lessonPackageChecksum == manifest.packageChecksum)
        #expect(assignment.versionDisplayName == "v1")
    }

    @MainActor
    @Test func classroomAssignmentStoreUpdatesAssignmentVersionWithoutChangingCode() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = ClassroomAssignmentStore(rootURL: rootURL) { "ALG011" }
        let lessonID = UUID()
        let firstVersionID = UUID()
        let secondVersionID = UUID()
        let lesson = Lesson(
            id: lessonID,
            name: "Reassignable Lesson",
            url: rootURL.appendingPathComponent("Reassignable Lesson.mathboard", isDirectory: true),
            createdAt: Date(),
            modifiedAt: Date()
        )
        let firstWidget = AssignedWidgetSummary(widgetID: UUID(), title: "Original Widget", maxScore: 5)
        let firstManifest = LessonPackageManifest(
            id: lessonID,
            title: lesson.name,
            versionID: firstVersionID,
            versionNumber: 1,
            packageFileName: "Reassignable Lesson.mathboard",
            packageStoragePath: "teacherLessonPackages/teacher/\(lessonID.uuidString)/versions/\(firstVersionID.uuidString)/package.mathboardpkg",
            packageChecksum: String(repeating: "c", count: 64),
            publishedAt: Date(timeIntervalSince1970: 1_800_000_400)
        )
        let assignment = try #require(store.createAssignments(
            for: lesson,
            classroomIDs: [UUID()],
            widgetSummaries: [firstWidget],
            lessonManifest: firstManifest
        ).first)
        let originalCode = assignment.classLessonCode
        let secondWidget = AssignedWidgetSummary(widgetID: UUID(), title: "Updated Widget", maxScore: 8)
        let secondManifest = LessonPackageManifest(
            id: lessonID,
            title: lesson.name,
            versionID: secondVersionID,
            versionNumber: 2,
            packageFileName: "Reassignable Lesson.mathboard",
            packageStoragePath: "teacherLessonPackages/teacher/\(lessonID.uuidString)/versions/\(secondVersionID.uuidString)/package.mathboardpkg",
            packageChecksum: String(repeating: "d", count: 64),
            publishedAt: Date(timeIntervalSince1970: 1_800_000_500)
        )

        let updated = try store.updateAssignment(
            assignment,
            lesson: lesson,
            widgetSummaries: [secondWidget],
            lessonManifest: secondManifest
        )

        #expect(updated.id == assignment.id)
        #expect(updated.classLessonCode == originalCode)
        #expect(updated.lessonVersionID == secondVersionID)
        #expect(updated.lessonVersionNumber == 2)
        #expect(updated.widgetSummaries.map(\.title) == ["Updated Widget"])
    }

    @MainActor
    @Test func classroomAssignmentStoreDetectsLocalActivityForAssignment() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = ClassroomAssignmentStore(rootURL: rootURL) { "ALG012" }
        let classroomID = UUID()
        let studentID = UUID()
        let widgetID = UUID()
        let assignment = try makeAssignment(in: store, rootURL: rootURL, classroomID: classroomID, widgetID: widgetID)

        #expect(!store.assignmentHasLocalActivity(assignment))
        try store.recordWidgetResult(
            StudentWidgetResult(
                assignmentID: assignment.id,
                classroomID: classroomID,
                studentID: studentID,
                widgetID: widgetID,
                numberCorrectFirstTry: 1,
                numberCorrectAfterRetry: 0,
                longestStreak: 1,
                finalPercentScore: 100
            )
        )

        #expect(store.assignmentHasLocalActivity(assignment))
    }

    @MainActor
    @Test func classroomAssignmentStoreReplacesExistingWidgetResultForStudent() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = ClassroomAssignmentStore(rootURL: rootURL) { "ALG001" }
        let classroomID = UUID()
        let studentID = UUID()
        let widgetID = UUID()
        let assignment = try makeAssignment(in: store, rootURL: rootURL, classroomID: classroomID, widgetID: widgetID)

        try store.recordWidgetResult(
            StudentWidgetResult(
                assignmentID: assignment.id,
                classroomID: classroomID,
                studentID: studentID,
                widgetID: widgetID,
                numberCorrectFirstTry: 3,
                numberCorrectAfterRetry: 1,
                longestStreak: 2,
                finalPercentScore: 60
            )
        )
        try store.recordWidgetResult(
            StudentWidgetResult(
                assignmentID: assignment.id,
                classroomID: classroomID,
                studentID: studentID,
                widgetID: widgetID,
                numberCorrectFirstTry: 4,
                numberCorrectAfterRetry: 1,
                longestStreak: 4,
                finalPercentScore: 100
            )
        )

        let result = try #require(store.widgetResults.first)
        #expect(store.widgetResults.count == 1)
        #expect(result.numberCorrectFirstTry == 4)
        #expect(result.longestStreak == 4)
        #expect(result.finalPercentScore == 100)
    }

    @MainActor
    @Test func classroomAssignmentStoreAveragesWidgetPercentScoresEqually() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = ClassroomAssignmentStore(rootURL: rootURL) { "ALG002" }
        let classroomID = UUID()
        let studentID = UUID()
        let fivePointWidgetID = UUID()
        let twelvePointWidgetID = UUID()
        let lesson = Lesson(
            id: UUID(),
            name: "Systems Practice",
            url: rootURL.appendingPathComponent("Systems Practice.mathboard", isDirectory: true),
            createdAt: Date(),
            modifiedAt: Date()
        )
        let assignment = try #require(store.createAssignments(
            for: lesson,
            classroomIDs: [classroomID],
            widgetSummaries: [
                AssignedWidgetSummary(widgetID: fivePointWidgetID, title: "Warmup", maxScore: 5),
                AssignedWidgetSummary(widgetID: twelvePointWidgetID, title: "Challenge", maxScore: 12)
            ]
        ).first)

        try store.recordWidgetResult(
            StudentWidgetResult(
                assignmentID: assignment.id,
                classroomID: classroomID,
                studentID: studentID,
                widgetID: fivePointWidgetID,
                numberCorrectFirstTry: 5,
                numberCorrectAfterRetry: 0,
                longestStreak: 5,
                finalPercentScore: 100
            )
        )
        try store.recordWidgetResult(
            StudentWidgetResult(
                assignmentID: assignment.id,
                classroomID: classroomID,
                studentID: studentID,
                widgetID: twelvePointWidgetID,
                numberCorrectFirstTry: 6,
                numberCorrectAfterRetry: 3,
                longestStreak: 4,
                finalPercentScore: 50
            )
        )

        #expect(store.averagePercentScore(for: assignment.id, studentID: studentID) == 75)
    }

    @MainActor
    @Test func classroomAssignmentReportFiltersSelectedStudents() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = ClassroomAssignmentStore(rootURL: rootURL) { "ALG003" }
        let selectedStudent = RosterStudent(
            firstName: "Ada",
            lastName: "Lovelace",
            officialStudentID: "A100",
            alternateStudentID: "ALG-001"
        )
        let unselectedStudent = RosterStudent(
            firstName: "Grace",
            lastName: "Hopper",
            officialStudentID: "G200",
            alternateStudentID: "ALG-002"
        )
        let classroom = Classroom(name: "Period 1", students: [selectedStudent, unselectedStudent])
        let widgetID = UUID()
        let assignment = try makeAssignment(in: store, rootURL: rootURL, classroomID: classroom.id, widgetID: widgetID)
        try store.recordWidgetResult(
            StudentWidgetResult(
                assignmentID: assignment.id,
                classroomID: classroom.id,
                studentID: selectedStudent.id,
                widgetID: widgetID,
                numberCorrectFirstTry: 4,
                numberCorrectAfterRetry: 1,
                longestStreak: 3,
                finalPercentScore: 80
            )
        )

        let report = try store.report(
            for: assignment.id,
            classroom: classroom,
            selectedStudentIDs: [selectedStudent.id]
        )

        #expect(report.studentReports.map(\.studentID) == [selectedStudent.id])
        #expect(report.studentReports.first?.studentName == "Ada Lovelace")
        #expect(report.studentReports.first?.averagePercentScore == 80)
        #expect(report.classAveragePercentScore == 80)
    }

    @MainActor
    @Test func classroomAssignmentStoreRejectsResultForUnassignedWidget() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = ClassroomAssignmentStore(rootURL: rootURL) { "ALG004" }
        let classroomID = UUID()
        let assignment = try makeAssignment(in: store, rootURL: rootURL, classroomID: classroomID, widgetID: UUID())

        do {
            try store.recordWidgetResult(
                StudentWidgetResult(
                    assignmentID: assignment.id,
                    classroomID: classroomID,
                    studentID: UUID(),
                    widgetID: UUID(),
                    numberCorrectFirstTry: 1,
                    numberCorrectAfterRetry: 0,
                    longestStreak: 1,
                    finalPercentScore: 20
                )
            )
            Issue.record("Recording a result for an unassigned widget should throw.")
        } catch ClassroomAssignmentStoreError.widgetNotAssigned {
        } catch {
            Issue.record("Recording an unassigned widget result threw an unexpected error: \(error)")
        }
    }

    @MainActor
    @Test func classroomAssignmentStoreBuildsWidgetSummariesFromLessonSidecars() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        let lessonURL = try makeTemporaryLessonPackage()
        defer {
            try? FileManager.default.removeItem(at: rootURL)
            try? FileManager.default.removeItem(at: lessonURL)
        }
        let store = ClassroomAssignmentStore(rootURL: rootURL) { "ALG005" }
        let lesson = Lesson(
            id: UUID(),
            name: "Widget Lesson",
            url: lessonURL,
            createdAt: Date(),
            modifiedAt: Date()
        )
        let slideStore = SlideStore(lessonURL: lessonURL)
        let slide = try #require(slideStore.slides.first)
        let widget = WidgetObject(
            name: "Exit Ticket",
            codeString: "not-json-yet",
            frame: CGRect(x: 10, y: 20, width: 300, height: 200)
        )
        try WidgetObject.save([widget], to: WidgetObject.sidecarURL(forDrawingURL: slideStore.drawingURL(for: slide)))

        let summaries = store.widgetSummaries(for: lesson)

        #expect(summaries.count == 1)
        #expect(summaries.first?.widgetID == widget.id)
        #expect(summaries.first?.title == "Exit Ticket")
    }

    @MainActor
    @Test func classroomAssignmentStoreRecordsWidgetScoreByLessonCodeAndAlternateID() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = ClassroomAssignmentStore(rootURL: rootURL) { "join-123" }
        let widgetID = UUID()
        let student = RosterStudent(
            firstName: "Ada",
            lastName: "Lovelace",
            officialStudentID: "A100",
            alternateStudentID: "ALG-001"
        )
        let classroom = Classroom(name: "Algebra", students: [student])
        let assignment = try makeAssignment(in: store, rootURL: rootURL, classroomID: classroom.id, widgetID: widgetID)
        let score = WidgetActivityScoreRecord(
            id: widgetID.uuidString,
            title: "Exit Ticket",
            status: .complete,
            score: 4,
            attempts: 5,
            points: 4,
            pointsPossible: 5,
            numberCorrectFirstTry: 3,
            numberCorrectAfterRetry: 1,
            longestStreak: 3
        )

        let result = try store.recordWidgetScore(
            score,
            classLessonCode: " join-123 ",
            studentIdentifier: "alg-001",
            classroom: classroom
        )
        let report = try store.report(for: assignment.id, classroom: classroom)

        #expect(result.studentID == student.id)
        #expect(result.finalPercentScore == 80)
        #expect(report.studentReports.first?.widgetResults.first?.numberCorrectFirstTry == 3)
        #expect(report.studentReports.first?.widgetResults.first?.numberCorrectAfterRetry == 1)
        #expect(report.classAveragePercentScore == 80)
    }

    @MainActor
    @Test func classroomAssignmentStoreRecordsWidgetScoreByOfficialIDAndReplacesRepeatSubmission() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = ClassroomAssignmentStore(rootURL: rootURL) { "join-456" }
        let widgetID = UUID()
        let student = RosterStudent(
            firstName: "Grace",
            lastName: "Hopper",
            officialStudentID: "G200",
            alternateStudentID: "ALG-002"
        )
        let classroom = Classroom(name: "Algebra", students: [student])
        _ = try makeAssignment(in: store, rootURL: rootURL, classroomID: classroom.id, widgetID: widgetID)

        try store.recordWidgetScore(
            WidgetActivityScoreRecord(
                id: widgetID.uuidString,
                title: "Exit Ticket",
                status: .complete,
                score: 2,
                attempts: 5,
                points: 2,
                pointsPossible: 5,
                longestStreak: 2
            ),
            classLessonCode: "JOIN456",
            studentIdentifier: "g200",
            classroom: classroom
        )
        try store.recordWidgetScore(
            WidgetActivityScoreRecord(
                id: widgetID.uuidString,
                title: "Exit Ticket",
                status: .complete,
                score: 5,
                attempts: 5,
                points: 5,
                pointsPossible: 5,
                numberCorrectFirstTry: 5,
                longestStreak: 5
            ),
            classLessonCode: "JOIN456",
            studentIdentifier: "G200",
            classroom: classroom
        )

        #expect(store.widgetResults.count == 1)
        #expect(store.widgetResults.first?.finalPercentScore == 100)
        #expect(store.widgetResults.first?.longestStreak == 5)
    }

    @MainActor
    @Test func classroomAssignmentStoreRejectsUnknownLessonCodeStudentAndIncompleteScores() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = ClassroomAssignmentStore(rootURL: rootURL) { "join-789" }
        let widgetID = UUID()
        let student = RosterStudent(
            firstName: "Ada",
            lastName: "Lovelace",
            officialStudentID: "A100",
            alternateStudentID: "ALG-001"
        )
        let classroom = Classroom(name: "Algebra", students: [student])
        _ = try makeAssignment(in: store, rootURL: rootURL, classroomID: classroom.id, widgetID: widgetID)
        let completedScore = WidgetActivityScoreRecord(
            id: widgetID.uuidString,
            title: "Exit Ticket",
            status: .complete,
            score: 4,
            attempts: 5,
            points: 4,
            pointsPossible: 5
        )

        do {
            try store.recordWidgetScore(completedScore, classLessonCode: "missing", studentIdentifier: "A100", classroom: classroom)
            Issue.record("Unknown lesson codes should be rejected.")
        } catch ClassroomAssignmentStoreError.classLessonCodeNotFound {
        } catch {
            Issue.record("Unknown lesson code threw an unexpected error: \(error)")
        }

        do {
            try store.recordWidgetScore(completedScore, classLessonCode: "JOIN789", studentIdentifier: "NOPE", classroom: classroom)
            Issue.record("Unknown students should be rejected.")
        } catch ClassroomAssignmentStoreError.studentNotFound {
        } catch {
            Issue.record("Unknown student threw an unexpected error: \(error)")
        }

        do {
            try store.recordWidgetScore(
                WidgetActivityScoreRecord(
                    id: widgetID.uuidString,
                    title: "Exit Ticket",
                    status: .inProgress,
                    score: 1,
                    attempts: 2,
                    points: 1,
                    pointsPossible: 2
                ),
                classLessonCode: "JOIN789",
                studentIdentifier: "A100",
                classroom: classroom
            )
            Issue.record("Incomplete scores should be rejected.")
        } catch ClassroomAssignmentStoreError.incompleteWidgetScore {
        } catch {
            Issue.record("Incomplete score threw an unexpected error: \(error)")
        }
    }

    @MainActor
    @Test func classroomAssignmentStoreRejectsAmbiguousStudentIdentifier() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = ClassroomAssignmentStore(rootURL: rootURL) { "join-999" }
        let widgetID = UUID()
        let classroom = Classroom(name: "Algebra", students: [
            RosterStudent(firstName: "Ada", lastName: "Lovelace", officialStudentID: "A100", alternateStudentID: "MATCH"),
            RosterStudent(firstName: "Grace", lastName: "Hopper", officialStudentID: "G200", alternateStudentID: "match")
        ])
        _ = try makeAssignment(in: store, rootURL: rootURL, classroomID: classroom.id, widgetID: widgetID)
        let score = WidgetActivityScoreRecord(
            id: widgetID.uuidString,
            title: "Exit Ticket",
            status: .complete,
            score: 1,
            attempts: 1,
            points: 1,
            pointsPossible: 1
        )

        do {
            try store.recordWidgetScore(score, classLessonCode: "JOIN999", studentIdentifier: "MATCH", classroom: classroom)
            Issue.record("Ambiguous student identifiers should be rejected.")
        } catch ClassroomAssignmentStoreError.ambiguousStudentIdentifier {
        } catch {
            Issue.record("Ambiguous student identifier threw an unexpected error: \(error)")
        }
    }

    @Test func widgetMultipleChoiceScoreRecordTracksFirstTryCorrectedAndStreak() throws {
        let widgetID = try #require(UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"))
        let widget = WidgetObject(
            id: widgetID,
            name: "Exit Ticket",
            codeString: WidgetSamples.orderOpsActivityJSON,
            frame: CGRect(x: 0, y: 0, width: 700, height: 360),
            activityRuntimeState: WidgetActivityRuntimeState(
                multipleChoice: WidgetMultipleChoiceRuntimeState(
                    score: 3,
                    attempts: 5,
                    streak: 2,
                    longestStreak: 2,
                    answeredQuestionIDs: Set(["a", "b", "c", "d", "e", "f"]),
                    correctlyAnsweredQuestionIDs: Set(["a", "b", "d"]),
                    questionAttempts: ["a": 1, "b": 2, "c": 1, "d": 3]
                )
            )
        )

        let scoreRecord = try #require(widget.activityScoreRecord)

        #expect(scoreRecord.id == widgetID.uuidString)
        #expect(scoreRecord.numberCorrectFirstTry == 1)
        #expect(scoreRecord.numberCorrectAfterRetry == 2)
        #expect(scoreRecord.longestStreak == 2)
        #expect(scoreRecord.percent == 60)
    }

    @MainActor
    @Test func mathBoardUserModeStorePersistsManualRoleSwitch() throws {
        let suiteName = "MathBoardUserModeStoreTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let store = MathBoardUserModeStore(userDefaults: userDefaults, storageKey: "mode")

        #expect(store.mode == .teacher)
        store.switchToStudentMode()
        #expect(store.mode == .student)
        #expect(MathBoardUserModeStore(userDefaults: userDefaults, storageKey: "mode").mode == .student)
    }

    @MainActor
    @Test func mathBoardTeacherAuthStoreTracksSignInCreateAccountAndSignOut() async throws {
        let authProvider = FakeTeacherAuthProvider()
        let store = MathBoardTeacherAuthStore(authProvider: authProvider)

        #expect(store.state == .signedOut)
        await store.signIn(email: "teacher@example.com", password: "password")
        #expect(store.state == .signedIn(userID: "teacher-user", email: "teacher@example.com"))
        #expect(store.errorMessage == nil)

        store.signOut()
        #expect(store.state == .signedOut)

        await store.createAccount(email: "new@example.com", password: "password")
        #expect(store.state == .signedIn(userID: "teacher-user", email: "new@example.com"))
    }

    @MainActor
    @Test func mathBoardTeacherAuthStoreSurfacesProviderErrors() async throws {
        let authProvider = FakeTeacherAuthProvider(error: TeacherAuthTestError.failed)
        let store = MathBoardTeacherAuthStore(authProvider: authProvider)

        await store.signIn(email: "teacher@example.com", password: "password")

        #expect(store.state == .signedOut)
        #expect(store.errorMessage == "Teacher auth failed.")
        store.clearError()
        #expect(store.errorMessage == nil)
    }

    @MainActor
    @Test func studentFirebaseAccessAuthorizerReusesCurrentAuthUser() async throws {
        let authProvider = FakeStudentFirebaseAuthProvider(currentUserID: "existing-student")
        let authorizer = MathBoardStudentFirebaseAccessAuthorizer(authProvider: authProvider)

        let userID = try await authorizer.ensureAuthenticatedForOnlineLessonAccess()

        #expect(userID == "existing-student")
        #expect(authProvider.anonymousSignInCount == 0)
    }

    @MainActor
    @Test func studentFirebaseAccessAuthorizerSignsInAnonymouslyWhenNeeded() async throws {
        let authProvider = FakeStudentFirebaseAuthProvider(anonymousUserID: "anonymous-student")
        let authorizer = MathBoardStudentFirebaseAccessAuthorizer(authProvider: authProvider)

        let userID = try await authorizer.ensureAuthenticatedForOnlineLessonAccess()

        #expect(userID == "anonymous-student")
        #expect(authProvider.currentUserID == "anonymous-student")
        #expect(authProvider.anonymousSignInCount == 1)
    }

    @MainActor
    @Test func classroomAssignmentStoreLooksUpAssignmentByNormalizedLessonCode() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = ClassroomAssignmentStore(rootURL: rootURL) { "join-123" }
        let assignment = try makeAssignment(in: store, rootURL: rootURL, classroomID: UUID(), widgetID: UUID())

        #expect(store.assignment(matchingClassLessonCode: " join 123 ")?.id == assignment.id)
        #expect(store.assignment(matchingClassLessonCode: "missing") == nil)
        #expect(ClassroomAssignmentStore.normalizedClassLessonCode(" join-123 ") == "JOIN123")
    }

    @MainActor
    @Test func localClassroomSyncServiceResolvesAssignmentPacketByLessonCode() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let rosterStore = ClassroomRosterStore(rootURL: rootURL)
        let assignmentStore = ClassroomAssignmentStore(rootURL: rootURL) { "join-321" }
        let teacherID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let teacher = TeacherSyncIdentity(id: teacherID, displayName: "Professor")
        let widgetID = UUID()
        let classroom = Classroom(name: "Algebra 1", students: [
            RosterStudent(firstName: "Ada", lastName: "Lovelace", officialStudentID: "A100", alternateStudentID: "ALG-001")
        ])
        rosterStore.classrooms = [classroom]
        let assignment = try makeAssignment(in: assignmentStore, rootURL: rootURL, classroomID: classroom.id, widgetID: widgetID)
        let syncService = LocalClassroomSyncService(
            teacherIdentity: teacher,
            rosterStore: rosterStore,
            assignmentStore: assignmentStore
        )

        let packet = try syncService.resolveAssignment(classLessonCode: " join 321 ")

        #expect(packet.id == assignment.id)
        #expect(packet.teacherID == teacher.id)
        #expect(packet.classroomID == classroom.id)
        #expect(packet.classroomName == "Algebra 1")
        #expect(packet.lesson.title == "Practice")
        #expect(packet.classLessonCode == "JOIN321")
        #expect(packet.widgetSummaries.first?.widgetID == widgetID)
    }

    @MainActor
    @Test func localClassroomSyncServiceSubmitsAndFetchesWidgetScores() throws {
        let rootURL = try makeTemporaryDocumentRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let rosterStore = ClassroomRosterStore(rootURL: rootURL)
        let assignmentStore = ClassroomAssignmentStore(rootURL: rootURL) { "join-654" }
        let teacher = TeacherSyncIdentity(id: UUID(), displayName: "Professor")
        let widgetID = UUID()
        let student = RosterStudent(
            firstName: "Grace",
            lastName: "Hopper",
            officialStudentID: "G200",
            alternateStudentID: "ALG-002"
        )
        let classroom = Classroom(name: "Algebra 1", students: [student])
        rosterStore.classrooms = [classroom]
        let assignment = try makeAssignment(in: assignmentStore, rootURL: rootURL, classroomID: classroom.id, widgetID: widgetID)
        let syncService = LocalClassroomSyncService(
            teacherIdentity: teacher,
            rosterStore: rosterStore,
            assignmentStore: assignmentStore
        )
        let scoreRecord = WidgetActivityScoreRecord(
            id: widgetID.uuidString,
            title: "Widget",
            status: .complete,
            score: 8,
            attempts: 10,
            points: 8,
            pointsPossible: 10,
            numberCorrectFirstTry: 7,
            numberCorrectAfterRetry: 1,
            longestStreak: 4
        )
        let submission = StudentSubmissionPacket(
            teacherID: teacher.id,
            classroomID: classroom.id,
            assignmentID: assignment.id,
            classLessonCode: "JOIN654",
            studentIdentifier: "alg-002",
            widgetScoreRecord: scoreRecord,
            submittedAt: Date(timeIntervalSince1970: 100)
        )

        let result = try syncService.submitWidgetScore(submission)
        let fetchedResults = try syncService.fetchSubmissions(assignmentID: assignment.id)

        #expect(result.studentID == student.id)
        #expect(result.widgetID == widgetID)
        #expect(result.finalPercentScore == 80)
        #expect(fetchedResults.count == 1)
        #expect(fetchedResults.first?.id == result.id)
        #expect(assignmentStore.widgetResults.first?.numberCorrectFirstTry == 7)
    }

    @Test func liveProgressIndicatorStateUsesActiveSubmittedAndInactiveRules() {
        let now = Date(timeIntervalSince1970: 1_000)
        let activeProgress = makeLiveProgress(
            status: .inProgress,
            isActiveOnStudentScreen: true,
            updatedAt: now.addingTimeInterval(-5)
        )
        let inactiveProgress = makeLiveProgress(
            status: .inProgress,
            isActiveOnStudentScreen: false,
            updatedAt: now.addingTimeInterval(-5)
        )
        let submittedProgress = makeLiveProgress(
            status: .complete,
            isActiveOnStudentScreen: false,
            updatedAt: now.addingTimeInterval(-5)
        )

        let missingProgress: StudentWidgetLiveProgress? = nil
        #expect(missingProgress.liveProgressIndicatorState(now: now) == .notStarted)
        #expect(missingProgress.liveProgressIndicatorState(now: now).displayName == "Not logged in")
        #expect(activeProgress.indicatorState(now: now) == .active)
        #expect(activeProgress.indicatorState(now: now).displayName == "On widget")
        #expect(inactiveProgress.indicatorState(now: now) == .inactive)
        #expect(inactiveProgress.indicatorState(now: now).displayName == "Logged in")
        #expect(submittedProgress.indicatorState(now: now) == .submitted)
        #expect(submittedProgress.indicatorState(now: now).displayName == "Submitted")
    }

    @Test func liveProgressIndicatorStateTreatsStaleActiveProgressAsOffline() {
        let now = Date(timeIntervalSince1970: 1_000)
        let staleActiveProgress = makeLiveProgress(
            status: .inProgress,
            isActiveOnStudentScreen: true,
            updatedAt: now.addingTimeInterval(-21)
        )
        let freshBoundaryProgress = makeLiveProgress(
            status: .inProgress,
            isActiveOnStudentScreen: true,
            updatedAt: now.addingTimeInterval(-20)
        )
        let staleInactiveProgress = makeLiveProgress(
            status: .inProgress,
            isActiveOnStudentScreen: false,
            updatedAt: now.addingTimeInterval(-21)
        )
        let staleSubmittedProgress = makeLiveProgress(
            status: .complete,
            isActiveOnStudentScreen: true,
            updatedAt: now.addingTimeInterval(-120)
        )

        #expect(staleActiveProgress.indicatorState(now: now) == .offline)
        #expect(staleActiveProgress.indicatorState(now: now).displayName == "Offline")
        #expect(staleInactiveProgress.indicatorState(now: now) == .offline)
        #expect(freshBoundaryProgress.indicatorState(now: now) == .active)
        #expect(staleSubmittedProgress.indicatorState(now: now) == .submitted)
    }

    @Test func studentAssignedLessonLiveProgressBuilderPublishesScoreableAssignedWidgets() throws {
        let activeWidgetID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let inactiveWidgetID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let submittedWidgetID = try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let matchGridWidgetID = try #require(UUID(uuidString: "44444444-4444-4444-4444-444444444444"))
        let packet = AssignmentSyncPacket(
            id: UUID(),
            teacherID: UUID(),
            classroomID: UUID(),
            classroomName: "Period 1",
            lesson: LessonPackageManifest(id: UUID(), title: "Inequalities"),
            classLessonCode: "ABC123",
            widgetSummaries: [
                AssignedWidgetSummary(widgetID: activeWidgetID, title: "Inequality Widget", maxScore: 10),
                AssignedWidgetSummary(widgetID: inactiveWidgetID, title: "Graph Widget", maxScore: 8),
                AssignedWidgetSummary(widgetID: submittedWidgetID, title: "Number Line Widget", maxScore: 6),
                AssignedWidgetSummary(widgetID: matchGridWidgetID, title: "MatchGrid", maxScore: 0, builtInKind: .matchGrid)
            ],
            assignedAt: Date(timeIntervalSince1970: 500)
        )
        let builder = StudentAssignedLessonLiveProgressBuilder(
            assignmentPacket: packet,
            studentIdentifier: "ALG-001",
            studentPreferredFirstName: "Alexander",
            submittedWidgetIDs: [submittedWidgetID]
        )

        let updates = builder.updates(
            activeWidgetIDs: [activeWidgetID, submittedWidgetID, matchGridWidgetID],
            submittedAt: Date(timeIntervalSince1970: 600)
        )
        let updatesByWidgetID = Dictionary(uniqueKeysWithValues: updates.compactMap { update in
            UUID(uuidString: update.submission.widgetScoreRecord.id).map { ($0, update) }
        })
        let activeUpdate = try #require(updatesByWidgetID[activeWidgetID])
        let inactiveUpdate = try #require(updatesByWidgetID[inactiveWidgetID])
        let submittedUpdate = try #require(updatesByWidgetID[submittedWidgetID])

        #expect(updates.count == 3)
        #expect(updatesByWidgetID[matchGridWidgetID] == nil)
        #expect(activeUpdate.isActiveOnStudentScreen)
        #expect(activeUpdate.submission.widgetScoreRecord.status == .inProgress)
        #expect(!inactiveUpdate.isActiveOnStudentScreen)
        #expect(inactiveUpdate.submission.widgetScoreRecord.status == .inProgress)
        #expect(submittedUpdate.isActiveOnStudentScreen)
        #expect(submittedUpdate.submission.widgetScoreRecord.status == .complete)
        #expect(submittedUpdate.submission.studentIdentifier == "ALG-001")
        #expect(submittedUpdate.submission.studentPreferredFirstName == "Alexander")
    }

    @Test func studentAssignedLessonLiveProgressBuilderPreservesCachedInactiveScores() throws {
        let activeWidgetID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let inactiveWidgetID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let submittedWidgetID = try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let packet = AssignmentSyncPacket(
            id: UUID(),
            teacherID: UUID(),
            classroomID: UUID(),
            classroomName: "Period 1",
            lesson: LessonPackageManifest(id: UUID(), title: "Inequalities"),
            classLessonCode: "ABC123",
            widgetSummaries: [
                AssignedWidgetSummary(widgetID: activeWidgetID, title: "Active Widget", maxScore: 10),
                AssignedWidgetSummary(widgetID: inactiveWidgetID, title: "Inactive Widget", maxScore: 8),
                AssignedWidgetSummary(widgetID: submittedWidgetID, title: "Submitted Widget", maxScore: 6)
            ],
            assignedAt: Date(timeIntervalSince1970: 500)
        )
        var builder = StudentAssignedLessonLiveProgressBuilder(
            assignmentPacket: packet,
            studentIdentifier: "ALG-001",
            submittedWidgetIDs: [submittedWidgetID]
        )
        builder.scoreRecordsByWidgetID = [
            inactiveWidgetID: WidgetActivityScoreRecord(
                id: inactiveWidgetID.uuidString,
                title: "Inactive Widget",
                status: .inProgress,
                score: 3,
                attempts: 5,
                points: 3,
                pointsPossible: 8,
                numberCorrectFirstTry: 2,
                numberCorrectAfterRetry: 1,
                longestStreak: 2
            ),
            submittedWidgetID: WidgetActivityScoreRecord(
                id: submittedWidgetID.uuidString,
                title: "Submitted Widget",
                status: .inProgress,
                score: 4,
                attempts: 6,
                points: 4,
                pointsPossible: 6,
                numberCorrectFirstTry: 3,
                numberCorrectAfterRetry: 1,
                longestStreak: 3
            )
        ]

        let updates = builder.updates(
            activeWidgetIDs: [activeWidgetID],
            submittedAt: Date(timeIntervalSince1970: 600)
        )
        let updatesByWidgetID = Dictionary(uniqueKeysWithValues: updates.compactMap { update in
            UUID(uuidString: update.submission.widgetScoreRecord.id).map { ($0, update) }
        })
        let inactiveUpdate = try #require(updatesByWidgetID[inactiveWidgetID])
        let submittedUpdate = try #require(updatesByWidgetID[submittedWidgetID])

        #expect(!inactiveUpdate.isActiveOnStudentScreen)
        #expect(inactiveUpdate.submission.widgetScoreRecord.status == .inProgress)
        #expect(inactiveUpdate.submission.widgetScoreRecord.score == 3)
        #expect(inactiveUpdate.submission.widgetScoreRecord.attempts == 5)
        #expect(!submittedUpdate.isActiveOnStudentScreen)
        #expect(submittedUpdate.submission.widgetScoreRecord.status == .complete)
        #expect(submittedUpdate.submission.widgetScoreRecord.score == 4)
        #expect(submittedUpdate.submission.widgetScoreRecord.attempts == 6)
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

    @MainActor
    private func makeAssignment(
        in store: ClassroomAssignmentStore,
        rootURL: URL,
        classroomID: UUID,
        widgetID: UUID
    ) throws -> ClassroomAssignment {
        let lesson = Lesson(
            id: UUID(),
            name: "Practice",
            url: rootURL.appendingPathComponent("Practice.mathboard", isDirectory: true),
            createdAt: Date(),
            modifiedAt: Date()
        )
        return try #require(store.createAssignments(
            for: lesson,
            classroomIDs: [classroomID],
            widgetSummaries: [AssignedWidgetSummary(widgetID: widgetID, title: "Widget", maxScore: 10)]
        ).first)
    }

    private func makeLiveProgress(
        status: WidgetActivityScoreStatus,
        isActiveOnStudentScreen: Bool,
        updatedAt: Date
    ) -> StudentWidgetLiveProgress {
        StudentWidgetLiveProgress(
            assignmentID: UUID(),
            classroomID: UUID(),
            studentID: UUID(),
            studentName: "Ada Lovelace",
            widgetID: UUID(),
            correctCount: 2,
            attemptedCount: 3,
            status: status,
            isActiveOnStudentScreen: isActiveOnStudentScreen,
            updatedAt: updatedAt
        )
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
        try Data("sample".utf8).write(to: packageURL.appendingPathComponent("assets/sample.txt"), options: .atomic)
        return packageURL
    }

    private func readDocumentMetadataID(at packageURL: URL) throws -> UUID {
        let data = try Data(contentsOf: packageURL.appendingPathComponent("document.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DocumentMetadata.self, from: data).id
    }

    @MainActor
    @Test func liveClassroomLessonCodeNormalizesForChannelName() {
        let configuration = LiveClassroomSessionConfiguration(
            lessonCode: " ab-12 c ",
            role: .teacher,
            clientID: "teacher-local",
            apiKey: "test-key"
        )

        #expect(configuration.lessonCode == "AB12C")
        #expect(configuration.inkChannelName == "classroom:AB12C:ink")
    }

    @MainActor
    @Test func liveClassroomStrokeChunkCapsTransportPointCount() {
        let slideID = UUID()
        let stroke = liveClassroomStroke(pointCount: TeacherInkStrokeChunk.maximumPointCount + 75)

        let chunk = TeacherInkStrokeChunk(
            stroke: stroke,
            lessonCode: "ABC123",
            slideID: slideID,
            strokeID: UUID(),
            sequence: 0,
            isFinalChunk: false
        )

        #expect(chunk?.points.count == TeacherInkStrokeChunk.maximumPointCount)
        #expect(chunk?.points.first?.x == 0)
        #expect(chunk?.points.last?.x == Double(stroke.samples.count - 1))
    }

    @MainActor
    @Test func liveClassroomCoordinatorFiltersReceivedInkBySlideID() {
        let slideA = UUID()
        let slideB = UUID()
        let session = FakeLiveClassroomSession()
        let coordinator = LiveTeacherInkCoordinator(sessionFactory: { _ in session })
        coordinator.configure(liveClassroomStudentConfiguration())

        session.deliver(liveClassroomChunk(slideID: slideA, strokeID: UUID(), x: 10))
        session.deliver(liveClassroomChunk(slideID: slideB, strokeID: UUID(), x: 20))

        #expect(coordinator.receivedStrokes(for: slideA).count == 1)
        #expect(coordinator.receivedStrokes(for: slideB).count == 1)
        #expect(coordinator.receivedStrokes(for: slideA).first?.samples.first?.location.x == 10)
    }

    @MainActor
    @Test func liveClassroomCoordinatorReturnsOnlyFinalInkChunksForPersistence() {
        let slideID = UUID()
        let finalStrokeID = UUID()
        let inProgressStrokeID = UUID()
        let session = FakeLiveClassroomSession()
        let coordinator = LiveTeacherInkCoordinator(sessionFactory: { _ in session })
        coordinator.configure(liveClassroomStudentConfiguration())

        session.deliver(liveClassroomChunk(slideID: slideID, strokeID: inProgressStrokeID, x: 10, isFinalChunk: false))
        session.deliver(liveClassroomChunk(slideID: slideID, strokeID: finalStrokeID, x: 20, isFinalChunk: true))

        let finalChunks = coordinator.receivedFinalInkChunks(for: slideID)

        #expect(finalChunks.map(\.strokeID) == [finalStrokeID])
        #expect(finalChunks.first?.canvasLiveStroke.samples.first?.location.x == 20)
    }

    @MainActor
    @Test func liveClassroomCoordinatorCallsDurableCallbackOnlyForFinalChunks() {
        let slideID = UUID()
        let session = FakeLiveClassroomSession()
        let coordinator = LiveTeacherInkCoordinator(
            publishInterval: .milliseconds(1),
            sessionFactory: { _ in session }
        )
        var durableChunks: [TeacherInkStrokeChunk] = []
        coordinator.onPublishedTeacherInkChunk = { chunk in
            durableChunks.append(chunk)
        }
        coordinator.configure(liveClassroomTeacherConfiguration())

        coordinator.publishTeacherStroke(liveClassroomStroke(pointCount: 8), slideID: slideID)
        coordinator.publishTeacherStroke(nil, slideID: slideID)

        #expect(durableChunks.count == 1)
        #expect(durableChunks.first?.isFinalChunk == true)
        #expect(durableChunks.first?.slideID == slideID)
    }

    @MainActor
    @Test func liveClassroomCoordinatorPublishesFinalChunkImmediatelyOnStrokeEnd() {
        let slideID = UUID()
        let session = FakeLiveClassroomSession()
        let coordinator = LiveTeacherInkCoordinator(
            publishInterval: .seconds(10),
            sessionFactory: { _ in session }
        )
        coordinator.configure(liveClassroomTeacherConfiguration())

        coordinator.publishTeacherStroke(liveClassroomStroke(pointCount: 8), slideID: slideID)
        #expect(session.publishedChunks.isEmpty)

        coordinator.publishTeacherStroke(nil, slideID: slideID)

        #expect(session.publishedChunks.count == 1)
        #expect(session.publishedChunks.first?.isFinalChunk == true)
        #expect(session.publishedChunks.first?.slideID == slideID)
    }

    @Test func canvasObjectSnapshotCapturesAndWritesJPEGAssets() throws {
        let sourceDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MathBoardObjectSnapshotSource-\(UUID().uuidString)", isDirectory: true)
        let destinationDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MathBoardObjectSnapshotDestination-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationDirectoryURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: sourceDirectoryURL)
            try? FileManager.default.removeItem(at: destinationDirectoryURL)
        }

        let slideID = UUID()
        let sourceDrawingURL = sourceDirectoryURL.appendingPathComponent("slide-live.drawing")
        let sourceTextSidecarURL = sourceDirectoryURL.appendingPathComponent("slide-live.textobjects.json")
        let sourceImageDirectoryURL = CanvasImageObject.assetDirectoryURL(forDrawingURL: sourceDrawingURL)
        let jpegData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02, 0x03])
        try Data(#"[{"text":"Live note"}]"#.utf8).write(to: sourceTextSidecarURL)
        try FileManager.default.createDirectory(at: sourceImageDirectoryURL, withIntermediateDirectories: true)
        try jpegData.write(to: sourceImageDirectoryURL.appendingPathComponent("teacher-photo.jpg"))

        let snapshot = CanvasObjectSnapshot.capture(slideID: slideID, drawingURL: sourceDrawingURL, revision: 12)

        #expect(snapshot.slideID == slideID)
        #expect(snapshot.revision == 12)
        #expect(snapshot.sidecarFiles.map(\.name) == ["textobjects.json"])
        #expect(snapshot.imageAssetFiles.map(\.name) == ["teacher-photo.jpg"])
        #expect(snapshot.imageAssetFiles.first?.data == jpegData)

        let destinationDrawingURL = destinationDirectoryURL.appendingPathComponent("student-slide.drawing")
        try snapshot.write(to: destinationDrawingURL)

        let destinationTextSidecarURL = destinationDirectoryURL.appendingPathComponent("student-slide.textobjects.json")
        let destinationImageURL = CanvasImageObject.assetDirectoryURL(forDrawingURL: destinationDrawingURL)
            .appendingPathComponent("teacher-photo.jpg")
        #expect((try? Data(contentsOf: destinationTextSidecarURL)) == Data(#"[{"text":"Live note"}]"#.utf8))
        #expect((try? Data(contentsOf: destinationImageURL)) == jpegData)
    }

    @Test @MainActor func inlineTeacherObjectSnapshotFirestoreDocumentRoundTrips() throws {
        let id = try #require(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let slideID = try #require(UUID(uuidString: "22222222-3333-4444-5555-666666666666"))
        let sentAt = Date(timeIntervalSince1970: 1_800_000_100)
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_050)
        let textData = Data(#"[{"text":"Factor"}]"#.utf8)
        let imageData = Data([0xFF, 0xD8, 0xFF, 0x01])
        let snapshot = TeacherObjectSnapshot(
            id: id,
            lessonCode: "abc123",
            slideID: slideID,
            revision: 9,
            snapshot: CanvasObjectSnapshot(
                slideID: slideID,
                revision: 9,
                capturedAt: capturedAt,
                sidecarFiles: [
                    CanvasObjectSnapshotFile(name: "textobjects.json", data: textData)
                ],
                imageAssetFiles: [
                    CanvasObjectSnapshotFile(name: "photo.jpg", data: imageData)
                ]
            ),
            sentAt: sentAt
        )

        let document = FirebaseClassroomSyncService.teacherObjectSnapshotDocument(snapshot, teacherUserID: "teacher-1")
        let decoded = try #require(FirebaseClassroomSyncService.inlineTeacherObjectSnapshot(from: document, fallbackCode: "FALLBACK"))

        #expect(document["objectSnapshotStoragePath"] == nil)
        #expect(decoded.id == id)
        #expect(decoded.lessonCode == "ABC123")
        #expect(decoded.slideID == slideID)
        #expect(decoded.revision == 9)
        #expect(decoded.snapshot.sidecarFiles.first?.data == textData)
        #expect(decoded.snapshot.imageAssetFiles.first?.name == "photo.jpg")
        #expect(decoded.snapshot.imageAssetFiles.first?.data == imageData)
    }

    @Test @MainActor func teacherObjectSnapshotSizeThresholdChoosesStorageBackedDocumentForLargeAssets() {
        let slideID = UUID()
        let smallSnapshot = TeacherObjectSnapshot(
            lessonCode: "LIVE01",
            slideID: slideID,
            revision: 1,
            snapshot: CanvasObjectSnapshot(
                slideID: slideID,
                revision: 1,
                sidecarFiles: [CanvasObjectSnapshotFile(name: "textobjects.json", data: Data("[]".utf8))],
                imageAssetFiles: []
            )
        )
        let largeSnapshot = TeacherObjectSnapshot(
            lessonCode: "LIVE01",
            slideID: slideID,
            revision: 2,
            snapshot: CanvasObjectSnapshot(
                slideID: slideID,
                revision: 2,
                sidecarFiles: [],
                imageAssetFiles: [
                    CanvasObjectSnapshotFile(name: "large-photo.jpg", data: Data(repeating: 0x7B, count: 600_000))
                ]
            )
        )

        #expect(!FirebaseClassroomSyncService.usesStorageBackedTeacherObjectSnapshotDocument(smallSnapshot, teacherUserID: "teacher-1"))
        #expect(FirebaseClassroomSyncService.usesStorageBackedTeacherObjectSnapshotDocument(largeSnapshot, teacherUserID: "teacher-1"))

        let referenceDocument = FirebaseClassroomSyncService.teacherObjectSnapshotReferenceDocument(
            largeSnapshot,
            teacherUserID: "teacher-1",
            storagePath: "classLessonAssets/LIVE01/teacherObjects/\(slideID.uuidString).json"
        )

        #expect(referenceDocument["objectSnapshotStoragePath"] as? String == "classLessonAssets/LIVE01/teacherObjects/\(slideID.uuidString).json")
        #expect(referenceDocument["sidecarFiles"] == nil)
        #expect(referenceDocument["imageAssetFiles"] == nil)
        #expect(
            FirebaseClassroomSyncService.estimatedFirestorePayloadSize(referenceDocument)
            < FirebaseClassroomSyncService.estimatedFirestorePayloadSize(
                FirebaseClassroomSyncService.teacherObjectSnapshotDocument(largeSnapshot, teacherUserID: "teacher-1")
            )
        )
    }

    private func liveClassroomTeacherConfiguration() -> LiveClassroomSessionConfiguration {
        LiveClassroomSessionConfiguration(
            lessonCode: "ABC123",
            role: .teacher,
            clientID: "teacher-test",
            apiKey: "test-key"
        )
    }

    private func liveClassroomStudentConfiguration() -> LiveClassroomSessionConfiguration {
        LiveClassroomSessionConfiguration(
            lessonCode: "ABC123",
            role: .student,
            clientID: "student-test",
            apiKey: "test-key"
        )
    }

    private func liveClassroomStroke(pointCount: Int) -> CanvasLiveStroke {
        CanvasLiveStroke(
            samples: (0..<pointCount).map { index in
                CanvasLiveStrokePoint(
                    location: CGPoint(x: index, y: index * 2),
                    pressure: 0.5,
                    timestamp: Double(index) / 120
                )
            },
            lineWidth: 8,
            color: CanvasStrokeColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1),
            kind: .ink
        )
    }

    private func liveClassroomChunk(
        slideID: UUID,
        strokeID: UUID,
        x: Double,
        isFinalChunk: Bool = true
    ) -> TeacherInkStrokeChunk {
        TeacherInkStrokeChunk(
            lessonCode: "ABC123",
            slideID: slideID,
            strokeID: strokeID,
            sequence: 0,
            isFinalChunk: isFinalChunk,
            colorHex: "#000000",
            alpha: 1,
            width: 4,
            points: [
                TeacherInkPoint(x: x, y: 1, timestampOffset: 0),
                TeacherInkPoint(x: x + 1, y: 2, timestampOffset: 0.01)
            ]
        )
    }
}

@MainActor
private final class FakeLiveClassroomSession: LiveClassroomSessioning {
    var onTeacherInkChunk: ((TeacherInkStrokeChunk) -> Void)?
    var onTeacherInkDrawingSnapshot: ((TeacherInkDrawingSnapshot) -> Void)?
    var onTeacherObjectSnapshot: ((TeacherObjectSnapshot) -> Void)?
    var onTeacherSlideManifestSnapshot: ((TeacherSlideManifestSnapshot) -> Void)?
    private(set) var lastErrorMessage: String?
    private(set) var didStart = false
    private(set) var didStop = false
    private(set) var publishedChunks: [TeacherInkStrokeChunk] = []
    private(set) var publishedInkDrawingSnapshots: [TeacherInkDrawingSnapshot] = []
    private(set) var publishedObjectSnapshots: [TeacherObjectSnapshot] = []
    private(set) var publishedSlideManifestSnapshots: [TeacherSlideManifestSnapshot] = []

    func start() {
        didStart = true
    }

    func publishTeacherInkChunk(_ chunk: TeacherInkStrokeChunk) {
        publishedChunks.append(chunk)
    }

    func publishTeacherInkDrawingSnapshot(_ snapshot: TeacherInkDrawingSnapshot) {
        publishedInkDrawingSnapshots.append(snapshot)
    }

    func publishTeacherObjectSnapshot(_ snapshot: TeacherObjectSnapshot) {
        publishedObjectSnapshots.append(snapshot)
    }

    func publishTeacherSlideManifestSnapshot(_ snapshot: TeacherSlideManifestSnapshot) {
        publishedSlideManifestSnapshots.append(snapshot)
    }

    func stop() {
        didStop = true
    }

    func deliver(_ chunk: TeacherInkStrokeChunk) {
        onTeacherInkChunk?(chunk)
    }
}

@MainActor
private final class FakeStudentFirebaseAuthProvider: StudentFirebaseAuthenticating {
    var currentUserID: String?
    let anonymousUserID: String
    var anonymousSignInCount = 0

    init(currentUserID: String? = nil, anonymousUserID: String = "anonymous-student") {
        self.currentUserID = currentUserID
        self.anonymousUserID = anonymousUserID
    }

    func signInAnonymously() async throws -> String {
        anonymousSignInCount += 1
        currentUserID = anonymousUserID
        return anonymousUserID
    }
}

@MainActor
private final class FakeTeacherAuthProvider: TeacherAuthenticating {
    var currentUserID: String?
    var currentEmail: String?
    var error: Error?

    init(currentUserID: String? = nil, currentEmail: String? = nil, error: Error? = nil) {
        self.currentUserID = currentUserID
        self.currentEmail = currentEmail
        self.error = error
    }

    func signIn(email: String, password: String) async throws {
        if let error {
            throw error
        }
        currentUserID = "teacher-user"
        currentEmail = email
    }

    func createAccount(email: String, password: String) async throws {
        if let error {
            throw error
        }
        currentUserID = "teacher-user"
        currentEmail = email
    }

    func signOut() throws {
        if let error {
            throw error
        }
        currentUserID = nil
        currentEmail = nil
    }
}

private enum TeacherAuthTestError: LocalizedError {
    case failed

    var errorDescription: String? {
        switch self {
        case .failed:
            return "Teacher auth failed."
        }
    }
}
