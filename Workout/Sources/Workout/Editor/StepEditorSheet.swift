import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct StepEditorSheet: View {
    let original: Step?
    var onSave: (Step) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var type: StepType
    // Video
    @State private var videoSource: VideoSource
    @State private var youtubeURL: String
    @State private var localPath: String
    @State private var startText: String
    @State private var endText: String
    @State private var label: String
    // Exercise
    @State private var exerciseName: String
    @State private var exerciseDuration: String
    // Rest
    @State private var restDuration: String
    // Dance
    @State private var playlistURL: String
    @State private var songCount: Int
    // Exercise / rest music
    @State private var hasMusic: Bool
    @State private var stepMusic: String

    init(original: Step?, initialType: StepType, onSave: @escaping (Step) -> Void) {
        self.original = original
        self.onSave = onSave
        let s = original
        _type = State(initialValue: s?.type ?? initialType)
        _videoSource = State(initialValue: s?.videoSource ?? .youtube)
        _youtubeURL = State(initialValue: s?.type == .video && s?.videoSource != .local ? (s?.url ?? "") : "")
        _localPath = State(initialValue: s?.localPath ?? "")
        _startText = State(initialValue: Fmt.fieldText(s?.startTime ?? 0))
        _endText = State(initialValue: Fmt.fieldText(s?.endTime ?? 0))
        _label = State(initialValue: s?.label ?? "")
        _exerciseName = State(initialValue: s?.exerciseName ?? "")
        _exerciseDuration = State(initialValue: Fmt.clock(s?.type == .timed ? s!.duration : 30))
        _restDuration = State(initialValue: Fmt.clock(s?.type == .rest ? s!.duration : 15))
        _playlistURL = State(initialValue: s?.type == .dance ? (s?.url ?? "") : "")
        _songCount = State(initialValue: s?.songCount ?? 3)
        _hasMusic = State(initialValue: s?.music != nil)
        _stepMusic = State(initialValue: s?.music ?? SpotifyURLParser.likedSongsURI)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(original == nil ? "New Step" : "Edit Step")
                    .font(.rounded(20, .bold))
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 16)

            HStack(spacing: 10) {
                ForEach(StepType.allCases) { t in
                    TypeTile(type: t, selected: type == t) {
                        withAnimation(.easeOut(duration: 0.15)) { type = t }
                    }
                }
            }
            .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 18) {
                switch type {
                case .video: videoForm
                case .timed: exerciseForm
                case .rest: restForm
                case .dance: danceForm
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.raised))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline))
            .padding(.horizontal, 24)
            .padding(.top, 18)

            HStack(spacing: 10) {
                if let problem = validationMessage {
                    Label(problem, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(original == nil ? "Add Step" : "Save") { save() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(validationMessage != nil)
            }
            .padding(24)
        }
        .frame(width: 580)
        .background(Theme.canvas)
    }

    // MARK: - Forms

    @ViewBuilder
    private var videoForm: some View {
        Picker("Source", selection: $videoSource) {
            Label("YouTube", systemImage: "globe").tag(VideoSource.youtube)
            Label("Video File", systemImage: "film").tag(VideoSource.local)
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        if videoSource == .youtube {
            FormRow(title: "YouTube link") {
                InputField(placeholder: "https://youtube.com/watch?v=…", text: $youtubeURL,
                           invalid: !youtubeURL.isEmpty && YouTubeURLParser.extractVideoID(from: youtubeURL) == nil)
            }
        } else {
            FormRow(title: "File") {
                HStack(spacing: 10) {
                    Image(systemName: "film").foregroundStyle(.tertiary)
                    Text(localPath.isEmpty ? "No file chosen" : URL(fileURLWithPath: localPath).lastPathComponent)
                        .foregroundStyle(localPath.isEmpty ? .tertiary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(localPath)
                    Spacer()
                    Button("Choose…") { chooseFile() }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .padding(.leading, 10)
                .padding(.trailing, 4)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.06)))
            }
        }

        HStack(alignment: .top, spacing: 18) {
            VideoThumbnail(step: previewStep)
                .frame(width: 192, height: 108)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline))

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    FormRow(title: "Start") { TimeField(placeholder: "0:00", text: $startText) }
                    FormRow(title: "End") { TimeField(placeholder: "End", text: $endText) }
                }
                Text("Leave End empty to play to the end of the video.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        FormRow(title: "Name", hint: nil) {
            InputField(placeholder: "Optional — e.g. “Warm-up”", text: $label)
        }
    }

    @ViewBuilder
    private var exerciseForm: some View {
        FormRow(title: "Exercise") {
            InputField(placeholder: "e.g. Push-ups", text: $exerciseName, font: .system(size: 15, weight: .medium))
        }
        FormRow(title: "Duration") {
            durationPicker(text: $exerciseDuration, presets: [20, 30, 45, 60, 90, 120])
        }
        musicSection
    }

    @ViewBuilder
    private var restForm: some View {
        FormRow(title: "Duration") {
            durationPicker(text: $restDuration, presets: [10, 15, 20, 30, 60, 90])
        }
        musicSection
    }

    @ViewBuilder
    private var musicSection: some View {
        Divider().overlay(Theme.hairline)
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Play Spotify music").font(.system(size: 13, weight: .semibold))
                Text(type == .rest
                     ? "Without its own music, a rest keeps the previous exercise's music going."
                     : "Steps in a row with the same music keep playing without restarting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("Play Spotify music", isOn: $hasMusic.animation(.easeOut(duration: 0.15)))
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(Theme.accent)
        }
        if hasMusic {
            SpotifySourcePicker(source: $stepMusic)
        }
    }

    @ViewBuilder
    private var danceForm: some View {
        FormRow(title: "Music") {
            SpotifySourcePicker(source: $playlistURL)
        }
        FormRow(title: "Songs") {
            HStack(spacing: 12) {
                Button { songCount = max(1, songCount - 1) } label: { Image(systemName: "minus") }
                    .buttonStyle(IconButtonStyle(size: 30))
                    .disabled(songCount <= 1)
                Text("\(songCount)")
                    .font(.rounded(22, .bold))
                    .monospacedDigit()
                    .frame(minWidth: 34)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: songCount)
                Button { songCount = min(50, songCount + 1) } label: { Image(systemName: "plus") }
                    .buttonStyle(IconButtonStyle(size: 30))
                    .disabled(songCount >= 50)
                Text("random song\(songCount == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
            }
        }
        FormRow(title: "Name") {
            InputField(placeholder: "Optional — e.g. “Dance break”", text: $label)
        }
    }

    private func durationPicker(text: Binding<String>, presets: [Int]) -> some View {
        HStack(spacing: 8) {
            TimeField(placeholder: "0:30", text: text, width: 84)
            ForEach(presets, id: \.self) { seconds in
                Chip(title: Fmt.short(seconds),
                     selected: Fmt.parseTime(text.wrappedValue) == TimeInterval(seconds)) {
                    text.wrappedValue = Fmt.clock(TimeInterval(seconds))
                }
            }
        }
    }

    // MARK: - Validation & saving

    private var previewStep: Step {
        Step(type: .video, videoSource: videoSource,
             url: videoSource == .youtube ? youtubeURL : nil,
             localPath: videoSource == .local ? localPath : nil,
             startTime: Fmt.parseTime(startText) ?? 0)
    }

    private var validationMessage: String? {
        switch type {
        case .video:
            if videoSource == .youtube {
                if youtubeURL.isEmpty { return "Paste a YouTube link" }
                if YouTubeURLParser.extractVideoID(from: youtubeURL) == nil { return "That isn't a YouTube link" }
            } else if localPath.isEmpty {
                return "Choose a video file"
            }
            guard let start = Fmt.parseTime(startText), let end = Fmt.parseTime(endText) else {
                return "Times look like 1:30 or 90"
            }
            if end > 0 && end <= start { return "End must be after start" }
        case .timed:
            if exerciseName.trimmingCharacters(in: .whitespaces).isEmpty { return "Name the exercise" }
            if let problem = musicProblem { return problem }
            guard let d = Fmt.parseTime(exerciseDuration), d > 0 else { return "Set a duration" }
        case .rest:
            guard let d = Fmt.parseTime(restDuration), d > 0 else { return "Set a duration" }
            if let problem = musicProblem { return problem }
        case .dance:
            if SpotifyURLParser.playlistURI(from: playlistURL) == nil {
                return playlistURL.isEmpty ? "Choose Liked Songs or paste a playlist link" : "That isn't a Spotify playlist link"
            }
        }
        return nil
    }

    private var musicProblem: String? {
        guard hasMusic, SpotifyURLParser.playlistURI(from: stepMusic) == nil else { return nil }
        return stepMusic.isEmpty ? "Choose Liked Songs or paste a playlist link" : "That isn't a Spotify playlist link"
    }

    private func applyMusic(to step: inout Step) {
        guard hasMusic else { return }
        step.music = stepMusic
        // Keep the looked-up name if the music didn't change.
        if let original, SpotifyURLParser.playlistURI(from: original.music ?? "") == SpotifyURLParser.playlistURI(from: stepMusic) {
            step.musicName = original.musicName
        }
    }

    private func save() {
        guard validationMessage == nil else { return }
        var step = Step(id: original?.id ?? UUID(), type: type)
        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)
        switch type {
        case .video:
            step.videoSource = videoSource
            if videoSource == .youtube {
                step.url = youtubeURL.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                step.localPath = localPath
            }
            step.startTime = Fmt.parseTime(startText) ?? 0
            step.endTime = Fmt.parseTime(endText) ?? 0
            step.label = trimmedLabel.isEmpty ? nil : trimmedLabel
            // Keep the looked-up video length if the video itself didn't change.
            if let original, original.type == .video, original.volumeKey == step.volumeKey {
                step.mediaDuration = original.mediaDuration
            }
        case .timed:
            step.exerciseName = exerciseName.trimmingCharacters(in: .whitespaces)
            step.duration = Fmt.parseTime(exerciseDuration) ?? 30
            applyMusic(to: &step)
        case .rest:
            step.duration = Fmt.parseTime(restDuration) ?? 15
            applyMusic(to: &step)
        case .dance:
            step.url = playlistURL.trimmingCharacters(in: .whitespacesAndNewlines)
            step.songCount = songCount
            step.label = trimmedLabel.isEmpty ? nil : trimmedLabel
        }
        onSave(step)
        dismiss()
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        if !localPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: localPath).deletingLastPathComponent()
        }
        if panel.runModal() == .OK, let url = panel.url {
            localPath = url.path
        }
    }
}
