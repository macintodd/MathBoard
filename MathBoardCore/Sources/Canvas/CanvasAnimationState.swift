//
//  CanvasAnimationState.swift
//  MathBoardCore - Canvas module
//

import CoreGraphics
import Foundation

public enum CanvasAnimatedObjectKind: String, Codable, Hashable, Sendable, CaseIterable {
    case text
    case image
    case geometry
    case widget
}

public struct CanvasAnimatedObjectRef: Codable, Hashable, Sendable {
    public var kind: CanvasAnimatedObjectKind
    public var id: UUID

    public init(kind: CanvasAnimatedObjectKind, id: UUID) {
        self.kind = kind
        self.id = id
    }
}

public enum CanvasAnimationPreset: String, Codable, Hashable, Sendable, CaseIterable {
    case appear
    case fade
    case slide
    case scale
    case typewriter
    case scrolling
    case popIn
    case glowPulse
    case highlightSweep
    case fancyTitle

    public var displayName: String {
        switch self {
        case .appear: return "Appear"
        case .fade: return "Fade"
        case .slide: return "Slide"
        case .scale: return "Scale"
        case .typewriter: return "Typewriter"
        case .scrolling: return "Scrolling"
        case .popIn: return "Pop In"
        case .glowPulse: return "Glow Pulse"
        case .highlightSweep: return "Highlight Sweep"
        case .fancyTitle: return "Fancy Title"
        }
    }

    public static let textEffectPresets: [CanvasAnimationPreset] = [
        .typewriter,
        .scrolling,
        .glowPulse,
        .highlightSweep
    ]
}

public enum CanvasAnimationTrigger: String, Codable, Hashable, Sendable, CaseIterable {
    case onSlideOpen
    case onNext
    case withPrevious
    case afterPrevious

    public var displayName: String {
        switch self {
        case .onSlideOpen: return "On Slide Open"
        case .onNext: return "On Next"
        case .withPrevious: return "With Previous"
        case .afterPrevious: return "After Previous"
        }
    }
}

public enum CanvasAnimationRepeatMode: String, Codable, Hashable, Sendable, CaseIterable {
    case once
    case twice
    case loop

    public var displayName: String {
        switch self {
        case .once: return "1x"
        case .twice: return "2x"
        case .loop: return "Loop"
        }
    }

    public var playCount: Int? {
        switch self {
        case .once: return 1
        case .twice: return 2
        case .loop: return nil
        }
    }
}

public struct CanvasObjectAnimation: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var target: CanvasAnimatedObjectRef
    public var preset: CanvasAnimationPreset
    public var trigger: CanvasAnimationTrigger
    public var order: Int
    public var duration: TimeInterval
    public var delay: TimeInterval
    public var isHidden: Bool
    public var repeatMode: CanvasAnimationRepeatMode
    public var isPaused: Bool
    public var manualStartedAt: Date?
    public var pausedElapsed: TimeInterval

    public init(
        id: UUID = UUID(),
        target: CanvasAnimatedObjectRef,
        preset: CanvasAnimationPreset,
        trigger: CanvasAnimationTrigger = .onNext,
        order: Int,
        duration: TimeInterval = 0.45,
        delay: TimeInterval = 0,
        isHidden: Bool = false,
        repeatMode: CanvasAnimationRepeatMode = .once,
        isPaused: Bool = false,
        manualStartedAt: Date? = nil,
        pausedElapsed: TimeInterval = 0
    ) {
        self.id = id
        self.target = target
        self.preset = preset
        self.trigger = trigger
        self.order = max(0, order)
        self.duration = max(0.01, duration)
        self.delay = max(0, delay)
        self.isHidden = isHidden
        self.repeatMode = repeatMode
        self.isPaused = isPaused
        self.manualStartedAt = manualStartedAt
        self.pausedElapsed = max(0, pausedElapsed)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case target
        case preset
        case trigger
        case order
        case duration
        case delay
        case isHidden
        case repeatMode
        case isPaused
        case manualStartedAt
        case pausedElapsed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        target = try container.decode(CanvasAnimatedObjectRef.self, forKey: .target)
        preset = try container.decode(CanvasAnimationPreset.self, forKey: .preset)
        trigger = try container.decodeIfPresent(CanvasAnimationTrigger.self, forKey: .trigger) ?? .onNext
        order = max(0, try container.decodeIfPresent(Int.self, forKey: .order) ?? 0)
        duration = max(0.01, try container.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0.45)
        delay = max(0, try container.decodeIfPresent(TimeInterval.self, forKey: .delay) ?? 0)
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        repeatMode = try container.decodeIfPresent(CanvasAnimationRepeatMode.self, forKey: .repeatMode) ?? .once
        isPaused = try container.decodeIfPresent(Bool.self, forKey: .isPaused) ?? false
        manualStartedAt = try container.decodeIfPresent(Date.self, forKey: .manualStartedAt)
        pausedElapsed = max(0, try container.decodeIfPresent(TimeInterval.self, forKey: .pausedElapsed) ?? 0)
    }
}

