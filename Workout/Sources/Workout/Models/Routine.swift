import Foundation

// The on-disk format matches the original WorkoutOrganizer app, so routines
// exported from either app can be imported into the other.

enum StepType: String, Codable, CaseIterable, Identifiable {
    case video
    case timed
    case rest
    case dance

    var id: String { rawValue }
}

enum VideoSource: String, Codable {
    case youtube
    case local
}

struct Step: Identifiable, Codable, Equatable {
    var id: UUID
    var type: StepType

    // Video
    var videoSource: VideoSource?
    var url: String?            // YouTube link, or Spotify playlist link for dance steps
    var localPath: String?
    var startTime: TimeInterval
    var endTime: TimeInterval   // 0 = play to the end
    var label: String?
    /// Full length of the video, looked up automatically (see DurationResolver).
    var mediaDuration: TimeInterval?

    // Timed exercise
    var exerciseName: String?

    // Timed / rest
    var duration: TimeInterval

    // Dance
    var songCount: Int?

    // Exercise / rest: Spotify music for this step (playlist link or Liked Songs URI)
    var music: String?
    var musicName: String?   // looked up for display

    init(id: UUID = UUID(), type: StepType, videoSource: VideoSource? = nil, url: String? = nil,
         localPath: String? = nil, startTime: TimeInterval = 0, endTime: TimeInterval = 0,
         label: String? = nil, exerciseName: String? = nil, duration: TimeInterval = 0,
         songCount: Int? = nil) {
        self.id = id
        self.type = type
        self.videoSource = videoSource
        self.url = url
        self.localPath = localPath
        self.startTime = startTime
        self.endTime = endTime
        self.label = label
        self.exerciseName = exerciseName
        self.duration = duration
        self.songCount = songCount
    }
}

extension Step {
    var displayName: String {
        switch type {
        case .video:
            if let label, !label.isEmpty { return label }
            if videoSource == .local, let localPath {
                return URL(fileURLWithPath: localPath).deletingPathExtension().lastPathComponent
            }
            return "YouTube video"
        case .timed:
            if let exerciseName, !exerciseName.isEmpty { return exerciseName }
            return "Exercise"
        case .rest:
            return "Rest"
        case .dance:
            if let label, !label.isEmpty { return label }
            return "Dance break"
        }
    }

    var detailText: String {
        switch type {
        case .video:
            let source = videoSource == .local ? "Video file" : "YouTube"
            let range: String
            if endTime > startTime {
                range = "\(Fmt.clock(startTime)) – \(Fmt.clock(endTime))"
            } else if startTime > 0 {
                range = "From \(Fmt.clock(startTime)) to end"
            } else {
                range = "Full video"
            }
            return "\(source) · \(range)"
        case .timed:
            return musicURI != nil ? "Exercise · ♫ \(musicName ?? "Spotify")" : "Timed exercise"
        case .rest:
            return musicURI != nil ? "Recover · ♫ \(musicName ?? "Spotify")" : "Recover"
        case .dance:
            let n = songCount ?? 1
            return "\(n) song\(n == 1 ? "" : "s") · Spotify shuffle"
        }
    }

    /// Assumed average song length for estimating dance steps.
    static let averageSongLength: TimeInterval = 210

    /// Length of the step: exact for timed/rest/trimmed videos, the video's full
    /// length (minus the start offset) for untrimmed videos once it's been looked up,
    /// and an estimate for dance steps. 0 when not known yet.
    var displayDuration: TimeInterval {
        switch type {
        case .video:
            if endTime > startTime { return endTime - startTime }
            if let mediaDuration, mediaDuration > startTime { return mediaDuration - startTime }
            return 0
        case .timed, .rest: return duration
        case .dance: return Double(songCount ?? 1) * Self.averageSongLength
        }
    }

    /// Dance steps are estimated; untrimmed videos are unknown until their length is looked up.
    var isApproximate: Bool {
        type == .dance || (type == .video && displayDuration == 0)
    }

    /// Video whose full length still needs looking up.
    var needsMediaDuration: Bool { type == .video && endTime <= startTime && mediaDuration == nil }

    /// "5:00", "~7:00" for estimates, or nil if unknown.
    var durationLabel: String? {
        let d = displayDuration
        guard d > 0 else { return nil }
        return (isApproximate ? "~" : "") + Fmt.clock(d)
    }

    /// Length used for drawing proportional bars.
    var visualWeight: TimeInterval {
        let d = displayDuration
        return d > 0 ? d : 120
    }

    var youtubeID: String? {
        guard type == .video, videoSource != .local, let url else { return nil }
        return YouTubeURLParser.extractVideoID(from: url)
    }

    /// Spotify URI of this exercise/rest step's own music, if any.
    var musicURI: String? {
        guard type == .timed || type == .rest, let music else { return nil }
        return SpotifyURLParser.playlistURI(from: music)
    }

    /// Key used to remember a per-media volume.
    var volumeKey: String { url ?? localPath ?? "" }
}

struct Routine: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var steps: [Step]
    var lastCompletedAt: Date?
    // Background audio for the whole routine (stored as strings so unknown
    // values can never break loading).
    var audio: String?              // "podcast" | "spotify"
    var audioPlaylist: String?      // Spotify playlist link
    var audioPlaylistName: String?  // looked up for display

    init(id: UUID = UUID(), name: String = "New Routine", steps: [Step] = []) {
        self.id = id
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
        self.steps = steps
    }

    var totalDuration: TimeInterval { steps.reduce(0) { $0 + $1.displayDuration } }

    var backgroundAudio: BackgroundAudio {
        get { BackgroundAudio(rawValue: audio ?? "") ?? .none }
        set { audio = newValue == .none ? nil : newValue.rawValue }
    }

    /// Spotify playlist URI when Spotify background audio is set up.
    var backgroundPlaylistURI: String? {
        guard backgroundAudio == .spotify else { return nil }
        return SpotifyURLParser.playlistURI(from: audioPlaylist ?? "")
    }

    /// "24 min", "~24 min" when it includes estimates, or "—".
    var durationSummary: String { Step.summary(of: steps) }
}

extension Step {
    static func summary(of steps: [Step]) -> String {
        let total = steps.reduce(0) { $0 + $1.displayDuration }
        if total == 0 { return "—" }
        return (steps.contains { $0.isApproximate } ? "~" : "") + Fmt.human(total)
    }
}

enum BackgroundAudio: String, CaseIterable, Identifiable {
    case none
    case podcast
    case spotify

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None"
        case .podcast: return "Podcast"
        case .spotify: return "Spotify"
        }
    }

    var symbol: String {
        switch self {
        case .none: return "speaker.slash"
        case .podcast: return "antenna.radiowaves.left.and.right"
        case .spotify: return "music.note.list"
        }
    }
}

/// What should be playing alongside a step.
enum AudioSource: Equatable {
    case none
    case podcast
    case spotify(String)   // playlist / Liked Songs URI
}
