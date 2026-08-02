//
//  LiveClassroomModels.swift
//  MathBoardCore - LiveClassroom module
//
//  Lightweight realtime transport models for classroom-live events. Firebase
//  remains the durable source of truth; this module handles temporary live ink.
//

import Canvas
import CoreGraphics
import Foundation
import Observation
import SwiftUI

public enum LiveClassroomRole: String, Sendable, Codable, Equatable {
    case teacher
    case student
}

public struct LiveClassroomSessionConfiguration: Sendable, Equatable {
    public var lessonCode: String
    public var role: LiveClassroomRole
    public var clientID: String
    public var apiKey: String

    public init(
        lessonCode: String,
        role: LiveClassroomRole,
        clientID: String,
        apiKey: String
    ) {
        self.lessonCode = Self.normalizedLessonCode(lessonCode)
        self.role = role
        self.clientID = clientID
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var inkChannelName: String {
        "classroom:\(lessonCode):ink"
    }

    public var isUsable: Bool {
        !lessonCode.isEmpty && !apiKey.isEmpty && !clientID.isEmpty
    }

    public static func normalizedLessonCode(_ code: String) -> String {
        code
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}

@MainActor
@Observable
public final class LiveClassroomSettings {
    public static let shared = LiveClassroomSettings()

    public static let enabledKey = "MathBoardLiveTeacherInkEnabled"
    public static let ablyAPIKeyKey = "MathBoardLiveClassroomAblyAPIKey"

    public var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    public var ablyAPIKey: String {
        get { UserDefaults.standard.string(forKey: Self.ablyAPIKeyKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.ablyAPIKeyKey) }
    }

    private init() {}

    public func configuration(
        lessonCode: String?,
        role: LiveClassroomRole,
        clientID: String
    ) -> LiveClassroomSessionConfiguration? {
        guard isEnabled,
              let lessonCode,
              !lessonCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let configuration = LiveClassroomSessionConfiguration(
            lessonCode: lessonCode,
            role: role,
            clientID: clientID,
            apiKey: ablyAPIKey
        )
        return configuration.isUsable ? configuration : nil
    }
}

public struct TeacherInkPoint: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var force: Double?
    public var timestampOffset: Double

    public init(x: Double, y: Double, force: Double? = nil, timestampOffset: Double) {
        self.x = x
        self.y = y
        self.force = force
        self.timestampOffset = timestampOffset
    }
}

public struct TeacherInkStrokeChunk: Codable, Sendable, Identifiable, Equatable {
    public static let maximumPointCount = 260

    public var id: UUID
    public var lessonCode: String
    public var slideID: UUID
    public var strokeID: UUID
    public var sequence: Int
    public var isFinalChunk: Bool
    public var colorHex: String
    public var alpha: Double
    public var width: Double
    public var points: [TeacherInkPoint]
    public var sentAt: Date

    public init(
        id: UUID = UUID(),
        lessonCode: String,
        slideID: UUID,
        strokeID: UUID,
        sequence: Int,
        isFinalChunk: Bool,
        colorHex: String,
        alpha: Double,
        width: Double,
        points: [TeacherInkPoint],
        sentAt: Date = Date()
    ) {
        self.id = id
        self.lessonCode = LiveClassroomSessionConfiguration.normalizedLessonCode(lessonCode)
        self.slideID = slideID
        self.strokeID = strokeID
        self.sequence = sequence
        self.isFinalChunk = isFinalChunk
        self.colorHex = colorHex
        self.alpha = alpha
        self.width = width
        self.points = points
        self.sentAt = sentAt
    }
}

public extension TeacherInkStrokeChunk {
    init?(
        stroke: CanvasLiveStroke,
        lessonCode: String,
        slideID: UUID,
        strokeID: UUID,
        sequence: Int,
        isFinalChunk: Bool
    ) {
        guard stroke.kind == .ink, !stroke.samples.isEmpty else { return nil }
        let samples = Self.transportSamples(from: stroke.samples)
        let firstTimestamp = samples.first?.timestamp ?? 0
        self.init(
            lessonCode: lessonCode,
            slideID: slideID,
            strokeID: strokeID,
            sequence: sequence,
            isFinalChunk: isFinalChunk,
            colorHex: stroke.color.hexRGBString,
            alpha: Double(stroke.color.alpha),
            width: Double(stroke.lineWidth),
            points: samples.map { sample in
                TeacherInkPoint(
                    x: Double(sample.location.x),
                    y: Double(sample.location.y),
                    force: Double(sample.pressure),
                    timestampOffset: sample.timestamp - firstTimestamp
                )
            }
        )
    }

    static func transportSamples(from samples: [CanvasLiveStrokePoint]) -> [CanvasLiveStrokePoint] {
        guard samples.count > maximumPointCount else { return samples }

        let stride = Double(samples.count - 1) / Double(maximumPointCount - 1)
        var reduced: [CanvasLiveStrokePoint] = []
        reduced.reserveCapacity(maximumPointCount)

        for index in 0..<maximumPointCount {
            let sourceIndex = Int((Double(index) * stride).rounded())
            reduced.append(samples[min(sourceIndex, samples.count - 1)])
        }

        return reduced
    }

    var canvasLiveStroke: CanvasLiveStroke {
        CanvasLiveStroke(
            samples: points.map { point in
                CanvasLiveStrokePoint(
                    location: CGPoint(x: point.x, y: point.y),
                    pressure: CGFloat(point.force ?? 0.5),
                    timestamp: sentAt.timeIntervalSinceReferenceDate + point.timestampOffset
                )
            },
            lineWidth: CGFloat(width),
            color: CanvasStrokeColor(hexRGBString: colorHex, alpha: CGFloat(alpha)),
            kind: .ink
        )
    }
}

public extension CanvasStrokeColor {
    var hexRGBString: String {
        let r = Int((red * 255).rounded()).clamped(to: 0...255)
        let g = Int((green * 255).rounded()).clamped(to: 0...255)
        let b = Int((blue * 255).rounded()).clamped(to: 0...255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    init(hexRGBString: String, alpha: CGFloat) {
        let trimmed = hexRGBString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = Int(trimmed, radix: 16) ?? 0
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha
        )
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
