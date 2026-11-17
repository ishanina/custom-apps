import Foundation
import AppKit

enum PlayerState {
    case playing
    case paused
    case nextUp     // short "Up next" interstitial between steps
    case complete
}

final class PlayerViewModel: ObservableObject {
    @Published private(set) var currentIndex = 0
    @Published private(set) var state: PlayerState = .playing
    @Published private(set) var remainingSeconds = 0
    @Published private(set) var currentDuration = 0
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var isLoaded = false
    @Published private(set) var volume = 0

    @Published var soundsEnabled: Bool {
        didSet { UserDefaults.standard.set(soundsEnabled, forKey: "soundsEnabled") }
    }
    /// Whether this routine has any background audio or step music.
    @Published private(set) var hasAudio = false
    /// What is meant to accompany the current step (ignoring pauses).
    @Published private(set) var currentAudio: AudioSource = .none
    /// Session on/off switch for background audio and step music.
    @Published var audioOn = false {
        didSet {
            guard isLoaded, audioOn != oldValue else { return }
            audioUserPaused = false
            if audioOn { syncAudio() } else { stopAudio() }
        }
    }
    /// Whether audio is currently meant to be playing.
    @Published private(set) var audioPlaying = false

    static let nextUpDuration: TimeInterval = 2.5

    let spotify = SpotifyController()
    let podcast = PodcastController()
    /// Spotify controller for background/step music (separate from the dance-step one).
    let music = SpotifyController()
    private var backgroundAudio: AudioSource = .none
    private var audioUserPaused = false   // paused with the audio button, not by the workout
    private var loadedMusic: String?      // playlist currently loaded in Spotify by `music`
    private var musicPlaying = false
    private(set) var steps: [Step] = []
    private(set) var routineName = ""
    private var onStop: () -> Void = {}
    private var onComplete: () -> Void = {}

    private var countdownTimer: Timer?
    private var nextUpTimer: Timer?
    private var clockTimer: Timer?
    private var sleepActivity: NSObjectProtocol?

    init() {
        let defaults = UserDefaults.standard
        soundsEnabled = defaults.object(forKey: "soundsEnabled") as? Bool ?? true
    }

    // MARK: - Derived

    var currentStep: Step? { steps.indices.contains(currentIndex) ? steps[currentIndex] : nil }
    var nextStep: Step? { steps.indices.contains(currentIndex + 1) ? steps[currentIndex + 1] : nil }
    var isTimedStep: Bool { currentStep.map { $0.type == .timed || $0.type == .rest } ?? false }
    var showsVolume: Bool { currentStep.map { $0.type == .video || $0.type == .dance } ?? false }

    /// Fraction of the current timed step still remaining (1 → 0).
    var remainingFraction: Double {
        guard currentDuration > 0 else { return 0 }
        return Double(remainingSeconds) / Double(currentDuration)
    }

    // MARK: - Lifecycle

    func load(routine: Routine, onStop: @escaping () -> Void, onComplete: @escaping () -> Void) {
        steps = routine.steps
        routineName = routine.name
        self.onStop = onStop
        self.onComplete = onComplete
        switch routine.backgroundAudio {
        case .podcast: backgroundAudio = .podcast
        case .spotify: backgroundAudio = routine.backgroundPlaylistURI.map { .spotify($0) } ?? .none
        case .none: backgroundAudio = .none
        }
        hasAudio = backgroundAudio != .none || routine.steps.contains { $0.musicURI != nil }
        audioOn = hasAudio
        isLoaded = true
        preventSleep()
        startClock()
        startCurrentStep()
    }

    func restart() {
        cancelStepTimers()
        currentIndex = 0
        elapsedSeconds = 0
        preventSleep()
        startClock()
        startCurrentStep()
    }

    /// Ends the workout and returns to the editor.
    func stop() {
        teardown()
        onStop()
    }

