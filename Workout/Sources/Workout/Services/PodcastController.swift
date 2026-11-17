import AppKit

/// Sends transport commands to a specific app through the private MediaRemote
/// framework. (Apple Podcasts has no AppleScript support; MediaRemote is what
/// the system's own media keys and Control Center use.)
enum MediaRemote {
    enum Command: UInt32 {
        case play = 0
        case pause = 1
        case skipForward = 17
        case skipBackward = 18
    }

    private typealias SendToApp = @convention(c) (UInt32, CFDictionary?, UnsafeRawPointer?, CFString, Int32, DispatchQueue?, UnsafeRawPointer?) -> Bool

    private static let sendToApp: SendToApp? = {
        let url = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, url as CFURL),
              let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommandToApp" as CFString)
        else { return nil }
        return unsafeBitCast(ptr, to: SendToApp.self)
    }()

    @discardableResult
    static func send(_ command: Command, to bundleID: String, skipInterval: Double? = nil) -> Bool {
        guard let sendToApp else { return false }
        let options = skipInterval.map { ["kMRMediaRemoteOptionSkipInterval": $0] as CFDictionary }
        return sendToApp(command.rawValue, options, nil, bundleID as CFString, 0, nil, nil)
    }
}

/// Plays whatever is up next in Apple Podcasts, in the background, alongside a workout.
final class PodcastController: ObservableObject {
    static let bundleID = "com.apple.podcasts"

    /// What we've asked Podcasts to do (macOS doesn't let us read its real state).
    @Published private(set) var isPlaying = false

    private var activationObserver: NSObjectProtocol?
    private var guardUntil = Date.distantPast
    private var launchedByUs = false
    private var launching = false

    private var runningApp: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first
    }

    func play() {
        isPlaying = true
        #if DEBUG
        if ProcessInfo.processInfo.environment["WORKOUT_SNAPSHOT_DIR"] != nil { return } // scripted screenshots: no audio
        #endif
        if let app = runningApp, app.isFinishedLaunching {
            MediaRemote.send(.play, to: Self.bundleID)
        } else {
            launchThenPlay()
        }
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        if runningApp != nil { MediaRemote.send(.pause, to: Self.bundleID) }
    }

    func togglePlayPause() { isPlaying ? pause() : play() }

    func skip(seconds: Double) {
        guard runningApp != nil else { return }
        MediaRemote.send(seconds >= 0 ? .skipForward : .skipBackward, to: Self.bundleID, skipInterval: abs(seconds))
    }

    func stop() {
        pause()
        stopFocusGuard()
    }

    // MARK: - Background launch

    private func launchThenPlay() {
        guard !launching,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else { return }
        launching = true
        launchedByUs = runningApp == nil
        guardFocus(for: 15)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.hides = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.launching = false
                self.hideIfLaunchedByUs()
                // A cold-launched Podcasts needs a moment before it accepts
                // commands; "play" is harmless to repeat.
                for delay in [1.5, 4.0] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                        guard let self, self.isPlaying else { return }
                        MediaRemote.send(.play, to: Self.bundleID)
                        self.hideIfLaunchedByUs()
                    }
                }
            }
        }
    }

    /// Podcasts likes to come to the front once it's loaded — hide it again.
    private func guardFocus(for seconds: TimeInterval) {
        guardUntil = Date().addingTimeInterval(seconds)
        guard activationObserver == nil else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == Self.bundleID else { return }
            if Date() > self.guardUntil { self.stopFocusGuard(); return }
            NSApp.activate(ignoringOtherApps: true)
            app.hide()
        }
    }

    private func hideIfLaunchedByUs() {
        guard launchedByUs, let app = runningApp else { return }
        if app.isActive { NSApp.activate(ignoringOtherApps: true) }
        app.hide()
    }

    private func stopFocusGuard() {
        if let observer = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            activationObserver = nil
        }
    }

    deinit { stopFocusGuard() }
}