public struct CanvasAnimationPlaybackState: Codable, Hashable, Sendable {
    public var currentStep: Int
    public var isPresenting: Bool
    public var stepStartedAt: Date

    public init(
        currentStep: Int = 0,
        isPresenting: Bool = false,
        stepStartedAt: Date = Date()
    ) {
        self.currentStep = max(0, currentStep)
        self.isPresenting = isPresenting
        self.stepStartedAt = stepStartedAt
    }

    public func advancing() -> CanvasAnimationPlaybackState {
        CanvasAnimationPlaybackState(
            currentStep: currentStep + 1,
            isPresenting: true,
            stepStartedAt: Date()
        )
    }

    public func reset() -> CanvasAnimationPlaybackState {
        CanvasAnimationPlaybackState(currentStep: 0, isPresenting: false)
    }
}

public struct CanvasAnimationRenderEffect: Equatable, Sendable {
    public var isVisible: Bool
    public var opacity: CGFloat
    public var scale: CGFloat
    public var translation: CGSize
    public var visibleCharacterCount: Int?
    public var textRevealFraction: CGFloat?
    public var clipFraction: CGFloat?
    public var highlightProgress: CGFloat?
    public var glowAlpha: CGFloat
    public var titleShadowAlpha: CGFloat

    public init(
        isVisible: Bool = true,
        opacity: CGFloat = 1,
        scale: CGFloat = 1,
        translation: CGSize = .zero,
        visibleCharacterCount: Int? = nil,
        textRevealFraction: CGFloat? = nil,
        clipFraction: CGFloat? = nil,
        highlightProgress: CGFloat? = nil,
        glowAlpha: CGFloat = 0,
        titleShadowAlpha: CGFloat = 0
    ) {
        self.isVisible = isVisible
        self.opacity = opacity
        self.scale = scale
        self.translation = translation
        self.visibleCharacterCount = visibleCharacterCount
        self.textRevealFraction = textRevealFraction.map { min(max($0, 0), 1) }
        self.clipFraction = clipFraction.map { min(max($0, 0), 1) }
        self.highlightProgress = highlightProgress.map { min(max($0, 0), 1) }
        self.glowAlpha = min(max(glowAlpha, 0), 1)
        self.titleShadowAlpha = min(max(titleShadowAlpha, 0), 1)
    }

    public static let visible = CanvasAnimationRenderEffect()
    public static let hidden = CanvasAnimationRenderEffect(isVisible: false, opacity: 0)
}

public struct CanvasAnimationState: Codable, Equatable, Sendable {
    public var animations: [CanvasObjectAnimation]

    public init(animations: [CanvasObjectAnimation] = []) {
        self.animations = animations.sortedForPresentation()
    }

    public static func sidecarURL(forDrawingURL drawingURL: URL) -> URL {
        drawingURL
            .deletingPathExtension()
            .appendingPathExtension("animations.json")
    }

