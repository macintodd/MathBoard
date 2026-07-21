import CoreGraphics
import Foundation
import Testing
@testable import WidgetEngine

struct WidgetEngineTests {
    @Test func widgetSidecarURLUsesDrawingBaseName() throws {
        let drawingURL = URL(fileURLWithPath: "/tmp/slide-123.drawing")
        let sidecarURL = WidgetObject.sidecarURL(forDrawingURL: drawingURL)

        #expect(sidecarURL.lastPathComponent == "slide-123.widgets.json")
        #expect(sidecarURL.deletingLastPathComponent() == drawingURL.deletingLastPathComponent())
    }

    @Test func widgetRuntimeStateRoundTripsThroughSidecarJSON() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetEngineTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let firstID = UUID()
        let secondID = UUID()
        let drawingURL = directoryURL.appendingPathComponent("slide-abc.drawing")
        let sidecarURL = WidgetObject.sidecarURL(forDrawingURL: drawingURL)
        let widgets = [
            WidgetObject(
                id: firstID,
                name: "First widget",
                codeString: WidgetSamples.orderOpsActivityJSON,
                frame: CGRect(x: 24, y: 32, width: 740, height: 360),
                activityRuntimeState: WidgetActivityRuntimeState(
                    multipleChoice: WidgetMultipleChoiceRuntimeState(score: 4, attempts: 5, streak: 2)
                )
            ),
            WidgetObject(
                id: secondID,
                name: "Second widget",
                codeString: WidgetSamples.orderOpsActivityJSON,
                frame: CGRect(x: 40, y: 420, width: 740, height: 360),
                activityRuntimeState: WidgetActivityRuntimeState(
                    multipleChoice: WidgetMultipleChoiceRuntimeState(score: 1, attempts: 3, streak: 0)
                )
            )
        ]

        try WidgetObject.save(widgets, to: sidecarURL)
        let loaded = WidgetObject.load(from: sidecarURL)

        #expect(loaded == widgets)
        #expect(loaded.map(\.id) == [firstID, secondID])
        #expect(loaded[0].activityRuntimeState?.multipleChoice.score == 4)
        #expect(loaded[1].activityRuntimeState?.multipleChoice.score == 1)
    }

    @Test func scoreSheetUsesWidgetInstanceIDsForDuplicateActivityDocuments() throws {
        let sharedJSON = WidgetSamples.orderOpsActivityJSON
        let firstID = UUID()
        let secondID = UUID()
        let widgets = [
            WidgetObject(
                id: firstID,
                name: "Warmup",
                codeString: sharedJSON,
                frame: CGRect(x: 0, y: 0, width: 600, height: 320),
                activityRuntimeState: WidgetActivityRuntimeState(
                    multipleChoice: WidgetMultipleChoiceRuntimeState(score: 3, attempts: 4)
                )
            ),
            WidgetObject(
                id: secondID,
                name: "Exit Ticket",
                codeString: sharedJSON,
                frame: CGRect(x: 0, y: 340, width: 600, height: 320),
                activityRuntimeState: WidgetActivityRuntimeState(
                    multipleChoice: WidgetMultipleChoiceRuntimeState(score: 2, attempts: 4)
                )
            )
        ]

        let scoreSheet = WidgetActivityScoreSheet(widgets: widgets)

        #expect(scoreSheet.records.map(\.id) == [firstID.uuidString, secondID.uuidString])
        #expect(scoreSheet.records.map(\.title) == ["Warmup", "Exit Ticket"])
    }

    @Test func missingWidgetSidecarLoadsAsEmptyArray() {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).widgets.json")

        #expect(WidgetObject.load(from: missingURL).isEmpty)
    }

    @Test func activityJSONRepairsUnescapedLaTeXCommandsFromAIOutput() throws {
        let source = #"""
        {
          "schemaVersion": 1,
          "widgetId": "latex-repair",
          "activity": "multipleChoice",
          "title": "LaTeX Repair",
          "learningObjective": "Decode AI-authored LaTeX commands.",
          "rules": {
            "advanceMode": "manual"
          },
          "questions": [
            {
              "id": "q1",
              "prompt": "Evaluate.",
              "expression": "5 + 3 \cdot 4",
              "choices": [
                { "id": "a", "label": "17", "isCorrect": true },
                { "id": "b", "label": "\frac{10}{2}", "isCorrect": false }
              ],
              "hints": []
            }
          ]
        }
        """#

        let result = WidgetActivityJSONCodec.decode(source)

        #expect(result.errors.isEmpty)
        #expect(result.document?.questions.first?.expression == #"5 + 3 \cdot 4"#)
        #expect(result.document?.questions.first?.choices.last?.label == #"\frac{10}{2}"#)
    }
}
