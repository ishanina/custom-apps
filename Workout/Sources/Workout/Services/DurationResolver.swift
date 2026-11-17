import Foundation
import AVFoundation

/// Looks up the full length of a video step so untrimmed videos count toward
/// routine time. Results are stored on the step (`mediaDuration`), so each
/// video is only looked up once.
enum DurationResolver {
    static func duration(for step: Step) async -> TimeInterval? {
        if step.videoSource == .local, let path = step.localPath {
            return await localDuration(path: path)
        }
        if let id = step.youtubeID {
            return await youtubeDuration(id: id)
        }
        return nil
    }

    private static func localDuration(path: String) async -> TimeInterval? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        guard let time = try? await asset.load(.duration) else { return nil }
        let seconds = time.seconds
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }

    /// Reads the length from the public watch page (no API key needed).
    private static func youtubeDuration(id: String) async -> TimeInterval? {
        guard let url = URL(string: "https://www.youtube.com/watch?v=\(id)") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8) else { return nil }
        if let s = firstMatch(#""lengthSeconds":"(\d+)""#, in: html), let v = Double(s), v > 0 { return v }
        if let s = firstMatch(#""approxDurationMs":"(\d+)""#, in: html), let v = Double(s), v > 0 { return v / 1000 }
        return nil
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}
