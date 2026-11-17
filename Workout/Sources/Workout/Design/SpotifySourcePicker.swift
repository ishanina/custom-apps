import SwiftUI

/// Liked Songs or a playlist link, for dance steps and background audio.
struct SpotifySourcePicker: View {
    /// Stored value: a playlist link, or the Liked Songs URI.
    @Binding var source: String
    @State private var link = ""
    @State private var usesLiked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: Binding(get: { usesLiked }, set: { choose(liked: $0) })) {
                Label("Liked Songs", systemImage: "heart.fill").tag(true)
                Label("Playlist", systemImage: "music.note.list").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if usesLiked {
                HStack(spacing: 10) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(LinearGradient(colors: [Color(red: 0.31, green: 0.2, blue: 0.95), Color(red: 0.55, green: 0.8, blue: 0.85)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Liked Songs").font(.system(size: 13, weight: .semibold))
                        Text("Shuffles the songs you've liked in Spotify").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                FormRow(title: "Spotify playlist", hint: "In Spotify: ••• → Share → Copy link to playlist") {
                    InputField(placeholder: "https://open.spotify.com/playlist/…", text: $link,
                               invalid: !link.isEmpty && SpotifyURLParser.playlistURI(from: link) == nil)
                }
            }
        }
        .onAppear {
            usesLiked = SpotifyURLParser.isLikedSongs(source)
            link = usesLiked ? "" : source
        }
        .onChange(of: link) { _, newValue in
            if !usesLiked { source = newValue.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
    }

    private func choose(liked: Bool) {
        usesLiked = liked
        source = liked ? SpotifyURLParser.likedSongsURI : link.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
