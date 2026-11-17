import Foundation
import AppKit

/// Drives a "Dance" step by controlling the Spotify desktop app over AppleScript:
/// turns on shuffle, starts the chosen playlist, then watches track changes until
/// the requested number of songs has played.
///
/// Spotify is launched in the background (never activated) so Workout
/// stays in front. The first time the app talks to Spotify, macOS shows an
/// Automation permission prompt that must be accepted.
final class SpotifyController: ObservableObject {
    @Published var songNumber: Int = 0 // 1-based; 0 until the first song is detected
    @Published var trackName: String = ""
    @Published var artistName: String = ""
    @Published var statusMessage: String = ""
    @Published var failed: Bool = false

    private static let spotifyBundleId = "com.spotify.client"

    // Shared so commands from the dance step and the background playlist run in order.
    private static let scriptQueue = DispatchQueue(label: "workout.spotify-script")
    private var pollTimer: Timer?
    private var lastTrackId: String?
    private var songsCompleted = 0
    private var songTarget = 0
    private var hasStartedPlaying = false
    private var startAttempts = 0
    private var active = false
    private var onFinished: (() -> Void)?
    private var countsSongs = true       // false = background playlist that just keeps playing

    // Keeping Spotify in the background
    private var activationObserver: NSObjectProtocol?
    private var guardFocusUntil = Date.distantPast
    private var launchedByUs = false     // Spotify wasn't running before this dance step
    private var workoutWasFrontmost = false

    // MARK: - Public

    func startDance(playlistURI: String, songCount: Int, volume: Int, onFinished: @escaping () -> Void) {
        begin(countingSongs: true)
        songTarget = max(1, songCount)
        self.onFinished = onFinished
        launchSpotifyInBackground(playlistURI: playlistURI, volume: volume)
    }

