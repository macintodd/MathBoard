//
//  ExternalCanvasView.swift
//  MathBoardCore — Presentation module
//
//  Renders the iPad canvas content on an external display. Observes
//  `DisplayBroker.shared.currentFrame` and re-renders whenever the iPad
//  publishes a new frame.
//
//  Layout uses `GeometryReader` and explicit `.frame(width:height:)`
//  rather than `.aspectRatio(contentMode: .fit)` — SwiftUI's automatic
//  aspect-fit was producing inconsistent results across screen scales
//  and image sizes (mirror clipping to a corner instead of expanding).
//  Computing the fitted size by hand is verbose but reliable.
//

#if os(iOS)

import SwiftUI
import Canvas
import Calculator
import GraphCalculator
import ToolPalette

public struct ExternalCanvasView: View {

    private let broker = DisplayBroker.shared
    private let paletteSettings = ToolPaletteSettings.shared

    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black

                if let frame = broker.currentFrame {
                    let aspect = CGFloat(frame.width) / CGFloat(frame.height)
                    let fitted = Self.fittedSize(forAspect: aspect, in: proxy.size)
                    ZStack(alignment: .topLeading) {
                        TransformedCanvasFrame(
                            frame: frame,
                            fittedSize: fitted,
                            frameSourceRect: broker.currentFrameSourceRect,
                            viewportSourceRect: broker.currentViewportSourceRect
                        )

                        if !broker.completedLiveStrokes.isEmpty || broker.currentLiveStroke != nil {
                            LiveStrokeOverlay(
                                strokes: broker.completedLiveStrokes + [broker.currentLiveStroke].compactMap { $0 },
                                viewportSourceRect: broker.currentViewportSourceRect,
                                fallbackSourceSize: Self.liveStrokeSourceSize(
                                    frame: frame,
                                    frameSourceRect: broker.currentFrameSourceRect,
                                    viewportSourceRect: broker.currentViewportSourceRect
                                ),
                                fittedSize: fitted
                            )
                        }

                        CalculatorTVOverlay(
                            state: .shared,
                            referenceSize: broker.calculatorReferenceSize ?? fitted
                        )
                        .allowsHitTesting(false)

                        if broker.isGraphCalculatorVisible {
                            let referenceSize = broker.calculatorReferenceSize ?? fitted
                            let visibleReferenceRect = Self.graphCalculatorVisibleReferenceRect(
                                mode: broker.mode,
                                referenceSize: referenceSize
                            )
                            let graphCalcScale = Self.graphCalculatorScale(
                                fittedSize: fitted,
                                visibleReferenceSize: Self.graphCalculatorSafeReferenceSize(visibleReferenceRect.size)
                            )
                            GraphCalculatorView(state: broker.graphCalculator)
                                .frame(width: referenceSize.width, height: referenceSize.height)
                                .offset(x: -visibleReferenceRect.minX, y: -visibleReferenceRect.minY)
                                .scaleEffect(graphCalcScale, anchor: .topLeading)
                                .allowsHitTesting(false)
                        }

                        if broker.mode == .mirror, paletteSettings.isCustomPaletteEnabled {
                            let referenceSize = broker.toolPaletteReferenceSize ?? fitted
                            let paletteScale = Self.toolPaletteScale(fittedSize: fitted, referenceSize: referenceSize)
                            switch paletteSettings.paletteStyle {
                            case .radial:
                                FloatingToolPaletteView(
                                    state: toolPaletteStateBinding,
                                    isExpanded: toolPaletteExpandedBinding,
                                    center: scaledToolPaletteCenterBinding(
                                        fittedSize: fitted,
                                        referenceSize: referenceSize
                                    ),
                                    dialSize: paletteSettings.paletteSize.dialSize * paletteScale,
                                    collapsedSize: paletteSettings.paletteSize.collapsedSize * paletteScale,
                                    onCommand: { _ in }
                                )
                                .allowsHitTesting(false)
                            case .compact:
                                CompactToolPaletteView(
                                    state: toolPaletteStateBinding,
                                    onCommand: { _ in }
                                )
                                .scaleEffect(paletteScale)
                                .position(
                                    scaledCompactToolPaletteCenter(
                                        fittedSize: fitted,
                                        referenceSize: referenceSize,
                                        paletteScale: paletteScale
                                    )
                                )
                                .allowsHitTesting(false)
                            }
                        }
                    }
                    .frame(width: fitted.width, height: fitted.height)
                    .clipped()
                } else {
                    ExternalDisplayPlaceholder()
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
    }

