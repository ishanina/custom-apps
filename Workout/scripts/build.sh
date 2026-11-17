#!/bin/bash
# Builds Workout.app into ./build. Usage: scripts/build.sh [--install] [--open]
#   --install  copy the app to /Applications
#   --open     launch it when done
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Workout.app"

cd "$ROOT"
swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Workout" "$APP/Contents/MacOS/Workout"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --sign - "$APP" >/dev/null

echo "Built $APP"

for arg in "$@"; do
  case "$arg" in
    --install)
      rm -rf /Applications/Workout.app
      cp -R "$APP" /Applications/Workout.app
      APP=/Applications/Workout.app
      echo "Installed to $APP"
      ;;
  esac
done
for arg in "$@"; do
  [ "$arg" = "--open" ] && open "$APP"
done
exit 0