    /// Shuffles a playlist in the background with no end (the routine's background music).
    func startBackground(playlistURI: String) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["WORKOUT_SNAPSHOT_DIR"] != nil { // scripted screenshots: no audio
            trackName = "Song Title"; artistName = "Artist"; return
        }
        #endif
        begin(countingSongs: false)
        launchSpotifyInBackground(playlistURI: playlistURI, volume: nil)
    }

    private func begin(countingSongs: Bool) {
        abort()
        active = true
        countsSongs = countingSongs
        songsCompleted = 0
        songNumber = 0
        trackName = ""
        artistName = ""
        statusMessage = "Opening Spotify…"
        failed = false
        lastTrackId = nil
        hasStartedPlaying = false
        startAttempts = 0
        workoutWasFrontmost = NSApp.isActive
        launchedByUs = NSRunningApplication.runningApplications(withBundleIdentifier: Self.spotifyBundleId).isEmpty
        // Cold launches take a while; keep pushing Spotify back until playback has settled.
        guardFocus(for: 60)
    }

    func pause() {
        runScript("tell application \"Spotify\" to pause")
    }

    func resume() {
        runScript("tell application \"Spotify\" to play")
    }

    func skipSong() {
        runScript("tell application \"Spotify\" to next track")
    }

    func setVolume(_ vol: Int) {
        runScript("tell application \"Spotify\" to set sound volume to \(max(0, min(100, vol)))")
    }

    /// Stops watching without pausing — used when another controller (a dance
    /// step) takes over Spotify.
    func detach() {
        pollTimer?.invalidate()
        pollTimer = nil
        onFinished = nil
        stopFocusGuard()
        active = false
    }

    /// Stops watching and pauses Spotify if a dance step is in progress.
    func abort() {
        pollTimer?.invalidate()
        pollTimer = nil
        onFinished = nil
        stopFocusGuard()
        if active {
            active = false
            pause()
        }
    }

    // MARK: - Private

    private func launchSpotifyInBackground(playlistURI: String, volume: Int?) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.spotifyBundleId) else {
            statusMessage = "Spotify is not installed."
            failed = true
            return
        }
        // Launch without activating so Workout stays in front.
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.hides = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self = self, self.active else { return }
                if error != nil {
                    self.statusMessage = "Couldn't open Spotify."
                    self.failed = true
                    return
                }
                self.statusMessage = "Connecting to Spotify…"
                self.keepSpotifyInBackground()
                self.attemptStart(playlistURI: playlistURI, volume: volume)
            }
        }
    }

    private func attemptStart(playlistURI: String, volume: Int?) {
        guard active, !hasStartedPlaying else { return }
        startAttempts += 1
        guard startAttempts <= 30 else {
            statusMessage = "Couldn't control Spotify. Allow it under System Settings → Privacy & Security → Automation, or skip this step."
            failed = true
            return
        }
        if startAttempts >= 4 {
            statusMessage = "Connecting to Spotify… If macOS asks for permission to control Spotify, click OK."
        }
        // Spotify may need a while after a cold launch before it accepts
        // commands — and it can also silently ignore a play command while
        // still loading. Keep re-sending until polling actually sees
        // playback happening.
        let script = """
        tell application "Spotify"
            set shuffling to true
            \(volume.map { "set sound volume to \(max(0, min(100, $0)))" } ?? "")
            play track "\(playlistURI)"
        end tell
        """
        runScript(script) { [weak self] ok in
            guard let self = self, self.active, !self.hasStartedPlaying else { return }
            if ok {
                self.keepSpotifyInBackground()
                self.startPolling()
            }
            // Whether or not the script succeeded, try again in a few seconds
            // unless playback has been observed by then.
            DispatchQueue.main.asyncAfter(deadline: .now() + (ok ? 5 : 1.5)) {
                self.attemptStart(playlistURI: playlistURI, volume: volume)
            }
        }
    }

    // MARK: - Background-only Spotify

    /// While a dance step is starting, any time Spotify comes to the front
    /// (it does this on its own after a cold launch), hide it right away.
    private func guardFocus(for seconds: TimeInterval) {
        guardFocusUntil = Date().addingTimeInterval(seconds)
        guard activationObserver == nil else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == Self.spotifyBundleId else { return }
            if Date() > self.guardFocusUntil {
                self.stopFocusGuard() // after startup, the user switching to Spotify is deliberate
                return
            }
            self.hide(app)
        }
    }

    private func stopFocusGuard() {
        if let observer = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            activationObserver = nil
        }
        guardFocusUntil = .distantPast
    }

    /// Hides Spotify if we launched it (an already-open Spotify is left alone
    /// unless it jumps to the front), and keeps Workout in front.
    private func keepSpotifyInBackground() {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.spotifyBundleId).first else { return }
        if launchedByUs || app.isActive { hide(app) }
    }

    private func hide(_ spotify: NSRunningApplication) {
        if workoutWasFrontmost && !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        spotify.hide()
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        guard active else { return }
        let script = """
        tell application "Spotify"
            if player state is playing then
                return (id of current track) & "|||" & (name of current track) & "|||" & (artist of current track)
            else
                return "##" & (player state as text)
            end if
        end tell
        """
        runScriptReturning(script) { [weak self] result in
            guard let self = self, self.active, let result = result else { return }
            if result.hasPrefix("##") {
                // Paused is fine (either our own pause or the user's).
                // Stopped after we saw playback means the playlist ran out.
                if result.contains("stopped") && self.hasStartedPlaying && self.countsSongs {
                    self.finish()
                }
                return
            }
            let parts = result.components(separatedBy: "|||")
            guard parts.count >= 3 else { return }
            if !self.hasStartedPlaying {
                self.hasStartedPlaying = true
                self.keepSpotifyInBackground()
                self.guardFocusUntil = Date().addingTimeInterval(8) // Spotify can still pop up just after playback starts
            }
            if !self.countsSongs {
                self.trackName = parts[1]
                self.artistName = parts[2]
                return
            }
            let id = parts[0]
            if self.lastTrackId == nil {
                self.lastTrackId = id
                self.songNumber = 1
            } else if id != self.lastTrackId {
                self.lastTrackId = id
                self.songsCompleted += 1
                if self.songsCompleted >= self.songTarget {
                    self.finish()
                    return
                }
                self.songNumber = self.songsCompleted + 1
            }
            self.trackName = parts[1]
            self.artistName = parts[2]
        }
    }

    private func finish() {
        let callback = onFinished
        abort()
        callback?()
    }

    // MARK: - AppleScript plumbing

    private func runScript(_ source: String, completion: ((Bool) -> Void)? = nil) {
        Self.scriptQueue.async {
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error = error {
                print("[Spotify] Script error: \(error)")
            }
            if let completion = completion {
                DispatchQueue.main.async { completion(result != nil) }
            }
        }
    }

    private func runScriptReturning(_ source: String, completion: @escaping (String?) -> Void) {
        Self.scriptQueue.async {
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            DispatchQueue.main.async { completion(result?.stringValue) }
        }
    }
}

enum SpotifyURLParser {
    /// Liked Songs has no share link, but Spotify accepts this URI.
    static let likedSongsURI = "spotify:collection:tracks"

    static func isLikedSongs(_ input: String) -> Bool {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return t == likedSongsURI || t == "spotify:collection"
            || (t.hasPrefix("spotify:user:") && t.hasSuffix(":collection"))
            || t.contains("open.spotify.com/collection/tracks")
    }

    /// Accepts "https://open.spotify.com/playlist/<id>?si=..." or "spotify:playlist:<id>"
    /// and returns a canonical "spotify:playlist:<id>" URI.
    static func playlistURI(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if isLikedSongs(trimmed) { return likedSongsURI }
        let patterns = [
            "spotify:playlist:([A-Za-z0-9]+)",
            "open\\.spotify\\.com/playlist/([A-Za-z0-9]+)"
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let range = Range(match.range(at: 1), in: trimmed) {
                return "spotify:playlist:" + trimmed[range]
            }
        }
        return nil
    }
}