    /// Largest CGSize with `aspect` that fits inside `container`.
    private static func fittedSize(forAspect aspect: CGFloat, in container: CGSize) -> CGSize {
        guard container.width > 0, container.height > 0, aspect > 0 else { return .zero }
        let containerAspect = container.width / container.height
        if aspect > containerAspect {
            // Source is wider than container — fit by width, letterbox top/bottom.
            return CGSize(width: container.width, height: container.width / aspect)
        } else {
            // Source is taller (or same aspect) — fit by height, letterbox left/right.
            return CGSize(width: container.height * aspect, height: container.height)
        }
    }

    private var toolPaletteStateBinding: Binding<ToolPaletteState> {
        Binding(
            get: { broker.toolPaletteState },
            set: { _ in }
        )
    }

    private var toolPaletteExpandedBinding: Binding<Bool> {
        Binding(
            get: { broker.isToolPaletteExpanded },
            set: { _ in }
        )
    }

    private static func toolPaletteScale(fittedSize: CGSize, referenceSize: CGSize) -> CGFloat {
        guard fittedSize.width > 0,
              fittedSize.height > 0,
              referenceSize.width > 0,
              referenceSize.height > 0 else { return 1 }
        return min(fittedSize.width / referenceSize.width, fittedSize.height / referenceSize.height)
    }

    private static func graphCalculatorScale(fittedSize: CGSize, visibleReferenceSize: CGSize) -> CGFloat {
        guard fittedSize.width > 0,
              fittedSize.height > 0,
              visibleReferenceSize.width > 0,
              visibleReferenceSize.height > 0 else { return 1 }
        return min(fittedSize.width / visibleReferenceSize.width, fittedSize.height / visibleReferenceSize.height)
    }

    private static let graphCalculatorTVSafeInset: CGFloat = 24

    private static func graphCalculatorSafeReferenceSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: size.width + graphCalculatorTVSafeInset,
            height: size.height + graphCalculatorTVSafeInset
        )
    }

    private static func graphCalculatorVisibleReferenceRect(mode: CanvasPresentationMode, referenceSize: CGSize) -> CGRect {
        guard referenceSize.width > 0, referenceSize.height > 0 else {
            return CGRect(origin: .zero, size: referenceSize)
        }

        switch mode {
        case .mirror:
            return CGRect(origin: .zero, size: referenceSize)
        case .present:
            let targetAspect: CGFloat = 16.0 / 9.0
            let referenceAspect = referenceSize.width / referenceSize.height
            let visibleSize: CGSize
            if referenceAspect > targetAspect {
                visibleSize = CGSize(width: referenceSize.height * targetAspect, height: referenceSize.height)
            } else {
                visibleSize = CGSize(width: referenceSize.width, height: referenceSize.width / targetAspect)
            }
            return CGRect(
                x: (referenceSize.width - visibleSize.width) / 2,
                y: (referenceSize.height - visibleSize.height) / 2,
                width: visibleSize.width,
                height: visibleSize.height
            )
        }
    }

    private func scaledToolPaletteCenterBinding(fittedSize: CGSize, referenceSize: CGSize) -> Binding<CGPoint?> {
        Binding(
            get: {
                guard let center = broker.toolPaletteCenter,
                      referenceSize.width > 0,
                      referenceSize.height > 0 else {
                    return nil
                }

                return CGPoint(
                    x: center.x * fittedSize.width / referenceSize.width,
                    y: center.y * fittedSize.height / referenceSize.height
                )
            },
            set: { _ in }
        )
    }

    private func scaledCompactToolPaletteCenter(fittedSize: CGSize, referenceSize: CGSize, paletteScale: CGFloat) -> CGPoint {
        guard let center = broker.compactToolPaletteCenter,
              referenceSize.width > 0,
              referenceSize.height > 0 else {
            return CGPoint(
                x: fittedSize.width - Self.compactPaletteFallbackSize.width * paletteScale / 2 - 16 * paletteScale,
                y: Self.compactPaletteFallbackSize.height * paletteScale / 2 + 16 * paletteScale
            )
        }

        return CGPoint(
            x: center.x * fittedSize.width / referenceSize.width,
            y: center.y * fittedSize.height / referenceSize.height
        )
    }

    private static let compactPaletteFallbackSize = CGSize(width: 360, height: 420)

    private static func liveStrokeSourceSize(
        frame: CGImage,
        frameSourceRect: CGRect?,
        viewportSourceRect: CGRect?
    ) -> CGSize {
        guard let frameSourceRect,
              let viewportSourceRect,
              frameSourceRect.width > 0,
              frameSourceRect.height > 0,
              viewportSourceRect.width > 0,
              viewportSourceRect.height > 0 else {
            return CGSize(width: CGFloat(frame.width), height: CGFloat(frame.height))
        }

        return CGSize(
            width: CGFloat(frame.width) * viewportSourceRect.width / frameSourceRect.width,
            height: CGFloat(frame.height) * viewportSourceRect.height / frameSourceRect.height
        )
    }
}