    /// Stops all timers and media without navigating.
    func teardown() {
        stopAudio()
        cancelStepTimers()
        clockTimer?.invalidate()
        clockTimer = nil
        allowSleep()
    }

    // MARK: - Transport

    func togglePause() {
        switch state {
        case .playing:
            state = .paused
            countdownTimer?.invalidate()
            countdownTimer = nil
            if currentStep?.type == .dance { spotify.pause() }
            syncAudio()
        case .paused:
            state = .playing
            if isTimedStep { startCountdown() }
            if currentStep?.type == .dance { spotify.resume() }
            syncAudio()
        case .nextUp:
            advance() // skip the interstitial
        case .complete:
            break
        }
    }

    func skip() {
        guard state != .complete else { return }
        if state == .nextUp { advance(); return }
        cancelStepTimers()
        advance()
    }

    func goBack() {
        guard state != .complete else { return }
        cancelStepTimers()
        // Like a music player: restart the step if we're well into it.
        if isTimedStep && currentDuration - remainingSeconds > 3 && state != .nextUp {
            startCurrentStep()
            return
        }
        if currentIndex > 0 { currentIndex -= 1 }
        startCurrentStep()
    }

    func jump(to index: Int) {
        guard steps.indices.contains(index), state != .complete else { return }
        cancelStepTimers()
        currentIndex = index
        startCurrentStep()
    }

    func addTime(_ seconds: Int) {
        guard isTimedStep, state == .playing || state == .paused else { return }
        remainingSeconds += seconds
        currentDuration += seconds
    }

    func videoDidEnd() {
        guard state == .playing || state == .paused else { return }
        finishStep()
    }

    // MARK: - Volume

    func setVolume(_ value: Int) {
        volume = value
        guard let step = currentStep else { return }
        VolumeStore.shared.setVolume(value, for: step.volumeKey)
        if step.type == .dance { spotify.setVolume(value) }
    }

    func toggleMute() {
        setVolume(volume == 0 ? 50 : 0)
    }

    // MARK: - Background audio

    func toggleAudioPlayback() {
        guard audioOn else { return }
        audioUserPaused = audioPlaying
        syncAudio()
    }

    /// Podcast: jump ±seconds. Spotify: forward = next song.
    func skipAudio(_ seconds: Double) {
        guard audioOn, audioPlaying else { return }
        switch currentAudio {
        case .podcast: podcast.skip(seconds: seconds)
        case .spotify: if seconds > 0 { music.skipSong() }
        case .none: break
        }
    }

    /// What should accompany step `index`:
    /// - an exercise/rest step's own Spotify music,
    /// - a rest without its own music carries on the previous step's music
    ///   (so exercise → rest → exercise on one playlist never stops),
    /// - otherwise the routine's background audio. Dance steps handle Spotify themselves.
    func plannedAudio(at index: Int) -> AudioSource {
        guard steps.indices.contains(index) else { return .none }
        let step = steps[index]
        if step.type == .dance { return .none }
        if let uri = step.musicURI { return .spotify(uri) }
        if step.type == .rest, index > 0, steps[index - 1].type != .dance {
            let previous = plannedAudio(at: index - 1)
            if previous != backgroundAudio { return previous }
        }
        return backgroundAudio
    }

    /// Makes Podcasts/Spotify match the current step. The same playlist on
    /// consecutive steps keeps playing; returning to a paused one resumes it.
    private func syncAudio() {
        guard isLoaded else { return }
        currentAudio = plannedAudio(at: currentIndex)
        let inDance = currentStep?.type == .dance && state != .complete
        let running = state == .playing || state == .nextUp
        let target: AudioSource = (audioOn && !audioUserPaused && running) ? currentAudio : .none

        // Podcast
        if target == .podcast {
            if !podcast.isPlaying { podcast.play() }
        } else if podcast.isPlaying {
            podcast.pause()
        }

        // Spotify (background / step music)
        if inDance {
            // The dance step takes Spotify over; start fresh afterwards.
            if loadedMusic != nil { music.detach(); loadedMusic = nil; musicPlaying = false }
        } else if case .spotify(let uri) = target {
            if loadedMusic == uri {
                if !musicPlaying { music.resume() }
            } else {
                music.startBackground(playlistURI: uri)
                loadedMusic = uri
            }
            musicPlaying = true
        } else if musicPlaying {
            music.pause()
            musicPlaying = false
        }

        audioPlaying = target != .none
    }

