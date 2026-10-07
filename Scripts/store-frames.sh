#!/bin/zsh
# Renders the App Store assets (iPhone/iPad screenshot frames, the product
# page header and the search-results card) from the app's own views and
# the raw simulator captures. See Scripts/StoreFrames/CLAUDE.md.
#
#   Scripts/store-frames.sh <work-dir> [frames|marketing|shots]
#
# <work-dir>/raw/ must hold the simulator captures the specs name
# (dashboard.png, detail-top.png, ...) and appicon.png. Output lands in
# <work-dir>/frames, <work-dir>/marketing or <work-dir>/widget-shots.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${1:?work dir}"; MODE="${2:-frames}"
BUILD="$WORK/store-frames-build"
rm -rf "$BUILD"; mkdir -p "$BUILD/Sources"
cp "$ROOT/Scripts/StoreFrames/Package.swift" "$BUILD/"
sed -i '' 's#path: "../../Packages/UsageKit"#path: "'"$ROOT"'/Packages/UsageKit"#' "$BUILD/Package.swift"
cp "$ROOT/Scripts/StoreFrames/Sources/"*.swift "$BUILD/Sources/"
# The views the frames draw: copied, never symlinked (SwiftPM misses edits
# behind a symlink), and the widget views minus their timeline plumbing.
for f in Theme ThemeComponents ProviderIdentityView ProviderMark PeakBadge ClaudePeakStatus \
         UsageFormatting WindowDisplay PreferencesStore AppConfig ProviderCatalog MenuBarLabelModel; do
  cp "$ROOT/Shared/$f.swift" "$BUILD/Sources/"
done
cp "$ROOT/AIMeterWidgets/MediumUsageView.swift" "$ROOT/AIMeterWidgets/SingleUsageWidgetView.swift" \
   "$ROOT/AIMeterWidgets/AllAccountsWidgetView.swift" "$BUILD/Sources/"
python3 - "$ROOT/AIMeterWidgets/UsageWidgetViews.swift" "$BUILD/Sources/UsageWidgetViews.swift" <<'PY'
import sys
s = open(sys.argv[1]).read()
a = s.index('struct UsageWidgetView: View'); b = s.index('// MARK: - System families')
open(sys.argv[2], 'w').write(s[:a] + s[b:])
PY
# The marks live in the app's asset catalog; the renderer loads them from
# its own bundle, so point the one Image(...) call there.
sed -i '' 's/Image(Self.assetName(for: mark))/Image(Self.assetName(for: mark), bundle: .module)/' "$BUILD/Sources/ProviderMark.swift"
cp -R "$ROOT/Shared/Media.xcassets" "$BUILD/Sources/Media.xcassets"
(cd "$BUILD" && swift build -c release 2>&1 | grep -E "error:|Build complete")
case "$MODE" in
  frames)    "$BUILD/.build/release/StoreFrames" "$WORK" frames ;;
  marketing) "$BUILD/.build/release/StoreFrames" "$WORK" marketing ;;
  shots)     mkdir -p "$WORK/widget-shots"; "$BUILD/.build/release/StoreFrames" "$WORK/widget-shots" ;;
esac
