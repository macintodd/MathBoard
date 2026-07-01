//
//  ToolPaletteStateTests.swift
//  MathBoardCore - ToolPalette tests
//

import Testing
@testable import ToolPalette

@Suite("Tool palette state")
struct ToolPaletteStateTests {
    @Test func defaultStateStartsOnPen() {
        let state = ToolPaletteState()

        #expect(state.activeTool == .pen)
        #expect(state.strokeColor == .graphite)
        #expect(state.penColor == .graphite)
        #expect(state.markerColor == .graphite)
        #expect(state.laserColor == .graphite)
        #expect(state.activeStrokeColor == .graphite)
        #expect(state.palettePreset == .bright)
        #expect(state.strokeWidth == 6)
        #expect(state.opacity == 1)
        #expect(state.penStrokeWidth == 6)
        #expect(state.penOpacity == 1)
        #expect(state.markerStrokeWidth == 18)
        #expect(state.markerOpacity == 0.5)
        #expect(state.laserDuration == 3)
        #expect(state.geometryLineArrowMode == .none)
        #expect(state.geometryFillOpacity == 0.35)
        #expect(state.textStyle == .normal)
        #expect(state.textIsItalic == false)
        #expect(state.textIsUnderlined == false)
        #expect(state.textSize == 28)
        #expect(state.textFontName == "System")
    }

    @Test func strokeColorChangesOnlyAffectTheActiveColorTool() {
        var state = ToolPaletteState()

        ToolPaletteReducer.reduce(&state, command: .setStrokeColor(.mint))
        #expect(state.penColor == .mint)
        #expect(state.markerColor == .graphite)
        #expect(state.laserColor == .graphite)

        ToolPaletteReducer.reduce(&state, command: .selectTool(.marker))
        ToolPaletteReducer.reduce(&state, command: .setStrokeColor(.amber))
        #expect(state.penColor == .mint)
        #expect(state.markerColor == .amber)
        #expect(state.laserColor == .graphite)
        #expect(state.activeStrokeColor == .amber)

        ToolPaletteReducer.reduce(&state, command: .selectTool(.laser))
        ToolPaletteReducer.reduce(&state, command: .setStrokeColor(.coral))
        #expect(state.penColor == .mint)
        #expect(state.markerColor == .amber)
        #expect(state.laserColor == .coral)
        #expect(state.activeStrokeColor == .coral)
    }

    @Test func penDefinitionExposesColorOrbitAndSliders() throws {
        let state = ToolPaletteState()
        let definition = ToolPaletteDefinitions.definition(for: .pen)
        let configuration = definition.configuration(for: state)

        #expect(configuration.topOrbit.count == 7)
        #expect(configuration.topOrbit.first?.command == .openColorPicker)
        #expect(configuration.topOrbit.last?.command == .openColorPaletteChooser)

        guard case .slider(let width) = configuration.leftArc else {
            Issue.record("Expected pen left arc to be width slider")
            return
        }
        #expect(width.id == "pen.width")
        #expect(width.value == 6)

        guard case .slider(let opacity) = configuration.rightArc else {
            Issue.record("Expected pen right arc to be opacity slider")
            return
        }
        #expect(opacity.id == "pen.opacity")
        #expect(opacity.value == 1)
    }

    @Test func markerDefinitionExposesColorOrbitAndSliders() throws {
        let state = ToolPaletteState(activeTool: .marker)
        let definition = ToolPaletteDefinitions.definition(for: .marker)
        let configuration = definition.configuration(for: state)

        #expect(configuration.topOrbit.count == 7)
        #expect(configuration.topOrbit.first?.command == .openColorPicker)
        #expect(configuration.topOrbit.last?.command == .openColorPaletteChooser)

        guard case .slider(let width) = configuration.leftArc else {
            Issue.record("Expected marker left arc to be width slider")
            return
        }
        #expect(width.id == "marker.width")
        #expect(width.value == 18)
        #expect(width.range == 4...36)

        guard case .slider(let opacity) = configuration.rightArc else {
            Issue.record("Expected marker right arc to be opacity slider")
            return
        }
        #expect(opacity.id == "marker.opacity")
        #expect(opacity.value == 0.5)
    }

