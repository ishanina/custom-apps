import SwiftUI

struct PlayerControls: View {
    @ObservedObject var vm: PlayerViewModel

    var body: some View {
        VStack(spacing: 14) {
            SegmentedProgress(vm: vm)

            HStack(spacing: 0) {
                // Left
                HStack(spacing: 4) {
                    Button(action: vm.stop) { Image(systemName: "xmark") }
                        .buttonStyle(IconButtonStyle(size: 38))
                        .keyboardShortcut(.cancelAction)
                        .help("End workout (esc)")
                    if vm.hasAudio {
                        Divider().frame(height: 18).padding(.horizontal, 8)
                        AudioCluster(vm: vm, music: vm.music)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Center transport
                HStack(spacing: 18) {
                    Button(action: vm.goBack) { Image(systemName: "backward.end.fill") }
                        .buttonStyle(IconButtonStyle(size: 44))
                        .keyboardShortcut(.leftArrow, modifiers: [])
                        .disabled(vm.currentIndex == 0 && !vm.isTimedStep)
                        .help("Previous step (←)")

                    Button(action: vm.togglePause) {
                        Image(systemName: vm.state == .paused ? "play.fill" : "pause.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Theme.accentInk)
                            .frame(width: 58, height: 58)
                            .background(Circle().fill(Theme.accent))
                            .shadow(color: Theme.accent.opacity(0.35), radius: 14)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(PressableStyle())
                    .keyboardShortcut(.space, modifiers: [])
                    .help(vm.state == .paused ? "Resume (space)" : "Pause (space)")

                    Button(action: vm.skip) { Image(systemName: "forward.end.fill") }
                        .buttonStyle(IconButtonStyle(size: 44))
                        .keyboardShortcut(.rightArrow, modifiers: [])
                        .help("Next step (→)")
                }

                // Right
                HStack(spacing: 4) {
                    Button { vm.soundsEnabled.toggle() } label: {
                        Image(systemName: vm.soundsEnabled ? "bell.fill" : "bell.slash")
                    }
                    .buttonStyle(IconButtonStyle(size: 34, active: vm.soundsEnabled))
                    .help(vm.soundsEnabled ? "Countdown beeps on" : "Countdown beeps off")


                    if vm.showsVolume {
                        Divider().frame(height: 18).padding(.horizontal, 6)
                        Button(action: vm.toggleMute) {
                            Image(systemName: volumeIcon)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(IconButtonStyle(size: 34))
                        .help(vm.volume == 0 ? "Unmute" : "Mute")
                        Slider(value: Binding(get: { Double(vm.volume) }, set: { vm.setVolume(Int($0)) }), in: 0...100)
                            .controlSize(.small)
                            .frame(width: 96)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.hairline))
        )
    }

    private var volumeIcon: String {
        switch vm.volume {
        case 0: return "speaker.slash.fill"
        case ..<34: return "speaker.wave.1.fill"
        case ..<67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}

private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// One segment per step, colored by type. Click a segment to jump to that step.
private struct SegmentedProgress: View {
    @ObservedObject var vm: PlayerViewModel

    var body: some View {
        HStack(spacing: vm.steps.count > 40 ? 2 : 4) {
            ForEach(Array(vm.steps.enumerated()), id: \.element.id) { index, step in
                Segment(step: step, fill: fill(for: index), isCurrent: index == vm.currentIndex)
                    .onTapGesture { vm.jump(to: index) }
                    .help("\(index + 1). \(step.displayName)")
            }
        }
        .frame(height: 14)
    }

    private func fill(for index: Int) -> Double {
        if index < vm.currentIndex { return 1 }
        if index > vm.currentIndex { return 0 }
        switch vm.state {
        case .nextUp, .complete: return 1
        default: return vm.isTimedStep ? 1 - vm.remainingFraction : 0.5
        }
    }
}

private struct Segment: View {
    let step: Step
    let fill: Double
    let isCurrent: Bool
    @State private var hovering = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(hovering ? 0.22 : 0.1))
                Capsule()
                    .fill(step.type.tint.opacity(isCurrent || fill < 1 ? 1 : 0.55))
                    .frame(width: max(0, geo.size.width * fill))
                    .animation(.linear(duration: 1), value: fill)
            }
            .frame(height: isCurrent || hovering ? 7 : 5)
            .frame(maxHeight: .infinity)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// Controls for the routine's background audio: ∓15 s for podcasts,
/// play/pause and next song (with what's playing) for Spotify.
private struct AudioCluster: View {
    @ObservedObject var vm: PlayerViewModel
    @ObservedObject var music: SpotifyController

    private var isPodcast: Bool { vm.currentAudio == .podcast }
    private var isSpotify: Bool { if case .spotify = vm.currentAudio { return true } else { return false } }
    private var label: String { isPodcast ? "podcast" : isSpotify ? "music" : "audio" }

    var body: some View {
        HStack(spacing: 2) {
            Button { vm.audioOn.toggle() } label: {
                Image(systemName: isPodcast ? "antenna.radiowaves.left.and.right" : isSpotify ? "music.note.list" : "speaker.wave.2")
            }
            .buttonStyle(IconButtonStyle(size: 34, active: vm.audioOn && vm.currentAudio != .none))
            .help(vm.audioOn ? "Turn off podcast and music for this workout" : "Turn on podcast and music")

            if vm.audioOn && vm.currentAudio != .none {
                if isPodcast {
                    Button { vm.skipAudio(-15) } label: { Image(systemName: "gobackward.15") }
                        .buttonStyle(IconButtonStyle(size: 34))
                        .keyboardShortcut("[", modifiers: [])
                        .help("Podcast back 15 seconds ([)")
                }
                Button { vm.toggleAudioPlayback() } label: {
                    Image(systemName: vm.audioPlaying ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(IconButtonStyle(size: 34))
                .help(vm.audioPlaying ? "Pause \(label)" : "Play \(label)")
                Button { vm.skipAudio(15) } label: {
                    Image(systemName: isPodcast ? "goforward.15" : "forward.end.fill")
                }
                .buttonStyle(IconButtonStyle(size: 34))
                .keyboardShortcut("]", modifiers: [])
                .help(isPodcast ? "Podcast forward 15 seconds (])" : "Next song (])")

                if isSpotify, !music.trackName.isEmpty {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(short(music.trackName)).font(.system(size: 12, weight: .semibold))
                        Text(short(music.artistName)).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.leading, 4)
                }
            }
        }
        .padding(.trailing, vm.audioOn && vm.currentAudio != .none ? 8 : 0)
        .background(Capsule().fill(Color.white.opacity(vm.audioOn && vm.currentAudio != .none ? 0.06 : 0)))
        .animation(.easeOut(duration: 0.18), value: vm.audioOn)
        .animation(.easeOut(duration: 0.18), value: vm.currentAudio)
    }

    private func short(_ text: String) -> String {
        text.count > 26 ? text.prefix(24) + "…" : text
    }
}
