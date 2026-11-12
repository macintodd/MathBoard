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

// MARK: - Main overlay

public struct ShootingStarCelebrationOverlay: View {
    public let event: ClassroomCelebrationEvent

    @State private var isFlying = false
    @State private var isVisible = true
    @State private var flightProgress: CGFloat = 0
    @State private var tailIntensity: CGFloat = 0
    @State private var burstScale: CGFloat = 0.4
    @State private var burstOpacity: Double = 0
    @State private var flightPath = ShootingStarFlightPath.default
    @State private var accentColor: Color = .cyan
    @State private var kudosPhrase: String = "Well done!"

    private static let flightDuration: Double = 11.5

    public init(event: ClassroomCelebrationEvent) {
        self.event = event
    }

    public var body: some View {
        GeometryReader { proxy in
            if isVisible {
                shootingStar
                    .position(
                        x: proxy.size.width * flightPath.point(at: flightProgress).x,
                        y: topGlideY(in: proxy.size)
                    )
                    .scaleEffect(isFlying ? 1.0 : 0.82)
                    .opacity(isFlying ? 1.0 : 0)

                EdgeBurstView(seed: event.id)
                    .scaleEffect(burstScale)
                    .opacity(burstOpacity)
                    .position(x: proxy.size.width + 10, y: topGlideY(in: proxy.size))
            }
        }
        .allowsHitTesting(false)
        .task(id: event.id) {
            flightPath = .topGlide()
            accentColor = KudosAccentColor.random(seed: event.id)
            kudosPhrase = KudosPhrase.random(seed: event.id)
            isFlying = false
            flightProgress = 0
            tailIntensity = 0
            burstScale = 0.4
            burstOpacity = 0
            isVisible = true
            await Task.yield()
            withAnimation(.easeOut(duration: 0.22)) {
                isFlying = true
                tailIntensity = 1
            }
            withAnimation(.linear(duration: Self.flightDuration)) {
                flightProgress = 1
            }
            do {
                try await Task.sleep(for: .milliseconds(Int(Self.flightDuration * 1000)))
            } catch {
                isVisible = false
                return
            }
            withAnimation(.easeOut(duration: 0.18)) { tailIntensity = 0.28 }
            withAnimation(.easeOut(duration: 0.16)) { burstScale = 1; burstOpacity = 1 }
            withAnimation(.easeOut(duration: 0.22).delay(0.12)) { burstScale = 1.28; burstOpacity = 0 }
            do {
                try await Task.sleep(for: .milliseconds(420))
                isVisible = false
            } catch {
                isVisible = false
            }
        }
    }

    // MARK: Placement

    /// Pins the placard to the top edge of the 16:9 viewfinder mask so the
    /// placard body lines up with the region shown on the secondary display.
    /// The viewfinder (`ViewfinderOverlay`) is a vertically centered 16:9 rect,
    /// so its top edge sits at `(height - viewfinderHeight) / 2`. The overlay
    /// shares the same full-screen container, so we can reproduce that here and
    /// drop the placard body so its top aligns with the mask.
    private func topGlideY(in size: CGSize) -> CGFloat {
        let targetAspect: CGFloat = 16.0 / 9.0
        let viewfinderHeight = size.width / max(size.height, 1) > targetAspect
            ? size.height
            : size.width / targetAspect
        let viewfinderTop = (size.height - viewfinderHeight) / 2
        // Half of KudosPlacardView.bodyHeight (112) — the `.position` sets the
        // placard center, so shift down by the body half-height to seat its
        // top on the mask line.
        let placardBodyHalfHeight: CGFloat = 56
        return viewfinderTop + placardBodyHalfHeight
    }

    // MARK: Composition

    private var shootingStar: some View {
        HStack(spacing: -52) {
            if flightPath.movesRight {
                ribbonTrail
                kudosPlacard
            } else {
                kudosPlacard
                ribbonTrail
                    .scaleEffect(x: -1, y: 1)
            }
        }
    }

    // MARK: Placard

    private var kudosPlacard: some View {
        KudosPlacardView(name: event.studentName, phrase: kudosPhrase, accentColor: accentColor)
            .shadow(color: .black.opacity(0.42), radius: 14, x: 0, y: 7)
            .shadow(color: Color(red: 0.90, green: 0.68, blue: 0.12).opacity(0.55), radius: 22, x: 0, y: 0)
    }

    // MARK: Ribbon trail