    @Test func eraserDefinitionExposesSizeSliderAndModeSegments() throws {
        let state = ToolPaletteState(activeTool: .eraser, eraserMode: .stroke)
        let definition = ToolPaletteDefinitions.definition(for: .eraser)
        let configuration = definition.configuration(for: state)

        #expect(configuration.topOrbit.isEmpty)

        guard case .slider(let size) = configuration.leftArc else {
            Issue.record("Expected eraser left arc to be size slider")
            return
        }
        #expect(size.id == "eraser.size")
        #expect(size.range == 4...40)

        guard case .segmented(let mode) = configuration.rightArc else {
            Issue.record("Expected eraser right arc to be mode segments")
            return
        }
        #expect(mode.id == "eraser.mode")
        #expect(mode.segments.count == 2)
        #expect(mode.segments[1].isSelected)
    }

    @Test func laserDefinitionExposesColorOrbitDiameterAndDurationSliders() throws {
        let state = ToolPaletteState(activeTool: .laser, laserDuration: 4)
        let definition = ToolPaletteDefinitions.definition(for: .laser)
        let configuration = definition.configuration(for: state)

        #expect(configuration.topOrbit.count == 7)
        #expect(configuration.topOrbit.first?.command == .openColorPicker)
        #expect(configuration.topOrbit.last?.command == .openColorPaletteChooser)

        guard case .slider(let diameter) = configuration.leftArc else {
            Issue.record("Expected laser left arc to be diameter slider")
            return
        }
        #expect(diameter.id == "laser.diameter")
        #expect(diameter.range == 3...28)

        guard case .slider(let duration) = configuration.rightArc else {
            Issue.record("Expected laser right arc to be duration slider")
            return
        }
        #expect(duration.id == "laser.duration")
        #expect(duration.value == 4)
        #expect(duration.range == 0...10)
    }

    @Test func selectionDefinitionExposesActionsTargetAndModeSegments() throws {
        let state = ToolPaletteState(activeTool: .selection, selectionTarget: .object, selectionMode: .marquee)
        let definition = ToolPaletteDefinitions.definition(for: .selection)
        let configuration = definition.configuration(for: state)

        #expect(configuration.topOrbit.count == 5)
        #expect(configuration.topOrbit.map(\.command).contains(.copySelection))
        #expect(configuration.topOrbit.map(\.command).contains(.deleteSelection))
        #expect(configuration.topOrbit.map(\.command).contains(.sendSelectionToNextSlide))

        guard case .segmented(let target) = configuration.leftArc else {
            Issue.record("Expected selection left arc to be target segments")
            return
        }
        #expect(target.id == "selection.target")
        #expect(target.segments.count == 2)
        #expect(target.segments[0].isSelected)

        guard case .segmented(let mode) = configuration.rightArc else {
            Issue.record("Expected selection right arc to be mode segments")
            return
        }
        #expect(mode.id == "selection.mode")
        #expect(mode.segments.count == 2)
        #expect(mode.segments[1].isSelected)
    }

    @Test func geometryDefinitionExposesColorsShapesAndAdaptiveControls() throws {
        let lineState = ToolPaletteState(activeTool: .geometry, geometryType: .line, geometryLineArrowMode: .both)
        let lineDefinition = ToolPaletteDefinitions.definition(for: .geometry)
        let lineConfiguration = lineDefinition.configuration(for: lineState)

        #expect(lineConfiguration.topOrbit.count == 8)
        #expect(lineConfiguration.topOrbit.first?.command == .openColorPicker)
        #expect(lineConfiguration.topOrbit[1].command == .openFillColorPicker)

        guard case .slider(let stroke) = lineConfiguration.leftArc else {
            Issue.record("Expected geometry left arc to be stroke slider")
            return
        }
        #expect(stroke.id == "geometry.strokeWidth")

        guard case .slider(let arrows) = lineConfiguration.rightArc else {
            Issue.record("Expected line right arc to be arrow slider")
            return
        }
        #expect(arrows.id == "geometry.lineArrows")
        #expect(arrows.value == 3)
        #expect(arrows.range == 0...3)

        let polygonState = ToolPaletteState(activeTool: .geometry, geometryType: .polygon, polygonSides: 7)
        let polygonConfiguration = lineDefinition.configuration(for: polygonState)
        guard case .slider(let sides) = polygonConfiguration.rightArc else {
            Issue.record("Expected polygon right arc to be sides slider")
            return
        }
        #expect(sides.id == "geometry.polygonSides")
        #expect(sides.value == 7)

        let circleState = ToolPaletteState(activeTool: .geometry, geometryType: .circle, geometryFillOpacity: 0.5)
        let circleConfiguration = lineDefinition.configuration(for: circleState)
        guard case .slider(let fill) = circleConfiguration.rightArc else {
            Issue.record("Expected filled geometry right arc to be fill opacity slider")
            return
        }
        #expect(fill.id == "geometry.fillOpacity")
        #expect(fill.value == 0.5)
    }

