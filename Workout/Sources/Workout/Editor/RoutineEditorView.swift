import SwiftUI
import AppKit
import UniformTypeIdentifiers

private let stepsPasteboardType = NSPasteboard.PasteboardType("com.workout.steps")
private let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "webm", "mpg", "mpeg"]

/// Identifies what the step sheet is editing: a new step of some type, or an existing one.
struct StepSheetRequest: Identifiable {
    let id = UUID()
    var step: Step?
    var type: StepType
}

struct RoutineEditorView: View {
    @Binding var routine: Routine
    @EnvironmentObject var store: DataStore
    @State private var selection: Set<UUID> = []
    @State private var sheet: StepSheetRequest?
    @State private var dropTargeted = false
    @State private var confirmDelete = false
    @State private var pasteboardChange = NSPasteboard.general.changeCount

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.hairline)
            if routine.steps.isEmpty {
                emptyState
            } else {
                stepList
            }
        }
        .background(Theme.canvas)
        .overlay { if dropTargeted { dropOverlay } }
        .dropDestination(for: URL.self) { urls, _ in
            addVideos(urls)
        } isTargeted: { dropTargeted = $0 }
        .sheet(item: $sheet) { request in
            StepEditorSheet(original: request.step, initialType: request.type) { saved in
                save(saved)
            }
        }
        .confirmationDialog("Delete “\(routine.name)”?", isPresented: $confirmDelete) {
            Button("Delete Routine", role: .destructive) { store.delete(id: routine.id) }
        } message: {
            Text("This can't be undone. Export it first if you might want it back.")
        }
        .onDeleteCommand { deleteSelected() }
        .onCopyCommand {
            copy(selectedSteps)
            return []
        }
        .onCutCommand {
            copy(selectedSteps)
            deleteSelected()
            return []
        }
        .onPasteCommand(of: [.json]) { _ in paste() }
        #if DEBUG
        .onAppear {
            if DebugScenes.kind == "sheet", store.routines.firstIndex(where: { $0.id == routine.id }) == DebugScenes.int(1) {
                let type = StepType(rawValue: DebugScenes.string(2) ?? "") ?? .timed
                let existing = DebugScenes.int(3).flatMap { routine.steps.indices.contains($0) ? routine.steps[$0] : nil }
                sheet = StepSheetRequest(step: existing, type: type)
            }
        }
        #endif
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            // Refresh the Paste button when steps are copied in another routine/window.
            if NSPasteboard.general.changeCount != pasteboardChange {
                pasteboardChange = NSPasteboard.general.changeCount
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Routine name", text: $routine.name)
                        .textFieldStyle(.plain)
                        .font(.rounded(30, .bold))
                    HStack(spacing: 18) {
                        StatLabel(icon: "clock", text: routine.durationSummary)
                        StatLabel(icon: "list.bullet", text: "\(routine.steps.count) step\(routine.steps.count == 1 ? "" : "s")")
                        if let done = routine.lastCompletedAt {
                            StatLabel(icon: "checkmark.circle", text: "Done \(done.formatted(.relative(presentation: .named)))")
                        }
                    }
                }
                Spacer(minLength: 20)
                AudioSettingButton(routine: $routine)
                Menu {
                    Button("Duplicate Routine") { store.duplicate(routine) }
                    Button("Export…") { store.export(routine) }
                    Divider()
                    Button("Delete Routine…", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white.opacity(0.07)))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()

                Button { store.play(routine.id) } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle(large: true))
                .disabled(routine.steps.isEmpty)
                .help("Start workout (⌘↩)")
            }

            if !routine.steps.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    CompositionBar(steps: routine.steps, height: 8, spacing: 2)
                    legend
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 20)
    }

    private var legend: some View {
        HStack(spacing: 18) {
            ForEach(StepType.allCases) { type in
                let steps = routine.steps.filter { $0.type == type }
                if !steps.isEmpty {
                    HStack(spacing: 6) {
                        Circle().fill(type.tint).frame(width: 7, height: 7)
                        Text(type.title).foregroundStyle(.secondary)
                        Text(legendValue(steps)).foregroundStyle(.tertiary).monospacedDigit()
                    }
                }
            }
        }
        .font(.system(size: 11, weight: .medium))
    }

    private func legendValue(_ steps: [Step]) -> String {
        Step.summary(of: steps)
    }

    // MARK: - Step list

    private var stepList: some View {
        List(selection: $selection) {
            ForEach(Array(routine.steps.enumerated()), id: \.element.id) { index, step in
                StepRow(index: index + 1, step: step) { sheet = StepSheetRequest(step: step, type: step.type) }
                    .tag(step.id)
                    .listRowSeparator(.hidden)
            }
            .onMove { routine.steps.move(fromOffsets: $0, toOffset: $1) }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: UUID.self) { ids in
            contextMenu(for: ids)
        } primaryAction: { ids in
            if ids.count == 1, let step = routine.steps.first(where: { ids.contains($0.id) }) {
                sheet = StepSheetRequest(step: step, type: step.type)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
    }

    @ViewBuilder
    private func contextMenu(for ids: Set<UUID>) -> some View {
        let steps = routine.steps.filter { ids.contains($0.id) }
        if steps.count == 1, let step = steps.first {
            Button("Edit…") { sheet = StepSheetRequest(step: step, type: step.type) }
            Divider()
        }
        if !steps.isEmpty {
            Button("Copy") { copy(steps) }
            Button("Duplicate") { duplicate(steps) }
            if hasCopiedSteps { Button("Paste After") { paste(after: steps.last?.id) } }
            Divider()
            Button("Delete", role: .destructive) { delete(ids) }
        } else {
            addMenuItems
            if hasCopiedSteps { Button("Paste") { paste() } }
        }
    }

    @ViewBuilder
    private var addMenuItems: some View {
        ForEach(StepType.allCases) { type in
            Button { sheet = StepSheetRequest(type: type) } label: {
                Label("Add \(type.title)", systemImage: type.symbol)
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 6) {
            if selection.isEmpty {
                Text("Drag to reorder · double-click to edit · drop video files to add")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            } else {
                Text("\(selection.count) selected")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.trailing, 4)
                if selection.count == 1, let step = selectedSteps.first {
                    barButton("Edit", "pencil") { sheet = StepSheetRequest(step: step, type: step.type) }
                }
                barButton("Duplicate", "plus.square.on.square") { duplicate(selectedSteps) }
                barButton("Copy", "doc.on.doc") { copy(selectedSteps) }
                barButton("Delete", "trash") { deleteSelected() }
            }
            Spacer(minLength: 8)
            if hasCopiedSteps {
                barButton("Paste", "doc.on.clipboard") { paste() }
            }
            Menu {
                addMenuItems
            } label: {
                Label("Add Step", systemImage: "plus")
            } primaryAction: {
                sheet = StepSheetRequest(type: routine.steps.last?.type == .timed ? .rest : .timed)
            }
            .menuStyle(.button)
            .buttonStyle(PrimaryButtonStyle())
            .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider().overlay(Theme.hairline) }
    }

    private func barButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: icon) }
            .buttonStyle(SecondaryButtonStyle())
            .labelStyle(.titleAndIcon)
    }

    // MARK: - Empty / drop states

    private var emptyState: some View {
        VStack(spacing: 22) {
            VStack(spacing: 6) {
                Text("Add your first step")
                    .font(.rounded(22, .bold))
                Text("Pick a step type to start building, or drop video files here.")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                ForEach(StepType.allCases) { type in
                    TypeTile(type: type, showsBlurb: true) { sheet = StepSheetRequest(type: type) }
                }
            }
            .frame(maxWidth: 620)
            if hasCopiedSteps {
                Button { paste() } label: { Label("Paste Copied Steps", systemImage: "doc.on.clipboard") }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dropOverlay: some View {
        ZStack {
            Theme.canvas.opacity(0.75)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .padding(16)
            VStack(spacing: 10) {
                Image(systemName: "film.stack").font(.system(size: 40)).foregroundStyle(Theme.accent)
                Text("Drop to add video steps").font(.rounded(18, .semibold))
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Actions

    private var selectedSteps: [Step] { routine.steps.filter { selection.contains($0.id) } }

    private var hasCopiedSteps: Bool {
        _ = pasteboardChange
        return NSPasteboard.general.data(forType: stepsPasteboardType) != nil
    }

    private func save(_ step: Step) {
        if let idx = routine.steps.firstIndex(where: { $0.id == step.id }) {
            routine.steps[idx] = step
        } else if let lastSelected = selectedSteps.last?.id,
                  let idx = routine.steps.firstIndex(where: { $0.id == lastSelected }) {
            routine.steps.insert(step, at: idx + 1)
            selection = [step.id]
        } else {
            routine.steps.append(step)
        }
    }

    private func copy(_ steps: [Step]) {
        guard !steps.isEmpty, let data = try? JSONEncoder().encode(steps) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: stepsPasteboardType)
        pb.setData(data, forType: NSPasteboard.PasteboardType(UTType.json.identifier))
        pasteboardChange = pb.changeCount
    }

    private func paste(after anchor: UUID? = nil) {
        guard let data = NSPasteboard.general.data(forType: stepsPasteboardType),
              var steps = try? JSONDecoder().decode([Step].self, from: data) else { return }
        for i in steps.indices { steps[i].id = UUID() }
        insert(steps, after: anchor ?? selectedSteps.last?.id)
    }

    private func duplicate(_ steps: [Step]) {
        let copies = steps.map { s -> Step in var c = s; c.id = UUID(); return c }
        insert(copies, after: steps.last?.id)
    }

    private func insert(_ steps: [Step], after anchor: UUID?) {
        if let anchor, let idx = routine.steps.firstIndex(where: { $0.id == anchor }) {
            routine.steps.insert(contentsOf: steps, at: idx + 1)
        } else {
            routine.steps.append(contentsOf: steps)
        }
        selection = Set(steps.map(\.id))
    }

    private func delete(_ ids: Set<UUID>) {
        routine.steps.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
    }

    private func deleteSelected() { delete(selection) }

    private func addVideos(_ urls: [URL]) -> Bool {
        let videos = urls.filter { $0.isFileURL && videoExtensions.contains($0.pathExtension.lowercased()) }
        guard !videos.isEmpty else { return false }
        let steps = videos.map { Step(type: .video, videoSource: .local, localPath: $0.path) }
        routine.steps.append(contentsOf: steps)
        selection = Set(steps.map(\.id))
        return true
    }
}

// MARK: - Row

private struct StepRow: View {
    let index: Int
    let step: Step
    var onEdit: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            Text("\(index)")
                .font(.rounded(12, .semibold))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(width: 22, alignment: .trailing)

            leading

            VStack(alignment: .leading, spacing: 3) {
                Text(step.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(step.detailText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if hovering {
                Button(action: onEdit) { Image(systemName: "pencil") }
                    .buttonStyle(IconButtonStyle(size: 28))
                    .help("Edit step")
                    .transition(.opacity)
            }

            Text(step.durationLabel ?? "—")
                .font(.rounded(14, .medium))
                .monospacedDigit()
                .foregroundStyle(step.displayDuration > 0 ? .secondary : .tertiary)
                .frame(minWidth: 48, alignment: .trailing)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    @ViewBuilder
    private var leading: some View {
        if step.type == .video {
            VideoThumbnail(step: step)
                .frame(width: 56, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.video.opacity(0.45), lineWidth: 1)
                )
                .overlay(alignment: .bottomLeading) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Circle().fill(Theme.video))
                        .padding(3)
                }
        } else {
            TypeBadge(type: step.type, size: 36)
                .frame(width: 56)
        }
    }
}

/// Header button + popover for the routine's background audio.
private struct AudioSettingButton: View {
    @Binding var routine: Routine
    @State private var showing = false
    @State private var hovering = false

    private var mode: BackgroundAudio { routine.backgroundAudio }
    private var isSet: Bool {
        mode == .podcast || (mode == .spotify && routine.backgroundPlaylistURI != nil)
    }

    private var title: String {
        switch mode {
        case .none: return "Audio"
        case .podcast: return "Podcast"
        case .spotify:
            guard routine.backgroundPlaylistURI != nil else { return "Spotify" }
            return routine.audioPlaylistName ?? "Spotify"
        }
    }

    var body: some View {
        Button { showing.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: mode == .none ? "speaker.wave.2" : mode.symbol)
                Text(title.count > 24 ? title.prefix(22) + "…" : title).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).opacity(0.6)
            }
            .font(.rounded(13, .semibold))
            .foregroundStyle(isSet ? Theme.accent : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(isSet ? Theme.accent.opacity(0.14) : Color.white.opacity(hovering ? 0.1 : 0.06)))
            .overlay(Capsule().strokeBorder(isSet ? Theme.accent.opacity(0.4) : .clear))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovering = $0 }
        .help("Background audio for this workout")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            AudioSettingPopover(routine: $routine)
        }
        .task(id: routine.audioPlaylist) {
            guard routine.audioPlaylistName == nil, let uri = routine.backgroundPlaylistURI,
                  let name = await SpotifyPlaylistInfo.name(uri: uri) else { return }
            routine.audioPlaylistName = name
        }
    }
}

