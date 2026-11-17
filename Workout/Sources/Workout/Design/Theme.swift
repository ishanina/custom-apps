import SwiftUI

enum Theme {
    /// Signature "volt" accent used for primary actions.
    static let accent = Color(red: 0.84, green: 1.0, blue: 0.28)
    static let accentInk = Color(red: 0.06, green: 0.08, blue: 0.02)

    static let canvas = Color(red: 0.075, green: 0.075, blue: 0.085)
    static let raised = Color.white.opacity(0.045)
    static let hairline = Color.white.opacity(0.08)

    static let video = Color(red: 0.47, green: 0.52, blue: 1.0)
    static let exercise = Color(red: 1.0, green: 0.60, blue: 0.22)
    static let rest = Color(red: 0.36, green: 0.80, blue: 0.97)
    static let dance = Color(red: 1.0, green: 0.36, blue: 0.66)
}

extension Font {
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension StepType {
    var title: String {
        switch self {
        case .video: return "Video"
        case .timed: return "Exercise"
        case .rest: return "Rest"
        case .dance: return "Dance"
        }
    }

    var blurb: String {
        switch self {
        case .video: return "Follow along with a clip"
        case .timed: return "Count down a move"
        case .rest: return "Catch your breath"
        case .dance: return "Shuffle a Spotify playlist"
        }
    }

    var tint: Color {
        switch self {
        case .video: return Theme.video
        case .timed: return Theme.exercise
        case .rest: return Theme.rest
        case .dance: return Theme.dance
        }
    }

    var symbol: String {
        switch self {
        case .video: return "play.rectangle.fill"
        case .timed: return "flame.fill"
        case .rest: return "wind"
        case .dance: return "music.note"
        }
    }
}
