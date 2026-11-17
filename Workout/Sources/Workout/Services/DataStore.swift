import Foundation
import AppKit
import UniformTypeIdentifiers

/// Owns all routines plus the app's navigation state, and persists routines
/// as JSON in ~/Library/Application Support/Workout.
final class DataStore: ObservableObject {
    @Published var routines: [Routine] = [] {
        didSet {
            if !isLoading { scheduleSave() }
            resolveMissingDurations()
        }
    }
    @Published var selectedRoutineID: UUID?
    @Published var playingRoutineID: UUID?

    private var isLoading = false
    private var durationLookups = Set<String>() // media already looked up this session
    private var pendingSave: DispatchWorkItem?
    private let fm = FileManager.default

    static let directory: URL = {
        if let override = ProcessInfo.processInfo.environment["WORKOUT_DATA_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("Workout", isDirectory: true)
    }()

    private var fileURL: URL { Self.directory.appendingPathComponent("routines.json") }

    /// Data from the original WorkoutOrganizer app, copied in on first launch.
    private var legacyFileURL: URL {
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("WorkoutOrganizer/routines.json")
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() {
        try? fm.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        importLegacyDataIfNeeded()
        load()
        selectedRoutineID = routines.first?.id
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.saveNow() }
    }

    // MARK: - Persistence

    private func importLegacyDataIfNeeded() {
        guard ProcessInfo.processInfo.environment["WORKOUT_DATA_DIR"] == nil,
              !fm.fileExists(atPath: fileURL.path),
              fm.fileExists(atPath: legacyFileURL.path) else { return }
        try? fm.copyItem(at: legacyFileURL, to: fileURL)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            routines = try Self.decoder.decode([Routine].self, from: data)
        } catch {
            NSLog("Workout: failed to load routines: \(error)")
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        do {
            let data = try Self.encoder.encode(routines)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Workout: failed to save routines: \(error)")
        }
    }

    // MARK: - Video lengths

    /// Fills in `mediaDuration` for untrimmed videos that don't have it yet.
    private func resolveMissingDurations() {
        for routine in routines {
            for step in routine.steps where step.musicURI != nil && step.musicName == nil {
                guard let uri = step.musicURI, !durationLookups.contains(uri) else { continue }
                durationLookups.insert(uri)
                Task { @MainActor [weak self] in
                    guard let name = await SpotifyPlaylistInfo.name(uri: uri) else { return }
                    self?.applyMusicName(name, uri: uri)
                }
            }
            for step in routine.steps where step.needsMediaDuration {
                let key = step.volumeKey
                guard !key.isEmpty, !durationLookups.contains(key) else { continue }
                durationLookups.insert(key)
                Task { @MainActor [weak self] in
                    guard let seconds = await DurationResolver.duration(for: step) else { return }
                    self?.applyMediaDuration(seconds, key: key)
                }
            }
        }
    }

    private func applyMusicName(_ name: String, uri: String) {
        var updated = routines
        var changed = false
        for r in updated.indices {
            for s in updated[r].steps.indices where updated[r].steps[s].musicURI == uri && updated[r].steps[s].musicName == nil {
                updated[r].steps[s].musicName = name
                changed = true
            }
        }
        if changed { routines = updated }
    }

    private func applyMediaDuration(_ seconds: TimeInterval, key: String) {
        var updated = routines
        var changed = false
        for r in updated.indices {
            for s in updated[r].steps.indices {
                let step = updated[r].steps[s]
                if step.type == .video, step.volumeKey == key, step.mediaDuration == nil {
                    updated[r].steps[s].mediaDuration = seconds
                    changed = true
                }
            }
        }
        if changed { routines = updated }
    }

    // MARK: - Routines

    func routine(id: UUID) -> Routine? { routines.first { $0.id == id } }

    @discardableResult
    func newRoutine() -> Routine {
        let routine = Routine(name: uniqueName("New Routine"))
        routines.append(routine)
        selectedRoutineID = routine.id
        return routine
    }

    func duplicate(_ routine: Routine) {
        var copy = routine
        copy.id = UUID()
        copy.name = uniqueName("\(routine.name) Copy")
        copy.createdAt = Date()
        copy.updatedAt = Date()
        copy.lastCompletedAt = nil
        for i in copy.steps.indices { copy.steps[i].id = UUID() }
        if let idx = routines.firstIndex(where: { $0.id == routine.id }) {
            routines.insert(copy, at: idx + 1)
        } else {
            routines.append(copy)
        }
        selectedRoutineID = copy.id
    }

    func delete(id: UUID) {
        guard let idx = routines.firstIndex(where: { $0.id == id }) else { return }
        routines.remove(at: idx)
        if selectedRoutineID == id {
            selectedRoutineID = routines.isEmpty ? nil : routines[min(idx, routines.count - 1)].id
        }
    }

    func markCompleted(id: UUID) {
        guard let idx = routines.firstIndex(where: { $0.id == id }) else { return }
        routines[idx].lastCompletedAt = Date()
    }

    func play(_ id: UUID) {
        guard let r = routine(id: id), !r.steps.isEmpty else { return }
        saveNow()
        playingRoutineID = id
    }

    private func uniqueName(_ base: String) -> String {
        let names = Set(routines.map(\.name))
        if !names.contains(base) { return base }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    // MARK: - Import / Export

    func export(_ routine: Routine) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(routine.name).json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try Self.encoder.encode(routine).write(to: url, options: .atomic)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    func importRoutines() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        panel.message = "Choose routine files exported from Workout or WorkoutOrganizer"
        panel.begin { [weak self] response in
            guard response == .OK, let self else { return }
            var imported: [Routine] = []
            for url in panel.urls {
                guard let data = try? Data(contentsOf: url) else { continue }
                if let one = try? Self.decoder.decode(Routine.self, from: data) {
                    imported.append(one)
                } else if let many = try? Self.decoder.decode([Routine].self, from: data) {
                    imported.append(contentsOf: many)
                } else {
                    let alert = NSAlert()
                    alert.messageText = "Couldn't import “\(url.lastPathComponent)”"
                    alert.informativeText = "The file isn't a Workout routine."
                    alert.runModal()
                }
            }
            for var routine in imported {
                routine.id = UUID() // fresh IDs avoid collisions with existing routines
                for i in routine.steps.indices { routine.steps[i].id = UUID() }
                self.routines.append(routine)
                self.selectedRoutineID = routine.id
            }
        }
    }
}
