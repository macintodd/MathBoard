//
//  LiveTeacherInkOverlay.swift
//  MathBoardCore - LiveClassroom module
//

import Canvas
import SwiftUI

public struct LiveTeacherInkOverlay: View {
    private let strokes: [CanvasLiveStroke]
    private let viewportSourceRect: CGRect?
    private let fallbackSourceSize: CGSize
    private let fittedSize: CGSize

    public init(
        strokes: [CanvasLiveStroke],
        viewportSourceRect: CGRect?,
        fallbackSourceSize: CGSize,
        fittedSize: CGSize
    ) {
        self.strokes = strokes
        self.viewportSourceRect = viewportSourceRect
        self.fallbackSourceSize = fallbackSourceSize
        self.fittedSize = fittedSize
    }

    public var body: some View {
        SwiftUI.Canvas { context, _ in
            for stroke in strokes where stroke.kind == .ink {
                let color = Color(
                    red: Double(stroke.color.red),
                    green: Double(stroke.color.green),
                    blue: Double(stroke.color.blue),
                    opacity: Double(stroke.color.alpha)
                )
                let path = CanvasVectorInk.smoothedPath(points: scaledPoints(for: stroke))
                let width = max(scaledLineWidth(for: stroke), 1)

                if stroke.color.alpha >= 0.95 {
                    context.stroke(
                        path,
                        with: .color(color),
                        style: StrokeStyle(
                            lineWidth: CanvasVectorInk.crispLineWidth(baseLineWidth: width),
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                } else {
                    context.stroke(
                        path,
                        with: .color(color.opacity(0.48)),
                        style: StrokeStyle(
                            lineWidth: width * 2.35,
                            lineCap: .butt,
                            lineJoin: .round
                        )
                    )
                }
            }
        }
        .frame(width: fittedSize.width, height: fittedSize.height)
        .allowsHitTesting(false)
    }

    private func scaledPoints(for stroke: CanvasLiveStroke) -> [CGPoint] {
        scaledSamples(for: stroke).map(\.location)
    }

    private func scaledLineWidth(for stroke: CanvasLiveStroke) -> CGFloat {
        if let viewportSourceRect,
           viewportSourceRect.width > 0,
           viewportSourceRect.height > 0 {
            return stroke.lineWidth * min(
                fittedSize.width / viewportSourceRect.width,
                fittedSize.height / viewportSourceRect.height
            )
        }

        guard fallbackSourceSize.width > 0, fallbackSourceSize.height > 0 else {
            return stroke.lineWidth
        }
        return stroke.lineWidth * min(
            fittedSize.width / fallbackSourceSize.width,
            fittedSize.height / fallbackSourceSize.height
        )
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
}
