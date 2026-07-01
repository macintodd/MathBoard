//
//  CanvasLiveStroke.swift
//  MathBoardCore - Canvas module
//
//  Lightweight vector representation for the active Apple Pencil stroke.
//  This is separate from PencilKit's committed PKDrawing model so external
//  displays can show live ink without snapshotting PKCanvasView.
//

import CoreGraphics
import Foundation

public struct CanvasLiveStrokePoint: Sendable, Equatable {
    public let location: CGPoint
    public let pressure: CGFloat
    public let timestamp: TimeInterval

    public init(location: CGPoint, pressure: CGFloat = 0.5, timestamp: TimeInterval = 0) {
        self.location = location
        self.pressure = min(max(pressure, 0), 1)
        self.timestamp = timestamp
    }
}

public struct CanvasStrokeColor: Sendable, Equatable {
    public let red: CGFloat
    public let green: CGFloat
    public let blue: CGFloat
    public let alpha: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

public struct CanvasLiveStroke: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case ink
        case laserDot
        case laserTrail
    }

    public let samples: [CanvasLiveStrokePoint]
    public let lineWidth: CGFloat
    public let color: CanvasStrokeColor
    public let kind: Kind
    public let displayDuration: TimeInterval

    public var isTransient: Bool {
        kind != .ink
    }

    public var points: [CGPoint] {
        samples.map(\.location)
    }

    public init(
        samples: [CanvasLiveStrokePoint],
        lineWidth: CGFloat,
        color: CanvasStrokeColor,
        kind: Kind = .ink,
        displayDuration: TimeInterval = 0
    ) {
        self.samples = samples
        self.lineWidth = lineWidth
        self.color = color
        self.kind = kind
        self.displayDuration = displayDuration
    }

    public init(
        points: [CGPoint],
        lineWidth: CGFloat,
        color: CanvasStrokeColor,
        kind: Kind = .ink,
        displayDuration: TimeInterval = 0
    ) {
        self.samples = points.map { CanvasLiveStrokePoint(location: $0) }
        self.lineWidth = lineWidth
        self.color = color
        self.kind = kind
        self.displayDuration = displayDuration
    }
}
