#!/bin/zsh
# Builds the Mac release: a Developer ID-signed, notarized, stapled
# AIMeter.app in a zip, ready for a GitHub Release. See README → Releasing.
#
#   Scripts/release-mac.sh <version> [work-dir]
#
# Everything goes through the Apple account Xcode is signed in to
# (Xcode → Settings → Accounts): the Developer ID signature is a
# cloud-managed certificate (no local certificate to create), and the
# export uploads the app to Apple's notary service with that account (no
# notarytool profile or app-specific password). The account must be the
# team's Account Holder or an Admin. Run it from a Terminal, not a
# non-interactive shell: the archive's signing reads the login keychain.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?version, e.g. 2.0.0}"
WORK="${2:-$(mktemp -d /tmp/aimeter-release-XXXXXX)}"
TEAM="$(sed -n 's/^DEVELOPMENT_TEAM *= *//p' "$ROOT/Config.local.xcconfig" | tail -1)"
[[ -n "$TEAM" ]] || { echo "DEVELOPMENT_TEAM missing from Config.local.xcconfig"; exit 1 }
ARCHIVE="$WORK/AIMeter-$VERSION.xcarchive"
EXPORT="$WORK/export"
ZIP="$WORK/AIMeter-$VERSION-macOS.zip"
mkdir -p "$WORK"

if [[ -d "$ARCHIVE" ]] && plutil -extract Distributions xml1 -o - "$ARCHIVE/Info.plist" 2>/dev/null | grep -q "Developer ID"; then
  # Rerun with the same work dir after an interrupted wait: the archive
  # is already with the notary service, so only the wait is left.
  echo "== resuming: $ARCHIVE is already uploaded for notarization"
else
  echo "== archive ($(git -C "$ROOT" rev-parse --short HEAD))"
  xcodebuild archive -project "$ROOT/AIMeter.xcodeproj" -scheme AIMeter -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" -allowProvisioningUpdates \
    > "$WORK/archive.log" 2>&1 || true
  grep -E "warning:|error:|ARCHIVE" "$WORK/archive.log" | grep -v appintentsmetadataprocessor || true
  [[ -d "$ARCHIVE" ]] || { echo "archive failed — see $WORK/archive.log"; exit 1 }

  echo "== Developer ID export, uploaded to the notary service"
  cat > "$WORK/upload.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>destination</key><string>upload</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$TEAM</string>
</dict></plist>
PLIST
  xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$WORK/upload.plist" \
    -exportPath "$WORK/upload" -allowProvisioningUpdates > "$WORK/upload.log" 2>&1 || true
  grep -E "error:|Uploaded|EXPORT" "$WORK/upload.log" || true
  grep -q "EXPORT SUCCEEDED" "$WORK/upload.log" || { echo "upload failed — see $WORK/upload.log"; exit 1 }
fi

# Usually minutes; a team's first Developer ID submissions took over an
# hour on 2026-10-10. Xcode's Organizer shows the same request.
echo "== waiting for notarization (up to three hours; rerun with the same work dir to resume)"
rm -rf "$EXPORT"
for attempt in {1..180}; do
  if xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath "$EXPORT" > "$WORK/notarized.log" 2>&1; then
    break
  fi
  # Anything but "still processing" (a rejection, an error) won't change.
  grep -q "is processing" "$WORK/notarized.log" || break
  sleep 60
done
APP="$EXPORT/AIMeter.app"
[[ -d "$APP" ]] || { echo "not notarized — see $WORK/notarized.log"; exit 1 }

echo "== verify"
codesign --verify --deep --strict "$APP"
codesign -dvv "$APP" 2>&1 | grep -E "Authority=Developer ID" || { echo "not Developer ID-signed"; exit 1 }
spctl --assess --type execute -v "$APP"
xcrun stapler validate "$APP"
# macOS loads no app extension without the sandbox: an unsandboxed widget
# is silently refused ("plug-ins must be sandboxed"), as every Mac build
# before 2.0.0's release was.
codesign -d --entitlements - --xml "$APP/Contents/PlugIns/AIMeterWidgetsExtension.appex" 2>/dev/null \
  | grep -q "com.apple.security.app-sandbox" || { echo "the widget extension is not sandboxed"; exit 1 }

echo "== zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP"
echo "ready: $ZIP"
echo "then: gh release create $VERSION \"$ZIP\" --title \"AIMeter $VERSION\" --notes-file <notes.md>"