private struct TransformedCanvasFrame: View {
    let frame: CGImage
    let fittedSize: CGSize
    let frameSourceRect: CGRect?
    let viewportSourceRect: CGRect?

    var body: some View {
        ZStack {
            Color.white

            Image(decorative: croppedFrame ?? frame, scale: 1.0)
                .resizable()
                .interpolation(.high)
        }
        .frame(width: fittedSize.width, height: fittedSize.height)
        .allowsHitTesting(false)
    }

    private var croppedFrame: CGImage? {
        guard let frameSourceRect,
              let viewportSourceRect,
              frameSourceRect.width > 0,
              frameSourceRect.height > 0,
              viewportSourceRect.width > 0,
              viewportSourceRect.height > 0,
              frame.width > 0,
              frame.height > 0 else {
            return nil
        }

        let intersection = viewportSourceRect.intersection(frameSourceRect)
        guard !intersection.isNull,
              intersection.width > 0,
              intersection.height > 0 else { return nil }

        let scaleX = CGFloat(frame.width) / frameSourceRect.width
        let scaleY = CGFloat(frame.height) / frameSourceRect.height
        let cropRect = CGRect(
            x: (intersection.minX - frameSourceRect.minX) * scaleX,
            y: (intersection.minY - frameSourceRect.minY) * scaleY,
            width: intersection.width * scaleX,
            height: intersection.height * scaleY
        ).integral

        let boundedCropRect = cropRect.intersection(
            CGRect(x: 0, y: 0, width: frame.width, height: frame.height)
        )
        guard !boundedCropRect.isNull,
              boundedCropRect.width > 0,
              boundedCropRect.height > 0 else { return nil }

        return frame.cropping(to: boundedCropRect)
    }
}

private struct LiveStrokeOverlay: View {
    let strokes: [CanvasLiveStroke]
    let viewportSourceRect: CGRect?
    let fallbackSourceSize: CGSize
    let fittedSize: CGSize

