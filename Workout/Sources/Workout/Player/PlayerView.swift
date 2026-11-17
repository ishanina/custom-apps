import SwiftUI

struct PlayerView: View {
    let routineID: UUID
    var onExit: () -> Void
    @EnvironmentObject var store: DataStore
    @StateObject private var vm = PlayerViewModel()

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                topBar
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if vm.isLoaded && vm.state != .complete {
                    PlayerControls(vm: vm)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 18)
                        .padding(.top, 12)
                }
            }
        }
        .onAppear {
            guard !vm.isLoaded, let routine = store.routine(id: routineID) else { return }
            vm.load(routine: routine, onStop: onExit, onComplete: { store.markCompleted(id: routineID) })
            #if DEBUG
            DebugScenes.apply(to: vm)
            #endif
        }
        .onDisappear { vm.teardown() }
    }

    // MARK: - Chrome

    private var accent: Color {
        switch vm.state {
        case .complete: return Theme.accent
        case .nextUp: return vm.nextStep?.type.tint ?? Theme.accent
        default: return vm.currentStep?.type.tint ?? Theme.accent
        }
    }

    private var background: some View {
        ZStack {
            Theme.canvas
            RadialGradient(colors: [accent.opacity(vm.currentStep?.type == .video && vm.state != .nextUp ? 0.08 : 0.22), .clear],
                           center: .top, startRadius: 0, endRadius: 700)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: accent)
    }

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.routineName.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                if vm.state != .complete, let step = vm.currentStep, step.type == .video {
                    Text(step.displayName)
                        .font(.rounded(15, .semibold))
                        .lineLimit(1)
                }
            }
            Spacer()
            if vm.state != .complete {
                HStack(spacing: 16) {
                    Text("Step \(min(vm.currentIndex + 1, vm.steps.count)) of \(vm.steps.count)")
                        .foregroundStyle(.secondary)
                    Label(Fmt.clock(TimeInterval(vm.elapsedSeconds)), systemImage: "stopwatch")
                        .foregroundStyle(.primary)
                }
                .font(.rounded(13, .medium))
                .monospacedDigit()
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !vm.isLoaded {
            ProgressView()
        } else {
            switch vm.state {
            case .complete:
                CompleteView(vm: vm, onDone: { vm.stop() })
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            case .nextUp:
                if let next = vm.nextStep {
                    NextUpView(step: next, number: vm.currentIndex + 2, total: vm.steps.count)
                        .transition(.opacity)
                }
            case .playing, .paused:
                if let step = vm.currentStep {
                    stepView(step)
                        .id("\(vm.currentIndex)-\(step.id)") // fresh view per step
                        .transition(.opacity)
                }
            }
        }
    }

    @ViewBuilder
    private func stepView(_ step: Step) -> some View {
        switch step.type {
        case .video:
            videoView(step)
                .padding(.horizontal, 24)
        case .timed, .rest:
            CountdownView(vm: vm, step: step)
        case .dance:
            DanceView(spotify: vm.spotify, songTarget: step.songCount ?? 1, isPaused: vm.state == .paused)
        }
    }

    @ViewBuilder
    private func videoView(_ step: Step) -> some View {
        if let id = step.youtubeID {
            YouTubePlayerView(videoID: id, startTime: step.startTime, endTime: step.endTime,
                              volume: vm.volume, isPaused: vm.state == .paused,
                              onEnded: { vm.videoDidEnd() })
        } else if step.videoSource == .local, let path = step.localPath {
            if FileManager.default.fileExists(atPath: path) {
                LocalVideoPlayerView(filePath: path, startTime: step.startTime, endTime: step.endTime,
                                     volume: vm.volume, isPaused: vm.state == .paused,
                                     onEnded: { vm.videoDidEnd() })
            } else {
                problem("Video file not found", detail: path)
            }
        } else {
            problem("This step has no video", detail: "Edit the routine to add a link or file.")
        }
    }

    private func problem(_ title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundStyle(.yellow)
            Text(title).font(.rounded(20, .semibold))
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Skip Step") { vm.skip() }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.top, 6)
        }
        .padding(40)
    }
}

