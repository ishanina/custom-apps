import Foundation

/// Looks up a playlist's name through Spotify's public oEmbed endpoint (no login needed).
enum SpotifyPlaylistInfo {
    static func name(uri: String) async -> String? {
        if SpotifyURLParser.isLikedSongs(uri) { return "Liked Songs" }
        guard let id = uri.split(separator: ":").last,
              var components = URLComponents(string: "https://open.spotify.com/oembed") else { return nil }
        components.queryItems = [URLQueryItem(name: "url", value: "https://open.spotify.com/playlist/\(id)")]
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = json["title"] as? String, !title.isEmpty else { return nil }
        return title
    }
}
