//
//  ClassroomCelebrationAudioPlayer.swift
//  MathBoardCore - Presentation module
//

import AVFoundation
import Foundation

@MainActor
public final class ClassroomCelebrationAudioPlayer {
    public static let shared = ClassroomCelebrationAudioPlayer()

    private var starLaunchPlayer: AVAudioPlayer?

    private init() {
        configureAudioSessionIfNeeded()
        starLaunchPlayer = Self.makePlayer(resourceName: "starlaunch", extension: "wav")
    }

    public func playStarLaunch() {
        guard let starLaunchPlayer else { return }
        if starLaunchPlayer.isPlaying {
            starLaunchPlayer.stop()
        }
        starLaunchPlayer.currentTime = 0
        starLaunchPlayer.play()
    }

    private static func makePlayer(resourceName: String, extension fileExtension: String) -> AVAudioPlayer? {
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: fileExtension),
              let player = try? AVAudioPlayer(contentsOf: url) else {
            return nil
        }
        player.prepareToPlay()
        return player
    }

    private func configureAudioSessionIfNeeded() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try? session.setActive(true)
        #endif
    }
}
