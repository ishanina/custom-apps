#if DEBUG
import AppKit

/// Debug-build-only hook for scripted screenshots:
///   WORKOUT_SCENE=editor:1 | sheet:1:timed | player:3:1[:paused] | complete:0 | welcome
///   WORKOUT_SNAPSHOT_DIR=/path  (writes <scene>-<n>.png per window, then quits)
enum DebugScenes {
    private static let env = ProcessInfo.processInfo.environment
    static var parts: [String] { env["WORKOUT_SCENE"]?.split(separator: ":").map(String.init) ?? [] }
    static var kind: String? { parts.first }
    static func int(_ i: Int) -> Int? { parts.indices.contains(i) ? Int(parts[i]) : nil }
    static func string(_ i: Int) -> String? { parts.indices.contains(i) ? parts[i] : nil }

    static func apply(to store: DataStore) {
        guard let kind else { return }
        let routine = int(1).flatMap { store.routines.indices.contains($0) ? store.routines[$0] : nil }
        switch kind {
        case "welcome": store.selectedRoutineID = nil
        case "editor", "sheet": store.selectedRoutineID = routine?.id
        case "player", "complete":
            store.selectedRoutineID = routine?.id
            if let routine { store.playingRoutineID = routine.id }
        default: break
        }
        scheduleSnapshot()
    }

    static func apply(to vm: PlayerViewModel) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if kind == "complete" {
                vm.jump(to: vm.steps.count - 1)
                vm.skip()
            } else if let step = int(2) {
                vm.jump(to: step)
                if string(3) == "paused" { vm.togglePause() }
                if string(3) == "nextup" { vm.debugShowNextUp() }
            }
        }
    }

    private static func scheduleSnapshot() {
        guard let dir = env["WORKOUT_SNAPSHOT_DIR"] else { return }
        let delay = Double(env["WORKOUT_SNAPSHOT_DELAY"] ?? "") ?? 3
        let name = (env["WORKOUT_SCENE"] ?? "scene").replacingOccurrences(of: ":", with: "_")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            for (i, window) in NSApp.windows.enumerated() where window.isVisible {
                guard let view = window.contentView?.superview ?? window.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name)-\(i).png")
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
            }
            NSApp.terminate(nil)
        }
    }
}
#endif