    @Test func textDefinitionExposesStyleActionsSizeAndFontPicker() throws {
        let state = ToolPaletteState(
            activeTool: .equation,
            textStyle: .bold,
            textIsItalic: true,
            textSize: 36,
            textFontName: "Serif"
        )
        let definition = ToolPaletteDefinitions.definition(for: .equation)
        let configuration = definition.configuration(for: state)

        #expect(ToolID.equation.displayName == "Text")
        #expect(configuration.topOrbit.count == 4)
        #expect(configuration.topOrbit.map(\.command).contains(.setTextBold(false)))
        #expect(configuration.topOrbit.map(\.command).contains(.setTextItalic(false)))
        #expect(configuration.topOrbit.map(\.command).contains(.openLatexEditor))

        guard case .slider(let size) = configuration.leftArc else {
            Issue.record("Expected text left arc to be size slider")
            return
        }
        #expect(size.id == "text.size")
        #expect(size.value == 36)
        #expect(size.range == 8...96)

        guard case .segmented(let font) = configuration.rightArc else {
            Issue.record("Expected text right arc to be font sample")
            return
        }
        #expect(font.id == "text.font")
        #expect(font.segments.count == 1)
        #expect(font.segments[0].command == .openFontPicker)
    }

    @Test func widgetDefinitionExposesWidgetActions() throws {
        let state = ToolPaletteState(activeTool: .reserved)
        let definition = ToolPaletteDefinitions.definition(for: .reserved)
        let configuration = definition.configuration(for: state)

        #expect(ToolID.reserved.displayName == "Widget")
        #expect(configuration.topOrbit.count == 4)
        #expect(configuration.topOrbit.map(\.command).contains(.createWidget))
        #expect(configuration.topOrbit.map(\.command).contains(.editWidget))
        #expect(configuration.topOrbit.map(\.command).contains(.openWidget))
        #expect(configuration.topOrbit.map(\.command).contains(.removeWidget))

        guard case .disabled(let leftLabel) = configuration.leftArc else {
            Issue.record("Expected widget left arc to describe HTML")
            return
        }
        #expect(leftLabel == "HTML")

        guard case .disabled(let rightLabel) = configuration.rightArc else {
            Issue.record("Expected widget right arc to describe slide limit")
            return
        }
        #expect(rightLabel == "One per slide")
    }

