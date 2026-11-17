# Workout

A macOS app for building and playing workout routines. A routine is a sequence of steps:

- **Video**: a YouTube link or a local video file, optionally trimmed to a start and end time
- **Exercise**: a named, timed countdown
- **Rest**: a timed recovery
- **Dance**: shuffles N songs from a Spotify playlist in the Spotify app

## Build & run

```sh
scripts/build.sh --open            # builds build/Workout.app and launches it
scripts/build.sh --install --open  # also copies it to /Applications
```

Requires macOS 14+ and the Xcode command-line tools. You can also open `Package.swift` in Xcode.

## Data

Routines are stored in `~/Library/Application Support/Workout/routines.json`. On first launch, routines from
the older WorkoutOrganizer app are copied in, and the old app's data is left untouched. The JSON format
matches the older app, so you can import and export routines between the two.

## Player shortcuts

Space: pause/resume · ←/→: previous/next step · Esc: end workout · ⌘↩: start the selected routine.
Click a segment in the progress bar to jump to that step.

## Development

- `swift scripts/make_icon.swift` regenerates `Resources/AppIcon.icns`.
- `WORKOUT_DATA_DIR` points the app at a different data folder. In debug builds, `WORKOUT_SCENE` /
  `WORKOUT_SNAPSHOT_DIR` render scenes to PNGs (see `App/DebugScenes.swift`).