private struct AudioSettingPopover: View {
    @Binding var routine: Routine
    @State private var link: String

    init(routine: Binding<Routine>) {
        _routine = routine
        _link = State(initialValue: routine.wrappedValue.audioPlaylist ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Background audio")
                .font(.rounded(15, .bold))
            Picker("", selection: Binding(get: { routine.backgroundAudio }, set: { routine.backgroundAudio = $0 })) {
                ForEach(BackgroundAudio.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch routine.backgroundAudio {
            case .none:
                Text("Just the workout — videos and dance steps play their own sound.")
                    .foregroundStyle(.secondary)
            case .podcast:
                Text("Plays whatever is up next in Apple Podcasts, in the background. Use [ and ] in the player to jump back or forward 15 seconds — handy for skipping ads.")
                    .foregroundStyle(.secondary)
            case .spotify:
                SpotifySourcePicker(source: $link)
                if let name = routine.audioPlaylistName, routine.backgroundPlaylistURI != nil,
                   !SpotifyURLParser.isLikedSongs(routine.audioPlaylist ?? "") {
                    Label(name, systemImage: "music.note.list")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                Text("Shuffles in the background. Use ] in the player to skip a song.")
                    .foregroundStyle(.secondary)
            }

            Text("Pauses with the workout and during dance steps.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 13))
        .fixedSize(horizontal: false, vertical: true)
        .padding(18)
        .frame(width: 380)
        .onChange(of: link) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed != (routine.audioPlaylist ?? "") else { return }
            routine.audioPlaylist = trimmed.isEmpty ? nil : trimmed
            routine.audioPlaylistName = nil
        }
    }
}