// MARK: - Countdown

private struct CountdownView: View {
    @ObservedObject var vm: PlayerViewModel
    let step: Step

    private var tint: Color { step.type.tint }
    private var isFinalSeconds: Bool { vm.remainingSeconds <= 3 && vm.state == .playing }

    var body: some View {
        GeometryReader { geo in
            let ring = min(geo.size.height * 0.58, geo.size.width * 0.5, 360)
            VStack(spacing: ring * 0.08) {
                VStack(spacing: 6) {
                    Text(step.type == .rest ? "REST" : "EXERCISE")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(tint)
                    Text(step.type == .rest ? "Breathe" : step.displayName)
                        .font(.rounded(min(44, ring * 0.14), .bold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6)
                }

                ZStack {
                    Circle()
                        .stroke(tint.opacity(0.14), lineWidth: ring * 0.055)
                    Circle()
                        .trim(from: 0, to: vm.remainingFraction)
                        .stroke(tint.gradient, style: StrokeStyle(lineWidth: ring * 0.055, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: tint.opacity(0.5), radius: 12)
                        .animation(.linear(duration: 1), value: vm.remainingSeconds)
                    VStack(spacing: 4) {
                        Text(Fmt.clock(TimeInterval(vm.remainingSeconds)))
                            .font(.rounded(ring * 0.26, .bold))
                            .monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.snappy, value: vm.remainingSeconds)
                            .foregroundStyle(isFinalSeconds ? tint : .primary)
                            .scaleEffect(isFinalSeconds ? 1.06 : 1)
                            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: vm.remainingSeconds)
                        if vm.state == .paused {
                            Text("PAUSED")
                                .font(.system(size: 12, weight: .bold))
                                .tracking(2)
                                .foregroundStyle(.secondary)
                        } else {
                            Button("+15 sec") { vm.addTime(15) }
                                .buttonStyle(SecondaryButtonStyle())
                                .help("Add 15 seconds")
                        }
                    }
                }
                .frame(width: ring, height: ring)
                .opacity(vm.state == .paused ? 0.6 : 1)

                upNext
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var upNext: some View {
        if let next = vm.nextStep {
            HStack(spacing: 8) {
                Text("Up next").foregroundStyle(.secondary)
                Circle().fill(next.type.tint).frame(width: 6, height: 6)
                Text(next.displayName).fontWeight(.semibold).lineLimit(1)
                if let label = next.durationLabel {
                    Text(label).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.white.opacity(0.06)))
        } else {
            Text("Last one — finish strong")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Up next interstitial

private struct NextUpView: View {
    let step: Step
    let number: Int
    let total: Int
    @State private var progress: CGFloat = 0
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 22) {
            Text("UP NEXT · \(number) OF \(total)")
                .font(.system(size: 12, weight: .bold))
                .tracking(2)
                .foregroundStyle(.secondary)
            TypeBadge(type: step.type, size: 84, solid: true)
                .shadow(color: step.type.tint.opacity(0.5), radius: 24)
                .scaleEffect(appeared ? 1 : 0.7)
            VStack(spacing: 8) {
                Text(step.displayName)
                    .font(.rounded(42, .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(step.type == .dance ? "\(step.detailText) · \(step.durationLabel ?? "")" : step.durationLabel.map { "\(step.type.title) · \($0)" } ?? step.detailText)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .offset(y: appeared ? 0 : 10)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(step.type.tint).frame(width: geo.size.width * progress)
                }
            }
            .frame(width: 220, height: 4)
            .padding(.top, 6)
        }
        .padding(40)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { appeared = true }
            withAnimation(.linear(duration: PlayerViewModel.nextUpDuration)) { progress = 1 }
        }
    }
}

// MARK: - Dance

private struct DanceView: View {
    @ObservedObject var spotify: SpotifyController
    let songTarget: Int
    let isPaused: Bool

    var body: some View {
        VStack(spacing: 26) {
            Equalizer(active: spotify.songNumber > 0 && !isPaused)
                .frame(width: 200, height: 110)

            VStack(spacing: 6) {
                Text("DANCE")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(Theme.dance)
                if spotify.songNumber > 0 {
                    Text(spotify.trackName)
                        .font(.rounded(34, .bold))
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                    Text(spotify.artistName)
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(spotify.failed ? "Spotify isn't responding" : "Getting the music going…")
                        .font(.rounded(28, .bold))
                }
            }

            if spotify.songNumber > 0 {
                HStack(spacing: 18) {
                    SongDots(current: min(spotify.songNumber, songTarget), total: songTarget)
                    Button { spotify.skipSong() } label: {
                        Label("Next Song", systemImage: "forward.end.fill")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            } else {
                HStack(spacing: 10) {
                    if spotify.failed {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Text(spotify.statusMessage)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 460)
            }
        }
        .padding(40)
    }
}

private struct SongDots: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 10) {
            if total <= 12 {
                HStack(spacing: 6) {
                    ForEach(1...total, id: \.self) { i in
                        Capsule()
                            .fill(i < current ? Theme.dance : i == current ? Theme.dance : Color.white.opacity(0.15))
                            .opacity(i < current ? 0.5 : 1)
                            .frame(width: i == current ? 22 : 8, height: 8)
                    }
                }
                .animation(.spring(response: 0.4), value: current)
            }
            Text("Song \(current) of \(total)")
                .font(.rounded(13, .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

private struct Equalizer: View {
    let active: Bool
    private let bars = 9

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !active)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let barWidth = (geo.size.width - CGFloat(bars - 1) * 7) / CGFloat(bars)
                HStack(alignment: .center, spacing: 7) {
                    ForEach(0..<bars, id: \.self) { i in
                        let phase = Double(i) * 0.9
                        let speed = 2.4 + Double(i % 4) * 0.7
                        let level = active ? 0.22 + 0.78 * abs(sin(t * speed + phase)) * (0.6 + 0.4 * abs(cos(t * 0.7 + phase))) : 0.14
                        Capsule()
                            .fill(LinearGradient(colors: [Theme.dance, Theme.dance.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                            .frame(width: barWidth, height: max(barWidth, geo.size.height * level))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .animation(.easeOut(duration: 0.3), value: active)
    }
}

// MARK: - Complete

private struct CompleteView: View {
    @ObservedObject var vm: PlayerViewModel
    var onDone: () -> Void
    @State private var ring: CGFloat = 0
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.1))
                Circle()
                    .trim(from: 0, to: ring)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "checkmark")
                    .font(.system(size: 52, weight: .heavy))
                    .foregroundStyle(Theme.accent)
                    .scaleEffect(appeared ? 1 : 0.3)
                    .opacity(appeared ? 1 : 0)
            }
            .frame(width: 140, height: 140)
            .shadow(color: Theme.accent.opacity(0.35), radius: 30)

            VStack(spacing: 8) {
                Text("Workout complete")
                    .font(.rounded(38, .bold))
                Text(vm.routineName)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                stat(Fmt.clock(TimeInterval(vm.elapsedSeconds)), "Total time", "stopwatch")
                stat("\(vm.steps.count)", vm.steps.count == 1 ? "Step" : "Steps", "list.bullet")
                if vm.steps.contains(where: { $0.type == .timed }) {
                    let active = vm.steps.filter { $0.type == .timed }.reduce(0) { $0 + $1.duration }
                    stat(Fmt.clock(active), "Exercise time", "flame.fill")
                }
            }

            HStack(spacing: 12) {
                Button { vm.restart() } label: { Label("Go Again", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Done", action: onDone)
                    .buttonStyle(PrimaryButtonStyle(large: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(40)
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) { ring = 1 }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.35)) { appeared = true }
        }
    }

    private func stat(_ value: String, _ label: String, _ icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(.tertiary)
            Text(value).font(.rounded(24, .bold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: 130)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.raised))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline))
    }
}