    private func stopAudio() {
        podcast.stop()
        if loadedMusic != nil { music.abort() }
        loadedMusic = nil
        musicPlaying = false
        audioPlaying = false
    }

    // MARK: - Step machinery

    private func startCurrentStep() {
        guard let step = currentStep else { complete(); return }
        state = .playing
        // Videos start muted by default (often paired with a podcast); dance needs sound.
        volume = VolumeStore.shared.volume(for: step.volumeKey, default: step.type == .dance ? 75 : 0)

        switch step.type {
        case .timed, .rest:
            currentDuration = max(1, Int(step.duration))
            remainingSeconds = currentDuration
            startCountdown()
        case .dance:
            currentDuration = 0
            startDance(step)
        case .video:
            currentDuration = 0 // the video view reports when it ends
        }
        syncAudio()
    }

    private func startCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.state == .playing else { return }
            self.remainingSeconds -= 1
            if (1...3).contains(self.remainingSeconds) { self.playSound("Tink") }
            if self.remainingSeconds <= 0 {
                self.countdownTimer?.invalidate()
                self.countdownTimer = nil
                self.playSound("Glass")
                self.finishStep()
            }
        }
    }

    private func startDance(_ step: Step) {
        guard let uri = SpotifyURLParser.playlistURI(from: step.url ?? "") else {
            advance()
            return
        }
        spotify.startDance(playlistURI: uri, songCount: step.songCount ?? 1, volume: volume) { [weak self] in
            guard let self, self.state == .playing || self.state == .paused else { return }
            self.finishStep()
        }
    }

    /// Current step finished on its own: show "Up next" briefly, then advance.
    private func finishStep() {
        cancelStepTimers()
        guard nextStep != nil else { advance(); return }
        state = .nextUp
        nextUpTimer = Timer.scheduledTimer(withTimeInterval: Self.nextUpDuration, repeats: false) { [weak self] _ in
            self?.advance()
        }
    }

    private func advance() {
        cancelStepTimers()
        currentIndex += 1
        if currentIndex >= steps.count {
            complete()
        } else {
            startCurrentStep()
        }
    }

    private func complete() {
        cancelStepTimers()
        currentIndex = steps.count
        state = .complete
        clockTimer?.invalidate()
        clockTimer = nil
        allowSleep()
        syncAudio()
        onComplete()
    }

    private func cancelStepTimers() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        nextUpTimer?.invalidate()
        nextUpTimer = nil
        spotify.abort()
    }

    private func startClock() {
        clockTimer?.invalidate()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.state == .playing || self.state == .nextUp else { return }
            self.elapsedSeconds += 1
        }
    }

    // MARK: - System

    private func playSound(_ name: String) {
        guard soundsEnabled else { return }
        (NSSound(named: NSSound.Name(name))?.copy() as? NSSound)?.play()
    }

    private func preventSleep() {
        guard sleepActivity == nil else { return }
        sleepActivity = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .userInitiated],
            reason: "Workout in progress"
        )
    }

    private func allowSleep() {
        if let activity = sleepActivity {
            ProcessInfo.processInfo.endActivity(activity)
            sleepActivity = nil
        }
    }

    #if DEBUG
    func debugShowNextUp() { finishStep() }
    #endif

    deinit {
        countdownTimer?.invalidate()
        nextUpTimer?.invalidate()
        clockTimer?.invalidate()
        allowSleep()
    }
}