    public static func load(from url: URL) -> CanvasAnimationState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(CanvasAnimationState.self, from: data) else {
            return CanvasAnimationState()
        }
        return CanvasAnimationState(animations: state.animations)
    }

    public static func save(_ state: CanvasAnimationState, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(CanvasAnimationState(animations: state.animations))
        try data.write(to: url, options: .atomic)
    }

    public func animation(for target: CanvasAnimatedObjectRef) -> CanvasObjectAnimation? {
        animations.first { $0.target == target }
    }

    public mutating func setPreset(_ preset: CanvasAnimationPreset, for target: CanvasAnimatedObjectRef) {
        if let index = animations.firstIndex(where: { $0.target == target }) {
            animations[index].preset = preset
            animations[index].duration = defaultDuration(for: preset)
            animations[index].manualStartedAt = nil
            animations[index].pausedElapsed = 0
            animations[index].isPaused = false
        } else {
            animations.append(CanvasObjectAnimation(
                target: target,
                preset: preset,
                order: nextOrder(),
                duration: defaultDuration(for: preset)
            ))
        }
        animations = animations.sortedForPresentation()
    }

    public mutating func setTextEffect(_ preset: CanvasAnimationPreset, forTextObjectID id: UUID) {
        setPreset(preset, for: CanvasAnimatedObjectRef(kind: .text, id: id))
    }

    public mutating func toggleHidden(for target: CanvasAnimatedObjectRef) {
        guard let index = animations.firstIndex(where: { $0.target == target }) else { return }
        animations[index].isHidden.toggle()
    }

    public mutating func playEffect(for target: CanvasAnimatedObjectRef, now: Date = Date()) {
        guard let index = animations.firstIndex(where: { $0.target == target }) else { return }
        animations[index].manualStartedAt = now
        animations[index].pausedElapsed = 0
        animations[index].isPaused = false
        animations[index].isHidden = false
    }

    public mutating func pauseEffect(for target: CanvasAnimatedObjectRef, now: Date = Date()) {
        guard let index = animations.firstIndex(where: { $0.target == target }) else { return }
        let animation = animations[index]
        if let startedAt = animation.manualStartedAt, !animation.isPaused {
            animations[index].pausedElapsed = max(0, now.timeIntervalSince(startedAt))
        }
        animations[index].isPaused = true
    }

    public mutating func setRepeatMode(_ repeatMode: CanvasAnimationRepeatMode, for target: CanvasAnimatedObjectRef) {
        guard let index = animations.firstIndex(where: { $0.target == target }) else { return }
        animations[index].repeatMode = repeatMode
    }

    public mutating func removeAnimation(for target: CanvasAnimatedObjectRef) {
        animations.removeAll { $0.target == target }
    }

    public mutating func removeMissingTargets(validTargets: Set<CanvasAnimatedObjectRef>) {
        animations.removeAll { !validTargets.contains($0.target) }
    }

    public func containsAnimation(for target: CanvasAnimatedObjectRef) -> Bool {
        animation(for: target) != nil
    }

    public var maximumStep: Int {
        animations.map(\.order).max() ?? 0
    }

    private func nextOrder() -> Int {
        maximumStep + 1
    }

    private func defaultDuration(for preset: CanvasAnimationPreset) -> TimeInterval {
        switch preset {
        case .appear: return 0.01
        case .fade, .slide, .scale: return 0.45
        case .typewriter: return 1.8
        case .scrolling: return 2.4
        case .popIn: return 0.7
        case .glowPulse: return 1.1
        case .highlightSweep: return 1.0
        case .fancyTitle: return 1.2
        }
    }

    public func renderEffect(
        for target: CanvasAnimatedObjectRef,
        playback: CanvasAnimationPlaybackState,
        now: Date = Date()
    ) -> CanvasAnimationRenderEffect {
        guard let animation = animation(for: target) else {
            return .visible
        }

        guard !animation.isHidden else { return .hidden }

        if let manualProgress = manualProgress(for: animation, now: now) {
            return effect(for: animation, progress: manualProgress)
        }

        guard playback.isPresenting else {
            return .visible
        }

        if animation.trigger == .onSlideOpen {
            guard playback.currentStep == 0 else { return .visible }
            return effect(for: animation, progress: progress(for: animation, playback: playback, now: now))
        }

        guard playback.currentStep >= animation.order else {
            return .hidden
        }

        guard playback.currentStep == animation.order else {
            return .visible
        }

        return effect(for: animation, progress: progress(for: animation, playback: playback, now: now))
    }

    public func needsRenderTicks(
        for kind: CanvasAnimatedObjectKind,
        playback: CanvasAnimationPlaybackState,
        now: Date = Date()
    ) -> Bool {
        return animations.contains { animation in
            animation.target.kind == kind && needsRenderTicks(for: animation, playback: playback, now: now)
        }
    }

    public func needsRenderTicks(
        playback: CanvasAnimationPlaybackState,
        now: Date = Date()
    ) -> Bool {
        return animations.contains { animation in
            needsRenderTicks(for: animation, playback: playback, now: now)
        }
    }

    private func needsRenderTicks(
        for animation: CanvasObjectAnimation,
        playback: CanvasAnimationPlaybackState,
        now: Date
    ) -> Bool {
        guard !animation.isHidden else { return false }
        if animation.manualStartedAt != nil {
            return animation.repeatMode == .loop || manualElapsed(for: animation, now: now) < animation.totalManualDuration
        }
        guard playback.isPresenting else { return false }
        return ((animation.trigger == .onSlideOpen && playback.currentStep == 0) || animation.order == playback.currentStep)
            && now.timeIntervalSince(playback.stepStartedAt) < animation.delay + animation.duration
    }

    private func progress(
        for animation: CanvasObjectAnimation,
        playback: CanvasAnimationPlaybackState,
        now: Date
    ) -> CGFloat {
        let elapsed = now.timeIntervalSince(playback.stepStartedAt) - animation.delay
        guard elapsed > 0 else { return 0 }
        return CGFloat(min(max(elapsed / animation.duration, 0), 1))
    }

    private func manualProgress(for animation: CanvasObjectAnimation, now: Date) -> CGFloat? {
        guard animation.manualStartedAt != nil else { return nil }
        let elapsed = manualElapsed(for: animation, now: now)
        guard elapsed > 0 else { return 0 }
        if animation.repeatMode == .loop {
            let cycleElapsed = elapsed.truncatingRemainder(dividingBy: animation.duration)
            return CGFloat(min(max(cycleElapsed / animation.duration, 0), 1))
        }
        guard elapsed < animation.totalManualDuration else { return 1 }
        let cycleElapsed = elapsed.truncatingRemainder(dividingBy: animation.duration)
        return CGFloat(min(max(cycleElapsed / animation.duration, 0), 1))
    }

    private func manualElapsed(for animation: CanvasObjectAnimation, now: Date) -> TimeInterval {
        guard let startedAt = animation.manualStartedAt else { return 0 }
        if animation.isPaused {
            return animation.pausedElapsed
        }
        return max(0, now.timeIntervalSince(startedAt))
    }

    private func effect(for animation: CanvasObjectAnimation, progress: CGFloat) -> CanvasAnimationRenderEffect {
        let eased = easeOut(progress)
        switch animation.preset {
        case .appear:
            return progress >= 1 ? .visible : .hidden
        case .fade:
            return CanvasAnimationRenderEffect(opacity: progress)
        case .slide:
            let remaining = 1 - progress
            return CanvasAnimationRenderEffect(opacity: progress, translation: CGSize(width: -36 * remaining, height: 0))
        case .scale:
            let scale = 0.82 + 0.18 * progress
            return CanvasAnimationRenderEffect(opacity: progress, scale: scale)
        case .typewriter:
            return CanvasAnimationRenderEffect(textRevealFraction: progress)
        case .scrolling:
            return CanvasAnimationRenderEffect(
                opacity: min(1, progress * 1.5),
                translation: CGSize(width: 72 * (1 - eased), height: 0),
                clipFraction: eased
            )
        case .popIn:
            let overshoot = progress < 0.72
                ? 0.45 + 0.72 * easeOut(progress / 0.72)
                : 1.17 - 0.17 * easeOut((progress - 0.72) / 0.28)
            return CanvasAnimationRenderEffect(opacity: min(1, progress * 1.4), scale: overshoot)
        case .glowPulse:
            let pulse = 0.5 + 0.5 * sin(progress * .pi * 2)
            return CanvasAnimationRenderEffect(scale: 1 + 0.035 * pulse, glowAlpha: pulse)
        case .highlightSweep:
            return CanvasAnimationRenderEffect(highlightProgress: eased)
        case .fancyTitle:
            return CanvasAnimationRenderEffect(
                opacity: min(1, progress * 1.35),
                scale: 0.82 + 0.18 * eased,
                glowAlpha: 0.35 * eased,
                titleShadowAlpha: eased
            )
        }
    }

    private func easeOut(_ value: CGFloat) -> CGFloat {
        let clamped = min(max(value, 0), 1)
        return 1 - pow(1 - clamped, 3)
    }
}

private extension CanvasObjectAnimation {
    var totalManualDuration: TimeInterval {
        duration * TimeInterval(repeatMode.playCount ?? 1)
    }
}

private extension Array where Element == CanvasObjectAnimation {
    func sortedForPresentation() -> [CanvasObjectAnimation] {
        sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
