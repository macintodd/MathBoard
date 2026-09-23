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
    @State private var flightProgress: CGFloat = 0
    @State private var tailIntensity: CGFloat = 0
    @State private var burstScale: CGFloat = 0.4
    @State private var burstOpacity: Double = 0
    @State private var flightPath = ShootingStarFlightPath.default

    public init(event: ClassroomCelebrationEvent) {
        self.event = event
    }

    public var body: some View {
        GeometryReader { proxy in
            if isVisible {
                shootingStar
                    .position(
                        x: proxy.size.width * flightPath.point(at: flightProgress).x,
                        y: proxy.size.height * flightPath.point(at: flightProgress).y
                    )
                    .rotationEffect(.degrees(flightPath.rotationDegrees))
                    .scaleEffect(isFlying ? 1.02 : 0.84)
                    .opacity(isFlying ? 0.98 : 0)
                    .shadow(color: Color.yellow.opacity(0.48), radius: 20, x: 0, y: 0)

                EdgeBurstView(seed: event.id)
                    .scaleEffect(burstScale)
                    .opacity(burstOpacity)
                    .position(x: proxy.size.width + 10, y: proxy.size.height * flightPath.end.y)
            }
        }
        .allowsHitTesting(false)
        .task(id: event.id) {
            flightPath = .random()
            isFlying = false
            flightProgress = 0
            tailIntensity = 0
            burstScale = 0.4
            burstOpacity = 0
            isVisible = true
            await Task.yield()
            withAnimation(.easeOut(duration: 0.08)) {
                isFlying = true
                tailIntensity = 1
            }
            withAnimation(.linear(duration: 8.5)) {
                flightProgress = 1
            }
            do {
                try await Task.sleep(for: .milliseconds(8_500))
            } catch {
                isVisible = false
                return
            }
            withAnimation(.easeOut(duration: 0.18)) {
                tailIntensity = 0.28
            }
            withAnimation(.easeOut(duration: 0.16)) {
                burstScale = 1
                burstOpacity = 1
            }
            withAnimation(.easeOut(duration: 0.22).delay(0.12)) {
                burstScale = 1.28
                burstOpacity = 0
            }
            do {
                try await Task.sleep(for: .milliseconds(420))
                isVisible = false
            } catch {
                isVisible = false
            }
        }
    }

    private var shootingStar: some View {
        HStack(spacing: -58) {
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
        Text(event.studentName)
            .font(.system(size: 66, weight: .heavy, design: .rounded))
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.98, blue: 0.34),
                        Color(red: 1.0, green: 0.78, blue: 0.08),
                        Color(red: 1.0, green: 0.44, blue: 0.02)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .lineLimit(1)
            .minimumScaleFactor(0.58)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(minWidth: 320, maxWidth: 680, minHeight: 104, alignment: .leading)
            .background {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.96, blue: 0.34).opacity(0.18),
                                Color(red: 1.0, green: 0.67, blue: 0.05).opacity(0.08),
                                Color.orange.opacity(0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .blur(radius: 14)
                    .scaleEffect(x: 1.04, y: 0.78)
            }
            .shadow(color: Color(red: 1.0, green: 0.95, blue: 0.20).opacity(0.95), radius: 5, x: 0, y: 0)
            .shadow(color: Color(red: 1.0, green: 0.53, blue: 0.02).opacity(0.82), radius: 9, x: 0, y: 0)
            .shadow(color: Color(red: 0.42, green: 0.12, blue: 0.0).opacity(0.58), radius: 2, x: 0, y: 3)
    }

    private var starTrail: some View {
        ZStack(alignment: .trailing) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.orange.opacity(0),
                            Color(red: 1.0, green: 0.75, blue: 0.08).opacity(0.34),
                            Color(red: 1.0, green: 0.92, blue: 0.20).opacity(0.58)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 430, height: 96)
                .blur(radius: 14)

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.78, blue: 0.08).opacity(0),
                            Color(red: 1.0, green: 0.72, blue: 0.04).opacity(0.26),
                            Color(red: 1.0, green: 0.86, blue: 0.12).opacity(0.66)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 360, height: 54)
                .blur(radius: 6)

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
                .frame(width: 240, height: 8)
                .offset(y: -22)

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
                .frame(width: 190, height: 6)
                .offset(y: 24)

            ParticleTailView(seed: event.id, intensity: tailIntensity)
        }
    }
}

private struct ParticleTailView: View {
    let seed: UUID
    let intensity: CGFloat

    private var particles: [ShootingStarParticle] {
        ShootingStarParticle.makeParticles(seed: seed, count: 44)
    }

    var body: some View {
        ZStack {
            ForEach(particles) { particle in
                ParticleShapeView(particle: particle, opacityMultiplier: Double(intensity))
                    .frame(width: particle.size, height: particle.size)
                    .rotationEffect(.degrees(particle.rotation + Double(intensity) * 210))
                    .offset(
                        x: particle.offset.width - (1 - intensity) * 44,
                        y: particle.offset.height + intensity * particle.gravity
                    )
                    .scaleEffect(0.55 + intensity * particle.scale)
                    .animation(.easeOut(duration: 0.24), value: intensity)
            }
        }
    }
}