    var body: some View {
        if strokes.contains(where: \.isTransient) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
                overlayCanvas(currentTime: ProcessInfo.processInfo.systemUptime)
            }
        } else {
            overlayCanvas(currentTime: ProcessInfo.processInfo.systemUptime)
        }
    }

    private func overlayCanvas(currentTime: TimeInterval) -> some View {
        SwiftUI.Canvas { context, _ in
            for stroke in strokes {
                let color = Color(
                    red: Double(stroke.color.red),
                    green: Double(stroke.color.green),
                    blue: Double(stroke.color.blue),
                    opacity: Double(stroke.color.alpha)
                )

                switch stroke.kind {
                case .laserDot:
                    let samples = visibleScaledSamples(for: stroke, currentTime: currentTime)
                    guard let sample = samples.last else { continue }
                    let point = sample.location
                    let diameter = max(scaledLineWidth(for: stroke), 4)
                    let alpha = laserAlpha(for: sample, in: stroke, currentTime: currentTime, maximum: 1)
                    let rect = CGRect(
                        x: point.x - diameter / 2,
                        y: point.y - diameter / 2,
                        width: diameter,
                        height: diameter
                    )
                    drawLaserDot(in: &context, rect: rect, color: color, alpha: alpha)

                case .laserTrail:
                    let samples = visibleScaledSamples(for: stroke, currentTime: currentTime)
                    guard !samples.isEmpty else { continue }
                    if samples.count == 1, let sample = samples.first {
                        let point = sample.location
                        let diameter = max(scaledLineWidth(for: stroke), 4)
                        let alpha = laserAlpha(for: sample, in: stroke, currentTime: currentTime, maximum: 1)
                        let rect = CGRect(
                            x: point.x - diameter / 2,
                            y: point.y - diameter / 2,
                            width: diameter,
                            height: diameter
                        )
                        drawLaserDot(in: &context, rect: rect, color: color, alpha: alpha)
                    } else {
                        context.drawLayer { layer in
                            for pair in zip(samples, samples.dropFirst()) {
                                let alpha = laserAlpha(for: pair.1, in: stroke, currentTime: currentTime, maximum: 1)
                                var path = Path()
                                path.move(to: pair.0.location)
                                path.addLine(to: pair.1.location)
                                drawLaserPath(path, in: &layer, baseWidth: scaledLineWidth(for: stroke), color: color, alpha: alpha)
                            }
                        }
                    }

                case .ink where stroke.color.alpha >= 0.95:
                    context.stroke(
                        CanvasVectorInk.smoothedPath(points: scaledPoints(for: stroke)),
                        with: .color(color),
                        style: StrokeStyle(
                            lineWidth: CanvasVectorInk.crispLineWidth(baseLineWidth: scaledLineWidth(for: stroke)),
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )

                case .ink:
                    context.stroke(
                        CanvasVectorInk.smoothedPath(points: scaledPoints(for: stroke)),
                        with: .color(color),
                        style: StrokeStyle(
                            lineWidth: scaledLineWidth(for: stroke),
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                }
            }
        }
        .frame(width: fittedSize.width, height: fittedSize.height)
        .allowsHitTesting(false)
    }

    private func drawLaserDot(
        in context: inout GraphicsContext,
        rect: CGRect,
        color: Color,
        alpha: CGFloat
    ) {
        let beamWidth = max(rect.width, 3)

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: beamWidth * 3))
            layer.fill(Path(ellipseIn: rect), with: .color(color.opacity(Double(alpha) * 0.30)))
        }

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: beamWidth))
            layer.fill(Path(ellipseIn: rect), with: .color(color.opacity(Double(alpha) * 0.70)))
        }

        context.drawLayer { layer in
            layer.blendMode = .screen
            layer.fill(Path(ellipseIn: rect), with: .color(color.opacity(Double(alpha))))
            layer.fill(
                Path(ellipseIn: rect.insetBy(dx: rect.width * 0.18, dy: rect.height * 0.18)),
                with: .color(.white.opacity(Double(alpha) * 0.38))
            )
            layer.fill(
                Path(ellipseIn: rect.insetBy(dx: rect.width * 0.30, dy: rect.height * 0.30)),
                with: .color(color.opacity(Double(alpha) * 0.92))
            )
            layer.fill(
                Path(ellipseIn: rect.insetBy(dx: rect.width * 0.43, dy: rect.height * 0.43)),
                with: .color(.white.opacity(Double(alpha) * 0.72))
            )
            layer.fill(
                Path(ellipseIn: rect.insetBy(dx: rect.width * 0.39, dy: rect.height * 0.39)),
                with: .color(color.opacity(Double(alpha) * 0.45))
            )
        }
    }

    private func drawLaserPath(
        _ path: Path,
        in context: inout GraphicsContext,
        baseWidth: CGFloat,
        color: Color,
        alpha: CGFloat
    ) {
        let beamWidth = max(baseWidth, 3)

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: beamWidth * 3))
            layer.stroke(
                path,
                with: .color(color.opacity(Double(alpha) * 0.30)),
                style: laserStrokeStyle(lineWidth: max(beamWidth * 1.65, 6))
            )
        }

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: beamWidth))
            layer.stroke(
                path,
                with: .color(color.opacity(Double(alpha) * 0.70)),
                style: laserStrokeStyle(lineWidth: max(beamWidth * 0.95, 4))
            )
        }

        context.drawLayer { layer in
            layer.blendMode = .screen
            layer.stroke(
                path,
                with: .color(color.opacity(Double(alpha))),
                style: laserStrokeStyle(lineWidth: max(beamWidth * 0.46, 2))
            )
            layer.stroke(
                path,
                with: .color(.white.opacity(Double(alpha) * 0.38)),
                style: laserStrokeStyle(lineWidth: max(beamWidth * 0.28, 1.5))
            )
            layer.stroke(
                path,
                with: .color(color.opacity(Double(alpha) * 0.86)),
                style: laserStrokeStyle(lineWidth: max(beamWidth * 0.22, 1.5))
            )
            layer.stroke(
                path,
                with: .color(.white.opacity(Double(alpha) * 0.68)),
                style: laserStrokeStyle(lineWidth: max(beamWidth * 0.10, 1))
            )
        }
    }

    private func laserStrokeStyle(lineWidth: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
    }

    private func visibleScaledSamples(
        for stroke: CanvasLiveStroke,
        currentTime: TimeInterval
    ) -> [CanvasLiveStrokePoint] {
        let lifetime = effectiveLaserLifetime(for: stroke)
        let liveSamples = scaledSamples(for: stroke).filter { sample in
            currentTime - sample.timestamp <= lifetime
        }

        switch stroke.kind {
        case .laserDot:
            return liveSamples.last.map { [$0] } ?? []
        case .laserTrail:
            return stroke.displayDuration <= 0
                ? liveSamples.last.map { [$0] } ?? []
                : liveSamples
        case .ink:
            return []
        }
    }

    private func laserAlpha(
        for sample: CanvasLiveStrokePoint,
        in stroke: CanvasLiveStroke,
        currentTime: TimeInterval,
        maximum: CGFloat
    ) -> CGFloat {
        let lifetime = max(effectiveLaserLifetime(for: stroke), 0.001)
        let progress = min(max((currentTime - sample.timestamp) / lifetime, 0), 1)
        return maximum * CGFloat(1 - progress)
    }

    private func effectiveLaserLifetime(for stroke: CanvasLiveStroke) -> TimeInterval {
        stroke.displayDuration <= 0 ? 0.14 : stroke.displayDuration
    }

    private func scaledSamples(for stroke: CanvasLiveStroke) -> [CanvasLiveStrokePoint] {
        if let viewportSourceRect,
           viewportSourceRect.width > 0,
           viewportSourceRect.height > 0 {
            let scaleX = fittedSize.width / viewportSourceRect.width
            let scaleY = fittedSize.height / viewportSourceRect.height
            return stroke.samples.map { sample in
                CanvasLiveStrokePoint(
                    location: CGPoint(
                        x: (sample.location.x - viewportSourceRect.minX) * scaleX,
                        y: (sample.location.y - viewportSourceRect.minY) * scaleY
                    ),
                    pressure: sample.pressure,
                    timestamp: sample.timestamp
                )
            }
        }

        guard fallbackSourceSize.width > 0, fallbackSourceSize.height > 0 else { return [] }
        let scaleX = fittedSize.width / fallbackSourceSize.width
        let scaleY = fittedSize.height / fallbackSourceSize.height
        return stroke.samples.map { sample in
            CanvasLiveStrokePoint(
                location: CGPoint(
                    x: sample.location.x * scaleX,
                    y: sample.location.y * scaleY
                ),
                pressure: sample.pressure,
                timestamp: sample.timestamp
            )
        }
    }

    private func scaledPoints(for stroke: CanvasLiveStroke) -> [CGPoint] {
        scaledSamples(for: stroke).map(\.location)
    }

    private func scaledLineWidth(for stroke: CanvasLiveStroke) -> CGFloat {
        if let viewportSourceRect,
           viewportSourceRect.width > 0,
           viewportSourceRect.height > 0 {
            let scale = min(fittedSize.width / viewportSourceRect.width, fittedSize.height / viewportSourceRect.height)
            return stroke.lineWidth * scale
        }

        guard fallbackSourceSize.width > 0, fallbackSourceSize.height > 0 else { return stroke.lineWidth }
        let scale = min(fittedSize.width / fallbackSourceSize.width, fittedSize.height / fallbackSourceSize.height)
        return stroke.lineWidth * scale
    }
}

private struct ExternalDisplayPlaceholder: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 144, weight: .regular))
                .foregroundStyle(.white.opacity(0.5))
            Text("MathBoard")
                .font(.system(size: 96, weight: .semibold))
                .foregroundStyle(.white)
            Text("Open a lesson on the iPad to begin.")
                .font(.title)
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

#endif