    @Test func reducerUpdatesPenState() {
        var state = ToolPaletteState()

        ToolPaletteReducer.reduce(&state, command: .setStrokeColor(.sky))
        ToolPaletteReducer.reduce(&state, command: .setPalettePreset(.jewel))
        ToolPaletteReducer.reduce(&state, command: .setStrokeWidth(12))
        ToolPaletteReducer.reduce(&state, command: .setOpacity(0.5))
        ToolPaletteReducer.reduce(&state, command: .setLaserDuration(4.5))
        ToolPaletteReducer.reduce(&state, command: .setGeometryType(.rectangle))
        ToolPaletteReducer.reduce(&state, command: .setGeometryLineArrowMode(.end))
        ToolPaletteReducer.reduce(&state, command: .setGeometryFillOpacity(0.6))
        ToolPaletteReducer.reduce(&state, command: .setSelectionTarget(.object))
        ToolPaletteReducer.reduce(&state, command: .setSelectionMode(.marquee))
        ToolPaletteReducer.reduce(&state, command: .setEraserMode(.stroke))
        ToolPaletteReducer.reduce(&state, command: .setTextBold(true))
        ToolPaletteReducer.reduce(&state, command: .setTextItalic(true))
        ToolPaletteReducer.reduce(&state, command: .setTextUnderlined(true))
        ToolPaletteReducer.reduce(&state, command: .setTextSize(44))
        ToolPaletteReducer.reduce(&state, command: .setTextFontName("Serif"))
        ToolPaletteReducer.reduce(&state, command: .setLatexSource("\\frac{1}{2}"))

        #expect(state.strokeColor == .sky)
        #expect(state.palettePreset == .jewel)
        #expect(state.strokeWidth == 12)
        #expect(state.opacity == 0.5)
        #expect(state.penStrokeWidth == 12)
        #expect(state.penOpacity == 0.5)
        #expect(state.laserDuration == 4.5)
        #expect(state.geometryType == .rectangle)
        #expect(state.geometryLineArrowMode == .end)
        #expect(state.geometryFillOpacity == 0.6)
        #expect(state.selectionTarget == .object)
        #expect(state.selectionMode == .marquee)
        #expect(state.eraserMode == .stroke)
        #expect(state.textStyle == .bold)
        #expect(state.textIsItalic)
        #expect(state.textIsUnderlined)
        #expect(state.textSize == 44)
        #expect(state.textFontName == "Serif")
        #expect(state.latexSource == "\\frac{1}{2}")
    }

    @Test func reducerClampsWidthAndOpacity() {
        var state = ToolPaletteState()

        ToolPaletteReducer.reduce(&state, command: .setStrokeWidth(100))
        ToolPaletteReducer.reduce(&state, command: .setOpacity(-2))
        ToolPaletteReducer.reduce(&state, command: .setLaserDuration(-2))
        ToolPaletteReducer.reduce(&state, command: .setGeometryFillOpacity(2))
        ToolPaletteReducer.reduce(&state, command: .setTextSize(200))

        #expect(state.strokeWidth == 40)
        #expect(state.opacity == 0.1)
        #expect(state.penStrokeWidth == 24)
        #expect(state.penOpacity == 0.1)
        #expect(state.laserDuration == 0)
        #expect(state.geometryFillOpacity == 1)
        #expect(state.textSize == 96)
    }

    @Test func selectingToolClosesColorBloom() {
        var state = ToolPaletteState(isColorBloomOpen: true)

        ToolPaletteReducer.reduce(&state, command: .selectTool(.marker))

        #expect(state.activeTool == .marker)
        #expect(state.isColorBloomOpen == false)
    }

    @Test func penAndMarkerKeepIndependentWidthAndOpacity() {
        var state = ToolPaletteState()

        ToolPaletteReducer.reduce(&state, command: .setStrokeWidth(10))
        ToolPaletteReducer.reduce(&state, command: .setOpacity(0.9))
        ToolPaletteReducer.reduce(&state, command: .selectTool(.marker))
        ToolPaletteReducer.reduce(&state, command: .setStrokeWidth(24))
        ToolPaletteReducer.reduce(&state, command: .setOpacity(0.5))

        #expect(state.penStrokeWidth == 10)
        #expect(state.penOpacity == 0.9)
        #expect(state.markerStrokeWidth == 24)
        #expect(state.markerOpacity == 0.5)

        let penConfiguration = ToolPaletteDefinitions.definition(for: .pen)
            .configuration(for: ToolPaletteState(penStrokeWidth: state.penStrokeWidth, penOpacity: state.penOpacity))
        guard case .slider(let penWidth) = penConfiguration.leftArc,
              case .slider(let penOpacity) = penConfiguration.rightArc else {
            Issue.record("Expected pen width and opacity sliders")
            return
        }
        #expect(penWidth.value == 10)
        #expect(penOpacity.value == 0.9)

        let markerConfiguration = ToolPaletteDefinitions.definition(for: .marker).configuration(for: state)
        guard case .slider(let markerWidth) = markerConfiguration.leftArc,
              case .slider(let markerOpacity) = markerConfiguration.rightArc else {
            Issue.record("Expected marker width and opacity sliders")
            return
        }
        #expect(markerWidth.value == 24)
        #expect(markerOpacity.value == 0.5)
    }
}
