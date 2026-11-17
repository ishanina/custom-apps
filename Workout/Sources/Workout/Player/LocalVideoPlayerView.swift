import SwiftUI
import AVKit

struct LocalVideoPlayerView: NSViewRepresentable {
    let filePath: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let volume: Int
    let isPaused: Bool
    var onEnded: () -> Void

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.controlsStyle = .floating
        playerView.wantsLayer = true
        playerView.layer?.cornerRadius = 14
        playerView.layer?.masksToBounds = true
        playerView.layer?.backgroundColor = NSColor.black.cgColor

        let item = AVPlayerItem(url: URL(fileURLWithPath: filePath))
        let player = AVPlayer(playerItem: item)
        player.isMuted = volume == 0
        player.volume = Float(volume) / 100
        playerView.player = player

        let coord = context.coordinator
        coord.player = player
        coord.endTime = endTime
        coord.onEnded = onEnded

        if startTime > 0 {
            player.seek(to: CMTime(seconds: startTime, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero) { [weak coord] _ in
                if coord?.wasPaused != true { player.play() }
            }
        } else {
            player.play()
        }

        if endTime > 0 {
            // Periodic observer is more reliable than a boundary observer after seeks.
            coord.periodicObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
            ) { [weak coord] time in
                guard let coord, time.seconds >= coord.endTime else { return }
                coord.player?.pause()
                coord.finish()
            }
        }

        coord.endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak coord] _ in coord?.finish() }

        return playerView
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        guard let player = view.player else { return }
        let coord = context.coordinator
        coord.onEnded = onEnded
        player.isMuted = volume == 0
        player.volume = Float(volume) / 100
        // Only react to transitions so we don't fight the player's own controls.
        if isPaused != coord.wasPaused {
            coord.wasPaused = isPaused
            if isPaused { player.pause() } else if !coord.hasEnded { player.play() }
        }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
        coordinator.cleanup()
        view.player?.pause()
        view.player = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var player: AVPlayer?
        var periodicObserver: Any?
        var endObserver: Any?
        var endTime: TimeInterval = 0
        var onEnded: (() -> Void)?
        var hasEnded = false
        var wasPaused = false

        func finish() {
            guard !hasEnded else { return }
            hasEnded = true
            onEnded?()
        }

        func cleanup() {
            if let o = periodicObserver { player?.removeTimeObserver(o); periodicObserver = nil }
            if let o = endObserver { NotificationCenter.default.removeObserver(o); endObserver = nil }
            player?.pause()
            player = nil
            onEnded = nil
            hasEnded = true
        }

        deinit { cleanup() }
    }
}
