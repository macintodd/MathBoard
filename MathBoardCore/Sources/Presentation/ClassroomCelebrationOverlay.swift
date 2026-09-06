//
//  ClassroomCelebrationOverlay.swift
//  MathBoardCore - Presentation module
//

import SwiftUI

public struct ClassroomCelebrationEvent: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let studentName: String

    public init(id: UUID = UUID(), studentName: String) {
        self.id = id
        let trimmedName = studentName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.studentName = trimmedName.isEmpty ? "Student" : trimmedName
    }
}

public struct ShootingStarCelebrationOverlay: View {
    public let event: ClassroomCelebrationEvent

    @State private var isFlying = false
    @State private var isVisible = true
    @State private var flightPath = ShootingStarFlightPath.default

    public init(event: ClassroomCelebrationEvent) {
        self.event = event
    }

    public var body: some View {
        GeometryReader { proxy in
            if isVisible {
                shootingStar
                    .position(
                        x: proxy.size.width * (isFlying ? flightPath.end.x : flightPath.start.x),
                        y: proxy.size.height * (isFlying ? flightPath.end.y : flightPath.start.y)
                    )
                    .rotationEffect(.degrees(flightPath.rotationDegrees))
                    .scaleEffect(isFlying ? 1.02 : 0.98)
                    .opacity(isFlying ? 0.98 : 0.94)
                    .shadow(color: Color.yellow.opacity(0.48), radius: 20, x: 0, y: 0)
            }
        }
        .allowsHitTesting(false)
        .task(id: event.id) {
            flightPath = .random()
            isFlying = false
            isVisible = true
            await Task.yield()
            withAnimation(.timingCurve(0.42, 0.0, 0.88, 0.98, duration: 10.0)) {
                isFlying = true
            }
            do {
                try await Task.sleep(for: .seconds(10.3))
                isVisible = false
            } catch {
                isVisible = false
            }
        }
    }

    private var shootingStar: some View {
        HStack(spacing: 0) {
            if flightPath.movesRight {
                starTrail
                nameBadge
            } else {
                nameBadge
                starTrail
            }
        }
    }

    private var nameBadge: some View {
        HStack(spacing: 12) {
            Image(systemName: "star.fill")
                .font(.system(size: 42, weight: .heavy))
                .foregroundStyle(.white)
                .shadow(color: Color.orange.opacity(0.65), radius: 4, x: 0, y: 2)

            Text(event.studentName)
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.22, green: 0.12, blue: 0.02))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .padding(.leading, 18)
        .padding(.trailing, 26)
        .frame(minWidth: 240, maxWidth: 420, minHeight: 84)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.88, blue: 0.20),
                            Color(red: 1.0, green: 0.62, blue: 0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.72), lineWidth: 2)
        }
    }

    private var starTrail: some View {
        ZStack(alignment: .trailing) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.yellow.opacity(0),
                            Color.yellow.opacity(0.18),
                            Color.orange.opacity(0.72)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 250, height: 24)

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0),
                            Color.white.opacity(0.82)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 172, height: 7)
                .offset(y: -18)

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0),
                            Color.white.opacity(0.62)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 148, height: 6)
                .offset(y: 19)
        }
    }
}

private struct ShootingStarFlightPath {
    let start: CGPoint
    let end: CGPoint
    let rotationDegrees: Double
    let movesRight: Bool

    static let `default` = ShootingStarFlightPath(
        start: CGPoint(x: -0.22, y: 0.58),
        end: CGPoint(x: 1.22, y: 0.30),
        rotationDegrees: -10,
        movesRight: true
    )

    static func random() -> ShootingStarFlightPath {
        let start: CGPoint
        let end: CGPoint

        switch Int.random(in: 0..<4) {
        case 0:
            start = CGPoint(x: -0.22, y: CGFloat.random(in: 0.24...0.76))
            end = CGPoint(x: 1.22, y: CGFloat.random(in: 0.18...0.68))
        case 1:
            start = CGPoint(x: 1.22, y: CGFloat.random(in: 0.24...0.76))
            end = CGPoint(x: -0.22, y: CGFloat.random(in: 0.18...0.68))
        case 2:
            let entersFromLeftHalf = Bool.random()
            start = CGPoint(
                x: entersFromLeftHalf ? CGFloat.random(in: -0.24...0.08) : CGFloat.random(in: 0.92...1.24),
                y: -0.18
            )
            end = CGPoint(
                x: entersFromLeftHalf ? CGFloat.random(in: 0.90...1.24) : CGFloat.random(in: -0.24...0.10),
                y: CGFloat.random(in: 0.88...1.18)
            )
        default:
            let entersFromLeftHalf = Bool.random()
            start = CGPoint(
                x: entersFromLeftHalf ? CGFloat.random(in: -0.24...0.08) : CGFloat.random(in: 0.92...1.24),
                y: 1.18
            )
            end = CGPoint(
                x: entersFromLeftHalf ? CGFloat.random(in: 0.90...1.24) : CGFloat.random(in: -0.24...0.10),
                y: CGFloat.random(in: -0.18...0.12)
            )
        }

        return ShootingStarFlightPath(start: start, end: end)
    }

    private init(start: CGPoint, end: CGPoint) {
        self.start = start
        self.end = end
        let horizontalDistance = end.x - start.x
        let verticalDistance = end.y - start.y
        movesRight = horizontalDistance >= 0
        rotationDegrees = Double(atan2(verticalDistance, abs(horizontalDistance)) * 180 / .pi)
    }

    private init(start: CGPoint, end: CGPoint, rotationDegrees: Double, movesRight: Bool) {
        self.start = start
        self.end = end
        self.rotationDegrees = rotationDegrees
        self.movesRight = movesRight
    }
}