private struct EdgeBurstView: View {
    let seed: UUID

    private var particles: [ShootingStarParticle] {
        ShootingStarParticle.makeParticles(seed: seed, count: 16)
    }

    var body: some View {
        ZStack {
            ForEach(Array(particles.enumerated()), id: \.element.id) { index, particle in
                let angle = Double(index) / Double(max(1, particles.count)) * .pi * 2
                ParticleShapeView(particle: particle, opacityMultiplier: 0.88 / max(0.01, particle.opacity))
                    .frame(width: particle.size + 2, height: particle.size + 2)
                    .rotationEffect(.degrees(particle.rotation))
                    .offset(x: cos(angle) * 44, y: sin(angle) * 44)
            }
        }
    }
}

private struct ShootingStarParticle: Identifiable {
    let id: Int
    let size: CGFloat
    let offset: CGSize
    let gravity: CGFloat
    let rotation: Double
    let opacity: Double
    let scale: CGFloat
    let color: Color
    let shapeKind: ShapeKind

    static func makeParticles(seed: UUID, count: Int) -> [ShootingStarParticle] {
        let bytes = seed.uuidString.utf8.reduce(0) { $0 &+ UInt64($1) }
        return (0..<count).map { index in
            var generator = SeededGenerator(seed: bytes &+ UInt64(index * 7919))
            let shapeKinds: [ShapeKind] = [.star, .square, .diamond, .circle, .triangle]
            let colors = [
                Color.white,
                Color(red: 1.0, green: 0.93, blue: 0.22),
                Color(red: 1.0, green: 0.62, blue: 0.08),
                Color(red: 0.46, green: 0.98, blue: 1.0),
                Color(red: 1.0, green: 0.80, blue: 0.58)
            ]
            return ShootingStarParticle(
                id: index,
                size: CGFloat.random(in: 4...13, using: &generator),
                offset: CGSize(
                    width: CGFloat.random(in: -360...36, using: &generator),
                    height: CGFloat.random(in: -48...48, using: &generator)
                ),
                gravity: CGFloat.random(in: 10...44, using: &generator),
                rotation: Double.random(in: 0...360, using: &generator),
                opacity: Double.random(in: 0.30...0.88, using: &generator),
                scale: CGFloat.random(in: 0.32...1.10, using: &generator),
                color: colors.randomElement(using: &generator) ?? .yellow,
                shapeKind: shapeKinds.randomElement(using: &generator) ?? .star
            )
        }
    }

    enum ShapeKind {
        case star
        case square
        case diamond
        case circle
        case triangle
    }
}

private struct ParticleShapeView: View {
    let particle: ShootingStarParticle
    let opacityMultiplier: Double

    var body: some View {
        switch particle.shapeKind {
        case .star:
            StarParticleShape()
                .fill(particle.color.opacity(opacityMultiplier * particle.opacity))
        case .square:
            RoundedRectangle(cornerRadius: 1.2)
                .fill(particle.color.opacity(opacityMultiplier * particle.opacity))
        case .diamond:
            DiamondParticleShape()
                .fill(particle.color.opacity(opacityMultiplier * particle.opacity))
        case .circle:
            Circle()
                .stroke(particle.color.opacity(opacityMultiplier * particle.opacity), lineWidth: 1.6)
        case .triangle:
            TriangleParticleShape()
                .stroke(particle.color.opacity(opacityMultiplier * particle.opacity), lineWidth: 1.5)
        }
    }
}

private struct StarParticleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * 0.42
        var path = Path()

        for pointIndex in 0..<10 {
            let radius = pointIndex.isMultiple(of: 2) ? outerRadius : innerRadius
            let angle = -Double.pi / 2 + Double(pointIndex) * Double.pi / 5
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
            pointIndex == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

private struct DiamondParticleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

private struct TriangleParticleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x1234ABCD : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}

private struct ShootingStarFlightPath {
    let start: CGPoint
    let end: CGPoint
    let rotationDegrees: Double
    let movesRight: Bool

    static let `default` = ShootingStarFlightPath(
        start: CGPoint(x: -0.14, y: 0.54),
        end: CGPoint(x: 1.14, y: 0.42),
        rotationDegrees: -5,
        movesRight: true
    )

    static func random() -> ShootingStarFlightPath {
        let startY = CGFloat.random(in: 0.26...0.72)
        let endY = min(0.78, max(0.20, startY + CGFloat.random(in: -0.15...0.10)))
        let start = CGPoint(x: -0.14, y: startY)
        let end = CGPoint(x: 1.14, y: endY)
        return ShootingStarFlightPath(start: start, end: end)
    }

    func point(at progress: CGFloat) -> CGPoint {
        let clampedProgress = min(1, max(0, progress))
        return CGPoint(
            x: start.x + (end.x - start.x) * clampedProgress,
            y: start.y + (end.y - start.y) * clampedProgress
        )
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
