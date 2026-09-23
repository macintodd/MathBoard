//
//  WidgetVideoPlayer.swift
//  WidgetEngine
//
//  Native AVPlayer-based video player for movie widgets. A single AVPlayer
//  per widget ID is shared between the teacher display (controls overlay) and
//  the external/presentation display (bare video layer), giving frame-perfect
//  sync with no JS bridge and no WKWebView compositing issues.
//

import AVFoundation
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AVKit
#endif

// MARK: - VideoPlayerRegistry

/// Maps widget IDs to shared AVPlayer instances so the teacher display and
/// external display always render from the same player timeline.
@MainActor
final class VideoPlayerRegistry {
    static let shared = VideoPlayerRegistry()
    private var players: [UUID: AVPlayer] = [:]

    func player(for widgetID: UUID, url: URL) -> AVPlayer {
        if let existing = players[widgetID] { return existing }
        let player = AVPlayer(url: url)
        players[widgetID] = player
        return player
    }
}

// MARK: - AVPlayerLayerView

/// Cross-platform SwiftUI wrapper around AVPlayerLayer.
/// On iOS/Catalyst the UIView's layerClass IS AVPlayerLayer, so the GPU
/// compositor routes video frames to whichever screen the view lives on —
/// which is exactly what WKWebView's internal compositor failed to do.
#if os(iOS)
struct AVPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    var backgroundColor: UIColor = .black

    func makeUIView(context: Context) -> PlayerUIView {
        PlayerUIView(player: player, backgroundColor: backgroundColor)
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.playerLayer.player = player
        uiView.backgroundColor = backgroundColor
        uiView.playerLayer.backgroundColor = backgroundColor.cgColor
    }

    final class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        init(player: AVPlayer, backgroundColor: UIColor) {
            super.init(frame: .zero)
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspect
            playerLayer.backgroundColor = backgroundColor.cgColor
            self.backgroundColor = backgroundColor
            isOpaque = true
        }
        required init?(coder: NSCoder) { fatalError() }
    }
}
#elseif os(macOS)
struct AVPlayerLayerView: NSViewRepresentable {
    let player: AVPlayer
    var backgroundColor: NSColor = .black

    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.player = player
        v.controlsStyle = .none
        v.wantsLayer = true
        v.layer?.backgroundColor = backgroundColor.cgColor
        return v
    }
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
        nsView.layer?.backgroundColor = backgroundColor.cgColor
    }
}
#endif

// MARK: - VideoPlayerState

/// Observable state for the teacher display's control bar.
/// Owns the time observer and end-of-video handler for a shared AVPlayer.
@MainActor
final class VideoPlayerState: ObservableObject {
    let player: AVPlayer

    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isLooping = false

    var isSeeking = false

    // nonisolated(unsafe): cleaned up in deinit, which in practice runs on the
    // main thread when the StateObject is released as the view disappears.
    nonisolated(unsafe) var timeObserverToken: Any?
    nonisolated(unsafe) var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?

    init(player: AVPlayer) {
        self.player = player
        isPlaying = player.rate > 0
        let t = player.currentTime().seconds
        currentTime = t.isFinite ? t : 0
        setupObservers()
    }

    private func setupObservers() {
        // KVO on item status to populate duration as soon as the asset is ready
        statusObserver = player.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self, item.status == .readyToPlay else { return }
                let d = item.duration
                if d.isNumeric && d.seconds.isFinite && d.seconds > 0 {
                    self.duration = d.seconds
                }
            }
        }

        // Async fallback for duration (covers slow-loading remote/network items)
        Task {
            guard let item = player.currentItem else { return }
            if let d = try? await item.asset.load(.duration),
               d.isNumeric && d.seconds.isFinite && d.seconds > 0 {
                duration = d.seconds
            }
        }

        // Periodic time observer drives the seek bar at 10 fps
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval, queue: .main
        ) { [weak self] time in
            // Callback is on .main; assumeIsolated crosses the Swift 6 actor boundary.
            MainActor.assumeIsolated {
                guard let self, !self.isSeeking else { return }
                let t = time.seconds
                self.currentTime = t.isFinite ? t : 0
                self.isPlaying = self.player.rate > 0
            }
        }

        // End-of-video: loop back or reset to first frame
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPlaying = false
                if self.isLooping {
                    self.player.seek(to: .zero) { [weak self] _ in
                        self?.player.play()
                    }
                } else {
                    self.player.seek(to: .zero)
                    self.currentTime = 0
                }
            }
        }
    }

    func togglePlayPause() {
        if isPlaying {
            player.pause()
        } else {
#if os(iOS)
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
#endif
            player.play()
        }
    }

    func seekBegan() { isSeeking = true }

    func seekCommit(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600)) { [weak self] _ in
            Task { @MainActor [weak self] in self?.isSeeking = false }
        }
    }

    func skip(by delta: Double) {
        let t = max(0, min(duration, currentTime + delta))
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600))
    }

    deinit {
        if let token = timeObserverToken { player.removeTimeObserver(token) }
        if let obs = endObserver { NotificationCenter.default.removeObserver(obs) }
        statusObserver?.invalidate()
    }
}

// MARK: - WidgetVideoPlayerView (teacher display)

/// Native video player for the teacher display. Shows the video with a
/// frosted-glass control bar (play/pause, ±10 s skip, seek slider, time)
/// and a Loop toggle overlaid top-right — matching the previous HTML player.
struct WidgetVideoPlayerView: View {
    let player: AVPlayer
    @StateObject private var state: VideoPlayerState

    init(player: AVPlayer) {
        self.player = player
        _state = StateObject(wrappedValue: VideoPlayerState(player: player))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
            AVPlayerLayerView(player: player)
            controlBar
        }
        .overlay(alignment: .topTrailing) {
            loopToggle.padding(10)
        }
    }

    // MARK: Loop toggle

    private var loopToggle: some View {
        Button { state.isLooping.toggle() } label: {
            Text("Loop")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(state.isLooping
                              ? Color(red: 0.035, green: 0.36, blue: 0.165).opacity(0.88)
                              : Color.black.opacity(0.58))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            state.isLooping
                                ? Color(red: 0.21, green: 0.85, blue: 0.43)
                                : Color.white.opacity(0.72),
                            lineWidth: 2
                        )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Control bar

    private var controlBar: some View {
        VStack(spacing: 2) {
            Slider(
                value: Binding(
                    get: { state.currentTime },
                    set: { state.currentTime = $0 }
                ),
                in: 0...max(state.duration, 1),
                onEditingChanged: { editing in
                    if editing { state.seekBegan() }
                    else { state.seekCommit(to: state.currentTime) }
                }
            )
            .tint(.white)
            .padding(.horizontal, 2)

            HStack(spacing: 0) {
                Text(timeLabel(state.currentTime))
                    .frame(width: 48, alignment: .leading)

                Spacer()

                Button { state.skip(by: -10) } label: {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 19, weight: .medium))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)

                Button { state.togglePlayPause() } label: {
                    Image(systemName: state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 38))
                }
                .buttonStyle(.plain)

                Button { state.skip(by: 10) } label: {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 19, weight: .medium))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)

                Spacer()

                Text(timeLabel(state.duration))
                    .frame(width: 48, alignment: .trailing)
            }
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }

    private func timeLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
