//
//  MathBoardTests.swift
//  MathBoardTests
//

import CoreGraphics
import Foundation
import Testing
import Documents
@testable import Canvas
import Slides

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
}
