#!/bin/zsh
# Builds the Mac release: a Developer ID-signed, notarized, stapled
# AIMeter.app in a zip, ready for a GitHub Release. See README → Releasing.
#
#   Scripts/release-mac.sh <version> [work-dir]
#
# Needs, once per Mac: a "Developer ID Application" certificate in the
# login keychain (Xcode → Settings → Accounts → Manage Certificates), and
# a notarytool keychain profile named "AIMeter":
#   xcrun notarytool store-credentials AIMeter --apple-id <id> --team-id <team>
# (the password is an app-specific password from appleid.apple.com; it is
# stored in the keychain, never in this repo). Run it from a Terminal, not
# a non-interactive shell: codesign and notarytool prompt the keychain.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?version, e.g. 2.0.0}"
WORK="${2:-$(mktemp -d /tmp/aimeter-release-XXXXXX)}"
TEAM="$(sed -n 's/^DEVELOPMENT_TEAM *= *//p' "$ROOT/Config.local.xcconfig" | tail -1)"
[[ -n "$TEAM" ]] || { echo "DEVELOPMENT_TEAM missing from Config.local.xcconfig"; exit 1 }
ARCHIVE="$WORK/AIMeter-$VERSION.xcarchive"
EXPORT="$WORK/export"
ZIP="$WORK/AIMeter-$VERSION-macOS.zip"

echo "== archive"
xcodebuild archive -project "$ROOT/AIMeter.xcodeproj" -scheme AIMeter -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" -allowProvisioningUpdates \
  2>&1 | grep -E "warning:|error:|ARCHIVE" || true
[[ -d "$ARCHIVE" ]] || { echo "archive failed"; exit 1 }

echo "== export (Developer ID)"
cat > "$WORK/export.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$TEAM</string>
</dict></plist>
PLIST
rm -rf "$EXPORT"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$WORK/export.plist" \
  -exportPath "$EXPORT" -allowProvisioningUpdates 2>&1 | grep -E "error:|EXPORT" || true
APP="$EXPORT/AIMeter.app"
[[ -d "$APP" ]] || { echo "export failed"; exit 1 }
codesign --verify --deep --strict "$APP"
codesign -dv "$APP" 2>&1 | grep -E "Authority=Developer ID" || { echo "not Developer ID-signed"; exit 1 }

echo "== notarize"
ditto -c -k --keepParent "$APP" "$WORK/notarize.zip"
xcrun notarytool submit "$WORK/notarize.zip" --keychain-profile AIMeter --wait
xcrun stapler staple "$APP"
spctl --assess --type execute -v "$APP"

echo "== zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP"
echo "ready: $ZIP"
echo "then: gh release create $VERSION \"$ZIP\" --title \"AIMeter $VERSION\" --notes-file <notes.md>"