    private var ribbonTrail: some View {
        ZStack(alignment: .trailing) {
            // Back glow — wide, warm amber haze
            RoundedRectangle(cornerRadius: 30)
                .fill(
                    LinearGradient(
                        colors: [.clear, Color(red: 1.0, green: 0.72, blue: 0.10).opacity(0.30)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(width: 470, height: 100)
                .blur(radius: 22)

            // Primary ribbon — main gold streak
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: [.clear, Color(red: 1.0, green: 0.84, blue: 0.24).opacity(0.60)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(width: 400, height: 46)
                .blur(radius: 8)

            // Bright white core
            RoundedRectangle(cornerRadius: 5)
                .fill(
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.80)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(width: 270, height: 10)
                .blur(radius: 2)

            // Upper accent ribbon — random color
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [.clear, accentColor.opacity(0.48)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(width: 310, height: 20)
                .offset(y: -32)
                .blur(radius: 6)

            // Lower accent ribbon — random color
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [.clear, accentColor.opacity(0.32)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(width: 250, height: 14)
                .offset(y: 32)
                .blur(radius: 5)

            // Fine upper highlight
            RoundedRectangle(cornerRadius: 3)
                .fill(
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.55)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(width: 210, height: 5)
                .offset(y: -20)
                .blur(radius: 1.5)

            // Fine lower highlight
            RoundedRectangle(cornerRadius: 3)
                .fill(
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.40)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(width: 170, height: 4)
                .offset(y: 22)
                .blur(radius: 1.5)

            // Particle sparkle tail
            ParticleTailView(seed: event.id, intensity: tailIntensity)
        }
        .opacity(Double(tailIntensity))
    }
}

// MARK: - Kudos Placard

private struct KudosPlacardView: View {
    let name: String
    let phrase: String
    let accentColor: Color

    private let bodyWidth: CGFloat = 504
    private let bodyHeight: CGFloat = 112
    private let cornerRadius: CGFloat = 36
    private let borderWidth: CGFloat = 5

    var body: some View {
        ZStack {
            // Subtle accent glow behind the whole badge (theme color)
            RoundedRectangle(cornerRadius: cornerRadius + 6)
                .fill(accentColor.opacity(0.18))
                .frame(width: bodyWidth + 14, height: bodyHeight + 14)
                .blur(radius: 12)

            // Gold outer border ring
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.93, blue: 0.52),
                            Color(red: 0.86, green: 0.63, blue: 0.18),
                            Color(red: 1.0, green: 0.88, blue: 0.44),
                            Color(red: 0.68, green: 0.44, blue: 0.08),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: bodyWidth, height: bodyHeight)

            // Dark navy inner body
            RoundedRectangle(cornerRadius: cornerRadius - borderWidth)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.13, green: 0.17, blue: 0.38),
                            Color(red: 0.06, green: 0.08, blue: 0.22),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottom
                    )
                )
                .frame(width: bodyWidth - borderWidth * 2, height: bodyHeight - borderWidth * 2)

            // Content row — star pinned to the leading edge while the name
            // stays centered across the full badge width.
            ZStack {
                nameTextBlock
                    .padding(.horizontal, 98)

                HStack {
                    starMedallion
                    Spacer()
                }
                .padding(.leading, 14)
            }
            .frame(width: bodyWidth - borderWidth * 2)

            // KUDOS pill — rides the top border edge
            VStack {
                kudosPill
                    .offset(y: -(bodyHeight * 0.5 - 10))
                Spacer()
            }
            .frame(height: bodyHeight)
        }
        .frame(width: bodyWidth, height: bodyHeight)
    }

    // MARK: Star medallion

    private var starMedallion: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.92, blue: 0.50),
                            Color(red: 0.72, green: 0.48, blue: 0.10),
                            Color(red: 1.0, green: 0.88, blue: 0.42),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 84, height: 84)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.15, green: 0.19, blue: 0.42),
                            Color(red: 0.06, green: 0.08, blue: 0.22),
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 52
                    )
                )
                .frame(width: 70, height: 70)

            Image(systemName: "star.fill")
                .font(.system(size: 34))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.97, blue: 0.56),
                            Color(red: 0.98, green: 0.77, blue: 0.18),
                            Color(red: 0.86, green: 0.53, blue: 0.04),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: Color.yellow.opacity(0.80), radius: 5, x: 0, y: 0)
                .shadow(color: Color.orange.opacity(0.55), radius: 10, x: 0, y: 0)
        }
    }

    // MARK: Name + phrase

    private var nameTextBlock: some View {
        VStack(alignment: .center, spacing: 2) {
            Text(name)
                .font(.system(size: 54, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.46)
                .multilineTextAlignment(.center)
                .shadow(color: .white.opacity(0.28), radius: 3)

            Text(phrase)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(Color.white.opacity(0.60))
                .lineLimit(1)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: KUDOS pill

    private var kudosPill: some View {
        Text("KUDOS")
            .font(.system(size: 10, weight: .black, design: .rounded))
            .foregroundColor(Color(red: 0.24, green: 0.14, blue: 0.02))
            .kerning(2.5)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.96, blue: 0.60),
                                Color(red: 0.94, green: 0.74, blue: 0.24),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(Capsule().stroke(Color.white.opacity(0.38), lineWidth: 0.5))
            )
            .shadow(color: .black.opacity(0.28), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Random accent colors (theme color for accent ribbons + badge glow)

private enum KudosAccentColor {
    static func random(seed: UUID) -> Color {
        let bytes = seed.uuidString.utf8.reduce(0) { $0 &+ UInt64($1) }
        var generator = SeededGenerator(seed: bytes &+ 77777)
        let palette: [Color] = [
            Color(red: 0.18, green: 0.84, blue: 1.0),   // electric cyan
            Color(red: 1.0, green: 0.20, blue: 0.72),   // hot magenta
            Color(red: 0.22, green: 1.0, blue: 0.58),   // aurora green
            Color(red: 0.74, green: 0.22, blue: 1.0),   // cosmic violet
            Color(red: 1.0, green: 0.44, blue: 0.12),   // deep orange
            Color(red: 0.40, green: 0.80, blue: 1.0),   // sky blue
        ]
        return palette.randomElement(using: &generator) ?? .cyan
    }
}

// MARK: - Random kudos phrases

private enum KudosPhrase {
    static func random(seed: UUID) -> String {
        let bytes = seed.uuidString.utf8.reduce(0) { $0 &+ UInt64($1) }
        var generator = SeededGenerator(seed: bytes &+ 55555)
        let phrases = [
            "Well done!",
            "Excellent work!",
            "Brilliant!",
            "Keep it up!",
            "Amazing!",
            "Superstar!",
            "Way to go!",
            "Fantastic!",
            "Outstanding!",
            "You rock!",
        ]
        return phrases.randomElement(using: &generator) ?? "Well done!"
    }
}

// MARK: - Particle tail

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

// MARK: - Edge burst

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

// MARK: - Particles

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
                Color(red: 1.0, green: 0.80, blue: 0.58),
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

    enum ShapeKind { case star, square, diamond, circle, triangle }
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

// MARK: - Particle shapes

private struct StarParticleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * 0.42
        var path = Path()
        for i in 0..<10 {
            let radius = i.isMultiple(of: 2) ? outerRadius : innerRadius
            let angle = -Double.pi / 2 + Double(i) * Double.pi / 5
            let point = CGPoint(x: center.x + CGFloat(cos(angle)) * radius,
                                y: center.y + CGFloat(sin(angle)) * radius)
            i == 0 ? path.move(to: point) : path.addLine(to: point)
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

// MARK: - Seeded RNG

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

// MARK: - Flight path

private struct ShootingStarFlightPath {
    let start: CGPoint
    let end: CGPoint
    let rotationDegrees: Double
    let movesRight: Bool

    static let `default` = ShootingStarFlightPath(
        start: CGPoint(x: -0.22, y: 0),
        end: CGPoint(x: 1.22, y: 0),
        rotationDegrees: 0,
        movesRight: true
    )

    /// A level left-to-right glide that enters from the side and slides
    /// straight across. The vertical position is fixed by `topGlideY`, so the
    /// path only carries horizontal travel and never tilts.
    static func topGlide() -> ShootingStarFlightPath {
        ShootingStarFlightPath(
            start: CGPoint(x: -0.22, y: 0),
            end: CGPoint(x: 1.22, y: 0)
        )
    }

    func point(at progress: CGFloat) -> CGPoint {
        let t = min(1, max(0, progress))
        return CGPoint(
            x: start.x + (end.x - start.x) * t,
            y: start.y + (end.y - start.y) * t
        )
    }

    private init(start: CGPoint, end: CGPoint) {
        self.start = start
        self.end = end
        let dx = end.x - start.x
        let dy = end.y - start.y
        movesRight = dx >= 0
        rotationDegrees = Double(atan2(dy, abs(dx)) * 180 / .pi)
    }

    private init(start: CGPoint, end: CGPoint, rotationDegrees: Double, movesRight: Bool) {
        self.start = start
        self.end = end
        self.rotationDegrees = rotationDegrees
        self.movesRight = movesRight
    }
}
