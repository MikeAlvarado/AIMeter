#!/bin/zsh
# Records the website's notch island videos (see Scripts/IslandVideo/CLAUDE.md):
#
#   Scripts/island-video.sh <a DEBUG AIMeter.app> [work dir]
#
# Run on a Mac with a notch, its built-in display on: the island records at
# the display's own scale, and a screen without a notch draws it instead.
# For each language and scene it relaunches the app as the recorder's
# (`-AIMeterIslandDirector YES`, the short island whatever the user chose),
# records the scene, and encodes site/src/assets/videos/island-<scene>-<lang>.mp4
# with its poster (.webp). The user's own app comes back at the end.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:?a DEBUG AIMeter.app}"
WORK="${2:-$(mktemp -d)}"
OUT="$ROOT/site/src/assets/videos"
mkdir -p "$WORK" "$OUT"
swift build -c release --package-path "$ROOT/Scripts/IslandVideo" --scratch-path "$WORK/build"
RECORD="$WORK/build/release/IslandVideo"
# Whatever happens, the user's own app (out of the demo) comes back.
trap 'open -n "$APP"' EXIT
for lang in en es; do
  open -n "$APP" --args -AIMeterIslandDirector YES -pref.claudeSessionsShowsName NO -AppleLanguages "($lang)"
  sleep 6
  for scene in limits sessions permission; do
    "$RECORD" "$scene" "$WORK/$scene-$lang.mov" "$lang"
    ffmpeg -loglevel error -y -i "$WORK/$scene-$lang.mov" -c:v libx264 -preset slow -crf 24 -pix_fmt yuv420p \
      -movflags +faststart -an "$OUT/island-$scene-$lang.mp4"
    ffmpeg -loglevel error -y -ss 0.4 -i "$WORK/$scene-$lang.mov" -frames:v 1 "$WORK/$scene-$lang.png"
    (cd "$ROOT/site" && node -e "require('sharp')(process.argv[1]).webp({ quality: 82 }).toFile(process.argv[2])" \
      "$WORK/$scene-$lang.png" "$OUT/island-$scene-$lang.webp")
  done
done
ls -la "$OUT"
