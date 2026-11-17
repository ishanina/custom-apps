import Foundation

struct YouTubeURLParser {
    static func extractVideoID(from urlString: String) -> String? {
        // Handle youtu.be/VIDEO_ID
        if let url = URL(string: urlString), url.host?.contains("youtu.be") == true {
            let id = url.pathComponents.last ?? ""
            return id.isEmpty ? nil : id
        }

        // Handle youtube.com/watch?v=VIDEO_ID
        if let url = URL(string: urlString),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let vParam = components.queryItems?.first(where: { $0.name == "v" })?.value,
           !vParam.isEmpty {
            return vParam
        }

        // Handle youtube.com/embed/VIDEO_ID
        if let url = URL(string: urlString),
           url.host?.contains("youtube") == true,
           url.pathComponents.count >= 3,
           url.pathComponents[1] == "embed" {
            return url.pathComponents[2]
        }

        // Fallback regex for edge cases
        let pattern = #"(?:v=|\/embed\/|youtu\.be\/)([a-zA-Z0-9_-]{11})"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)),
           let range = Range(match.range(at: 1), in: urlString) {
            return String(urlString[range])
        }

        return nil
    }
}
