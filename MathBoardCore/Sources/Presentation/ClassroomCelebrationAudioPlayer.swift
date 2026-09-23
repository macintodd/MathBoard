//
//  ClassroomCelebrationAudioPlayer.swift
//  MathBoardCore - Presentation module
//

import AVFoundation
import Foundation

@MainActor
public final class ClassroomCelebrationAudioPlayer {
    public static let shared = ClassroomCelebrationAudioPlayer()

    private let engine = AVAudioEngine()
    private let rewardNode = AVAudioPlayerNode()
    private let rewardFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 44_100,
        channels: 2,
        interleaved: false
    )
    private var starLaunchPlayer: AVAudioPlayer?

    private init() {
        configureAudioSessionIfNeeded()
        configureRewardEngine()
        starLaunchPlayer = Self.makePlayer(resourceName: "starlaunch", extension: "wav")
    }

    public func playStarLaunch() {
        if playLayeredRewardCue() {
            return
        }

        playBundledFallback()
    }

    private static func makePlayer(resourceName: String, extension fileExtension: String) -> AVAudioPlayer? {
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: fileExtension),
              let player = try? AVAudioPlayer(contentsOf: url) else {
            return nil
        }
        player.prepareToPlay()
        return player
    }

    private func configureRewardEngine() {
        guard let rewardFormat else { return }
        engine.attach(rewardNode)
        engine.connect(rewardNode, to: engine.mainMixerNode, format: rewardFormat)
        engine.mainMixerNode.outputVolume = 0.72
        try? engine.start()
    }

    private func playLayeredRewardCue() -> Bool {
        guard let rewardFormat,
              let buffer = makeLayeredRewardBuffer(format: rewardFormat) else {
            return false
        }

        if !engine.isRunning {
            try? engine.start()
        }
        guard engine.isRunning else { return false }

        if rewardNode.isPlaying {
            rewardNode.stop()
        }
        rewardNode.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        rewardNode.play()
        return true
    }

    private func playBundledFallback() {
        guard let starLaunchPlayer else { return }
        if starLaunchPlayer.isPlaying {
            starLaunchPlayer.stop()
        }
        starLaunchPlayer.enableRate = true
        starLaunchPlayer.rate = Float.random(in: 0.97...1.03)
        starLaunchPlayer.currentTime = 0
        starLaunchPlayer.play()
    }

    private func makeLayeredRewardBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let duration = 1.55
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let left = buffer.floatChannelData?[0],
              let right = buffer.floatChannelData?[1] else {
            return nil
        }

        buffer.frameLength = frameCount
        let pitchMultiplier = Double.random(in: 0.97...1.03)
        var filteredNoise = 0.0
        let twoPi = Double.pi * 2

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            var leftSample = 0.0
            var rightSample = 0.0

            if t < 0.24 {
                let dingEnvelope = exp(-14.0 * t)
                let shimmerEnvelope = exp(-22.0 * max(0, t - 0.03))
                let fundamental = sin(twoPi * 1_760 * pitchMultiplier * t)
                let overtone = sin(twoPi * 2_640 * pitchMultiplier * t + 0.65) * 0.58
                let glass = sin(twoPi * 3_520 * pitchMultiplier * t + sin(twoPi * 18 * t) * 0.18) * 0.24
                let ding = (fundamental + overtone + glass) * dingEnvelope * shimmerEnvelope * 0.38
                leftSample += ding
                rightSample += ding
            }

            if (0.16...0.84).contains(t) {
                let whooshProgress = (t - 0.16) / 0.68
                let envelope = sin(.pi * whooshProgress) * 0.30
                let randomSample = Double.random(in: -1...1)
                let cutoff = 0.035 + whooshProgress * 0.045
                filteredNoise += (randomSample - filteredNoise) * cutoff
                let airyTone = sin(twoPi * (185 + 90 * whooshProgress) * pitchMultiplier * t) * 0.18
                let whoosh = (filteredNoise * 0.82 + airyTone) * envelope
                let pan = whooshProgress
                leftSample += whoosh * sqrt(1 - pan)
                rightSample += whoosh * sqrt(pan)
            }

            if t >= 0.72 {
                let padProgress = min(1, (t - 0.72) / 0.83)
                let fade = pow(1 - padProgress, 1.85)
                let attack = min(1, padProgress * 5)
                let envelope = attack * fade * 0.17
                let base = 1_046.5 * pitchMultiplier
                let chord = [
                    base,
                    base * pow(2, 4.0 / 12.0) * 1.006,
                    base * pow(2, 7.0 / 12.0) * 0.996,
                    base * pow(2, 11.0 / 12.0) * 1.004
                ]
                var pad = 0.0
                for (index, frequency) in chord.enumerated() {
                    let detune = sin(twoPi * (0.9 + Double(index) * 0.27) * t) * 0.002
                    pad += sin(twoPi * frequency * (1 + detune) * t + Double(index) * 0.34)
                }
                let sparkle = sin(twoPi * 4_186 * pitchMultiplier * t) * 0.10 * fade
                leftSample += (pad / Double(chord.count) + sparkle) * envelope
                rightSample += (pad / Double(chord.count) + sparkle * 1.18) * envelope
            }

            left[frame] = Float(max(-1, min(1, leftSample)))
            right[frame] = Float(max(-1, min(1, rightSample)))
        }

        return buffer
    }

    private func configureAudioSessionIfNeeded() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try? session.setActive(true)
        #endif
    }
}
